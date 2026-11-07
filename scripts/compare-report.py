#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = ["pillow", "reportlab"]
# ///
"""Before/after comparison PDF from two screenshot folders.

    uv run scripts/compare-report.py spec.json out.pdf

Screenshots usually come from the app's snapshot mode (see AGENTS.md): capture
the old commit into one folder and the new one into another.

spec.json:
{
  "title": "...", "subtitle": "...",
  "intro": ["paragraph", ...],                          # optional cover page
  "before": "/tmp/shots/before", "after": "/tmp/shots/after",
  "pages": [
    {"title": "...", "notes": ["..."], "before": "a.png", "after": "a.png"},
    {"title": "...", "notes": ["..."], "image": "/abs/or/after-relative.png"},
    {"title": "...", "notes": ["..."], "sheet": "settings-*-ja-light-760x520.png", "columns": 4},
    {"title": "...", "notes": ["..."], "options": [
        {"label": "A", "text": "...", "images": ["light.png", "dark.png"]}]}
  ]
}
Relative image paths resolve against "after" (or "before" for the left side of a pair).
"""
import glob
import io
import json
import os
import sys

from PIL import Image
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas

# Arial Unicode covers CJK plus ⌥ · → etc.; the built-in CID fonts render those as boxes.
FONT = "AU"
pdfmetrics.registerFont(TTFont(FONT, "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"))
W, H = landscape(A4)
INK, SUB, ACC = (0.11, 0.105, 0.094), (0.4, 0.38, 0.36), (0.26, 0.4, 0.4)
M = 36  # page margin


class Report:
    def __init__(self, spec, out):
        self.spec = spec
        self.c = canvas.Canvas(out, pagesize=(W, H))
        self.c.setTitle(spec.get("title", "Comparison"))

    def path(self, name, side="after"):
        return name if os.path.isabs(name) else os.path.join(self.spec[side], name)

    def text(self, s, x, y, size=11, color=INK):
        self.c.setFont(FONT, size)
        self.c.setFillColorRGB(*color)
        self.c.drawString(x, y, s)

    def wrap(self, s, x, y, width, size=10.5, color=SUB, lead=None):
        lead = lead or size * 1.5
        self.c.setFont(FONT, size)
        self.c.setFillColorRGB(*color)
        line = ""
        for ch in s:  # per character: works for CJK and Latin alike
            if pdfmetrics.stringWidth(line + ch, FONT, size) > width:
                self.c.drawString(x, y, line)
                y -= lead
                line = ch.lstrip()
            else:
                line += ch
        if line:
            self.c.drawString(x, y, line)
            y -= lead
        return y

    def image(self, img, x, y, w, h):
        """Fit `img` (path or PIL image) into the box, top-aligned; returns its bottom edge."""
        im = Image.open(img).convert("RGB") if isinstance(img, str) else img
        r = min(w / im.width, h / im.height)
        dw, dh = im.width * r, im.height * r
        im = im.resize((max(1, int(dw * 2.2)), max(1, int(dh * 2.2))), Image.LANCZOS)
        buf = io.BytesIO()
        im.save(buf, "JPEG", quality=82)
        buf.seek(0)
        left, bottom = x + (w - dw) / 2, y + h - dh
        self.c.drawImage(ImageReader(buf), left, bottom, dw, dh)
        self.c.setStrokeColorRGB(0.85, 0.83, 0.8)
        self.c.setLineWidth(0.5)
        self.c.rect(left, bottom, dw, dh)
        return bottom

    def header(self, page):
        self.text(page["title"], M, H - 44, 17)
        y = H - 66
        for n in page.get("notes", []):
            y = self.wrap("· " + n, M, y, W - 2 * M)
        return y - 6

    def cover(self):
        self.text(self.spec.get("title", ""), M, H - 80, 26)
        self.text(self.spec.get("subtitle", ""), M, H - 108, 12, SUB)
        y = H - 150
        for p in self.spec.get("intro", []):
            y = self.wrap(p, M, y, W - 2 * M, 12, INK, 20) - 6
        self.c.showPage()

    def pair(self, page, top):
        half = (W - 2 * M - 12) / 2
        self.text("改前", M, top - 2, 10, SUB)
        self.text("改后", M + half + 12, top - 2, 10, ACC)
        h = top - 14 - 30
        self.image(self.path(page["before"], "before"), M, 30, half, h)
        self.image(self.path(page["after"]), M + half + 12, 30, half, h)

    def sheet(self, page, top):
        files = sorted(glob.glob(self.path(page["sheet"])))
        if not files:
            sys.exit(f"no screenshots match {page['sheet']}")
        ims = [Image.open(f).convert("RGB") for f in files]
        cw, ch = ims[0].size
        cols = page.get("columns", 4)
        rows = (len(ims) + cols - 1) // cols
        grid = Image.new("RGB", (cw * cols, ch * rows), "white")
        for i, im in enumerate(ims):
            grid.paste(im.resize((cw, ch)), ((i % cols) * cw, (i // cols) * ch))
        self.image(grid, M, 30, W - 2 * M, top - 30)

    def options(self, page, top):
        opts = page["options"]
        cw = (W - 2 * M - 12 * (len(opts) - 1)) / len(opts)
        for i, o in enumerate(opts):
            x = M + i * (cw + 12)
            self.text(o["label"], x, top - 14, 12, ACC if o.get("chosen") else INK)
            y = self.wrap(o.get("text", ""), x, top - 32, cw, 9.5) - 6
            per = (y - 30) / max(1, len(o["images"]))
            for j, img in enumerate(o["images"]):
                self.image(self.path(img), x, y - (j + 1) * per + 6, cw, per - 6)

    def build(self):
        if self.spec.get("intro"):
            self.cover()
        for page in self.spec["pages"]:
            top = self.header(page)
            if "before" in page:
                self.pair(page, top)
            elif "sheet" in page:
                self.sheet(page, top)
            elif "options" in page:
                self.options(page, top)
            elif "image" in page:
                self.image(self.path(page["image"]), M, 30, W - 2 * M, top - 30)
            self.c.showPage()
        self.c.save()


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    with open(sys.argv[1]) as f:
        Report(json.load(f), sys.argv[2]).build()
