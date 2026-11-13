#!/usr/bin/env python3
"""Check reproducibility, field masking, actors and prop geometry; not an art review.

Requires Pillow 13.0.0. Runs entirely on the committed source images and does
not touch game saves or overwrite any output textures.
"""
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile

from PIL import Image, ImageChops, ImageStat

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


def check_refinement():
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
        if region == "elah":
            assert water.getbbox() is not None, "Elah water mask is empty"
            assert ImageChops.subtract(shore_core, water).getbbox() is not None, \
                "Elah shoreline protection must extend beyond water tiles"
        assert ImageChops.multiply(diff, water).getbbox() is None, region + " changed water"
        assert ImageChops.multiply(diff, shore_core).getbbox() is None, region + " cut into shoreline"
        assert ImageChops.multiply(diff, masks["grass"]).getbbox() is not None, region + " lacks new meadow detail"
        assert ImageChops.multiply(diff, masks["path"]).getbbox() is not None, region + " lacks new path detail"

        # Fixed, ground-only crops from the previously published textures. This
        # numerical check catches a return to the blurred source processing, or
        # an extreme change in contrast/colour; it is not a substitute for
        # viewing actual frames or checking for shimmer while moving.
        part, box = {"elah": ("bottom", (700, 950, 1000, 1250)),
                     "bethlehem": ("top", (100, 400, 400, 700))}[region]
        before = Image.open(Path("tests/fixtures/ground_clarity") /
                            (region + "-published.png")).convert("RGB")
        after = pieces[part].crop(box)
        baseline_edge = adjacent_luma_difference(before)
        edge = adjacent_luma_difference(after)
        assert 1.25 * baseline_edge < edge < 1.95 * baseline_edge, \
            f"{region} clarity regression: before {baseline_edge:.2f}, after {edge:.2f}"
        old_mean, new_mean = ImageStat.Stat(before).mean, ImageStat.Stat(after).mean
        assert max(abs(a - b) for a, b in zip(old_mean, new_mean)) < 3.0, \
            region + " ground palette shifted in clarity crop"
    print("refined fig, clearer split ground, stable palettes and untouched water/shore: PASS")


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
    check_people()
    check_variants()
