#!/usr/bin/env bash
# Privileged tool bridge: root-owned bbt-run helper plus the polkit rule that
# lets the local desktop session start it without a fresh sudo password.

install_root_helper() {
    step "Privileged tool bridge"
    if [ ! -d /opt/bbt-os/scripts ]; then
        warn "desktop tree missing; bbt-run and its polkit rule were not installed"
        return 0
    fi
    install -d -m 755 /usr/libexec/bbt-os
    install -m 755 "$HERE/scripts/bbt-root-run.sh" /usr/libexec/bbt-os/bbt-run
    if [ -f "$HERE/share/polkit-1/rules.d/50-bbt-os-tools.rules" ]; then
        install -d -m 755 /etc/polkit-1/rules.d
        if printf '%s' "$TARGET_USER" | grep -Eq '^[a-z_][a-z0-9_-]*$'; then
            sed "s/@BBT_USER@/$TARGET_USER/g" \
                "$HERE/share/polkit-1/rules.d/50-bbt-os-tools.rules" \
                >/etc/polkit-1/rules.d/50-bbt-os-tools.rules
            chown root:root /etc/polkit-1/rules.d/50-bbt-os-tools.rules
            chmod 644 /etc/polkit-1/rules.d/50-bbt-os-tools.rules
        else
            warn "unexpected user name '$TARGET_USER'; polkit rule skipped"
        fi
    fi
    systemctl try-restart polkit >/dev/null 2>&1 \
        || systemctl try-restart polkitd >/dev/null 2>&1 || true
    ok "bbt-run ready: privileged tools start as root from the launcher"
}
