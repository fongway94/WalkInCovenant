#!/usr/bin/env python3
"""Build compact, foot-anchored people for the sunset-reference art direction.

Each of the witness, Corin, elder, woman, boy, Samuel, Jesse, Eliab and Saul
has individually generated front, right-facing and back sources. Samuel is
seated, matching his Bethlehem dialogue; his stool and figure remain one
stationary layer. The other feet are animated cutouts, not authored walking
frames. Left mirrors right. Independently generated angles require human review
for consistency.

The generated art is an interpretation of the reference, not a source from it.
The 70x98 canvases and bottom anchors preserve the runtime contract. Nothing
here changes actor positions, collision, navigation, story or saves. Requires
Pillow 13.0.0.
"""
from pathlib import Path
import argparse

from PIL import Image, ImageChops, ImageDraw

SRC = Path("tools/art/sources")
OUT = Path("art/characters_reference")
CANVAS = (70, 98)
# A seated figure must be shorter than a standing person but keep the same
# feet/stool ground anchor; HumanVisual.gd reports the same visible height.
SEATED_HEIGHT = 76

# Each view is a separate generated source. Fit its original aspect to the
# shared foot-anchored canvas; do not splice faces or costumes across angles.
ACTORS = {
    "pilgrim": {
        "front": "reference_pilgrim_front.png",
        "profile": "reference_pilgrim_profile.png",
        "back": "reference_pilgrim_back.png",
    },
    "corin": {
        "front": "reference_corin_front.png",
        "profile": "reference_corin_profile.png",
        "back": "reference_corin_back.png",
    },
    "elder": {
        "front": "reference_elder_front.png",
        "profile": "reference_elder_profile.png",
        "back": "reference_elder_back.png",
    },
    "woman": {
        "front": "reference_woman_front.png",
        "profile": "reference_woman_profile.png",
        "back": "reference_woman_back.png",
    },
    "boy": {
        "front": "reference_boy_front.png",
        "profile": "reference_boy_profile.png",
        "back": "reference_boy_back.png",
    },
    "samuel": {
        "front": "reference_samuel_front.png",
        "profile": "reference_samuel_profile.png",
        "back": "reference_samuel_back.png",
    },
    "jesse": {
        "front": "reference_jesse_front.png",
        "profile": "reference_jesse_profile.png",
        "back": "reference_jesse_back.png",
    },
    "eliab": {
        "front": "reference_eliab_front.png",
        "profile": "reference_eliab_profile.png",
        "back": "reference_eliab_back.png",
    },
    "king": {
        "front": "reference_king_front.png",
        "profile": "reference_king_profile.png",
        "back": "reference_king_back.png",
    },
}


def key_source(path):
    image = Image.open(path).convert("RGBA")
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            red, green, blue, alpha = pixels[x, y]
            # All sources are painted against magenta. Also remove dark key
            # spill, while retaining the warm browns of skin and clothing.
            key = min(red, blue)
            if key > 35 and green * 10 < key * 7 and abs(red - blue) < key * 1.4:
                pixels[x, y] = (0, 0, 0, 0)
    bounds = image.getchannel("A").getbbox()
    if bounds is None:
        raise ValueError("empty keyed source: " + str(path))
    return image.crop(bounds)


def fit_source(image, height=CANVAS[1]):
    if height < 2 or height > CANVAS[1] or height % 2:
        raise ValueError("unexpected actor height: " + str(height))
    half_height = height // 2
    width = round(image.width * half_height / image.height)
    if not 1 <= width <= CANVAS[0] // 2:
        raise ValueError("unexpected actor width: " + str(width))
    fitted = image.resize((width, half_height), Image.Resampling.LANCZOS)
    # The reference rig uses a two-pixel sampling grid. Preserve it consistently
    # across the views and let the engine scale the anchored canvas in world.
    fitted = fitted.resize((width * 2, height), Image.Resampling.NEAREST)
    canvas = Image.new("RGBA", CANVAS)
    canvas.alpha_composite(fitted, ((CANVAS[0] - fitted.width) // 2, CANVAS[1] - height))
    return canvas


def make_layers(image, actor, pose):
    alpha = image.getchannel("A")
    if actor == "samuel":
        # A seated NPC does not walk. Keep the stool and sandals together in a
        # single stationary layer rather than animating pieces of the chair.
        empty = image.copy()
        empty.putalpha(Image.new("L", CANVAS))
        return {"idle": image, "body": image.copy(),
                "boot_left": empty.copy(), "boot_right": empty.copy()}
    body_alpha = alpha.copy()
    outputs = {"idle": image}
    for name in ("left", "right"):
        selection = Image.new("L", CANVAS)
        draw = ImageDraw.Draw(selection)
        if pose == "profile":
            # Profiles show a single boot or overlapping boots. Never tear a
            # continuous side-on boot silhouette down the middle.
            if name == "left":
                draw.rectangle((0, 84, 69, 97), fill=255)
        elif name == "left":
            draw.rectangle((0, 84, 34, 97), fill=255)
        else:
            draw.rectangle((35, 84, 69, 97), fill=255)
        part_alpha = ImageChops.multiply(alpha, selection)
        part = image.copy()
        part.putalpha(part_alpha)
        outputs["boot_" + name] = part
        body_alpha = ImageChops.subtract(body_alpha, part_alpha)
    body = image.copy()
    body.putalpha(body_alpha)
    outputs["body"] = body
    return outputs


def build_all():
    poses = {}
    for actor, views in ACTORS.items():
        for pose, filename in views.items():
            height = SEATED_HEIGHT if actor == "samuel" else CANVAS[1]
            poses[actor, pose] = fit_source(key_source(SRC / filename), height)
    for (actor, pose), image in poses.items():
        for part, layer in make_layers(image, actor, pose).items():
            yield f"{actor}_{pose}_{part}.png", layer


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="compare outputs without overwriting")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    for name, image in build_all():
        path = OUT / name
        if args.check:
            with Image.open(path) as saved:
                if saved.mode != image.mode or saved.size != image.size or saved.tobytes() != image.tobytes():
                    raise SystemExit("non-reproducible character: " + str(path))
        else:
            image.save(path, optimize=True)
    print("verified" if args.check else "built", "compact character views in", OUT)


if __name__ == "__main__":
    main()
