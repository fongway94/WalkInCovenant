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
from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageOps

SRC = Path('tools/art/sources')
OUT = Path('art/scenes_painted')
PROPS = Path('art/props_painted')
SCALE = 2                  # texture pixels per world unit
TILE = 16 * SCALE


def reflected_texture(source, size):
    """Mirror-repeat an image without hard edges between repetitions."""
    source = source.convert('RGB')
    out = Image.new('RGB', size)
    w, h = source.size
    for y in range(0, size[1], h):
        for x in range(0, size[0], w):
            tile = source
            if (x // w) % 2:
                tile = ImageOps.mirror(tile)
            if (y // h) % 2:
                tile = ImageOps.flip(tile)
            out.paste(tile, (x, y))
    return out


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
    beth = Image.open(SRC / 'bethlehem_world.png').convert('RGB')
    # One continuous picture of stony grass, colour-graded into both the warm
    # earth and the olive grass. No embedded trees, buildings or phantom props.
    dry_sample = Image.open(SRC / 'camp_ground.png').convert('RGB')
    earth = reflected_texture(dry_sample, size)
    shade = ImageOps.grayscale(earth)
    grass = ImageOps.colorize(shade, black='#1f3022', white='#b1a04d',
                              blackpoint=10, whitepoint=235)
    # The crop contains only cobbles; the separate houses retain their own
    # collision and are never flattened into the playable ground.
    # At two texture pixels per world unit this native-size crop keeps the
    # individual cobbles smaller than a person, rather than giant paving slabs.
    paving_sample = beth.crop((525, 220, 600, 265))
    paving = reflected_texture(paving_sample, size)
    image = grass
    image = Image.composite(earth, image, soften_path(tile_mask(grid, 'd,sm', size, 16)))
    # Wheat uses grassy detail warmed toward the field palette rather than a
    # repeated drawn wheat sprite in every tile.
    wheat = Image.blend(grass, earth, 0.38)
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
    # Keep the original 26x18 canvas, foot anchor and 2x1 solid footprint.
    tent = chroma(Image.open(SRC / 'tent_prop.png'))
    tent.thumbnail((26, 18), Image.Resampling.LANCZOS)
    out = Image.new('RGBA', (26, 18))
    out.alpha_composite(tent, ((26 - tent.width) // 2, 18 - tent.height))
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
