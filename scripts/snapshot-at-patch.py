#!/usr/bin/env python3
"""Overlay the current snapshot mode onto an older checkout (used by snapshot-at.sh).

    python3 scripts/snapshot-at-patch.py <checkout> <current-repo>

Copies UISnapshotHarness.swift in, then adds whatever hooks the old code lacks.
Each patch is a no-op when the checkout already has the hook.
"""
import re
import shutil
import sys
from pathlib import Path

old, cur = Path(sys.argv[1]) / "Sources", Path(sys.argv[2]) / "Sources"
app = old / "WhyText"


def edit(rel, fn):
    p = app / rel
    s = p.read_text()
    p.write_text(fn(s))


# 1. The harness itself, minus features the old core lacks.
harness = (cur / "WhyText/Utils/UISnapshotHarness.swift").read_text()
if "pseudoLocalize" not in (old / "WhyTextCore/Localization/L10n.swift").read_text():
    harness = "\n".join(l for l in harness.splitlines() if "pseudoLocalize" not in l) + "\n"
    print("patched: no pseudo-language in this version (WHYTEXT_SNAPSHOT_PSEUDO is ignored)")
(app / "Utils").mkdir(exist_ok=True)
(app / "Utils/UISnapshotHarness.swift").write_text(harness)

# 2. Selecting a settings page: AppModel.settingsPane, or the view's own @State.
if "var settingsPane" in (app / "AppModel.swift").read_text():
    shutil.copy(cur / "WhyText/Utils/UISnapshotHooks.swift", app / "Utils/UISnapshotHooks.swift")
else:
    (app / "Utils/UISnapshotHooks.swift").write_text(
        "import Foundation\n\n@MainActor\nenum UISnapshotHooks {\n"
        "    static var pane: SettingsPane = .general\n"
        "    static func select(_ pane: SettingsPane, in model: AppModel) { Self.pane = pane }\n}\n")
    edit("UI/SettingsView.swift", lambda s: re.sub(
        r"(@State private var selection: SettingsPane = )\.general", r"\1UISnapshotHooks.pane", s))
    print("patched: settings page chosen through SettingsView's @State")

# 3. Entry point.
def hook_app(s):
    if "UISnapshotHarness" in s:
        return s
    print("patched: WhyTextApp starts the harness")
    return s.replace(
        "NSApplication.shared.setActivationPolicy(.accessory)\n",
        "NSApplication.shared.setActivationPolicy(.accessory)\n"
        "        if UISnapshotHarness.isActive {\n"
        "            let model = UISnapshotHarness.makeModel()\n"
        "            _appModel = StateObject(wrappedValue: model)\n"
        "            DispatchQueue.main.async { UISnapshotHarness.run(model: model) }\n"
        "        }\n", 1)
edit("WhyTextApp.swift", hook_app)

# 4. The bubble view was file-private before snapshot mode captured it.
edit("Services/SelectionBubbleController.swift",
     lambda s: s.replace("private struct SelectionBubbleBar", "struct SelectionBubbleBar"))
