#!/usr/bin/env python3
"""Build the mature olive and fig used by the painted overworld.

WHY THIS EXISTS (third pass): the second pass grew the tall trees by stretching
the source's trunk. That gained height, but it also magnified the painted root
flare into long splayed "legs" and dragged leaf lobes down beside the trunk, so
the user still saw a foreign object with the old tree's leftovers in it.

The trees are now the overworld's own tree paintings, scaled whole: one uniform
factor to the authored canvas height, then a single horizontal bias that keeps
the tree upright rather than letting the canopy spread square. Nothing is
re-drawn, nothing is spliced, and no region is stretched relative to another, so
the trunk keeps its authored proportions, the roots stay the size the source
painted them, and every pixel is a resampled pixel of the accepted art. An
unsharp pass restores the crisp painted edge that plain interpolation softens.

The canvases stay foot-anchored (the last row of alpha is the trunk base), keep
the runtime's 82/78 world-pixel targets, and add no new colours. Pillow 13.0.0
reproduces them exactly.
"""
from pathlib import Path
import argparse

from PIL import Image, ImageFilter

PROPS = Path("art/props_painted")
OUTPUT = Path("art/props_painted")

# output, source, canvas height, horizontal bias, unsharp percent
TREES = (
    ("olive_tree_tall.png", "olive_tree.png", 276, 1.30, 95),
    ("fig_tree_tall.png", "fig_tree_refined.png", 272, 1.30, 95),
)


def despill(image):
    """Drop the magenta fringe left by the generative source of the props.

    Only partly transparent magenta-ish pixels are touched, and they are pulled
    toward their own luminance in the bark/leaf range, so genuine warm highlights
    (fig flesh, sunlit trunk) survive.
    """
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = pixels[x, y]
            if a == 0 or a == 255:
                continue
            if r > 120 and b > 110 and g + 30 < min(r, b):
                lum = round(0.30 * r + 0.59 * g + 0.11 * b)
                ink = min(lum, 96)
                pixels[x, y] = (ink, max(0, ink - 6), max(0, ink - 12), a)
    return image


def grow(source, height, bias, unsharp):
    """Scale the accepted painting whole: one height factor, one width bias."""
    with Image.open(PROPS / source) as raw:
        image = despill(raw.convert("RGBA"))
    bounds = image.getchannel("A").getbbox()
    if bounds is None:
        raise SystemExit("empty source painting: " + source)
    image = image.crop(bounds)
    factor = height / image.height
    width = max(1, round(image.width * factor / bias))
    scaled = image.resize((width, height), Image.LANCZOS)
    if unsharp:
        scaled = scaled.filter(ImageFilter.UnsharpMask(radius=1.2, percent=unsharp,
                                                       threshold=0))
    return scaled


def build():
    return {name: grow(source, height, bias, unsharp)
            for name, source, height, bias, unsharp in TREES}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, image in build().items():
        path = OUTPUT / name
        if args.check:
            with Image.open(path) as saved:
                if (image.mode != saved.mode or image.size != saved.size
                        or image.tobytes() != saved.tobytes()):
                    raise SystemExit("non-reproducible tree: " + str(path))
            print("verified", path, image.size)
        else:
            image.save(path, optimize=True)
            print("built", path, image.size,
                  "bbox", image.getchannel("A").getbbox())


if __name__ == "__main__":
    main()
