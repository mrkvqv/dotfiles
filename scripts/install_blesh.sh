#!/bin/bash
# Install one pinned upstream ble.sh release outside the configuration repository.
set -euo pipefail

destination="$HOME/.local/share/blesh"
if [[ -f "$destination/ble.sh" ]]; then
    printf '%s\n' 'ble.sh is already installed; no second copy was created.'
    exit 0
fi
task_directory=$(mktemp -d "${TMPDIR:-/tmp}/install-blesh.XXXXXX")
trap 'rm -rf "$task_directory"' EXIT
curl -fsSL --retry 2 \
    https://github.com/akinomyoga/ble.sh/releases/download/nightly/ble-nightly-20260908%2Bd81fd54.tar.xz \
    -o "$task_directory/ble.tar.xz"
printf '%s  %s\n' \
    7a2445f138e7f099dd5dee749391a8b045646d1b8a605975885be5b34b6b5f7e \
    "$task_directory/ble.tar.xz" | shasum -a 256 -c -
mkdir -p "$destination"
tar -xJf "$task_directory/ble.tar.xz" --strip-components=1 -C "$destination"
printf '%s\n' 'Installed ble.sh in ~/.local/share/blesh.'
