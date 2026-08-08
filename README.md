<div align="center">

<img src="assets/logo.png" alt="fast-msoffice-linux" width="140">

# fast-msoffice-linux

**Run Excel and PowerPoint on Linux as native-feeling windows, with low latency.**

This repo is specifically optimized for low latency and responsiveness, so typing, scrolling, and dragging feel local rather than remote. Each app gets its own window, icon, and Alt-Tab entry, while the underlying Windows VM runs fully headless.

Setup takes a single command and installs nothing on your system.
<br>

[![License](https://img.shields.io/github/license/whitehole07/fast-msoffice-linux?style=flat-square&color=blue)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux-informational?style=flat-square)](#what-you-need)
[![KVM](https://img.shields.io/badge/KVM%2FQEMU-no%20libvirt-success?style=flat-square)](#how-it-works)
[![Stars](https://img.shields.io/github/stars/whitehole07/fast-msoffice-linux?style=flat-square&color=yellow)](https://github.com/whitehole07/fast-msoffice-linux/stargazers)

[Get started](#get-started) · [Why bother](#why-bother) · [Performance](#performance) · [Full guide](GUIDE.md)

<br>

<img src="assets/screenshot.png" alt="PowerPoint and Excel running as native windows on Fedora" width="880">

<sub>PowerPoint and Excel in the GNOME overview, each with its own icon. No Windows desktop anywhere.</sub>

</div>

---

## Get started

```bash
git clone https://github.com/whitehole07/fast-msoffice-linux
cd fast-msoffice-linux

./install.sh      # installs Windows and Office, no questions asked
./powerpoint.sh   # a real PowerPoint window
```

One thing you have to do yourself: grab a
[Windows 11 ISO](https://www.microsoft.com/software-download/windows11) and drop
it in `vm/iso/`. Microsoft hands out session-scoped download links and blocks
scripted requests, so nobody can automate that part reliably. No product key and
no account needed.

After that you can walk away. Windows partitions the disk, installs itself,
makes an account, applies all the tuning below, pulls down Office, and puts
Excel and PowerPoint in your application menu.

**[Read the full guide →](GUIDE.md)**

---

## Performance

This is the part the project is built around.

KVM runs the guest on the host CPU, so compute is close to native from the
start. The latency comes from the layers above it, and a stock Windows VM
leaves every one of them at a default that costs responsiveness. Each is
addressed during installation:

| Setting | Effect |
|---|---|
| Virtualization-Based Security disabled | Windows 11 runs a hypervisor inside the VM for Memory Integrity. Nested virtualisation adds cost to every context switch |
| `DWMFRAMEINTERVAL=15` | Windows throttles RDP compositing to roughly 30 fps; this targets 60 |
| `/gfx:AVC420` | H.264 4:2:0 halves the encode cost of 4:4:4. Encoding is the bottleneck during continuous motion |
| Office hardware acceleration disabled | With no GPU, Office's Direct3D path falls back to a software rasteriser slower than its own drawing code |
| `hv_passthrough` | Exposes every Hyper-V enlightenment the host supports: paravirtualised timers, interrupts, spinlocks, TLB flushes |
| virtio devices, 6 vCPU, 8 GB | Compositing is CPU-bound without a GPU, and RDP runs over loopback |

None of it requires configuration. See [the guide](GUIDE.md#performance) for the
reasoning behind each one.

There is no GPU in the guest, so the desktop compositor renders in software.
Editing, scrolling and animation are unaffected in practice. Switching between
two open Office windows is slow, which is a
[FreeRDP RemoteApp limitation](https://github.com/FreeRDP/FreeRDP/issues/12984)
rather than a tuning problem.

---

## Why bother

Office on Linux usually means picking which compromise annoys you least:

| | |
|---|---|
| Office Online | It's a browser tab |
| LibreOffice | Complex `.pptx` files come out wrong |
| Wine | Microsoft 365 won't even install. Click-to-Run dies before writing a log |
| A plain VM | Works fine, but now you're using a Windows desktop inside a window |

And if you rely on a PowerPoint add-in, none of those help at all. Ribbon
integration and COM automation need genuine Windows.

So this uses a VM, but hides it. RDP has a feature called RemoteApp that sends
a single application's window instead of the whole desktop. Windows runs
headless in the background and Office just sits on your desktop like anything
else.

---

## It stays in one folder

Nothing gets installed on your system. QEMU is called directly with no libvirt
daemon anywhere, and FreeRDP is unpacked into `opt/` instead of installed.

```bash
./lib/setup-desktop.sh --remove   # takes the menu entries back out
rm -rf fast-msoffice-linux        # Windows, Office, the VM, gone
```

---

## Using it

| Command | |
|---|---|
| `./powerpoint.sh`, `./excel.sh` | Office, as normal windows |
| `./desktop.sh` | Full Windows desktop, handy for installing add-ins |
| `./vm.sh start` · `headless` · `stop` · `status` | Control the VM |
| `./lib/setup-desktop.sh --remove` | Remove the menu entries |

Launching an app starts the VM if it isn't already up. Your home directory is
mounted inside Windows, so your files stay where they are.

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

KVM runs the guest on your CPU. QEMU provides the virtual hardware, with no
libvirt involved. swtpm fakes the TPM 2.0 chip that Windows 11 insists on.
OVMF is the UEFI firmware. RemoteApp publishes one app rather than a desktop,
and FreeRDP draws it as a native window.

---

## What you need

- A CPU with virtualisation (VT-x or AMD-V), about 80 GB of disk, 16 GB of RAM
  is comfortable
- A Microsoft 365 subscription for Office. Windows itself needs no licence key
- `qemu-kvm swtpm swtpm-tools edk2-ovmf genisoimage cpio curl`

Windows installs and runs indefinitely without activation. You get a watermark
and you can't change the wallpaper. Nothing else is restricted, and Office is
licensed by your subscription either way.

---

<div align="center">
<sub>MIT licensed. Not affiliated with Microsoft.</sub>
</div>
