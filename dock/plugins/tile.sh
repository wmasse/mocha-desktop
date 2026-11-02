#!/bin/bash
# Hover for a dock tile (an app or the trash). Clicks are handled by each
# tile's click_script in sketchybarrc so they never wait on this script.
#
# The hover grows the tile in whole 2px steps instead of using SketchyBar's
# animator: that one rounds width, padding and height separately each frame,
# which nudges the dock by a pixel whenever an animation is cut short. Here
# every step's width + padding adds up to the same total and heights stay
# even, so nothing around the tile moves.
#
# Sweeping across the dock fires enter/exit events faster than these scripts
# finish, so each tile has a small lock: only the newest event for a tile
# changes it, and it always reads the tile's real current step.
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar-dock}"
source "$CONFIG_DIR/sizes.sh"

STATE_DIR="/tmp/mochadock-$USER"
mkdir -p "$STATE_DIR"
MENU_FILE="$STATE_DIR/menu-open"   # which tile's right-click menu is open
STEP_FILE="$STATE_DIR/$NAME.step"
OWNER_FILE="$STATE_DIR/$NAME.owner"
LOCK="$STATE_DIR/$NAME.lock"
OPEN_MENU="$(cat "$MENU_FILE" 2>/dev/null)"

lock() {
  local tries=0
  until mkdir "$LOCK" 2>/dev/null; do
    tries=$(( tries + 1 ))
    [ "$tries" -gt 100 ] && rmdir "$LOCK" 2>/dev/null   # left behind by a killed script
    sleep 0.002
  done
}
unlock() { rmdir "$LOCK" 2>/dev/null; }

size_at() { # step 0 (resting) .. TILE_GAP (hovered)
  local size=$(( TILE + 2 * $1 )) pad=$(( TILE_GAP - $1 ))
  echo "icon.width=$size padding_left=$pad padding_right=$pad" \
       "background.height=$size background.corner_radius=$(( TILE_RADIUS + $1 / 2 ))"
}

hide_name() { # hide the app-name label, unless the popup is this tile's right-click menu
  [ "$OPEN_MENU" = "$NAME" ] || mochadock --set "$NAME" popup.drawing=off
}

close_menu() { # $1: tile whose menu is open
  mochadock --set "$1" popup.drawing=off --remove '/menu\..*/' 2>/dev/null
  rm -f "$MENU_FILE"
}

step_to() {
  local current owner
  while true; do
    lock
    read -r owner < "$OWNER_FILE"
    [ "$owner" = "$$" ] || { unlock; return 0; }   # a newer event took over
    read -r current 2>/dev/null < "$STEP_FILE" || current=0
    [ "$current" -eq "$1" ] && { unlock; return 0; }
    if [ "$current" -lt "$1" ]; then current=$(( current + 1 )); else current=$(( current - 1 )); fi
    mochadock --set "$NAME" $(size_at $current)
    echo "$current" > "$STEP_FILE"
    unlock
    [ "$current" -ne "$1" ] && sleep "$FRAME_DELAY"
  done
}

case "$SENDER" in
  mouse.entered)
    # Hovering another tile closes an open right-click menu
    [ -n "$OPEN_MENU" ] && [ "$OPEN_MENU" != "$NAME" ] && close_menu "$OPEN_MENU"
    lock; echo $$ > "$OWNER_FILE"; mochadock --set "$NAME" popup.drawing=on; unlock
    step_to "$TILE_GAP"
    ;;
  mouse.exited)
    # The label goes the moment the pointer leaves; a right-click menu stays
    # open so the pointer can move into it
    lock; echo $$ > "$OWNER_FILE"; hide_name; unlock
    step_to 0
    ;;
  mouse.exited.global)
    [ "$OPEN_MENU" = "$NAME" ] && close_menu "$NAME"
    mochadock --set "$NAME" popup.drawing=off
    ;;
esac
