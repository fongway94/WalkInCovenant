#!/usr/bin/env python3
"""measure_real_engine.py — compare REAL shipped-engine frames, not concepts.

Reads the frames decoded from a CI visual run (tools/decode_frames.py <run-id>)
and measures the same large-scale value hierarchy used for the four-way
comparison. It also builds the before/after evidence sheets at native size and
in grayscale.

    PYTHONPATH=<pillow-cache> python3 tools/art_reset/measure_real_engine.py

Inputs (all REAL 320x180 framebuffer captures):
    frames/15_shepherd_dialogue.png        classic, same camera & dialogue
    frames/16_shepherd_cinematic.png       opt-in integrated scene
    docs/art-reset/comparison/16_palette_only.png   previous CI frame, optional

Outputs:
    docs/art-reset/diagnosis/04_before_after_real_engine.png
    docs/art-reset/diagnosis/05_before_after_grayscale.png
    docs/art-reset/diagnosis/08_palette_vs_craft.png
    docs/art-reset/diagnosis/09_craft_iteration.png
    docs/art-reset/diagnosis/10_craft_iteration2.png
    docs/art-reset/diagnosis/11_craft_iteration3.png
    docs/art-reset/diagnosis/14_direction_override.png
    docs/art-reset/diagnosis/15_direction_progression_2x.png
    docs/art-reset/diagnosis/16_B_engine_vs_reference.png
    docs/art-reset/diagnosis/17_B_engine_vs_reference_grayscale.png
    docs/art-reset/comparison/B_engine_{native,desktop,mobile}.png
    docs/art-reset/comparison/B_engine_grayscale_{native,desktop,mobile}.png
    docs/art-reset/comparison/real_engine_metrics.json
"""
from __future__ import annotations

import json
import pathlib
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/art_reset"))
from build_prototypes import metrics  # noqa: E402

FRAMES = ROOT / "frames"
DIAG = ROOT / "docs/art-reset/diagnosis"
COMP = ROOT / "docs/art-reset/comparison"
DIAG.mkdir(parents=True, exist_ok=True)


def load(path):
    assert path.exists(), f"missing real frame {path} — run tools/decode_frames.py <run-id> first"
    return Image.open(path).convert("RGB")


def font(size):
    return ImageFont.truetype(str(ROOT / "fonts/game.ttf"), size)


def sheet(panels, path, scale=2):
    """panels: [(label, Image)] — two rows of labelled native frames."""
    w, h = panels[0][1].size
    pad, lab = 10, 20
    out = Image.new("RGB", (w * scale + 2 * pad,
                            (h * scale + lab + pad) * len(panels) + pad),
                    (24, 26, 32))
    d = ImageDraw.Draw(out)
    f = font(11)
    for i, (label, im) in enumerate(panels):
        y = pad + i * (h * scale + lab + pad)
        d.text((pad + 2, y), label, font=f, fill=(238, 232, 210))
        out.paste(im.resize((w * scale, h * scale), Image.NEAREST),
                  (pad, y + lab))
    out.save(path)
    return out


def main():
    before = load(FRAMES / "15_shepherd_dialogue.png")
    after = load(FRAMES / "16_shepherd_cinematic.png")
    assert before.size == after.size == (320, 180), (before.size, after.size)

    report = {
        "15_shepherd_dialogue": metrics(before),
        "16_shepherd_cinematic": metrics(after),
    }
    panels = [
        ("BEFORE — classic art, real engine frame 15", before),
        ("AFTER — Direction C integrated, real engine frame 16", after),
    ]
    sheet(panels, DIAG / "04_before_after_real_engine.png")
    sheet([(label, ImageOps.grayscale(im).convert("RGB"))
           for label, im in panels],
          DIAG / "05_before_after_grayscale.png")

    # The previous checkpoint (c5dbc69) had palette + UI but no crafted art.
    # Keep it in the comparison so the craft pass is measured against BOTH the
    # original and the failed palette-only attempt.
    palette = COMP / "16_palette_only.png"
    if palette.exists():
        p = load(palette)
        report["16_palette_only"] = metrics(p)
        sheet([
            ("PALETTE + UI ONLY — CI 42772672515 (world value spread 10.6)", p),
            ("+ HAND-AUTHORED ART, SHADOWS, DEPTH — current CI frame 16", after),
        ], DIAG / "08_palette_vs_craft.png")
    # The first craft attempt put its value planes outside the visible world
    # band and measured WORSE (8.0). Keep it so the iteration is auditable.
    v1 = COMP / "16_craft_v1.png"
    if v1.exists():
        q = load(v1)
        report["16_craft_v1"] = metrics(q)
        sheet([
            ("CRAFT v1 — depth planes outside the visible world (spread 8.0)", q),
            ("CRAFT v3 — final value planes, real CI frame 16", after),
        ], DIAG / "09_craft_iteration.png")
    v2 = COMP / "16_craft_v2.png"
    if v2.exists():
        r = load(v2)
        report["16_craft_v2"] = metrics(r)
        sheet([
            ("CRAFT v2 — three planes correctly placed, too weak (spread 12.3)", r),
            ("CRAFT v4 — graded band, irregular edges (current CI)", after),
        ], DIAG / "10_craft_iteration2.png")
    v3 = COMP / "16_craft_v3.png"
    if v3.exists():
        s = load(v3)
        report["16_craft_v3"] = metrics(s)
        sheet([
            ("CRAFT v3 — stronger values but a hard horizontal stripe (17.1)", s),
            ("CRAFT v4 — same values, graded band and organic edges", after),
        ], DIAG / "11_craft_iteration3.png")
    # The last Direction-C frame, before the user overrode the direction.
    cfinal = COMP / "16_storybook_final.png"
    if cfinal.exists():
        cf = load(cfinal)
        report["16_storybook_final"] = metrics(cf)
        sheet([
            ("DIRECTION C — assistant's selection, final craft pass", cf),
            ("DIRECTION B — user-selected cinematic, current CI frame 16", after),
        ], DIAG / "14_direction_override.png")

    # The user-selected direction must be reviewed at the same display sizes
    # and in grayscale as the original four-way comparison, not just measured.
    ref = ROOT / "docs/art-reset/user_selected_reference.png"
    ref_fit = (ImageOps.fit(Image.open(ref).convert("RGB"), (320, 180),
                            method=Image.LANCZOS) if ref.exists() else after)
    if ref.exists():
        report["user_reference_B_concept_fit"] = metrics(ref_fit)
    review = {
        "native": after,
        "desktop": after.resize((1280, 720), Image.NEAREST),
    }
    mob = Image.new("RGB", (844, 390), (18, 20, 26))
    mw, mh = 694, 390
    mob.paste(after.resize((mw, mh), Image.NEAREST), ((844 - mw) // 2, 0))
    review["mobile"] = mob
    for key, im in review.items():
        im.save(COMP / f"B_engine_{key}.png")
        ImageOps.grayscale(im).convert("RGB").save(
            COMP / f"B_engine_grayscale_{key}.png")
    # The user's actual reference, side by side with the real B engine frame.
    # This is the honest gap check: a painterly concept is NOT a shipped asset.
    sheet([
        ("USER REFERENCE — Direction B concept, painted, 681x348", ref_fit),
        ("REAL ENGINE — Direction B opt-in frame 16, 320x180", after),
    ], DIAG / "16_B_engine_vs_reference.png")
    ImageOps.grayscale(
        Image.open(DIAG / "16_B_engine_vs_reference.png").convert("RGB")
    ).save(DIAG / "17_B_engine_vs_reference_grayscale.png")

    # 2x2 progression sheet: classic -> C -> B real -> B concept reference.
    classic = load(FRAMES / "15_shepherd_dialogue.png")
    panels4 = [
        ("CLASSIC (frame 15)", classic),
        ("DIRECTION C (assistant-selected)", cf if cfinal.exists() else classic),
        ("DIRECTION B (user-selected, REAL ENGINE)", after),
        ("DIRECTION B CONCEPT (painted reference)", ref_fit),
    ]
    grid = Image.new("RGB", (2 * 640 + 30, 2 * (360 + 26) + 20), (24, 26, 32))
    gd = ImageDraw.Draw(grid)
    ff = font(12)
    for i, (label, im) in enumerate(panels4):
        x = 10 + (i % 2) * 650
        y = 10 + (i // 2) * 386
        gd.text((x + 2, y), label, font=ff, fill=(238, 232, 210))
        grid.paste(im.resize((640, 360), Image.NEAREST), (x, y + 22))
    grid.save(DIAG / "15_direction_progression_2x.png")

    out = COMP / "real_engine_metrics.json"
    out.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    print("wrote", out.relative_to(ROOT))
    print("world_value_spread: classic",
          report["15_shepherd_dialogue"]["world_value_spread"],
          "-> integrated",
          report["16_shepherd_cinematic"]["world_value_spread"])


if __name__ == "__main__":
    main()
