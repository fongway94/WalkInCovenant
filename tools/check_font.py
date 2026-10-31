#!/usr/bin/env python3
"""check_font.py — CI gate: no character the game can show may be missing
from the bundled font.

The web export has no system fonts to fall back on, so a glyph absent from
fonts/game.ttf renders as tofu on every player's screen. This gate reads the
ACTUAL cmap table out of fonts/game.ttf — with nothing but the standard
library, so the CI container needs no fonttools — and compares it against
every character data/**/*.json and the non-ASCII prose of scripts/**/*.gd can
put on screen.

Why the font itself and not fonts/game.charset.txt: the charset file records
what the subsetter was ASKED for, not what it produced. Noto Sans SC has no ✧
(U+2727), the subsetter dropped it without a word, the charset still listed
it — and the HUD's verse counter shipped as tofu with every gate green. The
bytes are the only honest record. (build_font.py now verifies its own output
too; this gate is the second lock, and the one that runs in CI.)

Exit 0: every character the game can show maps to a real glyph in the font.
Exit 1: something would render as tofu; the message names the characters and
the command that fixes it.
"""

import pathlib
import struct
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FONT = ROOT / "fonts" / "game.ttf"


def shipped_chars() -> set:
    chars = set(chr(c) for c in range(0x20, 0x7F))
    for p in sorted((ROOT / "data").rglob("*.json")):
        chars |= set(p.read_text(encoding="utf-8"))
    for p in sorted((ROOT / "scripts").rglob("*.gd")):
        chars |= set(ch for ch in p.read_text(encoding="utf-8") if ord(ch) > 0x7F)
    chars -= set("\r\n\t")
    return chars


def _tables(data: bytes) -> dict:
    num = struct.unpack(">H", data[4:6])[0]
    out = {}
    for i in range(num):
        off = 12 + i * 16
        tag = data[off:off + 4].decode("latin1")
        t_off, t_len = struct.unpack(">II", data[off + 8:off + 16])
        out[tag] = (t_off, t_len)
    return out


def _cmap_fmt4(data: bytes, f_off: int) -> dict:
    """Decode a format-4 subtable honestly: idDelta AND idRangeOffset, so a
    codepoint only counts when it maps to a real glyph (id != 0)."""
    seg_x2 = struct.unpack(">H", data[f_off + 6:f_off + 8])[0]
    n = seg_x2 // 2
    ends = struct.unpack(">%dH" % n, data[f_off + 14:f_off + 14 + seg_x2])
    starts = struct.unpack(">%dH" % n, data[f_off + 16 + seg_x2:f_off + 16 + 2 * seg_x2])
    deltas = struct.unpack(">%dh" % n, data[f_off + 16 + 2 * seg_x2:f_off + 16 + 3 * seg_x2])
    roffs = struct.unpack(">%dH" % n, data[f_off + 16 + 3 * seg_x2:f_off + 16 + 4 * seg_x2])
    ro_base = f_off + 16 + 3 * seg_x2
    out = {}
    for i in range(n):
        for cp in range(starts[i], ends[i] + 1):
            if cp == 0xFFFF:
                continue
            if roffs[i] == 0:
                gid = (cp + deltas[i]) & 0xFFFF
            else:
                addr = ro_base + i * 2 + roffs[i] + (cp - starts[i]) * 2
                g = struct.unpack(">H", data[addr:addr + 2])[0]
                gid = (g + deltas[i]) & 0xFFFF if g else 0
            if gid:
                out[cp] = gid
    return out


def _cmap_fmt12(data: bytes, f_off: int) -> dict:
    n_groups = struct.unpack(">I", data[f_off + 12:f_off + 16])[0]
    out = {}
    for g in range(n_groups):
        s, e, gi = struct.unpack(">III", data[f_off + 16 + g * 12:f_off + 28 + g * 12])
        for cp in range(s, e + 1):
            out[cp] = gi + (cp - s)
    return {cp: gi for cp, gi in out.items() if gi}


def font_glyphs(path: pathlib.Path) -> dict:
    """{codepoint: glyph id} for every codepoint the font really renders."""
    data = path.read_bytes()
    tables = _tables(data)
    if "cmap" not in tables:
        raise ValueError("%s has no cmap table" % path.name)
    c_off = tables["cmap"][0]
    n_sub = struct.unpack(">H", data[c_off + 2:c_off + 4])[0]
    best = None  # prefer (3,10)/fmt12, then (3,1) or (0,*) fmt4
    for i in range(n_sub):
        pid, eid, s_off = struct.unpack(">HHI", data[c_off + 4 + i * 8:c_off + 12 + i * 8])
        f_off = c_off + s_off
        fmt = struct.unpack(">H", data[f_off:f_off + 2])[0]
        if pid not in (0, 3) or fmt not in (4, 12):
            continue
        rank = (1 if fmt == 12 else 0)
        if best is None or rank > best[0]:
            best = (rank, fmt, f_off)
    if best is None:
        raise ValueError("%s has no usable Unicode cmap subtable" % path.name)
    _, fmt, f_off = best
    return _cmap_fmt12(data, f_off) if fmt == 12 else _cmap_fmt4(data, f_off)


def main() -> int:
    if not FONT.exists():
        print("check_font: FAIL — %s is missing; run python3 tools/build_font.py"
              % FONT.relative_to(ROOT))
        return 1
    try:
        glyphs = font_glyphs(FONT)
    except (ValueError, struct.error) as e:
        print("check_font: FAIL — could not read %s: %s" % (FONT.name, e))
        return 1
    missing = sorted(ch for ch in shipped_chars() if ord(ch) not in glyphs)
    if missing:
        print("check_font: FAIL — %d character(s) in data/ or scripts/ have no "
              "glyph in the bundled font and would render as tofu:" % len(missing))
        print("  %s" % "".join(missing[:60]))
        print("  fix: python3 tools/build_font.py && commit fonts/game.ttf "
              "fonts/game.charset.txt")
        print("  if build_font.py itself fails, the source face lacks the "
              "glyph — replace the character in the content (see EXTRA in "
              "tools/build_font.py for verified symbols).")
        return 1
    print("check_font: clean — every character the game can show has a glyph "
          "in the font (%d codepoints mapped)" % len(glyphs))
    return 0


if __name__ == "__main__":
    sys.exit(main())
