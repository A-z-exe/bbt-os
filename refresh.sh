#!/usr/bin/env bash
# BBT OS - lightweight refresh (packages, tool databases and desktop assets).
# Run as root: sudo bbt-os-refresh [options]
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(cat "$HERE/VERSION" 2>/dev/null || echo 1.0.0)"
LOG="${BBT_OS_LOG:-/var/log/bbt-os-refresh.log}"
ORIG_ARGS=("$@")

DO_UPGRADE=1
DO_WEB=1
DO_ANDROID=1
DO_WINDOWS=1
DO_MOBSF=1
DO_BBT=1
DO_DESKTOP=1
DO_BOOT=1
DO_LOCK=1
DO_SMARTCARD=1
DO_KERNEL=1
DO_WIFI=1
DO_WORKFLOWS=1
DO_AUDIT=1

while [ $# -gt 0 ]; do
    case "$1" in
        --no-upgrade) DO_UPGRADE=0 ;;
        --no-web)     DO_WEB=0 ;;
        --no-android) DO_ANDROID=0 ;;
        --no-windows) DO_WINDOWS=0 ;;
        --no-mobsf)   DO_MOBSF=0 ;;
        --no-bbt)     DO_BBT=0 ;;
        --no-desktop) DO_DESKTOP=0 ;;
        --no-boot)    DO_BOOT=0 ;;
        --no-lock)    DO_LOCK=0 ;;
        --no-smartcard) DO_SMARTCARD=0 ;;
        --no-kernel)  DO_KERNEL=0 ;;
        --no-wifi)    DO_WIFI=0 ;;
        --no-workflows) DO_WORKFLOWS=0 ;;
        --no-audit)   DO_AUDIT=0 ;;
        --target-user) shift; BBT_TARGET_USER="${1:-}" ;;
        --target-user=*) BBT_TARGET_USER="${1#*=}" ;;
        --help|-h)
            cat <<EOF
BBT OS $VERSION refresh

Usage: sudo bbt-os-refresh [options]

  --no-upgrade   skip apt full-upgrade
  --no-web       skip web packages and database refresh
  --no-android   skip Android packages
  --no-windows   skip Windows/AD packages
  --no-mobsf     skip the Docker/MobSF check
  --no-bbt       skip the BBT Toolkit update
  --no-desktop   skip relaunching/reinstalling desktop assets
  --no-boot      skip refreshing boot splash and GRUB artwork
  --no-lock      skip refreshing lock/login screen assets
  --no-smartcard skip smart card / NFC packages
  --no-kernel    skip kernel headers, firmware and modules
  --no-wifi      skip wireless packages and the bbt-wifi engine
  --no-workflows skip the matched workflow engine
  --no-audit     skip the health doctor
  --target-user USER  refresh user-level pieces for USER
  -h, --help     show this help
EOF
            exit 0
            ;;
        *)
            echo "unknown option: $1 (see --help)" >&2
            exit 2
            ;;
    esac
    shift
done

if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E bash "$HERE/refresh.sh" "${ORIG_ARGS[@]}"
fi

exec > >(tee -a "$LOG") 2>&1
echo "=== BBT OS $VERSION refresh: $(date -Is) ==="

# shellcheck source=modules/common.sh
source "$HERE/modules/common.sh"
detect_target_user

if ! apt-get update "${APT_OPTS[@]}"; then
    warn "apt update failed; continuing with existing package lists"
fi
if [ "$DO_UPGRADE" = 1 ]; then
    apt-get full-upgrade "${APT_OPTS[@]}" || warn "full-upgrade reported errors"
fi

if [ "$DO_KERNEL" = 1 ]; then
    # shellcheck source=modules/kernel.sh
    source "$HERE/modules/kernel.sh"
    install_kernel_support
fi

if [ "$DO_WEB" = 1 ]; then
    # shellcheck source=modules/web.sh
    source "$HERE/modules/web.sh"
    install_web
fi
if [ "$DO_ANDROID" = 1 ]; then
    # shellcheck source=modules/android.sh
    source "$HERE/modules/android.sh"
    install_android
fi
if [ "$DO_WINDOWS" = 1 ]; then
    # shellcheck source=modules/windows.sh
    source "$HERE/modules/windows.sh"
    install_windows
fi
if [ "$DO_SMARTCARD" = 1 ]; then
    # shellcheck source=modules/smartcard.sh
    source "$HERE/modules/smartcard.sh"
    install_smartcard
fi
if [ "$DO_WIFI" = 1 ]; then
    # shellcheck source=modules/wifi.sh
    source "$HERE/modules/wifi.sh"
    install_wifi
fi
if [ "$DO_MOBSF" = 1 ]; then
    BBT_MOBSF_PULL=0
    # shellcheck source=modules/mobsf.sh
    source "$HERE/modules/mobsf.sh"
    install_mobsf
fi
if [ "$DO_BBT" = 1 ]; then
    # shellcheck source=modules/bbt.sh
    source "$HERE/modules/bbt.sh"
    install_bbt
fi
if [ "$DO_WORKFLOWS" = 1 ]; then
    # shellcheck source=modules/workflows.sh
    source "$HERE/modules/workflows.sh"
    install_workflows
fi
if [ "$DO_DESKTOP" = 1 ]; then
    # shellcheck source=modules/desktop.sh
    source "$HERE/modules/desktop.sh"
    install_desktop
fi
# Needs the root-owned /opt/bbt-os copy that install_desktop refreshes.
# shellcheck source=modules/root.sh
source "$HERE/modules/root.sh"
install_root_helper
if [ "$DO_AUDIT" = 1 ]; then
    # shellcheck source=modules/audit.sh
    source "$HERE/modules/audit.sh"
    install_audit
fi
if [ "$DO_BOOT" = 1 ]; then
    # artwork only: the theme is already in the initramfs
    BBT_BOOT_DEEP=0
    # shellcheck source=modules/boot.sh
    source "$HERE/modules/boot.sh"
    install_boot_branding
fi
if [ "$DO_LOCK" = 1 ]; then
    # shellcheck source=modules/lockscreen.sh
    source "$HERE/modules/lockscreen.sh"
    install_lockscreen
fi

echo "=== refresh done: $(date -Is) ==="
