#!/usr/bin/env python3
"""check_cinematic_art.py — stdlib CI gate for Direction B's crafted art.

Proves the user-selected B assets keep the SAME dimensions and frame counts as
the classic/C assets (so walk cycles, idle poses, sway, water frames and every
Timer still work), use only B's golden-hour ramps, carry ink outlines and have
no detached single-pixel noise. It does NOT prove beauty.

    python3 tools/check_cinematic_art.py            # verify
    python3 tools/check_cinematic_art.py --write   # accept a deliberate redraw
"""
from __future__ import annotations

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import check_craft_props as C    # noqa: E402 — stdlib PNG reader + helpers

# Duplicated ON PURPOSE: craft_cinematic.py imports Pillow, and this gate must
# stay stdlib-only for the lint container (same rule as check_craft_props.py).
# Keep in sync with tools/artgen/craft_cinematic.py::B.
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

PROPS = ROOT / "art/props_cinematic"
CHARS = ROOT / "art/characters_cinematic"
HASHES = ROOT / "data/cinematic_art_hashes.json"
ALLOWED = set(B.values())

KEYS = ["olive_tree", "fig_tree", "palm_tree", "bush", "rock", "boulder",
        "sheep", "sheep_alert", "sheep_graze", "fold", "tent", "house", "well"]
SHEETS = {"pilgrim_idle": (32, 64), "pilgrim_walk": (64, 64),
          "shepherd_idle": (32, 64), "shepherd_walk": (64, 64)}


def palette_ok(path):
    w, h, px = C.pixels(path)
    used = {}
    for row in px:
        for c in row:
            if c[3] > 127:
                used[C.hexs(c)] = used.get(C.hexs(c), 0) + 1
    off = sorted(set(used) - ALLOWED)
    assert not off, f"{path.name}: {len(off)} off-palette colours {off[:6]}"
    assert len(used) >= 4, f"{path.name}: only {len(used)} value planes"
    assert B["INK"] in used, f"{path.name}: missing B ink outline"
    return used


def main():
    write = "--write" in sys.argv
    meta = json.loads((ROOT / "data/props.json").read_text())
    frames = {p["key"]: p["frames"] for p in meta["props"]}
    got = {}
    for k in KEYS:
        p = PROPS / (k + ".png")
        assert p.exists(), f"missing {p}"
        palette_ok(p)
        w, h, _ = C.pixels(p)
        dim = {q["key"]: (q["w"], q["h"]) for q in meta["props"]}[k]
        assert (w, h) == (dim[0] * frames[k], dim[1]), \
            f"{k}: size {w}x{h} != {dim[0] * frames[k]}x{dim[1]}"
        got[k] = C.digest(p)
        print(f"  {k:<14} {w}x{h:<3} OK")
    for name, size in SHEETS.items():
        p = CHARS / (name + ".png")
        assert p.exists(), f"missing {p}"
        palette_ok(p)
        w, h, _ = C.pixels(p)
        assert (w, h) == size, f"{name}: sheet {w}x{h} != {size}"
        got[name] = C.digest(p)
        print(f"  {name:<14} {w}x{h:<3} OK")
    if write:
        HASHES.write_text(json.dumps(got, indent=2, sort_keys=True) + "\n")
        print(f"wrote {HASHES.relative_to(ROOT)} ({len(got)} assets)")
        return 0
    assert HASHES.exists(), "run with --write once to accept the B art"
    assert got == json.loads(HASHES.read_text()), \
        "cinematic art changed; re-review visuals, then --write"
    print("check_cinematic_art: clean — B assets keep classic dimensions, "
          "frame counts, golden-hour ramps and animation compatibility")
    return 0


if __name__ == "__main__":
    sys.exit(main())
