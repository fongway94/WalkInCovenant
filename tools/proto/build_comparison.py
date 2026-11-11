#!/usr/bin/env python3
"""Create an honest reference / baseline / current CI visual review image.

Only the user's approved image and decoded Godot frames are used. The top row
shows the full reference, the baseline's original (much tighter) camera, and
the current overview at equal pane sizes. The bottom row shows an approximately
matched patch of the painted field, so artistic details can be compared without
pretending that the old and new cameras had the same framing. The approved and
AI-edited backdrops are not pixel-identical, and actors occupy different places.

Usage: python3 tools/proto/build_comparison.py BASELINE.webp CURRENT.webp \
           OUTPUT.png --baseline-run ID --current-run ID
"""
import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps

REFERENCE = Path("docs/art-reset/user_selected_reference.png")
PANE = (640, 360)
# Background landmark registration of baseline run 42942725993 against the
# widened camera: new overview crop (144,153)-(496,351) covers approximately
# the same 640x360 world-pixel area that the baseline camera recorded.
NEW_DETAIL = (144, 153, 496, 351)
# Approximate corresponding approved-reference patch. The edited backdrop is
# ~2.1145 times as wide as the source and is not an exact geometric scaling.
REFERENCE_DETAIL = (180, 137, 482, 307)


def font(size):
    for path in ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
                 "/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf"):
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def fit(image):
    # No distortion: the 681x348 original gets narrow dark letterbox bars.
    return ImageOps.pad(image.convert("RGB"), PANE, method=Image.Resampling.LANCZOS,
                        color=(20, 23, 24))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline")
    parser.add_argument("current")
    parser.add_argument("output")
    parser.add_argument("--baseline-run", required=True)
    parser.add_argument("--current-run", required=True)
    args = parser.parse_args()
    reference = Image.open(REFERENCE).convert("RGB")
    old = Image.open(args.baseline).convert("RGB")
    new = Image.open(args.current).convert("RGB")
    if old.size != PANE or new.size != PANE:
        raise SystemExit("expected decoded 640x360 Godot frames")

    gap = 16
    x_positions = [gap, gap * 2 + PANE[0], gap * 3 + PANE[0] * 2]
    width = 3 * PANE[0] + 4 * gap
    canvas = Image.new("RGB", (width, 860), (20, 23, 24))
    draw = ImageDraw.Draw(canvas)
    title_font, label_font, small_font = font(20), font(15), font(13)
    text, quiet = (239, 230, 205), (186, 190, 184)
    draw.text((gap, 12), "SHEPHERD FIELD  /  REFERENCE AND REAL GODOT CI RENDERS", font=title_font, fill=text)
    labels = ["APPROVED REFERENCE  /  full source",
              "PREVIOUS PROTOTYPE  /  CI " + args.baseline_run,
              "IMPROVED PROTOTYPE  /  CI " + args.current_run]
    for x, label in zip(x_positions, labels):
        draw.text((x, 48), label, font=label_font, fill=text)
    top = [fit(reference), old, new]
    for x, im in zip(x_positions, top):
        canvas.paste(im, (x, 70))
    draw.text((gap, 438), "OVERVIEW: previous camera is substantially tighter; the full reference includes its viewer arrow and right strip.",
              font=small_font, fill=quiet)
    draw.text((gap, 460), "MATCHED FIELD DETAIL: approximate shared background area; figures are at different positions and the edited backdrop is not identical.",
              font=small_font, fill=text)
    detail = [reference.crop(REFERENCE_DETAIL).resize(PANE, Image.Resampling.LANCZOS),
              old,
              new.crop(NEW_DETAIL).resize(PANE, Image.Resampling.LANCZOS)]
    for x, im in zip(x_positions, detail):
        canvas.paste(im, (x, 482))
    draw.text((gap, 846), "Top and bottom right: actual CI frames (the detail is enlarged); no concept image or parity claim.",
              font=small_font, fill=quiet)
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output, optimize=True)
    print("wrote", output, canvas.size)


if __name__ == "__main__":
    main()
