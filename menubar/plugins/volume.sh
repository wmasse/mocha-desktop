#!/bin/bash
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/glyphs.sh"
source "$CONFIG_DIR/plugins/hover.sh"

if [ "$SENDER" = "mouse.scrolled" ]; then
  # Scroll up for louder, down for quieter; volume_change then redraws the pill
  if [ "${SCROLL_DELTA:-0}" -gt 0 ]; then STEP=4; else STEP=-4; fi
  osascript -e "set volume output volume ((output volume of (get volume settings)) + $STEP)"
  exit 0
fi

read -r VOLUME MUTED <<< "$(osascript -e 'set s to get volume settings' \
                                    -e 'return ((output volume of s) as text) & " " & ((output muted of s) as text)')"

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
