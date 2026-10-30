"""Palette — the single source of colour truth for the whole game.

Every asset the generator produces is indexed to these ramps. This is the lever
that makes free/procedural art look like ONE game instead of five packs stapled
together (see docs/ART.md §5.3).

Inherited from Covenant's existing colour language, which was already coherent:
    field.js  COL.grassA #2b3d33  COL.water #16303c  COL.cliff #10171c
    rig.js    CHARS.pilgrim.robe #1b2a33  trim #c9a45c  hair #14202a
    styles.css  gold #f7dda5, indigo shadow #14202a

House style: deep indigo-teal shadows, warm gold highlights. Never pure black,
never pure white, never a fully-saturated colour.
"""

# Each ramp is ordered dark → light. Index 0 is the deepest shadow, the last is
# the specular highlight. Most surfaces use indices 1..3; 0 is for ambient
# occlusion and 4 (where present) is a rim light.
RAMPS = {
    # ── ground ──────────────────────────────────────────────────────────
    "grass":  ["#16211a", "#1f2e25", "#2b3d33", "#374c3e", "#46604d"],
    "dry":    ["#2a2519", "#3a3325", "#4a4130", "#5d5240", "#736650"],
    "path":   ["#332c20", "#463d2c", "#5a4e39", "#6e6047", "#857458"],
    "sand":   ["#574829", "#75613a", "#8f7849", "#a89160", "#c4ac78"],
    "wheat":  ["#4a4020", "#6a5c2c", "#8a7838", "#a8944a", "#c8b468"],
    "mud":    ["#3a2b1e", "#4e3a28", "#634a33", "#7a5d41", "#937354"],

    # ── stone & rock ────────────────────────────────────────────────────
    "stone":  ["#131a20", "#1e2932", "#2c3a45", "#3d4d59", "#546572", "#6f808c"],
    "cliff":  ["#0c1216", "#131c22", "#1d282f", "#2a373f", "#3a4a53"],

    # ── water ───────────────────────────────────────────────────────────
    "water":  ["#0a1620", "#122834", "#1a3b4a", "#245261", "#33707e", "#4d94a0"],
    "foam":   ["#3d7280", "#5d96a2", "#8abcc4", "#b8dce2"],

    # ── foliage ─────────────────────────────────────────────────────────
    "olive":  ["#1d2617", "#2b3820", "#3c4d2b", "#4f6437", "#657c47", "#7e9659"],
    "palm":   ["#1a2b1c", "#24402a", "#335a37", "#45743f", "#5b8f4a"],
    "dark_leaf": ["#101a13", "#1a2a1e", "#263d2a", "#345236"],

    # ── wood ────────────────────────────────────────────────────────────
    "wood":   ["#1a120b", "#2b1e13", "#3e2c1c", "#55402a", "#6d5539", "#876c4a"],

    # ── cloth & linen ───────────────────────────────────────────────────
    "linen":  ["#5c6470", "#7b8492", "#9aa3ae", "#bcc3ca", "#dde2e5", "#f2f5f6"],
    "wool":   ["#4a4034", "#63574a", "#7d6f5e", "#998a76"],

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
    "robe_pilgrim": ["#0e171d", "#16242c", "#1b2a33", "#24363f", "#33485a"],
    "robe_scribe":  ["#241d2e", "#312840", "#3a2f46", "#4a3d59", "#5c4d6e"],
    "robe_soldier": ["#252e24", "#313d30", "#3d4a3a", "#4b5a46", "#5e6f58"],
    "robe_woman":   ["#2e2029", "#3d2b36", "#4a3340", "#5b4250", "#705264"],
    "robe_david":   ["#4a3220", "#5f4128", "#7a5230", "#8d6339", "#a3764a"],
    "robe_elder":   ["#1e272e", "#28343d", "#2f3b46", "#3d4c58", "#4e606e"],
    "robe_giant":   ["#181e25", "#212a33", "#2b3540", "#3a4550", "#4a5763"],
    "robe_priest":  ["#8a8578", "#a8a294", "#c4beb0", "#ddd8cc", "#f0ece4"],
    "robe_pharisee": ["#141f2e", "#1d2c40", "#263a52", "#33496a", "#435c82"],

    "hair_dark":  ["#080c10", "#0e151b", "#14202a", "#1e2c38"],
    "hair_grey":  ["#6b6a66", "#8a8985", "#a5a4a0", "#c2c1bd"],
    "hair_red":   ["#3a1a10", "#5c2a18", "#7d3c22", "#9d5230"],
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
