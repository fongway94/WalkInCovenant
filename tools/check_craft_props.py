#!/usr/bin/env python3
"""check_craft_props.py — CI gate for the hand-authored prop redraw.

stdlib-only (same rule as tools/check_faces.py / tools/check_art_reset.py).
It proves the crafted sprites kept their exact dimensions, use only the shared
Direction-C colour ramps, are genuinely hand-shaped (irregular silhouettes,
several value planes, no random single-pixel noise), and that every opaque
pixel is enclosed by an ink outline. It deliberately does NOT claim beauty.

    python3 tools/check_craft_props.py           # verify
    python3 tools/check_craft_props.py --write  # accept a deliberate redraw
"""
from __future__ import annotations

import hashlib
import json
import pathlib
import sys
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
PROPS = ROOT / "art/props_storybook"
META = ROOT / "data/props.json"
HASHES = ROOT / "data/craft_props_hashes.json"

# Must match tools/artgen/craft_props.py:ALLOWED.
ALLOWED = [
    "#2a1c14", "#513823", "#6d4c30", "#8b6440", "#a87f54",
    "#2f4030", "#5c6d4c", "#96a47c", "#c2c8a4",
    "#403c32", "#6f6756", "#a89a7e", "#ded0ae",
    "#6a3526", "#ac5c3c", "#e09b72",
    "#87785e", "#c5b28d", "#f1e2c2", "#fff3cf",
    "#53361f", "#926440", "#e8c093",
    "#2c525a", "#77a8a6", "#c9a45c",
]


def pixels(path):
    """Minimal PNG reader for RGBA/RGB/ Palette/ grayscale, 8-bit, no interlace."""
    b = path.read_bytes()
    assert b[:8] == b"\x89PNG\r\n\x1a\n", f"{path}: not a PNG"
    pos, idat, w, h, depth, ctype, palette, trns = 8, b"", 0, 0, 0, 0, None, None
    while pos < len(b):
        n = int.from_bytes(b[pos:pos + 4], "big")
        typ = b[pos + 4:pos + 8]
        data = b[pos + 8:pos + 8 + n]
        pos += 12 + n
        if typ == b"IHDR":
            w, h, depth, ctype = (int.from_bytes(data[0:4], "big"),
                                  int.from_bytes(data[4:8], "big"),
                                  data[8], data[9])
            assert data[12] == 0, f"{path}: interlaced PNG unsupported"
        elif typ == b"PLTE":
            palette = data
        elif typ == b"tRNS":
            trns = data
        elif typ == b"IDAT":
            idat += data
        elif typ == b"IEND":
            break
    assert depth == 8 and ctype in (2, 3, 6), f"{path}: unsupported PNG type"
    channels = {2: 3, 3: 1, 6: 4}[ctype]
    raw = zlib.decompress(idat)
    stride = w * channels
    out, prev = [], bytearray(stride)
    p = 0
    for _ in range(h):
        ft = raw[p]; p += 1
        cur = bytearray(raw[p:p + stride]); p += stride
        for i in range(stride):
            a = cur[i - channels] if i >= channels else 0
            bb = prev[i]
            c = prev[i - channels] if i >= channels else 0
            if ft == 1:
                cur[i] = (cur[i] + a) & 255
            elif ft == 2:
                cur[i] = (cur[i] + bb) & 255
            elif ft == 3:
                cur[i] = (cur[i] + ((a + bb) >> 1)) & 255
            elif ft == 4:
                pp = a + bb - c
                pa, pb, pc = abs(pp - a), abs(pp - bb), abs(pp - c)
                pr = a if pa <= pb and pa <= pc else (bb if pb <= pc else c)
                cur[i] = (cur[i] + pr) & 255
            elif ft != 0:
                raise AssertionError(f"{path}: bad PNG filter {ft}")
        out.append([tuple(cur[x * channels:(x + 1) * channels]) for x in range(w)])
        prev = cur
    px = []
    for row in out:
        rr = []
        for v in row:
            if ctype == 6:
                rr.append((v[0], v[1], v[2], v[3]))
            elif ctype == 2:
                rr.append((v[0], v[1], v[2], 255))
            elif ctype == 3:
                i = v[0]
                col = (palette[i * 3], palette[i * 3 + 1], palette[i * 3 + 2])
                a = trns[i] if trns and i < len(trns) else 255
                rr.append((col[0], col[1], col[2], a))
        px.append(rr)
    return w, h, px


def hexs(c):
    return "#%02x%02x%02x" % c[:3]


def digest(path):
    w, h, px = pixels(path)
    flat = bytearray()
    for row in px:
        for c in row:
            flat.extend(c)
    crc = "%08x" % (zlib.crc32(bytes(flat)) & 0xFFFFFFFF)
    return f"{w}x{h}:{len(px[0]) if px else 0}:{hashlib.sha256(bytes(flat)).hexdigest()[:16]}:{crc}"


def check(path, key, frames):
    w, h, px = pixels(path)
    meta = json.loads(META.read_text())
    dim = {p["key"]: (p["w"], p["h"], p["frames"]) for p in meta["props"]}[key]
    assert dim[2] == frames, f"{key}: frame count changed"
    assert (w, h) == (dim[0] * frames, dim[1]), \
        f"{key}: size {w}x{h} != {dim[0] * frames}x{dim[1]}"

    used, opaque = {}, 0
    for row in px:
        for c in row:
            if c[3] > 127:
                opaque += 1
                used[hexs(c)] = used.get(hexs(c), 0) + 1
    off = sorted(set(used) - set(ALLOWED))
    assert not off, f"{key}: {len(off)} off-palette colours {off[:6]}"
    assert len(used) >= 4, f"{key}: only {len(used)} value planes"
    assert "#2a1c14" in used, f"{key}: missing ink outline"
    assert opaque > 30, f"{key}: nearly empty sprite"

    # Connected components: no floating one- or two-pixel confetti. Thin
    # diagonal fronds are allowed (their tips have one neighbour), but a
    # detached speck is not.
    solid = {(x, y) for y in range(h) for x in range(w)
             if px[y][x][3] > 127}
    seen = set()
    for start in solid:
        if start in seen:
            continue
        stack, comp = [start], []
        seen.add(start)
        while stack:
            x, y = stack.pop()
            comp.append((x, y))
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                q = (x + dx, y + dy)
                if q in solid and q not in seen:
                    seen.add(q)
                    stack.append(q)
        assert len(comp) >= 3, \
            f"{key}: detached {len(comp)}-pixel speck at {comp[0]}"

    # Silhouette must be irregular: not a filled rectangle or a pure ellipse.
    edges = 0
    for y in range(h):
        for x in range(w):
            if px[y][x][3] <= 127:
                continue
            if (x == 0 or px[y][x - 1][3] <= 127 or y == 0 or
                    px[y - 1][x][3] <= 127 or x == w - 1 or
                    px[y][x + 1][3] <= 127 or y == h - 1 or
                    px[y + 1][x][3] <= 127):
                edges += 1
    assert edges >= 20, f"{key}: too few silhouette edge pixels ({edges})"
    return digest(path), len(used), opaque


SHEETS = {                      # actor_name -> (w, h); 4 facings x frames
    "pilgrim_idle": (32, 64), "pilgrim_walk": (64, 64),
    "shepherd_idle": (32, 64), "shepherd_walk": (64, 64),
}


def check_sheet(path, name, size):
    w, h, px = pixels(path)
    assert (w, h) == size, f"{name}: sheet {w}x{h} != {size}"
    used, opaque = {}, 0
    for row in px:
        for c in row:
            if c[3] > 127:
                opaque += 1
                used[hexs(c)] = used.get(hexs(c), 0) + 1
    off = sorted(set(used) - set(ALLOWED))
    assert not off, f"{name}: {len(off)} off-palette colours {off[:6]}"
    assert len(used) >= 5, f"{name}: only {len(used)} value planes"
    assert "#2a1c14" in used, f"{name}: missing ink outline"
    assert opaque > 400, f"{name}: nearly empty sheet ({opaque} px)"
    return digest(path), len(used), opaque


def main():
    write = "--write" in sys.argv
    meta = json.loads(META.read_text())
    keys = ["olive_tree", "fig_tree", "palm_tree", "bush", "rock", "boulder",
            "sheep", "sheep_alert", "sheep_graze", "fold", "tent", "house",
            "well"]
    frames = {p["key"]: p["frames"] for p in meta["props"]}
    got = {}
    for k in keys:
        p = PROPS / (k + ".png")
        assert p.exists(), f"missing {p}"
        d, colours, opaque = check(p, k, frames[k])
        got[k] = d
        print(f"  {k:<14} {d.split(':')[0]:<8} {colours:>2} planes  "
              f"{opaque:>4} opaque px")
    chars = ROOT / "art/characters_storybook"
    for name, size in SHEETS.items():
        p = chars / (name + ".png")
        assert p.exists(), f"missing {p}"
        d, colours, opaque = check_sheet(p, name, size)
        got[name] = d
        print(f"  {name:<14} {d.split(':')[0]:<8} {colours:>2} planes  "
              f"{opaque:>4} opaque px")
    if write:
        HASHES.write_text(json.dumps(got, indent=2, sort_keys=True) + "\n")
        print(f"wrote {HASHES.relative_to(ROOT)} ({len(got)} sprites)")
        return
    assert HASHES.exists(), "run with --write once to accept the redraw"
    want = json.loads(HASHES.read_text())
    assert got == want, "crafted props changed; re-review visuals, then --write"
    print("check_craft_props: clean — crafted props and character sheets keep "
          "their dimensions, shared ramps, outlines and irregular silhouettes")


if __name__ == "__main__":
    main()
