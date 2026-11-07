#!/usr/bin/env bash
# Cut a WhyText release: bump VERSION, wait for green CI, build, zip, verify, publish.
#
#   scripts/release.sh <version> <build> <changes.md>             publish
#   scripts/release.sh <version> <build> <changes.md> --dry-run   build and verify only
#
# <changes.md> is the "## Changes" section of the release notes (user-facing, English).
# This script appends Verification (from the checks it ran) and Install.
# A dry run commits, pushes and publishes nothing, and restores VERSION afterwards.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${1:?usage: release.sh <version> <build> <changes.md> [--dry-run]}"
BUILD="${2:?usage: release.sh <version> <build> <changes.md> [--dry-run]}"
CHANGES="${3:?usage: release.sh <version> <build> <changes.md> [--dry-run]}"
DRY_RUN=false
[[ "${4:-}" == "--dry-run" ]] && DRY_RUN=true

TAG="v$VERSION"
ZIP="dist/WhyText-$VERSION-mac.zip"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

step() { printf '\n==> %s\n' "$*"; }
fail() { printf 'release: %s\n' "$*" >&2; exit 1; }

# --- Preconditions ---------------------------------------------------------
step "Checking preconditions"
[[ -f "$CHANGES" ]] || fail "changes file not found: $CHANGES"
grep -q '^## Changes' "$CHANGES" || fail "$CHANGES must start its section with '## Changes'"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must look like 1.2.3"
[[ "$BUILD" =~ ^[0-9]+$ ]] || fail "build must be a number"
gh auth status >/dev/null 2>&1 || fail "gh is not signed in"
git fetch -q origin main --tags
if $DRY_RUN; then
  [[ -z "$(git status --porcelain)" ]] || echo "Dry run: working tree has uncommitted changes; they are included in the build."
else
  [[ -z "$(git status --porcelain)" ]] || fail "working tree is not clean"
  [[ "$(git branch --show-current)" == "main" ]] || fail "not on main"
  [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "main is not in sync with origin/main"
fi
! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || fail "tag $TAG already exists"

CURRENT_BUILD="$(sed -n '2p' VERSION | tr -d '[:space:]')"
(( BUILD > CURRENT_BUILD )) || fail "build $BUILD must be greater than the current build $CURRENT_BUILD"

PREVIOUS_TAG="$(gh release view --json tagName --jq .tagName)"
echo "Previous release: $PREVIOUS_TAG"

# --- Local checks ----------------------------------------------------------
step "Running smoke tests and UI audit"
swift run --cache-path /tmp/swiftpm-cache WhyTextCoreSmokeTests | tail -1
python3 scripts/ux-audit.py >/dev/null || fail "UI audit has violations: run python3 scripts/ux-audit.py"

# --- Version bump and CI ---------------------------------------------------
step "Setting VERSION to $VERSION ($BUILD)"
ORIGINAL_VERSION="$(cat VERSION)"
printf '%s\n%s\n' "$VERSION" "$BUILD" > VERSION

if $DRY_RUN; then
  trap 'printf "%s\n" "$ORIGINAL_VERSION" > "$ROOT_DIR/VERSION"; rm -rf "$WORK"' EXIT
  echo "Dry run: VERSION will be restored; skipping commit, push and CI."
else
  git add VERSION
  git commit -q -m "Bump version to $VERSION ($BUILD)"
  git push -q origin main
  SHA="$(git rev-parse HEAD)"

  step "Waiting for CI on ${SHA:0:7}"
  RUN_ID=""
  for _ in $(seq 1 30); do
    RUN_ID="$(gh run list --commit "$SHA" --workflow CI --json databaseId --jq '.[0].databaseId // empty')"
    [[ -n "$RUN_ID" ]] && break
    sleep 5
  done
  [[ -n "$RUN_ID" ]] || fail "no CI run appeared for $SHA"
  gh run watch "$RUN_ID" --exit-status --interval 20 >/dev/null \
    || fail "CI did not pass: $(gh run view "$RUN_ID" --json url --jq .url). VERSION is committed and pushed; fix CI, then rerun from the build step by hand."
  echo "CI passed: run $RUN_ID"
fi

# --- Build and package -----------------------------------------------------
step "Building"
./scripts/build-app.sh | tail -2
codesign --verify --deep --strict dist/WhyText.app

step "Packaging $ZIP"
rm -f "$ZIP"
# ditto keeps the bundle's signature and symlinks intact; the in-app updater unpacks with ditto too.
ditto -c -k --keepParent dist/WhyText.app "$ZIP"

# --- Verify the zip the way the updater will see it --------------------------
step "Verifying the packaged app"
ditto -x -k "$ZIP" "$WORK/new"
APP="$WORK/new/WhyText.app"
GOT_VERSION="$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString)"
GOT_BUILD="$(defaults read "$APP/Contents/Info.plist" CFBundleVersion)"
[[ "$GOT_VERSION" == "$VERSION" && "$GOT_BUILD" == "$BUILD" ]] || fail "zip contains $GOT_VERSION ($GOT_BUILD), expected $VERSION ($BUILD)"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/WhyText")"
[[ "$ARCHS" == *x86_64* && "$ARCHS" == *arm64* ]] || fail "expected a universal binary, got: $ARCHS"
codesign --verify --deep --strict "$APP"

# The updater only installs an app that satisfies the running app's designated
# requirement (same bundle ID and certificate), so check against the last release.
gh release download "$PREVIOUS_TAG" --pattern 'WhyText-*-mac.zip' --dir "$WORK/prev-zip"
ditto -x -k "$WORK"/prev-zip/*.zip "$WORK/prev"
REQUIREMENT="$(codesign -d -r- "$WORK/prev/WhyText.app" 2>&1 | sed -n 's/^designated => //p')"
[[ -n "$REQUIREMENT" ]] || fail "could not read the designated requirement of $PREVIOUS_TAG"
codesign --verify -R="$REQUIREMENT" "$APP" || fail "the new app does not satisfy $PREVIOUS_TAG's designated requirement; in-app updates would refuse it"

SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "Version $GOT_VERSION ($GOT_BUILD), $ARCHS, satisfies $PREVIOUS_TAG's requirement"
echo "SHA-256 $SHA256"

# --- Release notes ---------------------------------------------------------
NOTES="$WORK/notes.md"
{
  cat "$CHANGES"
  cat <<NOTES

## Verification
- Built with \`./scripts/build-app.sh\`; CI (build and WhyTextCore smoke tests) passed on the release commit.
- Confirmed architectures: \`$ARCHS\` via \`lipo\`.
- Verified code signature with \`codesign --verify --deep --strict\`. Confirmed the app extracted from the zip with \`ditto -x -k\` (the in-app updater's method) reports $VERSION ($BUILD) and satisfies the ${PREVIOUS_TAG#v} app's designated requirement (same bundle ID and certificate), so in-app updates accept it.
- Ran WhyTextCore smoke tests and the UI audit (\`scripts/ux-audit.py\`).

SHA-256 of \`WhyText-$VERSION-mac.zip\`: \`$SHA256\`

## Install
**From 0.4.1 or later:** use **Install Update $VERSION…** in the menu bar (versions before 0.7.0 show **Update to $VERSION…**), or **Install Update** in Settings. WhyText downloads, checks, replaces itself, and relaunches.

**New install:** download \`WhyText-$VERSION-mac.zip\`, unzip, and move \`WhyText.app\` to Applications. macOS 13+ required.

WhyText is not notarized, so macOS blocks the first launch:
- macOS 15 and later: open it once, then go to System Settings → Privacy & Security and click "Open Anyway".
- macOS 13 / 14: right-click \`WhyText.app\` → Open → Open.
- Or run \`xattr -dr com.apple.quarantine /Applications/WhyText.app\`.

When upgrading manually, quit WhyText and replace the old app; settings and API keys are kept.
NOTES
} > "$NOTES"

if $DRY_RUN; then
  cp "$NOTES" "dist/release-notes-$VERSION.md"
  step "Dry run complete"
  echo "Package: $ZIP"
  echo "Notes:   dist/release-notes-$VERSION.md"
  exit 0
fi

# --- Publish ---------------------------------------------------------------
step "Publishing $TAG"
gh release create "$TAG" "$ZIP" --target "$(git rev-parse HEAD)" --title "WhyText $VERSION" --notes-file "$NOTES"

step "Checking the published asset"
gh release download "$TAG" --pattern "WhyText-$VERSION-mac.zip" --dir "$WORK/published"
PUBLISHED="$(shasum -a 256 "$WORK/published/WhyText-$VERSION-mac.zip" | awk '{print $1}')"
[[ "$PUBLISHED" == "$SHA256" ]] || fail "published asset hash $PUBLISHED differs from local $SHA256"
[[ "$(gh release view --json tagName --jq .tagName)" == "$TAG" ]] || fail "$TAG is not marked as the latest release"
echo "Published $(gh release view "$TAG" --json url --jq .url)"
