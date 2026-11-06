#!/usr/bin/env bash
# BBT OS smart card (PC/SC) and NFC tooling.

install_smartcard() {
    step "Smart card and NFC tooling"
    if [ -f "$HERE/packages/smartcard.txt" ]; then
        mapfile -t SMART_PKGS < <(grep -vE '^[[:space:]]*(#|$)' "$HERE/packages/smartcard.txt")
        apt_install "${SMART_PKGS[@]}"
    fi
    systemctl enable --now pcscd.socket >/dev/null 2>&1 \
        || systemctl enable --now pcscd >/dev/null 2>&1 \
        || warn "pcscd could not be enabled; card readers need it at boot"
    install -m 755 "$HERE/scripts/bbt-smartcard.sh" /usr/local/bin/bbt-smartcard
    ok "bbt-smartcard ready: readers, chip info, NFC/MIFARE read and write"
}
