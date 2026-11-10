#!/usr/bin/env python3
"""craft_characters.py — HAND-AUTHORED 16px character sheets for Direction C.

The old sheets were 16x16 blobs: a round head, a one-colour tunic and two
sticks for legs. No amount of palette work gives those a silhouette. These
figures have a defined head/hair shape, a shoulder line, a belt with a sash,
a tunic with folds and a shaded hem, two legs with sandals, an arm holding a
shepherd's staff, and a warm-brown ink outline. Four facings x 2 idle / 4 walk
frames are drawn on the SAME pixel grid as the shipped sheets, so hframes,
vframes, sprite offsets, walk timing, hitboxes and saves are untouched.

Only the two actors visible in the representative shepherd scene are crafted:
`pilgrim` (David / the player) and `shepherd` (the hired boy). Other actors
keep their classic sheets — this is one reversible scene, not a full rebuild.

    PYTHONPATH=<pillow-cache> python3 tools/artgen/craft_characters.py
    python3 tools/check_craft_props.py          # includes sheet checks
"""
from __future__ import annotations

import pathlib

from PIL import Image, ImageDraw

from tools.artgen.craft_props import (INK, WOOD_D, WOOD_M, WOOD_L, WOOD_H,
                                      CLAY_M, LINEN_D, LINEN_M, LINEN_L,
                                      LINEN_H, SKIN_D, SKIN_M, SKIN_L, GOLD,
                                      rgb, canvas, rect, poly, line, dot)

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "art/characters_storybook"
OUT.mkdir(parents=True, exist_ok=True)

# actor → tunic ramp, hair, sash accent. Kept inside the shared Direction-C
# palette so characters, props and tiles all belong to one material language.
ACTORS = {
    "pilgrim": {"robe": LINEN_D, "light": LINEN_M, "rim": LINEN_L,
                "shade": WOOD_D, "hair": WOOD_D, "sash": CLAY_M},
    "shepherd": {"robe": WOOD_M, "light": LINEN_D, "rim": LINEN_M,
                 "shade": WOOD_D, "hair": WOOD_D, "sash": WOOD_H},
}


def flat(d, pts, fill):
    """A filled plane with NO ink outline (used inside an outlined silhouette)."""
    d.polygon(pts, fill=rgb(fill))


def figure(actor: str, direction: int, frame: int, walking: bool):
    """One 16x16 cell. direction: 0 down, 1 left, 2 right, 3 up."""
    p = ACTORS[actor]
    im, d = canvas(16, 16)
    bob = 1 if walking and frame in (1, 2) else 0
    step = (0, -1, 0, 1)[frame % 4] if walking else 0

    # ── staff behind the body (the shepherd's silhouette marker) ──────────
    sx = 12 if direction != 1 else 3
    line(d, [(sx, 4 - bob), (sx, 14)], WOOD_D, 1)
    line(d, [(sx + 1, 4 - bob), (sx + 1, 14)], WOOD_M, 1)
    line(d, [(sx, 4 - bob), (sx + 2, 3 - bob)], WOOD_L, 1)

    # ── legs / sandals ───────────────────────────────────────────────────
    if walking:
        left = (5 + step, 11, 6 + step, 14)
        right = (9 - step, 11, 10 - step, 14)
    else:
        left, right = (5, 11, 6, 14), (9, 11, 10, 14)
    for box in (left, right):
        rect(d, (box[0] - 1, box[1], box[2] + 1, box[3] + 1), INK)
        rect(d, box, SKIN_D)
        rect(d, (box[0], box[3] + 1, box[2], box[3] + 1), WOOD_D)
    # ── tunic: outline, shaded right plane, lit left plane, fold lines ─────
    hem = 12 - bob
    body = [(4, 6 - bob), (11, 6 - bob), (12, hem), (3, hem)]
    poly(d, body, p["robe"])
    poly(d, [(4, 6 - bob), (7, 6 - bob), (7, hem), (3, hem)], p["light"])
    poly(d, [(10, 6 - bob), (11, 6 - bob), (12, hem), (10, hem)], p["shade"])
    # collar: one short lit edge, not a bright band across the chest
    rect(d, (6, 6 - bob, 9, 6 - bob), p["rim"])
    line(d, [(6, 8 - bob), (5, 11 - bob)], p["shade"], 1)   # cloth fold
    line(d, [(9, 8 - bob), (10, 11 - bob)], p["shade"], 1)
    # belt + hanging sash end
    rect(d, (3, 9 - bob, 12, 10 - bob), WOOD_D)
    rect(d, (3, 9 - bob, 12, 9 - bob), WOOD_M)
    rect(d, (7, 9 - bob, 8, 12 - bob), p["sash"])
    dot(d, 8, 9 - bob, GOLD)                                 # belt stud

    # ── arms: one hand on the staff, one swinging ────────────────────────
    if direction == 1:
        rect(d, (3, 7 - bob, 4, 10 - bob + step), p["shade"])
        dot(d, 3, 10 - bob + step, SKIN_M)
    else:
        rect(d, (11, 7 - bob, 12, 10 - bob - step), p["shade"])
        dot(d, 12, 10 - bob - step, SKIN_M)

    # ── head: one ink silhouette, then inner planes with NO extra outline ─
    head = [(5, 1 - bob), (10, 1 - bob), (11, 3 - bob), (10, 6 - bob),
            (5, 6 - bob), (4, 3 - bob)]
    poly(d, head, SKIN_D)
    flat(d, [(5, 2 - bob), (10, 2 - bob), (10, 4 - bob), (9, 5 - bob),
             (6, 5 - bob), (5, 4 - bob)], SKIN_M)
    # hair: a thin irregular cap with a short fringe, leaving a readable face
    flat(d, [(4, 2 - bob), (5, 0 - bob), (9, 0 - bob), (11, 2 - bob),
             (10, 2 - bob), (8, 1 - bob), (6, 2 - bob), (5, 3 - bob)],
         p["hair"])
    line(d, [(6, 1 - bob), (9, 1 - bob)], WOOD_L, 1)
    line(d, [(5, 0 - bob), (9, 0 - bob)], INK, 1)
    if direction == 0:                     # facing the player: two eyes
        dot(d, 6, 4 - bob, INK)
        dot(d, 9, 4 - bob, INK)
        dot(d, 7, 5 - bob, SKIN_L)
    elif direction == 1:                   # profile left
        dot(d, 5, 4 - bob, INK)
        rect(d, (4, 3 - bob, 4, 4 - bob), SKIN_L)
    elif direction == 2:                   # profile right
        dot(d, 10, 4 - bob, INK)
        rect(d, (11, 3 - bob, 11, 4 - bob), SKIN_L)
    else:                                  # back: hair covers the face
        poly(d, [(5, 2 - bob), (10, 2 - bob), (10, 5 - bob), (5, 5 - bob)],
             p["hair"])
        line(d, [(6, 3 - bob), (9, 3 - bob)], WOOD_M, 1)
    return im


def sheet(actor: str, walking: bool) -> Image.Image:
    n = 4 if walking else 2
    im = Image.new("RGBA", (16 * n, 64), (0, 0, 0, 0))
    for direction in range(4):
        for f in range(n):
            im.paste(figure(actor, direction, f, walking), (f * 16, direction * 16))
    return im


def main():
    for actor in ACTORS:
        for walking, name in ((False, "idle"), (True, "walk")):
            p = OUT / f"{actor}_{name}.png"
            sheet(actor, walking).save(p)
            print(f"  {p.relative_to(ROOT)}  {p.stat().st_size} bytes")
    print("wrote 4 hand-authored character sheets (2 actors x idle/walk)")


if __name__ == "__main__":
    main()
