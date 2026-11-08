#!/usr/bin/env bash
# bbt-access - authenticated web terminal reachable from any device.
#
#   bbt-access start [--public] [--lan]  start the terminal and print the link
#   bbt-access stop                      stop everything
#   bbt-access status                    running state, link and expiry
#   bbt-access link                      print the link and credentials again
#   bbt-access install                   fetch ttyd and cloudflared binaries
#
# Options:
#   --public          open a public https tunnel (link usable anywhere)
#   --provider P      tunnel provider: auto (default), serveo, localhost.run,
#                     cloudflare
#   --lan             bind 0.0.0.0 and print the local network address
#   --port N          local port (default 7681)
#   --expire MIN      auto-stop after MIN minutes (default 120, 0 = never)
#   --read-only       viewers cannot type commands
#   --shell PATH      login shell for the session (default bash -l)
#   --user NAME       login name for the web terminal (default $USER)
#   --password PASS   use a given password instead of the stored one
#   --reset-password  generate a new password
#   --authorized      skip the public-exposure confirmation
#
# The link is protected with HTTP Basic auth over TLS. Anyone who has both the
# link and the password gets a shell on this machine, so treat them as secrets.
set -uo pipefail

SELF=$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")
VERSION="$(cat /usr/share/bbt-os/VERSION 2>/dev/null || echo unknown)"
BIN_DIR="${BBT_ACCESS_BIN:-$HOME/.local/bin}"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bbt"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/bbt-access"
CREDS="$CONF_DIR/access.env"
TTYD="$BIN_DIR/ttyd"
CLOUDFLARED="$BIN_DIR/cloudflared"
TTYD_VERSION="1.7.7"
PORT=7681
EXPIRE=120
PUBLIC=0
LAN=0
PROVIDER="auto"
READONLY=0
AUTHORIZED=0
RESET_PASS=0
ACCESS_USER="${USER:-bbt}"
PASSWORD=""
SHELL_CMD="bash -l"

RED=$'\033[31m'; GREEN=$'\033[32m'; AMBER=$'\033[33m'; CYAN=$'\033[36m'; DIM=$'\033[2m'; OFF=$'\033[0m'
[ -t 1 ] || { RED=""; GREEN=""; AMBER=""; CYAN=""; DIM=""; OFF=""; }

info() { printf '%s[*]%s %s\n' "$GREEN" "$OFF" "$*"; }
warn() { printf '%s[!]%s %s\n' "$AMBER" "$OFF" "$*"; }
die()  { printf '%s[x]%s %s\n' "$RED" "$OFF" "$*" >&2; exit 1; }

usage() { sed -n '2,30p' "$SELF" | sed 's/^# \{0,1\}//'; }

have() { command -v "$1" >/dev/null 2>&1; }

port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null && exec 3<&- 3>&-; }

rand_pass() {
    local p=""
    while [ ${#p} -lt 20 ]; do
        p="$p$(tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 20)"
    done
    printf '%s' "${p:0:20}"
}

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64) printf 'x86_64' ;;
        aarch64|arm64) printf 'aarch64' ;;
        *) die "unsupported architecture: $(uname -m)" ;;
    esac
}

download() {
    local url=$1 out=$2
    if have curl; then
        curl -fsSL --retry 2 --connect-timeout 10 -o "$out.part" "$url" || { rm -f "$out.part"; return 1; }
    elif have wget; then
        wget -q -O "$out.part" "$url" || { rm -f "$out.part"; return 1; }
    else
        die "curl or wget is required to fetch the binaries"
    fi
    chmod 755 "$out.part" && mv -f "$out.part" "$out"
}

cmd_install() {
    mkdir -p "$BIN_DIR" "$CONF_DIR" "$STATE_DIR"
    chmod 700 "$CONF_DIR" "$STATE_DIR"
    local arch url
    arch=$(detect_arch)

    if [ -x "$TTYD" ] && "$TTYD" --version >/dev/null 2>&1; then
        info "ttyd present: $("$TTYD" --version)"
    else
        case "$arch" in
            x86_64) url="https://github.com/tsl0922/ttyd/releases/download/$TTYD_VERSION/ttyd.x86_64" ;;
            aarch64) url="https://github.com/tsl0922/ttyd/releases/download/$TTYD_VERSION/ttyd.aarch64" ;;
        esac
        info "fetching ttyd $TTYD_VERSION"
        download "$url" "$TTYD" || die "ttyd download failed; check the network"
        "$TTYD" --version >/dev/null 2>&1 || die "downloaded ttyd does not run"
    fi

    if [ -x "$CLOUDFLARED" ] && "$CLOUDFLARED" --version >/dev/null 2>&1; then
        info "cloudflared present: $("$CLOUDFLARED" --version 2>&1 | head -n1)"
    else
        case "$arch" in
            x86_64) url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" ;;
            aarch64) url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64" ;;
        esac
        info "fetching cloudflared"
        download "$url" "$CLOUDFLARED" || die "cloudflared download failed; check the network"
        "$CLOUDFLARED" --version >/dev/null 2>&1 || die "downloaded cloudflared does not run"
    fi
    info "binaries ready in $BIN_DIR"
}

load_creds() {
    mkdir -p "$CONF_DIR" "$STATE_DIR"
    chmod 700 "$CONF_DIR" "$STATE_DIR"
    local stored_pass="" stored_user=""
    if [ -f "$CREDS" ]; then
        # shellcheck disable=SC1090
        . "$CREDS"
        stored_user="${BBT_ACCESS_USER:-}"
        stored_pass="${BBT_ACCESS_PASS:-}"
        [ -n "$stored_user" ] && [ "$ACCESS_USER" = "${USER:-bbt}" ] && ACCESS_USER="$stored_user"
        [ -z "$PASSWORD" ] && PASSWORD="$stored_pass"
    fi
    if [ -z "$PASSWORD" ] || [ "$RESET_PASS" = 1 ]; then
        PASSWORD=$(rand_pass)
        info "new password generated in $CREDS"
    fi
    [ -n "$PASSWORD" ] || die "could not load or generate a password"
    if [ "$stored_pass" != "$PASSWORD" ] || [ "$stored_user" != "$ACCESS_USER" ]; then
        umask 077
        printf 'BBT_ACCESS_USER=%s\nBBT_ACCESS_PASS=%s\n' "$ACCESS_USER" "$PASSWORD" >"$CREDS"
        chmod 600 "$CREDS"
    fi
}

kill_pidfile() {
    local f=$1 pid
    [ -f "$f" ] || return 0
    pid=$(cat "$f" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        local i=0
        while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 20 ]; do sleep 0.1; i=$((i+1)); done
        kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$f"
}

cmd_stop() {
    kill_pidfile "$STATE_DIR/tunnel.pid"
    kill_pidfile "$STATE_DIR/cloudflared.pid"
    kill_pidfile "$STATE_DIR/ttyd.pid"
    kill_pidfile "$STATE_DIR/timer.pid"
    rm -f "$STATE_DIR/url" "$STATE_DIR/started" "$STATE_DIR/expire" "$STATE_DIR/provider" "$STATE_DIR/port"
    info "access stopped"
}

lan_ip() {
    ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}'
}

wait_for_url() {
    local log=$1 pattern=$2 exclude=${3:-'^$'} i=0 url
    while [ "$i" -lt 30 ]; do
        sleep 1
        url=$(grep -oE "$pattern" "$log" 2>/dev/null | grep -vE "$exclude" | head -n1)
        if [ -n "$url" ]; then printf '%s' "$url"; return 0; fi
        i=$((i+1))
    done
    return 1
}

start_serveo() {
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    : >"$STATE_DIR/tunnel.log"
    setsid nohup ssh -o StrictHostKeyChecking=accept-new \
        -o UserKnownHostsFile="$HOME/.ssh/known_hosts" \
        -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
        -o ExitOnForwardFailure=yes -o ConnectTimeout=10 \
        -R 80:127.0.0.1:"$PORT" serveo.net \
        </dev/null >>"$STATE_DIR/tunnel.log" 2>&1 &
    printf '%s\n' "$!" >"$STATE_DIR/tunnel.pid"
    wait_for_url "$STATE_DIR/tunnel.log" 'https://[a-z0-9.-]+\.(serveousercontent\.com|serveo\.net)'
}

start_lhr() {
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    : >"$STATE_DIR/tunnel.log"
    setsid nohup ssh -tt -o StrictHostKeyChecking=accept-new \
        -o UserKnownHostsFile="$HOME/.ssh/known_hosts" \
        -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
        -o ExitOnForwardFailure=yes -o ConnectTimeout=10 \
        -R 80:127.0.0.1:"$PORT" nokey@localhost.run \
        </dev/null >>"$STATE_DIR/tunnel.log" 2>&1 &
    printf '%s\n' "$!" >"$STATE_DIR/tunnel.pid"
    wait_for_url "$STATE_DIR/tunnel.log" 'https://[a-z0-9]+\.lhr\.life'
}

start_cloudflare() {
    [ -x "$CLOUDFLARED" ] || cmd_install
    : >"$STATE_DIR/tunnel.log"
    setsid nohup "$CLOUDFLARED" tunnel --no-autoupdate --url "http://127.0.0.1:$PORT" \
        >>"$STATE_DIR/tunnel.log" 2>&1 &
    printf '%s\n' "$!" >"$STATE_DIR/tunnel.pid"
    wait_for_url "$STATE_DIR/tunnel.log" 'https://[a-z0-9-]+\.trycloudflare\.com' '^https://api\.'
}

public_gate() {
    [ "$AUTHORIZED" = 1 ] && return 0
    printf '%s[!]%s This opens a shell on this machine to the internet.\n' "$AMBER" "$OFF"
    printf '    The link is protected by a random password, but anyone with both\n'
    printf '    gets full access. Keep it private. Type PUBLIC to continue: '
    local answer
    read -r answer
    [ "$answer" = "PUBLIC" ] || die "aborted"
}

cmd_start() {
    [ -x "$TTYD" ] || cmd_install
    load_creds

    cmd_stop >/dev/null 2>&1 || true
    port_open "$PORT" && die "port $PORT is already in use; pick another with --port"

    local bind="127.0.0.1"
    [ "$LAN" = 1 ] && bind="0.0.0.0"

    local args=(-p "$PORT" -i "$bind" -c "$ACCESS_USER:$PASSWORD" -t "titleFixed=BBT Access")
    [ "$READONLY" = 0 ] && args+=(-W)

    # shellcheck disable=SC2086
    setsid nohup "$TTYD" "${args[@]}" $SHELL_CMD >"$STATE_DIR/ttyd.log" 2>&1 &
    local ttyd_pid=$!
    printf '%s\n' "$ttyd_pid" >"$STATE_DIR/ttyd.pid"

    local i=0
    while ! port_open "$PORT" && [ "$i" -lt 30 ]; do sleep 0.2; i=$((i+1)); done
    if ! kill -0 "$ttyd_pid" 2>/dev/null || ! port_open "$PORT"; then
        rm -f "$STATE_DIR/ttyd.pid"
        die "ttyd failed to start; see $STATE_DIR/ttyd.log"
    fi

    local link="http://127.0.0.1:$PORT"
    local provider="" pub=""
    if [ "$PUBLIC" = 1 ]; then
        public_gate
        local order
        case "$PROVIDER" in
            auto) order="serveo localhost.run cloudflare" ;;
            serveo|localhost.run|cloudflare) order=$PROVIDER ;;
            *) die "unknown provider: $PROVIDER (use auto, serveo, localhost.run or cloudflare)" ;;
        esac
        for p in $order; do
            info "opening the $p tunnel"
            case "$p" in
                serveo) pub=$(start_serveo) ;;
                localhost.run) pub=$(start_lhr) ;;
                cloudflare) pub=$(start_cloudflare) ;;
            esac
            if [ -n "$pub" ]; then provider=$p; break; fi
            warn "$p tunnel did not come up"
            kill_pidfile "$STATE_DIR/tunnel.pid"
        done
        if [ -z "$pub" ]; then
            tail -n 4 "$STATE_DIR/tunnel.log" >&2 2>/dev/null || true
            cmd_stop >/dev/null 2>&1 || true
            die "no public tunnel available; check the network or use --lan"
        fi
        link=$pub
        printf '%s\n' "$link" >"$STATE_DIR/url"
        printf '%s\n' "$provider" >"$STATE_DIR/provider"
        chmod 600 "$STATE_DIR/url" "$STATE_DIR/provider"
    elif [ "$LAN" = 1 ]; then
        link="http://$(lan_ip):$PORT"
    fi

    date +%s >"$STATE_DIR/started"
    printf '%s\n' "$PORT" >"$STATE_DIR/port"
    if [ "$EXPIRE" -gt 0 ] 2>/dev/null; then
        date -d "+$EXPIRE minutes" +%s >"$STATE_DIR/expire"
        setsid nohup bash -c "sleep $((EXPIRE*60)); '$SELF' stop" >/dev/null 2>&1 &
        printf '%s\n' "$!" >"$STATE_DIR/timer.pid"
    else
        rm -f "$STATE_DIR/expire"
    fi

    printf '\n%sBBT Access is up%s\n\n' "$CYAN" "$OFF"
    printf '  link      %s\n' "$link"
    printf '  user      %s\n' "$ACCESS_USER"
    printf '  password  %s\n' "$PASSWORD"
    [ "$provider" = serveo ] && printf '  note      click "Continue to Site" once (Serveo free tunnel)\n'
    [ "$READONLY" = 1 ] && printf '  mode      read-only\n'
    if [ "$EXPIRE" -gt 0 ] 2>/dev/null; then
        printf '  expires    %s (%s min)\n' "$(date -d "+$EXPIRE minutes" '+%Y-%m-%d %H:%M')" "$EXPIRE"
    fi
    printf '\n  Open the link on any device, sign in, and use it as a terminal.\n'
    printf '  On a phone: browser menu -> "Add to Home Screen" to keep it app-like.\n'
    printf '  Stop with:  %s stop\n\n' "$SELF"
    if have qrencode; then
        printf '%s' "$link" | qrencode -t ANSIUTF8 2>/dev/null | sed 's/^/  /'
    fi
}

cmd_status() {
    local running=0
    if [ -f "$STATE_DIR/ttyd.pid" ] && kill -0 "$(cat "$STATE_DIR/ttyd.pid" 2>/dev/null)" 2>/dev/null; then
        running=1
    fi
    if [ "$running" = 0 ]; then
        printf 'BBT Access: %sstopped%s\n' "$DIM" "$OFF"
        return 1
    fi
    printf 'BBT Access: %srunning%s (pid %s, port %s)\n' "$GREEN" "$OFF" \
        "$(cat "$STATE_DIR/ttyd.pid")" "$(cat "$STATE_DIR/port" 2>/dev/null || echo "$PORT")"
    [ -f "$STATE_DIR/url" ] && printf '  link      %s\n' "$(cat "$STATE_DIR/url")"
    [ -f "$STATE_DIR/provider" ] && printf '  via       %s\n' "$(cat "$STATE_DIR/provider")"
    printf '  user      %s\n' "$ACCESS_USER"
    printf '  password  stored in %s\n' "$CREDS"
    if [ -f "$STATE_DIR/expire" ]; then
        local left=$(( $(cat "$STATE_DIR/expire") - $(date +%s) ))
        [ "$left" -gt 0 ] && printf '  expires   in %d min\n' $((left/60)) || printf '  expires   now\n'
    fi
}

cmd_link() {
    cmd_status || die "nothing is running; start with: $SELF start --public"
    [ -f "$STATE_DIR/url" ] || die "no public link; start with --public"
    printf '\n%s\n' "$(cat "$STATE_DIR/url")"
    . "$CREDS" 2>/dev/null || true
    printf 'user: %s\npassword: %s\n' "${BBT_ACCESS_USER:-$ACCESS_USER}" "${BBT_ACCESS_PASS:-?}"
}

# --- parse options ---------------------------------------------------------
ACTION=""
while [ $# -gt 0 ]; do
    case "$1" in
        start|stop|status|link|install|help|-h|--help) ACTION=$1; shift ;;
        --public) PUBLIC=1; shift ;;
        --provider) PROVIDER=$2; shift 2 ;;
        --provider=*) PROVIDER=${1#*=}; shift ;;
        --lan) LAN=1; shift ;;
        --port) PORT=$2; shift 2 ;;
        --port=*) PORT=${1#*=}; shift ;;
        --expire) EXPIRE=$2; shift 2 ;;
        --expire=*) EXPIRE=${1#*=}; shift ;;
        --read-only) READONLY=1; shift ;;
        --shell) SHELL_CMD=$2; shift 2 ;;
        --shell=*) SHELL_CMD=${1#*=}; shift ;;
        --user) ACCESS_USER=$2; shift 2 ;;
        --user=*) ACCESS_USER=${1#*=}; shift ;;
        --password) PASSWORD=$2; shift 2 ;;
        --password=*) PASSWORD=${1#*=}; shift ;;
        --reset-password) RESET_PASS=1; shift ;;
        --authorized) AUTHORIZED=1; shift ;;
        *) die "unknown option: $1" ;;
    esac
done

case "$ACTION" in
    start) cmd_start ;;
    stop) cmd_stop ;;
    status) cmd_status ;;
    link) cmd_link ;;
    install) cmd_install ;;
    ""|help|-h|--help) usage ;;
esac
