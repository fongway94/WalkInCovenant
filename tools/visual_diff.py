#!/usr/bin/env python3
"""visual_diff.py — local visual regression check for captured frames.

CI renders the frames (tools/visual_gd harness) and prints them back as base64
annotations; tools/decode_frames.py writes them into frames/. This tool compares
those captures with the committed baselines in tests/frames/ and, when told to,
promotes a reviewed capture to be the new baseline.

    python3 tools/visual_diff.py                 # compare, print diffs
    python3 tools/visual_diff.py --write-bases  # promote frames/ to baselines

Pillow is required. The CI runner does not ship it (the engine's own Image
class does the in-run comparison there), so this is a local authoring tool.
"""

import argparse
import pathlib
import shutil
import sys

try:
    from PIL import Image
except ImportError:
    print("visual_diff: Pillow is required (python3 -m pip install pillow)")
    sys.exit(2)

ROOT = pathlib.Path(__file__).resolve().parent.parent
FRAMES = ROOT / "frames"
BASES = ROOT / "tests" / "frames"
LIMIT = 0.18
CELL = 10


def grid(path):
    im = Image.open(path).convert("RGB")
    out = []
    for gy in range(18):
        for gx in range(32):
            r = g = b = 0
            n = 0
            for oy in (2, 6):
                for ox in (2, 6):
                    px = im.getpixel((gx * CELL + ox, gy * CELL + oy))
                    r += px[0]
                    g += px[1]
                    b += px[2]
                    n += 1
            out.append((r / n / 255.0, g / n / 255.0, b / n / 255.0))
    return out


def diff(a, b):
    return sum(abs(x[0] - y[0]) + abs(x[1] - y[1]) + abs(x[2] - y[2])
               for x, y in zip(a, b)) / (3.0 * len(a))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write-bases", action="store_true",
                    help="copy frames/*.png into tests/frames/baseline_*.png")
    args = ap.parse_args()

    shots = sorted(FRAMES.glob("*.png"))
    if not shots:
        print("no frames in frames/ — run tools/decode_frames.py <run-id> first")
        return 1

    if args.write_bases:
        BASES.mkdir(parents=True, exist_ok=True)
        for f in shots:
            dst = BASES / ("baseline_" + f.name)
            shutil.copyfile(f, dst)
            print("  baseline: " + str(dst.relative_to(ROOT)))
        print("promoted %d frame(s). Review them by eye first." % len(shots))
        return 0

    fails = 0
    for f in shots:
        base = BASES / ("baseline_" + f.name)
        if not base.exists():
            print("  NO BASE  %s (capture only; promote once reviewed)" % f.name)
            continue
        d = diff(grid(f), grid(base))
        ok = d < LIMIT
        print("  %s  %-24s diff %.4f (limit %.2f)" %
              ("OK  " if ok else "DIFF", f.name, d, LIMIT))
        if not ok:
            fails += 1
    if fails:
        print("visual_diff: %d frame(s) changed beyond the limit" % fails)
        return 1
    print("visual_diff: clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
