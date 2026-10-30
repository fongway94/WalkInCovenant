# Playtest #9 — inspection, plan, and what has landed

Written before touching the code, then kept up to date as the work was done.
Rule 9a of the playtest: **inspect and report before rebuilding.** This is that
report. Nothing below claims a fix that CI has not run.

Live build: <https://fongway94.github.io/WalkInCovenant/> — run `41094937423`, green.

---

## 1. What is already here (inventory, not a wish list)

The project is not empty, and nothing in it was thrown away for playtest #9.

| Layer | Files | What it actually is |
|---|---|---|
| Autoloads | `EventBus`, `GameState`, `I18n`, `AudioDirector` | typed signals, one save file, zh-default with an EN toggle, generated audio |
| Story | `RegionModel`, `DialogueBox`, `Npc` (359 lines) | content-as-data regions, a box that types out and never blocks, state-aware NPCs with `before`/`after` lines |
| World | `Region`, `TerrainLayer`, `Player`, `CameraRig` | 16 px tiles, tile-collision, walk-in-any-direction, camera follow with dead-zone |
| Systems | `CampaignModel`, `BecomeController` | campaigns as data; a generic two-mode controller (Witness ↔ biblical character) |
| Setpieces | `GoliathFight`, `SlingPractice`, `WordBattle` | three playable scenes, all drawn by code, all tested headless |
| UI | `Hud`, `Journal`, `ScreenFade`, `TouchControls`, `WaypointArrow` | objective line, one-screen book, fade transitions, on-screen stick + A, next-step arrow |
| Content | `data/regions/elah.json` (31 KB) | the whole of David & Goliath, bilingual, every verse 和合本 + KJV |
| Gates | 8 python tools + `run_all.gd` (58 checks) + `smoke.gd` (116 checks, 20 sections) | nothing reaches `main` without them |

Working, and confirmed by the smoke run: walk, talk, collect, trigger, both
modes, the fade, the drill, the duel, the journal, the seals, the ending, and
the save.

## 2. The four things you reported

**(a) "interact A until all done."** The interaction was real, but the *story*
was not physical: the king spoke from a card the moment the brothers finished.
Fixed in `f4ccc08` — `Region.spawn_npc()` puts Saul in the camp when the story
reaches him, the HUD points at his tent, and 1 Samuel 17:31 ("they brought him
before Saul") is now a walk you actually make before the armour scene.

**(b) "inconsistent chinese."** Audited every bilingual string in `data/` for
(a) Chinese sitting in an English field, (b) glyphs the font cannot draw,
(c) a line that overflows the box. All three are now gates, and all three are
clean: `check_font` 677 codepoints, `check_text_fit` at 4 rows, and a new check
that curio lines are `{en, zh}`. Two font rebuilds were needed because new text
added new characters (`ba0a01b`) — that is the audit working, not the audit
failing.

**(c) "the fight needs dodge + throw."** `79015d9` replaced the old
press-to-swing loop with a real duel: a red telegraph you must **dodge** inside
a 0.78 s window, then a gold band you must **throw** at, three hits to win, five
stones in the pouch (the brook resupplies), and nerve that drops when you are
hit but never ends the game. Steps get tighter each round.

**(d) "the game feels empty."** Four **curios** now sit in the valley — the
brook, the altar, the olives, a man mending his tent — one sentence each, once
ever, never listed anywhere. They are found, not handed over. `008791d`
`8dea4f8` fixed the two that were standing inside props.

## 3. Things found during the inspection that you had not reported

- The `≡` journal button was 22×14 px — under the thumb target. Now 28×18 (`942a0da`).
- Curio tiles could sit inside solid props, and two curio tiles shared a pickups
  tile, so a curio's box paused the world before a stone was collected. Both are
  now checked in `run_all`, and the test clears the box first.
- `run_all`'s curio validation compared a string to an object and would have
  passed a curio with a broken label. Fixed before it shipped a bad line.

## 4. What is deliberately *not* done

- **No second campaign.** The registry takes one (`data/campaigns.json`), the
  systems are generic, but shipping Moses as a stub would be exactly the
  "incomplete mechanic disguised as finished" the brief forbids.
- **No new art.** The last art change predates your last two reports and none of
  those reports mentioned art, so the sprites are untouched rather than churned.
- **No verse paraphrase anywhere.** Where a beat is invented (the prologue, the
  curios, Corin) it is narration or a witness speaking, never Scripture, and
  never presented as canon. Every quoted line carries its reference.

## 5. What to look at next time you play

1. Does the walk to the king's tent feel like a step in the story, or a chore?
2. Is the dodge window fair on a phone? (Red = dodge, gold = throw.)
3. Do the four curios read as discoveries — or do you want a map marker?
4. Any line of Chinese that still reads translated rather than written.
