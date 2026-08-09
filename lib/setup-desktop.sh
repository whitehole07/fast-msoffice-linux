#!/usr/bin/env bash
#
# Add Excel and PowerPoint to your application menu.
#
#   ./setup-desktop.sh            create the entries
#   ./setup-desktop.sh --remove   take them away again
#
# These are the only things this project writes outside its own folder, and
# --remove deletes all of them:
#   ~/.local/share/applications        two small .desktop files, the only place
#                                      a Linux desktop looks for menu entries
#   ~/.local/share/icons/hicolor/...   symlinks pointing back at icons/ here, so
#                                      spreadsheets and decks get the Office
#                                      icon in the file manager
#
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/env.sh"

APPS_DIR="${APPS_DIR:-$HOME/.local/share/applications}"
ICON_THEME_DIR="${ICON_THEME_DIR:-$HOME/.local/share/icons/hicolor}"
MIME_ICON_DIR="$ICON_THEME_DIR/256x256/mimetypes"
QUIET=0
if [ "${1:-}" = "--quiet" ]; then QUIET=1; fi

refresh_caches() {
    command -v update-desktop-database >/dev/null && update-desktop-database "$APPS_DIR" 2>/dev/null || true
    command -v gtk-update-icon-cache >/dev/null &&
        gtk-update-icon-cache -qtf "$ICON_THEME_DIR" 2>/dev/null || true
}

if [ "${1:-}" = "--remove" ]; then
    rm -f "$APPS_DIR"/m365-*.desktop
    # Only ours: symlinks in that directory that point back into this project.
    # Anything else there belongs to some other application.
    [ -d "$MIME_ICON_DIR" ] &&
        find "$MIME_ICON_DIR" -maxdepth 1 -type l -lname "$PROJECT_DIR/*" -delete 2>/dev/null || true
    refresh_caches
    log "Removed the application menu entries and file icons"
    exit 0
fi

mkdir -p "$APPS_DIR"

# StartupWMClass ties a running window back to this entry, which is what puts a
# real icon on it in alt-tab and the overview. It matches the /wm-class that
# rdp-app.sh passes to FreeRDP.
#
# Known limitation: Windows allows one RDP session per user, so opening a second
# Office app takes over the first one's session and one FreeRDP client ends up
# drawing every window with a single WM_CLASS. With both apps open they
# therefore share an icon, whichever connected last. Dropping StartupWMClass
# does not help; the switcher then shows no icon at all, because it needs an
# application match to have an icon to show.
#
# MimeType is what puts the app in the file manager's "Open With" list. It only
# offers it: which application actually opens a double click is decided by
# mimeapps.list, so adding these takes nothing away from LibreOffice unless you
# choose it yourself. Only the Office formats are claimed, deliberately not
# text/csv, which belongs to whatever you already edit text with.
write_entry() {
    local id="$1" name="$2" comment="$3" keywords="$4" mime="$6"
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
# Tells the desktop a launch is under way, so the dash shows a spinner while
# the VM boots instead of the click appearing to do nothing.
StartupNotify=true
Categories=Office;
Keywords=$keywords
StartupWMClass=$name
MimeType=$mime
EOF
}

XL='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;'
XL+='application/vnd.openxmlformats-officedocument.spreadsheetml.template;'
XL+='application/vnd.ms-excel;'
XL+='application/vnd.ms-excel.sheet.macroEnabled.12;'
XL+='application/vnd.ms-excel.template.macroEnabled.12;'
XL+='application/vnd.ms-excel.sheet.binary.macroEnabled.12;'

PP='application/vnd.openxmlformats-officedocument.presentationml.presentation;'
PP+='application/vnd.openxmlformats-officedocument.presentationml.slideshow;'
PP+='application/vnd.openxmlformats-officedocument.presentationml.template;'
PP+='application/vnd.ms-powerpoint;'
PP+='application/vnd.ms-powerpoint.presentation.macroEnabled.12;'
PP+='application/vnd.ms-powerpoint.slideshow.macroEnabled.12;'

# Making an app the default for a file type decides what opens it, not what it
# looks like: a file manager takes a document's icon from its MIME type through
# the icon theme, so .pptx keeps the generic office icon whatever owns it.
#
# The theme looks for an icon named after the MIME type with the slash turned
# into a dash, so linking the real Office icons under those names is all it
# takes. They are symlinks, not copies, so the only real files still live in
# this project folder. 256x256 is the size the icons were extracted at.
#
# A thumbnailer, if one is installed for Office formats, produces slide
# previews and those take precedence over any of this.
link_mime_icons() {
    local id="$1" mimes="$2"
    local src="$PROJECT_DIR/icons/${id}.png"
    # Placeholder icons are stock theme names, not files, and nothing to link.
    [ -f "$src" ] || return 0
    mkdir -p "$MIME_ICON_DIR"
    local mime
    while IFS= read -r mime; do
        [ -n "$mime" ] || continue
        ln -sfn "$src" "$MIME_ICON_DIR/${mime//\//-}.png"
    done < <(printf '%s' "$mimes" | tr ';' '\n')
}

write_entry powerpoint PowerPoint "Presentations (Windows VM)" "presentation;slides;office;microsoft;" presentation "$PP"
write_entry excel      Excel      "Spreadsheets (Windows VM)"  "spreadsheet;office;microsoft;"          spreadsheet "$XL"

link_mime_icons powerpoint "$PP"
link_mime_icons excel      "$XL"

refresh_caches

if [ "$QUIET" -eq 0 ]; then
    log "Added Excel and PowerPoint to your application menu"
    [ -f "$PROJECT_DIR/icons/powerpoint.png" ] \
        || warn "Using placeholder icons - run ./finish-setup.sh once Office is installed to get the real ones"
fi
