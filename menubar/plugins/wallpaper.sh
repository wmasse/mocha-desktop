#!/bin/bash
# Fills the bar with the top of the current wallpaper, so the strip that covers
# Apple's menu bar blends into the desktop. Dynamic wallpapers change through
# the day, so this runs every few minutes as well as on wake, space and display
# changes. If the strip can't be made, the bar keeps its solid Mocha color.
read -r STRIP SCALE <<< "$("$CONFIG_DIR/bin/barclick" strip "$CONFIG_DIR/cache" "${BAR_HEIGHT:-38}" 2>/dev/null)"
if [ -n "$STRIP" ] && [ -f "$STRIP" ]; then
  sketchybar --bar image="$STRIP" image.scale="${SCALE:-1}" image.drawing=on
else
  sketchybar --bar image.drawing=off
fi
