#!/usr/bin/env python3
"""Build the chapter's remaining painterly props from isolated source images.

The source art was generated against the approved shepherd-field image. The
small outputs use two texture pixels per legacy world unit; Region applies the
corresponding visual scale without changing the authored physics footprints.
All assets remain independent sprites. Requires Pillow; run from the repo root.
"""
from pathlib import Path

from PIL import Image, ImageEnhance

from build_world_ground import chroma

SRC = Path('tools/art/sources')
OUT = Path('art/props_painted')
SHEEP = Path('art/proto/sprites')

# Output canvas dimensions are twice the sizes in data/props.json. Keeping the
# transparent padding and bottom-alignment makes the foot anchor predictable.
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
        frame = fit_foot(chroma(Image.open(SRC / source)), size)
        if name == 'fire':
            # Region's existing animation expects two horizontal frames.
            sheet = Image.new('RGBA', (size[0] * 2, size[1]))
            sheet.alpha_composite(frame, (0, 0))
            sheet.alpha_composite(ImageEnhance.Brightness(frame).enhance(1.08), (size[0], 0))
            frame = sheet
        frame.save(OUT / (name + '.png'), optimize=True)
        print(name, frame.size)
    # Reuse the approved prototype's independent cutout sheep, not the old
    # blocky overworld sheet. The two available poses keep some life in a flock.
    for name, source in [('sheep', 'sheep_reference_a.png'),
                         ('sheep_graze', 'sheep_reference_b.png'),
                         ('sheep_alert', 'sheep_reference_a_stride_a.png')]:
        frame = fit_foot(Image.open(SHEEP / source), (28, 24))
        frame.save(OUT / (name + '.png'), optimize=True)
        print(name, frame.size)


if __name__ == '__main__':
    main()
