#!/usr/bin/env bash
# bbt-smartcard - PC/SC smart card and NFC tag helper.
# Cards and tags you own or are explicitly authorized to test only.
set -uo pipefail
if [ "$(id -u)" -eq 0 ]; then
    export PATH="/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
else
    export PATH="$HOME/.local/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
fi

AUTHORIZED=0
COMMAND=""
ARG=""

usage() {
    cat <<'EOF'
bbt-smartcard - smart card (PC/SC) and NFC tag helper

Usage:
  bbt-smartcard [--authorized] <command> [argument]

Read-only:
  status             Readers, ATR, card name and chip capabilities
  readers            List PC/SC readers
  info               ATR, card name and algorithms
  certs              List PKCS#15 / PIV certificates
  nfc-scan           List NFC targets in the field
  ndef-read [FILE]   Read an NDEF message from a MIFARE Classic tag
  apdu HEX           Send one APDU, e.g. 00A4040007A0000002471001

Modify (asks for AUTHORIZED confirmation):
  ndef-write FILE    Write an NDEF message to a MIFARE Classic tag
  mifare-dump FILE   Recover keys and dump a MIFARE Classic tag with mfoc

Options:
  --authorized       Skip the interactive confirmation (for scripts)
  -h, --help         Show this help

Only use this on cards and tags you own or have written authorization to
test. Never use it on payment cards, government IDs or someone else's
credentials: writing to them is illegal in most jurisdictions.
EOF
}

have() { command -v "$1" >/dev/null 2>&1; }

die() {
    printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2
    exit 1
}

require() {
    have "$1" || die "$1 is not installed (run: sudo bbt-os-refresh)"
}

PCSC_TIMEOUT="${BBT_PCSC_TIMEOUT:-10}"

# pcscd can wedge or crash-loop; never let a client block the whole command.
pcsc() {
    timeout "$PCSC_TIMEOUT" "$@"
    local rc=$?
    [ "$rc" -eq 124 ] && die "PC/SC daemon did not answer in ${PCSC_TIMEOUT}s (pcscd may be crash-looping). Check: journalctl -u pcscd; try: sudo systemctl restart pcscd"
    return "$rc"
}

require_auth() {
    [ "$AUTHORIZED" = 1 ] && return 0
    if [ -t 0 ]; then
        cat >&2 <<'EOF'
[!] This command writes to the card/tag.
    Only continue for cards you own or have written authorization to test.
EOF
        local reply
        read -r -p "Type AUTHORIZED to continue: " reply
        [ "$reply" = AUTHORIZED ] && return 0
    fi
    die "refused: pass --authorized or type AUTHORIZED to confirm"
}

list_readers() {
    if have opensc-tool; then
        pcsc opensc-tool --list-readers
    elif have pcsc_scan; then
        local out
        out=$(pcsc pcsc_scan -r 2>&1) || return 1
        printf '%s\n' "$out" | head -n 12
    else
        die "no PC/SC tools installed (run: sudo bbt-os-refresh)"
    fi
}

print_atr() {
    require opensc-tool
    printf 'ATR      : '
    pcsc opensc-tool --atr || { echo "no card or reader"; return 1; }
    printf 'Card     : '
    pcsc opensc-tool --name || echo "unknown card"
}

cmd_status() {
    list_readers
    echo
    print_atr || exit 1
    echo
    echo "== Algorithms =="
    opensc-tool --list-algorithms 2>/dev/null | head -n 20 || true
    if have pkcs15-tool; then
        echo
        echo "== PKCS#15 =="
        local info
        if info=$(pcsc pkcs15-tool --list-info); then
            printf '%s\n' "$info" | head -n 20
        else
            echo "no PKCS#15 application on this card"
        fi
    fi
}

cmd_info() {
    print_atr || exit 1
    echo
    echo "== Algorithms =="
    opensc-tool --list-algorithms 2>/dev/null | head -n 20 || true
}

cmd_certs() {
    require pkcs15-tool
    pcsc pkcs15-tool --list-certificates || \
        die "this card has no readable PKCS#15/PIV certificate store"
}

cmd_apdu() {
    require opensc-tool
    if [ -z "$ARG" ] && [ -t 0 ]; then
        read -r -p "APDU hex: " ARG
    fi
    [ -n "$ARG" ] || die "usage: bbt-smartcard apdu HEX"
    require_auth
    pcsc opensc-tool --send-apdu "$ARG"
}

cmd_nfc_scan() {
    require nfc-list
    local rc=0
    timeout 30 nfc-list -v || rc=$?
    [ "$rc" -eq 0 ] && return 0
    [ "$rc" -eq 124 ] && die "NFC scan did not finish in 30s"
    die "NFC scan failed (no reader or no tag in the field)"
}

cmd_ndef_read() {
    require mifare-classic-read-ndef
    local out="${ARG:-$HOME/bbt/smartcard/ndef-$(date +%Y%m%d-%H%M%S).bin}"
    mkdir -p "$(dirname "$out")"
    mifare-classic-read-ndef -y -o "$out" || die "no NDEF message found"
    echo
    echo "Saved: $out"
    if have xxd; then
        xxd "$out" | head -n 20
    elif have od; then
        od -An -tx1 "$out" | head -n 20
    fi
}

cmd_ndef_write() {
    require mifare-classic-write-ndef
    if [ -z "$ARG" ] && [ -t 0 ]; then
        read -r -e -p "NDEF message file: " ARG
    fi
    [ -n "$ARG" ] || die "usage: bbt-smartcard ndef-write FILE"
    [ -f "$ARG" ] || die "file not found: $ARG"
    require_auth
    mifare-classic-write-ndef -y -i "$ARG"
}

cmd_mifare_dump() {
    require mfoc
    if [ -z "$ARG" ]; then
        ARG="$HOME/bbt/smartcard/mifare-$(date +%Y%m%d-%H%M%S).mfd"
        if [ -t 0 ]; then
            read -r -e -p "Dump output file [$ARG]: " answer
            [ -n "${answer:-}" ] && ARG=$answer
        fi
    fi
    mkdir -p "$(dirname "$ARG")"
    require_auth
    echo "[*] Place the tag on the reader and keep it still..."
    mfoc -O "$ARG" || die "mfoc failed (tag moved, unsupported tag or no reader)"
    echo
    echo "Dump saved: $ARG"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --authorized) AUTHORIZED=1 ;;
        -h|--help) usage; exit 0 ;;
        --) shift; break ;;
        -*) echo "unknown option: $1" >&2; usage; exit 2 ;;
        *) break ;;
    esac
    shift
done

COMMAND="${1:-status}"
ARG="${2:-}"

case "$COMMAND" in
    status)      cmd_status ;;
    readers)     list_readers ;;
    info)        cmd_info ;;
    certs)       cmd_certs ;;
    apdu)        cmd_apdu ;;
    nfc-scan)    cmd_nfc_scan ;;
    ndef-read)   cmd_ndef_read ;;
    ndef-write)  cmd_ndef_write ;;
    mifare-dump) cmd_mifare_dump ;;
    -h|--help|help) usage ;;
    *) echo "unknown command: $COMMAND" >&2; usage; exit 2 ;;
esac
