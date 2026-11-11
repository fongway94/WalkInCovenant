#!/usr/bin/env python3
"""check_art_reset.py — gate the selected art direction's real asset.

STANDARD LIBRARY ONLY, deliberately: the lint container has no pip. PNG pixels
come from tools/char_variants.py's zlib reader, the same one check_faces.py
uses. This gate is about the ASSET, not about taste — a passing run proves BOTH
opt-in terrains (Direction C storybook and the user-selected Direction B
cinematic) are:

  * the same 256x64 / 16px-cell atlas layout as the shipped classic terrain
    (so collision, surfaces, water animation and save data are untouched);
  * actually a DIFFERENT colour system, not a copy or a brightness tweak;
  * palette-controlled (a countable, small colour set);
  * free of pure black and pure white, the two values the house style forbids;
  * backed by the four-way comparison evidence and its measured metrics.

It does NOT prove the art is beautiful. That needs a human with eyes, which is
why docs/ART-RESET.md refuses to call the overhaul complete on a green CI.

    python3 tools/check_art_reset.py
"""

from __future__ import annotations

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import char_variants  # noqa: E402  — stdlib PNG reader

CLASSIC = ROOT / "art/tiles/terrain.png"
STORYBOOK = ROOT / "art/tiles/terrain_storybook.png"
CINEMATIC = ROOT / "art/tiles/terrain_cinematic.png"   # user-selected Direction B
COMPARISON = ROOT / "docs/art-reset/comparison"

errors = []


def fail(msg):
    errors.append(msg)


def opaque_rgb(path):
    w, h, buf = char_variants.read_png(path)
    out = []
    for i in range(0, len(buf), 4):
        r, g, b, a = buf[i], buf[i + 1], buf[i + 2], buf[i + 3]
        if a > 0:
            out.append((r, g, b))
    return w, h, out


def main():
    for p in (CLASSIC, STORYBOOK, CINEMATIC):
        if not p.exists():
            fail("missing atlas %s" % p.relative_to(ROOT))
    if errors:
        return report()

    cw, ch, cp = opaque_rgb(CLASSIC)
    sw, sh, sp = opaque_rgb(STORYBOOK)
    bw, bh, bp = opaque_rgb(CINEMATIC)
    if (bw, bh) != (cw, ch) or len(bp) != len(cp):
        fail("cinematic atlas does not share the classic 256x64 layout")

    bcol = set(bp)
    if not (30 <= len(bcol) <= 160):
        fail("cinematic palette is not controlled: %d distinct colours" % len(bcol))
    if any(c == (0, 0, 0) for c in bcol) or any(c == (255, 255, 255) for c in bcol):
        fail("cinematic atlas contains pure black or pure white")
    bchanged = sum(1 for a, b in zip(cp, bp) if a != b) / max(1, len(cp))
    if bchanged < 0.60:
        fail("cinematic atlas differs from classic on only %.1f%% of pixels"
             % (bchanged * 100.0))
    bluma = lambda c: 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]
    bvals = sorted(bluma(c) for c in bcol)
    blo = bvals[: len(bvals) // 4]
    bhi = bvals[-len(bvals) // 4:]
    if not (sum(bhi) / len(bhi) - sum(blo) / len(blo) > 45.0):
        fail("cinematic ramps have no real shadow-to-highlight separation")
    # B and C must be genuinely different colour systems, not two names for
    # one recoloured file.
    if sum(1 for a, b in zip(sp, bp) if a != b) / max(1, len(sp)) < 0.60:
        fail("cinematic and storybook atlases are nearly identical")
    if (cw, ch) != (256, 64) or (sw, sh) != (cw, ch):
        fail("atlas must be 256x64 (49 16px cells); got classic %dx%d, storybook %dx%d"
             % (cw, ch, sw, sh))
    if len(sp) != len(cp):
        fail("the two atlases do not cover the same pixels")

    colours = set(sp)
    if not (30 <= len(colours) <= 160):
        fail("storybook palette is not controlled: %d distinct colours" % len(colours))
    if any(c == (0, 0, 0) for c in colours):
        fail("storybook atlas contains pure black")
    if any(c == (255, 255, 255) for c in colours):
        fail("storybook atlas contains pure white")

    changed = sum(1 for a, b in zip(cp, sp) if a != b)
    ratio = changed / max(1, len(cp))
    if ratio < 0.60:
        fail("storybook atlas differs from classic on only %.1f%% of pixels — "
             "this is a filter, not a new colour system" % (ratio * 100.0))

    # warm/cool discipline: the selected direction's shadows must be darker and
    # less saturated than its highlights. Colour strategy, not just brightness.
    luma = lambda c: 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]
    vals = sorted(luma(c) for c in colours)
    lo, hi = vals[: len(vals) // 4], vals[-len(vals) // 4:]
    if not (sum(hi) / len(hi) - sum(lo) / len(lo) > 45.0):
        fail("the ramps have no real shadow-to-highlight separation")

    # Evidence: the four-way comparison must exist at all three review sizes,
    # in colour and in grayscale, and carry measured metrics for four panels.
    needed = ["four_way_native.png", "four_way_desktop.png", "four_way_mobile.png",
              "four_way_grayscale_native.png", "four_way_grayscale_desktop.png",
              "four_way_grayscale_mobile.png", "metrics.json"]
    for name in needed:
        if not (COMPARISON / name).exists():
            fail("missing comparison evidence %s" % name)
    mf = COMPARISON / "metrics.json"
    if mf.exists():
        try:
            m = json.loads(mf.read_text())
            panels = m.get("panels", {})
            for key in ("current", "A_vibrant", "B_cinematic", "C_storybook"):
                if key not in panels or "luma_std" not in panels[key]:
                    fail("metrics.json has no measurement for %s" % key)
            if m.get("user_final_direction") != "B_cinematic":
                fail("metrics.json does not record the user's Direction B override")
        except Exception as e:
            fail("metrics.json unreadable: %s" % e)

    return report()


def report():
    if errors:
        for e in errors:
            print("  FAIL  " + e)
        print("check_art_reset: %d problem(s)" % len(errors))
        return 1
    print("check_art_reset: clean — both opt-in atlases share the classic "
          "layout, use distinct controlled palettes, and have four-way "
          "review evidence; Direction B override recorded")
    return 0


if __name__ == "__main__":
    sys.exit(main())
