#!/usr/bin/env bash
# Create the BBT OS login account and retire the stock kali account.
# The existing home directory stays in place, so tools and virtualenvs keep
# working; only the account name and ownership change.
#
# The password is never stored in this repository. Provide it at run time:
#   sudo BBT_NEW_PASS='<password>' bash scripts/bbt-os-account.sh
#   sudo bash scripts/bbt-os-account.sh --password '<password>'
set -uo pipefail

NEW_USER="${BBT_NEW_USER:-bbt}"
NEW_PASS="${BBT_NEW_PASS:-}"
OLD_USER="${BBT_OLD_USER:-kali}"

while [ $# -gt 0 ]; do
    case "$1" in
        --password) shift; NEW_PASS="${1:-}" ;;
        --password=*) NEW_PASS="${1#*=}" ;;
        --user) shift; NEW_USER="${1:-}" ;;
        --user=*) NEW_USER="${1#*=}" ;;
        -h|--help)
            echo "usage: sudo BBT_NEW_PASS='<password>' bash bbt-os-account.sh [--user NAME]"
            exit 0
            ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E bash "$0" "$@"
fi

[ -n "$NEW_PASS" ] || {
    echo "[!] set BBT_NEW_PASS (or pass --password) to choose the login password" >&2
    exit 2
}

if ! id "$OLD_USER" >/dev/null 2>&1; then
    echo "[!] $OLD_USER does not exist; nothing to migrate"
    exit 0
fi

OLD_HOME=$(getent passwd "$OLD_USER" | cut -d: -f6)
OLD_SHELL=$(getent passwd "$OLD_USER" | cut -d: -f7)
OLD_GROUPS=$(id -nG "$OLD_USER" | tr ' ' ',')

if [ -z "$OLD_HOME" ] || [ ! -d "$OLD_HOME" ]; then
    echo "[!] home directory for $OLD_USER not found" >&2
    exit 1
fi

if id "$NEW_USER" >/dev/null 2>&1; then
    echo "[*] user $NEW_USER already exists"
else
    echo "[*] creating $NEW_USER with home $OLD_HOME"
    useradd -d "$OLD_HOME" -s "${OLD_SHELL:-/bin/bash}" -c "BBT OS" \
        -G "$OLD_GROUPS" "$NEW_USER" || exit 1
fi

printf '%s:%s\n' "$NEW_USER" "$NEW_PASS" | chpasswd 2>/dev/null || {
    hash=$(openssl passwd -6 "$NEW_PASS" 2>/dev/null) || hash=""
    [ -n "$hash" ] || { echo "[!] could not set password" >&2; exit 1; }
    usermod -p "$hash" "$NEW_USER" || exit 1
}

echo "[*] transferring $OLD_HOME to $NEW_USER"
chown -R "$NEW_USER:$NEW_USER" "$OLD_HOME" || exit 1
[ -d "$OLD_HOME/.ssh" ] && chmod 700 "$OLD_HOME/.ssh"
[ -f "$OLD_HOME/.ssh/authorized_keys" ] && chmod 600 "$OLD_HOME/.ssh/authorized_keys"

usermod -aG sudo "$NEW_USER" 2>/dev/null || true
getent group docker >/dev/null 2>&1 && usermod -aG docker "$NEW_USER" 2>/dev/null || true

# Refuse to lock the old account unless the new one is usable.
if ! runuser -u "$NEW_USER" -- test -w "$OLD_HOME"; then
    echo "[!] $NEW_USER cannot write $OLD_HOME; leaving $OLD_USER enabled" >&2
    exit 1
fi
if ! id -nG "$NEW_USER" | tr ' ' '\n' | grep -qx sudo; then
    echo "[!] $NEW_USER is not in the sudo group; leaving $OLD_USER enabled" >&2
    exit 1
fi

if [ -f /etc/lightdm/users.conf ] && ! grep -qE "^hidden-users=.*\b$OLD_USER\b" /etc/lightdm/users.conf; then
    if grep -q '^hidden-users=' /etc/lightdm/users.conf; then
        sed -i "s|^hidden-users=.*|& $OLD_USER|" /etc/lightdm/users.conf
    else
        sed -i "/^\[UserList\]/a hidden-users=$OLD_USER" /etc/lightdm/users.conf
    fi
fi
acct=/var/lib/AccountsService/users/$OLD_USER
if [ -f "$acct" ] && ! grep -q '^SystemAccount=' "$acct"; then
    if grep -q '^\[User\]' "$acct"; then
        sed -i '/^\[User\]/a SystemAccount=true' "$acct"
    else
        printf '\n[User]\nSystemAccount=true\n' >>"$acct"
    fi
fi

if [ "$OLD_USER" != "$NEW_USER" ]; then
    usermod -s /usr/sbin/nologin "$OLD_USER"
    passwd -l "$OLD_USER" >/dev/null 2>&1 || true
    echo "[*] $OLD_USER disabled (nologin, password locked)"
fi

echo "[*] done: log in as $NEW_USER (change the password later with 'passwd')"
