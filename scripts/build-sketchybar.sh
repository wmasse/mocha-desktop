#!/bin/bash
# Builds the Mocha copy of SketchyBar for the menu bar.
#   build-sketchybar.sh <output> <native|universal>
# Stock SketchyBar's topmost=on puts the bar on the same layer as macOS's
# auto-hidden menu bar, which then takes clicks meant for the bar.
# menubar/sketchybar/topmost.patch moves it two layers up; that's the only change.
set -euo pipefail
OUT="$1"; ARCH="$2"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="v2.24.1"   # the patch is made against this release
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

git clone -q --depth 1 --branch "$VERSION" https://github.com/FelixKratz/SketchyBar.git "$TMP/src" 2>/dev/null
cd "$TMP/src"
git apply "$REPO/menubar/sketchybar/topmost.patch"
if [ "$ARCH" = "universal" ]; then
  make universal >/dev/null
else
  make "$(uname -m | sed 's/x86_64/x86/')" >/dev/null
fi
mkdir -p "$(dirname "$OUT")"
cp bin/sketchybar "$OUT"
codesign --force --sign - "$OUT" 2>/dev/null
echo "built $OUT"
