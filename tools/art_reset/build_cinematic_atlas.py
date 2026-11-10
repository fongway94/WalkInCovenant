#!/usr/bin/env python3
"""Build Direction B's terrain atlas with the shipped deterministic artgen.

Direction C was the assistant's selection in docs/ART-RESET.md §4. On
2026-11-10 the user overrode that choice: they want the golden-hour outcome of
Direction B ("Rich Cinematic") WITH the current animation system intact. This
tool implements B's colour system against the SAME 49 16px cells, the SAME
atlas indices and the SAME data/tiles.json as the classic and storybook
atlases, so collision, footstep surfaces, water animation and every save file
are untouched.

B's light: a low sun from the upper left. Shadows go cool green-slate and
long to the lower right; highlights go warm honey / gold. Path and stone are
sunlit ochre; olive foliage is deep green with a warm rim. No pure black or
white.

Direction B v3 (2026-11-10, after the user asked to "make in on par"): the v2
real engine frame measured world luma 67.9 against the concept's 86.6, and the
field had roughly half the concept's edge density. The ramps are lifted and the
generator adds directional, deterministic micro-detail — grass blades,
flower clusters, lit pebbles, warm dust and lower-right cast shadows — to the
16px cells. **v4**: a live screenshot showed that v3's per-cell marks repeated
into cream confetti across the whole field; the marks are now RARE and clustered,
with quiet ground between light pools. These are SHAPES on the pixel grid, not
a painted background, photographic texture or global blur. The 49 cells and all
four animated water variants keep their geometry and indices.

    PYTHONPATH=<pillow-cache> python3 tools/art_reset/build_cinematic_atlas.py

Outputs
    art/tiles/terrain_cinematic.png           (shipped, opt-in)
    docs/art-reset/cinematic_tiles_4x.png     (human review)
"""
from __future__ import annotations

import pathlib
import random
import sys
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from tools.artgen import palette as P          # noqa: E402
from tools.artgen import canvas as CV          # noqa: E402
from tools.artgen import terrain as T          # noqa: E402
from tools.artgen.canvas import atlas          # noqa: E402

# dark → light; index 0 is ambient occlusion, last is the golden rim light.
# v3 lifts the sunlit mid-tones while keeping cool deep shadow. The reference
# is a golden-hour meadow, not a uniformly bright field, so the low ramps stay.
CINEMATIC = {
    "grass":       ["#263a20", "#405a29", "#5f7f3b", "#849e4b", "#b0b65f", "#d8c477", "#f4dc95"],
    "dry":         ["#3e2e1b", "#5a4227", "#7b5a36", "#9f7747", "#c29a5d", "#dfba7c", "#f4d9a2"],
    "path":        ["#4e3620", "#71502c", "#986d39", "#bd8e49", "#dcae5e", "#f4cf7f", "#ffe9aa"],
    "sand":        ["#594329", "#7b5d37", "#9d7947", "#bf985b", "#dcb677", "#eed0a0", "#f9e7bb"],
    "wheat":       ["#503c1d", "#715624", "#93702e", "#b38c3e", "#d0a951", "#e8c670", "#f8e09d"],
    "mud":         ["#2e2619", "#463622", "#5f4831", "#795b42", "#967252", "#b18c6b", "#c9a783"],
    "stone":       ["#302f28", "#454237", "#5c584b", "#77705f", "#958b76", "#b4a88d", "#d3c7a8", "#ecdfbd"],
    "cliff":       ["#25251d", "#38372c", "#4d4a3c", "#64604e", "#807a63"],
    "water":       ["#173036", "#24464a", "#356165", "#4a7e7d", "#6b9e94", "#93bdaa", "#c2d9bd"],
    "foam":        ["#5f8c86", "#86ada0", "#b1cbb6", "#dce8cf"],
    "olive":       ["#203520", "#34502b", "#52703a", "#77904a", "#a2ad5c", "#cdc477", "#ecd799"],
    "palm":        ["#243a27", "#385535", "#527440", "#709253", "#96b167"],
    "dark_leaf":   ["#1c3021", "#2b432e", "#3d5a38", "#537044"],
    "wood":        ["#261a11", "#3b2616", "#52351e", "#6f4929", "#8d6037", "#ab7e4c", "#ca9e69"],
    "linen":       ["#3c372b", "#554b3c", "#70624b", "#8d7c60", "#aa9877", "#c9b694", "#e6d3b0", "#f7eaca"],
    "wool":        ["#352b1f", "#4c3c2b", "#65523b", "#806a4c", "#9e825e"],
    "skin":        ["#402a19", "#5e3d23", "#7f5531", "#a27245", "#c39160", "#e1b381", "#f3d5a8"],
    "gold":        ["#4f3611", "#704f1b", "#946926", "#bb8a33", "#daac4e", "#f0c975", "#fce3a3"],
    "bronze":      ["#2e2010", "#453016", "#5f4421", "#7c5b2d", "#9c773e"],
    "iron":        ["#191c1d", "#272d2e", "#383f40", "#4c5453", "#656d68"],
    "blood":       ["#26110d", "#3e1a14", "#592419", "#773125"],
    "holy":        ["#3c3416", "#75632c", "#ab9144", "#dabd6a", "#f7e3a6", "#fff5d0"],
    "spirit":      ["#1e3232", "#335554", "#4f7975", "#7ba69c", "#b5d1c2", "#deedd9"],
    "hair_dark":   ["#1c1611", "#2a2018", "#392c20", "#4a3a2a"],
    "hair_grey":   ["#484337", "#605b4d", "#7c7564", "#999280"],
    "hair_red":    ["#3f1f11", "#562b17", "#6f3c20", "#894c2b"],
}

OUTLINE = "#1b1710"      # dark warm brown ink, never pure black
SHADOW = "#221d16"       # cool-warm ambient occlusion
HIGHLIGHT = "#ffe6a3"    # low golden sun rim light

# A SMALL, fixed set of detail colours. Using one fixed palette stops the
# embellishment pass from exploding into hundreds of near-duplicate shades;
# check_art_reset.py still proves the shipped atlas is palette-controlled.
SUN_DUST = ["#d8c477", "#f4dc95", "#f4cf7f", "#ffe9aa"]
COOL_DUST = ["#263a20", "#34502b", "#2b432e", "#454237"]
GRASS_STEM = ["#405a29", "#5f7f3b", "#34502b", "#3d5a38"]
FLOWER = ["#f4dc95", "#f7eaca", "#fce3a3", "#d8c477"]
FLOWER_CORE = ["#bb8a33", "#daac4e"]
STONE_LIT = ["#d3c7a8", "#ecdfbd", "#dfba7c"]
STONE_DARK = ["#302f28", "#454237", "#3e2e1b"]

MEADOW = {"grass", "dark_grass", "dry", "rocky", "wheat", "flowers", "reeds"}
EARTH = {"path", "sand", "mud"}
HARD = {"stone_floor", "cliff"}
WATER = {"water", "shallow"}


def build_ramp_map():
    ramps = {k: list(v) for k, v in P.RAMPS.items()}
    for key, value in CINEMATIC.items():
        ramps[key] = list(value)
    return ramps


def _seed(key: str, variant: int, salt: int = 0) -> int:
    return zlib.crc32(("%s:%d:%d" % (key, variant, salt)).encode("utf-8"))


def _tuft(cv, rnd, x, y):
    """Three-pixel grass blade with a warm upper-left tip and a cool cast."""
    cv.px(x + 1, y + 1, rnd.choice(COOL_DUST))
    cv.px(x, y, rnd.choice(GRASS_STEM))
    cv.px(x, y - 1, rnd.choice(GRASS_STEM))
    cv.px(x - 1, y - 1, rnd.choice(SUN_DUST))
    if rnd.random() < 0.55:
        cv.px(x - 1, y - 2, rnd.choice(SUN_DUST))
    if rnd.random() < 0.35:
        cv.px(x + 1, y - 1, rnd.choice(GRASS_STEM))


def _flower(cv, rnd, x, y):
    """A tiny 2x2 blossom, not a detached one-pixel dot."""
    petal = rnd.choice(FLOWER)
    cv.px(x, y, petal)
    cv.px(x - 1, y, petal)
    cv.px(x, y - 1, rnd.choice(FLOWER_CORE))
    cv.px(x + 1, y, rnd.choice(COOL_DUST))
    cv.px(x, y + 1, rnd.choice(GRASS_STEM))


def _pebble(cv, rnd, x, y):
    """A lit upper-left face and a shadowed lower-right face."""
    cv.px(x, y, rnd.choice(STONE_LIT))
    cv.px(x - 1, y, rnd.choice(STONE_LIT))
    cv.px(x, y + 1, rnd.choice(STONE_DARK))
    cv.px(x + 1, y + 1, rnd.choice(STONE_DARK))


def _diagonal_shadow(cv, rnd, x, y):
    """Short lower-right cast from a blade or stone — one light direction."""
    tone = rnd.choice(COOL_DUST)
    for i in range(4):
        cv.px(x + i, y + int(i * 0.65), tone)
    cv.px(x + 2, y + 2, rnd.choice(STONE_DARK))


def embellish(key: str, variant: int, cv):
    """Add a FEW deterministic, directional details to one 16x16 cell.

    The B v3 atlas put ~20 marks in every cell. On a real 320x180 live frame
    that repeated into a uniform cream confetti (user screenshot
    2026-11-10-23-33-37). The reference has quiet ground between light pools,
    so B v4 keeps the same clustered SHAPES but makes them RARE: most cells
    now carry none, and the four-pixel global sprinkle is gone entirely. The
    macro-structures still come from the shipped terrain factories, and the
    marks remain on the integer pixel grid with a single upper-left sun.
    """
    rnd = random.Random(_seed(key, variant))
    if key in MEADOW:
        # One clump at most, and only on one variant in three. A blossom, a
        # pebble and a cast shadow each get their own rare variant so no cell
        # accumulates all four. Ground stays quiet between deliberate marks.
        if variant % 3 == 0:
            cx, cy = rnd.randrange(3, 12), rnd.randrange(4, 13)
            _tuft(cv, rnd, cx, cy)
            if rnd.random() < 0.45:
                _tuft(cv, rnd, cx + 1, cy)
        if variant % 4 == 0:
            _flower(cv, rnd, rnd.randrange(3, 12), rnd.randrange(3, 12))
        if variant % 3 == 1:
            _pebble(cv, rnd, rnd.randrange(3, 12), rnd.randrange(4, 12))
        if variant % 4 == 2:
            _diagonal_shadow(cv, rnd, rnd.randrange(1, 8), rnd.randrange(6, 11))
    elif key in EARTH:
        # Two paired warm/cool pixels and one short trodden stroke, not a
        # uniform sprinkle across the whole 16x16 cell.
        for _ in range(2):
            x, y = rnd.randrange(1, 14), rnd.randrange(1, 14)
            cv.px(x, y, rnd.choice(SUN_DUST[:2]))
            cv.px(x + 1, y + 1, rnd.choice(STONE_DARK))
        x, y = rnd.randrange(1, 12), rnd.randrange(2, 13)
        cv.px(x, y, rnd.choice(STONE_LIT))
        cv.px(x + 1, y, rnd.choice(STONE_LIT))
        cv.px(x + 2, y + 1, rnd.choice(STONE_DARK))
    elif key in HARD:
        # One stone chip catches the sun on its upper-left face only.
        x, y = rnd.randrange(2, 13), rnd.randrange(2, 13)
        cv.px(x, y, rnd.choice(STONE_LIT))
        cv.px(x + 1, y + 1, rnd.choice(STONE_DARK))
    elif key in WATER:
        # One short gold reflection dash on the animated water frames; the four
        # frames still differ from one another exactly as the classic atlas does.
        x, y = rnd.randrange(1, 11), rnd.randrange(3, 12)
        cv.px(x, y, rnd.choice(SUN_DUST[:2]))
        cv.px(x + 1, y, rnd.choice(SUN_DUST[:2]))
        cv.px(x + 2, y + 1, rnd.choice(COOL_DUST))
    return cv

def main():
    P.RAMPS = build_ramp_map()
    P.ALL = sorted({h for r in P.RAMPS.values() for h in r})
    P.SHADOW = SHADOW
    P.OUTLINE = OUTLINE
    P.HIGHLIGHT = HIGHLIGHT
    CV.OUTLINE = OUTLINE
    CV.SHADOW = SHADOW
    T.SHADOW = SHADOW

    tiles = T.build_tiles()
    cells = []
    for key, variant, cv, _walkable in tiles:
        cells.append(embellish(key, variant, cv))
    sheet = atlas(cells, T.ATLAS_COLS, 16, 16)

    out = ROOT / "art/tiles/terrain_cinematic.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)

    preview = ROOT / "docs/art-reset/cinematic_tiles_4x.png"
    preview.parent.mkdir(parents=True, exist_ok=True)
    img = sheet.to_image()
    img.resize((img.width * 4, img.height * 4), 0).save(preview)

    colours = set()
    for cv in cells:
        colours |= cv.used_colors()
    print("wrote %s (%dx%d, %d tiles, %d distinct colours)"
          % (out.relative_to(ROOT), sheet.w, sheet.h, len(cells), len(colours)))
    print("preview:", preview.relative_to(ROOT))
    print("outline %s  shadow %s  highlight %s" % (OUTLINE, SHADOW, HIGHLIGHT))


if __name__ == "__main__":
    main()
