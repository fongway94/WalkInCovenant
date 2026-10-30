#!/usr/bin/env python3
"""artgen build — generate the game's pixel art into art/.

    python3 -m tools.artgen.build            # everything
    python3 -m tools.artgen.build terrain    # one group
    python3 -m tools.artgen.build --preview  # also write 8× previews for review

Every output is deterministic: same code in, byte-identical PNG out. That keeps
git diffs meaningful and lets you trust that what you reviewed is what shipped.
"""

import json
import os
import sys

from . import TILE, CHAR_W, CHAR_H, atlas
from .canvas import Canvas
from . import terrain as T
from . import chars as C

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ART = os.path.join(ROOT, "art")
DATA = os.path.join(ROOT, "data")

PREVIEW_SCALE = 8


def _out(*parts):
    p = os.path.join(ART, *parts)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    return p


def _preview(cv, name):
    """Nearest-neighbour upscale so a human (or an agent) can actually see it."""
    img = cv.to_image().resize(
        (cv.w * PREVIEW_SCALE, cv.h * PREVIEW_SCALE), 0)  # 0 = NEAREST
    p = _out("_preview", name)
    img.save(p)
    return p


def build_terrain(preview=False):
    tiles = T.build_tiles()
    cells = [cv for (_k, _v, cv, _w) in tiles]
    sheet = atlas(cells, T.ATLAS_COLS, TILE, TILE)
    path = _out("tiles", "terrain.png")
    sheet.save(path)

    meta = json.loads(T.tiles_json())
    meta["atlas"] = "res://art/tiles/terrain.png"
    meta["rows"] = (len(cells) + T.ATLAS_COLS - 1) // T.ATLAS_COLS
    mpath = os.path.join(DATA, "tiles.json")
    os.makedirs(DATA, exist_ok=True)
    with open(mpath, "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=1, ensure_ascii=False)

    if preview:
        _preview(sheet, "terrain.png")
        # per-tile strips, big enough to judge individually
        for key, _f, variants, _w, _n in T.TERRAIN:
            cs = [cv for (k, _v, cv, _x) in tiles if k == key]
            if cs:
                _preview(atlas(cs, len(cs), TILE, TILE), "tile_%s.png" % key)
    return path, mpath, len(cells)


def build_chars(preview=False):
    sheets = C.build_sheets()
    n = 0
    for cid, d in sheets.items():
        for kind in ("walk", "idle"):
            p = _out("characters", "%s_%s.png" % (cid, kind))
            d[kind].save(p)
            n += 1
            if preview:
                _preview(d[kind], "char_%s_%s.png" % (cid, kind))
    return n


def build_props(preview=False):
    from . import props as P
    import json as _json
    ps = P.build_props()
    n = 0
    meta = {"props": []}
    for key, p in ps.items():
        frames = p["canvas"] if isinstance(p["canvas"], list) else [p["canvas"]]
        sheet = atlas(frames, len(frames), max(f.w for f in frames), max(f.h for f in frames))
        pw = _out("props", "%s.png" % key)
        sheet.save(pw)
        meta["props"].append({
            "key": key, "frames": len(frames),
            "w": frames[0].w, "h": frames[0].h,
            "footprint": list(p["footprint"]), "solid": p["solid"], "notes": p["notes"],
        })
        n += 1
        if preview:
            _preview(sheet, "prop_%s.png" % key)
    mpath = os.path.join(DATA, "props.json")
    os.makedirs(DATA, exist_ok=True)
    with open(mpath, "w", encoding="utf-8") as f:
        _json.dump(meta, f, indent=1, ensure_ascii=False)
    # a contact sheet so the whole prop set can be judged at a glance
    allframes = []
    widths = []
    for key, p in ps.items():
        frames = p["canvas"] if isinstance(p["canvas"], list) else [p["canvas"]]
        allframes.append((key, frames[0]))
    maxh = max(f.h for _k, f in allframes)
    totalw = sum(f.w + 2 for _k, f in allframes)
    strip = Canvas(totalw, maxh)
    x = 0
    for _k, f in allframes:
        strip.paste(f, x, maxh - f.h)
        x += f.w + 2
    if preview:
        _preview(strip, "props_strip.png")
    return n


GROUPS = {"terrain": build_terrain, "chars": build_chars, "props": build_props}


def main(argv):
    preview = "--preview" in argv
    args = [a for a in argv if not a.startswith("--")]
    only = set(args) if args else set(GROUPS)

    for name in sorted(GROUPS):
        if name not in only:
            continue
        res = GROUPS[name](preview=preview)
        if isinstance(res, tuple):
            print("%-10s %s" % (name, " ".join(str(r) for r in res)))
        else:
            print("%-10s %s file(s)" % (name, res))
    print("\nwrote into %s" % ART)
    if preview:
        print("previews   %s" % _out("_preview"))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
