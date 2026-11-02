#!/bin/bash
# Mocha Desktop installer.
#   ./install.sh                 install everything
#   ./install.sh menubar dock    install only some parts: menubar, dock, gaps, wallpaper
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
STAMP="$(date +%Y%m%d%H%M%S)"
PARTS=("$@")
[ ${#PARTS[@]} -eq 0 ] && PARTS=(menubar dock gaps wallpaper)

wants() { [[ " ${PARTS[*]} " == *" $1 "* ]]; }
step()  { echo; echo "==> $*"; }
backup() { [ -e "$1" ] && mv "$1" "$1.backup.$STAMP" && echo "    kept your old $(basename "$1") as $(basename "$1").backup.$STAMP"; true; }

if ! command -v brew >/dev/null; then
  echo "Homebrew is needed first. Install it from https://brew.sh, then run this again."
  exit 1
fi

if wants menubar || wants dock; then
  step "Installing SketchyBar and Hack Nerd Font"
  # Newer Homebrew asks you to trust third-party taps; this one is SketchyBar's official tap
  brew trust felixkratz/formulae >/dev/null 2>&1 || true
  brew tap FelixKratz/formulae
  brew trust felixkratz/formulae >/dev/null 2>&1 || true
  brew list sketchybar >/dev/null 2>&1 || brew install sketchybar
  brew list --cask font-hack-nerd-font >/dev/null 2>&1 || brew install --cask font-hack-nerd-font
fi

if wants menubar; then
  step "Menu bar"
  DEST="$HOME/.config/sketchybar"
  backup "$DEST"
  mkdir -p "$HOME/.config"
  cp -R "$REPO/menubar" "$DEST"
  chmod +x "$DEST/sketchybarrc" "$DEST"/*.sh "$DEST"/plugins/*.sh
  brew services restart sketchybar
  # Hide Apple's menu bar so the Mocha one takes its place (it still slides down at the top edge)
  defaults write NSGlobalDomain _HIHideMenuBar -bool true
  echo "    If Apple's menu bar still shows, set System Settings → Control Center →"
  echo "    \"Automatically hide and show the menu bar\" to Always."
fi

if wants dock; then
  step "Dock"
  DEST="$HOME/.config/sketchybar-dock"
  LABEL="com.mocha.dock"
  PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

  # Keep the app list from an earlier install
  SAVED_APPS=""
  if [ -f "$DEST/apps.txt" ]; then SAVED_APPS="$(mktemp)"; cp "$DEST/apps.txt" "$SAVED_APPS"; fi
  pkill -f "$DEST/bin/dockdrop" 2>/dev/null || true
  backup "$DEST"
  cp -R "$REPO/dock" "$DEST"
  chmod +x "$DEST/sketchybarrc" "$DEST"/*.sh "$DEST"/plugins/*.sh

  if [ -n "$SAVED_APPS" ]; then
    mv "$SAVED_APPS" "$DEST/apps.txt"
    echo "    kept your existing dock apps"
  else
    "$DEST/make-apps.sh" "$DEST/known-apps.txt" "$DEST/apps.txt"
    echo "    built the dock from the apps in your current Dock"
  fi

  # SketchyBar names each instance after the file it starts from, so the dock
  # runs through a link called "mochadock" to stay separate from the menu bar
  mkdir -p "$DEST/bin"
  ln -sf "$(brew --prefix)/bin/sketchybar" "$DEST/bin/mochadock"

  # Dock helper (hover and drag and drop): use the prebuilt one if this copy has it, else build it
  if [ -x "$REPO/dock/bin/dockdrop" ]; then
    cp "$REPO/dock/bin/dockdrop" "$DEST/bin/dockdrop"
  elif command -v swiftc >/dev/null || xcrun --find swiftc >/dev/null 2>&1; then
    "$REPO/scripts/swift-build.sh" "$DEST/bin/dockdrop" native "$REPO/dock/dockdrop/main.swift" || echo "    couldn't build the dock helper; the dock works, but without hover or drag and drop"
  else
    echo "    skipped the dock helper for hover and drag and drop (needs Xcode Command Line Tools: xcode-select --install)"
  fi

  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
  cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$DEST/bin/mochadock</string>
    <string>--config</string>
    <string>$DEST/sketchybarrc</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>CONFIG_DIR</key><string>$DEST</string>
    <key>LANG</key><string>en_US.UTF-8</string>
    <key>PATH</key><string>$DEST/bin:$(brew --prefix)/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/mocha-dock.log</string>
</dict>
</plist>
PLIST
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"

  # Apple's Dock stays available at the bottom edge (for minimized windows and badges)
  defaults write com.apple.dock autohide -bool true
  defaults write com.apple.dock autohide-delay -float 0.5
  defaults write com.apple.dock show-recents -bool false
  killall Dock
fi

if wants gaps; then
  step "Window gaps (Rectangle)"
  brew list --cask rectangle >/dev/null 2>&1 || brew install --cask rectangle
  # Even 8pt gap around zoomed windows: menu bar pills end 33pt down, the dock tray
  # starts 90pt up. Notched screens already keep their top strip clear, so subtract it.
  NOTCH="$(osascript -l JavaScript -e 'ObjC.import("AppKit"); var s=$.NSScreen.screens.objectAtIndex(0); var t=0; try { t=s.safeAreaInsets.top } catch(e) {}; Math.round(t)' 2>/dev/null || echo 0)"
  R=com.knollsoft.Rectangle
  defaults write $R screenEdgeGapTop -int 41
  defaults write $R screenEdgeGapTopNotch -int $(( 41 - ${NOTCH:-0} > 0 ? 41 - ${NOTCH:-0} : 8 ))
  defaults write $R screenEdgeGapBottom -int 98
  defaults write $R screenEdgeGapLeft -int 8
  defaults write $R screenEdgeGapRight -int 8
  defaults write $R screenEdgeGapsOnMainScreenOnly -bool true
  defaults write $R doubleClickTitleBar -int 3        # 3 = maximize
  defaults write $R doubleClickTitleBarRestore -int 1 # double-click again restores
  defaults write -g AppleActionOnDoubleClick -string "None"   # so macOS doesn't zoom too
  killall Rectangle 2>/dev/null || true
  open -a Rectangle
  echo "    Allow Rectangle in System Settings → Privacy & Security → Accessibility,"
  echo "    and turn on \"Launch on login\" in its settings."
fi

if wants wallpaper; then
  step "Wallpaper"
  mkdir -p "$HOME/Pictures"
  cp "$REPO/wallpaper/mocha-wallpaper.png" "$HOME/Pictures/mocha-wallpaper.png"
  osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"$HOME/Pictures/mocha-wallpaper.png\""
fi

echo
echo "Mocha Desktop is installed."
