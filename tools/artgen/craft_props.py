#!/usr/bin/env python3
"""craft_props.py — HAND-AUTHORED pixel silhouettes for the selected direction.

This is the answer to docs/ART-RESET.md §6. The old props were circles,
triangles and ovals: an olive tree was a stack of round blobs, a sheep was a
white dot with a black face, a rock was a filled circle. No palette change can
fix a silhouette. These ten props are drawn as deliberate polygons on the same
pixel grid, with:

  * a distinct outline (warm brown ink, never pure black),
  * 3-4 value planes per material (shadow / midtone / light / rim),
  * irregular, non-circular edges,
  * real anatomy (legs, head, ear, trunk, branches, roof faces, door, posts),
  * no baked contact shadow — the engine draws one for every prop, NPC and the
    player (scripts/world/Region.gd), so all shadows share one light direction.

Sizes and frame counts are taken from data/props.json and are NOT changed, so
collision footprints, sort order and save data are untouched.

Run AFTER `python3 -m tools.artgen.build`, never before:

    PYTHONPATH=<pillow-cache> python3 tools/artgen/craft_props.py
    python3 tools/check_craft_props.py           # stdlib gate
    python3 tools/check_craft_props.py --write   # accept a deliberate redraw
"""

from __future__ import annotations

import json
import math
import pathlib
import random

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parents[2]
## Opt-in by design: art/props/*.png stays the shipped classic art. The crafted
## silhouettes live beside it and are swapped in only by
## Region.apply_art_theme("storybook"), so every existing frame, collision
## footprint and save file is untouched (docs/ART-RESET.md §6).
PROPS = ROOT / "art/props_storybook"
META = ROOT / "data/props.json"

# Direction C ramps (same values as tools/art_reset/build_storybook_atlas.py).
INK = "#2a1c14"
WOOD_D, WOOD_M, WOOD_L, WOOD_H = "#513823", "#6d4c30", "#8b6440", "#a87f54"
OLIVE_D, OLIVE_M, OLIVE_L, OLIVE_H = "#2f4030", "#5c6d4c", "#96a47c", "#c2c8a4"
STONE_D, STONE_M, STONE_L, STONE_H = "#403c32", "#6f6756", "#a89a7e", "#ded0ae"
CLAY_D, CLAY_M, CLAY_L = "#6a3526", "#ac5c3c", "#e09b72"
LINEN_D, LINEN_M, LINEN_L, LINEN_H = "#87785e", "#c5b28d", "#f1e2c2", "#fff3cf"
SKIN_D, SKIN_M, SKIN_L = "#53361f", "#926440", "#e8c093"
WATER_D, WATER_L = "#2c525a", "#77a8a6"
GOLD = "#c9a45c"

ALLOWED = {INK, WOOD_D, WOOD_M, WOOD_L, WOOD_H, OLIVE_D, OLIVE_M, OLIVE_L,
           OLIVE_H, STONE_D, STONE_M, STONE_L, STONE_H, CLAY_D, CLAY_M,
           CLAY_L, LINEN_D, LINEN_M, LINEN_L, LINEN_H, SKIN_D, SKIN_M,
           SKIN_L, WATER_D, WATER_L, GOLD}


def rgb(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def canvas(w, h):
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def blob(d, cx, cy, rx, ry, fill, seed, outline=INK, n=11, wobble=0.20):
    """An irregular hand-shaped canopy/wool cluster, not a mathematical circle."""
    r = random.Random(seed)
    pts = []
    for i in range(n):
        a = 2.0 * math.pi * i / n
        j = 1.0 - wobble + r.random() * wobble * 2.0
        pts.append((int(round(cx + math.cos(a) * rx * j)),
                    int(round(cy + math.sin(a) * ry * j))))
    d.polygon(pts, fill=rgb(fill), outline=rgb(outline))


def poly(d, pts, fill, outline=INK):
    d.polygon(pts, fill=rgb(fill), outline=rgb(outline))


def rect(d, box, fill, outline=None):
    d.rectangle(box, fill=rgb(fill), outline=rgb(outline) if outline else None)


def line(d, pts, fill, width=1):
    d.line(pts, fill=rgb(fill), width=width)


def dot(d, x, y, fill):
    d.point((x, y), fill=rgb(fill))


# ── olive tree 65x49 ─────────────────────────────────────────────────────
def olive_tree(w, h):
    im, d = canvas(w, h)
    # twisted trunk: two value planes, a fork and three branches
    poly(d, [(27, 48), (29, 33), (25, 27), (30, 21), (37, 23), (36, 33),
             (39, 48)], WOOD_D)
    poly(d, [(29, 48), (30, 34), (28, 28), (32, 23), (35, 25), (34, 34),
             (36, 48)], WOOD_M)
    line(d, [(31, 30), (19, 18), (14, 14)], WOOD_L, 2)
    line(d, [(33, 27), (47, 16), (52, 14)], WOOD_L, 2)
    line(d, [(32, 26), (32, 12)], WOOD_L, 2)
    # canopy: back → front, dark → light, each an irregular 11-gon
    blob(d, 15, 17, 12, 10, OLIVE_D, 11)
    blob(d, 48, 16, 13, 11, OLIVE_D, 12)
    blob(d, 32, 10, 13, 10, OLIVE_M, 13)
    blob(d, 22, 25, 12, 9, OLIVE_M, 14)
    blob(d, 44, 26, 12, 9, OLIVE_M, 15)
    blob(d, 32, 20, 15, 11, OLIVE_L, 16)
    # rim-light clusters on the upper-left of each mass (single light source)
    blob(d, 13, 12, 5, 4, OLIVE_H, 17, outline=OLIVE_L, n=9)
    blob(d, 30, 6, 6, 4, OLIVE_H, 18, outline=OLIVE_L, n=9)
    blob(d, 46, 12, 5, 4, OLIVE_H, 19, outline=OLIVE_L, n=9)
    blob(d, 29, 16, 6, 4, OLIVE_H, 20, outline=OLIVE_L, n=9)
    # a few olives, placed deliberately (never scattered noise)
    for x, y in ((18, 22), (25, 12), (38, 22), (47, 25), (34, 9)):
        dot(d, x, y, OLIVE_D)
        dot(d, x, y + 1, OLIVE_D)
    return im


# ── smaller trees ────────────────────────────────────────────────────────
def fig_tree(w, h):
    im, d = canvas(w, h)
    poly(d, [(7, 24), (7, 12), (5, 8), (9, 8), (8, 24)], WOOD_D)
    poly(d, [(8, 24), (8, 12), (7, 9), (9, 9), (9, 24)], WOOD_M)
    blob(d, 4, 7, 5, 5, OLIVE_D, 31, n=9)
    blob(d, 12, 6, 5, 5, OLIVE_M, 32, n=9)
    blob(d, 8, 4, 6, 5, OLIVE_L, 33, n=9)
    blob(d, 7, 3, 3, 2, OLIVE_H, 34, outline=OLIVE_L, n=8)
    return im


def palm_tree(w, h):
    im, d = canvas(w, h)
    poly(d, [(7, 28), (8, 12), (7, 10), (9, 10), (9, 28)], WOOD_D)
    poly(d, [(8, 28), (8, 12), (8, 11), (9, 11), (9, 28)], WOOD_M)
    # six fronds share one crown, so no leaf is a floating single pixel
    fronds = [(-6, -2), (-4, -5), (-2, -6), (2, -6), (4, -5), (6, -2),
              (-5, 1), (5, 1)]
    for dx, dy in fronds:
        line(d, [(8, 10), (8 + dx, 10 + dy)], OLIVE_D, 3)
        line(d, [(8, 10), (8 + dx, 10 + dy - 1)], OLIVE_L, 1)
    blob(d, 8, 8, 5, 3, OLIVE_M, 35, n=9)
    return im


# ── bush 35x29 / rock 34x33 / boulder 33x31 ──────────────────────────────
def bush(w, h):
    im, d = canvas(w, h)
    poly(d, [(16, 29), (17, 20), (15, 17), (19, 17), (18, 29)], WOOD_D)
    blob(d, 9, 18, 9, 8, OLIVE_D, 41)
    blob(d, 26, 17, 9, 8, OLIVE_D, 42)
    blob(d, 17, 11, 11, 9, OLIVE_M, 43)
    blob(d, 10, 16, 7, 6, OLIVE_L, 44)
    blob(d, 25, 14, 7, 6, OLIVE_L, 45)
    blob(d, 17, 8, 6, 4, OLIVE_H, 46, outline=OLIVE_L, n=9)
    for x, y in ((6, 20), (13, 12), (22, 9), (29, 19)):
        dot(d, x, y, CLAY_M)   # a restrained anemone, not confetti
    return im


def _stone(w, h, seed, tall=False):
    im, d = canvas(w, h)
    r = random.Random(seed)
    cx, cy = w / 2, h / 2 + 2
    pts = []
    for i in range(9):
        a = 2.0 * math.pi * i / 9
        j = 0.80 + r.random() * 0.22
        pts.append((int(cx + math.cos(a) * (w * 0.44) * j),
                    int(cy + math.sin(a) * (h * 0.44) * j)))
    d.polygon(pts, fill=rgb(STONE_M), outline=rgb(INK))
    # top plane catches the light; right face sits in shadow
    top = [(pts[i][0], pts[i][1] - 3) for i in range(0, 5)]
    d.polygon(top, fill=rgb(STONE_L))
    d.line(top, fill=rgb(STONE_H), width=1)
    d.polygon([pts[4], pts[5], pts[6], pts[7], (cx - 2, cy + 1)],
              fill=rgb(STONE_D))
    # two deliberate strata / cracks, not random pixels
    line(d, [(int(cx - w * 0.28), int(cy + 2)),
             (int(cx - 2), int(cy + 4)), (int(cx + w * 0.22), int(cy + 1))],
         STONE_D, 1)
    line(d, [(int(cx - w * 0.24), int(cy + 3)),
             (int(cx - 2), int(cy + 5)), (int(cx + w * 0.20), int(cy + 2))],
         STONE_H, 1)
    return im


def rock(w, h):
    return _stone(w, h, 51)


def boulder(w, h):
    return _stone(w, h, 52, tall=True)


# ── sheep 14x12, three poses ─────────────────────────────────────────────
def sheep(w, h, pose):
    im, d = canvas(w, h)
    # legs first, behind the wool
    for x in (3, 5, 9, 11):
        rect(d, (x, 8, x, 10), SKIN_D)
        dot(d, x, 10, INK)
    # wool: irregular body + three deliberate top clusters
    blob(d, 6, 6, 5.2, 3.4, LINEN_M, 60 + pose, n=10, wobble=0.14)
    blob(d, 3, 5, 2.4, 2.0, LINEN_L, 70 + pose, outline=LINEN_M, n=8)
    blob(d, 6, 4, 2.4, 2.0, LINEN_H, 80 + pose, outline=LINEN_L, n=8)
    blob(d, 9, 5, 2.2, 2.0, LINEN_L, 90 + pose, outline=LINEN_M, n=8)
    # head / ear / eye, position defines the pose
    if pose == 0:      # idle, looking right
        head = [(10, 4), (13, 5), (13, 8), (10, 8)]
    elif pose == 1:    # alert, head up
        head = [(10, 2), (13, 3), (13, 7), (10, 7)]
    else:              # grazing, head down
        head = [(9, 7), (12, 8), (12, 11), (9, 10)]
    poly(d, head, SKIN_D)
    poly(d, [(11, head[0][1]), (13, head[0][1] + 1), (12, head[0][1] + 2)],
         SKIN_M, outline=INK)
    dot(d, head[1][0] - 1, head[0][1] + 2, INK)
    return im


# ── fold 16x12 ───────────────────────────────────────────────────────────
def fold(w, h):
    im, d = canvas(w, h)
    # rails: sunlit top, shadowed underside, one ink edge
    for y in (4, 8):
        rect(d, (0, y, 15, y + 1), WOOD_M)
        line(d, [(0, y), (15, y)], WOOD_H, 1)
        rect(d, (0, y + 2, 15, y + 2), INK)
    # posts in front: ink edge, shadowed right face, sunlit left face
    for x in (1, 8, 14):
        rect(d, (x, 2, x + 2, 11), WOOD_D)
        rect(d, (x + 1, 3, x + 1, 10), WOOD_L)
        line(d, [(x, 2), (x + 2, 2)], INK, 1)
        line(d, [(x, 11), (x + 2, 11)], INK, 1)
    return im


# ── tent 26x18 ───────────────────────────────────────────────────────────
def tent(w, h):
    im, d = canvas(w, h)
    poly(d, [(2, 17), (13, 1), (24, 17)], LINEN_D)
    poly(d, [(2, 17), (13, 1), (13, 17)], LINEN_M)
    poly(d, [(13, 1), (24, 17), (13, 17)], LINEN_D)
    poly(d, [(10, 17), (13, 6), (16, 17)], STONE_D)   # dark doorway
    line(d, [(13, 1), (13, 5)], LINEN_H, 1)
    line(d, [(2, 17), (13, 1)], LINEN_L, 1)
    for x in (2, 24):
        line(d, [(x, 17), (x + (2 if x == 2 else -2), 18)], WOOD_D, 1)
    return im


# ── house 66x83 ──────────────────────────────────────────────────────────
def house(w, h):
    im, d = canvas(w, h)
    # wall: front plane + a darker right face gives readable volume
    poly(d, [(5, 30), (56, 30), (56, 78), (5, 78)], STONE_M)
    poly(d, [(56, 30), (62, 26), (62, 74), (56, 78)], STONE_D)
    # roof with a highlight ridge and a shadowed eave
    poly(d, [(1, 31), (31, 5), (61, 31)], CLAY_M)
    poly(d, [(1, 31), (31, 5), (31, 12), (1, 34)], CLAY_L)
    poly(d, [(31, 5), (61, 31), (61, 34), (31, 12)], CLAY_D)
    line(d, [(1, 31), (31, 5), (61, 31)], INK, 1)
    # limestone courses — deliberate horizontal structure, not noise
    for y in (40, 52, 64, 74):
        line(d, [(6, y), (55, y)], STONE_D, 1)
        line(d, [(6, y + 1), (55, y + 1)], STONE_L, 1)
    for x in (18, 34, 46):
        line(d, [(x, 40), (x, 52)], STONE_D, 1)
    # door and shuttered window
    poly(d, [(27, 52), (39, 52), (39, 78), (27, 78)], WOOD_D)
    poly(d, [(28, 53), (38, 53), (38, 77), (28, 77)], WOOD_M)
    line(d, [(33, 53), (33, 77)], WOOD_D, 1)
    dot(d, 36, 66, GOLD)
    poly(d, [(10, 42), (20, 42), (20, 52), (10, 52)], STONE_D)
    poly(d, [(11, 43), (19, 43), (19, 51), (11, 51)], WOOD_D)
    line(d, [(15, 43), (15, 51)], WOOD_L, 1)
    return im


# ── well 16x16 ───────────────────────────────────────────────────────────
def well(w, h):
    im, d = canvas(w, h)
    blob(d, 8, 10, 7, 5, STONE_D, 101, n=10)
    blob(d, 8, 9, 5, 3, WATER_D, 102, outline=STONE_M, n=9)
    blob(d, 7, 9, 3, 2, WATER_L, 103, outline=WATER_D, n=8)
    for x, y in ((2, 9), (14, 9), (8, 5)):
        dot(d, x, y, STONE_L)
    return im


BUILDERS = {
    "olive_tree": lambda w, h: olive_tree(w, h),
    "fig_tree": fig_tree,
    "palm_tree": palm_tree,
    "bush": bush,
    "rock": rock,
    "boulder": boulder,
    "sheep": lambda w, h: sheep(w, h, 0),
    "sheep_alert": lambda w, h: sheep(w, h, 1),
    "sheep_graze": lambda w, h: sheep(w, h, 2),
    "fold": fold,
    "tent": tent,
    "house": house,
    "well": well,
}


def main():
    meta = json.loads(META.read_text())
    dims = {p["key"]: (p["w"], p["h"], p["frames"]) for p in meta["props"]}
    for key, fn in BUILDERS.items():
        w, h, frames = dims[key]
        im = fn(w, h)
        assert im.size == (w, h), (key, im.size, (w, h))
        if frames > 1:
            sheet = Image.new("RGBA", (w * frames, h), (0, 0, 0, 0))
            for i in range(frames):
                sheet.paste(im, (i * w, 0))
            im = sheet
        im.save(PROPS / f"{key}.png")
        used = {c for c in im.getdata() if c[3] > 0}
        off = [c[:3] for c in used
               if "#%02x%02x%02x" % c[:3] not in ALLOWED]
        print("  %-14s %dx%d  %2d colours  off-palette=%d"
              % (key, w, h, len(used), len(off)))
    print("wrote %d hand-authored prop(s)" % len(BUILDERS))


if __name__ == "__main__":
    main()
