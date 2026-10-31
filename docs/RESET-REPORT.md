# Development reset — phase reports

Companion to `docs/AUDIT.md` (the Phase 1 findings). This file is the report the
brief asks for at the end of each phase: what was wrong, what changed, which
files, what was tested, what is still open.

Read the **Evidence** column honestly. This sandbox has no Godot binary and no
browser, so:

- **CI** = the real engine, headless: `tests/run_all.gd` (content + layout) and
  `tests/smoke.gd` (a full playthrough of David & Goliath) on GitHub Actions.
- **READ** = proven by reading the code; not executed.
- **DEVICE** = needs a human on a phone. Not claimed.

Latest green run: **41168702816** — lint → export → deploy all succeeded.
Live: <https://fongway94.github.io/WalkInCovenant/>

---

## Mission architecture pass — the spine, the armour, and the stones

### MissionRunner

`Main.gd` was the chapter: order, objectives, rewards and mechanics in one file.
The **order, objectives and rewards are now data** (`missions` in the region
file) and the lifecycle lives in `scripts/systems/MissionRunner.gd`; `Main` keeps
only the mechanics a story needs, hooked in by the mission's `enter` name.

Two decisions worth flagging, because they went wrong first:

- **Two condition kinds, not a language.** `flag` and `count`. Everything else is
  an interaction, and interactions belong in the mission's own code.
- **Transitions are event-driven, not polled.** With polling, `elah_ended` and
  the runner's next frame could disagree, and the chapter walked *back* a beat
  after the ending. `Main._story_flag()` sets the flag and ticks the runner in
  the same breath. That bug was found by the smoke test, not by reading.

Rewards are granted behind a save flag (`mission:<id>:rewarded`), and the test
completes the same mission twice to prove nothing pays twice.

### Saul's armour (1 Samuel 17:38-39)

The armour was a paragraph. It is now a scene: the world comes back wearing it —
speed at 42%, a stagger drawn into the walk, bronze helmet and coat of mail drawn
over David — and it ends when the player has genuinely tried to walk (0.9 s of
intent, so pushing into a tent pole counts), or immediately on A. 17:39 is
spoken at the moment of taking it off.

Bugs found and fixed while testing this: the scene re-fired as soon as its box
closed (the player got 17:39 in a loop), and it measured distance covered rather
than intent, so a player walking into a wall never finished it.

### Five stones by hand (1 Samuel 17:40)

`scripts/setpiece/StoneChoice.gd`: nine stones in the shallow water, tap to take,
tap again to put back, five wanted, a `KEEP THEM` button once the fifth is in the
bag, a sixth stone refused. 17:40 is spoken *after* the choice, because the verse
reports what he did. The bag fills at the bottom of the screen, in the same pixel
world as the brook, so it reads as picking stones and not as a menu.

**Files.** `scripts/systems/MissionRunner.gd` (new), `scripts/setpiece/StoneChoice.gd`
(new), `scripts/main/Main.gd`, `scripts/world/Player.gd` (armour), 
`scripts/systems/RegionModel.gd` (`missions`), `data/regions/elah.json`
(missions, armour block, brook block), `tests/run_all.gd` (mission gate),
`tests/smoke.gd` (§6c2 armour, §6c3 stones, §9b resume, rewards-once).

**Tested (CI).** The whole chapter again, including: armour on → speed 0.42 →
walk → 17:39 → armour off → speed 1.0; the brook opening only when reached;
taking and putting back a stone; three, then five, then a refused sixth;
confirming; exactly five in the pouch; the mission gate reopening the line; and
a save that resumes into the right mission. **Not tested:** the feel of the
armour's weight or the picking hand on a real phone.

---

## Master directive pass — structure, story order, save, and one shot

Four changes, each with a reason you would notice as a player, all proven by the
same headless playthrough that already covers the chapter.

### 1. The stones are David's again

1 Samuel 17 is not a list of tasks in any order. It is: the camp is afraid for
forty days (v.11), David arrives with bread (17-20), his brother is scornful
(28), Saul dresses him in armour he cannot walk in (38-39), he goes down to the
brook and picks five stones (40), and only then does he stand at the line.

The old build had the **witness** collect the five stones in Act I and cross the
line carrying them, which meant the verse the whole chapter turns on happened to
somebody who was not yet David. Now:

- Act I ends at the line, and crossing it does nothing to the witness but show
  him 17:11 and Corin telling him the story is changing hands.
- The brook lays out the five stones **when 17:40 is spoken**, after Saul.
- The pouch counter does not exist before that, and the valley opens with
  nothing to collect at all.

### 2. Goliath is on the ridge

He was a pair of coordinates and a name in other people's dialogue. Nobody drew
him, so forty days of a man shouting across a valley had nobody in them. He is
now a sprite two tiles tall on the north slope, and walking up the ridge plays
the chapter's one scripted camera shot: pan to him, 17:10, pan back. The pan is
`CameraRig.pan_to` / `resume_follow`, so any later campaign can frame a scene.

### 3. The chapter survives the tab closing

`GameState.save_game()` existed and **nothing ever called it**: a phone that
switched apps, or a browser tab that closed, lost the whole chapter. It is now
written on every act change, every three seconds of free walking, and on the
browser's pause/close notifications — and boot reads it back: the act, the
counters, the tile. A save that says "ready" boots into "ready".

### 4. Fairness on the first spear

Round one's telegraph is 0.9 s longer than every later one and states the rule
("when the red tip comes, step aside") instead of "he is winding up". The duel
is entered on a cut rather than a pop, and the giant stays on screen while 17:47
is spoken over him.

**Files.** `data/regions/elah.json` (act order, brook block, firstsight trigger,
objectives), `scripts/main/Main.gd` (Act.STONES, `_witness_at_the_line`,
`_brook_beat`, `_first_sight`, autosave/resume), `scripts/world/Region.gd`
(Goliath sprite, pan helpers), `scripts/world/CameraRig.gd` (scripted shots),
`scripts/autoload/GameState.gd` (save on pause/close), `tests/run_all.gd`,
`tests/smoke.gd`.

**Tested.** CI: the whole chapter, start to finish, in one run — including the
first-look shot (camera holds him, then hands back), the witness refusal, the
handover beat, the brook spawning five stones and the fifth one sending you to
the line, and a save that resumes into David's act. **Not tested:** how any of
it feels, or reads on a phone.

---

## Pass after playtest 10 — the two reported bugs, and the duel's framing

Your message reported two things. Both had a single root cause each, and both
are fixed in code and played by the smoke test.

### 1. "The objective says follow Corin, but the NPC follows me"

**Root cause.** `Npc._do_follow()` had one branch: "walk to `lead_target`; if you
are there, nothing left to do" — and then execution fell through to the
player-follow branch that every escort in the game uses. So Corin led you
correctly *until he arrived*, at which point he turned round and walked behind
you while the HUD still said follow him.

**Fix.** Arrival is now an explicit state, not the absence of one:
`is_leading()` / `is_waiting_ahead()`. A guide with a valid `lead_target` either
walks to it or **stands there and faces you**, with a small chevron drawn over
his head so the person who is waiting is visibly waiting. The HUD arrow points
at him while he leads and at the next person once he waits.

**Files.** `scripts/world/Npc.gd`, `scripts/main/Main.gd` (arrow target).
**Tested.** smoke §2e drives both branches, and §3 (after the guide has actually
spoken) asserts the game gave him a `lead_target` at all. **CI.**

### 2. "David vs Goliath must be a real fight — throw stones and avoid his attacks"

The word-battle is gone. `scripts/setpiece/WordBattle.gd` is deleted, `shouts`
is gone from the data and from `RegionModel`. What replaced it is a duel loop:
he telegraphs, sweeps a spear, you step aside, a marker sweeps his forehead and
you let go. Three stones end it; five in the pouch; being hit costs nerve, never
the story. 17:44–45 open it, 17:47 closes it.

Since then this pass, three fairness/framing fixes, all in the same scene:

- **The first spear is slow and says what it is.** Round one's telegraph is
  0.9 s longer than every later one, and its line is the rule ("when the red tip
  comes, step aside"), not "he is winding up". A player meeting the fight for the
  first time cannot lose the first exchange to the clock.
- **Entered on a cut, not a pop.** The last verse closes, the screen goes dark
  for a heartbeat, and the light comes back on the ground the duel is fought on —
  the same grammar the chapter already uses for the shepherd's slope and the
  errand. (`Main._open_fight` → `ScreenFade`.)
- **He falls, and stays on screen.** The giant used to vanish the instant the
  third stone landed and 17:47 was spoken over an empty valley. `finished` now
  fires after a one-second fall, the duel's layer sits *under* the dialogue box
  (14 vs 20), and the chapter's last verses are spoken over him.

**Tested.** smoke §6d/§7: the cut is entered and the fight appears; strikes and
throws alternate at real speed; a dodge costs no nerve; the DONE phase is
reached; the fight's layer is under the dialogue layer; and 17:47 is open while
the duel is still on screen. **CI.** What is *not* tested: how the fall and the
cut feel in the hand — that needs a device.

---

## Phase 1 — Audit ✅

Delivered as `docs/AUDIT.md`. Three root causes, each with the code that proves
it:

1. **No layout authority.** Six subsystems derived screen geometry from their own
   constants; nothing reacted to a viewport change.
2. **Tap arbitration was distributed.** Three nodes read the input stream, a
   phone tap arrives as two events, and the A button adds a third — so one tap
   meant up to three advances.
3. **The chapter is a fetch chain, and the two perspectives never interleave.**
   This is a design problem, not a bug, and it is Phase 6–7 work.

---

## Phase 2 — Screen and display ✅ (logic), ⚠ (pixels need a device)

### What was wrong
- `BecomeController` drew two fixed 16-unit black bars on a 180-unit canvas —
  **18% of the picture** — to open the BECOME transition, with no framing, no
  resize handling, and no guarantee of retracting. On a phone this reads exactly
  as "the game shrank and black borders appeared".
- Every layout constant was right at 320×180 only. `tools/check_text_fit.py`
  modelled the dialogue as 265 px wide; the real column is 264 px at the design
  size and different at any other size.
- The toast started at y=18 — **on top of the objective line**, which lives at
  y=15–35. Every toast printed over the current task.
- No node listened to `size_changed`, so rotation, browser chrome, and fullscreen
  left stale geometry.

### What changed
| File | Change |
|---|---|
| `scripts/systems/ScreenFit.gd` | **new** — one source of truth: safe area, thumb strip, camera half/clamp, dialogue band + text column + height cap, letterbox height. Pure maths, testable without a window. |
| `scripts/story/DialogueBox.gd` | lays itself out from `ScreenFit`; re-lays out on `size_changed` and re-paginates. |
| `scripts/ui/Hud.gd` | every offset computed in `_apply_layout()`; toast moved to its own band under the objective; `size_changed` connected. |
| `scripts/world/CameraRig.gd` | clamp via `ScreenFit.clamp_camera`; re-centres on resize. |
| `scripts/systems/BecomeController.gd` | bars are **7.5% of the screen**, each with a gold hairline; retraction on every exit path, a `MAX_HOLD` watchdog, and re-layout on resize. |
| `scripts/ui/ScreenFade.gd` | refuses to stack two transitions; clears itself if it is ever black for more than 3 s. |
| `scripts/ui/PlaceCard.gd` | re-lays out on resize, sits clear of the thumb strip. |
| `tools/check_export.py` | new `SCREEN` rule: stretch mode/aspect/scale-mode, viewport size, landscape lock, canvas resize policy and PWA orientation must agree — each is legal alone, which is how they drift. |
| `tools/check_text_fit.py` | width now matches the real text column (258 px with slack), not a guess. |
| `tests/run_all.gd` | `_check_layout()`: 14 screen shapes from 320×180 to 2400×1080, asserting the dialogue stays on screen and under half the height, the text column stays readable, the letterbox stays under 11%, and the camera clamp never shows outside the region. |

**Deliberately not changed:** `project.godot`'s stretch chain
(`canvas_items` + `expand` + `fractional`). It is already the correct combination
for "no bars, no distortion, any landscape aspect", and swapping it is what
caused playtest 8's shrink bug. It is now *enforced* by `check_export.py`
instead of trusted.

### Tested
CI: layout matrix, export-config rules, full playthrough. READ: nothing here
needs a device to be *correct*, but whether it *looks* right does.

### Still open
- **Pixels need your eyes.** I cannot render a frame in this sandbox. The layout
  maths is asserted; the final look is not.
- `CameraRig` still snaps its position to whole world pixels while the canvas is
  fractionally scaled. With NEAREST filtering that is the lesser evil (the
  alternative shimmers), and it is left as-is by decision, not by oversight.

---

## Phase 3 — NPC interaction ✅

### What was wrong
- One physical tap reached `TouchControls`, `DialogueBox` and `Region` as
  separate events (touch + emulated mouse + synthetic action), and each acted on
  its own copy. That is the "same dialogue three times" report.
- `DialogueBox` advanced on **any** key, movement keys included.
- `Npc.talk()` had no per-NPC state, so two events in one frame both passed the
  guard, and the second open replayed the first-time lines (because `_talked` is
  only set when the box closes).
- The A button was drawn *under* the dialogue panel — invisible but still live.
- `Region._check_exits` polled `Input.is_action_just_pressed()` inside `_process`:
  a second input path.
- The touch layer consumed the whole left half of the screen, including the HUD's
  own Buttons.

### What changed
| File | Change |
|---|---|
| `scripts/systems/TapGate.gd` | **new** — one gesture, one `true`. Every consumer asks; exactly one is granted, and the touch/emulated-mouse twin is dropped by the same 180 ms window. |
| `scripts/story/DialogueBox.gd` | presses go through `TapGate`; only interact/accept/space/enter advance; Escape skips; number keys pick a choice; taps that land on the skip or an answer button are left to the button; a press over a control no longer advances underneath it. |
| `scripts/world/Npc.gd` | `Talk { READY, SPEAKING, COOLDOWN }` with `can_talk()` (pure, callable every frame) and a **wall-clock** cooldown — the first version ticked in `_physics_process`, which is switched off exactly when a conversation ends. |
| `scripts/ui/TouchControls.gd` | `blocked` while anything owns the screen (releases the stick, stops synthesising); circular hit areas matching the drawn buttons; claims only the stick half **below the HUD band**; consumes what it claims. |
| `scripts/world/Region.gd` | one input path: an `interact` press means "leave, if standing on an exit, else talk to the nearest available person"; exits no longer polled. |
| `scripts/main/Main.gd` | `_update_touch_ownership()` — one derived truth per frame, so a code path that forgets to restore control cannot leave the stick dead. |

### Tested
CI, smoke §10: talking opens **exactly one** box; a second call in the same
breath opens none; the NPC is `SPEAKING`; one gesture (touch **and** its
emulated mouse click) moves **exactly one step**; the next gesture moves exactly
one more; the controls stand down and come back; the NPC enters COOLDOWN and
returns to READY. Plus §2b: a tap on ≡ belongs to the HUD, a tap in the stick
half belongs to the stick.

### Still open
- No automated multi-touch test (two thumbs at once). `blocked` makes it
  structurally hard to hit, but it is not asserted.
- iOS Safari cannot be tested here at all.

---

## Phase 4 — Dialogue presentation ✅ (built), ⚠ (needs a phone eye)

### What was wrong
A full-width, 93%-opaque sheet with no height cap that grew upward over the
game; a 16×16 sprite stretched into a 30×38 slot; a bare `▼` only after the
typewriter finished; a `»»` button in the same corner; choices in the engine's
default theme; and overflow handled by a *lint* rather than by the box.

### What changed (all in `scripts/story/DialogueBox.gd`)
- **80% opacity, inset from the edges, capped at 44% of the height.** The scene
  stays readable behind a conversation — the point of a conversation here is that
  you are looking at the world while it happens.
- **Framed portrait** (border + dark backing) at 30×30 with aspect kept.
- **Gold hairline under the speaker's name**, so the speaker and the speech are
  not one paragraph.
- **Page counter** (`2/3`) when a line needs more than one page.
- **Continue cue that breathes** (a slow alpha bob), not a static triangle.
- **Styled choices** — dark, gold-edge, 24 px tall, matching the panel.
- **Pagination**: the box measures every character with the real font and splits
  the line into pages that fit. Overflow is now structurally impossible; the
  lint remains only as an authoring guide.
- **Skip is smaller and out of the cue's corner.**

### Tested
CI: the whole game is played through the paginated advance path; `check_text_fit`
is clean at 4 rows. The paginator is exercised on every line of a full
playthrough.

### Still open
- **Visual polish has to be judged by eye.** The geometry and behaviour are
  asserted; the taste is not.
- No per-mood portraits (each speaker has one face), no backlog/history screen.

---

## Phase 5 — Chinese ✅

### What was wrong
The data was clean — no Chinese in English fields, every glyph in the font,
every line inside the box. The problem was **register**: all four NPCs spoke in
the same staccato rhythm, several lines were written Chinese rather than spoken
Chinese, and modern written connectives leaked into 1020 BC speech. Your example
— 「几块石头垒成一座坛，上面没有火。没人有这个心气。」 — describes an object
from a narrator's distance instead of being what a person standing there would
say.

### What changed
Every spoken and narrative line in `data/regions/elah.json` was rewritten with a
voice for each speaker:

| Speaker | Voice |
|---|---|
| Corin (scribe) | measured, chooses each word, kind; `我们是见证人，不是主角` |
| The boy | plain, concrete, frightened; `我娘`, `比我胳膊还粗` |
| The woman | hands busy, no time for pretty sentences; `只求他别把命丢在上头` |
| The elder | dry, slow, has been appraised all his life; `都是这样被人上上下下看的` |
| Narration | short declaratives, no commentary |
| Curios | places, not a tour guide: the altar is **cold**, and nobody has offered there in a long while |

Also rewritten: the prologue, the briefing, the three days in Bethlehem, the
shepherd slope, Jesse's errand, Eliab's beat, Saul's tent, the ending and its
three answers, and every objective line.

**Two real content bugs surfaced while rewriting** — both now fixed:
- the boy's Deuteronomy 20:3 quotation was **duplicated across three boxes**,
  with a stray closing bracket;
- Saul's **1 Samuel 17:39** verse had gone missing in an earlier edit.

### Scripture
Untouched. Every quotation is 和合本 + KJV at the same scope, and the verse lines
were carried over byte-identical (verified by diffing the four `words[]` cards
and every `17:x` reference against the previous commit).

### Tested
CI: font rebuilt (702 glyphs, 116 KB) and `check_font` clean (703 codepoints);
`check_text_fit` clean at 4 rows; `run_all` bilingual checks on every new line.

### Still open
- The valley has ~70 spoken lines. Voice differentiation is only as visible as
  how much each person says — that improves when Phase 6 gives people more to do.

---

## Phase 6–7 — Gameplay and mission design ❌ not started (by instruction)

The brief is explicit: *"Do not add new campaigns or major features during this
repair phase. First make the existing game stable, polished and consistent."*
Phases 2–5 are that repair. This is the next build, and it is a **design** job,
not a patch — doing it in the same pass as the pipeline stabilisation is how a
game ends up as ten half-missions.

What is wrong, in one line each:
- Witness mode is talk → collect → cross. Four good conversations holding up a
  fetch chain.
- BECOME fires **once**, near the end. The two perspectives never interleave.
- The David act is talk-and-collect: no choosing of stones, no armour as an
  input, no weight you can feel.
- No mission has a briefing, a completion condition separate from a trigger, or
  a reward distinct from a toast.

The plan for the next pass (not built):
1. A `missions` block in campaign data: `{id, mode, brief, objective, mechanic,
   complete, reward, transition}` — so a mission is content, not code.
2. One authored mission per chapter, each with a mechanic that *is* the story:
   - Ch. 3 camp: carry Jesse's load and be turned back at the line (an escort
     that says no).
   - Ch. 4 Saul: the armour as a playable refusal — walk in it, and the walk is
     slow and clumsy until you take it off.
   - Ch. 5 stones: choose five from the brook by hand, with the text of 17:40
     attached to the choice.
3. A **return** to Witness mode mid-chapter (after the win, before the ending),
   so BECOME is a loop rather than a one-way door.

---

## Phase 8 — Campaign architecture ⚠ partially ready

Ready: `data/campaigns.json` + `CampaignModel` (region is a data choice), voice
and UI systems are generic, `Region.spawn_npc` / `spawn_pickup` let a campaign
add people and items at runtime, `Npc` state and dialogue come from data.

Not ready: **`Main.gd` is still 700 lines of *this* chapter's story.** Adding
Moses would mean editing it. The refactor — a `MissionRunner` driven by a
`missions` list, with `Main` reduced to boot/wiring — is deliberately scheduled
*after* Phases 2–5, because it must be done against stable, tested systems and
not during the repair.

---

## Phase 9 — Acceptance matrix

| Area | Check | Evidence |
|---|---|---|
| Display | Landscape, consistent scaling, no stretch | `check_export.py` SCREEN rule — **CI** |
| Display | Dialogue/HUD stay on screen at 14 shapes | `run_all._check_layout` — **CI** |
| Display | Letterbox never more than 11% of the picture | `run_all._check_layout` — **CI** |
| Display | Camera never shows outside the region | `run_all._check_layout` — **CI** |
| Display | No stuck black frame | `ScreenFade` watchdog — **READ** + full playthrough **CI** |
| Display | Actually looks right on a phone | **DEVICE — not claimed** |
| Interaction | One NPC interaction = one dialogue | smoke §10 — **CI** |
| Interaction | Dialogue does not duplicate | smoke §10 — **CI** |
| Interaction | Advances once per input | smoke §10 — **CI** |
| Interaction | Control returns after dialogue | smoke §10 — **CI** |
| Interaction | Quest progression single-fired | smoke §6/§7 — **CI** |
| Gameplay | Objectives always stated | smoke §2b — **CI** |
| Gameplay | Quest items visible and collectable | smoke §4 — **CI** |
| Gameplay | Witness → David switch loads correct state | smoke §6/§7 — **CI** |
| Gameplay | Two *interleaved* perspectives, mission design | **NOT BUILT — Phase 6/7** |
| Language | Reads naturally, no machine translation | rewritten by hand; **your judgement needed** |
| Language | Verses unchanged | diffed — **CI** (content) |
| Mobile | Touch controls work, buttons positioned | smoke `_owns` + layout — **CI** |
| Mobile | No accidental double taps | smoke §10 — **CI** |
| Mobile | Real device behaviour | **DEVICE — not claimed** |

---

## What I would fix first if you report a problem

1. **Anything about the conversation box on your phone** — that is the one thing
   above I can only prove geometrically.
2. **The letterbox during BECOME** — if it still reads as a bug rather than as a
   film frame, the answer is to cut it, not to widen it.
3. Then Phase 6, because that is the answer to "this feels like a top-down RPG
   with collection tasks", and no amount of layout work will answer it.
