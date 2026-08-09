#!/usr/bin/env bash
#
# Run once, after Windows has installed itself and settled.
#
#   ./finish-setup.sh
#
# Verifies Office is present, lifts the real application icons out of the
# Windows binaries, refreshes the menu entries and switches the VM to the
# faster virtio network card. Safe to re-run.
#
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/env.sh"

QUIET=0
if [ "${1:-}" = "--quiet" ]; then QUIET=1; fi

OFFICE='C:\Program Files\Microsoft Office\root\Office16'

# --- make sure the VM is up ------------------------------------------------
if ! pgrep -f 'qemu-system-x86_6[4]' >/dev/null 2>&1; then
    log "Starting the VM"
    # No idle watcher for this one. Setup connects in bursts with long gaps in
    # between, and Office may still be installing itself, so a VM that looks
    # idle from the outside is in the middle of work. Stop it with ./vm.sh stop
    # when setup is done, or let the next app launch adopt a watched VM.
    VM_IDLE_TIMEOUT=0 "$PROJECT_DIR/vm.sh" headless >/dev/null 2>&1 &
fi

log "Waiting for Windows"
for i in $(seq 1 45); do
    if timeout 12 "$FREERDP_BIN" /v:"127.0.0.1:$RDP_PORT" /u:"$RDP_USER" /d: \
         /p:"$(cat "$PASSWORD_FILE")" /cert:ignore +auth-only >/dev/null 2>&1; then
        log "Windows is up"
        break
    fi
    [ "$i" -eq 45 ] && die "Windows did not respond. Is it still installing? Watch with: ./vm.sh start"
    sleep 10
done

# --- pull the icons out of the Office binaries -----------------------------
# Rather than asking you to copy files by hand, run a command inside Windows
# that copies the executables onto the redirected drive, then read their PE
# icon resources here.
fetch() {
    local exe="$1" out="$2"
    [ -f "$PROJECT_DIR/icons/$out" ] && return 0
    log "Extracting the $out icon"
    # Retried: on a fresh install Office may still be finishing, and a missing
    # binary should mean "wait", not "give up".
    local dest='\\tsclient\linux'"${PROJECT_DIR#$HOME}"'\icons\'"$exe"
    dest="${dest//\//\\}"
    for _ in $(seq 1 10); do
        timeout 120 "$FREERDP_BIN" /v:"127.0.0.1:$RDP_PORT" /u:"$RDP_USER" /d: \
            /p:"$(cat "$PASSWORD_FILE")" /cert:ignore /drive:linux,"$HOME" \
            /app:program:"cmd.exe",cmd:"/c copy /y \"$OFFICE\\$exe\" \"$dest\"" \
            >/dev/null 2>&1 || true
        [ -f "$PROJECT_DIR/icons/$exe" ] && break
        sleep 30
    done
    if [ -f "$PROJECT_DIR/icons/$exe" ]; then
        python3 "$PROJECT_DIR/lib/extract-icons.py" \
            "$PROJECT_DIR/icons/$exe" "$PROJECT_DIR/icons/$out" >/dev/null 2>&1 \
            && log "  got $out" || warn "  could not decode an icon from $exe"
        rm -f "$PROJECT_DIR/icons/$exe"
    else
        warn "  could not copy $exe out of the VM (is Office installed?)"
    fi
}

fetch POWERPNT.EXE powerpoint.png
fetch EXCEL.EXE    excel.png

# --- refresh the menu entries so they pick up the real icons ---------------
"$PROJECT_DIR/lib/setup-desktop.sh" --quiet
log "Application menu entries refreshed"

# --- switch to the faster network card -------------------------------------
# The virtio driver is installed by configure.ps1 during setup, so this is
# safe by the time you get here. e1000e is used during installation only
# because Windows has a built-in driver for it.
if [ "$NIC_MODEL" = "e1000e" ] && ! grep -q 'NIC_MODEL:-virtio' "$PROJECT_DIR/env.sh"; then
    sed -i 's|NIC_MODEL="${NIC_MODEL:-e1000e}"|NIC_MODEL="${NIC_MODEL:-virtio-net-pci}"|' "$PROJECT_DIR/env.sh"
    log "Switched the VM to virtio networking (applies at next start)"
fi

touch "$VM_DIR/.installed"

if [ "$QUIET" -eq 0 ]; then
    echo
    log "Done. Launch Office with:"
    echo "     ./powerpoint.sh      ./excel.sh"
fi
