#!/usr/bin/env python3
"""Repaint the Elah river's water surface in the painterly ground's language.

WHY THIS EXISTS: after the ground-detail pass the meadow, earth, path and paving
were painted at a fine grain, while the brook was still the older tile-sprite
water — smooth, cyan and visibly built from repeated 16-pixel strokes. Standing
at the ford, the water read as a different, much flatter picture than the grass
one step away from it.

WHAT IS AND IS NOT CHANGED:

* Only pixels that are actually painted water are repainted. The mask is
  derived from the painting itself (saturation/value/hue, then a closing pass),
  not from the tile grid alone, so the irregular bank, the reeds, the sunlit
  stones and their foam edges keep their exact pixels. The few-pixel rim around
  every stone is deliberately left alone: it is what makes the stones sit in
  the water instead of floating on a new texture.
* The shallow ford keeps its pale sand bar and its wide pale band, because the
  new surface is built from the old water's own low frequencies, cooled toward
  the stream's teal only in the darker, deeper parts.
* The surface is built in the meadow's four-note palette: square-sampled fine
  grain, broad current bands stretched along the flow, short broken dashes,
  colour dabs (teal in the deep water, sand in the shallows) and warm glints.
  Grain and dabs come from three independent water paintings sampled in unique
  crops (the same anti-repetition scheme the meadow uses); no crop is reused
  and adjacent patches never share a source.
* Water within a few pixels of a stone or the bank is darkened, so stones sit in
  the stream rather than on top of it. Only water pixels darken.
* Collision, shore geometry, the crossing's walkable tiles, props and saves are
  untouched. This is a texture pass on `world_elah_refined_*` only.

The result is deterministic for the pinned Pillow version and fails closed: if
the Elah grid or the painted shore no longer match the layout this was tuned on,
the old water is preserved rather than a guessed repaint.
"""
from pathlib import Path
import math
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageStat

ROOT = Path("tools/art/sources")
# The visible brook band inside the 4x painted ground. Derived from the two
# authored water rows and kept wide enough to include the painted bank edges.
BAND_TOP = 1500
BAND_BOTTOM = 1900
WATER_ROWS = [26, 27]
SHALLOW = {(x, y) for y in range(24, 30) for x in range(12, 20)}
# Three independent painted water sources. The first two were generated for
# this pass; the third is the reviewed ripple candidate from the previous
# session. Each is sampled in unique crops, never stamped as a complete tile.
SOURCES = ("river_surface_mid.png", "river_surface_shallow.png",
           "river_ripples_source.png")
PATCH = 320
OVERLAP = 110
# Water is smoother than grass: detail is added at a lower gain and the source
# field is stretched horizontally first so the strokes read as current rather
# than as generic texture.
FINE_GAIN = 0.22
COARSE_GAIN = 0.22
TEAL = (92, 124, 136)
TEAL_AMOUNT = 0.14
# Only the broad current bands are stretched along the flow; the fine grain is
# sampled square, so the surface keeps the meadow's painterly dabs instead of a
# lacquered horizontal sheen.
COARSE_STRETCH = 2.4
BANK_SHADE = 0.30


def _rect_mask(size, top, bottom):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rectangle((0, max(0, top), size[0] - 1, min(size[1] - 1, bottom)),
                                   fill=255)
    return mask


def water_mask(band, water_rows=WATER_ROWS):
    """Select painted water: low-saturation, light, blue-green pixels.

    Stones are saturated warm/dark and grass is saturated green, so both fall
    outside the thresholds. The band rectangle stops the classifier from
    reaching grass above and below the brook.
    """
    hue, saturation, value = band.convert("HSV").split()
    selected = ImageChops.multiply(
        ImageChops.multiply(hue.point(lambda v: 255 if 14 < v < 175 else 0),
                            saturation.point(lambda v: 255 if v < 92 else 0)),
        value.point(lambda v: 255 if v > 110 else 0))
    # The painted water reaches a little past the authored water tiles; keep a
    # fixed margin around those rows and nothing beyond it.
    top = water_rows[0] * 64 - BAND_TOP - 48
    bottom = (water_rows[-1] + 1) * 64 - BAND_TOP + 58
    selected = ImageChops.multiply(selected, _rect_mask(band.size, top, bottom))
    # Close pinholes and remove isolated specks, but preserve the stone rims.
    return selected.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))


def supports(grid, size):
    """Only run on the reviewed Elah layout; anything else keeps the old water."""
    if size != (2048, 3072):
        return False
    rows = [y for y, row in enumerate(grid) if "~" in row]
    shallow = {(x, y) for y, row in enumerate(grid)
               for x, cell in enumerate(row) if cell == "="}
    return rows == WATER_ROWS and shallow == SHALLOW


def normalise_water(image):
    """Keep the three sources in one muted, sunlit water range."""
    stats = ImageStat.Stat(image)
    target_mean, target_dev = (146, 150, 140), (34, 34, 30)
    channels = []
    for channel, mean, deviation, want_mean, want_dev in zip(
            image.split(), stats.mean, stats.stddev, target_mean, target_dev):
        gain = max(0.45, min(1.5, want_dev / max(1.0, deviation)))
        channels.append(channel.point([
            round(max(0, min(255, want_mean + (value - mean) * gain)))
            for value in range(256)]))
    return Image.merge("RGB", channels)


def detail_field(size, seed=9173):
    """A unique, non-repeating field of painted water crops."""
    images = [normalise_water(Image.open(ROOT / name).convert("RGB")) for name in SOURCES]
    for name, image in zip(SOURCES, images):
        if min(image.size) < PATCH:
            raise ValueError("water detail source is too small: " + name)
    rng = random.Random(seed)
    result = Image.new("RGB", size, (146, 150, 140))
    step = PATCH - OVERLAP
    used = set()
    previous_row = []
    for y in range(0, size[1], step):
        row = []
        for column, x in enumerate(range(0, size[0], step)):
            excluded = set()
            if column:
                excluded.add(row[-1])
            if column < len(previous_row):
                excluded.add(previous_row[column])
            options = [i for i in range(len(images)) if i not in excluded]
            index = rng.choice(options)
            row.append(index)
            source = images[index]
            for _attempt in range(500):
                left = rng.randrange(source.width - PATCH + 1)
                top = rng.randrange(source.height - PATCH + 1)
                if (index, left, top) not in used:
                    used.add((index, left, top))
                    break
            else:
                raise ValueError("could not choose a unique water crop")
            piece = source.crop((left, top, left + PATCH, top + PATCH))
            if rng.random() < 0.5:
                piece = piece.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            result.paste(piece, (x, y), _patch_feather(x > 0, y > 0))
        previous_row = row
    return result


def _patch_feather(left, top):
    """Crisp crop centres, feathered joins only where a neighbour exists."""
    key = (left, top)
    if key not in _FEATHER_CACHE:
        mask = Image.new("L", (PATCH, PATCH), 255)
        pixels = mask.load()
        for y in range(PATCH):
            for x in range(PATCH):
                ax = min(1.0, (x + 1) / OVERLAP) if left else 1.0
                ay = min(1.0, (y + 1) / OVERLAP) if top else 1.0
                pixels[x, y] = round(255 * min(ax, ay))
        _FEATHER_CACHE[key] = mask
    return _FEATHER_CACHE[key]


_FEATHER_CACHE = {}


def _luminance_detail(field, radius):
    return ImageChops.subtract(field, field.filter(ImageFilter.GaussianBlur(radius)),
                               1.0, 128).convert("L")


def _add_luminance(base, detail, gain):
    lookup = [round(max(0, min(255, 128 + (value - 128) * gain))) for value in range(256)]
    detail = detail.point(lookup)
    return ImageChops.add(base, Image.merge("RGB", (detail, detail, detail)), 1.0, -128)


def _attenuate(detail, base, lo=150, hi=205, keep=0.45):
    """Fade fine grain where the water is bright: shallow ford water is calm.

    The pale bar is the shallowest, smoothest part of the ford; full-strength
    high-frequency grain there read as cracked ice rather than water.
    """
    lum = base.convert("L")
    span = float(hi - lo)
    weight = lum.point(lambda value: 0 if value <= lo else
                       255 if value >= hi else round(255 * min(1.0, (value - lo) / span)))
    weight = weight.point(lambda value: round(255 - (255 - value) * (1.0 - keep)))
    neutral = Image.new("L", detail.size, 128)
    return Image.composite(neutral, detail, weight)


def _cool(base):
    """Cool the deeper water, leaving the bright ford sand pale and warm."""
    weight = base.convert("L").point(
        lambda lum: round(TEAL_AMOUNT * 255 * (1.0 - max(0.0, min(1.0, (lum - 120) / 120)))))
    teal = Image.new("RGB", base.size, TEAL)
    return Image.composite(teal, base, weight)


def _current_strokes(image, mask, seed=3301):
    """Broken dashes and undertow lines: the stream's direction, not a sheen.

    The dashes are deliberately short and gapped. Continuous 150-pixel lines
    read as scratches once the ground beside them was painted at a fine grain.
    """
    width, height = image.size
    layer = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    rng = random.Random(seed)
    accepted = mask.load()
    for _ in range(2000):
        x = rng.uniform(0, width)
        y = rng.uniform(0.05 * height, 0.97 * height)
        xi, yi = int(x), int(y)
        if xi < 2 or xi >= width - 2 or yi < 1 or yi >= height - 1:
            continue
        if accepted[xi, yi] < 216:
            continue
        length = rng.randint(14, 64)
        angle = rng.uniform(-0.16, 0.16)
        if rng.random() < 0.70:
            colour = (248, 246, 226, rng.randint(9, 30))
        else:
            colour = (54, 74, 80, rng.randint(7, 22))
        dash = 0
        while dash < length:
            end = min(length, dash + rng.randint(3, 11))
            points = [(x + step * math.cos(angle),
                       y + step * math.sin(angle) + rng.uniform(-0.12, 0.12))
                      for step in range(dash, end + 1, 2)]
            if len(points) > 1:
                draw.line(points, fill=colour, width=1)
            dash = end + rng.randint(2, 7)
    return Image.alpha_composite(image.convert("RGBA"),
                                 layer.filter(ImageFilter.GaussianBlur(0.6))).convert("RGB")


def _colour_dabs(image, mask, seed=7717):
    """Short dabs of colour in the meadow's four-note palette.

    Luminance detail alone left the surface glassy: the grass beside it is built
    from warm and cool dabs at this scale, so the water gets them too, weighted
    toward teal where the water is deep and toward sand where it is shallow (the
    pale ford keeps its warm tone).
    """
    width, height = image.size
    depth = image.convert("L").filter(ImageFilter.GaussianBlur(6)).load()
    layer = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    rng = random.Random(seed)
    accepted = mask.load()
    palette = ((86, 118, 132), (236, 226, 198), (120, 134, 142), (206, 186, 150))
    for _ in range(3200):
        x = rng.uniform(0, width - 12)
        y = rng.uniform(0.05 * height, 0.97 * height)
        xi, yi = int(x), int(y)
        if accepted[xi, yi] < 216:
            continue
        shade = depth[xi, yi]
        if shade < 130:
            index = rng.choice((0, 0, 2, 2, 3))
        elif shade > 168:
            index = rng.choice((1, 1, 3, 3, 2))
        else:
            index = rng.choice((0, 1, 2, 3))
        colour = palette[index] + (rng.randint(16, 36),)
        length = rng.randint(4, 20)
        angle = rng.uniform(-0.2, 0.2)
        draw.line((x, y, x + length * math.cos(angle), y + length * math.sin(angle)),
                  fill=colour, width=1)
    return Image.alpha_composite(image.convert("RGBA"),
                                 layer.filter(ImageFilter.GaussianBlur(0.9))).convert("RGB")


def _bank_shading(image, mask):
    """Wet shadow where the water meets stone and bank.

    Only water pixels darken, so the audit's stone and shoreline pixels stay
    byte-identical; the zone is inset from the band rectangle so the repaint
    does not draw a straight dark seam across open water.
    """
    inner = mask.filter(ImageFilter.MinFilter(15))
    edge = ImageChops.subtract(mask, inner).filter(ImageFilter.GaussianBlur(4))
    inset = _rect_mask(mask.size, WATER_ROWS[0] * 64 - BAND_TOP - 48 + 22,
                       (WATER_ROWS[-1] + 1) * 64 - BAND_TOP + 58 - 22)
    weight = ImageChops.multiply(edge, inset).point(lambda value: round(value * BANK_SHADE))
    return Image.composite(Image.new("RGB", image.size, (34, 50, 56)), image, weight)


def _sun_glints(image, mask, seed=5521):
    """Sparse warm dashes: sunlight catching the surface, not a sparkle layer."""
    width, height = image.size
    layer = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    rng = random.Random(seed)
    accepted = mask.load()
    for _ in range(420):
        x = rng.randint(4, width - 30)
        y = rng.randint(int(0.08 * height), int(0.9 * height))
        if accepted[x, y] < 230:
            continue
        length = rng.randint(3, 16)
        draw.line((x, y, x + length, y), fill=(255, 248, 222, rng.randint(30, 90)), width=1)
    return Image.alpha_composite(image.convert("RGBA"),
                                 layer.filter(ImageFilter.GaussianBlur(0.5))).convert("RGB")


def paint(image):
    """Return the image with only its painted water surface repainted."""
    width, height = image.size
    band = image.crop((0, BAND_TOP, width, BAND_BOTTOM))
    mask = water_mask(band)
    weights = mask.filter(ImageFilter.GaussianBlur(1.6))

    # Remove the old water's hard tile strokes while keeping its depth, the
    # pale ford and the soft shading beneath every stone.
    base = band.filter(ImageFilter.MedianFilter(3))
    base = ImageChops.blend(base, band.filter(ImageFilter.GaussianBlur(2)), 0.4)
    base = _cool(base)

    field = detail_field(band.size)
    coarse = field.resize((round(width / COARSE_STRETCH), height),
                          Image.Resampling.LANCZOS).resize(
        band.size, Image.Resampling.BICUBIC)
    grain = _luminance_detail(field, 6)
    painted = _add_luminance(base, _attenuate(grain, base), FINE_GAIN)
    painted = _add_luminance(painted, _luminance_detail(coarse, 30), COARSE_GAIN)
    painted = _bank_shading(painted, mask)
    painted = _colour_dabs(painted, weights)
    painted = _current_strokes(painted, weights)
    painted = _sun_glints(painted, weights)

    # Fade the new surface out inside the mask, then paste strictly inside the
    # binary mask. Every changed pixel is therefore a painted-water pixel, the
    # bank/stones stay byte-identical, and the 1.6px feather still prevents a
    # hard new-vs-old water seam along each stone's foam rim.
    softened = Image.composite(painted, band, weights)
    result = image.copy()
    result.paste(Image.composite(softened, band, mask), (0, BAND_TOP))
    return result, mask
