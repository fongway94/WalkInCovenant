# BUGS — the stabilisation pass

**Status of this document:** live. Every entry was found by reading the code
and/or playing the build, not by a report, and every `Fixed` entry has a
regression check that failed before the fix and passes after it.

**Verification record.** Every entry below is `Fixed` **and** verified by a green
run in which its own check executed and passed:

| Run | Commit | Result |
|---|---|---|
| `41210725885` | `f01f81b` | pass 3: lint ✅ (static gates, content lint + reachability, playthrough, regression suite with the ten new checks) · export ✅ · deploy rejected by the Pages environment rule (only `main` may deploy) — the workflow now skips deploy on a working branch |
| `41203462329` | `e7e7c40` | merge of pass 1–2 to `main`: lint ✅ · export ✅ · deploy ✅ |
| `41197972787` | `85d24db` | lint ✅ (incl. the phone's A→world check) · export ✅ · deploy ✅ |
| `41195649414` | `805de7c` | lint ✅ (incl. the HUD band measurement) · export ✅ · deploy ✅ |
| `41195229562` | `9b67f29` | lint ✅ (incl. the choice-box button check) · export ✅ · deploy ✅ |
| `41194791034` | `8a02df0` | lint ✅ (incl. the pickup persistence check) · export ✅ · deploy ✅ |
| `41193918961` | `6f5853c` | lint ✅ (incl. the duel's real-input check) · export ✅ · deploy ✅ |
| `41179672932` | `bf7b05c` | lint ✅ (static gates, content lint, playthrough, regression suite) · export ✅ · deploy ✅ |
| `41179263331` | — | green: first all-checks-hold run of the regression suite |
| `41178877681` | `52ae810` | red: one check failed (a story trigger opening a box over an open one → BUG-013) |
| `41178871464` | `ce69ad2` | red: static gate (a ternary wrap in the test itself) |
| `41194441724` | `8a693e9` | red: BUG-018's new check walked the player out of Corin's reach and broke a later check — a test defect, fixed in `8a02df0` |
| `41196074087` | `d53dde1` | red: the phone check asked `has_talked()` before the conversation it was waiting for had closed |
| `41196452075` | `0f13cc6` | red: same, corrected — and still red, which is what turned this into six runs |
| `41196824038` | `32961ba` | red: the previous check left the world paused inside a trigger's area, so the tap was tested against a paused world |
| `41197178237` | `3992d4e` | red: preconditions green, tap still inert — the message split "the touch never arrived" from "nobody was in reach" |
| `41197584293` | `9049467` | red: `interact_action_opens=true` — the world's path worked, the parsed touch did not |
| `41178541547` | `7a5cabe` | red: seven suite failures, caused by un-awaited test coroutines — a fault in the *test*, fixed by fixing the test, not by weakening it |

**What proves a check actually ran.** A green job is not proof that a check
still exists: the regression suite now counts the checks it passes and fails if
the count falls below a floor (`MIN_CHECKS`), and prints the count in its PASS
line. The suite also had to be reachable at all — the workflow listed one
working branch by name, so the first push of this pass ran **no** build and the
entries below would have been reported from a commit CI never compiled. That is
fixed too; it is recorded here because "green" and "ran" are not the same claim.

**Method.** The build cannot be run in the authoring sandbox (Godot's release
binaries are on a host outside its network), so the loop is: inspect the source
→ write a check that expresses the expected player experience → fix the cause →
run the static gates locally → push → read the headless playthrough and the
regression suite out of CI. That is slower than a local REPL and it is why
nothing below is marked `Verified` until a green run has actually executed its
check. **No claim in this file rests on a build that was not run.**

Severity uses the mission's scale:

| Severity | Meaning |
|---|---|
| **P0 — Critical** | crash, save corruption/data loss, cannot progress, a major story sequence broken |
| **P1 — High** | a core mechanic fails, a mission cannot complete, people/objects missing, a transition is broken, an important interaction fails |
| **P2 — Medium** | UI, audio, wrong dialogue behaviour, visual inconsistency |
| **P3 — Low** | minor presentation and polish |

**Summary: 32 found, 32 addressed, 0 open, 0 P0** — 15 in pass 1, 7 in pass 2,
10 in pass 3 plus one investigation that cleared its suspect, plus the test
coverage each pass added. Two of them (BUG-006, BUG-010)
could leave a player permanently unable to continue; one (BUG-011) is the
save-corruption class and is fixed structurally rather than worked around.

---

## BUG-001 — the brook scene could not be finished on a keyboard

- **Severity:** P1 · **Status:** Fixed
- **Where:** `scripts/setpiece/StoneChoice.gd` → `press()`
- **Reproduce:** play to 1 Samuel 17:40 on desktop. Take five stones with the
  arrow keys and Space/A. The counter says 5/5, the "KEEP THEM" button appears —
  and pressing A takes/returns a stone instead of confirming. `_cursor` starts at
  -1 but is set the first time the player moves it and is never reset, so after
  any cursor use the confirm branch of `press()` is unreachable. Only a mouse
  click on the button could finish the scene.
- **Expected:** one button, one meaning, on every input method. The whole game
  is built on that.
- **Actual:** the scene is a dead end for keyboard players; the chapter cannot
  progress past the brook.
- **Root cause:** `press()` tested the cursor before it tested "the bag is
  full", i.e. it encoded *how* the player was navigating instead of *what the
  press means right now*.
- **Fix:** `press()` asks the state first — if five are held, A means keep them;
  otherwise it acts on the cursor.
- **Regression test:** `tests/deep.gd` → `_check_stones()` ("A confirms the five
  stones on a keyboard").

## BUG-002 — a stone could not be put back once five were held

- **Severity:** P2 · **Status:** Fixed
- **Where:** `scripts/setpiece/StoneChoice.gd` → `toggle()`
- **Reproduce:** take five stones, then tap one you are already holding.
- **Expected:** it goes back in the water (the file's own docstring says
  "touching it again puts it back").
- **Actual:** nothing happens; a toast says "Put one back first." — telling the
  player to do the thing it just refused.
- **Root cause:** the `is_full()` guard was written for the *take* branch and
  placed above the *return* branch. The one moment the player needs to change
  their mind is the moment the code was examined for the other case.
- **Fix:** returning a stone is always allowed; the full-bag guard now lives
  only on taking a new one.
- **Regression test:** `tests/deep.gd` → `_check_stones()` ("a held stone can be
  put back even when five are held").

## BUG-003 — the giant was drawn as eight tiny giants

- **Severity:** P2 · **Status:** Fixed
- **Where:** `scripts/world/Region.gd` → `_spawn_goliath()`
- **Reproduce:** start a new game and look north.
- **Expected:** one man, two tiles tall, standing on the ridge — the silhouette
  Act I is entirely about.
- **Actual:** the whole 32x64 character sheet was drawn as a single sprite at 2x:
  a 2x4 grid of eight small Goliaths, floating above the ground.
- **Root cause:** the sheet is sliced by `hframes`/`vframes`, which every other
  sprite in the project sets (the player, the NPCs, the fight). This one did not,
  so the default (1x1) applied. `GoliathFight` was unaffected because it slices
  with an `AtlasTexture`.
- **Fix:** `hframes = 2`, `vframes = 4`, `frame = 0`.
- **Why the old test missed it:** the smoke test asserted
  `goliath_sprite != null and visible`, which is true of eight tiny giants too.
  The regression check asserts the slicing and the scale.

## BUG-004 — everyone you had met forgot you after a reload

- **Severity:** P1 · **Status:** Fixed
- **Where:** `scripts/world/Npc.gd` (`_talked`), `GameState` flags
- **Reproduce:** talk to Corin and the other three in the valley, close the tab,
  come back.
- **Expected:** the people you have met say their *after* lines, the escort moves
  on, the objective points at whoever you have not met.
- **Actual:** every conversation replayed from the first line; `has_talked()`
  was in-memory only, so `_next_unspoken()` reported everybody as unmet and the
  HUD sent the player back round the same four people. Duplicate story dialogue
  after a reload is exactly the playtest-8 report.
- **Root cause:** the conversation state lived in a `var` and the save never saw
  it. Nothing in the save schema was wrong — the bit was simply not written.
- **Fix:** `talked:<region>:<npc>` is set the first time a person's lines finish
  and is read in `setup()`. Region-scoped because Bethlehem has an elder too.
- **Regression test:** `tests/deep.gd` → `_check_talked_survives()`, which builds
  a brand-new `Npc` from the same data and asks it whether it has met you.

## BUG-005 — the armour's stagger outlived the armour

- **Severity:** P3 · **Status:** Fixed
- **Where:** `scripts/world/Player.gd` → `set_armour()`
- **Reproduce:** wear Saul's armour, walk, take it off, stand still.
- **Expected:** a centred figure.
- **Actual:** the sprite kept whatever sine offset (±1.6 px) the last stagger
  frame wrote, and only the armour branch ever reset it, so the pilgrim stood
  permanently off their own shadow for the rest of the session.
- **Root cause:** the animation wrote to `sprite.offset` in one place and the
  "return to normal" path did not undo it.
- **Fix:** `set_armour(false)` restores `(0, -8)`.

## BUG-006 — a BECOME during a BECOME could stall the chapter for good

- **Severity:** P1 · **Status:** Fixed
- **Where:** `scripts/systems/BecomeController.gd` → `begin()`, `end()`
- **Reproduce:** reach 1 Samuel 17:31-39 with the transition controller already
  running — the case that matters is a resumed save which re-enters the mission
  whose `enter` is `become_david`, or any second story beat that asks for the
  transition while the bars are still in.
- **Expected:** the picture changes and the story continues.
- **Actual:** `begin()` and `end()` returned silently when `_busy`. Both callers
  pass a **callback that continues the chapter** (`_start_david_act`,
  `_after_return`). A dropped call means the callback never runs: the player is
  left as the witness with the line already crossed, `_in_battle` stuck true,
  and a mission that can never complete. `MAX_HOLD` only lifted the *visual*,
  not the dropped request.
- **Root cause:** "ignore the second call" is a safe rule for a purely cosmetic
  effect and an unsafe one for a controller whose callback is a story seam.
- **Fix:** a new request cancels the in-flight one (`_make_room()` kills the
  tween, resets the bars) and runs, so the newest continuation always fires.
  Documented at the top of the class.
- **Regression test:** `tests/deep.gd` → `_check_become_twice()` (a second BECOME
  completes, leaves `_busy` false and no bar on screen).

## BUG-007 — a fade started mid-fade could leave the screen black

- **Severity:** P2 · **Status:** Fixed
- **Where:** `scripts/ui/ScreenFade.gd` → `run()`
- **Reproduce:** start a fade, then start another one before it finishes
  (travel plus a story cut, or a double-triggered scene beat).
- **Expected:** one fade, and the picture comes back.
- **Actual:** the old tween was not killed, only the alpha was zeroed. Two tweens
  then wrote `color:a`: depending on the order they finished, the rect could end
  at 1.0 with nothing left to clear it — the "unexpected black frame" the
  playtests keep reporting, with the game running invisibly underneath.
- **Root cause:** `clear()` was a state reset that looked like a cancel.
- **Fix:** the live tween is kept, killed on a new run (and on boot), and the
  fade never starts without owning the property.
- **Regression test:** `tests/deep.gd` → `_check_fade_twice()`.

## BUG-008 — two camera shots fought over one property

- **Severity:** P2 · **Status:** Fixed
- **Where:** `scripts/world/CameraRig.gd` → `pan_to()`, `resume_follow()`
- **Reproduce:** a scripted shot (`pan_to`) handed back (`resume_follow`) before
  it finishes — i.e. dodge a dialogue box faster than the pan takes.
- **Expected:** the camera glides back to the player.
- **Actual:** both tweens animated `_cine_pos`; the camera jittered between two
  targets and could land on the old one.
- **Root cause:** same shape as BUG-007 — a second request without a cancel.
- **Fix:** both entrances kill the previous shot first.
- **Regression test:** `tests/deep.gd` → `_check_camera_shots()`.

## BUG-009 — a toast could erase the toast that replaced it

- **Severity:** P3 · **Status:** Fixed
- **Where:** `scripts/ui/Hud.gd` → `_toast()`
- **Reproduce:** two toasts inside ~2 seconds (easy: pick up the third provision
  and the "that is everything" line follow immediately).
- **Expected:** the newest line is shown for its full time.
- **Actual:** two tweens animated `modulate:a`; the older one could fade the newer
  text out early, or leave it dimmed.
- **Fix:** the previous toast tween is killed before the new one starts.

## BUG-010 — a restored position could be inside a wall

- **Severity:** P1 · **Status:** Fixed
- **Where:** `scripts/main/Main.gd` → `_place_at()`
- **Reproduce:** a save whose `progress.pos` is a tile that is solid in the
  current data (an edited map, a prop added over a doorway), or any story beat
  that teleports by authored coordinates into blocked ground.
- **Expected:** the player is put on the tile.
- **Actual:** the player is put *inside* the tile. The collision box refuses
  every direction it is itself inside, so the character cannot move at all. From
  the player's side that is indistinguishable from a crash.
- **Root cause:** the placement path trusted its input; only the *spawn* path
  (`Region._spawn_player`) asked the model for open ground.
- **Fix:** `_place_at()` snaps through `RegionModel.nearest_open()`. Every
  teleport, every restore and every rigged position goes through it.
- **Regression test:** `tests/deep.gd` → `_check_place_at_solid()`.

## BUG-011 — a save could be truncated by an interrupted write

- **Severity:** P1 (data loss) · **Status:** Fixed
- **Where:** `scripts/autoload/GameState.gd` → `save_game()`, `load_game()`
- **Reproduce:** this is a browser game that writes the save on focus loss, on
  app pause and every three seconds of walking. A tab killed mid-write, or a
  phone that runs out of memory, leaves a half-written `save.json`.
- **Expected:** the player's chapter survives, or at worst falls back to the
  previous good save.
- **Actual:** `save_game()` opened the real file and streamed the JSON into it.
  A partial file parses as invalid, `load_game()` returned false, and the game
  booted a **fresh new game** over the top of a player's chapter — silently. No
  error, no message: the game simply forgot.
- **Root cause:** the write was not atomic and there was no previous copy.
- **Fix:** the save is built in `save.json.tmp`, proven to parse, and only then
  renamed over `save.json`, keeping the old file as `save.json.bak`. Loading a
  file that exists but does not parse falls back to the backup and says so in a
  warning instead of starting a new game. `erase()` removes all three.
- **Regression test:** `tests/deep.gd` → `_check_save()` (temp file cleaned up; a
  deliberately corrupted save recovers the marker from the backup).

## BUG-012 — the journal had no keyboard escape

- **Severity:** P1 · **Status:** Fixed
- **Where:** `scripts/ui/Journal.gd`
- **Reproduce:** open the book (top-left ≡) and try to close it with the keyboard.
- **Expected:** Escape (or the pad's B) closes it. Every dialogue box in the game
  follows that rule — playtest 6 asked for it explicitly.
- **Actual:** the only exit was a small Button. The book pauses the world and
  blocks the touch controls, so a player without a working tap target is stuck
  with a still world and no way back. It is also the one overlay `Main`'s
  dead-pause watchdog deliberately exempts.
- **Fix:** `_input` closes the panel on `ui_cancel`/Escape.
- **Regression test:** `tests/deep.gd` → `_check_journal_escape()` (opens, pauses,
  Escape closes, world resumes).

## BUG-013 — a story trigger could open a scene on top of a conversation

- **Severity:** P1 · **Status:** Fixed
- **Where:** `scripts/world/Region.gd` → `_process()`
- **Reproduce:** be mid-conversation within reach of a story trigger (the
  challenge line, a curio, a first-sight radius). It was found by a test that
  put the player next to the line and then opened a box: the trigger fired, and
  `DialogueBox.show_lines()` replaced the box under the player's hand.
- **Expected:** a conversation owns the screen; the world's beats queue behind it.
  Every dialogue box in the game is supposed to be one beat at a time (AUDIT B1).
- **Actual:** two things followed from the same missing rule. (a) A trigger's
  scene replaced a box that was already open — the "the dialogue appears three
  times" report, from the world side. (b) A curio within range during a box was
  marked *seen* and then dropped by `Main._on_curio` (which does check), so that
  place never spoke again for the rest of that save.
- **Root cause:** the check lived at each consumer ("is a box open? then do
  nothing") rather than at the producer. `Region` fired its events and let the
  receivers sort it out, and one of them could not.
- **Fix:** `Region._process()` returns while a box is open. Nothing is consumed:
  triggers stay **armed** and fire the moment the conversation ends, and curios
  are not marked until they are actually spoken.
- **Regression test:** `tests/deep.gd` → `_check_dialogue_taps()` ("a story
  trigger cannot open a second box over an open one").

## BUG-014 — a region could place a quest item nobody could count

- **Severity:** P2 (latent) · **Status:** Fixed (gated, not enabled)
- **Where:** `scripts/main/Main.gd` → `_on_pickup()`, `tests/run_all.gd`
- **What:** the platform's pickup handler understands one kind of item — the
  provisions of 1 Samuel 17:17, whose ids begin `prov`. A region file may author
  `items` of any kind, so a future chapter could place a quest item, let the
  player walk over it, watch it disappear, and count nothing. A quest item that
  vanishes is worse than one that is absent.
- **Root cause:** a data-driven feature whose only consumer knows one key.
- **Fix:** this pass does not teach `Main` a second item kind (that would be a
  feature, and features are paused). It makes the failure impossible to ship:
  `tests/run_all.gd` now fails the build if any region places an item whose id
  the platform cannot count, with a message that says what to do about it.
- **Regression test:** `tests/run_all.gd` → `_check_region_any()`.

## BUG-015 — the drill could not be played on a keyboard

- **Severity:** P1 · **Status:** Fixed
- **Where:** `scripts/setpiece/SlingPractice.gd`
- **Reproduce:** play Act II on a desktop with the keyboard. The first mission
  after BECOME is the shepherd's drill (three jars, one button). Nothing happens.
- **Expected:** Space / Enter / A takes the shot, exactly as it does in the duel.
- **Actual:** `SlingPractice` connected only `gui_input`. The panel covers the
  screen and takes the mouse, `Main` blocks the touch controls while a setpiece
  is up, and no key was ever read — so the **chapter could not proceed past its
  first Act II mission** without a mouse. `GoliathFight` had the correct handler
  all along; the drill, written later, did not.
- **Root cause:** input handling duplicated per setpiece instead of following one
  pattern, so the second one was written with half of it.
- **Fix:** `_input` in `SlingPractice` handling the same keys and the same
  `TapGate` arbitration as the duel.
- **Regression test:** `tests/deep.gd` → `_check_drill_keys()`, which pushes a
  real `InputEventKey` through `Input.parse_input_event()` and waits for the
  drill to finish. (Calling `press()` would have passed before the fix, which is
  exactly why the bug survived the smoke test.)

## BUG-016 — the duel dropped most presses, in silence

- **Severity:** P1 · **Status:** Fixed
- **Reported by the player, first external report:** *"david vs goliath cant
  click anything to fight"*.
- **Where:** `scripts/setpiece/GoliathFight.gd` → `_input()`, `press()`
- **Reproduce:** enter the duel and press at the wrong moment. The fight has three
  interactive beats, but **more than half of its running time is phases that
  cannot use a press**: the telegraph (0.8 s, 1.7 s on the first round) and the
  resolve beat (0.55 s), against 0.8 s of strike and an open-ended aim. A press
  in any of the dead phases returned immediately — no sound, no message, no
  state change. A player who presses when they *see* the threat is therefore
  pressing mostly into a void, and a game that ignores you looks broken long
  before it is.
- **Expected:** every press means something, and a press made a fraction early
  still counts.
- **Actual:** silent nothing for most presses. The one input the chapter's
  climax asks for was the least reliable input in the game.
- **Root cause:** two. (a) Input was routed through one engine path (`_input`)
  only, and the state machine treated "not in a live phase" as "discard".
  (b) There was no input buffering, so the natural human timing — press as the
  spear is *released*, not as it *arrives* — always fell in the dead zone.
- **Fix:** taps are handled on both engine paths (the world's `_input` and the
  screen layer's `gui_input`), with `TapGate` arbitrating so one physical click
  is still exactly one action; a press in telegraph/resolve is **buffered for
  0.45 s** and spent as the dodge the instant the spear goes live; and every
  press is answered on screen ("Not yet — he is winding up"). The drill
  (`SlingPractice`) got the same acknowledgement.
- **Regression test:** `tests/deep.gd` → `_check_fight_input()`, which pushes
  **real events through `Input.parse_input_event`** (a mouse click, then the A
  button's synthetic action) and asserts the dodge, the nerves and the throw.
  The smoke test could never have caught this: it calls `press()` directly —
  the same blind spot that hid BUG-015.
- **Honest limit:** the engine-level path is now proven headless. Whether a
  *particular phone's* taps reach it is not proven here, and cannot be.

## BUG-017 — the game said "press A" while the A button was hidden

- **Severity:** P2 · **Status:** Fixed
- **Where:** `scripts/setpiece/GoliathFight.gd`, `scripts/setpiece/SlingPractice.gd`,
  `scripts/ui/TouchControls.gd`
- **Reproduce:** on a phone, reach the duel or the drill. The bottom of the
  screen reads "A / tap — STEP ASIDE". The on-screen A button is **gone**.
- **Expected:** a control the game names is a control the player can see and
  press (playtest 7: "every control mentioned must exist and be visible on
  phone").
- **Actual:** `TouchControls.set_blocked(true)` — correct, so the stick cannot
  drag the paused world — also stops `_draw_viz()` from drawing, so both
  buttons vanish for the whole setpiece. On a phone the fight therefore had no
  visible control at all, only prose naming one.
- **Root cause:** one flag meant two different things: "this layer must not
  consume input" and "this layer must not draw".
- **Fix:** a setpiece that takes the screen draws its own A badge, in the same
  position and style as the world's, and lights it during the live phases. The
  world's buttons stay hidden underneath, which is the part that was correct.
- **Regression test:** covered indirectly by `_check_fight_input()` (the badge is
  only drawn while `phase != DONE`); the visual itself needs a device.

## BUG-018 — the provisions you picked up were on the ground again after a reload

- **Severity:** P1 · **Status:** Fixed
- **Where:** `scripts/world/Region.gd` → `spawn_pickup()`, `_check_pickups()`;
  `scripts/main/Main.gd` → `_start_errand()`, `_errand_provisions()`
- **Reproduce:** start Jesse's errand, pick up one provision, let the game
  autosave (it does, every frame), reload. The provision is **back on the
  ground**, and picking it up again takes the count to 2 having carried 1.
  The same bread can be farmed: save, reload, pick up, save, reload. Ten
  reloads finish a four-item errand standing in one place.
- **Expected:** an item in the bag is not also on the ground (audit area D, "no
  duplication or loss").
- **Actual:** `spawn_pickup()` built every item unconditionally and
  `_check_pickups()` only set an in-memory `got`, so the ground had no memory
  while the counter beside it was restored from the save — the two disagreed
  after every reload, in the player's favour, silently.
- **Root cause:** pickups were the only collectable thing in the game without a
  save key. Curios already used `curio_<id>`; NPCs used `talked:<region>:<npc>`.
  The pattern existed and the errand simply was not using it.
- **Fix:** a region-scoped `pickup:<region>:<id>` flag, written when the item is
  taken and read by `spawn_pickup()` before it builds anything; and the errand's
  count is now **derived** from those flags (`_errand_provisions`) instead of
  being zeroed on entry. Deriving matters: the runner replays a resumed
  mission's opening beat, so `_start_errand()` runs again on a reload — with
  flags but a zero count, the errand would have been *unfinishable* (items gone,
  counter at 0/4) rather than merely farmable.
- **Regression test:** `tests/deep.gd` → `_check_pickups()`, which takes a real
  pickup by standing on it, asserts the flag, then asks the region for the same
  item again and asserts it does **not** come back, and that the derived count
  agrees.

## BUG-019 — a question could only be answered with a mouse or a thumb

- **Severity:** P2 · **Status:** Fixed
- **Where:** `scripts/story/DialogueBox.gd` → `_input()`, `_open_choices()`, `_pick()`
- **Reproduce:** reach any choice — the ending's question is the one that
  matters — and press the game's one button (A on the phone, Space/E on a
  keyboard, the pad's A). Nothing. The answers are `Button`s; the only ways in
  were a mouse click, a tap, or the number keys, none of which the game ever
  tells the player about.
- **Expected:** the same button that advances every other line answers a
  question, and a d-pad player can reach the second answer at all.
- **Actual:** with a gamepad the chapter's final question was a dead end, and on
  a desktop the game's own control scheme silently stopped working at the one
  moment it asks the player what they want to do.
- **Root cause:** choices were built as GUI widgets and the input path was
  written for widgets — "the click will land on the Button" — while every other
  line in the game is driven by `_input` and the `interact` action. Two input
  models, one screen.
- **Fix:** the in-choices branch of `_input` now understands the d-pad
  (left/right/up/down move the highlight, wrapping), and `interact` / `ui_accept`
  / Space / Enter answer the highlighted one. The highlight is a real focus ring
  (`grab_focus`), so the player can see what the button will do. `_pick()` is
  also idempotent now: the game path and the Button's own `pressed` signal can
  both deliver one press, and picking an ending twice must not run its callback
  twice.
- **Regression test:** `tests/deep.gd` → `_check_choice_keys()`, which opens a
  two-answer box, pushes a real `KEY_DOWN` and a real `interact` action through
  `Input.parse_input_event`, and asserts the second answer is the one chosen.

## BUG-020 — the objective band was sized for one line, and objectives are two

- **Severity:** P2 · **Status:** Fixed
- **Where:** `scripts/ui/Hud.gd` → `OBJECTIVE_H`, `TOAST_Y`
- **Reproduce:** switch the game to English and walk into any of the long
  objectives — "You have not understood yet what you are watching. Talk to the
  people in the camp." is 74 characters. At the design width the line is wider
  than the band, the label wraps to a second row, and that row is drawn over the
  toast band and out into the world.
- **Expected:** the band the HUD reserves is the band the text needs (the same
  rule the dialogue box already follows since "no dialogue box may overflow").
- **Actual:** `OBJECTIVE_H` was 20 px, fitted to one row of an 8 px font by eye,
  with `TOAST_Y` 1 px below the band's bottom. Any wrapped objective — and
  English wraps on a dozen of them — overlapped the toast.
- **Root cause:** a layout constant chosen against one example string, with no
  gate that would notice the day a longer string was authored. The same class of
  mistake as the fixed 312x78 dialogue box that `check_text_fit` exists for.
- **Fix:** the band is now sized for two rows of the objective font (26 px) and
  the toast moved down to 43, so the two bands cannot touch.
- **Regression test:** `tests/deep.gd` → `_check_hud_fit()`, which takes every
  objective string in both regions and both languages, measures it with
  **`Font.get_string_size()` against the label's real width**, multiplies by the
  real line height, and asserts the result fits the band and stays above the
  toast. It prints the measured numbers every run, so the margin is visible even
  when it passes.

## BUG-021 — three strings in one corner: the HUD printed over the duel

- **Severity:** P1 · **Status:** Fixed
- **Reported from a phone, with a screenshot:** *"how to play? press A no
  response. top left instructions is overlap. don't know what to do."* The
  screenshot shows the world's top bar, the world's objective line and the
  duel's own message stacked in the same top-left band, illegible.
- **Where:** `scripts/ui/Hud.gd`, `scripts/main/Main.gd`,
  `scripts/setpiece/GoliathFight.gd`
- **Reproduce:** enter the duel and press anything. The duel answers — "Not
  yet — he is winding up", "Wide. The stone is gone into the dust", "The stone
  finds his forehead" — but every one of those sentences is drawn at
  `(edge + 4, edge + 16)`, which is exactly where the HUD's bar sits and where
  the HUD's objective line begins. Three texts in one place is not a message.
- **Expected:** the screen that takes the whole picture draws the only words on
  it.
- **Actual:** the duel's feedback was invisible, so the fight felt dead — this,
  and not the input path, is what "press A no response" actually was. It is also
  why the timing was never learned: every miss explanation was printed under the
  objective line.
- **Root cause:** the HUD was never told that a setpiece had taken the screen.
  `TouchControls` was, because its buttons had already caused the same class of
  problem (BUG-017) — but the HUD has no equivalent flag, so it kept printing
  its objective over a scene that had its own.
- **Fix:** `Hud.set_covered()` hides the whole HUD while the fight, the drill or
  the stone-picking screen is up, driven from the *same* per-frame ownership
  expression `Main` already uses for the touch layer (one derived truth, so a
  path that forgets to restore it cannot leave the player without a HUD). The
  duel now carries the chapter's objective text itself, from the region file,
  and lays its own words out in three bands: what you are doing (dim), what to
  do *now* (bright), what just happened (gold).
- **Regression test:** `tests/deep.gd` → `_check_hud_yields()`: the HUD is
  visible in the world, hidden while a duel is up, the duel has a non-empty
  objective of its own, and the HUD comes back afterwards.

## BUG-022 — the pouch emptied and never refilled

- **Severity:** P1 · **Status:** Fixed
- **Same screenshot:** *"石子 0 块"* — zero stones — while the giant was still
  winding up for the next round.
- **Where:** `scripts/setpiece/GoliathFight.gd` → `_after_resolve_step()`,
  `_throw()`, `_resupply()`
- **Reproduce:** throw all five stones without landing one. Every throw ends a
  round with `_after_resolve = "round"`, so `_after_resolve_step()` takes the
  `"round"` branch and returns; the `stones <= 0` branch *below* it could never
  be reached. `_resupply()` was dead code. The counter then went negative on
  further throws, and the only visible result — "Wide. The stone is gone into
  the dust" — was printed under the HUD's objective line (BUG-021), so the
  player saw nothing at all.
- **Expected:** an empty pouch refills, and the screen says so.
- **Actual:** a fight that a player could keep pressing through with a stone
  count of −3 and no explanation.
- **Root cause:** branch order in a state machine, plus a resupply that gave back
  **two** stones when the fight requires **three** hits: even if it had been
  reachable, it could not have been enough.
- **Fix:** the pouch is checked before the round branch; `_throw()` refuses to
  spend a stone that is not there; the refill is `HITS_TO_WIN` (three) and says
  so. Two more changes came out of the same screenshot, because the aim is the
  one timing in the game and the player never got to learn it:
  - the sweep is slower (`MARKER_SPEED` 1.9 → 1.55, a 0.27 s → 0.33 s window)
    and the sweet band is wider at the start (0.26 → 0.30, narrowing per hit);
  - the **A button itself is the timing cue**: it turns solid gold, and the line
    under it changes to "NOW — let go!", exactly while the white line is inside
    the band. The player's thumb is on that button; the forehead is on the far
    side of a phone. The drill teaches the same cue, since the drill is where
    the gesture is supposed to be learned.
  - every accepted press now visibly punches the A badge, so a press that is
    *heard* never looks like a press that was ignored.
- **Regression test:** `tests/deep.gd` → `_check_duel_resupply()`: with an empty
  pouch and a round ending, the fight refills to enough stones to finish, the
  phase moves on, and a throw with no stone never spends one.


---

# Pass 3 — the whole game read against itself

Passes 1 and 2 fixed what players reported and what the code visibly got wrong.
This pass went looking for the defects nobody had hit yet, in the three shapes
they take in a game of this size:

* **the data says one thing and the code does another** (BUG-023) — the most
  expensive kind, because the level is authored by hand and looks correct;
* **a state that is written but never read back** (BUG-024, BUG-025, BUG-030) —
  the save, the mixer and the HUD all keep their own copy of the truth;
* **a thing that works until the player changes something mid-use** (BUG-026,
  BUG-027, BUG-028, BUG-029) — every one of these is "switch the language" or
  "the music is still playing", i.e. exactly what a player does in their first
  minute.

Each fix is guarded by a check that would have failed before it.

## BUG-023 — props declared walk-through still stopped the player

**Severity:** P2 · **Status:** Fixed · **Area:** world / collision
**Regression test:** `tests/run_all.gd` → non-solid-prop assertion; `_reachable()`
sweep over exits, curios, triggers, items and the giant.

- **Reproduce:** walk into the bushes in Bethlehem (`data/props.json` says
  `"solid": false`), or into the camp fire in the valley.
- **Expected:** the bush is scenery you can walk through; the game's own data
  says so.
- **Actual:** every prop tile was solid. `RegionModel._init_from()` set
  `_solid = 1` over each prop footprint and never read `_meta.solid`, so
  `solid: false` was a comment. Four props were authored as non-solid
  (`bush`, `wheat_sheaf`, `jar`, `signpost`) and all four were invisible walls;
  worse, the level author had no way to place decoration in a corridor.
- **Root cause:** the model consumed the prop's *footprint* and ignored the rest
  of its metadata — a data contract with only one side implemented.
- **Fix:** `RegionModel` now skips footprints whose meta says `solid: false`;
  `fire` is flipped to `solid: true` in the data, because a fire is a fire.
- **Why it is not cosmetic:** the same sweep that found it also found that a
  prop's footprint can be placed over an NPC's tile or an exit. The new content
  rule walks to every NPC, exit, curio, trigger, item and the giant from the
  spawn, and refuses the build if a non-solid prop still collides — the class of
  defect that would make a chapter unfinishable is now a red build, not a
  playtest.

## BUG-024 — a save with the wrong shape threw on boot

**Severity:** P1 · **Status:** Fixed · **Area:** save / load
**Regression test:** `tests/deep.gd` → `_check_save_shape()`.

- **Reproduce:** write a save whose `flags` is a list instead of an object (or
  `level` as a string), then start the game.
- **Expected:** the game boots into a sensible state, keeping what it can.
- **Actual:** `load_game()` merged the file over the defaults **per top-level
  key only** and then every reader indexed the result directly —
  `data["flags"].get(...)`, `int(data["level"])`, `data["words"].size()`. A
  list-shaped `flags` throws on the first frame; an `int(data["level"])` with a
  string is a silent `0`. JSON.parse proves the file is *JSON*, not that it is
  *our save*.
- **How a player gets here:** an older build (the schema has already changed
  once), a hand-edited or exported save, a browser killed mid-write (the `.bak`
  fallback covers truncation but not a wrong-but-valid file), or a
  phone-sync/extension that rewrote the file.
- **Root cause:** the loader trusted its own input, and the save is the one file
  in the game that is allowed to be wrong.
- **Fix:** `_coerce(defaults)` after the merge — every known dictionary, array,
  int, string and switch is coerced to the type the rest of the code assumes,
  each repair is announced with `push_warning`, and unrecognised keys are kept
  rather than dropped. Position is only accepted as a two-element array.
- **Coverage:** the check writes a deliberately wrong-typed save to the real
  path, loads it, asserts every field comes back in shape **and that the game
  still works afterwards** (`set_flag` round-trips), then restores the good save.

## BUG-025 — unmuting left the chapter silent

**Severity:** P2 · **Status:** Fixed · **Area:** audio
**Regression test:** `tests/deep.gd` → `_check_audio_unmute()`.

- **Reproduce:** mute, change region, unmute.
- **Expected:** the region's music comes back.
- **Actual:** silence for the rest of the region. A track requested while muted
  recorded its key in `_current_music` but never loaded a stream (there was
  nothing to play it through), and unmuting only unmuted the bus — so there was
  no stream to be heard, and no later event that would ask for one from the
  region's existing player.
- **Root cause:** muting was implemented on the bus, but loading was gated on
  not-muted. Two different notions of "muted" in one small class.
- **Fix:** `apply_settings()` replays `_current_music` at a zero-length fade when
  the sound is turned on and the music player is empty.

## BUG-026 — the ending's question played over the music

**Severity:** P3 · **Status:** Fixed · **Area:** audio / UI
**Regression test:** `tests/deep.gd` → `_check_choice_ducks()`.

- **Reproduce:** finish the chapter, read the ending's two-answer question.
- **Expected:** the music sits under the words, as it does in every other box.
- **Actual:** `show_lines()` and `show_choices()` both duck; the ending goes
  through `show_choices_standalone()`, which was added later and did not. The
  loudest, most important question in the game was the one you had to read over
  the soundtrack.
- **Root cause:** three entry points to the same box, and the newest one copied
  the layout instead of the audio contract. `hide_box()` unducks, so the bug was
  invisible on close.
- **Fix:** `show_choices_standalone()` ducks like its siblings. The check asserts
  the bus is actually quieter while the box is up and restored after it closes.

## BUG-027 — an open conversation ignored the language switch

**Severity:** P3 · **Status:** Fixed · **Area:** i18n / dialogue
**Regression test:** `tests/deep.gd` → `_check_language_switch()`.

- **Reproduce:** open any conversation, press the 中/EN button on the HUD.
- **Expected:** the line, and any answers on screen, are in the new language.
- **Actual:** the box kept the language it was opened in until it was closed and
  reopened. `I18n.language_changed` had existed since the first pass and **no
  node had ever connected to it**; the HUD only looked correct because
  `_update_guidance()` re-pushes its strings every frame. The box, which renders
  on open and on tap, never re-ran.
- **Root cause:** a "dead signal" — an event published by the language
  singleton that the UI never subscribed to, hidden by the one consumer that
  happened to poll.
- **Fix:** `DialogueBox` re-renders on the signal: the current line is
  re-paginated (Chinese and English wrap at different points, so the page break
  itself has to be recomputed) and an open set of answers is re-lettered A/B/C
  from the content, with the ring and the full-text reveal restored.

## BUG-028 — the book listed the verses and not the words

**Severity:** P2 · **Status:** Fixed · **Area:** journal / progression
**Regression test:** `tests/deep.gd` → `_check_journal_verse_text()`.

- **Reproduce:** earn a verse from anyone in the valley, open the book (the ☆
  panel). Read the "verses" section.
- **Expected:** the verse.
- **Actual:** `★ 1 Samuel 16:7`. The reward the entire game is built on — a
  person gives you a sentence of Scripture and the HUD's ☆ ticks up — could not
  be read anywhere in the game. The book is the only place it could live.
- **Root cause:** the journal was given `verse_refs` (strings) because the
  caller only had references to hand; the text was in the region data beside the
  reference the whole time, and the panel's contract was never revisited when
  verses became the main progression.
- **Fix:** the caller now passes `{ref, text}` resolved through `I18n`, and the
  panel prints the citation, then the words. A plain string is still accepted so
  no caller can break the panel. The check opens the book twice and asserts the
  verse appears exactly once — a reprint must not duplicate the page.

## BUG-029 — the book stayed in the language you just left

**Severity:** P3 · **Status:** Fixed · **Area:** journal / i18n
**Regression test:** `tests/deep.gd` → `_check_journal_language()`.

- **Reproduce:** open the book, press 中/EN.
- **Expected:** the page, its headings and its close button are in the new
  language.
- **Actual:** the whole panel kept its opening language. The book is precisely
  the screen a bilingual player lingers on, and it is the one screen the switch
  could not reach (BUG-027 was its sibling in the dialogue box).
- **Root cause:** the panel built its labels once, in `_build()` and
  `open_panel()`, and had no notion of being printed again.
- **Fix:** the panel keeps what it was opened with and reprints itself on
  `language_changed`; `Main` recomputes the objective line first, because that
  sentence comes from the HUD and would otherwise be a snapshot in the old
  language. Rows are detached before being freed, so the page does not print
  itself twice for one frame while the layout catches up.

## BUG-030 — a reload brought the pouch back empty-handed

**Severity:** P2 · **Status:** Fixed · **Area:** HUD / save state
**Regression test:** `tests/deep.gd` → `_check_pouch_restore()`.

- **Reproduce:** pick the five stones at the brook, then reload before the duel.
- **Expected:** you are carrying what you picked up, and the counter says so.
- **Actual:** `_resume_story()` restored `stones` into the script and the HUD
  showed nothing. `_on_region_ready()` blanks the counter on purpose (it must not
  be on screen while the witness is still arriving in the valley), and nothing
  put it back on a resume.
- **Root cause:** the same "written but never read back" shape as BUG-024 and
  BUG-025 — three copies of one number, one of them on screen.
- **Fix:** the resume hands the restored count to the HUD when it is non-zero.
  The check drives `_resume_story()` with a save that has stones and no `pos`
  (so the test cannot move the world), asserts the counter is visible and
  correct, then restores the live state.

## BUG-031 — the place card kept the old language

**Severity:** P3 · **Status:** Fixed · **Area:** UI / i18n
**Regression test:** `tests/deep.gd` → `_check_place_card_language()`.

- **Reproduce:** walk into a region (the card holds for 2.4 s) and press 中/EN
  while it is up.
- **Expected:** the caption is in the language the player is reading.
- **Actual:** the card printed its two lines once, at `show_card()`, and the
  signal it should have listened to did not exist in it. The third member of the
  same family as BUG-027 and BUG-029.
- **Root cause:** the card was written as a one-shot animation, and its text was
  an argument rather than state.
- **Fix:** it keeps the two dictionaries and reprints them on
  `language_changed` while it is busy; the fade is untouched, because the player
  is looking at a picture, not a menu.

## BUG-032 — lifting the walking thumb released the A button

**Severity:** P1 · **Status:** Fixed · **Area:** mobile input
**Regression test:** `tests/deep.gd` → `_check_two_thumbs()`.

- **Reproduce (phone):** hold the stick with the left thumb, press A with the
  right, then lift the left thumb first.
- **Expected:** A is still held until the thumb on it lifts.
- **Actual:** the release was matched to a control by *kind*, not by finger:
  every release ran all three "is this mine" branches, so the stick's release
  also emitted `interact` released. Any interaction that has to outlive the
  walking thumb — holding A, a charged input, a press-and-hold — was cancelled
  by the other hand. On a phone both thumbs are down almost all the time, and
  nothing in the keyboard-driven suite could see it.
- **Root cause:** one shared release path for three controls that each need a
  distinct owner. The stick had an id; the buttons never did.
- **Fix:** each control records the finger that pressed it and only that finger
  releases it; `_owns()` claims a release for the ids it knows. A second thumb on
  the stick half now takes the stick over instead of being ignored. The check
  drives the real `_press()`/`_drag()` path with two touch indices and asserts
  the four states in order.

---

## Investigated and cleared: `elah.arrive_act = "done"` (no bug)

Returning to the valley from Bethlehem sets the act straight to `DONE` (index 9
of `ACT_NAMES`), which has no `match` arm in `_update_guidance()` and falls to
the `_:` default. That default looked like the city path, and the report that
prompted this pass feared the return leg would point at Corin for a chapter that
is over.

It does not. The default resolves in order — Corin spoken to?, anyone unspoken?,
`elah_saw_him`?, `goliath_down`? — and by the time a player can walk to
Bethlehem and back, every one of those is answered, so the guidance lands on
`objectives.done` ("Chapter complete · the valley is quiet now"), which is
exactly what a finished valley should say. `first_unmet()` returning
`missions.size()` also stops the runner from replaying the chapter on re-entry.

Recorded rather than "fixed": there is nothing to change, and changing working
content on a suspicion is how a stabilisation pass breaks a game. The reasoning
is written down so the next pass does not re-investigate it.

---

## Closed by inspection: the service worker's pre-cache list

The deployed `index.service.worker.js` pre-caches seven files with
`cache.addAll()`, which **rejects the whole install if any one of them is a
404** — a silent way to ship a PWA that cannot be installed or run offline. The
two the engine generates rather than copies (`index.icon.png`,
`index.apple-touch-icon.png`) were on the open list for two passes because they
are binaries and the only tool this sandbox has for the live site returns HTTP
500 on binary bodies.

That is now settled with a control: a file that genuinely does not exist returns
the GitHub Pages **404 HTML page** through the same tool, and both icons return
500 — i.e. a 200 with a body the tool cannot decode. Both exist; the pre-cache
list is satisfied. Recorded here so it is not re-investigated.

---

## Coverage added in pass 2 (not bugs — gaps that let bugs hide)

- **The phone's whole verb, tested as a phone.** Every check in `tests/deep.gd`
  drove the game the way a keyboard does, and the report that opened this pass
  came from a phone. `_check_touch_interact()` now stands the player beside an
  unspoken villager, sends a real `InputEventScreenTouch` at the position
  `TouchControls` draws its A at, and asserts a conversation opens and that
  finishing it marks the person met.
- **What that check cannot prove.** Godot's headless build does not route a
  parsed touch event to `Node._input` — the run that discovered this reports
  `interact_action_opens=true, parsed_opens=false`, i.e. the world's own path
  works and the engine's touch routing is simply absent without a display. The
  check therefore drives `TouchControls._input()` — the exact handler the engine
  calls — with the same real touch event, which exercises the whole indirection
  that has broken before (`touch → TouchControls → interact action → world`).
  The engine's display-server routing is still only proven on hardware, and that
  remains on `docs/DEVICE-CHECKLIST.md`.

---

## Found, but not fixed in this pass (documented so they are not lost)

| # | Severity | What | Why it is still open |
|---|---|---|---|
| O-1 | P2 | `Region.progress` restores `stones`/`provisions` from the save, but the mission that owns them restarts its `enter` beat (`_brook_started()` resets `stones = 0`). A resumed save mid-brook therefore re-walks the brook. | This is the *designed* resume semantics ("replay the current mission's opening beat"), so it is a design question, not a defect. It costs the player one walk, never progress. Worth revisiting when resumes are re-specified. |
| O-2 | P3 | The interact prompt is driven from `Main._update_guidance()`, which also mutates the world (`corin.lead_to`, `_brothers_beat`). It is guarded today, but a guidance function with side effects is a bug waiting to happen. | Refactor only, no reproducible defect. Deferred deliberately: the mission forbids restructuring working systems without a demonstrated reason. |
| O-3 | P3 | `Hud.journal_btn` is 26x17 logical units. On a 2x window that is 52x34 physical pixels, under the 44 px thumb guideline. | Needs a real device to judge; see the device checklist. Changing it blind could crowd the objective line on a 4:3 screen. |
| O-5 | P2 | `Main._on_pickup()` understands one kind of quest item (`prov*`). A region that authors any other kind would place it, let the player collect it, and count nothing. | Not a live defect — no region authors one — but it is one edit away from being one. Guarded by a new content rule in `tests/run_all.gd` (a region may only place `prov*` items until `Main` learns another kind), so it can no longer fail silently in play. |
| O-4 | — | **Unverified:** audio (ducking, crossfade, no clicks) and the whole touch/layout experience on a real phone. | The authoring environment has no sound card, no touch screen and no Godot binary. Headless assertions prove the *levels and state*, not what a player hears or feels. See docs/DEVICE-CHECKLIST.md. |
