"""Characters — 16×24 sprite sheets, four directions, walk + idle.

This is the module that answers "why did the old world feel low quality".
Covenant drew its people as procedural vector lines; here they are real pixel
figures on a fixed grid with a fixed palette, an outline, top-left lighting,
and a genuine four-frame walk cycle whose feet actually swap.

Cell is 16×24 (1.5 tiles) so a figure overlaps the tile behind it — that overlap
is what creates depth in a top-down RPG and it is why characters are taller
than the tiles they stand on.

Sheet layout Godot expects (see build_sheets below):
    walk:  rows = down, left, right, up   cols = 4 frames   → 64×96
    idle:  rows = down, left, right, up   cols = 2 frames   → 32×96
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
    """Draw one frame of one direction. `s` is a character spec (see CHARS).

    Anatomy, in a 16×24 cell (feet on the bottom row, outline drawn last):

        y  0-8   head      8 wide (10 for a giant) — big head, GBA chibi read
        y  9-10  neck + shoulders
        y 11-17  torso: shoulders 10 → waist 8 → hem flare, with fold lines
        y 18-21  two legs, 3 wide each, 1px apart, striding with the frame
        y 22-23  sandals + outline

    The old version drew a rectangular head on a rectangular torso and read as
    two stacked boxes — that is the "low quality" feel the reference screenshots
    were being compared against. Shape is what carries quality at 16px: a
    corner-cut head, a shoulder slope, a waist, separated legs, and three tones
    per material with light from the top left.
    """
    cv = Canvas(CHAR_W, CHAR_H)
    bob = BOB[frame] if s.get("bob", True) else 0

    robe = s["robe"]; skin = s.get("skin", "skin"); hair = s.get("hair", "hair_dark")
    trim = s.get("trim", "gold")
    big = s.get("big", False)

    R = lambda i: c(robe, i)
    S = lambda i: c(skin, i)
    H = lambda i: c(hair, i)
    T = lambda i: c(trim, i) if trim in ramp_names() else R(3)

    cx = CHAR_W // 2                     # 8
    hw = 5 if big else 4                 # head half-width → 10 or 8 wide
    top = 0 if big else 1
    head_h = 10 if big else 9
    head_bot = top + head_h - 1
    face_top = top + 3
    look = {"down": 0, "up": 0, "left": -1, "right": 1}.get(dir_, 0)
    bob = bob if dir_ in ("down", "up") else 0

    def span(y, w, col, lit=True, shad=True):
        """One body row: centred, with a lit left column and a shadow right one."""
        x0 = cx - w // 2
        cv.hline(x0, y, w, col)
        if lit:
            cv.px(x0, y, R(3) if col != S(2) else S(4))
        if shad and w > 2:
            cv.px(x0 + w - 1, y, R(0) if col != S(2) else S(1))

    # ── head ──────────────────────────────────────────────────────────────
    hy = top + bob
    # crown of hair or cloth, corners cut so the skull is not a brick
    cv.hline(cx - hw + 1, hy, hw * 2 - 2, H(2) if not s.get("headcloth") else c("linen", 3))
    cv.hline(cx - hw, hy + 1, hw * 2, H(2) if not s.get("headcloth") else c("linen", 3))
    cv.px(cx - hw, hy + 1, H(3)); cv.px(cx + hw - 1, hy + 1, H(1))

    if s.get("helm"):
        cv.hline(cx - hw + 1, hy, hw * 2 - 2, c("bronze", 4))
        cv.hline(cx - hw, hy + 1, hw * 2, c("bronze", 3))
        cv.px(cx - hw + 1, hy + 1, c("bronze", 4))
        cv.px(cx, hy - 1, c("bronze", 4))                 # crest nub
        cv.px(cx, hy + 2, c("bronze", 2))                 # brow band

    if s.get("headcloth"):
        # a drape that falls past the ears and stops at the shoulders: the
        # strongest ancient-Near-East cue at this size
        cv.hline(cx - hw, hy + 2, hw * 2, c("linen", 2))
        cv.vline(cx - hw, hy + 2, 4, c("linen", 2))
        cv.vline(cx + hw - 1, hy + 2, 4, c("linen", 1))
        cv.px(cx - hw, hy + 2, c("linen", 4))             # lit fold
        cv.px(cx - hw + 1, hy + 5, c("linen", 1))         # shade under the fold

    # face block
    for y in range(face_top + bob, head_bot + bob):
        w = hw * 2 - (2 if y >= head_bot + bob - 1 else 0)   # chin narrows
        cv.hline(cx - w // 2, y, w, S(3))
    cv.hline(cx - hw + 1, face_top + bob, hw * 2 - 2, S(4))   # lit brow
    cv.px(cx - hw + 1, face_top + bob, H(2))
    cv.px(cx + hw - 2, face_top + bob, H(2))                  # temples

    ey = face_top + 2 + bob
    if dir_ == "up":
        cv.hline(cx - hw, face_top + bob, hw * 2, H(2))       # back of the head
        cv.hline(cx - hw + 1, ey, hw * 2 - 2, H(1))
        cv.vline(cx - hw, face_top + bob, head_h - 3, H(3))
        cv.vline(cx + hw - 1, face_top + bob, head_h - 3, H(1))
    else:
        e1 = cx - 2 + (1 if dir_ == "right" else 0)
        e2 = cx + 1 + (1 if dir_ == "right" else 0)
        if dir_ == "down":
            cv.px(e1, ey, c("hair_dark", 0)); cv.px(e2, ey, c("hair_dark", 0))
            cv.hline(cx - 1, ey + 2, 2, S(2))                 # mouth shadow
        elif dir_ == "right":
            cv.px(cx + 2, ey, c("hair_dark", 0))
            cv.px(cx + hw - 1, ey, S(4))                      # nose
            cv.px(cx + 1, ey + 2, S(2))
        else:
            cv.px(cx - 3, ey, c("hair_dark", 0))
            cv.px(cx - hw, ey, S(4))                          # nose
            cv.px(cx - 2, ey + 2, S(2))
        if s.get("beard"):
            bw = hw * 2 - 2
            cv.hline(cx - bw // 2, ey + 1, bw, H(2))
            cv.hline(cx - bw // 2 + 1, ey + 3, bw - 2, H(1))
            cv.px(cx - bw // 2 + 1, ey + 1, H(3))

    if s.get("veil"):
        cv.hline(cx - hw, hy + 2, hw * 2, S(2))
        cv.vline(cx - hw, hy + 2, 5, S(2))
        cv.vline(cx + hw - 1, hy + 2, 5, S(1))
        cv.hline(cx - hw + 1, hy + 3, hw * 2 - 2, S(4))
        cv.px(cx - 2, ey, c("hair_dark", 0)); cv.px(cx + 1, ey, c("hair_dark", 0))

    # ── neck + torso ──────────────────────────────────────────────────────
    ny = head_bot + bob
    cv.hline(cx - 2, ny, 4, S(2))                             # neck in shade
    cv.hline(cx - 2, ny + 1, 4, S(1))

    body_top = ny + 2
    hem = CHAR_H - 6                                          # last robe row
    rows = hem - body_top + 1
    for i in range(rows):
        t = i / max(1, rows - 1)
        w = 10 if big else 9
        if i == 0:
            w -= 2                                            # shoulder slope
        elif i <= 2:
            w = 10 if big else 9
        elif t < 0.55:
            w = 9 if big else 8                               # waist
        else:
            w = 11 if big else 10                             # hem flare
        span(body_top + i, w, R(2) if t < 0.6 else R(1))

    # robe folds: two darker columns break the slab without adding noise
    for fx in (-2, 2):
        cv.vline(cx + fx, body_top + 1, rows - 2, R(1))
    if not big:
        cv.vline(cx - 3, body_top + 2, rows - 4, R(3))        # lit placket

    # belt / sash
    belt_y = body_top + min(3, rows - 2)
    cv.hline(cx - 4, belt_y, 8, T(2))
    cv.px(cx - 4, belt_y, T(3))
    cv.px(cx + 3, belt_y, T(1))
    cv.px(cx + 1, belt_y + 1, T(2))                           # knot tail

    # hem shadow so the robe does not melt into the ground
    cv.hline(cx - 5, hem, 10, R(3))

    # ── arms ──────────────────────────────────────────────────────────────
    # outside the torso silhouette, sleeve then hand; the near arm swings
    swing = SIDE_ARM[frame] if dir_ in ("left", "right") else 0
    ay = body_top + 1
    if dir_ in ("down", "up"):
        for side in (-1, 1):
            ax = cx + side * 5
            cv.vline(ax, ay + (0 if side < 0 else 0), 4, R(2))
            cv.px(ax, ay, R(3) if side < 0 else R(1))
            cv.px(ax, ay + 4, S(3) if side < 0 else S(2))     # hand
    else:
        ax = cx + (2 if dir_ == "right" else -3)
        cv.vline(ax, ay + swing, 4, R(3) if dir_ == "right" else R(2))
        cv.px(ax, ay + 4 + swing, S(3))

    # ── legs ──────────────────────────────────────────────────────────────
    ly = hem + 1
    if dir_ in ("down", "up"):
        (nx, ny2), (fx, fy) = FRONT_FEET[frame]
        # 3px legs with a 1px gap: at 2px the legs read as sticks, and a chibi
        # reads as chibi because the LIMBS are chunky, not because the head is big
        for dx, dy, shade in ((-3 + nx, ny2, 2), (1 + fx, fy, 1)):
            x = cx + dx
            inner = CHAR_H - dy - ly - 2
            cv.rect(x, ly + dy, 3, inner, R(shade))
            cv.vline(x, ly + dy, inner, R(shade + 1))
            cv.vline(x + 2, ly + dy, inner, R(shade - 1))
            cv.hline(x, CHAR_H - 3, 3, c("wood", 2))          # sandal
            cv.px(x, CHAR_H - 3, c("wood", 3))
    else:
        (nx, ny2), (fx, fy) = SIDE_FEET[frame]
        far_x = cx - 2 + fx
        near_x = cx + nx
        for x, dy, col in ((far_x, fy, R(1)), (near_x, ny2, R(2))):
            inner = CHAR_H - dy - ly - 2
            cv.rect(x, ly + dy, 3, inner, col)
            cv.hline(x, CHAR_H - 3, 3, c("wood", 2 if col == R(2) else 1))
            cv.px(x + 2, CHAR_H - 3, c("wood", 1))

    # ── carried things ────────────────────────────────────────────────────
    if s.get("staff"):
        sx = cx + 6 if dir_ == "right" else cx - 7
        cv.vline(sx, top + 2, CHAR_H - top - 4, c("wood", 2))
        cv.px(sx, top + 2, c("wood", 4))
        cv.px(sx, top + 3, c("wood", 3))
    if s.get("sling") and dir_ != "up":
        lx = c("wood", 2)
        if dir_ == "right":
            cv.line(cx - 4, body_top, cx + 4, body_top + 4, lx)
        elif dir_ == "left":
            cv.line(cx + 4, body_top, cx - 4, body_top + 4, lx)
        else:
            cv.line(cx - 4, body_top, cx + 2, body_top + 4, lx)
            cv.px(cx + 2, body_top + 5, c("wood", 3))          # pouch
    if s.get("scroll") and dir_ in ("down", "left"):
        sx = cx - 7
        cv.rect(sx, body_top + 2, 2, 5, c("linen", 4))
        cv.px(sx, body_top + 2, c("linen", 5))
        cv.px(sx, body_top + 6, c("linen", 5))

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
