#!/bin/bash
# Volume pill. Reads and changes the volume through barclick (Core Audio): the
# AppleScript volume commands take about a second each on macOS 27.
# Clicking opens a menu: what's playing in Spotify or Music (artwork, title,
# artist, a progress bar with time left, back, pause and next), a volume slider, mute, and the Bluetooth devices that
# are connected (with their battery when they report it).
#   volume.sh          refresh (also on volume_change and scrolling)
#   volume.sh menu     open or close the menu
#   volume.sh mute     toggle mute
#   volume.sh set      set the volume from the slider ($PERCENTAGE)
#   volume.sh devices  refresh the Bluetooth list (slow, so it runs after the menu opens)
#   volume.sh play | next | back | player   pause or play, skip, go back, or open the player
#   volume.sh seek     jump to where the progress bar was clicked ($PERCENTAGE)
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/glyphs.sh"
source "$CONFIG_DIR/plugins/hover.sh"
BARCLICK="$CONFIG_DIR/bin/barclick"
ITEM=volume
SELF="CONFIG_DIR=$CONFIG_DIR NAME=volume $CONFIG_DIR/plugins/volume.sh"
DEVICES_FILE="$CONFIG_DIR/cache/bluetooth.txt"   # last known list, so the menu opens instantly
mkdir -p "$CONFIG_DIR/cache"

# Rebuild the device rows from DEVICES_FILE ("icon|name|battery" per line), then the
# settings row, so it always stays last
device_rows() {
  # Clear the old rows on their own: when there are none, a failed --remove would
  # make SketchyBar drop the rest of the command
  sketchybar --remove '/volume\.bt\..*/' >/dev/null 2>&1
  local args=() i=0
  if [ -s "$DEVICES_FILE" ]; then
    while IFS='|' read -r icon name battery; do
      i=$((i + 1))
      args+=(--add item "volume.bt.$i" popup.volume
             --set "volume.bt.$i" icon="${!icon:-$G_BLUETOOTH}" icon.color=$BLUE icon.width=28 icon.padding_left=14
                   label="$name" label.color=$TEXT label.max_chars=24 label.padding_left=6 width=$MENU_W
                   background.drawing=off)
      [ -n "$battery" ] && args+=(--add item "volume.bt.${i}b" popup.volume
             --set "volume.bt.${i}b" icon.drawing=off label="$battery" label.color=$OVERLAY
                   label.font.size=11 label.padding_left=48 width=$MENU_W background.drawing=off)
    done < "$DEVICES_FILE"
  else
    args+=(--add item volume.bt.none popup.volume
           --set volume.bt.none icon.drawing=off label="No devices connected" label.color=$OVERLAY
                 label.font.size=12 label.padding_left=16 width=$MENU_W background.drawing=off)
  fi
  args+=(--add item volume.bt.settings popup.volume
         --set volume.bt.settings icon="$G_GEAR" icon.color=$MAUVE icon.width=28 icon.padding_left=14
               label="Bluetooth Settings…" label.color=$SUBTEXT label.padding_left=6 width=$MENU_W
               background.drawing=on background.color=$MENU_COLOR background.height=30 background.corner_radius=9
               background.border_width=0
               padding_left=12 padding_right=12 script="$CONFIG_DIR/plugins/row.sh"
               click_script="sketchybar --set volume popup.drawing=off; open 'x-apple.systempreferences:com.apple.BluetoothSettings'"
         --subscribe volume.bt.settings mouse.entered mouse.exited)
  sketchybar "${args[@]}" 2>/dev/null
}

# Ask a music app something, but only if it's already running (asking would
# launch it), and never wait more than 2 seconds (a permission prompt would)
ask_player() { # app, AppleScript
  pgrep -xq "$1" || return 1
  perl -e 'alarm 2; exec @ARGV' osascript -e "tell application \"$1\" to $2" 2>/dev/null
}

# What's playing: "app|state|title|artist|artwork url|position|duration" (seconds),
# Spotify first, then Music
now_playing() {
  local out
  out="$(ask_player Spotify 'if player state is not stopped then return (player state as text) & "|" & name of current track & "|" & artist of current track & "|" & artwork url of current track & "|" & (player position as integer) & "|" & ((duration of current track) div 1000)')"
  [ -n "$out" ] && { echo "Spotify|$out"; return; }
  out="$(ask_player Music 'if player state is not stopped then return (player state as text) & "|" & name of current track & "|" & artist of current track & "||" & (player position as integer) & "|" & (duration of current track as integer)')"
  [ -n "$out" ] && echo "Music|$out"
}

# m:ss
clock() { printf '%d:%02d' $(( $1 / 60 )) $(( $1 % 60 )); }

# The progress bar: elapsed on the left, time left on the right
progress_args() { # position, duration (seconds)
  local pos=${1:-0} dur=${2:-0} pct=0
  [ "$dur" -gt 0 ] && pct=$(( pos * 100 / dur ))
  echo --set volume.np.progress slider.percentage=$pct icon=$(clock $pos) label=-$(clock $(( dur > pos ? dur - pos : 0 )))
}

# While the menu is open and something plays, move the progress bar every second
follow_progress() {
  local pidfile="$CONFIG_DIR/cache/np-follow.pid"
  [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null && return   # already running
  (
    while sketchybar --query volume 2>/dev/null | grep -A3 '"popup"' | grep -q '"drawing": "on"'; do
      PLAYER="$(cat "$CONFIG_DIR/cache/player" 2>/dev/null)"
      read -r POS DUR <<< "$(ask_player "${PLAYER:-Spotify}" 'return (player position as integer) & " " & (duration of current track as integer)')"
      [ "$PLAYER" = Spotify ] && DUR=$(( ${DUR:-0} / 1000 ))
      [ -n "$POS" ] && sketchybar $(progress_args "$POS" "$DUR") 2>/dev/null
      sleep 1
    done
    rm -f "$pidfile"
  ) >/dev/null 2>&1 &
  echo $! > "$pidfile"
}

# Fill in the Now Playing rows at the top of the menu (made in sketchybarrc),
# or hide them when nothing is playing
NP_ROWS="volume.np.title volume.np.artist volume.np.progress volume.np.back volume.np.play volume.np.next volume.np.rule"
now_playing_rows() {
  local args=() row cover=""
  IFS='|' read -r APP STATE TITLE ARTIST ART POS DUR <<< "$(now_playing)"
  if [ -z "$APP" ]; then
    rm -f "$CONFIG_DIR/cache/player"
    for row in $NP_ROWS; do args+=(--set $row drawing=off); done
    sketchybar "${args[@]}" 2>/dev/null
    return
  fi
  echo "$APP" > "$CONFIG_DIR/cache/player"
  if [ -n "$ART" ]; then
    cover="$CONFIG_DIR/cache/artwork-$(echo "$ART" | shasum | cut -c1-12).jpg"
    if [ ! -f "$cover" ]; then
      rm -f "$CONFIG_DIR"/cache/artwork-*.jpg
      curl -fsSL --max-time 2 "$ART" -o "$cover" 2>/dev/null || rm -f "$cover"
    fi
  fi
  for row in $NP_ROWS; do args+=(--set $row drawing=on); done
  args+=(--set volume.np.title label="$TITLE" --set volume.np.artist label="$ARTIST")
  args+=($(progress_args "$POS" "$DUR"))
  echo "$DUR" > "$CONFIG_DIR/cache/np-duration"
  if [ "$STATE" = "playing" ]; then
    args+=(--set volume.np.play icon="$G_PAUSE" label="Pause")
  else
    args+=(--set volume.np.play icon="$G_PLAY" label="Play")
  fi
  # The artwork (30pt, from Spotify's 640px covers), or a note when there isn't any
  if [ -n "$cover" ] && [ -f "$cover" ]; then
    args+=(--set volume.np.title icon=" " icon.background.drawing=on icon.background.image="$cover"
                 icon.background.image.scale=0.047 icon.background.image.corner_radius=5
                 icon.background.height=30)
  else
    args+=(--set volume.np.title icon="$G_MUSIC" icon.background.drawing=off)
  fi
  sketchybar "${args[@]}" 2>/dev/null
}

case "$1" in
  menu)
    if sketchybar --query $ITEM | grep -A3 '"popup"' | grep -q '"drawing": "on"'; then
      sketchybar --set $ITEM popup.drawing=off
      exit 0
    fi
    MENU_W=276
    now_playing_rows
    device_rows
    OPEN_MENU=1
    [ -f "$CONFIG_DIR/cache/player" ] && follow_progress
    # Refresh the device list without holding up the menu
    ( eval "$SELF devices" ) >/dev/null 2>&1 &
    ;;
  mute)
    "$BARCLICK" mute >/dev/null
    ;;
  player)
    sketchybar --set volume popup.drawing=off
    open -a "$(cat "$CONFIG_DIR/cache/player" 2>/dev/null || echo Spotify)"
    exit 0
    ;;
  seek)
    # click along the progress bar to jump there
    PLAYER="$(cat "$CONFIG_DIR/cache/player" 2>/dev/null)"
    DUR="$(cat "$CONFIG_DIR/cache/np-duration" 2>/dev/null)"
    [ -n "$DUR" ] && ask_player "${PLAYER:-Spotify}" "set player position to $(( DUR * ${PERCENTAGE:-0} / 100 ))" >/dev/null
    exit 0
    ;;
  play|next|back)
    PLAYER="$(cat "$CONFIG_DIR/cache/player" 2>/dev/null)"
    case "$1" in
      play) ask_player "${PLAYER:-Spotify}" 'playpause' >/dev/null ;;
      next) ask_player "${PLAYER:-Spotify}" 'next track' >/dev/null ;;
      back) ask_player "${PLAYER:-Spotify}" 'previous track' >/dev/null ;;   # restarts the song, or the one before near its start
    esac
    sleep 0.4
    MENU_W=276
    now_playing_rows
    exit 0
    ;;
  set)
    "$BARCLICK" volume "=${PERCENTAGE:-0}" >/dev/null
    ;;
  devices)
    MENU_W=276
    system_profiler SPBluetoothDataType -json 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)["SPBluetoothDataType"][0]
except Exception:
    sys.exit(0)
kinds = {"Headphones": "G_HEADPHONES", "Headset": "G_HEADPHONES", "Speaker": "G_SPEAKER",
         "Keyboard": "G_KEYBOARD", "Mouse": "G_MOUSE", "Trackpad": "G_MOUSE", "Phone": "G_PHONE"}
for dev in data.get("device_connected") or []:
    for name, info in dev.items():
        icon = kinds.get(info.get("device_minorType", ""), "G_BLUETOOTH")
        parts = []
        if "device_batteryLevelMain" in info: parts.append(info["device_batteryLevelMain"])
        if "device_batteryLevelLeft" in info: parts.append("L " + info["device_batteryLevelLeft"])
        if "device_batteryLevelRight" in info: parts.append("R " + info["device_batteryLevelRight"])
        if "device_batteryLevelCase" in info: parts.append("Case " + info["device_batteryLevelCase"])
        sep = "  ·  "
        print(icon + "|" + name.strip() + "|" + sep.join(parts))
' > "$DEVICES_FILE.tmp" && mv "$DEVICES_FILE.tmp" "$DEVICES_FILE"
    # only redraw the rows if the menu is still open
    sketchybar --query $ITEM | grep -A3 '"popup"' | grep -q '"drawing": "on"' && device_rows
    exit 0
    ;;
esac

if [ "$SENDER" = "mouse.scrolled" ]; then
  # Scroll up for louder, down for quieter
  if [ "${SCROLL_DELTA:-0}" -gt 0 ]; then STATE="$("$BARCLICK" volume +4)"; else STATE="$("$BARCLICK" volume -4)"; fi
else
  STATE="$("$BARCLICK" volume)"
fi
read -r VOLUME MUTED <<< "$STATE"

if [ "$MUTED" = "true" ]; then
  ARGS=(--set "$ITEM" icon="$G_VOL_MUTE" label="Muted" icon.color=$OVERLAY label.color=$OVERLAY
        --set volume.mute label="Unmute" icon="$G_VOL_3")
else
  case "$VOLUME" in
    [6-9][0-9]|100)   ICON="$G_VOL_3" ;;
    [3-5][0-9])       ICON="$G_VOL_2" ;;
    [1-9]|[1-2][0-9]) ICON="$G_VOL_1" ;;
    *)                ICON="$G_VOL_MUTE" ;;
  esac
  ARGS=(--set "$ITEM" icon="$ICON" label="${VOLUME}%" icon.color=$BLUE label.color=$BLUE
        --set volume.mute label="Mute" icon="$G_VOL_MUTE")
fi
ARGS+=(--set volume.slider slider.percentage="$VOLUME")
[ -n "$OPEN_MENU" ] && ARGS+=(--set $ITEM popup.drawing=on)
sketchybar "${ARGS[@]}" 2>/dev/null
exit 0
