#!/usr/bin/env python3
"""Check reproducibility, field masking and prop geometry; not an art review.

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
from prop_detail import DETAIL_FACTOR  # noqa: E402


def same_pixels(generated, path):
    with Image.open(path) as saved:
        return (generated.mode == saved.mode and generated.size == saved.size
                and generated.tobytes() == saved.tobytes())


def source_point_to_field(x, y):
    # Forward registration, for checking that every actor exclusion survives.
    denominator = 0.0000000393956484 * x - 0.000000903656387 * y + 1.0
    return (round((1.95901326 * x - 0.000350231808 * y + 4.92095688) / denominator),
            round((0.0000507730048 * x + 1.96166493 * y - 75.0694105) / denominator))


def check_field():
    digest = hashlib.sha256(field.REFERENCE.read_bytes()).hexdigest()
    assert digest == "7529dccc897638aeba86f33af8e5fa3d069ce5d92edeb80de4369f272a69a3ca"
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


if __name__ == "__main__":
    check_field()
    check_props()
