#!/usr/bin/env bash
# bbt-os-doctor - health check for the BBT OS kernel, services and toolchain.
#
#   bbt-os-doctor            human readable report
#   bbt-os-doctor --json     machine readable entries
#   bbt-os-doctor --summary  one line for the launcher status bar
#   bbt-os-doctor --fix      install missing core packages and fix services
set -uo pipefail

VERSION="$(cat /usr/share/bbt-os/VERSION 2>/dev/null || echo unknown)"
JSON=0
SUMMARY=0
FIX=0
QUIET=0

for arg in "$@"; do
    case "$arg" in
        --json) JSON=1 ;;
        --summary) SUMMARY=1 ;;
        --fix) FIX=1 ;;
        --quiet) QUIET=1 ;;
        -h|--help)
            awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0"
            exit 0
            ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

# --summary is consumed by the launcher status bar: one line, no report body.
[ "$SUMMARY" = 1 ] && QUIET=1
# A --fix pass only repairs; the clean re-exec below prints the new report.
if [ "$FIX" = 1 ] && [ "${BBT_DOCTOR_FIXED:-0}" != 1 ]; then
    QUIET=1
fi

PASS=0
WARN=0
FAIL=0
FAILED=()
ENTRIES=()

red()   { printf '\033[31m%s\033[0m' "$*"; }
green() { printf '\033[32m%s\033[0m' "$*"; }
amber() { printf '\033[33m%s\033[0m' "$*"; }
cyan()  { printf '\033[36m%s\033[0m' "$*"; }

section() { [ "$JSON" = 1 ] || [ "$QUIET" = 1 ] || printf '\n%s\n' "$(cyan "== $* ==")"; }

jesc() { printf '%s' "$1" | sed -e 's/[[:cntrl:]]/ /g' -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

record() {
    local status=$1 name=$2 detail=$3
    ENTRIES+=("{\"name\":\"$(jesc "$name")\",\"status\":\"$status\",\"detail\":\"$(jesc "$detail")\"}")
    case "$status" in
        PASS) PASS=$((PASS + 1)) ;;
        WARN) WARN=$((WARN + 1)) ;;
        FAIL) FAIL=$((FAIL + 1)); FAILED+=("$name") ;;
    esac
    if [ "$JSON" = 0 ] && [ "$QUIET" = 0 ]; then
        case "$status" in
            PASS) printf '  %s %-26s %s\n' "$(green PASS)" "$name" "$detail" ;;
            WARN) printf '  %s %-26s %s\n' "$(amber WARN)" "$name" "$detail" ;;
            FAIL) printf '  %s %-26s %s\n' "$(red "FAIL")" "$name" "$detail" ;;
        esac
    fi
}

pass() { record PASS "$1" "$2"; }
warn() { record WARN "$1" "$2"; }
fail() { record FAIL "$1" "$2"; }

need_root_fix() {
    [ "$FIX" = 1 ] && [ "$(id -u)" -ne 0 ]
}

if need_root_fix; then
    exec sudo -E bash "$0" "$@"
fi

target_user() {
    local uid=${PKEXEC_UID:-}
    if [ -n "$uid" ] && [ "$uid" != 0 ]; then
        getent passwd "$uid" | cut -d: -f1
        return
    fi
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then echo "$SUDO_USER"
    elif id bbt >/dev/null 2>&1; then echo bbt
    else id -un
    fi
}
TU="$(target_user)"
TH="$(getent passwd "$TU" | cut -d: -f6)"
[ -d "$TH" ] || TH="/home/kali"
if [ "$(id -u)" -ne 0 ]; then
    # pipx/uv tools live in ~/.local/bin and are absent from a non-login PATH
    export PATH="$TH/.local/bin:/usr/local/bin:$PATH"
fi

as_target() {
    if [ "$(id -u)" -eq 0 ]; then runuser -u "$TU" -- "$@"; else "$@"; fi
}

probe() {
    # probe <tool> -> prints first non-empty line of a version/help invocation
    local tool=$1 bin flag out
    bin=$(command -v "$tool" 2>/dev/null) || bin="$TH/.local/bin/$tool"
    [ -x "$bin" ] || return 127
    local -a runner=("$bin")
    if [ "$(id -u)" -eq 0 ] && [ "${bin#"$TH"/}" != "$bin" ]; then
        runner=(runuser -u "$TU" -- "$bin")
    fi
    for flag in --version -version -V version -h --help -Help -help; do
        out=$(timeout 6 "${runner[@]}" "$flag" 2>&1 | tr -s '\r' '\n' | grep -m1 -v '^[[:space:]]*$' | cut -c1-64)
        [ -n "$out" ] && { printf '%s' "$out"; return 0; }
    done
    return 1
}

tool_name() {
    # tool_name "a|b" -> prints the first installed name, or nothing
    local name
    local -a names=()
    IFS='|' read -ra names <<<"$1"
    for name in "${names[@]}"; do
        if command -v "$name" >/dev/null 2>&1 || [ -x "$TH/.local/bin/$name" ]; then
            printf '%s' "$name"
            return 0
        fi
    done
    return 1
}

check_tool() {
    # check_tool <tool[|alias]> <group> <package> <required 1|0>
    local tool=$1 group=$2 pkg=$3 required=$4 out rc found
    if ! found=$(tool_name "$tool"); then
        if [ "$required" = 1 ]; then
            fail "$tool" "missing (package: $pkg)"
        else
            warn "$tool" "not installed (package: $pkg)"
        fi
        return
    fi
    out=$(probe "$found")
    rc=$?
    if [ $rc -eq 0 ]; then
        pass "$tool" "$out"
    elif [ $rc -eq 124 ]; then
        warn "$tool" "present but did not answer in 6s"
    else
        fail "$tool" "installed but does not run"
    fi
}

# ---------------------------------------------------------------------------
section "Kernel"
# ---------------------------------------------------------------------------
KREL="$(uname -r)"
KARCH="$(uname -m)"
pass "kernel" "$KREL ($KARCH)"

if [ -d "/usr/src/linux-headers-$KREL" ]; then
    pass "kernel headers" "/usr/src/linux-headers-$KREL"
else
    warn "kernel headers" "linux-headers-$KREL not installed (DKMS modules cannot build)"
fi

if command -v dkms >/dev/null 2>&1; then
    pass "dkms" "$(dkms --version 2>/dev/null | head -n1)"
else
    warn "dkms" "not installed"
fi

missing_fw=()
for fw in firmware-atheros firmware-realtek firmware-iwlwifi firmware-misc-nonfree wireless-regdb; do
    dpkg-query -W -f='${Status}' "$fw" 2>/dev/null | grep -q 'install ok installed' || missing_fw+=("$fw")
done
if [ ${#missing_fw[@]} -eq 0 ]; then
    pass "wireless firmware" "atheros, realtek, iwlwifi, misc, regdb"
else
    warn "wireless firmware" "missing: ${missing_fw[*]}"
fi

for mod in cfg80211 mac80211 nfc; do
    if modinfo -n "$mod" >/dev/null 2>&1; then
        if lsmod | awk '{print $1}' | grep -qx "$mod"; then
            pass "module $mod" "loaded"
        else
            warn "module $mod" "available, not loaded"
        fi
    else
        fail "module $mod" "not built for $KREL"
    fi
done

if systemctl is-active -q open-vm-tools 2>/dev/null; then
    pass "open-vm-tools" "active"
else
    warn "open-vm-tools" "service not active (expected only on VMware)"
fi

ROOT_FREE=$(df -Pm / | awk 'NR==2{print $4}')
if [ "${ROOT_FREE:-0}" -ge 4096 ]; then
    pass "disk space" "${ROOT_FREE}MB free on /"
else
    warn "disk space" "only ${ROOT_FREE}MB free on /"
fi

# ---------------------------------------------------------------------------
section "Services"
# ---------------------------------------------------------------------------
svc() {
    local name=$1 desc=$2
    if systemctl is-active -q "$name" 2>/dev/null; then
        pass "$desc" "$name active"
    elif systemctl is-enabled -q "$name" 2>/dev/null; then
        warn "$desc" "$name enabled but not running"
    else
        warn "$desc" "$name inactive"
    fi
}
svc pcscd.socket "PC/SC smart card daemon"
svc docker "Docker (MobSF)"
svc NetworkManager "NetworkManager"
svc ssh "SSH server"

if command -v opensc-tool >/dev/null 2>&1; then
    readers=$(timeout 5 opensc-tool --list-readers 2>/dev/null)
    rc=$?
    if [ "$rc" -eq 124 ]; then
        warn "smart card daemon" "pcscd not responding (journalctl -u pcscd; sudo systemctl restart pcscd)"
    elif [ "$(printf '%s\n' "$readers" | grep -c '^#')" -gt 0 ]; then
        pass "smart card reader" "$(printf '%s\n' "$readers" | grep -c '^#') reader(s)"
    else
        warn "smart card reader" "none attached"
    fi
fi

# ---------------------------------------------------------------------------
section "NETWORK ADAPTERS"
# ---------------------------------------------------------------------------
WIFI_IFACES=$(for d in /sys/class/net/*; do [ -e "$d/wireless" ] && basename "$d"; done)
if [ -z "$WIFI_IFACES" ]; then
    warn "wireless adapter" "none (VMware: VM > Removable Devices > connect the USB adapter)"
    WIFI_COUNT=0
else
    WIFI_COUNT=$(printf '%s\n' "$WIFI_IFACES" | wc -l)
    for ifc in $WIFI_IFACES; do
        phy=$(basename "$(readlink -f "/sys/class/net/$ifc/phy80211" 2>/dev/null)" 2>/dev/null)
        drv=$(basename "$(readlink -f "/sys/class/net/$ifc/device/driver" 2>/dev/null)" 2>/dev/null)
        if iw phy "$phy" info 2>/dev/null | grep -qi 'monitor'; then mon=monitor; else mon="no-monitor"; fi
        pass "wireless $ifc" "driver=${drv:-?} phy=${phy:-?} $mon"
    done
fi
if command -v rfkill >/dev/null 2>&1; then
    blocked=$(rfkill list wifi 2>/dev/null | grep -c 'blocked: yes' || true)
    [ "${blocked:-0}" -eq 0 ] && pass "rfkill" "wifi not blocked" || warn "rfkill" "$blocked blocked device(s)"
fi

NFC_DEV=""
if lsusb 2>/dev/null | grep -qiE 'pn53|0x072f|acr122|nfc'; then NFC_DEV=usb; fi
if [ -n "$NFC_DEV" ]; then pass "nfc device" "USB reader present"; else warn "nfc device" "none attached"; fi

# ---------------------------------------------------------------------------
section "TOOLCHAIN"
# ---------------------------------------------------------------------------
# tool:package:required
TOOLS=(
    "subfinder:kali-tools-web:1" "httpx|httpx-toolkit:kali-tools-web:1" "nuclei:kali-tools-web:1"
    "katana:kali-tools-web:1" "naabu:kali-tools-web:1" "dnsx:kali-tools-web:1"
    "ffuf:ffuf:1" "feroxbuster:feroxbuster:1" "nmap:nmap:1" "masscan:masscan:1"
    "whatweb:whatweb:1" "nikto:nikto:1" "wpscan:wpscan:1" "sqlmap:sqlmap:1"
    "dalfox:dalfox:1" "arjun:arjun:0" "gobuster:gobuster:0" "wafw00f:wafw00f:0"
    "amass:amass:0" "gowitness:gowitness:0" "theharvester|theHarvester:theharvester:0"
    "adb:adb:1" "apktool:apktool:1" "jadx:jadx:1" "d2j-dex2jar:dex2jar:1"
    "frida-ps:frida-tools:1" "objection:objection:1" "scrcpy:scrcpy:1"
    "netexec:netexec:1" "evil-winrm:evil-winrm:1" "responder:responder:1"
    "enum4linux-ng:enum4linux-ng:1" "bloodhound-python:bloodhound.py:1"
    "impacket-secretsdump:python3-impacket:1" "hashcat:hashcat:1" "john:john:1"
    "opensc-tool:opensc:1" "pcsc_scan:pcsc-tools:1" "nfc-list:libnfc-bin:0"
    "mfoc:mfoc:0" "hcxdumptool:hcxdumptool:1" "hcxpcapngtool:hcxtools:1"
    "aircrack-ng:aircrack-ng:1" "airmon-ng:aircrack-ng:1" "reaver:reaver:1"
    "bully:bully:0" "wifite:wifite:0" "iw:iw:1" "iwconfig:wireless-tools:1"
    "rfkill:rfkill:1" "tshark:tshark:0" "bettercap:bettercap:0" "kismet:kismet:0"
    "docker:docker.io:1" "git:git:1"
)
for entry in "${TOOLS[@]}"; do
    IFS=: read -r tool pkg required <<<"$entry"
    check_tool "$tool" "" "$pkg" "$required"
done

# ---------------------------------------------------------------------------
section "DATA AND INTEGRATION"
# ---------------------------------------------------------------------------
if [ -f /usr/share/wordlists/rockyou.txt ]; then
    pass "rockyou wordlist" "$(wc -l < /usr/share/wordlists/rockyou.txt) lines"
elif [ -f /usr/share/wordlists/rockyou.txt.gz ]; then
    warn "rockyou wordlist" "compressed; run bbt-os-doctor --fix"
else
    fail "rockyou wordlist" "missing (package: wordlists)"
fi
[ -d /usr/share/seclists ] && pass "seclists" "present" || warn "seclists" "missing"

for tdir in "$TH/.local/share/nuclei-templates" "/root/nuclei-templates" "/usr/share/nuclei-templates"; do
    if [ -d "$tdir" ]; then pass "nuclei templates" "$tdir"; TEMPLATES=1; break; fi
done
[ "${TEMPLATES:-0}" = 1 ] || warn "nuclei templates" "run: nuclei -update-templates"

if [ -x "$TH/tools/BugBountyToolkit/.venv-sys/bin/python" ]; then
    if as_target "$TH/tools/BugBountyToolkit/.venv-sys/bin/python" -c "import bbt" >/dev/null 2>&1; then
        pass "BBT toolkit" "$(as_target "$TH/tools/BugBountyToolkit/.venv-sys/bin/python" -c "import bbt;print(getattr(bbt,'__version__','?'))" 2>/dev/null)"
    else
        fail "BBT toolkit" "installed but does not import"
    fi
else
    warn "BBT toolkit" "not installed in $TH/tools"
fi

for helper in bbt-wifi bbt-workflow bbt-surface bbt-bounty bbt-ktune bbt-access bbt-android-recovery bbt-smartcard bbt-os-launcher; do
    if [ -x "/usr/local/bin/$helper" ] || [ -x "$TH/.local/bin/$helper" ]; then
        pass "$helper" "installed"
    else
        warn "$helper" "not installed"
    fi
done
if [ -x /usr/libexec/bbt-os/bbt-run ]; then
    pass "bbt-run" "root bridge installed"
else
    warn "bbt-run" "root bridge missing; privileged tools will ask for a password"
fi
[ -d /usr/share/bbt-os/icons ] && pass "BBT icon theme" "$(ls /usr/share/bbt-os/icons/*.svg 2>/dev/null | wc -l) icons" \
    || warn "BBT icon theme" "not installed"

if [ "$FIX" = 0 ]; then
if [ "$JSON" = 0 ] && [ "$QUIET" = 0 ]; then
    printf '\n%s  %s pass  %s warn  %s fail\n' "$(cyan SUMMARY)" \
        "$(green "$PASS")" "$(amber "$WARN")" "$(red "$FAIL")"
    if [ "$FAIL" -gt 0 ]; then
        printf 'failed: %s\n' "${FAILED[*]}"
        printf 'try: sudo bbt-os-doctor --fix\n'
    fi
fi

if [ "$SUMMARY" = 1 ]; then
    printf 'pass=%s warn=%s fail=%s wifi=%s kernel=%s\n' "$PASS" "$WARN" "$FAIL" "${WIFI_COUNT:-0}" "$KREL"
fi

if [ "$JSON" = 1 ]; then
    printf '{"version":"%s","kernel":"%s","pass":%s,"warn":%s,"fail":%s,"wifi":%s,"items":[' \
        "$VERSION" "$KREL" "$PASS" "$WARN" "$FAIL" "${WIFI_COUNT:-0}"
    sep=""
    for e in "${ENTRIES[@]}"; do printf '%s%s' "$sep" "$e"; sep=,; done
    printf ']}\n'
fi
fi

if [ "$FIX" = 1 ]; then
    section "FIX"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq || warn "apt update" "failed"
    fix_pkgs=()
    for entry in "${TOOLS[@]}"; do
        IFS=: read -r tool pkg required <<<"$entry"
        if [ "$required" = 1 ] && ! tool_name "$tool" >/dev/null; then
            case "$pkg" in
                kali-tools-web|docker.io) continue ;;
                frida-tools|objection) continue ;;  # pipx-managed below
            esac
            fix_pkgs+=("$pkg")
        fi
    done
    [ -d "/usr/src/linux-headers-$KREL" ] && fix_pkgs+=(dkms build-essential)
    if [ -f /usr/share/wordlists/rockyou.txt.gz ] && [ ! -f /usr/share/wordlists/rockyou.txt ]; then
        gunzip -k /usr/share/wordlists/rockyou.txt.gz && chmod 644 /usr/share/wordlists/rockyou.txt
        pass "rockyou" "extracted"
    fi
    if [ ${#fix_pkgs[@]} -gt 0 ]; then
        mapfile -t fix_pkgs < <(printf '%s\n' "${fix_pkgs[@]}" | sort -u)
        log_msg="installing: ${fix_pkgs[*]}"
        [ "$JSON" = 1 ] || printf '  %s\n' "$log_msg"
        apt-get install -y --no-install-recommends "${fix_pkgs[@]}" \
            && pass "apt install" "${fix_pkgs[*]}" \
            || warn "apt install" "some packages failed"
    else
        pass "apt install" "nothing missing"
    fi
    apt-get install -y --no-install-recommends "linux-headers-$KREL" >/dev/null 2>&1 \
        && pass "kernel headers" "installed" || warn "kernel headers" "not available for $KREL"
    for pipx_spec in "frida-tools:frida-ps" "objection:objection"; do
        pipx_pkg=${pipx_spec%%:*}
        pipx_bin=${pipx_spec##*:}
        command -v "$pipx_bin" >/dev/null 2>&1 && continue
        if as_target pipx install "$pipx_pkg" >/dev/null 2>&1; then
            pass "pipx $pipx_pkg" "installed"
        else
            warn "pipx $pipx_pkg" "could not install"
        fi
    done
    systemctl enable --now pcscd.socket >/dev/null 2>&1 || true
    systemctl enable --now docker >/dev/null 2>&1 || true
    if [ -x /usr/local/bin/bbt-os-doctor ]; then
        [ "$JSON" = 1 ] || printf '  rerun %s for the updated report\n' "$(cyan bbt-os-doctor)"
    fi
    args=()
    for a in "$@"; do
        [ "$a" = "--fix" ] || args+=("$a")
    done
    exec env BBT_DOCTOR_FIXED=1 bash "$0" "${args[@]}"
fi

[ "$FAIL" -gt 0 ] && exit 1
exit 0
