#!/usr/bin/env python3
"""Compare the reference and two real staged Godot sheep diagnostics.

The CI diagnostic is a 640x360 sheet of four real viewport crops: sheep
variants A/B across and their opposing stride extremes down. The comparison
uses the upper row (same stride) from each run, with contextual reference
crops. It is a visual review aid, not a gameplay frame or a performance test.
"""
import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REFERENCE = Path("docs/art-reset/user_selected_reference.png")
PANE = (480, 270)
REF_CROPS = ((391, 169, 455, 205), (356, 137, 420, 173))


def font(size):
    for name in ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
                 "/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf"):
        if Path(name).is_file():
            return ImageFont.truetype(name, size)
    return ImageFont.load_default()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", help="decoded proto_08_sheep_gait.webp before the contact change")
    parser.add_argument("after", help="decoded proto_08_sheep_gait.webp after the contact change")
    parser.add_argument("output")
    parser.add_argument("--before-run", required=True)
    parser.add_argument("--after-run", required=True)
    args = parser.parse_args()
    reference = Image.open(REFERENCE).convert("RGB")
    before = Image.open(args.before).convert("RGB")
    after = Image.open(args.after).convert("RGB")
    if before.size != (640, 360) or after.size != before.size:
        raise SystemExit("expected two decoded 640x360 staged gait diagnostics")

    gap = 16
    xs = [gap + i * (PANE[0] + gap) for i in range(3)]
    image = Image.new("RGB", (PANE[0] * 3 + gap * 4, 730), (20, 23, 24))
    draw = ImageDraw.Draw(image)
    text, quiet = (239, 230, 205), (186, 190, 184)
    draw.text((gap, 12), "SHEEP CONTACT  /  REFERENCE AND REAL GODOT CROPS", font=font(20), fill=text)
    labels = ("APPROVED REFERENCE / source crop", "BEFORE / CI " + args.before_run,
              "AFTER / CI " + args.after_run)
    for x, label in zip(xs, labels):
        draw.text((x, 48), label, font=font(14), fill=text)
    for row in range(2):
        y = 87 + row * 300
        draw.text((gap, y - 16), "Variant " + ("A" if row == 0 else "B") + " / matched CI stride pose",
                  font=font(12), fill=quiet)
        samples = [reference.crop(REF_CROPS[row]),
                   before.crop((row * 320, 0, (row + 1) * 320, 180)),
                   after.crop((row * 320, 0, (row + 1) * 320, 180))]
        for x, sample in zip(xs, samples):
            image.paste(sample.resize(PANE, Image.Resampling.NEAREST), (x, y))
    draw.text((gap, 697), "Reference/backdrop framing differs. CI panes are staged, enlarged viewport crops; they are not gameplay stills.",
              font=font(13), fill=quiet)
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    image.save(output, optimize=True)
    print("wrote", output, image.size)


if __name__ == "__main__":
    main()
