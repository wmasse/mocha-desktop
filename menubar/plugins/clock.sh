#!/bin/bash
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/plugins/hover.sh"
sketchybar --set "$NAME" label="$(date '+%a %b %-d · %-I:%M')"
