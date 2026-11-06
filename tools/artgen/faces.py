"""faces.py — expressive 32x32 dialogue portraits, drawn in the house palette.

Why a separate asset and not the overworld sprite scaled up: a 16x16 walking
figure has three pixels of face. Stretching it to 32x32 (what the dialogue box
did until this pass) gives a chunky silhouette with no expression, no eye line
and no light. A portrait is a different drawing at a different scale, but it
must still look like the same person: the same robe ramp, the same hair ramp,
the same outline colour, the same top-left light, and the same 1 px geometry.

Rules, all enforced by tools/check_faces.py:
  * 32x32 RGBA, one actor per file, nothing outside the palette ramps.
  * Identical framing: head centred at (16,13), shoulders from row 24, a warm
    dark ground behind, no pure black and no pure white.
  * One outline pass around the *figure*, never around the background.
  * Expression is a small vocabulary of brow/eye/mouth shapes, not a new face
    per line: calm, firm, weary, gentle, stern, scorn, afraid, alert, joy.
  * Deterministic: no RNG, so a regenerated portrait is byte-identical.
"""

from .canvas import Canvas
from .palette import c, OUTLINE

W = H = 32
INK = c("hair_dark", 0)

# actor -> portrait spec. `rig` names the overworld rig this person wears, so
# the robe/hair/trim ramps cannot drift between the map and the conversation.
# `mood` is the resting expression; the box can still swap frames later.
FACES = {
    "pilgrim":    dict(rig="pilgrim",    mood="calm",   head="cloth",  item="staff"),
    "corin":      dict(rig="corin",      mood="alert",  head="hood",   item="scroll"),
    "soldier":    dict(rig="soldier",    mood="firm",   head="helm",   item="spear"),
    "woman":      dict(rig="woman",      mood="gentle", head="veil"),
    "david":      dict(rig="david",      mood="firm",   head="hair",   item="sling",
                       young=True, skin=5),
    "elder":      dict(rig="elder",      mood="weary",  head="hair",   beard=True,
                       marks=["wrinkles"]),
    "priest":     dict(rig="priest",     mood="calm",   head="cloth",  beard=True,
                       band="gold"),
    "pharisee":   dict(rig="pharisee",   mood="stern",  head="cloth",  beard=True),
    "goliath":    dict(rig="goliath",    mood="scorn",  head="helm",   beard=True,
                       item="spear", big=True, skin=3, marks=["scar", "heavy_brow"]),
    "boy":        dict(rig="boy",        mood="afraid", head="hair",   young=True),
    "villager_a": dict(rig="villager_a", mood="calm",   head="hair"),
    "villager_b": dict(rig="villager_b", mood="gentle", head="veil"),
    "villager_c": dict(rig="villager_c", mood="weary",  head="hair",   beard=True,
                       marks=["wrinkles"]),
    "shepherd":   dict(rig="shepherd",   mood="weary",  head="cloth",  beard=True,
                       item="staff", skin=3, marks=["sun"]),
    "king":       dict(rig="king",       mood="stern",  head="crown",  beard=True,
                       skin=3, marks=["heavy_brow"]),
    # The three Bethlehem variants. Their overworld sheets are recoloured rigs
    # (tools/char_variants.py); the portraits draw the same shifted ramp
    # directly so the face and the map agree without a second recolour pass.
    "jesse":      dict(rig="jesse",      mood="weary",  head="cloth",  beard=True,
                       skin=3, marks=["sun", "wrinkles"]),
    "eliab":      dict(rig="eliab",      mood="stern",  head="hair",   beard=True,
                       skin=4, marks=["heavy_brow"]),
    "samuel":     dict(rig="samuel",     mood="calm",   head="cloth",  beard=True,
                       band="gold", long_beard=True, marks=["wrinkles"]),
}

# Robe ramp per rig, including the hue-shifted household variants.
RIGS = {
    "pilgrim":    ("robe_pilgrim", "hair_dark",  "gold",   "skin"),
    "corin":      ("robe_scribe",  "hair_dark",  "gold",   "skin"),
    "soldier":    ("robe_soldier", "hair_dark",  "iron",   "skin"),
    "woman":      ("robe_woman",   "hair_dark",  "gold",   "skin"),
    "david":      ("robe_david",   "hair_red",   "gold",   "skin"),
    "elder":      ("robe_elder",   "hair_grey",  "gold",   "skin"),
    "priest":     ("robe_priest",  "hair_dark",  "gold",   "skin"),
    "pharisee":   ("robe_pharisee","hair_dark",  "linen",  "skin"),
    "goliath":    ("robe_giant",   "hair_dark",  "bronze", "skin"),
    "boy":        ("robe_soldier", "hair_dark",  "iron",   "skin"),
    "villager_a": ("robe_david",   "hair_dark",  "wool",   "skin"),
    "villager_b": ("robe_woman",   "hair_grey",  "wool",   "skin"),
    "villager_c": ("robe_elder",   "hair_grey",  "wool",   "skin"),
    "shepherd":   ("robe_pilgrim", "hair_dark",  "wool",   "skin"),
    "king":       ("robe_king",    "hair_grey",  "gold",   "skin"),
    # households: a brown farmer's coat, a ruddy eldest brother, indigo prophet
    "jesse":      ("wood",         "hair_grey",  "wool",   "skin"),
    "eliab":      ("robe_david",   "hair_red",   "wool",   "skin"),
    "samuel":     ("robe_pharisee","hair_grey",  "gold",   "skin"),
}


def _ground() -> Canvas:
    """A warm dark studio ground with a top-left light and a horizon band.

    Three flat shades only — no gradients, no antialiasing. The lighter arc
    behind the head is what makes the silhouette read at 32 px against the box.
    """
    # Warm sepia stone, deliberately NOT the blue-grey of the dialogue panel:
    # the portrait is a lit object sitting in a hole in the UI, not more UI.
    cv = Canvas(W, H, fill=c("wood", 0))
    cv.rect(0, 0, W, 12, c("wood", 1))
    cv.dither(0, 0, W, 12, c("wood", 1), c("wood", 2), pattern=2)
    cv.ellipse(16, 14, 13, 13, c("wood", 2), fill=True)
    cv.ellipse(16, 13, 10, 11, c("wood", 3), fill=True)
    cv.hline(0, 26, W, c("wood", 1))
    cv.hline(0, 27, W, c("wood", 0))
    # a thin warm rim from the top-left; never a glow
    cv.vline(0, 0, 27, c("gold", 1))
    cv.hline(0, 0, W, c("gold", 1))
    return cv


def _shoulders(fig: Canvas, R, T, big: bool) -> None:
    width = 30 if big else 26
    x0 = (W - width) // 2
    y0 = 24
    for row in range(y0, H):
        spread = (row - y0) // 2
        left = max(0, x0 - spread)
        right = min(W, x0 + width + spread)
        fig.hline(left, row, right - left, R(2))
        fig.px(left, row, R(3))
        fig.px(left + 1, row, R(4))
        fig.px(right - 1, row, R(1))
        fig.px(right - 2, row, R(1))
    # mantle / collar: a V of the trim ramp and a lit edge on the left shoulder
    fig.hline(x0 + 2, y0, width - 4, T(2))
    fig.line(x0 + 3, y0 + 1, 14, y0 + 5, T(3))
    fig.line(x0 + width - 4, y0 + 1, 18, y0 + 5, T(2))
    fig.hline(x0 + 3, y0 + 1, 5, R(4))
    fig.px(15, y0 + 5, T(4))
    fig.px(16, y0 + 5, T(4))
    # arm seam, so the bust does not read as a trapezoid
    fig.vline(x0 + 2, y0 + 3, H - y0 - 3, R(1))
    fig.vline(x0 + width - 3, y0 + 3, H - y0 - 3, R(1))


def _head_shape(fig: Canvas, S, big: bool, young: bool = False) -> tuple:
    """Head + ears + jaw. Returns (cx, cy, rx, ry, top).

    David and the hired boy are youths: a slightly smaller head and a higher
    eye line is most of what reads as 'younger' at thirty-two pixels. Goliath
    gets the largest head in the cast.
    """
    cx, cy = 16, 14 if young else 13
    rx, ry = (10, 11) if big else ((8, 9) if young else (9, 10))
    fig.ellipse(cx, cy, rx, ry, S(4), fill=True)
    # ears break the oval at eye height
    fig.rect(cx - rx - 1, cy + 1, 2, 4, S(3))
    fig.rect(cx + rx, cy + 1, 2, 4, S(2))
    # top-left light, right-side turn-under, jaw shade
    fig.ellipse(cx - 2, cy - 2, rx - 2, ry - 3, S(5), fill=True)
    fig.hline(cx - rx + 3, cy + ry - 1, rx * 2 - 6, S(2))
    fig.vline(cx + rx - 1, cy - 2, 6, S(3))
    fig.px(cx - rx + 2, cy + ry - 2, S(3))
    return cx, cy, rx, ry, cy - ry


def _cap(fig: Canvas, top: int, cx: int, rx: int, rows: int, col, lit) -> None:
    """A rounded hair/hat cap over the top of the head only.

    The previous version filled an ellipse right down over the eyes, which made
    every portrait look like it was wearing a mask. Hair belongs on rows
    `top..top+rows`; the forehead below it must stay skin.
    """
    for i in range(rows):
        y = top + i
        inset = max(0, 3 - i) if i < 3 else (1 if i >= rows - 1 else 0)
        fig.hline(cx - rx + inset, y, 2 * rx + 1 - 2 * inset, col)
    fig.hline(cx - rx + 3, top, rx - 1, lit)
    fig.px(cx - rx + 3, top + 1, lit)


def _hair(fig: Canvas, s, H, cx, cy, rx, top) -> None:
    kind = s.get("head", "hair")
    if kind in ("hair", "crown"):
        hair_col = c("hair_grey", 2) if kind == "crown" else H(2)
        hair_lit = c("hair_grey", 3) if kind == "crown" else H(3)
        _cap(fig, top, cx, rx, 7, hair_col, hair_lit)
        # an asymmetric fringe dipping over the LEFT brow, and two sideburns
        fig.hline(cx - rx + 1, top + 6, 5, H(2))
        fig.px(cx - rx + 1, top + 7, H(1))
        fig.vline(cx - rx, top + 4, 6, H(1))
        fig.vline(cx + rx, top + 4, 4, H(1))
        fig.px(cx + rx - 1, top + 2, H(3))
    if kind == "hood":
        _cap(fig, top, cx, rx + 1, 8, c("linen", 2), c("linen", 4))
        fig.hline(cx - rx - 1, top + 7, 2 * rx + 3, c("linen", 1))
        fig.vline(cx - rx - 1, top + 4, 10, c("linen", 2))
        fig.vline(cx + rx + 1, top + 4, 10, c("linen", 1))
        # the hood's shadow falls across the brow — Corin reads as a scribe
        fig.hline(cx - rx + 2, top + 7, 2 * rx - 3, c("linen", 0))
    if kind in ("cloth", "veil"):
        # A wrapped headcloth is fabric, not a white helmet: a mid-grey mass,
        # one bright fold on the lit side, and a dark binding band. The band
        # takes the actor's trim colour so a priest, a prophet and a farmer do
        # not all read as the same person in the same hat.
        _cap(fig, top, cx, rx, 6, c("linen", 2), c("linen", 4))
        fig.hline(cx - rx + 2, top + 1, rx - 1, c("linen", 4))
        fig.line(cx - rx + 2, top + 3, cx + rx - 2, top + 1, c("linen", 3))
        band = s.get("band", "wool")
        fig.hline(cx - rx - 1, top + 5, 2 * rx + 3, c(band, 2))
        fig.hline(cx - rx - 1, top + 6, 2 * rx + 3, c(band, 1))
        fig.px(cx - rx + 3, top + 5, c(band, 4))
        fig.vline(cx + rx + 1, top + 5, 9, c("linen", 2))
        fig.vline(cx + rx + 2, top + 7, 7, c("linen", 1))
        if kind == "veil":
            fig.vline(cx - rx - 1, top + 5, 13, c("linen", 2))
            fig.vline(cx - rx - 2, top + 8, 10, c("linen", 1))
    if kind == "helm":
        metal = "bronze" if s.get("big") else "iron"
        _cap(fig, top, cx, rx + 1, 7, c(metal, 3), c(metal, 4))
        fig.hline(cx - rx - 1, top + 6, 2 * rx + 3, c(metal, 2))
        fig.vline(cx - rx - 1, top + 5, 9, c(metal, 1))   # cheek guards
        fig.vline(cx + rx + 1, top + 5, 9, c(metal, 1))
        fig.vline(cx, top + 6, 5, c(metal, 1))            # nose guard
        fig.px(cx, top + 6, c(metal, 4))
        if s.get("big"):
            # the champion's crest: three dark plumes above the bronze bowl
            for dx in (-4, 0, 4):
                fig.vline(cx + dx, top - 3, 4, c("blood", 2))
                fig.px(cx + dx, top - 3, c("blood", 3))
            fig.hline(cx - 6, top - 1, 13, c("bronze", 2))
    if kind == "crown":
        fig.hline(cx - rx - 1, top + 4, 2 * rx + 3, c("gold", 3))
        fig.hline(cx - rx - 1, top + 5, 2 * rx + 3, c("gold", 2))
        fig.hline(cx - rx - 1, top + 6, 2 * rx + 3, c("gold", 1))
        for px in (cx - rx, cx - 4, cx + 3, cx + rx):
            fig.vline(px, top + 2, 3, c("gold", 4))
            fig.px(px, top + 1, c("gold", 5))
        fig.px(cx, top + 4, c("blood", 3))                # one stone in the band


def _expression(fig: Canvas, mood: str, S, cx, cy, rx) -> None:
    """A small, consistent vocabulary. Only brows, eye height and mouth move."""
    ey = cy + 2
    # eyes: 2x2 ink with one lit corner
    for ex in (cx - 5, cx + 3):
        fig.rect(ex, ey, 2, 2, INK)
        fig.px(ex, ey, c("linen", 3))
    # brows
    brow_y = ey - 2
    if mood == "firm":
        fig.hline(cx - 6, brow_y, 4, INK); fig.hline(cx - 6, brow_y + 1, 2, INK)
        fig.hline(cx + 3, brow_y, 4, INK); fig.hline(cx + 5, brow_y + 1, 2, INK)
    elif mood == "stern" or mood == "scorn":
        fig.hline(cx - 6, brow_y + 1, 4, INK); fig.px(cx - 6, brow_y, INK)
        fig.hline(cx + 3, brow_y, 4, INK); fig.px(cx + 6, brow_y + 1, INK)
    elif mood == "weary" or mood == "afraid":
        fig.hline(cx - 6, brow_y, 4, INK); fig.px(cx - 3, brow_y + 1, INK)
        fig.hline(cx + 3, brow_y, 4, INK); fig.px(cx + 3, brow_y + 1, INK)
        if mood == "afraid":
            fig.px(cx + 4, ey - 1, S(3)); fig.px(cx - 5, ey - 1, S(3))
    elif mood == "gentle" or mood == "joy":
        fig.hline(cx - 5, brow_y, 3, INK)
        fig.hline(cx + 3, brow_y, 3, INK)
    else:  # calm, alert
        fig.hline(cx - 5, brow_y, 3, INK)
        fig.hline(cx + 3, brow_y, 3, INK)
    # nose: two pixels of shade and a lit bridge
    fig.vline(cx, ey + 2, 3, S(3))
    fig.px(cx - 1, ey + 4, S(2))
    fig.px(cx + 1, ey + 2, S(5))
    # mouth
    my = cy + 8
    if mood in ("gentle", "joy"):
        fig.hline(cx - 2, my, 5, S(2))
        fig.px(cx - 3, my - 1, S(2)); fig.px(cx + 3, my - 1, S(2))
    elif mood in ("firm", "stern"):
        fig.hline(cx - 3, my, 7, S(2))
        fig.px(cx - 3, my - 1, S(1)); fig.px(cx + 3, my - 1, S(1))
    elif mood == "scorn":
        fig.hline(cx - 3, my, 7, S(1))
        fig.px(cx - 4, my - 1, S(2))
    elif mood in ("weary", "afraid"):
        fig.hline(cx - 2, my + 1, 5, S(2))
        fig.px(cx - 2, my, S(1)); fig.px(cx + 2, my, S(1))
    else:
        fig.hline(cx - 2, my, 5, S(2))
    # one cheek light, always on the left
    fig.px(cx - rx + 3, cy + 5, S(5))


def _beard(fig: Canvas, H, cx, cy, rx, long: bool = False) -> None:
    end = cy + 18 if long else cy + 15
    fig.hline(cx - rx + 3, cy + 8, 2 * rx - 5, H(1))
    fig.vline(cx - rx + 3, cy + 8, 6, H(1))
    fig.vline(cx + rx - 3, cy + 8, 6, H(1))
    fig.tri(cx - rx + 4, cy + 9, cx + rx - 4, cy + 9, cx, end, H(2))
    fig.hline(cx - 2, cy + 10, 5, H(3))
    fig.px(cx - rx + 4, cy + 9, H(3))
    if long:
        fig.hline(cx - 3, cy + 15, 7, H(3))
        fig.px(cx, cy + 17, H(4))


def _marks(fig: Canvas, marks: list, S, cx: int, cy: int, rx: int) -> None:
    """Small, character-specific details. These are what stop eighteen
    portraits from being one face in eighteen hats."""
    if "wrinkles" in marks:
        for dx in (-rx - 1, rx + 1):
            fig.px(cx + dx, cy + 2, S(2))
            fig.px(cx + dx, cy + 4, S(2))
        fig.hline(cx - 2, cy + 6, 5, S(3))
    if "scar" in marks:
        fig.line(cx + 4, cy + 2, cx + 6, cy + 7, c("blood", 2))
        fig.px(cx + 4, cy + 2, c("blood", 3))
    if "heavy_brow" in marks:
        fig.hline(cx - 6, cy, 5, INK)
        fig.hline(cx + 2, cy, 5, INK)
        fig.px(cx - 6, cy - 1, INK)
        fig.px(cx + 6, cy - 1, INK)
    if "sun" in marks:
        # weathered shepherd: two short creases above the brow on the left
        fig.hline(cx - rx + 1, cy - 1, 3, S(3))
        fig.hline(cx - rx + 2, cy, 2, S(3))


def _item(fig: Canvas, what: str, R, T) -> None:
    if what == "sling":
        # two cords across David's chest and a stone pouch at his hip
        fig.line(6, 31, 15, 25, c("wool", 1))
        fig.line(7, 31, 16, 25, c("wool", 3))
        fig.line(26, 31, 18, 25, c("wool", 1))
        fig.circle(22, 29, 2, c("wool", 2), fill=True)
        fig.px(22, 28, c("wool", 3))
    elif what == "scroll":
        fig.rect(24, 27, 6, 4, c("linen", 4))
        fig.hline(24, 27, 6, c("linen", 5))
        fig.vline(24, 27, 4, c("wood", 2))
        fig.vline(29, 27, 4, c("wood", 1))
    elif what == "staff":
        fig.vline(2, 16, 16, c("wood", 2))
        fig.px(2, 16, c("wood", 4))
        fig.hline(1, 15, 3, c("wood", 3))
        fig.px(1, 16, c("wood", 3))
    elif what == "spear":
        fig.vline(30, 2, 30, c("wood", 2))
        fig.tri(28, 2, 32, 2, 30, 8, c("iron", 4))
        fig.px(30, 2, c("iron", 5))
        fig.hline(28, 12, 5, c("iron", 2))


def _face(spec: dict) -> Canvas:
    robe, hair, trim, skin = RIGS[spec["rig"]]

    base = spec.get("skin", 4)

    def R(i): return c(robe, i)
    def T(i): return c(trim, i)
    def S(i): return c(skin, base + i - 4)
    def Hs(i): return c(hair, i)
    def Linen(i): return c("linen", i)

    young = spec.get("young", False)
    fig = Canvas(W, H)
    _shoulders(fig, R, T, spec.get("big", False))
    cx, cy, rx, ry, top = _head_shape(fig, S, spec.get("big", False), young)
    # neck drawn AFTER the head so the jaw sits over it
    fig.rect(13, 21, 7, 4, S(3))
    fig.hline(14, 21, 5, S(2))
    _hair(fig, spec, Hs, cx, cy, rx, top)
    _expression(fig, spec.get("mood", "calm"), S, cx, cy, rx)
    _marks(fig, spec.get("marks", []), S, cx, cy, rx)
    if spec.get("beard"):
        _beard(fig, Linen if spec.get("long_beard") else Hs,
               cx, cy, rx, spec.get("long_beard", False))
    if spec.get("item"):
        _item(fig, spec["item"], R, T)
    fig.outline(OUTLINE)
    out = _ground()
    out.paste(fig, 0, 0)
    return out


def build_faces() -> dict:
    return {actor: _face(spec) for actor, spec in FACES.items()}
