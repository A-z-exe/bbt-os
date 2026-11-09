#!/usr/bin/env bash
# bbt-smartcard-remote - use a smart card in a remote Windows reader.
#
# SmartCardRelay.exe on the Windows machine exposes its real reader over the
# Virtual Smart Card Protocol (VPCD, TCP 35963-35964). Kali's libifdvpcd dials
# that socket, so pcscd lists the remote card as a local reader and opensc-tool,
# pkcs11-tool, pcsc_scan and friends work on the real hardware.
#
# The Windows side must be started first: it listens, Kali connects out.
set -uo pipefail
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

CONF=/etc/reader.conf.d/vpcd
LIBPATH=/usr/lib/pcsc/drivers/serial/libifdvpcd.so
HOST="${BBT_CARD_HOST:-192.168.1.176}"
PORT="${BBT_CARD_PORT:-35963}"
CHANNEL="0x8C7B"   # 35963, the VPCD default

usage() {
    cat <<'EOF'
bbt-smartcard-remote - remote smart card reader over VPCD

Usage:
  bbt-smartcard-remote setup [HOST] [PORT]   point pcscd at the Windows relay
  bbt-smartcard-remote status                show readers and the card ATR
  bbt-smartcard-remote test                  read the ATR and card name
  bbt-smartcard-remote remove                restore the default virtual reader
  bbt-smartcard-remote -h | --help

Defaults: HOST 192.168.1.176 (override with BBT_CARD_HOST),
          PORT 35963 (override with BBT_CARD_PORT).

Setup writes /etc/reader.conf.d/vpcd and restarts pcscd, so it asks for the
administrator password. Start SmartCardRelay.exe on the Windows 7/10/11 machine
before running setup, and leave it running while the card is in use.
EOF
}

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

need_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        die "root or sudo is required for: $*"
    fi
}

reachable() {
    timeout 4 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null
}

restart_pcscd() {
    need_sudo systemctl restart pcscd.socket >/dev/null 2>&1 \
        || need_sudo systemctl restart pcscd >/dev/null 2>&1 \
        || die "could not restart pcscd"
    sleep 1
    if systemctl is-active --quiet pcscd; then
        say "pcscd restarted."
    else
        need_sudo systemctl start pcscd >/dev/null 2>&1 || true
        sleep 1
        systemctl is-active --quiet pcscd \
            && say "pcscd started." \
            || die "pcscd is not running; check 'sudo systemctl status pcscd'"
    fi
}

show_readers() {
    if command -v pcsc_scan >/dev/null 2>&1; then
        timeout 6 pcsc_scan -r 2>&1 | head -n 20
    else
        say "pcsc_scan is not installed; using opensc-tool."
        timeout 6 opensc-tool --list-readers 2>&1 | head -n 20
    fi
}

setup() {
    local host="${1:-$HOST}" port="${2:-$PORT}"
    [[ "$host" =~ ^[A-Za-z0-9.:_-]+$ ]] || die "bad host: $host"
    [[ "$port" =~ ^[0-9]+$ ]] || die "bad port: $port"

    if ! dpkg -s vsmartcard-vpcd >/dev/null 2>&1; then
        say "Installing vsmartcard-vpcd..."
        need_sudo apt-get update -qq || true
        need_sudo apt-get install -y vsmartcard-vpcd || die "install failed"
    fi
    [ -f "$LIBPATH" ] || die "driver missing: $LIBPATH"

    say "Checking the Windows relay at $host:$port..."
    reachable "$host" "$port" \
        || die "no relay at $host:$port - start SmartCardRelay.exe on the Windows machine first"

    local channel
    channel="$(printf '0x%X' "$port")"
    need_sudo install -d /etc/reader.conf.d
    need_sudo tee "$CONF" >/dev/null <<EOF
FRIENDLYNAME "BBT Remote Card"
DEVICENAME   $host:$channel
LIBPATH      $LIBPATH
CHANNELID    $channel
EOF
    say "Wrote $CONF (remote card at $host:$port)."

    restart_pcscd
    sleep 2
    show_readers
    if timeout 6 pcsc_scan -r 2>/dev/null | grep -qi "BBT Remote Card"; then
        say
        say "Remote reader is live. Test it with: bbt-smartcard-remote test"
    else
        say
        say "Reader not listed yet. Check that the relay window on the Windows"
        say "machine shows two lines 'listening on 0.0.0.0:35963/35964' (the"
        say "driver dials both Lun slots), then run:"
        say "  sudo systemctl restart pcscd && pcsc_scan -r"
    fi
}

status() {
    if [ -f "$CONF" ]; then
        say "--- $CONF"
        cat "$CONF" 2>/dev/null || need_sudo cat "$CONF"
        say
    else
        say "No $CONF yet; run: bbt-smartcard-remote setup"
        say
    fi
    systemctl is-active pcscd >/dev/null 2>&1 \
        && say "pcscd: active" || say "pcscd: inactive"
    say
    show_readers
    say
    say "ATR: $(timeout 8 opensc-tool -a 2>&1 | head -n 1)"
}

test_card() {
    say "ATR:  $(timeout 8 opensc-tool -a 2>&1 | head -n 1)"
    say "Name: $(timeout 8 opensc-tool -n 2>&1 | head -n 1)"
    command -v pkcs15-tool >/dev/null 2>&1 \
        && say "Certificates: $(timeout 8 pkcs15-tool --list-certificates 2>&1 | head -n 3 | tr '\n' ' ')"
}

remove() {
    need_sudo tee "$CONF" >/dev/null <<EOF
FRIENDLYNAME "Virtual PCD"
DEVICENAME   /dev/null:$CHANNEL
LIBPATH      $LIBPATH
CHANNELID    $CHANNEL
EOF
    say "Restored the default virtual reader in $CONF."
    restart_pcscd
}

command="${1:-}"
[ $# -gt 0 ] && shift || true
case "$command" in
    setup) setup "$@" ;;
    status) status ;;
    test) test_card ;;
    remove) remove ;;
    -h|--help|help|"") usage ;;
    *) usage; exit 1 ;;
esac
