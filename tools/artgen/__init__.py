"""artgen — procedural, palette-locked pixel art for WalkInCovenant.

Why generate art instead of drawing it or downloading it:

  * Budget is US$0 and the author works spare-time solo (docs/PLAN.md §6).
  * The sandbox that builds this cannot reach itch.io, so the CC0 packs
    recommended in docs/ART.md are not available at generation time.
  * Most importantly: generated art is grid-locked and palette-locked BY
    CONSTRUCTION. Every pixel lands on the 16px grid and every colour comes
    from palette.RAMPS. That is precisely the consistency AI image models
    cannot deliver and that hand-mixing free packs usually loses.

The output format deliberately matches what a real pack provides — uniform-cell
atlas PNGs — so swapping in Ninja Adventure later is a file replacement, not a
rewrite. See docs/ART.md §3.
"""

from .canvas import Canvas, atlas, save_atlas
from .palette import RAMPS, c, ramp, blend, shade, OUTLINE, SHADOW

TILE = 16          # the one true tile size, project-wide
CHAR_W = 16        # character cell width
CHAR_H = 24        # character cell height (1.5 tiles — allows depth overlap)

DIRS = ["down", "left", "right", "up"]
