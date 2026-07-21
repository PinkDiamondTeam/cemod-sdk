#!/usr/bin/env python3
import argparse
import json
import pathlib
import re
import struct
import subprocess
import tempfile
import zipfile


ALLOWED_RELOCATIONS = {
    "R_PPC_NONE", "R_PPC_ADDR32", "R_PPC_ADDR16_LO", "R_PPC_ADDR16_HI",
    "R_PPC_ADDR16_HA", "R_PPC_REL24", "R_PPC_RELATIVE", "R_PPC_REL32",
}


def output(*command: str) -> str:
    return subprocess.run(command, check=True, text=True, stdout=subprocess.PIPE).stdout


def bootstrap_section(elf: bytes) -> bytes:
    if len(elf) < 52:
        raise SystemExit("mod.elf is truncated")
    section_offset = struct.unpack_from(">I", elf, 32)[0]
    entry_size, count, names_index = struct.unpack_from(">HHH", elf, 46)
    if entry_size < 40 or not count or names_index >= count or \
            section_offset + entry_size * count > len(elf):
        raise SystemExit("mod.elf section table is invalid")

    def section(index: int) -> tuple[int, ...]:
        offset = section_offset + index * entry_size
        return struct.unpack_from(">10I", elf, offset)

    names = section(names_index)
    names_offset, names_size = names[4], names[5]
    if names_offset + names_size > len(elf):
        raise SystemExit("mod.elf section-name table is invalid")
    matches = []
    for index in range(count):
        current = section(index)
        name_offset = current[0]
        if name_offset >= names_size:
            continue
        end = elf.find(b"\0", names_offset + name_offset, names_offset + names_size)
        if end < 0:
            continue
        name = elf[names_offset + name_offset:end]
        if name == b".cemod.bootstrap":
            file_offset, size = current[4], current[5]
            if file_offset + size > len(elf) or not (current[2] & 2):
                raise SystemExit(".cemod.bootstrap is not a loadable section")
            matches.append(elf[file_offset:file_offset + size])
    if len(matches) != 1:
        raise SystemExit("mod.elf must contain exactly one .cemod.bootstrap section")
    return matches[0]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", required=True, type=pathlib.Path)
    parser.add_argument("--readelf", required=True)
    parser.add_argument("--nm", required=True)
    parser.add_argument("--objdump", required=True)
    args = parser.parse_args()

    with zipfile.ZipFile(args.package) as archive:
        names = archive.namelist()
        allowed = {"manifest.json", "mod.elf"}
        signed = {"manifest.json", "mod.elf", "public_key.ed25519", "signature.ed25519"}
        if set(names) not in (allowed, signed) or len(names) != len(set(names)):
            raise SystemExit("package contains unexpected or duplicate entries")
        manifest = json.loads(archive.read("manifest.json"))
        elf = archive.read("mod.elf")
        if set(names) == signed and (len(archive.read("public_key.ed25519")) != 32 or
                                     len(archive.read("signature.ed25519")) != 64):
            raise SystemExit("invalid Ed25519 material")

    if manifest.get("package_version") != 1 or manifest.get("api_version") != 2 or \
            manifest.get("execution_mode") != "trusted_native":
        raise SystemExit("manifest is not a trusted_native ABI 2 package")
    if not manifest.get("title_ids") or any(key in manifest for key in ("memory", "cpu", "entrypoint")):
        raise SystemExit("trusted_native manifest fields are invalid")

    section = bootstrap_section(elf)
    if len(section) < 12:
        raise SystemExit("CMB1 header is truncated")
    magic, version, record_size, count = struct.unpack_from(">IHHI", section)
    if magic != 0x434D4231 or version != 1 or record_size != 24 or not 1 <= count <= 64 or \
            len(section) != 12 + count * record_size:
        raise SystemExit("CMB1 header or record count is invalid")
    for index in range(count):
        module_hash, target, expected, mask, handler, flags = struct.unpack_from(
            ">6I", section, 12 + index * record_size)
        if not module_hash or not target or not mask or flags != 0:
            raise SystemExit(f"CMB1 record {index} is invalid")

    with tempfile.TemporaryDirectory() as directory:
        elf_path = pathlib.Path(directory) / "mod.elf"
        elf_path.write_bytes(elf)
        header = output(args.readelf, "-h", str(elf_path))
        if "ELF32" not in header or "2's complement, big endian" not in header or \
                "PowerPC" not in header or "DYN (Shared object file)" not in header:
            raise SystemExit("mod.elf is not a 32-bit big-endian PowerPC ET_DYN image")
        program_headers = output(args.readelf, "-W", "-l", str(elf_path))
        for line in program_headers.splitlines():
            if line.lstrip().startswith("LOAD") and " RWE " in f" {line} ":
                raise SystemExit("mod.elf contains a writable-executable segment")
        undefined = output(args.nm, "-u", str(elf_path)).strip()
        if undefined:
            raise SystemExit(f"mod.elf contains undefined symbols:\n{undefined}")
        relocations = output(args.readelf, "-W", "-r", str(elf_path))
        found = set(re.findall(r"R_PPC_[A-Z0-9_]+", relocations))
        unsupported = found - ALLOWED_RELOCATIONS
        if unsupported:
            raise SystemExit(f"mod.elf uses unsupported relocations: {sorted(unsupported)}")
        symbols = output(args.nm, "-g", str(elf_path))
        if " entry" not in symbols and not symbols.rstrip().endswith(" entry"):
            raise SystemExit("mod.elf is missing the bootstrap entry symbol")
    print(f"Verified trusted_native package: {args.package}")


if __name__ == "__main__":
    main()
