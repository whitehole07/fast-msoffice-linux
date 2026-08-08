#!/usr/bin/env bash
#
# Start the Windows VM.
#
#   ./run-vm.sh install    boot with the Windows + virtio ISOs attached
#   ./run-vm.sh            boot normally, in a window
#   ./run-vm.sh headless   boot with no window (for RemoteApp use)
#
# Uses QEMU directly — no libvirt daemon, no VM registered anywhere on the
# host. All state (disk, UEFI vars, TPM) lives in vm/.
#
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

MODE="${1:-normal}"

[ -f "$DISK" ] || die "No disk image. Run ./install.sh first."
[ -f "$OVMF_VARS" ] || die "No UEFI vars file. Run ./install.sh first."

mkdir -p "$TPM_DIR"

# --- software TPM 2.0 -------------------------------------------------------
# Windows 11 refuses to install without a TPM. swtpm emulates one; its state is
# a file in vm/tpm/, so the "chip" belongs to this folder like everything else.
TPM_SOCK="$TPM_DIR/swtpm-sock"
if ! pgrep -f "swtpm.*$TPM_DIR" >/dev/null 2>&1; then
    swtpm socket --tpmstate dir="$TPM_DIR" \
                 --ctrl type=unixio,path="$TPM_SOCK" \
                 --tpm2 --daemon --log level=0
    sleep 0.5
fi
[ -S "$TPM_SOCK" ] || die "swtpm failed to start"

# Stop the TPM when the VM exits so nothing lingers.
cleanup() { pkill -f "swtpm.*$TPM_DIR" 2>/dev/null || true; }
trap cleanup EXIT

# --- display ----------------------------------------------------------------
# q35 has no USB controller by default, so an xHCI one is added explicitly.
# usb-tablet then gives absolute pointer coordinates, which stops the VM window
# from grabbing the mouse and needing a key to release it.
case "$MODE" in
    headless) DISPLAY_ARGS=(-display none -vga std) ;;
    *)        DISPLAY_ARGS=(-display gtk -vga std
                            -device qemu-xhci,id=xhci
                            -device usb-tablet,bus=xhci.0) ;;
esac

# --- install media ----------------------------------------------------------
MEDIA=()

# The virtio driver CD is attached in every mode, so the drivers are always
# reachable from inside Windows. It is read-only and never booted.
if [ -f "$VIRTIO_ISO" ] && [ "$MODE" != "install" ]; then
    MEDIA+=(-drive "file=$VIRTIO_ISO,if=none,id=cdv,media=cdrom,readonly=on"
            -device ide-cd,drive=cdv,bus=sata.2)
fi

if [ "$MODE" = "install" ]; then
    [ -n "${WIN_ISO:-}" ] && [ -f "$WIN_ISO" ] \
        || die "No Windows ISO found in $ISO_DIR — download one and re-run."
    # UEFI ignores QEMU's -boot order and uses its own boot list, so the CD is
    # given an explicit bootindex lower than the hard disk's instead. The
    # virtio CD gets no bootindex — it is not bootable and only supplies drivers.
    MEDIA+=(-drive "file=$WIN_ISO,if=none,id=cd0,media=cdrom,readonly=on"
            -device ide-cd,drive=cd0,bus=sata.1,bootindex=0)
    [ -f "$VIRTIO_ISO" ] && MEDIA+=(
            -drive "file=$VIRTIO_ISO,if=none,id=cd1,media=cdrom,readonly=on"
            -device ide-cd,drive=cd1,bus=sata.2)
    # Windows Setup scans removable media for autounattend.xml; attaching this
    # CD is what makes the installation hands-off.
    if [ -f "$ISO_DIR/unattend.iso" ]; then
        MEDIA+=(-drive "file=$ISO_DIR/unattend.iso,if=none,id=cdu,media=cdrom,readonly=on"
                -device ide-cd,drive=cdu,bus=sata.3)
    fi
    MEDIA+=(-boot menu=on,splash-time=3000)
    log "Installing from $(basename "$WIN_ISO")"
fi

log "Starting VM (${VM_CPUS} vCPU, ${VM_RAM} RAM) — RDP forwarded to localhost:${RDP_PORT}"

# Notes on the choices below:
#  q35 + smm=on + the secure pflash global are required for Secure Boot.
#  The disk is AHCI/SATA and the NIC is e1000e on purpose: Windows has built-in
#  drivers for both, so setup needs no "Load driver" step. The virtio ISO is
#  still attached if you later want to switch for extra speed.
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
