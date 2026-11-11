#!/usr/bin/env bash
# bbt-ktune - raise Linux network limits for high-concurrency scanning.
#
#   bbt-ktune              show current vs recommended values
#   bbt-ktune --plan       print the sysctl drop-in without touching anything
#   sudo bbt-ktune --apply write the drop-in, back up old values, apply
#   sudo bbt-ktune --revert restore the newest backup and remove the drop-in
#
# Only limits are raised. SYN cookies, rp_filter, ASLR, kptr_restrict and every
# other protection stay enabled; nothing is disabled to make scanning faster.
set -uo pipefail

VERSION="$(cat /usr/share/bbt-os/VERSION 2>/dev/null || echo dev)"
DROPIN=/etc/sysctl.d/90-bbt-scan.conf
BACKUP_DIR=/var/backups
RED=$'\033[31m'; GREEN=$'\033[32m'; AMBER=$'\033[33m'; CYAN=$'\033[36m'; OFF=$'\033[0m'
[ -t 1 ] || { RED=""; GREEN=""; AMBER=""; CYAN=""; OFF=""; }
info() { printf '%s[*]%s %s\n' "$GREEN" "$OFF" "$*"; }
warn() { printf '%s[!]%s %s\n' "$AMBER" "$OFF" "$*"; }
die()  { printf '%s[x]%s %s\n' "$RED" "$OFF" "$*" >&2; exit 1; }

# key|recommended value|why
SETTINGS=(
    "fs.file-max|1048576|file descriptors for parallel scanners"
    "net.core.somaxconn|4096|accept backlog for busy listeners"
    "net.core.netdev_max_backlog|16384|packet queue during bursts"
    "net.core.rmem_max|16777216|socket receive buffer for HTTP floods"
    "net.core.wmem_max|16777216|socket send buffer"
    "net.ipv4.tcp_max_syn_backlog|8192|SYN queue for fast connection bursts"
    "net.ipv4.tcp_tw_reuse|1|reuse TIME_WAIT sockets safely for new connections"
    "net.ipv4.ip_local_port_range|10240 65535|more ephemeral ports for many requests"
    "net.netfilter.nf_conntrack_max|262144|conntrack table if the module is loaded"
)

usage() {
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
    cat <<'EOF'

Options:
  --show      current vs recommended (default)
  --plan      print the sysctl drop-in
  --apply     write and apply it (root), after backing up current values
  --revert    restore the newest backup and remove the drop-in (root)
EOF
}

current() { sysctl -n "$1" 2>/dev/null; }

is_lower() {
    awk -v a="$1" -v b="$2" 'BEGIN{ exit !(a+0 < b+0) }'
}

print_plan() {
    printf '# BBT OS scan tuning (bbt-ktune %s, %s)\n' "$VERSION" "$(date -Is)"
    printf '# Only limits are raised. No protection is disabled.\n'
    local row key val why
    for row in "${SETTINGS[@]}"; do
        IFS='|' read -r key val why <<<"$row"
        printf '%s = %s\n' "$key" "$val"
    done
}

do_show() {
    local row key val why cur
    printf '%-38s %-18s %-18s %s\n' SETTING CURRENT RECOMMENDED NOTE
    for row in "${SETTINGS[@]}"; do
        IFS='|' read -r key val why <<<"$row"
        cur=$(current "$key")
        if [ -z "$cur" ]; then
            printf '%-38s %-18s %-18s %s\n' "$key" "-" "$val" "not available"
        elif [ "$key" = "net.ipv4.ip_local_port_range" ]; then
            printf '%-38s %-18s %-18s %s\n' "$key" "$cur" "$val" "$why"
        elif is_lower "$cur" "$val"; then
            printf '%-38s %-18s %-18s %s\n' "$key" "$cur" "$val" "raise ($why)"
        else
            printf '%-38s %-18s %-18s %s\n' "$key" "$cur" "$val" "ok"
        fi
    done
    printf '\nNothing changed. Use --plan to preview, sudo %s --apply to apply.\n' "$0"
}

do_apply() {
    [ "$(id -u)" = 0 ] || die "--apply needs root: sudo bbt-ktune --apply"
    mkdir -p "$BACKUP_DIR"
    local stamp backup row key val cur
    backup=$(ls -1t "$BACKUP_DIR"/bbt-ktune-*.conf 2>/dev/null | head -n1)
    if [ -z "$backup" ]; then
        stamp=$(date +%Y%m%d-%H%M%S)
        backup="$BACKUP_DIR/bbt-ktune-$stamp.conf"
        : >"$backup"
        for row in "${SETTINGS[@]}"; do
            IFS='|' read -r key val _ <<<"$row"
            cur=$(current "$key")
            [ -n "$cur" ] && printf '%s = %s\n' "$key" "$cur" >>"$backup"
        done
        chmod 600 "$backup"
    fi
    info "backup: $backup"

    print_plan >"$DROPIN"
    chmod 644 "$DROPIN"
    info "wrote $DROPIN"
    if sysctl -p "$DROPIN" >/dev/null 2>&1; then
        info "applied"
    else
        warn "some keys were skipped (module not loaded); file stays for the next boot"
    fi
    printf '\nRevert with: sudo bbt-ktune --revert\n'
}

do_revert() {
    [ "$(id -u)" = 0 ] || die "--revert needs root: sudo bbt-ktune --revert"
    local backup
    backup=$(ls -1t "$BACKUP_DIR"/bbt-ktune-*.conf 2>/dev/null | head -n1)
    if [ -n "$backup" ]; then
        info "restoring $backup"
        sysctl -p "$backup" >/dev/null 2>&1 || warn "some values could not be restored"
        rm -f "$backup"
    else
        warn "no backup found; removing the drop-in only"
    fi
    rm -f "$DROPIN"
    info "removed $DROPIN"
}

case "${1:-}" in
    ""|--show) do_show ;;
    --plan|--dry-run) print_plan ;;
    --apply) do_apply ;;
    --revert) do_revert ;;
    -h|--help) usage ;;
    *) die "unknown option: $1 (try --help)" ;;
esac
