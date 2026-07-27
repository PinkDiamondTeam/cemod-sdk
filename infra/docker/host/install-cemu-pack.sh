#!/bin/sh
# Copy one just-built .cemod package into a Cemu data directory's mods
# folder. Installs exactly out/dist/<PROJECT_NAME><suffix>.cemod -- suffix
# is "" for the cemod_elf payload (./docker-build.sh) or "-wups" for the
# WUPS payload (./docker-build.sh --wups). Never touches any other package
# that might already be sitting in out/dist.
#
# Required environment: PROJECT_ROOT (consuming project root, containing
# config/project.mk and out/dist/).
# Usage: install-cemu-pack.sh <suffix> [Cemu data directory]
set -eu

: "${PROJECT_ROOT:?PROJECT_ROOT must be set}"
suffix="${1?suffix must be given (\"\" for cemod_elf, \"-wups\" for wups)}"

project_config="$PROJECT_ROOT/config/project.mk"
if [ ! -f "$project_config" ]; then
  echo "Project configuration is missing: $project_config" >&2
  exit 1
fi

project_name=$(sed -n 's/^[[:space:]]*PROJECT_NAME[[:space:]]*:=[[:space:]]*\([A-Za-z0-9._-][A-Za-z0-9._-]*\)[[:space:]]*$/\1/p' "$project_config" | head -n 1)
if [ -z "$project_name" ]; then
  echo "PROJECT_NAME is missing or invalid in: $project_config" >&2
  exit 1
fi

if [ -n "${2:-}" ]; then
  cemu_dir=${2%/}
else
  cemu_dir="${XDG_DATA_HOME:-$HOME/.local/share}/Cemu"
fi

source_file="$PROJECT_ROOT/out/dist/$project_name$suffix.cemod"
if [ ! -s "$source_file" ]; then
  echo "Build artifact is missing: $source_file" >&2
  exit 1
fi

mod_destination="$cemu_dir/cemuextend/mods"
mkdir -p "$mod_destination"
installed_file="$mod_destination/$project_name$suffix.cemod"
cp "$source_file" "$installed_file"
echo "Installed $project_name$suffix cemod: $installed_file"
