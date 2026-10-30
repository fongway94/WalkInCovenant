# WalkInCovenant — Master Plan

> **The question that started this:** *"Is it achievable to remake Covenant like a Pokémon game on
> Nintendo Switch — where you control a character, do quests, follow NPCs, interact, and then when the
> story comes, you become the Bible character and live it?"*
>
> **The answer:** Yes for the *feel*. No for the *volume*. This plan is built entirely around that
> distinction, because confusing the two is how solo projects die.

**Constraints locked by the author (2026-10-30)**

| Constraint | Decision |
|---|---|
| Engine | **Godot 4.7** (free, MIT) |
| Budget | **US$0** |
| Team | **Solo, spare time** (assume 8–12 h/week) |
| Primary platform | **Phone** — web PWA + Android + iOS |
| Quality bar | *"Switch-quality feel"*, not Switch hardware |
| Predecessor | [`fongway94/Covenant`](https://github.com/fongway94/Covenant) v0.9.38 — **content and systems are reused, presentation is rebuilt** |

---

## 1. Feasibility, honestly

### 1.1 What "Pokémon quality" is actually made of

Players cannot tell you what makes a Pokémon game feel good, so they say "graphics." They are wrong.
Break it down and the cost distribution looks like this:

| Layer | Share of perceived quality | Solo achievable? |
|---|---|---|
| **Movement feel** — grid-snapped walking, turn-in-place before moving, acceleration, run button | ~15% | ✅ Yes, fully |
| **Camera** — smooth follow, deadzone, lookahead, room-based transitions | ~10% | ✅ Yes, fully |
| **Tileset art & autotiling** — coherent terrain, edges, transitions | ~25% | ⚠️ Yes *only* with a free pack, re-skinned |
| **Character art & animation** — 4-dir walk/idle/run, facesets, expressions | ~20% | ⚠️ Yes *only* with a free pack |
| **Audio** — footsteps, UI blips, 30+ music tracks, ambient beds | ~10% | ✅ Yes (Ninja Adventure ships 37 tracks + 100 SFX, CC0) |
| **Juice** — screen shake, particles, tweened UI, hit-stop, weather | ~10% | ✅ Yes, fully |
| **Content volume** — hundreds of hours, 8 regions, 400 creatures | ~10% | ❌ **No. Never, solo, at $0.** |

The first six layers total roughly **90% of what a player *feels* in the first 20 minutes**, and all
six are achievable. The seventh is what you cannot have, and — critically — **you do not need it**.
Nobody plays a Bible story game for 200 hours. They play for the 11 minutes of the lions' den.

> **The strategic conclusion: depth over breadth.** One beautiful region, four to six fully-realized
> chapters, thirty to forty hours of play — not ten thin ones. Covenant already has ten chapters.
> The remake ships with **four** and earns the right to add more.

### 1.2 The two hard truths

**Truth #1 — Art is your bottleneck, not code.**
You have already proven you can write the code: Covenant is ~27,000 lines with twelve green lints.
What you have never had is a coherent art set. `rig.js:51` literally reads `export const SHEETS = {}` —
you built the hook for real sprite sheets and there was nothing to put in it. At US$0 the only route to
coherent art is a **single complete CC0 pack, re-skinned**, never a mashup of five packs. See
[`ART.md`](ART.md).

**Truth #2 — Your own README already diagnosed this and was wrong about the cause.**
Covenant's `docs/GAME_DESIGN.md` argues *"不使用游戏引擎"* — that engines don't make art better. That
was **correct in 2024 for a text-and-choice PWA**, and it is the reason the art stayed flat. It is
**wrong for what you are building now.** The moment you need tile collision, NPC pathfinding, animation
state machines, camera rules, day/night lighting and a scene editor, hand-rolling them costs you the
months you should be spending on content. Godot's TileMap, AStarGrid2D, AnimationTree, Camera2D and
PointLight2D are exactly the things you were rebuilding badly in `field.js`.

### 1.3 What specifically felt low quality (evidence from the code)

Diagnosis of `Covenant/src/world/`, so the remake fixes causes and not symptoms:

| # | Finding | Evidence | Remake fix |
|---|---|---|---|
| 1 | Characters are **procedurally drawn vector figures** — lines and arcs from a palette, not art | `rig.js` `drawActor()`, `SHEETS = {}` empty | Real 16×16 sprite sheets + `AnimatedSprite2D` |
| 2 | Tiles are **flat colour + three hashed noise specks** | `field.js` `drawTile()`, `COL.grassA/grassB` | TileSet with terrain autotiling and edge transitions |
| 3 | **NPCs never move** — "follow NPC" is not weak, it is absent | `field.js:64` `entities = NPCS.map(n => ({...n}))`; positions static forever | `AStarGrid2D` paths, patrol routes, escort behaviour |
| 4 | **Reachability exists but is test-only** | `elah.js:72` `reachable()` BFS, imported by no runtime code | Same BFS logic becomes Godot navigation, used at runtime |
| 5 | **No footstep audio, no idle/run/turn states** | `grep sfx( src/world/*.js` → only `battle.js` and `mode.js` | Per-terrain footstep SFX, 6+ animation states |
| 6 | **No lighting** — flat full-bright everywhere | no `Light2D` anywhere | `CanvasModulate` + `PointLight2D` for torches and time of day |
| 7 | Map is **generated from stamps in code**, so it cannot be art-directed | `elah.js` `buildGrid()` | Authored `.tscn` maps painted in the Godot editor |

**But note what was *right*:** the `elah.js` (content) / `field.js` (loop) / `rig.js` (draw) split is
clean, and the design idea — *four people each hand you one verse, and those four verses become your
four moves in the fight* — is genuinely excellent and ports forward unchanged. The architecture was not
the problem. The art pipeline and the missing engine were.

---

## 2. Design pillars

Inherited from Covenant's GDD, sharpened for a walking game. When two options conflict, the higher
pillar wins.

1. **Presence over information.** You have a body in the place. You walk, you wait, you carry.
2. **Witness, not author.** Your choices shape *your* character. They never change the scriptural outcome.
3. **The world teaches the verse.** Every mechanic is a physical form of a spiritual truth — the walk up
   the valley *earns* the four words you fight with. Nothing is a decoration bolted on.
4. **Switch feel on a phone.** Grid movement, turn-in-place, snap camera, crunchy audio. Non-negotiable.
5. **Formation over winning.** No game-over screens, no wrong reflections. The scoreboard is four virtues.
6. **Short sessions.** 8–15 minutes per chapter. One bus ride.
7. **Offline and free.** No account, no ads, no paywall between a person and Scripture.
8. **Red-letter discipline.** Jesus speaks only verbatim KJV / 和合本. `check:redletter` is rebuilt in Godot.

---

## 3. The core loop

```
        ┌──────────────────────────────────────────────────────────┐
        │                                                          │
   OVERWORLD ──► NPC / QUEST ──► STORY SCENE ──► BECOME ──► SET-PIECE
   walk, look,   talk, follow,   dialogue,       possess   mini-game
   gather,       escort, trade   choose, pray    a Bible   or word-battle
   day/night                     virtues rise    character      │
        ▲                                                        │
        │                                                        │
        └──────── REFLECTION ◄── RETURN ◄────────────────────────┘
                  verse card,    you are
                  +relic +fruit  yourself again
```

**The "BECOME" transition is the remake's signature moment** and the thing your v0.9.x world mode
already reached for in `mode.js`:

> *"You hear your own heartbeat, and then it stops being yours. You look down: the hands holding the
> sling are not your hands."*

That line is the whole game. The remake makes it **cinematic**: the overworld letterboxes, the palette
shifts, the camera pushes in on your pilgrim, the sprite cross-fades into David's, the HUD nameplate
changes from your name to **大卫 / DAVID**, and control hands over. Then it hands back — *"You are
yourself again"* — and you walk down the mountain carrying what you learned. Keep that exact
two-beat structure. It is your best idea.

---

## 4. Roadmap

### Phase 0 — The Feel Test · **2 weeks · M1**

> **Goal: prove the walk feels like Pokémon, before writing one line of game.**
> If this fails, nothing else matters and we change approach. Do not skip ahead.

Deliverables:
- Godot 4.7 project scaffolded with correct pixel-perfect settings (done — see `project.godot`)
- Download and evaluate CC0 asset packs; pick **one** (protocol in `ART.md`)
- One 40×30 tile test map with terrain autotiling
- Player character: 8-directional or 4-directional grid movement, **turn-in-place first, then step**
- Run button (hold), walk/run speed difference, footstep SFX per terrain
- Camera with deadzone + lookahead, clamped to map bounds
- Virtual joystick (touch) **and** keyboard/gamepad — both feel identical
- One NPC that patrols a route; walking into them starts dialogue
- Day/night `CanvasModulate` slider to preview lighting

**M1 exit test:** put the build on your phone. Walk for two minutes without a goal.
*Does it feel good to walk?* If no → tune until yes. Do not proceed until yes.

---

### Phase 1 — Vertical Slice: Valley of Elah · **8–12 weeks · M2**

> **Goal: one chapter, complete, at target quality.** This is the asset you show a pastor, a youth
> group, and a potential collaborator. Everything after this is repetition.

`elah.js` already contains nearly all of this content — it ports almost 1:1.

Deliverables:
- **Region: the Valley of Elah** — Israelite camp at the south, road climbing north, brook with a ford,
  dry ground where the giant waits (map authored in Godot, not generated)
- **4 NPCs**, each handing over one verse (Corin, the young soldier, the woman at the tent, the old
  soldier) — dialogue ported verbatim from `elah.js` `NPCS`, both languages
- **5 smooth stones** at the brook, picked up by walking over them
- **The challenge line** — crossing north with fewer than 5 stones gently refuses you (no fail state)
- **BECOME transition** → the word-battle with Goliath (port `battle.js`: he shouts one of four kinds
  of taunt, you answer with the matching verse, 5 pips of bluster, 3 hearts of nerve)
- **RETURN transition** → *"You are yourself again"* → walk back down → chapter complete
- Dialogue box system: typewriter, faceset portraits, nameplate, advance on tap, backlog
- Quest tracker UI (3 objectives, ticked off live)
- Save/load, language toggle (zh default / en), pause menu
- Ported procedural audio *or* Ninja Adventure music beds — decided in Phase 0
- **Godot headless smoke test** that plays the whole chapter (replaces `tools/smoke.js`)

**M2 exit test:** ten people from a youth group play it on their phones unaided.
Three questions after: *What story do you remember? Did anything make you think? Would you play
another chapter tomorrow?* Fix the top three confusions. **This is Covenant's own Phase 1 plan and it
is still the right one.**

---

### Phase 2 — Systems that scale · **6–8 weeks · M3**

> **Goal: make chapter two cost a tenth of chapter one.** Build the machine before the product.

- **Content-as-data pipeline**: a chapter is a `.json`/`.tres` bundle (nodes, cast, verses, rewards),
  not GDScript. Volunteers can write chapters without touching code.
- **Port the content converter** — `tools/port-chapters.mjs` reads Covenant's `chapters.js`,
  `chapters-extra.js`, `zh-story.js` and emits Godot resources (see `CONTENT.md`)
- **Quest system** — multi-stage, tracked, journal UI
- **NPC scheduler** — time-of-day positions, patrol routes, escort/"follow me" behaviour,
  `AStarGrid2D` repathing when the player blocks a doorway
- **Virtues / XP / Guidance / relics / fruits / seals** — port `compendium.js` and `state.js`
- **Camp hub** — port the day/night cycle, breathing prayer, satchel, quest board
- **Journey Mirror** — port `mirror.js` (10 profiles, 4 ways, label-free) as the ending
- **Accessibility** — text size, `prefers-reduced-motion` equivalent, colourblind-safe virtue colours,
  one-handed reach, full screen-reader labels on UI
- **Rebuild the twelve lints** as Godot headless tests: `check:copy`, `check:i18n`, `check:redletter`,
  `check:moments`, `check:mirror`, `check:world`, `smoke`

**M3 exit test:** author chapter two (the lions' den) **without writing GDScript** — only data and maps.
If that works, the machine is real.

---

### Phase 3 — Content · **6–12 months, ongoing · M4**

> **Goal: four to six chapters at target quality. Not ten at half quality.**

Recommended ship order — chosen for mechanical variety and for reuse of art:

| # | Chapter | Passage | Why here | Reuses from Covenant |
|---|---|---|---|---|
| I | **The Valley of Elah** | 1 Sam 17 | The vertical slice. Desert/camp art. | `elah.js`, `battle.js`, `games.js` sling |
| II | **The Lions' Den** | Dan 6 | Interior + prison art, night lighting, a *waiting* mechanic | `chapters.js` lions, 20-moment hold |
| III | **The Road to Jericho** | Luke 10:25–37 | Road/desert reuse, escort-then-tend, compassion | `chapters.js` jericho |
| IV | **Peace, Be Still** | Mark 4:35–41 | Water tiles, boat interior, weather VFX, red-letter chapter | `chapters.js` storm |
| V *(stretch)* | **For Such a Time** | Esther 4–5 | Palace interior, court walk, rhythm-of-steps | `chapters.js` esther |
| VI *(stretch)* | **The Far Country** | Luke 15:11–32 | Farm/village reuse, the long walk home | `chapters.js` prodigal |

Cut for v1.0 (keep in Covenant's web build, return later): burning bush, Ruth's field, Jonah's deep,
Zacchaeus' tree. Each needs bespoke art you cannot afford yet.

**M4 exit test:** a full playthrough of four chapters, both languages, on a mid-range Android phone,
under 30 minutes of loading total, no crashes.

---

### Phase 4 — Ship · **4–6 weeks · M5**

- **Web PWA first** — Godot single-threaded web export (default since 4.3, so **no SharedArrayBuffer
  headers needed and it works on iOS Safari**), service worker, add-to-home-screen.
  Keep Covenant's GitHub Pages workflow.
- **Android** — Godot native export → Play Store (or direct APK + QR code, as Covenant does today)
- **iOS** — needs a Mac for signing; use a GitHub Actions macOS runner (Covenant's own
  `MOBILE_DEPLOY.md` already plans this)
- **Bundle budget: under 60 MB web / under 120 MB native.** Enforce it in CI. Pixel art at 16×16 makes
  this easy — this is a real advantage over Godot's typical 40 MB WASM baseline plus assets.
- Store listings, privacy policy (collect nothing), a share-card generator for WhatsApp — *the single
  most effective growth loop for a faith app*
- Soft launch in Malaysia for two weeks, then widen

**Switch hardware is explicitly out of scope.** Godot has no first-party console export; it requires
Nintendo Developer Portal approval, a dev kit, and a paid porting partner (W4 Games / RAWRLAB) at
roughly **US$10k–50k per platform**. Revisit only if the game earns it.

---

## 5. Timeline, realistically

Assuming **8–12 hours/week, solo, US$0**:

| Phase | Weeks | Cumulative | Milestone |
|---|---|---|---|
| 0 — Feel Test | 2 | ~1 month | M1: it feels good to walk |
| 1 — Vertical Slice | 8–12 | ~4 months | M2: one chapter, playable, tested on 10 people |
| 2 — Systems | 6–8 | ~6 months | M3: chapter two costs a tenth as much |
| 3 — Content (4 chapters) | 24–48 | ~12–18 months | M4: four chapters at quality |
| 4 — Ship | 4–6 | ~18 months | M5: public, free, on phones |

**Plan for 18 months to v1.0.** Not 3. The failure mode of solo game development is not running out of
ideas — it is compressing this table by half and quitting at month 7 when the truth arrives.

Two rules that make this survivable:
1. **Every milestone is playable.** No "engine work" phase that produces nothing you can hand someone.
2. **Covenant stays live the whole time.** The old web build at
   `fongway94.github.io/Covenant/` keeps serving players. The remake launches beside it, and only
   replaces it when it is demonstrably better. Nothing is deleted. (This is exactly what
   `MILESTONE-v0.9.37.md` already prescribes — honour it.)

---

## 6. Budget: US$0, itemised

| Need | Source | Cost |
|---|---|---|
| Engine | Godot 4.7 (MIT) | $0 |
| Tilesets, characters, facesets, monsters, UI | **Ninja Adventure** by Pixel-Boy & AAA — CC0, 16×16, 50+ animated characters, 89 MB | $0 (pay-what-you-want) |
| Backup / alternative packs | Kenney (CC0), 0x72 Dungeon Tileset II (CC0), Pixel Frog (CC0) | $0 |
| Music | Ninja Adventure ships 37 tracks; or port Covenant's procedural Web Audio score | $0 |
| SFX | Ninja Adventure ships 100+; plus Freesound CC0 filter | $0 |
| Pixel editor | **LibreSprite** (free, open-source Aseprite fork) or **Piskel** in-browser | $0 |
| Map editor | Godot's built-in TileMap + terrain sets | $0 |
| Fonts | Covenant already subsets Noto Sans Symbols (OFL); add a CC0 pixel font for Latin | $0 |
| Hosting | GitHub Pages (already working) | $0 |
| Android publishing | Play Console one-time fee | **$25** *(only unavoidable cost; optional if you ship APK + QR)* |
| iOS publishing | Apple Developer Program | **$99/yr** *(defer — web PWA + Android first)* |

**Realistic total to a public, playable game: $0–25.**

Where $0 genuinely costs you: **no bespoke art.** The biblical world will be built by *re-skinning* a
Japanese-ninja-themed pack — mud-brick houses redrawn over pagoda tiles, olive trees over bamboo. At
16×16 a house is ~32×32 pixels, so this is feasible by hand in LibreSprite, but it is the single
biggest time sink in the plan and it is scheduled accordingly. If money ever appears, **the first
US$300 should buy a custom tileset**, not marketing.

---

## 7. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| **Art never reaches the bar** | 🔴 High | One CC0 pack only; shared palette; re-skin rather than mix; `ART.md` evaluation protocol before any map work. If M1 still looks bad, stop and reconsider before Phase 1. |
| **Scope creep** — "just one more system" | 🔴 High | Ship four chapters, not ten. Cut list is written above and is binding. Every new system must pass *"does this make a Bible story land harder?"* |
| **Solo burnout** | 🔴 High | 8–12 h/week is the plan, not the fallback. Every milestone is playable so you get dopamine regularly. Covenant stays live so there is no all-or-nothing moment. |
| **Godot web export on iOS Safari** | 🟡 Med | Single-threaded export is the default since 4.3 and needs no COOP/COEP headers. Test on a real iPhone in Phase 0, not Phase 4. |
| **Bundle size blows past 100 MB** | 🟡 Med | 16×16 pixel art is tiny; enforce a size budget in CI; audio is the real risk — stream music, don't preload. |
| **Doctrinal disagreement** | 🟡 Med | Witness-not-author rule, public-domain translations only, reference shown in every chapter, `check:redletter` enforced by lint, review by leaders from two traditions. |
| **Copyright on modern translations** | 🟡 Med | KJV and 和合本 are public domain. **Never** quote NIV/ESV/NLT/NKJV without a licence. |
| **"Games trivialise the Bible"** | 🟡 Med | Keep reflection, show the real passage at the end, never reward "beating" a Bible character. Playtest with pastors early — in Phase 1, not Phase 4. |
| **Losing 27k lines of working content** | 🟢 Low | Nothing is deleted. Covenant stays published. Content ports by script (`CONTENT.md`), not by retyping. |

---

## 8. Immediate next actions

In order. Do not parallelise — each one de-risks the next.

1. ☐ Install **Godot 4.7.2** (godotengine.org) — standard build, not .NET
2. ☐ Open this repo as a Godot project. It should import cleanly; `project.godot` is already configured.
3. ☐ Download **Ninja Adventure** from `pixel-boy.itch.io/ninja-adventure-asset-pack` (CC0). Also
   clone `github.com/pixel-boy/NinjaAdventure` — a working Godot 4 example project worth studying.
4. ☐ Run the **`ART.md` evaluation protocol** — one week, three packs, one identical test scene.
5. ☐ Build the **Phase 0 feel test**. Export to web. Open it **on your phone**.
6. ☐ **Answer M1:** does it feel good to walk? Tune until yes. Only then start Phase 1.

---

*Companion documents: [`ART.md`](ART.md) · [`ARCHITECTURE.md`](ARCHITECTURE.md) ·
[`FEEL.md`](FEEL.md) · [`CONTENT.md`](CONTENT.md)*
