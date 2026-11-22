#!/bin/bash
set -euo pipefail

source_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$source_dir"

build_system="${DO_BUILD_SYSTEM:-native}"
swift build --build-system "$build_system" -c release "$@"
bin_dir="$(swift build --build-system "$build_system" -c release "$@" --show-bin-path)"
staging="$(mktemp -d /private/tmp/do-build.XXXXXX)"
trap 'rm -rf "$staging"' EXIT
app_dir="$staging/Do.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
install -m 755 "$bin_dir/Do" "$app_dir/Contents/MacOS/Do"
install -m 644 scripts/Info.plist "$app_dir/Contents/Info.plist"

swift scripts/draw-icon.swift "$app_dir/Contents/Resources/Do.icns"
codesign --force --options runtime --sign - "$app_dir"
codesign --verify --strict "$app_dir"

mkdir -p "$source_dir/dist"
(cd "$staging" && zip -q -r "$staging/Do-Mac.zip" Do.app)
cp "$staging/Do-Mac.zip" "$source_dir/dist/Do-Mac.zip"
unzip -oq "$staging/Do-Mac.zip" -d "$source_dir/dist"
printf '%s\n' "$source_dir/dist/Do.app" "$source_dir/dist/Do-Mac.zip"
