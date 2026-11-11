#!/bin/bash
# Sourced at the top of each clickable pill's (or menu row's) script: lighten it
# while the pointer is over it, then stop (hover events need no other handling).
# Click actions pass a command ($1) and still carry SENDER from the last event,
# which is a hover since the pointer is on the pill, so only act without one.
# Menu rows (names with a dot, like amphetamine.1h) rest in the menu's color; a
# pill can keep its own resting color in cache/rest-<name> (the Low Power battery).
if [ -z "$1" ]; then
  if [[ "$NAME" == *.* ]]; then REST=$MENU_COLOR; else REST=$PILL_COLOR; fi
  [ -f "$CONFIG_DIR/cache/rest-$NAME" ] && REST="$(cat "$CONFIG_DIR/cache/rest-$NAME")"
  case "$SENDER" in
    mouse.entered) sketchybar --animate tanh 6 --set "$NAME" background.color=$PILL_HOVER_COLOR; exit 0 ;;
    mouse.exited)  sketchybar --animate tanh 6 --set "$NAME" background.color=$REST; exit 0 ;;
  esac
fi
