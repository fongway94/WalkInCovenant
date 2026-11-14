#!/usr/bin/env python3
"""Make a few non-repeating camp and village props, with old foot anchors.

Two tents are hand-matted from the existing Elah source painting; the open
royal tent and second house are isolated generated images. Three brook stones
are matted from the existing brook painting. These are cosmetic sprites, not
new colliders or map placements. Polygon mattes are approximations and should
be reviewed at actual game scale. Requires Pillow 13.0.0.
"""
from pathlib import Path
import argparse

from PIL import Image, ImageDraw, ImageFilter

from build_world_ground import chroma

SRC = Path("tools/art/sources")
OUT = Path("art/props_painted")

TENTS = {
    "tent_camp_a": [
        (207, 786), (211, 793), (224, 806), (239, 816), (253, 822),
        (269, 826), (278, 831), (284, 845), (291, 864), (299, 882),
        (304, 898), (309, 917), (301, 927), (293, 935), (284, 933),
        (273, 928), (264, 924), (254, 917), (246, 909), (237, 900),
        (231, 902), (226, 915), (218, 929), (209, 938), (199, 941),
        (186, 940), (177, 938), (165, 940), (155, 938), (147, 940),
        (143, 933), (141, 922), (138, 909), (138, 895), (135, 888),
        (139, 868), (140, 850), (144, 840), (154, 836), (165, 829),
        (177, 818), (191, 803),
    ],
    "tent_camp_b": [
        (772, 813), (780, 822), (787, 840), (800, 861), (812, 881),
        (817, 889), (815, 905), (817, 928), (812, 938), (800, 945),
        (788, 948), (778, 954), (763, 961), (751, 964), (738, 969),
        (728, 964), (718, 955), (706, 945), (696, 941), (687, 928),
        (682, 914), (678, 899), (676, 887), (670, 891), (666, 904),
        (659, 916), (653, 926), (641, 933), (635, 925), (634, 914),
        (636, 898), (638, 880), (648, 870), (663, 856), (678, 844),
        (697, 840), (718, 836), (739, 830), (753, 823),
    ],
}


STONES = {
    "brook_stone_a": [
        (819, 174), (820, 164), (829, 156), (841, 150), (853, 144),
        (868, 140), (882, 139), (900, 142), (911, 148), (918, 156),
        (920, 166), (919, 182), (910, 190), (900, 193), (883, 195),
        (866, 193), (850, 190), (836, 186), (825, 182),
    ],
    "brook_stone_b": [
        (822, 647), (826, 638), (835, 632), (848, 626), (860, 622),
        (873, 622), (885, 624), (898, 630), (910, 637), (918, 645),
        (922, 653), (918, 659), (910, 662), (899, 666), (881, 667),
        (860, 665), (844, 662), (832, 659), (824, 655),
    ],
    "brook_stone_c": [
        (1188, 516), (1193, 506), (1203, 499), (1213, 490), (1223, 483),
        (1233, 482), (1246, 482), (1258, 483), (1267, 487), (1270, 496),
        (1270, 516), (1263, 524), (1253, 528), (1239, 531), (1223, 533),
        (1208, 531), (1198, 528), (1191, 524),
    ],
}


def tents():
    source = Image.open(SRC / "elah_world.png").convert("RGBA")
    for name, polygon in TENTS.items():
        matte = Image.new("L", source.size)
        ImageDraw.Draw(matte).polygon(polygon, fill=255)
        matte = matte.filter(ImageFilter.GaussianBlur(0.4))
        image = source.copy()
        image.putalpha(matte)
        image = image.crop(matte.getbbox())
        # Same 156x108 detail canvas as the original tent. Slightly varying
        # the silhouette is intentional; feet still land on the map position.
        image = image.resize((144, 102), Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", (156, 108))
        canvas.alpha_composite(image, (6, 6))
        yield name + ".png", canvas


def royal_tent():
    # The king stands at the authored position inside the tent footprint. Give
    # his larger rig an open doorway and room beneath the canopy; the runtime
    # sorts this backdrop behind him without changing the prop's ground anchor.
    image = chroma(Image.open(SRC / "reference_royal_open_tent.png"))
    image = image.resize((252, 210), Image.Resampling.LANCZOS)
    # Saul's authored feet sit 18 world pixels north of the tent's base. At
    # the runtime 0.3 scale that is y=150 on this 210px canvas. Expose the
    # ground and contact shadow there rather than leaving his feet floating
    # against the rear curtain; the tied side curtains stay full height.
    alpha = image.getchannel("A")
    ImageDraw.Draw(alpha).rectangle((48, 150, 203, 209), fill=0)
    image.putalpha(alpha)
    return "tent_royal_open.png", image


def brook_stones():
    source = Image.open(SRC / "brook_environment.png").convert("RGBA")
    for name, polygon in STONES.items():
        matte = Image.new("L", source.size)
        ImageDraw.Draw(matte).polygon(polygon, fill=255)
        matte = matte.filter(ImageFilter.GaussianBlur(0.35))
        image = source.copy()
        image.putalpha(matte)
        image = image.crop(matte.getbbox())
        image.thumbnail((54, 36), Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", (54, 36))
        canvas.alpha_composite(image, ((54 - image.width) // 2, (36 - image.height) // 2))
        yield name + ".png", canvas


def house():
    image = chroma(Image.open(SRC / "reference_house_alt.png"))
    image = image.resize((198, 183), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (198, 249))
    canvas.alpha_composite(image, (0, 66))
    # A small shaded window on the receding wall makes this a dwelling, not a
    # blank box. The pixels are subordinate to the source's existing masonry.
    draw = ImageDraw.Draw(canvas)
    draw.polygon([(154, 132), (165, 127), (165, 146), (154, 151)], fill=(57, 52, 34, 255))
    draw.polygon([(156, 134), (163, 131), (163, 144), (156, 147)], fill=(26, 27, 23, 255))
    draw.line([(154, 132), (165, 127)], fill=(139, 116, 72, 255), width=1)
    return "house_reference_alt.png", canvas


def build_all():
    yield from tents()
    yield royal_tent()
    yield house()
    yield from brook_stones()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="compare without overwriting")
    args = parser.parse_args()
    for name, image in build_all():
        path = OUT / name
        if args.check:
            with Image.open(path) as saved:
                if saved.mode != image.mode or saved.size != image.size or saved.tobytes() != image.tobytes():
                    raise SystemExit("non-reproducible prop: " + str(path))
        else:
            image.save(path, optimize=True)
        print("verified" if args.check else "built", path)


if __name__ == "__main__":
    main()
