#!/usr/bin/env python3
"""preview.py — render a region from its own data as a fake screenshot.

Art iteration is blind without this. It composes exactly what the engine would
blit — terrain atlas cells chosen with the SAME variant hash TerrainLayer uses
(RegionModel.cell_variant, replicated in six lines below), props at their
authored footprints, items, and the cast at their spawn tiles — and scales it
nearest-neighbour so a tile reads the way it will on a phone.

It is a MOCK, not engine output: no y-sorting between overlapping sprites, no
camera, no lighting modulate. It exists to answer "does this tile/robe/wave
read at a glance", which is the question every art change is really asking.

    python3 -m tools.artgen.preview [region_id] [x0 y0 w h] [scale]

Defaults to elah, a 26x26 window over the ford and the camp, at 4x.
Output: art/_preview/<region>_mock.png (gitignored) and stdout path.
"""

import json
import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
T = 16


def _s64(n: int) -> int:
    return (n + 2**63) % 2**64 - 2**63


def cell_variant(x: int, y: int) -> int:
    """RegionModel.cell_variant, verbatim — GDScript ints are 64-bit signed."""
    n = (x * 73856093) ^ (y * 19349663)
    n = _s64(_s64(n ^ (n >> 13)) * 1274126177)
    return abs(n) % 997


def main() -> int:
    args = sys.argv[1:]
    rid = args[0] if args else "elah"
    X0, Y0, CW, CH = (int(v) for v in args[1:5]) if len(args) >= 5 else (6, 20, 26, 26)
    S = int(args[5]) if len(args) >= 6 else 4

    region = json.loads((ROOT / ("data/regions/%s.json" % rid)).read_text(encoding="utf-8"))
    tiles = json.loads((ROOT / "data/tiles.json").read_text(encoding="utf-8"))
    propsj = json.loads((ROOT / "data/props.json").read_text(encoding="utf-8"))
    props_meta = {p["key"]: p for p in propsj["props"]}
    atlas = Image.open(ROOT / "art/tiles/terrain.png").convert("RGBA")
    cols = int(tiles.get("columns", 16))

    order = {}
    for i, t in enumerate(tiles["tiles"]):
        order.setdefault(t["key"], []).append(i)

    scene = Image.new("RGBA", (CW * T, CH * T), (0, 0, 0, 255))
    legend = region["legend"]
    for gy in range(Y0, Y0 + CH):
        row = region["grid"][gy] if gy < len(region["grid"]) else ""
        for gx in range(X0, X0 + CW):
            ch = row[gx] if gx < len(row) else " "
            key = legend.get(ch, "grass")
            vs = order.get(key, [0])
            # water/shallow variants are ANIMATION frames, not scatter
            i = vs[0] if key in ("water", "shallow") else vs[cell_variant(gx, gy) % len(vs)]
            cell = atlas.crop(((i % cols) * T, (i // cols) * T,
                               (i % cols) * T + T, (i // cols) * T + T))
            scene.paste(cell, ((gx - X0) * T, (gy - Y0) * T))

    for pr in region.get("props", []):
        if pr["type"] not in props_meta:
            continue
        f = Image.open(ROOT / ("art/props/%s.png" % pr["type"])).convert("RGBA")
        ax, ay = pr["at"]
        px, py = (ax - X0) * T, (ay - Y0 + 1) * T - f.height
        if -f.width < px < CW * T and -f.height < py < CH * T:
            scene.paste(f, (px, py), f)

    for it in region.get("items", []):
        f = Image.open(ROOT / ("art/props/%s.png" % it.get("sprite", "rock"))).convert("RGBA")
        small = f.resize((max(1, int(f.width * 0.6)), max(1, int(f.height * 0.6))), Image.NEAREST)
        scene.paste(small, ((int(it["at"][0]) - X0) * T + 4, (int(it["at"][1]) - Y0) * T + 8), small)

    def person(cid, tx, ty, frame=0):
        path = ROOT / ("art/characters/%s_walk.png" % cid)
        if not path.exists():
            path = ROOT / "art/characters/villager_a_walk.png"
        sheet = Image.open(path).convert("RGBA")
        cell = sheet.crop((frame * 16, 0, frame * 16 + 16, 24))
        scene.paste(cell, ((tx - X0) * T, (ty - Y0 + 1) * T - 24 + 4), cell)

    sp = region["spawn"]
    person("pilgrim", int(sp[0]), int(sp[1]), 1)
    for n in region.get("npcs", []):
        person(str(n.get("actor", "villager_a")), int(n["at"][0]), int(n["at"][1]), 0)

    out = ROOT / ("art/_preview/%s_mock.png" % rid)
    out.parent.mkdir(parents=True, exist_ok=True)
    scene.resize((scene.width * S, scene.height * S), Image.NEAREST).save(out)
    print("preview: %s (%dx%d tiles at %dx) -> %s" % (rid, CW, CH, S, out.relative_to(ROOT)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
