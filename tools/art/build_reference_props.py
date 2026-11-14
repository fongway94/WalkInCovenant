#!/usr/bin/env python3
"""Build the chapter's remaining painterly props from isolated source images.

The source art was generated against the approved shepherd-field image. The
outputs are rebuilt at triple the previous texture density from those sources.
The game compensates the visual scale, without changing physics footprints or
moving their foot anchors. All assets remain independent sprites. Requires
Pillow; run from the repo root.
"""
from pathlib import Path

from PIL import Image, ImageEnhance

from build_world_ground import chroma
from prop_detail import align_to_legacy, detail_size

SRC = Path('tools/art/sources')
OUT = Path('art/props_painted')
SHEEP = Path('art/proto/sprites')

# Legacy canvas dimensions (before the detail multiplier). The helper keeps
# their transparent padding and bottom alignment at the same world positions.
PROPS = {
    'fire': ('prop_fire_reference.png', (32, 24)),
    'altar_stones': ('prop_altar_reference.png', (32, 32)),
    'fold': ('prop_fold_reference.png', (32, 24)),
    'trough': ('prop_trough_reference.png', (32, 20)),
    'staff': ('prop_staff_reference.png', (16, 36)),
    'wheat_sheaf': ('prop_wheat_reference.png', (16, 24)),
    'bush': ('prop_bush_reference.png', (70, 58)),
    'wool_tuft': ('prop_wool_reference.png', (16, 12)),
    'signpost': ('prop_signpost_reference.png', (32, 32)),
}


def fit_foot(image, size):
    image = image.convert('RGBA')
    bbox = image.getchannel('A').getbbox()
    if bbox is None:
        raise ValueError('empty sprite')
    image = image.crop(bbox)
    image.thumbnail(size, Image.Resampling.LANCZOS)
    out = Image.new('RGBA', size)
    out.alpha_composite(image, ((size[0] - image.width) // 2, size[1] - image.height))
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (source, size) in PROPS.items():
        art = chroma(Image.open(SRC / source))
        frame = align_to_legacy(fit_foot(art, size), fit_foot(art, detail_size(size)))
        if name == 'fire':
            # Align a single frame first; both animation frames therefore keep
            # the same feet and do not shift as brightness changes.
            width, height = frame.size
            sheet = Image.new('RGBA', (width * 2, height))
            sheet.alpha_composite(frame, (0, 0))
            sheet.alpha_composite(ImageEnhance.Brightness(frame).enhance(1.08), (width, 0))
            frame = sheet
        frame.save(OUT / (name + '.png'), optimize=True)
        print(name, frame.size)
    # Reuse the approved prototype's actual reference-derived cutouts. Their
    # available native pixels are limited; a larger canvas is not new detail.
    for name, source in [('sheep', 'sheep_reference_a.png'),
                         ('sheep_graze', 'sheep_reference_b.png'),
                         ('sheep_alert', 'sheep_reference_a_stride_a.png')]:
        art = Image.open(SHEEP / source)
        size = (28, 24)
        frame = align_to_legacy(fit_foot(art, size), fit_foot(art, detail_size(size)))
        frame.save(OUT / (name + '.png'), optimize=True)
        print(name, frame.size)


if __name__ == '__main__':
    main()
