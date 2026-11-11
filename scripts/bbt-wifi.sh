#!/usr/bin/env bash
# bbt-wifi - wireless reconnaissance and authorized WPA auditing.
#
#   bbt-wifi status                     adapters, drivers, monitor support
#   bbt-wifi scan [--iface IF] [--tsv]  nearby access points (root)
#   bbt-wifi plan --ssid S [--bssid B]  show the recommended tool chain
#   bbt-wifi attack --ssid S [options]  run the recommended attack
#   bbt-wifi crack --hash FILE          crack a captured .22000 hash
#   bbt-wifi captures [--open]          list previous runs
#   bbt-wifi doctor                     adapter and tool readiness
#
# Options for attack:
#   --bssid B --channel N --security WPA2|WPA3|WEP|OPEN --method auto|pmkid|
#   handshake|wps|wep --iface IF --timeout N --wordlist F --deauth --client C
#   --no-crack --dry-run --authorized
#
# Only test networks you own or have written permission to test. Deauth is
# opt-in, capped at 3 frames and scoped to the single BSSID you name.
set -uo pipefail

VERSION="$(cat /usr/share/bbt-os/VERSION 2>/dev/null || echo unknown)"

USER_HOME="${HOME:-/root}"
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
    USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
fi
BBT_DIR="${BBT_WIFI_DIR:-$USER_HOME/bbt/wifi}"
CACHE="$BBT_DIR/last-scan.tsv"
DEFAULT_WORDLIST="/usr/share/wordlists/rockyou.txt"
HASHCAT_RULES="/usr/share/hashcat/rules/best64.rule"

RED=$'\033[31m'; GREEN=$'\033[32m'; AMBER=$'\033[33m'; CYAN=$'\033[36m'; DIM=$'\033[2m'; OFF=$'\033[0m'
[ -t 1 ] || { RED=""; GREEN=""; AMBER=""; CYAN=""; DIM=""; OFF=""; }

info() { printf '%s[*]%s %s\n' "$GREEN" "$OFF" "$*"; }
warn() { printf '%s[!]%s %s\n' "$AMBER" "$OFF" "$*"; }
die()  { printf '%s[x]%s %s\n' "$RED" "$OFF" "$*" >&2; exit 1; }

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        exec sudo -E BBT_WIFI_DIR="$BBT_DIR" bash "$0" "$@"
    fi
}

is_wireless() { [ -e "/sys/class/net/$1/wireless" ]; }

default_iface() {
    local d
    for d in /sys/class/net/*; do
        if [ -e "$d/wireless" ]; then basename "$d"; return 0; fi
    done
    return 1
}

monitor_support() {
    local iface=$1 phy
    phy=$(basename "$(readlink -f "/sys/class/net/$iface/phy80211" 2>/dev/null)" 2>/dev/null)
    [ -n "$phy" ] || return 1
    iw phy "$phy" info 2>/dev/null | awk '
        /Supported interface modes/ {inmodes=1; next}
        inmodes && /Band [0-9]/ {inmodes=0}
        inmodes && /monitor/ {found=1}
        END {exit !found}'
}

driver_of() { basename "$(readlink -f "/sys/class/net/$1/device/driver" 2>/dev/null)" 2>/dev/null; }

band_of_freq() {
    local f=${1:-0}
    if [ "$f" -lt 3000 ]; then echo "2.4GHz"
    elif [ "$f" -lt 5925 ]; then echo "5GHz"
    else echo "6GHz"; fi
}

have() { command -v "$1" >/dev/null 2>&1; }

auth_gate() {
    [ "${AUTHORIZED:-0}" = 1 ] && return 0
    printf '%s[!]%s Only test networks you own or have written permission to test.\n' "$AMBER" "$OFF"
    printf '    Type AUTHORIZED to continue: '
    local answer
    read -r answer
    [ "$answer" = "AUTHORIZED" ] || die "aborted"
}

norm_bssid() {
    local b
    b=$(printf '%s' "$1" | tr 'A-F' 'a-f' | tr -d ':-')
    [ ${#b} -eq 12 ] || return 1
    printf '%s:%s:%s:%s:%s:%s' "${b:0:2}" "${b:2:2}" "${b:4:2}" "${b:6:2}" "${b:8:2}" "${b:10:2}"
}

slug() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-40; }

# ---------------------------------------------------------------------------
cmd_status() {
    printf '%sBBT OS wireless status%s  (kernel %s)\n\n' "$CYAN" "$OFF" "$(uname -r)"
    local found=0 iface phy drv bands mon state
    for iface in $(iw dev 2>/dev/null | awk '/Interface/{print $2}'); do
        is_wireless "$iface" || continue
        found=1
        phy=$(basename "$(readlink -f "/sys/class/net/$iface/phy80211" 2>/dev/null)" 2>/dev/null)
        drv=$(driver_of "$iface")
        bands=$(iw phy "$phy" info 2>/dev/null | grep -oE 'Band [0-9]:' | sort -u | tr '\n' ' ')
        if monitor_support "$iface"; then mon="${GREEN}yes$OFF"; else mon="${RED}no$OFF"; fi
        state=$(cat "/sys/class/net/$iface/operstate" 2>/dev/null || echo unknown)
        printf '  %-12s %-8s %-14s %-8s monitor=%s %s\n' \
            "$iface" "${phy:-?}" "${drv:-?}" "${bands:-?}" "$mon" "$state"
    done

    if [ "$found" = 0 ]; then
        warn "no wireless adapter visible"
        local hyper="" mods="" missing_mod=""
        local fw=""
        for d in ath9k_htc rtlwifi rtw88 rtw89 mt76 mediatek; do
            [ -e "/lib/firmware/$d" ] && fw="$fw $d"
        done
        compgen -G "/lib/firmware/iwlwifi-*" >/dev/null && fw="$fw iwlwifi"
        fw="${fw:-none found}"
        if systemd-detect-virt --quiet --vm 2>/dev/null; then
            hyper="virtual machine ($(systemd-detect-virt 2>/dev/null))"
        fi
        for m in cfg80211 mac80211; do
            if lsmod 2>/dev/null | grep -q "^$m "; then mods="$mods $m:loaded"
            elif modinfo "$m" >/dev/null 2>&1; then mods="$mods $m:available"
            else missing_mod="$missing_mod $m"; fi
        done
        printf '\n  host      %s\n' "${hyper:-bare metal}"
        printf '  modules  %s%s\n' "${mods# }" "${missing_mod:+  MISSING:$missing_mod}"
        printf '  firmware  %s\n\n' "$fw"
        if [ -n "$hyper" ]; then
            cat <<EOF
  A guest cannot create a wireless radio: the host card is not usable inside a
  VM. You need a USB Wi-Fi adapter (monitor mode + frame injection) and it must
  be attached to this guest.
    1. Plug in a supported USB adapter. Recommended chipsets:
         Atheros AR9271      (ath9k_htc, 2.4GHz, cheapest)
         MediaTek MT7612U    (mt76x2u, 2.4/5GHz, driver in-kernel)
         Realtek RTL8812AU   (rtl8812au-dkms, 2.4/5GHz)
         Realtek RTL8814AU   (4x4, needs DKMS)
       Do NOT use RTL8188EUS/RTL8192CU class dongles for injection.
    2. VMware Workstation: VM > Removable Devices > <adapter> > Connect
       (Disconnect from Host). VirtualBox: Devices > USB > <adapter>.
    3. If "Connect" is greyed out, power the VM off and add a USB 3.x
       (xHCI) controller in VM Settings > USB, then reboot the guest.
    4. In the guest, enable the stack:
         printf 'nfc\ncfg80211\nmac80211\n' | sudo tee /etc/modules-load.d/bbt-os.conf
         sudo modprobe cfg80211 mac80211 && sudo rfkill unblock wifi
    5. Verify:
         lsusb | grep -iE 'wireless|802.11|atheros|realtek|ralink|mediatek'
         iw dev ; ip -br link ; bbt-wifi status

  The built-in PCIe card (e.g. Intel AX201) cannot be passed through to VMware
  Workstation, so an internal radio will never appear here.
EOF
        else
            cat <<EOF

  Check that the adapter is plugged in, then:
    lsusb | grep -iE 'wireless|802.11|atheros|realtek|ralink|mediatek'
    dmesg | tail -20          # driver/firmware errors
    sudo rfkill unblock wifi && bbt-wifi status
EOF
        fi
        return 1
    fi

    printf '\n  tools  '
    for t in hcxdumptool hcxpcapngtool aircrack-ng reaver bully hashcat iw; do
        if have "$t"; then printf '%s%s%s ' "$GREEN" "$t" "$OFF"; else printf '%s%s%s ' "$RED" "$t" "$OFF"; fi
    done
    printf '\n  wordlist  %s\n' "$([ -f "$DEFAULT_WORDLIST" ] && echo "$DEFAULT_WORDLIST" || echo 'missing (bbt-os-doctor --fix)')"
}

# ---------------------------------------------------------------------------
cmd_scan() {
    local iface="" tsv=0
    local orig=("$@")
    while [ $# -gt 0 ]; do
        case "$1" in
            --iface) iface=$2; shift 2 ;;
            --iface=*) iface=${1#*=}; shift ;;
            --tsv) tsv=1; shift ;;
            *) die "unknown scan option: $1" ;;
        esac
    done
    need_root scan "${orig[@]}"
    [ -n "$iface" ] || iface=$(default_iface) || die "no wireless adapter; see bbt-wifi status"
    is_wireless "$iface" || die "$iface is not wireless"

    rfkill unblock wifi 2>/dev/null || true
    ip link set "$iface" up 2>/dev/null || true
    info "scanning on $iface (15s)"
    local raw
    raw=$(timeout 30 iw dev "$iface" scan 2>/dev/null) || die "scan failed on $iface"
    [ -n "$raw" ] || die "scan returned no data; interface busy?"

    mkdir -p "$BBT_DIR"
    printf '%s\n' "$raw" | awk -v OFS='\t' '
        function flush() {
            if (ssid == "" || bssid == "") return
            print bssid, ssid, ch, freq, band, sig, sec, wps
        }
        /^BSS / {
            flush()
            bssid = $2; sub(/\(.*/, "", bssid)
            ssid = ""; ch = "?"; freq = 0; band = "?"; sig = "?"; sec = "OPEN"; wps = 0
            next
        }
        /^[[:space:]]*freq:/ { freq = $2 + 0; band = (freq < 3000) ? "2.4GHz" : ((freq < 5925) ? "5GHz" : "6GHz") }
        /^[[:space:]]*signal:/ { sig = $2 }
        /^[[:space:]]*SSID:/ { sub(/^[[:space:]]*SSID:[[:space:]]*/, ""); ssid = $0 }
        /^[[:space:]]*DS Parameter set:/ { ch = $NF }
        /^[[:space:]]*RSN:/ { sec = "WPA2" }
        /^[[:space:]]*WPA:/ { sec = "WPA" }
        /^[[:space:]]*WPS:/ { wps = 1 }
        /SAE/ { if (sec == "WPA2" || sec == "WPA") sec = "WPA3" }
        /^[[:space:]]*Privacy:/ { if (sec == "OPEN") sec = "WEP" }
        END { flush() }
    ' >"$CACHE.raw"

    if [ ! -s "$CACHE.raw" ]; then
        rm -f "$CACHE.raw"; die "no access points found"
    fi
    sort -t$'\t' -k6,6nr "$CACHE.raw" >"$CACHE"
    rm -f "$CACHE.raw"

    if [ "$tsv" = 1 ]; then
        cat "$CACHE"
        return 0
    fi
    printf '%-32s %-18s %-3s %-6s %-6s %-6s %s\n' "SSID" "BSSID" "CH" "BAND" "SIGNAL" "SEC" "WPS"
    printf '%-32s %-18s %-3s %-6s %-6s %-6s %s\n' "--------------------------------" "------------------" "---" "------" "------" "------" "---"
    awk -F'\t' '{sig=$6+0; printf "%-32.32s %-18s %-3s %-6s %-4s dBm %-6s %s\n", $2, $1, $3, $5, sig, $7, ($8==1 ? "yes" : "-")}' "$CACHE"
    info "cached in $CACHE"
}

# ---------------------------------------------------------------------------
lookup_ap() {
    # lookup_ap <ssid> -> fills BSSID_FOUND, CHANNEL_FOUND, SECURITY_FOUND
    local ssid=$1
    [ -f "$CACHE" ] || return 1
    local row
    row=$(awk -F'\t' -v s="$ssid" '$2 == s {print; exit}' "$CACHE")
    [ -n "$row" ] || return 1
    BSSID_FOUND=$(printf '%s' "$row" | cut -f1)
    CHANNEL_FOUND=$(printf '%s' "$row" | cut -f3)
    FREQ_FOUND=$(printf '%s' "$row" | cut -f4)
    SECURITY_FOUND=$(printf '%s' "$row" | cut -f7)
    WPS_FOUND=$(printf '%s' "$row" | cut -f8)
    return 0
}

pick_method() {
    local sec=$1 wps=$2
    case "$sec" in
        OPEN) echo open; return ;;
        WEP) have aircrack-ng && { echo wep; return; }; echo "none"; return ;;
        WPA3)
            have hcxdumptool && { echo sae; return; }
            have aircrack-ng && { echo handshake; return; }
            echo none; return ;;
    esac
    if [ "$wps" = 1 ] && { have reaver || have bully; } && have airmon-ng; then
        echo wps; return
    fi
    if have hcxdumptool && have hcxpcapngtool; then echo pmkid; return; fi
    if have aircrack-ng; then echo handshake; return; fi
    echo none
}

tool_for_method() {
    case "$1" in
        pmkid|sae) echo hcxdumptool ;;
        handshake) echo aircrack-ng ;;
        wps) echo reaver/bully ;;
        wep) echo aircrack-ng ;;
        open) echo "none needed" ;;
        *) echo "-" ;;
    esac
}

# ---------------------------------------------------------------------------
cmd_plan() {
    local ssid="" bssid="" channel="" security="" iface="" method=auto
    while [ $# -gt 0 ]; do
        case "$1" in
            --ssid) ssid=$2; shift 2 ;;
            --bssid) bssid=$2; shift 2 ;;
            --channel) channel=$2; shift 2 ;;
            --security) security=$2; shift 2 ;;
            --iface) iface=$2; shift 2 ;;
            --method) method=$2; shift 2 ;;
            *) die "unknown plan option: $1" ;;
        esac
    done
    [ -n "$ssid" ] || die "--ssid is required"
    if [ -z "$bssid" ] && lookup_ap "$ssid"; then
        bssid=$BSSID_FOUND; channel=${channel:-$CHANNEL_FOUND}
        security=${security:-$SECURITY_FOUND}; wps=${WPS_FOUND:-0}
    fi
    [ -n "$security" ] || security=UNKNOWN
    [ -n "$bssid" ] || bssid="(scan required)"
    : "${channel:=auto}"
    : "${wps:=0}"
    [ -n "$iface" ] || iface=$(default_iface 2>/dev/null || echo "(none)")
    [ "$method" = auto ] && method=$(pick_method "$security" "$wps")
    local drv
    drv=$(driver_of "$iface" 2>/dev/null | head -n1)
    [ -n "$drv" ] || drv="?"

    printf 'target     %s\n' "$ssid"
    printf 'bssid      %s\n' "$bssid"
    printf 'channel    %s\n' "$channel"
    printf 'security   %s%s\n' "$security" "$([ "$wps" = 1 ] && echo ' + WPS' || true)"
    printf 'adapter    %s (%s)\n' "$iface" "$drv"
    printf 'method     %s -> %s\n' "$method" "$(tool_for_method "$method")"
    case "$method" in
        pmkid|sae)
            printf 'chain      hcxdumptool -> hcxpcapngtool -> hashcat -m 22000\n'
            printf 'note       SAE/PMKID capture is passive; a client association helps\n' ;;
        handshake)
            printf 'chain      airmon-ng -> airodump-ng -> aireplay-ng -> aircrack-ng\n'
            printf 'note       handshake needs a client reconnect; use --deauth explicitly\n' ;;
        wps)
            printf 'chain      airmon-ng -> reaver (PixieWPS) -> fallback bully\n'
            printf 'note       only against APs that advertise WPS\n' ;;
        wep)
            printf 'chain      airmon-ng -> airodump-ng -> aireplay-ng ARP replay -> aircrack-ng\n'
            printf 'note       needs ARP traffic on the network\n' ;;
        open)
            printf 'chain      none - the network is open, no key to recover\n' ;;
        *)
            printf 'chain      none - no compatible tool installed (run bbt-os-doctor --fix)\n' ;;
    esac
}

# ---------------------------------------------------------------------------
cmd_crack() {
    local hash="" wordlist="" runtime=1800 rules=$HASHCAT_RULES show=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --hash) hash=$2; shift 2 ;;
            --hash=*) hash=${1#*=}; shift ;;
            --wordlist) wordlist=$2; shift 2 ;;
            --wordlist=*) wordlist=${1#*=}; shift ;;
            --runtime) runtime=$2; shift 2 ;;
            --no-rules) rules=""; shift ;;
            --show) show=1; shift ;;
            -h|--help)
                printf 'usage: bbt-wifi crack --hash FILE [--wordlist FILE] [--runtime SECONDS]\n'
                printf '                       [--no-rules] [--show]\n'
                return 0 ;;
            *) die "unknown crack option: $1" ;;
        esac
    done
    [ -n "$hash" ] || die "--hash is required"
    [ -f "$hash" ] || die "hash file not found: $hash"
    have hashcat || die "hashcat is not installed"

    local pot="${hash%.*}.potfile"
    if [ "$show" = 1 ]; then
        hashcat -m 22000 --show --potfile-path "$pot" "$hash" 2>/dev/null | cut -d: -f2-
        return 0
    fi
    [ -n "$wordlist" ] || wordlist=$DEFAULT_WORDLIST
    [ -f "$wordlist" ] || die "wordlist not found: $wordlist (bbt-os-doctor --fix)"
    mkdir -p "$(dirname "$pot")"
    local -a cmd=(hashcat -m 22000 -a 0 "$hash" "$wordlist"
        --potfile-path "$pot" --runtime "$runtime" --status --status-timer 20 -w 3)
    [ -n "$rules" ] && [ -f "$rules" ] && cmd+=(-r "$rules")
    info "hashcat -m 22000 for ${runtime}s ($(basename "$wordlist"))"
    "${cmd[@]}" || true
    local found
    found=$(hashcat -m 22000 --show --potfile-path "$pot" "$hash" 2>/dev/null | cut -d: -f2-)
    if [ -n "$found" ]; then
        printf '%s[+] recovered:%s %s\n' "$GREEN" "$OFF" "$found"
    else
        warn "no key recovered within ${runtime}s; try rules, another wordlist or longer runtime"
    fi
}

# ---------------------------------------------------------------------------
disable_nm() {
    IFACE_MANAGED=0
    if have nmcli; then
        if nmcli -t -f GENERAL.STATE device show "$1" >/dev/null 2>&1; then
            nmcli device set "$1" managed no >/dev/null 2>&1 && IFACE_MANAGED=1
        fi
    fi
}

restore_iface() {
    local iface=${IFACE:-}
    [ -n "$iface" ] || return 0
    [ -n "${MON_IFACE:-}" ] && airmon-ng stop "$MON_IFACE" >/dev/null 2>&1 || true
    if [ -n "${AIRODUMP_PID:-}" ]; then kill "$AIRODUMP_PID" >/dev/null 2>&1 || true; fi
    ip link set "$iface" down 2>/dev/null || true
    iw dev "$iface" set type managed 2>/dev/null || true
    ip link set "$iface" up 2>/dev/null || true
    if [ "${IFACE_MANAGED:-0}" = 1 ]; then
        nmcli device set "$iface" managed yes >/dev/null 2>&1 || true
        nmcli device connect "$iface" >/dev/null 2>&1 || true
    fi
}

start_monitor() {
    local iface=$1
    local before after
    before=$(iw dev 2>/dev/null | awk '/Interface/{print $2}')
    airmon-ng start "$iface" >/dev/null 2>&1 || true
    after=$(iw dev 2>/dev/null | awk '/Interface/{print $2}')
    MON_IFACE=$(comm -13 <(printf '%s\n' "$before" | sort) <(printf '%s\n' "$after" | sort) | head -n1)
    [ -n "$MON_IFACE" ] || MON_IFACE="$iface"
    printf '%s' "$MON_IFACE"
}

hex_bssid() { printf '%s' "$1" | tr -d ':' | tr 'A-F' 'a-f'; }

hcx_is_v7() { hcxdumptool -h 2>&1 | grep -q -- '--bpfc'; }

capture_hcx() {
    local iface=$1 bssid=$2 timeout_s=$3 freq=$4 active=$5 out=$6 log=$7
    local minutes=$(( (timeout_s + 59) / 60 )) mode=passive
    if hcx_is_v7; then
        local -a args=(-i "$iface" -w "$out" --tot="$minutes" --exitoneapol=3)
        [ -n "$freq" ] && [ "$freq" != 0 ] && [ "$freq" != "?" ] && args+=(-f "$freq")
        if hcxdumptool --bpfc="wlan addr3 $(hex_bssid "$bssid")" >"$RUN/target.bpf" 2>/dev/null \
           && [ -s "$RUN/target.bpf" ]; then
            args+=(--bpf="$RUN/target.bpf")
        fi
        if [ "$active" = 1 ]; then
            args+=(--associationmax=100)
            mode=active
        else
            args+=(--associationmax=0 --proberesponsetx=0 --disable_disassociation)
            mode=passive
        fi
        info "hcxdumptool 7.x, BPF-scoped $mode capture (${minutes}m)"
        timeout "$((timeout_s + 90))" hcxdumptool "${args[@]}" >"$log" 2>&1 || true
    else
        printf '%s\n' "$(hex_bssid "$bssid")" >"$RUN/filter-ap.txt"
        info "hcxdumptool 6.x filterlist capture (${timeout_s}s)"
        timeout "$((timeout_s + 60))" hcxdumptool -i "$iface" -o "$out" \
            --filterlist_ap="$RUN/filter-ap.txt" --filtermode=2 \
            --tot="$timeout_s" --enable_status=1 >"$log" 2>&1 || true
    fi
}

convert_hashes() {
    local pcap=$1 out=$2
    have hcxpcapngtool || return 1
    hcxpcapngtool -o "$out" -E "$RUN/essids.txt" "$pcap" >"$RUN/hcxpcapngtool.log" 2>&1 || true
    [ -s "$out" ] || return 1
}

crack_hashes() {
    local hash=$1 wordlist=$2 runtime=$3
    have hashcat || { warn "hashcat missing"; return 1; }
    [ -f "$wordlist" ] || { warn "wordlist missing: $wordlist"; return 1; }
    local pot="$RUN/hashcat.potfile"
    info "hashcat -m 22000 (${runtime}s)"
    hashcat -m 22000 -a 0 "$hash" "$wordlist" --potfile-path "$pot" \
        --runtime "$runtime" --status --status-timer 20 -w 3 >"$RUN/hashcat.log" 2>&1 || true
    local found
    found=$(hashcat -m 22000 --show --potfile-path "$pot" "$hash" 2>/dev/null | cut -d: -f2-)
    if [ -z "$found" ] && [ -f "$HASHCAT_RULES" ]; then
        hashcat -m 22000 -a 0 "$hash" "$wordlist" -r "$HASHCAT_RULES" \
            --potfile-path "$pot" --runtime "$runtime" -w 3 >>"$RUN/hashcat.log" 2>&1 || true
        found=$(hashcat -m 22000 --show --potfile-path "$pot" "$hash" 2>/dev/null | cut -d: -f2-)
    fi
    printf '%s' "$found"
}

wps_attack() {
    local iface=$1 bssid=$2 channel=$3 timeout_s=$4
    local mon; mon=$(start_monitor "$iface"); MON_IFACE=$mon
    info "reaver PixieWPS on $mon ($bssid ch $channel)"
    timeout "$timeout_s" reaver -i "$mon" -b "$bssid" -c "$channel" -K 1 -vv -N \
        >"$RUN/reaver.log" 2>&1 || true
    local psk
    psk=$(awk -F"'" '/WPA PSK|WPS PIN/{print $2}' "$RUN/reaver.log" | tail -n1)
    if [ -z "$psk" ] && have bully; then
        info "trying bully"
        timeout "$timeout_s" bully -b "$bssid" -c "$channel" "$mon" -d >"$RUN/bully.log" 2>&1 || true
        psk=$(awk -F"'" '/key|PIN/{print $2}' "$RUN/bully.log" | tail -n1)
    fi
    [ -n "$psk" ] && printf '%s' "$psk"
}

wep_attack() {
    local iface=$1 bssid=$2 channel=$3 timeout_s=$4
    local mon; mon=$(start_monitor "$iface"); MON_IFACE=$mon
    local cap="$RUN/wep"
    info "airodump-ng on $mon, channel $channel"
    airodump-ng --ivs -w "$cap" --bssid "$bssid" -c "$channel" "$mon" >/dev/null 2>"$RUN/airodump.err" &
    AIRODUMP_PID=$!
    sleep 6
    info "aireplay-ng fake auth + ARP replay"
    aireplay-ng --fakeauth 0 -a "$bssid" "$mon" >"$RUN/aireplay.log" 2>&1 || true
    aireplay-ng --arpreplay -b "$bssid" "$mon" >>"$RUN/aireplay.log" 2>&1 &
    local replay_pid=$!
    sleep "$timeout_s"
    kill "$replay_pid" "$AIRODUMP_PID" >/dev/null 2>&1 || true
    wait "$AIRODUMP_PID" 2>/dev/null || true
    local capfile
    capfile=$(ls "$RUN"/wep-*.ivs 2>/dev/null | head -n1)
    if [ -z "$capfile" ]; then warn "no WEP capture produced"; return 1; fi
    aircrack-ng -b "$bssid" "$capfile" 2>&1 | tee "$RUN/aircrack.log" >/dev/null
    awk -F: '/KEY FOUND/{gsub(/ /,"",$2); print $2}' "$RUN/aircrack.log" | tail -n1
}

legacy_handshake() {
    local iface=$1 bssid=$2 channel=$3 timeout_s=$4 wordlist=$5 deauth=$6 client=$7
    local mon; mon=$(start_monitor "$iface"); MON_IFACE=$mon
    local cap="$RUN/handshake"
    info "airodump-ng on $mon ($bssid ch $channel)"
    airodump-ng -w "$cap" --bssid "$bssid" -c "$channel" "$mon" >/dev/null 2>"$RUN/airodump.err" &
    AIRODUMP_PID=$!
    sleep 5
    if [ "$deauth" = 1 ]; then
        info "scoped deauth burst (3 frames) to $bssid"
        if [ -n "$client" ]; then
            aireplay-ng --deauth 3 -a "$bssid" -c "$client" "$mon" >"$RUN/deauth.log" 2>&1 || true
        else
            aireplay-ng --deauth 3 -a "$bssid" "$mon" >"$RUN/deauth.log" 2>&1 || true
        fi
    fi
    local waited=0 capfile=""
    while [ "$waited" -lt "$timeout_s" ]; do
        capfile=$(ls "$RUN"/handshake-*.cap 2>/dev/null | head -n1)
        if [ -n "$capfile" ] && aircrack-ng "$capfile" 2>/dev/null | grep -q '1 handshake'; then break; fi
        sleep 5; waited=$((waited + 5))
    done
    kill "$AIRODUMP_PID" >/dev/null 2>&1 || true
    AIRODUMP_PID=""
    wait 2>/dev/null || true
    capfile=$(ls "$RUN"/handshake-*.cap 2>/dev/null | head -n1)
    [ -n "$capfile" ] || { warn "no capture file"; return 1; }
    if [ "$wordlist" = /dev/null ]; then
        info "capture-only run; keeping $capfile for later cracking"
        return 1
    fi
    info "aircrack-ng against $(basename "$capfile")"
    aircrack-ng -w "$wordlist" -b "$bssid" "$capfile" 2>&1 | tee "$RUN/aircrack.log" >/dev/null
    awk -F: '/KEY FOUND/{gsub(/ /,"",$2); print $2}' "$RUN/aircrack.log" | tail -n1
}

# ---------------------------------------------------------------------------
cmd_attack() {
    local ssid="" bssid="" channel="" security="" iface="" method=auto timeout_s=180
    local wordlist="" deauth=0 client="" no_crack=0 dry=0 crack_time=1800 freq=""
    local authorized=0
    local orig=("$@")
    while [ $# -gt 0 ]; do
        case "$1" in
            --ssid) ssid=$2; shift 2 ;;
            --ssid=*) ssid=${1#*=}; shift ;;
            --bssid) bssid=$2; shift 2 ;;
            --bssid=*) bssid=${1#*=}; shift ;;
            --channel) channel=$2; shift 2 ;;
            --channel=*) channel=${1#*=}; shift ;;
            --security) security=$2; shift 2 ;;
            --security=*) security=${1#*=}; shift ;;
            --iface) iface=$2; shift 2 ;;
            --iface=*) iface=${1#*=}; shift ;;
            --method) method=$2; shift 2 ;;
            --method=*) method=${1#*=}; shift ;;
            --timeout) timeout_s=$2; shift 2 ;;
            --timeout=*) timeout_s=${1#*=}; shift ;;
            --wordlist) wordlist=$2; shift 2 ;;
            --wordlist=*) wordlist=${1#*=}; shift ;;
            --crack-time) crack_time=$2; shift 2 ;;
            --crack-time=*) crack_time=${1#*=}; shift ;;
            --client) client=$2; shift 2 ;;
            --client=*) client=${1#*=}; shift ;;
            --deauth) deauth=1; shift ;;
            --no-crack) no_crack=1; shift ;;
            --dry-run) dry=1; shift ;;
            --authorized) authorized=1; shift ;;
            *) die "unknown attack option: $1" ;;
        esac
    done

    [ -n "$ssid" ] || die "--ssid is required (the network name you own or may test)"
    [ "$(printf '%s' "$ssid" | wc -c)" -le 32 ] || die "SSID longer than 32 bytes"
    printf '%s' "$ssid" | LC_ALL=C grep -q '[[:cntrl:]]' && die "SSID contains control characters"
    case "$ssid" in *'*'*|*'?'*) die "wildcards are not allowed; name one network" ;; esac
    [[ "$timeout_s" =~ ^[0-9]+$ ]] && [ "$timeout_s" -ge 30 ] && [ "$timeout_s" -le 3600 ] \
        || die "--timeout must be 30..3600 seconds"

    [ -n "$iface" ] || iface=$(default_iface)
    if [ -n "$iface" ]; then
        is_wireless "$iface" || die "$iface is not a wireless interface"
        monitor_support "$iface" || die "$iface does not support monitor mode; use a supported adapter"
    elif [ "$dry" = 1 ]; then
        warn "no wireless adapter visible; dry run plans without hardware"
        iface="(none)"
    else
        die "no wireless adapter; see bbt-wifi status"
    fi
    IFACE=$iface

    if [ -z "$bssid" ]; then
        lookup_ap "$ssid" || die "SSID '$ssid' is not in the last scan; run bbt-wifi scan first"
        bssid=$BSSID_FOUND
        channel=${channel:-$CHANNEL_FOUND}
        freq=$FREQ_FOUND
        security=${security:-$SECURITY_FOUND}
        wps=${WPS_FOUND:-0}
    fi
    bssid=$(norm_bssid "$bssid") || die "invalid --bssid"
    : "${wps:=0}"

    if [ -f "$CACHE" ] && { [ -z "$security" ] || [ -z "$freq" ]; }; then
        security=${security:-$(awk -F'\t' -v b="$bssid" '$1 == b {print $7; exit}' "$CACHE")}
        wps=$(awk -F'\t' -v b="$bssid" '$1 == b {print $8; exit}' "$CACHE")
        freq=$(awk -F'\t' -v b="$bssid" '$1 == b {print $4; exit}' "$CACHE")
    fi
    : "${security:=WPA2}"
    [ -n "$channel" ] || channel=auto

    [ "$method" = auto ] && method=$(pick_method "$security" "${wps:-0}")
    if [ "$dry" = 1 ]; then
        cmd_plan --ssid "$ssid" --bssid "$bssid" --channel "$channel" \
            --security "$security" --iface "$iface" --method "$method"
        [ "$method" = none ] && return 2
        return 0
    fi
    [ "$method" = none ] && die "no compatible tool installed (run bbt-os-doctor --fix)"
    [ "$method" = open ] && { info "'$ssid' is open - there is no key to recover"; return 0; }

    AUTHORIZED=$authorized auth_gate
    need_root attack "${orig[@]}"

    [ -n "$wordlist" ] || wordlist=$DEFAULT_WORDLIST
    if [ "$method" != wps ] && [ "$method" != wep ] && [ "$no_crack" = 0 ]; then
        [ -f "$wordlist" ] || warn "wordlist not found ($wordlist); capture only"
    fi

    RUN="$BBT_DIR/$(slug "$ssid")-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$RUN"
    ln -sfn "$RUN" "$BBT_DIR/latest"
    trap restore_iface EXIT INT TERM
    exec > >(tee -a "$RUN/run.log") 2>&1
    info "run directory: $RUN"
    info "target $ssid ($bssid) ch $channel $security, method $method"

    local psk="" hashfile="$RUN/hashes.22000" use_hcx=0
    case "$method" in
        pmkid|sae) use_hcx=1 ;;
        handshake) have aircrack-ng || use_hcx=1 ;;
    esac
    case "$method" in
        pmkid|sae|handshake)
            if [ "$use_hcx" = 1 ] && have hcxdumptool && have hcxpcapngtool; then
                disable_nm "$iface"
                ip link set "$iface" down 2>/dev/null || true
                capture_hcx "$iface" "$bssid" "$timeout_s" "$freq" "$deauth" \
                    "$RUN/capture.pcapng" "$RUN/hcxdumptool.log"
                if convert_hashes "$RUN/capture.pcapng" "$hashfile"; then
                    local count; count=$(grep -c 'WPA\*' "$hashfile" 2>/dev/null || echo 0)
                    info "captured $count hash line(s)"
                else
                    warn "no PMKID/handshake in the capture"
                fi
                ip link set "$iface" up 2>/dev/null || true
                if [ -s "$hashfile" ] && [ "$no_crack" = 0 ]; then
                    psk=$(crack_hashes "$hashfile" "$wordlist" "$crack_time")
                fi
            else
                [ "$channel" = auto ] && die "handshake mode needs --channel (or run bbt-wifi scan)"
                if [ "$no_crack" = 0 ]; then
                    psk=$(legacy_handshake "$iface" "$bssid" "$channel" "$timeout_s" "$wordlist" "$deauth" "$client")
                else
                    legacy_handshake "$iface" "$bssid" "$channel" "$timeout_s" "/dev/null" "$deauth" "$client" >/dev/null || true
                fi
            fi
            ;;
        wps)
            [ "$channel" = auto ] && die "WPS mode needs --channel (or run bbt-wifi scan)"
            psk=$(wps_attack "$iface" "$bssid" "$channel" "$timeout_s") ;;
        wep)
            [ "$channel" = auto ] && die "WEP mode needs --channel (or run bbt-wifi scan)"
            psk=$(wep_attack "$iface" "$bssid" "$channel" "$timeout_s") ;;
    esac

    local clients=""
    clients=$(awk -F, '/Station MAC/{f=1; next} f && NF {gsub(/^ +| +$/, "", $1); if ($1 != "") print $1}' "$RUN"/handshake-*.csv 2>/dev/null | tr '\n' ' ')
    {
        printf '# Wi-Fi audit: %s\n\n' "$ssid"
        printf '- BSSID: `%s`\n- Channel: %s\n- Security: %s\n' "$bssid" "$channel" "$security"
        printf '- Adapter: `%s` (%s)\n- Method: %s (%s)\n' "$iface" "$(driver_of "$iface")" "$method" "$(tool_for_method "$method")"
        printf '- Started: %s\n- Capture: `%s`\n' "$(date -Is)" "${hashfile#$RUN/}"
        printf '- Clients seen: %s\n' "${clients:-none}"
        if [ -n "$psk" ]; then printf '\n**Key recovered:** `%s`\n' "$psk"; else printf '\n**Result:** no key recovered in this run.\n'; fi
        printf '\n## Files\n\n'
        ls -1 "$RUN" | sed 's/^/- /'
    } >"$RUN/summary.md"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -Is)" "$ssid" "$bssid" "$method" "${psk:-none}" "$RUN" >>"$BBT_DIR/history.tsv"
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
        chown -R "$SUDO_USER":"$(id -gn "$SUDO_USER" 2>/dev/null || echo "$SUDO_USER")" "$RUN" 2>/dev/null || true
    fi

    if [ -n "$psk" ]; then
        printf '\n%s[+] KEY RECOVERED:%s %s\n' "$GREEN" "$OFF" "$psk"
    else
        printf '\n%s[!]%s nothing recovered. Logs: %s\n' "$AMBER" "$OFF" "$RUN"
    fi
    restore_iface
}

# ---------------------------------------------------------------------------
cmd_captures() {
    mkdir -p "$BBT_DIR"
    local open=0 arg
    for arg in "$@"; do [ "$arg" = "--open" ] && open=1; done
    if [ ! -s "$BBT_DIR/history.tsv" ]; then
        printf 'no runs yet. start with: bbt-wifi scan && bbt-wifi attack --ssid <name>\n'
        return 0
    fi
    printf '%-20s %-28s %-18s %-10s %s\n' "TIME" "SSID" "BSSID" "METHOD" "KEY"
    awk -F'\t' '{printf "%-20s %-28.28s %-18s %-10s %s\n", $1, $2, $3, $4, $5}' "$BBT_DIR/history.tsv" | tail -n 20
    if [ "$open" = 1 ]; then
        xdg-open "$BBT_DIR" >/dev/null 2>&1 || true
    fi
}

cmd_doctor() {
    cmd_status; local rc=$?
    printf '
'
    local t
    for t in iw ip aircrack-ng aireplay-ng hcxdumptool hcxpcapngtool hashcat reaver bully; do
        if have "$t"; then info "$t present"; else warn "$t missing (sudo bbt-os-doctor --fix)"; fi
    done
    if [ -f "$DEFAULT_WORDLIST" ]; then
        info "wordlist $(basename "$DEFAULT_WORDLIST") ($(du -h "$DEFAULT_WORDLIST" 2>/dev/null | cut -f1))"
    else
        warn "rockyou.txt missing: sudo bbt-os-doctor --fix"
    fi
    if [ -f "$HASHCAT_RULES" ]; then
        info "hashcat rules best64 present"
    else
        warn "hashcat best64 rules missing"
    fi
    return $rc
}

usage() {
    sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
}

main() {
    local cmd=${1:-status}
    [ $# -gt 0 ] && shift
    case "$cmd" in
        status) cmd_status ;;
        scan) cmd_scan "$@" ;;
        plan) cmd_plan "$@" ;;
        attack) cmd_attack "$@" ;;
        crack) cmd_crack "$@" ;;
        captures) cmd_captures "$@" ;;
        doctor) cmd_doctor ;;
        --version|-V) echo "bbt-wifi $VERSION" ;;
        -h|--help|help) usage ;;
        *) usage; exit 2 ;;
    esac
}

main "$@"
