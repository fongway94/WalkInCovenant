#!/usr/bin/env python3
"""craft_cinematic.py — Direction B versions of the crafted art.

Same geometry, same pixel grid, same dimensions and SAME FRAME COUNTS as the
Direction-C crafted assets, but B's golden-hour palette: deep cool green
shadows, warm honey rim light, sunlit ochre stone and dark warm ink outlines.
That is exactly the constraint the user set: "outcome like B, with the
necessary animation like current" — the walk cycles, idle poses, sway, water
frames and Timer-driven prop frames are unchanged.

The generator reuses the hand-authored shape functions verbatim; only the
module-level colour ramps are rebound. No proprietary art is involved.

    PYTHONPATH=<pillow-cache> python3 tools/artgen/craft_cinematic.py
    python3 tools/check_cinematic_art.py --write   # stdlib CI gate
"""
from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from tools.artgen import craft_props as CP        # noqa: E402
from tools.artgen import craft_characters as CC   # noqa: E402

# B's ramps, taken from tools/art_reset/build_cinematic_atlas.py.
B = {
    "INK":      "#1b1710",
    "WOOD_D":   "#241810", "WOOD_M": "#50331d", "WOOD_L": "#8a5e36", "WOOD_H": "#c79b66",
    "OLIVE_D":  "#182c1c", "OLIVE_M": "#395730", "OLIVE_L": "#6a8c46", "OLIVE_H": "#dbe49c",
    "STONE_D":  "#2b2a24", "STONE_M": "#545045", "STONE_L": "#a89f88", "STONE_H": "#e6dabb",
    "CLAY_D":   "#4c3823", "CLAY_M": "#8c6840", "CLAY_L": "#cda866",
    "LINEN_D":  "#3a352a", "LINEN_M": "#8a7a5e", "LINEN_L": "#e4d1ae", "LINEN_H": "#f6e8c8",
    "SKIN_D":   "#3e2818", "SKIN_M": "#7d5330", "SKIN_L": "#dfb17f",
    "WATER_D":  "#173036", "WATER_L": "#6b9e94",
    "GOLD":     "#d8a94c",
}


def rebind():
    for name, value in B.items():
        setattr(CP, name, value)
        if hasattr(CC, name):
            setattr(CC, name, value)
    CP.ALLOWED = set(B.values())
    # `poly()` and `blob()` bind `outline=INK` as a DEFAULT ARGUMENT at import
    # time. Rebinding the module global alone would leave C's brown ink on
    # every silhouette, so the defaults must be rebound too. CC imported the
    # very same function objects, so this covers both modules.
    CP.poly.__defaults__ = (B["INK"],)
    CP.blob.__defaults__ = (B["INK"], 11, 0.20)
    CP.PROPS = ROOT / "art/props_cinematic"
    CC.OUT = ROOT / "art/characters_cinematic"
    CC.OUT.mkdir(parents=True, exist_ok=True)
    CP.PROPS.mkdir(parents=True, exist_ok=True)
    CC.ACTORS = {
        "pilgrim": {"robe": B["LINEN_D"], "light": B["LINEN_M"],
                    "rim": B["LINEN_L"], "shade": B["WOOD_D"],
                    "hair": B["WOOD_D"], "sash": B["CLAY_M"]},
        "shepherd": {"robe": B["WOOD_M"], "light": B["LINEN_D"],
                     "rim": B["LINEN_M"], "shade": B["WOOD_D"],
                     "hair": B["WOOD_D"], "sash": B["GOLD"]},
    }


def main():
    rebind()
    CP.main()
    CC.main()
    print("Direction B crafted art written with identical geometry and frame counts")


if __name__ == "__main__":
    main()
