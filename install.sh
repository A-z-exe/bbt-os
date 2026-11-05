#!/usr/bin/env bash
# BBT OS installer entry point. Usage: sudo bash install.sh [options]
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
    echo "[*] root is required; re-running with sudo"
    exec sudo -E bash "$HERE/provision.sh" "$@"
fi
exec bash "$HERE/provision.sh" "$@"
