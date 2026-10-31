# Asset provenance and licences

> **This file is committed even though the asset packs are git-ignored.**
> It is the record of where every third-party asset came from and under what
> terms. Update it the day you add a pack, not the day you ship.
>
> Licences below were checked on **2026-10-30**. Authors change terms — re-verify
> before any public release, and record the new date here.

---

## Planned

| Pack | Author | Licence | Source | Unzip to | Checked |
|---|---|---|---|---|---|
| **Ninja Adventure Asset Pack** | Pixel-Boy & AAA | **CC0 1.0 Universal** — commercial use allowed, attribution not required (but give it) | `pixel-boy.itch.io/ninja-adventure-asset-pack` (89 MB, pay-what-you-want) | `assets/ninja-adventure/` | 2026-10-30 |
| **Ninja Adventure — Godot 4 example project** | Pixel-Boy | CC0 (assets); study the structure | `github.com/pixel-boy/NinjaAdventure` | reference only, do not vendor | 2026-10-30 |
| Kenney (Tiny Town / RPG packs) | Kenney Vleugels | **CC0** | `kenney.nl/assets` | `assets/kenney/` | 2026-10-30 |
| Dungeon Tileset II | 0x72 | **CC0** — "use this tileset for whatever you like" | `0x72.itch.io` | `assets/0x72/` | 2026-10-30 |
| Tiny Swords / free packs | Pixel Frog | **CC0** (free packs specifically) | `pixelfrog-assets.itch.io` | `assets/pixelfrog/` | 2026-10-30 |

### ⚠️ Verify before use — licence is NOT clearly CC0

| Pack | Author | Concern |
|---|---|---|
| Sprout Lands | Cup Nooble | Free tier has historically been **non-commercial**. Check the current page before touching it. |
| Cute Fantasy RPG | LimeZu | Free tier — confirm what it covers and whether commercial use is permitted. |
| Serene Village | — | Confirm licence and whether the free tier permits commercial use. |
| CraftPix freebies | CraftPix | Usually personal/non-commercial, and typically forbids redistributing raw files. |

**Never use a CC BY-NC or share-alike (CC BY-SA / GPL) asset.** NC blocks any monetised release;
share-alike terms can extend to your whole project and conflict with shipping closed-source.

---

## Inherited from Covenant (already owned, reuse freely)

| Asset | Source | Licence |
|---|---|---|
| 13 cinematic scene images (`assets/art/*.jpg`, 848×1264) | `fongway94/Covenant` | Project's own — reuse directly for cutscenes and chapter cards. See `docs/ART.md` §8. |
| 7 character portraits (`assets/art/portrait-*.jpg`) | `fongway94/Covenant` | Project's own |
| 14 cut-out sprites (`assets/art/sprites/*.webp`) | `fongway94/Covenant` | Project's own — used for set pieces, not the overworld |
| `covenant-symbols-a.woff2`, `covenant-symbols-b.woff2` | subsetted from **Noto Sans Symbols 1 & 2** | **SIL Open Font License 1.1** — `assets/fonts/OFL-Noto-Symbols.txt` must ship alongside |

> ⚠️ **AI-generated images.** Covenant's scene art was produced with image models and post-processed by
> `tools/process-art.py` and `tools/cutout.py`. If any of it is reused, confirm you hold the rights per
> the terms of the model/service used, and disclose it where a store listing asks. Note also that
> Ninja Adventure explicitly states **"No generative AI was used"** — do not mix AI-generated sprites
> into a CC0 pack and claim the pack's provenance for the result.

---

## Scripture

| Text | Use | Status |
|---|---|---|
| **King James Version (KJV)** | English scripture quotations | Public domain |
| **中文和合本 (Chinese Union Version)** | Chinese scripture quotations | Public domain (1919) |
| NIV, ESV, NLT, NKJV, CSB, NASB | — | ❌ **Copyrighted. Never quoted without a licence.** Paraphrase and cite the reference instead. |

---

## Engine and tooling

| Tool | Licence |
|---|---|
| Godot Engine 4.7 | MIT |
| LibreSprite | GPL-2.0 (a *tool* — its licence does not touch your output) |
| Piskel | Apache-2.0 (a tool) |
| Noto Sans SC | SIL OFL 1.1 |
| Node.js (`tools/` only) | MIT |

---

## In-game credits screen

CC0 does not require attribution. **Credit them anyway** — it costs one scene, it is the right thing to
do, and these are independent artists who released excellent work for free.

```
WalkInCovenant

Art, audio and UI assets
  Ninja Adventure — Pixel-Boy and AAA · CC0 1.0
  Additional assets — Kenney · 0x72 · Pixel Frog · CC0

Engine
  Godot 4.7 · MIT

Scripture
  King James Version · 中文和合本 · public domain

Built on Covenant (2024–2026) by the same author.

"This game does not let you rewrite the Bible. It lets you stand there."
```

---

## Adding a pack — checklist

1. ☐ Read the licence on the pack's own page, today, not from memory
2. ☐ Confirm it permits **commercial** use (even though the game is free, store
   distribution and any future donation/sponsorship model counts)
3. ☐ Confirm it is not share-alike (CC BY-SA / GPL) — those can infect the project
4. ☐ Record it in the table above with today's date
5. ☐ Unzip into its own folder under `assets/`, which is git-ignored
6. ☐ Add a `CREDITS.md` inside that folder with the same information
7. ☐ **Check the grid size matches** — 16×16, same as everything else. A 32×32 pack
   mixed into a 16×16 game is the single most common cause of the "free assets look
   cheap" problem. See `docs/ART.md` §2.
