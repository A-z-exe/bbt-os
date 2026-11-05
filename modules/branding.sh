#!/usr/bin/env bash
# BBT OS identity: hostname, os-release, issue and MOTD.

BACKUP_DIR=/var/backups/bbt-os

backup_once() {
    local src=$1 name=$2
    if [ -f "$src" ] && [ ! -f "$BACKUP_DIR/$name" ]; then
        cp -a "$src" "$BACKUP_DIR/$name" 2>/dev/null || true
    fi
}

install_branding() {
    step "BBT OS identity"
    install -d -m 755 "$BACKUP_DIR"

    log "Setting hostname to bbt-os"
    hostnamectl set-hostname bbt-os 2>/dev/null || warn "hostnamectl failed"
    echo "bbt-os" >/etc/hostname
    if grep -q '^127\.0\.1\.1' /etc/hosts; then
        sed -i 's|^127\.0\.1\.1.*|127.0.1.1 bbt-os|' /etc/hosts
    else
        echo "127.0.1.1 bbt-os" >>/etc/hosts
    fi

    if [ -L /etc/os-release ]; then
        OS_BASE=$(readlink -f /etc/os-release)
    else
        OS_BASE=/etc/os-release
    fi
    backup_once "$OS_BASE" os-release.orig
    backup_once /etc/hostname hostname.orig
    backup_once /etc/issue issue.orig
    backup_once /etc/issue.net issue.net.orig
    backup_once /etc/motd motd.orig

    log "Writing BBT OS release metadata"
    local tmp
    tmp=$(mktemp)
    sed "s|^PRETTY_NAME=.*|PRETTY_NAME=\"BBT OS $VERSION (Kali GNU/Linux Rolling)\"|" "$OS_BASE" >"$tmp"
    if grep -q '^VARIANT_ID=' "$tmp"; then
        sed -i 's|^VARIANT_ID=.*|VARIANT_ID=bbt-os|' "$tmp"
    else
        echo 'VARIANT_ID=bbt-os' >>"$tmp"
    fi
    if grep -q '^VARIANT=' "$tmp"; then
        sed -i 's|^VARIANT=.*|VARIANT="BBT OS"|' "$tmp"
    else
        echo 'VARIANT="BBT OS"' >>"$tmp"
    fi
    sed -i '/^BBT_OS_/d' "$tmp"
    cat >>"$tmp" <<EOF
BBT_OS_VERSION="$VERSION"
BBT_OS_DEVELOPER="AmirHossein Zarei (A-z-exe)"
BBT_OS_GITHUB="https://github.com/A-z-exe"
BBT_OS_EMAIL="207771865+A-z-exe@users.noreply.github.com"
EOF
    install -m 644 "$tmp" "$OS_BASE"
    rm -f "$tmp"

    install -m 644 "$HERE/branding/issue" /etc/issue
    install -m 644 "$HERE/branding/issue.net" /etc/issue.net
    install -m 644 "$HERE/branding/motd" /etc/motd

    cat >/etc/profile.d/bbt-os.sh <<EOF
# BBT OS identity
export BBT_OS_VERSION="$VERSION"
alias bbt-os='bbt-os-launcher'
EOF
    chmod 644 /etc/profile.d/bbt-os.sh

    install -d /usr/share/bbt-os
    install -m 644 "$HERE/AUTHORS.md" /usr/share/bbt-os/AUTHORS.md
    install -m 644 "$HERE/LICENSE" /usr/share/bbt-os/LICENSE
    [ -f "$HERE/README.md" ] && install -m 644 "$HERE/README.md" /usr/share/bbt-os/README.md

    ok "identity set to BBT OS $VERSION (ID=kali preserved)"
}
