#!/bin/bash
# Sourced at the top of each clickable pill's script: lighten it while the
# pointer is over it, then stop (hover events need no other handling)
case "$SENDER" in
  mouse.entered) sketchybar --animate tanh 6 --set "$NAME" background.color=$SURFACE1; exit 0 ;;
  mouse.exited)  sketchybar --animate tanh 6 --set "$NAME" background.color=$SURFACE0; exit 0 ;;
esac
