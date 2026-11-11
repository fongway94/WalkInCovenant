#!/usr/bin/env python3
"""Rebuild docs/ART-COMPARISON.png — the premium-art shortlist evidence.

    PYTHONPATH=<pillow> python3 tools/build_art_comparison.py

Four panels, all from real pixels rather than descriptions:

  A  the shipped art BEFORE this pass, reconstructed from the pinned commit
     (sprites) and the committed reviewed frame baselines (rendered game);
  B  the same art improved in-house (distinct silhouettes + drawn portraits);
  C  the CC0 alternatives that were downloaded and inspected, and rejected;
  D  the chosen direction: one palette, one outline, project-specific art.

Panel C needs the research downloads in /tmp/wic_assets/; if they are absent
the panel is drawn with a clear "sources not present" message instead of
silently producing a misleading comparison. The other three panels are fully
reproducible from this repository alone.
"""

import io
import pathlib
import subprocess
import sys

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "ART-COMPARISON.png"
BEFORE_SHA = "4ab143607d31c479fb8a0b737c629c9e97a924b9"
RESEARCH = pathlib.Path("/tmp/wic_assets")

PW, PH, PAD, HEAD = 560, 340, 14, 26
BG, PANEL, INK, MUT = (20, 22, 26), (32, 34, 38), (235, 230, 215), (160, 166, 170)


def _blob(rel):
    raw = subprocess.check_output(
        ["git", "-C", str(ROOT), "show", "%s:%s" % (BEFORE_SHA, rel)])
    return Image.open(io.BytesIO(raw)).convert("RGBA")


def _sprite(name, scale=5, before=False):
    im = (_blob("art/characters/%s_idle.png" % name) if before
          else Image.open(ROOT / "art" / "characters" / ("%s_idle.png" % name))
          .convert("RGBA")).crop((0, 0, 16, 16))
    bg = Image.new("RGBA", (16, 16), (74, 104, 64, 255))
    bg.alpha_composite(im)
    return bg.convert("RGB").resize((16 * scale, 16 * scale), Image.NEAREST)


def _before_sheet():
    names = ["boy", "corin", "david", "elder", "eliab", "goliath",
             "jesse", "king", "pharisee", "pilgrim", "priest", "samuel",
             "shepherd", "soldier", "villager_a", "villager_b",
             "villager_c", "woman"]
    sheet = Image.new("RGB", (646, 382), (28, 28, 32))
    d = ImageDraw.Draw(sheet)
    for i, name in enumerate(names):
        im = _sprite(name, 6, before=True)
        x, y = 10 + (i % 6) * 106, 10 + (i // 6) * 124
        sheet.paste(im, (x, y))
        d.text((x + 2, y + 98), name[:8], fill=(230, 230, 220))
    return sheet


def _face(name, scale=4):
    return Image.open(ROOT / "art" / "facesets" / ("%s.png" % name)).convert("RGB") \
        .resize((32 * scale, 32 * scale), Image.NEAREST)


def _duel(name, scale=2):
    n = 64 if name == "goliath" else 32
    im = Image.open(ROOT / "art" / "duel" / ("%s.png" % name)).convert("RGBA")
    bg = Image.new("RGBA", (n, n), (74, 104, 64, 255))
    bg.alpha_composite(im)
    return bg.convert("RGB").resize((n * scale, n * scale), Image.NEAREST)


def _research(name):
    p = RESEARCH / name
    return Image.open(p).convert("RGB") if p.is_file() else None


def _panel(sheet, idx, title, items):
    col, row = idx % 2, idx // 2
    x, y = PAD + col * (PW + PAD), PAD + row * (PH + PAD + HEAD)
    ImageDraw.Draw(sheet).rectangle((x, y, x + PW, y + PH + HEAD), fill=PANEL)
    d = ImageDraw.Draw(sheet)
    d.text((x + 10, y + 7), title, fill=INK)
    for im, label, (bx, by, bw, bh) in items:
        if im is None:
            continue
        im = im.convert("RGB")
        im.thumbnail((bw, bh), Image.LANCZOS)
        px, py = x + bx + (bw - im.width) // 2, y + HEAD + by + (bh - im.height) // 2
        sheet.paste(im, (px, py))
        ly = y + HEAD + by + bh - 15
        d.rectangle((x + bx, ly - 1, x + bx + bw, ly + 13), fill=(20, 22, 26))
        d.text((x + bx + 3, ly), label, fill=MUT)


def main() -> int:
    sheet = Image.new("RGB", (2 * (PW + PAD) + PAD, 2 * (PH + PAD + HEAD) + PAD), BG)
    diag = Image.open(ROOT / "tests" / "frames" / "baseline_03_dialogue.png") \
        .convert("RGB").crop((0, 100, 320, 180)).resize((320, 80), Image.NEAREST)
    field = Image.open(ROOT / "tests" / "frames" / "baseline_06_flock.png") \
        .convert("RGB").crop((0, 30, 200, 150)).resize((240, 144), Image.NEAREST)
    _panel(sheet, 0, "A · EXISTING (before): one body, tiny face, flat light", [
        (_before_sheet(), "18 map sprites — same silhouette", (10, 8, 540, 180)),
        (diag, "rendered dialogue: 16px sprite as portrait", (10, 196, 260, 110)),
        (field, "rendered shepherd field", (280, 196, 260, 110)),
    ])
    _panel(sheet, 1, "B · IMPROVED IN-HOUSE: shape, expression, scale", [
        (_sprite("david", 7), "David: mantle, satchel, sling", (10, 8, 150, 150)),
        (_face("david", 5), "new 32px portrait", (180, 8, 180, 180)),
        (_duel("goliath", 2), "new 64px duel Goliath", (380, 8, 160, 160)),
        (_face("goliath", 3), "Goliath: scar + crest", (10, 196, 120, 110)),
        (_face("samuel", 3), "Samuel: long beard", (150, 196, 120, 110)),
        (_face("corin", 3), "Corin: hood + scroll", (290, 196, 120, 110)),
        (_duel("david", 3), "new 32px duel David", (430, 196, 110, 110)),
    ])
    c1 = _research("kenney_ui_sample.png")
    c2 = _research("kenney_rpg_pack.jpg")
    c3 = _research("kenney_chars_preview.png")
    c4 = _research("oga_16x16_tiles.png")
    if c4:
        c4 = c4.resize((240, 172), Image.NEAREST)
    missing = [n for n, im in (("ui", c1), ("rpg", c2), ("chars", c3),
                               ("tiles", c4)) if im is None]
    _panel(sheet, 2, "C · CC0 ALTERNATIVES INSPECTED (rejected): cool high-fantasy", [
        (c1, "Kenney Fantasy UI Borders", (10, 8, 340, 180)),
        (c4, "OpenGameArt 16x16 terrain", (370, 8, 180, 180)),
        (c2, "Kenney Roguelike/RPG pack", (10, 196, 340, 110)),
        (c3, "Kenney Roguelike Characters", (370, 196, 180, 110)),
    ])
    if missing:
        ImageDraw.Draw(sheet).text(
            (PAD + 14, PAD + (PH + PAD + HEAD) + 40),
            "research PNGs not present: %s (see assets/LICENSES.md)" % ", ".join(missing),
            fill=MUT)
    faces = Image.open(ROOT / "art" / "_preview" / "faces_sheet.png").convert("RGB") \
        if (ROOT / "art" / "_preview" / "faces_sheet.png").is_file() else None
    if faces is None:
        cells = [_face(n) for n in ("boy", "corin", "david", "elder", "eliab",
                                    "goliath", "jesse", "king", "priest",
                                    "samuel", "shepherd", "soldier")]
        faces = Image.new("RGB", (6 * 128, 2 * 128), PANEL)
        for i, c in enumerate(cells):
            faces.paste(c, ((i % 6) * 128, (i // 6) * 128))
    _panel(sheet, 3, "D · CHOSEN: one palette, one outline, project-specific", [
        (faces, "18 expressive portraits (8x preview)", (10, 8, 540, 190)),
        (_duel("goliath", 2), "Goliath 64px", (10, 206, 140, 110)),
        (_duel("david", 3), "David 32px", (170, 206, 110, 110)),
        (_sprite("david", 6), "map David", (300, 206, 110, 110)),
        (_sprite("goliath", 6), "map Goliath", (430, 206, 110, 110)),
    ])
    sheet.save(OUT, optimize=True)
    print("wrote %s (%dx%d, %d bytes)" % (OUT, sheet.width, sheet.height,
                                          OUT.stat().st_size))
    return 0


if __name__ == "__main__":
    sys.exit(main())
