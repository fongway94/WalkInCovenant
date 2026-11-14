#!/usr/bin/env python3
"""Check reproducibility and the deliberately limited sheep-stride edits.

This validates source textures, not the Godot renderer. The visual harness
separately checks the changing poses, idle, blocking and hopping in-scene.
Run from the repository root; requires Pillow.
"""
from pathlib import Path
import sys
import tempfile

from PIL import Image, ImageChops

sys.path.insert(0, str(Path("tools/proto").resolve()))
import extract_reference_sprites as extract  # noqa: E402


def visible(image):
    # Ignore RGB under zero alpha: only compare what would be seen on a field.
    background = Image.new("RGBA", image.size, (80, 99, 56, 255))
    background.alpha_composite(image.convert("RGBA"))
    return background.convert("RGB")


def main():
    checked = Path("art/proto/sprites")
    with tempfile.TemporaryDirectory() as temporary:
        extract.OUTPUT = Path(temporary)
        extract.main()
        for generated in extract.OUTPUT.glob("*.png"):
            expected = checked / generated.name
            if not expected.is_file():
                raise AssertionError("missing generated texture: " + str(expected))
            with Image.open(generated) as actual, Image.open(expected) as original:
                if actual.size != original.size or actual.convert("RGBA").tobytes() != original.convert("RGBA").tobytes():
                    raise AssertionError("texture differs from the reference pipeline: " + str(expected))
        for variant, cutoff_y in (("a", 63), ("b", 57)):
            base = checked / ("sheep_reference_" + variant)
            with Image.open(str(base) + ".png") as source:
                still = visible(source)
            strides = []
            for side in ("a", "b"):
                with Image.open(str(base) + "_stride_" + side + ".png") as source:
                    pose = visible(source)
                if pose.size != still.size:
                    raise AssertionError("a stride changed its canvas/anchor")
                bounds = ImageChops.difference(still, pose).getbbox()
                if bounds is None or bounds[1] < cutoff_y:
                    raise AssertionError("stride must change only the feet: " + variant + "/" + side)
                strides.append(pose)
                print("sheep %s stride %s visible change bounds=%s" % (variant, side, bounds))
            if ImageChops.difference(*strides).getbbox() is None:
                raise AssertionError("the two stride poses are identical: " + variant)
    print("reference sheep texture checks: PASS")


if __name__ == "__main__":
    main()
