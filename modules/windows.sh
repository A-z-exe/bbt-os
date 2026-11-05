#!/usr/bin/env bash
# Windows and Active Directory tool group.

install_windows() {
    step "Windows and Active Directory tooling"
    mapfile -t pkgs < <(grep -vE '^[[:space:]]*(#|$)' "$HERE/packages/windows.txt")
    apt_install "${pkgs[@]}"

    # Impacket example scripts occasionally land outside PATH on fresh installs.
    if [ -d /usr/share/doc/python3-impacket/examples ]; then
        chmod 755 /usr/share/doc/python3-impacket/examples >/dev/null 2>&1 || true
    fi
}
