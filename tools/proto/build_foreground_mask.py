#!/usr/bin/env python3
"""Refine the prototype's lower-left foreground into a partial-occlusion matte.

The original mask was a big filled polygon containing path and grass behind
its apparent boundary. That drew an invisible diagonal wall across characters.
Use that polygon only as a rough region, grow it to include foliage tips, and
keep dark silhouettes and cool stones from the same backdrop. This is an
imperfect image-derived matte, not a semantic 3-D depth map. The output's top
left is world (0, 250); no production assets are touched. Requires Pillow.
"""
from pathlib import Path

from PIL import Image, ImageFilter

BACKGROUND = Path("art/proto/shepherd_field_empty.png")
REGION = Path("art/proto/shepherd_field_fg.png")
OUTPUT = Path("art/proto/shepherd_field_fg_cutout.png")
CROP = (0, 250, 440, 666)


def build_layer(background, guide_image):
    """Recompute the existing foreground matte for the supplied colours."""
    bg = background.convert("RGB")
    # Grow the guide to include narrow blades that cross the former polygon's
    # edge. Colour/brightness filtering below prevents keeping the whole path.
    region = guide_image.getchannel("A").filter(ImageFilter.MaxFilter(41))
    matte = Image.new("L", bg.size)
    pixels, guide, alpha = bg.load(), region.load(), matte.load()
    for y in range(CROP[1], CROP[3]):
        for x in range(CROP[0], CROP[2]):
            if not guide[x, y]:
                continue
            r, g, b = pixels[x, y]
            luma = 0.22 * r + 0.70 * g + 0.08 * b
            dark = max(0.0, min(1.0, (110.0 - luma) / 40.0))
            stone = 0.0
            if b > g * 0.88 and b > r * 0.72:
                stone = max(0.0, min(1.0, (165.0 - max(r, g, b)) / 30.0))
            alpha[x, y] = round(255 * max(dark, stone))
    matte = matte.filter(ImageFilter.GaussianBlur(0.55))
    result = bg.convert("RGBA")
    result.putalpha(matte)
    return result.crop(CROP)


def main():
    with Image.open(BACKGROUND) as background, Image.open(REGION) as guide:
        layer = build_layer(background, guide)
    layer.save(OUTPUT)
    print("%s: crop=%s" % (OUTPUT, CROP))


if __name__ == "__main__":
    main()
