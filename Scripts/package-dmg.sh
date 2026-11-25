#!/bin/bash
# Builds a Release Flowday.app and packages it into a drag-to-install DMG under dist/.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

"$project_root/Scripts/build.sh"

app="$project_root/.build/Build/Products/Release/Flowday.app"
[ -d "$app" ] || { echo "error: $app not found" >&2; exit 1; }
codesign --verify --deep --strict "$app"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
dist="$project_root/dist"
dmg="$dist/Flowday-$version.dmg"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

ditto "$app" "$staging/Flowday.app"
ln -s /Applications "$staging/Applications"

mkdir -p "$dist"
rm -f "$dmg"
hdiutil create -volname "Flowday $version" -srcfolder "$staging" -fs HFS+ \
  -format UDZO -imagekey zlib-level=9 -ov "$dmg" >/dev/null
hdiutil verify "$dmg" >/dev/null

echo "$dmg"
