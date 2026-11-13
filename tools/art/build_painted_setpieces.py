#!/usr/bin/env python3
"""Prepare the chapter's painted setpiece assets from their source art.

Each source is one generated image, made against the user-approved field. The
backgrounds are modest-sized, aspect-preserving crops; the warrior is isolated
from magenta and fitted to a square with transparent margins. Requires Pillow.

The warrior source was replaced after the user reported that the figure on the
north ridge did not match the painterly people: the previous source was glossy,
thin-limbed and softly shaded like a smooth illustration, while the cast are
matte gouache cutouts with inked edges. The new source keeps the same pose and
spear/shield layout, so the foot anchor, forehead aim band, defeat rotation and
striking cut still line up with the existing layout.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageOps

SRC = Path('tools/art/sources')
OUT = Path('art/scenes_painted')

# The matte, inked figure that matches the painted cast. The earlier glossy
# source is retained in git history; nothing else in the duel depends on it.
WARRIOR_SOURCE = 'warrior_goliath_v2.png'


def background(name):
    source = Image.open(SRC / (name + '_environment.png')).convert('RGB')
    result = ImageOps.fit(source, (960, 540), method=Image.Resampling.LANCZOS)
    result.save(OUT / (name + '.png'), optimize=True)


def despill(image):
    """Drop the magenta fringe left on anti-aliased cutout edges.

    The key below removes the flat background, but generated art retains a thin
    pink halo. At the 0.4 overworld scale that halo reads as a glowing outline,
    which is exactly the kind of mismatch this figure is being replaced for.
    """
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue
            if r > 70 and b > 70 and g < min(r, b) * 0.72 and min(r, b) - g > 24:
                lum = r * 0.299 + g * 0.587 + b * 0.114
                pixels[x, y] = (round(lum * 0.94), round(lum * 0.92),
                                round(lum * 0.74), round(a * 0.6))
    return image


def warrior():
    image = Image.open(SRC / WARRIOR_SOURCE).convert('RGBA')
    px = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = px[x, y]
            # Detect chroma key rather than exact RGB; the generator has a small
            # amount of purple in anti-aliased edge pixels. Never key bronze.
            if (r > 85 and b > 85 and g < 110 and min(r, b) - g > 70) or (
                    r > 45 and b > r * 0.68 and g < min(r, b) * 0.42 and min(r, b) - g > 28):
                px[x, y] = (0, 0, 0, 0)
    image = despill(image)
    box = image.getchannel('A').getbbox()
    if box is None:
        raise ValueError('warrior source was empty')
    image = image.crop(box)
    width = max(1, round(image.width * 128 / image.height))
    if width > 128:
        raise ValueError('warrior is unexpectedly wider than tall')
    image = image.resize((width, 128), Image.Resampling.LANCZOS)
    out = Image.new('RGBA', (128, 128))
    out.alpha_composite(image, ((128 - width) // 2, 0))
    out.save(OUT / 'goliath.png', optimize=True)

    # The source holds a vertical spear. During a thrust a separate spear is
    # drawn from the hand; keep the hand/arm but remove the baked shaft above
    # and below it so there are not two spears on screen. These polygons are
    # tied to the 128x128 fitted source, not the game layout.
    striking = out.copy()
    alpha = striking.getchannel('A')
    mask = ImageDraw.Draw(alpha)
    mask.rectangle((0, 0, 45, 47), fill=0)
    mask.polygon([(33, 58), (44, 58), (45, 127), (31, 127)], fill=0)
    striking.putalpha(alpha)
    striking.save(OUT / 'goliath_striking.png', optimize=True)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name in ('duel', 'practice', 'brook'):
        background(name)
    warrior()
    print('Built painterly duel, practice, brook and warrior assets in', OUT)


if __name__ == '__main__':
    main()
