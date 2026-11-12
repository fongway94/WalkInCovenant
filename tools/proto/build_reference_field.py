#!/usr/bin/env python3
"""Restore reference pixels to the playable shepherd field and its depth layers.

The user's 740x413 attachment and the previously edited 1440x666 backdrop
show the same painting. A fixed, feature-matched registration maps the former
into the latter's existing coordinate system. We keep the edited/inpainted
pixels wherever the reference contains a baked-in person or sheep, and along
the repainted right edge. Tree, fence and foreground masks are regenerated from
THE RESULT, so they stay colour-aligned with the pixels behind them.

This reuses the available reference pixels; it does not invent a higher-
resolution original. Characters and animals remain independent game nodes.
The original approved prototype files are not modified.

Run from the repository root; requires Pillow 13.0.0:
    python3 tools/proto/build_reference_field.py
    python3 tools/proto/build_reference_field.py --check
"""
import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

import build_fence_depth
import build_foreground_mask
import build_tree_depth

REFERENCE = Path("tools/proto/sources/user_sunset_field.png")
INPAINTED = Path("art/proto/shepherd_field_empty.png")
FOREGROUND_GUIDE = Path("art/proto/shepherd_field_fg.png")
OUT = Path("art/scenes_painted")

# Inverse of the feature-matched homography, expressed for Pillow's pixel
# centres. Estimated against the old backdrop: 881/886 SIFT matches were
# inliers within 5 backdrop pixels. The numbers are fixed so this build does
# not need OpenCV, feature detection, or a network connection.
INVERSE_TRANSFORM = (
    0.5104435151231627, 0.00009020991139752017, -2.2603826151467827,
    -0.00001399169941020696, 0.5097713443363316, 38.51340725544929,
    -0.000000020121888243110212, 0.0000004606543782784042,
)
# Bounding rectangles in the 740x413 attachment. These cover the two people
# and five sheep, including their edges. Their previous inpaint remains beneath
# the real moving actors; feathering prevents hard rectangular transitions.
ACTOR_EXCLUSIONS = (
    (180, 145, 232, 222), (357, 80, 410, 154),
    (393, 181, 439, 227), (469, 178, 514, 222),
    (430, 216, 481, 263), (509, 136, 548, 173),
    (638, 111, 683, 154),
)
RIGHT_EDGE_START = 708


def restore(reference, inpainted):
    if reference.size != (740, 413) or inpainted.size != (1440, 666):
        raise ValueError("unexpected reference or field dimensions")
    reference = reference.convert("RGB")
    inpainted = inpainted.convert("RGB")
    mask = Image.new("L", reference.size, 255)
    draw = ImageDraw.Draw(mask)
    for rect in ACTOR_EXCLUSIONS:
        draw.rectangle(rect, fill=0)
    draw.rectangle((RIGHT_EDGE_START, 0, reference.width, reference.height), fill=0)
    mask = mask.filter(ImageFilter.GaussianBlur(3)).transform(
        inpainted.size, Image.Transform.PERSPECTIVE, INVERSE_TRANSFORM,
        resample=Image.Resampling.BILINEAR)
    registered = reference.transform(
        inpainted.size, Image.Transform.PERSPECTIVE, INVERSE_TRANSFORM,
        resample=Image.Resampling.NEAREST)
    return Image.composite(registered, inpainted, mask), mask


def build():
    with Image.open(REFERENCE) as source, Image.open(INPAINTED) as old:
        field, mask = restore(source, old)
    with Image.open(FOREGROUND_GUIDE) as guide:
        foreground = build_foreground_mask.build_layer(field, guide)
    return {
        "shepherd_field_reference.png": field,
        "shepherd_field_reference_tree.png": build_tree_depth.build_layer(field),
        "shepherd_field_reference_fence.png": build_fence_depth.build_layer(field),
        "shepherd_field_reference_foreground.png": foreground,
    }, mask


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="compare generated pixels with committed outputs")
    args = parser.parse_args()
    images, mask = build()
    if not args.check:
        OUT.mkdir(parents=True, exist_ok=True)
    for name, image in images.items():
        path = OUT / name
        if args.check:
            with Image.open(path) as saved:
                if image.mode != saved.mode or image.size != saved.size or image.tobytes() != saved.tobytes():
                    raise SystemExit("field asset differs from source pipeline: " + str(path))
        else:
            image.save(path, optimize=True)
        print("%s %s %s" % ("checked" if args.check else "built", path, image.size))
    coverage = sum(mask.histogram()[241:]) / (mask.width * mask.height)
    print("reference pixels at >94%% opacity: %.1f%% of the field" % (coverage * 100))


if __name__ == "__main__":
    main()
