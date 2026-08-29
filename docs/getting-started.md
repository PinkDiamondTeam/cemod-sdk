# Getting started

This guide integrates `cemod-sdk` into a mod repository, builds or selects a
payload, creates a `.cemod` archive, and installs it into CemuExtend.

## Choose a payload

A `.cemod` package contains exactly one executable payload:

| Format | Archive entry | Typical use |
| --- | --- | --- |
| `cemod_elf` | `mod.elf` | A CemuExtend trusted-native ELF with a project-owned CMB1 bootstrap table |
| `wups` | `plugin.wps` | A WUPS plugin built by the consuming project |

The payload format is independent of `execution_mode`. WUPS payloads require
`trusted_native`; they are never a separate execution mode.

## Add the SDK

The usual layout vendors the SDK as a submodule:

```text
example-mod/
├── Makefile
├── manifest.json
├── src/
└── third_party/
    └── cemod-sdk/
```

The SDK may live elsewhere if `CEMOD_SDK_ROOT` points to its absolute or
project-relative location.

## Trusted-native ELF workflow

The SDK supplies the compilation flags, short-`wchar_t` library selection,
link script, relocation normalization, packaging, and verification steps. The
mod remains responsible for its source code, game-specific hooks, manifest,
and `.cemod.bootstrap` section.

Create a Makefile with all configuration above the include:

```make
MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
PROJECT_ROOT := $(patsubst %/,%,$(MAKEFILE_DIR))

CEMOD_SDK_ROOT ?= $(PROJECT_ROOT)/third_party/cemod-sdk
CEMOD_NAME      := example-mod
CEMOD_SOURCES   := src
CEMOD_INCLUDES  := include
CEMOD_MANIFEST  := $(PROJECT_ROOT)/manifest.json

include $(CEMOD_SDK_ROOT)/cemod.mk
```

The trusted-native path expects `DEVKITPRO` and `DEVKITPPC`, plus the
codecave-safe GCC and 16-bit `wchar_t` standard library described in
[Docker builds](docker-build.md). `USE_SYSTEM_STDLIB=1` is only a linker
diagnostic: `verify-wchar` rejects that incompatible standard library, and the
Docker build runs this check before packaging. Do not distribute an output
built with `USE_SYSTEM_STDLIB=1`.

Build and package with:

```sh
make package
```

The default artifacts are:

```text
out/build/example-mod/example-mod.elf
out/build/example-mod/example-mod_dbg.elf
out/dist/example-mod.cemod
```

The project must provide the CMB1 bootstrap records expected by
`config/link.ld`. Those records contain game-specific hook addresses and do
not belong in the reusable SDK.

## WUPS workflow

The consuming project owns the rule that produces the `.wps`. Configure the
SDK to validate and package that output:

```make
CEMOD_PAYLOAD_FORMAT := wups
CEMOD_WPS            := $(PROJECT_ROOT)/platforms/wups/example-mod.wps
```

The manifest must select the same payload:

```json
{
  "package_version": 2,
  "api_version": 2,
  "execution_mode": "trusted_native",
  "mod_id": "example-mod",
  "title_ids": ["0005000012345678"],
  "requested_permissions": [],
  "payload": {"format": "wups", "path": "plugin.wps"}
}
```

Useful commands are:

```sh
make CEMOD_PAYLOAD_FORMAT=wups package
make CEMOD_PAYLOAD_FORMAT=wups verify-wups
make CEMOD_PAYLOAD_FORMAT=wups inspect-wups
```

`verify-wups` performs strict binary validation. `inspect-wups` also reports
metadata, hooks, imports, exports, relocations, process targets, and inferred
permission use, and compares the result with the selected manifest.

Use the dedicated `wups-builder` Docker stage when compiling against libwut
and libwups. The trusted-native short-`wchar_t` runtime and the WUPS runtime
must not be mixed.

## Package an existing CMake target

Include the helper after defining a target whose target file is already a
valid `plugin.wps` or `mod.elf` payload:

```cmake
include(/path/to/cemod-sdk/cmake/CemodPackage.cmake)
cemod_package(
  TARGET example_mod
  MANIFEST ${CMAKE_CURRENT_SOURCE_DIR}/manifest.json
  PAYLOAD_FORMAT wups
  OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/example-mod.cemod
)
```

Optional `UI_DIR` and `PRIVATE_KEY` arguments enable package-version-4 assets
and Ed25519 signing. The helper creates an `<target>_cemod` target that is part
of the default build.

## Use the tools directly

Create a package from an existing trusted-native ELF:

```sh
python3 /path/to/cemod-sdk/tools/package_cemod.py \
  --manifest manifest.json \
  --elf build/mod.elf \
  --output build/example-mod.cemod
```

Or from an existing WPS payload:

```sh
python3 /path/to/cemod-sdk/tools/package_cemod.py \
  --manifest manifest.json \
  --wps build/plugin.wps \
  --output build/example-mod.cemod
```

The general `--payload` form requires an explicit `--payload-format`:

```sh
python3 tools/package_cemod.py \
  --manifest manifest.json \
  --payload build/plugin.wps \
  --payload-format wups \
  --output build/example-mod.cemod
```

Packaging is transactional: the output is replaced only after the manifest,
payload, optional UI tree, and optional signature all validate.

## Verify and install

Verify a WPS package with:

```sh
python3 tools/verify_cemod.py --package build/example-mod.cemod
```

Trusted-native ELF verification additionally needs the PowerPC binutils used
to inspect the payload:

```sh
python3 tools/verify_cemod.py \
  --package build/example-mod.cemod \
  --readelf powerpc-eabi-readelf \
  --nm powerpc-eabi-nm
```

For Make-based projects, install the selected package with:

```sh
make CEMU_DATA_DIR=/path/to/Cemu install
```

This copies only the current package to:

```text
<CEMU_DATA_DIR>/cemuextend/mods/<CEMOD_NAME>.cemod
```

For the complete Make variable and target reference, see
[GNU Make configuration](configuration.md). Manifest and signing details are
in [Package format](package-format.md).
