#!/usr/bin/env python3
"""Pull the application icon out of a Windows .exe and save it as a PNG.

    ./extract-icons.py icons/POWERPNT.EXE icons/powerpoint.png

Windows executables carry their icons as PE resources: RT_ICON (type 3) holds
each size, and the largest is what we want for a HiDPI desktop. Modern icons
store the 256x256 entry as an embedded PNG; smaller ones are raw DIB bitmaps,
which we wrap in a minimal .ico header so Pillow can decode them.

Used to give the RemoteApp windows a real PowerPoint/Excel icon instead of a
generic placeholder.
"""
import struct
import sys
from io import BytesIO
from pathlib import Path

RT_ICON = 3


def rva_to_offset(rva, sections):
    for va, vsize, raw_ptr, raw_size in sections:
        if va <= rva < va + max(vsize, raw_size):
            return raw_ptr + (rva - va)
    raise ValueError(f"RVA {rva:#x} is not inside any section")


def parse_pe(data):
    """Return (resource_base_rva, resource_offset, sections)."""
    if data[:2] != b"MZ":
        raise ValueError("not a DOS/PE executable")
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe:pe + 4] != b"PE\0\0":
        raise ValueError("PE signature missing")

    n_sections = struct.unpack_from("<H", data, pe + 6)[0]
    opt_size = struct.unpack_from("<H", data, pe + 20)[0]
    opt_off = pe + 24
    magic = struct.unpack_from("<H", data, opt_off)[0]
    # PE32+ has a wider image base, shifting the data directories by 16 bytes.
    dir_off = opt_off + (112 if magic == 0x20B else 96)
    res_rva, _ = struct.unpack_from("<II", data, dir_off + 8 * 2)

    sec_off = opt_off + opt_size
    sections = []
    for i in range(n_sections):
        s = sec_off + 40 * i
        vsize, va, raw_size, raw_ptr = struct.unpack_from("<IIII", data, s + 8)
        sections.append((va, vsize, raw_ptr, raw_size))
    return res_rva, rva_to_offset(res_rva, sections), sections


def walk(data, base, offset, depth=0, wanted=None):
    """Yield (data_rva, size) leaves under the given resource directory."""
    n_named, n_id = struct.unpack_from("<HH", data, offset + 12)
    for i in range(n_named + n_id):
        e = offset + 16 + 8 * i
        name, entry = struct.unpack_from("<II", data, e)
        if depth == 0 and wanted is not None and not (name & 0x80000000):
            if name != wanted:
                continue
        if entry & 0x80000000:
            yield from walk(data, base, base + (entry & 0x7FFFFFFF), depth + 1, wanted)
        else:
            rva, size = struct.unpack_from("<II", data, base + entry)
            yield rva, size


def as_png(blob, sections):
    """Return PNG bytes for one RT_ICON payload."""
    if blob[:8] == b"\x89PNG\r\n\x1a\n":
        return blob
    from PIL import Image
    # Wrap the bare DIB in a one-entry .ico so Pillow will decode it.
    width, height = struct.unpack_from("<ii", blob, 4)
    height //= 2  # DIB height covers XOR + AND masks stacked
    bpp = struct.unpack_from("<H", blob, 14)[0]
    ico = struct.pack("<HHH", 0, 1, 1)
    ico += struct.pack("<BBBBHHII", width & 0xFF, height & 0xFF, 0, 0,
                       1, bpp, len(blob), 22)
    img = Image.open(BytesIO(ico + blob))
    out = BytesIO()
    img.save(out, format="PNG")
    return out.getvalue()


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    data = src.read_bytes()

    res_rva, res_off, sections = parse_pe(data)
    icons = []
    for rva, size in walk(data, res_off, res_off, 0, RT_ICON):
        off = rva_to_offset(rva, sections)
        icons.append(data[off:off + size])

    if not icons:
        sys.exit(f"no RT_ICON resources found in {src}")

    # Validate rather than trusting the resource type: Office binaries carry
    # hundreds of resources and the walk picks up non-icon payloads too, some
    # of them larger than any real icon. Keep only blobs that parse as a PNG or
    # as a plausible icon DIB, then choose the one with the most pixels.
    def describe(blob):
        if blob[:8] == b"\x89PNG\r\n\x1a\n":
            w, h = struct.unpack_from(">II", blob, 16)
            return (w, h) if 0 < w <= 1024 and 0 < h <= 1024 else None
        if len(blob) < 40:
            return None
        header, w, h, _planes, bpp = struct.unpack_from("<iiiHH", blob, 0)
        h //= 2  # DIB height spans the XOR and AND masks stacked
        if header != 40 or not (0 < w <= 512 and 0 < h <= 512):
            return None
        if bpp not in (1, 4, 8, 16, 24, 32):
            return None
        return (w, h)

    candidates = [(d, b) for b in icons if (d := describe(b))]
    if not candidates:
        sys.exit(f"found {len(icons)} resources in {src} but none decode as icons")

    (w, h), best = max(candidates, key=lambda c: c[0][0] * c[0][1])
    png = as_png(best, sections)
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes(png)

    from PIL import Image
    with Image.open(dst) as im:
        print(f"{src.name}: {len(icons)} icons found, wrote {dst} at {im.size[0]}x{im.size[1]}")


if __name__ == "__main__":
    main()
