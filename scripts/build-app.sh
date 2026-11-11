#!/bin/bash
# Builds dist/Mocha Desktop.app (universal) and dist/Mocha-Desktop.zip for a release.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-1.0.0}"
DIST="$REPO/dist"
APP="$DIST/Mocha Desktop.app"
PAYLOAD="$APP/Contents/Resources/payload"

rm -rf "$APP" "$DIST/Mocha-Desktop.zip"
mkdir -p "$APP/Contents/MacOS" "$PAYLOAD"

echo "==> App"
"$REPO/scripts/swift-build.sh" "$APP/Contents/MacOS/MochaDesktop" universal "$REPO/app/MochaDesktop.swift" -parse-as-library

echo "==> Payload (the installer and everything it installs)"
cp -R "$REPO/install.sh" "$REPO/uninstall.sh" "$REPO/menubar" "$REPO/dock" "$REPO/wallpaper" "$REPO/scripts" "$PAYLOAD/"
rm -f "$PAYLOAD/dock/apps.txt"   # each Mac builds its own from its Dock
rm -rf "$PAYLOAD/menubar/bin" "$PAYLOAD/menubar/cache" "$PAYLOAD/dock/cache"   # anything built locally; prebuilt below
"$REPO/scripts/swift-build.sh" "$PAYLOAD/dock/bin/dockdrop" universal "$REPO/dock/dockdrop/main.swift" \
  "$REPO/dock/dockdrop/apps.swift" "$REPO/dock/dockdrop/gallery.swift"
"$REPO/scripts/swift-build.sh" "$PAYLOAD/dock/bin/dockart" universal "$REPO/dock/dockart/main.swift"
"$REPO/scripts/swift-build.sh" "$PAYLOAD/menubar/bin/barclick" universal "$REPO/menubar/barclick/main.swift"
"$REPO/scripts/build-sketchybar.sh" "$PAYLOAD/menubar/bin/sketchybar" universal

cp "$REPO/app/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Mocha Desktop</string>
  <key>CFBundleDisplayName</key><string>Mocha Desktop</string>
  <key>CFBundleIdentifier</key><string>io.github.wmasse.mochadesktop</string>
  <key>CFBundleExecutable</key><string>MochaDesktop</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Mocha Desktop sets your wallpaper through System Events.</string>
</dict>
</plist>
PLIST

echo "==> Signing (ad hoc) and zipping"
codesign --force --deep --sign - "$APP"
(cd "$DIST" && ditto -c -k --keepParent "Mocha Desktop.app" "Mocha-Desktop.zip")
echo "built $APP"
echo "built $DIST/Mocha-Desktop.zip"
