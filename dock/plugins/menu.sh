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
COLOR_ROLES="SURFACE0 SURFACE1 TEXT BASE"
role_label() {
  case "$1" in
    SURFACE0) echo "Tray & menus" ;;
    SURFACE1) echo "Empty tiles" ;;
    TEXT)     echo "Text & front-app ring" ;;
    BASE)     echo "Icons on open apps" ;;
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
               icon.font.size=16 label="$4" label.drawing=on label.padding_right=12
               background.drawing=off padding_left=8 padding_right=8
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
    menu_entry theme "$G_THEME" $MAUVE "Theme…" themes
    mochadock "${MENU[@]}" --set "$ITEM" popup.drawing=on 2>/dev/null
    mkdir -p "$(dirname "$MENU_FILE")" && echo "$ITEM" > "$MENU_FILE"
    ;;

  themes)
    # Swap this menu's entries for the themes. Each row is drawn in its own
    # theme's colors, so the list doubles as a preview.
    MENU=(--remove '/menu\..*/')
    menu_entry back "$G_BACK" $OVERLAY "Back" show
    for file in "$CONFIG_DIR"/themes/*.sh; do
      NAME_KEY="$(basename "$file" .sh)"
      read -r T_BASE T_SURFACE T_TEXT T_ACCENT T_NAME <<< \
        "$(source "$file"; echo "$BASE $SURFACE1 $TEXT $MAUVE $THEME_NAME")"
      if [ "$NAME_KEY" = "$THEME" ]; then ICON="$G_CHECK"; else ICON="$G_SWATCH"; fi
      menu_entry "theme_$NAME_KEY" "$ICON" "$T_ACCENT" "$T_NAME" "theme-$NAME_KEY"
      MENU+=(--set "menu.theme_$NAME_KEY" label.color="$T_TEXT" width=230
                   background.drawing=on background.color="$T_BASE" background.height=30
                   background.corner_radius=8 background.border_width=1 background.border_color="$T_SURFACE")
    done

    # Customize: each row shows its color now; click to pick a new one
    MENU+=(--add item menu.customize popup."$ITEM"
           --set menu.customize icon.drawing=off label="CUSTOMIZE ${THEME_NAME}" label.drawing=on
                 label.color=$OVERLAY label.font.size=11 label.padding_left=10 background.drawing=off
                 padding_left=8)
    for role in $COLOR_ROLES; do
      menu_entry "color_$role" " " "${!role}" "$(role_label "$role")" "color-$role"
      # The swatch is the icon's own background, outlined so it shows even when
      # the color matches the menu
      MENU+=(--set "menu.color_$role" icon.width=18 icon.padding_left=10 icon.padding_right=0
                   label.padding_left=14
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
    HEX="${!ROLE#0xff}"
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
