#!/usr/bin/env python3
"""check_text_fit.py — no line of dialogue may fall off the dialogue box.

WHY: the box used to be a fixed 312x78 rectangle. Anything longer than about two
rows of Chinese ran past its bottom edge and was clipped, and the longest lines
in the game — the verses — were the ones most likely to be cut in half. That is
the "npc dialog box some will over the screen" report, and the reason some lines
read as broken sentences.

The box itself now grows to fit (scripts/story/DialogueBox.gd), so this gate is
about the other half of the problem: a line so long that the growing box eats the
screen and the player loses the world behind it. Content should be written in
beats, not paragraphs.

Model (deliberately the worst case, 320 px logical width):

    panel width      320 - 2*5 (margins) - 2*5 (content) = 300
    portrait + gap                                         =  35
    text width                                             = 258
    CJK glyph at font size 10                              =  10 px
    Latin glyph average                                     =  6 px

A line is reported when it needs more than MAX_ROWS rows. `\\n` is a hard break
and counts as a new row block, so deliberate two-beat lines are fine.

Usage:  python3 tools/check_text_fit.py [--max-rows 5]
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
# At the design size (320x180) ScreenFit.dialogue() gives a text column of
# 264 px: 311 box - 10 padding - 32 portrait - 5 gap, minus 4 px of slack for a
# wrap engine that breaks at word boundaries and this model that does not.
# DialogueBox also paginates, so this is an AUTHORING guide (write lines that fit
# one page); the box cannot overflow even if a line ignores it.
TEXT_W = 258.0
CJK_PX = 10.0
LAT_PX = 6.0
MAX_ROWS = 5


def rows_for(text: str) -> float:
    """Rows this string needs in the dialogue box, worst case."""
    total = 0.0
    for block in str(text).split("\n"):
        w = 0.0
        for ch in block:
            w += CJK_PX if ord(ch) > 0x2E80 else LAT_PX
        total += max(1.0, -(-w // TEXT_W))   # ceil
    return total


def walk(node, path, out):
    if isinstance(node, dict):
        if "zh" in node and "en" in node:
            out.append((path, node))
        else:
            for k, v in node.items():
                walk(v, "%s.%s" % (path, k) if path else str(k), out)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            walk(v, "%s[%d]" % (path, i), out)


def main() -> int:
    limit = MAX_ROWS
    if "--max-rows" in sys.argv:
        limit = int(sys.argv[sys.argv.index("--max-rows") + 1])
    bad = 0
    worst = []
    for region in sorted((ROOT / "data/regions").glob("*.json")):
        data = json.loads(region.read_text(encoding="utf-8"))
        found = []
        walk(data, "", found)
        for path, pair in found:
            # A verse is not a dialogue line: it is a card in the book and in
            # the fight, and both wrap and scroll on their own. Its quotations
            # still have to fit the box where somebody speaks them, and those
            # live in npcs[].lines, which stays checked.
            if path.startswith("words["):
                continue
            zh, en = str(pair.get("zh", "")), str(pair.get("en", ""))
            r = max(rows_for(zh), rows_for(en))
            if r > limit:
                bad += 1
                worst.append((r, region.name, path, zh))
    if bad == 0:
        print("check_text_fit: clean — every line fits the dialogue box at %d rows"
              % limit)
        return 0
    print("check_text_fit: %d line(s) need more than %d rows of a %dpx box:"
          % (bad, limit, int(TEXT_W)))
    for r, name, path, zh in sorted(worst, key=lambda t: -t[0])[:20]:
        print("  %.1f rows  %s%s" % (r, name, path))
        print("             %s" % zh[:70])
    print("  fix: split the beat into two lines — a box is one thought.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
