#!/usr/bin/env python3
"""Check reproducibility, field masking, actors and prop geometry; not an art review.

Requires Pillow 13.0.0. Runs entirely on the committed source images and does
not touch game saves or overwrite any output textures.
"""
import hashlib
import json
import os
from pathlib import Path
import statistics
import sys
import tempfile

from PIL import Image, ImageChops, ImageDraw, ImageStat

ROOT = Path(__file__).resolve().parents[2]
os.chdir(ROOT)
sys.path.insert(0, str(ROOT / "tools/proto"))
sys.path.insert(0, str(ROOT / "tools/art"))

import build_reference_field as field  # noqa: E402
import build_world_ground as world  # noqa: E402
import build_reference_props as reference_props  # noqa: E402
import build_painted_props as painted_props  # noqa: E402
import build_reference_world as continuation  # noqa: E402
import build_reference_characters as characters  # noqa: E402
import build_reference_variants as variants  # noqa: E402
import build_refined_ground as refined_ground  # noqa: E402
import build_refined_props as refined_props  # noqa: E402
import build_tall_trees as tall_trees  # noqa: E402
import river_detail  # noqa: E402
from prop_detail import DETAIL_FACTOR  # noqa: E402


def same_pixels(generated, path):
    with Image.open(path) as saved:
        return (generated.mode == saved.mode and generated.size == saved.size
                and generated.tobytes() == saved.tobytes())


def adjacent_luma_difference(image):
    """Mean local edge strength, used only as a blur regression indicator."""
    gray = image.convert("L")
    width, height = gray.size
    horizontal = ImageChops.difference(gray.crop((0, 0, width - 1, height)),
                                       gray.crop((1, 0, width, height)))
    vertical = ImageChops.difference(gray.crop((0, 0, width, height - 1)),
                                     gray.crop((0, 1, width, height)))
    return (ImageStat.Stat(horizontal).mean[0] + ImageStat.Stat(vertical).mean[0]) / 2.0


def row_boundary_difference(image, y):
    """Mean RGB change between neighbouring rows of a reconstructed image."""
    width = image.width
    change = ImageChops.difference(image.crop((0, y - 1, width, y)),
                                   image.crop((0, y, width, y + 1)))
    return sum(ImageStat.Stat(change).mean) / 3.0


def source_point_to_field(x, y):
    # Forward registration, for checking that every actor exclusion survives.
    denominator = 0.0000000893508570 * x - 0.000000537761701 * y + 1.0
    return (round((1.43202038 * x - 0.000241270343 * y - 2.74793799) / denominator),
            round((-0.0000121064900 * x + 1.43371684 * y - 83.2078352) / denominator))


def check_field():
    digest = hashlib.sha256(field.REFERENCE.read_bytes()).hexdigest()
    assert digest == "73d0baa80239745904985e4348e45238b9ae9e41dedf0b90e3d60b87957a2833"
    images, mask = field.build()
    for name, image in images.items():
        assert same_pixels(image, field.OUT / name), "non-reproducible field: " + name
    old = Image.open(field.INPAINTED).convert("RGB")
    backdrop = images["shepherd_field_reference.png"]
    for left, top, right, bottom in field.ACTOR_EXCLUSIONS:
        point = source_point_to_field((left + right) / 2, (top + bottom) / 2)
        assert mask.getpixel(point) == 0, "reference actor was not excluded: " + str(point)
        assert backdrop.getpixel(point) == old.getpixel(point), "inpaint lost: " + str(point)
    assert mask.getpixel((1430, 300)) == 0
    assert backdrop.getpixel((1430, 300)) == old.getpixel((1430, 300))
    coverage = sum(mask.histogram()[241:]) / (mask.width * mask.height)
    assert 0.84 < coverage < 0.90, "unexpected reference coverage: " + str(coverage)

    # Confirm the coloured pixels in each depth layer come from this very
    # backdrop. Low-alpha antialiased edges can differ slightly by rounding.
    for name, offset in (("tree", (0, 0)), ("fence", (0, 0)), ("foreground", (0, 250))):
        layer = images["shepherd_field_reference_" + name + ".png"]
        samples = 0
        for y in range(0, layer.height, 7):
            for x in range(0, layer.width, 7):
                pixel = layer.getpixel((x, y))
                if pixel[3] < 253:
                    continue
                under = backdrop.getpixel((x + offset[0], y + offset[1]))
                assert all(abs(pixel[i] - under[i]) <= 2 for i in range(3)), (name, x, y)
                samples += 1
        assert samples > 10, "no visible depth samples for " + name
    print("reference field, actor exclusions, right edge and three aligned masks: PASS")


def check_props():
    geometry = json.loads(Path("tests/fixtures/painted_prop_geometry.json").read_text())["props"]
    assert DETAIL_FACTOR == 3
    with tempfile.TemporaryDirectory(prefix="wic-detail-props-") as temp:
        directory = Path(temp)
        world.PROPS = directory
        reference_props.OUT = directory
        painted_props.OUT = directory
        world.props()
        reference_props.main()
        painted_props.main()
        outputs = {p.stem: p for p in directory.glob("*.png")}
        assert set(outputs) == set(geometry), "painted prop set changed"
        for key, spec in geometry.items():
            with Image.open(outputs[key]) as image:
                expected_size = tuple(n * DETAIL_FACTOR for n in spec["size"])
                expected_bounds = tuple(n * DETAIL_FACTOR for n in spec["bounds"])
                assert image.size == expected_size, (key, image.size, expected_size)
                assert image.getchannel("A").getbbox() == expected_bounds, key + " changed apparent bounds"
                assert same_pixels(image, Path("art/props_painted") / (key + ".png")), key + " differs from builder"
        for region in ("elah", "bethlehem"):
            data = json.loads(Path("data/regions/" + region + ".json").read_text())
            missing = {p["type"] for p in data["props"]} - set(outputs)
            assert not missing, "%s has missing painted props: %s" % (region, sorted(missing))
        with Image.open(outputs["fire"]) as fire:
            width = fire.width // 2
            first = fire.crop((0, 0, width, fire.height))
            second = fire.crop((width, 0, fire.width, fire.height))
            assert first.getchannel("A").tobytes() == second.getchannel("A").tobytes()
            assert ImageChops.difference(first.convert("RGB"), second.convert("RGB")).getbbox() is not None
    print("20 source-rebuilt props, legacy bounds, animation and both map inventories: PASS")


def check_continuations():
    for region in ("elah", "bethlehem"):
        image, mask = continuation.continuation(region)
        path = Path("art/scenes_painted/world_" + region + "_reference.png")
        assert same_pixels(image, path), "non-reproducible ground: " + region
        data = json.loads(Path("data/regions/" + region + ".json").read_text())
        base = Image.open(Path("art/scenes_painted/world_" + region + ".png")).convert("RGB")
        assert image.size == base.size
        water = world.tile_mask(data["grid"], "~=", image.size, 0)
        assert ImageChops.multiply(mask, water).getbbox() is None, "meadow changed a crossing: " + region
        diff = ImageChops.difference(image, base).convert("L")
        assert ImageChops.multiply(diff, water).getbbox() is None, "water pixels changed: " + region
        assert mask.getbbox() is not None, "missing meadow continuation: " + region
    print("two map-aligned meadow continuations and untouched water: PASS")


def check_paving_join():
    # An identical overlap must reconstruct the complete image exactly; odd
    # widths must not leave a black final column, and bad inputs fail closed.
    for width in (25, 26):
        full = Image.new("RGB", (width, 11))
        pixels = full.load()
        for y in range(full.height):
            for x in range(width):
                pixels[x, y] = ((x * 13 + y * 3) % 256,
                                (x * 7 + y * 11) % 256, (x * 5 + y * 17) % 256)
        first = full.crop((0, 0, 17, full.height))
        second = full.crop((12, 0, width, full.height))
        joined = refined_ground.join_painted_sections(first, second, 5)
        assert joined.size == full.size and joined.tobytes() == full.tobytes(), "paving join lost pixels"
    try:
        refined_ground.join_painted_sections(Image.new("RGB", (8, 8)), Image.new("RGB", (8, 9)), 4)
    except ValueError:
        pass
    else:
        raise AssertionError("paving join accepted incompatible image heights")


def check_refinement():
    check_paving_join()
    fig = refined_props.build()
    assert fig.size == (96, 144) and fig.getchannel("A").getbbox() == (0, 46, 96, 144)
    assert same_pixels(fig, refined_props.OUTPUT), "non-reproducible refined fig"
    visible_key = [(r, g, b) for r, g, b, a in fig.get_flattened_data()
                   if a > 200 and r > 140 and b > 140 and g < 70]
    assert not visible_key, "visible magenta key in refined fig"
    for region in ("elah", "bethlehem"):
        pieces, masks = refined_ground.build(region)
        raw = json.loads(Path("data/regions/" + region + ".json").read_text())
        width = len(raw["grid"][0]) * refined_ground.TILE
        height = len(raw["grid"]) * refined_ground.TILE
        assert width == 2048 and height in (2048, 3072)
        image = Image.new("RGB", (width, height))
        for name, y in (("top", 0), ("bottom", height // 2)):
            piece = pieces[name]
            path = Path(f"art/scenes_painted/world_{region}_refined_{name}.png")
            assert piece.size == (width, height // 2)
            assert max(piece.size) <= 2048, "texture exceeds older phone WebGL limits"
            assert same_pixels(piece, path), "non-reproducible refined ground: " + str(path)
            image.paste(piece, (0, y))
        # A discontinuity at the top/bottom texture join would create an
        # anomalous full-width jump. This is only a regression indicator; the
        # actual Godot frames must also be checked for rendered seams.
        middle = height // 2
        neighbours = [row_boundary_difference(image, y)
                      for y in range(middle - 30, middle + 31) if y != middle]
        join = row_boundary_difference(image, middle)
        assert join < 2.2 * statistics.median(neighbours) + 1.0, region + " texture join discontinuity"
        # Compare independently against the original reference, not the
        # builder's sharpened land base: otherwise sharpening the protected
        # shoreline could make both output and expected pixels wrong together.
        reference = Image.open(Path("art/scenes_painted") /
                               ("world_" + region + "_reference.png")).convert("RGB")
        reference = reference.resize((width, height), Image.Resampling.LANCZOS)
        assert reference.tobytes() == masks["reference_base"].tobytes()
        # Use the max across RGB channels, not grayscale, which can round a
        # one-channel difference to zero. Both halves are reassembled here.
        red, green, blue = ImageChops.difference(image, reference).split()
        diff = ImageChops.lighter(ImageChops.lighter(red, green), blue)
        water = refined_ground.material_mask(raw["grid"], "~=e", (width, height))
        shore_core = refined_ground.material_mask(raw["grid"], "~=e", (width, height), padding=24)
        assert masks["water"].tobytes() == water.tobytes(), region + " changed protected materials"
        assert masks["shore_core"].tobytes() == shore_core.tobytes(), region + " changed shoreline core"

        # The original ford mask also covers dry grass well inland. Only that
        # grass is allowed to change: independently protect the entire visible
        # river/shore band inside the crossing, plus the padded water/reed tiles.
        if region == "elah":
            assert water.getbbox() is not None and masks["water_band"] == (398 * 4, 462 * 4)
            assert ImageChops.subtract(shore_core, water).getbbox() is not None
            band = Image.new("L", (width, height))
            ImageDraw.Draw(band).rectangle((0, 398 * 4, width - 1, 462 * 4 - 1), fill=255)
            crossing = refined_ground.material_mask(raw["grid"], "=", (width, height), padding=24)
            outer_water = refined_ground.material_mask(raw["grid"], "~e", (width, height), padding=24)
            protected = ImageChops.lighter(outer_water, ImageChops.multiply(crossing, band))
            # The visible water is now deliberately repainted in the ground's
            # painterly language (river_detail.py). The bank, reeds, the ford's
            # pale approach and every sunlit stone must still be pixel-identical
            # to the reference: only pixels inside the painted-water mask may
            # differ, and that mask is confined to the reviewed brook band.
            painted = masks["painted_water"].point(lambda value: 255 if value else 0)
            assert painted.getbbox() is not None, "missing painterly water surface"
            # The stones standing in the repainted water get their own pass
            # (river_detail._stone_detail): their interiors may change, the
            # three-pixel ring that beds them in the stream may not.
            stones = masks["stone_detail"].point(lambda value: 255 if value else 0)
            assert stones.getbbox() is not None, "missing stone detail pass"
            assert ImageChops.multiply(stones, painted).getbbox() is None, \
                "the stone pass overlapped the water"
            shore_without_water = ImageChops.subtract(
                protected, ImageChops.lighter(painted, stones))
            assert ImageChops.multiply(diff, shore_without_water).getbbox() is None, \
                "changed bank, reeds or stone pixels beside the water"
            assert ImageChops.multiply(diff, painted).getbbox() is not None, \
                "painterly water pass changed nothing"
            confined = Image.new("L", (width, height))
            band_top = river_detail.WATER_ROWS[0] * 64 - 48
            band_bottom = (river_detail.WATER_ROWS[-1] + 1) * 64 + 57
            ImageDraw.Draw(confined).rectangle((0, band_top, width - 1, band_bottom), fill=255)
            assert ImageChops.subtract(painted, confined).getbbox() is None, \
                "water repaint escaped the brook band"
            for x, y in ((800, 1660), (790, 1715), (790, 1780), (1240, 1730), (1300, 1640)):
                assert painted.getpixel((x, y)) == 0, "a sunlit stone was repainted as water"
                # The stone pass may sharpen these pixels, but they must still
                # read as warm stone rather than as water.
                red_, green_, blue_ = image.getpixel((x, y))
                assert red_ > blue_ + 30, "a sunlit stone lost its stone colour"
            for x, y in ((1900, 1700), (300, 1750), (600, 1700), (1050, 1720)):
                assert painted.getpixel((x, y)) == 255, "water sample was skipped"
            assert masks["inland"].getbbox() is not None, "missing inland bank transition"
            approach = masks["approach"]
            assert approach.getpixel((16 * refined_ground.TILE, 470 * 4)) > 128, "missing ford path approach"
            assert ImageChops.subtract(approach, masks["inland"]).getbbox() is None
            assert approach.crop((0, 0, width, 462 * 4)).getbbox() is None, "approach entered the protected band"
            assert ImageChops.multiply(approach, painted).getbbox() is None, \
                "ford approach was repainted as water"
            mutated = list(raw["grid"])
            mutated[24] = mutated[24][:12] + "." + mutated[24][13:]
            fallback, bounds = refined_ground.crossing_inland_mask(mutated, (width, height))
            assert fallback.getbbox() is None and bounds is None, "changed river grid must fail closed"
            fallback, bounds = refined_ground.crossing_inland_mask(raw["grid"], (width, height), "0" * 64)
            assert fallback.getbbox() is None and bounds is None, "changed shore painting must fail closed"
            mutated = list(raw["grid"])
            mutated[30] = mutated[30].replace(",", ".")
            fallback = refined_ground.crossing_south_approach(mutated, (width, height), masks["inland"],
                                                              masks["water_band"])
            assert fallback.getbbox() is None, "changed ford path must fail closed"
            # The water pass is tied to this grid and texture size; any other
            # layout keeps the old water instead of a guessed repaint.
            assert river_detail.supports(raw["grid"], (width, height))
            changed_grid = list(raw["grid"])
            changed_grid[26] = changed_grid[26].replace("~", ".")
            assert not river_detail.supports(changed_grid, (width, height))
            assert not river_detail.supports(raw["grid"], (1024, 1536))
        else:
            assert masks["inland"].getbbox() is None and masks["water_band"] is None
            assert masks["approach"].getbbox() is None

        # Everywhere else in the old protected shoreline core remains exact.
        changed_inland = masks["inland"].point(lambda value: 255 if value else 0)
        still_protected = ImageChops.subtract(shore_core, changed_inland)
        still_protected = ImageChops.subtract(
            still_protected, masks["painted_water"].point(lambda value: 255 if value else 0))
        still_protected = ImageChops.subtract(
            still_protected, masks["stone_detail"].point(lambda value: 255 if value else 0))
        assert ImageChops.multiply(diff, still_protected).getbbox() is None, region + " cut into protected shoreline"

        # Verify genuinely new grass/soil/paving, and forbid changes outside
        # those material masks. This also compares against the prior public
        # ground, not merely the older reference bitmap.
        red, green, blue = ImageChops.difference(image, masks["baseline"]).split()
        new_diff = ImageChops.lighter(ImageChops.lighter(red, green), blue)
        for name in ("updated_grass", "rocky", "soil"):
            assert ImageChops.multiply(new_diff, masks[name]).getbbox() is not None, region + " lacks " + name
        # Rocky tiles are scattered throughout both regions; they must not
        # retain isolated blurry squares or bleed onto the protected shore.
        shore = refined_ground.material_mask(raw["grid"], "~=e", (width, height), feather=20, padding=40)
        safe = ImageChops.invert(ImageChops.lighter(shore_core, shore))
        expected_rocky = ImageChops.multiply(
            refined_ground.material_mask(raw["grid"], "r", (width, height), feather=18), safe)
        assert masks["rocky"].tobytes() == expected_rocky.tobytes(), region + " rocky mask changed"
        for y, row in enumerate(raw["grid"]):
            for x, char in enumerate(row):
                if char != "r":
                    continue
                box = (x * refined_ground.TILE, y * refined_ground.TILE,
                       (x + 1) * refined_ground.TILE, (y + 1) * refined_ground.TILE)
                if safe.crop(box).getbbox() is not None:
                    assert ImageChops.multiply(new_diff.crop(box), masks["rocky"].crop(box)).getbbox() is not None, \
                        f"{region} rocky ground ({x}, {y}) lacks detail"
        if region == "bethlehem":
            assert ImageChops.multiply(new_diff, masks["paving"]).getbbox() is not None, "missing detailed paving"
        allowed = ImageChops.lighter(ImageChops.lighter(masks["updated_grass"], masks["soil"]), masks["paving"])
        allowed = ImageChops.lighter(allowed, masks["painted_water"])
        allowed = ImageChops.lighter(allowed, masks["stone_detail"])
        allowed = allowed.point(lambda value: 255 if value else 0)
        assert ImageChops.multiply(new_diff, ImageChops.invert(allowed)).getbbox() is None, \
            region + " changed outside the ground material masks"
        expected_crops = ((width + 223) // 224) * ((height + 223) // 224)
        assert masks["grass_crops"] == expected_crops and masks["soil_crops"] == expected_crops, \
            region + " reused an identical source crop"

        # Ground-only crops from two earlier published builds anchor the
        # palette and catch a return to low detail or excessive contrast. Edge
        # energy alone cannot establish artistic quality or absence of shimmer.
        part, box = {"elah": ("bottom", (700, 950, 1000, 1250)),
                     "bethlehem": ("top", (100, 400, 400, 700))}[region]
        old = Image.open(Path("tests/fixtures/ground_clarity") /
                         (region + "-published.png")).convert("RGB")
        before = Image.open(Path("tests/fixtures/ground_materials") /
                            (region + "-f2afae9.png")).convert("RGB")
        offset_y = 0 if part == "top" else height // 2
        previous = masks["baseline"].crop((box[0], box[1] + offset_y, box[2], box[3] + offset_y))
        assert previous.tobytes() == before.tobytes(), region + " previous public ground changed"
        after = pieces[part].crop(box)
        previous_edge, edge = adjacent_luma_difference(before), adjacent_luma_difference(after)
        assert 1.15 * previous_edge < edge < 1.75 * previous_edge, \
            f"{region} detail regression: before {previous_edge:.2f}, after {edge:.2f}"
        earlier_edge = adjacent_luma_difference(old)
        assert 1.75 * earlier_edge < edge < 2.75 * earlier_edge, region + " extreme edge contrast"
        old_mean, new_mean = ImageStat.Stat(old).mean, ImageStat.Stat(after).mean
        assert max(abs(a - b) for a, b in zip(old_mean, new_mean)) < 3.0, \
            region + " ground palette shifted in clarity crop"
        mean_change = sum(ImageStat.Stat(ImageChops.difference(before, after)).mean) / 3
        assert 5.0 < mean_change < 35.0, region + " ground detail changed too little or too much"
    print("refined fig, tall trees and rebuilt grass, earth, paving and painterly water with protected bank: PASS")


def check_tall_trees():
    """The mature trees must be reproducible, foot-anchored and key-clean.

    The visible-height contract itself lives in the runtime test
    (tests/painted_world.gd) where the real Sprite2D scales exist; here the
    authored canvases and mattes are checked against the committed files.
    """
    outputs = tall_trees.build()
    # The canvases are grown from the overworld's own tree paintings, so their
    # width follows each source's aspect; the height is what the runtime scales
    # against, and it must stay 276/272 for the 82/78 world-pixel targets.
    expected = {"olive_tree_tall.png": 276, "fig_tree_tall.png": 272}
    assert set(outputs) == set(expected)
    for name, image in outputs.items():
        assert image.mode == "RGBA" and image.height == expected[name], name
        assert 150 <= image.width <= 240, name + " canvas width is off: %d" % image.width
        assert same_pixels(image, Path("art/props_painted") / name), "non-reproducible tree: " + name
        bounds = image.getchannel("A").getbbox()
        assert bounds is not None, "empty tree: " + name
        assert bounds[3] == image.height, "tree lost its trunk-base anchor: " + name
        assert bounds[1] == 0 and bounds[0] <= 12 and bounds[2] >= image.width - 12, \
            "tree canvas cropped the canopy: " + name
        visible_key = [(r, g, b) for r, g, b, a in image.get_flattened_data()
                       if a > 200 and r > 140 and b > 140 and g < 70]
        assert not visible_key, "visible magenta key in " + name
    olive = outputs["olive_tree_tall.png"]
    fig = outputs["fig_tree_tall.png"]
    # Taller than wide: the old olive's alpha was 141x147 (about square), which
    # is exactly why it read as a big shrub. A mature tree must be clearly
    # upright even before the runtime scale is applied.
    for name, image in (("olive", olive), ("fig", fig)):
        bounds = image.getchannel("A").getbbox()
        ratio = (bounds[3] - bounds[1]) / (bounds[2] - bounds[0])
        assert ratio > 1.25, name + " tree is not upright: %.2f" % ratio
        # Grown from the accepted prop paintings: no pixel may be a new colour
        # family, so the canopy must stay in the world's warm olive range and
        # the trunk in its bark range.
        foliage = 0
        bark = 0
        for r, g, b, a in image.get_flattened_data():
            if a < 200:
                continue
            if 40 <= r <= 140 and g >= r and b < g * 0.8:
                foliage += 1
            elif r > g > b and r - b > 30:
                bark += 1
        assert foliage > 2000 and bark > 800, name + " lost the world's tree colours"
    print("two taller, trunk-anchored olive and fig canvases with clean mattes: PASS")


def check_people():
    outputs = dict(characters.build_all())
    actual = {p.name for p in Path("art/characters_reference").glob("*.png")}
    assert len(outputs) == 108 and set(outputs) == actual, "unexpected character output set"
    expected_views = {
        actor: {"front", "profile", "back"}
        for actor in ("pilgrim", "corin", "elder", "woman", "boy", "samuel", "jesse", "eliab", "king")
    }
    assert characters.SEATED_HEIGHT == 76
    assert {actor: set(views) for actor, views in characters.ACTORS.items()} == expected_views
    for actor, views in characters.ACTORS.items():
        for pose, source in views.items():
            assert source == f"reference_{actor}_{pose}.png", "unexpected source for " + actor + "/" + pose
    for name, image in outputs.items():
        assert image.mode == "RGBA" and image.size == (70, 98), name
        assert same_pixels(image, Path("art/characters_reference") / name), "non-reproducible: " + name
        if name.endswith("_idle.png"):
            assert image.getchannel("A").getbbox() is not None, "empty actor: " + name
            visible_key = [(r, g, b) for r, g, b, a in image.get_flattened_data()
                           if a > 200 and r > 140 and b > 140 and g < 70]
            assert not visible_key, "visible magenta key in " + name
            prefix = name[:-len("idle.png")]
            parts = [outputs[prefix + part + ".png"] for part in ("body", "boot_left", "boot_right")]
            alpha = [part.getchannel("A") for part in parts]
            if name.startswith("samuel_"):
                bounds = image.getchannel("A").getbbox()
                assert bounds[1] >= 98 - characters.SEATED_HEIGHT and bounds[3] == 98, name
                assert alpha[1].getbbox() is None and alpha[2].getbbox() is None, "seated stool was split: " + name
                assert alpha[0].tobytes() == image.getchannel("A").tobytes(), "seated body changed: " + name
            assert all(ImageChops.multiply(alpha[a], alpha[b]).getbbox() is None
                       for a, b in ((0, 1), (0, 2), (1, 2))), "overlapping layers: " + name
            combined = ImageChops.add(ImageChops.add(alpha[0], alpha[1]), alpha[2])
            assert combined.tobytes() == image.getchannel("A").tobytes(), "missing layer pixels: " + name
            for part, part_alpha in zip(parts, alpha):
                difference = ImageChops.difference(part.convert("RGB"), image.convert("RGB"))
                for channel in difference.split():
                    assert ImageChops.multiply(channel, part_alpha).getbbox() is None, "layer colour: " + name
    print("27 foot-anchored actor views, 108 reproducible layers and clean mattes: PASS")


def check_variants():
    expected = {"tent_camp_a.png": (156, 108), "tent_camp_b.png": (156, 108),
                "tent_royal_open.png": (252, 210), "house_reference_alt.png": (198, 249),
                "brook_stone_a.png": (54, 36), "brook_stone_b.png": (54, 36),
                "brook_stone_c.png": (54, 36)}
    outputs = dict(variants.build_all())
    assert set(outputs) == set(expected)
    for name, image in outputs.items():
        assert image.mode == "RGBA" and image.size == expected[name]
        assert same_pixels(image, Path("art/props_painted") / name), "non-reproducible: " + name
        bounds = image.getchannel("A").getbbox()
        assert bounds is not None, "empty variant: " + name
        if name.startswith("tent_"):
            assert bounds[3] >= image.height - 2, "tent foot anchor changed: " + name
        if name == "tent_royal_open.png":
            # The rear curtain ends at Saul's authored foot depth, leaving the
            # ground and his shadow visible while the tied curtains remain.
            assert image.getpixel((126, 149))[3] > 200
            assert image.getpixel((126, 150))[3] == 0
            assert image.getpixel((10, 200))[3] > 200
            assert image.getpixel((240, 200))[3] > 200
        if name.startswith("house_"):
            assert bounds[3] == 249, "house foot anchor changed: " + name
    print("seven cosmetic tent, house and brook-stone variants: PASS")


if __name__ == "__main__":
    check_field()
    check_props()
    check_continuations()
    check_refinement()
    check_tall_trees()
    check_people()
    check_variants()
