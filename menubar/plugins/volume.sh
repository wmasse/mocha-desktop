#!/bin/bash
# Volume pill. Reads and changes the volume through barclick (Core Audio): the
# AppleScript volume commands take about a second each on macOS 27.
#   volume.sh          refresh (also on volume_change, scrolling and clicks)
#   volume.sh mute     toggle mute (the pill's click)
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/glyphs.sh"
source "$CONFIG_DIR/plugins/hover.sh"
BARCLICK="$CONFIG_DIR/bin/barclick"

if [ "$1" = "mute" ]; then
  STATE="$("$BARCLICK" mute)"
elif [ "$SENDER" = "mouse.scrolled" ]; then
  # Scroll up for louder, down for quieter
  if [ "${SCROLL_DELTA:-0}" -gt 0 ]; then STATE="$("$BARCLICK" volume +4)"; else STATE="$("$BARCLICK" volume -4)"; fi
else
  STATE="$("$BARCLICK" volume)"
fi
read -r VOLUME MUTED <<< "$STATE"

if [ "$MUTED" = "true" ]; then
  sketchybar --set "$NAME" icon="$G_VOL_MUTE" label="Muted" icon.color=$OVERLAY label.color=$OVERLAY
  exit 0
fi

case "$VOLUME" in
  [6-9][0-9]|100)   ICON="$G_VOL_3" ;;
  [3-5][0-9])       ICON="$G_VOL_2" ;;
  [1-9]|[1-2][0-9]) ICON="$G_VOL_1" ;;
  *)                ICON="$G_VOL_MUTE" ;;
esac

sketchybar --set "$NAME" icon="$ICON" label="${VOLUME}%" icon.color=$BLUE label.color=$BLUE
