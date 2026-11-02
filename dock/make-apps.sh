#!/bin/bash
# Builds apps.txt for the Mocha dock from the apps in your current macOS Dock.
#   make-apps.sh <known-apps.txt> <output apps.txt>
KNOWN="$1"
OUT="$2"
PALETTE=(PINK PEACH GREEN TEAL BLUE LAVENDER MAUVE YELLOW RED)

urldecode() { local s="${1//+/ }"; printf '%b' "${s//%/\\x}"; }

# Finder always comes first, like the real Dock
PATHS=("/System/Library/CoreServices/Finder.app")
while IFS= read -r url; do
  path="$(urldecode "${url#file://}")"
  PATHS+=("${path%/}")
done < <(defaults read com.apple.dock persistent-apps 2>/dev/null \
         | sed -n 's/.*"_CFURLString" = "\(file:[^"]*\)";.*/\1/p')

{
  echo "# key|app path|bundle id|icon|color — one app per line, left to right."
  echo "# Right-click a tile in the dock to move, remove or add apps."
  KEYS=" "
  i=0
  for path in "${PATHS[@]}"; do
    [ -d "$path" ] || continue
    bundle="$(defaults read "$path/Contents/Info" CFBundleIdentifier 2>/dev/null)"
    [ -z "$bundle" ] && continue
    name="$(basename "$path" .app)"
    key="$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"
    [ -z "$key" ] && key="app"
    while [[ "$KEYS" == *" $key "* ]]; do key="${key}x"; done
    KEYS+="$key "

    match="$(grep -F "$bundle|" "$KNOWN" | head -1)"
    if [ -n "$match" ]; then
      icon="$(echo "$match" | cut -d'|' -f2)"
      color="$(echo "$match" | cut -d'|' -f3)"
    else
      icon="$(echo "$name" | cut -c1 | tr '[:lower:]' '[:upper:]')"
      color="${PALETTE[$(( i % ${#PALETTE[@]} ))]}"
    fi
    echo "$key|$path|$bundle|$icon|$color"
    i=$(( i + 1 ))
  done
} > "$OUT"
