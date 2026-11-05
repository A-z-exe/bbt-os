#!/usr/bin/env bash
# Re-apply the BBT OS wallpaper to every XFCE monitor and workspace.
set -uo pipefail

if [ -n "${BBT_OS_WALLPAPER:-}" ]; then
    WALLPAPER="$BBT_OS_WALLPAPER"
elif [ -f /usr/share/bbt-os/wallpaper.png ]; then
    WALLPAPER=/usr/share/bbt-os/wallpaper.png
else
    WALLPAPER=/usr/share/bbt-os/wallpaper.svg
fi
[ -f "$WALLPAPER" ] || exit 0
command -v xfconf-query >/dev/null 2>&1 || exit 0

set_prop() {
    local prop=$1 type=$2 value=$3
    if xfconf-query -c xfce4-desktop -p "$prop" >/dev/null 2>&1; then
        xfconf-query -c xfce4-desktop -p "$prop" -s "$value" >/dev/null 2>&1 || true
    else
        xfconf-query -c xfce4-desktop -p "$prop" \
            -n -t "$type" -s "$value" >/dev/null 2>&1 || true
    fi
}

# Screens and the monitor keys XFCE currently knows about.
mapfile -t SCREENS < <(
    xfconf-query -c xfce4-desktop -l 2>/dev/null \
        | grep -oE '/backdrop/screen[0-9]+' | sort -u
)
[ ${#SCREENS[@]} -gt 0 ] || SCREENS=(/backdrop/screen0)

mapfile -t MONITORS < <(
    xfconf-query -c xfce4-desktop -l 2>/dev/null \
        | grep -oE '/backdrop/screen[0-9]+/monitor[^/]+' | sort -u
)

# XFCE 4.20 names monitor keys after the XRandR connector; older releases
# use monitor0..monitorN, so cover both.
if command -v xrandr >/dev/null 2>&1; then
    for screen in "${SCREENS[@]}"; do
        while read -r connector; do
            [ -n "$connector" ] || continue
            MONITORS+=("$screen/monitor$connector")
        done < <(xrandr --query 2>/dev/null | awk '/ connected/{print $1}')
    done
fi

mapfile -t MONITORS < <(printf '%s\n' "${MONITORS[@]}" | sort -u)

for base in "${MONITORS[@]}"; do
    set_prop "$base/image-path" string "$WALLPAPER"
    set_prop "$base/last-image" string "$WALLPAPER"
    set_prop "$base/last-single-image" string "$WALLPAPER"
    set_prop "$base/image-show" bool true
    set_prop "$base/image-style" int 5
    for ws in 0 1 2 3; do
        set_prop "$base/workspace$ws/last-image" string "$WALLPAPER"
        set_prop "$base/workspace$ws/image-path" string "$WALLPAPER"
    done
done

if command -v xfdesktop >/dev/null 2>&1; then
    xfdesktop --reload >/dev/null 2>&1 || true
fi
