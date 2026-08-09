#!/usr/bin/env bash
#
# Open a single Windows application as a native window on this desktop.
#
#   ./rdp-app.sh 'C:\Program Files\...\EXCEL.EXE'
#
# This is RemoteApp: RDP streams one application's window rather than a whole
# Windows desktop, so the app gets its own taskbar entry and alt-tab slot and
# the VM stays invisible.
#
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/env.sh"

APP="${1:?usage: rdp-app.sh '<windows path to .exe>' [args...]}"
shift || true

[ -x "$FREERDP_BIN" ] || die "FreeRDP missing. Run ./install.sh"

# Window naming. Left alone, FreeRDP labels the window "RAIL:<something>"
# (RAIL = Remote Applications Integrated Locally, the RemoteApp protocol), which
# is what shows up in alt-tab. Two hints fix that:
#   name:       the application name carried over the RemoteApp channel
#   /wm-class:  the X11 WM_CLASS hint, which is what GNOME actually reads to
#               label and group a window
# APP_NAME defaults to the executable's basename; the launchers override it
# with something human-readable.
APP_BASE="$(basename "${APP//\\//}")"
APP_NAME="${APP_NAME:-${APP_BASE%.*}}"

# --- a document to open, if we were handed one ------------------------------
# The desktop entries pass %f, so double-clicking a spreadsheet arrives here as
# an ordinary Linux path. Windows sees your home directory as \\tsclient\linux,
# the same share lib/finish-setup.sh copies icons through, so the file needs
# translating rather than copying.
#
# Anything outside your home directory is genuinely not reachable from inside
# Windows, and a launch from a file manager has no terminal to print to, so say
# so on the desktop instead of failing silently.
refuse() {
    warn "$1"
    command -v notify-send >/dev/null 2>&1 &&
        notify-send -a "$APP_NAME" -i dialog-error -t 8000 "$APP_NAME" "$1" 2>/dev/null
    exit 1
}

DOC=""
if [ "${1:-}" ] && [ -e "$1" ]; then
    DOC="$(readlink -f "$1")"
    shift

    case "$DOC" in
        "$HOME"/*) ;;
        *) refuse "Only files in your home folder can be opened. Windows cannot see $DOC" ;;
    esac

    # /app: takes comma separated options, so a comma in the name would be read
    # as the start of another one. FreeRDP offers no escape for it.
    case "$DOC" in
        *,*) refuse "Rename the file without a comma. Remote Desktop cannot pass a name containing one" ;;
    esac

    WIN_DOC='\\tsclient\linux'"${DOC#"$HOME"}"
    WIN_DOC="${WIN_DOC//\//\\}"
fi

# Start the VM headless if it is not already running.
if ! pgrep -f 'qemu-system-x86_6[4]' >/dev/null 2>&1; then
    log "Starting Windows in the background - about a minute the first time"
    # Launched from the application menu there is no terminal to read, and a
    # cold start takes 40-60 seconds while Windows boots. Without this the
    # click appears to do nothing at all.
    if command -v notify-send >/dev/null 2>&1; then
        ICON="$PROJECT_DIR/icons/$(printf '%s' "$APP_NAME" | tr '[:upper:]' '[:lower:]').png"
        [ -f "$ICON" ] || ICON=applications-office
        notify-send -a "$APP_NAME" -i "$ICON" -t 8000 \
            "Starting $APP_NAME" "Waiting for Windows - this takes about a minute" 2>/dev/null || true
    fi
    "$PROJECT_DIR/vm.sh" headless >/dev/null 2>&1 &

    # Wait for Windows to actually accept a login, not merely for the port to
    # open: QEMU binds the forwarded port the moment it starts, long before
    # Windows has booted, so a port check returns immediately and the
    # connection below fails with nothing visible happening.
    for _ in $(seq 1 90); do
        timeout 8 "$FREERDP_BIN" /v:"127.0.0.1:$RDP_PORT" /u:"$RDP_USER" /d: \
            /p:"$(cat "$PASSWORD_FILE" 2>/dev/null)" /cert:ignore +auth-only \
            >/dev/null 2>&1 && break
        sleep 2
    done
fi

# All connection and performance flags live in env.sh so this script and
# desktop.sh cannot drift apart. /app:program: is what turns an RDP session
# into a single published window instead of a whole desktop.
# One FreeRDP client can end up drawing several Office windows, all sharing a
# single WM_CLASS, which leaves alt-tab showing one application's icon for all
# of them. This watcher corrects each window from its title, and exits with us.
"$PROJECT_DIR/lib/window-icons.sh" $$ >/dev/null 2>&1 &

# cmd: is the RemoteApp command line, so the document arrives as the argument
# Office would have received had it been started with the file on Windows.
#
# A name containing spaces has to reach Windows quoted or the application reads
# it as several arguments. FreeRDP's option parser does not really support
# quotes here and logs "Invalid quoted argument", but passes them through, and
# the file does open. Names without spaces need none of that, so they take the
# quiet path, which is nearly all of them.
APP_OPT="/app:program:$APP,name:$APP_NAME"
if [ -n "$DOC" ]; then
    case "$WIN_DOC" in
        *" "*) APP_OPT="$APP_OPT,cmd:\"$WIN_DOC\"" ;;
        *)     APP_OPT="$APP_OPT,cmd:$WIN_DOC" ;;
    esac
fi

rdp_run "$APP_OPT" /wm-class:"$APP_NAME" "$@"
