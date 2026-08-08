#!/usr/bin/env bash
# Shared configuration for the Windows/Office VM.
# Sourced by the other scripts — do not run directly.
#
# Every path below lives inside this project folder. Nothing is installed on
# the host: qemu/swtpm/edk2 come from the system, FreeRDP is extracted locally
# into opt/, and no libvirt daemon is involved.

# This file lives in lib/, so the project root is one level up.
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VM_DIR="${VM_DIR:-$PROJECT_DIR/vm}"
ISO_DIR="${ISO_DIR:-$VM_DIR/iso}"
TPM_DIR="${TPM_DIR:-$VM_DIR/tpm}"
OPT_DIR="${OPT_DIR:-$PROJECT_DIR/opt}"

DISK="${DISK:-$VM_DIR/windows.qcow2}"
DISK_SIZE="${DISK_SIZE:-60G}"
OVMF_VARS="${OVMF_VARS:-$VM_DIR/OVMF_VARS.qcow2}"

# Windows 11 requires UEFI + Secure Boot + TPM 2.0. The .secboot firmware ships
# with Microsoft's keys enrolled, which is what lets the installer proceed.
#
# Use the 4M qcow2 build, NOT the 2M OVMF_CODE.secboot.fd: Fedora's 2M images
# are the deprecated legacy build and lack TPM 2.0 support, so Windows setup
# reports "The PC must support TPM 2.0" even with a working swtpm attached.
OVMF_CODE="${OVMF_CODE:-/usr/share/edk2/ovmf/OVMF_CODE_4M.secboot.qcow2}"
OVMF_VARS_TEMPLATE="${OVMF_VARS_TEMPLATE:-/usr/share/edk2/ovmf/OVMF_VARS_4M.secboot.qcow2}"
OVMF_FORMAT="${OVMF_FORMAT:-qcow2}"

# Look in vm/iso/ first, then the project root, so an ISO downloaded straight
# into the folder by a browser is picked up without moving it.
# The `|| true` matters: this file is sourced under `set -e` with pipefail, and
# before an ISO exists the pipeline fails and would abort the calling script.
WIN_ISO="${WIN_ISO:-$(ls "$ISO_DIR"/*.iso "$PROJECT_DIR"/*.iso 2>/dev/null \
                      | grep -viE 'virtio' | head -1 || true)}"
VIRTIO_ISO="${VIRTIO_ISO:-$ISO_DIR/virtio-win.iso}"
VIRTIO_URL="${VIRTIO_URL:-https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso}"

# Guest sizing. You have 8 cores / 30GB, so 4 vCPU + 8GB leaves the host ample
# headroom. Raise VM_RAM if you work with very large decks.
# Compositing happens on the CPU (no GPU in the VM), so cores directly affect
# how smooth the session feels. 6 of your 8 still leaves the host headroom.
VM_CPUS="${VM_CPUS:-6}"

# Hyper-V enlightenments. Windows has paravirtualised interfaces for timers,
# interrupts, spinlocks and TLB flushes, but only uses them when the hypervisor
# advertises them. Without these it falls back to emulated hardware timers and
# busy-waits on spinlocks, which is a large and constant overhead.
CPU_MODEL="${CPU_MODEL:-host,hv_relaxed,hv_spinlocks=0x1fff,hv_vapic,hv_time,hv_vpindex,hv_runtime,hv_synic,hv_stimer,hv_stimer_direct,hv_frequencies,hv_tlbflush,hv_ipi,hv_reenlightenment}"
VM_RAM="${VM_RAM:-8G}"

# RDP is reached over QEMU user-mode networking, which needs no root and no
# bridge. Guest port 3389 is forwarded to this port on the host loopback.
# Network card model. e1000e works with no driver installation, which is why
# Windows setup used it. virtio-net-pci is markedly faster and lower latency,
# but needs the NetKVM driver installed inside Windows first -- otherwise the
# VM boots with no network at all. Switch only after installing the drivers.
NIC_MODEL="${NIC_MODEL:-virtio-net-pci}"

RDP_PORT="${RDP_PORT:-13389}"
RDP_USER="${RDP_USER:-office}"

# Keyboard layout announced to Windows.
#
# This cannot be left to FreeRDP's own detection: it reads the X11 keymap, and
# under GNOME/Wayland XWayland reports "us" to X clients even when the session
# is Italian, so Windows silently ends up on a US layout.
#
# Detect the real layout from the desktop instead, preferring GNOME's input
# sources (authoritative on Wayland) and falling back to localectl. Override
# with RDP_KBD=0x... for anything not covered; /list:kbd prints all 262.
detect_kbd_layout() {
    local xkb=""
    if command -v gsettings >/dev/null 2>&1; then
        xkb=$(gsettings get org.gnome.desktop.input-sources sources 2>/dev/null \
              | grep -oE "'xkb', '[^']+'" | head -1 | grep -oE "'[^']+'$" | tr -d "'")
    fi
    if [ -z "$xkb" ] && command -v localectl >/dev/null 2>&1; then
        xkb=$(localectl status 2>/dev/null | awk -F: '/X11 Layout/{gsub(/ /,"",$2); print $2}' | cut -d, -f1)
    fi
    if [ -z "$xkb" ] && command -v setxkbmap >/dev/null 2>&1; then
        xkb=$(setxkbmap -query 2>/dev/null | awk '/^layout/{print $2}' | cut -d, -f1)
    fi

    case "$xkb" in
        it) echo 0x00000410 ;; us) echo 0x00000409 ;; gb) echo 0x00000809 ;;
        de) echo 0x00000407 ;; at) echo 0x00000407 ;; fr) echo 0x0000040C ;;
        es) echo 0x0000040A ;; pt) echo 0x00000816 ;; br) echo 0x00000416 ;;
        nl) echo 0x00000413 ;; be) echo 0x00000813 ;; ch) echo 0x00000807 ;;
        se) echo 0x0000041D ;; no) echo 0x00000414 ;; dk) echo 0x00000406 ;;
        fi) echo 0x0000040B ;; pl) echo 0x00000415 ;; cz) echo 0x00000405 ;;
        sk) echo 0x0000041B ;; hu) echo 0x0000040E ;; ro) echo 0x00000418 ;;
        ru) echo 0x00000419 ;; ua) echo 0x00000422 ;; gr) echo 0x00000408 ;;
        tr) echo 0x0000041F ;; jp) echo 0x00000411 ;; kr) echo 0x00000412 ;;
        *)  echo 0x00000409 ;;   # unknown -> US, the safest fallback
    esac
}

RDP_KBD="${RDP_KBD:-$(detect_kbd_layout)}"

# FreeRDP extracted into opt/ rather than installed system-wide.
FREERDP_BIN="${FREERDP_BIN:-$OPT_DIR/usr/bin/xfreerdp}"
export LD_LIBRARY_PATH="$OPT_DIR/usr/lib64:${LD_LIBRARY_PATH:-}"

# Arguments shared by desktop.sh and rdp-app.sh.
#
#   /d:            empty domain. Without it FreeRDP prompts "Domain:" on the
#                  terminal, which fails outright when there is no TTY.
#   /drive:linux   maps your Linux home into Windows as \\tsclient\linux, so
#                  Office can open and save files outside the VM.
#   /gfx:AVC444    H.264 4:4:4 — 4:2:0 subsampling would blur small text.
#   /network:lan   stop trading quality for bandwidth we are not short of.
# Codec. AVC420 (H.264 4:2:0) is the default because it roughly halves the
# per-frame encode work compared with 4:4:4, which sends a second auxiliary
# chroma frame. That extra frame buys sharper static text but costs latency
# during continuous motion, which is exactly when it hurts - dragging shapes.
#   RDP_GFX=AVC444  sharper text, laggier dragging
#   RDP_GFX=RFX     older codec, try if H.264 misbehaves
#   RDP_GFX=off     plain bitmaps, most compatible
RDP_GFX="${RDP_GFX:-AVC420}"
if [ "$RDP_GFX" = "off" ]; then
    GFX_ARGS=()
else
    GFX_ARGS=(/gfx:"$RDP_GFX")
fi

RDP_ARGS=(
    /v:"127.0.0.1:$RDP_PORT"
    "${GFX_ARGS[@]}"
    /u:"$RDP_USER"
    /d:
    /kbd:layout:"$RDP_KBD"
    /drive:linux,"$HOME"
    /network:lan
    # Less to draw and less to encode, so redraws land sooner. Themes are
    # deliberately left on: disabling them makes Office chrome look broken.
    -menu-anims
    -wallpaper
    /bpp:32
    # +async-update omitted: FreeRDP force-deactivates it (upstream #10153).
    +async-channels
    /dynamic-resolution
    /scale:180
    # Leave Alt+Tab, Super and other window-manager shortcuts to the host.
    # Without this FreeRDP grabs the keyboard and swallows them.
    -grab-keyboard
    # Explicit beats the bare +clipboard default: name the X selection and turn
    # on both directions, including file copy/paste.
    /clipboard:use-selection:CLIPBOARD,direction-to:all,files-to:all
    # +auto-reconnect removed: on a loopback socket there is no transient
    # network loss to recover from, and when the app closes normally the
    # reconnect path segfaults inside client_auto_reconnect_ex.
    /cert:ignore
)

# Run FreeRDP, obtaining the password in whichever way suits the context.
# With a terminal, FreeRDP prompts normally. Without one — a desktop shortcut,
# an application menu, a tool session — it cannot, so ask via a dialog and pass
# the answer on stdin. Stdin rather than /p: keeps the password out of the
# process list, where any other user on the machine could read it.
PASSWORD_FILE="${PASSWORD_FILE:-$PROJECT_DIR/.rdp-password}"

rdp_run() {
    # A saved password takes precedence, so launching never blocks on a prompt.
    #
    # This passes it via /p:, which puts it in the process list where any
    # process of yours (or root) could read it. The tidier options do not work:
    # /from-stdin insists on a real terminal even when reading a pipe, and
    # /args-from's file format is undocumented and rejected every variant.
    # On a single-user laptop, talking to a VM on loopback, the exposure is
    # equivalent to the 0600 file itself. Delete .rdp-password to go back to
    # being asked each time.
    if [ -r "$PASSWORD_FILE" ]; then
        "$FREERDP_BIN" "${RDP_ARGS[@]}" /p:"$(cat "$PASSWORD_FILE")" "$@"
    elif [ -t 0 ]; then
        "$FREERDP_BIN" "${RDP_ARGS[@]}" "$@"
    elif command -v zenity >/dev/null 2>&1; then
        local pw
        pw=$(zenity --password --title="M365-office" \
                    --text="Password for Windows user '$RDP_USER'" 2>/dev/null) \
            || { warn "Password entry cancelled"; return 1; }
        printf '%s\n' "$pw" | "$FREERDP_BIN" "${RDP_ARGS[@]}" /from-stdin "$@"
    else
        die "No terminal and no zenity — cannot ask for the password"
    fi
}

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!! \033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERR\033[0m %s\n' "$*" >&2; exit 1; }
