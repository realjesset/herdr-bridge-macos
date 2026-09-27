#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ "$(uname -s)" != Darwin ]]; then
  printf '%s\n' 'Herdr Bridge requires macOS 13+ and Xcode/Command Line Tools (Swift 5.9+).' >&2
  exit 1
fi
command -v swift >/dev/null
swift test
swift build -c release --product HerdrBridge
BIN="$(swift build -c release --show-bin-path)"
APP="$PWD/dist/Herdr Bridge.app"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/HerdrBridge" "$APP/Contents/MacOS/HerdrBridge"
cp Info.plist "$APP/Contents/Info.plist"
/usr/bin/plutil -lint "$APP/Contents/Info.plist"
/usr/bin/codesign --force --sign - --identifier com.herdr.bridge "$APP"
/usr/bin/codesign --verify --strict --verbose=2 "$APP"
printf 'Built and ad-hoc signed: %s\n' "$APP"
printf 'Run: open "%s"\n' "$APP"
