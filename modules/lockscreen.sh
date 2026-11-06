#!/usr/bin/env bash
# BBT OS lock screen and login screen branding.

BBT_LOCK_BACKUP=/var/backups/bbt-os

lock_backup_once() {
    local src=$1 name=$2
    [ -f "$src" ] || return 0
    install -d -m 755 "$BBT_LOCK_BACKUP"
    if [ ! -f "$BBT_LOCK_BACKUP/$name" ]; then
        cp -a "$src" "$BBT_LOCK_BACKUP/$name" 2>/dev/null || true
        printf '%s\t%s\n' "$src" "$name" >>"$BBT_LOCK_BACKUP/lock-restore.tsv"
    fi
}

lock_set_ini() {
    local file=$1 key=$2 value=$3
    if grep -qE "^[[:space:]]*$key[[:space:]]*=" "$file"; then
        sed -i -E "s|^[[:space:]]*$key[[:space:]]*=.*|$key = $value|" "$file"
    elif grep -q '^\[greeter\]' "$file"; then
        sed -i "/^\[greeter\]/a $key = $value" "$file"
    else
        printf '[greeter]\n%s = %s\n' "$key" "$value" >>"$file"
    fi
}

lock_set_accounts_icon() {
    local user=$1 icon=$2 dir=/var/lib/AccountsService/users
    [ -d "$dir" ] || return 0
    local file="$dir/$user"
    if [ ! -f "$file" ]; then
        printf '[User]\nIcon=%s\nSystemAccount=false\n' "$icon" >"$file"
        return 0
    fi
    if grep -q '^Icon=' "$file"; then
        sed -i "s|^Icon=.*|Icon=$icon|" "$file"
    elif grep -q '^\[User\]' "$file"; then
        sed -i "/^\[User\]/a Icon=$icon" "$file"
    else
        printf '\n[User]\nIcon=%s\n' "$icon" >>"$file"
    fi
}

install_lockscreen() {
    step "BBT OS lock and login screen"
    install -d -m 755 /usr/share/bbt-os
    install -m 644 "$HERE/assets/login.png" /usr/share/bbt-os/login.png
    install -m 644 "$HERE/assets/avatar.png" /usr/share/bbt-os/avatar.png

    local greeter=/etc/lightdm/lightdm-gtk-greeter.conf
    lock_backup_once "$greeter" lightdm-gtk-greeter.conf.orig
    if [ -f "$greeter" ]; then
        lock_set_ini "$greeter" background /usr/share/bbt-os/login.png
        lock_set_ini "$greeter" default-user-image /usr/share/bbt-os/avatar.png
    else
        cat >"$greeter" <<'EOF'
[greeter]
background = /usr/share/bbt-os/login.png
theme-name = Kali-Light
icon-theme-name = Flat-Remix-Blue-Dark
default-user-image = /usr/share/bbt-os/avatar.png
EOF
    fi
    ok "login screen background set"

    lock_set_accounts_icon "$TARGET_USER" /usr/share/bbt-os/avatar.png

    local css_dir="$TARGET_HOME/.config/gtk-3.0" css="$TARGET_HOME/.config/gtk-3.0/gtk.css"
    install -d -m 755 "$css_dir"
    if ! grep -q 'BBT OS lock dialog' "$css" 2>/dev/null; then
        cat >>"$css" <<'EOF'

/* BBT OS lock dialog */
#login_window {
  background-color: rgba(5, 15, 13, 0.94);
  border: 1px solid #145c4a;
  border-radius: 14px;
}
#login_window entry {
  background-color: #04120e;
  color: #d7fff1;
  border: 1px solid #145c4a;
  border-radius: 6px;
}
#login_window button {
  background-image: none;
  background-color: #0a1c19;
  color: #d7fff1;
  border: 1px solid #145c4a;
  border-radius: 6px;
}
#login_window button:hover { background-color: #123f38; }
#login_button { background-image: none; background-color: #39ff14; color: #04120e; font-weight: bold; }
#auth-realname-label, #auth-status-label { color: #7de3c3; }
EOF
    fi
    chown "$TARGET_USER:$(id -gn "$TARGET_USER")" "$css_dir" "$css" 2>/dev/null || true

    lock_xfset() {
        local channel=$1 prop=$2 type=$3 value=$4
        with_user_session xfconf-query -c "$channel" -p "$prop" -t "$type" -s "$value" 2>/dev/null \
            || with_user_session xfconf-query -c "$channel" -p "$prop" -n -t "$type" -s "$value" 2>/dev/null \
            || true
    }
    if has_user_session; then
        lock_xfset xfce4-screensaver /lock/enabled bool true
        lock_xfset xfce4-screensaver /lock/saver-activation/delay int 0
        lock_xfset xfce4-screensaver /lock/idle-activation/enabled bool true
        lock_xfset xfce4-power-manager /xfce4-power-manager/lock-screen-suspend-hibernate bool true
        lock_xfset xfce4-session /shutdown/LockScreen bool true
        lock_xfset xfce4-keyboard-shortcuts "/commands/custom/<Primary><Alt>l" string xflock4
        ok "lock settings applied (Ctrl+Alt+L locks the screen)"
    else
        warn "no graphical session; lock settings apply at next login"
    fi
    ok "lock screen ready"
}
