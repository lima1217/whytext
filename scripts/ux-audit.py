#!/usr/bin/env python3
"""UI audit for WhyText: font sizes per view, styling that needs a reason,
color contrast of the design tokens, and number formatting smells.

Run from the repo root:  python3 scripts/ux-audit.py
Exit code is the number of hard violations (0 = clean).
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UI = ROOT / "Sources/WhyText"
CORE = ROOT / "Sources/WhyTextCore"

# Views whose fonts are resolved through tokens; map token -> size.
TOKEN_SIZES = {}
tokens_src = (UI / "UI/DesignTokens.swift").read_text()
for name, size in re.findall(r"static let (\w+) = Font\.system\(size: ([\d.]+)", tokens_src):
    TOKEN_SIZES[name] = float(size)
panel_src = (UI / "UI/FloatingPanelView.swift").read_text()
PANEL_SIZES = {n: float(v) for n, v in re.findall(r"static let (\w+FontSize|iconSize): CGFloat = ([\d.]+)", panel_src)}

# A "view" here = one file, which is one screen or one surface in this codebase.
SURFACES = {
    "Settings (all panes share chrome)": [
        "UI/SettingsDesignSystem.swift", "UI/SettingsView.swift", "UI/GeneralSettingsView.swift",
        "UI/ShortcutsSettingsView.swift", "UI/TranslationSettingsView.swift",
        "UI/ProvidersSettingsView.swift", "UI/PromptsSettingsView.swift",
        "UI/MemorySettingsView.swift", "UI/PermissionsSettingsView.swift",
        "UI/UpdatesSettingsView.swift", "UI/HotKeyRecorderView.swift",
    ],
    "Floating panel": ["UI/FloatingPanelView.swift", "UI/DesignControls.swift"],
    "Selection bubble": ["Services/SelectionBubbleController.swift"],
}

TEXT_ICON_HINT = re.compile(r"Image\(systemName|chevron|symbol", re.I)


def text_font_sizes(path: Path):
    """Sizes applied to text (icons excluded by a nearby Image(systemName:) heuristic)."""
    sizes = []
    lines = path.read_text().splitlines()
    for i, line in enumerate(lines):
        context = "\n".join(lines[max(0, i - 3): i + 1])
        is_icon = bool(TEXT_ICON_HINT.search(context)) and "Text(" not in context
        for m in re.finditer(r"\.system\(size: ([\w.]+)", line):
            raw = m.group(1)
            val = PANEL_SIZES.get(raw.split(".")[-1]) if not raw[0].isdigit() else float(raw)
            if val is None:
                continue
            sizes.append((val, i + 1, "icon" if is_icon else "text"))
        for m in re.finditer(r"AstryxFont\.(\w+)", line):
            if m.group(1) in TOKEN_SIZES:
                sizes.append((TOKEN_SIZES[m.group(1)], i + 1, "text"))
        if re.search(r"\.font\(\.(body|headline|title\d?|callout|caption2?|footnote|subheadline)\b", line):
            sizes.append((13.0, i + 1, "text"))
    return sizes


def srgb_lum(hex_):
    h = hex_.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    a = int(h[6:8], 16) / 255 if len(h) == 8 else 1.0
    return (r, g, b), a


def blend(fg, a, bg):
    return tuple(f * a + b * (1 - a) for f, b in zip(fg, bg))


def lum(rgb):
    def ch(c):
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(c1, c2):
    l1, l2 = sorted((lum(c1), lum(c2)), reverse=True)
    return (l1 + 0.05) / (l2 + 0.05)


def main():
    violations = 0
    print("# WhyText UI audit\n")

    print("## Text font sizes per surface (limit 4)\n")
    for surface, files in SURFACES.items():
        found = {}
        for f in files:
            for size, line, kind in text_font_sizes(UI / f):
                if kind == "text":
                    found.setdefault(size, []).append(f"{Path(f).name}:{line}")
        sizes = sorted(found)
        flag = "OK" if len(sizes) <= 4 else "OVER"
        if flag == "OVER":
            violations += 1
        print(f"- {surface}: {len(sizes)} sizes {sizes} [{flag}]")
        for s in sizes:
            print(f"    {s:g}pt: {', '.join(found[s][:6])}{' …' if len(found[s]) > 6 else ''}")
    print()

    print("## Styling that needs a written reason\n")
    patterns = {
        "italic": r"\.italic\(|\bitalic\b\)",
        "uppercase": r"uppercased\(\)|textCase\(\.upper",
        "middle dot": r"·",
        "monospaced": r"monospaced|\.monospaced\b|design: \.monospaced",
    }
    allowed_mono = re.compile(r"monospacedDigit|Base URL|baseURL|model|apiKey|API Key|TextEditor|bodyMono|Bundle|report|Diagnostics|path", re.I)
    for name, pat in patterns.items():
        hits = []
        for path in list(UI.rglob("*.swift")) + list(CORE.rglob("*.swift")):
            if "Localization" in str(path) and name == "middle dot":
                continue
            for i, line in enumerate(path.read_text().splitlines(), 1):
                if line.strip().startswith("//"):
                    continue
                if re.search(pat, line):
                    ctx = path.read_text().splitlines()[max(0, i - 8): i]
                    reason = {"monospaced": "Monospaced:", "italic": "Italic:", "middle dot": "Middle dot:", "uppercase": "Uppercase:"}[name]
                    justified = any(reason in c for c in ctx) or (name == "monospaced" and any(allowed_mono.search(c) for c in ctx))
                    hits.append((path.relative_to(ROOT), i, justified, line.strip()[:90]))
        unjustified = [h for h in hits if not h[2]]  # a "<Kind>: reason" comment within 8 lines justifies a hit
        violations += len(unjustified)
        print(f"- {name}: {len(hits)} hits, {len(unjustified)} without an obvious reason")
        for p, i, ok, text in hits:
            print(f"    {'  ' if ok else '! '}{p}:{i}  {text}")
    # Middle dots in user-facing strings
    dots = []
    for path in CORE.glob("Localization/*.swift"):
        for i, line in enumerate(path.read_text().splitlines(), 1):
            if "·" in line:
                dots.append(f"{path.name}:{i}")
    print(f"- middle dot in strings: {len(dots)} {dots[:8]}")
    violations += len(dots)
    print()

    print("## Token contrast (WCAG 2.2: text >= 4.5, large text/icons >= 3)\n")
    colors = dict(re.findall(r'static let (\w+) = Color\.dynamic\(light: "(#\w+)", dark: "#\w+"\)', tokens_src))
    dark = dict(re.findall(r'static let (\w+) = Color\.dynamic\(light: "#\w+", dark: "(#\w+)"\)', tokens_src))
    # macOS windowBackgroundColor (Sonoma): light #ECECEC, dark #1E1E1E; grouped form rows are #FFFFFF / #2A2A2A.
    surfaces = {"light window": "#ECECEC", "light row": "#FFFFFF", "dark window": "#1E1E1E", "dark row": "#2A2A2A"}
    text_tokens = [t for t in ("textPrimary", "textSecondary", "textDisabled", "success", "error", "warning", "accentText") if t in colors]
    for t in text_tokens:
        row = []
        for sname, shex in surfaces.items():
            src = colors[t] if sname.startswith("light") else dark[t]
            fg, a = srgb_lum(src)
            bg, _ = srgb_lum(shex)
            ratio = contrast(blend(fg, a, bg), bg)
            need = 3.0 if t == "textDisabled" else 4.5
            mark = "" if ratio >= need else " !"
            if ratio < need and t != "textDisabled":
                violations += 1
            row.append(f"{sname} {ratio:.2f}{mark}")
        print(f"- {t}: " + ", ".join(row))
    # Warm-gray check: neutral grays should lean warm (R >= B).
    print()
    print("## Gray temperature (R-B > 0 is warm)\n")
    for t in ("textPrimary", "textSecondary", "textDisabled", "borderEmphasized", "border"):
        for mode, table in (("light", colors), ("dark", dark)):
            if t in table:
                (r, g, b), _ = srgb_lum(table[t])
                d = round((r - b) * 255)
                tag = "warm" if d > 0 else ("neutral" if d == 0 else "COOL")
                print(f"- {t} {mode} {table[t]}: R-B={d} {tag}")
    print()

    print("## Numbers built by string interpolation (should use a formatter)\n")
    num = re.compile(r'L10n\.f\([^)]*String\((?!localized)[^)]*\)|"\\\(Int\([^)]*\* ?100\)\)%"|"\\\(Int\([^)]*\)\) pt"|String\(format: "%\.')
    for path in UI.rglob("*.swift"):
        for i, line in enumerate(path.read_text().splitlines(), 1):
            # HTTP status codes are identifiers, never grouped; debug logs aren't UI.
            if num.search(line) and "HTTP" not in line and "DebugLog" not in path.read_text().splitlines()[max(0, i - 3)] and "mouseUp" not in line:
                print(f"  ! {path.relative_to(ROOT)}:{i}  {line.strip()[:100]}")
                violations += 1
    print()
    print(f"Hard violations: {violations}")
    return violations


if __name__ == "__main__":
    sys.exit(min(main(), 255))
