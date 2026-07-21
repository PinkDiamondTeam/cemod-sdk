#!/bin/sh
# Copy a built .cemod into a Cemu data directory's mods folder.
#
# Required environment: PROJECT_ROOT (consuming project root, containing
# config/project.mk and out/dist/<PROJECT_NAME>.cemod).
set -eu

: "${PROJECT_ROOT:?PROJECT_ROOT must be set}"
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

source_file="$PROJECT_ROOT/out/dist/$project_name.cemod"
if [ ! -s "$source_file" ]; then
  echo "Build artifact is missing: $source_file" >&2
  echo "Run ./docker-build.sh first." >&2
  exit 1
fi

if [ -n "${1:-}" ]; then
  cemu_dir=${1%/}
else
  cemu_dir="${XDG_DATA_HOME:-$HOME/.local/share}/Cemu"
fi

mod_destination="$cemu_dir/cemuextend/mods"
installed_file="$mod_destination/$project_name.cemod"

mkdir -p "$mod_destination"
cp "$source_file" "$installed_file"

echo "Installed $project_name cemod: $installed_file"
