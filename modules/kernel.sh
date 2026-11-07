#!/usr/bin/env bash
# BBT OS kernel, firmware and driver readiness.

install_kernel_support() {
    step "Kernel and drivers"
    if [ -f "$HERE/packages/kernel.txt" ]; then
        mapfile -t KERNEL_PKGS < <(grep -vE '^[[:space:]]*(#|$)' "$HERE/packages/kernel.txt")
        apt_install "${KERNEL_PKGS[@]}"
    fi

    local running
    running=$(uname -r)
    log "Running kernel: $running"
    if [ -d "/usr/src/linux-headers-$running" ]; then
        ok "headers for $running present"
    elif apt-get install "${APT_OPTS[@]}" --no-install-recommends "linux-headers-$running" >/dev/null 2>&1; then
        ok "linux-headers-$running"
    else
        local newest
        newest=$(apt-cache search --names-only '^linux-headers-[0-9].*kali-amd64$' 2>/dev/null \
            | awk '{print $1}' | sort -V | tail -n1)
        if [ -n "$newest" ]; then
            log "no headers for $running; installing $newest for the next kernel"
            apt-get install "${APT_OPTS[@]}" --no-install-recommends "$newest" >/dev/null 2>&1 \
                && ok "$newest" \
                || warn "$newest could not be installed"
            warn "DKMS modules build after rebooting into the matching kernel"
        else
            warn "no Kali kernel headers are available"
        fi
    fi

    log "Enabling NFC and 802.11 modules at boot"
    cat >/etc/modules-load.d/bbt-os.conf <<'EOF'
# BBT OS: NFC and wireless stack for card/NFC and Wi-Fi auditing
nfc
cfg80211
mac80211
EOF
    chmod 644 /etc/modules-load.d/bbt-os.conf
    local mod
    for mod in nfc cfg80211 mac80211; do
        modprobe "$mod" 2>/dev/null && ok "module $mod" || warn "module $mod unavailable for $running"
    done

    if systemctl enable --now open-vm-tools >/dev/null 2>&1; then
        ok "open-vm-tools active"
    else
        warn "open-vm-tools not active (normal outside VMware)"
    fi

    install -m 755 "$HERE/scripts/bbt-ktune.sh" /usr/local/bin/bbt-ktune
    ok "bbt-ktune ready: raise network limits for high-concurrency scans"

    if command -v rfkill >/dev/null 2>&1; then
        rfkill unblock wifi 2>/dev/null || true
        rfkill unblock bluetooth 2>/dev/null || true
    fi

    local found=0
    if lsusb 2>/dev/null | grep -qiE 'wireless|802\.11|wlan|atheros|realtek|ralink|mediatek|nfc|pn53|acr122'; then
        ok "wireless/NFC USB device visible"
        found=1
    fi
    for d in /sys/class/net/*; do
        [ -e "$d/wireless" ] && { ok "wireless interface $(basename "$d")"; found=1; }
    done
    if [ "$found" = 0 ]; then
        warn "no wireless adapter visible; in VMware attach it under VM > Removable Devices"
    fi

    ok "kernel support ready (bbt-os-doctor shows the live state)"
}
