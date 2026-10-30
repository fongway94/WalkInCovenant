# Architecture — Godot 4.7 project structure and the port from Covenant

> Design principle: **content is data, not code.** Covenant's greatest structural achievement was that
> a volunteer could write a chapter in `chapters.js` without touching engine code, and twelve lints
> would catch their mistakes. That property is more valuable than anything the remake adds visually,
> and it must survive the port. Everything below is organised to protect it.

---

## 1. What comes across, and what is rebuilt

| Covenant module | Lines | Verdict |
|---|---|---|
| `data/chapters.js`, `chapters-extra.js`, `zh-story.js` | 2,049 | 🟢 **Port verbatim.** The story. Convert by script, never retype. |
| `data/mirror.js`, `deeper.js`, `compendium.js` | 499 | 🟢 **Port verbatim.** Journey Mirror, reading invitations, virtues/relics/fruits/seals. |
| `data/quests.js`, `portraits.js` | 141 | 🟢 **Port.** Quest definitions and portrait mapping. |
| `world/elah.js` — `NPCS`, `WORDS`, `SHOUTS`, `STONES` | 208 | 🟢 **Port the content, discard `buildGrid()`.** Maps become authored `.tscn`, not generated stamps. The four-verses-become-four-moves design is excellent and survives intact. |
| `world/battle.js` | 567 | 🟡 **Rebuild as a Godot scene**, reusing its rules and text exactly. |
| `core/audio.js` — procedural score | 779 | 🟡 **Decision point in Phase 0.** Either port to GDScript `AudioStreamGenerator`, or replace with Ninja Adventure's 37 CC0 tracks. Recommendation: **use the CC0 tracks for regions, keep the procedural engine for prayer/ambience** — you already wrote it and it is distinctive. |
| `core/i18n.js`, `state.js` | 521 | 🟡 **Rebuild in Godot** (TranslationServer + a `SaveGame` resource) but preserve the exact save schema so old saves can migrate. |
| `assets/art/*.jpg`, `portrait-*.jpg` | — | 🟢 **Reuse directly** for cutscenes, chapter cards, mirrors. See `ART.md` §8. |
| `tools/check-*.js` (12 lints) | ~1,700 | 🟡 **Rebuild as Godot headless tests.** Same assertions, new runner. Do not lose these. |
| `engine/scene.js`, `visual.js`, `games.js`, `stages.js`, `moments.js`, `momentart.js` | 7,469 | 🔴 **Replaced by Godot.** This is the hand-rolled engine you are retiring. |
| `world/rig.js`, `field.js` | 1,164 | 🔴 **Replaced.** Vector character drawing and hand-written collision → `AnimatedSprite2D` + `TileMap` physics layers. |
| `screens/*.js`, `main.js`, `styles.css` | 4,246 | 🔴 **Replaced** by Godot `Control` scenes and themes. |

**Net: ~4,300 lines of irreplaceable content port forward. ~13,000 lines of engine and UI get replaced
by things Godot gives you free.** That is the entire argument for the remake, quantified.

---

## 2. Project layout

```
WalkInCovenant/
├── project.godot                  ← pixel-perfect settings, input map, autoloads
├── export_presets.cfg             ← web / android / ios (created when you first export)
├── icon.svg
│
├── assets/                        ← IMPORTED third-party art (never hand-edited in place)
│   ├── ninja-adventure/           ← CC0 pack, kept in its original folder structure
│   │   └── CREDITS.md             ← licence text + attribution, committed
│   ├── kenney/
│   └── LICENSES.md                ← one line per pack: name, author, licence, URL, date verified
│
├── art/                           ← YOUR art. Anything here you drew or re-skinned.
│   ├── tiles/                     ← re-skinned tilesets (mud-brick, tents, olive trees)
│   ├── characters/                ← re-costumed sprite sheets, 4-dir × 4-frame
│   ├── facesets/
│   ├── ui/
│   └── painted/                   ← Covenant's assets/art/*.jpg, copied in
│
├── audio/
│   ├── music/                     ← region beds
│   ├── sfx/                       ← footsteps per terrain, UI blips
│   └── ambience/                  ← wind, water, crowd (Covenant's procedural layer)
│
├── data/                          ← ★ CONTENT. No GDScript in this folder, ever.
│   ├── chapters/
│   │   ├── ch01_elah.json         ← nodes, lines, choices, cast, verses — both languages
│   │   ├── ch02_lions.json
│   │   └── ...
│   ├── characters.json            ← cast registry: id → sprite, faceset, name{en,zh}
│   ├── npcs/
│   │   └── elah_camp.json         ← position, patrol route, dialogue, verse granted
│   ├── quests.json
│   ├── compendium.json            ← virtues, fruits, relics, seals, callings
│   ├── mirror.json                ← 10 Journey Mirror profiles
│   ├── words.json                 ← elah.js WORDS — the four verses that become four moves
│   ├── shouts.json                ← elah.js SHOUTS
│   └── ui_strings.{en,zh}.csv     ← Godot TranslationServer CSV import
│
├── scenes/
│   ├── main/
│   │   ├── Main.tscn              ← boot, language, save load, scene router
│   │   ├── Title.tscn
│   │   └── GameOver.gd            ← there isn't one. Pillar 5. (Kept as a joke-free empty file? No — omitted.)
│   ├── world/
│   │   ├── Region.tscn            ← generic region shell: TileMap layers, Player, Camera, NPCs
│   │   ├── regions/
│   │   │   ├── ElahValley.tscn    ← authored map
│   │   │   ├── ElahCampInterior.tscn
│   │   │   └── ...
│   │   ├── Player.tscn            ← CharacterBody2D + AnimatedSprite2D + CollisionShape2D
│   │   ├── Player.gd
│   │   ├── Npc.tscn               ← patrol / escort / static behaviours
│   │   ├── Npc.gd
│   │   ├── Interactable.tscn      ← Area2D: pickup, door, trigger line, sign
│   │   └── CameraRig.gd           ← deadzone + lookahead + clamp
│   ├── story/
│   │   ├── StoryScene.tscn        ← painterly background + dialogue + choices
│   │   ├── DialogueBox.tscn       ← typewriter, faceset, nameplate, backlog
│   │   ├── DialogueBox.gd
│   │   └── BecomeTransition.tscn  ← ★ the signature moment
│   ├── setpiece/
│   │   ├── WordBattle.tscn        ← Goliath confrontation
│   │   ├── SlingMinigame.tscn
│   │   └── Moments.tscn           ← hold / tap / trace / balance / rhythm
│   ├── ui/
│   │   ├── Hud.tscn               ← virtues, quest tracker, guidance
│   │   ├── PauseMenu.tscn
│   │   ├── Journal.tscn           ← scrolls / relics / fruits / seals
│   │   ├── CharacterSheet.tscn
│   │   ├── QuestLog.tscn
│   │   ├── Mirror.tscn            ← Journey Mirror finale
│   │   └── TouchControls.tscn     ← VirtualJoystick + action buttons
│   └── hub/
│       ├── Camp.tscn              ← day/night, quest board, breathing prayer
│       └── WorldMap.tscn
│
├── scripts/                       ← ★ ENGINE. GDScript lives here.
│   ├── autoload/
│   │   ├── GameState.gd           ← save data, virtues, xp, flags, relics
│   │   ├── EventBus.gd            ← signals decoupling content from engine
│   │   ├── I18n.gd                ← language state, zh default
│   │   ├── AudioDirector.gd       ← region music, ambience, crossfade
│   │   ├── SceneRouter.gd         ← region ↔ story ↔ setpiece transitions
│   │   └── QuestLog.gd
│   ├── systems/
│   │   ├── ChapterLoader.gd       ← parses data/chapters/*.json into a node graph
│   │   ├── DialogueRunner.gd
│   │   ├── Navigation.gd          ← AStarGrid2D wrapper, patrol + escort
│   │   ├── DayNight.gd            ← CanvasModulate schedule
│   │   ├── Virtues.gd             ← courage / wisdom / compassion / faith + 4 ways
│   │   ├── BecomeController.gd    ← possession handover: sprite, nameplate, control
│   │   └── SaveMigrator.gd        ← reads Covenant v0.9.38 localStorage saves
│   └── util/
│
├── tests/                         ← headless Godot tests, run in CI
│   ├── run_all.gd
│   ├── test_chapters.gd           ← every `to`/`next` resolves, every node reachable
│   ├── test_redletter.gd          ← ★ Jesus speaks only verbatim KJV / 和合本
│   ├── test_i18n.gd               ← zh/en parity, no missing keys
│   ├── test_moments.gd            ← all moments winnable and skippable
│   ├── test_mirror.gd             ← deterministic, label-free
│   ├── test_navigation.gd         ← every NPC route is reachable (replaces `check:world`)
│   └── test_smoke_elah.gd         ← plays chapter I end to end, headless
│
├── tools/
│   ├── port-chapters.mjs          ← Covenant chapters.js/zh-story.js → data/chapters/*.json
│   ├── port-compendium.mjs
│   ├── port-mirror.mjs
│   ├── check-licenses.mjs         ← asserts every asset folder has a licence line
│   └── build-web.mjs              ← export + service worker + GitHub Pages deploy
│
├── web/                           ← PWA shell for the web export
│   ├── sw.js                      ← port Covenant's sw.js offline cache
│   ├── manifest.webmanifest
│   └── index.html                 ← Godot generates; this is your overlay
│
└── docs/                          ← PLAN.md, ART.md, ARCHITECTURE.md, FEEL.md, CONTENT.md
```

**The two hard rules:**
1. **No GDScript in `data/`.** Content authors — including a pastor or a youth leader who has never
   coded — must be able to edit a chapter without fear.
2. **No content strings in `scripts/`.** Every player-visible string comes from `data/` or
   `ui_strings.csv`. Enforced by `test_i18n.gd`.

Covenant held both disciplines for 51 commits. Losing them would be the real regression.

---

## 3. Autoloads and the event bus

`EventBus` is the seam that keeps content decoupled from engine, and it maps directly onto Covenant's
existing `core/bus.js`:

```gdscript
# scripts/autoload/EventBus.gd
extends Node

## ── World ────────────────────────────────────────────────
signal player_entered_region(region_id: String)
signal player_interacted_with(target: Node)      # NPC, pickup, door, trigger
signal item_picked_up(item_id: String)
signal verse_received(word_id: String, ref: String)

## ── Story ────────────────────────────────────────────────
signal chapter_started(chapter_id: String)
signal chapter_completed(chapter_id: String)
signal dialogue_finished(node_id: String)
signal choice_made(node_id: String, choice_index: int)
signal moment_completed(moment_id: String, kind: String)

## ── ★ The signature transition ──────────────────────────
signal become_requested(biblical_character: String)   # "david"
signal become_ended(biblical_character: String)

## ── Progression ─────────────────────────────────────────
signal virtue_changed(virtue: String, value: int)
signal way_recorded(way: String)      # step / notice / stay / wait
signal xp_gained(amount: int)
signal relic_granted(relic_id: String)
signal fruit_gathered(fruit_id: String)
signal seal_earned(seal_id: String)
signal guidance_changed(amount: int)
signal hint_used()                    # tracked SEPARATELY — never pollutes `ways`

## ── Quests ──────────────────────────────────────────────
signal quest_started(quest_id: String)
signal quest_objective_met(quest_id: String, objective_id: String)
signal quest_completed(quest_id: String)
```

> **Note `hint_used()` is its own signal.** In v0.7 Covenant fixed a real analytics bug where requesting
> a hint polluted the "ways" statistics that feed the Journey Mirror. `addHintUse()` was separated from
> `ways`. **Preserve that fix.** The Mirror is only honest if it measures unaided choices.

---

## 4. Scene flow

```
Main.tscn (boot)
   │  load save · pick language · preload audio
   ▼
Title.tscn ──► CharacterCreate ──► Camp.tscn (hub)
                                       │
                    ┌──────────────────┼──────────────────┐
                    ▼                  ▼                  ▼
              WorldMap.tscn       Journal.tscn      CharacterSheet.tscn
                    │
                    ▼
            Region.tscn  ◄──────────────────────────────┐
            (ElahValley)                                │
                    │  walk · talk · pick up 5 stones   │
                    │  cross the challenge line         │
                    ▼                                   │
          ★ BecomeTransition.tscn                       │
            letterbox · palette shift · camera push     │
            sprite crossfade pilgrim → david            │
            nameplate: 你的名字 → 大卫 / DAVID           │
                    ▼                                   │
          WordBattle.tscn  (set piece)                  │
            4 shouts × 4 verses · 5 pips · 3 hearts     │
                    ▼                                   │
          ★ BecomeTransition.tscn (reverse)             │
            "你又是你自己了 / You are yourself again"     │
                    └───────────────────────────────────┘
                    │  walk back down · onHome
                    ▼
          StoryScene.tscn — reflection · end card · "再走一步"
                    │  +relic +fruit +xp +seal
                    ▼
                 Camp.tscn  (day advances, sky changes)
```

**The field is paused underneath the battle, never rebuilt** — Covenant's `mode.js` already gets this
right, with a comment saying so explicitly:

> *"the field is paused underneath it the whole time, not rebuilt, so you come back to the exact stone
> you were standing on."*

In Godot this is trivial and correct by default: keep the region scene in the tree, `get_tree().paused`
or simply hide it under a `CanvasLayer`, and run the battle on top. **Come back to the exact stone.**
That detail is a real quality signal and it is free here.

---

## 5. Chapter data schema

Direct port of Covenant's chapter template (`docs/GAME_DESIGN.md` §6), so the converter is mechanical:

```jsonc
// data/chapters/ch01_elah.json
{
  "id": "elah",
  "num": 1,
  "roman": "I",
  "title":     { "en": "The Valley of Elah", "zh": "以拉谷" },
  "subtitle":  { "en": "Five smooth stones", "zh": "五块光滑的石子" },
  "ref": "1 Samuel 17",
  "theme":     { "en": "Courage", "zh": "勇气" },
  "paintedArt": "res://art/painted/elah-field.jpg",
  "region": "res://scenes/world/regions/ElahValley.tscn",
  "length": "10–14 min",
  "ambience": "valley",

  "scroll": {
    "verse":    { "en": "\"Fear not, stand still...\"", "zh": "「不要惧怕，只管站住……」" },
    "ref": "Exodus 14:13 (KJV)",
    "note":     { "en": "...", "zh": "..." },
    "timeline": { "en": "c. 1020 BC · the Shephelah", "zh": "约公元前1020年 · 示非拉" }
  },

  "cast": {
    "corin":   { "name": {"en":"Corin","zh":"柯林"}, "role": {...}, "sprite": "corin", "faceset": "corin" },
    "david":   { "name": {"en":"David","zh":"大卫"}, "sprite": "david", "faceset": "david",
                 "playable": true, "redLetter": false },
    "jesus":   { "redLetter": true, "faceset": "radiance" }
  },

  "start": "camp_morning",
  "endFruits": ["faithfulness"],
  "relic": "stones",

  "nodes": {
    "camp_morning": {
      "lines": [
        { "who": "",      "text": {...} },
        { "who": "corin", "text": {...} }
      ],
      "choices": [
        { "t": {...}, "to": "brook", "stat": { "courage": 2 }, "xp": 6,
          "tag": "Courage", "reply": {...} }
      ],
      "moment": { "id": "elah_hold_breath", "kind": "hold", "skippable": true },
      "next": "brook"
    }
  },

  "ending":     { "seal": "☆", "title": {...}, "text": {...}, "takeaway": {...} },
  "reflection": { "q": {...}, "options": [ /* exactly 3, each grows a virtue */ ] },
  "deeper":     { "ref": "1 Samuel 17:45", "observe": {...}, "question": {...} }
}
```

**Invariants enforced by `tests/test_chapters.gd`** (ported from `tools/validate.js`):
- every `to` / `next` resolves to a real node
- every node is reachable from `start`
- every node with gated choices also has ≥1 ungated choice — **a player can never be locked out**
- every `endFruits` entry exists in `compendium.json` and is obtainable
- every `who` exists in `cast`
- every chapter has an end node and exactly 3 reflection options
- every `redLetter: true` speaker's lines are verbatim scripture (see §7)

---

## 6. Player controller — the grid-movement contract

Detailed tuning lives in [`FEEL.md`](FEEL.md). The structural decision here:

**Move in continuous space, but snap intent to the grid.** This is what modern Pokémon does and it is
why it feels good — free 2D `CharacterBody2D` movement, with turn-in-place on direction change and a
soft magnetism toward tile centres so doorways and one-tile gaps never feel unfair.

```gdscript
# scenes/world/Player.gd  (structure, not final tuning)
extends CharacterBody2D

const TILE := 16.0

enum Mode { IDLE, TURNING, WALKING, RUNNING }

@export var walk_speed  := 60.0   # px/s  → 3.75 tiles/s
@export var run_speed   := 96.0   # px/s  → 6.00 tiles/s
@export var turn_time   := 0.07   # s — the pause before a new direction steps
@export var accel       := 900.0
@export var magnet      := 22.0   # px/s pull toward the tile centre on the crossing axis

var mode := Mode.IDLE
var facing := Vector2i.DOWN
var buffered_dir: Vector2i = Vector2i.ZERO   # ← input buffering, see FEEL.md §3

func _physics_process(delta: float) -> void:
    var intent := _read_intent()          # joystick / keys / gamepad, unified
    if intent != Vector2i.ZERO and intent != facing:
        if mode != Mode.TURNING:
            _begin_turn(intent)           # turn in place FIRST — never strafe-turn
            return
    if mode == Mode.TURNING:
        return
    _apply_movement(intent, delta)
    _apply_grid_magnetism(delta)
    _advance_animation(delta)
```

**Why `turn_time` matters more than anything else in this file:** without it, the character rotates and
moves in the same frame, which reads as *sliding*. With a ~70 ms turn-in-place, it reads as a *person
deciding to walk somewhere*. This single parameter is a large share of "feels like Pokémon."

---

## 7. The red-letter rule, enforced by machine

Covenant's most distinctive engineering contribution is that a theological commitment is enforced by a
lint rather than by memory. `tools/check-redletter.js` verifies every `jesus` / `voice` line in both
languages against a whitelist of verbatim KJV / 和合本 quotations, and the whitelist doubles as the
review checklist for a theological adviser.

Rebuilt as `tests/test_redletter.gd`:

```gdscript
## Every line spoken by a cast member with redLetter == true must appear
## verbatim in the approved scripture whitelist. No exceptions, no fuzzy match.
func test_red_letter_lines_are_verbatim() -> void:
    for chapter in ChapterLoader.all():
        for node in chapter.nodes:
            for line in node.lines:
                var speaker = chapter.cast.get(line.who)
                if not speaker or not speaker.get("redLetter", false):
                    continue
                for lang in ["en", "zh"]:
                    var text = line.text[lang]
                    assert_true(
                        Whitelist.contains(speaker.id, lang, text),
                        "Chapter %s node %s: %s speaks a line that is not in the " \
                        + "scripture whitelist (%s). Add the citation first, " \
                        + "then the line." % [chapter.id, node.id, speaker.name[lang], lang]
                    )
```

**Rule for anyone adding content:** add the scripture reference to the whitelist *first*, then the line.
If you cannot cite it, it is not Jesus speaking — make it narration, as v0.6 did for the burning bush's
*"I AM"* explanation.

Whether to depict Christ visually at all remains a decision for your pastors, not for code. Covenant
handles this with a single switch — `portraits.js` `JESUS_FACE = "radiance"`. Keep an equivalent
`data/settings.json → "portrayJesus": false` that swaps every Jesus faceset to a non-figurative light.

---

## 8. Save compatibility

Covenant players have saves in `localStorage` under a versioned key, with a `settingsVersion` migration
already implemented (v0.5 migrated `cleanMode` once, on load, then wrote back).

`SaveMigrator.gd` should read those saves on first launch of the remake and grant equivalent progress,
so **nobody who walked ten chapters loses their journey.** This is a small script and a large act of
respect. Covenant's own migration pattern — *migrate once, write back immediately, then honour the
player's choice forever* — is the correct pattern; copy it.

---

## 9. Export targets and CI

```
Web (primary)     → single-threaded WASM, gl_compatibility, GitHub Pages
                    No COOP/COEP headers needed (default since Godot 4.3) → works on iOS Safari
Android           → gl_compatibility, AAB for Play Store or APK + QR for direct
iOS               → deferred; needs a macOS runner for signing
```

**CI (GitHub Actions):**

```yaml
# .github/workflows/ci.yml — outline
on: [push, pull_request]
jobs:
  content-lints:
    # godot --headless --script tests/run_all.gd --quit
    # fails the build on: broken node links, red-letter violations, missing zh/en keys,
    # unreachable NPC routes, unwinnable moments
  web-build:
    # export, then assert the bundle size budget
    # fail if web/ > 60 MB
```

Size budgets, enforced by CI because solo developers do not notice gradual bloat:

| Target | Budget |
|---|---|
| Web (WASM + pck) | **< 60 MB** |
| Android APK/AAB | **< 120 MB** |
| First load to title | **< 8 s on 4G** |
| Region load | **< 1.5 s** |
