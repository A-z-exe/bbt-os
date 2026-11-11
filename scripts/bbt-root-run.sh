#!/usr/bin/env bash
# bbt-run - root bridge for BBT OS tools started from the desktop launcher.
#
# Installed root-owned as /usr/libexec/bbt-os/bbt-run. Only the matching
# polkit rule may invoke it without a password, and only the tools listed
# below are accepted. Each tool runs from the root-owned copy under
# /opt/bbt-os, never from a user-writable checkout.
set -uo pipefail

TOOLS_ROOT=/opt/bbt-os/scripts
BIN_DIR=/usr/local/bin

die() { printf 'bbt-run: %s\n' "$*" >&2; exit 64; }

[ "$(id -u)" -eq 0 ] || die "must be started through pkexec"

[ $# -ge 1 ] || die "usage: bbt-run TOOL [ARGUMENTS...]"
tool=$1
shift

case "$tool" in
    bbt-wifi|bbt-ktune|bbt-os-doctor|bbt-smartcard-remote)
        target="$TOOLS_ROOT/$tool.sh" ;;
    bbt-os-refresh)
        target="$BIN_DIR/bbt-os-refresh" ;;
    *)
        die "tool not allowed: $tool" ;;
esac

[ -f "$target" ] || die "missing $target"
target=$(realpath -e -- "$target") || die "cannot resolve $target"

check_root_owned() {
    local path=$1 owner mode
    owner=$(stat -c %u -- "$path" 2>/dev/null) || die "cannot stat $path"
    [ "$owner" -eq 0 ] || die "refusing non-root-owned $path"
    mode=$(stat -c %a -- "$path" 2>/dev/null) || die "cannot read mode of $path"
    (( (8#$mode & 8#22) == 0 )) || die "refusing group/world-writable $path"
}

check_tree() {
    local bad
    bad=$(find /opt/bbt-os \( ! -user root -o -perm /022 \) -print -quit 2>/dev/null)
    [ -z "$bad" ] || die "refusing unsafe tree entry $bad"
}

check_root_owned "$TOOLS_ROOT"
check_root_owned "$target"
check_tree

uid="${PKEXEC_UID:-${SUDO_UID:-0}}"
[ "$uid" -gt 0 ] || die "no desktop user in PKEXEC_UID"
user=$(getent passwd "$uid" | cut -d: -f1)
[ -n "$user" ] || die "unknown uid $uid"
home=$(getent passwd "$uid" | cut -d: -f6)
[ -d "$home" ] || home=/root

export HOME="$home" USER="$user" LOGNAME="$user" SUDO_USER="$user"
export PATH="$TOOLS_ROOT:$BIN_DIR:/usr/local/sbin:/usr/sbin:/sbin:/usr/bin:/bin"
export LANG="${LANG:-C.UTF-8}"
[ -n "${TERM:-}" ] && export TERM
[ -n "${DISPLAY:-}" ] && export DISPLAY
[ -n "${XAUTHORITY:-}" ] && export XAUTHORITY
cd "$home" 2>/dev/null || cd /

exec "$target" "$@"
