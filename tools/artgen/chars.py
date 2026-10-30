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
    """Draw one frame of one direction. `s` is a character spec (see CHARS)."""
    cv = Canvas(CHAR_W, CHAR_H)
    bob = BOB[frame] if s.get("bob", True) else 0

    robe = s["robe"]; skin = s.get("skin", "skin"); hair = s.get("hair", "hair_dark")
    trim = s.get("trim", "gold")
    big = s.get("big", False)

    # vertical extents; a "big" character (Goliath) is drawn at the same cell
    # but fills more of it, which is how he reads as huge without a new system.
    top = 0 if big else 3
    head_h = 7 if big else 6
    head_w = 8 if big else 7
    body_top = top + head_h + (0 if big else 1)
    body_bot = CHAR_H - 4          # feet occupy the last 4 rows
    cx = CHAR_W // 2

    R = lambda i: c(robe, i)
    S = lambda i: c(skin, i)
    H = lambda i: c(hair, i)

    def head(oy):
        """Head + hair/headcloth/helm. Returns the y the neck starts at."""
        hx = cx - head_w // 2
        hy = oy
        # hair or headcloth crown first
        cv.rect(hx, hy, head_w, 2, H(2))
        cv.hline(hx, hy, head_w, H(3))
        cv.px(hx, hy + 1, H(1)); cv.px(hx + head_w - 1, hy + 1, H(1))
        if s.get("helm"):
            cv.rect(hx, hy - 0, head_w, 2, c("bronze", 3))
            cv.hline(hx, hy, head_w, c("bronze", 4))
            cv.px(cx, hy - 1, c("bronze", 4))
        if s.get("headcloth"):
            # a cloth that falls past the shoulders — the single strongest
            # "ancient Near East" silhouette cue at this size
            cv.rect(hx - 1, hy, head_w + 2, head_h, S(3))
            cv.vline(hx - 1, hy, head_h, S(2)); cv.vline(hx + head_w, hy, head_h, S(2))
            cv.hline(hx - 1, hy, head_w + 2, S(4))
        # face — hair frames the temples so the crown doesn't read as a hat,
        # and the eyes sit at the MID of the face, not under the hairline
        fy = hy + 2
        eye = c("hair_dark", 0)
        if dir_ == "up":
            cv.rect(hx, fy, head_w, head_h - 2, H(2))       # back of the head
            cv.vline(hx, fy, head_h - 2, H(3)); cv.vline(hx + head_w - 1, fy, head_h - 2, H(1))
            cv.hline(hx, fy + head_h - 3, head_w, H(1))
        else:
            cv.rect(hx, fy, head_w, head_h - 2, S(3))
            cv.hline(hx, fy, head_w, S(4))                   # lit brow
            cv.px(hx, fy, H(2)); cv.px(hx + head_w - 1, fy, H(2))     # temples
            cv.px(hx, fy + 1, S(2)); cv.px(hx + head_w - 1, fy + 1, S(2))
            ey = fy + 2
            if dir_ == "down":
                cv.px(hx + 2, ey, eye); cv.px(hx + head_w - 3, ey, eye)
                cv.hline(hx + 2, ey + 2, head_w - 4, S(2))   # mouth shadow
                if s.get("beard"):
                    cv.rect(hx + 1, ey + 1, head_w - 2, 3, H(2))
                    cv.hline(hx + 1, ey + 3, head_w - 2, H(1))
                    cv.px(hx + 2, ey, eye); cv.px(hx + head_w - 3, ey, eye)
            elif dir_ == "right":
                cv.px(hx + head_w - 2, ey, eye)
                cv.px(hx + head_w - 1, ey + 1, S(4))          # nose
                if s.get("beard"):
                    cv.rect(hx + head_w - 3, ey + 1, 3, 3, H(2))
            elif dir_ == "left":
                cv.px(hx + 1, ey, eye)
                cv.px(hx, ey + 1, S(4))                       # nose
                if s.get("beard"):
                    cv.rect(hx, ey + 1, 3, 3, H(2))
        if s.get("veil"):
            cv.rect(hx - 1, hy, head_w + 2, head_h + 1, S(2))
            cv.hline(hx - 1, hy, head_w + 2, S(3))
            cv.vline(hx - 1, hy, head_h + 1, S(1)); cv.vline(hx + head_w, hy, head_h + 1, S(1))
            # face opening
            cv.rect(hx + 1, fy, head_w - 2, head_h - 3, S(4))
            cv.px(hx + 2, fy + 1, c("hair_dark", 0)); cv.px(hx + head_w - 3, fy + 1, c("hair_dark", 0))
        return fy + head_h - 2

    w_top = head_w + 1              # shoulders wider than the head: reads as a person
    w_bot = head_w + 4              # robe flares to the hem

    def body(oy):
        """Robe: narrow at shoulders, flaring to the hem. Light from top-left."""
        rows = body_bot - oy
        for i in range(rows):
            t = i / max(1, rows - 1)
            w = int(w_top + (w_bot - w_top) * t)
            x0 = cx - w // 2
            col = R(2) if i < rows * 0.5 else R(1)
            cv.hline(x0, oy + i, w, col)
            # lit left edge, shadowed right edge — the whole figure's form light
            cv.px(x0, oy + i, R(3))
            cv.px(x0 + w - 1, oy + i, R(0))
        # belt / sash
        cv.hline(cx - w_top // 2 - 1, oy + 2, w_top + 2, c(trim, 2) if trim in ramp_names() else R(3))
        # hem highlight so the robe doesn't melt into the ground
        cv.hline(cx - w_bot // 2, body_bot - 1, w_bot, R(3))
        return w_bot

    def feet(w_bot, frame):
        y = CHAR_H - 3
        if dir_ in ("down", "up"):
            (nx, ny), (fx, fy) = FRONT_FEET[frame]
            cv.px(cx - 2 + nx, y + ny, c("wood", 1))
            cv.px(cx + 1 + fx, y + fy, c("wood", 1))
            cv.px(cx - 2 + nx, y + ny + 1, c("wood", 0))
            cv.px(cx + 1 + fx, y + fy + 1, c("wood", 0))
        else:
            (nx, ny), (fx, fy) = SIDE_FEET[frame]
            cv.px(cx + nx, y + ny, c("wood", 1))
            cv.px(cx + fx, y + fy + 1, c("wood", 0))
            cv.px(cx + nx, y + ny + 1, c("wood", 0))

    def arms(oy):
        """One visible arm per direction, swinging on side views."""
        y = oy + 2 + SIDE_ARM[frame] if dir_ in ("left", "right") else oy + 3
        if dir_ == "right":
            cv.vline(cx + head_w // 2, y, 4, R(3)); cv.px(cx + head_w // 2, y + 4, S(3))
        elif dir_ == "left":
            cv.vline(cx - head_w // 2 - 1, y, 4, R(3)); cv.px(cx - head_w // 2 - 1, y + 4, S(3))
        elif dir_ == "down":
            cv.vline(cx - head_w // 2 - 1, y, 4, R(2)); cv.px(cx - head_w // 2 - 1, y + 4, S(3))
            cv.vline(cx + head_w // 2, y, 4, R(0)); cv.px(cx + head_w // 2, y + 4, S(2))
        if s.get("staff") and dir_ != "up":
            sx = cx + head_w // 2 + 2 if dir_ == "right" else cx - head_w // 2 - 3
            cv.vline(sx, top + 2, CHAR_H - top - 5, c("wood", 3))
            cv.px(sx, top + 2, c("wood", 4))
        if s.get("sling") and dir_ != "up":
            # a leather strap across the chest, shoulder to opposite hip, with
            # the pouch at the belt. A diagonal strap reads as "carries a sling"
            # at 16px; a loose line off the shoulder reads as a rendering bug.
            lx = c("wood", 2)
            if dir_ == "right":
                cv.line(cx - w_top // 2 + 1, oy, cx + w_top // 2, oy + 4, lx)
            elif dir_ == "left":
                cv.line(cx + w_top // 2, oy, cx - w_top // 2 + 1, oy + 4, lx)
            else:
                cv.line(cx - w_top // 2 + 1, oy, cx + 1, oy + 4, lx)
                cv.px(cx + 1, oy + 4, c("wood", 3))          # the pouch
        if s.get("scroll") and dir_ in ("down", "left"):
            cv.rect(cx - head_w // 2 - 3, oy + 3, 2, 5, c("linen", 4))
            cv.px(cx - head_w // 2 - 3, oy + 3, c("linen", 5))
            cv.px(cx - head_w // 2 - 3, oy + 7, c("linen", 5))

    head_bottom = head(top + 1 - bob)
    body_top2 = max(body_top, head_bottom)
    w_bot = body(body_top2 - bob)
    feet(w_bot, frame)
    arms(body_top2 - bob)

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
