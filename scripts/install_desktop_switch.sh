#!/bin/bash
# Build the Karabiner helper with the MIT-licensed native swipe core.
set -euo pipefail
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source_file="$script_directory/../home/.config/karabiner/desktop-switch.swift"
output_file="${1:-$HOME/.local/bin/desktop-switch}"
upstream_commit=f7616e42651b1ed8d81625e3640eceed6efa8018
task_directory=$(mktemp -d "${TMPDIR:-/tmp}/desktop-switch-build.XXXXXX")
trap 'rm -rf "$task_directory"' EXIT
mkdir -p "$task_directory/include"
for path in ISS.c event_serialize.c event_serialize.h include/ISS.h; do
    curl -fsSL --retry 2 \
        "https://raw.githubusercontent.com/jurplel/InstantSpaceSwitcher/$upstream_commit/Sources/ISS/$path" \
        -o "$task_directory/$path"
done
curl -fsSL --retry 2 \
    "https://raw.githubusercontent.com/jurplel/InstantSpaceSwitcher/$upstream_commit/LICENSE" \
    -o "$task_directory/LICENSE"
xcrun clang -O2 -c "$task_directory/ISS.c" -o "$task_directory/ISS.o"
xcrun clang -O2 -c "$task_directory/event_serialize.c" -o "$task_directory/event_serialize.o"
swiftc -O "$source_file" "$task_directory/ISS.o" "$task_directory/event_serialize.o" \
    -o "$task_directory/desktop-switch"
mkdir -p "$(dirname -- "$output_file")" "$HOME/.local/share/desktop-switch"
install -m 755 "$task_directory/desktop-switch" "$output_file"
cp "$task_directory/LICENSE" "$HOME/.local/share/desktop-switch/LICENSE"
printf '%s\n' "Built desktop-switch using native Dock gestures ($upstream_commit)."
