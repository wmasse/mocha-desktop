#!/bin/bash
# Dock actions: menu.sh <action> <key>
#   open     launch or switch to the app (or open the Trash)
#   show     show the right-click menu
#   quit     ask the app to quit
#   finder   show the app in Finder
#   left / right   move the tile one place
#   remove   take the app off the dock
#   add      pick an app and add it after this tile (at the end for the trash)
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar-dock}"
PLUGIN_DIR="$CONFIG_DIR/plugins"
APPS_FILE="$CONFIG_DIR/apps.txt"
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/glyphs.sh"

ACTION="$1"
KEY="$2"
ITEM="app.$KEY"
[ "$KEY" = "trash" ] && ITEM="trash"

# Read the app list (comment lines are kept as the file's header)
HEADER="$(grep '^#' "$APPS_FILE")"
LINES=()
INDEX=-1
while IFS= read -r line; do
  case "$line" in ''|\#*) continue ;; esac
  [ "${line%%|*}" = "$KEY" ] && INDEX=${#LINES[@]}
  LINES+=("$line")
done < "$APPS_FILE"
LAST=$(( ${#LINES[@]} - 1 ))

field() { echo "${LINES[$INDEX]}" | cut -d'|' -f"$1"; }

save_and_reload() {
  { echo "$HEADER"; printf '%s\n' "${LINES[@]}"; } > "$APPS_FILE.tmp" && mv "$APPS_FILE.tmp" "$APPS_FILE"
  mochadock --reload
}

MENU_FILE="/tmp/mochadock-$USER/menu-open"

# Theme colors you can change from the theme screen; saved per theme
CUSTOM_FILE="$CONFIG_DIR/custom-$THEME.sh"
COLOR_ROLES="TRAY_COLOR TILE_IDLE_COLOR TEXT BASE"
role_label() {
  case "$1" in
    TRAY_COLOR)      echo "Tray" ;;
    TILE_IDLE_COLOR) echo "Empty tiles" ;;
    TEXT)            echo "Text & icons" ;;
    BASE)            echo "Icons on open apps" ;;
  esac
}

# Themes and colors are shared with the menu bar, so redraw both
reload_bars() {
  mochadock --reload
  sketchybar --reload 2>/dev/null
}

close_menu() {
  mochadock --set "$ITEM" popup.drawing=off --remove '/menu\..*/' 2>/dev/null
  rm -f "$MENU_FILE"
}

is_running() { [ -n "$(lsappinfo find bundleid="$1")" ]; }

menu_entry() { # id icon color label action
  MENU+=(--add item "menu.$1" popup."$ITEM"
         --set "menu.$1" icon="$2" icon.color="$3" icon.width=30 icon.align=left
               icon.font.size=16 label="$4" label.drawing=on label.padding_right=18
               icon.padding_left=6 background.drawing=off padding_left=12 padding_right=12
               click_script="$PLUGIN_DIR/menu.sh $5 $KEY")
}

case "$ACTION" in
  open)
    if [ "$KEY" = "trash" ]; then
      open "$HOME/.Trash"
    else
      open -b "$(field 3)" 2>/dev/null || open "$(field 2)"
    fi
    close_menu
    ;;

  show)
    # The trash opens the open-apps panel (dockdrop/apps.swift), whose footer has
    # the trash's own actions; MENU_ONLY=1 gets this menu instead (its Theme button)
    if [ "$KEY" = "trash" ] && [ -z "$MENU_ONLY" ] && [ -x "$CONFIG_DIR/bin/dockdrop" ]; then
      mochadock --set '/app\..*/' popup.drawing=off --set trash popup.drawing=off --remove '/menu\..*/' 2>/dev/null
      rm -f "$MENU_FILE"
      "$CONFIG_DIR/bin/dockdrop" apps
      exit 0
    fi
    MENU=(--set '/app\..*/' popup.drawing=off --set trash popup.drawing=off
          --remove '/menu\..*/')
    # The app-name label already in this tile's popup serves as the menu's header
    if [ "$KEY" = "trash" ]; then
      menu_entry open "$G_FOLDER" $BLUE "Open Trash" open
      menu_entry add "$G_ADD" $GREEN "Add app…" add
    else
      if is_running "$(field 3)"; then
        menu_entry quit "$G_QUIT" $RED "Quit" quit
      else
        menu_entry open "$G_OPEN" $GREEN "Open" open
      fi
      menu_entry finder "$G_FINDER" $BLUE "Show in Finder" finder
      [ "$INDEX" -gt 0 ] && menu_entry left "$G_LEFT" $MAUVE "Move left" left
      [ "$INDEX" -lt "$LAST" ] && menu_entry right "$G_RIGHT" $MAUVE "Move right" right
      menu_entry add "$G_ADD" $GREEN "Add app here…" add
      menu_entry remove "$G_REMOVE" $RED "Remove from Dock" remove
    fi
    menu_entry theme "$G_THEME" $MAUVE "Theme…" gallery
    mochadock "${MENU[@]}" --set "$ITEM" popup.drawing=on 2>/dev/null
    mkdir -p "$(dirname "$MENU_FILE")" && echo "$ITEM" > "$MENU_FILE"
    ;;

  gallery)
    # The theme gallery (dockdrop/gallery.swift); the list below is the fallback
    close_menu
    if [ -x "$CONFIG_DIR/bin/dockdrop" ] && pgrep -f "$CONFIG_DIR/bin/dockdrop" >/dev/null; then
      "$CONFIG_DIR/bin/dockdrop" themes
    else
      MENU_ONLY=1 "$0" show "$KEY" && "$0" themes "$KEY"
    fi
    ;;

  themes)
    # Swap this menu's entries for the themes, by section. Each row
    # previews its theme: scenes show a strip of their scenery, the others their
    # tray color and edge. Colors are on their own screen (Customize colors…).
    MENU=(--remove '/menu\..*/')
    menu_entry back "$G_BACK" $OVERLAY "Back" show
    CLASSIC="mocha latte graphite paper nord terminal"
    SCENES="harvest dusklake alpenglow nightgarden sakura aurora dune tide velvet matcha nebula orbit"
    CANDY_ORBIT="sticker sherbet daybreak gasgiant ring rocket cumulus starlight redplanet moonlight"
    STYLES="broadsheet saddle swiss phosphor pop precision obsidian millennium bento riso"
    EFFECTS="current claymation ferrofluid popup livewire hourglass overgrowth lava campfire jelly"
    # any other theme files (your own) go with the classics
    for file in "$CONFIG_DIR"/themes/*.sh; do
      key="$(basename "$file" .sh)"
      [[ " $CLASSIC $SCENES $CANDY_ORBIT $STYLES $EFFECTS " == *" $key "* ]] || CLASSIC+=" $key"
    done
    mkdir -p "$CONFIG_DIR/cache"
    for section in CLASSIC SCENES CANDY_ORBIT STYLES EFFECTS; do
      MENU+=(--add item "menu.section_$section" popup."$ITEM"
             --set "menu.section_$section" icon.drawing=off label="${section//_/ }" label.drawing=on
                   label.color=$OVERLAY label.font.size=11 label.padding_left=12 background.drawing=off
                   padding_left=8 width=250)
      for NAME_KEY in ${!section}; do
        file="$CONFIG_DIR/themes/$NAME_KEY.sh"
        [ -f "$file" ] || continue
        # Read each theme in a clean shell, so the current theme's settings can't leak in
        read -r T_TRAY T_BORDER T_BORDER_W T_RADIUS T_TEXT T_ACCENT T_NAME <<< "$(env -i HOME="$HOME" /bin/bash -c '
          source "$1"; THEME_DIR="$2"; source "$2/style.sh"
          echo "$TRAY_COLOR $TRAY_BORDER_COLOR $TRAY_BORDER_WIDTH $TRAY_RADIUS $TEXT $APPLE_COLOR $THEME_NAME"' _ "$file" "$CONFIG_DIR")"
        if [ "$NAME_KEY" = "$THEME" ]; then ICON="$G_CHECK"; else ICON="$G_SWATCH"; fi
        [ "$T_RADIUS" -gt 10 ] && T_RADIUS=10
        [ "$T_BORDER_W" -lt 1 ] && T_BORDER_W=1
        menu_entry "theme_$NAME_KEY" "$ICON" "$T_ACCENT" "$T_NAME" "theme-$NAME_KEY"
        MENU+=(--set "menu.theme_$NAME_KEY" label.color="$T_TEXT" width=262 padding_left=12 padding_right=12
                     icon.width=22 icon.padding_left=14 label.padding_left=10 label.padding_right=14
                     background.drawing=on background.color="$T_TRAY" background.height=30
                     background.corner_radius="$T_RADIUS" background.border_width="$T_BORDER_W"
                     background.border_color="$T_BORDER")
        # A strip of the scenery behind the scene themes' rows
        PREVIEW="$CONFIG_DIR/cache/preview-$NAME_KEY.png"
        [ -f "$PREVIEW" ] || "$CONFIG_DIR/bin/dockart" "$NAME_KEY" 250 "$PREVIEW" 30 2>/dev/null || rm -f "$PREVIEW"
        [ -f "$PREVIEW" ] && MENU+=(--set "menu.theme_$NAME_KEY" background.image="$PREVIEW"
                                    background.image.scale=0.5 background.image.corner_radius="$T_RADIUS"
                                    background.image.drawing=on)
      done
    done
    menu_entry customize "$G_THEME" $MAUVE "Customize colors…" customize
    mochadock "${MENU[@]}" 2>/dev/null
    ;;

  customize)
    # This theme's colors: each row shows its color now; click to pick a new one
    MENU=(--remove '/menu\..*/')
    menu_entry back "$G_BACK" $OVERLAY "Back" themes
    MENU+=(--add item menu.customize popup."$ITEM"
           --set menu.customize icon.drawing=off label="${THEME_NAME}" label.drawing=on
                 label.color=$OVERLAY label.font.size=11 label.padding_left=12 background.drawing=off
                 padding_left=8 width=250)
    for role in $COLOR_ROLES; do
      menu_entry "color_$role" " " "${!role}" "$(role_label "$role")" "color-$role"
      # The swatch is the icon's own background, outlined so it shows even when
      # the color matches the menu
      MENU+=(--set "menu.color_$role" icon.width=18 icon.padding_left=14 icon.padding_right=0
                   label.padding_left=14 width=250
                   icon.background.drawing=on icon.background.color="${!role}" icon.background.height=18
                   icon.background.corner_radius=9 icon.background.border_width=1
                   icon.background.border_color=$OVERLAY)
    done
    [ -f "$CUSTOM_FILE" ] && menu_entry reset "$G_RESET" $RED "Reset colors" reset-colors
    mochadock "${MENU[@]}" 2>/dev/null
    ;;

  theme-*)
    echo "${ACTION#theme-}" > "$CONFIG_DIR/theme.txt"
    close_menu
    reload_bars
    ;;

  color-*)
    ROLE="${ACTION#color-}"
    close_menu
    # macOS's color picker, starting from the current color (16-bit channels)
    HEX="${!ROLE: -6}"   # last six hex digits; see-through colors have a different prefix
    R=$(( 16#${HEX:0:2} * 257 )); G=$(( 16#${HEX:2:2} * 257 )); B=$(( 16#${HEX:4:2} * 257 ))
    PICKED="$(osascript -e 'activate' -e "choose color default color {$R, $G, $B}" 2>/dev/null)" || exit 0
    IFS=', ' read -r R G B <<< "$PICKED"
    NEW="$(printf '0xff%02x%02x%02x' $(( R / 257 )) $(( G / 257 )) $(( B / 257 )))"
    # Keep one line per color in this theme's custom file
    { grep -v "^export $ROLE=" "$CUSTOM_FILE" 2>/dev/null; echo "export $ROLE=$NEW"; } > "$CUSTOM_FILE.tmp"
    mv "$CUSTOM_FILE.tmp" "$CUSTOM_FILE"
    reload_bars
    ;;

  reset-colors)
    rm -f "$CUSTOM_FILE"
    close_menu
    reload_bars
    ;;

  quit)
    close_menu
    osascript -e "tell application id \"$(field 3)\" to quit" >/dev/null 2>&1
    ;;

  finder)
    close_menu
    open -R "$(field 2)"
    ;;

  left|right)
    [ "$INDEX" -lt 0 ] && exit 0
    if [ "$ACTION" = "left" ]; then OTHER=$(( INDEX - 1 )); else OTHER=$(( INDEX + 1 )); fi
    [ "$OTHER" -lt 0 ] || [ "$OTHER" -gt "$LAST" ] && exit 0
    TMP="${LINES[$INDEX]}"; LINES[$INDEX]="${LINES[$OTHER]}"; LINES[$OTHER]="$TMP"
    save_and_reload
    ;;

  remove)
    [ "$INDEX" -lt 0 ] && exit 0
    KEPT=()
    for i in "${!LINES[@]}"; do [ "$i" -ne "$INDEX" ] && KEPT+=("${LINES[$i]}"); done
    LINES=("${KEPT[@]}")
    save_and_reload
    ;;

  add)
    close_menu
    APP_PATH="$(osascript -e 'activate' \
      -e 'POSIX path of (choose application with title "Add to dock" with prompt "Pick an app to add to the dock:" as alias)' 2>/dev/null)" || exit 0
    APP_PATH="${APP_PATH%/}"
    BUNDLE="$(defaults read "$APP_PATH/Contents/Info" CFBundleIdentifier 2>/dev/null)"
    [ -z "$BUNDLE" ] && exit 0
    printf '%s\n' "${LINES[@]}" | cut -d'|' -f3 | grep -qxF "$BUNDLE" && exit 0  # already on the dock

    APP_NAME="$(basename "$APP_PATH" .app)"
    NEW_KEY="$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"
    [ -z "$NEW_KEY" ] && NEW_KEY="app"
    while printf '%s\n' "${LINES[@]}" | grep -q "^$NEW_KEY|"; do NEW_KEY="${NEW_KEY}x"; done
    LETTER="$(echo "$APP_NAME" | cut -c1 | tr '[:lower:]' '[:upper:]')"
    PALETTE=(PINK PEACH GREEN TEAL BLUE LAVENDER MAUVE YELLOW RED)
    COLOR="${PALETTE[$(( ${#LINES[@]} % ${#PALETTE[@]} ))]}"
    NEW_LINE="$NEW_KEY|$APP_PATH|$BUNDLE|$LETTER|$COLOR"

    # Insert after the clicked tile, or at the end when added from the trash
    [ "$INDEX" -lt 0 ] && INDEX=$LAST
    NEW=()
    for i in "${!LINES[@]}"; do
      NEW+=("${LINES[$i]}")
      [ "$i" -eq "$INDEX" ] && NEW+=("$NEW_LINE")
    done
    [ ${#LINES[@]} -eq 0 ] && NEW=("$NEW_LINE")
    LINES=("${NEW[@]}")
    save_and_reload
    ;;
esac
