#!/usr/bin/env bash
# Launcher, wallpaper, cursor, installer associations and desktop entries.

install_desktop() {
    step "Desktop integration"

    install -d /opt/bbt-os
    if [ "$HERE" != "/opt/bbt-os" ]; then
        cp -a "$HERE/." /opt/bbt-os/
    fi
    install -d /usr/share/bbt-os /usr/share/icons/hicolor/scalable/apps
    install -m 644 "$HERE/assets/bbt-os.svg" /usr/share/bbt-os/bbt-os.svg
    install -m 644 "$HERE/assets/bbt-os.svg" /usr/share/icons/hicolor/scalable/apps/bbt-os.svg
    install -m 644 "$HERE/assets/wallpaper.svg" /usr/share/bbt-os/wallpaper.svg
    install -m 644 "$HERE/README.md" /usr/share/bbt-os/README.md
    install -m 644 "$HERE/AUTHORS.md" /usr/share/bbt-os/AUTHORS.md
    install -m 644 "$HERE/LICENSE" /usr/share/bbt-os/LICENSE

    log "Installing launcher and command wrappers"
    cat >/usr/local/bin/bbt-os-launcher <<'EOF'
#!/usr/bin/env bash
exec python3 /opt/bbt-os/menu/bbt-os-launcher.py "$@"
EOF
    chmod 755 /usr/local/bin/bbt-os-launcher
    install -m 755 /usr/local/bin/bbt-os-launcher /usr/local/bin/bbt-os

    cat >/usr/local/bin/bbt-os-refresh <<'EOF'
#!/usr/bin/env bash
if [ "$(id -u)" -eq 0 ]; then
    exec bash /opt/bbt-os/refresh.sh "$@"
fi
exec sudo bash /opt/bbt-os/refresh.sh "$@"
EOF
    chmod 755 /usr/local/bin/bbt-os-refresh

    cat >/usr/local/bin/bbt-os-wallpaper <<'EOF'
#!/usr/bin/env bash
exec bash /opt/bbt-os/scripts/bbt-os-wallpaper.sh "$@"
EOF
    chmod 755 /usr/local/bin/bbt-os-wallpaper

    cat >/usr/local/bin/bbt-os-install-file <<'EOF'
#!/usr/bin/env bash
exec bash /opt/bbt-os/scripts/bbt-os-install-file.sh "$@"
EOF
    chmod 755 /usr/local/bin/bbt-os-install-file

    cat >/usr/local/bin/bbt-os-cursor <<'EOF'
#!/usr/bin/env bash
exec bash /opt/bbt-os/scripts/bbt-os-cursor.sh "$@"
EOF
    chmod 755 /usr/local/bin/bbt-os-cursor

    install -m 644 "$HERE/menu/bbt-os.desktop" /usr/share/applications/bbt-os.desktop

    log "Installing double-click installer associations"
    install -m 644 "$HERE/scripts/bbt-os-installer.desktop" /usr/share/applications/bbt-os-installer.desktop
    install -D -m 644 "$HERE/share/bbt-os-installer.xml" /usr/share/mime/packages/bbt-os-installer.xml
    update-mime-database /usr/share/mime >/dev/null 2>&1 || true
    update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
    gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
    for mime in application/vnd.debian.binary-package application/x-deb \
                application/x-appimage application/x-bbt-os-run \
                application/x-shellscript; do
        run_as_user xdg-mime default bbt-os-installer.desktop "$mime" >/dev/null 2>&1 || true
    done

    log "Applying the VMware cursor fix"
    cat >/etc/xdg/autostart/bbt-os-cursor.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=BBT OS cursor
Comment=Restore the VMware pointer after login
Exec=/usr/local/bin/bbt-os-cursor
OnlyShowIn=XFCE;
X-GNOME-Autostart-enabled=true
EOF
    chmod 644 /etc/xdg/autostart/bbt-os-cursor.desktop
    cat >/etc/profile.d/bbt-os-cursor.sh <<'EOF'
export XCURSOR_THEME=Adwaita
export XCURSOR_SIZE=24
EOF
    chmod 644 /etc/profile.d/bbt-os-cursor.sh

    mkdir -p /etc/X11/xorg.conf.d
    cat >/etc/X11/xorg.conf.d/20-bbt-os-swcursor.conf <<'EOF'
Section "Device"
    Identifier "bbt-os-swcursor"
    Driver "modesetting"
    Option "SWcursor" "true"
EndSection
EOF
    chmod 644 /etc/X11/xorg.conf.d/20-bbt-os-swcursor.conf

    log "Applying wallpaper autostart"
    install -m 644 "$HERE/scripts/bbt-os-wallpaper.desktop" /etc/xdg/autostart/bbt-os-wallpaper.desktop

    log "Disabling sleep, suspend and screen lock"
    systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null 2>&1 || true
    mkdir -p /etc/systemd/logind.conf.d
    cat >/etc/systemd/logind.conf.d/99-bbt-os-no-sleep.conf <<'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
IdleAction=ignore
EOF
    cat >/etc/xdg/autostart/bbt-os-no-blank.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=BBT OS keep the console awake
Comment=Disable screen blanking for long scans
Exec=sh -c "xset s off -dpms; xset s noblank"
OnlyShowIn=XFCE;
X-GNOME-Autostart-enabled=true
EOF
    chmod 644 /etc/xdg/autostart/bbt-os-no-blank.desktop

    apply_xfce_session_settings
    ok "desktop integration ready"
}

apply_xfce_session_settings() {
    if ! has_user_session; then
        warn "no graphical session bus; wallpaper, cursor and power settings apply at next login"
        return 0
    fi

    xfset() {
        local channel=$1 prop=$2 type=$3 value=$4
        with_user_session xfconf-query -c "$channel" -p "$prop" -t "$type" -s "$value" 2>/dev/null \
            || with_user_session xfconf-query -c "$channel" -p "$prop" -n -t "$type" -s "$value" 2>/dev/null \
            || true
    }

    xfset xsettings /Gtk/CursorThemeName string Adwaita
    xfset xsettings /Gtk/CursorThemeSize int 24
    xfset xfce4-power-manager /xfce4-power-manager/dpms-enabled bool false
    xfset xfce4-power-manager /xfce4-power-manager/dpms-on-ac-sleep int 0
    xfset xfce4-power-manager /xfce4-power-manager/dpms-on-ac-off int 0
    xfset xfce4-power-manager /xfce4-power-manager/blank-on-ac int 0
    xfset xfce4-power-manager /xfce4-power-manager/inactivity-on-ac int 0
    xfset xfce4-power-manager /xfce4-power-manager/lock-screen-suspend-hibernate bool false
    xfset xfce4-screensaver /saver/enabled bool false
    xfset xfce4-screensaver /lock/enabled bool false
    xfset xfce4-session /shutdown/LockScreen bool false

    with_user_session /usr/local/bin/bbt-os-wallpaper >/dev/null 2>&1 || true
    with_user_session /usr/local/bin/bbt-os-cursor >/dev/null 2>&1 || true
    ok "wallpaper, cursor and power settings applied to the running session"
}
