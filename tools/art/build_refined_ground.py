#!/usr/bin/env python3
"""Build detailed, map-aligned ground for the chapter's painted overworld.

First reconstruct the previously published ground. Then add small-scale grass
and earth detail from original painted source art, matched to the existing
colour and light, plus a unique stone-paving section. Source crops are chosen
and blended deterministically; neither a repeated tile nor a random-noise
texture is stamped over the scene. Materials stay restricted by the map grid.
The river and its visible shoreline remain untouched; only inland grass in the
ends of the broad crossing tiles is updated to remove a soft rectangular seam.

This is visual art only: navigation, collision, props and story positions
remain in region JSON. The shepherd-field reference is deliberately untouched.
Each output is at most 2048 pixels on a side, to avoid requiring a larger WebGL
texture limit. The runtime places the two halves at their original world extent.
Requires Pillow 13.0.0. Run from the repository root; --check is read-only.
"""
from pathlib import Path
from functools import lru_cache
import argparse
import hashlib
import json
import math
import random

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

# Fine structure is sampled from several original paintings rather than an
# enlarged or repeated single image. These are build-time inputs, not extra
# textures loaded by the game. Nearby crops never use the same source.
GRASS_DETAIL = ("ground_detail_grass_a.png", "ground_detail_grass_b.png",
                "ground_detail_meadow_north.png", "ground_detail_meadow_camp.png",
                "ground_detail_meadow_town.png")
SOIL_DETAIL = ("ground_detail_earth.png", "refine_path_ground.png",
               "reference_earth_ground.png")
PAVING_DETAIL = "ground_detail_paving.png"
DETAIL_PATCH = 320
DETAIL_OVERLAP = 96
# The ford's protected pixel band below is registered to this reference. If
# the painting changes, fall back to fully protecting the old crossing until
# the actual shoreline has been reviewed again.
ELAH_SHORE_REFERENCE_SHA256 = "dfd5c90596c8ca24cbe19e93faf2c9add324315b4a2896477314a61a7782a224"


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


def build_published_base(region):
    """Reconstruct the previous public texture without reading current output."""
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


def normalise_detail_source(image):
    """Keep the different source paintings in a compatible tonal range."""
    stats = ImageStat.Stat(image)
    channels = []
    for channel, mean, deviation, target_mean, target_deviation in zip(
            image.split(), stats.mean, stats.stddev, (125.0, 108.0, 45.0), (42.0, 34.0, 23.0)):
        gain = max(0.45, min(1.45, target_deviation / max(1.0, deviation)))
        channels.append(channel.point([
            round(max(0, min(255, target_mean + (value - mean) * gain)))
            for value in range(256)
        ]))
    return Image.merge("RGB", channels)


@lru_cache(maxsize=4)
def detail_patch_mask(left, top):
    """Feather the small joins, leaving the centre of every crop crisp."""
    mask = Image.new("L", (DETAIL_PATCH, DETAIL_PATCH), 255)
    pixels = mask.load()
    for y in range(DETAIL_PATCH):
        for x in range(DETAIL_PATCH):
            ax = min(1.0, (x + 1) / DETAIL_OVERLAP) if left else 1.0
            ay = min(1.0, (y + 1) / DETAIL_OVERLAP) if top else 1.0
            pixels[x, y] = round(255 * min(ax, ay))
    return mask


def painted_detail(size, sources, seed, scale):
    """Build a deterministic field of small, varied painted source crops.

    Crop positions and left/right reflection vary in world space; immediately
    adjacent crops use different sources and no exact crop is reused within a
    region. This is *not* a seamless repeating tile or procedural random noise.
    Afterwards the low frequencies are removed, so the existing scene supplies
    broad lighting and colour without introducing a checkerboard of patches.
    """
    rng = random.Random(seed)
    images = []
    for name in sources:
        source = normalise_detail_source(Image.open(ROOT / name).convert("RGB"))
        source = source.resize((round(source.width * scale), round(source.height * scale)),
                               Image.Resampling.NEAREST)
        if min(source.size) < DETAIL_PATCH:
            raise ValueError("detail source is too small: " + name)
        images.append(source)
    result = Image.new("RGB", size, (125, 108, 45))
    used = set()
    previous_row = []
    step = DETAIL_PATCH - DETAIL_OVERLAP
    for y in range(0, size[1], step):
        row = []
        for column, x in enumerate(range(0, size[0], step)):
            excluded = set()
            if column:
                excluded.add(row[-1])
            if column < len(previous_row):
                excluded.add(previous_row[column])
            options = [i for i in range(len(images)) if i not in excluded]
            if not options:
                raise ValueError("not enough independent detail sources")
            index = rng.choice(options)
            row.append(index)
            source = images[index]
            for _attempt in range(100):
                left = rng.randrange(source.width - DETAIL_PATCH + 1)
                top = rng.randrange(source.height - DETAIL_PATCH + 1)
                mirrored = rng.random() < 0.5
                # A reflected copy of the same source rectangle still counts
                # as a repeat, so exclude it regardless of orientation.
                key = (index, left, top)
                if key not in used:
                    used.add(key)
                    break
            else:
                raise ValueError("could not choose a unique detail crop")
            piece = source.crop((left, top, left + DETAIL_PATCH, top + DETAIL_PATCH))
            if mirrored:
                piece = ImageOps.mirror(piece)
            result.paste(piece, (x, y), detail_patch_mask(x > 0, y > 0))
        previous_row = row
    low = result.filter(ImageFilter.GaussianBlur(12))
    return ImageChops.subtract(result, low, 1.0, 128), len(used)


def apply_painted_detail(base, base_low, detail, gain, original):
    """Combine real fine painted forms with the existing broad scene lighting."""
    lit_base = Image.blend(base_low, base, original)
    lut = [round(max(0, min(255, 128 + (value - 128) * gain)))
           for value in range(256)]
    return ImageChops.add(lit_base, detail.point(lut * 3), 1.0, -128)


def crossing_inland_mask(grid, size, reference_digest=None):
    """Refresh only the grassy ends of the Elah crossing, never the bank.

    The old map mask treats a six-tile-high crossing as entirely water, even
    where the painting has inland grass. Its rectangular soft patch is visible
    in gameplay. The reference bank lies inside world y=398..462, so retain that
    complete band in the crossing plus the padded water/reed tiles. This narrow
    mask is only enabled for the known grid and reference painting; changes to
    either fall back to the fully protected crossing rather than guessing.
    """
    empty = Image.new("L", size)
    water_rows = [y for y, row in enumerate(grid) if "~" in row or "e" in row]
    shallow = {(x, y) for y, row in enumerate(grid) for x, cell in enumerate(row) if cell == "="}
    expected = {(x, y) for y in range(24, 30) for x in range(12, 20)}
    if size != (2048, 3072) or water_rows != [26, 27] or shallow != expected:
        return empty, None
    if reference_digest is None:
        reference = SCENES / "world_elah_reference.png"
        if not reference.is_file():
            return empty, None
        reference_digest = hashlib.sha256(reference.read_bytes()).hexdigest()
    if reference_digest != ELAH_SHORE_REFERENCE_SHA256:
        return empty, None
    top = 398 * WORLD_PIXEL_SCALE
    bottom = 462 * WORLD_PIXEL_SCALE
    inland = material_mask(grid, "=", size, padding=24)
    ImageDraw.Draw(inland).rectangle((0, top, size[0] - 1, bottom - 1), fill=0)
    inland = inland.filter(ImageFilter.GaussianBlur(24))
    ImageDraw.Draw(inland).rectangle((0, top, size[0] - 1, bottom - 1), fill=0)
    inland = ImageChops.multiply(inland, material_mask(grid, "=", size, padding=40))
    return inland, (top, bottom)


def crossing_south_approach(grid, size, inland, water_band):
    """Keep the existing south path legible where it reaches the ford.

    The crossing's inland mask includes a short continuation of the path.
    Use soil rather than grass detail there, following the comma tiles directly
    below it. Unknown layouts fail closed instead of painting a guessed route.
    """
    empty = Image.new("L", size)
    if water_band is None or len(grid) <= 30:
        return empty
    columns = [x for x, cell in enumerate(grid[30]) if cell == ","]
    if (not columns or columns != list(range(columns[0], columns[-1] + 1))
            or columns[0] < 12 or columns[-1] > 19
            or len(columns) * TILE <= 32):
        return empty
    mask = Image.new("L", size)
    draw = ImageDraw.Draw(mask)
    for y in range(water_band[1], size[1]):
        sway = 10 * math.sin(y / 149.0) + 6 * math.sin(y / 57.0)
        left = columns[0] * TILE + sway + 7 * math.sin(y / 83.0) + 16
        right = (columns[-1] + 1) * TILE + sway + 9 * math.sin(y / 97.0 + 1.3) - 16
        draw.line((round(left), y, round(right), y), fill=255)
    return ImageChops.multiply(inland, mask.filter(ImageFilter.GaussianBlur(24)))


def join_painted_sections(first, second, overlap):
    """Join two paving crops along a low-error, gently feathered seam.

    A broad crossfade doubles the outlines of stones. Following an irregular
    low-difference path through the overlap keeps the stones legible without a
    tile-straight cut. Only the narrow seven-pixel edge is blended.
    """
    if (first.mode != "RGB" or second.mode != "RGB" or first.height != second.height
            or overlap <= 0 or overlap > min(first.width, second.width)):
        raise ValueError("incompatible painted sections")
    height = first.height
    left = first.crop((first.width - overlap, 0, first.width, height))
    right = second.crop((0, 0, overlap, height))
    red, green, blue = ImageChops.difference(left, right).split()
    r, g, b = red.load(), green.load(), blue.load()
    previous = [0.0] * overlap
    backs = []
    for y in range(height):
        current = [0.0] * overlap
        back = bytearray(overlap)
        for x in range(overlap):
            value, parent = min((previous[k], k)
                                for k in range(max(0, x - 1), min(overlap, x + 2)))
            back[x] = parent - x + 1
            current[x] = value + r[x, y] + g[x, y] + b[x, y] + abs(x - overlap / 2) * 0.12
        backs.append(back)
        previous = current
    seam = [0] * height
    x = min(range(overlap), key=lambda i: previous[i])
    for y in range(height - 1, -1, -1):
        seam[y] = x
        x = max(0, min(overlap - 1, x + backs[y][x] - 1))

    mask = Image.new("L", second.size, 255)
    draw = ImageDraw.Draw(mask)
    for y, x in enumerate(seam):
        if x > 3:
            draw.line((0, y, x - 4, y), fill=0)
        for i in range(max(0, x - 3), min(overlap, x + 4)):
            mask.putpixel((i, y), round(255 * (i - (x - 3)) / 6))
    result = Image.new("RGB", (first.width + second.width - overlap, height))
    result.paste(first, (0, 0))
    result.paste(second, (first.width - overlap, 0), mask)
    return result


def paving_image(size, box):
    """Use two non-overlapping parts of the curated, non-mirrored paving art."""
    source = Image.open(ROOT / PAVING_DETAIL).convert("RGB")
    width, height = box[2] - box[0], box[3] - box[1]
    overlap = min(110, width // 3)
    first_width = (width + overlap) // 2
    second_width = width - first_width + overlap
    first = source.crop((0, 0, source.width, source.height // 2))
    second = source.crop((0, source.height // 2, source.width, source.height))
    first = ImageOps.fit(first, (first_width, height), Image.Resampling.NEAREST)
    second = ImageOps.fit(second, (second_width, height), Image.Resampling.NEAREST)
    strip = join_painted_sections(first, second, overlap)
    result = Image.new("RGB", size)
    result.paste(strip, box[:2])
    return result


def build(region):
    pieces, masks = build_published_base(region)
    data = json.loads(Path("data/regions/" + region + ".json").read_text(encoding="utf8"))
    grid = data["grid"]
    size = (len(grid[0]) * TILE, len(grid) * TILE)
    baseline = Image.new("RGB", size)
    baseline.paste(pieces["top"], (0, 0))
    baseline.paste(pieces["bottom"], (0, size[1] // 2))
    base_low = baseline.filter(ImageFilter.GaussianBlur(8))

    shore = material_mask(grid, "~=e", size, feather=20, padding=40)
    safe = ImageChops.invert(ImageChops.lighter(masks["shore_core"], shore))
    inland, water_band = crossing_inland_mask(grid, size)
    # Rocky map tiles are painted as part of the surrounding meadow; leaving
    # them out exposed soft square patches around otherwise crisp tree props.
    # Restore the same fine land detail without changing the rocky tile's
    # collision/surface or touching protected water and shoreline pixels.
    rocky = ImageChops.multiply(material_mask(grid, "r", size, 18), safe)
    approach = crossing_south_approach(grid, size, inland, water_band)
    inland_grass = ImageChops.subtract(inland, approach)
    grass_mask = ImageChops.lighter(ImageChops.lighter(masks["grass"], inland_grass), rocky)
    soil_mask = ImageChops.lighter(masks["path"], approach)
    if region == "elah":
        soil_mask = ImageChops.lighter(soil_mask,
                                       ImageChops.multiply(ridge_mask_for(grid, size), safe))
    paving_mask = ImageChops.multiply(material_mask(grid, "p", size, 18), safe)

    grass, grass_crops = painted_detail(size, GRASS_DETAIL, 131 if region == "elah" else 431, 0.76)
    soil, soil_crops = painted_detail(size, SOIL_DETAIL, 731 if region == "elah" else 719, 0.56)
    image = Image.composite(apply_painted_detail(baseline, base_low, grass, 0.90, 0.48),
                            baseline, grass_mask)
    image = Image.composite(apply_painted_detail(baseline, base_low, soil, 0.58, 0.45),
                            image, soil_mask)
    box = paving_mask.getbbox()
    if box is not None:
        paving = match_mean(paving_image(size, box), baseline, paving_mask)
        image = Image.composite(paving, image, paving_mask)

    middle = size[1] // 2
    pieces = {"top": image.crop((0, 0, size[0], middle)),
              "bottom": image.crop((0, middle, size[0], size[1]))}
    masks.update({"baseline": baseline, "updated_grass": grass_mask, "rocky": rocky,
                  "inland": inland, "approach": approach, "water_band": water_band,
                  "soil": soil_mask, "paving": paving_mask,
                  "grass_crops": grass_crops, "soil_crops": soil_crops})
    return pieces, masks


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
