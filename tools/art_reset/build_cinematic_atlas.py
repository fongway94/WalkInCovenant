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

    PYTHONPATH=<pillow-cache> python3 tools/art_reset/build_cinematic_atlas.py

Outputs
    art/tiles/terrain_cinematic.png           (shipped, opt-in)
    docs/art-reset/cinematic_tiles_4x.png     (human review)
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

# dark → light; index 0 is ambient occlusion, last is the golden rim light.
CINEMATIC = {
    # Direction B v2: the low sun actually reaches the grass. The first B atlas
    # measured world luma 58.0 against the concept's 84.6, so the dark green
    # ramps were lifted toward warm olive/gold while the shadows stay cool.
    "grass":       ["#24361f", "#3a5127", "#557337", "#7a9345", "#a8ad55", "#d0bb6b", "#f2d68a"],
    "dry":         ["#3a2b19", "#533d24", "#725433", "#946f43", "#b89057", "#d8b375", "#efd19a"],
    "path":        ["#4a3420", "#6a4a29", "#8d6535", "#b28544", "#d5a757", "#efc775", "#ffe4a0"],
    "sand":        ["#544128", "#755934", "#967544", "#b89458", "#d5b074", "#e9ca90", "#f7e2b4"],
    "wheat":       ["#4e3a1c", "#6d5322", "#8e6c2c", "#ad883a", "#cba54d", "#e4c26c", "#f5dd97"],
    "mud":         ["#2c2418", "#423322", "#5a4430", "#755840", "#926f52", "#ac8968", "#c5a480"],
    "stone":       ["#2b2a24", "#3e3c33", "#545045", "#6d685a", "#898272", "#a89f88", "#cbc1a3", "#e6dabb"],
    "cliff":       ["#23231c", "#35342b", "#4a473a", "#615c4b", "#7c7660"],
    "water":       ["#173036", "#24464a", "#356165", "#4a7e7d", "#6b9e94", "#93bdaa", "#c2d9bd"],
    "foam":        ["#5f8c86", "#86ada0", "#b1cbb6", "#dce8cf"],
    "olive":       ["#1d3020", "#2f4a28", "#496631", "#6b8440", "#93a253", "#c1ba69", "#e6d08a"],
    "palm":        ["#223826", "#355133", "#4d7040", "#6a8d50", "#8fae63"],
    "dark_leaf":   ["#1b2e20", "#29412c", "#3b5736", "#516e42"],
    "wood":        ["#241810", "#382415", "#50331d", "#6c4728", "#8a5e36", "#a87b4b", "#c79b66"],
    "linen":       ["#3a352a", "#53493a", "#6e6049", "#8a7a5e", "#a89675", "#c7b492", "#e4d1ae", "#f6e8c8"],
    "wool":        ["#33291e", "#4a3a2a", "#63503a", "#7e684a", "#9c805c"],
    "skin":        ["#3e2818", "#5c3b22", "#7d5330", "#a07043", "#c28f5e", "#dfb17f", "#f2d3a6"],
    "gold":        ["#4d3410", "#6d4d1a", "#916724", "#b88731", "#d8a94c", "#eec773", "#fbe2a1"],
    "bronze":      ["#2c1e0e", "#432e15", "#5d4220", "#7a592b", "#9a753c"],
    "iron":        ["#171b1c", "#252b2c", "#363d3e", "#4a5251", "#636b66"],
    "blood":       ["#24100c", "#3c1913", "#572318", "#753024"],
    "holy":        ["#3a3214", "#73612a", "#a98f42", "#d8bb68", "#f6e2a4", "#fff4cf"],
    "spirit":      ["#1d3031", "#315254", "#4d7773", "#79a49a", "#b3cfc0", "#dcebd8"],
    "hair_dark":   ["#1b1510", "#291f17", "#382b1f", "#493929"],
    "hair_grey":   ["#464237", "#5e594b", "#7a7362", "#97907d"],
    "hair_red":    ["#3d1e10", "#542a16", "#6d3a1f", "#874a29"],
}

OUTLINE = "#1b1710"      # dark warm brown ink, never pure black
SHADOW = "#221d16"       # cool-warm ambient occlusion
HIGHLIGHT = "#ffe6a3"    # low golden sun rim light


def build_ramp_map():
    ramps = {k: list(v) for k, v in P.RAMPS.items()}
    for key, value in CINEMATIC.items():
        ramps[key] = list(value)
    return ramps


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
    cells = [cv for (_k, _v, cv, _w) in tiles]
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
