#!/bin/bash
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/glyphs.sh"
source "$CONFIG_DIR/plugins/hover.sh"

if [ -n "$(ipconfig getifaddr en0)" ]; then
  sketchybar --set "$NAME" icon="$G_WIFI" icon.color=$GREEN
else
  sketchybar --set "$NAME" icon="$G_WIFI_OFF" icon.color=$RED
fi
