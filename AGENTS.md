# WhyText

macOS menu bar app (SwiftUI + AppKit, SwiftPM). `Sources/WhyTextCore` holds pure logic and the interface strings; `Sources/WhyText` holds the app and its UI.

## Checks

- `swift build --cache-path /tmp/swiftpm-cache`
- `swift run --cache-path /tmp/swiftpm-cache WhyTextCoreSmokeTests` — includes translation coverage: every key in every language, no unused keys, matching placeholders.
- `swift run --cache-path /tmp/swiftpm-cache WhyTextStateMachineTests` — deterministic state-machine and cancellation tests for `Sources/WhyText`.
- `python3 scripts/ux-audit.py` — exit code is the violation count.
- `bash -n scripts/*.sh && shellcheck -S warning scripts/*.sh` — CI runs all five.

## Interface work

- **Before changing UI or copy**, read `docs/design/guidelines.md`: one accent, warm grays, flat surfaces, type scale, one verb per action, number formatting, when to confirm.
- **Strings**: the key is the Simplified Chinese text itself (`L10n.t("…")`); add the same key to all four tables in `Sources/WhyTextCore/Localization/`.
- **Seeing the UI**: snapshot mode renders every settings page, the result panel states and the bubble, then quits. It uses throwaway settings, never the user's.
  `WHYTEXT_SNAPSHOT_DIR=/tmp/shots .build/debug/WhyText` — filters and the pseudo-language are in the header of `Sources/WhyText/Utils/UISnapshotHarness.swift`.
- **Before/after for the user**: `scripts/snapshot-at.sh <git-ref> <dir>` captures any commit, even ones older than snapshot mode; capture old and new, then `uv run scripts/compare-report.py spec.json out.pdf` (spec format in its header).
- **Menu bar icon**: `scripts/menubar-icon-preview.sh out.png [git-ref]` shows it at real size beside system icons.

## Reviewing

Apply `CODING_STANDARDS.md` to the diff.

## Releasing

- Local build & replace `/Applications/WhyText.app`: `scripts/build-app.sh --install` (keeps the stable `WhyText Local Code Signing` identity so TCC grants survive).
- GitHub release: `scripts/release.sh <version> <build> <changes.md>` — bumps VERSION, waits for green CI, builds, verifies the zip against the previous release, publishes. Try `--dry-run` first.
