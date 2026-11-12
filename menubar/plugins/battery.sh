#!/bin/bash
# Battery pill: yellow normally, red under 20%, green on power. In Low Power Mode
# (however it was turned on) the pill gets a soft amber tint, like the iPhone's
# yellow battery, so it shows without another icon. Clicking it opens a menu with
# how much is left and, in minutes, how long it'll last (or how long until it's full).
#   battery.sh        refresh the pill and the menu
#   battery.sh menu   open or close the menu
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/glyphs.sh"
source "$CONFIG_DIR/plugins/hover.sh"
NAME="${NAME:-battery}"
REST_FILE="$CONFIG_DIR/cache/rest-$NAME"   # the color hover returns this pill to

if [ "$1" = "menu" ]; then
  # Opening waits for the refresh below, so the menu appears already filled in
  if sketchybar --query "$NAME" | grep -A3 '"popup"' | grep -q '"drawing": "on"'; then
    sketchybar --set "$NAME" popup.drawing=off
    exit 0
  fi
  OPEN_MENU=1
fi

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

ARGS=(--set "$NAME" icon="$ICON" label="${PERCENTAGE}%" icon.color=$COLOR label.color=$COLOR
      background.color=$BG "${BORDER[@]}")

# ── The menu ──
tint() { echo "0x33${1#0xff}"; }   # a see-through version of a color, for the chip
LINE="$(echo "$BATT" | grep -m1 'InternalBattery')"
STATE="$(echo "$LINE" | awk -F'; ' '{print $2}')"            # discharging, charging, charged, AC attached, finishing charge
ESTIMATE="$(echo "$LINE" | grep -Eo '[0-9]+:[0-9]{2} remaining' | cut -d' ' -f1)"
MINUTES=""
if [ -n "$ESTIMATE" ]; then
  MINUTES=$(( 10#${ESTIMATE%%:*} * 60 + 10#${ESTIMATE##*:} ))
fi
# macOS's own averages, for when pmset is still working out its estimate
SMART="$(ioreg -rn AppleSmartBattery 2>/dev/null)"
smart() { echo "$SMART" | grep -m1 "\"$1\" = " | grep -Eo '[0-9]+$'; }
CYCLES="$(smart CycleCount)"

long() { # minutes → "1 hr 17 min"
  local h=$(( $1 / 60 )) m=$(( $1 % 60 ))
  if [ $h -gt 0 ] && [ $m -gt 0 ]; then echo "$h hr $m min"
  elif [ $h -gt 0 ]; then echo "$h hr"
  else echo "$m min"; fi
}
at() { date -v+"$1"M "+%-I:%M %p"; }   # the clock time that many minutes from now

case "$STATE" in
  charging|"finishing charge")
    [ -z "$MINUTES" ] || [ "$MINUTES" -eq 0 ] && { t="$(smart AvgTimeToFull)"; [ -n "$t" ] && [ "$t" -lt 6000 ] && MINUTES=$t; }
    CHIP="Charging"; CHIP_COLOR=$GREEN; BAR=$GREEN
    if [ -n "$MINUTES" ] && [ "$MINUTES" -gt 0 ]; then
      TIME="$MINUTES min until full"
      WHEN="$(long "$MINUTES") · full around $(at "$MINUTES")"
    else
      TIME="Working out time to full…"; WHEN="Check back in a minute"
    fi
    TIME_ICON="$G_BOLT"; TIME_COLOR=$GREEN
    ;;
  charged|"AC attached"*)
    if [ "$STATE" = "charged" ] || [ "$PERCENTAGE" -ge 100 ]; then CHIP="Fully charged"; else CHIP="Plugged in · not charging"; fi
    CHIP_COLOR=$GREEN; BAR=$GREEN
    TIME="On power"; WHEN="Running on the adapter, not the battery"
    [ "$CHIP" != "Fully charged" ] && WHEN="macOS is holding the charge to protect the battery"
    TIME_ICON="$G_BOLT"; TIME_COLOR=$GREEN
    ;;
  *)
    [ -z "$MINUTES" ] && { t="$(smart AvgTimeToEmpty)"; [ -n "$t" ] && [ "$t" -lt 6000 ] && [ "$t" -gt 0 ] && MINUTES=$t; }
    CHIP="On battery"; CHIP_COLOR=$COLOR; BAR=$COLOR
    [ "$PERCENTAGE" -lt 20 ] && CHIP="Low battery · plug in soon"
    if [ -n "$MINUTES" ]; then
      TIME="$MINUTES min left"
      WHEN="About $(long "$MINUTES") · until $(at "$MINUTES")"
    else
      TIME="Working out time left…"; WHEN="Check back in a minute"
    fi
    TIME_ICON="$G_TIMER"; TIME_COLOR=$COLOR
    ;;
esac
pmset -g | grep -q 'lowpowermode *1' && CHIP="$CHIP · Low Power"

ARGS+=(--set "$NAME.title" icon="$ICON" icon.color=$COLOR label="${PERCENTAGE}%"
       --set "$NAME.level" slider.percentage="$PERCENTAGE" slider.highlight_color=$BAR
       --set "$NAME.status" label="$CHIP" label.color=$CHIP_COLOR label.background.color="$(tint "$CHIP_COLOR")"
       --set "$NAME.time" icon="$TIME_ICON" icon.color=$TIME_COLOR label="$TIME"
       --set "$NAME.when" label="$WHEN"
       --set "$NAME.cycles" label="${CYCLES:+$CYCLES charge cycles}" drawing=$([ -n "$CYCLES" ] && echo on || echo off))
[ -n "$OPEN_MENU" ] && ARGS+=(--set "$NAME" popup.drawing=on)
sketchybar "${ARGS[@]}"
