# cemod-sdk

`cemod-sdk` is the build, validation, and packaging toolchain for CemuExtend
`.cemod` mods. It supports both CemuExtend trusted-native ELF payloads and Wii U
Plugin System (`.wps`) payloads without mixing packaging code into each mod
repository.

The SDK provides:

- a PowerPC ET_DYN link configuration for trusted-native `mod.elf` payloads;
- deterministic `.cemod` packaging and strict host-side verification;
- WPS/RPL validation and inspection;
- optional Ed25519 package signing;
- package-version-4 Web UI asset packaging; and
- reproducible Docker builders for the trusted-native and WUPS toolchains.

Package version 1 uses the legacy `mod.elf` layout. Versions 2 and 3 select
`mod.elf` or `plugin.wps` with an explicit payload descriptor. Version 4 adds
Web UI assets, which are covered when package signing is enabled. All
supported manifests use CemuExtend API version 2.

## Requirements

The exact requirements depend on the workflow:

- Python 3 is required by all packaging and verification tools.
- GNU Make, devkitPro/devkitPPC, and the SDK's codecave-safe toolchain are
  required for a local trusted-native ELF build.
- CMake 3.20 or newer can package an existing payload target.
- Docker with Docker Compose is recommended for reproducible builds and does
  not require a host devkitPro installation.
- OpenSSL is required only when creating or verifying Ed25519 signatures.

See [Getting started](docs/getting-started.md) for integration options and
[Docker builds](docs/docker-build.md) for the reproducible toolchain setup.

## GNU Make quick start

Set every `CEMOD_*` variable before including `cemod.mk`; GNU Make expands
source discovery and prerequisites while parsing the file.

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

Build, package, verify, and install the result with:

```sh
make package
make verify-package
make CEMU_DATA_DIR=/path/to/Cemu install
```

The package is written to `out/dist/example-mod.cemod`.

For a WUPS payload built by the consuming project, select the existing `.wps`
file before the include:

```make
CEMOD_PAYLOAD_FORMAT := wups
CEMOD_WPS            := $(PROJECT_ROOT)/platforms/wups/example-mod.wps
```

Then run `make package`, `make verify-wups`, or `make inspect-wups` as needed.

## CMake quick start

`CemodPackage.cmake` packages an existing CMake payload target; it does not
define how that target is compiled.

```cmake
include(/path/to/cemod-sdk/cmake/CemodPackage.cmake)

cemod_package(
  TARGET example_mod
  MANIFEST ${CMAKE_CURRENT_SOURCE_DIR}/manifest.json
  PAYLOAD_FORMAT wups
)
```

This adds an `example_mod_cemod` target and writes
`example_mod.cemod` in the current binary directory by default.

## Standalone tools

The Python tools can also package or inspect externally built payloads:

```sh
python3 tools/package_cemod.py \
  --manifest manifest.json \
  --wps build/example-mod.wps \
  --output build/example-mod.cemod

python3 tools/verify_cemod.py --package build/example-mod.cemod
python3 tools/verify_wups.py --wps build/example-mod.wps
python3 tools/inspect_wups.py \
  --wps build/example-mod.wps \
  --manifest manifest.json
```

Run the regression suite with:

```sh
python3 -m unittest discover -s tests -v
```

## Documentation

- [Getting started](docs/getting-started.md) — integration, payload workflows,
  installation, and standalone tools.
- [GNU Make configuration](docs/configuration.md) — all public variables,
  extension hooks, and targets.
- [Package format](docs/package-format.md) — manifests, payloads, signatures,
  Web UI assets, and validation limits.
- [Docker builds](docs/docker-build.md) — reproducible ELF and WUPS builders.
- [WUPS support design](docs/wups-support-design.md) — the low-level parser and
  runtime-boundary contract.
- [SDK conformance tests](tests/README.md) — test and fuzz corpus details.

`cemod-sdk` validates and packages guest code but does not execute it. WUPS
lifecycle calls, FunctionPatcher, WUMS loading, HLE services, and GUI
integration are CemuExtend runtime responsibilities. For the ABI 2 C++ client
used by a payload, see
[`libcemuextend`](https://github.com/CemuExtend/libcemuextend).
