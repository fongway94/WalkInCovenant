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
| **Valley of Elah** | 1 Sam 17 | dry valley, brook, camp | word-battle *(built)* |
| **Bethlehem & the fields** | Ruth 1–4 | wheat, threshing floor, well | gleaning |
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
3. ⏳ Region two (Bethlehem/fields) to prove regions are cheap to add.
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
