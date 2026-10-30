#!/usr/bin/env python3
"""check_font.py — CI gate: no character the game can show may be missing
from the bundled font.

The web export has no system fonts to fall back on, so a glyph absent from
fonts/game.ttf renders as tofu on every player's screen. The font is a subset
built by tools/build_font.py from the characters present in data/ and scripts/,
and fonts/game.charset.txt records exactly what it covers. This gate compares
the two sets with nothing but the standard library — the CI container has no
fonttools and never needs any.

Exit 0: every character in data/**/*.json and in the non-ASCII prose of
scripts/**/*.gd is inside the charset the font was built from.
Exit 1: something new was written and the font was not rebuilt; the message
names the characters and the command that fixes it.
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CHARSET = ROOT / "fonts" / "game.charset.txt"


def shipped_chars() -> set:
    chars = set(chr(c) for c in range(0x20, 0x7F))
    for p in sorted((ROOT / "data").rglob("*.json")):
        chars |= set(p.read_text(encoding="utf-8"))
    for p in sorted((ROOT / "scripts").rglob("*.gd")):
        chars |= set(ch for ch in p.read_text(encoding="utf-8") if ord(ch) > 0x7F)
    chars -= set("\r\n\t")
    return chars


def main() -> int:
    if not CHARSET.exists():
        print("check_font: FAIL — %s is missing; run python3 tools/build_font.py"
              % CHARSET.relative_to(ROOT))
        return 1
    covered = set(CHARSET.read_text(encoding="utf-8"))
    missing = sorted(shipped_chars() - covered)
    if missing:
        shown = "".join(missing[:60])
        print("check_font: FAIL — %d character(s) in data/ or scripts/ are not in "
              "the bundled font and would render as tofu:" % len(missing))
        print("  %s" % shown)
        print("  fix: python3 tools/build_font.py && commit fonts/game.ttf "
              "fonts/game.charset.txt")
        return 1
    print("check_font: clean — every character the game can show is in the font "
          "(%d covered)" % len(covered))
    return 0


if __name__ == "__main__":
    sys.exit(main())
