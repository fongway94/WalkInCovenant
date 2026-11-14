#!/usr/bin/env python3
"""Prepare the chapter's painted setpiece assets from their source art.

Each source is one generated image, made against the user-approved field. The
backgrounds are modest-sized, aspect-preserving crops. Requires Pillow.

The ridge champion is NOT built here: tools/art/build_champion.py owns
art/scenes_painted/goliath*.png. Keeping the champion out of this file is what
stops a routine setpiece rebuild from quietly putting the old duel sprite back on
the ridge, which is exactly how it regressed once.
"""
from pathlib import Path
from PIL import Image, ImageOps

SRC = Path('tools/art/sources')
OUT = Path('art/scenes_painted')


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


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name in ('duel', 'practice', 'brook'):
        background(name)
    print('Built painterly duel, practice and brook assets in', OUT)


if __name__ == '__main__':
    main()
