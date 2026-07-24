#!/bin/sh
# Host-side Docker orchestrator for the WUPS payload build, shared by every
# cemod-sdk project. Mirrors docker-build.sh's role for the ELF path, but
# for the wups-builder service defined in the project's own
# compose.wups.yaml (see README.md's WUPS Docker build section).
#
# Required environment (normally exported by the project's
# docker-build-wups.sh wrapper):
#   PROJECT_ROOT          absolute path to the consuming project (compose context)
#   CEMOD_SDK_ROOT        absolute path to this SDK checkout
#   DEVKITPPC_ARCHIVE     path, relative to PROJECT_ROOT, to the vendored
#                         devkitPPC .pkg.tar.zst (the wups-builder image is
#                         layered on top of the ELF `builder` image, which
#                         needs this to build)
#   DEVKITPPC_SHA256      expected sha256 of that archive
#
# Optional environment:
#   CEMOD_PREBUILD_CHECK  path to an executable run before Docker starts (see
#                         docker-build.sh)
set -eu

: "${PROJECT_ROOT:?PROJECT_ROOT must be set}"
: "${CEMOD_SDK_ROOT:?CEMOD_SDK_ROOT must be set}"
: "${DEVKITPPC_ARCHIVE:?DEVKITPPC_ARCHIVE must be set}"
: "${DEVKITPPC_SHA256:?DEVKITPPC_SHA256 must be set}"

cd "$PROJECT_ROOT"

command -v docker >/dev/null 2>&1 || { echo "Docker is required." >&2; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "Docker Compose is required." >&2; exit 1; }

if [ -n "${CEMOD_PREBUILD_CHECK:-}" ]; then
  "$CEMOD_PREBUILD_CHECK"
fi

devkit_archive="$PROJECT_ROOT/$DEVKITPPC_ARCHIVE"
if [ ! -f "$devkit_archive" ]; then
  echo "Required devkitPPC archive is missing: $devkit_archive" >&2
  exit 1
fi
if ! echo "$DEVKITPPC_SHA256  $devkit_archive" | sha256sum -c - >/dev/null; then
  echo "Invalid devkitPPC archive checksum: $devkit_archive" >&2
  exit 1
fi

export HOST_UID="$(id -u)"
export HOST_GID="$(id -g)"
export CEMOD_SDK_ROOT
export DEVKITPPC_ARCHIVE
export DEVKITPPC_SHA256

docker compose build builder
docker compose -f compose.wups.yaml build wups-builder
docker compose -f compose.wups.yaml run --rm wups-builder

if [ "${1:-}" = "--install" ]; then
  if [ "$#" -gt 2 ]; then
    echo "Usage: $0 [--install [Cemu data directory]]" >&2
    exit 2
  fi
  sh "$CEMOD_SDK_ROOT/infra/docker/install-cemu-pack.sh" "${2:-}"
fi
