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

from PIL import Image, ImageChops

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
from prop_detail import DETAIL_FACTOR  # noqa: E402


def same_pixels(generated, path):
    with Image.open(path) as saved:
        return (generated.mode == saved.mode and generated.size == saved.size
                and generated.tobytes() == saved.tobytes())


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
    check_people()
    check_variants()
