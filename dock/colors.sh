#!/bin/bash
# Colors for the dock and the menu bar (the menu bar's colors.sh sources this).
# They come from the theme named in theme.txt (one of themes/*.sh), plus any
# colors you picked for that theme (custom-<theme>.sh). Change both with
# right-click → Theme… on any tile. Catppuccin Mocha if unset.
THEME_DIR="${THEME_DIR:-$HOME/.config/sketchybar-dock}"
THEME="$(cat "$THEME_DIR/theme.txt" 2>/dev/null)"
[ -f "$THEME_DIR/themes/$THEME.sh" ] || THEME=mocha
source "$THEME_DIR/themes/$THEME.sh"
[ -f "$THEME_DIR/custom-$THEME.sh" ] && source "$THEME_DIR/custom-$THEME.sh"
export THEME
export TRANSPARENT=0x00000000
