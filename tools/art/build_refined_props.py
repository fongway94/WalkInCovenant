#!/usr/bin/env python3
"""Build the detailed, independently keyed fig used in the scale pass.

The old fig was a very small copy of the olive, with only a 48-pixel-wide
texture. This distinct source retains more foliage detail at the larger world
size. Its transparent 96x144 canvas is six times the old 16x24 canvas; the
runtime compensates for that density before applying its visual scale. It is
still bottom anchored and does not change the old collider. Pillow 13.0.0.
"""
from pathlib import Path
import argparse

from PIL import Image

from build_world_ground import chroma
from build_reference_props import fit_foot

SOURCE = Path("tools/art/sources/refine_fig_tree.png")
OUTPUT = Path("art/props_painted/fig_tree_refined.png")


def build():
    image = chroma(Image.open(SOURCE))
    return fit_foot(image, (96, 144))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    image = build()
    if args.check:
        with Image.open(OUTPUT) as saved:
            if image.mode != saved.mode or image.size != saved.size or image.tobytes() != saved.tobytes():
                raise SystemExit("non-reproducible fig: " + str(OUTPUT))
    else:
        image.save(OUTPUT, optimize=True)
    print("verified" if args.check else "built", OUTPUT, image.size, image.getchannel("A").getbbox())


if __name__ == "__main__":
    main()
