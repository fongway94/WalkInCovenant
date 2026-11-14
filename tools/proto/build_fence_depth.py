#!/usr/bin/env python3
"""Extract the painted upper fence as a world-aligned, y-sorted depth layer.

Only its three posts and two rails are kept; the gaps stay transparent so a
character behind the fence remains visible between the boards. Pixel values
come directly from the prototype backdrop. The image starts at world (0, 0),
matching the backdrop's origin and entire quad dimensions. Differently sized
quads can snap to different vertices and sample different pixels at the mask
edges. This is one manually traced fence, not a complete scene-depth solution.
Requires Pillow; run from the repository root.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

BACKGROUND = Path("art/proto/shepherd_field_empty.png")
OUTPUT = Path("art/proto/shepherd_field_upper_fence.png")
BOARDS = [
    # Posts (including their softly lit tops and irregular lower ends).
    [(857, 200), (867, 200), (871, 203), (870, 263), (866, 267), (857, 266)],
    [(917, 202), (926, 201), (930, 203), (930, 265), (925, 268), (917, 266)],
    [(961, 184), (971, 183), (975, 187), (974, 264), (970, 267), (960, 265)],
    # Horizontal rails, separate so their intervening grass stays transparent.
    [(854, 212), (975, 212), (975, 222), (854, 223)],
    [(854, 230), (975, 229), (975, 241), (854, 242)],
]


def build_layer(background):
    """Cut the existing rail and post mattes from the supplied backdrop."""
    image = background.convert("RGBA")
    alpha = Image.new("L", image.size)
    draw = ImageDraw.Draw(alpha)
    for board in BOARDS:
        draw.polygon(board, fill=255)
    image.putalpha(alpha.filter(ImageFilter.GaussianBlur(0.7)))
    clean = Image.new("RGBA", image.size)
    clean.alpha_composite(image)
    return clean


def main():
    with Image.open(BACKGROUND) as background:
        clean = build_layer(background)
    clean.save(OUTPUT)
    print("%s: world size=%s, depth foot y=268" % (OUTPUT, clean.size))


if __name__ == "__main__":
    main()
