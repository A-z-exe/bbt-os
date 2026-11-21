#!/usr/bin/env bash
# bbt-autohunt - automated, scope-gated bug-bounty recon and triage.
# Usage: bbt-autohunt --target <domain|ip> --scope <scope.txt> --out <dir> [--authorized]
set -uo pipefail

usage() {
    cat <<'EOF'
Usage: bbt-autohunt --target <domain|ip> --scope <scope.txt> --out <dir> [options]

  --target     Domain or IP to assess (must appear in the scope file)
  --scope      File with in-scope hosts, one per line (*.example.com allowed)
  --out        Output directory for logs and the report
  --authorized Required confirmation that testing is authorized
  --quick      Skip slower sqlmap/commix stages
  --skip-tls   Skip sslscan/testssl.sh (many programs exclude TLS findings)
  --rate N     Max requests/second for ffuf (default: 20)
  -h, --help   Show this help

Only run against systems you own or have explicit written permission to test.
EOF
}

TARGET=""; SCOPE=""; OUT=""; AUTHORIZED=0; QUICK=0; SKIP_TLS=0; RATE=20
while [ $# -gt 0 ]; do
    case "$1" in
        --target) TARGET=${2:-}; shift 2 ;;
        --scope) SCOPE=${2:-}; shift 2 ;;
        --out) OUT=${2:-}; shift 2 ;;
        --authorized) AUTHORIZED=1; shift ;;
        --quick) QUICK=1; shift ;;
        --skip-tls) SKIP_TLS=1; shift ;;
        --rate) RATE=${2:-20}; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$TARGET" ] && [ -n "$SCOPE" ] && [ -n "$OUT" ] || { usage >&2; exit 2; }
[ "$AUTHORIZED" -eq 1 ] || { echo "ERROR: --authorized is required." >&2; exit 2; }
[ -f "$SCOPE" ] || { echo "ERROR: scope file not found: $SCOPE" >&2; exit 2; }

# Scope gate: exact host, wildcard suffix, or IP range prefix.
in_scope=0
while IFS= read -r line || [ -n "$line" ]; do
    line=$(printf '%s' "$line" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    case "$line" in ''|\#*) continue ;; esac
    case "$line" in
        \*.*) suffix=${line#\*}; case "$TARGET" in *"$suffix") in_scope=1 ;; esac ;;
        *) [ "$TARGET" = "$line" ] && in_scope=1 ;;
    esac
done <"$SCOPE"
[ "$in_scope" -eq 1 ] || { echo "ERROR: target '$TARGET' is not in scope." >&2; exit 3; }

mkdir -p "$OUT"/{recon,scan,exploit,report}
RECON="$OUT/recon"; SCAN="$OUT/scan"; EXPLOIT="$OUT/exploit"
log() { printf '\033[1;36m[*]\033[0m %s\n' "$*"; }
run() { log "$*"; timeout "${TIMEOUT:-300}" "$@" || true; }

log "Scope verified: $TARGET"
printf '%s\n' "$TARGET" >"$RECON/target.txt"

# 1) Passive/active subdomain discovery for domains; direct for IPs.
if [[ "$TARGET" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s\n' "$TARGET" >"$RECON/hosts.txt"
else
    run subfinder -d "$TARGET" -o "$RECON/subfinder.txt"
    cat "$RECON/subfinder.txt" 2>/dev/null | sort -u >"$RECON/hosts.txt"
    printf '%s\n' "$TARGET" >>"$RECON/hosts.txt"
    sort -u -o "$RECON/hosts.txt" "$RECON/hosts.txt"
fi

# 2) Probe live HTTP services.
run httpx -l "$RECON/hosts.txt" -o "$RECON/alive.txt" -silent
[ -s "$RECON/alive.txt" ] || cp "$RECON/hosts.txt" "$RECON/alive.txt"
log "Live hosts: $(wc -l <"$RECON/alive.txt")"

# 3) Fingerprint + TLS checks.
while IFS= read -r url; do
    [ -n "$url" ] || continue
    host=${url#http://}; host=${host#https://}; host=${host%%/*}
    safe=$(printf '%s' "$host" | tr -c 'A-Za-z0-9._-' '_')
    run whatweb "$url" >"$SCAN/whatweb_$safe.txt" 2>&1
    if [ "$SKIP_TLS" -eq 0 ]; then
        run sslscan "$host:443" >"$SCAN/sslscan_$safe.txt" 2>&1
    fi
done <"$RECON/alive.txt"

# 4) Vulnerability sweeps.
run nuclei -l "$RECON/alive.txt" -o "$SCAN/nuclei.txt" -silent
run dalfox file "$RECON/alive.txt" -o "$SCAN/dalfox.txt"
run nikto -h "$(head -1 "$RECON/alive.txt")" -o "$SCAN/nikto.txt" 2>/dev/null
if [ "$QUICK" -eq 0 ]; then
    run ffuf -u "$(head -1 "$RECON/alive.txt")/FUZZ" \
        -w /usr/share/seclists/Discovery/Web-Content/common.txt \
        -rate "$RATE" -o "$SCAN/ffuf.json" -of json
    run commix --url="$(head -1 "$RECON/alive.txt")" --batch -o "$SCAN/commix.txt"
fi

# 5) Safe, manual-verification PoC hints (never destructive).
{
    echo "# Manual verification hints"
    echo
    echo "- XSS: replay any dalfox finding in Burp Repeater."
    echo "- Injection: replay commix/sqlmap candidates with --batch."
    echo "- Misconfig: review nuclei info/severity:info findings."
    echo "- Exploitation: use msfconsole only inside the authorized scope."
} >"$EXPLOIT/poc-hints.md"

# 6) Report.
python3 "$(dirname "$0")/bbt-report.py" --target "$TARGET" --out "$OUT"
log "Done. Report: $OUT/report/report.md"
