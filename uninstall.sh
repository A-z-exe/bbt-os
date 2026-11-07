#!/usr/bin/env bash
# Remove the BBT OS overlay. Installed apt tools and the BBT Toolkit checkout
# are intentionally left in place.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E bash "$HERE/uninstall.sh" "$@"
fi

if [ "${1:-}" != "--yes" ]; then
    printf 'Remove the BBT OS overlay (launcher, wallpaper, branding)? [y/N] '
    read -r answer
    case "$answer" in
        y|Y|yes|YES) ;;
        *) echo "aborted"; exit 0 ;;
    esac
fi

echo "[*] Removing BBT OS wrappers and desktop entries"
rm -f /usr/local/bin/bbt-os-launcher /usr/local/bin/bbt-os \
      /usr/local/bin/bbt-os-refresh /usr/local/bin/bbt-os-wallpaper \
      /usr/local/bin/bbt-os-install-file /usr/local/bin/bbt-os-cursor \
      /usr/local/bin/bbt-smartcard /usr/local/bin/mobsf \
      /usr/local/bin/bbt-wifi /usr/local/bin/bbt-workflow \
      /usr/local/bin/bbt-surface \
      /usr/local/bin/bbt-android-recovery /usr/local/bin/bbt-os-doctor
rm -f /usr/share/applications/bbt-os.desktop \
      /usr/share/applications/bbt-os-installer.desktop
rm -f /etc/xdg/autostart/bbt-os-*.desktop
rm -f /etc/profile.d/bbt-os.sh /etc/profile.d/bbt-os-cursor.sh
rm -f /etc/X11/xorg.conf.d/20-bbt-os-swcursor.conf
rm -f /etc/systemd/logind.conf.d/99-bbt-os-no-sleep.conf
rm -f /usr/share/mime/packages/bbt-os-installer.xml
rm -f /usr/share/icons/hicolor/scalable/apps/bbt-os.svg
rm -rf /usr/share/bbt-os /opt/bbt-os

update-mime-database /usr/share/mime >/dev/null 2>&1 || true
update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true

BACKUP_DIR=/var/backups/bbt-os
if [ -d "$BACKUP_DIR" ]; then
    echo "[*] Restoring original identity files"
    [ -f "$BACKUP_DIR/hostname.orig" ] && cp -a "$BACKUP_DIR/hostname.orig" /etc/hostname
    [ -f "$BACKUP_DIR/issue.orig" ] && cp -a "$BACKUP_DIR/issue.orig" /etc/issue
    [ -f "$BACKUP_DIR/issue.net.orig" ] && cp -a "$BACKUP_DIR/issue.net.orig" /etc/issue.net
    [ -f "$BACKUP_DIR/motd.orig" ] && cp -a "$BACKUP_DIR/motd.orig" /etc/motd
    if [ -f "$BACKUP_DIR/os-release.orig" ]; then
        if [ -L /etc/os-release ]; then
            OS_BASE=$(readlink -f /etc/os-release)
        else
            OS_BASE=/etc/os-release
        fi
        cp -a "$BACKUP_DIR/os-release.orig" "$OS_BASE"
    fi
    if [ -f /etc/hostname ]; then
        hostnamectl set-hostname "$(cat /etc/hostname)" 2>/dev/null || true
        sed -i 's|^127\.0\.1\.1.*|127.0.1.1 '"$(cat /etc/hostname)"'|' /etc/hosts 2>/dev/null || true
    fi
fi

systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null 2>&1 || true

if [ -d "$BACKUP_DIR" ]; then
    rm -rf /usr/share/plymouth/themes/bbt-os
    if [ -f "$BACKUP_DIR/boot-restore.tsv" ]; then
        echo "[*] Restoring original boot artwork"
        while IFS=$'\t' read -r target backup; do
            [ -f "$BACKUP_DIR/$backup" ] && cp -a "$BACKUP_DIR/$backup" "$target"
        done <"$BACKUP_DIR/boot-restore.tsv"
        rm -f "$BACKUP_DIR/boot-restore.tsv"
    else
        # backups written before boot-restore.tsv existed
        for theme_dir in /boot/grub/themes/kali /usr/share/grub/themes/kali; do
            [ -d "$theme_dir" ] || continue
            [ -f "$BACKUP_DIR/grub-4x3.kali.png" ] \
                && cp -a "$BACKUP_DIR/grub-4x3.kali.png" "$theme_dir/grub-4x3.png"
            [ -f "$BACKUP_DIR/grub-16x9.kali.png" ] \
                && cp -a "$BACKUP_DIR/grub-16x9.kali.png" "$theme_dir/grub-16x9.png"
            [ -f "$BACKUP_DIR/theme.kali.txt" ] \
                && cp -a "$BACKUP_DIR/theme.kali.txt" "$theme_dir/theme.txt"
        done
    fi
    if [ -f "$BACKUP_DIR/plymouthd.conf.orig" ]; then
        cp -a "$BACKUP_DIR/plymouthd.conf.orig" /etc/plymouth/plymouthd.conf
        rm -f "$BACKUP_DIR/plymouthd.conf.orig"
    fi
    if command -v plymouth-set-default-theme >/dev/null 2>&1; then
        plymouth-set-default-theme kali -R >/dev/null 2>&1 || true
    fi
    command -v update-grub >/dev/null 2>&1 && update-grub >/dev/null 2>&1 || true
    if [ -f "$BACKUP_DIR/lock-restore.tsv" ]; then
        echo "[*] Restoring login screen configuration"
        while IFS=$'\t' read -r target backup; do
            [ -f "$BACKUP_DIR/$backup" ] && cp -a "$BACKUP_DIR/$backup" "$target"
        done <"$BACKUP_DIR/lock-restore.tsv"
        rm -f "$BACKUP_DIR/lock-restore.tsv"
    fi
    for gtk_css in /home/*/.config/gtk-3.0/gtk.css; do
        [ -f "$gtk_css" ] && sed -i '/\/\* BBT OS lock dialog \*\//,$d' "$gtk_css"
    done
fi

echo "[*] BBT OS overlay removed."
echo "    Apt tools and ~/tools/BugBountyToolkit were left installed."
echo "    Log out and back in to restore the Kali session identity."
