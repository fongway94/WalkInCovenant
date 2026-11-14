#!/usr/bin/env python3
"""Check camera translation using *rendered* overlapping background pixels.

This is a geometric sanity check, not an artistic-quality score. The two
640x360 frames must be the same zoom; independently moving actors are allowed.
Use the camera positions and zoom printed by the prototype's PROTOLOG:

  python3 tools/proto/check_camera_alignment.py field.webp camera.webp \
      --cam-a 700 338.73 --cam-b 781.38 338.73 --zoom 0.55

A small search tolerates integer snapping and WebP compression. We report the
best translation of actual image content, its predicted translation, and the
unaligned/matched residuals. This does not prove alignment of every obstacle.
"""
import argparse
import sys

from PIL import Image, ImageChops, ImageStat


def mean_difference(a, b):
    return sum(ImageStat.Stat(ImageChops.difference(a, b)).mean) / 3.0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("field")
    parser.add_argument("camera")
    parser.add_argument("--cam-a", type=float, nargs=2, required=True)
    parser.add_argument("--cam-b", type=float, nargs=2, required=True)
    parser.add_argument("--zoom", type=float, required=True)
    args = parser.parse_args()
    first = Image.open(args.field).convert("RGB")
    second = Image.open(args.camera).convert("RGB")
    if first.size != (640, 360) or second.size != first.size:
        raise SystemExit("expected two 640x360 CI frames")
    expected_x = -(args.cam_b[0] - args.cam_a[0]) * args.zoom
    expected_y = -(args.cam_b[1] - args.cam_a[1]) * args.zoom
    if abs(expected_x) < 10:
        raise SystemExit("camera did not move far enough horizontally for this comparison")

    # Crop away the HUD and image edges, retaining one common region across all
    # candidate translations. It includes some actors, but most pixels are
    # independently painted field landmarks.
    ex, ey = round(expected_x), round(expected_y)
    x0, x1 = max(55, 55 - ex + 5), min(585, 585 - ex - 5)
    y0, y1 = max(42, 42 - ey + 4), min(325, 325 - ey - 4)
    if x1 - x0 < 120 or y1 - y0 < 100:
        raise SystemExit("camera views do not have enough overlap")
    area = (x0, y0, x1, y1)
    patch = first.crop(area)
    candidates = []
    for dx in range(ex - 5, ex + 6):
        for dy in range(ey - 4, ey + 5):
            shifted = (x0 + dx, y0 + dy, x1 + dx, y1 + dy)
            candidates.append((mean_difference(patch, second.crop(shifted)), dx, dy))
    residual, dx, dy = min(candidates)
    no_shift = mean_difference(patch, second.crop(area))
    error = ((dx - expected_x) ** 2 + (dy - expected_y) ** 2) ** 0.5
    print("camera predicted=(%.2f, %.2f)px observed=(%d, %d)px error=%.2fpx" % (
        expected_x, expected_y, dx, dy, error))
    print("background residual aligned=%.2f unaligned=%.2f (lower is more consistent)" % (
        residual, no_shift))
    if error > 2.0 or residual >= no_shift * 0.75:
        print("camera alignment: FAIL")
        return 1
    print("camera alignment: PASS (image evidence, not a full collision/depth audit)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
