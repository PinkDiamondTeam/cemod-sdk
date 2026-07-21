#!/usr/bin/env python3
"""Normalize unaligned PPC32 absolute relocations for the Cemu loader.

GNU ld emits R_PPC_UADDR32 for a few packed libstdc++ tables.  Cemu applies
R_PPC_ADDR32 byte-by-byte, so the two have identical runtime behaviour here.
The package ABI intentionally has one absolute-32 relocation spelling.
"""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


SHT_RELA = 4
R_PPC_ADDR32 = 1
R_PPC_UADDR32 = 24


def normalize(path: Path) -> int:
    data = bytearray(path.read_bytes())
    if len(data) < 52 or data[:7] != b"\x7fELF\x01\x02\x01":
        raise ValueError("expected a 32-bit big-endian ELF")

    section_offset = struct.unpack_from(">I", data, 32)[0]
    section_size = struct.unpack_from(">H", data, 46)[0]
    section_count = struct.unpack_from(">H", data, 48)[0]
    if section_size < 40 or section_offset + section_size * section_count > len(data):
        raise ValueError("ELF section table is out of bounds")

    changed = 0
    for index in range(section_count):
        header = section_offset + index * section_size
        section_type = struct.unpack_from(">I", data, header + 4)[0]
        if section_type != SHT_RELA:
            continue
        offset, size, entry_size = struct.unpack_from(">III", data, header + 16)[0], struct.unpack_from(">III", data, header + 16)[1], struct.unpack_from(">I", data, header + 36)[0]
        if entry_size < 12 or size % entry_size or offset + size > len(data):
            raise ValueError("ELF relocation section is invalid")
        for relocation in range(offset, offset + size, entry_size):
            info = struct.unpack_from(">I", data, relocation + 4)[0]
            if (info & 0xFF) == R_PPC_UADDR32:
                struct.pack_into(">I", data, relocation + 4,
                                 (info & ~0xFF) | R_PPC_ADDR32)
                changed += 1

    path.write_bytes(data)
    return changed


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("elf", type=Path)
    arguments = parser.parse_args()
    print(f"normalized {normalize(arguments.elf)} R_PPC_UADDR32 relocations")


if __name__ == "__main__":
    main()
