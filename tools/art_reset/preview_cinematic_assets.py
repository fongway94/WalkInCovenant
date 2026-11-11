#!/usr/bin/env python3
"""preview_cinematic_assets.py — 3x nearest-neighbour review sheet for B art.

    PYTHONPATH=<pillow-cache> python3 tools/art_reset/preview_cinematic_assets.py

Outputs docs/art-reset/diagnosis/13_cinematic_props_3x.png. This is an ASSET
sheet, not an engine capture: it exists so a human can check silhouettes and
value planes at native-ish size before a real CI frame is promoted.
"""
from __future__ import annotations

import pathlib

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parents[2]
PROPS = ROOT / "art/props_cinematic"
CHARS = ROOT / "art/characters_cinematic"
OUT = ROOT / "docs/art-reset/diagnosis/13_cinematic_props_3x.png"

PROP_KEYS = ["olive_tree", "fig_tree", "palm_tree", "bush", "rock", "boulder",
             "sheep", "sheep_alert", "sheep_graze", "fold", "tent", "house",
             "well"]
SHEETS = ["pilgrim_idle", "pilgrim_walk", "shepherd_idle", "shepherd_walk"]
S = 3
PAD = 10
LABEL = 12
CELL_W = 230
CELL_H = 120
COLS = 4


def main():
    canvas = Image.new("RGB", (COLS * (CELL_W + PAD) + PAD,
                               5 * (CELL_H + PAD) + PAD + 20),
                       (20, 22, 26))
    d = ImageDraw.Draw(canvas)
    d.text((PAD, PAD), "Direction B — golden-hour crafted assets, 3x nearest",
           fill=(238, 224, 186))

    items = [(PROPS / (k + ".png"), "PROP " + k) for k in PROP_KEYS]
    items += [(CHARS / (k + ".png"), "SHEET " + k) for k in SHEETS]
    for i, (path, label) in enumerate(items):
        row = i // COLS
        col = i % COLS
        x = PAD + col * (CELL_W + PAD)
        y = PAD + 20 + row * (CELL_H + PAD)
        im = Image.open(path).convert("RGBA")
        im = im.resize((im.width * S, im.height * S), Image.NEAREST)
        plate = Image.new("RGB", (CELL_W, CELL_H), (34, 38, 34))
        plate.paste(im, ((CELL_W - im.width) // 2,
                         (CELL_H - im.height) // 2), im)
        canvas.paste(plate, (x, y))
        d.text((x + 2, y + CELL_H - LABEL - 2), label,
               fill=(232, 216, 172))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(OUT)
    print("wrote", OUT.relative_to(ROOT), "with", len(items), "assets")


if __name__ == "__main__":
    main()
