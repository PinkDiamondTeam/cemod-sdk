#!/usr/bin/env python3
"""Strictly validate a raw Wii U plugin.wps image."""

import argparse
import pathlib

from cemodlib import CemodError, inspect_wups


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--wps", required=True, type=pathlib.Path)
    args = parser.parse_args()
    try:
        image = args.wps.read_bytes()
        result = inspect_wups(image)
    except (OSError, CemodError) as error:
        raise SystemExit(str(error)) from None
    print(f"Verified WUPS plugin {result['metadata']['name']!r}, ABI {result['wups_abi_version']}: {args.wps}")


if __name__ == "__main__":
    main()
