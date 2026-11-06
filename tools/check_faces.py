#!/usr/bin/env python3
"""check_faces.py — the dialogue portraits really exist, are palette-locked,
are all different people, and are actually wired into the shipped dialogue box.

This is a real gate, not a file-count assertion. It catches the four ways a
premium portrait pass quietly rots:

  * an actor added to data/regions/*.json with no drawn face (falls back to a
    16x16 walking sprite, so the box looks cheap again and nothing fails);
  * a portrait that leaves the palette (a one-off colour that fights the rest
    of the game every time it is on screen);
  * a copy-paste portrait (two major characters with the same face in one
    scene — the exact complaint this pass exists to fix);
  * the UI reverting to the old `_set_portrait()` sprite path.

It also regenerates every face in memory and compares it byte-for-byte with the
PNG on disk, so "deterministic" is verified rather than claimed in a comment.
"""

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from PIL import Image  # noqa: E402
from tools.artgen import faces as F  # noqa: E402
from tools.artgen.palette import ALL, OUTLINE, RAMPS  # noqa: E402

ALLOWED = set(h.lower() for h in ALL) | {OUTLINE.lower()}
SKIN = set(h.lower() for h in RAMPS["skin"])


def rgb_hex(px):
    return "#%02x%02x%02x" % (px[0], px[1], px[2])


def actors_in_data():
    out = set()
    for path in sorted((ROOT / "data").rglob("*.json")):
        doc = json.loads(path.read_text(encoding="utf-8"))
        stack = [doc]
        while stack:
            node = stack.pop()
            if isinstance(node, dict):
                if "actor" in node and isinstance(node["actor"], str):
                    out.add(node["actor"])
                stack.extend(node.values())
            elif isinstance(node, list):
                stack.extend(node)
    return out


def main() -> int:
    errs = []
    folder = ROOT / "art" / "facesets"
    needed = actors_in_data() | set(F.FACES)
    expected = F.build_faces()

    for actor in sorted(needed):
        p = folder / ("%s.png" % actor)
        if not p.is_file():
            errs.append("missing portrait: art/facesets/%s.png" % actor)
            continue
        im = Image.open(p).convert("RGBA")
        if im.size != (F.W, F.H):
            errs.append("%s.png is %s, expected %dx%d" % (actor, im.size, F.W, F.H))
            continue
        px = im.load()
        cols = set()
        opaque = True
        for y in range(im.height):
            for x in range(im.width):
                p4 = px[x, y]
                cols.add(rgb_hex(p4))
                if p4[3] != 255:
                    opaque = False
        if not opaque:
            errs.append("%s.png has transparent pixels — the panel shows through" % actor)
        bad = cols - ALLOWED
        if bad:
            errs.append("%s.png uses %d off-palette colour(s): %s"
                        % (actor, len(bad), ", ".join(sorted(bad)[:4])))
        if len(cols) < 12:
            errs.append("%s.png has only %d colours — too flat to read as a face"
                        % (actor, len(cols)))
        if not cols & SKIN:
            errs.append("%s.png has no skin pixels" % actor)
        if OUTLINE.lower() not in cols:
            errs.append("%s.png has no outline" % actor)
        # determinism: the generator must reproduce exactly what ships
        if actor in expected:
            live = expected[actor].to_image().convert("RGBA")
            if live.tobytes() != im.tobytes():
                errs.append("%s.png is stale — regenerate with `python3 -m "
                            "tools.artgen.build faces`" % actor)

    # distinct faces: no two major actors may share one drawing
    digests = {}
    for actor in sorted(needed):
        p = folder / ("%s.png" % actor)
        if p.is_file():
            d = p.read_bytes()
            if d in digests:
                errs.append("%s.png is a byte-for-byte copy of %s.png"
                            % (actor, digests[d]))
            digests[d] = actor

    # the duel must use its own drawn figures, not 8x-upscaled 16x16 sprites
    from tools.artgen import duel as D  # noqa: E402
    duel_expected = D.build_duel()
    for name, cv in duel_expected.items():
        p = ROOT / "art" / "duel" / ("%s.png" % name)
        if not p.is_file():
            errs.append("missing duel figure: art/duel/%s.png" % name)
            continue
        im = Image.open(p).convert("RGBA")
        if im.size != (cv.w, cv.h):
            errs.append("%s duel figure is %s, expected %dx%d"
                        % (name, im.size, cv.w, cv.h))
        if im.tobytes() != cv.to_image().tobytes():
            errs.append("%s duel figure is stale — regenerate with "
                        "`python3 -m tools.artgen.build duel`" % name)
        px = im.load()
        # transparent pixels are background, not a colour choice: skip them
        cols = {rgb_hex(px[x, y])
                for y in range(im.height) for x in range(im.width)
                if px[x, y][3] != 0}
        off = cols - ALLOWED
        if off:
            errs.append("art/duel/%s.png uses %d off-palette colour(s)"
                        % (name, len(off)))
    fight = (ROOT / "scripts" / "setpiece" / "GoliathFight.gd").read_text(encoding="utf-8")
    for name in ("goliath", "david"):
        if 'preload("res://art/duel/%s.png")' % name not in fight:
            errs.append("GoliathFight does not preload art/duel/%s.png" % name)

    # Every named actor must be a STATIC preload in the dialogue box. A
    # computed `load("res://...%s...")` path is invisible to Godot's export
    # dependency scanner, so the web build would silently lose the faces.
    box = (ROOT / "scripts" / "story" / "DialogueBox.gd").read_text(encoding="utf-8")
    setter = box[box.find("func _set_portrait"):]
    if "FACES.has(actor)" not in setter:
        errs.append("DialogueBox._set_portrait() no longer uses the drawn portraits")
    if setter.find("FACES") > setter.find("_idle.png") >= 0:
        errs.append("DialogueBox._set_portrait() tries the sprite before the portrait")
    table = box[box.find("const FACES"):]
    for actor in sorted(needed):
        line = '"%s": preload("res://art/facesets/%s.png")' % (actor, actor)
        if line not in table:
            errs.append("DialogueBox.FACES has no preload for %s" % actor)

    if errs:
        for e in errs:
            print("  FAIL %s" % e)
        print("check_faces: %d problem(s)" % len(errs))
        return 1
    print("check_faces: clean — %d portraits, %d named actors, %d duel figures; "
          "palette-locked, distinct, deterministic, wired into the game"
          % (len(list(folder.glob("*.png"))), len(needed), len(duel_expected)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
