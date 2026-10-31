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
9. **Saul** — the armour that cannot be walked in (17:31-39).
10. **The brook** — 17:40 is spoken, and the five stones appear in the shallow
    water for the first time in the game. Five, not six.
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

## Known gaps (honest)

| Gap | Why it is still open |
|---|---|
| How any of it *feels* on a real phone | No device and no browser in the build environment. Layout is proven geometrically, not by eye. |
| Audio mix, music transitions | SFX and music are wired; nobody has heard the mix on a phone speaker. |
| Mission *types* beyond walk/talk/drill/fight | The chapter uses four interaction shapes. More (carrying a load and being turned back, choosing stones with the verse attached) are designed in `RESET-REPORT.md` but not built. |
| `Main.gd` still carries this chapter's story | ~900 lines. It is the last campaign-specific piece; a `MissionRunner` driven by a `missions` list in data is the refactor that makes campaign #2 a content change. Deliberately after the chapter is stable. |
| Mid-act resume replays the act's opening beat | Honest and safe: the chapter, not the frame. Documented in `Main._resume_story`. |
| Chinese as a native reader would judge it | Rewritten throughout by hand; needs your ear, not mine. |

## Next, in order

1. `MissionRunner` — missions as data (objective, briefing, completion,
   reward, transition) so `Main` is boot and wiring, and campaign #2 needs no
   script. This is also the fix for "the chapter is a chain of beats" if it ever
   reads that way again.
2. Two more interaction shapes in David's act: the armour *walk* (slow, clumsy,
   then take it off) and choosing the five stones by hand with 17:40 attached.
3. A second region stub (Bethlehem, Ruth 1–4) purely to prove the registry, then
   stop — no second campaign content this pass.
4. Device pass: real phone, landscape, several aspect ratios, touch through the
   whole chapter.
