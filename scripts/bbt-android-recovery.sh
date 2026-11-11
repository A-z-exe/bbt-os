#!/usr/bin/env bash
# bbt-android-recovery - non-destructive access to phones you own or may service.
#
#   bbt-android-recovery status    device state, encryption, root and lock options
#   bbt-android-recovery plan      what can be done without wiping the device
#   bbt-android-recovery pull      copy photos and documents off an authorized device
#   bbt-android-recovery unlock    clear the lock screen on a rooted, authorized device
#   bbt-android-recovery linux     recovery steps for Linux phones (postmarketOS, Librem)
#
# This helper never wipes, never flashes, never unlocks a bootloader and never
# runs an exploit. Removal without data loss is only possible when ADB was
# already authorized and root is available; everything else needs the vendor,
# a service center with proof of purchase, or accepts a factory reset.
set -uo pipefail

VERSION="$(cat /usr/share/bbt-os/VERSION 2>/dev/null || echo unknown)"

USER_HOME="${HOME:-/root}"
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
    USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
fi
BACKUP_ROOT="${BBT_ANDROID_DIR:-$USER_HOME/bbt/android}"

RED=$'\033[31m'; GREEN=$'\033[32m'; AMBER=$'\033[33m'; CYAN=$'\033[36m'; OFF=$'\033[0m'
[ -t 1 ] || { RED=""; GREEN=""; AMBER=""; CYAN=""; OFF=""; }

info() { printf '%s[*]%s %s\n' "$GREEN" "$OFF" "$*"; }
warn() { printf '%s[!]%s %s\n' "$AMBER" "$OFF" "$*"; }
die()  { printf '%s[x]%s %s\n' "$RED" "$OFF" "$*" >&2; exit 1; }

usage() {
    awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0"
}

require_adb() {
    command -v adb >/dev/null 2>&1 || die "adb is not installed (sudo apt install adb)"
    adb start-server >/dev/null 2>&1 || true
}

require_consent() {
    [ "${CONSENT:-0}" = 1 ] || die \
        "this command reads or changes a personal device; confirm ownership or written authorization with --i-own-this-device"
}

# <serial> -> "device", "unauthorized", "offline" or empty
device_state() {
    adb devices 2>/dev/null | awk -v s="$1" '$1 == s {print $2; exit}'
}

authorized_serials() {
    adb devices 2>/dev/null | awk 'NR > 1 && $2 == "device" {print $1}'
}

pick_serial() {
    local wanted=${1:-}
    if [ -n "$wanted" ]; then
        [ "$(device_state "$wanted")" = device ] \
            || die "device $wanted is not connected and authorized (state: $(device_state "$wanted" || true))"
        printf '%s' "$wanted"
        return 0
    fi
    local -a serials=()
    mapfile -t serials < <(authorized_serials)
    case "${#serials[@]}" in
        0)
            local pending
            pending=$(adb devices 2>/dev/null | awk 'NR > 1 && $2 != "" {print $1 " (" $2 ")"}' | paste -sd', ' -)
            [ -n "$pending" ] && warn "connected but not authorized: $pending"
            die "no authorized device; connect USB, enable USB debugging and accept the RSA prompt"
            ;;
        1) printf '%s' "${serials[0]}" ;;
        *)
            die "several devices connected (${serials[*]}); choose one with --serial"
            ;;
    esac
}

prop() {
    adb -s "$1" shell getprop "$2" 2>/dev/null | tr -d '\r' | head -n1
}

# prints "su" or "adbd" when the device can run a command as uid 0
root_mode() {
    local serial=$1 out
    out=$(adb -s "$serial" shell "su -c 'id -u'" 2>/dev/null | tr -d '\r' | tail -n1)
    [ "$out" = 0 ] && { printf 'su'; return 0; }
    out=$(adb -s "$serial" shell id -u 2>/dev/null | tr -d '\r' | tail -n1)
    [ "$out" = 0 ] && { printf 'adbd'; return 0; }
    return 1
}

# userdebug builds can restart adbd as root without touching data
try_adb_root() {
    local serial=$1
    [ "$(prop "$serial" ro.debuggable)" = 1 ] || return 1
    adb -s "$serial" root >/dev/null 2>&1 || return 1
    sleep 2
    [ "$(adb -s "$serial" shell id -u 2>/dev/null | tr -d '\r' | tail -n1)" = 0 ]
}

root_exec() {
    local serial=$1 mode=$2 cmd=$3
    case "$mode" in
        su)   adb -s "$serial" shell "su -c '$cmd'" ;;
        adbd) adb -s "$serial" shell "$cmd" ;;
        *)    return 1 ;;
    esac
}

is_linux_phone() {
    local serial=$1 os name
    os=$(adb -s "$serial" shell 'cat /etc/os-release 2>/dev/null' 2>/dev/null | tr -d '\r')
    name=$(prop "$serial" ro.product.name)
    case "$os $name" in
        *postmarketOS*|*Alpine*|*PinePhone*|*pinephone*|*Librem*|*librem*) return 0 ;;
    esac
    return 1
}

describe_device() {
    local serial=$1 model maker release patch boot debug crypto ctype root linux
    model=$(prop "$serial" ro.product.model)
    maker=$(prop "$serial" ro.product.manufacturer)
    release=$(prop "$serial" ro.build.version.release)
    patch=$(prop "$serial" ro.build.version.security_patch)
    boot=$(prop "$serial" ro.boot.verifiedbootstate)
    debug=$(prop "$serial" ro.debuggable)
    crypto=$(prop "$serial" ro.crypto.state)
    ctype=$(prop "$serial" ro.crypto.type)
    root=$(root_mode "$serial" || true)
    linux=0
    is_linux_phone "$serial" && linux=1

    info "${model:-unknown model}${maker:+ ($maker)} - $serial"
    printf '    android        %s\n' "${release:-?}"
    printf '    security patch %s\n' "${patch:-?}"
    printf '    verified boot  %s\n' "${boot:-?}"
    printf '    debuggable     %s\n' "${debug:-?}"
    printf '    encryption     %s%s\n' "${crypto:-?}" \
        "$([ -n "$ctype" ] && [ "$ctype" != unknown ] && echo " ($ctype)" || true)"
    if [ -n "$root" ]; then
        printf '    root           yes (%s)\n' "$root"
    else
        printf '    root           no\n'
    fi
    [ "$linux" = 1 ] && printf '    platform       Linux phone (postmarketOS/Alpine detected)\n'

    if [ "$linux" = 1 ]; then
        printf '    lock option    account password: bbt-android-recovery linux\n'
    elif [ -n "$root" ]; then
        printf '    lock option    clear without wipe: bbt-android-recovery unlock --i-own-this-device\n'
    else
        printf '    lock option    data pull only; no supported non-destructive unlock\n'
    fi
}

cmd_status() {
    require_adb
    local -a serials=()
    printf '%s[*]%s adb %s\n' "$GREEN" "$OFF" "$(adb version 2>/dev/null | head -n1)"
    mapfile -t serials < <(authorized_serials)
    if [ "${#serials[@]}" -eq 0 ]; then
        warn "no authorized device"
        local pending
        pending=$(adb devices 2>/dev/null | awk 'NR > 1 && $2 != "" {print "    " $1 "  " $2}')
        [ -n "$pending" ] && printf '%s\n' "$pending"
        printf '    enable USB debugging, plug in and accept the RSA prompt on the phone\n'
        return 1
    fi
    local serial
    for serial in "${serials[@]}"; do
        describe_device "$serial"
    done
    local unauthorized
    unauthorized=$(adb devices 2>/dev/null | awk 'NR > 1 && $2 == "unauthorized" {print $1}' | paste -sd', ' -)
    [ -n "$unauthorized" ] && warn "unauthorized: $unauthorized (unlock once and accept the prompt)"
    return 0
}

cmd_plan() {
    require_adb
    cat <<'EOF'
Non-destructive options, strongest first:

1) ADB already authorized + root (Magisk/su or a userdebug build)
   -> bbt-android-recovery unlock --i-own-this-device
      clears the credential with locksettings, no wipe, no reboot.
   -> If the phone rebooted and has not been unlocked since, /data is still
      encrypted and ADB will not answer until the first unlock. Nothing can be
      done over ADB in that state.

2) ADB already authorized, no root
   -> bbt-android-recovery pull --dest DIR --i-own-this-device
      photos, downloads and documents can be copied off.
   -> No supported way to clear the lock through ADB. Root the device with a
      method for that exact model first, or use the vendor path below.

3) Vendor path (keeps data only if the vendor says so)
   -> Samsung: remote unlock through the Samsung account, if the service is
      still offered for that model.
   -> Google Find My Device, Xiaomi and Huawei only erase the device.
   -> Service center with proof of purchase can unlock some models.
   -> Unlocking a locked bootloader always wipes the device.

4) Linux phones (postmarketOS, PinePhone, Librem 5)
   -> The lock is the OS account password; reset it offline:
      bbt-android-recovery linux

What this helper will not do: exploits, bootloader unlocks, FRP bypass or any
step that erases data. Those are out of scope for a bug bounty workstation.
EOF
}

cmd_pull() {
    local serial="" dest="" all=0
    local -a paths=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --serial) [ $# -ge 2 ] || die "--serial needs a value"; serial=$2; shift 2 ;;
            --serial=*) serial=${1#*=}; shift ;;
            --dest) [ $# -ge 2 ] || die "--dest needs a value"; dest=$2; shift 2 ;;
            --dest=*) dest=${1#*=}; shift ;;
            --path) [ $# -ge 2 ] || die "--path needs a value"; paths+=("$2"); shift 2 ;;
            --path=*) paths+=("${1#*=}"); shift ;;
            --all) all=1; shift ;;
            --i-own-this-device) CONSENT=1; shift ;;
            -h|--help) usage; return 0 ;;
            *) die "unknown pull option: $1" ;;
        esac
    done
    require_consent
    require_adb
    serial=$(pick_serial "$serial") || exit 1
    [ -n "$dest" ] || dest="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)-$serial"
    dest="${dest/#\~/$USER_HOME}"
    mkdir -p "$dest" || die "cannot create $dest"

    if [ "$all" = 1 ]; then
        paths=(/sdcard/)
    elif [ "${#paths[@]}" -eq 0 ]; then
        paths=(/sdcard/DCIM /sdcard/Pictures /sdcard/Download /sdcard/Documents /sdcard/Movies)
    fi

    info "copying from $serial to $dest"
    info "(private app data stays encrypted; root or a vendor migration tool is needed for that)"
    local path failed=0
    for path in "${paths[@]}"; do
        if adb -s "$serial" pull "$path" "$dest" >/dev/null 2>&1; then
            printf '    %s %s\n' "$(printf '\033[32mok\033[0m')" "$path"
        else
            printf '    %s %s\n' "$(printf '\033[31mfailed\033[0m')" "$path" >&2
            failed=$((failed + 1))
        fi
    done
    if [ "$failed" -gt 0 ]; then
        warn "$failed path(s) failed; check the path on the device or whether the lock blocks access"
        return 1
    fi
    info "done: $dest"
}

cmd_unlock() {
    local serial="" mode
    while [ $# -gt 0 ]; do
        case "$1" in
            --serial) serial=$2; shift 2 ;;
            --serial=*) serial=${1#*=}; shift ;;
            --i-own-this-device) CONSENT=1; shift ;;
            -h|--help) usage; return 0 ;;
            *) die "unknown unlock option: $1" ;;
        esac
    done
    require_consent
    require_adb
    serial=$(pick_serial "$serial") || exit 1

    mode=$(root_mode "$serial" || true)
    if [ -z "$mode" ] && try_adb_root "$serial"; then
        mode=adbd
    fi
    if [ -z "$mode" ]; then
        die "no root on $serial; a lock cannot be removed without wiping.
     Run 'bbt-android-recovery plan' for the vendor and Linux-phone options."
    fi

    local model
    model=$(prop "$serial" ro.product.model)
    info "device: ${model:-unknown} ($serial), root via $mode"
    info "clearing the lock credential without touching user data"

    if root_exec "$serial" "$mode" "locksettings clear"; then
        printf '%s[+]%s lock cleared; wake the phone and it should open without a PIN\n' "$GREEN" "$OFF"
        return 0
    fi

    warn "locksettings clear was refused (some ROMs restrict it)"
    cat <<'EOF'
Manual path for the same device, data preserved:
  - With root in a terminal app: su -c "locksettings clear"
  - With an already-unlocked bootloader and a custom recovery:
      boot recovery, mount /data, delete
        /data/system/locksettings.db
        /data/system/locksettings.db-shm
        /data/system/locksettings.db-wal
      then reboot. This keeps user data but loses the saved fingerprint/PIN.
  - Never run 'fastboot -w' or a factory reset: both erase everything.
EOF
    return 1
}

cmd_linux() {
    cat <<'EOF'
Linux phone recovery (postmarketOS, PinePhone, Librem 5, Fedora/Ubuntu Touch)

The lock screen asks for the account password, so removing it is a password
reset, not a bootloader or vendor operation. Data stays in place.

  1. Power off and boot a Linux live USB on a PC.
  2. Identify the phone storage:          lsblk -f
  3. Encrypted (LUKS) installs need the  cryptsetup open /dev/sdXN phone-root
     disk passphrase; without it the data is unrecoverable.
  4. Mount the root file system:          sudo mount /dev/mapper/phone-root /mnt/phone
  5. For a separate /home, mount it too:  sudo mount /dev/sdXZ /mnt/phone/home
  6. Chroot and reset the password:
       sudo mount --bind /dev  /mnt/phone/dev
       sudo mount --bind /proc /mnt/phone/proc
       sudo mount --bind /sys  /mnt/phone/sys
       sudo chroot /mnt/phone passwd USER
  7. If the account was locked:           sudo chroot /mnt/phone passwd -u USER
  8. Unmount everything, remove the USB and boot the phone.
     The PIN is the account password, so the new password opens the lock screen.

Android phones with a Linux userland (Termux, a chroot, a custom ROM):
  - Termux is a normal app; clearing the Android lock is the Android path above.
  - For a proot/chroot userland, boot recovery, mount /data and fix the shadow
    file inside the image; full-disk encryption still requires the first unlock.

This helper does not mount or edit anything itself; run these steps yourself on
a device you own.
EOF
}

main() {
    local cmd=${1:-help}
    shift || true
    case "$cmd" in
        status) cmd_status "$@" ;;
        plan) cmd_plan "$@" ;;
        pull) cmd_pull "$@" ;;
        unlock) cmd_unlock "$@" ;;
        linux) cmd_linux "$@" ;;
        version|--version|-V) printf 'bbt-android-recovery %s\n' "$VERSION" ;;
        help|-h|--help) usage ;;
        *) die "unknown command: $cmd (try: status, plan, pull, unlock, linux)" ;;
    esac
}

main "$@"
