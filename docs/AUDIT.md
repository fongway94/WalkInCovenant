# Walk in Covenant — technical audit (development reset)

This is the Phase 1 deliverable: what is actually in the code, what is broken,
why, what it affects, and what changing it would risk. It was written by reading
the source, not by looking at a screenshot.

**Status after the repair pass** — sections 1–4 are fixed and covered by CI;
section 5 is the next build. See `docs/RESET-REPORT.md` for the per-phase reports.

| Section | Status |
|---|---|
| §1 Screen and display | **fixed** (layout authority, letterbox, resize) |
| §2 NPC interaction | **fixed** (tap arbitration, NPC state machine) |
| §3 Dialogue presentation | **rebuilt** (opacity, portrait, pagination) |
| §4 Chinese | **rewritten** (voice, register; verses untouched) |
| §5 Gameplay vs the brief | **not started** — scheduled as the next pass |
| §6 Campaign architecture | partially ready; `Main.gd` still campaign-specific |
| §7 Duplicate handlers | the input conflicts are gone |

**How to read the confidence column**

| Mark | Meaning |
|---|---|
| **read** | Proven by reading the code. No engine needed. |
| **tested** | Reproduced by a check that now runs in CI. |
| **unverified** | Cannot be proven from this sandbox (no Godot binary, no browser). Stated as unverified on purpose. |

---

## 0. What the game actually is, in code

| Layer | File | Lines | Role |
|---|---|---|---|
| Boot | `scripts/main/Main.gd` | 713 | `Act` state machine, guidance, every story beat |
| World | `scripts/world/Region.gd` | 421 | levels the JSON, owns player/NPCs/dialogue/triggers |
| | `scripts/world/Npc.gd` | 359 | patrol / follow / lead / talk |
| | `scripts/world/Player.gd` | 271 | 4-way movement, tile collision, own input path |
| | `scripts/world/CameraRig.gd` | 93 | deadzone, lookahead, clamp |
| | `scripts/world/TerrainLayer.gd` | 88 | visible-range tile blit |
| Dialogue | `scripts/story/DialogueBox.gd` | 394 | typewriter, portraits, choices, its own input path |
| UI | `Hud` 240, `TouchControls` 162, `Journal` 157, `PlaceCard` 96, `ScreenFade` 39, `WaypointArrow` 63 | | six independent `CanvasLayer`s |
| Cinematics | `BecomeController` 115 | | letterbox bars, wash, nameplate |
| Setpieces | `GoliathFight` 326, `SlingPractice` 215, `WordBattle` 199 | | three drawn-UI scenes |
| Content | `data/regions/elah.json` (31 KB) | | all 5 chapters of David |

Engine: **Godot 4.7, GL Compatibility, web-first**. Base viewport 320×180.
Chinese is the default locale; English is the toggle. Content is `{en, zh}` pairs
inline in JSON.

**The shape of the problem.** Every subsystem above is individually reasonable.
What is missing is a *layer* between them. There are **six** things that own a
piece of the screen, **three** things that read the input event stream, and
**two** things that decide what a tap means. No file is wrong by itself; the
composition is. That is why the symptoms reappear after every feature.

---

## 1. Screen and display

| # | Finding | Confidence | Affected |
|---|---|---|---|
| A1 | **The letterbox is drawn by us.** `BecomeController.BAR_H = 16.0` slides two black bars in over a 180-unit-tall canvas — 18% of the picture — for the whole BECOME transition, with only a 14px caption line as context. Nothing retracts them if the tween is interrupted, and `_busy` silently refuses a second call, so an interrupted transition leaves bars on screen with no way out but the watchdog. This is the most likely source of "the game becomes smaller and black borders appear". | read | `BecomeController.gd` |
| A2 | **No layout authority.** `DialogueBox` (width 320−10), `Hud` (objective width −30, prompt ±110), `TouchControls` (A at `vs.x−30`), `CameraRig`, `TerrainLayer`, `GoliathFight` (`vs.x−54`) each derive geometry from `get_viewport_rect()` with their own constants. `tools/check_text_fit.py` models the dialogue as **265 px wide**; the real text column is `320 − 10 − 10(pad) − 30(portrait) − 5(gap) = 265` *only at exactly 320×180* and by coincidence. Any of these can disagree at another resolution. | read | 6 files, 1 python tool |
| A3 | **Nothing listens to `size_changed`.** Rotation, browser chrome hiding, or entering fullscreen re-lays the engine viewport but no game system re-lays itself. Fixed offsets (`arrow` at −26/−6, `journal_btn` 2..30) assume one screen shape. | read | `Hud`, `DialogueBox`, `PlaceCard` |
| A4 | **Pixel snapping fights fractional scaling.** `2d/snap/snap_2d_transforms_to_pixel=true` plus `CameraRig` rounding `global_position`, while the canvas is scaled by a **fractional** factor (2.63× on a 844×390 phone). At non-integer scales the camera snaps in *logical* pixels, so the world shimmers and steps by 2–3 device pixels at a time. | read | `CameraRig.gd`, `project.godot` |
| A5 | `window_width_override=1280×720` forces a native window larger than many laptop viewports. Harmless in the browser (the canvas is sized by the HTML shell), confusing on desktop. | read | `project.godot` |
| A6 | The dialogue panel is **93% opaque and full width**, grows upward without a maximum, and is drawn *over* the A button (layer 20 > 12) — so during a conversation the player cannot see the world they are meant to be watching, and the button they are told to press is hidden while still accepting input. | read | `DialogueBox`, `TouchControls` |
| A7 | Verified web-shell behaviour: the engine's own `full-size.html` sizes the canvas to the window and does **not** letterbox it. So the black bands are not the shell; they are ours (A1) or a fade (A8). | read (upstream source) | — |
| A8 | `ScreenFade` fades to α=1 (near-black) for `0.45 s` on every chapter transition. Correct as design, but with A1 running at the same moment the two black effects stack, which reads as a stall or a bug. | read | `ScreenFade`, `Main` |

**Root cause (display):** there is no single answer to "where is the screen and
what may use it", and one cinematic effect is implemented as *black bars over the
game* rather than as a framed composition.

**Risk of changing it:** low for the layout helper (new file, additive). Medium
for `BecomeController` (it is the signature moment and is covered by the smoke
run). Changing `project.godot` stretch settings is high-risk — the current
`canvas_items + expand + fractional` combination is the correct one and must not
be swapped for `integer` or `keep` (that was playtest 8's bug C).

---

## 2. NPC interaction and the "dialogue three times" bug

| # | Finding | Confidence | Affected |
|---|---|---|---|
| B1 | **Three consumers, one tap.** `TouchControls._input` handles `InputEventScreenTouch` *and* `InputEventMouseButton` and never calls `set_input_as_handled()`. Godot emulates a mouse event from a touch (`emulate_mouse_from_touch`, default **true**), so one physical tap arrives **twice**. `DialogueBox._input` advances on *any* touch/mouse press. And `TouchControls` synthesises an `InputEventAction("interact")` for the A button, which `DialogueBox._input` advances on *as well*. One tap on A with a box open = up to **three advances**: the exact reported symptom. | read | `TouchControls.gd`, `DialogueBox.gd` |
| B2 | The tap that closes a box can also satisfy `Region._unhandled_input` and immediately reopen the conversation. `Region.INTERACT_LOCK = 0.35 s` is a band-aid over this one path only. | read | `Region.gd` |
| B3 | `Npc.talk()` guards on `dialogue.is_open()` but has **no per-NPC state**. Two events in one frame both pass the guard before either sets `state = TALK`, and `_talked` (which switches the NPC to their `after` lines) is only set in `_on_done`, i.e. when the box closes — so a double-open replays the *first* conversation verbatim. | read | `Npc.gd` |
| B4 | `Npc.State` conflates world behaviour (PATROL/FOLLOW) with conversation. There is no COOLDOWN and no "available" state, so availability is inferred from distance by whoever asks. | read | `Npc.gd`, `Region.nearest_interactable()` |
| B5 | In choices mode, `DialogueBox._input` maps **any key press** to option 0. Walking away from a choice with W silently picks the first answer. | read | `DialogueBox.gd` |
| B6 | `DialogueBox` treats every key as "advance", including movement keys. Holding W to walk into a conversation advances two lines before you let go. | read | `DialogueBox.gd` |
| B7 | `Region._check_exits` polls `Input.is_action_just_pressed()` inside `_process`: a second, parallel input path that bypasses the action-event flow entirely. | read | `Region.gd` |
| B8 | Quest progression is single-fired by `Npc._talked`, but `EventBus.player_interacted_with` fires once per *closed box*, so a re-entered conversation emits it again; `Main._on_interacted` currently tolerates it by checking `act`, which will not scale to more NPCs. | read | `Npc.gd`, `Main.gd` |

**Root cause (interaction):** tap arbitration is distributed across the nodes
that *react* to a tap instead of being decided once by the layer that *owns* the
tap. Every player-visible symptom follows from that.

**Risk of changing it:** medium. The smoke run drives `Npc.talk()`,
`DialogueBox._advance()` and the touch A button directly, so the seams are
already under test — but this is the system the whole game hangs on, so it gets
its own regression checks before anything else is layered on top.

---

## 3. Dialogue presentation

| # | Finding | Confidence |
|---|---|---|
| C1 | Panel is full-width, α=0.93, no maximum height, no inset from the screen edge — it reads as a UI sheet laid over the game, not as a voice in the scene. |
| C2 | Speaker identity is a 9px label above 10px body text with no separation element; the portrait is a 16×16 idle frame stretched to 30×38 with `KEEP_ASPECT` (so it letterboxes itself inside its own box). |
| C3 | The "you can continue" cue is a bare `▼` that appears only after the typewriter finishes, and the 22×16 `»»` skip button overlaps the same corner. |
| C4 | No pagination. Long lines are handled by growing the panel upward — which is why the panel reached the top of the screen and why `check_text_fit.py` exists. A lint is a poor substitute for pagination. |
| C5 | Choices are rendered inside the same panel with no visual separation from prose, and they inheriting the default Godot button theme, which is the one place the pixel-art identity breaks. |
| C6 | During a conversation the touch buttons stay drawn (under the panel) and stay live. | 

---

## 4. Chinese

Audited every bilingual pair in `data/` with a script (0 pairs with Chinese in
the English field; 696 codepoints all covered by the font; all lines ≤ 4 rows at
265px). Machine-detectable problems are therefore **none**. That is the honest
finding: the problem is not broken data, it is **register**.

| # | Finding | Confidence |
|---|---|---|
| D1 | All four NPCs speak in the same rhythm: 6–12 character staccato sentences, one idea per box. A scribe, a boy, a woman baking and an old man with a leather strap should not sound like the same author. |
| D2 | Several lines are **written** Chinese, not **spoken** Chinese, e.g. 「他错在以为年轻就没有用」 (a maxim) and 「没人有这个心气」 (the line you flagged: it describes the altar from a narrator's distance instead of being what a person would say standing there). |
| D3 | Modern written connectives leak into 1020 BC speech: 「所以」「可是」「反正」「其实」 are used where period speech uses juxtaposition or 「只是」「偏」. |
| D4 | Curios are all narration in the same voice; they read as flavour text from a tour guide. |
| D5 | Scripture itself is exact (和合本 + KJV), verified against a CUV source; the risky sentence fields were already corrected. Nothing here proposes to touch a verse. |

**Risk of changing it:** low technically (data only), medium editorially: every
line must keep its `{en, zh}` pair, stay ≤ 4 rows, and any new character must be
added to the font (CI fails otherwise). **Verses must not change at all.**

---

## 5. Gameplay against the brief

| # | Finding | Confidence |
|---|---|---|
| E1 | **Witness mode is a fetch chain.** Talk to four people → collect five stones → cross a line. The four conversations are good; the *objectives* around them are all "go to the next marker". |
| E2 | **The two modes do not interleave.** BECOME fires exactly once, near the end. The chapter is witness → (one transition) → David → ending. The concept asks for a loop between the two perspectives. |
| E3 | **The David act is talk-and-collect.** Drill → three provisions → brothers → king → line. Nothing in it uses a mechanic that *is* the story: no choosing of stones, no refusal of armour as an input, no walking out under a weight you can feel. |
| E4 | Chapters 1–6 exist as *beats* but not as *missions*: none has a briefing, a completion condition separate from a trigger, or a reward distinct from a toast. |
| E5 | Escort exists (`Npc.lead_to`) and is used well for Corin, but it is the only "follow the character" mechanic. |

**Risk of changing it:** high — this is the part that decides whether the game
is worth finishing, and it cannot be done by patching. It must be designed
(missions with introduction → objective → mechanic → completion → reward) and
then built against the systems that Phase 2–4 stabilise.

---

## 6. Architecture for future campaigns

| # | Finding | Confidence |
|---|---|---|
| F1 | `data/campaigns.json` + `CampaignModel` already make the region a data choice. Good. |
| F2 | `Main.gd` is 713 lines of *this* chapter's story. It is the one file that would have to be rewritten for Moses. That violates "adding a campaign is content development". |
| F3 | BECOME hard-codes `CampaignModel.current_hero()` but the David act's beats (`shepherd`, `items`, `brothers`, `saul`) are bespoke keys read by bespoke functions. A generic mission list would have made Moses a data file. |
| F4 | `Npc.talk()` chooses lines from a fixed `lines/after/after_win` triple. Any richer state (quest stage) needs a data-driven selector. |

**Risk:** splitting `Main.gd` is a real refactor. Do it *after* the interaction
and dialogue systems are stable and tested, in one move, with the smoke run as
the harness — not during this repair pass.

---

## 7. Duplicate and conflicting handlers (item 9 of the brief)

| Handler | Status |
|---|---|
| `TouchControls._input` / `DialogueBox._input` / `Region._unhandled_input` | **conflict** — one tap, three meanings (B1, B2) |
| `Region._check_exits` (`Input.is_action_just_pressed`) | **parallel path** (B7) |
| `EventBus.verse_received` → `Hud._refresh` + `Main._on_verse` | fine, different concerns |
| `EventBus.toast_requested` → `Hud._toast` | single listener, fine |
| `DialogueBox.closed` → `Region` (interact lock) + `Main` (story) | fine but the lock belongs in the box's owner, not in a global timer |
| `Npc._on_done` → `pause_fn(false)` then `EventBus.player_interacted_with` | ordering is deliberate and documented; keep |

---

## 8. Repair order, and why

1. **Tap arbitration + NPC state machine** (fixes the reported duplication; every
   later phase depends on a conversation being exactly one conversation).
2. **Display authority** (one layout module; dialogue and HUD lay themselves out
   from it; the cinematic bars stop being a black rectangle).
3. **Dialogue presentation** (the panel becomes a speaking voice in the scene,
   with pagination so overflow is structurally impossible).
4. **Chinese pass** (register, voice, spoken grammar; verses untouched).
5. **Mission design** (E1–E4): design and build, not patch. This is the next
   substantial piece of work and the one that decides whether the game matches
   the concept.

Phases 1–4 are repairs and will not add a new mechanic. Phase 5 will.
