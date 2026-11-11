#!/usr/bin/env python3
"""Build Direction B versions of the two full-size Goliath duel figures.

The user's live screenshot showed the golden-hour OVERWORLD but a still-classic
duel setpiece. These two sheets keep the exact 32x32 / 64x64 geometry, alpha,
forehead position, frame count (one) and every pixel coordinate of the shipped
classic figures. Only the colour indices are remapped to the SAME B palette
JSON used by the crafted props, characters and stdlib CI gate. No proprietary
art, no painted background, no gameplay or animation change.

    PYTHONPATH=<pillow-cache> python3 tools/art_reset/build_cinematic_duel.py
    python3 tools/check_cinematic_art.py --write   # accept the redraw

Outputs
    art/duel_cinematic/david_cinematic.png
    art/duel_cinematic/goliath_cinematic.png
    docs/art-reset/cinematic_duel_4x.png           (human review)
"""
from __future__ import annotations

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from PIL import Image, ImageDraw  # noqa: E402

B = json.loads((ROOT / "data/cinematic_palette.json").read_text())
DUEL = ROOT / "art/duel"
B_DUEL = ROOT / "art/duel_cinematic"
OUT = ROOT / "docs/art-reset"

# Classic ramp index -> B palette key. The mapping is hand-authored so the
# armour, linen, skin, wood and spear each keep four readable value planes;
# a nearest-colour quantiser collapsed the bronze and linen into one muddy
# brown in the first local test. Transparent pixels are left untouched.
MAP = {
    # ink / iron / cool stone
    "#0a0e12": "INK", "#20242c": "STONE_D", "#3a424e": "LINEN_D",
    "#4a5460": "STONE_M", "#545e66": "STONE_M", "#5c6470": "LINEN_D",
    "#6f7a83": "STONE_L", "#7b8492": "LINEN_M", "#98a4ae": "STONE_L",
    "#9aa3ae": "LINEN_L", "#bcc3ca": "LINEN_H",
    # bronze armour / gold
    "#3d2a14": "CLAY_D", "#5c4020": "WOOD_D", "#7d5a2e": "CLAY_M",
    "#9d7540": "CLAY_L", "#bd9356": "WOOD_H", "#b3893c": "GOLD",
    "#8d6a2a": "CLAY_M", "#e2c07e": "LINEN_L", "#c9a45c": "GOLD",
    # blood / wound
    "#6f2823": "BLOOD_D", "#8f3830": "BLOOD_L",
    # skin
    "#5e3f28": "SKIN_D", "#7d5436": "SKIN_D", "#a06f45": "SKIN_M",
    "#c08e5c": "SKIN_M", "#d9ad7c": "SKIN_L", "#eec99c": "SKIN_L",
    # red hair
    "#3f1f11": "WOOD_D", "#562b17": "CLAY_D", "#6f3c20": "CLAY_M",
    "#894c2b": "CLAY_L", "#7a3a20": "CLAY_D",
    # David's robe
    "#7a4028": "CLAY_D", "#945232": "CLAY_M", "#ae6640": "CLAY_L",
    "#c87e50": "SKIN_M", "#e09a68": "SKIN_L",
    # wood / spear shaft
    "#4a3220": "WOOD_D", "#64462c": "WOOD_M", "#7e5a38": "WOOD_M",
    "#987248": "WOOD_L", "#b28a58": "WOOD_L", "#cca46c": "WOOD_H",
    # wool / sash
    "#6a5c48": "WOOD_D", "#84745c": "WOOD_M", "#9e8c72": "LINEN_M",
    "#b8a688": "LINEN_L",
    # loose clay / stone highlights seen in the classic sheets
    "#98492a": "CLAY_M", "#b65c36": "CLAY_L", "#7a6242": "WOOD_M",
    "#8a7448": "WOOD_L", "#a89058": "LINEN_M", "#c4ac74": "LINEN_L",
    "#dcc894": "LINEN_H", "#6b5a38": "WOOD_M", "#8a7448": "WOOD_L",
    "#74583e": "WOOD_M", "#8c6e4c": "WOOD_L", "#a48460": "LINEN_M",
    "#bc9c74": "LINEN_L", "#5a4430": "WOOD_D", "#4a3220": "WOOD_D",
}


def _rgb(key: str) -> tuple[int, int, int]:
    v = B[key].lstrip("#")
    return tuple(int(v[i:i + 2], 16) for i in (0, 2, 4))


def remap(src: pathlib.Path, dst: pathlib.Path) -> None:
    im = Image.open(src).convert("RGBA")
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    sp, op = im.load(), out.load()
    used = set()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = sp[x, y]
            if a < 128:
                continue
            key = MAP.get("#%02x%02x%02x" % (r, g, b))
            if key is None:
                raise SystemExit("%s: unmapped opaque colour #%02x%02x%02x at %d,%d"
                                 % (src.name, r, g, b, x, y))
            used.add(key)
            op[x, y] = (*_rgb(key), 255)
    assert "INK" in used, "%s lost its ink outline" % src.name
    assert len(used) >= 4, "%s has only %d value planes" % (src.name, len(used))
    dst.parent.mkdir(parents=True, exist_ok=True)
    out.save(dst)
    print("wrote %s (%dx%d, %d B colours)" % (dst.relative_to(ROOT),
                                              im.width, im.height, len(used)))


def preview() -> None:
    names = [("david.png", "david_cinematic.png"),
             ("goliath.png", "goliath_cinematic.png")]
    scale = 4
    pad = 12
    biggest = max(Image.open(DUEL / classic).height for classic, _ in names)
    cell_w = max(Image.open(DUEL / classic).width for classic, _ in names) * scale + pad * 2
    cell_h = biggest * scale + pad * 2 + 14
    sheet = Image.new("RGB", (cell_w * 2, cell_h * 2), "#14202a")
    d = ImageDraw.Draw(sheet)
    for col, (classic, cinematic) in enumerate(names):
        for row, (name, label) in enumerate(((classic, "classic " + classic[:-4]),
                                             (cinematic, "B v4 " + classic[:-4]))):
            im = Image.open((B_DUEL if row else DUEL) / name).convert("RGBA")
            big = im.resize((im.width * scale, im.height * scale),
                            Image.Resampling.NEAREST)
            x = col * cell_w + pad
            y = row * cell_h + pad + 14
            sheet.paste(big, (x, y), big)
            d.text((x, row * cell_h + 2), label, fill="#e6d3b0")
    OUT.mkdir(parents=True, exist_ok=True)
    p = OUT / "cinematic_duel_4x.png"
    sheet.save(p)
    print("preview:", p.relative_to(ROOT))


def main() -> None:
    for classic, cinematic in (("david.png", "david_cinematic.png"),
                               ("goliath.png", "goliath_cinematic.png")):
        remap(DUEL / classic, B_DUEL / cinematic)
    preview()


if __name__ == "__main__":
    main()
