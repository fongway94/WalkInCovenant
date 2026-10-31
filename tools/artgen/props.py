"""Props — the things that make a tile field into a PLACE.

Each prop has a pixel size and a tile footprint (how many tiles it blocks).
Footprints are recorded into data/props.json so Region.gd and the collision
grid agree with what the art actually covers.

Ancient-Near-East rules from docs/ART.md §5.1: flat mud-brick roofs, goat-hair
tents, olive and fig and palm trees, stone wells and altars, clay jars. No
pagodas, no European cottages.
"""

from .canvas import Canvas, atlas
from .palette import c, blend, SHADOW

PROPS = []   # filled by the builders below: (key, canvas_or_frames, footprint, solid, notes)


def _reg(key, cv, footprint, solid=True, frames=1, notes=""):
    PROPS.append({"key": key, "canvas": cv, "footprint": footprint,
                  "solid": solid, "frames": frames, "notes": notes})


# ── vegetation ──────────────────────────────────────────────────────────
def olive_tree(seed=1):
    cv = Canvas(16, 26)
    # Contact shadow FIRST: the tree stands IN the ground, not on top of it.
    # This one ellipse is half of what separates a sticker from a place.
    cv.ellipse(8, 24, 4, 1, blend(SHADOW, c("grass", 1), 0.45), fill=True)
    # trunk: gnarled, leaning — olive trees are never straight
    # trunk: 2px tapered column, lit on the left, NOT a ladder of alternating
    # pixels (that read as a sawhorse). Slight lean keeps it organic.
    for y in range(23, 14, -1):
        x = 7 + (1 if y < 18 else 0)
        cv.px(x, y, c("wood", 3)); cv.px(x + 1, y, c("wood", 1))
    cv.px(6, 23, c("wood", 1)); cv.px(9, 23, c("wood", 2))   # root flare
    # canopy: one scalloped mass, not three blobs — at 16px the SILHOUETTE is
    # the tree. Overlapping circles give the wavy edge the reference sheets
    # have; a single circle reads as a ball on a stick.
    for (cx, cy, r) in ((5, 9, 3), (8, 7, 4), (11, 9, 3), (6, 11, 3), (10, 11, 3)):
        cv.circle(cx, cy, r, c("olive", 2), fill=True)
    for (cx, cy, r) in ((6, 7, 2), (9, 6, 2), (11, 9, 1)):   # sunlit crown
        cv.circle(cx, cy, r, c("olive", 3), fill=True)
    cv.px(5, 5, c("olive", 4)); cv.px(8, 4, c("olive", 4))
    cv.px(10, 5, c("olive", 4)); cv.px(9, 7, c("olive", 4))
    # shaded underside + leaf notches so the mass is not a balloon
    cv.px(4, 12, c("olive", 1)); cv.px(7, 13, c("olive", 1))
    cv.px(11, 13, c("olive", 1)); cv.px(6, 10, c("olive", 1)); cv.px(10, 9, c("olive", 1))
    cv.outline(); return cv


def palm_tree(seed=2):
    cv = Canvas(16, 28)
    cv.ellipse(8, 27, 4, 1, SHADOW, fill=True)
    for y in range(27, 10, -1):
        x = 8 - (y - 10) // 9
        cv.px(x, y, c("wood", 3)); cv.px(x + 1, y, c("wood", 2))
    # fronds radiating
    for dx, dy in ((-5, -2), (-4, -4), (-1, -5), (2, -5), (4, -4), (5, -2), (-6, 0), (6, 0)):
        for t in range(1, 6):
            cv.px(8 + dx * t // 5, 10 + dy * t // 5, c("palm", 3) if t < 4 else c("palm", 2))
    cv.px(8, 9, c("palm", 4)); cv.px(7, 10, c("gold", 2)); cv.px(9, 10, c("gold", 2))
    cv.outline(); return cv


def fig_tree(seed=3):
    cv = Canvas(16, 24)
    cv.ellipse(8, 22, 4, 1, SHADOW, fill=True)
    cv.vline(8, 21, 7, c("wood", 2)); cv.px(9, 20, c("wood", 1))
    cv.px(7, 21, c("wood", 1))                              # root flare
    for (cx, cy, r) in ((6, 9, 4), (10, 8, 4), (8, 12, 4), (5, 12, 2), (11, 11, 2)):
        cv.circle(cx, cy, r, c("dark_leaf", 2), fill=True)
    cv.circle(6, 7, 2, c("olive", 3), fill=True)
    cv.circle(9, 6, 1, c("olive", 4), fill=True)
    cv.px(6, 10, "#6a2f52"); cv.px(10, 8, "#6a2f52")         # figs
    cv.px(9, 12, "#6a2f52"); cv.px(7, 13, "#7a3f62")
    cv.px(5, 12, c("dark_leaf", 1)); cv.px(10, 13, c("dark_leaf", 1))
    cv.outline(); return cv


def bush(seed=4):
    cv = Canvas(16, 10)
    cv.circle(6, 6, 4, c("olive", 2), fill=True); cv.circle(10, 6, 3, c("olive", 2), fill=True)
    cv.circle(6, 5, 2, c("olive", 3), fill=True)
    cv.outline(); cv.drop_shadow(); return cv


def wheat_sheaf(seed=5):
    cv = Canvas(8, 12)
    for x in range(1, 7):
        cv.vline(x, 11, 7 - abs(x - 3), c("wheat", 3))
        cv.px(x, 11 - (7 - abs(x - 3)), c("wheat", 4))
    cv.hline(1, 8, 6, c("wool", 2))
    cv.outline(); cv.drop_shadow(); return cv


# ── stone & earth ───────────────────────────────────────────────────────
def rock(seed=6):
    cv = Canvas(16, 10)
    cv.tri(3, 9, 8, 2, 13, 9, c("stone", 3))
    cv.line(8, 2, 4, 9, c("stone", 4)); cv.line(8, 2, 12, 9, c("stone", 2))
    cv.hline(3, 9, 11, c("stone", 1))
    cv.outline(); cv.drop_shadow(); return cv


def boulder(seed=7):
    cv = Canvas(16, 14)
    cv.circle(8, 8, 6, c("stone", 3), fill=True)
    cv.circle(6, 6, 3, c("stone", 4), fill=True)
    cv.circle(10, 10, 3, c("stone", 2), fill=True)
    cv.hline(3, 13, 10, c("stone", 1))
    cv.outline(); cv.drop_shadow(); return cv


def altar_stones(seed=8):
    """An altar of unhewn stones — Exodus 20:25 forbids tool-dressed stone."""
    cv = Canvas(16, 16)
    for (x, y, w, h) in ((3, 12, 10, 3), (4, 9, 8, 3), (5, 6, 6, 3), (6, 4, 4, 2)):
        cv.rect(x, y, w, h, c("stone", 3))
        cv.hline(x, y, w, c("stone", 4)); cv.hline(x, y + h - 1, w, c("stone", 1))
    # embers
    cv.px(7, 3, c("gold", 4)); cv.px(8, 3, c("blood", 3))
    cv.outline(); cv.drop_shadow(); return cv


def well(seed=9):
    cv = Canvas(16, 16)
    cv.ellipse(8, 11, 6, 4, c("stone", 3), fill=True)
    cv.ellipse(8, 10, 4, 2, c("water", 1), fill=True)
    cv.ellipse(8, 11, 6, 4, c("stone", 4))
    cv.vline(3, 3, 8, c("wood", 3)); cv.vline(12, 3, 8, c("wood", 3))
    cv.hline(3, 3, 10, c("wood", 4))
    cv.line(8, 4, 8, 8, c("wool", 2))
    cv.rect(7, 8, 2, 2, c("wood", 2))
    cv.outline(); cv.drop_shadow(); return cv


def cistern(seed=10):
    cv = Canvas(16, 12)
    cv.ellipse(8, 8, 6, 3, c("stone", 2), fill=True)
    cv.ellipse(8, 8, 4, 2, c("cliff", 0), fill=True)
    cv.ellipse(8, 8, 6, 3, c("stone", 4))
    cv.outline(); cv.drop_shadow(); return cv


def millstone(seed=11):
    cv = Canvas(16, 12)
    cv.ellipse(8, 8, 6, 4, c("stone", 3), fill=True)
    cv.ellipse(8, 6, 5, 3, c("stone", 4), fill=True)
    cv.px(8, 6, c("stone", 1))
    cv.rect(11, 4, 4, 2, c("wood", 3))
    cv.outline(); cv.drop_shadow(); return cv


# ── shelter ─────────────────────────────────────────────────────────────
def tent(seed=12):
    """Goat-hair tent: low, wide, lit doorway, guy ropes.

    The pack has no tent, so this stays generated — which means it has to sit
    NEXT TO pack art without looking pasted on. The first attempt was a dark
    navy triangle, and beside the village sheet's warm tan-and-green it read as
    a hole in the ground. Canvas and rope now come from the pack's own warm
    range (linen 0-3 for cloth, wood 0-2 for rope), with the lit doorway kept.
    """
    cv = Canvas(26, 18)
    # canvas body, lit from the left like every pack sprite
    cv.tri(2, 17, 13, 3, 24, 17, c("wool", 1))             # goat-hair canvas
    cv.tri(2, 17, 13, 3, 13, 17, c("wool", 2))             # sunlit half
    cv.line(2, 17, 13, 3, c("linen", 3)); cv.line(13, 3, 24, 17, c("wool", 0))
    cv.hline(3, 16, 20, c("wool", 0))                      # ground hem
    # doorway: warm interior, never black (black reads as a missing sprite)
    cv.tri(9, 17, 13, 9, 17, 17, c("wood", 1))
    cv.px(13, 14, c("gold", 3)); cv.px(12, 15, c("gold", 2)); cv.px(14, 15, c("gold", 2))
    # rope + pegs
    cv.line(2, 17, 0, 17, c("wood", 2)); cv.line(24, 17, 25, 17, c("wood", 2))
    cv.px(13, 2, c("wood", 1))
    cv.outline(); cv.drop_shadow(); return cv


def house(seed=13):
    """Flat-roofed mud-brick house, whitewashed, small window, external stair.
    1 Samuel 9:25 — Saul converses with Samuel on the roof. The stair matters."""
    cv = Canvas(32, 32)
    cv.rect(4, 10, 24, 20, c("mud", 3))
    cv.hline(4, 10, 24, c("mud", 4))                       # lit roof edge
    cv.rect(4, 8, 24, 2, c("mud", 4))                      # parapet (Deut 22:8)
    cv.vline(4, 10, 20, c("mud", 4)); cv.vline(27, 10, 20, c("mud", 1))
    # brick courses
    for y in range(12, 30, 3):
        cv.hline(5, y, 22, c("mud", 2))
    # door, arched
    cv.rect(13, 20, 6, 10, c("wood", 1))
    cv.hline(13, 20, 6, c("wood", 3))
    cv.px(17, 25, c("gold", 3))
    # window, small and dark
    cv.rect(8, 14, 3, 3, c("cliff", 0))
    cv.px(8, 14, c("mud", 4))
    # external stair up the right wall
    for i in range(6):
        cv.rect(28 - i, 28 - i * 3, 3, 3, c("stone", 3))
        cv.hline(28 - i, 28 - i * 3, 3, c("stone", 4))
    cv.outline(); cv.drop_shadow(); return cv


def column(seed=14):
    cv = Canvas(8, 24)
    cv.rect(2, 2, 4, 20, c("stone", 3))
    cv.vline(2, 2, 20, c("stone", 4)); cv.vline(5, 2, 20, c("stone", 2))
    cv.rect(1, 0, 6, 2, c("stone", 4)); cv.rect(1, 22, 6, 2, c("stone", 4))
    for y in range(4, 22, 4):
        cv.hline(2, y, 4, c("stone", 2))
    cv.outline(); cv.drop_shadow(); return cv


def gate(seed=15):
    cv = Canvas(32, 32)
    cv.rect(0, 4, 32, 28, c("stone", 3))
    cv.rect(0, 2, 32, 3, c("stone", 4))
    cv.rect(10, 12, 12, 20, c("cliff", 0))                # the opening
    cv.ellipse(16, 12, 6, 4, c("cliff", 0), fill=True)    # arch
    cv.rect(10, 12, 2, 20, c("stone", 2)); cv.rect(20, 12, 2, 20, c("stone", 2))
    for y in range(6, 32, 4):
        cv.hline(0, y, 10, c("stone", 2)); cv.hline(22, y, 10, c("stone", 2))
    cv.outline(); cv.drop_shadow(); return cv


# ── small stuff ─────────────────────────────────────────────────────────
def jar(seed=16):
    cv = Canvas(8, 10)
    cv.ellipse(4, 6, 3, 3, c("mud", 3), fill=True)
    cv.rect(3, 1, 2, 3, c("mud", 3))
    cv.hline(2, 1, 4, c("mud", 4))
    cv.px(2, 5, c("mud", 4))
    cv.outline(); return cv


def fire(seed=17):
    f0 = Canvas(16, 12)
    for (x, y) in ((5, 11), (7, 11), (9, 11), (11, 11)):
        f0.px(x, y, c("stone", 2))
    f0.tri(6, 11, 8, 4, 10, 11, c("gold", 3))
    f0.tri(7, 11, 8, 6, 9, 11, c("gold", 5))
    f0.px(8, 3, c("gold", 4))
    f1 = Canvas(16, 12)
    for (x, y) in ((5, 11), (7, 11), (9, 11), (11, 11)):
        f1.px(x, y, c("stone", 2))
    f1.tri(6, 11, 8, 5, 10, 11, c("gold", 3))
    f1.tri(7, 11, 8, 7, 9, 11, c("gold", 5))
    f1.px(7, 3, c("gold", 4)); f1.px(9, 4, c("gold", 4))
    return [f0, f1]


def boat(seed=18):
    cv = Canvas(32, 16)
    cv.tri(2, 6, 16, 14, 30, 6, c("wood", 2))
    cv.hline(2, 6, 28, c("wood", 4))
    cv.rect(4, 6, 24, 3, c("wood", 3))
    cv.vline(16, 0, 8, c("wood", 2))
    cv.outline(); return cv


def signpost(seed=19):
    cv = Canvas(16, 16)
    cv.vline(8, 4, 12, c("wood", 3))
    cv.rect(4, 3, 9, 4, c("wood", 4))
    cv.hline(5, 4, 7, c("wood", 2)); cv.hline(5, 6, 5, c("wood", 2))
    cv.outline(); return cv


def _build():
    _reg("olive_tree", olive_tree(), (1, 1), True, notes="Gethsemane, the Mount of Olives")
    _reg("palm_tree", palm_tree(), (1, 1), True, notes="Jericho, the Jordan, Egypt")
    _reg("fig_tree", fig_tree(), (1, 1), True, notes="Nathanael under the fig tree")
    _reg("bush", bush(), (1, 1), False)
    _reg("wheat_sheaf", wheat_sheaf(), (0, 0), False, notes="Ruth gleaned these")
    _reg("rock", rock(), (1, 1), True)
    _reg("boulder", boulder(), (1, 1), True)
    _reg("altar_stones", altar_stones(), (1, 1), True, notes="Exodus 20:25")
    _reg("well", well(), (1, 1), True, notes="Jacob's well, Rebecca at the well")
    _reg("cistern", cistern(), (1, 1), True, notes="Joseph's pit")
    _reg("millstone", millstone(), (1, 1), True, notes="Matthew 18:6")
    _reg("tent", tent(), (2, 1), True, notes="the camp at Elah")
    _reg("house", house(), (2, 2), True, notes="flat roof + external stair")
    _reg("column", column(), (1, 1), True, notes="temple, palace")
    _reg("gate", gate(), (2, 2), True, notes="city gate — where elders sat")
    _reg("jar", jar(), (0, 0), False)
    _reg("fire", fire(), (1, 1), False, frames=2, notes="Peter warmed himself by one")
    _reg("boat", boat(), (2, 1), True, notes="Sea of Galilee")
    _reg("signpost", signpost(), (0, 0), False)


_build()


def build_props():
    return {p["key"]: p for p in PROPS}
