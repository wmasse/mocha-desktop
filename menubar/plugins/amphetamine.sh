#!/bin/bash
# Amphetamine: a full cup while a keep-awake session is on, an empty one when
# it's off. Clicking the cup opens a menu to start a session, keep the Mac awake
# with the lid closed, or turn it off.
#   amphetamine.sh                  refresh the cup and the menu
#   amphetamine.sh menu             open or close the menu
#   amphetamine.sh start <key> [n hours|minutes]   start a session (no length: until turned off)
#   amphetamine.sh lid              turn "stay awake with lid closed" on or off
#   amphetamine.sh off              end the session
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/glyphs.sh"
source "$CONFIG_DIR/plugins/hover.sh"
ITEM=amphetamine
STATE="$CONFIG_DIR/cache"
LID_FILE="$STATE/amphetamine-lid"        # present = keep awake with the lid closed
CHOICE_FILE="$STATE/amphetamine-choice"  # which option started the current session
OPTIONS="forever 30m 1h 2h 4h"
mkdir -p "$STATE"

amphetamine() { osascript -e "tell application \"Amphetamine\" to $1" 2>/dev/null; }
lid_wanted() { [ -f "$LID_FILE" ]; }

case "$1" in
  menu)
    # Set the opposite of what's showing; a plain toggle can get out of step
    if sketchybar --query $ITEM | grep -A3 '"popup"' | grep -q '"drawing": "on"'; then
      sketchybar --set $ITEM popup.drawing=off
    else
      sketchybar --set $ITEM popup.drawing=on
    fi
    ;;
  start)
    if [ -n "$3" ]; then
      amphetamine "start new session with options {duration:$3, interval:$4, displaySleepAllowed:false}"
    else
      amphetamine "start new session with options {displaySleepAllowed:false}"
    fi
    lid_wanted && amphetamine 'enable closed display mode'
    echo "$2" > "$CHOICE_FILE"
    sketchybar --set $ITEM popup.drawing=off
    ;;
  lid)
    # Stays open so you can see the switch flip
    if lid_wanted; then
      rm -f "$LID_FILE"
      [ "$(amphetamine 'return session is active')" = "true" ] && amphetamine 'disable closed display mode'
    else
      touch "$LID_FILE"
      [ "$(amphetamine 'return session is active')" = "true" ] && amphetamine 'enable closed display mode'
    fi
    ;;
  off)
    amphetamine 'end session'
    rm -f "$CHOICE_FILE"
    sketchybar --set $ITEM popup.drawing=off
    ;;
esac

ARGS=()
ACTIVE="$(amphetamine 'return session is active')"

# Cup and status line
if [ "$ACTIVE" = "true" ]; then
  LEFT="$(amphetamine 'return session time remaining')"
  STATUS="Keeping awake"
  if [ "${LEFT:-0}" -gt 0 ]; then
    H=$(( LEFT / 3600 )); M=$(( (LEFT % 3600 + 59) / 60 ))
    [ "$M" -eq 60 ] && { H=$(( H + 1 )); M=0; }
    if [ "$H" -gt 0 ]; then STATUS+=" · ${H}h ${M}m left"; else STATUS+=" · ${M}m left"; fi
  else
    STATUS+=" · until you turn it off"
  fi
  [ "$(amphetamine 'return closed display mode enabled')" = "true" ] && STATUS+=" · lid ok"
  ARGS+=(--set $ITEM icon="$G_AWAKE" icon.color=$PEACH
         --set $ITEM.title icon="$G_AWAKE" icon.color=$PEACH
         --set $ITEM.status label="$STATUS" label.color=$PEACH
         --set $ITEM.off drawing=on)
else
  rm -f "$CHOICE_FILE"
  ARGS+=(--set $ITEM icon="$G_AWAKE_OFF" icon.color=$OVERLAY
         --set $ITEM.title icon="$G_AWAKE_OFF" icon.color=$OVERLAY
         --set $ITEM.status label="Off · your Mac sleeps as usual" label.color=$OVERLAY
         --set $ITEM.off drawing=off)
fi

# Lid switch, and a warning when it would run the battery down
if lid_wanted; then
  ARGS+=(--set $ITEM.lid icon="$G_TOGGLE_ON" icon.color=$GREEN label.color=$TEXT)
  if pmset -g batt | grep -q "Battery Power"; then
    PERCENT="$(pmset -g batt | grep -o '[0-9]*%' | head -1)"
    ARGS+=(--set $ITEM.warning drawing=on label="On battery (${PERCENT:-?}) · plug in first")
  else
    ARGS+=(--set $ITEM.warning drawing=off)
  fi
else
  ARGS+=(--set $ITEM.lid icon="$G_TOGGLE_OFF" icon.color=$OVERLAY label.color=$SUBTEXT
         --set $ITEM.warning drawing=off)
fi

# Check mark on the option that's running
CHOICE="$(cat "$CHOICE_FILE" 2>/dev/null)"
for key in $OPTIONS; do
  if [ "$ACTIVE" = "true" ] && [ "$key" = "$CHOICE" ]; then
    ARGS+=(--set $ITEM.$key icon="$G_CHECK" icon.color=$GREEN label.color=$TEXT)
  elif [ "$key" = "forever" ]; then
    ARGS+=(--set $ITEM.$key icon="$G_INFINITY" icon.color=$PEACH label.color=$SUBTEXT)
  else
    ARGS+=(--set $ITEM.$key icon="$G_TIMER" icon.color=$YELLOW label.color=$SUBTEXT)
  fi
done

sketchybar "${ARGS[@]}"
