#!/bin/bash
# The scenery behind the tray, for themes that have it (drawn by bin/dockart from
# dockart/main.swift). Drawn at the tray's exact width, so its rounded ends line
# up, and told where the gaps between tiles are, so details sit in the gaps
# instead of being cut up by the tiles. Cached; only redrawn when the theme or
# the layout changes.
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar-dock}"
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/sizes.sh"
CACHE="$CONFIG_DIR/cache"

# The tray's width, the center of each gap between app tiles (relative to the
# tray's left edge; the gap holding the divider is left out, so nothing crowds it),
# and every tile's left and right edge, the Trash's too.
read -r WIDTH GAPS TILES <<< "$(python3 -c '
import json, subprocess
def query(name):
    out = subprocess.run(["mochadock", "--query", name], capture_output=True, text=True).stdout
    return json.loads(out)
def rect(name):
    return list(query(name)["bounding_rects"].values())[0]
try:
    tray = rect("dock")
    apps = [i for i in query("bar")["items"] if i.startswith("app.")]
except Exception:
    raise SystemExit
left = tray["origin"][0]
spans = []
for name in apps:
    try:
        r = rect(name)
        spans.append((r["origin"][0] - left, r["origin"][0] - left + r["size"][0]))
    except Exception:
        pass
spans.sort()
gaps = [round((a[1] + b[0]) / 2, 1) for a, b in zip(spans, spans[1:])]
tiles = list(spans)
try:
    r = rect("trash"); tiles.append((r["origin"][0] - left, r["origin"][0] - left + r["size"][0]))
except Exception:
    pass
print(int(round(tray["size"][0])), ",".join(map(str, gaps)), ",".join("%.1f-%.1f" % t for t in tiles))' 2>/dev/null)"
[ -z "$WIDTH" ] && exit 0

KEY="$(echo "$THEME $WIDTH $GAPS $TILES $TRAY_BORDER_COLOR" | shasum | cut -c1-10)"
ART="$CACHE/scenery-$THEME-$KEY.png"
mkdir -p "$CACHE"
if [ ! -f "$ART" ]; then
  rm -f "$CACHE"/scenery-*.png
  # the outline goes on top, since the scenery covers the tray's own border
  DOCKART_GAPS="$GAPS" DOCKART_TILES="$TILES" DOCKART_TILE="$TILE" "$CONFIG_DIR/bin/dockart" "$THEME" "$WIDTH" "$ART" 68 \
    "$TRAY_BORDER_COLOR" "$TRAY_BORDER_WIDTH" "$(( TRAY_RADIUS > 30 ? 30 : TRAY_RADIUS ))" 2>/dev/null || rm -f "$ART"
fi

if [ -f "$ART" ]; then
  mochadock --set dock background.image="$ART" background.image.scale=0.5 \
                       background.image.corner_radius=$(( TRAY_RADIUS > 30 ? 30 : TRAY_RADIUS )) background.image.drawing=on
else
  mochadock --set dock background.image.drawing=off
fi
