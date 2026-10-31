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
CHAR_H = 16        # character cell height — ONE tile, like the reference pack.
# Was 24 (1.5 tiles). The extra height bought depth overlap and cost the whole
# look: at 16x24 the head is a sixth of the figure and the body is a slab. The
# hand-drawn reference is 16x16 with a head that is nearly half the sprite, and
# that proportion is most of why it reads as a character instead of a peg.

DIRS = ["down", "left", "right", "up"]
