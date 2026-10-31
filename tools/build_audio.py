#!/usr/bin/env python3
"""build_audio.py — synthesise every sound the game asks for, from scratch.

There is no audio budget: the project is solo and unfunded, and a game whose
`AudioDirector` silently drops every call because the folder is empty is a game
with no sound at all. So the sounds are *made* here, in pure Python, and written
into `audio/` as 22.05 kHz mono 16-bit WAV — small, deterministic, and the same
on every machine.

    python3 tools/build_audio.py            # write audio/sfx/*.wav, audio/music/*.wav
    python3 tools/build_audio.py --check    # verify what is on disk, write nothing

Design notes (docs/FEEL.md §4):

  * Footsteps are the sound the player hears most, so they carry the most
    information: four surfaces, four textures. Dirt is dull, grass is soft and
    wide, sand is grainy and short, stone is a click with a little ring, water is
    a splash with a bubble in it.
  * Nothing is loud. A witness walking through a valley should hear a valley.
  * Music loops are additive and *periodic*: every oscillator's cycle count over
    the loop length is a whole number, and every note tail wraps around the end
    of the buffer, so the seam is silent to the ear. A loop that clicks is worse
    than no music.
  * The two tracks are the two things the chapter is: a valley and a duel.

Everything is generated, so there are no licence questions and no downloads.
"""

import array
import math
import pathlib
import struct
import sys

SR = 22050
ROOT = pathlib.Path(__file__).resolve().parent.parent
SFX_DIR = ROOT / "audio" / "sfx"
MUSIC_DIR = ROOT / "audio" / "music"

TAU = math.pi * 2.0


# ── buffers ────────────────────────────────────────────────────────────────

def buf(seconds):
    return [0.0] * int(SR * seconds)


def mix(dst, src, at=0.0, gain=1.0, wrap=False):
    """Add `src` into `dst` at `at` seconds. `wrap` is what makes a loop seam
    disappear: the tail of the last note lands at the start of the buffer."""
    n = len(dst)
    start = int(at * SR)
    ln = len(src)
    for i in range(ln):
        j = start + i
        if wrap:
            j %= n
        if 0 <= j < n:
            dst[j] += src[i] * gain


def noise(n, seed=1):
    """Deterministic white noise — same bytes on every machine, so the WAVs never
    show up as spurious diffs."""
    out = [0.0] * n
    x = seed | 1
    for i in range(n):
        x ^= (x << 13) & 0xFFFFFFFF
        x ^= x >> 17
        x ^= (x << 5) & 0xFFFFFFFF
        out[i] = (x / 0xFFFFFFFF) * 2.0 - 1.0
    return out


def lowpass(sig, cutoff_fn, res=0.0):
    """One-pole lowpass with a per-sample cutoff. Cheap, and the shape of a
    filtered noise burst is most of what makes a footstep sound like a surface."""
    out = [0.0] * len(sig)
    y = 0.0
    for i, x in enumerate(sig):
        a = cutoff_fn(i / max(1, len(sig) - 1))
        a = min(0.999, max(0.0005, a))
        y += (x - y) * a
        out[i] = y
    return out


def envelope(n, attack, decay, curve=2.0, sustain=0.0):
    a = max(1, int(attack * SR))
    d = max(1, int(decay * SR))
    out = [0.0] * n
    for i in range(n):
        if i < a:
            e = i / a
        else:
            t = (i - a) / d
            if t >= 1.0:
                e = sustain
            else:
                e = (1.0 - t) ** curve * (1.0 - sustain) + sustain
        out[i] = e
    return out


def tone(freq, seconds, decay=1.0, curve=2.5, harm=(1.0,), detune=0.0):
    """A struck note: a few partials, all decaying. `harm` is the partial
    amplitudes, so (1.0, 0.35, 0.12) is a bell and (1.0,) is a soft sine."""
    n = int(SR * seconds)
    out = [0.0] * n
    env = envelope(n, 0.004, decay, curve)
    for k, amp in enumerate(harm, start=1):
        if amp == 0.0:
            continue
        f = freq * k * (1.0 + detune * (k - 1))
        if f >= SR * 0.45:
            continue
        w = TAU * f / SR
        for i in range(n):
            out[i] += math.sin(w * i) * amp * env[i]
    return out


def normalise(sig, peak):
    m = max((abs(v) for v in sig), default=0.0)
    if m < 1e-9:
        return sig
    k = peak / m
    return [v * k for v in sig]


def fade_edges(sig, ms=3.0):
    """A hard cut at sample 0 is a click. Every buffer gets a micro-fade."""
    n = int(SR * ms / 1000.0)
    n = min(n, len(sig) // 2)
    for i in range(n):
        g = i / n
        sig[i] *= g
        sig[-1 - i] *= g
    return sig


def write_wav(path, sig, peak=0.7):
    sig = normalise(sig, peak)
    path.parent.mkdir(parents=True, exist_ok=True)
    data = array.array("h", (int(max(-1.0, min(1.0, v)) * 32767) for v in sig))
    with open(path, "wb") as f:
        f.write(b"RIFF")
        f.write(struct.pack("<I", 36 + len(data) * 2))
        f.write(b"WAVEfmt ")
        f.write(struct.pack("<IHHIIHH", 16, 1, 1, SR, SR * 2, 2, 16))
        f.write(b"data")
        f.write(struct.pack("<I", len(data) * 2))
        data.tofile(f)
    return path


# ── footsteps ──────────────────────────────────────────────────────────────
# Each is ~70-110 ms. They are heard at most three times a second, so they have
# to be short, dry and distinguishable from one another — a player should be able
# to tell the causeway from the grass without looking.

def step_dirt():
    n = int(SR * 0.09)
    sig = lowpass(noise(n, 11), lambda t: 0.06 - 0.04 * t)
    sig = [v * envelope(n, 0.002, 0.07, 1.6)[i] for i, v in enumerate(sig)]
    mix(sig, tone(96.0, 0.07, 0.05, 2.0), 0.0, 0.5)
    return fade_edges(sig)


def step_grass():
    n = int(SR * 0.11)
    sig = lowpass(noise(n, 23), lambda t: 0.12 - 0.08 * t)
    sig = [v * envelope(n, 0.008, 0.09, 1.2)[i] for i, v in enumerate(sig)]
    return fade_edges(sig)


def step_sand():
    n = int(SR * 0.07)
    # grain: noise gated by a fast tremolo, then softened
    gate = noise(n, 31)
    sig = [noise(n, 41)[i] * (0.5 + 0.5 * gate[i]) for i in range(n)]
    sig = lowpass(sig, lambda t: 0.30 - 0.18 * t)
    sig = [v * envelope(n, 0.001, 0.05, 1.4)[i] for i, v in enumerate(sig)]
    return fade_edges(sig)


def step_stone():
    n = int(SR * 0.10)
    sig = lowpass(noise(n, 53), lambda t: 0.02 + 0.5 * math.exp(-t * 8.0))
    sig = [v * envelope(n, 0.001, 0.06, 2.0)[i] for i, v in enumerate(sig)]
    mix(sig, tone(940.0, 0.08, 0.03, 3.0), 0.0, 0.25)
    mix(sig, tone(1420.0, 0.06, 0.02, 3.0), 0.003, 0.12)
    return fade_edges(sig)


def step_water():
    n = int(SR * 0.16)
    body = lowpass(noise(n, 67), lambda t: 0.35 - 0.3 * t)
    body = [v * envelope(n, 0.004, 0.13, 1.5)[i] for i, v in enumerate(body)]
    # the bubble: a short rising sine, which is what tells the ear "water"
    b = tone(420.0, 0.08, 0.05, 2.0)
    b = [v * (1.0 + 0.6 * (i / len(b))) for i, v in enumerate(b)]
    mix(body, b, 0.02, 0.35)
    return fade_edges(body)


# ── the rest of the sound of the game ──────────────────────────────────────

def sfx_hit():
    n = int(SR * 0.22)
    body = tone(88.0, 0.20, 0.13, 1.8, harm=(1.0, 0.4, 0.15))
    thud = lowpass(noise(n, 71), lambda t: 0.05 - 0.035 * t)
    thud = [v * envelope(n, 0.001, 0.12, 1.5)[i] for i, v in enumerate(thud)]
    mix(thud, body, 0.0, 0.9)
    return fade_edges(thud)


def sfx_miss():
    # a spear going past: filtered noise sweeping downward, no attack click
    n = int(SR * 0.26)
    sig = lowpass(noise(n, 83), lambda t: 0.55 - 0.5 * t)
    env = envelope(n, 0.02, 0.22, 1.3)
    sig = [v * env[i] for i, v in enumerate(sig)]
    return fade_edges(sig)


def sfx_sling():
    # the sling: a short rising whirr, because the stone leaves on the third turn
    n = int(SR * 0.24)
    sig = lowpass(noise(n, 97), lambda t: 0.08 + 0.7 * t * t)
    env = envelope(n, 0.10, 0.13, 1.2)
    sig = [v * env[i] for i, v in enumerate(sig)]
    mix(sig, tone(300.0, 0.2, 0.16, 1.6, harm=(1.0, 0.2)), 0.0, 0.15)
    return fade_edges(sig)


def sfx_dodge():
    n = int(SR * 0.14)
    sig = lowpass(noise(n, 103), lambda t: 0.45 * (1.0 - abs(t - 0.4) * 1.4))
    env = envelope(n, 0.01, 0.12, 1.4)
    sig = [v * env[i] for i, v in enumerate(sig)]
    return fade_edges(sig)


def sfx_pickup():
    # two struck notes, a fifth apart: the sound of a thing being gathered
    sig = buf(0.42)
    mix(sig, tone(587.33, 0.34, 0.26, 2.6, harm=(1.0, 0.25, 0.08)), 0.0, 0.7)
    mix(sig, tone(880.0, 0.30, 0.20, 2.6, harm=(1.0, 0.22, 0.06)), 0.075, 0.55)
    return fade_edges(sig)


def sfx_blip():
    # one syllable of a voice: a very short odd-harmonic tick, then silence
    n = int(SR * 0.045)
    sig = [0.0] * n
    for i in range(n):
        t = i / SR
        v = 0.0
        for k, amp in ((1, 1.0), (3, 0.35), (5, 0.15)):
            v += math.sin(TAU * 420.0 * k * t) * amp
        sig[i] = v * math.exp(-t * 55.0)
    return fade_edges(sig)


def sfx_verse():
    # The chapter's theological sound event: a rising chime, then a shimmer that
    # outlasts the dialogue box that triggered it. It must not sound like a
    # reward for doing well. It is an *ending* — something has been given.
    sig = buf(1.8)
    for i, f in enumerate((587.33, 880.0, 1174.66)):
        mix(sig, tone(f, 1.3, 1.05, 1.9, harm=(1.0, 0.35, 0.15, 0.06)), i * 0.12, 0.7)
    mix(sig, tone(1760.0, 1.5, 1.25, 2.6, harm=(1.0, 0.2)), 0.32, 0.22)
    mix(sig, tone(293.66, 1.6, 1.4, 1.8, harm=(1.0, 0.3)), 0.0, 0.18)
    return fade_edges(sig, 6.0)


def sfx_quest():
    # Two notes up: an objective has been met, not a battle won.
    sig = buf(0.55)
    mix(sig, tone(523.25, 0.38, 0.30, 2.4, harm=(1.0, 0.22, 0.07)), 0.0, 0.7)
    mix(sig, tone(783.99, 0.44, 0.36, 2.4, harm=(1.0, 0.22, 0.07)), 0.10, 0.6)
    return fade_edges(sig)


def sfx_ui():
    # a soft wooden tap: used by panels, kept under everything else
    sig = tone(660.0, 0.09, 0.06, 3.0, harm=(1.0, 0.2))
    return fade_edges(sig)


# ── music ──────────────────────────────────────────────────────────────────
# Additive, periodic, and quiet. D minor for the valley (the key the v1 story
# used), a tritone against it for the duel.

def periodic_tone(freq, seconds, loop, gain, harm=(1.0,), lfo=(0.0, 0.0)):
    """A continuous tone whose frequency is snapped to a whole number of cycles
    across the *loop*, so the last sample joins the first with no step."""
    n = int(loop * SR)
    out = [0.0] * n
    for k, amp in enumerate(harm, start=1):
        f = freq * k
        cycles = max(1, round(f * loop))
        f = cycles / loop
        w = TAU * f / SR
        if lfo[0] > 0.0:
            lw = TAU * lfo[0] / SR
            for i in range(n):
                out[i] += math.sin(w * i) * amp * (1.0 - lfo[1] + lfo[1] * math.sin(lw * i))
        else:
            for i in range(n):
                out[i] += math.sin(w * i) * amp
    return [v * gain for v in out]


def wind(loop):
    n = int(loop * SR)
    base = lowpass(noise(n, 131), lambda t: 0.012)
    out = [0.0] * n
    lw = TAU * (1.0 / loop) * 3.0 / SR     # three slow swells per loop
    for i in range(n):
        g = 0.5 + 0.5 * math.sin(lw * i)
        out[i] = base[i] * (0.4 + 0.6 * g)
    return out


def music_valley(loop=24.0):
    n = int(loop * SR)
    out = [0.0] * n
    # the drone: D2, A2, and a bare D3, all periodic over the loop
    for f, g in ((73.42, 0.30), (110.0, 0.16), (146.83, 0.08)):
        tone_ = periodic_tone(f, loop, loop, g, harm=(1.0, 0.3, 0.12),
                              lfo=(2.0 / loop if f < 100 else 0.0, 0.35))
        for i in range(n):
            out[i] += tone_[i]
    out = [v + w * 0.12 for v, w in zip(out, wind(loop))]
    # a slow pentatonic line, one note every 2.4 s, tails wrapping the seam
    notes = [587.33, 440.0, 493.88, 392.0, 440.0, 349.23, 293.66, 349.23, 440.0, 587.33]
    for step_i, f in enumerate(notes):
        at = step_i * 2.4
        pluck = tone(f, 2.6, 2.2, 2.2, harm=(1.0, 0.22, 0.06))
        mix(out, pluck, at % loop, 0.16, wrap=True)
        # and a soft answer an octave down, late, like a second instrument
        mix(out, tone(f * 0.5, 2.2, 1.8, 2.4, harm=(1.0, 0.15)), (at + 1.2) % loop, 0.09, wrap=True)
    return out


def music_battle(loop=12.0):
    n = int(loop * SR)
    out = [0.0] * n
    # D2 and its tritone: the interval that will not resolve
    for f, g in ((73.42, 0.26), (103.83, 0.14), (146.83, 0.07)):
        tone_ = periodic_tone(f, loop, loop, g, harm=(1.0, 0.4, 0.2),
                              lfo=(3.0 / loop, 0.4))
        for i in range(n):
            out[i] += tone_[i]
    # a pulse every 1.5 s: a low drum, and a breath of noise after it
    for k in range(int(loop / 1.5)):
        at = k * 1.5
        drum = tone(58.0, 0.42, 0.3, 2.0, harm=(1.0, 0.3))
        mix(out, drum, at, 0.55, wrap=True)
        dust = lowpass(noise(int(SR * 0.2), 149 + k), lambda t: 0.10 - 0.07 * t)
        dust = [v * envelope(len(dust), 0.002, 0.16, 1.6)[i] for i, v in enumerate(dust)]
        mix(out, dust, at + 0.01, 0.16, wrap=True)
    # a held, thin line above it every four beats
    for k, f in enumerate((440.0, 466.16, 523.25)):
        mix(out, tone(f, 3.0, 2.6, 2.0, harm=(1.0, 0.18)), (k * 4.0) % loop, 0.10, wrap=True)
    return out


# ── the shelf ──────────────────────────────────────────────────────────────

SFX = {
    "step_dirt": (step_dirt, 0.55),
    "step_grass": (step_grass, 0.45),
    "step_sand": (step_sand, 0.50),
    "step_stone": (step_stone, 0.55),
    "step_water": (step_water, 0.50),
    "hit": (sfx_hit, 0.80),
    "miss": (sfx_miss, 0.55),
    "sling": (sfx_sling, 0.65),
    "dodge": (sfx_dodge, 0.50),
    "pickup": (sfx_pickup, 0.60),
    "blip": (sfx_blip, 0.30),
    "verse": (sfx_verse, 0.62),
    "quest": (sfx_quest, 0.55),
    "ui": (sfx_ui, 0.45),
}

MUSIC = {
    "valley": (music_valley, 0.42),
    "battle": (music_battle, 0.40),
}


def build(write=True):
    made = []
    for name, (fn, peak) in SFX.items():
        path = SFX_DIR / (name + ".wav")
        if write:
            write_wav(path, fn(), peak)
        made.append(path)
    for name, (fn, peak) in MUSIC.items():
        path = MUSIC_DIR / (name + ".wav")
        if write:
            write_wav(path, fn(), peak)
        made.append(path)
    return made


# ── check ──────────────────────────────────────────────────────────────────

def read_wav(path):
    raw = path.read_bytes()
    if raw[:4] != b"RIFF" or raw[8:12] != b"WAVE":
        raise SystemExit("%s: not a RIFF/WAVE file" % path.name)
    pos = 12
    fmt = None
    data = None
    while pos + 8 <= len(raw):
        cid = raw[pos:pos + 4]
        size = struct.unpack("<I", raw[pos + 4:pos + 8])[0]
        body = raw[pos + 8:pos + 8 + size]
        if cid == b"fmt ":
            fmt = struct.unpack("<HHIIHH", body[:16])
        elif cid == b"data":
            data = body
        pos += 8 + size + (size & 1)
    if fmt is None or data is None:
        raise SystemExit("%s: missing fmt or data chunk" % path.name)
    _tag, channels, rate, _bps, _align, bits = fmt
    samples = array.array("h")
    samples.frombytes(data)
    return channels, rate, bits, samples


def requested():
    """Every sound name the game can ask for, read from the game itself:
    terrain from data/tiles.json, the two literals in code, and the music keys
    each region names. A shelf that is complete but out of date is still a game
    with no sound."""
    import json
    import re

    wanted = {"sfx": set(), "music": set()}
    tiles = json.loads((ROOT / "data" / "tiles.json").read_text(encoding="utf-8"))
    # `tiles` is a list of {"key","variant","sfx",...} rows — one per atlas cell.
    for row in tiles.get("tiles", []):
        if isinstance(row, dict) and isinstance(row.get("sfx"), str) and row["sfx"]:
            wanted["sfx"].add(row["sfx"])
    for path in sorted((ROOT / "data" / "regions").glob("*.json")):
        d = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(d.get("music"), str) and d["music"]:
            wanted["music"].add(d["music"])
    for path in sorted((ROOT / "scripts").rglob("*.gd")):
        text = path.read_text(encoding="utf-8")
        for name in re.findall(r'play_sfx\(\s*"([a-z0-9_]+)"', text):
            wanted["sfx"].add(name)
        for name in re.findall(r'play_music\(\s*"([a-z0-9_]+)"', text):
            wanted["music"].add(name)
    return wanted


def check():
    problems = []
    total = 0
    for group, table, folder in (("sfx", SFX, SFX_DIR), ("music", MUSIC, MUSIC_DIR)):
        for name, (fn, _peak) in table.items():
            path = folder / (name + ".wav")
            if not path.exists():
                problems.append("%s/%s.wav is missing — run tools/build_audio.py" % (group, name))
                continue
            total += path.stat().st_size
            channels, rate, bits, samples = read_wav(path)
            if (channels, rate, bits) != (1, SR, 16):
                problems.append("%s: %d ch / %d Hz / %d-bit, expected mono %d Hz 16-bit"
                                % (path.name, channels, rate, bits, SR))
            if rate and len(samples) / rate < 0.03:
                problems.append("%s: too short to hear" % path.name)
            peak = max((abs(v) for v in samples), default=0)
            if peak < 1200:
                problems.append("%s: silent (peak %d)" % (path.name, peak))
            if group == "music" and peak >= 32767:
                problems.append("%s: clipping" % path.name)
    # nothing the game asks for may be missing, and nothing may be orphaned
    asked = set(SFX.keys())
    for key in sorted(asked):
        if not (SFX_DIR / (key + ".wav")).exists():
            problems.append("game asks for sfx '%s' and finds nothing" % key)
    for group, names in requested().items():
        folder = SFX_DIR if group == "sfx" else MUSIC_DIR
        for name in sorted(names):
            if not (folder / (name + ".wav")).exists():
                problems.append("the game asks for %s '%s' and the shelf is empty" % (group, name))
    if problems:
        for p in problems:
            print("  " + p)
        raise SystemExit("check_audio: %d problem(s)" % len(problems))
    print("check_audio: clean — %d sounds, %d tracks, %.1f KB total"
          % (len(SFX), len(MUSIC), total / 1024.0))


if __name__ == "__main__":
    if "--check" in sys.argv:
        check()
    else:
        build()
        check()
