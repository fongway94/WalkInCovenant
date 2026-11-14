#!/usr/bin/env python3
"""Key and foot-anchor the chapter's painterly actors.

Images are AI-generated sources guided by the user-approved field, not authored
sprite sheets. Three views cover the moving pilgrim, Corin and elder; left
mirrors right. The standing woman and boy have a front pose only. Small layered
foot movements are procedural; these outputs are not hand-animated walk cycles.
Run from the repository root with Pillow installed.
"""
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw

SRC = Path('tools/art/sources')
OUT = Path('art/characters_painted')
ACTORS = {
    'pilgrim': {'front': 'pilgrim_front', 'profile': 'pilgrim_profile', 'back': 'pilgrim_back'},
    'corin': {'front': 'corin_front', 'profile': 'corin_profile', 'back': 'corin_back'},
    'elder': {'front': 'elder_front', 'profile': 'elder_profile', 'back': 'elder_back'},
    'woman': {'front': 'woman_clean'},
    'boy': {'front': 'hired_boy'},
}


def key_and_fit(path):
    im = Image.open(path).convert('RGBA')
    pix = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, _ = pix[x, y]
            if (r > 90 and b > 90 and g < 110 and min(r, b) - g > 70) or (
                    r > 45 and b > r * 0.68 and g < min(r, b) * 0.42 and min(r, b) - g > 28):
                pix[x, y] = (0, 0, 0, 0)
    box = im.getchannel('A').getbbox()
    if box is None:
        raise ValueError('empty source ' + str(path))
    im = im.crop(box)
    width = round(im.width * 49 / im.height)
    if not 0 < width <= 35:
        raise ValueError('unexpected aspect ratio ' + str(path))
    # The approved shepherd's mat is on a 2px pixel grid. Match it, while
    # preserving alpha so the glow never becomes a magenta outline.
    im = im.resize((width, 49), Image.Resampling.LANCZOS)
    im = im.resize((width * 2, 98), Image.Resampling.NEAREST)
    canvas = Image.new('RGBA', (70, 98))
    canvas.alpha_composite(im, ((70 - im.width) // 2, 0))
    return canvas


def layers(prefix, image):
    image.save(OUT / (prefix + '_idle.png'), optimize=True)
    alpha = image.getchannel('A')
    body = alpha.copy()
    for name, rect in [('left', (0, 84, 34, 98)), ('right', (35, 84, 70, 98))]:
        selection = Image.new('L', image.size)
        ImageDraw.Draw(selection).rectangle((rect[0], rect[1], rect[2]-1, rect[3]-1), fill=255)
        part_alpha = ImageChops.multiply(alpha, selection)
        part = image.copy()
        part.putalpha(part_alpha)
        part.save(OUT / (prefix + '_boot_' + name + '.png'), optimize=True)
        body = ImageChops.subtract(body, part_alpha)
    part = image.copy()
    part.putalpha(body)
    part.save(OUT / (prefix + '_body.png'), optimize=True)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for actor, poses in ACTORS.items():
        for pose, source in poses.items():
            result = key_and_fit(SRC / (source + '.png'))
            layers(actor + '_' + pose, result)
            print(actor, pose, result.getchannel('A').getbbox())


if __name__ == '__main__':
    main()
