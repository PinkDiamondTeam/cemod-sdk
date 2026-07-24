#!/bin/sh
# Copy built .cemod package(s) into a Cemu data directory's mods folder.
# Installs out/dist/<PROJECT_NAME>.cemod (cemod_elf payload, from
# ./docker-build.sh) and/or out/dist/<PROJECT_NAME>-wups.cemod (wups
# payload, from ./docker-build-wups.sh) -- whichever have been built. At
# least one must exist.
#
# Required environment: PROJECT_ROOT (consuming project root, containing
# config/project.mk and out/dist/).
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

if [ -n "${1:-}" ]; then
  cemu_dir=${1%/}
else
  cemu_dir="${XDG_DATA_HOME:-$HOME/.local/share}/Cemu"
fi

mod_destination="$cemu_dir/cemuextend/mods"
installed_any=0

for suffix in "" "-wups"; do
  source_file="$PROJECT_ROOT/out/dist/$project_name$suffix.cemod"
  if [ -s "$source_file" ]; then
    mkdir -p "$mod_destination"
    installed_file="$mod_destination/$project_name$suffix.cemod"
    cp "$source_file" "$installed_file"
    echo "Installed $project_name$suffix cemod: $installed_file"
    installed_any=1
  fi
done

if [ "$installed_any" -eq 0 ]; then
  echo "Build artifacts are missing: $PROJECT_ROOT/out/dist/$project_name.cemod / $project_name-wups.cemod" >&2
  echo "Run ./docker-build.sh and/or ./docker-build-wups.sh first." >&2
  exit 1
fi
