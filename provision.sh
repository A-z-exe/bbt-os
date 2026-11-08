#!/usr/bin/env bash
# BBT OS - provisioning overlay for Kali Rolling.
#
# Run as root:  sudo bash install.sh   (or: sudo bash provision.sh)
# This does not modify the Kali installer ISO. It turns a stock Kali system
# into BBT OS: identity, launcher, wallpaper, tool groups and BBT Toolkit.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(cat "$HERE/VERSION" 2>/dev/null || echo 1.0.0)"
LOG="${BBT_OS_LOG:-/var/log/bbt-os-provision.log}"
ORIG_ARGS=("$@")

DO_UPGRADE=1
DO_WEB=1
DO_ANDROID=1
DO_WINDOWS=1
DO_MOBSF=1
DO_BBT=1
DO_DESKTOP=1
DO_BRANDING=1
DO_BOOT=1
DO_LOCK=1
DO_SMARTCARD=1
DO_KERNEL=1
DO_WIFI=1
DO_WORKFLOWS=1
DO_AUDIT=1

while [ $# -gt 0 ]; do
    case "$1" in
        --no-upgrade)  DO_UPGRADE=0 ;;
        --no-web)      DO_WEB=0 ;;
        --no-android)  DO_ANDROID=0 ;;
        --no-windows)  DO_WINDOWS=0 ;;
        --no-mobsf)    DO_MOBSF=0 ;;
        --no-bbt)      DO_BBT=0 ;;
        --no-desktop)  DO_DESKTOP=0 ;;
        --no-branding) DO_BRANDING=0 ;;
        --no-boot)     DO_BOOT=0 ;;
        --no-lock)     DO_LOCK=0 ;;
        --no-smartcard) DO_SMARTCARD=0 ;;
        --no-kernel)   DO_KERNEL=0 ;;
        --no-wifi)     DO_WIFI=0 ;;
        --no-workflows) DO_WORKFLOWS=0 ;;
        --no-audit)    DO_AUDIT=0 ;;
        --web-only)    DO_ANDROID=0; DO_WINDOWS=0; DO_MOBSF=0 ;;
        --target-user) shift; BBT_TARGET_USER="${1:-}" ;;
        --target-user=*) BBT_TARGET_USER="${1#*=}" ;;
        --help|-h)
            cat <<EOF
BBT OS $VERSION installer

Usage: sudo bash install.sh [options]

  --no-upgrade       skip apt full-upgrade
  --no-web           skip web/recon tools and database refresh
  --no-android       skip Android tools (adb, apktool, jadx, frida, scrcpy)
  --no-windows       skip Windows/AD tools (impacket, netexec, evil-winrm...)
  --no-mobsf         skip Docker/MobSF
  --no-bbt           skip the BBT Toolkit checkout
  --no-desktop       skip launcher, wallpaper and file associations
  --no-branding      skip hostname, os-release, issue and MOTD
  --no-boot          skip the BBT OS boot splash and GRUB artwork
  --no-lock          skip lock/login screen branding and lock settings
  --no-smartcard     skip smart card / NFC tools
  --no-kernel        skip kernel headers, firmware and module setup
  --no-wifi          skip wireless tools and the bbt-wifi engine
  --no-workflows     skip the matched workflow engine
  --no-audit         skip installing the health doctor
  --web-only         web tooling only (no Android, Windows or MobSF)
  --target-user USER install user-level pieces for USER (default: SUDO_USER)
  -h, --help         show this help

Environment:
  BBT_TARGET_USER    same as --target-user
  BBT_MOBSF_PULL=0   do not pull the MobSF image
  BBT_OS_LOG         log path (default /var/log/bbt-os-provision.log)
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
    exec sudo -E bash "$HERE/provision.sh" "${ORIG_ARGS[@]}"
fi

exec > >(tee -a "$LOG") 2>&1
echo "=== BBT OS $VERSION provisioning: $(date -Is) ==="

# shellcheck source=modules/common.sh
source "$HERE/modules/common.sh"
detect_target_user
log "Install user: $TARGET_USER ($TARGET_HOME)"

# ---------------------------------------------------------------------------
# apt
# ---------------------------------------------------------------------------
step "Package lists"
if ! apt-get update "${APT_OPTS[@]}"; then
    warn "apt update failed (network or VPN?). Continuing with existing lists."
fi

if [ "$DO_UPGRADE" = 1 ]; then
    step "System upgrade"
    apt-get full-upgrade "${APT_OPTS[@]}" || warn "full-upgrade reported errors"
else
    log "System upgrade skipped (--no-upgrade)"
fi

step "Base packages"
mapfile -t BASE_PKGS < <(grep -vE '^[[:space:]]*(#|$)' "$HERE/packages/base.txt")
apt_install "${BASE_PKGS[@]}"
apt-get install "${APT_OPTS[@]}" libfuse2 >/dev/null 2>&1 \
    || apt-get install "${APT_OPTS[@]}" libfuse2t64 >/dev/null 2>&1 \
    || warn "libfuse2 unavailable; AppImages run in extract-and-run mode"

# ---------------------------------------------------------------------------
# kernel and drivers
# ---------------------------------------------------------------------------
if [ "$DO_KERNEL" = 1 ]; then
    # shellcheck source=modules/kernel.sh
    source "$HERE/modules/kernel.sh"
    install_kernel_support
fi

# ---------------------------------------------------------------------------
# tool groups
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# desktop and identity
# ---------------------------------------------------------------------------
if [ "$DO_DESKTOP" = 1 ]; then
    # shellcheck source=modules/desktop.sh
    source "$HERE/modules/desktop.sh"
    install_desktop
fi
if [ "$DO_AUDIT" = 1 ]; then
    # shellcheck source=modules/audit.sh
    source "$HERE/modules/audit.sh"
    install_audit
fi
if [ "$DO_BRANDING" = 1 ]; then
    # shellcheck source=modules/branding.sh
    source "$HERE/modules/branding.sh"
    install_branding
fi
if [ "$DO_BOOT" = 1 ]; then
    # shellcheck source=modules/boot.sh
    source "$HERE/modules/boot.sh"
    install_boot_branding
fi
if [ "$DO_LOCK" = 1 ]; then
    # shellcheck source=modules/lockscreen.sh
    source "$HERE/modules/lockscreen.sh"
    install_lockscreen
fi

# ---------------------------------------------------------------------------
# services
# ---------------------------------------------------------------------------
step "Services"
systemctl enable --now ssh >/dev/null 2>&1 || warn "SSH could not be enabled"
systemctl restart open-vm-tools >/dev/null 2>&1 || true
loginctl enable-linger "$TARGET_USER" >/dev/null 2>&1 || true
ok "ssh, open-vm-tools and linger"

# ---------------------------------------------------------------------------
# verification
# ---------------------------------------------------------------------------
step "Tool inventory"
missing=0
for t in nmap ffuf nuclei httpx subfinder katana amass dnsx naabu gobuster \
         feroxbuster dirb nikto sqlmap wpscan hydra whatweb wafw00f gowitness \
         theharvester searchsploit msfconsole burpsuite wireshark \
         adb fastboot apktool jadx apksigner d2j-dex2jar scrcpy \
         frida-ps objection \
         netexec evil-winrm responder enum4linux-ng bloodhound-python docker bbt \
         aircrack-ng hcxdumptool hcxpcapngtool hcxtools reaver bettercap hashcat; do
    if command -v "$t" >/dev/null 2>&1 || [ -x "$TARGET_HOME/.local/bin/$t" ]; then
        printf '  OK      %s\n' "$t"
    else
        printf '  MISSING %s\n' "$t"
        missing=$((missing + 1))
    fi
done
[ -x /usr/local/bin/bbt-os-launcher ] \
    && printf '  OK      %s\n' "/usr/local/bin/bbt-os-launcher" \
    || printf '  MISSING %s\n' "/usr/local/bin/bbt-os-launcher"
for t in bbt-wifi bbt-workflow bbt-surface bbt-bounty bbt-ktune bbt-access bbt-os-doctor; do
    if [ -x "/usr/local/bin/$t" ]; then
        printf '  OK      %s\n' "/usr/local/bin/$t"
    else
        printf '  MISSING %s\n' "/usr/local/bin/$t"
        missing=$((missing + 1))
    fi
done
[ "$missing" -eq 0 ] || warn "$missing tools are missing; see the log above"

echo
echo "=== Done: $(date -Is) ==="
echo "Log out and back in (or reboot) once to apply identity, wallpaper and cursor."
echo "Launch: search for \"BBT OS\" in the menu, or run: bbt-os"
echo "Refresh later with: sudo bbt-os-refresh"
