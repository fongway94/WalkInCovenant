#!/usr/bin/env python3
"""Prepare the chapter's painted setpiece assets from their source art.

Each source is one generated image, made against the user-approved field. The
backgrounds are modest-sized, aspect-preserving crops; the warrior is isolated
from magenta and fitted to a square with transparent margins. Requires Pillow.

The ridge warrior now comes from the duel's own champion sprite, doubled with
nearest-neighbour sampling. Two earlier generated paintings were rejected by the
user for not matching the cast: the first was glossy and thin-limbed, the second
detailed bronze armour. The cast are matte pixel-gouache cutouts with inked
edges, so the champion must be one of them.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageOps

SRC = Path('tools/art/sources')
OUT = Path('art/scenes_painted')

# The duel's own champion sprite, painted in the cast's language. The earlier
# generated bronze source is retained in git history; nothing else depends on it.
DUEL_CHAMPION = Path('art/duel/goliath.png')


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
    """Use the game's own duel champion for the ridge, twice as large.

    WHY: the ridge figure was a smooth bronze painting. Beside the cast — matte
    pixel-gouache cutouts with inked edges — it read as a different game, which
    the user reported twice. The duel already ships a champion painted in the
    cast's language, so the ridge uses that exact sprite at 2x nearest
    neighbour: same pose, same palette, same chunky edges as the people he
    stands over. Doubling keeps the 128x128 canvas, foot anchor, offset and
    scale the world, tests and the duel's aim bands were tuned against.
    """
    source = Image.open(DUEL_CHAMPION).convert('RGBA')
    if source.size != (64, 64):
        raise ValueError('duel champion changed size: %s' % (source.size,))
    out = source.resize((128, 128), Image.Resampling.NEAREST)
    out.save(OUT / 'goliath.png', optimize=True)

    # The duel draws its own thrust spear from the hand, so the baked vertical
    # shaft is removed for the strike frame. The cut is a narrow band around the
    # shaft only: a wider polygon clipped his left shin in the thrust frame.
    striking = out.copy()
    alpha = striking.getchannel('A')
    mask = ImageDraw.Draw(alpha)
    mask.rectangle((92, 0, 126, 58), fill=0)
    mask.rectangle((99, 84, 121, 127), fill=0)
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
