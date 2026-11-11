#!/usr/bin/env python3
"""Extract a few grounded props from the generated chapter scenery.

The polygon mattes are manual approximations around objects in the source
pictures, not automatically inferred collision boundaries. Output canvases and
bottom anchors match data/props.json; RegionModel remains the sole authority
for footprints and solidity. Requires Pillow. Run from the repository root.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

SRC = Path('tools/art/sources')
OUT = Path('art/props_painted')

# Coordinates are in the full-size source, before the fit to each prop canvas.
MATTES = {
    'olive_tree': ('bethlehem_world.png', (65, 49), [
        (51, 271), (58, 251), (67, 238), (73, 222), (84, 211),
        (98, 204), (114, 200), (121, 184), (135, 177), (151, 178),
        (164, 183), (181, 188), (195, 199), (217, 197), (230, 207),
        (238, 217), (249, 229), (260, 245), (265, 259), (262, 269),
        (267, 278), (259, 293), (251, 304), (240, 313), (239, 327),
        (228, 332), (219, 330), (207, 325), (199, 333), (193, 345),
        (185, 357), (183, 369), (196, 380), (194, 390), (182, 384),
        (174, 378), (170, 389), (166, 399), (157, 400), (151, 389),
        (145, 388), (137, 398), (127, 396), (124, 389), (127, 377),
        (132, 369), (135, 351), (133, 339), (120, 331), (110, 321),
        (96, 317), (83, 306), (67, 299), (53, 284)]),
    'rock': ('elah_world.png', (34, 33), [
        (225, 286), (226, 278), (231, 271), (239, 266), (249, 261),
        (259, 257), (265, 257), (272, 263), (276, 270), (279, 280),
        (282, 287), (280, 293), (273, 296), (264, 296), (257, 294),
        (249, 297), (239, 297), (230, 294), (225, 291)]),
    'boulder': ('elah_world.png', (33, 31), [
        (698, 282), (701, 273), (710, 264), (718, 255), (724, 244),
        (735, 237), (746, 233), (759, 229), (771, 228), (781, 232),
        (788, 239), (794, 248), (799, 257), (803, 271), (799, 286),
        (793, 291), (781, 291), (772, 294), (762, 294), (752, 291),
        (740, 294), (729, 295), (717, 292), (707, 292), (699, 288)]),
    'jar': ('bethlehem_world.png', (18, 26), [
        (404, 209), (406, 204), (409, 202), (417, 202), (421, 205),
        (423, 209), (426, 213), (427, 220), (424, 225), (420, 228),
        (412, 229), (406, 226), (403, 222), (402, 216)]),
}


def make_prop(source, size, points, holes=()):
    image = Image.open(SRC / source).convert('RGBA')
    matte = Image.new('L', image.size)
    draw = ImageDraw.Draw(matte)
    draw.polygon(points, fill=255)
    for hole in holes:
        draw.polygon(hole, fill=0)
    matte = matte.filter(ImageFilter.GaussianBlur(0.5))
    image.putalpha(matte)
    image = image.crop(matte.getbbox())
    image.thumbnail(size, Image.Resampling.LANCZOS)
    canvas = Image.new('RGBA', size)
    canvas.alpha_composite(image, ((size[0] - image.width) // 2, size[1] - image.height))
    return canvas


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (source, size, points) in MATTES.items():
        image = make_prop(source, size, points)
        image.save(OUT / (name + '.png'), optimize=True)
        print(name, image.size, image.getchannel('A').getbbox())
    source, _, points = MATTES['olive_tree']
    # The small fig remains within its original 16x24 canvas.
    make_prop(source, (16, 24), points).save(OUT / 'fig_tree.png', optimize=True)
    # Bethlehem's stone well is also used in Elah. Remove the visible opening
    # under the crossbar so the surrounding ground is not baked into the prop.
    well = [(333, 516), (339, 510), (340, 503), (344, 501), (346, 494),
            (354, 494), (356, 498), (384, 486), (389, 480), (391, 474),
            (398, 474), (402, 479), (402, 550), (396, 555), (387, 558),
            (352, 558), (340, 553), (339, 522), (333, 522)]
    holes = [[(357, 501), (379, 491), (379, 502), (357, 506)],
             [(382, 490), (388, 487), (388, 502), (382, 502)]]
    make_prop('bethlehem_world.png', (16, 16), well, holes).save(OUT / 'well.png', optimize=True)


if __name__ == '__main__':
    main()
