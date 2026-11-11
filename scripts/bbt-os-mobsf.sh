#!/usr/bin/env bash
# Start, stop or inspect the MobSF container used by BBT OS.
set -uo pipefail

IMAGE="opensecurity/mobile-security-framework-mobsf:latest"
NAME="bbt-mobsf"
PORT="${MOBSF_PORT:-8000}"

if ! command -v docker >/dev/null 2>&1; then
    echo "docker is not installed; run: sudo bbt-os-refresh" >&2
    exit 1
fi

DOCKER=(docker)
if ! docker info >/dev/null 2>&1; then
    DOCKER=(sudo docker)
fi

case "${1:-start}" in
    start)
        if "${DOCKER[@]}" ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$NAME"; then
            "${DOCKER[@]}" start "$NAME" >/dev/null || exit 1
        else
            "${DOCKER[@]}" run -d --name "$NAME" -p "127.0.0.1:$PORT:8000" "$IMAGE" >/dev/null || {
                echo "could not start MobSF; pull the image with:" >&2
                echo "  sudo docker pull $IMAGE" >&2
                exit 1
            }
        fi
        echo "MobSF is running: http://127.0.0.1:$PORT"
        ;;
    stop)
        "${DOCKER[@]}" stop "$NAME" >/dev/null && echo "MobSF stopped"
        ;;
    status)
        "${DOCKER[@]}" ps -a --filter "name=^/$NAME\$"
        ;;
    logs)
        exec "${DOCKER[@]}" logs -f "$NAME"
        ;;
    *)
        echo "usage: mobsf {start|stop|status|logs}" >&2
        exit 2
        ;;
esac
