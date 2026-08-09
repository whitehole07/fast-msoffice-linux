# Microsoft Office on Linux, properly

Run Excel and PowerPoint on Linux as **real desktop windows**, own taskbar
entry, own alt-tab slot, real Office icons, backed by a Windows VM that stays
invisible.

Not a browser tab. Not a Windows desktop in a window. Not Wine.

```
./install.sh      # one command: installs Windows and Office, unattended
./powerpoint.sh   # a real PowerPoint window
```

Everything lives in this one folder. **Nothing is installed on your system.**
Delete the folder and every trace is gone.

---

## Why this exists

Office on Linux usually means picking a compromise. Office Online is a browser
tab. LibreOffice mangles complicated `.pptx` files. Wine can't install
Microsoft 365 at all, its Click-to-Run installer gives up before it even writes
a log. And PowerPoint add-ins need real Windows, because ribbon integration and
COM automation aren't things you can fake.

A VM fixes compatibility but normally hands you a Windows desktop stuck inside
a window, which is its own kind of annoying. RDP has a feature called RemoteApp
that sends one application's window instead of the whole desktop, so that's
what this uses. Windows runs headless in the background and PowerPoint behaves
like any other app you have open.

## Requirements

| | |
|---|---|
| CPU | Hardware virtualization (VT-x / AMD-V) |
| RAM | 16 GB recommended (8 GB goes to the VM) |
| Disk | ~80 GB free |
| Licence | A Microsoft 365 subscription, for Office |

Windows itself needs **no licence key**. It installs and runs indefinitely
unactivated, you get a watermark and locked personalization settings, and
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

### 2. Run one command

```bash
./install.sh
```

Then walk away. It checks your system, unpacks FreeRDP, downloads the virtio
drivers, generates a random Windows password, builds an unattended-install CD
matched to your keyboard layout and timezone, creates the disk, firmware
variables and virtual TPM, then **installs Windows and Office without any
input** and finishes by extracting the real Office icons and adding the apps to
your menu.

Expect 15-30 minutes, mostly downloading Office. A window shows progress; you
can minimise it, but closing it kills the VM.

Safe to interrupt and re-run - every step detects work already done, so it
picks up where it left off rather than starting over.

### 3. Activate Office

Open PowerPoint and sign in with your Microsoft 365 account.

> If it offers to let your organization manage the device, choose
> **"No, sign in to this app only"**. Otherwise Windows tries to enrol this VM
> into your employer's or university's device management, handing their IT
> administrators control over it, and the enrolment often fails anyway.

---

## Daily use

```bash
./powerpoint.sh     # or launch from your application menu
./excel.sh
```

The VM starts automatically if it isn't running. First launch of the day waits
for Windows to boot (~30s); after that it's instant.

Closing the last Office window leaves the VM with nothing to do, so it shuts
itself down 15 minutes later and gives back its 8 GB. The next launch starts it
again, so this only ever costs you the boot wait. Raise `VM_IDLE_TIMEOUT` to
keep it warm for longer, or set it to `0` to leave it up until you say
otherwise:

```bash
./vm.sh stop        # shut the VM down now
```

The countdown only runs on a VM started by an application launcher. `./vm.sh
start` opens a window because you asked for one, and is left alone. Nothing is
closed underneath you either: a document with unsaved changes blocks the
shutdown, and the VM stays up until you deal with it.

| Command | Purpose |
|---|---|
| `./powerpoint.sh`, `./excel.sh` | Office apps as native windows |
| `./desktop.sh` | Full Windows desktop, for installing add-ins or settings |
| `./vm.sh start` | Start the VM in a window |
| `./vm.sh headless` | Start it invisibly |
| `./vm.sh stop` | Graceful shutdown |
| `./vm.sh stop force` | Pull the plug (only if wedged) |
| `./lib/setup-desktop.sh --remove` | Remove the application menu entries |

### Your files

Your Linux home is mounted inside Windows as `\\tsclient\linux`, so Office can
open and save files that live on the Linux side. Documents stay where they are;
nothing is trapped in the VM.

Double-clicking works too. Excel and PowerPoint appear under "Open With" for
the formats they own, and can be set as the default for them. The path is
translated on the way in, so Office opens the file where it already lives
rather than a copy. `configure.ps1` marks the share as trusted, without which
Office would treat it as a network location and open everything read only.

Two limits. A file has to be somewhere under your home directory, because that
is the only thing Windows can see, and a file name cannot contain a comma,
which Remote Desktop uses to separate the arguments it sends. Both say so on
the desktop rather than failing quietly.

Spreadsheets and presentations also get the real Office icons in the file
manager. Icons come from the file type rather than from whichever application
opens it, so this is separate from the default-application setting and works
either way. A thumbnailer, if you have one for these formats, shows slide
previews instead and takes precedence.

### Other Windows apps

```bash
./lib/rdp-app.sh 'C:\Windows\System32\notepad.exe'
APP_NAME='My App' ./lib/rdp-app.sh 'C:\Path\To\App.exe'
```

Anything installed in the VM can be published as a window this way.

---

## Configuration

Everything is in `lib/env.sh`, and any setting can be overridden per-run:

```bash
VM_RAM=16G ./vm.sh start          # more memory for large files
RDP_GFX=AVC444 ./powerpoint.sh  # sharper text, slightly laggier motion
RDP_KBD=0x00000409 ./excel.sh   # force a US keyboard
```

| Variable | Default | Notes |
|---|---|---|
| `VM_CPUS` | 6 | Compositing is CPU-bound; more cores means smoother |
| `VM_RAM` | 8G | |
| `DISK_SIZE` | 60G | Sparse, it only uses what it needs |
| `RDP_GFX` | AVC420 | `AVC444` sharper, `RFX` older, `off` most compatible |
| `RDP_KBD` | auto | Detected from your desktop |
| `NIC_MODEL` | virtio-net-pci | `e1000e` if virtio drivers are missing |
| `VM_IDLE_TIMEOUT` | 900 | Seconds with no window open before shutdown, `0` never |
| `VM_IDLE_GRACE` | 300 | Seconds to allow for booting before the timeout applies |

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
 , libvirt would scatter VM state across `/etc/libvirt` and `/var/lib/libvirt`,
  breaking the "one folder" property.
- **swtpm** emulates the TPM 2.0 chip Windows 11 demands.
- **OVMF** is the UEFI firmware, with Secure Boot keys enrolled.
- **RemoteApp (RAIL)** publishes one application instead of a desktop.
- **FreeRDP** renders it as a native X11 window.

### The files

| | |
|---|---|
| `lib/env.sh` | Every setting, one place. Sourced by the rest |
| `install.sh` | One-command preparation |
| `vm.sh` | Start, stop and status for the VM |
| `lib/rdp-app.sh` | Publishes a single app; starts the VM if needed |
| `lib/idle-stop.sh` | Shuts the VM down once no application is open |
| `lib/finish-setup.sh` | Post-install: icons, menu entries, virtio |
| `lib/extract-icons.py` | Reads icons out of Windows PE resources |
| `lib/window-icons.sh` | Gives each Office window the right icon in alt-tab |
| `windows/autounattend.xml.template` | Unattended install answer file |
| `windows/configure.ps1` | Runs inside Windows at first logon |
| `vm/` | Disk, firmware variables, TPM state, ISOs |
| `opt/` | FreeRDP, unpacked rather than installed |

---

## Performance

KVM runs the guest on the host CPU, so compute is close to native. What follows
concerns the layers above that, all enabled by default in a stock Windows VM.

**Virtualization-Based Security, off.** Windows 11 enables VBS and Memory
Integrity by default, which runs a hypervisor inside the VM. The resulting
nested virtualisation adds cost to every context switch. VBS protects
credentials on physical hardware; here it guards a disposable sandbox reachable
only on loopback, so it is disabled.

**Hyper-V enlightenments.** Windows has paravirtualised interfaces for timers,
interrupts, spinlocks and TLB flushes, but only uses them if the hypervisor
says they exist. Without them it falls back to emulated hardware timers and
spins on locks. We pass `hv_passthrough`, which exposes everything the host
kernel supports.

**60 fps compositing.** Windows throttles RDP to about 30 fps.
`DWMFRAMEINTERVAL` is the minimum gap between frames in milliseconds, so 15
targets 60.

**H.264, 4:2:0.** Pass no codec flag and FreeRDP negotiates whatever the server
offers, often something considerably slower. AVC420 halves the encoding work of
4:4:4 for a small loss of text sharpness, and encoding is the bottleneck during
continuous motion like dragging a shape.

**Office hardware acceleration, off.** Office draws through Direct3D. With no
GPU that lands on WARP, Microsoft's software rasteriser, which is slower than
Office's own drawing path. This is the largest single improvement for dragging
objects on a slide.

**virtio networking and 6 vCPUs.** RDP runs over loopback, so the emulated
network card was pure overhead. Compositing is CPU-bound without a GPU, so
cores translate directly into smoothness.

### Where it still falls short

There is no GPU in the VM, so the compositor renders in software. In practice
this has not been the limiting factor; the settings above matter more.

Switching between two open Office windows is slow, and clicks can land in the
window you switched away from. That is a
[FreeRDP RemoteApp limitation](https://github.com/FreeRDP/FreeRDP/issues/12984):
Windows sends "this window is active now" messages that the X11 client does not
act on. No client setting works around it. With one window open it does not
arise, and `./desktop.sh` avoids it when you need several apps at once.

## Troubleshooting

**Windows didn't install / setup asked questions**
The unattended CD wasn't picked up. Check `vm/iso/unattend.iso` exists, re-run
`./install.sh`, and make sure you used `./vm.sh install`.

**"The PC must support TPM 2.0"**
Your firmware lacks TPM support. `lib/env.sh` must point at the **4 MB** OVMF build
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
The driver wasn't installed. Recover with `NIC_MODEL=e1000e ./vm.sh start`, then
install `virtio-win-gt-x64.msi` from the virtio CD inside Windows.

**Dragging feels sluggish**
Check `File → Options → Advanced → Display → Disable hardware graphics
acceleration` is ticked in Office.

---

## Uninstalling

```bash
./lib/setup-desktop.sh --remove     # menu entries and file icons
rm -rf ~/Documents/Projects/fast-msoffice-linux
```

That's everything: Windows, Office, the VM and all its state. Outside its own
folder this project writes two `.desktop` entries and a handful of icon
symlinks pointing back here, because an application menu and an icon theme are
the two things that cannot live in a project directory. `--remove` deletes
them, and the icons are links rather than copies, so nothing of them is left
behind either way.

---

## Notes on licensing

Windows installs without a key and runs indefinitely unactivated. Microsoft
permits the installation and does not enforce activation for personal use,
though its licence terms do nominally expect a key. You get a watermark and
cannot change wallpaper or accent colours. Nothing here circumvents activation.

Office requires a genuine Microsoft 365 subscription. This project installs the
software; your subscription licenses it.
