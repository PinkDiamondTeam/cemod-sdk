#!/usr/bin/env python3
"""Build a deterministic, optionally signed .cemod package."""

import argparse
import json
import pathlib
import subprocess
import tempfile
import zipfile

from cemodlib import CemodError, canonical_signature_digest, inspect_wups, validate_manifest


ED25519_DER_PREFIX = bytes.fromhex("302a300506032b6570032100")


def read_file(path: pathlib.Path, description: str) -> bytes:
    try:
        return path.read_bytes()
    except OSError as error:
        raise CemodError(f"cannot read {description}: {error}") from None


def sign(entries: dict[str, bytes], private_key: pathlib.Path) -> tuple[bytes, bytes]:
    try:
        public_der = subprocess.run(
            ["openssl", "pkey", "-in", str(private_key), "-pubout", "-outform", "DER"],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout
    except (OSError, subprocess.CalledProcessError) as error:
        detail = getattr(error, "stderr", b"").decode("utf-8", "replace").strip()
        raise CemodError(f"cannot derive Ed25519 public key: {detail or error}") from None
    if not public_der.startswith(ED25519_DER_PREFIX) or len(public_der) != len(ED25519_DER_PREFIX) + 32:
        raise CemodError("private key is not an Ed25519 key")
    public_key = public_der[len(ED25519_DER_PREFIX):]
    signed_entries = dict(entries)
    signed_entries["public_key.ed25519"] = public_key
    digest = canonical_signature_digest(signed_entries)
    with tempfile.NamedTemporaryFile() as digest_file:
        digest_file.write(digest)
        digest_file.flush()
        try:
            signature = subprocess.run(
                ["openssl", "pkeyutl", "-sign", "-rawin", "-inkey", str(private_key),
                 "-in", digest_file.name], check=True, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE).stdout
        except (OSError, subprocess.CalledProcessError) as error:
            detail = getattr(error, "stderr", b"").decode("utf-8", "replace").strip()
            raise CemodError(f"cannot sign package: {detail or error}") from None
    if len(signature) != 64:
        raise CemodError("OpenSSL returned an invalid Ed25519 signature")
    return public_key, signature


def verify_detached(entries: dict[str, bytes]) -> None:
    public_der = ED25519_DER_PREFIX + entries["public_key.ed25519"]
    digest = canonical_signature_digest(entries)
    with tempfile.TemporaryDirectory() as directory:
        root = pathlib.Path(directory)
        public_path, signature_path, digest_path = (
            root / "public.der", root / "signature.bin", root / "digest.bin")
        public_path.write_bytes(public_der)
        signature_path.write_bytes(entries["signature.ed25519"])
        digest_path.write_bytes(digest)
        try:
            subprocess.run([
                "openssl", "pkeyutl", "-verify", "-rawin", "-pubin", "-keyform", "DER",
                "-inkey", str(public_path), "-sigfile", str(signature_path), "-in", str(digest_path),
            ], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        except (OSError, subprocess.CalledProcessError):
            raise CemodError("detached Ed25519 signature does not match the package inputs") from None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True, type=pathlib.Path)
    payload = parser.add_mutually_exclusive_group(required=True)
    payload.add_argument("--elf", type=pathlib.Path, help="compatibility alias for --payload-format cemod_elf")
    payload.add_argument("--wps", type=pathlib.Path, help="compatibility alias for --payload-format wups")
    payload.add_argument("--payload", type=pathlib.Path)
    parser.add_argument("--payload-format", choices=("cemod_elf", "wups"))
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--private-key", type=pathlib.Path, help="Ed25519 PEM private key")
    parser.add_argument("--public-key", type=pathlib.Path, help="raw 32-byte Ed25519 key")
    parser.add_argument("--signature", type=pathlib.Path, help="raw 64-byte detached signature")
    args = parser.parse_args()

    try:
        manifest_raw = read_file(args.manifest, "manifest")
        try:
            manifest = json.loads(manifest_raw)
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise CemodError(f"manifest is malformed: {error}") from None
        manifest_format, manifest_path = validate_manifest(manifest)
        if args.elf:
            selected_format, payload_path = "cemod_elf", args.elf
        elif args.wps:
            selected_format, payload_path = "wups", args.wps
        else:
            if not args.payload_format:
                raise CemodError("--payload requires --payload-format")
            selected_format, payload_path = args.payload_format, args.payload
        if args.payload_format and args.payload_format != selected_format:
            raise CemodError("payload option and --payload-format disagree")
        if (selected_format, {"cemod_elf": "mod.elf", "wups": "plugin.wps"}[selected_format]) != \
                (manifest_format, manifest_path):
            raise CemodError("manifest payload descriptor does not match the selected payload")
        payload_data = read_file(payload_path, "payload")
        if not payload_data:
            raise CemodError("payload is empty")
        if selected_format == "wups":
            inspect_wups(payload_data)

        encoded_manifest = (json.dumps(manifest, ensure_ascii=False, sort_keys=True,
                                       separators=(",", ":")) + "\n").encode("utf-8")
        entries = {"manifest.json": encoded_manifest, manifest_path: payload_data}
        detached = args.public_key is not None or args.signature is not None
        if args.private_key and detached:
            raise CemodError("--private-key cannot be combined with detached signature options")
        if (args.public_key is None) != (args.signature is None):
            raise CemodError("--public-key and --signature must be supplied together")
        if args.private_key:
            public_key, signature = sign(entries, args.private_key)
            entries["public_key.ed25519"] = public_key
            entries["signature.ed25519"] = signature
        elif args.public_key:
            public_key = read_file(args.public_key, "public key")
            signature = read_file(args.signature, "signature")
            if len(public_key) != 32 or len(signature) != 64:
                raise CemodError("Ed25519 public key/signature must be raw 32/64-byte files")
            entries["public_key.ed25519"] = public_key
            entries["signature.ed25519"] = signature
            verify_detached(entries)

        args.output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=args.output.parent, delete=False) as temporary:
            temporary_path = pathlib.Path(temporary.name)
        try:
            with zipfile.ZipFile(temporary_path, "w", compression=zipfile.ZIP_DEFLATED,
                                 compresslevel=9) as archive:
                for name, data in entries.items():
                    info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
                    info.compress_type = zipfile.ZIP_DEFLATED
                    info.external_attr = 0o100644 << 16
                    archive.writestr(info, data)
            temporary_path.replace(args.output)
            args.output.chmod(0o644)
        finally:
            temporary_path.unlink(missing_ok=True)
    except CemodError as error:
        raise SystemExit(str(error)) from None


if __name__ == "__main__":
    main()
