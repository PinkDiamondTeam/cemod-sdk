#!/usr/bin/env python3
import argparse
import json
import pathlib
import tempfile
import zipfile


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True, type=pathlib.Path)
    parser.add_argument("--elf", required=True, type=pathlib.Path)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--public-key", type=pathlib.Path)
    parser.add_argument("--signature", type=pathlib.Path)
    args = parser.parse_args()

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    if (manifest.get("package_version") != 1 or manifest.get("api_version") != 2 or
            manifest.get("execution_mode") != "trusted_native"):
        raise SystemExit("manifest must describe a package_version 1 trusted_native ABI 2 Mod")
    if any(name in manifest for name in ("memory", "cpu", "entrypoint")):
        raise SystemExit("trusted_native manifest contains isolated-only fields")
    encoded_manifest = (json.dumps(manifest, ensure_ascii=False, sort_keys=True,
                                   separators=(",", ":")) + "\n").encode("utf-8")
    elf = args.elf.read_bytes()
    if not elf:
        raise SystemExit("PPC ELF is empty")

    entries = [("manifest.json", encoded_manifest), ("mod.elf", elf)]
    if (args.public_key is None) != (args.signature is None):
        raise SystemExit("--public-key and --signature must be supplied together")
    if args.public_key:
        public_key = args.public_key.read_bytes()
        signature = args.signature.read_bytes()
        if len(public_key) != 32 or len(signature) != 64:
            raise SystemExit("Ed25519 public key/signature must be raw 32/64-byte files")
        entries.extend((("public_key.ed25519", public_key),
                        ("signature.ed25519", signature)))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=args.output.parent, delete=False) as temporary:
        temporary_path = pathlib.Path(temporary.name)
    try:
        with zipfile.ZipFile(temporary_path, "w", compression=zipfile.ZIP_DEFLATED,
                             compresslevel=9) as archive:
            for name, data in entries:
                info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o100644 << 16
                archive.writestr(info, data)
        temporary_path.replace(args.output)
        args.output.chmod(0o644)
    finally:
        temporary_path.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
