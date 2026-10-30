# CONTENT — porting 27,000 lines of Covenant into Godot without retyping any of it

> **Rule: nobody retypes a Bible story.** Covenant's chapters are already written, reviewed, bilingual,
> and protected by twelve green lints. The port is a **script**, not a rewrite. If you find yourself
> hand-copying dialogue into a Godot inspector, stop — the converter is incomplete.

---

## 1. Inventory of what exists

Measured from `fongway94/Covenant` at v0.9.38:

| Asset | Where | Volume | Port method |
|---|---|---|---|
| 6 EN→ZH chapters | `data/chapters.js` | 851 lines | script |
| 4 native bilingual chapters | `data/chapters-extra.js` | 435 lines, via `buildChapter(spec, lang)` | script — must *call* `buildChapter`, not parse it |
| Full Chinese story, ch. I–VI | `data/zh-story.js` | 753 lines, ~5,300 characters | script |
| Chinese UI dictionary | `data/zh-ui.js` | 389 lines | script → CSV for TranslationServer |
| Walkable valley content | `world/elah.js` | `NPCS` (4), `WORDS` (4), `SHOUTS` (4), `STONES` (5) | script |
| Virtues / fruits / relics / seals / callings | `data/compendium.js` | 94 lines | script |
| Journey Mirror profiles | `data/mirror.js` | 324 lines, 10 profiles | script |
| "再走一步" reading invitations | `data/deeper.js` | 81 lines, 10 | script |
| 20 story moments | `data/moments.js` + `moment-steps.js` | 257 lines | script |
| Camp quests + NPC dialogue + day phases | `data/quests.js` | 89 lines | script |
| Portrait mapping | `data/portraits.js` | 52 lines, incl. `JESUS_FACE` switch | script |
| Cinematic scene art | `assets/art/*.jpg` | 13 images, 848×1264 | **copy verbatim** |
| Character portraits | `assets/art/portrait-*.jpg` | 7 | **copy verbatim** |
| Cut-out sprites | `assets/art/sprites/*.webp` | 14 | copy — used for set pieces, not the overworld |
| Symbol font subsets | `assets/fonts/*.woff2` | 2 × ~5 KB, OFL | copy — see §6 |
| Approved prose | `tools/check-copy.js` `KEEP` list | **22 lines the author rewrote by hand** | **frozen. verbatim. never touch.** |

### The frozen lines

`MILESTONE-v0.9.37.md` records this precisely:

> *"The user rewrote 22 weak lines themselves and those exact strings are approved, frozen, and
> protected in `check-copy`'s `KEEP` list."*

**These 22 strings must survive the port byte-identically.** Add a test:

```gdscript
# tests/test_frozen_copy.gd
func test_the_22_approved_lines_survived_the_port() -> void:
    for entry in FROZEN_KEEP:      # ported from tools/check-copy.js
        assert_true(find_string_in_content(entry.text),
            "An author-approved line was altered or lost in the port: %s" % entry.text)
```

This is the single most important content test in the project. It is not about code coverage — it is
about not silently discarding the author's own editorial judgement during a mechanical migration.

Also carry across the **house voice** documented in the same milestone: full explanatory sentences;
看起来 / 其实 / 原来 / 未必 / 或许 / 真正 / 依然 as connective glue; 不是…而是… used sparingly;
*meaning carried, not gestured at.* Any new writing in the remake is held to that standard.

---

## 2. The converter

`tools/port-chapters.mjs` — a Node script that imports Covenant's ES modules directly (they are plain
ESM, no build step) and writes JSON. **Run it against a clone of the old repo; never vendor the old
source into this one.**

```js
// tools/port-chapters.mjs   (outline — run with node 20+)
// usage: node tools/port-chapters.mjs /path/to/Covenant data/chapters/

import { CHAPTERS } from "<covenant>/src/data/chapters.js";
import { buildChapter, EXTRA_CHAPTER_SPECS } from "<covenant>/src/data/chapters-extra.js";
import { ZH_STORY } from "<covenant>/src/data/zh-story.js";

for (const ch of CHAPTERS) {
  // Chapters VII–X only exist after buildChapter() has run for each language.
  // Call it, don't parse it.
  const resolved = ch.spec ? buildChapter(ch.spec, "en") : ch;
  const resolvedZh = ch.spec ? buildChapter(ch.spec, "zh") : null;

  const out = {
    id: resolved.id, num: resolved.num, roman: resolved.roman,
    title: { en: resolved.title, zh: ZH_STORY[ch.id]?.title ?? resolvedZh?.title },
    ref: resolved.ref, theme: resolved.theme,
    paintedArt: `res://art/painted/${resolved.art.split("/").pop()}`,
    region: `res://scenes/world/regions/${regionNameFor(resolved.id)}.tscn`,
    scroll: resolved.scroll,
    cast: resolved.cast,
    start: resolved.start,
    endFruits: resolved.endFruits, relic: resolved.relic,
    nodes: resolved.nodes,           // ← already the right shape; see ARCHITECTURE.md §5
    ending: resolved.ending,
    reflection: resolved.reflection,
    deeper: DEEPER[resolved.id],
  };
  write(`data/chapters/ch${pad(out.num)}_${out.id}.json`, out);
}
```

**Why this is safe:** Covenant's chapter shape (`nodes` → `lines` / `choices` / `next` / `mini`) is
*already* the shape proposed in `ARCHITECTURE.md` §5. That schema was not designed by accident — it was
designed so that content authors could write chapters without touching engine code. The remake adopts
it, so the converter is a **field rename plus a bilingual merge**, not a restructuring.

**What the converter must also emit, per chapter:**
- a `nodes` reachability report (so you can see the branch shape before you build a map for it)
- a list of every `who` in `cast` → which sprite/faceset they need (**this becomes your art backlog**)
- a list of every verse reference cited → cross-check against public-domain sources
- a count of `lines` and `choices` → matches `npm run check`'s reported
  `Chapters: 10 · Nodes: 58 · Lines: 223 · Choices: 135`

That last line is your **checksum**. If the converter reports different totals, it dropped something.

---

## 3. Order of porting

Port in this sequence. Each step is independently testable.

| Step | Script | Verify with |
|---|---|---|
| 1 | `port-compendium.mjs` — virtues, fruits, relics, seals, callings | counts match `compendium.js` |
| 2 | `port-chapters.mjs` — all 10 chapters to JSON | `Chapters: 10 · Nodes: 58 · Lines: 223 · Choices: 135` |
| 3 | `port-mirror.mjs` — 10 profiles + 4 ways + disclaimers | deterministic scoring reproduces old results |
| 4 | `port-ui-strings.mjs` — `zh-ui.js` → `ui_strings.{en,zh}.csv` | zero missing keys either language |
| 5 | `port-elah.mjs` — `NPCS`, `WORDS`, `SHOUTS`, `STONES` | 4 verses, 4 shouts, 5 stones, 4 NPCs |
| 6 | `port-moments.mjs` — 20 moments | all skippable, all winnable |
| 7 | `port-quests.mjs` — camp quests, day phases | 3 quests, 5 day phases |
| 8 | copy `assets/art/` → `art/painted/` | 13 scenes + 7 portraits, byte-identical |

Only after step 8 do you open the Godot editor and build a map. **Content first, engine second** —
because content is the irreplaceable part and the engine is the replaceable part.

---

## 4. What must be *rewritten*, not ported

Honest list. These have no clean automatic path:

| Item | Why | Effort |
|---|---|---|
| **Maps** | `buildGrid()` generated the valley from code stamps. A Godot TileMap is authored by hand, painted in the editor. There is no useful conversion — and you don't want one, because hand-authoring is the whole point. | 4–8 h per region |
| **The 15 set-piece games** (`engine/games.js`, 2,977 lines) | Canvas-drawn mini-games with per-frame `step`/`draw`. Each becomes a Godot scene. **Port the rules and the text; rewrite the presentation.** | 4–12 h each |
| **The 20 moments** (hold/tap/trace/balance/rhythm) | Same — but these are *small*. Consider making them one generic `Moments.tscn` with five modes, as Covenant already does with `engine/moments.js`. | 8 h total |
| **The procedural audio score** (`core/audio.js`, 779 lines) | A real Web Audio synthesis graph: chord progressions, plucked oud voice, counter-melody with 5 Hz vibrato, frame drum, convolution reverb, filtered brown noise. Porting to GDScript `AudioStreamGenerator` is possible but genuinely hard. **Recommendation: use Ninja Adventure's 37 CC0 tracks for region music and port only the ambience layer** (wind/water/crowd), which is simple and distinctive. | 2 h (ambience only) |
| **The WebGL atmosphere shader** (`engine/atmosphere.js`) | Volumetric light, dust, grain, vignette. Godot has `CanvasItem` shaders — arguably easier to rewrite than to port, and `PointLight2D` + `CanvasModulate` will do 80% of it natively. | 4 h |
| **Dialogue UI** | `screens/story.js` is 1,433 lines of DOM. Godot `Control` nodes replace it entirely. | 8 h |

---

## 5. Content the remake should ADD

Small, high-value, and all in the spirit of the existing design:

1. **Bystander ambience dialogue.** In an overworld you can walk past people. Give unnamed NPCs
   one-line barks that change by chapter state — before Goliath falls, the camp is frightened; after,
   it is incredulous. This is free immersion that a text-and-choice game structurally could not have.
   *Discipline: barks are never scripture and never doctrine. They are crowd noise with a heart.*
2. **Walk-and-talk escorts.** An NPC who walks with you and talks en route. This is the single best
   "follow NPC" affordance and Covenant could never do it because its NPCs never moved.
3. **Returnable regions.** After a chapter, let the player walk back. The camp is different. The woman
   at the tent has one new line. `elah.js` already models this with `lines` vs `after` — **that field
   pair is the whole feature, port it.**
4. **A physical journal in-world.** Not a menu — a scroll object you open, with the ten passages,
   as Covenant's `deeper.js` reading list already intends.
5. **Breathing prayer as a world action.** Covenant's camp breathing prayer (inhale → hold → exhale,
   three rounds, +2 Guidance) becomes something you can do anywhere by stopping and holding a button.
   In an overworld game, *standing still deliberately* is a beautiful mechanic. Do not lose it.

---

## 6. Localisation and fonts

- **Chinese is the default language, English is the toggle.** That is Covenant's existing choice and it
  should not change: the author writes in Chinese, the first audiences are Chinese-speaking churches.
- Scripture: **KJV** (English) and **中文和合本** (Chinese). Both public domain. Never NIV/ESV/NLT/NKJV
  without a licence.
- Godot's `TranslationServer` + CSV import handles UI strings. **Chapter content stays in the JSON**
  with inline `{en, zh}` pairs, because that is how Covenant already models it and it keeps a line of
  dialogue next to its translation — which matters enormously when a pastor is reviewing.
- **Fonts:** a 16×16 pixel font cannot render Chinese legibly. Use a small crisp CJK font (Noto Sans SC
  subset, OFL) for dialogue and keep a pixel font for Latin numerals, titles and UI chrome. Covenant
  already subsets Noto Sans Symbols 1 & 2 into two ~5 KB woff2 files with an explicit `unicode-range`
  list — **reuse that subsetting approach** to keep CJK font payload small. For Godot, generate a
  `.fnt`/dynamic font with a restricted glyph set covering exactly the characters your script uses.

  ```bash
  # Extract every unique CJK character actually used in the content, then subset.
  node tools/collect-glyphs.mjs data/ > glyphs.txt
  pyftsubset NotoSansSC-Regular.otf --text-file=glyphs.txt --output-file=art/fonts/covenant-sc.otf
  ```
  ~5,300 unique-enough characters subsets to a few hundred KB instead of a 10 MB full CJK font.
  **This is the difference between a 25 MB and a 60 MB web build.**

- **Adding Malay later** (`strings.ms.json` in Covenant's roadmap) is cheap *if* the `{en, zh}` inline
  pattern becomes a general language map `{en, zh, ms}`. Do that in the converter now, while it is free.

---

## 7. Theological review workflow

Covenant's `review/` folder is a genuinely good idea and should be carried across and extended:

```
review/
├── HOW-TO-USE.txt          ← instructions for a non-technical reviewer
├── chapters/01-elah.tsv    ← every line, one row, with a "verdict" column
├── zh-story.tsv
└── weak-lines.md           ← lines the author flagged as still not right
```

**TSV per chapter is the correct format** — a pastor can open it in Excel or Numbers, read the whole
script in order, and mark rows. No Git knowledge required. Regenerate these from `data/chapters/*.json`
with a script after every content change, and add:

- a `red-letter` column that is **read-only** for reviewers, showing the citation each Jesus line must
  match, so the whitelist in `ARCHITECTURE.md` §7 doubles as the review checklist
- a `public-domain` column asserting each verse reference is KJV / 和合本
- a `tradition-vs-text` column, for the places where Covenant's GDD already insists on honesty:
  *"Where tradition adds details the text does not (e.g. the meaning of David's five stones), Elias
  explicitly says so."*

**Every chapter is read by at least two church leaders before release, ideally from different
denominations.** That was Covenant's rule. Keep it. It is the reason a game like this can be trusted.
