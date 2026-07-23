#!/usr/bin/env python3
"""Inspect WUPS metadata, ABI descriptors, and inferred permissions."""

import argparse
import json
import pathlib

from cemodlib import CemodError, inspect_wups, validate_manifest


def permission_warnings(result: dict, manifest: dict | None) -> list[str]:
    if manifest is None:
        return []
    validate_manifest(manifest)
    declared = manifest.get("permissions", {})
    filesystem = declared.get("filesystem", {})
    inferred = result["required_permissions"]
    comparisons = {
        "native_memory": declared.get("native_memory", False),
        "function_patching": declared.get("function_patching", False),
        "physical_address_patching": declared.get("physical_address_patching", False),
        "filesystem_read": filesystem.get("read", False),
        "filesystem_write": filesystem.get("write", False),
        "network": declared.get("network", False),
        "mapped_memory": declared.get("mapped_memory", False),
        "notifications": declared.get("notifications", False),
        "content_redirection": declared.get("content_redirection", False),
    }
    warnings = [f"uses {name} but manifest does not declare it"
                for name, needed in inferred.items() if isinstance(needed, bool) and needed and not comparisons[name]]
    declared_modules = set(declared.get("modules", []))
    missing_modules = set(inferred["modules"]) - declared_modules
    if missing_modules:
        warnings.append(f"required modules are undeclared: {', '.join(sorted(missing_modules))}")
    return warnings


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--wps", required=True, type=pathlib.Path)
    parser.add_argument("--manifest", type=pathlib.Path)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    try:
        result = inspect_wups(args.wps.read_bytes())
        manifest = json.loads(args.manifest.read_text(encoding="utf-8")) if args.manifest else None
        result["permission_warnings"] = permission_warnings(result, manifest)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, CemodError) as error:
        raise SystemExit(str(error)) from None
    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
        return
    metadata = result["metadata"]
    print(f"Plugin: {metadata['name']}")
    print(f"WUPS ABI: {result['wups_abi_version']}")
    for key in ("version", "author", "license", "description", "buildtimestamp", "storage_id", "debug"):
        if key in metadata:
            print(f"Metadata {key}: {metadata[key]}")
    print("Hooks: " + (", ".join(item["name"] for item in result["hooks"]) or "none"))
    print("Replacements: " + (", ".join(
        f"{item['name']} ({'mandatory' if item['mandatory'] else 'optional'}, "
        f"process={item['process_target']}, physical=0x{item['physical_address']:08x}, "
        f"virtual=0x{item['virtual_address']:08x})" for item in result["replacements"]) or "none"))
    print("Imports: " + (", ".join(
        f"{item['module']}:{item['name']} [{item['kind']}]" for item in result["imports"]) or "none"))
    print("Exports: " + (", ".join(
        f"{item['name']} [{item['kind']}]" for item in result["exports"]) or "none"))
    print("Required modules: " + (", ".join(result["required_modules"]) or "none"))
    print("Process targets: " + (", ".join(result["process_targets"]) or "none"))
    print("Relocation types: " + (", ".join(map(str, result["relocation_types"])) or "none"))
    print(f"TLS: {'yes' if result['tls'] else 'no'}")
    print(f"Fixed-address patches: {'yes' if result['fixed_address_patches'] else 'no'}")
    print("Required permissions: " + json.dumps(result["required_permissions"], sort_keys=True))
    for warning in result["compatibility_warnings"] + result["permission_warnings"]:
        print(f"Warning: {warning}")


if __name__ == "__main__":
    main()
