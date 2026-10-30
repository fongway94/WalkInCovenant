# FEEL — the specification for "Switch quality on a phone"

> This is the document that answers your actual question. Not "can it be built" — it can — but
> **why does Pokémon feel good, and what numbers do I type to get that.**
>
> "Game feel" is not magic and it is not graphics. It is a short list of measurable decisions.
> Every number below is a starting point to be tuned in Phase 0, not a law.

---

## 1. The eight things that make a top-down RPG feel like Pokémon

Ranked by impact-per-hour for a solo developer. **Work top-down. Do not skip to the bottom.**

| # | Thing | Impact | Effort |
|---|---|---|---|
| 1 | **Turn-in-place** — a direction change rotates first, then steps | ★★★★★ | 30 min |
| 2 | **Input buffering** — the press you made *during* the turn is not lost | ★★★★★ | 1 h |
| 3 | **Grid magnetism** — soft pull to tile centres on the crossing axis | ★★★★☆ | 2 h |
| 4 | **Camera deadzone + lookahead + clamp** | ★★★★☆ | 2 h |
| 5 | **Footsteps keyed to terrain, alternating L/R** | ★★★★☆ | 2 h |
| 6 | **Animation states beyond walk** (idle, run, turn, emote, carry) | ★★★☆☆ | 4 h |
| 7 | **Juice on every interaction** (tween, blip, particle, shake) | ★★★☆☆ | 6 h |
| 8 | **Lighting + weather** (CanvasModulate, PointLight2D, particles) | ★★★☆☆ | 8 h |

Items 1–5 together cost about **one weekend** and are responsible for most of the difference between
your current `field.js` and something that feels professional. Your existing controller does have
`tryMove()` with collision and a `frame` walk cycle — what it lacks is *all eight of these*, and
especially the temporal ones (1, 2, 5), which are invisible in a screenshot and enormous in the hand.

---

## 2. Movement

### 2.1 Numbers

Logical space: **1 tile = 16 px**, base viewport **320×180** = 20 × 11.25 tiles visible.

| Parameter | Start value | Notes |
|---|---|---|
| Walk speed | **60 px/s** (3.75 tiles/s) | Pokémon's overworld walk is roughly 3–4 tiles/s. Above 5 feels frantic. |
| Run speed | **96 px/s** (6.0 tiles/s) | 1.6× walk. Hold-to-run, never a toggle. |
| Acceleration | **900 px/s²** | Reaches walk speed in ~67 ms — effectively instant, but not literally instant, which avoids the "ice" feel. |
| Deceleration | **1200 px/s²** | Stops faster than it starts. Snappy stop = responsive. |
| Turn time | **0.07 s** (70 ms) | The single most important number in this document. See §2.2. |
| Grid magnet | **22 px/s** toward tile centre | Applied only on the axis you are *not* moving along. |
| Interaction range | **0.9 tile** | Face the thing, press A. Not proximity-auto like Covenant's `TALK_RANGE = TILE * 1.45`. |
| Body radius | **5 px** capsule, feet at +6 y | Small hitbox, so one-tile doorways never catch you. |

### 2.2 Turn-in-place — the whole ballgame

```
Frame 0        Player holds RIGHT while facing DOWN.
Frame 0–4      Character rotates to face RIGHT. Does NOT translate.
               (~70 ms at 60 fps = 4 frames)
Frame 5+       Character begins stepping RIGHT at walk speed.
```

**Why:** without this, a direction change translates and rotates in the same frame. The sprite's feet
are then moving sideways relative to its facing for a few frames, and the brain reads that as *sliding
on ice*. With it, the character reads as a **person who decided to go somewhere**.

**Why 70 ms and not 150 ms:** 150 ms feels sluggish and laggy on repeated taps. 40 ms is too fast to
read. 60–80 ms is the sweet spot. Pokémon's own turn delay is in this range.

**Exception — the 180°:** turning from DOWN to UP should use the same 70 ms, but you may skip it
entirely when the player is holding run, because at run speed the delay reads as input lag.
Tune by feel; document what you land on.

### 2.3 Input buffering

The bug that makes grid games feel broken: you press RIGHT during your turn animation, the turn
system is mid-rotation, the press is consumed and discarded, and you have to press again. Players
experience this as "the game didn't hear me" and cannot articulate it.

```gdscript
# Buffer the most recent directional press for BUFFER_WINDOW seconds.
# On exiting TURNING, consume the buffer instead of requiring a fresh press.
const BUFFER_WINDOW := 0.18

var _buffer: Vector2i = Vector2i.ZERO
var _buffer_age := 999.0

func _buffer_input(dir: Vector2i) -> void:
    _buffer = dir
    _buffer_age = 0.0

func _consume_buffer() -> Vector2i:
    if _buffer_age <= BUFFER_WINDOW and _buffer != Vector2i.ZERO:
        var d := _buffer
        _buffer = Vector2i.ZERO
        _buffer_age = 999.0
        return d
    return Vector2i.ZERO
```

180 ms is generous — about 11 frames. Generous is correct here; a dropped input feels far worse than
a slightly-too-eager one.

### 2.4 Grid magnetism (corner correction)

Pure free movement makes one-tile doorways infuriating: you are 3 px off centre and you bounce.
Pure tile-lock movement feels stiff and dated.

**Do this:** while moving along one axis, apply a gentle pull toward the centre of the current tile on
the *other* axis. 22 px/s is imperceptible as force but reliably centres you before a gap.

```gdscript
func _apply_grid_magnetism(delta: float) -> void:
    if velocity == Vector2.ZERO:
        return
    var centre := (global_position / TILE).floor() * TILE + Vector2(TILE * 0.5, TILE)
    if absf(velocity.x) > absf(velocity.y):
        # moving horizontally → pull vertically toward centre
        var dy := centre.y - global_position.y
        global_position.y += clampf(dy, -magnet * delta, magnet * delta)
    else:
        var dx := centre.x - global_position.x
        global_position.x += clampf(dx, -magnet * delta, magnet * delta)
```

Also add explicit **corner correction**: if a move is blocked and the overlap on the perpendicular
axis is ≤ 4 px, nudge past the corner instead of stopping. This is the difference between "the wall
ate me" and "I slipped through the door."

### 2.5 Collision layers

| Layer | Contents |
|---|---|
| 1 | World — terrain, walls, buildings, props |
| 2 | Player |
| 3 | NPCs (solid — you cannot walk through people, which matters for escort quests) |
| 4 | Interactable triggers (Area2D, non-solid: pickups, doors, the challenge line) |
| 5 | Set-piece actors |

In Godot: put collision on a **TileMap physics layer**, not on individual `StaticBody2D` per tile.
One `TileSet` resource, painted in the editor, is exactly the workflow you were missing when
`buildGrid()` generated the map from stamps in code.

---

## 3. Camera

```gdscript
# scenes/world/CameraRig.gd
extends Camera2D

@export var deadzone      := Vector2(48, 32)   # px — player moves freely inside this box
@export var lookahead     := Vector2(24, 12)   # px — offset toward the facing direction
@export var smooth_speed  := 8.0               # exponential follow, frame-rate independent
@export var bounds_rect   := Rect2()           # set from the region's TileMap used rect
```

Rules:

1. **Deadzone, not dead-centre.** The player can wander inside a 48×32 px box without the camera
   moving. This kills constant micro-jitter and is a large part of the "calm, professional" feel.
2. **Lookahead** — offset the target ~24 px toward the facing direction so you see where you're going.
   Lerp the offset over ~0.3 s, never snap it.
3. **Exponential smoothing**, frame-rate independent:
   `global_position = global_position.lerp(target, 1.0 - exp(-smooth_speed * delta))`.
   Never write `pos += (target - pos) * 0.1` in `_process` — that changes with frame rate, and it is
   precisely what Covenant's `st.cam.x += (tx - st.cam.x) * Math.min(1, dt * 6.5)` was carefully
   avoiding. Godot makes it easy to reintroduce the bug; don't.
4. **Clamp to map bounds** — `limit_left/right/top/bottom` from the TileMap's used rect. Covenant
   already does this correctly, including the `MAP_W <= view.w` centre-fallback case. Keep it.
5. **Pixel-snap the camera.** With `snap_2d_transforms_to_pixel=true` set project-wide this is mostly
   handled, but also `position_smoothing_enabled = false` on Camera2D and do the smoothing yourself —
   Godot's built-in smoothing fights pixel snapping.
6. **Room transitions** — on entering a new region: fade to black over 0.25 s, swap scene, fade in over
   0.3 s, camera starts *already at* the player (no visible catch-up pan). Covenant's bug report about
   *"跳跃后飞走不再落地"* is a reminder that camera and physics state must be re-initialised together.

---

## 4. Audio — the most underrated half of "feel"

Covenant's world mode has **no footstep audio at all** (`grep 'sfx(' src/world/` → only `battle.js`
and `mode.js`). This is one of the largest single reasons it feels flat, and it costs two hours to fix.

| Sound | Trigger | Notes |
|---|---|---|
| **Footstep** | every 0.32 s while walking, 0.22 s while running | **Alternate L/R** — never the same sample twice in a row. Vary pitch ±4%. |
| Footstep variant | per terrain: grass / dirt / stone / sand / water / wood | Four to six variants per terrain, randomly chosen. |
| Turn | *nothing* | A turn should be silent. Adding a sound here makes it feel busy. |
| Interact prompt | a soft blip when an interactable comes into range | Teaches the player what is interactive without a UI marker. |
| Dialogue advance | short, dry, quiet click | Plays **per character group**, not per character — see below. |
| Dialogue blip | per 2–3 characters of typewriter text, pitched per speaker | Animal Crossing / Undertale style. Each named character gets their own pitch. **Do not** blip per character — it becomes a machine gun. |
| Verse received | a warm, rising, reverberant chime | This is a *theological* sound event. Make it distinct and beautiful. Covenant's `onWord` → `sfx("complete")` is the right instinct with the wrong sample. |
| Quest complete | two-note ascending | |
| Menu | cursor / confirm / cancel | Three sounds, used everywhere, always the same. Consistency *is* polish. |
| Region music | on region enter | Crossfade ~1.0 s, as Covenant already does. |
| Ambience | wind / water / crowd / night insects | Layered *under* music at low volume. Covenant's filtered brown noise with a slowly sweeping cutoff is a genuinely good implementation — port it. |

**Mix bus targets:** music −12 dB, SFX −6 dB, dialogue/UI −3 dB, master 0 dB. Duck music by −6 dB
while a dialogue box is open — this one automation makes the game feel produced.

---

## 5. Animation states

Minimum viable set per character. Your current rig has exactly one (`frame` cycling 0–3 while moving).

| State | Frames | Loop | Transition |
|---|---|---|---|
| `idle_down` / `_left` / `_right` / `_up` | 2 (breathing bob) | yes | from walk, 1 frame blend |
| `walk_down` / `_left` / `_right` / `_up` | 4 | yes | — |
| `run_*` (player only) | 4 | yes | — |
| `turn_*` | 1 held | no | 70 ms |
| `interact` | 2–3 | no | on A press facing an NPC/object |
| `emote_*` (surprise, question, joy) | 2 | no | driven by dialogue tags |

Plus an **emote bubble** above the head — `!`, `?`, `♪`, `…`, `💧`. In a Bible game this carries real
weight: a `?` over an NPC who has something to say, a `✧` when a verse is received. Covenant's
floating text (`floater()` in `field.js`) is the right idea; make it a sprite bubble with a pop tween.

**Godot:** use `AnimatedSprite2D` + a `SpriteFrames` resource, with `left` mirrored from `right`
(`flip_h`) to halve the art. Drive it from a small state machine, not a chain of `if`s.

---

## 6. Juice — the interaction checklist

Every one of these is a 5–30 minute job and together they are what makes a game feel *expensive*.
Covenant already implements several of these well in `engine/scene.js` (click ripples, drag trails,
hit-stop, combo floaters) — **port the ideas, they were good.**

| Moment | Response |
|---|---|
| Pick up a stone | Sprite scales 1.0 → 1.3 → 0 over 0.25 s, rises 12 px, fades. +1 particle sparkle. Soft chime. Floating text *"一块光滑的石子 · 3/5"* — Covenant already does exactly this, keep the string. |
| Talk to an NPC | NPC turns to face you. Dialogue box slides up 8 px + fades in over 0.12 s. Faceset pops in with a 1.15 → 1.0 scale. |
| Receive a verse | Screen flashes warm gold at 8% opacity for 0.1 s. Time slows to 40% for 0.25 s. The verse card enters with a scale-up and a light bloom. **This is your signature reward — spend the most time here.** |
| Complete a quest objective | Tracker item ticks with a bounce, plays a two-note sting, then the row fades to a completed state. |
| Cross the challenge line | Camera pushes in 1.15× over 0.6 s, ambience drops out, a low drone swells. Then BECOME. |
| Wrong answer in the word-battle | 3-frame screen shake (±2 px), red flash at 12%, hit-stop 60 ms, nerve pip drains. Covenant's `battle.js` already has `sh` (shake) and `flash` — the instinct was right. |
| Right answer | Goliath's bluster pip shatters into particles, hit-stop 80 ms, sling loads with a taut-string sound. |
| Enter a region | 0.25 s fade from black. Region name card, serif, fades in and out over 2.5 s. Covenant's chapter subtitle nameplate already does this. |
| Menu open | 0.08 s scale 0.96 → 1.0 + fade. Every menu, identical. |
| Button hover/press | 1 px down + 5% darker. **Every button. No exceptions.** |

**Hit-stop discipline:** freeze the game for 60–90 ms on significant impacts. This is the cheapest
"expensive feel" trick in existence and Covenant's `engine/scene.js` already implements `hitStop`.

**Reduced motion:** honour it. Covenant respects `prefers-reduced-motion` in CSS; in Godot, read
`DisplayServer.is_dark_mode_supported()`-style OS settings or expose your own toggle, and gate every
shake/flash/time-scale behind it. **This is pillar 5 and it is non-negotiable for a game churches will
hand to children and elderly players.**

---

## 7. Touch controls — where most phone ports of this genre fail

You want Switch feel **on a phone**. This is the hardest constraint in the project and it deserves
more attention than the art.

### 7.1 Layout, landscape

```
┌────────────────────────────────────────────────────────────┐
│  ♥ ♥ ♥   ✦ 12   ▸ 以拉谷                        ☰  ♪  中/EN │
│                                                            │
│                                                            │
│                        (world)                             │
│                                                            │
│                                                            │
│      ┌──────┐                                    ┌───┐     │
│      │  ◉   │  floating joystick                 │ A │     │
│      └──────┘                                    └───┘     │
│                                              ┌───┐  ┌───┐   │
│                                              │ B │  │run│   │
│                                              └───┘  └───┘   │
└────────────────────────────────────────────────────────────┘
```

- **Left thumb:** floating virtual joystick. Appears *where you touch*, not at a fixed position — this
  is critical, because a fixed joystick forces the player to look at their thumb. Godot 4.7 ships a
  **`VirtualJoystick`** node; use it, don't write your own.
- **Right thumb:** A (interact/advance), B (cancel/menu), and a **hold-to-run** zone.
- **Deadzone 12 px**, as Covenant's `STEER_DEAD = 12` already had — that value was correct.
- **Analog magnitude → speed.** Covenant did this well: `push = Math.min(1, m / 44)`. Preserve it —
  a gentle tilt walks, a full tilt runs. This makes the *run button optional* rather than mandatory.
- **Safe areas.** `DisplayServer.get_display_safe_area()` on all four sides. Covenant's v0.4.1 bug —
  *"完成面板被挤到屏幕外"* — was exactly a safe-area failure and cost a release. Don't repeat it.
- **One-handed portrait fallback.** If orientation is portrait, move the joystick to bottom-left,
  A/B to bottom-right, and widen the deadzone to 16 px. Do not just letterbox a landscape layout.

### 7.2 The tap-to-walk question

Covenant's world mode used **drag-to-steer or tap-the-ground-to-walk**, with a comment explaining the
choice: *"no on-screen d-pad taking up half the phone."*

**Verdict: keep tap-to-walk as an accessibility option, but make the joystick primary.** Tap-to-walk
needs pathfinding to feel right (otherwise the player taps behind a rock and the character sticks),
and it fights with "walk at the thing to interact." A joystick is direct, immediate, and — importantly
— it is what makes the game feel like a *console* game on a phone, which is your stated goal.

Covenant's `npcUnder()` — *a thumb on a face is a request to talk, however far away they are* — is a
genuinely good touch affordance. **Keep it.** Tap an NPC across the screen and your character
pathfinds to them and talks. That requires `AStarGrid2D`, which Godot gives you free and which
Covenant's `reachable()` BFS only ever used in tests.

### 7.3 Gamepad and keyboard

Support both from day one; they cost almost nothing once input is routed through an InputMap rather
than read directly. `ui_accept` = A, `ui_cancel` = B, `move_*` = dpad/stick/WASD. Godot's InputMap
handles this — **never call `Input.is_key_pressed(KEY_W)` in gameplay code.** This is also what makes
a future Steam/Switch port possible without touching the controller.

---

## 8. The Phase 0 feel-test acceptance criteria

Print this. Tick it on a real phone, not in the editor.

- ☐ Walking feels *good* with no objective — you'd walk for two minutes just to walk
- ☐ Turning around a corner never feels like sliding
- ☐ No input ever feels dropped, including rapid direction changes
- ☐ One-tile doorways are reliably passable at walk speed without aiming
- ☐ Camera never shows out-of-bounds, never jitters, never lags visibly
- ☐ Footsteps are audible, alternate, and change with terrain
- ☐ Dialogue blips are pleasant at 20 consecutive lines, not fatiguing
- ☐ Joystick works one-handed and does not require looking at your thumb
- ☐ Nothing important is under the phone's rounded corners, notch, or gesture bar
- ☐ 16 px is legible at arm's length on a 6.1" screen — if not, raise base viewport to 288×162
- ☐ **Chinese text in the dialogue box is comfortable to read** (see `ART.md` §6)
- ☐ Sustained 60 fps for 5 minutes of walking, phone not visibly hot
- ☐ Turning reduced-motion on removes shake and flash without breaking anything

**If any box is unticked, do not start Phase 1.** Every one of these is cheap now and expensive later.
