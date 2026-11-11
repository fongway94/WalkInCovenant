#!/usr/bin/env python3
"""Hand-matte actors from the user's approved reference, for this prototype.

The previous AI-keyed sprites had oversaturated key-colour specks, a different
outline/pixel density, and bright white wool. These are *not* new concept art:
we preserve the actual reference's pixels, including its upper-left highlights
and cool lower-right shading. The polygons below are hand-traced at the source's
native resolution; holes exclude the grass between limbs and inside the crook.

The 2x/3x nearest-neighbour enlargement preserves source pixels while fitting
this prototype's 1440px-wide edited backdrop and its 0.66 sheep scale. This is
an exploratory cutout pipeline, not a production-ready animated sprite sheet.
Requires Pillow. Re-run from the repo root after editing the masks.
"""
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

REFERENCE = Path("docs/art-reset/user_selected_reference.png")
OUTPUT = Path("art/proto/sprites")

# Absolute coordinates in the 681x348 approved image. Keeping the contours
# explicit makes the extraction repeatable and reviewable, rather than hiding
# a chroma-key/recolouring pass in a black box.
ACTORS = {
    "david_reference": {
        "scale": 2,
        "positive": [
            [(351, 52), (357, 52), (360, 54), (361, 56), (362, 59),
             (361, 62), (359, 64), (361, 65), (363, 69), (365, 72),
             (367, 72), (369, 73), (369, 76), (366, 77), (362, 79),
             (362, 83), (361, 84), (361, 90), (361, 96), (360, 97),
             (356, 97), (356, 93), (355, 91), (353, 90), (352, 92),
             (352, 96), (351, 98), (347, 98), (346, 96), (346, 89),
             (344, 88), (342, 86), (341, 83), (340, 79), (340, 76),
             (341, 72), (343, 68), (345, 64), (347, 62), (346, 60),
             (346, 57), (347, 55), (349, 53)],
            [(365, 60), (365, 56), (366, 54), (369, 54), (371, 55),
             (372, 57), (372, 59), (371, 61), (368, 62), (368, 97),
             (367, 98), (367, 62)],
        ],
        "negative": [
            [(367, 56), (369, 56), (370, 57), (370, 59), (369, 60),
             (367, 60), (366, 59), (366, 57)],
            [(352, 91), (355, 90), (355, 96), (353, 97), (352, 96)],
        ],
    },
    "sheep_reference_a": {
        "scale": 3,
        "positive": [
            [(415, 175), (418, 173), (423, 173), (426, 175), (429, 175),
             (432, 177), (435, 180), (436, 183), (438, 185), (440, 186),
             (441, 188), (439, 190), (439, 194), (438, 196), (435, 196),
             (433, 195), (432, 197), (430, 198), (429, 197), (429, 194),
             (427, 194), (427, 197), (425, 199), (423, 198), (423, 194),
             (421, 194), (420, 197), (419, 199), (417, 199), (416, 197),
             (416, 194), (414, 193), (413, 198), (411, 199), (409, 198),
             (409, 194), (407, 192), (406, 189), (406, 183), (407, 181),
             (409, 178), (412, 176)],
        ],
        "negative": [
            [(412, 194), (414, 193), (415, 194), (415, 199), (412, 199)],
            [(420, 194), (422, 193), (422, 199), (420, 199)],
            [(427, 194), (428, 193), (428, 198), (427, 198)],
        ],
    },
    "sheep_reference_b": {
        "scale": 3,
        "positive": [
            [(385, 142), (389, 142), (391, 143), (394, 143), (397, 145),
             (399, 147), (401, 148), (403, 149), (402, 151), (401, 152),
             (401, 156), (400, 157), (399, 157), (398, 159), (397, 164),
             (396, 165), (394, 165), (394, 162), (393, 161), (391, 162),
             (390, 165), (389, 166), (387, 166), (386, 164), (386, 161),
             (384, 161), (383, 165), (382, 167), (380, 167), (379, 165),
             (379, 162), (377, 161), (376, 163), (376, 166), (374, 166),
             (374, 161), (373, 159), (373, 154), (374, 150), (376, 147),
             (378, 145), (381, 144), (383, 143)],
        ],
        "negative": [
            [(377, 162), (378, 161), (379, 162), (379, 166), (377, 165)],
            [(383, 162), (385, 161), (385, 166), (383, 166)],
            [(391, 162), (393, 161), (393, 165), (391, 165)],
        ],
    },
}


def main():
    source = Image.open(REFERENCE).convert("RGBA")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, spec in ACTORS.items():
        mask = Image.new("L", source.size)
        draw = ImageDraw.Draw(mask)
        for outline in spec["positive"]:
            draw.polygon(outline, fill=255)
        for hole in spec["negative"]:
            draw.polygon(hole, fill=0)
        # A fractional-pixel feather softens cut edges without blurring the
        # source interior. Upscale *after* masking, without inventing detail.
        mask = mask.filter(ImageFilter.GaussianBlur(0.25))
        bounds = mask.getbbox()
        if bounds is None:
            raise ValueError("empty mask: " + name)
        actor = source.copy()
        actor.putalpha(mask)
        actor = actor.crop(bounds)
        scale = spec["scale"]
        save_scaled(actor, OUTPUT / (name + ".png"), scale, bounds)
        if name == "david_reference":
            # Separate only the bottoms of the two boots. At rest the three
            # layers reconstruct the same pixels; in motion the boots can
            # stride modestly without inventing a new illustrated body.
            split_boots(actor, bounds, scale)


def save_scaled(image, destination, scale, bounds):
    enlarged = image.resize((image.width * scale, image.height * scale), Image.Resampling.NEAREST)
    enlarged.save(destination)
    print("%s: source=%s output=%s" % (destination, bounds, enlarged.size))


def split_boots(actor, bounds, scale):
    original_alpha = actor.getchannel("A")
    parts = []
    for name, outline in (
        ("left", [(346, 91), (352, 91), (352, 99), (346, 99)]),
        ("right", [(356, 91), (362, 91), (362, 99), (356, 99)]),
    ):
        shape = Image.new("L", actor.size)
        local = [(x - bounds[0], y - bounds[1]) for x, y in outline]
        ImageDraw.Draw(shape).polygon(local, fill=255)
        alpha = ImageChops.multiply(original_alpha, shape)
        part = actor.copy()
        part.putalpha(alpha)
        save_scaled(part, OUTPUT / ("david_reference_boot_" + name + ".png"), scale, bounds)
        parts.append(alpha)
    body = actor.copy()
    body.putalpha(ImageChops.subtract(ImageChops.subtract(original_alpha, parts[0]), parts[1]))
    save_scaled(body, OUTPUT / "david_reference_body.png", scale, bounds)


if __name__ == "__main__":
    main()
