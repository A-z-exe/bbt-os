#!/usr/bin/env bash
# BBT OS boot branding: Plymouth splash and GRUB boot menu artwork.

BBT_PLYMOUTH_NAME=bbt-os
BBT_PLYMOUTH_DIR="/usr/share/plymouth/themes/$BBT_PLYMOUTH_NAME"
BBT_BOOT_BACKUP=/var/backups/bbt-os

boot_backup_once() {
    local src=$1 name=$2
    [ -f "$src" ] || return 0
    install -d -m 755 "$BBT_BOOT_BACKUP"
    if [ ! -f "$BBT_BOOT_BACKUP/$name" ]; then
        cp -a "$src" "$BBT_BOOT_BACKUP/$name" 2>/dev/null || return 0
        printf '%s\t%s\n' "$src" "$name" >>"$BBT_BOOT_BACKUP/boot-restore.tsv"
    fi
}

install_plymouth_theme() {
    step "BBT OS boot splash"
    install -d -m 755 "$BBT_PLYMOUTH_DIR"
    install -m 644 "$HERE/assets/plymouth/bbt-os.plymouth" "$BBT_PLYMOUTH_DIR/bbt-os.plymouth"
    install -m 644 "$HERE/assets/plymouth/bbt-os.script" "$BBT_PLYMOUTH_DIR/bbt-os.script"
    local img
    for img in background.png logo.png bar-bg.png bar-fg.png dot.png; do
        install -m 644 "$HERE/assets/plymouth/$img" "$BBT_PLYMOUTH_DIR/$img"
    done

    if command -v plymouth-set-default-theme >/dev/null 2>&1; then
        if [ "${BBT_BOOT_DEEP:-1}" = 1 ]; then
            log "Activating Plymouth theme $BBT_PLYMOUTH_NAME (rebuilding initramfs)"
            if plymouth-set-default-theme -R "$BBT_PLYMOUTH_NAME"; then
                ok "Plymouth theme active: $BBT_PLYMOUTH_NAME"
                return 0
            fi
            warn "plymouth-set-default-theme failed; writing config directly"
        else
            plymouth-set-default-theme "$BBT_PLYMOUTH_NAME" >/dev/null 2>&1 \
                || warn "plymouth-set-default-theme failed"
        fi
    fi

    boot_backup_once /etc/plymouth/plymouthd.conf plymouthd.conf.orig
    install -d -m 755 /etc/plymouth
    if [ -f /etc/plymouth/plymouthd.conf ] && grep -q '^\[Daemon\]' /etc/plymouth/plymouthd.conf; then
        sed -i "s|^Theme=.*|Theme=$BBT_PLYMOUTH_NAME|" /etc/plymouth/plymouthd.conf
        grep -q '^Theme=' /etc/plymouth/plymouthd.conf \
            || sed -i "/^\[Daemon\]/a Theme=$BBT_PLYMOUTH_NAME" /etc/plymouth/plymouthd.conf
    else
        cat >/etc/plymouth/plymouthd.conf <<EOF
[Daemon]
Theme=$BBT_PLYMOUTH_NAME
ShowDelay=0
EOF
    fi
    if [ "${BBT_BOOT_DEEP:-1}" = 1 ] && command -v update-initramfs >/dev/null 2>&1; then
        update-initramfs -u || warn "update-initramfs failed"
    fi
    ok "Plymouth theme set to $BBT_PLYMOUTH_NAME"
}

install_grub_art() {
    step "BBT OS boot menu (GRUB)"
    local theme_dir tag seen="" found=0
    for theme_dir in /boot/grub/themes/* /usr/share/grub/themes/*; do
        [ -f "$theme_dir/theme.txt" ] || continue
        theme_dir=$(readlink -f "$theme_dir")
        case " $seen " in *" $theme_dir "*) continue ;; esac
        seen="$seen $theme_dir"
        found=1
        tag=$(printf '%s' "${theme_dir#/}" | tr '/' '_')
        boot_backup_once "$theme_dir/grub-16x9.png" "grub-16x9.$tag.png"
        boot_backup_once "$theme_dir/grub-4x3.png"  "grub-4x3.$tag.png"
        boot_backup_once "$theme_dir/theme.txt"     "theme.$tag.txt"        [ -f "$theme_dir/grub-16x9.png" ] \
            && install -m 644 "$HERE/assets/grub/grub-16x9.png" "$theme_dir/grub-16x9.png"
        [ -f "$theme_dir/grub-4x3.png" ] \
            && install -m 644 "$HERE/assets/grub/grub-4x3.png" "$theme_dir/grub-4x3.png"
        if grep -q '^desktop-color:' "$theme_dir/theme.txt"; then
            sed -i 's|^desktop-color:.*|desktop-color: "#030708"|' "$theme_dir/theme.txt"
        else
            sed -i '/^desktop-image:/a desktop-color: "#030708"' "$theme_dir/theme.txt"
        fi
        log "GRUB artwork updated in $theme_dir"
    done

    if [ "$found" = 0 ]; then
        warn "no GRUB theme directory found; boot menu keeps the distro default"
    elif command -v update-grub >/dev/null 2>&1; then
        update-grub >/dev/null 2>&1 || warn "update-grub failed"
        ok "GRUB menu rebuilt"
    fi
}

install_boot_branding() {
    install_plymouth_theme
    install_grub_art
}
