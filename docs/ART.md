# Art Direction — the decision, and how to reach "Pokémon quality" at US$0

> You asked me to choose. This document is that choice, plus the reasoning, plus the exact protocol for
> validating it in one week before you commit months to it.

---

## 1. The decision

**Style: GBA-era 16×16-tile top-down pixel art, in one coherent CC0 pack, re-skinned for the ancient
Near East.**

Concretely:

| Parameter | Value | Why |
|---|---|---|
| Tile size | **16×16 px** | Pokémon FireRed/Emerald, Zelda: Link's Awakening, Stardew Valley all live here. Smallest art cost per screen, easiest to keep coherent, fastest to re-skin. |
| Character cell | **16×24 or 32×32** (head+body taller than a tile) | Standard top-down RPG proportion; lets a character overlap the tile behind them, which is what creates depth. |
| Directions | **4** (down / left / right / up) | Pokémon's own overworld is 4-directional. 8-directional doubles the sprite count for a fraction of the feel. Mirror left→right to halve it again. |
| Animation frames | **4-frame walk, 2-frame idle, 4-frame run** | The minimum that reads as "alive." |
| Facesets | **48×48 or 64×64 portraits** | For the dialogue box. Ninja Adventure includes these per character — a huge free win. |
| Base viewport | **320×180 logical px** (20 × 11.25 tiles) | The Godot-recommended pixel-art base. Integer-scales to 1080p at exactly 6×. |
| Palette | **One shared 32–48 colour palette, earth-and-gold** | The single most important lever. A shared palette makes art from different sources look like one game. |
| Lighting | **`CanvasModulate` + `PointLight2D`** | Time of day, torchlight, the burning bush. Cheap, enormous payoff, and it is what lifts 16×16 art above "GBA" toward "Switch." |

### What this gets you

With a shared palette, terrain autotiling, 2D lighting and weather particles, a 16×16 game on a phone
screen at 6× integer scale is **genuinely indistinguishable in quality from a well-made modern indie
pixel-art game** — which is the honest reading of "Switch quality" for a 2D title. *Octopath Traveller*
is Switch-quality HD-2D and it was made by a 60-person team at Square Enix and Acquire. You are one
person at $0. **16×16 + lighting is the highest quality-per-hour available to you.**

---

## 2. What I rejected, and why

| Option | Verdict |
|---|---|
| **HD-2D** (Octopath: pixel sprites + 3D tilt-shift + bloom) | ❌ Gorgeous, and it would look stunning for a Bible game — volumetric light through a temple. But it needs 3D-laid-out maps, a much larger art volume per scene, and post-processing that hurts low-end Android phones. At solo/$0 it triples Phase 1. **Revisit as a stretch goal in v2 once the game ships.** |
| **32×32 tiles** | ❌ 4× the pixel count per tile, 4× the re-skinning work, and *fewer* tiles visible on screen — which makes a top-down world feel cramped on a phone. Wrong trade at $0. |
| **Hand-painted 2D + procedural rig** (Covenant today) | ❌ The painted *scene backgrounds* in Covenant are genuinely good and should be **kept for story cutscenes and chapter cards**. But this is exactly the look that reads as low-quality *next to Pokémon* when you're walking around, because the characters are vector drawings. Split the difference: pixel art for the walkable world, painterly art for the cinematic story beats. |
| **AI-generated pixel art** | ❌ Rejected as the *foundation*, despite your existing `tools/process-art.py` / `cutout.py` pipeline. The failure mode is specific and unavoidable: AI sprites do not sit on a consistent pixel grid, do not share a palette across frames, and produce a 4-frame walk cycle whose frames disagree about where the feet are. Animation consistency is precisely what AI image models are worst at. **Permitted use:** concept art, colour scripts, painterly chapter backgrounds, and one-off set dressing — never walk-cycle sprites. |
| **Commissioning art** | ❌ Not at $0. But: **the first US$300 this project ever earns should buy a custom tileset**, because it is the single highest-leverage quality jump available. Write that down. |
| **Mixing several free packs** | ❌ **This is the trap.** Mismatched outlines, palettes and grid sizes show at the seams and are the real reason free-asset games look cheap — not the fact that they're free. One pack. Re-skin it. |

---

## 3. The pack shortlist

All verified as of October 2026. **Licences must be re-checked on each pack's page before you ship** —
authors change terms.

### 🥇 Primary recommendation — **Ninja Adventure** (Pixel-Boy & AAA)

- **Licence: CC0 1.0 Universal.** Commercial use allowed, **attribution not required** (but credit them —
  it costs you nothing and they are excellent). Page states *"No generative AI was used."*
- **Where:** `pixel-boy.itch.io/ninja-adventure-asset-pack` — pay-what-you-want, 89 MB.
  **Note:** this sandbox can only reach GitHub, so *you* download it from itch.io.
- **Also clone `github.com/pixel-boy/NinjaAdventure`** — a working **Godot 4** example project
  (`project.godot`, `main.gd`, `world.tscn`) with the pack organised into
  `content/{character,environment,map,ui,particle,stat,team,weapon,destroyable,behavior,menu}`.
  Studying how they structure a top-down RPG in Godot is worth a day on its own.
- **Contents:** 50+ animated characters **with facesets**, 30+ monsters, 9 bosses, 60+ items,
  tilesets with **autotiling floors**, exterior + interior elements, 100+ sound effects,
  **37 music tracks**, UI elements, 30+ visual effects, 2 fonts.
- **Why it wins:** it is the only free pack that is a **complete ecosystem** — characters, tiles, UI,
  audio, VFX *in one style, by one team, on one grid*. That coherence is exactly the thing you cannot
  buy by mixing five packs. It single-handedly closes the asset question, the audio question, **and**
  gives you a Godot reference implementation.
- **The catch, honestly:** it is a **Japanese / ninja** theme — pagoda roofs, torii gates, bamboo,
  kimono. For ancient Israel you must **re-skin the architecture and clothing layer.** Terrain
  (grass, water, rock, sand, cliff, path), props (trees, pots, crates, fire), interiors (floors, walls,
  furniture), UI and audio are largely **usable as-is or with a palette shift.**

### Alternatives to evaluate alongside it

| Pack | Licence | Fit for ancient Near East |
|---|---|---|
| **Cute Fantasy RPG** — LimeZu, itch.io | Free tier | 🟡 Good. Rural/fantasy village, warm, coherent. Check the free tier covers what you need. |
| **Modern Interiors / Modern exteriors** — LimeZu, 16×16 | Free tier | 🔴 Wrong era. Useful only for a modern-day framing sequence. |
| **Tiny Swords** — Pixel Frog | CC0 (free packs) | 🟡 Beautiful and juicy, but stylised/chibi and side-ish. Less "Pokémon." |
| **Kenney — Tiny Town / RPG packs** | CC0 | 🟡 Clean and safe, but a distinctive chunky "Kenney" look that reads more *mobile-casual* than *GBA RPG*. |
| **0x72 — Dungeon Tileset II** | CC0 | 🟢 Excellent for interiors, the lions' den, prison cells. Grid discipline is superb. Add as a *supplement*, not a base. |
| **Serene Village** / **Sprout Lands** | Varies — **Sprout Lands is non-commercial on the free tier** | ⚠️ Check licence carefully before use. |

---

## 4. The one-week evaluation protocol (do this before any map work)

**Do not pick a pack by scrolling screenshots.** Pick it by building the same scene three times.
One week, roughly 6 hours.

### The test scene — identical for every candidate

One 20×12 tile screen containing exactly these elements:

1. A dirt **path** crossing grass, with autotiled edges
2. A **water** body with a shoreline transition
3. One **tree**, one **rock**, one **pot/crate** prop
4. One **building** with a doorway you can enter (or fake one)
5. Your **player character** standing on the path, facing down, mid-walk-frame
6. One **NPC** facing left
7. A **dialogue box** with a faceset portrait and three lines of Chinese text
8. **Day** version and **night** version, lit only by one torch `PointLight2D`

### Score each pack 1–5 on these seven axes

| Axis | Question |
|---|---|
| Coherence | Does every element look like the same artist drew it? |
| Biblical plausibility | Can a viewer see *ancient Israel*, not *feudal Japan* or *medieval Europe*? |
| Readability at 6× | On a phone, at real scale, can you tell grass from path from water instantly? |
| Re-skin effort | How many tiles must you personally redraw to fix the theme? Count them. |
| Character quality | Does the walk cycle read as walking? Do the facesets have personality? |
| Lighting response | Does the night version look *beautiful*, or just dark? |
| Coverage | Does it already include what chapters I–IV need, or will you be drawing half of it? |

**Highest total wins. Tie-break on re-skin effort** — because at solo/$0, hours are your only currency.
Write the scores into this file so the decision is recorded and you never relitigate it at 2am in month six.

| Pack | Coh | Bibl | Read | Reskin | Char | Light | Cover | **Total** |
|---|---|---|---|---|---|---|---|---|
| Ninja Adventure | | | | | | | | |
| Cute Fantasy RPG | | | | | | | | |
| Kenney Tiny Town | | | | | | | | |

---

## 5. Re-skinning for the biblical world

The work that makes a ninja pack into an Israel pack. Budgeted as the largest art line item.

### 5.1 Architecture — the highest-impact change

| Draw | Not draw |
|---|---|
| **Flat-roofed mud-brick houses**, whitewashed, small windows, external stairs (1 Sam 9:25 — Saul sleeps on the roof) | Pagoda roofs, curved eaves, torii gates |
| **Stone walls**, dry-laid, with a low plaster finish | Timber-frame, wattle-and-daub |
| **Tents** — goat-hair black/brown, guy ropes, tent pegs (Exodus, the camp at Elah) | Any European medieval building |
| **Olive trees** — gnarled, silver-green, low canopy | Bamboo, cherry blossom, pine |
| **Fig trees, date palms, sycamore-fig** (Zacchaeus' tree is a sycamore-fig, *Ficus sycomorus*) | — |
| **Wheat and barley fields**, threshing floors | Rice paddies |
| **Stone winepresses, cisterns, wells, millstones** | — |
| **Pottery** — oiled jars, amphorae, clay lamps | Porcelain, lacquerware |

At 16×16 a house is roughly 32×32 pixels. **Redrawing a flat-roofed mud-brick house is a two-hour job
in LibreSprite once you've done one.** You need maybe four or five building variants for the whole
vertical slice. This is very achievable.

### 5.2 Clothing — the second-highest

- Men: **tunic** (knee-length, undyed wool or striped), **belt/sash**, **headcloth** or bare-headed
  with dark hair and beard. Sandals.
- Women: longer tunic, **veil** or head covering, often carrying a **water jar on the shoulder or hip**.
- Soldiers: **bronze scale armour** or a leather cuirass, **helmet**, spear, round shield — for
  Goliath, bronze scale armour and a bronze helmet are textually specified (1 Sam 17:5–6).
- Priests: **white linen ephod**.
- **Re-colour existing pack characters rather than redrawing silhouettes.** A kimono sprite recoloured
  to undyed wool with a headcloth added is 80% of the way there, and the *animation* — the expensive
  part — is already done.

### 5.3 The shared palette

Lock this before drawing a single tile. Everything imported gets indexed to it.

| Role | Direction |
|---|---|
| Ground / earth | Warm ochre → dry sienna → umber shadow |
| Grass / foliage | Olive-green, desaturated, **not** bright cartoon green |
| Stone | Cool grey-blue with a warm highlight |
| Water | Deep teal → slate, per Covenant's existing `COL.water: #16303c` — reuse it |
| Wood / tent hair | Dark warm brown, near-black in shadow |
| **Accent gold** | Covenant's `#c9a45c` / `#f7dda5` — the divine, the temple, verse text, rewards |
| Shadow | Never pure black — a desaturated indigo `#14202a` (Covenant already uses this) |

**This palette is already in your old code.** `rig.js` `CHARS`, `field.js` `COL`, and `styles.css`
encode a consistent Covenant colour language: deep indigo-teal shadows, warm gold highlights. That is
your house style. **Carry it across — it is the thing that will make the remake feel like the same
game, and it is free.**

### 5.4 Godot import settings (non-negotiable for pixel art)

`project.godot` in this repo already sets these; documented here so you know why:

```ini
[display]
window/size/viewport_width=320
window/size/viewport_height=180
window/stretch/mode="canvas_items"      ; 2D + UI scale correctly together
window/stretch/aspect="expand"          ; fills 19.5:9 phones, shows more world
window/stretch/scale_mode="integer"     ; whole-number upscale, no shimmer
window/handheld/orientation="sensor_landscape"

[rendering]
textures/canvas_textures/default_texture_filter=0   ; Nearest — no blur
renderer/rendering_method="gl_compatibility"        ; required for web export
renderer/rendering_method.mobile="gl_compatibility" ; fastest on phones
2d/snap/snap_2d_transforms_to_pixel=true            ; kills sub-pixel jitter
2d/snap/snap_2d_vertices_to_pixel=true

[gui]
theme/default_font_antialiasing=0
theme/default_font_subpixel_positioning=0
```

Per-texture: **Filter = Nearest, Mipmaps = Off.** For tilesets, set
`Rendering → Textures → Canvas Textures → Default Texture Filter` to Nearest globally (done) so you
never have to remember per-sprite.

---

## 6. Tooling at $0

| Task | Tool | Notes |
|---|---|---|
| Sprite editing, re-skinning | **LibreSprite** | Free, open-source Aseprite fork. Layers, onion skin, palette lock. |
| Quick edits / no install | **Piskel** (browser) | Fine for one-off tiles. |
| Tilemap authoring | **Godot's TileMap + Terrain Sets** | Autotiling built in. Do not use Tiled — Godot 4.7's native terrain system is good enough and avoids a converter. |
| Palette indexing | LibreSprite palette lock, or a GIMP/Python index pass | Force every imported sheet through the shared palette. |
| Animation preview | Godot `SpriteFrames` editor | Built in. |
| Texture packing | Godot auto-import | Free pack at export. |
| Font (Latin pixel) | Any CC0 pixel font on itch.io/OpenGameArt | Must include full Latin + punctuation. |
| Font (Chinese) | **Covenant already has the answer** | A CJK pixel font at 16px is very hard to read. For Chinese dialogue, use a **subtle non-pixel CJK font** (Noto Sans SC subset, OFL) — this is what Chinese pixel-art games actually do, and Covenant already subsets Noto symbols. Bilingual legibility beats stylistic purity here. |

> ⚠️ **The Chinese text problem is real and often missed.** 16×16 pixel fonts render Latin beautifully
> and Chinese illegibly. Covenant ships ~5,300 Chinese characters of story. **Do not** try to force CJK
> into a pixel font. Use a crisp small-size CJK font in the dialogue box, slightly larger than the
> Latin, and it will look *intentional*. Test this in Phase 0, in both languages, on your phone.

---

## 7. Per-chapter asset checklist

Copy this per chapter. If a chapter's list is longer than this, cut content.

**Region assets (shared, drawn once):**
- ☐ 1 terrain tileset (grass, dirt, path, sand, rock, cliff, water + edges) — *from pack, re-paletted*
- ☐ 4–6 building variants — *re-skinned to mud-brick / flat roof*
- ☐ 3 tent variants — *re-skinned*
- ☐ 6–8 trees/plants (olive, fig, palm, sycamore-fig, wheat, barley) — *re-skinned*
- ☐ 6–8 props (jar, cistern, well, millstone, altar of stones, fire pit, crate, bench) — *mixed*
- ☐ 2 interior tilesets (tent interior, stone room) — *from pack*

**Character assets (per named character):**
- ☐ 4-dir × 4-frame walk (16 frames)
- ☐ 4-dir × 2-frame idle (8 frames)
- ☐ 4-dir × 4-frame run *(player only)*
- ☐ 1 faceset, minimum 2 expressions (neutral + one other)
- ☐ *All from the pack's existing characters, re-coloured and re-costumed*

**Chapter-specific assets:**
- ☐ 1 set piece (Goliath; the lions; the boat; the palace throne room)
- ☐ 1 story-scene painterly background — **reuse Covenant's `assets/art/*.jpg` directly**
- ☐ 2–4 VFX (dust, water spray, fire, divine light) — *from pack's 30+ VFX*

**Audio:**
- ☐ 1 region music bed — *from Ninja Adventure's 37 tracks, or Covenant's procedural score*
- ☐ Footsteps × terrain (grass / stone / sand / water) — *from pack's 100+ SFX*
- ☐ UI blips: cursor, confirm, cancel, quest-complete, verse-found
- ☐ 1 set-piece sting

---

## 8. Where the painterly art survives

Covenant's 13 cinematic scene images (`assets/art/*.jpg` — 848×1264, one consistent style) and its
7 portraits (`portrait-*.jpg`) are **good and paid for in time already.** Do not discard them.

Use them for:
- **Story/cutscene backgrounds** — when a chapter's narrative beat plays out, cut from pixel overworld
  to the painterly image with a dialogue box. This contrast is *itself* a quality signal: pixel for
  walking, painting for revelation.
- **Chapter cards and the map screen**
- **The Journey Mirror profiles** and the finale
- **The BECOME transition** — the moment you become David is the perfect place to bloom from pixel art
  into the painted `elah-field.jpg`

This hybrid is your differentiator. Very few Bible games have both a walkable pixel world *and*
cinematic painted set pieces. You already own the second half.

---

## 9. Recording the decision

Once the one-week protocol is run, fill in the table in §4 and add a line here:

```
DECISION — <date>
Pack chosen: <name>
Licence verified: <licence + URL + date checked>
Total score: <n>/35
Re-skin estimate: <n> tiles to redraw personally
Notes:
```

**Attribution (recommended even though CC0 does not require it):** put a credits screen in the game.

> Art, audio and UI assets: **Ninja Adventure** by Pixel-Boy and AAA, released under CC0 1.0.
> Additional assets: Kenney (CC0), 0x72 (CC0).
> Engine: Godot 4.7 (MIT). Scripture: KJV and 中文和合本, both public domain.

A credits screen costs you one scene and it is the right thing to do.
