#!/bin/bash
# The design side of a theme, beyond its palette. Sourced after the theme and
# your custom colors; each setting falls back to the Mocha look, so a theme only
# sets what it changes.

# Dock tray
export TRAY_COLOR="${TRAY_COLOR:-$SURFACE0}"
export TRAY_BORDER_COLOR="${TRAY_BORDER_COLOR:-$SURFACE1}"
export TRAY_BORDER_WIDTH="${TRAY_BORDER_WIDTH:-1}"
export TRAY_RADIUS="${TRAY_RADIUS:-24}"

# Dock tiles
export TILE_IDLE_COLOR="${TILE_IDLE_COLOR:-$SURFACE1}"        # an app that isn't open
export TILE_BORDER_COLOR="${TILE_BORDER_COLOR:-$SURFACE1}"
export TILE_BORDER_WIDTH="${TILE_BORDER_WIDTH:-0}"
export THEME_TILE_RADIUS="${THEME_TILE_RADIUS:-15}"
export ICON_STYLE="${ICON_STYLE:-color}"        # color: each app's own color · mono: all TEXT
export RUNNING_STYLE="${RUNNING_STYLE:-fill}"   # fill: tile takes the app's color
                                                # invert: tile turns TEXT, icon BASE
                                                # outline: tile keeps its color, 2pt border in the app's color
export FRONT_RING_COLOR="${FRONT_RING_COLOR:-$TEXT}"  # ring around the app in front

# Menus (dock and menu bar)
export MENU_COLOR="${MENU_COLOR:-$SURFACE0}"
export MENU_BORDER_COLOR="${MENU_BORDER_COLOR:-$SURFACE1}"
export MENU_RADIUS="${MENU_RADIUS:-14}"

# Menu bar pills
export PILL_COLOR="${PILL_COLOR:-$SURFACE0}"
export PILL_HOVER_COLOR="${PILL_HOVER_COLOR:-$SURFACE1}"
export PILL_BORDER_COLOR="${PILL_BORDER_COLOR:-$SURFACE1}"
export PILL_BORDER_WIDTH="${PILL_BORDER_WIDTH:-0}"
export PILL_RADIUS="${PILL_RADIUS:-12}"
export APPLE_COLOR="${APPLE_COLOR:-$PINK}"            # the Apple pill
export APPLE_ICON_COLOR="${APPLE_ICON_COLOR:-$BASE}"

# Text. Icons always use the Nerd Font; labels (clock, battery, menus, app names)
# use the theme's typeface: a family plus the style names for its bold and regular
export LABEL_FONT="${LABEL_FONT:-Hack Nerd Font}"
export LABEL_BOLD="${LABEL_BOLD:-Bold}"
export LABEL_REGULAR="${LABEL_REGULAR:-Regular}"

# Optional: empty tiles in several colors, one after another (a collage), and
# scenery behind the tray, drawn by bin/dockart for themes it knows
export TILE_IDLE_COLORS="${TILE_IDLE_COLORS:-}"
export RUNNING_COLOR="${RUNNING_COLOR:-}"   # with RUNNING_STYLE=fill: one color for every open app (empty: each app's own)
