#!/bin/bash
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/glyphs.sh"
source "$CONFIG_DIR/plugins/hover.sh"

BATT="$(pmset -g batt)"
PERCENTAGE="$(echo "$BATT" | grep -Eo "[0-9]+%" | cut -d% -f1)"
[ -z "$PERCENTAGE" ] && sketchybar --set "$NAME" drawing=off && exit 0  # desktop Macs

case "$PERCENTAGE" in
  9[0-9]|100) ICON="$G_BATT_4" ;;
  [6-8][0-9]) ICON="$G_BATT_3" ;;
  [3-5][0-9]) ICON="$G_BATT_2" ;;
  [1-2][0-9]) ICON="$G_BATT_1" ;;
  *)          ICON="$G_BATT_0" ;;
esac

COLOR=$YELLOW
if echo "$BATT" | grep -q "AC Power"; then
  ICON="$G_BOLT"
  COLOR=$GREEN
elif [ "$PERCENTAGE" -lt 20 ]; then
  COLOR=$RED
fi

sketchybar --set "$NAME" icon="$ICON" label="${PERCENTAGE}%" icon.color=$COLOR label.color=$COLOR
