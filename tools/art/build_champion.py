#!/usr/bin/env python3
"""Paint the ridge champion in the cast's own language.

WHY this file exists. The champion was the one figure still drawn with the old
duel sprite: a 64x64 pixel champion doubled with nearest sampling. In the
painted valley that reads as the previous game — flat colours and blocks twice
the size of everybody else's pixels — which the user reported as "this soldier
art is the old one". Two earlier attempts failed the other way: a glossy
thin-limbed figure, then a detailed bronze render, both too glossy for a cast of
matte gouache cutouts with inked edges.

So the champion is painted at the cast's own pixel density (a 128-tall canvas
holds him at twice the 27.4-world-pixel walker, the size the duel and the ridge
tests are built around) and finished the way the cast is finished:

* the source painting is keyed off its flat cream ground and median-filtered, so
  the silhouette is clean at one pixel;
* it is reduced to 32 levels a channel, which is what turns a smooth rendering
  into gouache at this size;
* the outermost opaque ring is darkened toward the ink line every cast figure
  carries;
* the spear is redrawn by hand. The painted shaft is 1.3 pixels wide once the
  figure is fitted to the canvas — invisible in the valley — so a five-pixel
  shaft with a bronze head is drawn where his fist already is, matching the
  sprite it replaces. That shaft is what the duel's thrust frame hides.

Deterministic and Pillow-only, like the rest of tools/art. `--check` builds into
a temporary directory and compares byte-for-byte with what is committed, so the
build can never drift from the reviewed image without failing CI.
"""
import argparse
import hashlib
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageOps

SRC = Path('tools/art/sources/champion_goliath.png')
OUT = Path('art/scenes_painted')
CANVAS = 128
# The source's flat ground, sampled far from the figure.
GROUND_SAMPLE = (4, 4)
# Keying tolerance in 8-bit luminance difference. The paper ground varies by a
# couple of levels across the sheet; 26 keeps the sandal straps (which are close
# to the ground colour) and still drops every background pixel.
KEY = 26
# The fist that grips the shaft, in source pixels. Measured once from the
# column of the shaft: the run where the skin replaces the wood.
GRIP = (486, 566)
# How much broader than the fitted figure the champion stands. Goliath has to
# read as a big man at 51 world pixels tall, and the painted figure fits the
# canvas thinner than the blocky sprite it replaces.
BUILD = 1.30
INK = (52, 38, 26)
WOOD = (146, 108, 70)
BRONZE = (170, 146, 102)


def keyed_source():
    """The figure on transparency, with its flat cream ground removed."""
    image = Image.open(SRC).convert('RGB')
    ground = Image.new('RGB', image.size, image.getpixel(GROUND_SAMPLE))
    difference = ImageChops.difference(image, ground).convert('L')
    alpha = difference.point(lambda v: 255 if v > KEY else 0)
    # A 3-pixel median removes the single-pixel speckle the paper grain leaves
    # along the silhouette without eating the sandal straps.
    alpha = alpha.filter(ImageFilter.MedianFilter(3))
    figure = image.convert('RGBA')
    figure.putalpha(alpha)
    return figure, alpha


def fitted(figure, alpha):
    """The figure at CANVAS tall, its body centred, feet on the last row."""
    box = alpha.getbbox()
    if box is None:
        raise ValueError('the champion source has no figure in it')
    scale = CANVAS / float(box[3] - box[1])
    pixels = alpha.load()
    # The shaft runs the whole height, so the body centre is measured across the
    # torso only, left of the shaft's column.
    low = box[1] + int(0.28 * (box[3] - box[1]))
    high = box[1] + int(0.55 * (box[3] - box[1]))
    columns = [x for y in range(low, high) for x in range(box[0], 744)
               if pixels[x, y]]
    body = sum(columns) / float(len(columns))
    small = figure.resize((max(1, round(figure.width * scale)),
                           max(1, round(figure.height * scale))),
                          Image.Resampling.LANCZOS)
    canvas = Image.new('RGBA', (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.alpha_composite(small, (round(CANVAS * 0.5 - body * scale),
                                   CANVAS - round(box[3] * scale)))
    return canvas, scale, box


def gouache(image):
    """One opaque silhouette, 32 levels a channel, an inked outer ring."""
    alpha = image.getchannel('A').point(lambda v: 255 if v > 110 else 0)
    flat = ImageOps.posterize(image.convert('RGB'), 5)
    image = Image.merge('RGBA', (*flat.split(), alpha))
    ring = ImageChops.subtract(alpha, alpha.filter(ImageFilter.MinFilter(3)))
    ink = Image.new('RGBA', image.size, INK + (255,))
    return Image.composite(Image.blend(image, ink, 0.62), image,
                           ring.point(lambda v: 255 if v else 0))


def broader(image, factor):
    """Widen about the body's centre so he stands like the giant he is."""
    width = round(CANVAS * factor)
    wide = image.resize((width, CANVAS), Image.Resampling.LANCZOS)
    canvas = Image.new('RGBA', (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.alpha_composite(wide, (round(CANVAS * 0.5 - width * 0.5), 0))
    return canvas


def spear_handles(image, shaft_x, grip):
    """Draw the standing shaft and the thrust frame, and return both."""
    standing = image.copy()
    pen = ImageDraw.Draw(standing)
    pen.rectangle((shaft_x - 2, 0, shaft_x + 2, CANVAS - 1), fill=INK + (255,))
    pen.rectangle((shaft_x - 1, 11, shaft_x + 1, CANVAS - 1), fill=WOOD + (255,))
    pen.polygon([(shaft_x - 4, 13), (shaft_x + 4, 13), (shaft_x, 0)],
                fill=INK + (255,))
    pen.polygon([(shaft_x - 3, 12), (shaft_x + 3, 12), (shaft_x, 1)],
                fill=BRONZE + (255,))
    # The duel draws its own thrust spear, so the standing shaft is missing
    # above and below the fist during the strike — exactly what the sprite this
    # replaces did, and what GoliathFight._redraw() expects to hide.
    striking = standing.copy()
    eraser = ImageDraw.Draw(striking)
    # Erase the shaft and its head exactly, never a wider band: the fist wraps
    # the shaft, and fingers clipped off with it were a real regression in the
    # first pass of this frame.
    eraser.rectangle((shaft_x - 2, 0, shaft_x + 2, grip[0] - 1), fill=(0, 0, 0, 0))
    eraser.rectangle((shaft_x - 2, grip[1] + 1, shaft_x + 2, CANVAS - 1),
                     fill=(0, 0, 0, 0))
    eraser.polygon([(shaft_x - 5, 14), (shaft_x + 5, 14), (shaft_x, 0)],
                   fill=(0, 0, 0, 0))
    return standing, striking


def build():
    figure, alpha = keyed_source()
    canvas, scale, box = fitted(figure, alpha)
    canvas = gouache(canvas)
    canvas = broader(canvas, BUILD)
    # Where the shaft sits now: the source's shaft column, moved by the same
    # fit and the same widening the figure went through.
    shaft = round(CANVAS * 0.5 + (766 - 490) * scale * BUILD)
    grip = (round((GRIP[0] - box[1]) * scale),
            round((GRIP[1] - box[1]) * scale))
    standing, striking = spear_handles(canvas, shaft, grip)
    return {'goliath.png': standing, 'goliath_striking.png': striking}


def digest(image):
    return hashlib.sha256(image.tobytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true',
                        help='verify the committed images match this build')
    arguments = parser.parse_args()
    images = build()
    if arguments.check:
        bad = []
        for name, image in images.items():
            path = OUT / name
            if not path.exists():
                bad.append(name + ' is missing')
                continue
            committed = Image.open(path).convert('RGBA')
            if digest(committed) != digest(image):
                bad.append(name + ' differs from the build')
        for line in bad:
            print('FAIL', line)
        if bad:
            return 1
        print('verified %s (%d files)' % (OUT, len(images)))
        return 0
    OUT.mkdir(parents=True, exist_ok=True)
    for name, image in images.items():
        image.save(OUT / name, optimize=True)
        print('wrote', OUT / name, image.getbbox())
    return 0


if __name__ == '__main__':
    sys.exit(main())
