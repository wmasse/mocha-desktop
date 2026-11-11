#!/bin/bash
# Shows the name of the app in focus, and names it in the pill's menu
if [ "$SENDER" = "front_app_switched" ]; then
  sketchybar --set "$NAME" label="$INFO" \
             --set "$NAME.hide" label="Hide $INFO" \
             --set "$NAME.quit" label="Quit $INFO"
fi
