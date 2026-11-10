# ART DIRECTION — the David chapter (updated 2026-11-06)

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

`tests/visual.gd` captures **fourteen** real engine frames at CI under Xvfb +
llvmpipe. The six older states (boot, valley, dialogue, journal, Bethlehem,
flock) sit beside six living-world states (a sheep that has noticed the player,
a quest counter updating, a 2× nearest review of Chinese dialogue, a 4:3
window, a real `ScreenFade` caught mid-cut, and the book scrolled to its
optional "How you came here" pages) **and two climax states**: the Goliath
duel and the valley after the fall. The harness also asserts cold-boot
control latency, that the 4:3 framebuffer really is taller than 180 px, and
that the duel's figures are the drawn sheets rather than scaled map sprites.

Frames are decoded with `tools/decode_frames.py`, **looked at**, and only then
promoted to `tests/frames/baseline_*.png`. The coarse grid diff is a
*wrong-scene* detector, never evidence that art is good; a near-zero diff does
not mean the mood, hierarchy or legibility improved. A change to this document
without a matching frame review is not a visual change. What CI still cannot
judge for us: how the Chinese reads at 10 px on a phone, whether the horn and
bleat sound right, and how the stick feels under a thumb.


## 7. Premium-art extension (2026-11-06)

The shortlist review in `assets/LICENSES.md` inspected the actual PNGs of six
candidate sources (`docs/ART-COMPARISON.png`). All four external packs were
rejected: cool blue/silver high-fantasy UI, flat un-outlined 16 px characters,
and bright cyan/yellow terrain fight the warm outlined palette that already
holds this game together. Three of them also carry mixed or platform-restricted
terms. **The chosen direction is original, project-specific art**, generated
from the same `palette.py` ramps, so coherence improves instead of being
replaced by a second style.

| Rule | Applied in |
|---|---|
| A dialogue portrait is a **separate drawing**, never the 16×16 walking sprite scaled up. 32×32, head at ~30% height, warm sepia ground, one outline pass, resting expression per character, nine-mood vocabulary. | `tools/artgen/faces.py`, `art/facesets/*.png`, `DialogueBox.FACES` |
| Major characters differ in **silhouette**, not only robe colour: mantle, satchel, sling, staff, spear, crown, helm crest, beard, veil. | `tools/artgen/chars.py`, `art/characters/*_idle.png` |
| A setpiece owns its own art scale. Goliath 64×64, David 32×32 — a real 2:1 contrast, no 8× upscale. Foreheads sit at ~30% of the figure height because the aim band is drawn there. | `tools/artgen/duel.py`, `art/duel/*.png`, `GoliathFight` |
| The valley of the duel is directed, not a grey card: warm sky bands, two ridgelines, spear silhouettes of both armies (1 Sam 17:1-3), pebbled ground, per-figure contact shadows, and a body-fall rotation. Restrained — no glowing magic, no particles. | `scripts/setpiece/GoliathFight.gd` |
| Every new art file is palette-locked, deterministic and statically `preload`ed, so the web export cannot silently lose it. | `tools/check_faces.py`, CI static gate |
| A story result must change the world: once `goliath_down` is set, the standing figure leaves the ridge. | `Region.set_giant_down()`, `14_aftermath` frame |

No external pack was vendored in this pass. The existing Ninja Adventure CC0
tiles stay where they are; see `assets/LICENSES.md` for the exact licence
evidence and the attribution wording for a future credits screen.

---

## 8. Art direction reset (2026-11-05) — comparison first

This file remains the **contract for the shipped classic art**. A new milestone
started a separate investigation: **`docs/ART-RESET.md`**. It contains a real
diagnosis of all eight major scenes, three original art-direction prototypes,
a four-way comparison at native / desktop / mobile sizes with grayscale review,
measured colour and value metrics, and a selection.

**Selected: Direction C — Biblical Storybook RPG**, with B's value hierarchy and
A's silhouette clarity borrowed as mandatory corrections. One reversible,
opt-in prototype was integrated into the shepherd-field scene
(`art/tiles/terrain_storybook.png`, `Main.apply_art_theme()`); the default atlas
and every baseline were left in place. The report explicitly does **not** claim
the overhaul is complete: the measured world value spread fell 20.1 → 10.6,
which proves a better palette is not a substitute for hand-authored sprites,
tile shapes and layered lighting. The manual art work required is listed in
`docs/ART-RESET.md` §6 and queued in `docs/DEVELOPMENT_BACKLOG.md` #19–23.

Nothing here is superseded or deleted. When the hand-authored assets exist, this
contract will be extended rather than rewritten.

### §8 update — craft pass (2026-11-10)

The report's own negative result has been acted on, in **one reversible scene
only**. See `docs/ART-RESET.md` §12 for the full evidence. Summary:

* 13 hand-authored opt-in props (`art/props_storybook/`) and 4 hand-authored
  16px character sheets (`art/characters_storybook/`) replace geometric circles
  and peg figures with ink-outlined, multi-plane silhouettes. Classic assets are
  untouched and are the default.
* `scripts/world/ContactShadowLayer.gd` gives props, animals, NPCs and the
  player one shared ground shade; `TerrainLayer._draw_depth()` adds far/middle/
  near value planes with a graded warm band and irregular hill edges.
* Four successive real CI frames measured world value spread
  **8.0 → 12.3 → 17.1 → 17.7** (palette-only was 10.6; classic 20.1, inflated
  by its HUD scrim). CI `42784090190` is green: 16 frames, `deep 143`,
  browser 30/0, deploy skipped.
* `tools/check_craft_props.py` is a stdlib lint gate; `measure_real_engine.py`
  is the reproducible measurement.

This file remains the **contract for the shipped classic art**. The overhaul is
still NOT complete: one opt-in scene, two actors, no new maps for Bethlehem /
court / valley, journal and menus untouched, no parallax or per-location light,
and no professional-grade manual pixel editing. Backlog #19–23 still stands,
with #19/#20 now partially done for one scene only.

### §9 update — user-selected Direction B (2026-11-10)

The user reviewed the three original concept sources and explicitly chose
Direction B's golden-hour outcome: *"i want the outcome like B, with the
neccessary animation like current"*. This **supersedes the assistant's C
selection** recorded earlier in this file; C is retained as a reversible opt-in
theme and as a comparison baseline, not deleted.

Direction B is implemented for the **same one opt-in scene only**
(`docs/ART-RESET.md` §12.7). It keeps the shipped 16px grid, the 49 atlas
indices, every walk/idle/sway/water/prop animation frame and every timer. B adds
a warm 49-cell terrain atlas, 13 props, 4 character sheets, a dusk-slate/gold
UI skin, camera-relative golden-hour ground light, long cast shadows and an
animated upper-left rim light on moving figures. Real CI `42798442187` is green
on all game jobs; final all-green `42803804441` also carries the browser-harness
jitter fix: 16 frames, `deep 143`, browser 30/0, deploy skipped at that time.
The reviewed frame 16 was promoted as `baseline_16_shepherd_cinematic.png`.
A working-branch live preview was later explicitly authorised — §10.

This file remains the **contract for the shipped classic art**. The default
atlas, gameplay, state, collision, input, quests, save format, every other
scene, every other baseline and PR/merge status are unchanged. The user later
authorised a working-branch live preview (§10); this is not a release. The visual overhaul is still NOT complete: the painterly B concept
is not a shippable pixel asset, the real frame is not on par with it, and the
remaining manual environments, UI skins, parallax, human art-director review,
device/audio/Chinese/playtest gates are listed in `docs/DEVELOPMENT_BACKLOG.md`
#19–23. No release claim is made.

### §10 update — live branch preview authorised (2026-11-10)

The user explicitly asked to *"serve this branch to live for me to feel. then
make in on par"*. That authorises a **working-branch preview deployment**, not
a merge to `main`, a default-asset replacement, or a release. Because the
sandbox token cannot create a `workflow_dispatch` event, the named branch's
push-deploy condition (used successfully for the earlier `dceac57` / `5d1c5ff`
preview) is restored. `build_type` remains `workflow`; the `github-pages`
environment already allows this branch. The live URL is
https://fongway94.github.io/WalkInCovenant/ and every subsequent push to
`arena/46955931-walkincovenant` updates it. The next `main` push republishes
`main`.

The "on par" instruction is being pursued as richer original pixel art within
the existing 16px / animation constraints, not by dropping the painterly
concept into the engine. Exact parity with a 681×348 illustration containing
135,490 colours, no UI and no tile grid is not a shippable game frame. This
file remains the contract for the shipped classic art; no release claim is
made.
