# ART DIRECTION — the David chapter (living-world milestone, 2026-11-05)

One page, so every pixel change in this milestone is answerable to the same
rules. Sources of truth: `tools/artgen/palette.py` (colours),
`tools/artgen/canvas.py` (1 px silhouettes), `project.godot` (viewport),
`scripts/ui/Hud.gd` (UI hierarchy), `scripts/world/Region.gd` (light + markers).
This document is a **contract**, not a mood board: each rule below is applied to
a shipped change in this milestone, named in the last column.

## 1. Scale and frame

| Rule | Applied in |
|---|---|
| 16 px tiles; base viewport 320×180 (`20 × 11.25` tiles), `canvas_items` stretch with `expand` so 4:3 hardware sees ~320×240 rather than a letterboxed lie. | `tests/visual.gd` `10_layout_4x3` (the harness asserts the framebuffer really is taller than 180 px) |
| Props are 8–16 px tall, characters 32 px. A sheep is 14×12 — roughly a third of a person, never a dot that reads as a rock. | `sheep*.png`, `trough.png`, `staff.png` |
| Every sprite carries a 1 px dark outline and a contact shadow. Nothing floats. | all new `art/props/*` |
| No pure black, no pure white. Deepest shadow is `#14202a` family, highest light is `linen[5]` / `gold[5]`. | `palette.py` ramps |

## 2. Colour and light tell the time of day

- **Valley (witness act):** `morning` — `Color(1.0, 0.98, 0.92)`. Army dust, pale
  sky, readable UI.
- **Bethlehem:** `morning`. Same chapter of the day, a different street; the
  place is not a dream sequence.
- **Shepherd slope (David act):** `dusk` — `Color(0.80, 0.62, 0.55)`. The
  objective literally says *before dark*; warm low light makes the deadline
  visible without a timer or a countdown. Restored to `morning` when the errand
  begins, so the two acts are visually distinct.
- Transitions go through black (`ScreenFade`), never a cross-dissolve between
  two maps. | `Main._start_david_act()`, `Main._start_errand()`,
  `Region.set_time_of_day()`.

## 3. Movement is small and continuous

- Idle animation is **two frames** (graze / head up), ~1.1 s, with a ≤1 px
  vertical bob. A sheep eating is the difference between a herd and three icons.
- Ambient prop sway (wheat, thorn bush, wool on the thorn) is ≤1 px at
  0.6–1.0 Hz, phase-offset per instance so a row of wheat does not pulse as one
  object. Nothing animates while a dialogue box owns the screen.
- A startled animal moves **≤ 12 px** and stays on its tile. The world reacts;
  the objective never becomes a chase.
- Direction is `flip_h`, never a second art asset. | `scripts/world/FlockSheep.gd`,
  `Region._spawn_props()` ambient list.

## 4. Visual hierarchy (in order of importance)

1. The objective line, top-left, 10 px, `gold[4]` on a shadow. One sentence, one
   number (`n/3`) — the player must never wonder what to do.
2. The thing the objective points at: a marker above the sprite plus a faint
   ring on the ground. **Gold** for a quest item; **pale wool** for livestock, so
   the fold reads as an animal job, not a fetch list.
3. Dialogue box with a nameplate and portrait; the box pauses the world, so it
   must be the brightest thing on screen and must fit 5 rows of Chinese.
4. Toasts below the objective; they never cover it (BUG-020).
5. Waypoint arrow top-right, one button bottom-right.

## 5. What is deliberately *not* drawn

- No quest markers on optional discoveries. The broken hurdle, the trough and
  the ridge view are found by walking, and give one quiet line each.
- No filler props to make a map look busy. The slope gets a trough, a leaning
  staff and a second fold rail because each says something about David's work.
- No fantasy silhouettes, no European roofs, no glowing loot, no damage numbers.
  Flat mud-brick, goat-hair tents, olive/fig, stone water vessels, wool, wood.
- No invented Chinese idioms or devotional captions in the art layer.

## 6. Review gate

`tests/visual.gd` captures eleven real engine frames at CI under Xvfb +
llvmpipe. The six older states (boot, valley, dialogue, journal, Bethlehem,
flock) now sit beside five new ones: a sheep that has noticed the player, a
quest counter updating, a 2× nearest review of Chinese dialogue, a 4:3 window,
and a real `ScreenFade` caught mid-cut. The harness also asserts cold-boot
control latency and that the 4:3 framebuffer really is taller than 180 px.

Frames are decoded with `tools/decode_frames.py`, **looked at**, and only then
promoted to `tests/frames/baseline_*.png`. The coarse grid diff is a
*wrong-scene* detector, never evidence that art is good; a near-zero diff does
not mean the mood, hierarchy or legibility improved. A change to this document
without a matching frame review is not a visual change. What CI still cannot
judge for us: how the Chinese reads at 10 px on a phone, whether the horn and
bleat sound right, and how the stick feels under a thumb.
