"""Characters — 16×16 sprite sheets, four directions, walk + idle.

This is the module that answers "why did the old world feel low quality".
Covenant drew its people as procedural vector lines; here they are real pixel
figures on a fixed grid with a fixed palette, an outline, top-left lighting,
and a genuine four-frame walk cycle whose feet actually swap.

Cell is 16×16 — one tile, like the reference pack. The figure stands on the
tile it occupies and the ground shadow does the depth work.

Sheet layout Godot expects (see build_sheets below):
    walk:  rows = down, left, right, up   cols = 4 frames   → 64×64
    idle:  rows = down, left, right, up   cols = 2 frames   → 32×64
"""

from . import CHAR_W, CHAR_H, DIRS
from .canvas import Canvas, atlas
from .palette import c, ramp, blend


# ────────────────────────────────────────────────────────────────────────
# walk-cycle phase tables
# ────────────────────────────────────────────────────────────────────────
# bob: body rises one pixel on the two "passing" frames. This vertical bob is
# most of what makes a 4-frame cycle read as walking rather than shuffling.
BOB = [0, 1, 0, 1]

# foot offsets. For front/back views the two feet separate vertically (one
# forward = lower on screen). For side views they separate horizontally.
FRONT_FEET = [((-1, 2), (2, 1)), ((-1, 1), (2, 1)), ((2, 2), (-1, 1)), ((-1, 1), (2, 1))]
# each entry: ((dx_near, dy_near), (dx_far, dy_far)) applied to the two feet
SIDE_FEET = [((1, 0), (-2, 0)), ((0, 1), (0, 1)), ((-2, 0), (1, 0)), ((0, 1), (0, 1))]
# near arm swings opposite the near leg
SIDE_ARM = [1, 0, -1, 0]


def _figure(dir_, frame, s):
    """One frame of one direction, in a 16x16 cell. `s` is a CHARS spec.

    ROW BUDGET — the whole design lives or dies here, so it is written out:

        0  hair crown (6 wide)
        1  hair (8 wide) + temple hair at 10 wide
        2  brow row: forehead skin, short fringe on the left, hair at the edges
        3  eyes: two 2px eyes, one row tall, in ink
        4  nose + mouth
        5  jaw (6 wide, one step darker)
        6  neck
        7  shoulders: the widest horizontal in the figure (10 px)
        8  torso
        9  torso
       10  torso
       11  belt: gold, the second-strongest horizontal
       12  legs
       13  legs
       14  legs
       15  sandals

    Head is six rows of sixteen, body nine, and the shoulders are as wide as
    the head with its temples. That is the balance the reference pack uses: a
    character at 16 px must be BOLD, not realistic. The earlier rejected casts
    failed for the opposite reasons — a 10-row head over a 4-row body (a
    toddler) and later a thin 8-wide silhouette (a peg).
    """
    cv = Canvas(CHAR_W, CHAR_H)

    robe = s["robe"]; skin = s.get("skin", "skin"); hair = s.get("hair", "hair_dark")
    trim = s.get("trim", "gold")
    big = s.get("big", False)

    def R(i): return c(robe, i)
    def S(i): return c(skin, i)
    def H(i): return c(hair, i)
    def T(i): return c(trim, i) if trim in ramp_names() else R(3)
    INK = c("hair_dark", 0)

    bob = BOB[frame] if s.get("bob", True) else 0
    face_dir = "down" if dir_ == "down" else ("up" if dir_ == "up" else "side")
    side = dir_ in ("left", "right")

    hw = 4                                  # head 8 wide: x 4..11
    hx = 8 - hw
    hy = bob
    cloth = s.get("headcloth", False)
    helm = s.get("helm", False)
    hair_on = not (helm or cloth)
    if helm:
        skull, lit, dark = c("iron", 2), c("iron", 4), c("iron", 1)
    elif cloth:
        skull, lit, dark = c("linen", 2), c("linen", 5), c("linen", 1)
    else:
        skull, lit, dark = H(2), H(3), H(1)

    FY, EY, MY, JY = hy + 2, hy + 3, hy + 4, hy + 5
    neck_on = not bob                        # the rise eats the neck row
    BY = hy + 6 + (1 if neck_on else 0)      # shoulders: row 7 grounded, 6 raised
    LY = BY + 5                              # legs: row 12 grounded, 11 raised

    # ── hair mass ─────────────────────────────────────────────────────────
    cv.hline(hx + 1, hy, hw * 2 - 2, skull)
    cv.hline(hx, hy + 1, hw * 2, skull)
    cv.px(hx + 1, hy, lit); cv.px(hx + 2, hy, lit)
    cv.px(hx, hy + 1, lit); cv.px(hx + 1, hy + 1, lit)
    cv.px(hx + hw * 2 - 1, hy + 1, dark)
    # temple hair one pixel wider than the skull: gives the head weight
    cv.px(hx - 1, hy + 1, lit if not hair_on else H(3))
    cv.px(hx + hw * 2, hy + 1, dark)
    cv.px(hx - 1, hy + 2, dark); cv.px(hx + hw * 2, hy + 2, dark)

    if helm:
        cv.hline(hx - 1, hy + 2, hw * 2 + 2, c("iron", 2))
        cv.hline(hx - 1, hy + 2, hw * 2 + 2, c("iron", 3))
        cv.px(hx, hy + 2, c("iron", 4))
        cv.hline(hx + hw - 1, hy + 3, 2, c("iron", 1))       # nose guard
        cv.px(hx + hw - 1, hy + 4, c("iron", 1))
        cv.px(hx + hw, hy + 4, c("iron", 1))
    elif cloth:
        cv.hline(hx - 1, hy + 1, hw * 2 + 2, c("linen", 3))
        cv.hline(hx - 1, hy + 2, hw * 2 + 2, c("linen", 2))
        cv.px(hx, hy + 1, c("linen", 5)); cv.px(hx + 3, hy + 2, c("linen", 5))
        cv.px(hx + hw * 2, hy + 2, c("linen", 1))
        cv.vline(hx + hw * 2, hy + 3, 3, c("linen", 2))      # tail down the back
    if s.get("crown"):
        # A band of gold across the brow, lit on one side. At eight pixels a
        # crown is a colour, not a shape — so it is two rows of gold above the
        # eyes, and the top row of the hair mass alternates to read as points.
        cv.hline(hx + 1, hy, hw * 2 - 2, c("gold", 3))
        cv.hline(hx - 1, hy + 1, hw * 2 + 2, c("gold", 2))
        cv.hline(hx - 1, hy, 1, c("gold", 2))
        cv.px(hx + 2, hy, c("gold", 4))
        cv.px(hx + hw * 2 - 2, hy, c("gold", 4))
    if s.get("veil"):
        cv.vline(hx - 1, hy + 2, 5, c("linen", 3))
        cv.vline(hx + hw * 2, hy + 2, 5, c("linen", 1))

    # ── face ──────────────────────────────────────────────────────────────
    if face_dir == "up":
        for y in range(FY, JY + 1):
            cv.hline(hx, y, hw * 2, H(2))
        cv.hline(hx, FY, hw * 2, H(3))       # lit crown, seen from behind
        cv.px(hx + 1, FY, H(3))
        cv.vline(hx, FY + 1, 3, H(3))
        cv.hline(hx + 1, JY, hw * 2 - 2, H(1))
        cv.px(hx + hw * 2 - 1, FY + 2, H(1))
    else:
        for y in range(FY, JY + 1):
            cv.hline(hx, y, hw * 2, S(4))
        cv.hline(hx, FY, hw * 2, S(5))          # forehead catches the light
        cv.hline(hx + 1, JY, hw * 2 - 2, S(2))  # jaw turns under
        cv.px(hx, MY, S(3)); cv.px(hx + hw * 2 - 1, MY, S(3))
        if hair_on:
            # a short fringe over the LEFT brow only — the face is never covered
            cv.hline(hx, FY, 3, H(2))
            cv.px(hx, FY + 1, H(2))
            cv.px(hx + 3, FY, H(1))
            cv.px(hx + hw * 2 - 1, FY, dark)
        cv.px(hx, EY, S(3)); cv.px(hx + hw * 2 - 1, EY, S(3))   # temples

        if face_dir == "down":
            cv.hline(hx + 1, EY, 2, INK)            # left eye
            cv.hline(hx + 5, EY, 2, INK)            # right eye
            cv.px(hx + 1, EY - 1, H(1) if hair_on else dark)   # brows
            cv.px(hx + 6, EY - 1, H(1) if hair_on else dark)
            cv.hline(hx + 3, MY, 2, S(3))           # nose
            cv.hline(hx + 3, MY + 1, 2, S(2))       # mouth
        else:
            fx = hx + hw * 2 - 3 if dir_ == "right" else hx + 1
            out = 1 if dir_ == "right" else -1
            cv.hline(fx, EY, 2, INK)
            cv.px(fx, EY - 1, H(1) if hair_on else dark)
            cv.px(fx + (3 if out > 0 else -1), MY, S(5))    # nose breaks the edge
            cv.px(fx + (2 if out > 0 else 0), MY + 1, S(2))  # mouth
        if s.get("beard"):
            cv.hline(hx + 1, MY + 1, hw * 2 - 2, H(2))
            cv.hline(hx + 2, JY, hw * 2 - 4, H(1))
            cv.px(hx + 1, MY + 1, H(3))

    # ── neck ──────────────────────────────────────────────────────────────
    if neck_on:
        cv.hline(hx + 3, JY + 1, 3, S(3))
        cv.px(hx + 3, JY + 1, S(2))

    # ── torso ─────────────────────────────────────────────────────────────
    span = 12 if big else 10
    sx = 8 - span // 2
    cv.hline(sx, BY, span, R(3))
    cv.px(sx, BY, R(4)); cv.px(sx + 1, BY, R(4))
    cv.px(sx + span - 1, BY, R(2)); cv.px(sx + span - 2, BY, R(2))
    for i, w in enumerate((span - 2, span - 2, span - 3)):
        y = BY + 1 + i
        x0 = 8 - w // 2
        cv.hline(x0, y, w, R(3))
        cv.px(x0, y, R(4))                       # lit left edge
        cv.px(x0 + 1, y, R(4))
        cv.px(x0 + w - 1, y, R(2))               # shadow right edge
    # belt
    cv.hline(sx + 1, BY + 4, span - 2, T(3))
    cv.hline(sx + 2, BY + 4, span - 4, T(4))
    cv.px(sx + 1, BY + 4, T(2)); cv.px(sx + span - 2, BY + 4, T(1))
    # arms
    cv.vline(sx - 1, BY + 1, 3, R(3))
    cv.vline(sx + span, BY + 1, 3, R(2))
    if not side:
        cv.px(sx - 1, BY + 4, S(4)); cv.px(sx + span, BY + 4, S(3))
    else:
        sw = SIDE_ARM[frame]
        near_x = sx + span if dir_ == "right" else sx - 1
        cv.vline(near_x, BY + 1 + max(sw, 0), 3, R(3))
        cv.px(near_x, BY + 4 + max(sw, 0), S(4))

    # ── legs (rows 12-15) ─────────────────────────────────────────────────
    ground = CHAR_H - 1
    if not side:
        legs = [
            ((4, ground), (9, ground - 1)),
            ((4, ground - 1), (9, ground - 1)),
            ((4, ground - 1), (9, ground)),
            ((4, ground - 1), (9, ground - 1)),
        ][frame]
        for li, (x, foot) in enumerate(legs):
            col = R(2) if li == 0 else R(1)
            cv.rect(x, LY, 3, foot - LY, col)
            cv.px(x, LY, R(2))
            cv.px(x + 2, foot - 1, R(0))
            cv.hline(x - 1, foot, 4, c("wood", 2) if li == 0 else c("wood", 1))
            cv.px(x - 1, foot, c("wood", 3))
    else:
        swing = SIDE_FEET[frame][0][0]
        far_x = 7 - max(swing, 0)
        near_x = 5 + max(-swing, 0)
        lift = 0 if frame in (1, 3) else 1
        for x, foot, col in ((far_x, ground - lift, R(1)), (near_x, ground, R(2))):
            cv.rect(x, LY, 3, foot - LY, col)
            cv.px(x, LY, R(2))
            cv.hline(x - (1 if dir_ == "right" else 0), foot, 4, c("wood", 2))

    # ── carried ───────────────────────────────────────────────────────────
    if s.get("staff"):
        stx = (sx + span + 2) if side else (sx - 2)
        cv.vline(stx, hy + 1, CHAR_H - 2, c("wood", 2))
        cv.px(stx, hy + 1, c("wood", 4))
        cv.px(stx, hy + 2, c("wood", 3))
    if s.get("sling") and dir_ != "up":
        cv.line(sx + 2, BY + 1, sx + span - 3, BY + 4, c("wood", 2))
        cv.px(sx + span - 3, BY + 4, c("wood", 4))
    if s.get("scroll") and dir_ in ("down", "left"):
        cv.rect(sx - 2, BY, 2, 5, c("linen", 4))
        cv.px(sx - 2, BY, c("linen", 5))
        cv.px(sx - 2, BY + 4, c("linen", 5))

    cv.outline()
    return cv


def ramp_names():
    from .palette import RAMPS
    return RAMPS


# ────────────────────────────────────────────────────────────────────────
# the cast — robes inherited from Covenant's rig.js CHARS table
# ────────────────────────────────────────────────────────────────────────
CHARS = {
    "pilgrim": dict(robe="robe_pilgrim", skin="skin", hair="hair_dark",
                    trim="gold", headcloth=True, staff=True),
    "corin":   dict(robe="robe_scribe", skin="skin", hair="hair_dark",
                    trim="gold", hood=False, scroll=True),
    "soldier": dict(robe="robe_soldier", skin="skin", hair="hair_dark",
                    trim="iron", helm=True),
    "woman":   dict(robe="robe_woman", skin="skin", hair="hair_dark",
                    trim="gold", veil=True),
    "david":   dict(robe="robe_david", skin="skin", hair="hair_red",
                    trim="gold", sling=True),
    "elder":   dict(robe="robe_elder", skin="skin", hair="hair_grey",
                    trim="gold", beard=True),
    "priest":  dict(robe="robe_priest", skin="skin", hair="hair_dark",
                    trim="gold", headcloth=True),
    "pharisee": dict(robe="robe_pharisee", skin="skin", hair="hair_dark",
                     trim="linen", headcloth=True, beard=True),
    "goliath": dict(robe="robe_giant", skin="skin", hair="hair_dark",
                    trim="bronze", helm=True, big=True, beard=True),
    "boy":     dict(robe="robe_soldier", skin="skin", hair="hair_dark",
                    trim="iron"),
    "villager_a": dict(robe="robe_david", skin="skin", hair="hair_dark", trim="wool"),
    "villager_b": dict(robe="robe_woman", skin="skin", hair="hair_grey", trim="wool", veil=True),
    "villager_c": dict(robe="robe_elder", skin="skin", hair="hair_grey", trim="wool", beard=True),
    "shepherd": dict(robe="robe_pilgrim", skin="skin", hair="hair_dark",
                    trim="wool", staff=True, headcloth=True),
    "king":    dict(robe="robe_king", skin="skin", hair="hair_grey",
                    trim="gold", beard=True, crown=True),
    # NOTE: Bethlehem's household — jesse, eliab, samuel — is NOT drawn here.
    # Those three are variations of the rigs above, made by tools/char_variants.py,
    # so one body and one palette stay in use across the whole cast. Adding them
    # here as well would give the same three people two different builds in the
    # same scene once anyone re-ran this script.
}


def build_sheets():
    """Return {char_id: {"walk": Canvas, "idle": Canvas, "frames": {...}}}.

    Rows are directions in DIRS order (down, left, right, up); columns are frames.
    Godot's SpriteFrames maps this directly: one animation per row.
    """
    out = {}
    for cid, spec in CHARS.items():
        walk_cells = [cv for d in DIRS for f in range(4) for cv in [_figure(d, f, spec)]]
        idle_cells = [cv for d in DIRS for f in (1, 3) for cv in [_figure(d, f, spec)]]
        out[cid] = {
            "walk": atlas(walk_cells, 4, CHAR_W, CHAR_H),
            "idle": atlas(idle_cells, 2, CHAR_W, CHAR_H),
            "frames": {"walk": 4, "idle": 2},
        }
    return out
