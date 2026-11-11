#!/bin/bash
# Wi-Fi pill: green when connected, red when not. Clicking opens a small menu
# right away (System Settings takes a second or more to come up).
#   wifi.sh          refresh
#   wifi.sh menu     open or close the menu
#   wifi.sh power    turn Wi-Fi off or on
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/glyphs.sh"
source "$CONFIG_DIR/plugins/hover.sh"
ITEM=wifi
DEVICE="$(networksetup -listallhardwareports | awk '/Wi-Fi/ { getline; print $2; exit }')"
DEVICE="${DEVICE:-en0}"

case "$1" in
  menu)
    if sketchybar --query $ITEM | grep -A3 '"popup"' | grep -q '"drawing": "on"'; then
      sketchybar --set $ITEM popup.drawing=off
    else
      sketchybar --set $ITEM popup.drawing=on
    fi
    ;;
  power)
    if networksetup -getairportpower "$DEVICE" | grep -q ': On'; then
      networksetup -setairportpower "$DEVICE" off
    else
      networksetup -setairportpower "$DEVICE" on
    fi
    sketchybar --set $ITEM popup.drawing=off
    ;;
esac

POWER_ON=false
networksetup -getairportpower "$DEVICE" | grep -q ': On' && POWER_ON=true
ADDRESS="$(ipconfig getifaddr "$DEVICE")"

if [ -n "$ADDRESS" ]; then
  sketchybar --set $ITEM icon="$G_WIFI" icon.color=$GREEN \
             --set $ITEM.status label="Connected · $ADDRESS"
elif [ "$POWER_ON" = true ]; then
  sketchybar --set $ITEM icon="$G_WIFI_OFF" icon.color=$RED \
             --set $ITEM.status label="Not connected"
else
  sketchybar --set $ITEM icon="$G_WIFI_OFF" icon.color=$RED \
             --set $ITEM.status label="Wi-Fi is off"
fi

if [ "$POWER_ON" = true ]; then
  sketchybar --set $ITEM.power label="Turn Wi-Fi Off" icon.color=$RED
else
  sketchybar --set $ITEM.power label="Turn Wi-Fi On" icon.color=$GREEN
fi
