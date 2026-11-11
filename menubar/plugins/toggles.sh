#!/bin/bash
# Low Power Mode and Do Not Disturb buttons.
#   Low Power: pmset, which needs root. A sudoers rule lets this account run only
#   "pmset -a lowpowermode 0" and "... 1" without a password
#   (/etc/sudoers.d/mocha-lowpower); its state comes from pmset too.
#   Do Not Disturb: a one-step shortcut, "Mocha Do Not Disturb" (Set Focus →
#   Do Not Disturb → Toggle). Its state is private to macOS, so this remembers
#   what the button last set.
#   toggles.sh            refresh (NAME is lowpower or dnd)
#   toggles.sh toggle     switch it, then refresh
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/glyphs.sh"
source "$CONFIG_DIR/plugins/hover.sh"
DND_FILE="$CONFIG_DIR/cache/dnd-on"   # present = Do Not Disturb is on (as far as we know)
mkdir -p "$CONFIG_DIR/cache"

low_power_on() { pmset -g | grep -q 'lowpowermode *1'; }
notify() { osascript -e "display notification \"$1\" with title \"Mocha\"" 2>/dev/null; }

if [ "$1" = "toggle" ]; then
  case "$NAME" in
    lowpower)
      if low_power_on; then NEW=0; else NEW=1; fi
      # -n: never ask for a password; fails if the sudoers rule isn't set up
      sudo -n /usr/bin/pmset -a lowpowermode $NEW 2>/dev/null \
        || notify "Low Power Mode needs a one-time setup; see the Mocha README."
      sketchybar --trigger lowpower_change
      ;;
    dnd)
      if shortcuts run "Mocha Do Not Disturb" >/dev/null 2>&1; then
        if [ -f "$DND_FILE" ]; then rm -f "$DND_FILE"; else touch "$DND_FILE"; fi
      else
        notify "Make a shortcut named “Mocha Do Not Disturb” in the Shortcuts app first."
        open -a Shortcuts
      fi
      ;;
  esac
fi

case "$NAME" in
  lowpower)
    if low_power_on; then
      sketchybar --set lowpower icon="$G_LOWPOWER" icon.color=$YELLOW
    else
      sketchybar --set lowpower icon="$G_LOWPOWER" icon.color=$OVERLAY
    fi
    ;;
  dnd)
    if [ -f "$DND_FILE" ]; then
      sketchybar --set dnd icon="$G_DND" icon.color=$MAUVE
    else
      sketchybar --set dnd icon="$G_DND" icon.color=$OVERLAY
    fi
    ;;
esac
