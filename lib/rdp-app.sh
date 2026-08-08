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
"$PROJECT_DIR/lib/fix-window-class.sh" $$ >/dev/null 2>&1 &

rdp_run /app:program:"$APP",name:"$APP_NAME" /wm-class:"$APP_NAME" "$@"
