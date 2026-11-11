#!/usr/bin/env bash
# bbt-workflow - matched tool chains for authorized targets.
#
#   bbt-workflow list
#   bbt-workflow web --target example.com --scope ~/scope.txt [--deep] [--domain d]
#   bbt-workflow wordpress --url https://site --scope ~/scope.txt
#   bbt-workflow android --apk app.apk
#   bbt-workflow ad --dc 10.0.0.10 --domain corp.local --scope ~/scope.txt
#
# Every web/AD chain refuses a host that is not listed in the scope file.
# Add --authorized to skip the interactive confirmation (used by the launcher).
# Add --dry-run to print the exact commands without running them.
set -uo pipefail

VERSION="$(cat /usr/share/bbt-os/VERSION 2>/dev/null || echo unknown)"
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

slug() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-50; }

scope_allows() {
    # scope_allows <host> <scope-file>
    local host=$1 file=$2 entry clean rc
    [ -f "$file" ] || return 2
    while IFS= read -r entry || [ -n "$entry" ]; do
        clean=$(printf '%s' "$entry" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        [ -n "$clean" ] || continue
        case "$clean" in
            http://*|https://*)
                clean=$(printf '%s' "$clean" | sed -E 's#^https?://##; s#[/:].*$##')
                [ "$host" = "$clean" ] && return 0
                ;;
            *"*."*)
                case "$host" in *"${clean#\*}" ) return 0 ;; esac
                ;;
            */*)
                python3 - "$host" "$clean" <<'PY' && return 0
import ipaddress, sys
try:
    sys.exit(0 if ipaddress.ip_address(sys.argv[1]) in ipaddress.ip_network(sys.argv[2], strict=False) else 1)
except ValueError:
    sys.exit(1)
PY
                ;;
            *)
                [ "$host" = "$clean" ] && return 0
                case "$host" in *".$clean") return 0 ;; esac
                ;;
        esac
    done <"$file"
    return 1
}

auth_gate() {
    [ "${AUTHORIZED:-0}" = 1 ] && return 0
    printf '%s[!]%s Authorized targets only. Type AUTHORIZED to continue: ' "$AMBER" "$OFF"
    local answer; read -r answer
    [ "$answer" = "AUTHORIZED" ] || die "aborted"
}

start_run() {
    # start_run <recipe> <label> -> sets RUN and redirects output to a log
    RUN="$RUNS/$(slug "$1")-$(slug "$2")-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$RUN"
    ln -sfn "$RUN" "$RUNS/latest"
    exec > >(tee -a "$RUN/run.log") 2>&1
    info "run directory: $RUN"
}

run() {
    # run <description> <command...>
    local desc=$1; shift
    if [ "$DRY" = 1 ]; then
        printf '  %s\n    %s\n' "$desc" "$*"
        return 0
    fi
    info "$desc"
    "$@" || warn "step failed: $desc"
}

# ---------------------------------------------------------------------------
workflow_web() {
    local target="" scope="" domain="" deep=0 DRY=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --target) target=$2; shift 2 ;;
            --target=*) target=${1#*=}; shift ;;
            --scope) scope=$2; shift 2 ;;
            --scope=*) scope=${1#*=}; shift ;;
            --domain) domain=$2; shift 2 ;;
            --domain=*) domain=${1#*=}; shift ;;
            --deep) deep=1; shift ;;
            --dry-run) DRY=1; shift ;;
            --authorized) AUTHORIZED=1; shift ;;
            *) die "unknown web option: $1" ;;
        esac
    done
    [ -n "$target" ] || die "--target is required"
    [ -n "$scope" ] || die "--scope is required (one host/domain/CIDR per line)"
    [ -f "$scope" ] || die "scope file not found: $scope"

    local host
    host=$(printf '%s' "$target" | sed -E 's#^https?://##; s#[/:].*$##')
    [ -n "$domain" ] || domain=$host
    scope_allows "$host" "$scope" || die "$host is NOT inside $scope"
    scope_allows "$domain" "$scope" || die "$domain is NOT inside $scope"
    auth_gate

    local DRY_FLAG=$DRY
    if [ "$DRY_FLAG" = 0 ]; then
        start_run web "$host"
    else
        RUN="$RUNS/web-$(slug "$host")-DRYRUN"
        [ -d "$RUN" ] || mkdir -p "$RUN"
    fi
    DRY=$DRY_FLAG

    local out="$RUN" subs="$RUN/subdomains.txt" live="$RUN/live.txt"
    printf '%s\n' "$domain" >"$subs"
    if have subfinder; then
        run "subfinder $domain" subfinder -d "$domain" -silent -o "$RUN/subfinder.txt"
        [ -s "$RUN/subfinder.txt" ] && sort -u "$subs" "$RUN/subfinder.txt" -o "$subs"
    else
        warn "subfinder missing; continuing with the target host"
        printf '%s\n' "$host" >>"$subs"
    fi

    # Only keep hosts that the scope file allows.
    if [ "$DRY" = 0 ] && [ -s "$subs" ]; then
        local keep="$RUN/subdomains.in-scope.txt"
        : >"$keep"
        while IFS= read -r name; do
            [ -n "$name" ] || continue
            scope_allows "$name" "$scope" && printf '%s\n' "$name" >>"$keep"
        done <"$subs"
        sort -u "$keep" -o "$keep"
        subs=$keep
        info "in-scope hosts: $(wc -l <"$subs")"
    fi

    if have httpx; then
        run "httpx probing" httpx -l "$subs" -silent -title -tech-detect -status-code \
            -web-server -o "$live"
        awk '{print $1}' "$live" 2>/dev/null | grep -E '^https?://' | sort -u >"$RUN/live-urls.txt"
    else
        warn "httpx missing; writing raw hosts as live targets"
        cp "$subs" "$live"
        cp "$subs" "$RUN/live-urls.txt"
    fi
    [ -s "$RUN/live-urls.txt" ] || cp "$subs" "$RUN/live-urls.txt"

    if [ "$deep" = 1 ]; then
        if have katana; then
            run "katana crawl" katana -list "$RUN/live-urls.txt" -silent -jc -d 2 -rl 40 \
                -o "$RUN/crawl.txt"
        fi
        if have nuclei; then
            run "nuclei templates" nuclei -l "$RUN/live-urls.txt" -severity low,medium,high,critical \
                -rl 30 -c 10 -o "$RUN/nuclei.txt"
        fi
    fi

    [ "$DRY" = 1 ] && return 0
    {
        printf '# Recon: %s\n\n' "$domain"
        printf '- Started: %s\n- Scope: `%s`\n- Deep: %s\n\n' "$(date -Is)" "$scope" "$([ "$deep" = 1 ] && echo yes || echo no)"
        printf '| Artifact | Count |\n| --- | --- |\n'
        printf '| Subdomains | %s |\n' "$(wc -l <"$subs" 2>/dev/null || echo 0)"
        printf '| Live HTTP | %s |\n' "$(wc -l <"$live" 2>/dev/null || echo 0)"
        [ -f "$RUN/crawl.txt" ] && printf '| Crawled URLs | %s |\n' "$(wc -l <"$RUN/crawl.txt")"
        [ -f "$RUN/nuclei.txt" ] && printf '| Nuclei findings | %s |\n' "$(grep -c 'http' "$RUN/nuclei.txt" 2>/dev/null || echo 0)"
        printf '\nNext: review nuclei.txt, then BBT -m auto for scope-gated verification.\n'
    } >"$RUN/summary.md"
    info "summary: $RUN/summary.md"
}

workflow_wordpress() {
    local url="" scope="" DRY=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --url) url=$2; shift 2 ;;
            --url=*) url=${1#*=}; shift ;;
            --scope) scope=$2; shift 2 ;;
            --scope=*) scope=${1#*=}; shift ;;
            --dry-run) DRY=1; shift ;;
            --authorized) AUTHORIZED=1; shift ;;
            *) die "unknown wordpress option: $1" ;;
        esac
    done
    [ -n "$url" ] || die "--url is required"
    [ -n "$scope" ] || die "--scope is required"
    [ -f "$scope" ] || die "scope file not found: $scope"
    local host
    host=$(printf '%s' "$url" | sed -E 's#^https?://##; s#[/:].*$##')
    scope_allows "$host" "$scope" || die "$host is NOT inside $scope"
    auth_gate
    [ "$DRY" = 1 ] && RUN="$RUNS/wp-$host-DRYRUN" || start_run wordpress "$host"
    have wpscan || die "wpscan missing (sudo bbt-os-doctor --fix)"

    run "wpscan enumeration" wpscan --url "$url" --enumerate vp,vt,u \
        --random-user-agent --format cli-no-color -o "$RUN/wpscan.txt"
    if have nuclei; then
        run "nuclei wordpress tags" nuclei -u "$url" -tags wordpress \
            -severity low,medium,high,critical -rl 20 -o "$RUN/nuclei-wp.txt"
    fi
    [ "$DRY" = 1 ] && return 0
    {
        printf '# WordPress audit: %s\n\n- Started: %s\n- Scope: `%s`\n\n' "$url" "$(date -Is)" "$scope"
        printf '## Plugins and themes\n\n'
        grep -E '^\s*\[[+!]\]' "$RUN/wpscan.txt" 2>/dev/null | head -n 60 || echo "see wpscan.txt"
        printf '\n## Nuclei\n\n'
        [ -s "$RUN/nuclei-wp.txt" ] && head -n 40 "$RUN/nuclei-wp.txt" || echo "no findings"
    } >"$RUN/summary.md"
    info "summary: $RUN/summary.md"
}

workflow_android() {
    local apk="" DRY=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --apk) apk=$2; shift 2 ;;
            --apk=*) apk=${1#*=}; shift ;;
            --dry-run) DRY=1; shift ;;
            *) die "unknown android option: $1" ;;
        esac
    done
    [ -n "$apk" ] || die "--apk is required"
    [ -f "$apk" ] || die "APK not found: $apk"
    local base; base=$(basename "${apk%.apk}")
    if [ "$DRY" = 1 ]; then RUN="$RUNS/android-$base-DRYRUN"; mkdir -p "$RUN"; else start_run android "$base"; fi

    if have apktool; then
        run "apktool decode" apktool d -f -o "$RUN/apktool" "$apk"
    else
        warn "apktool missing"
    fi
    if have jadx; then
        run "jadx decompile" jadx -d "$RUN/jadx" --no-res "$apk"
    else
        warn "jadx missing"
    fi
    [ "$DRY" = 1 ] && return 0

    local src="$RUN/jadx/sources"
    : >"$RUN/endpoints.txt"
    if [ -d "$src" ]; then
        grep -rhoE 'https?://[A-Za-z0-9._~:/?#@!$&()*+,;=%-]+' "$src" 2>/dev/null \
            | sort -u | head -n 500 >"$RUN/endpoints.txt"
    fi
    grep -rhoE '(AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|"-----BEGIN [A-Z ]*PRIVATE KEY)' \
        "$RUN/apktool" "$RUN/jadx" 2>/dev/null | sort -u >"$RUN/secrets.txt"
    if have aapt; then
        aapt dump badging "$apk" >"$RUN/badging.txt" 2>/dev/null || true
    fi
    {
        printf '# APK analysis: %s\n\n- File: `%s`\n- SHA256: `%s`\n- Started: %s\n\n' \
            "$base" "$apk" "$(sha256sum "$apk" | cut -d' ' -f1)" "$(date -Is)"
        printf '| Artifact | Count |\n| --- | --- |\n'
        printf '| Endpoints | %s |\n' "$(wc -l <"$RUN/endpoints.txt")"
        printf '| Secret candidates | %s |\n\n' "$(wc -l <"$RUN/secrets.txt")"
        printf '## First endpoints\n\n```\n'; head -n 25 "$RUN/endpoints.txt"; printf '```\n'
        printf '\n## Secret candidates (verify before reporting)\n\n```\n'; head -n 15 "$RUN/secrets.txt"; printf '```\n'
    } >"$RUN/summary.md"
    info "summary: $RUN/summary.md"
}

workflow_ad() {
    local dc="" domain="" scope="" DRY=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --dc) dc=$2; shift 2 ;;
            --dc=*) dc=${1#*=}; shift ;;
            --domain) domain=$2; shift 2 ;;
            --domain=*) domain=${1#*=}; shift ;;
            --scope) scope=$2; shift 2 ;;
            --scope=*) scope=${1#*=}; shift ;;
            --dry-run) DRY=1; shift ;;
            --authorized) AUTHORIZED=1; shift ;;
            *) die "unknown ad option: $1" ;;
        esac
    done
    [ -n "$dc" ] || die "--dc is required"
    [ -n "$domain" ] || die "--domain is required"
    [ -n "$scope" ] || die "--scope is required"
    [ -f "$scope" ] || die "scope file not found: $scope"
    scope_allows "$dc" "$scope" || die "$dc is NOT inside $scope"
    auth_gate
    [ "$DRY" = 1 ] && RUN="$RUNS/ad-$dc-DRYRUN" || start_run ad "$dc"

    # -sS needs root; keep the chain working for unprivileged launches too
    local scan_type=-sT
    [ "$(id -u)" -eq 0 ] && scan_type=-sS
    run "nmap domain controller ports" nmap -Pn "$scan_type" --open \
        -p 53,88,135,139,389,445,464,593,636,3268,3269,5985,5986 \
        -oN "$RUN/nmap.txt" "$dc"
    if have enum4linux-ng; then
        run "enum4linux-ng" enum4linux-ng -A "$dc" -oJ "$RUN/enum4linux" >"$RUN/enum4linux.txt" 2>&1
    fi
    [ "$DRY" = 1 ] && return 0
    {
        printf '# AD passive enumeration: %s (%s)\n\n- Started: %s\n- Scope: `%s`\n\n' \
            "$dc" "$domain" "$(date -Is)" "$scope"
        printf '## Open ports\n\n```\n'; grep -E '^[0-9]+/tcp' "$RUN/nmap.txt" 2>/dev/null || echo "see nmap.txt"; printf '```\n'
        printf '\n## Next steps (run only with credentials and written authorization)\n\n'
        printf -- '- `netexec smb %s -u <user> -p <pass> --shares`\n' "$dc"
        printf -- '- `bloodhound-python -d %s -ns %s -c All -u <user> -p <pass>`\n' "$domain" "$dc"
        printf -- '- `enum4linux-ng -A %s` for null-session detail\n' "$dc"
    } >"$RUN/summary.md"
    info "summary: $RUN/summary.md"
}

usage() {
    sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
}

main() {
    local cmd=${1:-list}; [ $# -gt 0 ] && shift
    case "$cmd" in
        web) workflow_web "$@" ;;
        wordpress|wp) workflow_wordpress "$@" ;;
        android|apk) workflow_android "$@" ;;
        ad) workflow_ad "$@" ;;
        list)
            usage
            printf '\nRecipes chain these tools:\n'
            printf '  web        subfinder -> dnsx/httpx -> katana -> nuclei\n'
            printf '  wordpress  wpscan -> nuclei (wordpress tags)\n'
            printf '  android    apktool -> jadx -> endpoint and secret extraction\n'
            printf '  ad         nmap -> enum4linux-ng (passive only)\n'
            ;;
        --version|-V) echo "bbt-workflow $VERSION" ;;
        -h|--help|help) usage ;;
        *) usage; exit 2 ;;
    esac
}

main "$@"
