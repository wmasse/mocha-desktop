#!/bin/bash
# Tile sizes. Corner radius is ~28% of the tile so it reads as a squircle.
export TILE=52
export TILE_RADIUS=15
export TILE_FONT=26
export TILE_GAP=4        # padding on each side of a tile; also the number of
                         # 2px hover steps (a hovered tile grows into its own
                         # padding, so the tiles next to it don't move)
export HOVER=$(( TILE + 2 * TILE_GAP ))
export PRESS=56          # quick dip when a tile is clicked
export FRAME_DELAY=0.012 # pause between hover steps (~60 fps with drawing time)
export TRAY_HEIGHT=68
export DOCK_Y=8          # gap between the dock and the bottom of the screen
export DOCK_HIDDEN_Y=-96 # parked below the screen while a full-screen app is up
