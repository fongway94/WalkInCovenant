# WalkInCovenant 行走在圣约中

**A Bible story RPG you walk through.** Remake of [`Covenant`](https://github.com/fongway94/Covenant)
(v0.9.38, ~27,000 lines) rebuilt in **Godot 4.7** so that you control a character in a real tile-based
world — talk to people, follow them, take quests, gather things — and when the story arrives, **you
become the Bible character and live it.**

> **Player is witness, not author.** Your choices shape your own character. They never change the
> scriptural outcome. David still faces Goliath. Daniel still goes into the den. Jesus still calms the
> storm.

```
Status:   pre-Phase 0 — planning complete, scaffold committed
Engine:   Godot 4.7 (MIT, free)
Targets:  Web PWA → Android → iOS  (phone-first; Switch hardware explicitly out of scope)
Budget:   US$0
Team:     Solo, spare time
Content:  10 bilingual chapters inherited from Covenant, 4 shipping in v1.0
```

---

## Is "Pokémon quality" achievable?

**Yes for the feel. No for the volume.** That distinction is the whole plan.

What a player *feels* in their first twenty minutes is roughly 90% movement feel, camera, tileset art,
character animation, audio and juice — **all of it achievable solo at $0** with a real engine and one
coherent CC0 asset pack. What is not achievable is Pokémon's *content volume*: Game Freak's Switch
titles credit around a thousand people across three companies. You do not need that. Nobody plays a
Bible story game for two hundred hours. They play for the eleven minutes of the lions' den.

So the strategy is **depth over breadth**: one beautiful region, four fully-realized chapters,
thirty to forty hours of play.

Full reasoning, evidence and cost breakdown → **[`docs/PLAN.md`](docs/PLAN.md)**

---

## Documents

| Document | What it answers |
|---|---|
| [`docs/PLAN.md`](docs/PLAN.md) | Is it achievable? Feasibility, design pillars, 5 phases, 18-month timeline, $0 budget, risks |
| [`docs/ART.md`](docs/ART.md) | **The art decision.** 16×16 GBA-style pixel art, one CC0 pack (Ninja Adventure), re-skinned for ancient Israel. Includes a one-week evaluation protocol. |
| [`docs/FEEL.md`](docs/FEEL.md) | **The "Switch feel" spec.** Exact numbers for movement, turn-in-place, input buffering, grid magnetism, camera, footsteps, juice, touch controls. |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Godot project structure, scene flow, event bus, chapter data schema, red-letter lint, save migration |
| [`docs/CONTENT.md`](docs/CONTENT.md) | Porting Covenant's 27k lines by script, not by retyping. The 22 frozen author-approved lines. |

---

## What is inherited from Covenant

Nothing is thrown away. **~4,300 lines of irreplaceable content port forward**; ~13,000 lines of
hand-rolled engine and DOM UI are replaced by things Godot gives free.

| Comes across | Rebuilt |
|---|---|
| 10 bilingual chapters, ~5,300 zh characters of story | The canvas engine (`engine/`, 7,469 lines) |
| Journey Mirror — 10 profiles, 4 ways, deliberately label-free | The vector character rig (`world/rig.js`) |
| Virtues / XP / relics / fruits / seals / callings | The generated tile grid (`world/elah.js` `buildGrid()`) |
| The red-letter rule + the lint that enforces it | The DOM screens and `styles.css` |
| 4 NPCs, 4 verses, 5 stones, one real fight — the whole valley | Procedural audio score (partly kept) |
| 13 cinematic painted scenes + 7 portraits, **reused directly** | — |
| The 22 lines the author rewrote by hand — **frozen byte-identical** | — |
| 12 lint scripts — same assertions, new runner | — |

**Covenant stays live at `fongway94.github.io/Covenant/` throughout development.** The remake launches
*beside* it and only replaces it when it is demonstrably better. This is the rule
`Covenant/docs/MILESTONE-v0.9.37.md` already set — honoured here.

---

## Getting started

```bash
# 1. Install Godot 4.7.2 (standard build, NOT the .NET one) from godotengine.org

# 2. Open this folder as a Godot project — project.godot is already configured
#    for pixel-perfect rendering: 320×180 base, canvas_items stretch, integer
#    scaling, nearest filtering, gl_compatibility renderer, 2D pixel snapping.

# 3. Press F5. You should see the boot screen.

# 4. Download the art pack (the sandbox that wrote this plan could not):
#    https://pixel-boy.itch.io/ninja-adventure-asset-pack      (CC0, 89 MB)
#    https://github.com/pixel-boy/NinjaAdventure                (working Godot 4 example)
#    → unzip into assets/ninja-adventure/
```

### Then, in this order

1. ☐ Run the **[`ART.md` §4 evaluation protocol](docs/ART.md)** — one week, three packs, one identical
   test scene. Record the scores. **Do not skip this and do not pick by scrolling screenshots.**
2. ☐ Build the **Phase 0 feel test** and tick every box in
   **[`FEEL.md` §8](docs/FEEL.md)** — *on a real phone, not in the editor.*
3. ☐ **Answer the only question that matters:** does it feel good to walk?
   Tune until yes. Only then start Phase 1.

---

## Repository layout

```
project.godot          ← pixel-perfect settings, input map, autoload
scenes/main/           ← boot scene (F5 target)
scripts/autoload/      ← EventBus and friends
data/                  ← ★ CONTENT. No GDScript in here, ever.
art/                   ← ★ YOUR art — anything you drew or re-skinned
assets/                ← imported third-party packs, never hand-edited in place
audio/
tests/                 ← headless Godot tests: chapters, red-letter, i18n, navigation
tools/                 ← port-*.mjs converters from the Covenant repo
web/                   ← PWA shell for the web export
docs/                  ← the five documents above
```

**Two hard rules**, inherited from Covenant's discipline:
1. **No GDScript in `data/`.** A pastor or a youth leader who has never coded must be able to edit a
   chapter without fear.
2. **No content strings in `scripts/`.** Every player-visible string comes from `data/` or
   `ui_strings.csv`, enforced by test.

---

## The signature moment

The reason this game exists, already written in Covenant's `world/mode.js`:

> 你听见自己的心跳。然后那不像是你的心跳了。你低头，看见一双不属于自己的手，正握着一根甩石的绳子。
>
> *"You hear your own heartbeat, and then it stops being yours. You look down: the hands holding the
> sling are not your hands."*

Four people each hand you one verse on the walk up the valley. Those four verses become your four moves
in the fight. **The game does not give you a weapon the walk did not earn.**

Then, afterwards:

> *"You are yourself again."* — and you walk back down the mountain carrying what you learned.

That two-beat structure — **BECOME, then RETURN** — is the best idea in this project and it survives
the remake intact.

---

## Licence and credits

Code: to be decided by the author (MIT recommended, matching Godot and the asset packs).

> Art, audio and UI assets: **Ninja Adventure** by Pixel-Boy and AAA, CC0 1.0.
> Additional assets: Kenney (CC0), 0x72 (CC0).
> Engine: Godot 4.7 (MIT).
> Scripture: **KJV** and **中文和合本**, both public domain. Modern translations (NIV, ESV, NLT, NKJV)
> are copyrighted and are never quoted without a licence.

Whether to depict Christ visually at all is a decision for the author's pastors, not for code — a single
`data/settings.json → "portrayJesus": false` swaps every Jesus faceset to a non-figurative light.
