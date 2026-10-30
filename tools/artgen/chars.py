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
    """One frame of one direction, in a 16×16 cell. `s` is a CHARS spec.

    Proportions are lifted from the hand-drawn reference in art/pack (a 16×16
    chibi): the head is TEN of the sixteen rows and ten columns wide, the body
    four rows, the legs three. That ratio is the whole trick — at the old
    16×24 with a small head the figure read as a peg with a hat, and no amount
    of shading fixed it.

        y  0-9   head (10 wide, corners cut, chin narrows, hair/cloth on top)
        y 10-13  body: shoulders, belt, hem
        y 14-15  legs + sandals, striding with the frame

    Light is top-left, three tones per material, outline drawn last.
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
    INK = c("hair_dark", 0)

    cx = CHAR_W // 2                      # 8
    hw = 6 if big else 5                  # half width → 12 or 10 wide head
    top = 0 if big else 1
    head_h = 11 if big else 10
    face_top = top + 4

    # ── head ──────────────────────────────────────────────────────────────
    hy = top + bob
    # skull: rounded — corners cut on the top row and at the jaw
    crown = c("linen", 3) if s.get("headcloth") else (c("bronze", 3) if s.get("helm") else H(2))
    # Rounded skull: two rows of inset before the full width, so the silhouette
    # is a dome rather than a brick. The reference's head is nearly circular and
    # that curve is a large part of why it reads as a face.
    cv.hline(cx - hw + 3, hy, hw * 2 - 6, crown)
    cv.hline(cx - hw + 2, hy + 1, hw * 2 - 4, crown)
    cv.hline(cx - hw + 1, hy + 2, hw * 2 - 2, crown)
    cv.hline(cx - hw, hy + 3, hw * 2, crown)
    cv.px(cx - hw + 3, hy + 1, blend(crown, "#ffffff", 0.20))
    cv.px(cx - hw + 2, hy + 2, blend(crown, "#ffffff", 0.12))
    cv.px(cx + hw - 3, hy + 1, blend(crown, "#000000", 0.14))
    cv.px(cx + hw - 2, hy + 2, blend(crown, "#000000", 0.10))

    if s.get("helm"):
        cv.hline(cx - hw + 1, hy + 3, hw * 2 - 2, c("bronze", 2))
        cv.px(cx, hy - 1, c("bronze", 4))
        cv.px(cx - 1, hy, c("bronze", 4)); cv.px(cx + 1, hy, c("bronze", 4))
    if s.get("headcloth"):
        cv.hline(cx - hw, hy + 3, hw * 2, c("linen", 2))
        cv.vline(cx - hw, hy + 3, 3, c("linen", 2))
        cv.vline(cx + hw - 1, hy + 3, 3, c("linen", 1))
        cv.px(cx - hw, hy + 3, c("linen", 4))

    # face: wide, lit on the brow, jaw narrows by one on each side
    for y in range(face_top + bob, hy + head_h):
        inset = 1 if y >= hy + head_h - 1 else 0
        cv.hline(cx - hw + inset, y, hw * 2 - inset * 2, S(3))
        # cheeks: one step down at each edge and under the jaw. Without this the
        # face is a flat rectangle with eyes on it, which is exactly what made
        # the old sprites read as cardboard.
        if y > face_top + bob + 1:
            cv.px(cx - hw + 1, y, S(2))
            cv.px(cx + hw - 2, y, S(2))
    cv.hline(cx - hw + 2, hy + head_h - 1, hw * 2 - 4, S(2))
    cv.hline(cx - hw + 1, face_top + bob, hw * 2 - 2, S(4))
    cv.px(cx - hw + 1, face_top + bob, S(2))
    cv.px(cx + hw - 2, face_top + bob, S(2))

    # fringe: two rows of hair over the forehead, parted off-centre
    if dir_ in ("down", "right", "left") and not s.get("headcloth") and not s.get("helm"):
        cv.hline(cx - hw + 1, face_top + bob - 1, hw * 2 - 2, H(2))
        cv.hline(cx - hw + 2, face_top + bob, hw - 1, H(2))
        cv.px(cx - hw + 2, face_top + bob - 1, H(3))
    ey = face_top + 2 + bob
    if dir_ == "up":
        cv.hline(cx - hw + 1, face_top + bob, hw * 2 - 2, H(2))
        cv.hline(cx - hw + 2, face_top + bob + 1, hw * 2 - 4, H(1))
        cv.vline(cx - hw + 1, face_top + bob, head_h - 4, H(3))
        cv.vline(cx + hw - 2, face_top + bob, head_h - 4, H(1))
    else:
        # two-pixel eyes with a lit pixel under each — the reference's trick:
        # eyes big enough to carry expression at 1x
        if dir_ == "down":
            cv.rect(cx - 3, ey, 2, 2, INK)
            cv.rect(cx + 1, ey, 2, 2, INK)
            cv.px(cx - 3, ey, S(4)); cv.px(cx + 1, ey, S(4))
            cv.px(cx - 1, ey + 3, S(2)); cv.px(cx, ey + 3, S(1))   # mouth
        elif dir_ == "right":
            cv.rect(cx + 1, ey, 2, 2, INK)
            cv.px(cx + 1, ey, S(4))
            cv.hline(cx + 1, ey - 1, 2, H(1))                       # brow
            cv.px(cx + hw - 1, ey + 1, S(4))                        # nose
            cv.px(cx + hw - 2, ey + 3, S(2))                        # cheek shade
        else:
            cv.rect(cx - 3, ey, 2, 2, INK)
            cv.px(cx - 3, ey, S(4))
            cv.hline(cx - 3, ey - 1, 2, H(1))                       # brow
            cv.px(cx - hw, ey + 1, S(4))
            cv.px(cx - hw + 2, ey + 3, S(2))
        if s.get("beard"):
            cv.hline(cx - 3, ey + 3, 6, H(2))
            cv.hline(cx - 2, ey + 4, 4, H(1))
            cv.px(cx - 3, ey + 3, H(3))
    if s.get("veil"):
        cv.vline(cx - hw, hy + 3, 4, S(2))
        cv.vline(cx + hw - 1, hy + 3, 4, S(1))
        cv.hline(cx - hw + 1, hy + 3, hw * 2 - 2, S(4))
        cv.px(cx - 3, ey, INK); cv.px(cx + 1, ey, INK)

    # ── body ──────────────────────────────────────────────────────────────
    by = hy + head_h                     # 10 or 11
    span = 8 if big else 7
    # shoulders → belt → hem, three visual bands like the reference
    for i, w in enumerate((span, span, span - 1, span - 1)):
        y = by + i
        x0 = cx - w // 2
        cv.hline(x0, y, w, R(2) if i < 2 else R(1))
        cv.px(x0, y, R(3))
        if w > 2:
            cv.px(x0 + w - 1, y, R(1 if i < 2 else 0))
    # belt
    cv.hline(cx - span // 2, by + 2, span, T(2))
    cv.px(cx - span // 2, by + 2, T(3))
    cv.px(cx + span // 2 - 1, by + 2, T(1))
    # sleeves: short, at the shoulder corners, so arms are not a separate stick
    sw = 1 if dir_ in ("down", "up") else 2
    cv.vline(cx - span // 2 - 1, by, 2, R(2))
    cv.vline(cx + span // 2, by, 2, R(1))
    cv.px(cx - span // 2 - 1, by + 2, S(3))               # hands
    cv.px(cx + span // 2, by + 2, S(2))
    if dir_ in ("left", "right"):
        # the far sleeve is hidden; the near one swings a row with the frame
        sy = by + SIDE_ARM[frame]
        if dir_ == "right":
            cv.vline(cx + span // 2, sy, 2, R(2))
            cv.px(cx + span // 2, sy + 2, S(3))
        else:
            cv.vline(cx - span // 2 - 1, sy, 2, R(2))
            cv.px(cx - span // 2 - 1, sy + 2, S(3))

    # ── legs ──────────────────────────────────────────────────────────────
    ly = by + 4
    if dir_ in ("down", "up"):
        (nx, ny2), (fx, fy) = FRONT_FEET[frame]
        for dx, dy, shade in ((-2 + nx, ny2, 2), (1 + fx, fy, 1)):
            x = cx + dx
            cv.rect(x, min(ly, CHAR_H - 3), 2, CHAR_H - 2 - min(ly, CHAR_H - 3), R(shade))
            cv.px(x, min(ly, CHAR_H - 3), R(shade + 1))
            cv.hline(x, CHAR_H - 2, 2, c("wood", 2))
    else:
        (nx, ny2), (fx, fy) = SIDE_FEET[frame]
        for x, col in ((cx - 2 + fx, R(1)), (cx + nx - 1, R(2))):
            cv.vline(x, min(ly, CHAR_H - 3), CHAR_H - 2 - min(ly, CHAR_H - 3), col)
            cv.hline(x, CHAR_H - 2, 2, c("wood", 2))

    # ── carried ───────────────────────────────────────────────────────────
    if s.get("staff"):
        sx = cx + 6 if dir_ == "right" else cx - 7
        cv.vline(sx, top + 1, CHAR_H - 3, c("wood", 2))
        cv.px(sx, top + 1, c("wood", 4))
    if s.get("sling") and dir_ != "up":
        cv.line(cx - 3, by, cx + 3, by + 2, c("wood", 2))
        cv.px(cx + 3, by + 3, c("wood", 3))
    if s.get("scroll") and dir_ in ("down", "left"):
        cv.rect(cx - 6, by, 2, 4, c("linen", 4))
        cv.px(cx - 6, by, c("linen", 5))
        cv.px(cx - 6, by + 3, c("linen", 5))

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
