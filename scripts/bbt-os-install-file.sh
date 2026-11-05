#!/usr/bin/env bash
# BBT OS double-click installer.
#
# Handles .deb, .AppImage, .run and .sh files opened from the file manager.
# Every action needs an explicit confirmation; .deb installation runs through
# apt in a terminal so the sudo password prompt and package output stay visible.
#
# Usage: bbt-os-install-file [--dry-run] <file>
set -uo pipefail

SELF="BBT OS installer"
FILE=""
DRY_RUN=0

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --help|-h)
            printf 'Usage: bbt-os-install-file [--dry-run] <file>\n'
            printf 'Supported: .deb  .AppImage  .run  .sh\n'
            exit 0
            ;;
        *) FILE="$arg" ;;
    esac
done

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
    printf 'BBT OS installer: file not found: %s\n' "${FILE:-<none>}" >&2
    exit 1
fi
FILE="$(cd "$(dirname "$FILE")" && pwd)/$(basename "$FILE")"
name="${FILE##*/}"

gui=0
if [ -n "${DISPLAY:-}" ] && [ -z "${BBT_OS_NO_GUI:-}" ] && command -v zenity >/dev/null 2>&1; then
    gui=1
fi

markup() {
    printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

notify() {
    if [ "$gui" = 1 ]; then
        zenity --info --title="$SELF" --width=480 --text="$(markup "$1")" 2>/dev/null || true
    else
        printf '%s\n' "$1"
    fi
}

fail() {
    if [ "$gui" = 1 ]; then
        zenity --error --title="$SELF" --width=480 --text="$(markup "$1")" 2>/dev/null || true
    else
        printf 'ERROR: %s\n' "$1" >&2
    fi
    exit 1
}

ask() {
    if [ "$gui" = 1 ]; then
        zenity --question --title="$SELF" --width=480 \
            --ok-label="Continue" --cancel-label="Cancel" \
            --text="$(markup "$1")" 2>/dev/null
    else
        printf '%s [y/N] ' "$1"
        read -r answer || return 1
        case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
    fi
}

# Run a command in a visible terminal and keep the window open with the result.
run_in_terminal() {
    local title="$1" command="$2" runner
    runner=$(mktemp "${TMPDIR:-/tmp}/bbt-os-run-XXXXXX.sh") || fail "cannot create a temporary runner"
    {
        printf '#!/usr/bin/env bash\n'
        printf 'set -uo pipefail\n'
        printf 'trap '\''rm -f -- "$0"'\'' EXIT\n'
        printf 'clear 2>/dev/null || true\n'
        printf 'echo %q\n' "$title"
        printf 'echo\n'
        printf '%s\n' "$command"
        printf 'rc=$?\n'
        printf 'echo\n'
        printf 'if [ "$rc" -eq 0 ]; then echo "Done."; else echo "Failed (exit $rc)."; fi\n'
        printf 'read -rp "Press Enter to close..." _\n'
    } >"$runner"
    chmod 700 "$runner"

    if command -v x-terminal-emulator >/dev/null 2>&1; then
        x-terminal-emulator -e "$runner" >/dev/null 2>&1 &
    elif command -v qterminal >/dev/null 2>&1; then
        qterminal -e "$runner" >/dev/null 2>&1 &
    elif command -v xfce4-terminal >/dev/null 2>&1; then
        xfce4-terminal -x "$runner" >/dev/null 2>&1 &
    elif command -v xterm >/dev/null 2>&1; then
        xterm -e "$runner" >/dev/null 2>&1 &
    else
        fail "No terminal emulator found. Install qterminal or xterm."
    fi
}

lower="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
case "$lower" in
    *.deb) kind=deb ;;
    *.appimage) kind=appimage ;;
    *.run) kind=run ;;
    *.sh) kind=sh ;;
    *)
        mime="$(file -b --mime-type -- "$FILE" 2>/dev/null || true)"
        case "$mime" in
            application/x-executable|application/x-pie-executable) kind=run ;;
            *) fail "Unknown installer type: $name\nSupported: .deb, .AppImage, .run, .sh" ;;
        esac
        ;;
esac

if [ "$DRY_RUN" = 1 ]; then
    printf 'file: %s\ntype: %s\n' "$FILE" "$kind"
    case "$kind" in
        deb) printf 'command: sudo apt-get install -y -- %q\n' "$FILE" ;;
        appimage) printf 'action: copy to ~/Applications, create wrapper and menu entry\n' ;;
        run) printf 'command: %q (in a terminal)\n' "$FILE" ;;
        sh) printf 'command: bash %q (in a terminal)\n' "$FILE" ;;
    esac
    exit 0
fi

case "$kind" in
    deb)
        dpkg-deb --info "$FILE" >/dev/null 2>&1 \
            || fail "$name is not a valid Debian package."
        ask "Install this Debian package?

$name

The administrator password will be requested in a terminal." || exit 0
        deb_cmd="$(printf 'sudo apt-get install -y -- %q' "$FILE")"
        run_in_terminal "BBT OS installer: $name" "$deb_cmd"
        ;;

    appimage)
        head -c 4 -- "$FILE" | grep -q $'\x7fELF' \
            || fail "$name does not look like an AppImage (missing ELF header)."
        dest="$HOME/Applications/$name"
        if [ -e "$dest" ]; then
            ask "An AppImage with this name already exists:

$dest

Replace it?" || exit 0
        fi
        ask "Install this AppImage into your applications folder?

$name

It will be copied to ~/Applications and added to the menu." || exit 0

        mkdir -p "$HOME/Applications" "$HOME/.local/bin" "$HOME/.local/share/applications"
        cp -f -- "$FILE" "$dest" || fail "Could not copy the AppImage."
        chmod +x -- "$dest"

        slug="$(printf '%s' "${name%.*}" | sed 's/[^A-Za-z0-9._-]/-/g')"
        wrapper="$HOME/.local/bin/bbt-os-$slug"
        {
            printf '#!/usr/bin/env bash\n'
            printf '# Generated by BBT OS installer.\n'
            printf 'APPIMAGE_EXTRACT_AND_RUN=1 exec %q "$@"\n' "$dest"
        } >"$wrapper"
        chmod 700 "$wrapper"

        {
            printf '[Desktop Entry]\n'
            printf 'Type=Application\n'
            printf 'Name=%s\n' "${name%.*}"
            printf 'Comment=Installed by BBT OS installer\n'
            printf 'Exec=%s %%U\n' "$wrapper"
            printf 'Icon=application-x-executable\n'
            printf 'Terminal=false\n'
            printf 'Categories=Utility;\n'
        } >"$HOME/.local/share/applications/bbt-os-$slug.desktop"

        update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
        notify "Installed $name

Location: $dest
Menu entry: bbt-os-$slug
The wrapper uses extract-and-run, so it works without libfuse2."
        ;;

    run|sh)
        chmod +x -- "$FILE" 2>/dev/null || true
        ask "Run this installer script?

$name

Only continue if you trust this file. It runs as your user in a terminal; if it needs root, it will ask for the password itself." || exit 0
        if [ "$kind" = sh ]; then
            script_cmd="bash $(printf '%q' "$FILE")"
        else
            script_cmd="$(printf '%q' "$FILE")"
        fi
        run_in_terminal "BBT OS installer: $name" "$script_cmd"
        ;;
esac
