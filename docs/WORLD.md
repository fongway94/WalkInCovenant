# WORLD — free-roaming, revisitable, long-play

> **A correction to `PLAN.md` §1.** The plan originally argued *"nobody plays a
> Bible story game for 200 hours; they play for the 11 minutes of the lions'
> den"* and concluded depth-over-breadth. The author rejected that, correctly:
> the goal is that people **stay a long time and come to know the Bible**, and
> that requires a world worth roaming, not a sequence of short chapters.
>
> This document is the revision. It is not a contradiction of the feasibility
> analysis — it is the part of it that was under-weighted:
>
> **Exploration is the cheapest playtime in games.** Authored narrative costs
> days per eleven minutes. A traversal + collection + revisitable-scene world
> costs weeks *once* and yields hundreds of hours, because the player generates
> the play. So a free-roaming Bible world is not a bigger version of the chapter
> game — it is a *cheaper* way to reach long playtime, and it serves the mission
> (more hours in the world = more exposure to scripture) better than chapters do.

---

## 1. The shape of the world

One continuous land — the biblical world — divided into **regions** you walk
between, not menus you click through. Each region is a `data/regions/*.json`
ASCII map (see `elah.json`), so adding a place is adding a text file and some
props, never touching GDScript.

| Region | Passage anchor | Terrain identity | Set piece |
|---|---|---|---|
| **Valley of Elah** | 1 Sam 17 | dry valley, brook, camp | the fight with Goliath *(built)* |
| **Bethlehem** | 1 Sam 16 | hill town, gate, Jesse's house, the field | the anointing *(built)* |
| **The wilderness of Judea** | Ps 23, 1 Sam 24 | rocky, caves, springs | hiding from Saul |
| **Jerusalem** | 2 Sam 6–7, Neh 3 | stone paving, gates, temple court | rebuilding the wall |
| **The Jordan & Jericho** | Josh 3–6 | river, ford, walls | the march |
| **Sea of Galilee** | Mark 4, John 21 | lake, boats, reed shore | calming the storm |
| **The way to Emmaus** | Luke 24 | road, dusk lighting | the walk-and-talk |
| **Egypt & the delta** | Ex 1–14 | reeds, Nile, brick pits | the exodus road |
| **Sinai** | Ex 19–20 | high rock, snow, cloud | the mountain |
| **Babylon & the river** | Dan 6, Ps 137 | canals, palace, lions' pit | the den |

Ten regions. **Ship four.** The rest are the backlog that makes "hundreds of
hours" real, and each is cheap because the systems already exist.

### The era idea (the content multiplier)

The same land, walked in different periods. Jerusalem under David is not
Jerusalem under Nehemiah is not Jerusalem under Jesus. One map geometry, three
prop/lighting/NPC passes, three sets of scenes. **This is how a solo developer
gets a big world: reuse geometry, vary time.** It is also theologically honest —
the land is the constant; the covenants unfold across it.

Do not build eras in v1. Build the *structure* that allows them (a `era` field on
regions and NPCs) and ship one era. Revisit in v2 when there is content to fill it.

---

## 2. The systems that make staying worth it

These are what convert "a place to walk" into "a reason to keep walking".
Ordered by playtime-per-hour-of-work:

| System | Playtime yield | Cost | Status |
|---|---|---|---|
| **Traversal + surfaces** — sand slows you, fords are crossable, paths are fast | huge, free | done (`FEEL.md`, `tiles.json` surface data) | ✅ |
| **Collection: verses, relics, fruits, seals** | huge | low | ✅ GameState |
| **Revisitable scene anchors** — walk back to where a story happened; it remembers you | huge | low | ⏳ flags exist; needs anchors |
| **NPC schedules + escorts** — people move by time of day; walk with them | high | medium | ✅ patrol/follow in `Npc.gd` |
| **Day/night** — the same place is different at dusk; some scenes only at night | high | low | ✅ `CanvasModulate` |
| **Discovery %** — a region is "known" when you've walked its corners | high | low | ⏳ |
| **Bystander barks** — unnamed crowd lines that change with chapter state | medium | low | ⏳ |
| **Walk-and-talk** — an NPC talks *while* escorting you | medium | medium | ✅ follow; needs dialogue-while-moving |
| **Breathing prayer anywhere** — stop and hold; the world waits with you | medium | low | ⏳ (Covenant had it at camp only) |
| **Eras** | huge | high | ⏳ v2 |

The crucial property: **almost all of these are data or small systems, not
content.** That is why free-roaming is affordable and authored-chapter-volume is
not.

---

## 3. Revisitable scene anchors — the heart of "come to know the Bible"

Every place where something happened gets an **anchor**: a spot you can stand on
again, at any time, in any order.

- Standing on an anchor the **first** time plays the full set piece / BECOME.
- Standing on it **later** plays a short *memory*: the painted scene
  (`art/painted/*.jpg`), the key verse, and one line about what you did there.
  Ten seconds. No replay required, no lockout.
- Anchors are listed in the **Journal → Places** tab with a "you were here" mark
  and the scripture reference, one tap to fast-travel.

This is the mechanic that turns a one-pass story game into a **place you return
to** — which is the actual goal. A player who has finished chapter one can spend
an evening just walking the valley at dusk, standing where David stood, reading
1 Samuel 17:45 again. That evening is the product.

```jsonc
// data/regions/elah.json → anchors
"anchors": [
  { "id": "elah_stone", "at": [16, 12],
    "first": "become:david",
    "memory": { "art": "elah-field", "verse": "1 Samuel 17:45",
                "line": { "en": "You stood here. The cord was never yours.",
                          "zh": "你站过这里。那根绳子从来不是你的。" } } }
]
```

---

## 4. What this means for scope and order

The vertical slice (Phase 1) is unchanged and is now explicitly **region one of
a roaming world**, not a standalone chapter:

1. ✅ Systems that make roaming feel good — done this pass (movement, camera,
   collision, NPCs that move, dialogue, save, day/night, touch).
2. ⏳ Anchors + Journal-Places + fast travel — small, and it is what makes the
   world *revisitable*. **Build this before adding region two.** A second region
   without revisit is just more one-pass content.
3. ✅ Region two — Bethlehem (1 Sam 16) — built as a full chapter, walked into
   from the valley and walked out of again. That is the proof that a region is a
   file, a chapter is a script, and neither needs the engine to know its name.
4. ⏳ Discovery %, bystander barks, prayer-anywhere.
5. ⏳ Eras, in v2.

**The 18-month timeline in `PLAN.md` §5 still holds**, but its content phase now
spends its hours on *regions and anchors* rather than on additional authored
chapters. Same hours, far more playtime, and a world that rewards returning.

---

## 5. The line that was wrong, kept here on purpose

> *"Nobody plays a Bible story game for 200 hours. They play for the 11 minutes
> of the lions' den."*

The second sentence is true and remains the design test for every set piece.
The first sentence mistook the *medium* for the *motive*. People do not stay for
the lions' den; they stay because the valley is a place, and places are
returnable, and returning is how you come to know anything — scripture included.

The game is now built for the return.

---

## 5a. The three systems the brief asks for, as one panel

| Brief | Here |
|---|---|
| Quest journal | The **book** (`≡`, top-left): the chapter's current objective, the verses carried with their references, the stones, and the marks. It pauses the world and closes with one tap. |
| Inventory | Same panel: verses and stones are what the bag holds in this chapter. Relics live in the save and the ending reports them. |
| Achievements | `data/achievements.json` — six marks, each granted by `GameState.grant_seal()` at the moment it is earned (first verse, five stones, the drill, the argument, the giant, the chapter). Titles are data; the rule is platform. |

## 5b. The platform, as built

One game, many stories. `data/campaigns.json` is the registry; a campaign points
at a region file, and the shared layer — witness mode, escort, BECOME, word
battle, HUD, save, font, language toggle — runs it without knowing which story
it is. `CampaignModel.current_region()` is the single string that used to be
hardcoded in `Main.gd`.

| Shared, never per-campaign | Per-campaign, in data |
|---|---|
| Movement, camera, tile collision, day light | `grid`, `legend`, `props`, `spawn` |
| Dialogue box, portraits, choices, skip | `briefing`, `npcs[].lines/after`, `words` |
| HUD objective, waypoint arrow, role plate | `objectives`, `ending`, `triggers` |
| Escort/lead (`Npc.lead_to`) | who walks with you, `follow_after_talk` |
| Stone-and-sling fight + BECOME transition | the hero's name, his lines |
| Save/load, XP, relics, completion | — |

**Reloading mid-chapter.** `Main._resume_story()` reads the save before the
prologue: a valley with `goliath_down` set boots into the aftermath (or straight
into free roam if `elah_ended` is set). Without it, refreshing after the win
dropped you into chapter 1 with a dead giant and no way to reach the ending.

`elah` is campaign 01 and is complete through the ending. `exodus` is registered
as `available: false`: it exists so the registry has a second shape to satisfy,
and so nobody has to guess what the next story costs (one region file, one art
pass, one Chinese pass — not a rewrite).

## 6. The chapter loop, as built (Elah / David & Goliath)

This is what a player actually does, in order. Every step is asserted by
`tests/smoke.gd`, which plays the whole thing headless in CI — if a change
breaks the loop, the build goes red instead of someone's first playtest.

| # | The player | The game's job |
|---|---|---|
| 1 | **Chapter 1 — the arrival** | Five lines in the witness's own century: a bus, waking with dust in your mouth, clothes that are not yours, two armies that are not moving. Then the briefing: **you are a witness**, this is not your battle, and at the end you will *be* David. Then the controls, in phone terms. The screen comes up out of black. |
| 2 | Talks to Corin | He does not just mark a map. `follow_after_talk` turns him into an escort, and then a *guide*: `Npc.lead_to()` walks him to the next person, he stops beside them, and one toast points you at them. |
| 3 | Talks to the other three | Each hands over one verse. A toast confirms it; the HUD's ☆ counts them. `A · 交谈` prompts whenever someone is in range — and an escort never steals the prompt from the villager you walked up to. |
| 4 | Follows the arrow to the brook | Picks up five smooth stones — **for David**, which is what Corin says they are for. |
| 5 | Walks north to the line in the dust | Without five stones he refuses you and says how many you carry. With them, **BECOME**: letterbox, gold wash, the plate reads 大卫, and the nameplate changes. |
| 6 | **Chapter 2 — the shepherd slope** | Three days earlier, and the cut is a cut: half a second of black, then the slope (`ScreenFade`). Narration, then a drill: three clay jars, the same sweeping marker the fight uses, a band that narrows with each jar (no penalty for missing). It exists so the fight's single input is learned before the giant is in frame. |
| 6b | **Chapter 4 — Jesse's errand** | Three provisions spawned in Bethlehem, a real objective line (`父亲给的东西 1／3`), the walk to the camp, Eliab's accusation at the brothers' post. |
| 6c | **Chapter 4b — the king's tent** | Saul is spawned into the camp as a person (`Region.spawn_npc`), the HUD points at his tent, and you walk to him. 1 Samuel 17:31-39 plays: he says you cannot go (17:33), you answer with the lion and the bear (17:37), the armour goes on (17:38) and comes straight off (17:39). Then the line is yours to walk to — crossing it while `Act.READY` starts the fight, with no dialogue in between to click through. |
| 7 | Fights Goliath | One exchange per verse you carry (2–4 rounds), then **the fight proper**: he telegraphs and strikes (press A to dodge), then the sling sweeps (press A in the gold band to throw). `GoliathFight` — three stones land, missed dodges cost *nerve*, never the story. |
| 8 | **Chapter 6 — the aftermath, witnessed** | RETURN gives the valley back to the witness; Corin has something new to say (`after_win`), and only after he has said it does the ending card, the reflection question and three answers play. |
| 9 | Free roam | Objective reads `本章完成`. Walking back over the line gives the memory beat once. Four **curios** — the brook, the altar, the olives, a man mending a tent — say one sentence each, once, and never appear in a list. |

Every box also carries a visible `»»` skip in its header and honours Escape: it
jumps to the last line of the beat and a second press closes it **through the
same on_done**, so skipping can never eat the beat that follows it. Playtests 5,
6 and 7 each asked for that in their own words.

### 6.0 Three bugs, and where each one actually lived

| Report | Root cause | Fix | Gate |
|---|---|---|---|
| "Every time I click an NPC the dialogue appears three times" | One tap can arrive as **two** events (a touch and the action the on-screen A button synthesises). The tap that *closed* a box was then read by `Region._unhandled_input` as a fresh interaction, so the conversation restarted from line one. `Npc.talk()` would also happily replace a box that was already open. | `DialogueBox` emits `closed`; `Region` ignores the A button for 0.35 s after it, and `Npc.talk()` refuses while a box is up. | `tests/smoke.gd` presses A twice on every one of the four NPCs and asserts the beat id does not change, then that the closing tap leaves the lock set. |
| "The quest item cannot be seen on the map" | The first provision was placed at (12,45) — inside the solid `altar_stones` prop — and all three were 35 tiles south of where becoming David left you, off camera. The sprite is also 10 px of brown on brown mud. | Provisions moved to free tiles (14,45), (18,45), (16,42); the errand now begins at (16,45) with a camera snap; unclaimed pickups draw a bobbing chevron and a ground ring, gold for quest items, pale for stones. | `tests/run_all.gd` fails if any `david_act.items`, `brothers_at` or `start_at` tile is solid or unreachable; `smoke.gd` asserts every provision is within six tiles of the errand start. |
| "The screen suddenly becomes smaller with a black frame" | `window/stretch/scale_mode="integer"`. Integer scaling can only pick whole numbers, so a few pixels of window change (address bar sliding away, rotate, resize) drops the factor by a whole step and the canvas shrinks inside black bars. | `scale_mode="fractional"` (nearest filtering and `snap_2d` were already on, so the pixels stay crisp). | `tests/run_all.gd` `_check_display()` fails the build if `scale_mode` is ever set back to integer or `aspect` is not `expand`. |

### 6.1 Why the player is not David until step 5

The mission and the role had to stop contradicting each other (playtest 6: *"i am
朝圣者 or david? if i am not david then why i am given mission to pick the rock?"*).
The answer is now stated twice, in-fiction and in the HUD line:

* Corin, at the start: we are only witnesses; we cannot change the ending.
* The stones are carried **for** the boy at the brook, not for you to throw.
* At the line, the pilgrimage stops being observation: `BecomeController` hands
  you his hands, and the HUD nameplate becomes 大卫 for the length of the fight.

### 6.2 The interaction contract (and the bug that broke it)

`Input.action_press()` updates an action's *state*; it does **not** put an
`InputEvent` into the pipeline. The on-screen A button used it, and `Region` and
`DialogueBox` both listen for `event.is_action_pressed("interact")` — so on a
phone the A button moved a thumb and nothing else. "Cant talk with npc" was that
one line. Touch controls now synthesise a real `InputEventAction` through
`Input.parse_input_event()`, and the A/RUN buttons are drawn **always** rather
than only while the stick is held (they were invisible until you touched the
screen).

Rules that follow from it:

* Anything that can be pressed must produce an event, not just a state.
* Every control a phone player needs must be visible before they touch anything.
* A prompt appears where the action is possible, not in a manual.
