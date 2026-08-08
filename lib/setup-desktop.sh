#!/usr/bin/env bash
#
# Add Excel and PowerPoint to your application menu.
#
#   ./setup-desktop.sh            create the entries
#   ./setup-desktop.sh --remove   take them away again
#
# These are the only files this project writes outside its own folder: two
# small .desktop files in ~/.local/share/applications, which is the only place
# a Linux desktop looks for application entries. --remove deletes them.
#
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/env.sh"

APPS_DIR="${APPS_DIR:-$HOME/.local/share/applications}"
QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

if [ "${1:-}" = "--remove" ]; then
    rm -f "$APPS_DIR"/m365-*.desktop
    command -v update-desktop-database >/dev/null && update-desktop-database "$APPS_DIR" 2>/dev/null || true
    log "Removed the application menu entries"
    exit 0
fi

mkdir -p "$APPS_DIR"

# StartupWMClass is the important line: it matches a running window back to
# this entry, which is what makes the real Office icon appear in alt-tab and
# the dash rather than a generic placeholder. It must match the /wm-class
# passed to FreeRDP, which rdp-app.sh sets from APP_NAME.
write_entry() {
    local id="$1" name="$2" comment="$3" keywords="$4"
    local icon="$PROJECT_DIR/icons/${id}.png"
    # Fall back to a stock icon until the real one has been extracted.
    [ -f "$icon" ] || icon="x-office-${5:-document}"

    cat > "$APPS_DIR/m365-${id}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$name
Comment=$comment
Exec=$PROJECT_DIR/${id}.sh %f
Icon=$icon
Terminal=false
Categories=Office;
Keywords=$keywords
StartupWMClass=$name
EOF
}

write_entry powerpoint PowerPoint "Presentations (Windows VM)" "presentation;slides;office;microsoft;" presentation
write_entry excel      Excel      "Spreadsheets (Windows VM)"  "spreadsheet;office;microsoft;"          spreadsheet

command -v update-desktop-database >/dev/null && update-desktop-database "$APPS_DIR" 2>/dev/null || true

if [ "$QUIET" -eq 0 ]; then
    log "Added Excel and PowerPoint to your application menu"
    [ -f "$PROJECT_DIR/icons/powerpoint.png" ] \
        || warn "Using placeholder icons - run ./finish-setup.sh once Office is installed to get the real ones"
fi
