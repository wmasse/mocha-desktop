#!/bin/bash
# Tile sizes. The corner radius comes from the theme (style.sh: THEME_TILE_RADIUS,
# 15 by default, ~28% of the tile so it reads as a squircle); source colors.sh first.
export TILE=52
export TILE_RADIUS=${THEME_TILE_RADIUS:-15}
export TILE_FONT=26
export TILE_GAP=4        # padding on each side of a tile; a hovered tile grows
                         # by this much on each side, into its own padding,
                         # so the tiles next to it don't move
export HOVER=$(( TILE + 2 * TILE_GAP ))
export PRESS=56          # quick dip when a tile is clicked
export TRAY_HEIGHT=68
export DOCK_Y=8          # gap between the dock and the bottom of the screen
export DOCK_HIDDEN_Y=-96 # parked below the screen while a full-screen app is up
