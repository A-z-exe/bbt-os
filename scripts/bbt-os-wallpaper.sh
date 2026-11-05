#!/usr/bin/env bash
# Re-apply the BBT OS wallpaper to every XFCE monitor/workspace.
set -uo pipefail

WALLPAPER="${BBT_OS_WALLPAPER:-/usr/share/bbt-os/wallpaper.svg}"
[ -f "$WALLPAPER" ] || exit 0
command -v xfconf-query >/dev/null 2>&1 || exit 0

while IFS= read -r prop; do
    xfconf-query -c xfce4-desktop -p "$prop" -s "$WALLPAPER" >/dev/null 2>&1 || true
done < <(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep '/last-image$' || true)

while IFS= read -r prop; do
    xfconf-query -c xfce4-desktop -p "$prop" -s 5 >/dev/null 2>&1 || true
done < <(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep '/image-style$' || true)
