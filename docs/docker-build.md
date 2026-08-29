# Docker builds

The Docker workflow provides reproducible build environments without a host
devkitPro checkout. It intentionally uses different toolchains for a
trusted-native ELF and a WUPS plugin.

## Architecture

`infra/docker/image/Dockerfile` exposes two stages:

| Stage | Toolchain | Output |
| --- | --- | --- |
| `builder` | Pinned devkitPPC plus the SDK-built codecave-safe GCC and 16-bit `wchar_t` newlib/libstdc++ | Trusted-native `mod.elf` package |
| `wups-builder` | Stock devkitPro runtime matching libwut/libwups, plus the consuming project's WiiUPluginSystem | `plugin.wps` package |

These runtimes are not interchangeable. In particular, a WUPS plugin must be
compiled against the same newlib/devkitPro ABI as the libwut and libwups
archives it links.

The Docker files are grouped by where they run:

```text
infra/docker/
├── host/       # host orchestrator and installer
├── image/      # Dockerfile, stdlib build script, and patch
└── container/  # in-container ELF and WUPS build drivers
```

## Project requirements

A consuming project supplies:

- Docker with the Compose plugin;
- a `compose.yaml` with `builder` and `wups-builder` services;
- a vendored devkitPPC archive and SHA-256 (the current host orchestrator
  verifies this input for either path, while the trusted-native image consumes
  it);
- a Makefile that includes `cemod.mk`;
- for WUPS, `third_party/toolchains/WiiUPluginSystem` and a platform Makefile
  producing release/debug `.wps` files and an `.elf`; and
- a writable bind mount for the project plus a read-only bind mount for the
  SDK at the same absolute path inside the container.

The Docker build context must be the consuming project root. A named
additional context called `sdk` must point to `cemod-sdk/infra/docker/image`
so the Dockerfile can copy the SDK's stdlib build inputs.

## Compose example

The following shows the required structure. Project-specific environment and
volume entries may be added as needed.

```yaml
services:
  builder:
    build:
      context: .
      dockerfile: ${CEMOD_SDK_ROOT}/infra/docker/image/Dockerfile
      target: builder
      additional_contexts:
        sdk: ${CEMOD_SDK_ROOT}/infra/docker/image
      args:
        DEVKITPPC_ARCHIVE: ${DEVKITPPC_ARCHIVE}
        DEVKITPPC_SHA256: ${DEVKITPPC_SHA256}
    working_dir: /project
    user: "${HOST_UID}:${HOST_GID}"
    environment:
      CEMOD_SDK_ROOT: ${CEMOD_SDK_ROOT}
      CEMOD_EXTRA_VERIFY: ${CEMOD_EXTRA_VERIFY:-}
    volumes:
      - .:/project
      - ${CEMOD_SDK_ROOT}:${CEMOD_SDK_ROOT}:ro

  wups-builder:
    profiles: ["wups"]
    build:
      context: .
      dockerfile: ${CEMOD_SDK_ROOT}/infra/docker/image/Dockerfile
      target: wups-builder
      additional_contexts:
        sdk: ${CEMOD_SDK_ROOT}/infra/docker/image
    working_dir: /project
    user: "${HOST_UID}:${HOST_GID}"
    environment:
      CEMOD_SDK_ROOT: ${CEMOD_SDK_ROOT}
    volumes:
      - .:/project
      - ${CEMOD_SDK_ROOT}:${CEMOD_SDK_ROOT}:ro
```

Compose variable interpolation and absolute bind-mount paths vary by host.
Run `docker compose config` in the consuming project to inspect the resolved
configuration before building.

## Required host variables

The shared host orchestrator reads:

| Variable | Required | Purpose |
| --- | --- | --- |
| `PROJECT_ROOT` | yes | Absolute consuming-project root and Compose context |
| `CEMOD_SDK_ROOT` | yes | Absolute SDK checkout path |
| `DEVKITPPC_ARCHIVE` | yes | Archive path relative to `PROJECT_ROOT` |
| `DEVKITPPC_SHA256` | yes | Expected archive SHA-256 |
| `CEMOD_PREBUILD_CHECK` | no | Executable project preflight check run before Docker |
| `CEMOD_EXTRA_VERIFY` | no | Space-separated Make targets run before ELF packaging |
| `CEMOD_DOCKER_ARGS` | no | Extra arguments forwarded by the Make target to the host orchestrator; normally managed by `docker-install` |

`CEMOD_EXTRA_VERIFY` applies only to the trusted-native path. The host script
verifies the vendored archive before invoking Docker.

## Build commands

If the project exposes the `cemod.mk` targets:

```sh
make docker-build
make CEMOD_PAYLOAD_FORMAT=wups docker-build
```

The equivalent shared-script invocations are:

```sh
sh "$CEMOD_SDK_ROOT/infra/docker/host/docker-build.sh"
sh "$CEMOD_SDK_ROOT/infra/docker/host/docker-build.sh" --wups
```

The ELF driver verifies the 16-bit `wchar_t` standard library, runs optional
project verification targets, and executes `make package`. Set
`CEMOD_CLEAN_BUILD=1` in the container environment to clean `out/` first.

The WUPS driver:

1. verifies that the stock WUPS toolchain is present and the short-`wchar_t`
   prefixes are absent;
2. obtains `CEMOD_PAYLOAD_SOURCE` from `make print-project-config`;
3. builds its containing platform directory;
4. validates the release `.wps`, debug `.wps`, and intermediate `.elf`;
5. packages the release `.wps`; and
6. copies all WUPS artifacts to `out/wups/`.

Set `CEMOD_WUPS_CLEAN_BUILD=1` to clean the WUPS platform directory first.
Both container drivers honor `JOBS`; otherwise they use the detected processor
count.

## Install the result

Build and install with:

```sh
make CEMU_DATA_DIR=/path/to/Cemu docker-install
make CEMOD_PAYLOAD_FORMAT=wups CEMU_DATA_DIR=/path/to/Cemu docker-install
```

The shared installer copies only the package produced for the selected path;
it does not scan or install unrelated files from `out/dist`. When invoked
directly with no Cemu directory, it defaults to
`${XDG_DATA_HOME:-$HOME/.local/share}/Cemu`.

The host installer expects the consuming project to define a valid
`PROJECT_NAME := ...` in `config/project.mk`, because it uses that value to
select the exact output filename.
