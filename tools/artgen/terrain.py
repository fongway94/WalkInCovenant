"""Terrain tiles — 16×16, four variants each, plus organic edge transitions.

Quality rules that separate this from "flat colour + noise":
  1. Every tile uses at least three steps of its own ramp (shadow / base / light).
  2. Detail is placed, not scattered — grass grows in tufts, stone cracks along
     lines, sand ripples horizontally. Randomness picks WHERE, never WHETHER.
  3. Variants share the same macro-structure so tiling never shows a seam grid.
  4. Edges are organic and dithered, never a straight line.
"""

import random
import zlib

from . import TILE
from .canvas import Canvas
from .palette import c, ramp, blend, SHADOW


# ────────────────────────────────────────────────────────────────────────
# base terrain
# ────────────────────────────────────────────────────────────────────────

def _ground(ramp_name, seed, tufts=None, grains=0.08, crack=None, base_step=2,
            macro_alpha=1.0):
    """Generic ground: clean mid base, broad macro mottling, sparse fine grain.

    The failure mode of generated tiles is uniform noise — every pixel jittered,
    so the surface reads as TV static. Real 16px tiles keep the base CLEAN and put
    a small amount of deliberate, readable detail on top. So: large soft blobs at
    adjacent ramp steps for macro variation, then only a little grain, then a few
    hand-placed features (tufts, pebbles, ripples, cracks).
    """
    rnd = random.Random(seed)
    cv = Canvas(TILE, TILE)
    n = len(ramp(ramp_name))
    base = c(ramp_name, base_step)
    dark, light = c(ramp_name, max(0, base_step - 1)), c(ramp_name, min(n - 1, base_step + 1))

    cv.rect(0, 0, TILE, TILE, base)

    # Macro mottling: 2 large, low-contrast blobs. These are what stop a tiled
    # field from looking like wallpaper, and they must be low-contrast or they
    # tile visibly.
    for _ in range(2):
        bx, by = rnd.randrange(-2, TILE), rnd.randrange(-2, TILE)
        br = rnd.randint(5, 8)
        tone = dark if rnd.random() < 0.5 else light
        # the dial: at 1.0 the blob is the full ramp step (bare dirt), at 0.35
        # it is a whisper (grass). Adjacent tiles at a strong step made every
        # cell its own brightness square — a checkerboard with grass on it.
        if macro_alpha < 1.0:
            tone = blend(tone, base, macro_alpha)
        for y in range(TILE):
            for x in range(TILE):
                d2 = (x - bx) ** 2 + (y - by) ** 2
                if d2 <= br * br and rnd.random() < 0.5:
                    cv.px(x, y, tone)

    # Fine grain: sparse. This number is the quality dial.
    for _ in range(int(TILE * TILE * grains)):
        cv.px(rnd.randrange(TILE), rnd.randrange(TILE),
              rnd.choice([dark, light]))

    if tufts:
        for _ in range(tufts):
            x, y = rnd.randrange(3, TILE - 2), rnd.randrange(4, TILE - 1)
            # a tuft is a SHAPE, not a bright dot: tip only one step up from
            # the base reads as grass; two steps read as sprinkled glitter
            tip = c(ramp_name, min(n - 1, base_step + 1))
            stem = c(ramp_name, max(0, base_step))
            cv.px(x - 1, y, stem)
            cv.px(x, y - 1, stem); cv.px(x, y, stem)
            cv.px(x + 1, y, stem)
            cv.px(x, y - 2, tip)
            cv.px(x - 1, y - 1, tip) if rnd.random() < 0.5 else None

    if crack:
        x, y = rnd.randrange(3, TILE - 3), rnd.randrange(3, TILE - 3)
        for _ in range(rnd.randint(3, 6)):
            cv.px(x, y, dark)
            x += rnd.choice((-1, 0, 1)); y += rnd.choice((0, 1))
            if not (0 <= x < TILE and 0 <= y < TILE):
                break
    return cv


def grass(seed=1):
    """Meadow. The base is DELIBERATELY quiet and the four variants each carry
    a DIFFERENT kind of detail: nothing / blades / one flower / blades+pebble.

    Why: the earlier build put a flower on every tile, and the seeded scatter
    hash made the identical blossom reappear on a visible lattice — the field
    read as wallpaper (playtest 3). Detail that is rare is detail that reads.
    """
    cv = _ground("grass", seed, tufts=2, grains=0.012, base_step=2,
                 macro_alpha=0.35)
    rnd = random.Random(seed + 41)
    kind = seed % 4
    bx, by = rnd.randrange(4, 12), rnd.randrange(5, 12)
    tip = c("grass", 4)
    stem = c("grass", 1)

    def blade(x, y, h=2):
        cv.px(x, y, tip)
        for i in range(1, h + 1):
            cv.px(x, y + i, stem)

    if kind == 0:
        blade(bx, by, 2)
    elif kind == 1:
        blade(bx, by, 2); blade(bx + 3, by - 1, 3); blade(bx + 5, by + 2, 2)
    elif kind == 2:
        # the one flower in four tiles — warm enough to catch the eye, small
        # enough to disappear once the camera moves
        petal = blend(c("linen", 5), c("gold", 3), 0.35)
        cv.px(bx, by - 1, petal); cv.px(bx + 1, by - 1, petal)
        cv.px(bx, by, petal); cv.px(bx + 1, by, c("gold", 4))
        cv.px(bx, by + 1, stem)
    else:
        blade(bx, by, 3); blade(bx + 2, by + 1, 2)
        cv.px(bx + 6, by + 3, blend(c("stone", 4), c("grass", 3), 0.4))
        cv.px(bx + 7, by + 3, blend(c("stone", 3), c("grass", 2), 0.4))
    return cv


def dry(seed=2):
    cv = _ground("dry", seed, tufts=3, grains=0.015, base_step=2, macro_alpha=0.5)
    # green survivors at the edges tie the patch into the field around it
    rnd = random.Random(seed + 13)
    for _ in range(3):
        x, y = rnd.randrange(1, TILE - 2), rnd.randrange(2, TILE - 1)
        cv.px(x, y, blend(c("grass", 2), c("dry", 2), 0.35))
        cv.px(x, y - 1, blend(c("grass", 3), c("dry", 3), 0.3))
    return cv


def path(seed=3):
    cv = _ground("path", seed, grains=0.10)
    rnd = random.Random(seed + 99)
    # One trodden pebble cluster, warmed toward the road so it sits in the dirt
    # instead of reading as a blue dot.
    lit = blend(c("stone", 4), c("path", 4), 0.5)
    mid = blend(c("stone", 3), c("path", 3), 0.5)
    sh = blend(c("stone", 2), c("path", 1), 0.5)
    for _ in range(2):
        x, y = rnd.randrange(3, TILE - 5), rnd.randrange(3, TILE - 5)
        cv.px(x, y, lit); cv.px(x + 1, y, mid)
        cv.px(x, y + 1, mid); cv.px(x + 1, y + 1, sh)
    # a couple of packed-rut marks along the walking direction
    for _ in range(2):
        x, y = rnd.randrange(2, TILE - 2), rnd.randrange(2, TILE - 2)
        cv.px(x, y, c("path", 1)); cv.px(x + 1, y, c("path", 1))
    return cv


def sand(seed=4):
    cv = _ground("sand", seed, grains=0.07)
    rnd = random.Random(seed + 7)
    # wind ripples: short broken horizontal strokes, not full-width lines
    for y in (4, 9, 13):
        yy = y + rnd.randint(-1, 1)
        x = rnd.randrange(0, 6)
        ln = rnd.randint(5, 10)
        for i in range(ln):
            if rnd.random() < 0.8:
                cv.px(x + i, yy, c("sand", 4))
        cv.px(x + rnd.randrange(ln), yy - 1, c("sand", 2))
    return cv


def stone_floor(seed=5):
    """Cut paving — Jerusalem, temple courts, palace floors."""
    rnd = random.Random(seed)
    cv = Canvas(TILE, TILE)
    cv.rect(0, 0, TILE, TILE, c("stone", 3))
    # 2×2 flagstones with mortar gaps
    for by in range(0, TILE, 8):
        for bx in range(0, TILE, 8):
            ox = 4 if (by // 8) % 2 else 0
            tone = rnd.choice([c("stone", 2), c("stone", 3), c("stone", 4)])
            cv.rect(bx + ox, by, 8, 8, tone)
            cv.hline(bx + ox, by + 7, 8, c("stone", 1))
            cv.vline(bx + ox + 7, by, 8, c("stone", 1))
            cv.hline(bx + ox, by, 8, c("stone", 4))
            cv.noise(bx + ox, by, 7, 7, [blend(tone, "#000000", .08), blend(tone, "#ffffff", .08)],
                     0.12, seed + bx + by)
    return cv.crop(0, 0, TILE, TILE)


def mud(seed=6):
    """Packed earth. Clean, not gravel: 0.20 grain turned the whole camp into
    TV static at phone size."""
    return _ground("mud", seed, grains=0.06, crack=True, macro_alpha=0.6)


def water(seed=7, frame=0):
    """Open water: a depth gradient plus two wave crests that shift with the
    frame. Scattered single-pixel dashes read as static; a crest is a horizontal
    stroke with a foam cap, which is how every handheld tileset draws water."""
    rnd = random.Random(seed + frame * 31)
    cv = Canvas(TILE, TILE)
    cv.rect(0, 0, TILE, TILE, c("water", 1))
    # NO full-width rows. The old tile painted a darker row at y=0 and a lit row
    # at y=15; side by side those lines joined into continuous horizontal bands
    # and the lake looked like brickwork. Water is a flat field with a few
    # discrete crests, and a crest is a short stroke with a foam cap.
    shift = (frame % 2) * 2
    for wy, wx in ((5, 2 + shift), (12, 6 - shift)):
        for i in range(4):
            cv.px(wx + i, wy, c("water", 2))
        cv.px(wx + 1, wy, c("water", 3)); cv.px(wx + 2, wy, c("water", 3))
        cv.px(wx + 2, wy - 1, c("water", 4))          # one lit crest pixel
        cv.px(wx + 1, wy + 1, c("water", 0))          # trough under the crest
    x, y = rnd.randrange(1, TILE - 2), rnd.randrange(2, TILE - 2)
    cv.px(x, y, c("water", 2))
    return cv


def shallow(seed=8, frame=0):
    """The ford: water over sand, with a foam line where the two meet and
    pebbles visible under the surface — the stones David picks up live here."""
    rnd = random.Random(seed + frame * 17)
    cv = Canvas(TILE, TILE)
    cv.rect(0, 0, TILE, TILE, blend(c("water", 2), c("sand", 2), 0.28))
    # translucent water over sand: the bed shows through in patches
    for _ in range(18):
        x, y = rnd.randrange(TILE), rnd.randrange(6, TILE)
        cv.px(x, y, blend(c("water", 2), c("sand", 3), 0.45))
    # foam edge, WAVY and broken — a straight 2px line across every tile
    # boundary tiled into a ruler-straight rule on the map
    fx = frame % 2
    for x in range(TILE):
        wob = (0, 1, 0, -1)[(x + fx) % 4]
        cv.px(x, 4 + wob, c("foam", 1))
        if (x + fx) % 3:
            cv.px(x, 5 + wob, blend(c("foam", 1), c("water", 3), 0.5))
    for _ in range(4):
        x, y = rnd.randrange(2, TILE - 3), rnd.randrange(8, TILE - 2)
        cv.px(x, y, c("sand", 3)); cv.px(x + 1, y, c("sand", 2))
    for i in range(3):
        cv.px(3 + i + (frame % 2), 10, c("water", 3))
    return cv


def cliff(seed=9):
    """Rock face / mountain. Impassable, so it needs to read as hard."""
    rnd = random.Random(seed)
    cv = Canvas(TILE, TILE)
    cv.rect(0, 0, TILE, TILE, c("cliff", 2))
    # horizontal strata — sedimentary rock reads instantly
    for y in range(TILE):
        band = c("cliff", 1) if (y // 4 + rnd.random() < 0.5) else c("cliff", 3)
        cv.hline(0, y, TILE, band if rnd.random() < 0.6 else cv.get(0, y) or band)
    cv.noise(0, 0, TILE, TILE, [c("cliff", 1), c("cliff", 3), c("cliff", 4)], 0.28, seed)
    # lit lip along the top, deep shadow along the bottom
    cv.hline(0, 0, TILE, c("cliff", 4))
    cv.hline(0, 1, TILE, c("cliff", 3))
    cv.hline(0, TILE - 1, TILE, c("cliff", 0))
    cv.hline(0, TILE - 2, TILE, c("cliff", 1))
    return cv


def rocky(seed=10):
    """Stony ground — the wilderness of Judea and Sinai.

    Rocks read as rocks because each is a 3px cluster with a lit top-left face
    and a shadowed bottom-right, in a WARM grey that sits on the dirt instead
    of floating above it as a blue dot.
    """
    cv = _ground("dry", seed, grains=0.10)
    rnd = random.Random(seed + 3)
    lit, mid, sh = c("stone", 4), c("stone", 3), c("stone", 2)
    # warm the stone one step toward the dirt so it belongs here
    lit = blend(lit, c("dry", 4), 0.35); mid = blend(mid, c("dry", 3), 0.35); sh = blend(sh, c("dry", 1), 0.4)
    for _ in range(3):
        x, y = rnd.randrange(1, TILE - 3), rnd.randrange(1, TILE - 3)
        cv.px(x, y, lit); cv.px(x + 1, y, lit)
        cv.px(x, y + 1, mid); cv.px(x + 1, y + 1, mid); cv.px(x + 2, y + 1, sh)
        cv.px(x + 1, y + 2, sh); cv.px(x + 2, y + 2, sh)
    return cv


def wheat(seed=11):
    """Standing grain — Ruth's field, the sheaves of Joseph's dream."""
    cv = grass(seed + 20)
    rnd = random.Random(seed)
    for x in range(1, TILE, 2):
        h = rnd.randint(6, 11)
        for y in range(TILE - 2, TILE - 2 - h, -1):
            cv.px(x + (1 if y % 4 == 0 else 0), y, c("wheat", 3))
        cv.px(x, TILE - 2 - h, c("wheat", 4))       # the ear
        cv.px(x + 1, TILE - 3 - h, c("wheat", 5))
    return cv


def flowers(seed=12):
    """Lilies of the field — worth having for their own sake."""
    cv = grass(seed + 30)
    rnd = random.Random(seed)
    for _ in range(4):
        x, y = rnd.randrange(2, TILE - 2), rnd.randrange(2, TILE - 2)
        petal = rnd.choice([c("linen", 5), c("gold", 4), "#a8443a", c("spirit", 3)])
        cv.px(x, y - 1, petal); cv.px(x - 1, y, petal)
        cv.px(x + 1, y, petal); cv.px(x, y + 1, petal)
        cv.px(x, y, c("gold", 3))
    return cv


def snow(seed=13):
    """Mount Hermon, Lebanon. Rare but it makes the world feel like a place.

    Snow must be NEARLY WHITE with cool blue shadows in the hollows — not grey
    noise. The shadows are what give it form; the highlights must stay clean.
    """
    rnd = random.Random(seed)
    cv = Canvas(TILE, TILE)
    cv.rect(0, 0, TILE, TILE, c("linen", 5))
    # cool hollow shadows, a few soft patches
    for _ in range(3):
        bx, by = rnd.randrange(TILE), rnd.randrange(TILE)
        br = rnd.randint(2, 4)
        for y in range(TILE):
            for x in range(TILE):
                if (x - bx) ** 2 + (y - by) ** 2 <= br * br and rnd.random() < 0.6:
                    cv.px(x, y, c("linen", 4))
    for _ in range(6):
        cv.px(rnd.randrange(TILE), rnd.randrange(TILE), c("linen", 3))
    return cv


def reeds(seed=14):
    """Marsh edge — the Nile delta, the Jordan, the Sea of Galilee shore."""
    cv = shallow(seed)
    rnd = random.Random(seed + 11)
    for _ in range(6):
        x = rnd.randrange(TILE)
        h = rnd.randint(5, 10)
        for y in range(TILE - 1, TILE - 1 - h, -1):
            cv.px(x + (1 if y % 5 == 0 else 0), y, c("olive", 3))
        cv.px(x, TILE - 1 - h, c("olive", 4))
    return cv


def dark_grass(seed=15):
    """Shaded grass, for under trees and in courtyards at dusk."""
    cv = grass(seed + 40)
    return cv.remap({c("grass", i): c("grass", max(0, i - 1)) for i in range(5)})


# ────────────────────────────────────────────────────────────────────────
# registry
# ────────────────────────────────────────────────────────────────────────
# Each entry: key → (factory, variants, walkable, notes)
# `walkable` becomes the TileMap physics layer; the generator writes it to
# data/tiles.json so Godot and the tests agree about the world.

TERRAIN = [
    ("grass",       grass,       4, True,  "pasture, hills of Galilee"),
    ("dark_grass",  dark_grass,  2, True,  "shaded ground under trees"),
    ("dry",         dry,         4, True,  "dry earth, the Shephelah"),
    ("path",        path,        4, True,  "trodden road — walk speed unchanged"),
    ("sand",        sand,        4, True,  "desert, beach, Egypt"),
    ("rocky",       rocky,       4, True,  "wilderness of Judea and Sinai"),
    ("mud",         mud,         2, True,  "packed earth, threshing floor"),
    ("stone_floor", stone_floor, 4, True,  "paving: temple, palace, city"),
    ("wheat",       wheat,       3, True,  "standing grain — Ruth gleaned here"),
    ("flowers",     flowers,     2, True,  "lilies of the field"),
    ("snow",        snow,        2, True,  "Hermon, Lebanon"),
    ("water",       water,       4, False, "deep water — impassable, animated"),
    ("shallow",     shallow,     4, True,  "the ford — passable, slows you"),
    ("reeds",       reeds,       2, True,  "marsh edge"),
    ("cliff",       cliff,       4, False, "rock face — impassable"),
]

# Terrain that changes footstep sound and/or movement speed.
SURFACE = {
    "grass":       {"sfx": "step_grass", "speed": 1.00},
    "dark_grass":  {"sfx": "step_grass", "speed": 1.00},
    "dry":         {"sfx": "step_dirt",  "speed": 1.00},
    "path":        {"sfx": "step_dirt",  "speed": 1.05},
    "sand":        {"sfx": "step_sand",  "speed": 0.86},
    "rocky":       {"sfx": "step_stone", "speed": 0.94},
    "mud":         {"sfx": "step_dirt",  "speed": 1.00},
    "stone_floor": {"sfx": "step_stone", "speed": 1.00},
    "wheat":       {"sfx": "step_grass", "speed": 0.92},
    "flowers":     {"sfx": "step_grass", "speed": 1.00},
    "snow":        {"sfx": "step_sand",  "speed": 0.90},
    "water":       {"sfx": None,         "speed": 0.00},
    "shallow":     {"sfx": "step_water", "speed": 0.72},
    "reeds":       {"sfx": "step_water", "speed": 0.80},
    "cliff":       {"sfx": None,         "speed": 0.00},
}


def _stable_seed(key):
    """A seed that is the same in every process.

    This used to be `hash(key)`, and Python randomises string hashes per
    process: every `artgen` run produced a DIFFERENT ground, so the terrain the
    author approved was not the terrain the next build shipped. CRC32 is stable
    across runs, machines and Python versions.
    """
    return zlib.crc32(key.encode("utf-8")) % 9973


def build_tiles():
    """Return [(key, variant_index, Canvas, walkable)] in atlas order."""
    out = []
    for key, factory, variants, walkable, _note in TERRAIN:
        for v in range(variants):
            if key == "water":
                cv = factory(seed=7, frame=v)
            elif key == "shallow":
                cv = factory(seed=8, frame=v)
            else:
                cv = factory(seed=_stable_seed(key) + v * 31)
            out.append((key, v, cv, walkable))
    return out


def tiles_json():
    """Metadata for Godot + tests: which tile is which, is it walkable, how fast."""
    import json
    tiles, i = [], 0
    for key, _f, variants, walkable, note in TERRAIN:
        for v in range(variants):
            tiles.append({
                "key": key, "variant": v, "atlas_index": i,
                "walkable": walkable, "note": note,
                "sfx": SURFACE[key]["sfx"], "speed": SURFACE[key]["speed"],
            })
            i += 1
    return json.dumps({
        "tile": TILE,
        "columns": ATLAS_COLS,
        "tiles": tiles,
        # footstep sound + movement-speed multiplier per terrain key. Region.gd
        # reads this so the *feel* of walking on sand vs paving is data, not code.
        "surface": SURFACE,
    }, indent=1)


ATLAS_COLS = 16
