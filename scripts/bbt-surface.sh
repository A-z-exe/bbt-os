#!/usr/bin/env bash
# bbt-surface - safe, scope-gated surface audit for authorized web targets.
#
#   bbt-surface --target https://app.example.com --scope ~/scope.txt --authorized
#
# Passive by design: a handful of GET/HEAD requests, no payloads, no brute
# force and no out-of-scope redirects. Every step is written to a run
# directory with a Markdown summary you can turn into a report.
set -uo pipefail

VERSION="$(cat /usr/share/bbt-os/VERSION 2>/dev/null || echo dev)"
USER_HOME="${HOME:-/root}"
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
    USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
fi
RUNS="$USER_HOME/bbt/runs"
RED=$'\033[31m'; GREEN=$'\033[32m'; AMBER=$'\033[33m'; CYAN=$'\033[36m'; OFF=$'\033[0m'
[ -t 1 ] || { RED=""; GREEN=""; AMBER=""; CYAN=""; OFF=""; }

info() { printf '%s[*]%s %s\n' "$GREEN" "$OFF" "$*"; }
warn() { printf '%s[!]%s %s\n' "$AMBER" "$OFF" "$*"; }
die()  { printf '%s[x]%s %s\n' "$RED" "$OFF" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
    sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
    cat <<'EOF'

Options:
  --target URL       host or URL to audit (required)
  --scope FILE       allowed hosts/domains, one per line (required)
  --authorized       skip the interactive confirmation
  --timeout SEC      per-request timeout (default 15)
  --max-bundles N    JavaScript bundles to inspect (default 6)
  --check-scope URL  test a URL against the scope file and exit
EOF
}

norm_host() {
    printf '%s' "$1" | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://##; s#^//##; s#^[^/@]*@##; s#[/:?#].*$##' | tr 'A-Z' 'a-z'
}

# Host plus optional port, for building URLs. norm_host drops the port.
norm_authority() {
    printf '%s' "$1" | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://##; s#^//##; s#^[^/@]*@##; s#[/?#].*$##' | tr 'A-Z' 'a-z'
}

norm_path() {
    local ppath
    ppath=$(printf '%s' "$1" | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://[^/]*##; s#[?#].*$##')
    case "$ppath" in
        /*) : ;;
        *) ppath="/" ;;
    esac
    printf '%s' "$ppath"
}

# Scope entries are host or URL. A URL with a path only authorizes that path
# prefix, so "https://api.example.com/srv/tinylink" does not unlock the host.
scope_allows() {
    local host ppath file entry ehost epath
    host=$(norm_host "$1"); ppath=$(norm_path "$1"); file=$2
    [ -f "$file" ] || return 2
    while IFS= read -r entry || [ -n "$entry" ]; do
        entry=$(printf '%s' "$entry" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        [ -n "$entry" ] || continue
        ehost=$(norm_host "$entry"); epath=$(norm_path "$entry")
        case "$ehost" in
            \*.*) case "$host" in *".${ehost#\*.}") : ;; *) continue ;; esac ;;
            *)   [ "$host" = "$ehost" ] || case "$host" in *".$ehost") : ;; *) continue ;; esac ;;
        esac
        if [ "$epath" = "/" ] || [ "$epath" = "$ppath" ]; then
            return 0
        fi
        case "$epath" in */) epath=${epath%/} ;; esac
        case "$ppath" in "$epath"/*) return 0 ;; esac
    done <"$file"
    return 1
}

auth_gate() {
    [ "${AUTHORIZED:-0}" = 1 ] && return 0
    printf '%s[!]%s Authorized targets only. Type AUTHORIZED to continue: ' "$AMBER" "$OFF"
    local answer; read -r answer
    [ "$answer" = "AUTHORIZED" ] || die "aborted"
}

TARGET=""; SCOPE=""; AUTHORIZED=0; TIMEOUT=15; MAX_BUNDLES=6; CHECK=""
while [ $# -gt 0 ]; do
    case "$1" in
        --target) TARGET=${2:-}; shift 2 ;;
        --target=*) TARGET=${1#*=}; shift ;;
        --scope) SCOPE=${2:-}; shift 2 ;;
        --scope=*) SCOPE=${1#*=}; shift ;;
        --authorized|--i-am-authorized) AUTHORIZED=1; shift ;;
        --timeout) TIMEOUT=${2:-15}; shift 2 ;;
        --timeout=*) TIMEOUT=${1#*=}; shift ;;
        --max-bundles) MAX_BUNDLES=${2:-6}; shift 2 ;;
        --max-bundles=*) MAX_BUNDLES=${1#*=}; shift ;;
        --check-scope) CHECK=${2:-}; shift 2 ;;
        --check-scope=*) CHECK=${1#*=}; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1 (try --help)" ;;
    esac
done
if [ -n "$CHECK" ]; then
    [ -n "$SCOPE" ] || die "--scope is required"
    [ -f "$SCOPE" ] || die "scope file not found: $SCOPE"
    if scope_allows "$CHECK" "$SCOPE"; then
        info "allowed: $CHECK"
    else
        warn "denied: $CHECK"
        exit 1
    fi
    exit 0
fi
[ -n "$TARGET" ] || die "--target is required"
[ -n "$SCOPE" ] || die "--scope is required"
[ -f "$SCOPE" ] || die "scope file not found: $SCOPE"
have curl || die "curl is required"

case "$TARGET" in
    http://*|https://*) URL=$TARGET ;;
    *) URL="https://$TARGET" ;;
esac
SCHEME=${URL%%://*}; HOST=$(norm_host "$URL"); AUTHORITY=$(norm_authority "$URL")
TARGET_PATH=$(norm_path "$URL")
BASE="$SCHEME://$AUTHORITY"
case "$TARGET_PATH" in
    /) : ;;
    *) BASE="$BASE${TARGET_PATH%/}" ;;
esac
scope_allows "$URL" "$SCOPE" || die "$HOST is NOT inside $SCOPE"
auth_gate

STAMP=$(date +%Y%m%d-%H%M%S)
RUN="$RUNS/surface-$(printf '%s' "$AUTHORITY" | tr -c 'A-Za-z0-9._-' '_')-$STAMP"
mkdir -p "$RUN/evidence"
rm -f "$RUNS/latest-surface" 2>/dev/null || true
ln -sfn "$RUN" "$RUNS/latest-surface"
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/126 Safari/537.36 bbt-surface/$VERSION"
CURL=(curl -sS -A "$UA" --max-time "$TIMEOUT" --max-redirs 0 --max-filesize 10000000)

info "run directory: $RUN"
printf 'target: %s\nscope: %s\nstarted: %s\n' "$URL" "$SCOPE" "$(date -Is)" >"$RUN/run.txt"

# --- redirect-aware fetch, never leaving scope -----------------------------
fetch_in_scope() {
    local url=$1 out=$2 cur=$1 code loc next cur_host hops=0
    : >"$out.chain"
    while :; do
        rm -f "$out.hdr"
        code=$("${CURL[@]}" -o "$out" -D "$out.hdr" -w '%{http_code}' "$cur" 2>"$out.err") || true
        printf '%s\n' "$code" >"$out.code"
        loc=$(awk 'BEGIN{IGNORECASE=1} /^location:/{sub(/^[^:]*:[[:space:]]*/,""); sub(/\r$/,""); print; exit}' "$out.hdr")
        case "$code" in
            301|302|303|307|308)
                printf '%s -> %s (%s)\n' "$cur" "$loc" "$code" >>"$out.chain"
                cur_host=$(norm_host "$cur")
                case "$loc" in
                    http://*|https://*) next=$loc ;;
                    //*) next="$SCHEME:$loc" ;;
                    /*) next="$SCHEME://$cur_host$loc" ;;
                    *) next="$SCHEME://$cur_host/$loc" ;;
                esac
                if ! scope_allows "$next" "$SCOPE"; then
                    printf 'redirect-left-scope: %s -> %s\n' "$cur" "$next" >>"$RUN/findings.txt"
                    printf '%s\n' "$next" >"$out.location"
                    return 0
                fi
                cur=$next
                hops=$((hops + 1)); [ "$hops" -ge 5 ] && return 0
                ;;
            *) printf '%s\n' "$loc" >"$out.location"; return 0 ;;
        esac
    done
}

# --- 1. main response and headers -----------------------------------------
info "fetching $URL"
fetch_in_scope "$URL" "$RUN/evidence/root"
ROOT_CODE=$(cat "$RUN/evidence/root.code" 2>/dev/null || echo 000)
ROOT_SIZE=$(wc -c <"$RUN/evidence/root" 2>/dev/null || echo 0)
{
    printf '%s\n' "status=$ROOT_CODE size=$ROOT_SIZE host=$HOST"
    awk 'BEGIN{IGNORECASE=1} /^[a-z-]+:/{sub(/\r$/,""); print}' "$RUN/evidence/root.hdr" 2>/dev/null
} >"$RUN/headers.txt"
info "HTTP $ROOT_CODE, $ROOT_SIZE bytes"

case "$ROOT_CODE" in
    2??)
        for h in content-security-policy strict-transport-security x-frame-options x-content-type-options referrer-policy permissions-policy; do
            grep -qi "^$h:" "$RUN/headers.txt" || printf 'missing-header: %s\n' "$h" >>"$RUN/findings.txt"
        done
        awk 'BEGIN{IGNORECASE=1} /^set-cookie:/{
            name=$2; sub(/=.*/,"",name)
            if ($0 !~ /secure/)   printf "cookie-missing-secure: %s\n", name
            if ($0 !~ /httponly/) printf "cookie-missing-httponly: %s\n", name
            if ($0 !~ /samesite/) printf "cookie-missing-samesite: %s\n", name
        }' "$RUN/headers.txt" 2>/dev/null >>"$RUN/findings.txt"
        ;;
esac

# --- 2. fixed discovery paths (no brute force) -----------------------------
looks_like() {
    case "$1" in
        .git/HEAD)     head -c 200 "$2" 2>/dev/null | grep -qE '^([0-9a-f]{40}|ref: refs/)' ;;
        .env)          grep -qE '^[A-Z0-9_]+=' "$2" 2>/dev/null ;;
        package.json)  grep -qE '"[a-z]+"[[:space:]]*:' "$2" 2>/dev/null ;;
        *)             return 0 ;;
    esac
}
for p in robots.txt sitemap.xml .well-known/security.txt .git/HEAD .env package.json; do
    safe=$(printf '%s' "$p" | tr '/.' '__')
    fetch_in_scope "$BASE/$p" "$RUN/evidence/$safe"
    code=$(cat "$RUN/evidence/$safe.code" 2>/dev/null || echo 000)
    size=$(wc -c <"$RUN/evidence/$safe" 2>/dev/null || echo 0)
    printf '%-28s %s %s bytes\n' "$p" "$code" "$size" >>"$RUN/discovery.txt"
    case "$p:$code" in
        .git/HEAD:200|.env:200|package.json:200)
            if looks_like "$p" "$RUN/evidence/$safe"; then
                printf 'exposed-artifact: /%s (%s bytes)\n' "$p" "$size" >>"$RUN/findings.txt"
            else
                printf 'possible-soft-404: /%s returned 200 with unrelated content\n' "$p" >>"$RUN/findings.txt"
            fi ;;
    esac
done

# --- 3. JavaScript bundles ------------------------------------------------
grep -oE 'src="[^"]+\.js[^"]*"' "$RUN/evidence/root" 2>/dev/null \
    | sed 's/^src="//; s/"$//' | awk '!seen[$0]++' | head -n "$MAX_BUNDLES" >"$RUN/bundles.txt"
: >"$RUN/secrets.txt"
: >"$RUN/maps.txt"
: >"$RUN/api-hosts.txt"
n=0
while IFS= read -r src; do
    [ -n "$src" ] || continue
    n=$((n + 1))
    case "$src" in
        http://*|https://*) burl=$src ;;
        //*) burl="$SCHEME:$src" ;;
        /*) burl="$SCHEME://$AUTHORITY$src" ;;
        *) burl="$BASE/$src" ;;
    esac
    case "$burl" in
        http*|"$SCHEME"://*) scope_allows "$burl" "$SCOPE" || continue ;;
    esac
    info "bundle $n: $src"
    "${CURL[@]}" --max-filesize 6000000 -o "$RUN/evidence/bundle-$n.js" "$burl" 2>/dev/null || true
    f="$RUN/evidence/bundle-$n.js"
    [ -f "$f" ] || continue
    grep -oE 'sourceMappingURL=[^[:space:]"]+' "$f" | grep -E '\.map$' | awk -v s="$burl" '{print s " -> " $0}' >>"$RUN/maps.txt"
    grep -oE '(https?://[A-Za-z0-9._-]+(:[0-9]+)?)' "$f" | sort -u >>"$RUN/api-hosts.txt"
    grep -oE '(AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|gh[pousr]_[A-Za-z0-9]{36}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,})' "$f" \
        | awk -v s="$(basename "$src")" '{print s ": " $0}' >>"$RUN/secrets.txt"
done <"$RUN/bundles.txt"
sort -u "$RUN/api-hosts.txt" -o "$RUN/api-hosts.txt"
sort -u "$RUN/secrets.txt" -o "$RUN/secrets.txt"
[ -s "$RUN/maps.txt" ] && sed 's/^/source-map-reference: /' "$RUN/maps.txt" >>"$RUN/findings.txt"
[ -s "$RUN/secrets.txt" ] && sed 's/^/secret-candidate: /' "$RUN/secrets.txt" >>"$RUN/findings.txt"

# --- 4. source maps referenced by bundles ---------------------------------
if [ -s "$RUN/maps.txt" ]; then
    while IFS= read -r line; do
        burl=$(printf '%s' "$line" | sed -E 's/[[:space:]]+->[[:space:]]+sourceMappingURL=.*$//')
        mpath=$(printf '%s' "$line" | sed -E 's/^.*sourceMappingURL=//')
        case "$mpath" in
            http*|//*|data:*) continue ;;
            *.map) : ;;
            *) continue ;;
        esac
        case "$mpath" in
            /*) mapurl="$SCHEME://$AUTHORITY$mpath" ;;
            *) mapurl="${burl%/*}/$mpath" ;;
        esac
        scope_allows "$mapurl" "$SCOPE" || continue
        "${CURL[@]}" -o /dev/null -w '%{http_code}' "$mapurl" 2>/dev/null \
            | grep -q '^200$' && printf 'exposed-source-map: %s\n' "$mpath" >>"$RUN/findings.txt"
    done <"$RUN/maps.txt"
fi

# --- 5. summary and report draft ------------------------------------------
{
    printf '# Surface audit: %s\n\n' "$HOST"
    printf -- '- Started: %s\n- Target: `%s`\n- HTTP: `%s` (%s bytes)\n- Scope: `%s`\n' \
        "$(date -Is)" "$URL" "$ROOT_CODE" "$ROOT_SIZE" "$SCOPE"
    printf -- '- Tool: bbt-surface %s\n\n' "$VERSION"
    printf '## Discovery\n\n```\n'; cat "$RUN/discovery.txt" 2>/dev/null; printf '```\n\n'
    printf '## Signals to verify (not confirmed vulnerabilities)\n\n'
    if [ -s "$RUN/findings.txt" ]; then
        sort -u "$RUN/findings.txt" | sed 's/^/- /'
    else
        printf -- '- none\n'
    fi
    printf '\n## JavaScript hosts (informational; not scope-checked)\n\n```\n'
    head -n 20 "$RUN/api-hosts.txt" 2>/dev/null
    printf '```\n\n## Report draft\n\n'
    printf -- '- Title: <vulnerability> in %s\n- Severity: <CVSS v3.1>\n- Steps: 1) ... 2) ...\n' "$HOST"
    printf -- '- Evidence: attach requests from `%s/evidence`\n- Impact: ...\n- Remediation: ...\n' "$RUN"
    printf '\nOnly submit after you reproduce an impact; automated signals alone are rejected by most programs.\n'
} >"$RUN/summary.md"

info "summary: $RUN/summary.md"
[ -s "$RUN/findings.txt" ] && warn "signals found: review before reporting" || info "no surface signals"
