"""Palette — the single source of colour truth for the whole game.

Every asset the generator produces is indexed to these ramps. This is the lever
that makes free/procedural art look like ONE game instead of five packs stapled
together (see docs/ART.md §5.3).

Inherited from Covenant's existing colour language, which was already coherent:
    field.js  COL.grassA #2b3d33  COL.water #16303c  COL.cliff #10171c
    rig.js    CHARS.pilgrim.robe #1b2a33  trim #c9a45c  hair #14202a
    styles.css  gold #f7dda5, indigo shadow #14202a

House style, revised after the first playtest: the original ramps inherited
Covenant's deep indigo-teal shadows, and on a phone screen that read as mud next
to the GBA-bright tilesets the game is measured against. Ramps now sit at
handheld saturation — mid-tones carry the hue, index 0 still carries ambient
occlusion, and the warm-gold highlight language is untouched. Never pure black,
never pure white.
"""

# Each ramp is ordered dark → light. Index 0 is the deepest shadow, the last is
# the specular highlight. Most surfaces use indices 1..3; 0 is for ambient
# occlusion and 4 (where present) is a rim light.
RAMPS = {
    # ── ground ──────────────────────────────────────────────────────────
    "grass": ["#2e6b34","#3f8a40","#58a850","#74c462","#98dc78"],
    "dry": ["#6b5a38","#8a7448","#a89058","#c4ac74","#dcc894"],
    "path": ["#7a6242","#98805a","#b49a6e","#ccb484","#e0cc9c"],
    "sand": ["#8a7448","#a89060","#c4ac78","#dcc894","#f0e0b4"],
    "wheat": ["#8a7428","#a89438","#c4b44c","#dccc64","#f0e084"],
    "mud": ["#5a4430","#74583e","#8c6e4c","#a48460","#bc9c74"],

    # ── stone & rock ────────────────────────────────────────────────────
    "stone": ["#4a545c","#626e78","#7c8894","#98a4ae","#b4bec6","#ccd4da"],
    "cliff": ["#333c44","#46505a","#5a646e","#727c86","#8a949e"],

    # ── water ───────────────────────────────────────────────────────────
    "water": ["#1a3c7c","#2858a8","#3878c8","#58a0e0","#88c8f0","#c0e8fc"],
    "foam": ["#78b8d8","#a0d4e8","#c8ecf8","#e8f8fc"],

    # ── foliage ─────────────────────────────────────────────────────────
    "olive": ["#3c5424","#506c2c","#688838","#84a448","#a0c060","#bcda7c"],
    "palm": ["#2c5c30","#3c7840","#4c9450","#60b060","#78cc74"],
    "dark_leaf": ["#24422a","#34583a","#46704a","#5a8a5c"],

    # ── wood ────────────────────────────────────────────────────────────
    "wood": ["#4a3220","#64462c","#7e5a38","#987248","#b28a58","#cca46c"],

    # ── cloth & linen ───────────────────────────────────────────────────
    "linen":  ["#5c6470", "#7b8492", "#9aa3ae", "#bcc3ca", "#dde2e5", "#f2f5f6"],
    "wool": ["#6a5c48","#84745c","#9e8c72","#b8a688"],

    # ── skin ────────────────────────────────────────────────────────────
    "skin":   ["#5e3f28", "#7d5436", "#a06f45", "#c08e5c", "#d9ad7c", "#eec99c"],

    # ── metals & accents ────────────────────────────────────────────────
    "gold":   ["#6b4f1e", "#8d6a2a", "#b3893c", "#c9a45c", "#e2c07e", "#f7dda5"],
    "bronze": ["#3d2a14", "#5c4020", "#7d5a2e", "#9d7540", "#bd9356"],
    "iron":   ["#1a1e22", "#2a3036", "#3d454c", "#545e66", "#6f7a83"],
    "blood":  ["#2e1212", "#4d1c1a", "#6f2823", "#8f3830"],

    # ── divine / supernatural ───────────────────────────────────────────
    "holy":   ["#4a4020", "#8d7a3a", "#c9b45c", "#f0e0a0", "#fff8dc"],
    "spirit": ["#16303c", "#2f6272", "#5d96a2", "#a8d8e0", "#e0f4f8"],

    # ── robe colours per character (Covenant's CHARS table) ─────────────
    "robe_pilgrim": ["#3c4c28","#4e6234","#627a40","#78924e","#90ac60"],
    "robe_scribe": ["#4a3860","#5e4a78","#745e92","#8a74aa","#a28cc2"],
    "robe_soldier": ["#3e4a34","#506044","#647654","#7a8c66","#92a47a"],
    "robe_woman": ["#6a3848","#844a5c","#9e5e72","#b8768a","#d292a4"],
    "robe_david": ["#7a4028","#945232","#ae6640","#c87e50","#e09a68"],
    "robe_elder": ["#3a4a5c","#4c5e72","#607488","#768a9e","#8ea2b4"],
    "robe_giant": ["#4a3a28","#5e4c34","#746042","#8a7452","#a28a64"],
    "robe_priest":  ["#8a8578", "#a8a294", "#c4beb0", "#ddd8cc", "#f0ece4"],
    "robe_pharisee": ["#2a3c66","#385080","#48649a","#5a7ab4","#7092cc"],

    "hair_dark": ["#20242c","#2c323c","#3a424e","#4a5460"],
    "hair_grey":  ["#6b6a66", "#8a8985", "#a5a4a0", "#c2c1bd"],
    "hair_red": ["#5c2a18","#7a3a20","#98492a","#b65c36"],
}


def ramp(name):
    """The full dark→light ramp for a material."""
    return RAMPS[name]


def c(name, i):
    """One colour from a ramp, clamped. `c('grass', 2)` is the mid-tone."""
    r = RAMPS[name]
    return r[max(0, min(len(r) - 1, i))]


def hexrgb(h):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


# The complete flat list, for building a PNG palette or checking an image is
# fully indexed. Anything not in here should not appear in shipped art.
ALL = sorted({h for r in RAMPS.values() for h in r})

# ── Semantic aliases used throughout the generator ───────────────────────────
SHADOW      = c("cliff", 0)     # deepest ambient shadow, never pure black
OUTLINE     = "#0a0e12"         # sprite outlines: near-black indigo, not #000
HIGHLIGHT   = c("gold", 5)      # warm rim light / divine accent
GOLD        = c("gold", 3)
WATER_DEEP  = c("water", 1)
SKY_NIGHT   = "#0b1218"
SKY_DAWN    = "#2a3340"
SKY_DAY     = "#4a6070"
SKY_DUSK    = "#3a2c33"


def blend(h1, h2, t):
    """Linear blend between two hex colours. t=0 → h1, t=1 → h2."""
    a, b = hexrgb(h1), hexrgb(h2)
    return "#%02x%02x%02x" % tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def shade(h, amount):
    """Lighten (amount>0) or darken (amount<0) a colour toward white/black."""
    return blend(h, "#ffffff" if amount > 0 else "#000000", min(0.95, abs(amount)))
