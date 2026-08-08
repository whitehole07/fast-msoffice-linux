# M365-office

Excel and PowerPoint on Linux as **real desktop windows** — own taskbar entry,
own alt-tab slot, real Office icons — backed by a Windows VM that stays out of
sight.

Not a browser tab. Not a Windows desktop in a window. Not Wine.

```bash
./install.sh          # prepare everything
./run-vm.sh install   # Windows installs itself, unattended
./finish-setup.sh     # icons, menu entries, faster networking
./powerpoint.sh       # a real PowerPoint window
```

Everything lives in this folder. Nothing is installed on your system — QEMU
runs directly with no libvirt daemon, and FreeRDP is unpacked into `opt/`
rather than installed. Delete the folder and it's all gone.

Built for Office add-ins that need genuine Windows, such as Efficient Elements
and think-cell, which Wine and Office Online cannot run.

**[Read the full guide →](GUIDE.md)**

## Requirements

- CPU with virtualization (VT-x / AMD-V), ~80 GB disk, 16 GB RAM recommended
- A Microsoft 365 subscription (Windows itself needs no licence key)
- `qemu-kvm swtpm swtpm-tools edk2-ovmf genisoimage cpio curl`
