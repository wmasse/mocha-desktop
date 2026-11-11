#!/bin/bash
# Removes Mocha Desktop and puts macOS's own menu bar, Dock and window zoom back.
# Your configs are moved aside (not deleted) so you can restore them.
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
STAMP="$(date +%Y%m%d%H%M%S)"

echo "==> Dock"
launchctl bootout "gui/$(id -u)/com.mocha.dock" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/com.mocha.dock.plist"
pkill -f "$HOME/.config/sketchybar-dock/bin/dockdrop" 2>/dev/null
[ -d "$HOME/.config/sketchybar-dock" ] && mv "$HOME/.config/sketchybar-dock" "$HOME/.config/sketchybar-dock.removed.$STAMP"
defaults write com.apple.dock autohide -bool false
defaults delete com.apple.dock autohide-delay 2>/dev/null
killall Dock

echo "==> Menu bar"
launchctl bootout "gui/$(id -u)/com.mocha.menubar" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/com.mocha.menubar.plist"
pkill -fx "$HOME/.config/sketchybar/bin/barclick" 2>/dev/null
brew services stop sketchybar 2>/dev/null
[ -d "$HOME/.config/sketchybar" ] && mv "$HOME/.config/sketchybar" "$HOME/.config/sketchybar.removed.$STAMP"
defaults write NSGlobalDomain _HIHideMenuBar -bool false

echo "==> Window zoom"
defaults delete -g AppleActionOnDoubleClick 2>/dev/null
killall Rectangle 2>/dev/null

echo
echo "Done. SketchyBar, Rectangle and the font are still installed; remove them with:"
echo "  brew uninstall sketchybar && brew uninstall --cask rectangle font-hack-nerd-font"
echo "If you set up the Low Power button, remove its rule with: sudo rm /etc/sudoers.d/mocha-lowpower"
echo "If Apple's menu bar stays hidden, set System Settings → Control Center →"
echo "\"Automatically hide and show the menu bar\" back to Never."
