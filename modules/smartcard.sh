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
    install -m 755 "$HERE/scripts/bbt-smartcard-remote.sh" /usr/local/bin/bbt-smartcard-remote
    if [ -f "$HERE/share/polkit-1/rules.d/50-bbt-os-pcsc.rules" ]; then
        install -d -m 755 /etc/polkit-1/rules.d
        if printf '%s' "$TARGET_USER" | grep -Eq '^[a-z_][a-z0-9_-]*$'; then
            sed "s/@BBT_USER@/$TARGET_USER/g" \
                "$HERE/share/polkit-1/rules.d/50-bbt-os-pcsc.rules" \
                >/etc/polkit-1/rules.d/50-bbt-os-pcsc.rules
            chown root:root /etc/polkit-1/rules.d/50-bbt-os-pcsc.rules
            chmod 644 /etc/polkit-1/rules.d/50-bbt-os-pcsc.rules
        else
            warn "unexpected user name '$TARGET_USER'; pcsc polkit rule skipped"
        fi
    fi
    ok "bbt-smartcard ready: readers, chip info, NFC/MIFARE read and write"
    ok "bbt-smartcard-remote ready: remote Windows reader over VPCD"
}
