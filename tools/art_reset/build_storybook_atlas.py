#!/usr/bin/env python3
"""Build the SELECTED art direction's terrain atlas with the shipped artgen.

Direction C (Biblical Storybook RPG) won the four-way comparison. This tool
implements its COLOUR SYSTEM (section 5 of the brief) against the game's real,
deterministic 16x16 tile generator: the same 49 atlas cells, the same tile
shapes, the same atlas indices, the same data/tiles.json — but a completely
different, warm Levantine palette with explicit highlight/midtone/shadow ramps,
warm/cool hue shifts and a warm-brown outline instead of near-black indigo.

Because the atlas layout is unchanged, swapping it cannot break collision,
footstep surface, save data or the water animation. It is a real, integrable
asset, not a recoloured screenshot.

    PYTHONPATH=<pillow-cache> python3 tools/art_reset/build_storybook_atlas.py

Outputs
    art/tiles/terrain_storybook.png           (shipped, opt-in)
    docs/art-reset/storybook_tiles_4x.png     (human review)

LIMITATION: this changes the COLOUR SYSTEM. It does not redraw silhouettes,
sprites, buildings or tile shapes. Section 6 of docs/ART-RESET.md is explicit
that hand-authored pixel art is still required for those.
"""

from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from tools.artgen import palette as P          # noqa: E402
from tools.artgen import canvas as CV          # noqa: E402
from tools.artgen import terrain as T          # noqa: E402
from tools.artgen.canvas import atlas          # noqa: E402

# ── Direction C ramps. Each is dark → light; index 0 is ambient occlusion,
# index 2 is the mid-tone, the last is the rim light. Warm/cool shift: shadows
# go cool slate-olive, highlights go warm honey/parchment. ───────────────────
STORYBOOK = {
    "grass":       ["#3c4a34", "#536346", "#6f8056", "#8f9e70", "#b4bf92", "#ced4ac"],
    "dry":         ["#54402c", "#72563a", "#94714a", "#b28c5e", "#cda97c", "#e3c69a"],
    "path":        ["#5f5340", "#7d6b51", "#9c8766", "#b8a07c", "#d3ba93", "#e9d5b2"],
    "sand":        ["#6f5836", "#8f7448", "#ad8f5c", "#c8aa74", "#dfc392", "#efdcb4"],
    "wheat":       ["#65502a", "#846936", "#a48542", "#c2a257", "#dcbd75", "#efda9a"],
    "mud":         ["#3d3023", "#55412f", "#70553d", "#8a6c4e", "#a6845f", "#bd9a72"],
    "stone":       ["#403c32", "#575045", "#6f6756", "#897e69", "#a89a7e", "#c6b795", "#ded0ae"],
    "cliff":       ["#2c2a22", "#403c31", "#555044", "#6e6756", "#88806b"],
    "water":       ["#1f3b42", "#2c525a", "#3d6c72", "#578a8c", "#77a8a6", "#a0c6bd"],
    "foam":        ["#78a49e", "#9cc0b4", "#c2d8c8", "#e2ecdc"],
    "olive":       ["#2f4030", "#43553c", "#5c6d4c", "#778760", "#96a47c", "#b7c19c", "#d0d5b4"],
    "palm":        ["#2b4433", "#3b5b40", "#4e7550", "#659062", "#81a978"],
    "dark_leaf":   ["#213428", "#304632", "#415a40", "#54704e"],
    "wood":        ["#38271a", "#513823", "#6d4c30", "#8b6440", "#a87f54", "#c39a6c"],
    "linen":       ["#4c4438", "#695e4b", "#87785e", "#a69475", "#c5b28d", "#dfcca6", "#f1e2c2"],
    "wool":        ["#40362a", "#584838", "#715c47", "#8c7358", "#a98b6b"],
    "skin":        ["#53361f", "#714a2b", "#926440", "#b28256", "#cfa172", "#e8c093"],
    "gold":        ["#654719", "#86642a", "#aa8438", "#c9a45c", "#e2c07e", "#f7dda5"],
    "bronze":      ["#392715", "#553c20", "#75542d", "#956c3c", "#b28650"],
    "iron":        ["#1c2022", "#2b3032", "#3d4345", "#535a5b", "#6e7572"],
    "blood":       ["#2e1612", "#4b201b", "#6d2a21", "#8c382c"],
    "holy":        ["#4a4020", "#8d7a3a", "#c9b45c", "#f0e0a0", "#fff3cf"],
    "spirit":      ["#27383a", "#3f6062", "#638a88", "#9cbdb2", "#d6e6d8"],
    "hair_dark":   ["#241d18", "#332820", "#443629", "#574533"],
    "hair_grey":   ["#5c574c", "#7a7465", "#999180", "#b8af9b"],
    "hair_red":    ["#4d2818", "#683620", "#83472a", "#9e5a34"],
}

OUTLINE = "#2a1c14"     # warm brown ink, never pure black
SHADOW = "#3b3021"      # warm-cool ambient occlusion
HIGHLIGHT = "#f2dda4"   # morning rim light


def build_ramp_map():
    """Start from the classic ramps so every key the generator asks for exists,
    then replace the environment materials with the Levantine ramps."""
    ramps = {k: list(v) for k, v in P.RAMPS.items()}
    for key, value in STORYBOOK.items():
        ramps[key] = list(value)
    return ramps


def main():
    # Mutate the palette module IN PLACE: c()/ramp() are functions defined in
    # that module, so they look up its global RAMPS at call time. Importing the
    # names into this module would keep the classic colours.
    P.RAMPS = build_ramp_map()
    P.ALL = sorted({h for r in P.RAMPS.values() for h in r})
    P.SHADOW = SHADOW
    P.OUTLINE = OUTLINE
    P.HIGHLIGHT = HIGHLIGHT
    # These three were imported BY VALUE into the generator modules.
    CV.OUTLINE = OUTLINE
    CV.SHADOW = SHADOW
    T.SHADOW = SHADOW

    tiles = T.build_tiles()
    cells = [cv for (_k, _v, cv, _w) in tiles]
    sheet = atlas(cells, T.ATLAS_COLS, 16, 16)

    out = ROOT / "art/tiles/terrain_storybook.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)

    preview = ROOT / "docs/art-reset/storybook_tiles_4x.png"
    preview.parent.mkdir(parents=True, exist_ok=True)
    img = sheet.to_image()
    img.resize((img.width * 4, img.height * 4), 0).save(preview)

    colours = set()
    for cv in cells:
        colours |= cv.used_colors()
    print("wrote %s (%dx%d, %d tiles, %d distinct colours)"
          % (out.relative_to(ROOT), sheet.w, sheet.h,
             len(cells), len(colours)))
    print("preview:", preview.relative_to(ROOT))
    print("outline %s  shadow %s  highlight %s" % (OUTLINE, SHADOW, HIGHLIGHT))


if __name__ == "__main__":
    main()
