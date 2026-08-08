# Microsoft Office on Linux, properly

Run Excel and PowerPoint on Linux as **real desktop windows** — own taskbar
entry, own alt-tab slot, real Office icons — backed by a Windows VM that stays
invisible.

Not a browser tab. Not a Windows desktop in a window. Not Wine.

```
./install.sh          # prepare everything
./run-vm.sh install   # Windows installs itself, unattended
./finish-setup.sh     # icons, menu entries, faster networking
./powerpoint.sh       # a real PowerPoint window
```

Everything lives in this one folder. **Nothing is installed on your system.**
Delete the folder and every trace is gone.

---

## Why this exists

Office on Linux usually means compromises: Office Online is a browser tab,
LibreOffice breaks complex `.pptx` formatting, and Wine cannot install
Microsoft 365 at all — its Click-to-Run installer fails before it can even
write a log. Add-ins like **Efficient Elements** or **think-cell** hook so
deeply into PowerPoint that only real Windows will do.

A VM solves compatibility but normally costs you the desktop experience. This
project closes that gap with **RemoteApp**: an RDP feature that streams a
single application's window instead of a whole desktop. The VM runs headless in
the background, and PowerPoint behaves like any other Linux app.

---

## Requirements

| | |
|---|---|
| CPU | Hardware virtualization (VT-x / AMD-V) |
| RAM | 16 GB recommended (8 GB goes to the VM) |
| Disk | ~80 GB free |
| Licence | A Microsoft 365 subscription, for Office |

Windows itself needs **no licence key**. It installs and runs indefinitely
unactivated — you get a watermark and locked personalization settings, and
nothing else is restricted. Office is licensed separately by your subscription.

Packages (Fedora shown; the names are similar elsewhere):

```bash
sudo dnf install qemu-kvm swtpm swtpm-tools edk2-ovmf genisoimage cpio curl
```

These are the *only* things installed system-wide, and most machines with
virtualization set up already have them. FreeRDP is unpacked into `opt/` inside
this folder rather than installed.

---

## Setup

### 1. Get a Windows 11 ISO

From [microsoft.com/software-download/windows11](https://www.microsoft.com/software-download/windows11),
choose **"Windows 11 Disk Image (ISO) for x64 devices"**. No key, no
registration. Save it into `vm/iso/`.

### 2. Prepare

```bash
./install.sh
```

Checks your system, unpacks FreeRDP, downloads the virtio drivers, generates a
random Windows password, builds an unattended-install CD matched to your
keyboard layout and timezone, and creates the disk, UEFI variables and virtual
TPM.

Safe to re-run at any time — every step skips work already done, so an
interrupted download simply resumes.

### 3. Install Windows

```bash
./run-vm.sh install
```

Then walk away for 15–30 minutes. No wizard, no keypresses. Windows partitions
the disk, installs **Pro**, creates a local account, enables Remote Desktop,
applies every performance tweak, installs Office and reboots.

A window shows progress. Closing it kills the VM — minimize instead.

### 4. Finish

```bash
./finish-setup.sh
```

Extracts the real Office icons out of the Windows binaries, adds Excel and
PowerPoint to your application menu, and switches the VM to faster virtio
networking.

### 5. Activate Office

Open PowerPoint and sign in with your Microsoft 365 account.

> If it offers to let your organization manage the device, choose
> **"No, sign in to this app only"**. Otherwise Windows tries to enrol this VM
> into your employer's or university's device management, handing their IT
> administrators control over it — and the enrolment often fails anyway.

---

## Daily use

```bash
./powerpoint.sh     # or launch from your application menu
./excel.sh
```

The VM starts automatically if it isn't running. First launch of the day waits
for Windows to boot (~30s); after that it's instant.

```bash
./stop-vm.sh        # shut the VM down when you're done
```

Leaving it running costs 8 GB of RAM but makes launches instant. It uses almost
no CPU when idle.

| Command | Purpose |
|---|---|
| `./powerpoint.sh`, `./excel.sh` | Office apps as native windows |
| `./desktop.sh` | Full Windows desktop, for installing add-ins or settings |
| `./run-vm.sh` | Start the VM in a window |
| `./run-vm.sh headless` | Start it invisibly |
| `./stop-vm.sh` | Graceful shutdown |
| `./stop-vm.sh force` | Pull the plug (only if wedged) |
| `./setup-desktop.sh --remove` | Remove the application menu entries |

### Your files

Your Linux home is mounted inside Windows as `\\tsclient\linux`, so Office can
open and save files that live on the Linux side. Documents stay where they are;
nothing is trapped in the VM.

### Other Windows apps

```bash
./rdp-app.sh 'C:\Windows\System32\notepad.exe'
APP_NAME='My App' ./rdp-app.sh 'C:\Path\To\App.exe'
```

Anything installed in the VM can be published as a window this way.

---

## Configuration

Everything is in `env.sh`, and any setting can be overridden per-run:

```bash
VM_RAM=16G ./run-vm.sh          # more memory for large files
RDP_GFX=AVC444 ./powerpoint.sh  # sharper text, slightly laggier motion
RDP_KBD=0x00000409 ./excel.sh   # force a US keyboard
```

| Variable | Default | Notes |
|---|---|---|
| `VM_CPUS` | 6 | Compositing is CPU-bound; more cores means smoother |
| `VM_RAM` | 8G | |
| `DISK_SIZE` | 60G | Sparse — it only uses what it needs |
| `RDP_GFX` | AVC420 | `AVC444` sharper, `RFX` older, `off` most compatible |
| `RDP_KBD` | auto | Detected from your desktop |
| `NIC_MODEL` | virtio-net-pci | `e1000e` if virtio drivers are missing |

---

## How it works

```
   your desktop                      inside the VM
  ┌───────────────┐                ┌──────────────────┐
  │ PowerPoint    │◄── RemoteApp ──┤ PowerPoint       │
  │ window        │     over RDP   │ (real Windows)   │
  └───────────────┘                └──────────────────┘
        FreeRDP  ────── loopback ──────►  QEMU/KVM
```

- **KVM** runs Windows instructions directly on your CPU. Not emulation, so the
  speed penalty is small.
- **QEMU** provides the virtual hardware. Invoked directly, with **no libvirt**
  — libvirt would scatter VM state across `/etc/libvirt` and `/var/lib/libvirt`,
  breaking the "one folder" property.
- **swtpm** emulates the TPM 2.0 chip Windows 11 demands.
- **OVMF** is the UEFI firmware, with Secure Boot keys enrolled.
- **RemoteApp (RAIL)** publishes one application instead of a desktop.
- **FreeRDP** renders it as a native X11 window.

### The files

| | |
|---|---|
| `env.sh` | Every setting, one place. Sourced by the rest |
| `install.sh` | One-command preparation |
| `run-vm.sh` | Builds the QEMU command line |
| `rdp-app.sh` | Publishes a single app; starts the VM if needed |
| `finish-setup.sh` | Post-install: icons, menu entries, virtio |
| `extract-icons.py` | Reads icons out of Windows PE resources |
| `windows/autounattend.xml.template` | Unattended install answer file |
| `windows/configure.ps1` | Runs inside Windows at first logon |
| `vm/` | Disk, firmware variables, TPM state, ISOs |
| `opt/` | FreeRDP, unpacked rather than installed |

---

## Performance

Editing feels essentially native. The tuning that gets it there is applied
automatically:

- **Virtualization-Based Security off** — Windows 11 runs a hypervisor *inside*
  your VM by default for Memory Integrity. Nested virtualization taxes
  everything; this is the single biggest win.
- **Hyper-V enlightenments** — paravirtualized timers, interrupts and
  spinlocks, so Windows stops busy-waiting.
- **60 fps compositing** — Windows caps RDP at ~30 fps by default.
- **AVC420 (H.264)** — half the encode work of 4:4:4, which matters most during
  continuous motion like dragging shapes.
- **Office hardware acceleration off** — with no GPU, Office's Direct3D path
  falls back to a software rasterizer that is *slower* than plain drawing.
- **virtio networking** — lower latency than emulated hardware.

**The honest limit:** there is no GPU in the VM, so the desktop compositor
renders on the CPU. Editing, scrolling and typing feel native; a slideshow with
heavy transitions will not. Fixing that properly needs GPU passthrough, which
means a second GPU — impractical on a laptop.

---

## Troubleshooting

**Windows didn't install / setup asked questions**
The unattended CD wasn't picked up. Check `vm/iso/unattend.iso` exists, re-run
`./install.sh`, and make sure you used `./run-vm.sh install`.

**"The PC must support TPM 2.0"**
Your firmware lacks TPM support. `env.sh` must point at the **4 MB** OVMF build
(`OVMF_CODE_4M.secboot.qcow2`); the 2 MB one is a legacy build without TPM, and
the error appears even with a perfectly working swtpm attached.

**App window closes immediately / `RAIL_EXEC_E_NOT_IN_ALLOWLIST`**
RemoteApp isn't allowed. Connect with `./desktop.sh` and run, **as
Administrator**:

```
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Terminal Server\TSAppAllowList" /v fDisabledAllowList /t REG_DWORD /d 1 /f
```

A non-elevated shell fails silently here.

**Black window**
Codec negotiation. Try `RDP_GFX=RFX ./powerpoint.sh`, then `RDP_GFX=off`.

**Wrong keyboard layout**
Detection reads your desktop's input source. Override with
`RDP_KBD=0x00000410` (see `opt/usr/bin/xfreerdp /list:kbd`). Windows must also
have that layout added under Settings → Time & language.

**No network after switching to virtio**
The driver wasn't installed. Recover with `NIC_MODEL=e1000e ./run-vm.sh`, then
install `virtio-win-gt-x64.msi` from the virtio CD inside Windows.

**Dragging feels sluggish**
Check `File → Options → Advanced → Display → Disable hardware graphics
acceleration` is ticked in Office.

---

## Uninstalling

```bash
./setup-desktop.sh --remove     # the two application menu entries
rm -rf ~/Documents/Projects/M365-office
```

That's everything: Windows, Office, the VM and all its state. The only files
this project ever writes outside its own folder are those two `.desktop`
entries, because an application menu is the one thing that cannot live in a
project directory.

---

## Notes on licensing

Windows installs without a key and runs indefinitely unactivated. Microsoft
permits the installation and does not enforce activation for personal use,
though its licence terms do nominally expect a key. You get a watermark and
cannot change wallpaper or accent colours. Nothing here circumvents activation.

Office requires a genuine Microsoft 365 subscription. This project installs the
software; your subscription licenses it.
