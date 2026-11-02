#!/bin/bash
# Hover for a dock tile (an app or the trash). Clicks are handled by each
# tile's click_script in sketchybarrc so they never wait on this script.
#
# The hover grows the tile in whole 2px steps instead of using SketchyBar's
# animator: that one rounds width, padding and height separately each frame,
# which nudges the dock by a pixel whenever an animation is cut short. Here
# every step's width + padding adds up to the same total and heights stay
# even, so nothing around the tile moves.
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar-dock}"
source "$CONFIG_DIR/sizes.sh"

STATE_DIR="/tmp/mochadock-$USER"
mkdir -p "$STATE_DIR"
MENU_FILE="$STATE_DIR/menu-open"   # which tile's right-click menu is open
STEP_FILE="$STATE_DIR/$NAME.step"
OWNER_FILE="$STATE_DIR/$NAME.owner"

size_at() { # step 0 (resting) .. TILE_GAP (hovered)
  local size=$(( TILE + 2 * $1 )) pad=$(( TILE_GAP - $1 ))
  echo "icon.width=$size padding_left=$pad padding_right=$pad" \
       "background.height=$size background.corner_radius=$(( TILE_RADIUS + $1 / 2 ))"
}

step_to() {
  # The newest hover event for this tile owns it; an older one stops stepping
  echo $$ > "$OWNER_FILE"
  local current=0 owner
  read -r current 2>/dev/null < "$STEP_FILE" || current=0
  while [ "$current" -ne "$1" ]; do
    read -r owner < "$OWNER_FILE"
    [ "$owner" = "$$" ] || exit 0
    if [ "$current" -lt "$1" ]; then current=$(( current + 1 )); else current=$(( current - 1 )); fi
    mochadock --set "$NAME" $(size_at $current)
    echo "$current" > "$STEP_FILE"
    [ "$current" -ne "$1" ] && sleep "$FRAME_DELAY"
  done
  return 0
}

OPEN_MENU="$(cat "$MENU_FILE" 2>/dev/null)"

close_menu() { # $1: tile whose menu is open
  mochadock --set "$1" popup.drawing=off --remove '/menu\..*/' 2>/dev/null
  rm -f "$MENU_FILE"
}

case "$SENDER" in
  mouse.entered)
    # Hovering another tile closes an open right-click menu and shows this app's name
    [ -n "$OPEN_MENU" ] && [ "$OPEN_MENU" != "$NAME" ] && close_menu "$OPEN_MENU"
    mochadock --set "$NAME" popup.drawing=on
    step_to "$TILE_GAP"
    ;;
  mouse.exited)
    # Keep the popup while it's a right-click menu, so the pointer can move into it
    [ "$OPEN_MENU" = "$NAME" ] || mochadock --set "$NAME" popup.drawing=off
    step_to 0
    ;;
  mouse.exited.global)
    [ "$OPEN_MENU" = "$NAME" ] && close_menu "$NAME"
    mochadock --set "$NAME" popup.drawing=off
    ;;
esac
