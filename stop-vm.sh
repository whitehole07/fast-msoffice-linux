#!/usr/bin/env bash
# Shut the VM down gracefully from the host.
#
#   ./stop-vm.sh        ask Windows to shut down (ACPI), then wait
#   ./stop-vm.sh force   pull the plug (only if Windows is wedged)
#
# The graceful path sends an ACPI power button event, exactly like pressing
# the power button on a physical machine: Windows flushes its disks and exits
# cleanly. Killing QEMU instead risks a dirty filesystem.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./env.sh

pgrep -f 'qemu-system-x86_6[4]' >/dev/null || { log "VM is not running"; exit 0; }

if [ "${1:-}" = "force" ]; then
    warn "Forcing power off - Windows will not shut down cleanly"
    pkill -f 'qemu-system-x86_6[4]' || true
    sleep 2
    pkill -f 'swtp[m] socket' 2>/dev/null || true
    exit 0
fi

MON="$VM_DIR/monitor.sock"
[ -S "$MON" ] || die "No monitor socket. This VM was started before stop-vm.sh existed - shut down from inside Windows this once."

log "Asking Windows to shut down..."
python3 - "$MON" <<'PY'
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sys.argv[1])
s.sendall(b"system_powerdown\n")
s.close()
PY

for _ in $(seq 1 60); do
    pgrep -f 'qemu-system-x86_6[4]' >/dev/null || { log "VM is off"; exit 0; }
    sleep 2
done
warn "Still running after 2 minutes - Windows may be showing a 'save your work' prompt"
