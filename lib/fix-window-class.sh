#!/usr/bin/env bash
#
# Give each RemoteApp window a WM_CLASS matching the application it really is.
#
#   ./lib/fix-window-class.sh [pid-to-follow]
#
# Windows allows one RDP session per user, so opening a second Office app takes
# over the first one's session and a single FreeRDP client ends up drawing every
# window. FreeRDP can only stamp one WM_CLASS on all of them, so alt-tab and the
# overview show whichever application connected last for every window.
#
# The window titles are still correct, so this watches for RemoteApp windows and
# rewrites the class from the title. Runs alongside a session and exits when the
# process it was given goes away.
#
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/env.sh"

FOLLOW="${1:-}"
XDOTOOL="$OPT_DIR/usr/bin/xdotool"

# Nothing to do if the tools are missing; the session still works, the icons are
# just wrong, so this must never be fatal.
command -v xprop >/dev/null 2>&1 || exit 0
[ -x "$XDOTOOL" ] || exit 0

app_from_title() {
    case "$1" in
        *PowerPoint*) echo PowerPoint ;;
        *Excel*)      echo Excel ;;
        *Word*)       echo Word ;;
        *Outlook*)    echo Outlook ;;
        *OneNote*)    echo OneNote ;;
        *)            echo "" ;;
    esac
}

while :; do
    [ -z "$FOLLOW" ] || kill -0 "$FOLLOW" 2>/dev/null || break

    for w in $(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -oE '0x[0-9a-f]+'); do
        cls=$(xprop -id "$w" WM_CLASS 2>/dev/null) || continue
        # Only touch RemoteApp windows. FreeRDP marks them with a RAIL instance.
        case "$cls" in *RAIL*) ;; *) continue ;; esac

        title=$(xprop -id "$w" _NET_WM_NAME 2>/dev/null | sed 's/.*= "//; s/"$//')
        app=$(app_from_title "$title")
        [ -n "$app" ] || continue

        "$XDOTOOL" set_window --class "$app" --classname "$app" "$w" 2>/dev/null || true
    done

    sleep 1
done
