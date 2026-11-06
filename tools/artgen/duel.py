"""duel.py — large, drawn figures for the Goliath setpiece.

The fight used to take a 16x16 overworld sprite and stretch it to 128x128.
Eight-times-upscaled pixels are not a character: no face, no armour, no light,
and no scale contrast. These two sheets are drawn at the size the setpiece
actually shows them, from the same ramps, outline and top-left light as the
map. Goliath 64x64, David 32x32 — a genuine 2:1 difference on screen.

The forehead of each figure sits at ~30% of its height because
GoliathFight._head() aims the gold band there. Moving the head without updating
that function would break the one timing cue the whole duel depends on.
"""

from .canvas import Canvas
from .palette import c, OUTLINE

INK = c("hair_dark", 0)


def _goliath() -> Canvas:
    cv = Canvas(64, 64)

    # ── the spear: "the staff of whose spear was like a weaver's beam" ──
    # Behind the body, so the hand and the shoulder read in front of it.
    cv.vline(54, 2, 60, c("wood", 2))
    cv.vline(53, 4, 56, c("wood", 4))
    cv.vline(55, 4, 56, c("wood", 1))
    cv.tri(50, 1, 58, 1, 54, 13, c("iron", 4))
    cv.tri(52, 2, 56, 2, 54, 10, c("iron", 5))
    cv.hline(51, 34, 7, c("iron", 3))
    cv.px(54, 34, c("iron", 5))

    # ── legs and greaves ──
    for x, lit, dark in ((22, c("bronze", 3), c("bronze", 1)),
                         (36, c("bronze", 2), c("bronze", 0))):
        cv.rect(x, 48, 9, 13, dark)
        cv.vline(x, 48, 13, lit)
        cv.hline(x, 48, 9, lit)
        cv.hline(x, 55, 9, c("bronze", 3))
        cv.hline(x, 60, 9, c("bronze", 0))
        cv.hline(x - 1, 61, 11, c("wood", 2))
        cv.hline(x - 1, 62, 11, c("wood", 1))

    # ── kilt / tunic under the armour, with real pleats ──
    cv.rect(20, 39, 26, 10, c("linen", 1))
    for x in range(22, 45, 4):
        cv.vline(x, 40, 9, c("linen", 2))
        cv.px(x + 1, 47, c("linen", 0))
    cv.hline(19, 39, 28, c("gold", 2))
    cv.hline(19, 40, 28, c("gold", 1))
    cv.rect(30, 39, 5, 3, c("gold", 4))
    cv.px(32, 40, c("blood", 2))

    # ── scale armour: three rows of overlapping plates, not a flat slab ──
    cv.rect(20, 27, 26, 12, c("bronze", 2))
    cv.vline(20, 27, 12, c("bronze", 4))
    cv.vline(21, 28, 10, c("bronze", 3))
    cv.vline(45, 27, 12, c("bronze", 0))
    for row, y in enumerate((29, 33, 37)):
        for x in range(23 + (row % 2) * 2, 45, 6):
            cv.hline(x, y, 4, c("bronze", 3))
            cv.px(x, y + 1, c("bronze", 1))
            cv.px(x + 3, y, c("bronze", 4))
    cv.hline(22, 27, 22, c("bronze", 4))

    # ── shoulders, arms, and the hand that holds the spear ──
    cv.rect(15, 26, 8, 6, c("bronze", 3))
    cv.rect(43, 26, 8, 6, c("bronze", 1))
    cv.hline(15, 26, 8, c("bronze", 4))
    cv.rect(14, 31, 5, 10, c("skin", 3))
    cv.vline(14, 31, 10, c("skin", 4))
    cv.rect(48, 31, 5, 9, c("skin", 2))
    cv.vline(51, 31, 9, c("skin", 3))
    cv.rect(51, 31, 6, 5, c("skin", 3))       # grip closes over the shaft
    cv.hline(51, 31, 6, c("skin", 4))
    cv.hline(14, 39, 5, c("gold", 2))         # armband
    cv.hline(48, 39, 5, c("gold", 1))

    # ── neck and head. cy=18 puts the eye line at 0.30*64, where the band is ──
    cv.rect(29, 23, 8, 5, c("skin", 2))
    cv.hline(30, 23, 6, c("skin", 3))
    cv.ellipse(32, 18, 9, 10, c("skin", 4), fill=True)
    cv.ellipse(30, 16, 7, 8, c("skin", 5), fill=True)
    cv.vline(41, 15, 7, c("skin", 2))
    cv.hline(26, 27, 13, c("skin", 2))
    # heavy brow, two eyes, a nose that breaks the profile
    cv.hline(27, 16, 5, INK)
    cv.hline(35, 16, 5, INK)
    cv.px(27, 15, INK); cv.px(39, 15, INK)
    cv.rect(28, 18, 2, 2, INK)
    cv.rect(36, 18, 2, 2, INK)
    cv.px(28, 18, c("linen", 3)); cv.px(36, 18, c("linen", 3))
    cv.vline(33, 19, 3, c("skin", 3))
    cv.hline(30, 23, 5, c("skin", 1))
    # a thick, dark beard, and a scar across the right cheek
    cv.tri(25, 22, 40, 22, 32, 33, c("hair_dark", 2))
    cv.hline(27, 23, 11, c("hair_dark", 3))
    cv.line(38, 19, 40, 24, c("blood", 2))
    cv.px(38, 19, c("blood", 3))

    # ── bronze helm, cheek guards and a champion's crest ──
    cv.rect(22, 7, 21, 8, c("bronze", 2))
    cv.hline(23, 7, 19, c("bronze", 4))
    cv.hline(22, 14, 21, c("bronze", 1))
    cv.vline(22, 13, 10, c("bronze", 1))
    cv.vline(42, 13, 10, c("bronze", 0))
    cv.vline(32, 12, 5, c("bronze", 3))       # nose guard
    cv.px(32, 12, c("bronze", 4))
    for dx in (-6, -2, 2, 6):
        cv.vline(32 + dx, 1, 7, c("blood", 2))
        cv.px(32 + dx, 1, c("blood", 3))
    cv.hline(25, 5, 15, c("bronze", 3))
    cv.px(28, 8, c("bronze", 4)); cv.px(36, 8, c("bronze", 4))

    cv.outline(OUTLINE)
    return cv


def _david() -> Canvas:
    cv = Canvas(32, 32)

    # ── legs, sandals, and the short shepherd's tunic ──
    for x, col in ((12, c("skin", 3)), (18, c("skin", 2))):
        cv.rect(x, 23, 4, 7, col)
        cv.hline(x - 1, 30, 6, c("wood", 2))
        cv.hline(x - 1, 31, 6, c("wood", 1))
    cv.rect(10, 14, 13, 10, c("robe_david", 2))
    cv.vline(10, 14, 10, c("robe_david", 4))
    cv.vline(22, 14, 10, c("robe_david", 1))
    cv.hline(10, 22, 13, c("wool", 2))
    cv.hline(11, 23, 11, c("wool", 1))
    cv.px(16, 22, c("gold", 3))

    # ── the wool mantle over one shoulder, and the shepherd's bag ──
    cv.hline(9, 13, 14, c("wool", 1))
    cv.hline(9, 14, 4, c("wool", 2))
    cv.line(10, 15, 14, 20, c("wool", 2))
    cv.px(11, 13, c("wool", 3))
    cv.rect(7, 20, 4, 4, c("wool", 2))
    cv.hline(7, 20, 4, c("wool", 3))
    cv.px(8, 22, c("stone", 3))
    cv.line(12, 15, 9, 20, c("wood", 2))

    # ── the throwing arm, raised, with a sling and a stone ──
    cv.line(21, 16, 27, 10, c("skin", 4))
    cv.line(22, 17, 28, 11, c("skin", 3))
    cv.rect(26, 8, 3, 3, c("skin", 4))
    cv.line(27, 8, 30, 3, c("wool", 1))
    cv.line(27, 8, 24, 3, c("wool", 3))
    cv.circle(27, 4, 1, c("stone", 3), fill=True)
    cv.px(30, 3, c("wool", 3))

    # ── head at ~30% of the height, the same proportion as the giant ──
    cv.rect(14, 12, 5, 3, c("skin", 3))
    cv.ellipse(16, 9, 6, 6, c("skin", 5), fill=True)
    cv.ellipse(14, 8, 4, 4, c("skin", 5), fill=True)
    cv.px(21, 9, c("skin", 3))
    # red hair, a short fringe, no beard — the youngest person on this field
    cv.rect(10, 3, 12, 4, c("hair_red", 2))
    cv.hline(11, 3, 9, c("hair_red", 3))
    cv.hline(10, 7, 5, c("hair_red", 2))
    cv.px(10, 8, c("hair_red", 1))
    cv.vline(21, 5, 4, c("hair_red", 1))
    # one eye and a firm brow, seen in profile toward the giant
    cv.hline(18, 8, 3, INK)
    cv.rect(18, 10, 2, 2, INK)
    cv.px(18, 10, c("linen", 3))
    cv.px(21, 11, c("skin", 4))
    cv.hline(17, 13, 3, c("skin", 2))

    cv.outline(OUTLINE)
    return cv


def build_duel() -> dict:
    return {"goliath": _goliath(), "david": _david()}
