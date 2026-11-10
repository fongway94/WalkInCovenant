#!/usr/bin/env python3
"""Build the four-way art-direction comparison for the shepherd-field scene.

This is an AUTHORING tool, not a CI gate. It needs Pillow + numpy (the same
local wheel cache the other art tools use) and it is deliberately deterministic:
every PNG in docs/art-reset/comparison/ can be regenerated from the committed
sources with one command.

    PYTHONPATH=<pillow-cache> python3 tools/art_reset/build_prototypes.py

Inputs
  docs/art-reset/prototypes/A_vibrant_source.png     (original concept art)
  docs/art-reset/prototypes/B_cinematic_source.png   (original concept art)
  docs/art-reset/prototypes/C_storybook_source.png   (original concept art)
  frames/15_shepherd_dialogue.png                    (REAL rendered game frame,
                                                     decoded from CI visual job)

What it does
  1. Centre-crops each concept to 16:9, reduces it to the game's native logical
     320x180, cleans isolated pixels, and maps it to a controlled 64-colour
     palette (no dithering). DESIGN_RAMPS below state the intended per-material
     shadow/midtone/highlight language; the final palette is adaptive so the
     concept's own hues survive. This is what makes a painted concept read as
     pixel art with a controlled colour system rather than a downscaled painting.
  2. Draws a direction-specific HUD + dialogue UI at the SAME position, SAME
     size and SAME Chinese strings as the shipped game, using the shipped font
     fonts/game.ttf and the shipped 32x32 portrait. Layout is held constant so
     UI differences are artistic, not functional.
  3. Emits four 320x180 panels (Current / A / B / C), three review sizes
     (native 320x180, desktop 1280x720, mobile landscape 844x390), grayscale
     versions, detail crops and a metrics.json with value/contrast measurements.

LIMITATION: these are concept composites. They are NOT game assets, they have
not been sliced into tiles or animation frames, and no in-engine screenshot of
them exists. See docs/ART-RESET.md section 6.
"""

from __future__ import annotations

import json
import pathlib

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
PROTO = ROOT / "docs/art-reset/prototypes"
OUT = ROOT / "docs/art-reset/comparison"
FONT = ROOT / "fonts/game.ttf"
PORTRAIT = ROOT / "art/facesets/shepherd.png"

W, H = 320, 180
SIZES = {
    "native": (W, H),
    "desktop": (1280, 720),
    "mobile": (844, 390),
}

# ── DESIGN RAMPS: the intended per-material shadow → highlight language and
# the UI accent source for each direction. The shipped prototype uses an adaptive
# 64-colour reduction of the concept (see pixelate) because snapping a painted
# concept onto a fixed ramp set destroyed its hue relationships; these ramps are
# the contract a hand-authored tile set would be drawn against. ────────────────
DESIGN_RAMPS = {
    "A_vibrant": [
        # outline / shadow
        "#121a2e", "#243252", "#3a4a70",
        # grass: shadow -> highlight
        "#1d5a26", "#2e7d33", "#45a044", "#66c158", "#8ee073", "#b6f29a",
        # earth / path
        "#6b4a26", "#8f6736", "#b98a4c", "#d9ae70", "#f0d199", "#f8e6bf",
        # limestone / wall
        "#4c5a70", "#6c7c92", "#8f9db0", "#b8c4d2", "#e2e9f0",
        # tree canopy
        "#174a22", "#256b2c", "#389243", "#57b657", "#7ed06f", "#a8e88e",
        # wood / trunk
        "#3a2415", "#5b3a20", "#7d5530", "#a37448", "#c79868",
        # linen / wool / skin
        "#37507c", "#52709e", "#7b98c2", "#b7c9e0",
        "#f0e2c8", "#d8c09c", "#b3906a",
        "#6b3f24", "#9a6238", "#c48a58", "#e6b784", "#f5d3a8",
        # sky / water / accents
        "#2e6da8", "#4a95cf", "#82c4ea", "#c6e9f8",
        "#8a5a18", "#c9a45c", "#f0d47c", "#fff0b8",
        "#c0403c", "#e06850",
    ],
    "B_cinematic": [
        # cool shadow / near-black
        "#0c1018", "#171d2a", "#242c3e", "#333d54", "#46516a", "#5d6880",
        # amber light ramp
        "#3d2a18", "#6b4522", "#9c6a30", "#c49143", "#e0b263", "#f4d394", "#fce9bd",
        # olive / grass in shade and light
        "#182a20", "#263d2a", "#365034", "#4a6640", "#638052", "#89a066",
        # earth / path
        "#2a231c", "#443427", "#63482f", "#86603d", "#a87c50", "#c99e6d",
        # stone / wall
        "#282f39", "#3c444f", "#535c67", "#6e7881", "#8d969c", "#b2b9ba",
        # haze / distance
        "#4a4550", "#6d6170", "#938091", "#b9a2a2", "#d8bda9",
        # cloth / skin
        "#2b3145", "#414b63", "#5f6a82", "#8790a3",
        "#5a371f", "#835534", "#a9794d", "#c99c6e", "#e3bd8e",
        "#8a2f26", "#b34833",
        # ember gold
        "#8c5a20", "#c08b3c", "#e8bb6a",
        # UI-only colours, kept inside the same ramp system so the HUD does not
        # crush to pure black when the whole frame is snapped to the palette
        "#d8bd9c", "#b8aca0",
    ],
    "C_storybook": [
        # warm ink outline / shadow
        "#2a1c14", "#423023", "#5c4431",
        # limestone / wall
        "#7a6a52", "#9a896c", "#b6a384", "#cfbe9e", "#e5d6b8", "#f3e7cf",
        # ochre earth / path
        "#6b4a2c", "#8b6540", "#a98154", "#c39e6c", "#dcbd8b", "#eed7ab",
        # olive foliage (silver-green)
        "#3b4a38", "#526346", "#6d7c58", "#8b9a70", "#aab68a", "#c7d0a4",
        # terracotta / clay
        "#6a3526", "#8b4630", "#ac5c3c", "#c87a53", "#e09b72",
        # linen / wool / skin
        "#8a7c62", "#aca085", "#c9bda2", "#e2d7bd", "#f4ecd8",
        "#5a3a22", "#825738", "#a87951", "#c99a70", "#e5bd90", "#f2d4ac",
        # wood
        "#3e2a1a", "#5f4127", "#825b38", "#a87a50",
        # lapis / muted blue accent
        "#2f4658", "#44637a", "#65839a",
        # gold / holy accent
        "#7d5a20", "#b18a3c", "#dcc070", "#f2dda4",
        "#7a3a30", "#a2553c",
    ],
}

# Direction-specific UI skins. Every skin uses the SAME geometry and the SAME
# Chinese copy as the shipped DialogueBox, so the comparison isolates art.
SKINS = {
    "A_vibrant": {
        "hud": "#16294e", "hud_rule": "#c9a45c", "hud_text": "#f7e9c4",
        "hud_dim": "#a9c0e0", "panel": "#16294e", "panel_edge": "#f0d47c",
        "panel_inner": "#2e4b7a", "name": "#f7dda5", "rule": "#7b98c2",
        "body": "#f3ead4", "frame": "#c9a45c", "frame_bg": "#0d1a33",
        "chevron": "#f0d47c", "corner": "#f0d47c",
    },
    "B_cinematic": {
        "hud": "#171d2a", "hud_rule": "#9c6a30", "hud_text": "#d8bd9c",
        "hud_dim": "#b8aca0", "panel": "#242c3e", "panel_edge": "#c49143",
        "panel_inner": "#333d54", "name": "#e0b263", "rule": "#9c6a30",
        "body": "#fce9bd", "frame": "#c08b3c", "frame_bg": "#0c1018",
        "chevron": "#e8bb6a", "corner": "#9c6a30",
    },
    "C_storybook": {
        "hud": "#4a3524", "hud_rule": "#c39e6c", "hud_text": "#f4ecd8",
        "hud_dim": "#d8bd9b", "panel": "#e5d6b8", "panel_edge": "#5c4431",
        "panel_inner": "#cfbe9e", "name": "#5a3a22", "rule": "#a87951",
        "body": "#3b2a1c", "frame": "#8b6540", "frame_bg": "#f3e7cf",
        "chevron": "#7a3a30", "corner": "#8b4630",
    },
}

NAME = "帮工的孩子"
LINE1 = "「还有三只没回来。我守着栅栏，"
LINE2 = "你去把它们带回来。」"


def hexrgb(h: str):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[1:3], 16), int(h[3:5], 16))


def palette_image(colors):
    """A Pillow P-mode palette holding exactly `colors` RGB tuples/hexes.

    Pillow considers ALL 256 palette slots. Padding with zeros would add pure
    black as a real, selectable colour and crush every shadow to #000; repeat
    the deepest authored shadow instead.
    """
    flat = []
    for c in colors:
        flat.extend(hexrgb(c) if isinstance(c, str) else c)
    pad = tuple(flat[0:3])
    while len(flat) < 768:
        flat.extend(pad)
    p = Image.new("P", (1, 1))
    p.putpalette(flat[:768])
    return p


# Exactly how many colours the world of each direction may use. 64 is a real
# 16-bit-era budget: enough for five-step ramps per material, few enough that
# a human can still name every colour in the scene.
NCOLORS = {"A_vibrant": 64, "B_cinematic": 64, "C_storybook": 64}


def crop_16x9(im: Image.Image) -> Image.Image:
    w, h = im.size
    target = 16.0 / 9.0
    if w / h > target:
        nw = int(round(h * target))
        x = (w - nw) // 2
        im = im.crop((x, 0, x + nw, h))
    else:
        nh = int(round(w / target))
        y = (h - nh) // 2
        im = im.crop((0, y, w, y + nh))
    return im


def tone(src: Image.Image, key: str) -> Image.Image:
    """Per-direction exposure / lighting BEFORE pixelation.

    B's concept is a dusk scene; mapping it straight to a limited ramp crushed
    the shadows to pure black (measured luma p10 = 0.0). Lift the tonal curve.
    C gets a gentle morning light gradient so its value hierarchy is deliberate
    rather than one uniform mid-tone field.
    """
    a = np.asarray(src.convert("RGB"), dtype=np.float32) / 255.0
    if key == "B_cinematic":
        a = a ** 0.72
    elif key == "C_storybook":
        h, w = a.shape[:2]
        yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
        # upper right catches the light; lower left sits in cool shade
        g = 0.84 + 0.22 * (0.55 * (xx / w) + 0.45 * (1.0 - yy / h))
        a = a * g[..., None]
    elif key == "A_vibrant":
        a = a * 1.02
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))


def despeckle(pimg: Image.Image, passes: int = 2) -> Image.Image:
    """Remove isolated single-pixel colour confetti from a quantised image.

    Reducing a smooth concept to ~40 colours with NO dithering otherwise leaves
    scattered lone pixels of a neighbouring ramp step — the exact "random
    single-pixel noise" the brief forbids. Work on palette INDICES so the result
    is always still one of the authored colours.
    """
    idx = np.asarray(pimg, dtype=np.uint8).copy()
    palette = pimg.getpalette()
    for _ in range(passes):
        stack = []
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dx == 0 and dy == 0:
                    continue
                stack.append(np.roll(np.roll(idx, dy, axis=0), dx, axis=1))
        neighbours = np.stack(stack, axis=2)
        same = (neighbours == idx[..., None]).sum(axis=2)
        ys, xs = np.where(same <= 1)
        out = idx.copy()
        for y, x in zip(ys, xs):
            vals = neighbours[y, x]
            counts = np.bincount(vals, minlength=256)
            counts[idx[y, x]] = 0
            out[y, x] = int(counts.argmax())
        idx = out
    res = Image.fromarray(idx, mode="P")
    res.putpalette(palette)
    return res


def pixelate(src: Image.Image, key: str):
    """Downsample to native resolution, reduce to a controlled 64-colour ramp,
    then remove isolated pixels. Returns (world RGB, the exact palette used).

    An ADAPTIVE palette is used rather than the hand-authored DESIGN_RAMPS:
    mapping a painted concept onto a fixed ramp set destroyed its hue
    relationships (measured: B collapsed to 14 colours and purple haze). The
    design ramps below still define the intended highlight/midtone/shadow
    language and the UI accent choices; the concept's own hues survive the
    reduction, and the final panel still has a countable, limited palette.
    """
    im = crop_16x9(tone(src, key)).resize((W, H), Image.LANCZOS)
    im = im.filter(ImageFilter.ModeFilter(size=3))
    q = im.quantize(colors=NCOLORS[key], method=Image.Quantize.MEDIANCUT,
                    dither=Image.Dither.NONE)
    q = despeckle(q, passes=2)
    pal = q.getpalette()
    used = sorted(set(np.asarray(q, dtype=np.uint8).ravel().tolist()))
    colors = [tuple(pal[i * 3:i * 3 + 3]) for i in used]
    return q.convert("RGB"), colors


def ui_palette(world_colors, skin):
    """World palette + that direction's UI accents = ONE controlled palette."""
    cols = list(world_colors)
    for value in skin.values():
        c = hexrgb(value)
        if c not in cols:
            cols.append(c)
    return palette_image(cols)


def bitmap_text(im: Image.Image, xy, text, font, fill):
    """1-bit Chinese glyphs: no TrueType anti-aliasing, so the UI stays pixel art.

    The shipped game renders fonts/game.ttf through Godot at 9px with nearest
    filtering. Pillow's default TrueType renderer would add hundreds of grey
    in-between colours and blur the 9px strokes — exactly the weakness the art
    reset is trying to remove. Threshold the glyph mask instead.
    """
    x, y = xy
    box = font.getbbox(text)
    w, h = max(1, box[2] - box[0] + 2), max(1, box[3] - box[1] + 2)
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).text((1 - box[0], 1 - box[1]), text,
                              font=font, fill=255)
    mask = mask.point(lambda v: 255 if v >= 110 else 0)
    im.paste(fill, (x, y), mask)


def draw_ui(im: Image.Image, skin: dict, portrait: Image.Image) -> Image.Image:
    d = ImageDraw.Draw(im)
    f9 = ImageFont.truetype(str(FONT), 9)

    # ── HUD: 22px band, same information hierarchy as the shipped HUD ──────
    d.rectangle((0, 0, W - 1, 21), fill=skin["hud"])
    d.line((0, 21, W - 1, 21), fill=skin["hud_rule"])
    bitmap_text(im, (5, 1), "朝圣者 · 1级  以拉谷", f9, skin["hud_text"])
    bitmap_text(im, (5, 11), "还有三只没回来", f9, skin["hud_dim"])
    # right-hand counters, drawn as small glyphs rather than real text so the
    # comparison is not a typography contest
    bitmap_text(im, (243, 1), "☆0  清晨  EN", f9, skin["hud_text"])
    bitmap_text(im, (268, 11), "≡", f9, skin["hud_dim"])

    # ── Dialogue panel: fixed geometry for all three directions ───────────
    x0, y0, x1, y1 = 4, 116, 315, 176
    d.rectangle((x0, y0, x1, y1), fill=skin["panel"],
                outline=skin["panel_edge"], width=1)
    d.rectangle((x0 + 2, y0 + 2, x1 - 2, y1 - 2),
                outline=skin["panel_inner"], width=1)
    # small corner diamonds — restrained, never ornate enough to cover text
    for cx, cy in ((x0 + 3, y0 + 3), (x1 - 3, y0 + 3),
                   (x0 + 3, y1 - 3), (x1 - 3, y1 - 3)):
        d.rectangle((cx - 1, cy - 1, cx + 1, cy + 1), fill=skin["corner"])

    # portrait: the SHIPPED 32x32 face, only its frame changes per direction
    d.rectangle((9, 121, 44, 156), fill=skin["frame_bg"],
                outline=skin["frame"], width=1)
    im.paste(portrait.convert("RGB"), (10, 122))

    bitmap_text(im, (50, 120), NAME, f9, skin["name"])
    d.line((50, 132, 302, 132), fill=skin["rule"])
    bitmap_text(im, (50, 137), LINE1, f9, skin["body"])
    bitmap_text(im, (50, 151), LINE2, f9, skin["body"])
    d.polygon([(304, 166), (309, 166), (306, 170)], fill=skin["chevron"])
    return im


def resize_for(size_name, im):
    tw, th = SIZES[size_name]
    if size_name == "native":
        return im.copy()
    if size_name == "desktop":
        return im.resize((tw, th), Image.NEAREST)
    # Mobile landscape: the real web viewport WIDENS to 320x148 logical rather
    # than letterboxing. Fit the whole frame into 844x390 so no UI is hidden,
    # then note the real crop separately in the report.
    scale = th / H
    fw, fh = int(round(W * scale)), th
    fitted = im.resize((fw, fh), Image.NEAREST)
    canvas = Image.new("RGB", (tw, th), (18, 20, 26))
    canvas.paste(fitted, ((tw - fw) // 2, 0))
    return canvas


def metrics(im: Image.Image) -> dict:
    a = np.asarray(im.convert("RGB"), dtype=np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    luma = 0.299 * r + 0.587 * g + 0.114 * b
    mx, mn = a.max(axis=2), a.min(axis=2)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1), 0)
    world = luma[24:112, :]
    hud = luma[0:21, :]
    ui = luma[116:176, :]
    gx = np.abs(np.diff(luma, axis=1))[:, :W - 1]
    gy = np.abs(np.diff(luma, axis=0))[:H - 1, :]
    edges = (gx > 18).mean() + (gy > 18).mean()
    # large-scale value variation = a proxy for depth/composition
    # 11 x 8 grid of 8x40 px blocks: large-scale value variation, a proxy for
    # whether the scene has real depth or is one flat mid-tone field.
    blocks = world.reshape(11, 8, 8, 40).mean(axis=(1, 3))
    uniq = len(np.unique(a.reshape(-1, 3), axis=0))
    return {
        "unique_colors": int(uniq),
        "luma_mean": round(float(luma.mean()), 1),
        "luma_std": round(float(luma.std()), 1),
        "luma_p10": round(float(np.percentile(luma, 10)), 1),
        "luma_p50": round(float(np.percentile(luma, 50)), 1),
        "luma_p90": round(float(np.percentile(luma, 90)), 1),
        "saturation_mean": round(float(sat.mean()), 3),
        "edge_density": round(float(edges), 3),
        "world_luma_mean": round(float(world.mean()), 1),
        "world_value_spread": round(float(blocks.std()), 1),
        "hud_luma_mean": round(float(hud.mean()), 1),
        "ui_luma_mean": round(float(ui.mean()), 1),
        "world_ui_separation": round(float(abs(world.mean() - ui.mean())), 1),
    }


def labelled_grid(panels, title, labels, cellw, cellh, scale=1):
    cols = 2
    pad, lab = 10, 22
    rows = (len(panels) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (cellw + pad) + pad,
                              rows * (cellh + lab + pad) + pad), (24, 26, 32))
    d = ImageDraw.Draw(sheet)
    f = ImageFont.truetype(str(FONT), 12)
    for i, (key, im) in enumerate(panels):
        x = pad + (i % cols) * (cellw + pad)
        y = pad + (i // cols) * (cellh + lab + pad)
        sheet.paste(im, (x, y + lab))
        d.text((x + 3, y + 4), labels[key], font=f, fill=(238, 232, 210))
    return sheet


def refine_selected(panel: Image.Image) -> Image.Image:
    """Direction C won, but its measured weakness was a flat value hierarchy
    (world_value_spread 16.9 vs B's 26.6). Borrow B's LIGHTING LOGIC, not its
    palette: atmospheric darkening toward the far edge, a brighter focal band
    in the middle ground, a darker near edge, and a mild contrast S-curve.
    Re-snap to the SAME palette so colour discipline is unchanged.
    """
    a = np.asarray(panel.convert("RGB"), dtype=np.float32)
    band = a[24:112].copy()
    h = band.shape[0]
    yy = np.linspace(0.0, 1.0, h, dtype=np.float32)[:, None, None]
    g = 0.84 + 0.26 * np.sin(np.pi * yy)
    mean = float(band.mean())
    band = (band - mean) * 1.12 + mean
    band = np.clip(band * g, 0, 255)
    a[24:112] = band
    raw = Image.fromarray(a.astype(np.uint8), "RGB")
    cols = [tuple(c) for c in np.unique(
        np.asarray(panel.convert("RGB")).reshape(-1, 3), axis=0)]
    return raw.quantize(palette=palette_image(cols),
                        dither=Image.Dither.NONE).convert("RGB")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    portrait = Image.open(PORTRAIT).convert("RGB").resize((32, 32), Image.NEAREST)

    # Prefer a freshly decoded CI frame; fall back to the committed baseline so
    # the comparison is reproducible from a clean clone (frames/ is gitignored).
    frame = ROOT / "frames/15_shepherd_dialogue.png"
    if not frame.exists():
        frame = ROOT / "tests/frames/baseline_15_shepherd_dialogue.png"
    current = Image.open(frame).convert("RGB")
    assert current.size == (W, H), current.size
    print("before frame:", frame.relative_to(ROOT))

    panels = {"current": current}
    for key in ("A_vibrant", "B_cinematic", "C_storybook"):
        src = Image.open(PROTO / f"{key}_source.png")
        world, world_colors = pixelate(src, key)
        composite = draw_ui(world, SKINS[key], portrait)
        # One final snap means the WHOLE panel — world, portrait, HUD, panel and
        # text — uses one countable palette (64 world colours + UI accents).
        panels[key] = composite.quantize(
            palette=ui_palette(world_colors, SKINS[key]),
            dither=Image.Dither.NONE).convert("RGB")
        panels[key].save(OUT / f"{key}_native.png")
    panels["current"].save(OUT / "current_native.png")

    labels = {
        "current": "CURRENT — real rendered game (CI 42765837238)",
        "A_vibrant": "DIRECTION A — Vibrant Classic RPG",
        "B_cinematic": "DIRECTION B — Rich Cinematic Pixel Art",
        "C_storybook": "DIRECTION C — Biblical Storybook RPG",
    }

    report = {"panels": {}, "sizes": {}}
    for size_name, (cw, ch) in SIZES.items():
        scaled = {k: resize_for(size_name, im) for k, im in panels.items()}
        for k, im in scaled.items():
            im.save(OUT / f"{k}_{size_name}.png")
        order = [(k, scaled[k]) for k in
                 ("current", "A_vibrant", "B_cinematic", "C_storybook")]
        sheet = labelled_grid(order, size_name, labels, cw, ch)
        sheet.save(OUT / f"four_way_{size_name}.png")

        gray = {k: Image.fromarray(
            (0.299 * np.asarray(im.convert("RGB"), dtype=np.float32)[..., 0]
             + 0.587 * np.asarray(im.convert("RGB"), dtype=np.float32)[..., 1]
             + 0.114 * np.asarray(im.convert("RGB"), dtype=np.float32)[..., 2]
             ).astype(np.uint8)).convert("RGB")
                for k, im in scaled.items()}
        order_g = [(k, gray[k]) for k in
                   ("current", "A_vibrant", "B_cinematic", "C_storybook")]
        gsheet = labelled_grid(order_g, size_name, labels, cw, ch)
        gsheet.save(OUT / f"four_way_grayscale_{size_name}.png")
        for k, im in gray.items():
            im.save(OUT / f"{k}_grayscale_{size_name}.png")
        report["sizes"][size_name] = {"colour": f"four_way_{size_name}.png",
                                      "grayscale": f"four_way_grayscale_{size_name}.png"}

    # Detail crops at 6x: character / sheep / foliage / UI, same boxes on each.
    boxes = {
        "characters": (30, 55, 130, 110),
        "foliage": (190, 30, 300, 110),
        "ui": (0, 112, 320, 180),
    }
    crop_panels = {}
    for key, im in panels.items():
        strip = []
        for _, box in boxes.items():
            strip.append(im.crop(box))
        row = Image.new("RGB", (sum(s.width for s in strip), 68), (24, 26, 32))
        x = 0
        for s in strip:
            row.paste(s, (x, 0))
            x += s.width
        crop_panels[key] = row.resize((row.width * 4, row.height * 4), Image.NEAREST)
    cw, ch = crop_panels["current"].size
    sheet = labelled_grid([(k, crop_panels[k]) for k in
                           ("current", "A_vibrant", "B_cinematic", "C_storybook")],
                          "details", labels, cw, ch)
    sheet.save(OUT / "four_way_details_4x.png")

    # ── Selected-direction refinement ─────────────────────────────────────
    # Not a fourth alternative: the SAME Direction C with the lighting logic
    # borrowed from B. Proves the chosen direction's one measured weakness is
    # fixable by colour strategy rather than by adding more detail.
    refined = refine_selected(panels["C_storybook"])
    refined.save(OUT / "C_selected_refined_native.png")
    refined.resize(SIZES["desktop"], Image.NEAREST).save(
        OUT / "C_selected_refined_desktop.png")
    Image.fromarray((0.299 * np.asarray(refined)[..., 0]
                     + 0.587 * np.asarray(refined)[..., 1]
                     + 0.114 * np.asarray(refined)[..., 2]).astype(np.uint8)
                    ).convert("RGB").save(OUT / "C_selected_refined_grayscale_native.png")
    pairs = [("C_storybook", panels["C_storybook"]), ("C_refined", refined)]
    sheet = labelled_grid(pairs, "refinement",
                          {"C_storybook": "SELECTED C — as prototyped",
                           "C_refined": "SELECTED C+ — value hierarchy from B"},
                          W, H)
    sheet.save(OUT / "selected_refinement_native.png")

    for k, im in panels.items():
        report["panels"][k] = metrics(im)
    report["panels"]["C_refined"] = metrics(refined)
    report["selected"] = "C_storybook"
    (OUT / "metrics.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report["panels"], indent=2))
    print("wrote", len(list(OUT.glob('*.png'))), "PNG(s) to", OUT.relative_to(ROOT))


if __name__ == "__main__":
    main()
