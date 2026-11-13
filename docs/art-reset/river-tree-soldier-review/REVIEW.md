# River, tree height and the northern figure

Three requested changes are implemented on branch `arena/0854f8bd-walkincovenant`
and verified by hosted CI. The user approved publishing, and the reviewed build is
now live at https://fongway94.github.io/WalkInCovenant/ (Pages deployment
`7771808949`, 2026-11-13 17:24 UTC). It replaced the previous site; a push to
`main` republishes `main`.

| # | Request | What changed | Where |
|---|---------|--------------|-------|
| 1 | River detail at the ground's painterly level, shoreline and crossing included | Water surface rebuilt with square-sampled grain in the deep water, stretched current bands, short broken dashes, four-note colour dabs and wet shading against stones and banks; the bright ford is left calm | `tools/art/river_detail.py`, `art/scenes_painted/world_elah_refined_bottom.png` |
| 2 | Trees visibly **taller** than people, not wider | Tall olive/fig canvases scaled to 82 / 78 world pixels against a 27.4-pixel person (about 3x), feet and trunk anchors unchanged | `art/props_painted/olive_tree_tall.png`, `fig_tree_tall.png`, `scripts/world/Region.gd` |
| 3 | The mismatched figure seen walking north | The ridge Goliath repainted in the painterly bronze style used by the duel | `art/scenes_painted/goliath.png`, `goliath_striking.png` |

## Evidence

![The ford before and after](01-river-ingame.png)

![Trees before and after](02-trees-ingame.png)

![The northern figure before and after](03-north-figure-ingame.png)

![Second camera on the same meadow](04-trees-second-camera.png)

![Ford water at art scale](05-water-detail-art-scale.png)

![Champion sprite at 4x](06-champion-asset.png)

The four in-game frames are real framebuffers from `tests/art_review_probe.tscn`,
captured under Xvfb with software OpenGL in CI run
[43462121260](https://github.com/fongway94/WalkInCovenant/actions/runs/43462121260)
(commit `87d8708`). They arrive here through the run's annotations, so they are
500x225 at 24 colours derived from the 1000x450 capture; the art-scale panels
(1b, 3b) are native pixels.

## What is and is not touched

- Water: only pixels of the painted-water mask are repainted. The audit in
  `tests/proto/check_quality_assets.py` still proves the bank, reeds, the ford's
  pale approach and every sunlit stone are byte-identical, that five stone
  coordinates stay unpainted and four water samples stay painted, and that the
  repaint stays inside the brook band. Collision, crossing tiles, shore geometry
  and saves are untouched.
- Trees: same footprints, anchors, shadow and y-sorting; only the canvas and the
  visual scale changed. `tests/painted_world.gd` measures the visible sprite
  height at runtime (olive 82, fig 78, person 27.4) and `check_tall_trees()`
  checks the canvases are foot-anchored, upright, transparent-matted and
  byte-reproducible.
- Champion: same 128x128 source size, bbox, spawn offset, scale, y-sort and
  per-theme texture filter. The strike variant's spear cut is now a narrow band
  around the shaft, so it no longer clips his left shin.

## Verification

Hosted [run 43462121260](https://github.com/fongway94/WalkInCovenant/actions/runs/43462121260)
passed lint (static, xref, API, font, pack, painted-world and the chapter
contracts), the visual job with the four new review frames, both art-review
publication jobs, export-web, the release browser suite, the chapter browser suite
and the proto browser suites. `deploy` was skipped, so
https://fongway94.github.io/WalkInCovenant/ still serves the previously approved
build.

Locally: `gd_lint` clean (57 files), `xref_check` clean, `check_font` 850
codepoints, `check_faces`, `check_art_reset`, `check_craft_props`,
`check_cinematic_art`, `tests/proto/check_quality_assets.py` (refined fig, tall
trees, meadow, paving and painterly water with protected bank),
`tools/pack_art.py`, `test_pack_contents` (9 tests), `test_api_reference`
(5 tests) and `node --test tests/browser/seeded_boot.test.cjs` all pass.

## Publication record

* Published artifact: the `web` artifact of run 43462121260 (commit `87d8708`).
* Live `index.pck` SHA-256: `d1751ce0ba8cedaaff1c6250cd6005e1ece41faf37bd6a7ea2411d7b70e01116`,
  36,531,020 bytes, `GDPC` magic.
* Verified byte-identical to the artifact (PCK and `index.html`) by
  [run 43472774388](https://github.com/fongway94/WalkInCovenant/actions/runs/43472774388)
  after the redeploy. The 404s that run warns about for `sw.js` and
  `manifest.webmanifest` are expected: this engine emits `index.service.worker.js`
  and `index.manifest.json`, both present in the artifact.
* Getting there needed two settings the app token cannot change: the branch had to
  be added to the `github-pages` environment's deployment-branch policy, and Pages
  → Build and deployment → Source had to stay on **GitHub Actions**. While it was
  briefly on "Deploy from a branch", Pages served a Jekyll build of the repository
  instead of the game; restoring the source and redeploying fixed it.
* The temporary one-shot publisher and verifier workflows were deleted after use.

Not verified: appearance on a physical phone, and human art approval. Automated
checks establish geometry, protection of shoreline pixels and reproducibility,
not taste.
