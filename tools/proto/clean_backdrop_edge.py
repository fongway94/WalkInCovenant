#!/usr/bin/env python3
"""Remove the reference viewer's right-hand strip from the prototype backdrop.

Only the rightmost 40 pixels of the edited 1440x666 painting are replaced.
An adjacent reflected edge is blended into another nearby grass/wall sample so
there is no hard boundary or obvious mirror line. This is a small, approximate
paint-over, not new authored scenery. Both samples lie to the left of the edit,
so applying it again is deterministic and cannot alter the rest of the field.

    python3 tools/proto/clean_backdrop_edge.py          # update the image
    python3 tools/proto/clean_backdrop_edge.py --check  # check the committed PNG
"""
import argparse
from pathlib import Path

from PIL import Image, ImageChops, ImageOps

BACKDROP = Path("art/proto/shepherd_field_empty.png")
SIZE = (1440, 666)
START = 1400
WIDTH = 40


def clean_edge(source: Image.Image) -> Image.Image:
    if source.size != SIZE or source.mode != "RGB":
        raise ValueError("expected an RGB 1440x666 prototype backdrop")
    height = source.height
    # The first sample meets the old edge continuously; the second avoids a
    # conspicuous symmetric motif as the strip approaches the outside edge.
    reflected = ImageOps.mirror(source.crop((1360, 0, 1400, height)))
    nearby = source.crop((1320, 0, 1360, height))
    ramp = Image.new("L", (WIDTH, 1))
    for x in range(WIDTH):
        t = min(1.0, x / 12.0)
        ramp.putpixel((x, 0), round(255 * t * t * (3.0 - 2.0 * t)))
    patch = Image.composite(nearby, reflected, ramp.resize((WIDTH, height)))
    result = source.copy()
    result.paste(patch, (START, 0))
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if the backdrop edge is not cleaned")
    args = parser.parse_args()
    with Image.open(BACKDROP) as original:
        image = original.copy()
    cleaned = clean_edge(image)
    if args.check:
        if ImageChops.difference(image, cleaned).getbbox() is not None:
            raise SystemExit("prototype backdrop edge is not cleaned")
        print("prototype backdrop edge: PASS")
    else:
        cleaned.save(BACKDROP)
        print("cleaned %s, x=%d..%d" % (BACKDROP, START, SIZE[0] - 1))


if __name__ == "__main__":
    main()
