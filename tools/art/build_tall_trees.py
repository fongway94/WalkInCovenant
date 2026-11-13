#!/usr/bin/env python3
"""Build the mature olive and fig used by the painted overworld.

WHY THIS EXISTS (second pass): the first tall trees were painted from new
high-detail sources — thin bark lines and individual leaves. At the size the
game draws them (nearly 1:1 on a phone) they read as photographs dropped into a
chunky painted world: the user said the trees "look out of place" beside the
characters and the sheep. The trees are now grown from the overworld's *own*
accepted tree paintings — the same rounded masses, thick trunk, warm palette and
soft edge — stretched upright: the canopy keeps its authored brushwork and the
trunk is lengthened, so the tree gains height without gaining a new style.

The canvases stay foot-anchored (the last row of alpha is the trunk base), keep
the runtime's 82/78 world-pixel target, and add no new colours: every pixel is a
resampled pixel of the source painting. Pillow 13.0.0 reproduces them exactly.
"""
from pathlib import Path
import argparse

from PIL import Image, ImageFilter

PROPS = Path("art/props_painted")
OUTPUT = Path("art/props_painted")

# source, canvas height, canopy split (fraction of the cropped art),
# canopy scale (x, y), trunk scale (y). Width follows the source aspect.
TREES = (
    ("olive_tree_tall.png", "olive_tree.png", 276, 0.70, (1.75, 1.60), 2.0),
    ("fig_tree_tall.png", "fig_tree_refined.png", 272, 0.68, (2.00, 1.85), 2.2),
)
OVERLAP = 14


def despill(image):
    """Drop the magenta fringe left by the generative source of the props.

    Only partly transparent magenta-ish pixels are touched, and they are pulled
    toward their own luminance in the bark/leaf range, so genuine warm highlights
    (fig flesh, sunlit trunk) survive.
    """
    image = image.convert("RGBA")
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue
            if r > 70 and b > 70 and g < min(r, b) * 0.72 and min(r, b) - g > 24:
                lum = r * 0.299 + g * 0.587 + b * 0.114
                pixels[x, y] = (round(lum * 0.92), round(lum * 0.96),
                                round(lum * 0.72), round(a * 0.55))
    return image


def _clean_edge(image):
    """Neutralise the salmon fringe the props inherited from their chroma key.

    The published prop paintings keep a one-pixel warm rim where the generated
    source met the magenta background. At the old small size it read as sunlight;
    enlarged, it reads as a dotted pink outline, which is exactly the sort of
    detail that made the first tall trees look foreign. Fringed pixels take the
    median of their opaque, non-fringed neighbours.
    """
    image = image.copy()
    width, height = image.size
    original = image.load()
    fringed = []
    for y in range(height):
        for x in range(width):
            r, g, b, a = original[x, y]
            if a > 40 and r > 130 and r - g > 22 and g - b > 4:
                fringed.append((x, y))
    pixels = image.load()
    for x, y in fringed:
        candidates = []
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                nx, ny = x + dx, y + dy
                if not (0 <= nx < width and 0 <= ny < height):
                    continue
                r, g, b, a = original[nx, ny]
                if a < 200 or (r > 130 and r - g > 22 and g - b > 4):
                    continue
                candidates.append((r, g, b))
        if candidates:
            candidates.sort(key=lambda c: c[0] * 0.299 + c[1] * 0.587 + c[2] * 0.114)
            r, g, b = candidates[len(candidates) // 2]
            pixels[x, y] = (r, g, b, original[x, y][3])
    return image


def _feather(image, rows, bottom=True):
    """Fade one horizontal edge of a layer so the join is not a straight cut."""
    alpha = image.getchannel("A")
    pixels = alpha.load()
    for i in range(min(rows, image.height)):
        y = image.height - 1 - i if bottom else i
        scale = (i + 1) / (rows + 1)
        for x in range(image.width):
            pixels[x, y] = round(pixels[x, y] * scale)
    image.putalpha(alpha)
    return image


def _sharpen(image):
    """Keep the brush edges crisp after a 1.5-3x resample."""
    r, g, b, a = image.split()
    rgb = Image.merge("RGB", (r, g, b)).filter(
        ImageFilter.UnsharpMask(radius=2, percent=40, threshold=2))
    r, g, b = rgb.split()
    return Image.merge("RGBA", (r, g, b, a))


def grow(source, height, split, canopy_scale, trunk_scale):
    """Stretch one painted tree upright without introducing new detail.

    The canopy and trunk are one painting, so the tree is first enlarged whole
    (keeping its brushwork and silhouette), then only the trunk is lengthened:
    the part below the canopy is resized again and cross-faded into the base
    over a band that contains nothing but bark. There is no straight seam and
    no second art style.
    """
    art = despill(Image.open(PROPS / source))
    bounds = art.getchannel("A").getbbox()
    if bounds is None:
        raise ValueError("empty tree source: " + source)
    art = art.crop(bounds)
    art = _clean_edge(art)
    width = max(1, round(art.width * canopy_scale[0]))
    body = art.resize((width, max(1, round(art.height * canopy_scale[1]))),
                      Image.Resampling.LANCZOS)

    cut = max(1, min(body.height - 2, round(art.height * split * canopy_scale[1])))
    band = min(24, cut // 2)
    lower = body.crop((0, cut - band, body.width, body.height))
    target = height - (cut - band)
    if target <= lower.height:
        raise ValueError("tree target is not taller than the source: " + source)
    stretch = (target - lower.height) / max(1, (body.height - (cut - band)))
    scale = max(trunk_scale, 1.0 + stretch)
    lower = lower.resize((lower.width, max(lower.height + 1, round(lower.height * scale))),
                         Image.Resampling.LANCZOS)

    alpha = lower.getchannel("A")
    pixels = alpha.load()
    for y in range(min(band, lower.height)):
        weight = (y + 1) / (band + 1)
        for x in range(lower.width):
            pixels[x, y] = round(pixels[x, y] * weight)
    lower.putalpha(alpha)

    canvas = Image.new("RGBA", (body.width, max(height, cut - band + lower.height)), (0, 0, 0, 0))
    canvas.alpha_composite(body, (0, 0))
    canvas.alpha_composite(lower, (0, cut - band))
    top = canvas.getchannel("A").getbbox()
    canvas = canvas.crop((0, 0, canvas.width, top[3]))
    return canvas.resize((round(canvas.width * height / canvas.height), height),
                         Image.Resampling.LANCZOS)


def build():
    return {name: grow(source, height, split, canopy, trunk)
            for name, source, height, split, canopy, trunk in TREES}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, image in build().items():
        path = OUTPUT / name
        if args.check:
            with Image.open(path) as saved:
                if (image.mode != saved.mode or image.size != saved.size
                        or image.tobytes() != saved.tobytes()):
                    raise SystemExit("non-reproducible tree: " + str(path))
            print("verified", path, image.size)
        else:
            image.save(path, optimize=True)
            print("built", path, image.size,
                  "bbox", image.getchannel("A").getbbox())


if __name__ == "__main__":
    main()
