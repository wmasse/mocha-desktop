#!/bin/bash
# Running apps get a filled pastel tile and the app in front gets a light ring.
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar-dock}"
source "$CONFIG_DIR/colors.sh"

bundle_of() { lsappinfo info -only bundleid "$1" | sed -n 's/.*="\(.*\)"/\1/p'; }

RUNNING=" "
for asn in $(lsappinfo visibleProcessList | tr ' ' '\n' | sed -n 's/^\(ASN:[^-]*-[^-]*\)-.*/\1/p'); do
  RUNNING+="$(bundle_of "$asn") "
done
FRONT="$(bundle_of "$(lsappinfo front | sed 's/:$//')")"

ARGS=()
while IFS='|' read -r key path bundle glyph color; do
  case "$key" in ''|\#*) continue ;; esac
  if [[ "$RUNNING" == *" $bundle "* ]]; then
    BG="${!color}"; FG=$BASE
  else
    BG=$SURFACE1; FG="${!color}"
  fi

  RING=0
  [ "$bundle" = "$FRONT" ] && RING=2

  ARGS+=(--set "app.$key" background.color=$BG icon.color=$FG
         background.border_width=$RING background.border_color=$TEXT)
done < "$CONFIG_DIR/apps.txt"

mochadock "${ARGS[@]}"
