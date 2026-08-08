# fast-msoffice-linux

**Microsoft Excel and PowerPoint on Linux, as real native windows — fast and smooth.**

Own taskbar entry. Own alt-tab slot. Real Office icons. The Windows VM behind
it stays completely invisible.

Not a browser tab. Not a Windows desktop in a window. Not Wine.

```bash
./install.sh          # prepare everything
./run-vm.sh install   # Windows installs itself, unattended
./finish-setup.sh     # icons, menu entries, faster networking
./powerpoint.sh       # a real PowerPoint window
```

## Fast

Typing, scrolling, dragging objects and slide animations all feel like a local
app. This is not an emulator — **KVM runs Windows instructions directly on your
CPU** — and the setup is tuned hard out of the box:

- **Virtualization-Based Security disabled** — Windows 11 otherwise runs a
  hypervisor *inside* your VM, taxing everything. The biggest single win.
- **Hyper-V enlightenments** — paravirtualized timers, interrupts and
  spinlocks, so Windows stops busy-waiting.
- **60 fps compositing** — Windows caps RDP at ~30 fps by default.
- **H.264 (AVC420) video pipeline** — half the encode cost of 4:4:4, which is
  exactly what you feel when dragging objects.
- **Office hardware acceleration off** — with no GPU, Office's Direct3D path
  falls back to a software rasterizer that is *slower* than plain drawing.
- **virtio networking**, 6 vCPUs, and RDP over loopback — sub-millisecond.

Every one of these is applied automatically. Most guides to Office-in-a-VM skip
them, which is why this feels different from a VM you have tried before.

## Self-contained

Everything lives in one folder. **Nothing is installed on your system** — QEMU
is invoked directly with no libvirt daemon, and FreeRDP is unpacked into `opt/`
rather than installed. Delete the folder and every trace is gone.

## Hands-off

`./run-vm.sh install` and walk away. Windows partitions the disk, installs Pro,
creates a local account, enables Remote Desktop, applies every tweak above and
installs Office — no wizard, no keypresses. The answer file is generated to
match your keyboard layout and timezone automatically.

## Why

Office Online is a browser tab. LibreOffice mangles complex `.pptx`. Wine
cannot install Microsoft 365 at all — Click-to-Run fails before it writes a
log. And add-ins like **Efficient Elements** or **think-cell** hook so deeply
into PowerPoint that only real Windows will do.

**[Read the full guide →](GUIDE.md)**

## Requirements

- CPU with virtualization (VT-x / AMD-V), ~80 GB disk, 16 GB RAM recommended
- A Microsoft 365 subscription — Windows itself needs **no licence key**
- `qemu-kvm swtpm swtpm-tools edk2-ovmf genisoimage cpio curl`
