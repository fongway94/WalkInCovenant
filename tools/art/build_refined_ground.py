#!/usr/bin/env python3
"""Make sharper, map-aligned ground for the chapter's painted overworld.

The existing reference ground is two texture pixels per world unit and blends
multiple paintings across large areas. This version uses four texture pixels
per world unit, places different ground paintings once per region, and only
cross-fades in their small joins. Grass and paths are restricted by the
original map materials; the brook and crossing retain the old pixels. This is
visual art only: navigation, collision, props and story positions remain in
region JSON. The shepherd-field reference is deliberately untouched.

The source paintings are sharpened before nearest-neighbour resizing, so their
existing small details survive without an extra smooth resampling pass. This
improves perceived edge clarity; it does not invent high-resolution detail.
The original shoreline and water retain their previous Lanczos-scaled pixels.

Each output is at most 2048 pixels on a side, to avoid requiring a larger WebGL
texture limit. The runtime places the two halves at their original world extent.
Requires Pillow 13.0.0. Run from the repository root; --check is read-only.
"""
from pathlib import Path
import argparse
import json
import math

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageOps, ImageStat

ROOT = Path("tools/art/sources")
SCENES = Path("art/scenes_painted")
WORLD_PIXEL_SCALE = 4
TILE = 16 * WORLD_PIXEL_SCALE

# Each painting occurs only once in a region. Four shallow Elah bands keep the
# grasses smaller relative to the people; two suit the shorter Bethlehem map.
# Large, recognisable flowers are never stamped around the map. The light fade
# is limited to the band joins; some paintings are mirrored for visual variety.
MEADOWS = {
    "elah": (("reference_meadow_village_ground.png", False),
             ("reference_meadow_quiet_ground.png", True),
             ("reference_meadow_second_ground.png", False),
             ("refine_elah_meadow.png", True)),
    "bethlehem": (("refine_bethlehem_meadow.png", False),
                  ("reference_meadow_quiet_ground.png", False)),
}


def material_mask(grid, chars, size, feather=0, padding=0):
    image = Image.new("L", size)
    draw = ImageDraw.Draw(image)
    for y, row in enumerate(grid):
        for x, char in enumerate(row):
            if char in chars:
                draw.rectangle((x * TILE - padding, y * TILE - padding,
                                (x + 1) * TILE - 1 + padding,
                                (y + 1) * TILE - 1 + padding), fill=255)
    if feather:
        image = image.filter(ImageFilter.GaussianBlur(feather))
    return image


def ridge_mask_for(grid, size):
    """Soften the dry ridge with an irregular verge, not a tile-straight line.

    This only selects painted pixels; the region grid remains the authoritative
    surface and collision map. A few low-amplitude, incommensurate curves keep
    the transition from looking like a rectangular strip.
    """
    mask = Image.new("L", size)
    draw = ImageDraw.Draw(mask)
    for x in range(size[0]):
        column = x // TILE
        offset = round(20 * math.sin(x / 139.0) + 12 * math.sin(x / 61.0 + 0.8)
                       + 6 * math.sin(x / 29.0 + 1.7))
        for y, row in enumerate(grid):
            if row[column] == "d":
                draw.line((x, y * TILE + offset, x, (y + 1) * TILE - 1 + offset), fill=255)
    return mask.filter(ImageFilter.GaussianBlur(26))


def fit_ground_detail(source, size):
    """Retain the painting's small edges instead of smoothing them twice.

    Sharpen at the *source* scale, not after enlargement. Nearest-neighbour
    fitting then preserves those painted edges without adding interpolated blur.
    This is deliberately limited to land artwork, not the protected water.
    """
    source = source.filter(ImageFilter.UnsharpMask(radius=1.0, percent=140, threshold=3))
    return ImageOps.fit(source, size, Image.Resampling.NEAREST)


def meadow(region, size):
    width, height = size
    sources = MEADOWS[region]
    overlap = 160 if region == "elah" else 192
    band_h = (height + (len(sources) - 1) * overlap) // len(sources)
    result = Image.new("RGB", size)
    for index, (filename, mirrored) in enumerate(sources):
        source = Image.open(ROOT / filename).convert("RGB")
        # Remove exaggerated foreground tufts from the lower edge; leave the
        # remaining irregular grass and flowers at their natural proportions.
        trim = 80 if region == "elah" else 48
        source = source.crop((0, 0, source.width, source.height - trim))
        image = fit_ground_detail(source, (width, band_h))
        if mirrored:
            image = ImageOps.mirror(image)
        if index == 0:
            result.paste(image, (0, 0))
        else:
            fade = Image.new("L", (width, band_h), 255)
            draw = ImageDraw.Draw(fade)
            for y in range(overlap):
                draw.line((0, y, width - 1, y), fill=round(255 * y / (overlap - 1)))
            result.paste(image, (0, index * (band_h - overlap)), fade)
    return result


def path_texture(size):
    """Use four distinct source crops, not a repeated earth tile.

    Paths outside the central strip retain the original art. Each segment is
    placed only once in the region.
    """
    width, height = size
    strip_w = 512
    overlap = 80
    band_h = (height + 3 * overlap + 3) // 4
    sources = [Image.open(ROOT / name).convert("RGB") for name in
               ("refine_path_ground.png", "reference_earth_ground.png")]
    crops = []
    for source in sources:
        middle = source.width // 2
        crops.extend([source.crop((0, 0, middle, source.height)),
                      source.crop((middle, 0, source.width, source.height))])
    strip = Image.new("RGB", (strip_w, height))
    for i, crop in enumerate(crops):
        section = fit_ground_detail(crop, (strip_w, band_h))
        y = i * (band_h - overlap)
        if i == 0:
            strip.paste(section, (0, y))
        else:
            fade = Image.new("L", (strip_w, band_h), 255)
            draw = ImageDraw.Draw(fade)
            for j in range(overlap):
                draw.line((0, j, strip_w - 1, j), fill=round(255 * j / (overlap - 1)))
            strip.paste(section, (0, y), fade)
    result = Image.new("RGB", size)
    left = (width - strip_w) // 2
    result.paste(strip, (left, 0))
    coverage = Image.new("L", size)
    ImageDraw.Draw(coverage).rectangle((left + 8, 0, left + strip_w - 9, height - 1), fill=255)
    coverage = coverage.filter(ImageFilter.GaussianBlur(8))
    return result, coverage


def path_mask_for(grid, size):
    """Soft irregular verges, centred on the existing comma tiles.

    These low-amplitude curves are purely decorative; they never shift tiles,
    alter collision or add a second route. Broad feathering lets the grass
    merge into the soil instead of exposing a straight-edged tile rectangle.
    """
    mask = Image.new("L", size)
    draw = ImageDraw.Draw(mask)
    for y in range(size[1]):
        row = grid[min(y // TILE, len(grid) - 1)]
        columns = [x for x, cell in enumerate(row) if cell == ","]
        if not columns:
            continue
        sway = 10 * math.sin(y / 149.0) + 6 * math.sin(y / 57.0)
        left = columns[0] * TILE + sway + 7 * math.sin(y / 83.0)
        right = (columns[-1] + 1) * TILE + sway + 9 * math.sin(y / 97.0 + 1.3)
        draw.line((round(left), y, round(right), y), fill=255)
    return mask.filter(ImageFilter.GaussianBlur(32))


def match_mean(source, target, mask):
    """Colour-match earth to the established ground without blurring detail."""
    source = ImageEnhance.Color(source).enhance(0.85)
    src = ImageStat.Stat(source, mask).mean
    dst = ImageStat.Stat(target, mask).mean
    channels = []
    for channel, a, b in zip(source.split(), src, dst):
        gain = max(0.65, min(1.35, b / max(1.0, a)))
        channels.append(channel.point([max(0, min(255, round(value * gain))) for value in range(256)]))
    return Image.merge("RGB", channels)


def build(region):
    if region not in MEADOWS:
        raise ValueError("unknown region: " + region)
    data = json.loads(Path("data/regions/" + region + ".json").read_text(encoding="utf8"))
    grid = data["grid"]
    size = (len(grid[0]) * TILE, len(grid) * TILE)
    previous = Image.open(SCENES / ("world_" + region + "_reference.png")).convert("RGB")
    if previous.size != (size[0] // 2, size[1] // 2):
        raise ValueError("previous ground no longer matches the region: " + region)
    reference_base = previous.resize(size, Image.Resampling.LANCZOS)
    # Protect the river tiles exactly AND the irregular painted shoreline that
    # extends into adjacent grass tiles. Without that extra feathered margin,
    # replacing the meadow cuts the winding bank into a straight tile edge.
    # Water and crossing pixels keep the previous pass's exact pixels.
    water = material_mask(grid, "~=e", size)
    shore_core = material_mask(grid, "~=e", size, padding=24)
    shoreline = material_mask(grid, "~=e", size, feather=20, padding=40)
    protected = ImageChops.lighter(shore_core, shoreline)
    safe = ImageChops.invert(protected)

    # The reference also remains visible on paving and the edges of paths.
    # Sharpen those existing land pixels, too, but cross-fade to the unchanged
    # reference before reaching the shoreline. No map or collision changes.
    sharper_base = previous.filter(ImageFilter.UnsharpMask(radius=1.0, percent=100, threshold=3))
    sharper_base = sharper_base.resize(size, Image.Resampling.NEAREST)
    base = Image.composite(sharper_base, reference_base, safe)
    grass_mask = ImageChops.multiply(material_mask(grid, ".fgwm", size, 18), safe)
    meadow_texture = meadow(region, size)
    image = Image.composite(meadow_texture, base, grass_mask)

    if region == "elah":
        # Give the irregular soil edge some meadow underneath it. Without
        # this narrow overlap, the old tile-straight verge would show through
        # whenever the new ridge recedes. Keep water and crossings protected.
        ridge_edge = ImageChops.multiply(material_mask(grid, "d", size, 10),
                                         material_mask(grid, ".fgwm", size, 20, 46))
        ridge_edge = ImageChops.multiply(ridge_edge, safe)
        image = Image.composite(meadow_texture, image, ridge_edge)
        # The battle ridge is a broad patch of soil, not an enlarged low-detail
        # old bitmap. Keep its established palette and feather into the meadow.
        ridge_mask = ImageChops.multiply(ridge_mask_for(grid, size), safe)
        ridge = Image.new("RGB", size)
        earth = Image.open(ROOT / "reference_earth_ground.png").convert("RGB")
        ridge.paste(fit_ground_detail(earth, (size[0], 11 * TILE)), (0, 0))
        ridge = match_mean(ridge, base, ridge_mask)
        image = Image.composite(ridge, image, ridge_mask)

    soil, soil_coverage = path_texture(size)
    # Comma tiles are the actual path. Crop its new detail to the unique source
    # strip, retaining old ground elsewhere and on all water/crossing tiles.
    path_mask = ImageChops.multiply(path_mask_for(grid, size), soil_coverage)
    path_mask = ImageChops.multiply(path_mask, safe)
    if path_mask.getbbox() is not None:
        soil = match_mean(soil, base, path_mask)
        image = Image.composite(soil, image, path_mask)

    # Keep a maximum side of 2048 for older WebGL2 phones. The two halves are
    # cut from one completed image, with no repeated edges or per-piece scaling.
    middle = size[1] // 2
    pieces = {"top": image.crop((0, 0, size[0], middle)),
              "bottom": image.crop((0, middle, size[0], size[1]))}
    return pieces, {"base": base, "reference_base": reference_base,
                    "water": water, "shore_core": shore_core,
                    "grass": grass_mask, "path": path_mask}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="verify without overwriting")
    args = parser.parse_args()
    for region in MEADOWS:
        pieces, _masks = build(region)
        for part, image in pieces.items():
            path = SCENES / ("world_" + region + "_refined_" + part + ".png")
            if args.check:
                with Image.open(path) as saved:
                    if image.mode != saved.mode or image.size != saved.size or image.tobytes() != saved.tobytes():
                        raise SystemExit("non-reproducible ground: " + str(path))
            else:
                image.save(path, optimize=True)
            print("verified" if args.check else "built", path, image.size)


if __name__ == "__main__":
    main()
