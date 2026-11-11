#!/usr/bin/env bash
# bbt-bounty - bounty programs, report quality gate and income ledger.
#
#   bbt-bounty init --program spara --scope ~/scope.txt --authorized
#   bbt-bounty new --title "IDOR in ..." --target https://app.example.com/x
#   bbt-bounty check report.md
#   bbt-bounty submit report.md --status accepted --bounty 250
#   bbt-bounty status
set -uo pipefail

VERSION="$(cat /usr/share/bbt-os/VERSION 2>/dev/null || echo dev)"
ROOT="${BBT_BOUNTY_ROOT:-${HOME:-/root}/bbt/bounty}"
RED=$'\033[31m'; GREEN=$'\033[32m'; AMBER=$'\033[33m'; CYAN=$'\033[36m'; OFF=$'\033[0m'
[ -t 1 ] || { RED=""; GREEN=""; AMBER=""; CYAN=""; OFF=""; }
info() { printf '%s[*]%s %s\n' "$GREEN" "$OFF" "$*"; }
warn() { printf '%s[!]%s %s\n' "$AMBER" "$OFF" "$*"; }
die()  { printf '%s[x]%s %s\n' "$RED" "$OFF" "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
bbt-bounty - track programs, gate reports, and count what you earned.

Commands:
  init      create a program workspace around a scope file
  new       scaffold a report with the program metadata prefilled
  check     quality gate: scope, PoC, evidence, impact, excluded classes
  submit    record a report in the ledger with its current status
  status    per-program income and acceptance summary
  list      programs, scope size and deadline
  cvss      compute a CVSS v3.1 base score from a vector
  help      this text

Common options:
  --program NAME     program slug (defaults to the only program)
  --profile ravro    apply Ravro submission rules (default from program.conf)
  --json             machine-readable output for status/cvss

init options:
  --program NAME --scope FILE --authorized [--platform URL] [--currency USD]
  [--deadline YYYY-MM-DD] [--test-ip IP] [--min N] [--max N] [--force]

new options:
  --title TEXT --target URL [--severity High] [--cvss VECTOR]
  [--test-ip IP] [--out FILE]

check options:
  REPORT.md [--force]        (scope and evidence issues are never forced)

submit options:
  REPORT.md --status draft|submitted|triaged|accepted|paid|duplicate|rejected|informative
  [--bounty N] [--currency USD] [--id R-001] [--note TEXT] [--force]

Authorized testing only. bbt-bounty never contacts a target.
EOF
}

slugify() { printf '%s' "$1" | tr 'A-Z' 'a-z' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'; }

norm_host() {
    printf '%s' "$1" | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://##; s#^//##; s#^[^/@]*@##; s#[/:?#].*$##' | tr 'A-Z' 'a-z'
}

norm_path() {
    local ppath
    ppath=$(printf '%s' "$1" | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://[^/]*##; s#[?#].*$##')
    case "$ppath" in /*) : ;; *) ppath="/" ;; esac
    printf '%s' "$ppath"
}

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
        [ "$epath" = "/" ] || [ "$epath" = "$ppath" ] && return 0
        case "$epath" in */) epath=${epath%/} ;; esac
        case "$ppath" in "$epath"/*) return 0 ;; esac
    done <"$file"
    return 1
}

conf_get() { sed -n "s/^$2=//p" "$1/program.conf" 2>/dev/null | tail -n1; }

select_program() {
    local want=$1 dirs
    if [ -n "$want" ]; then
        PROG_DIR="$ROOT/$(slugify "$want")"
        [ -d "$PROG_DIR" ] || die "program not found: $PROG_DIR"
    else
        mapfile -t dirs < <(find "$ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
        [ "${#dirs[@]}" -gt 0 ] || die "no programs yet: bbt-bounty init --program NAME --scope FILE --authorized"
        [ "${#dirs[@]}" -eq 1 ] || die "multiple programs; pass --program NAME (bbt-bounty list)"
        PROG_DIR=${dirs[0]}
    fi
    [ -f "$PROG_DIR/program.conf" ] || die "missing program.conf in $PROG_DIR"
}

cvss_score() {
    awk -v v="$1" 'BEGIN{
        n=split(v,p,"/")
        for(i=1;i<=n;i++){ if(p[i] ~ /^CVSS:/) continue; split(p[i],kv,":"); m[kv[1]]=kv[2] }
        if(m["AV"]=="N")av=0.85; else if(m["AV"]=="A")av=0.62
        else if(m["AV"]=="L")av=0.55; else if(m["AV"]=="P")av=0.2; else exit 2
        if(m["AC"]=="L")ac=0.77; else if(m["AC"]=="H")ac=0.44; else exit 2
        if(m["UI"]=="N")ui=0.85; else if(m["UI"]=="R")ui=0.62; else exit 2
        s=(m["S"]=="C")
        if(s) pr=(m["PR"]=="N"?0.85:(m["PR"]=="L"?0.68:0.5))
        else  pr=(m["PR"]=="N"?0.85:(m["PR"]=="L"?0.62:0.27))
        c=(m["C"]=="H"?0.56:(m["C"]=="L"?0.22:0))
        i2=(m["I"]=="H"?0.56:(m["I"]=="L"?0.22:0))
        a=(m["A"]=="H"?0.56:(m["A"]=="L"?0.22:0))
        if(m["C"]=="N")c=0; if(m["I"]=="N")i2=0; if(m["A"]=="N")a=0
        if(m["C"]!~/^[NHL]$/||m["I"]!~/^[NHL]$/||m["A"]!~/^[NHL]$/) exit 2
        iss=1-(1-c)*(1-i2)*(1-a)
        imp=s?7.52*(iss-0.029)-3.25*(iss-0.02)^15:6.42*iss
        if(imp<=0){print "0.0"; exit}
        expl=8.22*av*ac*pr*ui
        base=s?1.08*(imp+expl):(imp+expl)
        if(base>10)base=10
        r=base*10; if(r>int(r)) r=int(r)+1
        printf "%.1f", r/10
    }'
}

severity_of() {
    awk -v s="$1" 'BEGIN{ if(s==0)print "None"; else if(s<4)print "Low"; else if(s<7)print "Medium"; else if(s<9)print "High"; else print "Critical" }'
}

field_of() {
    sed -n "s/^[-*][[:space:]]*$2[[:space:]]*:[[:space:]]*//Ip" "$1" 2>/dev/null | head -n1 | tr -d '\r'
}

has_section() { grep -qiE "^#{2,4}[[:space:]]+$2" "$1" 2>/dev/null; }

# ---------------------------------------------------------------------------
cmd=${1:-help}; [ $# -gt 0 ] && shift
PROGRAM=""; PROFILE=""
case "$cmd" in help|-h|--help) usage; exit 0 ;; esac

# parse flags common to commands
ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --program) PROGRAM=${2:-}; shift 2 ;;
        --program=*) PROGRAM=${1#*=}; shift ;;
        --profile) PROFILE=${2:-}; shift 2 ;;
        --profile=*) PROFILE=${1#*=}; shift ;;
        *) ARGS+=("$1"); shift ;;
    esac
done

if [ "$cmd" = init ]; then
    NAME="${PROGRAM:-}"; SCOPE=""; AUTHORIZED=0; PLATFORM=""; CURRENCY="USD"
    DEADLINE=""; TEST_IP=""; MINB=""; MAXB=""; FORCE=0
    i=0
    while [ "$i" -lt "${#ARGS[@]}" ]; do
        a=${ARGS[$i]}
        case "$a" in
            --scope) SCOPE=${ARGS[$((i+1))]:-}; i=$((i+2)) ;;
            --scope=*) SCOPE=${a#*=}; i=$((i+1)) ;;
            --authorized|--i-am-authorized) AUTHORIZED=1; i=$((i+1)) ;;
            --platform) PLATFORM=${ARGS[$((i+1))]:-}; i=$((i+2)) ;;
            --platform=*) PLATFORM=${a#*=}; i=$((i+1)) ;;
            --currency) CURRENCY=${ARGS[$((i+1))]:-USD}; i=$((i+2)) ;;
            --currency=*) CURRENCY=${a#*=}; i=$((i+1)) ;;
            --deadline) DEADLINE=${ARGS[$((i+1))]:-}; i=$((i+2)) ;;
            --deadline=*) DEADLINE=${a#*=}; i=$((i+1)) ;;
            --test-ip) TEST_IP=${ARGS[$((i+1))]:-}; i=$((i+2)) ;;
            --test-ip=*) TEST_IP=${a#*=}; i=$((i+1)) ;;
            --min) MINB=${ARGS[$((i+1))]:-}; i=$((i+2)) ;;
            --min=*) MINB=${a#*=}; i=$((i+1)) ;;
            --max) MAXB=${ARGS[$((i+1))]:-}; i=$((i+2)) ;;
            --max=*) MAXB=${a#*=}; i=$((i+1)) ;;
            --force) FORCE=1; i=$((i+1)) ;;
            -h|--help) usage; exit 0 ;;
            *) die "init: unknown option: $a" ;;
        esac
    done
    [ -n "$NAME" ] || die "init: --program NAME is required"
    [ -n "$SCOPE" ] || die "init: --scope FILE is required"
    [ -f "$SCOPE" ] || die "init: scope file not found: $SCOPE"
    grep -qvE '^[[:space:]]*(#|$)' "$SCOPE" || die "init: scope file is empty"
    [ "$AUTHORIZED" = 1 ] || die "init: pass --authorized to confirm you may test these assets"
    PROG_DIR="$ROOT/$(slugify "$NAME")"
    [ -e "$PROG_DIR" ] && [ "$FORCE" != 1 ] && die "program exists: $PROG_DIR (use --force)"
    mkdir -p "$PROG_DIR/reports" "$PROG_DIR/evidence" "$PROG_DIR/archive"
    cp "$SCOPE" "$PROG_DIR/scope.txt"
    {
        printf 'name=%s\n' "$NAME"
        printf 'slug=%s\n' "$(slugify "$NAME")"
        printf 'platform=%s\n' "$PLATFORM"
        printf 'currency=%s\n' "$CURRENCY"
        printf 'deadline=%s\n' "$DEADLINE"
        printf 'test_ip=%s\n' "$TEST_IP"
        printf 'min_bounty=%s\n' "$MINB"
        printf 'max_bounty=%s\n' "$MAXB"
        printf 'profile=%s\n' "${PROFILE:-ravro}"
        printf 'created=%s\n' "$(date +%F)"
        printf 'authorized=1\n'
    } >"$PROG_DIR/program.conf"
    if [ -s "$PROG_DIR/ledger.tsv" ]; then
        cp "$PROG_DIR/ledger.tsv" "$PROG_DIR/archive/ledger-$(date +%Y%m%d-%H%M%S).tsv"
    fi
    : >"$PROG_DIR/ledger.tsv"
    cat >"$PROG_DIR/report-template.md" <<EOF
# <exact vulnerability and affected endpoint>

- Target: https://<in-scope host>/<path>
- Severity: High
- CVSS: CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:U/C:H/I:N/A:N
- Test IP: ${TEST_IP:-<your public testing IP>}
- Test account: <own account only>

## Summary
One paragraph: what is broken and where.

## Steps to Reproduce
1. Request the endpoint with the user above.
2. Change the object id to another user's id.
3. Observe their data in the response.

## Evidence
- evidence/request-01.txt
- evidence/response-01.txt

## Impact
What an attacker gains, with the affected data or action named.

## Remediation
The concrete fix, not a generic recommendation.
EOF
    info "program ready: $PROG_DIR"
    info "template: $PROG_DIR/report-template.md"
    exit 0
fi

if [ "$cmd" = list ]; then
    printf '%-18s %-8s %-12s %s\n' PROGRAM SCOPE CURRENCY DEADLINE
    while IFS= read -r d; do
        [ -f "$d/program.conf" ] || continue
        n=$(grep -cvE '^[[:space:]]*(#|$)' "$d/scope.txt" 2>/dev/null); n=${n:-0}
        printf '%-18s %-8s %-12s %s\n' "$(conf_get "$d" slug)" "$n" \
            "$(conf_get "$d" currency)" "$(conf_get "$d" deadline)"
    done < <(find "$ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
    exit 0
fi

select_program "$PROGRAM"
PROG_NAME=$(conf_get "$PROG_DIR" name); PROG_NAME=${PROG_NAME:-$(basename "$PROG_DIR")}
CURRENCY=$(conf_get "$PROG_DIR" currency); CURRENCY=${CURRENCY:-USD}
PROF=${PROFILE:-$(conf_get "$PROG_DIR" profile)}; PROF=${PROF:-ravro}
TEST_IP_DEFAULT=$(conf_get "$PROG_DIR" test_ip)
SCOPE_FILE="$PROG_DIR/scope.txt"

case "$cmd" in
    status)
        printf 'program: %s (%s)\n\n' "$PROG_NAME" "$PROG_DIR"
        if [ ! -s "$PROG_DIR/ledger.tsv" ]; then
            info "no reports recorded yet"
            exit 0
        fi
        awk -F'\t' -v cur="$CURRENCY" '
            { n++; c[$3]++; if($3=="paid"){ paid+=$6; paidn++ } if($3=="accepted") acc++ }
            END {
                printf "reports: %d\n", n
                split("draft submitted triaged accepted paid duplicate rejected informative", s, " ")
                for(i=1;i<=8;i++) if(c[s[i]]) printf "  %-12s %d\n", s[i], c[s[i]]
                closed=c["accepted"]+c["paid"]+c["duplicate"]+c["rejected"]+c["informative"]
                if(closed>0) printf "acceptance:  %.0f%% (%d/%d decided)\n", (c["accepted"]+c["paid"])*100/closed, c["accepted"]+c["paid"], closed
                printf "paid:        %s %s across %d reports\n", paid, cur, paidn
                if(paidn>0) printf "average:     %.2f %s\n", paid/paidn, cur
            }' "$PROG_DIR/ledger.tsv"
        exit 0 ;;
    cvss)
        vec=${ARGS[0]:-}
        [ -n "$vec" ] || die "cvss: pass a CVSS:3.1 vector"
        score=$(cvss_score "$vec") || die "cvss: invalid or incomplete vector"
        sev=$(severity_of "$score")
        printf '%s\nscore: %s\nseverity: %s\n' "$vec" "$score" "$sev"
        exit 0 ;;
    new)
        TITLE=""; TARGET=""; OUT=""; SEV="High"; VEC=""; TESTIP="$TEST_IP_DEFAULT"
        i=0
        while [ "$i" -lt "${#ARGS[@]}" ]; do
            a=${ARGS[$i]}
            case "$a" in
                --title) TITLE=${ARGS[$((i+1))]:-}; i=$((i+2)) ;;
                --title=*) TITLE=${a#*=}; i=$((i+1)) ;;
                --target) TARGET=${ARGS[$((i+1))]:-}; i=$((i+2)) ;;
                --target=*) TARGET=${a#*=}; i=$((i+1)) ;;
                --severity) SEV=${ARGS[$((i+1))]:-}; i=$((i+2)) ;;
                --cvss) VEC=${ARGS[$((i+1))]:-}; i=$((i+2)) ;;
                --test-ip) TESTIP=${ARGS[$((i+1))]:-}; i=$((i+2)) ;;
                --out) OUT=${ARGS[$((i+1))]:-}; i=$((i+2)) ;;
                --out=*) OUT=${a#*=}; i=$((i+1)) ;;
                *) die "new: unknown option: $a" ;;
            esac
        done
        [ -n "$TITLE" ] || die "new: --title is required"
        [ -n "$TARGET" ] || die "new: --target is required"
        scope_allows "$TARGET" "$SCOPE_FILE" || die "new: $TARGET is outside $SCOPE_FILE"
        slug=$(printf '%s' "$TITLE" | tr 'A-Z' 'a-z' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-50)
        OUT=${OUT:-$PROG_DIR/reports/$(date +%F)-$slug.md}
        [ -e "$OUT" ] && die "new: $OUT exists"
        sevline=${VEC:-CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N}
        {
            printf '# %s\n\n' "$TITLE"
            printf -- '- Target: %s\n' "$TARGET"
            [ -n "$SEV" ] && printf -- '- Severity: %s\n' "$SEV"
            printf -- '- CVSS: %s\n' "$sevline"
            printf -- '- Test IP: %s\n' "${TESTIP:-<your public testing IP>}"
            printf -- '- Test account: <own account only>\n\n'
            printf '## Summary\n\n## Steps to Reproduce\n1. \n\n## Evidence\n- evidence/request-01.txt\n\n## Impact\n\n## Remediation\n'
        } >"$OUT"
        info "draft: $OUT"
        exit 0 ;;
    check|submit) : ;;
    *) die "unknown command: $cmd (bbt-bounty help)" ;;
esac

REPORT=${ARGS[0]:-}
[ -n "$REPORT" ] || die "$cmd: report file is required"
[ -f "$REPORT" ] || die "$cmd: report not found: $REPORT"

# ---- quality gate ---------------------------------------------------------
BLOCKS=0; WARNS=0; HARD=0
block() { printf '%s[BLOCK]%s %s\n' "$RED" "$OFF" "$*"; BLOCKS=$((BLOCKS+1)); }
hard_block() { block "$@"; HARD=$((HARD+1)); }
notet() { printf '%s[WARN]%s  %s\n' "$AMBER" "$OFF" "$*"; WARNS=$((WARNS+1)); }
ok()    { printf '%s[ OK ]%s  %s\n' "$GREEN" "$OFF" "$*"; }

TITLE=$(sed -n 's/^#[[:space:]]*//p' "$REPORT" | head -n1 | tr -d '\r')
[ -n "$TITLE" ] || block "no '# title' line"

TARGET=$(field_of "$REPORT" Target)
if [ -z "$TARGET" ]; then
    block "missing 'Target:' metadata"
elif ! scope_allows "$TARGET" "$SCOPE_FILE"; then
    hard_block "target is outside $SCOPE_FILE: $TARGET"
else
    ok "target is in scope"
fi

VEC=$(sed -n 's/.*\(CVSS:3\.[01]\/[A-Za-z0-9:\/.]*\).*/\1/p' "$REPORT" | head -n1)
SEV=$(field_of "$REPORT" Severity)
if [ -n "$VEC" ]; then
    SCORE=$(cvss_score "$VEC" 2>/dev/null) || { block "CVSS vector is invalid: $VEC"; SCORE=""; }
    if [ -n "$SCORE" ]; then
        DERIVED=$(severity_of "$SCORE")
        ok "CVSS $SCORE ($DERIVED)"
        if [ -n "$SEV" ] && [ "${SEV,,}" != "${DERIVED,,}" ]; then
            notet "Severity '$SEV' does not match CVSS band '$DERIVED'"
        fi
        [ -n "$SEV" ] || SEV=$DERIVED
    fi
elif [ -z "$SEV" ]; then
    block "no 'Severity:' or CVSS vector"
fi

TEST_IP=$(field_of "$REPORT" "Test IP")
if [ -z "$TEST_IP" ]; then
    block "missing 'Test IP:' (programs require the source IP used for testing)"
elif ! printf '%s' "$TEST_IP" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$|:'; then
    notet "Test IP does not look like an IP address: $TEST_IP"
else
    ok "test IP declared"
fi

for sec in "Steps to Reproduce" "Impact" "Evidence" "Remediation"; do
    has_section "$REPORT" "$sec" || block "missing section: ## $sec"
done

# evidence references must exist next to the report
REPORT_DIR=$(cd "$(dirname "$REPORT")" && pwd)
mapfile -t REFS < <(grep -oE 'evidence/[A-Za-z0-9._%/-]+' "$REPORT" | sed 's/[.,;:)]$//' | sort -u)
badref=0
for r in "${REFS[@]}"; do
    if [ -f "$REPORT_DIR/$r" ]; then
        :
    elif [ -f "$REPORT_DIR/../$r" ]; then
        :
    else
        hard_block "evidence file missing: $r"; badref=1
    fi
done
if [ "${#REFS[@]}" -eq 0 ]; then
    if grep -qE '^[[:space:]]*(curl|GET |POST |PUT |PATCH |DELETE )' "$REPORT"; then
        notet "inline request found but no evidence file attached"
    else
        hard_block "no evidence file and no request in the report"
    fi
elif [ "$badref" = 0 ]; then
    ok "${#REFS[@]} evidence file(s) present"
fi

# a manual, reproducible request is mandatory
if grep -qiE '(curl|wget)[[:space:]]|^[[:space:]]*(GET|POST|PUT|PATCH|DELETE)[[:space:]]+[^ ]+[[:space:]]+HTTP/' "$REPORT"; then
    ok "manual request present"
elif grep -qiE '^[[:space:]]*[0-9]+\.' "$REPORT"; then
    notet "numbered steps but no raw HTTP request; add the exact request"
else
    hard_block "no reproducible request (curl or raw HTTP) and no numbered steps"
fi

# scanner output without a manual confirmation is not a report
if ! grep -qiE '(curl|wget)[[:space:]]|^[[:space:]]*(GET|POST|PUT|PATCH|DELETE)[[:space:]]' "$REPORT" \
   && grep -qiE '(nuclei|nikto|nmap|wpscan|ffuf|gobuster|masscan|sqlmap)[[:space:]]' "$REPORT"; then
    block "scanner output only; confirm manually and attach the request"
fi

# excluded vulnerability classes
if [ "$PROF" = ravro ]; then
    BODY=$(tr '\n' ' ' <"$REPORT" | tr 'A-Z' 'a-z')
    case "$BODY" in
        *"missing header"*|*"security header"*|*"content-security-policy"*|*"strict-transport-security"*|*"x-frame-options"*|*"hsts"*)
            block "Ravro excludes security-header findings" ;;
    esac
    case "$BODY" in
        *"weak cipher"*|*"tls version"*|*"ssl certificate"*|*"certificate expir"*)
            block "Ravro excludes TLS/certificate findings" ;;
    esac
    case "$BODY" in
        *"brute force"*|*"bruteforce"*|*"rate limit"*|*"rate-limit"*)
            block "Ravro excludes brute-force and rate-limit findings" ;;
    esac
    case "$BODY" in
        *"denial of service"*|*"dos attack"*|*"resource exhaustion"*|*"memory exhaustion"*)
            block "Ravro excludes denial-of-service findings" ;;
    esac
    case "$BODY" in
        *wordpress*|*wpscan*) block "Ravro excludes WordPress findings" ;;
    esac
    case "$BODY" in
        *"outdated version"*|*"library version"*|*"version disclosure"*)
            block "Ravro excludes version/library findings" ;;
    esac
    case "$BODY" in
        *cors*)
            case "$BODY" in
                *"exploited"*|*"exfiltrat"*|*"credential"*) : ;;
                *) block "CORS finding without a demonstrated exploit (Ravro excludes it)" ;;
            esac ;;
    esac
    case "$BODY" in
        *"dns rebinding"*|*"dns-only ssrf"*)
            block "Ravro excludes DNS-only SSRF/rebinding" ;;
    esac
    case "$BODY" in
        *cookie*)
            case "$BODY" in
                *"session fixation"*|*"session hijack"*|*"account takeover"*|*"csrf"*|*"steal"*|*"exfiltrat"*|*"exploited"*|*"demonstrated impact"*) : ;;
                *) block "Ravro excludes cookie-flag configuration findings without an exploit" ;;
            esac ;;
    esac
fi

# duplicate title+target already in the ledger
if [ -s "$PROG_DIR/ledger.tsv" ] && [ -n "$TARGET" ]; then
    dup=$(awk -F'\t' -v t="$TITLE" -v g="$TARGET" 'tolower($9)==tolower(t) && $8==g {print; exit}' "$PROG_DIR/ledger.tsv")
    [ -n "$dup" ] && notet "same title and target already recorded: $(printf '%s' "$dup" | cut -f1,2,3)"
fi

if [ "$HARD" -gt 0 ]; then
    printf '\n%sBLOCKED%s: %d issue(s) cannot be overridden with --force (scope or evidence).\n' \
        "$RED" "$OFF" "$HARD"
    exit 1
fi
if [ "$BLOCKS" -gt 0 ]; then
    if [ "$cmd" = submit ] && printf '%s\n' "${ARGS[@]}" | grep -qx -- '--force'; then
        warn "gate has $BLOCKS blocking issue(s); continuing because --force was passed"
    else
        printf '\n%sBLOCKED%s: %d issue(s), %d warning(s). Do not submit yet.\n' "$RED" "$OFF" "$BLOCKS" "$WARNS"
        exit 1
    fi
fi
if [ "$BLOCKS" -gt 0 ]; then
    printf '\n%sOVERRIDE%s: recording despite %d blocking issue(s), as requested.\n' "$RED" "$OFF" "$BLOCKS"
else
    printf '\n%sREADY%s: %d warning(s). Attach evidence and state the impact precisely.\n' "$GREEN" "$OFF" "$WARNS"
fi
[ "$cmd" = check ] && exit 0

# ---- submit ---------------------------------------------------------------
STATUS=""; BOUNTY=""; SID=""; NOTE=""; FORCE=0; CURR="$CURRENCY"
i=1
while [ "$i" -lt "${#ARGS[@]}" ]; do
    a=${ARGS[$i]}
    case "$a" in
        --status) STATUS=${ARGS[$((i+1))]:-}; i=$((i+2)) ;;
        --status=*) STATUS=${a#*=}; i=$((i+1)) ;;
        --bounty) BOUNTY=${ARGS[$((i+1))]:-}; i=$((i+2)) ;;
        --bounty=*) BOUNTY=${a#*=}; i=$((i+1)) ;;
        --currency) CURR=${ARGS[$((i+1))]:-}; i=$((i+2)) ;;
        --currency=*) CURR=${a#*=}; i=$((i+1)) ;;
        --id) SID=${ARGS[$((i+1))]:-}; i=$((i+2)) ;;
        --id=*) SID=${a#*=}; i=$((i+1)) ;;
        --note) NOTE=${ARGS[$((i+1))]:-}; i=$((i+2)) ;;
        --note=*) NOTE=${a#*=}; i=$((i+1)) ;;
        --force) FORCE=1; i=$((i+1)) ;;
        *) die "submit: unknown option: $a" ;;
    esac
done
case "$STATUS" in
    draft|submitted|triaged|accepted|paid|duplicate|rejected|informative) : ;;
    "") die "submit: --status is required" ;;
    *) die "submit: invalid status: $STATUS" ;;
esac
case "$STATUS" in
    paid)
        case "$BOUNTY" in ''|*[!0-9.]*) die "submit: --bounty NUMERIC is required for paid" ;; esac ;;
esac
[ -n "$SID" ] || SID=$(printf 'R-%03d' $(( $(wc -l <"$PROG_DIR/ledger.tsv") + 1 )))

DEST="$PROG_DIR/reports/$(date +%F)-$SID.md"
if [ "$(cd "$(dirname "$REPORT")" && pwd)" != "$(cd "$PROG_DIR/reports" && pwd)" ]; then
    cp "$REPORT" "$DEST"
    for r in "${REFS[@]}"; do
        src="$REPORT_DIR/$r"; [ -f "$src" ] || src="$REPORT_DIR/../$r"
        [ -f "$src" ] || continue
        mkdir -p "$PROG_DIR/$(dirname "$r")"
        cp "$src" "$PROG_DIR/$r"
    done
else
    DEST=$(cd "$(dirname "$REPORT")" && pwd)/$(basename "$REPORT")
fi
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date +%F)" "$SID" "$STATUS" "${SEV:-}" "${SCORE:-}" "${BOUNTY:-0}" \
    "$CURR" "$TARGET" "$TITLE" "$DEST" >>"$PROG_DIR/ledger.tsv"
info "recorded $SID ($STATUS) in $PROG_DIR/ledger.tsv"
[ -n "$NOTE" ] && printf '%s\n' "$NOTE" >>"$PROG_DIR/archive/$SID.note"
exit 0
