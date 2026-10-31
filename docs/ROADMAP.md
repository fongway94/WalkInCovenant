# Walk in Covenant — development roadmap and status

This is the working record the master directive asks for: what is done, what is
broken, what is next. `docs/AUDIT.md` holds the Phase 1 findings,
`docs/RESET-REPORT.md` the per-phase reports with evidence, and this file the
order the work is being done in.

**Evidence key** — CI = the real engine, headless, on GitHub Actions
(`tests/run_all.gd` content + `tests/smoke.gd` full playthrough). READ = proven
by reading the code, not executed. DEVICE = needs a phone; **never claimed**.

---

## The chapter as it now plays

1. **Prologue** — you wake in the valley in somebody else's clothes (5 lines).
2. **Briefing** — where you are, who the armies are, what the hands do.
3. **Corin** — the scribe who adopts you, tells you the rule of the chapter
   ("we are witnesses, not the protagonists"), and then escorts you.
4. **Three people** — a soldier holding a spear he dare not use (Deut 20:3), a
   woman handing out bread (Ps 23:1), an old man mending a strap (1 Sam 16:7).
   Each hands you one verse. The escort stops beside each of them and waits.
5. **The first look** — walking up the ridge plays the chapter's one scripted
   shot: pan to Goliath on the far slope, 1 Samuel 17:10, pan back.
6. **The line** — the witness crosses it, and nothing happens to him. 17:11,
   then Corin: *"you came to see this, you did not come to end it."* The story
   changes hands.
7. **BECOME** — the nameplate, the bars, the fade; three days earlier, the sheep
   slope, and the sling drill that teaches the one input the fight asks for.
8. **Jesse's errand** — provisions, the walk, and the brothers who want him gone
   (17:17-28).
9. **Saul** — the armour goes *on*, and the player is handed the world back
   wearing it: 42% speed, a stagger in the walk, bronze drawn over the sprite.
   The scene ends when they have actually tried to walk, or on A. Then 17:39.
10. **The brook** — the picking scene: nine stones in the water, tap to take,
    tap to put back, five wanted, a KEEP THEM button when the fifth is in the
    bag. 17:40 is spoken after the choice, because the verse reports what he
    did.
11. **The line, as David** — 17:44-45, then a real duel: telegraph, spear,
    step aside, aim, throw. Three stones, five in the pouch, no game over.
12. **The aftermath** — the giant falls and stays on screen while 17:47 is
    spoken over him; back in the valley as yourself, Corin has to hear it; then
    the ending card, the reflection question, and free roam.

---

## Done (and how it is proven)

| Area | State | Evidence |
|---|---|---|
| Viewport, scaling, safe areas, one layout authority (`ScreenFit`) | done | CI run_all `_check_layout`, 14 screen shapes |
| One tap = one action (`TapGate`, dialogue open guard, interact lock) | done | CI smoke §10 |
| NPC interaction state machine, distance, touch == mouse | done | CI smoke §3/§10 |
| Guide leads, then waits; HUD arrow follows the truth | done | CI smoke §2e |
| Dialogue box: pages, portraits, speaker, 44% cap, escape | done | CI smoke + run_all |
| Goliath is visible; scripted camera shot | done | CI smoke §1/§2g |
| The fight is a fight (dodge + throw), entered and left as a scene | done | CI smoke §6d/§7 |
| Act order follows 1 Samuel 17 (stones at 17:40, in David's act) | done | CI smoke §6c/§6c2 + run_all content gate |
| Autosave + resume into the right act | done | CI smoke §9b |
| Bilingual content, verse integrity, font coverage | done | CI run_all + check_font |
| Ending, chapter completion, seals, XP, free roam | done | CI smoke §7c/§8 |
| `MissionRunner`: missions as data, lifecycle in one place | done | CI smoke whole run + run_all mission gate |
| Saul's armour is a playable scene (weight, look, 17:39) | done | CI smoke §6c2 |
| Five stones chosen by hand at the brook | done | CI smoke §6c3 |
| Sound: 14 synthesised effects and two looping tracks | done | `tools/build_audio.py --check` in CI static gates |
| Buses and music looping declared in the project, not left to defaults | done | `default_bus_layout.tres`, `AudioDirector._loop()` |
| One control that silences the whole mix, remembered across reloads | done | smoke §1d |
| `gd_lint` refuses a duplicate class-scope `var` | done | `DUP-MEMBER` rule |

## Known gaps (honest)

| Gap | Why it is still open |
|---|---|
| How any of it *feels* on a real phone | No device and no browser in the build environment. Layout is proven geometrically, not by eye. |
| Audio mix, music transitions | SFX and music are wired; nobody has heard the mix on a phone speaker. |
| Mission *types* beyond walk/talk/drill/fight | The chapter uses four interaction shapes. More (carrying a load and being turned back, choosing stones with the verse attached) are designed in `RESET-REPORT.md` but not built. |
| `Main.gd` is still ~1,050 lines | The mission *order* and the rewards now live in data, and the HUD/guidance is generic — but this chapter's mechanics (drill, errand, armour, brook, duel) are still functions here. That is the intended split: the runner is reusable, the mechanics are this campaign's. A second campaign would add a ~200-line campaign script of its own, not edit this one. |
| Mid-act resume replays the act's opening beat | Honest and safe: the chapter, not the frame. Documented in `Main._resume_story`. |
| Chinese as a native reader would judge it | Rewritten throughout by hand; needs your ear, not mine. |

## MissionRunner — how the chapter is wired now

`scripts/systems/MissionRunner.gd` owns the lifecycle, once, for every mission:

    briefing → objective → tracking → completion → rewards (once) → next

A mission is a dictionary in `data/regions/elah.json`:

    {"id": "brook_stones", "act": "stones", "objective": "brook",
     "enter": "brook",
     "complete": {"kind": "count", "key": "stones", "at_least": 5}}

- **`enter`** names a mechanic this chapter implements (`become_david`, `errand`,
  `saul`, `brook`, `ready`). `Main` switches on that name — the runner never
  knows what a sling is.
- **Completion conditions** are two kinds on purpose: `flag` and `count`. A
  condition *language* is where mission systems go to die; anything richer is an
  interaction, and interactions belong in the mission's own code.
- **Rewards** (`xp`, `seal`, `relic`, `fruit`) are granted by the runner behind a
  save flag (`mission:<id>:rewarded`), so a reload cannot pay twice.
- **Transitions are event-driven**: `Main._story_flag()` sets a flag and ticks the
  runner in the same breath. Polling alone left a one-frame window in which the
  chapter had already ended and the runner then walked it *back* a beat — the
  exact kind of bug a dual state machine invites.
- A resumed save is "start the list at this index", so a reload replays the
  current mission's opening beat instead of dropping the player mid-scene.

The chapter list: `witness_camp → witness_line → shepherd_drill → errand →
saul_armour → brook_stones → the_line → aftermath`.

## Next, in order

1. Device pass: real phone, landscape, several aspect ratios, thumbs through the
   whole chapter. Nothing here replaces that.
2. A second region stub (Bethlehem, Ruth 1–4) with its own `missions` list, purely
   to prove the registry and the data contract, then stop.
3. The armour and the brook are the template for "unique mechanics with a shared
   spine": the next chapter's mechanics should be a campaign script that talks to
   `MissionRunner`, never a branch inside `Main.gd`.
