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
#   ~/.local/share/icons/<theme>/...   symlinks pointing back at icons/ here, so
#                                      spreadsheets and decks get the Office
#                                      icon in the file manager
#
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/env.sh"

APPS_DIR="${APPS_DIR:-$HOME/.local/share/applications}"
ICONS_ROOT="${ICONS_ROOT:-$HOME/.local/share/icons}"
QUIET=0
if [ "${1:-}" = "--quiet" ]; then QUIET=1; fi

# Which icon theme is actually in use. An icon has to be installed into that
# theme to be seen: a file type asks for a specific name first and a generic one
# second, and the desktop searches the whole active theme before falling back to
# hicolor. Adwaita answers the generic name, so an icon left only in hicolor
# never gets reached. Change your icon theme and this needs running again.
current_icon_theme() {
    local t=""
    command -v gsettings >/dev/null 2>&1 &&
        t=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")
    printf '%s' "${t:-hicolor}"
}

# A theme only searches the directories its index.theme lists, so pick one of
# those rather than inventing a path. Scalable holds any size; failing that,
# take the largest pixel directory the theme declares.
theme_mimetype_dir() {
    local theme="$1" index="" base dirs d
    for base in "$ICONS_ROOT" /usr/share/icons /usr/local/share/icons; do
        [ -f "$base/$theme/index.theme" ] && { index="$base/$theme/index.theme"; break; }
    done
    [ -n "$index" ] || { printf '256x256/mimetypes'; return; }

    dirs=$(grep -m1 '^Directories=' "$index" | sed 's/^Directories=//' \
           | tr ',' '\n' | grep '/mimetypes$' || true)
    d=$(printf '%s\n' "$dirs" | grep '^scalable/' | head -1 || true)
    [ -n "$d" ] || d=$(printf '%s\n' "$dirs" | grep -E '^[0-9]+x' | sort -t x -k1 -n | tail -1 || true)
    printf '%s' "${d:-256x256/mimetypes}"
}

THEME="$(current_icon_theme)"
ICON_DIRS=("$ICONS_ROOT/hicolor/256x256/mimetypes")
[ "$THEME" = "hicolor" ] || ICON_DIRS+=("$ICONS_ROOT/$THEME/$(theme_mimetype_dir "$THEME")")

refresh_caches() {
    command -v update-desktop-database >/dev/null && update-desktop-database "$APPS_DIR" 2>/dev/null || true
    if command -v gtk-update-icon-cache >/dev/null; then
        local d
        for d in "$ICONS_ROOT/hicolor" "$ICONS_ROOT/$THEME"; do
            [ -d "$d" ] && gtk-update-icon-cache -qtf "$d" 2>/dev/null || true
        done
    fi
}

if [ "${1:-}" = "--remove" ]; then
    rm -f "$APPS_DIR"/m365-*.desktop
    # Only ours: symlinks anywhere under the icon directory that point back into
    # this project. Anything else there belongs to another application, and
    # searching the whole tree also catches icons left in a theme you have since
    # stopped using.
    [ -d "$ICONS_ROOT" ] &&
        find "$ICONS_ROOT" -type l -lname "$PROJECT_DIR/*" -delete 2>/dev/null || true
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
# this project folder.
#
# They go into both the active theme and hicolor: the active theme is what
# actually gets read, hicolor is there for whatever you switch to next.
#
# A thumbnailer, if one is installed for Office formats, produces previews and
# those take precedence over any icon, so this shows up mostly on the formats
# it does not handle.
#
# An icon is only claimed for a type this app actually opens. Putting the Excel
# logo on a file that LibreOffice is going to open would be a plain lie about
# what a double click does. Set the default in your file manager and run this
# again to pick the icons up.
CLAIMED=0
SKIPPED=0

# Read the choice you actually made, which the desktop records under
# [Default Applications] in mimeapps.list.
#
# Deliberately not `xdg-mime query default`: that answers with the effective
# default, and with no choice recorded it falls back to whichever application
# claims the type first. Since these entries claim the Office formats, it
# reports them as the default for files nobody has chosen them for, which is
# the confusion this whole check exists to avoid.
is_default_for() {
    local mime="$1" want="m365-$2.desktop" got=""
    got=$(awk -F= -v m="$mime" '
        /^\[Default Applications\]/ {f=1; next}
        /^\[/                       {f=0}
        f && $1 == m                {print $2; exit}
    ' "${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list" 2>/dev/null || true)

    # The value can be a list of fallbacks, so match a whole entry in it.
    case ";${got//[[:space:]]/};" in *";$want;"*) return 0 ;; esac
    return 1
}

link_mime_icons() {
    local id="$1" mimes="$2"
    local src="$PROJECT_DIR/icons/${id}.png"
    # Placeholder icons are stock theme names, not files, and nothing to link.
    [ -f "$src" ] || return 0
    local dir mime
    while IFS= read -r mime; do
        [ -n "$mime" ] || continue
        if ! is_default_for "$mime" "$id"; then
            SKIPPED=$((SKIPPED + 1))
            continue
        fi
        for dir in "${ICON_DIRS[@]}"; do
            mkdir -p "$dir"
            ln -sfn "$src" "$dir/${mime//\//-}.png"
        done
        CLAIMED=$((CLAIMED + 1))
    done < <(printf '%s' "$mimes" | tr ';' '\n')
}

write_entry powerpoint PowerPoint "Presentations (Windows VM)" "presentation;slides;office;microsoft;" presentation "$PP"
write_entry excel      Excel      "Spreadsheets (Windows VM)"  "spreadsheet;office;microsoft;"          spreadsheet "$XL"

# Start from nothing so a type you have since handed back to another
# application loses its icon here too.
[ -d "$ICONS_ROOT" ] &&
    find "$ICONS_ROOT" -type l -lname "$PROJECT_DIR/*" -delete 2>/dev/null || true

link_mime_icons powerpoint "$PP"
link_mime_icons excel      "$XL"

refresh_caches

if [ "$QUIET" -eq 0 ]; then
    log "Added Excel and PowerPoint to your application menu"
    if [ "$CLAIMED" -gt 0 ]; then
        log "Office icons on $CLAIMED file type(s) these apps open by default"
    fi
    if [ "$SKIPPED" -gt 0 ]; then
        log "$SKIPPED type(s) left alone, another application opens them. Make Excel or PowerPoint the default and run this again to give those files the Office icon"
    fi
    [ -f "$PROJECT_DIR/icons/powerpoint.png" ] \
        || warn "Using placeholder icons - run ./finish-setup.sh once Office is installed to get the real ones"
fi
