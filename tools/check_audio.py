#!/usr/bin/env python3
"""check_audio.py — the CI face of `tools/build_audio.py --check`.

The static gate runs one file per name (`python3 tools/check_audio.py`), so the
real verifier stays with the generator it belongs to and this file only forwards.
It checks two different things, and both matter:

  1. the shelf is valid — mono 22.05 kHz 16-bit, not silent, not clipping;
  2. the shelf answers the game — every `play_sfx("…")`, every terrain sound in
     `data/tiles.json` and every `music` key in a region file has a file.

A complete-but-stale shelf is a game with no sound, which is exactly the state
this repository shipped in for months, so the second check is the one that earns
its keep.
"""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import build_audio  # noqa: E402

if __name__ == "__main__":
    build_audio.check()
