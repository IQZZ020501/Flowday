#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcodebuild -project "$project_root/Flowday.xcodeproj" -scheme Flowday -configuration Release -destination 'platform=macOS' -derivedDataPath "$project_root/.build" build
