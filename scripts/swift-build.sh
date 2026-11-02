#!/bin/bash
# Compiles one Swift file into an executable.
#   swift-build.sh <output> <native|universal> <source.swift> [extra swiftc args...]
# Some Command Line Tools releases ship two module maps that both define
# SwiftBridging, which breaks every Swift build. If that happens, retry with an
# overlay that hides the duplicate for this build only (nothing on disk changes).
set -euo pipefail
OUT="$1"; ARCH="$2"; SRC="$3"; shift 3
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

compile() { # extra args for the workaround...
  if [ "$ARCH" = "universal" ]; then
    xcrun swiftc -O "$@" "${EXTRA[@]}" -target arm64-apple-macos13 -o "$TMP/arm64" "$SRC" &&
    xcrun swiftc -O "$@" "${EXTRA[@]}" -target x86_64-apple-macos13 -o "$TMP/x86_64" "$SRC" &&
    lipo -create "$TMP/arm64" "$TMP/x86_64" -output "$OUT"
  else
    xcrun swiftc -O "$@" "${EXTRA[@]}" -o "$OUT" "$SRC"
  fi
}

EXTRA=("$@")
[ ${#EXTRA[@]} -eq 0 ] && EXTRA=(-D MOCHA)   # keeps "${EXTRA[@]}" non-empty for bash 3.2 with set -u
mkdir -p "$(dirname "$OUT")"
if ! compile 2>"$TMP/err"; then
  if grep -q "redefinition of module 'SwiftBridging'" "$TMP/err"; then
    INCLUDE="$(cd "$(dirname "$(xcrun --find swiftc)")/../include/swift" && pwd)"
    : > "$TMP/empty.modulemap"
    cat > "$TMP/overlay.yaml" <<YAML
{ "version": 0, "case-sensitive": "false", "roots": [ { "type": "directory", "name": "$INCLUDE",
  "contents": [ { "type": "file", "name": "module.modulemap", "external-contents": "$TMP/empty.modulemap" } ] } ] }
YAML
    compile -vfsoverlay "$TMP/overlay.yaml" -Xcc -ivfsoverlay -Xcc "$TMP/overlay.yaml"
  else
    cat "$TMP/err" >&2
    exit 1
  fi
fi
echo "built $OUT"
