#!/usr/bin/env python3
"""Small stdlib fuzz entry point for WPS, manifest, and .cemod inputs.

It is usable as a corpus smoke runner today and can be wrapped by an external
fuzzer without adding a Python dependency.  Every malformed input is a
normal rejection; unexpected exceptions are deliberately re-raised.
"""

from __future__ import annotations

import json
import pathlib
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from cemodlib import (CemodError, _reject_json_constant, inspect_wups, read_package,
                      validate_manifest)  # noqa: E402


def fuzz_one(data: bytes) -> None:
    try:
        inspect_wups(data)
    except CemodError:
        pass
    try:
        value = json.loads(data, parse_constant=_reject_json_constant)
        validate_manifest(value)
    except (CemodError, ValueError, TypeError, json.JSONDecodeError, UnicodeDecodeError, RecursionError):
        pass
    if data.startswith(b"PK"):
        with tempfile.NamedTemporaryFile(suffix=".cemod") as package:
            package.write(data)
            package.flush()
            try:
                read_package(pathlib.Path(package.name))
            except CemodError:
                pass


def main() -> None:
    for argument in sys.argv[1:]:
        fuzz_one(pathlib.Path(argument).read_bytes())


if __name__ == "__main__":
    main()
