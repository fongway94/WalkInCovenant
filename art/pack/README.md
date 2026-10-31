# Ninja Adventure Asset Pack — vendored sheets

These five PNGs are the map layer of the **Ninja Adventure Asset Pack** by
**Pixel-Boy** and **AAA**.

- **Licence: CC0 1.0 (public domain).** Commercial use, modification and
  redistribution are all permitted, no credit required. Credit is given anyway,
  here and in `docs/ART.md`.
- **Source: https://github.com/pixel-boy/NinjaAdventure** — the author's own
  repository, `content/map/`. Downloaded 2026-10-30, unmodified.

| file | what it holds |
|---|---|
| `tileset_floor.png` | ground: grass, dry earth, trodden road, rock, snow, water, marsh |
| `tileset_village_abandoned.png` | props: olive/fig trees, bushes, rocks, pots, ruins, houses |
| `tileset_interior_floor.png` | temple/palace floors (not yet used) |
| `tileset_wall_simple.png` | walls (not yet used) |
| `tileset_animated.png` | four-frame white flower (not yet used) |

## Do not edit these files

They are the cut source, not the game's art. `tools/pack_art.py` reads them and
stamps the cells named in `tools/art_manifest.json` into `art/tiles/terrain.png`
and `art/props/*.png`, over the procedural base that `tools/artgen/` builds.

## Why the whole pack is not used

The pack is a **ninja/Japanese** setting: characters are ninjas and samurai, and
there are torii-style ruins. The remake is the ancient Near East. Ground,
foliage and rock carry over without any dissonance; characters, architecture and
weapons do not. `docs/ART.md §5.5` records what was taken, what was left, and
what still needs drawing.
