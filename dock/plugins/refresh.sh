#!/bin/bash
# Open apps get the theme's "running" look and the app in front gets a ring:
#   fill     the tile takes the app's color (or the theme's RUNNING_COLOR), icon in BASE
#   invert   the tile turns TEXT, icon in BASE
#   outline  the tile stays as it is, with a 2pt border in the app's color
# Icons are each app's own color, or all TEXT when the theme's ICON_STYLE is mono.
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar-dock}"
source "$CONFIG_DIR/colors.sh"

bundle_of() { lsappinfo info -only bundleid "$1" | sed -n 's/.*="\(.*\)"/\1/p'; }

RUNNING=" "
for asn in $(lsappinfo visibleProcessList | tr ' ' '\n' | sed -n 's/^\(ASN:[^-]*-[^-]*\)-.*/\1/p'); do
  RUNNING+="$(bundle_of "$asn") "
done
FRONT="$(bundle_of "$(lsappinfo front | sed 's/:$//')")"

ARGS=()
IDLE_COLORS=($TILE_IDLE_COLORS)   # a collage, if the theme has one
TILE_INDEX=0
while IFS='|' read -r key path bundle glyph color; do
  case "$key" in ''|\#*) continue ;; esac
  APP_COLOR="${!color}"
  [ "$ICON_STYLE" = mono ] && APP_COLOR=$TEXT
  IDLE=$TILE_IDLE_COLOR
  [ ${#IDLE_COLORS[@]} -gt 0 ] && IDLE=${IDLE_COLORS[$(( TILE_INDEX % ${#IDLE_COLORS[@]} ))]}
  TILE_INDEX=$(( TILE_INDEX + 1 ))
  BG=$IDLE; FG=$APP_COLOR; BW=$TILE_BORDER_WIDTH; BC=$TILE_BORDER_COLOR

  if [[ "$RUNNING" == *" $bundle "* ]]; then
    case "$RUNNING_STYLE" in
      invert)  BG=$TEXT; FG=$BASE; BW=0 ;;
      outline) BW=2; BC=$APP_COLOR ;;
      *)       BG="${RUNNING_COLOR:-${!color}}"; FG=$BASE; BW=0 ;;
    esac
  fi
  if [ "$bundle" = "$FRONT" ]; then BW=2; BC=$FRONT_RING_COLOR; fi

  ARGS+=(--set "app.$key" background.color=$BG icon.color=$FG
         background.border_width=$BW background.border_color=$BC)
done < "$CONFIG_DIR/apps.txt"

mochadock "${ARGS[@]}"
