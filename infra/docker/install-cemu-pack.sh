#!/bin/sh
# Install a built .cemod into a Cemu data directory's mods folder.
#
# Required environment: PROJECT_ROOT (consuming project root).
# Optional environment: CEMOD_NAME (otherwise read from config/project.mk).
set -eu

: "${PROJECT_ROOT:?PROJECT_ROOT must be set}"

if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [Cemu data directory]" >&2
  exit 2
fi

project_name=${CEMOD_NAME:-}
if [ -z "$project_name" ]; then
  project_config="$PROJECT_ROOT/config/project.mk"
  if [ ! -f "$project_config" ]; then
    echo "Project configuration is missing: $project_config" >&2
    exit 1
  fi
  project_name=$(sed -n 's/^[[:space:]]*PROJECT_NAME[[:space:]]*:=[[:space:]]*\([A-Za-z0-9._-][A-Za-z0-9._-]*\)[[:space:]]*$/\1/p' "$project_config" | head -n 1)
fi
if [ -z "$project_name" ]; then
  echo "CEMOD_NAME/PROJECT_NAME is missing." >&2
  exit 1
fi
case "$project_name" in
  *[!A-Za-z0-9._-]*)
    echo "Invalid CEMOD_NAME/PROJECT_NAME: $project_name" >&2
    exit 1
    ;;
esac

if [ -n "${1:-}" ]; then
  cemu_dir=${1%/}
else
  cemu_dir="${XDG_DATA_HOME:-$HOME/.local/share}/Cemu"
fi
if [ -z "$cemu_dir" ]; then
  echo "Cemu data directory must not be empty." >&2
  exit 1
fi

source_file="$PROJECT_ROOT/out/dist/$project_name.cemod"
if [ ! -s "$source_file" ]; then
  echo "Build artifact is missing: $source_file" >&2
  echo "Run ./docker-build.sh first." >&2
  exit 1
fi

mod_destination="$cemu_dir/cemuextend/mods"
installed_file="$mod_destination/$project_name.cemod"
staging_file="$mod_destination/.$project_name.cemod.tmp.$$"

cleanup_staging()
{
  rm -f "$staging_file"
}

mkdir -p "$mod_destination"
trap cleanup_staging EXIT
trap 'exit 1' HUP INT TERM
cp "$source_file" "$staging_file"
mv -f "$staging_file" "$installed_file"
trap - EXIT HUP INT TERM

echo "Installed $project_name cemod: $installed_file"
