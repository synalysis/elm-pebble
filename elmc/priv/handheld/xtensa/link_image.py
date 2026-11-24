#!/usr/bin/env python3
"""Link a staged Elm handheld program into an Xtensa app.meow image.

The image is linked at address 0. Absolute pointers are recorded so the
firmware can add the real load address. Instruction bytes stay Xtensa.
"""

import os
import struct
import subprocess
import sys

def u16(buf, off):
    return struct.unpack_from("<H", buf, off)[0]


def u32(buf, off):
    return struct.unpack_from("<I", buf, off)[0]


def die(msg):
    print(msg, file=sys.stderr)
    sys.exit(1)


def run(cmd, cwd):
    result = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if result.returncode != 0:
        die(result.stdout or "command failed")
    return result.stdout


def compile_sources(gcc, app_dir, sources, out_dir):
    objects = []
    for name in sources:
        obj = os.path.join(out_dir, name + ".o")
        run(
            [
                gcc,
                "-c",
                "-std=c11",
                "-Os",
                "-ffreestanding",
                "-fno-stack-protector",
                "-mlongcalls",
                "-mtext-section-literals",
                "-ffunction-sections",
                "-fdata-sections",
                "-I",
                app_dir,
                "-o",
                obj,
                os.path.join(app_dir, name),
            ],
            app_dir,
        )
        objects.append(obj)
    return objects


def link_elf(gcc, app_dir, objects, ld_script, elf_path, origin):
    run(
        [
            gcc,
            "-nostdlib",
            "-o",
            elf_path,
            *objects,
            "-lgcc",
            "-Wl,--gc-sections",
            "-Wl,--defsym,MEOW_ORIGIN=" + origin,
            "-Wl,-u,meow_app_stop",
            "-Wl,-u,meow_app_event",
            "-Wl,-u,meow_app_frame",
            "-Wl,-T," + ld_script,
            "-Wl,-e,meow_app_start",
        ],
        app_dir,
    )


def parse_image(elf):
    if elf[:4] != b"\x7fELF" or elf[4] != 1 or elf[5] != 1:
        die("expected a little-endian ELF32 image")
    phoff = u32(elf, 28)
    shoff = u32(elf, 32)
    phentsize = u16(elf, 42)
    phnum = u16(elf, 44)
    shentsize = u16(elf, 46)
    shnum = u16(elf, 48)
    shstrndx = u16(elf, 50)
    load = None
    for i in range(phnum):
        off = phoff + i * phentsize
        if u32(elf, off) != 1:
            continue
        vaddr = u32(elf, off + 8)
        filesz = u32(elf, off + 16)
        memsz = u32(elf, off + 20)
        offset = u32(elf, off + 4)
        if load is None or vaddr < load[0]:
            load = (vaddr, offset, filesz, memsz)
    if load is None:
        die("elf has no load segment")
    vaddr, offset, filesz, memsz = load
    image = bytearray(elf[offset : offset + filesz]) + bytearray(memsz - filesz)
    sections = []
    for i in range(shnum):
        off = shoff + i * shentsize
        sections.append(
            {
                "name": u32(elf, off),
                "type": u32(elf, off + 4),
                "addr": u32(elf, off + 12),
                "offset": u32(elf, off + 16),
                "size": u32(elf, off + 20),
                "link": u32(elf, off + 24),
                "info": u32(elf, off + 28),
                "entsize": u32(elf, off + 36),
            }
        )
    strtab = sections[shstrndx]
    strings = elf[strtab["offset"] : strtab["offset"] + strtab["size"]]

    def section_name(sec):
        end = strings.index(b"\0", sec["name"])
        return strings[sec["name"] : end].decode()

    symbols = {}
    for sec in sections:
        if sec["type"] != 2:
            continue
        symtab = elf[sec["offset"] : sec["offset"] + sec["size"]]
        names = sections[sec["link"]]
        name_bytes = elf[names["offset"] : names["offset"] + names["size"]]
        for i in range(0, len(symtab), 16):
            name_off = u32(symtab, i)
            value = u32(symtab, i + 4)
            shndx = u16(symtab, i + 14)
            end = name_bytes.index(b"\0", name_off)
            name = name_bytes[name_off:end].decode()
            if name:
                symbols[name] = (value, shndx)
    return image, symbols, vaddr


def slide_sites(base_image, shifted_image, delta):
    if len(base_image) != len(shifted_image):
        die("the two link addresses produced different image sizes")
    sites = []
    for off in range(0, len(base_image) - 3, 4):
        base = u32(base_image, off)
        shifted = u32(shifted_image, off)
        if base == shifted:
            continue
        if (shifted - base) & 0xFFFFFFFF != delta:
            die(f"byte {off} changed by {(shifted - base) & 0xFFFFFFFF:#x}, not a pure slide")
        if base >= len(base_image):
            die(f"absolute word at {off} points outside the image ({base:#x})")
        sites.append(off)
    return sites


def main():
    if len(sys.argv) != 5:
        die("usage: link_image.py GCC APP_DIR LD_SCRIPT SUPPORT_C")
    gcc, app_dir, ld_script, support = sys.argv[1:]
    sources = [
        "elmc_generated.c",
        "elmc_worker.c",
        "elmc_runtime.c",
        "elmc_ports.c",
        "meow_app_entry.c",
        "elmc_handheld_shim.c",
    ]
    for name in sources:
        if not os.path.isfile(os.path.join(app_dir, name)):
            die(f"missing {name}")
    staged_support = os.path.join(app_dir, "meow_support.c")
    with open(support, "rb") as src, open(staged_support, "wb") as dst:
        dst.write(src.read())
    objects = compile_sources(gcc, app_dir, sources + ["meow_support.c"], app_dir)
    elf_path = os.path.join(app_dir, "app.elf")
    shifted_path = os.path.join(app_dir, "app.shifted.elf")
    link_elf(gcc, app_dir, objects, ld_script, elf_path, "0")
    link_elf(gcc, app_dir, objects, ld_script, shifted_path, "0x10000000")
    with open(elf_path, "rb") as fh:
        image, symbols, vaddr = parse_image(fh.read())
    with open(shifted_path, "rb") as fh:
        shifted, _, shifted_vaddr = parse_image(fh.read())
    if vaddr != 0 or shifted_vaddr != 0x10000000:
        die(f"unexpected load addresses {vaddr:#x} and {shifted_vaddr:#x}")
    relocs = slide_sites(image, shifted, 0x10000000)
    os.remove(shifted_path)
    entries = {}
    for name in ("meow_app_start", "meow_app_stop", "meow_app_event", "meow_app_frame"):
        if name not in symbols or symbols[name][1] == 0:
            die(f"missing symbol {name}")
        off = symbols[name][0] - vaddr
        if off < 0 or off >= len(image):
            die(f"{name} offset {off} is outside the image")
        entries[name] = off
    header = struct.pack(
        "<4sHHIIIIIII",
        b"MEOW",
        1,
        1,
        len(image),
        0,
        len(relocs),
        entries["meow_app_start"],
        entries["meow_app_stop"],
        entries["meow_app_event"],
        entries["meow_app_frame"],
    )
    blob_path = os.path.join(app_dir, "app.meow")
    with open(blob_path, "wb") as fh:
        fh.write(header)
        fh.write(image)
        for off in relocs:
            fh.write(struct.pack("<Ii", off, 0))
    print(
        f"xtensa image {len(image)} bytes, {len(relocs)} relocs, entry {entries['meow_app_start']}"
    )


if __name__ == "__main__":
    main()
