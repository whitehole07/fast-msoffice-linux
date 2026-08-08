#!/usr/bin/env bash
#
# Control the Windows VM.
#
#   ./vm.sh start        start it, in a window
#   ./vm.sh headless     start it with no window (what the app launchers use)
#   ./vm.sh install      boot the Windows installer (unattended)
#   ./vm.sh stop         shut Windows down gracefully
#   ./vm.sh stop force   pull the plug (only if Windows is wedged)
#   ./vm.sh status       is it running?
#
# QEMU is invoked directly - no libvirt, no daemon, nothing registered on the
# host. Every piece of state lives in vm/.
#
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/env.sh"

running() { pgrep -f 'qemu-system-x86_6[4]' >/dev/null 2>&1; }

ACTION="${1:-start}"

case "$ACTION" in
    status)
        running && log "VM is running" || log "VM is not running"
        exit 0
        ;;

    stop)
        running || { log "VM is not running"; exit 0; }

        if [ "${2:-}" = "force" ]; then
            warn "Forcing power off - Windows will not shut down cleanly"
            pkill -f 'qemu-system-x86_6[4]' || true
            sleep 2
            pkill -f 'swtp[m] socket' 2>/dev/null || true
            exit 0
        fi

        MON="$VM_DIR/monitor.sock"
        [ -S "$MON" ] || die "No monitor socket; shut down from inside Windows this once"

        # An ACPI power button event, exactly like pressing power on a physical
        # machine: Windows flushes its disks and exits cleanly. Killing QEMU
        # instead risks a dirty filesystem.
        log "Asking Windows to shut down..."
        python3 -c "
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sys.argv[1]); s.sendall(b'system_powerdown\n'); s.close()
" "$MON"

        for _ in $(seq 1 60); do
            running || { log "VM is off"; exit 0; }
            sleep 2
        done
        warn "Still running after 2 minutes - Windows may be asking you to save something"
        exit 0
        ;;

    start)    MODE=normal ;;
    headless) MODE=headless ;;
    install)  MODE=install ;;
    *) die "Unknown command '$ACTION'. Try: start | headless | install | stop | status" ;;
esac


# --------------------------------------------------------------------- start
[ -f "$DISK" ]      || die "No disk image. Run ./install.sh first."
[ -f "$OVMF_VARS" ] || die "No UEFI variables. Run ./install.sh first."

mkdir -p "$TPM_DIR"

# --- software TPM 2.0 -------------------------------------------------------
# Windows 11 refuses to install without a TPM. swtpm emulates one and keeps its
# state in vm/tpm/, so the "chip" belongs to this folder like everything else.
TPM_SOCK="$TPM_DIR/swtpm-sock"
if ! pgrep -f "swtpm.*$TPM_DIR" >/dev/null 2>&1; then
    rm -f "$TPM_SOCK"
    swtpm socket --tpmstate dir="$TPM_DIR" \
                 --ctrl type=unixio,path="$TPM_SOCK" \
                 --tpm2 --daemon --log level=0
    sleep 0.5
fi
[ -S "$TPM_SOCK" ] || die "swtpm failed to start"

# Stop the TPM when the VM exits so nothing lingers.
trap 'pkill -f "swtpm.*$TPM_DIR" 2>/dev/null || true' EXIT

# --- display ----------------------------------------------------------------
# q35 has no USB controller by default, so an xHCI one is added explicitly.
# usb-tablet then gives absolute pointer coordinates, which stops the window
# from grabbing the mouse and needing a key to release it.
case "$MODE" in
    headless) DISPLAY_ARGS=(-display none -vga std) ;;
    *)        DISPLAY_ARGS=(-display gtk -vga std
                            -device qemu-xhci,id=xhci
                            -device usb-tablet,bus=xhci.0) ;;
esac

# --- optical media ----------------------------------------------------------
MEDIA=()

# The virtio driver CD stays attached in normal use so the drivers are always
# reachable from inside Windows. Read-only, never booted.
if [ -f "$VIRTIO_ISO" ] && [ "$MODE" != "install" ]; then
    MEDIA+=(-drive "file=$VIRTIO_ISO,if=none,id=cdv,media=cdrom,readonly=on"
            -device ide-cd,drive=cdv,bus=sata.2)
fi

if [ "$MODE" = "install" ]; then
    [ -n "${WIN_ISO:-}" ] && [ -f "$WIN_ISO" ] \
        || die "No Windows ISO in $ISO_DIR - see GUIDE.md, then run ./install.sh"

    # UEFI ignores QEMU's -boot order and uses its own boot list, so the install
    # CD gets an explicit bootindex below the hard disk's. The virtio CD gets
    # none: it is not bootable and only supplies drivers.
    MEDIA+=(-drive "file=$WIN_ISO,if=none,id=cd0,media=cdrom,readonly=on"
            -device ide-cd,drive=cd0,bus=sata.1,bootindex=0)
    [ -f "$VIRTIO_ISO" ] && MEDIA+=(
            -drive "file=$VIRTIO_ISO,if=none,id=cd1,media=cdrom,readonly=on"
            -device ide-cd,drive=cd1,bus=sata.2)
    # Windows Setup scans removable media for autounattend.xml; this CD is what
    # makes the installation hands-off.
    [ -f "$ISO_DIR/unattend.iso" ] && MEDIA+=(
            -drive "file=$ISO_DIR/unattend.iso,if=none,id=cdu,media=cdrom,readonly=on"
            -device ide-cd,drive=cdu,bus=sata.3)
    MEDIA+=(-boot menu=on,splash-time=3000)
    log "Installing from $(basename "$WIN_ISO") - this takes 15-30 minutes, unattended"
fi

log "Starting VM (${VM_CPUS} vCPU, ${VM_RAM} RAM), RDP on localhost:${RDP_PORT}"

# q35 + smm=on + the secure pflash global are what Secure Boot requires.
# The disk is AHCI and the NIC defaults to virtio-net once its driver is in;
# during installation e1000e is used because Windows has that driver built in.
exec qemu-system-x86_64 \
    -name "M365-office" \
    -enable-kvm \
    -machine q35,smm=on \
    -cpu "$CPU_MODEL" \
    -smp "$VM_CPUS",sockets=1,cores="$VM_CPUS",threads=1 \
    -m "$VM_RAM" \
    -rtc base=localtime,driftfix=slew \
    -global kvm-pit.lost_tick_policy=discard \
    -global driver=cfi.pflash01,property=secure,value=on \
    -drive "if=pflash,format=$OVMF_FORMAT,unit=0,readonly=on,file=$OVMF_CODE" \
    -drive "if=pflash,format=$OVMF_FORMAT,unit=1,file=$OVMF_VARS" \
    -chardev "socket,id=chrtpm,path=$TPM_SOCK" \
    -tpmdev emulator,id=tpm0,chardev=chrtpm \
    -device tpm-crb,tpmdev=tpm0 \
    -device ich9-ahci,id=sata \
    -drive "file=$DISK,if=none,id=hd0,format=qcow2,cache=writeback,discard=unmap" \
    -device ide-hd,drive=hd0,bus=sata.0,bootindex=2 \
    -monitor "unix:$VM_DIR/monitor.sock,server,nowait" \
    -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:${RDP_PORT}-:3389" \
    -device "$NIC_MODEL",netdev=net0 \
    "${DISPLAY_ARGS[@]}" \
    "${MEDIA[@]}"
