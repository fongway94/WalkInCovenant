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
* The surface is sampled from three independent water paintings in unique crops
  (the same anti-repetition scheme the meadow uses) and built in five layers:
  fine grain, mid grain, broad current bands stretched along the flow, short
  broken dashes and small colour dabs. The grain fades out on the bright ford so
  the shallows stay calm instead of cracking into ice.
* The water keeps the stream's own colour: measured, the muted pass sat at about
  16% saturation and 123 degrees, i.e. wet stone, so the deep water is pulled
  toward 108 degrees and a higher saturation floor while the pale ford stays
  warm. A gentle vertical gradient darkens the water under the far bank.
* Water within a few pixels of a stone or the bank is darkened, so stones sit in
  the stream rather than on top of it, and three fading rings of disturbed water
  are drawn around every stone's real hole in the mask. Only water pixels
  change.
* The surface is finally posterised and stroked at brush size, because detail
  smaller than a screen pixel averages into blur.
* The stones themselves get their own pass: their interiors are unsharp-masked
  and flattened onto a few values so their facets read as paint, while the
  three-pixel ring that beds each stone in the water keeps its exact pixels.
* Collision, shore geometry, the crossing's walkable tiles, props and saves are
  untouched. This is a texture pass on `world_elah_refined_*` only.

The result is deterministic for the pinned Pillow version and fails closed: if
the Elah grid or the painted shore no longer match the layout this was tuned on,
the old water is preserved rather than a guessed repaint.
"""
from pathlib import Path
import math
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageOps, ImageStat

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
MID_GAIN = 0.20
COARSE_GAIN = 0.20
TEAL = (92, 124, 136)
TEAL_AMOUNT = 0.30
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
    for _ in range(5200):
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
        length = rng.randint(2, 12)
        angle = rng.uniform(-0.2, 0.2)
        draw.line((x, y, x + length * math.cos(angle), y + length * math.sin(angle)),
                  fill=colour, width=1)
    return Image.alpha_composite(image.convert("RGBA"),
                                 layer.filter(ImageFilter.GaussianBlur(0.9))).convert("RGB")


def _ripple_rings(image, mask):
    """Rings of disturbed water around every stone in the stream.

    Painted water breaks into rings where it runs past an obstacle. Three
    shrinking rings are built from the stone holes themselves (dilations of the
    inverse mask), so each ring follows the real shoreline of that rock, fades
    with distance, and is broken up by the surface grain so it never reads as a
    drawn circle. Only water pixels are touched.
    """
    stones = ImageChops.invert(mask).filter(ImageFilter.MinFilter(5))
    grain = image.convert("L").filter(ImageFilter.GaussianBlur(1))
    out = image
    for outer_size, inner_size, strength in ((11, 7, 0.55), (19, 15, 0.40), (29, 25, 0.28)):
        outer = stones.filter(ImageFilter.MaxFilter(outer_size))
        inner = stones.filter(ImageFilter.MaxFilter(inner_size))
        ring = ImageChops.subtract(outer, inner)
        ring = ImageChops.multiply(ring, mask).filter(ImageFilter.GaussianBlur(1.6))
        # Break the ring where the surface is already busy so it stays painterly.
        ring = ImageChops.multiply(ring, grain.point(
            lambda value: round(max(0.35, min(1.0, abs(value - 140) / 90)) * 255)))
        ring = ring.point(lambda value: round(value * strength * 0.34))
        out = Image.composite(Image.new("RGB", image.size, (246, 246, 232)), out, ring)
    return out


def _depth_tone(image, mask):
    """Darker, cooler water toward the far bank; a lighter lip at the near one.

    A field of flat mid-grey reads as concrete however much grain it carries. A
    gentle vertical gradient restores the sense of a channel: shaded water under
    the far bank, sunlit shallows at the viewer's side.
    """
    width, height = image.size
    ramp = Image.linear_gradient("L").resize((width, height), Image.BILINEAR)
    far = ramp.point(lambda value: round((255 - value) / 255 * 0.26 * 255))
    near = ramp.point(lambda value: round(max(0, value - 190) / 65 * 0.16 * 255))
    far = ImageChops.multiply(far, mask)
    near = ImageChops.multiply(near, mask)
    image = Image.composite(Image.new("RGB", image.size, (48, 76, 88)), image, far)
    return Image.composite(Image.new("RGB", image.size, (250, 246, 226)), image, near)


def _tint(image, mask):
    """Give the water its own blue-green voice without leaving the palette.

    The ground pass muted the brook toward the meadow's ochre; measured, the
    water sat at about 16% saturation and 123 degrees, i.e. wet stone. Water in
    the chapter's own palette is cooler and clearly more saturated, so the deep
    water is pulled toward 138 degrees and at least 28% saturation while the
    bright ford stays pale and warm.
    """
    hsv = image.convert("HSV")
    hue, sat, val = hsv.split()
    depth = val.point(lambda value: round(max(0.0, min(1.0, (162 - value) / 42.0)) * 255))
    weight = ImageChops.multiply(depth, mask)
    hue = Image.blend(hue, Image.new("L", hue.size, 108), 0.38)
    sat = ImageChops.lighter(sat, weight.point(lambda value: round(value * 0.30)))
    tinted = Image.merge("HSV", (hue, sat, val)).convert("RGB")
    return Image.composite(tinted, image, mask)


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


def _posterise(image, mask, bits=3, strength=0.55):
    """Pull the surface onto a handful of flat values.

    A smooth gradient at 1:1 reads as blur however much grain sits on it; the
    meadow beside it looks crisp because it is built from flat painted values.
    Posterising three bits per channel and blending back keeps every hue the
    painting already has, but gives the water edges to its shape.
    """
    from PIL import ImageOps
    flat = ImageOps.posterize(image, bits)
    out = ImageChops.blend(image, flat, strength)
    # quantising flattens saturation, so put the stream's own colour back
    hue, sat, val = out.convert("HSV").split()
    sat = sat.point(lambda value: min(255, round(value * 1.20)))
    return Image.merge("HSV", (hue, sat, val)).convert("RGB")


def _flow_strokes(image, mask, seed=6037, count=2600):
    """Brush-sized strokes along the current: the detail a brush leaves.

    Detail smaller than a screen pixel averages into mush, so the fine pass is
    made of short strokes 10-40 pixels long and 2-4 pixels thick, alternating
    dark undertow and light crest along a slow noise field. Hard edges, no blur.
    """
    width, height = image.size
    layer = image.copy()
    draw = ImageDraw.Draw(layer)
    rng = random.Random(seed)
    accepted = mask.load()
    flow = Image.effect_noise((width, height), 48).filter(ImageFilter.GaussianBlur(6)).load()
    for _ in range(count):
        x = rng.randrange(0, width)
        y = rng.randrange(0, height)
        if accepted[x, y] < 216:
            continue
        light = flow[x, y] > 128
        gain = 1.0 + (0.16 if light else -0.15) * rng.uniform(0.5, 1.0)
        red, green, blue = image.getpixel((x, y))
        colour = (max(0, min(255, round(red * gain))),
                  max(0, min(255, round(green * gain))),
                  max(0, min(255, round(blue * gain))))
        length = rng.randint(10, 40)
        slope = rng.uniform(-0.10, 0.10)
        draw.line((x, y, x + length, y + slope * length), fill=colour,
                  width=rng.randint(2, 4))
    return Image.composite(layer, image, mask)


def _foam_edges(image, mask, seed=8123, count=520):
    """Bright broken foam on the stones' upstream rim, one or two pixels wide."""
    width, height = image.size
    layer = image.copy()
    draw = ImageDraw.Draw(layer)
    rng = random.Random(seed)
    accepted = mask.load()
    inner = mask.filter(ImageFilter.MinFilter(9)).load()
    for _ in range(count):
        x = rng.randrange(0, width)
        y = rng.randrange(0, height)
        if accepted[x, y] < 216 or inner[x, y] > 0:
            continue
        red, green, blue = image.getpixel((x, y))
        amount = rng.uniform(0.35, 0.70)
        colour = (round(red * (1 - amount) + 226 * amount),
                  round(green * (1 - amount) + 240 * amount),
                  round(blue * (1 - amount) + 232 * amount))
        length = rng.randint(2, 7)
        draw.line((x, y, x + length, y - length // 3), fill=colour, width=1)
    return Image.composite(layer, image, mask)


def stone_mask(band, water):
    """The sunlit stones standing in the brook, as a mask.

    Only the stream's own rows are searched, so the bank above and below cannot
    qualify, and inside them a stone is simply warm, saturated paint outside the
    water: the meadow is green, the ford's sand bar is pale, and the water is
    already excluded by the water mask.
    """
    inside = _rect_mask(band.size, WATER_ROWS[0] * 64 - BAND_TOP + 8,
                        (WATER_ROWS[-1] + 1) * 64 - BAND_TOP - 8)
    hue, saturation, value = band.convert("HSV").split()
    warm = ImageChops.multiply(
        ImageChops.multiply(hue.point(lambda v: 255 if v < 60 else 0),
                            saturation.point(lambda v: 255 if v > 40 else 0)),
        value.point(lambda v: 255 if v > 90 else 0))
    warm = ImageChops.multiply(warm, inside)
    stones = ImageChops.multiply(warm, ImageChops.invert(water))
    # A stone is a body, not a speck of sand: open out anything thinner than
    # nine pixels, then restore the body's own size.
    body = stones.filter(ImageFilter.MinFilter(9)).filter(ImageFilter.MaxFilter(9))
    stones = ImageChops.multiply(stones, body)
    stones = stones.filter(ImageFilter.MedianFilter(3))
    # the opening and the median both move edges; keep stones out of the water
    return ImageChops.multiply(stones, ImageChops.invert(water))


def _stone_detail(image, water, seed=4517):
    """Give the stones painted faces instead of an airbrush.

    Each stone's interior is unsharp-masked and flattened onto a few values, so
    its facets and its silhouette edge read as paint rather than as a soft
    gradient. A three-pixel ring around every stone is left exactly as painted,
    so the foam rim that beds it in the stream still belongs to the shoreline.
    """
    stones = stone_mask(image, water)
    core = stones.filter(ImageFilter.MinFilter(7))
    detail = image.filter(ImageFilter.UnsharpMask(radius=1.2, percent=140, threshold=2))
    detail = ImageChops.blend(image, detail, 0.75)
    flat = ImageOps.posterize(detail, 5)
    painted = ImageChops.blend(detail, flat, 0.55)
    # Bevel: the top of every stone catches the sky, its underside sits in the
    # water. One pixel each, so the silhouette reads as a painted outline.
    up_out = ImageChops.invert(ImageChops.offset(core, 0, 1))
    down_out = ImageChops.invert(ImageChops.offset(core, 0, -1))
    top_edge = ImageChops.multiply(core, up_out)
    bottom_edge = ImageChops.multiply(core, down_out)
    lit = ImageChops.add(painted, Image.new("RGB", image.size, (30, 27, 20)))
    dark = ImageChops.subtract(painted, Image.new("RGB", image.size, (44, 39, 30)))
    painted = Image.composite(lit, painted, top_edge.point(lambda value: round(value * 0.6)))
    painted = Image.composite(dark, painted, bottom_edge.point(lambda value: round(value * 0.75)))
    return Image.composite(painted, image, core), core


def paint(image):
    """Return the image with only its painted water surface repainted."""
    width, height = image.size
    band = image.crop((0, BAND_TOP, width, BAND_BOTTOM))
    mask = water_mask(band)
    weights = mask.filter(ImageFilter.GaussianBlur(1.6))

    # Remove the old water's hard tile strokes while keeping its depth, the
    # pale ford and the soft shading beneath every stone.
    base = band.filter(ImageFilter.MedianFilter(3))
    base = ImageChops.blend(base, band.filter(ImageFilter.GaussianBlur(1)), 0.3)
    base = _cool(base)

    field = detail_field(band.size)
    coarse = field.resize((round(width / COARSE_STRETCH), height),
                          Image.Resampling.LANCZOS).resize(
        band.size, Image.Resampling.BICUBIC)
    fine = _luminance_detail(field, 3)
    mid = _luminance_detail(field, 9)
    painted = _add_luminance(base, _attenuate(fine, base), FINE_GAIN)
    painted = _add_luminance(painted, _attenuate(mid, base), MID_GAIN)
    painted = _add_luminance(painted, _luminance_detail(coarse, 30), COARSE_GAIN)
    painted = _tint(painted, mask)
    painted = _depth_tone(painted, mask)
    painted = _bank_shading(painted, mask)
    painted = _ripple_rings(painted, mask)
    painted = _colour_dabs(painted, weights)
    painted = _current_strokes(painted, weights)
    painted = _sun_glints(painted, weights)
    painted = _posterise(painted, mask)
    painted = _flow_strokes(painted, mask)
    painted = _foam_edges(painted, mask)

    # Fade the new surface out inside the mask, then paste strictly inside the
    # binary mask. Every changed pixel is therefore a painted-water pixel, the
    # bank/stones stay byte-identical, and the 1.6px feather still prevents a
    # hard new-vs-old water seam along each stone's foam rim.
    softened = Image.composite(painted, band, weights)
    result = image.copy()
    result.paste(Image.composite(softened, band, mask), (0, BAND_TOP))

    # The stones are painted objects standing in the repainted water, so they
    # get the same treatment: crisp faces, hard dabs, a contact shadow. Only
    # their interior changes; the outer ring keeps the shoreline's own pixels.
    stones_image, stone_core = _stone_detail(result.crop((0, BAND_TOP, width, BAND_BOTTOM)), mask)
    # paste only through the stones' own mask: the water under it is already final
    result.paste(stones_image, (0, BAND_TOP), stone_core)
    return result, mask, stone_core
