#!/usr/bin/env python3
"""Build map-aligned painterly ground and selected props for the David chapter.

Terrain masks come from the authored region grids, NOT a scaled concept map.
As a result the brook, crossing and paths remain at their real walkable tiles;
interactive objects remain separate Region nodes at their original footprints.
The generated sources are not game resources; the outputs are reproducible with
Pillow and the source PNGs in tools/art/sources. Run from the repository root.
"""
from pathlib import Path
import json
import math
import random
from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageOps

SRC = Path('tools/art/sources')
OUT = Path('art/scenes_painted')
PROPS = Path('art/props_painted')
SCALE = 2                  # texture pixels per world unit
TILE = 16 * SCALE


def quilted_texture(source, size, seed, patch=(560, 480), overlap=(160, 140)):
    """Feather varied crops together; avoid the obvious mirrored flower rows.

    The large overlaps make a soft transition without putting a recognisable
    reflected axis through the playable screen. Only horizontal mirroring is
    used, so upright grasses never appear upside down.
    """
    source = source.convert('RGB')
    pw, ph = patch
    ox, oy = overlap
    if source.width < pw or source.height < ph:
        raise ValueError('source is smaller than the requested texture patch')
    rng = random.Random(seed)
    out = Image.new('RGB', size)
    xfade = Image.new('L', patch, 255)
    yfade = Image.new('L', patch, 255)
    xd, yd = ImageDraw.Draw(xfade), ImageDraw.Draw(yfade)
    for i in range(ox):
        xd.line((i, 0, i, ph - 1), fill=round(255 * i / ox))
    for i in range(oy):
        yd.line((0, i, pw - 1, i), fill=round(255 * i / oy))
    opaque = Image.new('L', patch, 255)
    for row, y in enumerate(range(0, size[1], ph - oy)):
        for col, x in enumerate(range(0, size[0], pw - ox)):
            sx = rng.randrange(source.width - pw + 1)
            sy = rng.randrange(source.height - ph + 1)
            tile = source.crop((sx, sy, sx + pw, sy + ph))
            if rng.random() < 0.5:
                tile = ImageOps.mirror(tile)
            mx = xfade if col else opaque
            my = yfade if row else opaque
            out.paste(tile, (x, y), ImageChops.multiply(mx, my))
    return out


def meadow_sections(region, size):
    """Join two different, full-size paintings rather than tiling flower clumps.

    Each painting appears only once per region. The old random quilting still
    repeated the same conspicuous yellow flower bed several times, sometimes in
    the same phone viewport. A single soft overlap joins unique source areas;
    the Elah join also falls mostly under the river. Bottom-edge foreground
    blades are cropped away so they do not resemble impassable obstacles.
    """
    specs = {
        'elah': (
            ('reference_meadow_second_ground.png', None, 1.0, 1.0),
            ('reference_meadow_quiet_ground.png', None, 1.0, 1.0),
        ),
        'bethlehem': (
            ('reference_meadow_village_ground.png', None, 0.95, 0.85),
            ('reference_meadow_settlement_ground.png', None, 0.86, 1.0),
        ),
    }
    overlap = 160
    height = (size[1] + overlap + 1) // 2
    bands = []
    for filename, crop, brightness, saturation in specs[region]:
        source = Image.open(SRC / filename).convert('RGB')
        if crop is None:
            crop = (0, 0, source.width, source.height - 70)
        source = source.crop(crop)
        source = ImageEnhance.Color(source).enhance(saturation)
        source = ImageEnhance.Brightness(source).enhance(brightness)
        bands.append(ImageOps.fit(source, (size[0], height), Image.Resampling.LANCZOS))
    canvas = Image.new('RGB', size)
    canvas.paste(bands[0], (0, 0))
    fade = Image.new('L', bands[1].size, 255)
    draw = ImageDraw.Draw(fade)
    for y in range(overlap):
        draw.line((0, y, size[0] - 1, y), fill=round(255 * y / (overlap - 1)))
    canvas.paste(bands[1], (0, size[1] - height), fade)
    return canvas


def tile_mask(grid, chars, size, blur=8):
    m = Image.new('L', size)
    d = ImageDraw.Draw(m)
    for y, row in enumerate(grid):
        for x, ch in enumerate(row):
            if ch in chars:
                d.rectangle((x*TILE, y*TILE, (x+1)*TILE-1, (y+1)*TILE-1), fill=255)
    return m.filter(ImageFilter.GaussianBlur(blur)) if blur else m


def soften_path(mask):
    # Organic earth edges: warp rows AND columns by small, deterministic
    # offsets; the grid remains the authority for navigation.
    rows = Image.new('L', mask.size)
    for y in range(mask.height):
        shift = round(12 * math.sin(y / 125.0) + 6 * math.sin(y / 41.0 + 0.5))
        rows.paste(mask.crop((0, y, mask.width, y + 1)), (shift, y))
    out = Image.new('L', mask.size)
    for x in range(mask.width):
        shift = round(13 * math.sin(x / 135.0 + 1) + 6 * math.sin(x / 49.0))
        out.paste(rows.crop((x, 0, x + 1, mask.height)), (x, shift))
    return out


def world(region):
    raw = json.loads(Path('data/regions/' + region + '.json').read_text(encoding='utf-8'))
    grid = raw['grid']
    size = (len(grid[0]) * TILE, len(grid) * TILE)
    # The game map remains the authority for paths and collisions. Unlike a
    # repeating tile or random quilt of one small swatch, these are unique
    # ground paintings placed once per region and joined with one soft overlap.
    grass = meadow_sections(region, size)
    # Use a quieter, shadow-free portion of the existing stony ground for the
    # walkable track. A warm earth grade brings it closer to the reference.
    dry_sample = Image.open(SRC / 'camp_ground.png').convert('RGB').crop((0, 0, 360, 280))
    dry_sample = dry_sample.resize((720, 560), Image.Resampling.LANCZOS)
    earth_base = quilted_texture(dry_sample, size, seed=82, patch=(520, 400), overlap=(150, 120))
    soil_sample = Image.open(SRC / 'reference_earth_ground.png').convert('RGB')
    soil = quilted_texture(soil_sample, size, seed=38, patch=(560, 480), overlap=(160, 140))
    earth_base = Image.blend(earth_base, soil, 0.35)
    warm = ImageOps.colorize(ImageOps.grayscale(earth_base), black='#362b1c',
                             white='#e9b178', blackpoint=5, whitepoint=245)
    earth = Image.blend(earth_base, warm, 0.58)
    # A larger, ground-only cobble source avoids mirror-repeating the same tiny
    # crop into obvious symmetrical rows. Buildings remain independent nodes;
    # the map mask continues to determine where the paving is visible.
    paving_sample = Image.open(SRC / 'reference_paving_ground.png').convert('RGB')
    # The generated source has stones almost as wide as a person at 2 px per
    # world unit. Reduce it before quilting so the paving reads as small stones.
    paving_sample = paving_sample.resize((paving_sample.width // 2, paving_sample.height // 2),
                                         Image.Resampling.LANCZOS)
    # The swatch itself contains repeating rows. Mix smaller, overlapping crops
    # so no full row is carried intact into the playable paving.
    cobbles = quilted_texture(paving_sample, size, seed=63, patch=(96, 84), overlap=(24, 20))
    paving = Image.blend(earth, cobbles, 0.54)
    image = grass
    image = Image.composite(earth, image, soften_path(tile_mask(grid, 'd,s', size, 14)))
    # The camp's broad mud grid is a navigation/material description, not a
    # demand for a bare rectangle. Keep grasses visible between the tents.
    camp = Image.blend(grass, earth, 0.20)
    image = Image.composite(camp, image, soften_path(tile_mask(grid, 'm', size, 18)))
    wheat = Image.blend(grass, earth, 0.18)
    image = Image.composite(wheat, image, tile_mask(grid, 'w', size, 8))
    image = Image.composite(paving, image, soften_path(tile_mask(grid, 'p', size, 10)))
    if region == 'elah':
        elah = Image.open(SRC / 'elah_world.png').convert('RGB')
        # Keep the source's natural banks. The blue water is at y=390..443,
        # aligned to rows 26..27; its extra grassy margins blend into the
        # surrounding ground instead of forming a rectangle of water.
        water = elah.crop((0, 365, 848, 468)).resize((size[0], 124), Image.Resampling.LANCZOS)
        top = 26*TILE - 30
        river = image.copy()
        river.paste(water, (0, top))
        river_mask = Image.new('L', size)
        rd = ImageDraw.Draw(river_mask)
        for dy in range(water.height):
            alpha = min(255, dy * 32, (water.height - 1 - dy) * 32)
            rd.line((TILE, top + dy, size[0]-TILE-1, top + dy), fill=alpha)
        image = Image.composite(river, image, river_mask)
    edge = ImageEnhance.Brightness(grass).enhance(0.65)
    image = Image.composite(edge, image, tile_mask(grid, '#', size, 2))
    image = ImageEnhance.Contrast(image).enhance(1.06)
    image.save(OUT / ('world_' + region + '.png'), optimize=True)


def chroma(image):
    image = image.convert('RGBA')
    p = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = p[x, y]
            if (r > 85 and b > 85 and g < 110 and min(r, b) - g > 70) or (
                    r > 45 and b > r * 0.68 and g < min(r, b) * 0.42 and min(r, b) - g > 28):
                p[x, y] = (0, 0, 0, 0)
    bbox = image.getchannel('A').getbbox()
    if bbox is None:
        raise ValueError('no visible pixels in keyed source')
    return image.crop(bbox)


def props():
    # The old 26x18 tent read as a little box next to a person. Preserve its
    # 2x1 collision footprint but use a larger, detailed visual canvas. Region
    # anchors the visual at the same foot tile independently of its size.
    tent = chroma(Image.open(SRC / 'tent_prop.png'))
    tent = tent.resize((52, 34), Image.Resampling.LANCZOS)
    out = Image.new('RGBA', (52, 36))
    out.alpha_composite(tent, (0, 2))
    out.save(PROPS / 'tent.png', optimize=True)

    # Bethlehem's buildings retain their original 66x83 canvas and 2x2
    # collision footprint. The isolated source has a wider, lower silhouette,
    # so fit it inside that canvas and align its base with the original anchor.
    house = chroma(Image.open(SRC / 'house_prop.png'))
    house.thumbnail((66, 83), Image.Resampling.LANCZOS)
    out = Image.new('RGBA', (66, 83))
    out.alpha_composite(house, ((66 - house.width) // 2, 83 - house.height))
    out.save(PROPS / 'house.png', optimize=True)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    PROPS.mkdir(parents=True, exist_ok=True)
    for region in ('elah', 'bethlehem'):
        world(region)
    props()
    print('Built map-aligned painterly ground and tent art')


if __name__ == '__main__':
    main()
