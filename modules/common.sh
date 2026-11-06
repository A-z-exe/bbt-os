#!/usr/bin/env bash
# Shared helpers for BBT OS modules. Sourced by provision.sh and refresh.sh.

VERSION="${VERSION:-$(cat "$HERE/VERSION" 2>/dev/null || echo 1.0.0)}"
export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

MOBSF_IMAGE="opensecurity/mobile-security-framework-mobsf:latest"
MOBSF_NAME="bbt-mobsf"
BBT_REPO_URL="https://github.com/A-z-exe/BugBountyToolkit.git"

log()  { printf '\033[1;32m[*]\033[0m %s\n' "$*"; }
step() { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
ok()   { printf '    \033[32mOK\033[0m %s\n' "$*"; }

apt_install() {
    local pkg
    for pkg in "$@"; do
        if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed'; then
            ok "$pkg (already installed)"
            continue
        fi
        if apt-get install "${APT_OPTS[@]}" --no-install-recommends "$pkg"; then
            ok "$pkg"
        else
            warn "package unavailable: $pkg"
        fi
    done
}

run_as_user() {
    runuser -u "$TARGET_USER" -- env \
        HOME="$TARGET_HOME" \
        PATH="$TARGET_HOME/.local/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin" \
        "$@"
}

target_group() { id -gn "$TARGET_USER"; }

detect_target_user() {
    TARGET_USER="${BBT_TARGET_USER:-${SUDO_USER:-}}"
    if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = root ]; then
        if id bbt >/dev/null 2>&1; then
            TARGET_USER=bbt
        else
            TARGET_USER=$(awk -F: '$3 >= 1000 && $3 < 65534 && $7 !~ /(nologin|false)$/ {print $1; exit}' /etc/passwd)
        fi
    fi
    if [ -z "$TARGET_USER" ]; then
        warn "no desktop user found; falling back to kali"
        TARGET_USER=kali
    fi
    TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    if [ -z "$TARGET_HOME" ] || [ ! -d "$TARGET_HOME" ]; then
        warn "home directory for $TARGET_USER not found; falling back to /home/kali"
        TARGET_HOME=/home/kali
    fi
    TARGET_GROUP=$(target_group)
    TARGET_UID=$(id -u "$TARGET_USER")
    export TARGET_USER TARGET_HOME TARGET_GROUP TARGET_UID
}

# Print the XFCE session env for the target user when a session is running.
has_user_session() {
    [ -S "/run/user/$TARGET_UID/bus" ]
}

with_user_session() {
    runuser -u "$TARGET_USER" -- env \
        HOME="$TARGET_HOME" \
        DISPLAY="${DISPLAY:-:0}" \
        XDG_RUNTIME_DIR="/run/user/$TARGET_UID" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus" \
        PATH="$TARGET_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin" \
        "$@"
}
