#!/usr/bin/env python3
"""build_font.py — subset a CJK font down to exactly what this game ships.

WHY: the web build rendered every Chinese character as tofu. Nothing in the
project bundled a font, so the export fell back to Godot's built-in one, which
has Latin only. A full Simplified-Chinese face is ~8 MB, which is a third of the
web budget on its own; but the game's prose is finite and lives in data/**/*.json
and the string literals in scripts/**/*.gd, so the font can be subset to exactly
those glyphs (~1 MB) without losing a single readable character.

The subset is only honest as long as it is REGENERATED when content changes, so
this writes fonts/game.charset.txt next to the font and tools/check_font.py —
pure stdlib, no fonttools needed — fails CI the moment any character in data or
scripts is not in that charset. Add a line of Chinese, forget the font, and the
build goes red instead of shipping tofu.

USAGE (needs fonttools; CI never runs this, the outputs are committed):

    python3 tools/build_font.py [path/to/NotoSansSC-Regular.otf]

Source of the face: googlefonts/noto-cjk, Sans/SubsetOTF/SC, SIL Open Font
License 1.1 — see fonts/LICENSE-OFL.txt. Sparse-cloneable through github.com:

    git clone --depth 1 --filter=blob:none --sparse https://github.com/googlefonts/noto-cjk
    cd noto-cjk && git sparse-checkout set Sans/SubsetOTF/SC
"""

import pathlib
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "fonts" / "game.ttf"
CHARSET = ROOT / "fonts" / "game.charset.txt"

# CJK punctuation and symbols the prose reaches for even where a file happens
# not to contain one yet; cheaper to carry them than to rediscover tofu.
# NOTE: every one of these was verified present in Noto Sans SC — a symbol the
# source face lacks is silently dropped by the subsetter (✧ U+2727 shipped as
# tofu in the HUD for exactly that reason). verify() below now fails the build
# instead, but pick from this list when writing new UI chrome.
EXTRA = set("「」『』【】《》〈〉—–…·、，。！？；：（）〈〉％＋×÷・〜★☆※◆◇●○▲■□")


def verify(chars: set) -> int:
    """Every collected char must really be in the OUTPUT font's cmap.

    The subsetter drops whatever the SOURCE face lacks without a word, and the
    charset file used to record the promise instead of the outcome — which is
    how ✧ reached players as tofu with every gate green. Read the built font
    back and fail loudly if the promise and the bytes disagree.
    """
    from fontTools.ttLib import TTFont
    cmap = TTFont(str(OUT), fontNumber=0, lazy=True).getBestCmap()
    missing = sorted(ch for ch in chars if ord(ch) not in cmap)
    if missing:
        shown = "".join(missing[:40])
        print("build_font: FAIL — %d character(s) are not in the built font; "
              "the source face has no glyph for them and they would ship as "
              "tofu:" % len(missing))
        print("  %s" % shown)
        print("  replace them in data/scripts with a glyph the font carries "
              "(see EXTRA), or pick another source face.")
        return 1
    return 0


def collect_chars() -> set:
    """Every character the shipped game can put on screen."""
    chars = set(chr(c) for c in range(0x20, 0x7F))   # printable ASCII
    for p in sorted((ROOT / "data").rglob("*.json")):
        chars |= set(p.read_text(encoding="utf-8"))
    for p in sorted((ROOT / "scripts").rglob("*.gd")):
        # non-ASCII in the scripts is Chinese prose in string literals
        chars |= set(ch for ch in p.read_text(encoding="utf-8") if ord(ch) > 0x7F)
    chars |= EXTRA
    chars -= set("\r\n\t")
    return chars


def main() -> int:
    src = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else \
        pathlib.Path("/tmp/noto-cjk/Sans/SubsetOTF/SC/NotoSansSC-Regular.otf")
    if not src.exists():
        print("build_font: source face not found: %s" % src)
        print("  git clone --depth 1 --filter=blob:none --sparse "
              "https://github.com/googlefonts/noto-cjk")
        print("  cd noto-cjk && git sparse-checkout set Sans/SubsetOTF/SC")
        return 1
    try:
        from fontTools import subset
    except ImportError:
        print("build_font: needs fonttools: pip install fonttools")
        return 1

    chars = collect_chars()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False,
                                     encoding="utf-8") as tf:
        tf.write("".join(sorted(chars)))
        textfile = tf.name

    subset.main([
        str(src),
        "--text-file=%s" % textfile,
        "--output-file=%s" % OUT,
        "--no-hinting",          # pixel display, integer scaling: hinting only adds bytes
        "--desubroutinize",      # CFF subroutines defeat subsetting; flatten them
        "--notdef-outline",      # keep a visible .notdef so a miss is a box, not a hole
        "--layout-features=kern,liga",
        "--name-IDs=1,2,3,4,6",
    ])
    if verify(chars) != 0:
        return 1
    CHARSET.write_text("".join(sorted(chars)), encoding="utf-8")
    print("build_font: %d glyphs -> %s (%d KB); charset in %s"
          % (len(chars), OUT.relative_to(ROOT), OUT.stat().st_size // 1024,
             CHARSET.relative_to(ROOT)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
