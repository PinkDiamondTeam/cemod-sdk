#!/usr/bin/env python3
"""Verify the container, signature, manifest, and selected payload."""

import argparse
import pathlib
import re
import struct
import subprocess
import tempfile

from cemodlib import CemodError, canonical_signature_digest, read_package


ALLOWED_RELOCATIONS = {
    "R_PPC_NONE", "R_PPC_ADDR32", "R_PPC_ADDR16_LO", "R_PPC_ADDR16_HI",
    "R_PPC_ADDR16_HA", "R_PPC_REL24", "R_PPC_RELATIVE", "R_PPC_REL32",
}
ED25519_DER_PREFIX = bytes.fromhex("302a300506032b6570032100")


def output(*command: str) -> str:
    try:
        return subprocess.run(command, check=True, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout
    except (OSError, subprocess.CalledProcessError) as error:
        detail = getattr(error, "stderr", "").strip()
        raise CemodError(f"tool failed: {' '.join(command)}: {detail or error}") from None


def bootstrap_section(elf: bytes) -> bytes:
    if len(elf) < 52 or elf[:7] != b"\x7fELF\x01\x02\x01" or struct.unpack_from(">HHI", elf, 16) != (3, 20, 1):
        raise CemodError("mod.elf is not a 32-bit big-endian PowerPC ET_DYN image")
    section_offset = struct.unpack_from(">I", elf, 32)[0]
    entry_size, count, names_index = struct.unpack_from(">HHH", elf, 46)
    if entry_size < 40 or not count or names_index >= count or \
            section_offset + entry_size * count > len(elf):
        raise CemodError("mod.elf section table is invalid")

    def section(index: int) -> tuple[int, ...]:
        return struct.unpack_from(">10I", elf, section_offset + index * entry_size)

    names = section(names_index)
    names_offset, names_size = names[4], names[5]
    if names_offset + names_size > len(elf):
        raise CemodError("mod.elf section-name table is invalid")
    matches = []
    for index in range(count):
        current = section(index)
        name_offset = current[0]
        if name_offset >= names_size:
            continue
        end = elf.find(b"\0", names_offset + name_offset, names_offset + names_size)
        if end < 0:
            continue
        if elf[names_offset + name_offset:end] == b".cemod.bootstrap":
            file_offset, size = current[4], current[5]
            if file_offset + size > len(elf) or not current[2] & 2:
                raise CemodError(".cemod.bootstrap is not a loadable section")
            matches.append(elf[file_offset:file_offset + size])
    if len(matches) != 1:
        raise CemodError("mod.elf must contain exactly one .cemod.bootstrap section")
    return matches[0]


def verify_signature(entries: dict[str, bytes]) -> None:
    if "signature.ed25519" not in entries:
        return
    public_der = ED25519_DER_PREFIX + entries["public_key.ed25519"]
    digest = canonical_signature_digest(entries)
    with tempfile.TemporaryDirectory() as directory:
        root = pathlib.Path(directory)
        public_path = root / "public.der"
        signature_path = root / "signature.bin"
        digest_path = root / "digest.bin"
        public_path.write_bytes(public_der)
        signature_path.write_bytes(entries["signature.ed25519"])
        digest_path.write_bytes(digest)
        try:
            subprocess.run([
                "openssl", "pkeyutl", "-verify", "-rawin", "-pubin", "-keyform", "DER",
                "-inkey", str(public_path), "-sigfile", str(signature_path), "-in", str(digest_path),
            ], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        except (OSError, subprocess.CalledProcessError):
            raise CemodError("package Ed25519 signature verification failed") from None


def verify_elf(elf: bytes, readelf: str | None, nm: str | None) -> None:
    section = bootstrap_section(elf)
    if len(section) < 12:
        raise CemodError("CMB1 header is truncated")
    magic, version, record_size, count = struct.unpack_from(">IHHI", section)
    if magic != 0x434D4231 or version != 1 or record_size != 24 or not 1 <= count <= 64 or \
            len(section) != 12 + count * record_size:
        raise CemodError("CMB1 header or record count is invalid")
    for index in range(count):
        module_hash, target, expected, mask, handler, flags = struct.unpack_from(
            ">6I", section, 12 + index * record_size)
        if not module_hash or not target or not mask or flags != 0:
            raise CemodError(f"CMB1 record {index} is invalid")
    if not readelf or not nm:
        raise CemodError("--readelf and --nm are required to verify cemod_elf payloads")
    with tempfile.TemporaryDirectory() as directory:
        elf_path = pathlib.Path(directory) / "mod.elf"
        elf_path.write_bytes(elf)
        header = output(readelf, "-h", str(elf_path))
        if "ELF32" not in header or "2's complement, big endian" not in header or \
                "PowerPC" not in header or "DYN (Shared object file)" not in header:
            raise CemodError("mod.elf is not a 32-bit big-endian PowerPC ET_DYN image")
        program_headers = output(readelf, "-W", "-l", str(elf_path))
        for line in program_headers.splitlines():
            if line.lstrip().startswith("LOAD") and " RWE " in f" {line} ":
                raise CemodError("mod.elf contains a writable-executable segment")
        undefined = output(nm, "-u", str(elf_path)).strip()
        if undefined:
            raise CemodError(f"mod.elf contains undefined symbols:\n{undefined}")
        relocations = output(readelf, "-W", "-r", str(elf_path))
        unsupported = set(re.findall(r"R_PPC_[A-Z0-9_]+", relocations)) - ALLOWED_RELOCATIONS
        if unsupported:
            raise CemodError(f"mod.elf uses unsupported relocations: {sorted(unsupported)}")
        symbols = output(nm, "-g", str(elf_path))
        if " entry" not in symbols and not symbols.rstrip().endswith(" entry"):
            raise CemodError("mod.elf is missing the bootstrap entry symbol")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", required=True, type=pathlib.Path)
    parser.add_argument("--readelf")
    parser.add_argument("--nm")
    parser.add_argument("--objdump", help="retained for command-line compatibility")
    args = parser.parse_args()
    try:
        package = read_package(args.package)
        verify_signature(package.entries)
        if package.payload_format == "cemod_elf":
            verify_elf(package.payload, args.readelf, args.nm)
        metadata = f" ({package.wups['metadata']['name']}, ABI {package.wups['wups_abi_version']})" \
            if package.wups else ""
        print(f"Verified {package.payload_format} package{metadata}: {args.package}")
    except CemodError as error:
        raise SystemExit(str(error)) from None


if __name__ == "__main__":
    main()
