#!/usr/bin/env bash
# Capture snapshot-mode screenshots of any commit, including ones older than snapshot mode.
#   scripts/snapshot-at.sh <git-ref> <output-dir>
# WHYTEXT_SNAPSHOT_* filters pass through (see UISnapshotHarness.swift). The current
# snapshot code is overlaid on a temporary checkout of <git-ref>, built, run, and removed.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF="${1:?usage: snapshot-at.sh <git-ref> <output-dir>}"
OUT="${2:?usage: snapshot-at.sh <git-ref> <output-dir>}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
WORK="$(mktemp -d)/checkout"
cleanup() { git -C "$ROOT_DIR" worktree remove --force "$WORK" 2>/dev/null || true; }
trap cleanup EXIT

git -C "$ROOT_DIR" worktree add -q --detach "$WORK" "$REF"
python3 "$ROOT_DIR/scripts/snapshot-at-patch.py" "$WORK" "$ROOT_DIR"
echo "Building $REF…"
swift build --package-path "$WORK" --cache-path /tmp/swiftpm-cache 2>&1 | grep -E "error|Compiling|Build complete" | tail -5
BIN="$(swift build --package-path "$WORK" --cache-path /tmp/swiftpm-cache --show-bin-path)/WhyText"
# Run from /tmp so the app never picks up files from the checkout as its working directory.
(cd /tmp && WHYTEXT_SNAPSHOT_DIR="$OUT" "$BIN")
echo "$(ls "$OUT" | wc -l | tr -d ' ') screenshots in $OUT"
