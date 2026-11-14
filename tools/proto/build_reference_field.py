#!/usr/bin/env python3
"""Restore reference pixels to the playable shepherd field and its depth layers.

The user's newer 1024x576 attachment and the previously edited 1440x666
backdrop show the same painting. A fixed, feature-matched registration maps
that larger attachment into the existing coordinate system. We keep the
edited/inpainted pixels wherever the reference contains a baked-in person or
sheep, and along the repainted right edge. Tree, fence and foreground masks
are regenerated from THE RESULT, so they stay colour-aligned with the pixels
behind them. Characters and animals remain independent game nodes; the
original isolated prototype files and the earlier attachment are unchanged.

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

REFERENCE = Path("tools/art/sources/user_reference_1024.webp")
INPAINTED = Path("art/proto/shepherd_field_empty.png")
FOREGROUND_GUIDE = Path("art/proto/shepherd_field_fg.png")
OUT = Path("art/scenes_painted")

# Inverse of the feature-matched homography, expressed for Pillow's pixel
# centres. Against the existing backdrop, 1261 of 1268 SIFT matches were
# inliers within four backdrop pixels. These fixed values avoid requiring
# OpenCV or network access during regeneration. OpenCV and Pillow transforms
# agree to <0.001 mean RGB levels on this reference.
INVERSE_TRANSFORM = (
    0.6982922888628293, 0.00011823422666437068, 1.9287019199538598,
    0.0000022754721710618288, 0.6974879164210881, 58.03646583308495,
    -0.00000006239179077694417, 0.000000375071723811082,
)
# The previous attachment's exclusion rectangles were mapped into the newer
# image. They cover both people and all five sheep. Feathering keeps their
# prior inpaint under the real, independent actors without rectangular seams.
ACTOR_EXCLUSIONS = (
    (251, 204, 323, 309), (494, 115, 566, 216),
    (543, 253, 606, 316), (647, 249, 708, 309),
    (594, 301, 663, 365), (702, 192, 755, 242),
    (878, 157, 940, 216),
)
RIGHT_EDGE_START = 974


def restore(reference, inpainted):
    if reference.size != (1024, 576) or inpainted.size != (1440, 666):
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
