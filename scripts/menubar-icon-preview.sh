#!/usr/bin/env bash
# Preview the menu bar icon at real size beside system icons (light and dark bars, 2x).
#   scripts/menubar-icon-preview.sh out.png           current icon only
#   scripts/menubar-icon-preview.sh out.png <git-ref> previous icon from <git-ref>, then current
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:?usage: menubar-icon-preview.sh out.png [git-ref]}"
REF="${2:-}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SOURCES=("$ROOT_DIR/Sources/WhyText/UI/MenuBarIcon.swift" "$ROOT_DIR/scripts/menubar-icon-preview.swift")
FLAGS=()
if [[ -n "$REF" ]]; then
  git -C "$ROOT_DIR" show "$REF:Sources/WhyText/UI/MenuBarIcon.swift" \
    | sed 's/enum MenuBarIcon/enum PreviousMenuBarIcon/' > "$WORK/PreviousMenuBarIcon.swift"
  SOURCES+=("$WORK/PreviousMenuBarIcon.swift")
  FLAGS+=(-D PREVIOUS)
fi
swiftc -parse-as-library ${FLAGS[@]+"${FLAGS[@]}"} "${SOURCES[@]}" -o "$WORK/preview"
"$WORK/preview" "$OUT"
