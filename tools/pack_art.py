#!/usr/bin/env python3
"""pack_art.py — cut the vendored Ninja Adventure sheets into the game's art.

The pack is CC0 (public domain) and is the base layer for every tile and prop it
can supply; anything it cannot supply keeps the generated art from
tools/artgen/. tools/art_manifest.json says which is which, by pixel rectangle.

    python3 tools/pack_art.py            # cut + write art/, data/tiles.json, data/props.json
    python3 tools/pack_art.py --check    # verify only, write nothing

What it guarantees (and --check re-verifies):
  * every terrain key keeps the same NUMBER of variants data/tiles.json already
    declares, so RegionModel's variant hash still spreads across the field
  * the hand-authored fields in data/tiles.json (walkable / speed / sfx / note)
    and in data/props.json (footprint / solid) are PRESERVED — art only changes
    w/h, which the engine reads to place a sprite
  * every key a region legend uses maps to a real tile
  * every prop type a region places maps to a real PNG

The tileset sheet is 16 columns wide, like the generated one it replaces, and
each key's variants are contiguous — artgen, Region.gd and the preview tool all
assume that layout.
"""

import json
import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
T = 16
COLS = 16
SHEETS = {
    "floor": "art/pack/tileset_floor.png",
    "village": "art/pack/tileset_village_abandoned.png",
    "interior_floor": "art/pack/tileset_interior_floor.png",
    "wall": "art/pack/tileset_wall_simple.png",
    "animated": "art/pack/tileset_animated.png",
}


def load_sheets() -> dict:
    out = {}
    for key, rel in SHEETS.items():
        p = ROOT / rel
        if not p.exists():
            sys.exit("pack_art: missing sheet %s — is the pack vendored?" % rel)
        out[key] = Image.open(p).convert("RGBA")
    return out


def manifest() -> dict:
    return json.loads((ROOT / "tools/art_manifest.json").read_text(encoding="utf-8"))


def cut(sheets: dict, sheet: str, x: int, y: int, w: int, h: int) -> Image.Image:
    s = sheets[sheet]
    if x + w > s.width or y + h > s.height:
        sys.exit("pack_art: rect %s@%d,%d %dx%d runs off the %dx%d sheet"
                 % (sheet, x, y, w, h, s.width, s.height))
    return s.crop((x, y, x + w, y + h))


# ── terrain ────────────────────────────────────────────────────────────────
def build_terrain(sheets: dict, man: dict, check_only: bool) -> int:
    """Overlay pack cells onto the atlas artgen just built.

    Overlay, not rebuild: tools/artgen owns the atlas LAYOUT (which index is
    which key/variant) and supplies every key the pack cannot — water, the
    ford, mud, cliff. Rebuilding here would mean duplicating that layout and
    silently drifting from it.
    """
    if not man["terrain"]:
        print("terrain    (none in the manifest)")
        return 0
    tiles_path = ROOT / "data/tiles.json"
    data = json.loads(tiles_path.read_text(encoding="utf-8"))
    atlas_path = ROOT / "art/tiles/terrain.png"
    if not atlas_path.exists():
        sys.exit("pack_art: %s is missing — run tools/artgen/build.py first" % atlas_path)
    atlas = Image.open(atlas_path).convert("RGBA")
    cols = int(data.get("columns", COLS))

    placed = 0
    for i, t in enumerate(data["tiles"]):
        picks = man["terrain"].get(t["key"])
        if not picks:
            continue
        v = int(t.get("variant", 0))
        sheet, x, y = picks[v % len(picks)]
        cell = cut(sheets, sheet, x, y, T, T)
        opaque = sum(1 for px in cell.getdata() if px[3] > 8) / float(T * T)
        if opaque < 0.97:
            sys.exit("pack_art: '%s' variant %d picks %s@%d,%d which is only %.0f%% "
                     "filled — that is a sprite edge or empty cell, not ground"
                     % (t["key"], v, sheet, x, y, opaque * 100))
        if not check_only:
            atlas.alpha_composite(cell, ((i % cols) * T, (i // cols) * T))
        t["source"] = "ninja:%s@%d,%d" % (sheet, x, y)
        placed += 1

    if check_only:
        print("check: terrain overlay %d cells" % placed)
        return 0
    atlas.save(atlas_path)
    tiles_path.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print("terrain    %d cells from the pack, %d keys still generated"
          % (placed, len({t["key"] for t in data["tiles"]}) - len(man["terrain"])))
    return 0


# ── props ──────────────────────────────────────────────────────────────────
def clean_fragments(img: Image.Image) -> Image.Image:
    """Drop stray marks that belong to a NEIGHBOUR sprite in the sheet.

    The pack lays sprites flush against each other, so a rectangle that holds
    one whole sprite also clips a 1px outline of the one beside it. Those slivers
    read as dust floating next to a tree. Anything small that only touches the
    rectangle's border goes.
    """
    from collections import deque
    w, h = img.size
    px = img.load()
    seen = [[False] * w for _ in range(h)]
    kill = []
    for y in range(h):
        for x in range(w):
            if px[x, y][3] == 0 or seen[y][x]:
                continue
            q = deque([(x, y)])
            seen[y][x] = True
            comp = []
            edge = False
            while q:
                cx, cy = q.popleft()
                comp.append((cx, cy))
                if cx in (0, w - 1) or cy in (0, h - 1):
                    edge = True
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx] and px[nx, ny][3] > 0:
                        seen[ny][nx] = True
                        q.append((nx, ny))
            if edge and len(comp) < 40:
                kill.extend(comp)
    for (x, y) in kill:
        px[x, y] = (0, 0, 0, 0)
    return img


def build_props(sheets: dict, man: dict, check_only: bool) -> int:
    props_path = ROOT / "data/props.json"
    data = json.loads(props_path.read_text(encoding="utf-8"))
    by_key = {p["key"]: p for p in data["props"]}

    placed = 0
    for key, spec in man["props"].items():
        meta = by_key.get(key)
        if meta is None:
            sys.exit("pack_art: manifest has prop '%s' that data/props.json does not" % key)
        x, y, w, h = spec["rect"]
        placed += 1
        img = clean_fragments(cut(sheets, spec["sheet"], x, y, w, h))
        if check_only:
            continue
        img.save(ROOT / ("art/props/%s.png" % key))
        meta["w"], meta["h"] = w, h
        meta["frames"] = spec.get("frames", 1)
        meta["source"] = "ninja:%s@%d,%d" % (spec["sheet"], x, y)

    if not check_only:
        props_path.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print("props      %d from the pack, %d still generated"
          % (len(man["props"]), len(data["props"]) - len(man["props"])))
    return 0


# ── verification ───────────────────────────────────────────────────────────
def verify() -> int:
    bad = []
    tiles = json.loads((ROOT / "data/tiles.json").read_text(encoding="utf-8"))
    props = {p["key"]: p for p in json.loads((ROOT / "data/props.json").read_text(encoding="utf-8"))["props"]}
    keys = {t["key"] for t in tiles["tiles"]}

    for region in (ROOT / "data/regions").glob("*.json"):
        r = json.loads(region.read_text(encoding="utf-8"))
        for ch, key in r.get("legend", {}).items():
            if key not in keys:
                bad.append("%s: legend '%s' -> terrain '%s' has no tile" % (region.name, ch, key))
        for p in r.get("props", []):
            if p["type"] not in props:
                bad.append("%s: prop '%s' missing from data/props.json" % (region.name, p["type"]))
            elif not (ROOT / ("art/props/%s.png" % p["type"])).exists():
                bad.append("%s: prop '%s' has no PNG" % (region.name, p["type"]))

    for p in props.values():
        img = ROOT / ("art/props/%s.png" % p["key"])
        if not img.exists():
            continue
        w, h = Image.open(img).size
        # frames are laid out in a row: the PNG is w*frames × h
        want_w, want_h = p["w"] * int(p.get("frames", 1)), p["h"]
        if (w, h) != (want_w, want_h):
            bad.append("prop '%s': PNG is %dx%d but data says %dx%d (%d frame(s) of %dx%d)"
                       % (p["key"], w, h, want_w, want_h, p.get("frames", 1), p["w"], p["h"]))

    sheet = Image.open(ROOT / "art/tiles/terrain.png")
    need = ((len(tiles["tiles"]) + COLS - 1) // COLS) * T
    if sheet.height < need:
        bad.append("terrain.png is %dpx tall, %d tiles need %dpx" % (sheet.height, len(tiles["tiles"]), need))

    if bad:
        print("pack_art: FAIL — %d problem(s)" % len(bad))
        for b in bad[:20]:
            print("  " + b)
        return 1
    print("pack_art: clean — %d tiles (%d keys), %d props, every region key resolves"
          % (len(tiles["tiles"]), len(keys), len(props)))
    return 0


def main() -> int:
    check_only = "--check" in sys.argv
    sheets = load_sheets()
    man = manifest()
    build_terrain(sheets, man, check_only)
    build_props(sheets, man, check_only)
    return verify()


if __name__ == "__main__":
    sys.exit(main())
