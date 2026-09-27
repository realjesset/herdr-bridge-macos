#!/bin/bash
# Package an already-built app; never install or mount it.
set -euo pipefail
cd "$(dirname "$0")"
if [[ "$(uname -s)" != Darwin ]]; then
  printf '%s\n' 'DMG packaging requires macOS and hdiutil.' >&2
  exit 1
fi
if [[ "$#" -ne 0 ]]; then
  printf '%s\n' 'Usage: bash package-dmg.sh (run bash build-app.sh first)' >&2
  exit 1
fi
APP="$PWD/dist/Herdr Bridge.app"
DMG="$PWD/dist/Herdr Bridge.dmg"
if [[ ! -d "$APP" ]]; then
  printf '%s\n' 'App not found. Run bash build-app.sh first.' >&2
  exit 1
fi
if [[ -e "$DMG" || -L "$DMG" ]]; then
  printf '%s\n' 'Output already exists; move dist/Herdr Bridge.dmg aside first.' >&2
  exit 1
fi
/usr/bin/codesign --verify --strict --verbose=2 "$APP"
STAGE="$(mktemp -d "$PWD/dist/.dmg-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
/usr/bin/ditto "$APP" "$STAGE/Herdr Bridge.app"
ln -s /Applications "$STAGE/Applications"
/usr/bin/hdiutil create -volname 'Herdr Bridge' -srcfolder "$STAGE"   -format UDZO "$DMG"
/usr/bin/hdiutil verify "$DMG"
printf 'Created (ad-hoc app; not notarized): %s\n' "$DMG"
