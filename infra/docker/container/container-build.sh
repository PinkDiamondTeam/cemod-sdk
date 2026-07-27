#!/bin/sh
# In-container build driver. Generic across cemod-sdk projects: it only
# assumes the project's Makefile includes cemod.mk and therefore exposes the
# verify-wchar / package / print-project-config targets, plus
# whatever extra verification targets the project lists in
# CEMOD_EXTRA_VERIFY (e.g. "verify-cemuextend-sdk").
#
# Build products live in the bind-mounted project tree, so they survive the
# disposable `docker compose run --rm` container and can be reused by make.
# Set CEMOD_CLEAN_BUILD=1 to explicitly discard them before building.
set -eu

jobs=${JOBS:-}
if [ -z "$jobs" ]; then
  jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
fi

powerpc-eabi-gcc --version
python3 --version
if [ "${CEMOD_CLEAN_BUILD:-0}" = "1" ]; then
  make clean
fi
test -f /opt/devkitpro/mcwiiu-stdlib/.wchar16
make verify-wchar
for target in ${CEMOD_EXTRA_VERIFY:-}; do
  make "$target"
done
make -j"$jobs" package

project_name=$(make --no-print-directory print-project-config | sed -n 's/^PROJECT_NAME=//p')
echo "Trusted native package: out/dist/$project_name.cemod"
