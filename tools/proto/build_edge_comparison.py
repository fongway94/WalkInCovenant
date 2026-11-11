#!/usr/bin/env python3
"""Compare the prototype's right edge in two real, decoded Godot CI frames.

The two full views are displayed without compositing; the 2x details below are
cropped from the same frames. Sheep can move between runs. This is evidence of
one sampled camera position, not proof for every size or path.

    python3 tools/proto/build_edge_comparison.py BEFORE.webp AFTER.webp OUT.png \
        --before-run ID --after-run ID
"""
import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def font(size):
    for path in ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
                 "/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf"):
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before")
    parser.add_argument("after")
    parser.add_argument("output")
    parser.add_argument("--before-run", required=True)
    parser.add_argument("--after-run", required=True)
    args = parser.parse_args()
    images = [Image.open(path).convert("RGB") for path in (args.before, args.after)]
    if any(image.size != (640, 360) for image in images):
        raise SystemExit("expected two decoded 640x360 Godot frames")

    gap, width = 16, 1312
    canvas = Image.new("RGB", (width, 916), (20, 23, 24))
    draw = ImageDraw.Draw(canvas)
    text, quiet = (239, 230, 205), (186, 190, 184)
    draw.text((gap, 12), "SHEPHERD FIELD  /  RIGHT EDGE IN REAL GODOT CI RENDERS", font=font(20), fill=text)
    xs = [gap, gap * 2 + 640]
    labels = ["BEFORE  /  CI " + args.before_run, "AFTER  /  CI " + args.after_run]
    for x, label, image in zip(xs, labels, images):
        draw.text((x, 47), label, font=font(15), fill=text)
        canvas.paste(image, (x, 69))
    draw.text((gap, 441), "2x DETAILS: the reference-viewer strip was replaced with an approximate adjacent-texture paint-over.",
              font=font(13), fill=text)
    # Show the far-right quarter at 2x, excluding the HUD. No pixels are added
    # to the real frame itself; these are enlarged crops for review only.
    for x, image in zip(xs, images):
        detail = image.crop((480, 80, 640, 270)).resize((320, 380), Image.Resampling.NEAREST)
        canvas.paste(detail, (x + 160, 467))
    draw.text((gap, 871), "Same staged tree-front camera; sheep positions differ between runs. This is one sampled view, not a full traversal audit.",
              font=font(13), fill=quiet)
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output, optimize=True)
    print("wrote", output, canvas.size)


if __name__ == "__main__":
    main()
