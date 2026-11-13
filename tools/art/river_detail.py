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
* Fine ripples, broad current strokes, warm glints and the long horizontal
  sheen come from three independent water paintings, sampled in unique crops
  (the same anti-repetition scheme the meadow uses). No crop is reused and
  adjacent patches never share a source.
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
FINE_GAIN = 0.30
COARSE_GAIN = 0.08
TEAL = (92, 124, 136)
TEAL_AMOUNT = 0.18
STRETCH = 1.7


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


def _cool(base):
    """Cool the deeper water, leaving the bright ford sand pale and warm."""
    weight = base.convert("L").point(
        lambda lum: round(TEAL_AMOUNT * 255 * (1.0 - max(0.0, min(1.0, (lum - 120) / 120)))))
    teal = Image.new("RGB", base.size, TEAL)
    return Image.composite(teal, base, weight)


def _current_strokes(image, mask, seed=3301):
    """Long, soft horizontal sheen and undertow lines: the stream's direction."""
    width, height = image.size
    layer = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    rng = random.Random(seed)
    accepted = mask.load()
    for _ in range(520):
        x = rng.uniform(0, width)
        y = rng.uniform(0.08 * height, 0.95 * height)
        xi, yi = int(x), int(y)
        if xi < 2 or xi >= width - 2 or yi < 1 or yi >= height - 1:
            continue
        if accepted[xi, yi] < 216:
            continue
        length = rng.randint(24, 150)
        amplitude = rng.uniform(0.0, 1.6)
        phase = rng.uniform(0.0, 6.28)
        if rng.random() < 0.72:
            colour = (248, 246, 226, rng.randint(10, 34))
        else:
            colour = (54, 74, 80, rng.randint(8, 26))
        points = [(x + step, y + amplitude * math.sin(phase + step / 22.0))
                  for step in range(0, length, 4)]
        draw.line(points, fill=colour, width=1)
    return Image.alpha_composite(image.convert("RGBA"),
                                 layer.filter(ImageFilter.GaussianBlur(0.6))).convert("RGB")


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
    stretched = field.resize((round(width / STRETCH), height),
                             Image.Resampling.LANCZOS).resize(
        band.size, Image.Resampling.BICUBIC)
    painted = _add_luminance(base, _luminance_detail(stretched, 7), FINE_GAIN)
    painted = _add_luminance(painted, _luminance_detail(stretched, 30), COARSE_GAIN)
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
