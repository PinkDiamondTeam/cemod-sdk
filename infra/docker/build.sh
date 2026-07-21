#!/bin/sh
# In-container build driver. Generic across cemod-sdk projects: it only
# assumes the project's Makefile includes cemod.mk and therefore exposes the
# clean / verify-wchar / package / print-project-config targets, plus
# whatever extra verification targets the project lists in
# CEMOD_EXTRA_VERIFY (e.g. "verify-cemuextend-sdk").
set -eu

jobs=${JOBS:-}
if [ -z "$jobs" ]; then
  jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
fi

powerpc-eabi-gcc --version
python3 --version
make clean
test -f /opt/devkitpro/mcwiiu-stdlib/.wchar16
make verify-wchar
for target in ${CEMOD_EXTRA_VERIFY:-}; do
  make "$target"
done
make -j"$jobs" package

project_name=$(make --no-print-directory print-project-config | sed -n 's/^PROJECT_NAME=//p')
echo "Trusted native package: out/dist/$project_name.cemod"
