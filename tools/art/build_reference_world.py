#!/usr/bin/env python3
"""Build a reversible, map-aligned meadow continuation for both regions.

The supplied sunset field remains a single, separate scene. This builder blends
one newly generated, ground-only meadow painting with the existing map-aligned
ground: it is not a claim that the other places were in the reference. A given
painting is placed only once per region, not tiled into repeated flower beds.
The region JSON still owns paths, water, collisions and story positions.

Input/source art is excluded from game exports. Output textures keep the old
ground's pixel size and world coordinates; the old textures remain available.
Requires Pillow 13.0.0. Run from the repo root.
"""
from pathlib import Path
import argparse
import json

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageOps

import build_world_ground

SOURCES = Path("tools/art/sources")
SCENES = Path("art/scenes_painted")
MEADOW = SOURCES / "reference_continuation_meadow.png"


def no_red_earth(image):
    """Keep the source's accidental rusty soil patches out of the grass.

    Grass highlights can also contain red; feathering avoids a hard colour
    contour. This is a visual mask only, never a collision or gameplay mask.
    """
    mask = Image.new("L", image.size)
    mask.putdata([
        0 if red * 10 > green * 13 and red - green > 15 else 255
        for red, green, _blue in image.get_flattened_data()
    ])
    return mask.filter(ImageFilter.GaussianBlur(6))


def continuation(region):
    if region not in ("elah", "bethlehem"):
        raise ValueError("unknown region: " + region)
    base = Image.open(SCENES / ("world_" + region + ".png")).convert("RGB")
    raw = json.loads(Path("data/regions/" + region + ".json").read_text(encoding="utf-8"))
    grid = raw["grid"]
    expected = (len(grid[0]) * build_world_ground.TILE,
                len(grid) * build_world_ground.TILE)
    if base.size != expected:
        raise ValueError("existing ground no longer aligns with " + region)
    size = base.size
    # In Elah, the new painting occurs once on the camp's side of the brook;
    # the original northern meadow and the crossing remain their own pictures.
    # Bethlehem is a separate place and uses one centered crop, not a quilt.
    height = 850 if region == "elah" else size[1]
    top = size[1] - height
    source = Image.open(MEADOW).convert("RGB")
    source = ImageOps.fit(source, (size[0], height), Image.Resampling.LANCZOS)
    source = ImageEnhance.Brightness(source).enhance(1.12)
    overlay = Image.new("RGB", size)
    overlay.paste(source, (0, top))
    colour_mask = no_red_earth(overlay)

    # Blend only the grassy map materials; the soft fade occurs in world space,
    # never in screen space. Protect the actual river and its crossing exactly.
    grass = build_world_ground.tile_mask(grid, ".fgwm", size, 16)
    water = build_world_ground.tile_mask(grid, "~=", size, 0)
    grass = ImageChops.multiply(grass, ImageChops.invert(water))
    strength = Image.new("L", size)
    draw = ImageDraw.Draw(strength)
    for y in range(top, size[1]):
        alpha = round(255 * 0.65 * min(1.0, (y - top) / 100.0))
        draw.line((0, y, size[0] - 1, y), fill=alpha)
    mask = ImageChops.multiply(ImageChops.multiply(grass, strength), colour_mask)
    return Image.composite(overlay, base, mask), mask


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="verify committed outputs without overwriting")
    args = parser.parse_args()
    for region in ("elah", "bethlehem"):
        image, mask = continuation(region)
        path = SCENES / ("world_" + region + "_reference.png")
        if args.check:
            with Image.open(path) as saved:
                if image.size != saved.size or image.tobytes() != saved.convert("RGB").tobytes():
                    raise SystemExit("non-reproducible ground: " + str(path))
            print("verified", path)
        else:
            image.save(path, optimize=True)
            print("built", path, image.size, "mean overlay alpha", round(sum(i * n for i, n in enumerate(mask.histogram())) / (255 * mask.width * mask.height), 3))


if __name__ == "__main__":
    main()
