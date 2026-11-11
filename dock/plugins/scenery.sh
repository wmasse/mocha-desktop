#!/bin/bash
# The scenery behind the tray, for themes that have it (drawn by bin/dockart from
# dockart/main.swift). Drawn at the tray's exact width, so its rounded ends line
# up; cached, so it's only redrawn when the theme or the tray's width changes.
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar-dock}"
source "$CONFIG_DIR/colors.sh"
CACHE="$CONFIG_DIR/cache"

WIDTH="$(mochadock --query dock 2>/dev/null | python3 -c '
import json, sys
try:
    rects = json.load(sys.stdin)["bounding_rects"]
    print(int(round(list(rects.values())[0]["size"][0])))
except Exception:
    pass')"
[ -z "$WIDTH" ] && exit 0

ART="$CACHE/scenery-$THEME-$WIDTH.png"
mkdir -p "$CACHE"
if [ ! -f "$ART" ]; then
  rm -f "$CACHE"/scenery-*.png
  "$CONFIG_DIR/bin/dockart" "$THEME" "$WIDTH" "$ART" 2>/dev/null || rm -f "$ART"
fi

if [ -f "$ART" ]; then
  mochadock --set dock background.image="$ART" background.image.scale=0.5 \
                       background.image.corner_radius=$(( TRAY_RADIUS > 30 ? 30 : TRAY_RADIUS )) background.image.drawing=on
else
  mochadock --set dock background.image.drawing=off
fi
