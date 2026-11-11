#!/usr/bin/env python3
"""check_faces.py — portraits and duel figures really exist, are palette-locked,
are all different people, are the reviewed generated output, and are wired into
the shipped game.

Standard library ONLY. The lint job runs inside a Godot CI container where pip
is unavailable, so a gate that needs Pillow would either fail the build or (much
worse) be skipped. PNG decoding is borrowed from tools/char_variants.py, which
already does this with zlib alone.

    python3 tools/check_faces.py                 # CI / local gate
    python3 tools/check_faces.py --write-hashes # accept a deliberate art change

The hash manifest (`data/art_hashes.json`) covers the generator sources as well
as every output PNG: editing faces.py without regenerating the art, or editing
one PNG by hand, both fail. With Pillow available locally the gate ALSO
regenerates every figure in memory and compares pixel-for-pixel, so
"deterministic" is verified rather than merely claimed.
"""

import hashlib
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "tools"))

import char_variants  # noqa: E402  — stdlib PNG reader, no Pillow

MANIFEST = ROOT / "data" / "art_hashes.json"
FACES_DIR = ROOT / "art" / "facesets"
DUEL_DIR = ROOT / "art" / "duel"
GENERATORS = ("tools/artgen/faces.py", "tools/artgen/duel.py")
SIZES = {"facesets": (32, 32), "duel/goliath": (64, 64), "duel/david": (32, 32)}

# Palette ramps parsed from the source of truth without importing the artgen
# package (which imports Pillow). This keeps the lint container honest.
def _palette():
    """Parse the hex literals straight out of palette.py, no import, no Pillow."""
    src = (ROOT / "tools" / "artgen" / "palette.py").read_text(encoding="utf-8")
    colours = {m.lower() for m in re.findall(r"#[0-9a-fA-F]{6}", src)}
    skin = set()
    outline = "#0a0e12"
    for line in src.splitlines():
        t = line.strip()
        if t.startswith('"skin"'):
            skin = {m.lower() for m in re.findall(r"#[0-9a-fA-F]{6}", t)}
        if t.startswith("OUTLINE"):
            hits = re.findall(r"#[0-9a-fA-F]{6}", t)
            if hits:
                outline = hits[0].lower()
    return colours | {outline}, skin, outline


ALLOWED, SKIN, OUTLINE = _palette()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def hex_at(rgba, i):
    return "#%02x%02x%02x" % (rgba[i], rgba[i + 1], rgba[i + 2])


def actors_in_data():
    out = set()
    for path in sorted((ROOT / "data").rglob("*.json")):
        if path.name == "art_hashes.json":
            continue
        doc = json.loads(path.read_text(encoding="utf-8"))
        stack = [doc]
        while stack:
            node = stack.pop()
            if isinstance(node, dict):
                if isinstance(node.get("actor"), str):
                    out.add(node["actor"])
                stack.extend(node.values())
            elif isinstance(node, list):
                stack.extend(node)
    # every idle sheet is a potential speaker, not only those named today
    for p in (ROOT / "art" / "characters").glob("*_idle.png"):
        out.add(p.name[: -len("_idle.png")])
    return out


def checked_files():
    files = sorted(FACES_DIR.glob("*.png")) + sorted(DUEL_DIR.glob("*.png"))
    return [p.relative_to(ROOT).as_posix() for p in files]


def write_hashes():
    doc = {"generators": {g: sha(ROOT / g) for g in GENERATORS},
           "files": {rel: sha(ROOT / rel) for rel in checked_files()}}
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(json.dumps(doc, indent=1, sort_keys=True) + "\n",
                        encoding="utf-8")
    print("wrote %s (%d generator(s), %d PNG(s))"
          % (MANIFEST.relative_to(ROOT), len(doc["generators"]), len(doc["files"])))
    return 0


def main() -> int:
    if "--write-hashes" in sys.argv:
        return write_hashes()
    errs = []
    needed = actors_in_data()

    # ── the reviewed output cannot drift silently ────────────────────────
    if not MANIFEST.is_file():
        errs.append("data/art_hashes.json is missing — run check_faces.py "
                    "--write-hashes after reviewing the art")
        man = {"generators": {}, "files": {}}
    else:
        man = json.loads(MANIFEST.read_text(encoding="utf-8"))
    for g in GENERATORS:
        if man["generators"].get(g) != sha(ROOT / g):
            errs.append("%s changed but the art was not regenerated "
                        "(and the manifest not reviewed)" % g)
    for rel in checked_files():
        if man["files"].get(rel) != sha(ROOT / rel):
            errs.append("%s is not the reviewed generated output" % rel)
    for rel in man["files"]:
        if not (ROOT / rel).is_file():
            errs.append("manifest lists %s but the file is gone" % rel)

    # ── every actor has a real, distinct, palette-locked drawing ─────────
    digests = {}
    for actor in sorted(needed):
        rel = "art/facesets/%s.png" % actor
        p = ROOT / rel
        if not p.is_file():
            errs.append("missing portrait: %s" % rel)
            continue
        w, h, rgba = char_variants.read_png(p)
        if (w, h) != SIZES["facesets"]:
            errs.append("%s is %dx%d, expected 32x32" % (rel, w, h))
            continue
        cols, opaque = set(), True
        for i in range(0, len(rgba), 4):
            cols.add(hex_at(rgba, i))
            if rgba[i + 3] != 255:
                opaque = False
        if not opaque:
            errs.append("%s has transparent pixels — the panel shows through" % rel)
        off = cols - ALLOWED
        if off:
            errs.append("%s uses %d off-palette colour(s): %s"
                        % (rel, len(off), ", ".join(sorted(off)[:4])))
        if len(cols) < 12:
            errs.append("%s has only %d colours — too flat to read as a face"
                        % (rel, len(cols)))
        if not cols & SKIN:
            errs.append("%s has no skin pixels" % rel)
        if OUTLINE not in cols:
            errs.append("%s has no outline" % rel)
        d = p.read_bytes()
        if d in digests:
            errs.append("%s is a byte-for-byte copy of %s" % (rel, digests[d]))
        digests[d] = rel

    for name, size in (("goliath", (64, 64)), ("david", (32, 32))):
        rel = "art/duel/%s.png" % name
        p = ROOT / rel
        if not p.is_file():
            errs.append("missing duel figure: %s" % rel)
            continue
        w, h, rgba = char_variants.read_png(p)
        if (w, h) != size:
            errs.append("%s is %dx%d, expected %dx%d" % (rel, w, h, size[0], size[1]))
        cols = {hex_at(rgba, i) for i in range(0, len(rgba), 4)
                if rgba[i + 3] != 0}
        off = cols - ALLOWED
        if off:
            errs.append("%s uses %d off-palette colour(s)" % (rel, len(off)))

    # ── statically preloaded, so the web export cannot lose them ─────────
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
    fight = (ROOT / "scripts" / "setpiece" / "GoliathFight.gd").read_text(encoding="utf-8")
    for name in ("goliath", "david"):
        if 'preload("res://art/duel/%s.png")' % name not in fight:
            errs.append("GoliathFight does not preload art/duel/%s.png" % name)

    # ── bonus, only where Pillow exists: regenerate and compare pixels ───
    regen = "skipped (Pillow not installed; hash manifest is the gate)"
    try:
        from tools.artgen import faces as F, duel as D  # noqa: E402
        from PIL import Image  # noqa: E402
        made = F.build_faces()
        for actor, cv in made.items():
            live = cv.to_image().tobytes()
            w, h, rgba = char_variants.read_png(FACES_DIR / ("%s.png" % actor))
            if bytes(rgba) != live or (w, h) != (cv.w, cv.h):
                errs.append("%s portrait does not match a fresh generation" % actor)
        for name, cv in D.build_duel().items():
            live = cv.to_image().tobytes()
            w, h, rgba = char_variants.read_png(DUEL_DIR / ("%s.png" % name))
            if bytes(rgba) != live or (w, h) != (cv.w, cv.h):
                errs.append("%s duel figure does not match a fresh generation" % name)
        regen = "verified by regeneration"
    except ImportError:
        pass

    if errs:
        for e in errs:
            print("  FAIL %s" % e)
        print("check_faces: %d problem(s)" % len(errs))
        return 1
    print("check_faces: clean — %d portraits, %d named actors, %d duel figures; "
          "palette-locked, distinct, wired into the game, determinism %s"
          % (len(list(FACES_DIR.glob("*.png"))), len(needed),
             len(list(DUEL_DIR.glob("*.png"))), regen))
    return 0


if __name__ == "__main__":
    sys.exit(main())
