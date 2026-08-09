#!/usr/bin/env bash
#
# Shut the VM down once nothing is using it.
#
# Started by vm.sh in headless mode, which is the mode the app launchers use.
# A `./vm.sh start` window is a deliberate session, so it is left alone.
#
# What counts as "in use" is the number of FreeRDP clients on this host. Under
# RemoteApp a client process is the application window, so its lifetime is
# exactly the signal we want: no clients means nothing is on screen. Detecting
# idleness inside Windows instead would need a scheduled task and a channel back
# to the host, for something the host can already see.
#
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/env.sh"

[ "${VM_IDLE_TIMEOUT:-0}" -gt 0 ] || exit 0

mkdir -p "$VM_DIR"
LOG="$VM_DIR/idle-stop.log"
say() { printf '%s %s\n' "$(date -Is)" "$*" >>"$LOG"; }

# Match the client on its executable name, not its command line. `pgrep -f
# xfreerdp` also matches any script or shell that merely mentions the path, and
# a client that is not really there would keep the VM up forever.
#
# QEMU cannot be found that way: the kernel keeps only 15 characters of a
# process name, so qemu-system-x86_64 is stored truncated. It is matched on the
# command line instead, with the bracket vm.sh uses to avoid matching itself.
FREERDP_NAME="$(basename "$FREERDP_BIN")"
running() { pgrep -f 'qemu-system-x86_6[4]' >/dev/null 2>&1; }
clients() { pgrep -x "$FREERDP_NAME" >/dev/null 2>&1; }

# There is deliberately no guard against a second watcher. It would need either
# a lock, which a child process inherits and can then hold after we are gone,
# blocking the next real watcher, or a search for our own script name, which
# matches any shell that mentions the path. Duplicates are harmless anyway:
# whichever one calls vm.sh stop first wins, and the other finds the VM already
# off and exits.

# vm.sh launches this just before it execs QEMU, so give the process a moment
# to appear rather than concluding the VM has already gone.
for _ in $(seq 1 30); do
    running && break
    sleep 2
done
running || exit 0

say "watching (timeout ${VM_IDLE_TIMEOUT}s, grace ${VM_IDLE_GRACE}s)"

INTERVAL=30
idle=0
used=0

while running; do
    sleep "$INTERVAL"

    if clients; then
        idle=0
        used=1
        continue
    fi

    # A cold boot takes 40 to 60 seconds before the first client can connect,
    # and a launch that fails leaves no client at all. Until one has been seen,
    # hold off until the grace period is up so neither case stops the VM early.
    if [ "$used" -eq 0 ] && [ "$SECONDS" -lt "$VM_IDLE_GRACE" ]; then
        continue
    fi

    idle=$(( idle + INTERVAL ))
    [ "$idle" -ge "$VM_IDLE_TIMEOUT" ] || continue

    say "idle for ${idle}s, shutting down"
    "$PROJECT_DIR/vm.sh" stop >>"$LOG" 2>&1 || true

    # An ACPI shutdown does not always complete: Office blocks it while a
    # document has unsaved changes, which is what stops this from throwing work
    # away. Start the clock again and try later rather than giving up.
    if running; then
        say "still running, Windows is refusing to shut down"
        idle=0
    fi
done

# vm.sh arms an EXIT trap for swtpm and then execs QEMU, which replaces the
# shell and discards the trap, so the emulated TPM outlives every graceful stop.
# We are still here, so clean it up.
pkill -f "swtpm.*$TPM_DIR" 2>/dev/null || true
say "VM is off"
