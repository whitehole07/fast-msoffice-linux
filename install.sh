#!/usr/bin/env bash
#
# One-command setup: Microsoft Office on Linux, in a Windows VM, with the apps
# appearing as native windows on your desktop.
#
#   ./install.sh
#
# Prepares everything that can be automated and then installs Windows
# unattended - no wizard, no keypresses. Safe to re-run: every step skips work
# already done, so an interrupted download or a failed step just resumes.
#
# Nothing is installed on your system. Deleting this folder removes everything.
#
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/env.sh"

STEP=0; TOTAL=10
step() { STEP=$((STEP + 1)); log "[$STEP/$TOTAL] $*"; }


# --------------------------------------------------------------- 1. host check
step "Checking the host can run VMs"

[ -e /dev/kvm ] || die "/dev/kvm missing - enable virtualization (VT-x/AMD-V) in your BIOS"
[ -r /dev/kvm ] && [ -w /dev/kvm ] || die "No access to /dev/kvm. Fix: sudo usermod -aG kvm $(id -un), then log out and back in"

MISSING=()
for b in qemu-system-x86_64 qemu-img swtpm swtpm_setup rpm2cpio cpio curl genisoimage; do
    command -v "$b" >/dev/null || MISSING+=("$b")
done
[ ${#MISSING[@]} -eq 0 ] || die "Missing tools: ${MISSING[*]}
  On Fedora: sudo dnf install qemu-kvm swtpm swtpm-tools edk2-ovmf genisoimage cpio curl"

[ -f "$OVMF_CODE" ] || die "UEFI firmware missing: $OVMF_CODE
  On Fedora: sudo dnf install edk2-ovmf"

AVAIL_GB=$(df -BG --output=avail "$PROJECT_DIR" | tail -1 | tr -dc '0-9')
[ "${AVAIL_GB:-0}" -ge 80 ] || die "Only ${AVAIL_GB}G free; this needs about 80G"

mkdir -p "$VM_DIR" "$ISO_DIR" "$TPM_DIR" "$OPT_DIR" "$PROJECT_DIR/icons"
log "KVM ready, ${AVAIL_GB}G free, QEMU $(qemu-system-x86_64 --version | awk 'NR==1{print $4}')"


# ------------------------------------------------------------------ 2. FreeRDP
step "Setting up FreeRDP (into opt/, not onto your system)"

if [ -x "$FREERDP_BIN" ]; then
    log "Already present, skipping"
else
    TMP_RPM="$PROJECT_DIR/.tmp-rpm"
    rm -rf "$TMP_RPM"; mkdir -p "$TMP_RPM"
    # Download the packages as a normal user and unpack them here rather than
    # installing them, so the host stays untouched.
    ( cd "$TMP_RPM" && dnf download --resolve freerdp >/dev/null 2>&1 ) \
        || die "Could not download the freerdp packages"
    for r in "$TMP_RPM"/*.rpm; do
        rpm2cpio "$r" | ( cd "$OPT_DIR" && cpio -idmu --quiet ) 2>/dev/null
    done
    rm -rf "$TMP_RPM"
    [ -x "$FREERDP_BIN" ] || die "FreeRDP extraction failed"
fi
log "$("$FREERDP_BIN" --version 2>&1 | head -1)"


# ------------------------------------------------------------- 3. Windows media
step "Checking for the Windows 11 ISO"

if [ -n "${WIN_ISO:-}" ] && [ -f "$WIN_ISO" ]; then
    log "Found $(basename "$WIN_ISO")"
else
    # Not automated on purpose. Microsoft issues only session-scoped, expiring
    # links, and its anti-automation checks reject scripted requests with
    # "SentinelReject" even given a full browser fingerprint. A downloader here
    # would fail for everyone and bury this message under a stack trace.
    die "No Windows 11 ISO found - this is the one manual step.

  1. Open  https://www.microsoft.com/software-download/windows11
  2. Under 'Windows 11 Disk Image (ISO) for x64 devices', pick your language
  3. Save the .iso into:  $ISO_DIR

  No product key, no account, no registration. Then run ./install.sh again."
fi


# ------------------------------------------------------------- 4. virtio drivers
step "Fetching the virtio drivers"

VIRTIO_EXPECTED=$(curl -sSIL --max-time 30 "$VIRTIO_URL" 2>/dev/null \
                  | tr -d '\r' | awk 'tolower($1)=="content-length:"{n=$2} END{print n}')
if [ -f "$VIRTIO_ISO" ] && [ -n "${VIRTIO_EXPECTED:-}" ] \
   && [ "$(stat -c%s "$VIRTIO_ISO")" -eq "$VIRTIO_EXPECTED" ]; then
    log "Already downloaded, skipping"
else
    curl -L -C - --retry 5 --progress-bar -o "$VIRTIO_ISO" "$VIRTIO_URL" \
        || warn "virtio download failed - not fatal, but the VM will use slower emulated devices"
fi


# ------------------------------------------------------------------ 5. password
step "Preparing the Windows account"

if [ -f "$PASSWORD_FILE" ]; then
    log "Using the existing password from $(basename "$PASSWORD_FILE")"
else
    # Generated rather than fixed, so a published repo never implies a known
    # password. Stored 0600 and gitignored.
    umask 077
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20 > "$PASSWORD_FILE"
    chmod 600 "$PASSWORD_FILE"
    log "Generated a random password for user '$RDP_USER'"
fi


# ------------------------------------------------------- 6. unattended install
step "Building the unattended-install CD"

UNATTEND_ISO="$ISO_DIR/unattend.iso"
UNATTEND_SRC="$VM_DIR/.unattend"
rm -rf "$UNATTEND_SRC"; mkdir -p "$UNATTEND_SRC"

# Windows Setup scans removable media for autounattend.xml, so handing it this
# CD is all it takes to make the installation hands-off.
TZ_WIN="${TZ_WIN:-$(timedatectl show -p Timezone --value 2>/dev/null || echo UTC)}"
case "$TZ_WIN" in
    Europe/Rome|Europe/Berlin|Europe/Paris|Europe/Madrid|Europe/Amsterdam|Europe/Brussels|Europe/Vienna)
        TZ_WIN="W. Europe Standard Time" ;;
    Europe/London|Europe/Dublin|Europe/Lisbon) TZ_WIN="GMT Standard Time" ;;
    Europe/Athens|Europe/Helsinki|Europe/Kyiv)  TZ_WIN="E. Europe Standard Time" ;;
    America/New_York) TZ_WIN="Eastern Standard Time" ;;
    America/Chicago)  TZ_WIN="Central Standard Time" ;;
    America/Denver)   TZ_WIN="Mountain Standard Time" ;;
    America/Los_Angeles) TZ_WIN="Pacific Standard Time" ;;
    *) TZ_WIN="UTC" ;;
esac

# Windows wants a locale like it-IT; derive it from the detected keyboard.
case "$RDP_KBD" in
    0x00000410) WIN_LOCALE="it-IT" ;; 0x00000407) WIN_LOCALE="de-DE" ;;
    0x0000040C) WIN_LOCALE="fr-FR" ;; 0x0000040A) WIN_LOCALE="es-ES" ;;
    0x00000809) WIN_LOCALE="en-GB" ;; 0x00000413) WIN_LOCALE="nl-NL" ;;
    0x00000816) WIN_LOCALE="pt-PT" ;; 0x0000041D) WIN_LOCALE="sv-SE" ;;
    *)          WIN_LOCALE="en-US" ;;
esac

PW=$(cat "$PASSWORD_FILE")
sed -e "s|@@USERNAME@@|$RDP_USER|g" \
    -e "s|@@PASSWORD@@|$PW|g" \
    -e "s|@@TIMEZONE@@|$TZ_WIN|g" \
    -e "s|@@INPUTLOCALE@@|$WIN_LOCALE|g" \
    -e "s|@@USERLOCALE@@|$WIN_LOCALE|g" \
    "$PROJECT_DIR/windows/autounattend.xml.template" > "$UNATTEND_SRC/autounattend.xml"
cp "$PROJECT_DIR/windows/configure.ps1"     "$UNATTEND_SRC/configure.ps1"
cp "$PROJECT_DIR/windows/install-office.ps1" "$UNATTEND_SRC/install-office.ps1"

genisoimage -quiet -J -r -V "UNATTEND" -o "$UNATTEND_ISO" "$UNATTEND_SRC" 2>/dev/null \
    || die "Could not build the unattended ISO"
rm -rf "$UNATTEND_SRC"
log "Built $(basename "$UNATTEND_ISO") (locale $WIN_LOCALE, timezone $TZ_WIN)"


# ------------------------------------------------------- 7. firmware, TPM, disk
step "Creating the virtual machine"

if [ -f "$OVMF_VARS" ]; then
    log "UEFI variables already exist"
else
    # Firmware code stays read-only in /usr/share; only this per-VM copy of the
    # variable store belongs to the project.
    cp "$OVMF_VARS_TEMPLATE" "$OVMF_VARS"; chmod u+w "$OVMF_VARS"
fi

if [ -f "$TPM_DIR/tpm2-00.permall" ]; then
    log "TPM already initialised"
else
    # No --create-ek-cert: that needs root-owned /var/lib/swtpm-localca, and
    # Windows only requires a TPM to exist, not a certified one.
    swtpm_setup --tpmstate "$TPM_DIR" --tpm2 --overwrite >/dev/null 2>&1 \
        || die "swtpm_setup failed - Windows 11 will not install without a TPM"
fi

if [ -f "$DISK" ]; then
    log "Disk already exists ($(du -h "$DISK" | cut -f1) used)"
else
    qemu-img create -f qcow2 "$DISK" "$DISK_SIZE" >/dev/null
    log "Created a $DISK_SIZE sparse disk"
fi


# ------------------------------------------------------------ 8. install Windows
step "Installing Windows"

if [ -f "$VM_DIR/.installed" ]; then
    log "Already installed, skipping"
else
    log "Starting the unattended installation - no input needed"
    log "A window will show progress; it is safe to minimise but not to close"
    "$PROJECT_DIR/vm.sh" install >/dev/null 2>&1 &

    # Microsoft's boot image prints "Press any key to boot from CD or DVD" and
    # waits about five seconds. Nobody is watching an unattended install, so
    # press it through the QEMU monitor. Sent repeatedly because the exact
    # moment the prompt appears depends on how fast the firmware initialises;
    # stray Enter keys in Windows Setup are harmless.
    (
        for _ in $(seq 1 40); do
            [ -S "$VM_DIR/monitor.sock" ] && break
            sleep 1
        done
        for _ in $(seq 1 30); do
            monitor_send "sendkey ret" || true
            sleep 1
        done
    ) &

    # Windows partitions the disk, installs, runs configure.ps1 at first logon
    # (which is what enables Remote Desktop), installs Office and reboots. RDP
    # answering is therefore the signal that all of that has finished.
    log "Waiting for Windows - typically 15 to 30 minutes"
    DEADLINE=$(( $(date +%s) + 4500 ))   # 75 minutes; Office is a big download
    until timeout 12 "$FREERDP_BIN" /v:"127.0.0.1:$RDP_PORT" /u:"$RDP_USER" /d: \
            /p:"$(cat "$PASSWORD_FILE")" /cert:ignore +auth-only >/dev/null 2>&1; do
        [ "$(date +%s)" -lt "$DEADLINE" ] \
            || die "Windows did not finish in 75 minutes.
  Watch it with:  ./vm.sh start
  Then re-run this script; it will pick up where it left off."
        sleep 20
    done
    touch "$VM_DIR/.installed"
    log "Windows is up"
fi


# ---------------------------------------------------------------- 9. finishing
step "Extracting icons and adding menu entries"

"$PROJECT_DIR/lib/finish-setup.sh" --quiet || warn "Finishing steps had a problem; re-run ./install.sh to retry"


# --------------------------------------------------------------- 10. all done
step "Done"

echo
log "Setup complete. Launch Office with:"
echo
echo "     ./powerpoint.sh        ./excel.sh"
echo
echo "  or find PowerPoint and Excel in your application menu."
echo
echo "  Sign in inside PowerPoint with your Microsoft 365 account to activate"
echo "  Office. If it offers to manage your device, choose 'No, sign in to this"
echo "  app only' - that avoids enrolling this VM in an organisation."
echo
echo "  ./vm.sh stop     when you are finished for the day"
