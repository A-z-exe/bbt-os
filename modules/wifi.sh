#!/usr/bin/env bash
# BBT OS wireless auditing: adapters, captures and cracking.

install_wifi() {
    step "Wireless auditing"
    if [ -f "$HERE/packages/wifi.txt" ]; then
        mapfile -t WIFI_PKGS < <(grep -vE '^[[:space:]]*(#|$)' "$HERE/packages/wifi.txt")
        apt_install "${WIFI_PKGS[@]}"
    fi

    if [ -f /usr/share/wordlists/rockyou.txt.gz ] && [ ! -f /usr/share/wordlists/rockyou.txt ]; then
        if gunzip -k /usr/share/wordlists/rockyou.txt.gz 2>/dev/null; then
            chmod 644 /usr/share/wordlists/rockyou.txt
            ok "rockyou.txt extracted"
        else
            warn "rockyou.txt could not be extracted"
        fi
    elif [ -f /usr/share/wordlists/rockyou.txt ]; then
        ok "rockyou.txt present"
    else
        warn "rockyou wordlist missing; install the wordlists package"
    fi

    if ! ls /usr/share/hashcat/rules/best64.rule >/dev/null 2>&1; then
        warn "hashcat best64.rule missing; rules stage is skipped"
    fi

    if command -v hcxdumptool >/dev/null 2>&1 && command -v hcxpcapngtool >/dev/null 2>&1; then
        ok "hcxdumptool + hcxpcapngtool $(
            hcxdumptool -v 2>&1 | head -n1 | awk '{print $2}')"
    else
        warn "hcxdumptool/hcxtools missing: PMKID capture disabled"
    fi
    command -v aircrack-ng >/dev/null 2>&1 && ok "aircrack-ng suite" || warn "aircrack-ng missing"
    command -v reaver >/dev/null 2>&1 && ok "reaver (WPS)" || warn "reaver missing"
    command -v hashcat >/dev/null 2>&1 && ok "hashcat (WPA 22000)" || warn "hashcat missing"

    install -m 755 "$HERE/scripts/bbt-wifi.sh" /usr/local/bin/bbt-wifi
    install -d -o "$TARGET_USER" -g "$TARGET_GROUP" "$TARGET_HOME/bbt/wifi"
    ok "bbt-wifi ready: status, scan, auto attack, crack and captures"

    if [ ! -e /sys/class/net/wlan0 ] && [ -z "$(for d in /sys/class/net/*; do [ -e "$d/wireless" ] && echo "$d"; done)" ]; then
        warn "no wireless adapter in this VM yet; attach one via VMware Removable Devices"
    fi
}
