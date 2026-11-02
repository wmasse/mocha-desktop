#!/bin/bash
# Slide the dock below the screen on full-screen spaces, and back up after,
# so it eases in instead of popping when you leave a full-screen app.
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar-dock}"
source "$CONFIG_DIR/sizes.sh"

# Space switches finish animating a moment after the event fires
[ "$SENDER" = "space_change" ] && sleep 0.15

STATE="$(osascript -l JavaScript "$CONFIG_DIR/plugins/fullscreen.js" 2>/dev/null)"
CURRENT_Y="$(mochadock --query bar | grep -o '"y_offset":[[:space:]]*-\{0,1\}[0-9]*' | grep -o -- '-\{0,1\}[0-9]*$')"

if [ "$STATE" = "fullscreen" ]; then
  [ "$CURRENT_Y" != "$DOCK_HIDDEN_Y" ] && mochadock --animate sin 12 --bar y_offset=$DOCK_HIDDEN_Y
else
  [ "$CURRENT_Y" != "$DOCK_Y" ] && mochadock --animate sin 20 --bar y_offset=$DOCK_Y
fi
exit 0
