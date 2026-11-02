#!/bin/bash
# Shows the name of the app in focus
if [ "$SENDER" = "front_app_switched" ]; then
  sketchybar --set "$NAME" label="$INFO"
fi
