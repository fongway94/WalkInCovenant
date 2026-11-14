#!/usr/bin/env python3
"""Prepare the two painterly David source poses for the production rig.

The front pose and its two feet were hand-matted from the user-supplied visual
reference by tools/proto/extract_reference_sprites.py. The side and rear source
images in tools/art/sources are original AI-generated images made for this
project, referenced to that approved design. Their near-magenta backgrounds are
removed before downsampling; feet are separated into layers on a shared 70x98
canvas. Left currently mirrors the right profile, including its baked light.
These are procedural cutout strides, not hand-drawn animation frames.
Requires Pillow. Run from the repository root.
"""
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw

SOURCES = Path("tools/art/sources")
OUTPUT = Path("art/characters_painted")

# Separate only the lower boots, never the crook (to the right). Coordinates
# refer to the common 70x98 transparent output canvas.
BOOTS = {
    "profile": ((20, 80, 44, 98), None),
    "back": ((15, 80, 30, 98), (31, 80, 48, 98)),
}


def key_and_fit(path):
    image = Image.open(path).convert("RGBA")
    px = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, _ = px[x, y]
            # Generated key varies slightly across the background and includes
            # dark anti-aliased key spill. Keep warm brown/olive character pixels.
            if (r > 90 and b > 90 and g < 110 and min(r, b) - g > 70) or (
                r > 45 and b > r * 0.68 and g < min(r, b) * 0.42 and min(r, b) - g > 28
            ):
                px[x, y] = (0, 0, 0, 0)
    bounds = image.getchannel("A").getbbox()
    if bounds is None:
        raise ValueError("no visible character in " + str(path))
    image = image.crop(bounds)
    width = round((image.width * 98 / image.height) / 2) * 2
    if not 0 < width <= 70:
        raise ValueError("unexpected source aspect ratio: " + str(path))
    # Same 2x sampling grid as the reference-derived front pose.
    image = image.resize((width // 2, 49), Image.Resampling.LANCZOS)
    image = image.resize((width, 98), Image.Resampling.NEAREST)
    canvas = Image.new("RGBA", (70, 98))
    canvas.alpha_composite(image, ((70 - width) // 2, 0))
    return canvas


def write_layers(label, image):
    image.save(OUTPUT / ("david_" + label + "_idle.png"))
    alpha = image.getchannel("A")
    remaining = alpha.copy()
    for name, bounds in zip(("left", "right"), BOOTS[label]):
        shape = Image.new("L", image.size)
        if bounds:
            x0, y0, x1, y1 = bounds
            ImageDraw.Draw(shape).rectangle((x0, y0, x1 - 1, y1 - 1), fill=255)
        part_alpha = ImageChops.multiply(alpha, shape)
        part = image.copy()
        part.putalpha(part_alpha)
        part.save(OUTPUT / ("david_" + label + "_boot_" + name + ".png"))
        remaining = ImageChops.subtract(remaining, part_alpha)
    body = image.copy()
    body.putalpha(remaining)
    body.save(OUTPUT / ("david_" + label + "_body.png"))


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for label in BOOTS:
        image = key_and_fit(SOURCES / ("david_" + label + ".png"))
        write_layers(label, image)
        print(label, image.size, image.getchannel("A").getbbox())
    boy = key_and_fit(SOURCES / "hired_boy.png")
    boy.save(OUTPUT / "hired_boy_idle.png")
    print("hired_boy", boy.size, boy.getchannel("A").getbbox())


if __name__ == "__main__":
    main()
