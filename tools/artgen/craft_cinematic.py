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

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from PIL import Image                             # noqa: E402

from tools.artgen import craft_props as CP        # noqa: E402
from tools.artgen import craft_characters as CC   # noqa: E402

# B's ramps are read from the shipped palette file so that the atlas,
# the crafted props, the character sheets and the stdlib CI gate cannot drift.
B = json.loads((ROOT / "data/cinematic_palette.json").read_text())


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


def _rgb(value: str):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def _directional_rim(path, light: str, dark: str) -> None:
    """Shape-aware upper-left rim and lower-right shade, on EXISTING pixels.

    The crafted C geometry is already clean; a palette swap alone leaves the
    sprites as flat cut-outs. This recolours the pixels immediately inside each
    silhouette's ink edge, so the low upper-left sun reads on trees, stones,
    sheep and every animation frame without adding a detached halo or changing
    one alpha value. The ink outline itself is preserved.
    """
    from collections import deque

    im = Image.open(path).convert("RGBA")
    a = im.load()
    w, h = im.size
    ink, lit, dim = _rgb(B["INK"]), _rgb(light), _rgb(dark)
    opaque = [[a[x, y][3] >= 128 for x in range(w)] for y in range(h)]
    # Flood-fill the REAL outside through transparent pixels. Internal ink
    # lines (eyes, belts, roof seams) must NOT be mistaken for a silhouette
    # edge: the first pass did that and turned the character sheets into pale
    # skeletons. Only ink directly adjacent to this outside is an outline.
    outside = [[False] * w for _ in range(h)]
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if not opaque[y][x] and not outside[y][x]:
                outside[y][x] = True; q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if not opaque[y][x] and not outside[y][x]:
                outside[y][x] = True; q.append((x, y))
    while q:
        x, y = q.popleft()
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h and not opaque[ny][nx] and not outside[ny][nx]:
                outside[ny][nx] = True; q.append((nx, ny))
    boundary = [[False] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            if not opaque[y][x] or a[x, y][:3] != ink:
                continue
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if not (0 <= nx < w and 0 <= ny < h) or outside[ny][nx]:
                    boundary[y][x] = True
                    break
    out = im.copy()
    b = out.load()
    for y in range(h):
        for x in range(w):
            col = a[x, y]
            if not opaque[y][x] or col[:3] == ink:
                continue
            ul = ((x - 1, y), (x, y - 1))
            lr = ((x + 1, y), (x, y + 1))
            def near(points):
                return any(0 <= nx < w and 0 <= ny < h and boundary[ny][nx]
                           for nx, ny in points)
            if near(ul):
                b[x, y] = (*lit, 255)
            elif near(lr):
                b[x, y] = (*dim, 255)
    out.save(path)


def embellish_assets() -> None:
    """Add B's single-light rim to the crafted props and actor sheets."""
    foliage = {"olive_tree", "fig_tree", "palm_tree", "bush"}
    for key in ["olive_tree", "fig_tree", "palm_tree", "bush", "rock",
                "boulder", "sheep", "sheep_alert", "sheep_graze", "fold",
                "tent", "house", "well"]:
        light = B["OLIVE_L"] if key in foliage else B["STONE_L"]
        dark = B["OLIVE_D"] if key in foliage else B["STONE_D"]
        _directional_rim(CP.PROPS / (key + ".png"), light, dark)
    for name in ["pilgrim_idle", "pilgrim_walk", "shepherd_idle", "shepherd_walk"]:
        _directional_rim(CC.OUT / (name + ".png"), B["LINEN_L"], B["WOOD_D"])


def main():
    rebind()
    CP.main()
    CC.main()
    embellish_assets()
    print("Direction B crafted art written with identical geometry, frame counts "
          "and a shape-aware golden-hour rim")


if __name__ == "__main__":
    main()
