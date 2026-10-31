#!/usr/bin/env python3
"""check_chars.py — the CI face of `tools/char_variants.py --check`.

The static gate runs one file per tool, so this only forwards. It verifies that
every variant actor named in tools/char_variants.py has both sheets on disk, at
the rig's size, and that the sheet is actually a variant rather than a copy of
its rig (a copy would silently put two identical people in one scene).
"""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import char_variants  # noqa: E402

if __name__ == "__main__":
    char_variants.check()
