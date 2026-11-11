#!/bin/bash
# Battery pill: yellow normally, red under 20%, green on power. In Low Power Mode
# (however it was turned on) the pill gets a soft amber tint, like the iPhone's
# yellow battery, so it shows without another icon.
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/glyphs.sh"
source "$CONFIG_DIR/plugins/hover.sh"
REST_FILE="$CONFIG_DIR/cache/rest-$NAME"   # the color hover returns this pill to

mix() { # color1 color2 percent-of-color2 → 0xAARRGGBB (keeps color1's opacity)
  local a=${1#0x} b=${2#0x} p=$3 out="0x${1:2:2}" i
  for i in 2 4 6; do
    printf -v out '%s%02x' "$out" $(( (16#${a:i:2} * (100 - p) + 16#${b:i:2} * p) / 100 ))
  done
  echo "$out"
}

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

if pmset -g | grep -q 'lowpowermode *1'; then
  COLOR=$YELLOW
  BG="$(mix "$PILL_COLOR" "$YELLOW" 22)"   # the pill, tinged amber (solid, so it reads on any wallpaper)
  BORDER=(background.border_width=1 background.border_color="0x80${YELLOW: -6}")
else
  BG=$PILL_COLOR
  BORDER=(background.border_width=$PILL_BORDER_WIDTH background.border_color=$PILL_BORDER_COLOR)
fi
mkdir -p "$CONFIG_DIR/cache"; echo "$BG" > "$REST_FILE"

sketchybar --set "$NAME" icon="$ICON" label="${PERCENTAGE}%" icon.color=$COLOR label.color=$COLOR \
                         background.color=$BG "${BORDER[@]}"
