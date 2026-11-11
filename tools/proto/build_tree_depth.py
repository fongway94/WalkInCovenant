#!/usr/bin/env python3
"""Extract one upper-tree depth layer from the prototype backdrop.

This tree was painted into the background, so David previously drew over the
canopy even while behind it. These manually traced polygons retain the same
pixels at the same world coordinates. At runtime the layer is y-sorted at the
trunk's ground line. It is a limited experiment, not a full semantic
segmentation of the scene. Requires Pillow; run from the repository root.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

BACKGROUND = Path("art/proto/shepherd_field_empty.png")
OUTPUT = Path("art/proto/shepherd_field_upper_tree.png")
# The image begins at world (0, 0), even though the tree starts at x=890.
# Sharing the backdrop's origin prevents independently snapped Sprite2D
# transforms from shifting the duplicate canopy by half a logical pixel.
CROP = (0, 0, 1265, 210)
CANOPY = [
    (945, 0), (1206, 0), (1210, 14), (1223, 24), (1222, 39), (1229, 45),
    (1228, 58), (1240, 65), (1243, 76), (1252, 85), (1255, 102),
    (1249, 112), (1240, 116), (1241, 125), (1230, 131), (1222, 129),
    (1214, 139), (1203, 142), (1192, 136), (1183, 143), (1170, 148),
    (1161, 148), (1152, 142), (1140, 137), (1130, 143), (1120, 140),
    (1110, 131), (1100, 135), (1090, 131), (1080, 135), (1070, 129),
    (1060, 135), (1052, 128), (1040, 132), (1030, 131), (1015, 136),
    (1006, 133), (995, 137), (986, 134), (970, 137), (960, 132),
    (952, 132), (940, 126), (930, 121), (920, 116), (916, 108),
    (919, 101), (910, 98), (904, 90), (901, 82), (901, 68), (906, 57),
    (912, 49), (919, 45), (918, 36), (929, 28), (932, 19), (939, 15),
    (940, 8),
]
TRUNKS = [
    [(997, 112), (1029, 110), (1040, 139), (1039, 174), (1033, 195),
     (1018, 198), (1010, 182), (1009, 155), (1000, 148)],
    [(1060, 110), (1109, 110), (1100, 147), (1098, 175), (1105, 195),
     (1088, 204), (1063, 201), (1057, 188), (1067, 159)],
    [(1147, 108), (1186, 112), (1184, 143), (1177, 164), (1177, 185),
     (1161, 191), (1156, 168), (1154, 145)],
]


def main():
    image = Image.open(BACKGROUND).convert("RGBA")
    alpha = Image.new("L", image.size)
    draw = ImageDraw.Draw(alpha)
    draw.polygon(CANOPY, fill=255)
    for trunk in TRUNKS:
        draw.polygon(trunk, fill=255)
    image.putalpha(alpha.filter(ImageFilter.GaussianBlur(0.7)))
    clean = Image.new("RGBA", image.size)
    clean.alpha_composite(image)
    clean.crop(CROP).save(OUTPUT)
    print("%s: world crop=%s, depth foot y=202" % (OUTPUT, CROP))


if __name__ == "__main__":
    main()
