#!/usr/bin/env python3
"""Build the taller, mature olive and fig used by the painted overworld.

WHY THIS EXISTS: the previous painted olive was a squat, wide canopy on a short
trunk. In gameplay it read as a large bush beside a person rather than a tree
standing over one, and the user asked for trees that are visibly TALLER than
people, not merely wider. The new sources keep the same painted language (warm
olive greens, dark hand-inked outline, trunk with exposed roots) but are much
more upright, with a real trunk and a canopy lifted off the ground.

The transparent canvases are sized so the runtime keeps the authored collision
footprint (1x1 tile) while the visible tree is roughly three people tall. The
bottom of every canvas is the trunk base, so the existing foot anchor, contact
shadow and y-sort point do not move. Requires Pillow 13.0.0.
"""
from pathlib import Path
import argparse

from PIL import Image

from build_reference_props import fit_foot
from build_world_ground import chroma

SOURCE = Path("tools/art/sources")
OUTPUT = Path("art/props_painted")

# The canvases keep the sources' own pixel density (no upscaling): wide enough
# for the canopy, tall enough that the visible height is the canvas height.
TREES = {
    "olive_tree_tall.png": ("olive_tree_tall_source_v2.png", (208, 276)),
    "fig_tree_tall.png": ("fig_tree_tall_source_v2.png", (200, 272)),
}


def despill(image):
    """Remove the last magenta halo from semi-transparent cutout edges.

    ``chroma`` keys the flat background, but generated sources retain a thin
    pink fringe where the figure was anti-aliased against magenta. At the
    downscaled game size that reads as a glowing outline. Only pixels that are
    still magenta-ish AND partly transparent are touched, so genuine warm
    highlights on bark or figs are never recoloured.
    """
    image = image.convert("RGBA")
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue
            if r > 70 and b > 70 and g < min(r, b) * 0.72 and min(r, b) - g > 24:
                # Keep the shape, drop the magenta: pull the edge toward the
                # neighbouring bark/leaf hue at the same luminance.
                lum = (r * 0.299 + g * 0.587 + b * 0.114)
                pixels[x, y] = (round(lum * 0.92), round(lum * 0.96),
                                round(lum * 0.72), round(a * 0.55))
    return image


def build():
    built = {}
    for name, (source, size) in TREES.items():
        art = despill(chroma(Image.open(SOURCE / source)))
        built[name] = fit_foot(art, size)
    return built


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
        else:
            image.save(path, optimize=True)
        print("verified" if args.check else "built", path, image.size,
              image.getchannel("A").getbbox())


if __name__ == "__main__":
    main()
