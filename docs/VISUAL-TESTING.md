# VISUAL TESTING — what can actually be rendered and inspected here

**Established:** 2026-11-05, milestone *David's Life Before the Battlefield*,
Priority 1. This document is the capability report, not a claim of quality.

## What the environment allows

| Capability | Here (authoring sandbox) | In CI (GitHub Actions) |
|---|---|---|
| Godot runtime | **No binary.** Release assets redirect to `release-assets.githubusercontent.com`, which is outside the sandbox's network. `api.github.com`, `registry.npmjs.org`, `pypi.org`, `codeload.github.com` and `github.com` are reachable; the asset host is not. | **Yes.** `barichello/godot-ci:4.7.2` for lint/export; the `visual` job downloads the 4.7.2 editor binary on a hosted runner. |
| Display / GPU | **None.** No Xvfb, no Mesa DRI, no browser, no sound card. | **Yes, software.** `xvfb-run` + Mesa llvmpipe (`LIBGL_ALWAYS_SOFTWARE=1`), `--rendering-driver opengl3`. |
| Automated input | n/a | **Yes.** `Input.parse_input_event(InputEventAction)` through the engine's own pipeline, with a direct-handler fallback that is reported separately. |
| Screenshot capture | n/a | **Yes.** `RenderingServer.frame_post_draw` → `get_viewport().get_texture().get_image()` → nearest-downscale to 320×180 → PNG. |
| Scene-by-scene | n/a | **Yes.** `tests/visual.tscn` boots the shipped `Main.tscn` and captures fourteen named beats: cold boot, the valley, a conversation, a 2× Chinese review, the journal and its optional background page, the shepherd flock, a sheep reacting, a quest update, **the Goliath duel**, **the valley after the fall**, Bethlehem, a 4:3 window, and a real fade. |
| Visual regression | **Yes, locally**, on decoded PNGs (`tools/visual_diff.py`). | **Yes, in-run**, when `tests/frames/baseline_*.png` are committed: a 32×18 averaged colour-grid diff with a 0.18 limit. |
| Browser export testing | **No.** No browser binary, and the Pages host / CI artifact host are unreachable. | Not built. The web export is produced and size-checked by `export-web`, but nothing opens it in a browser. |
| Console / runtime errors | n/a | **Yes.** The render log is grepped for `SCRIPT ERROR`, `Parse Error`, `ERROR:`, failed script loads, null instances and unresolved classes; a match fails the job. |
| Audio | **No**, and no claim is made. | Not tested; only file/format/level gates (`check_audio.py`). |
| Real phone / touch | **No**, and no claim is made. | Not tested; see `docs/DEVICE-CHECKLIST.md`. |

## How a rendered frame gets back to the author

CI artifacts and raw logs live on hosts this sandbox cannot reach
(`productionresultssa*.blob.core.windows.net`,
`results-receiver.actions.githubusercontent.com`) — `gh run download` and
`gh run view --log` both fail with `EOF`. **Check-run annotations are on
`api.github.com`** and are readable with `gh api`. So the `visual` job prints
each PNG as base64 `::notice::WICFRAME|name|chunk|total|data` lines. An
annotation is truncated at 4096 characters and a step may emit ~10 notices, so
chunks are 3800 characters (still under the 4096-character truncation),
spread round-robin over fourteen short steps
(measured: a 320×180 capture is ~20 KB → ~27 KB base64 → ~8 chunks; after
48-colour quantisation the twelve-frame run measured 37 chunks, and fourteen
frames is budgeted at ~43 — still under the cap, subject to the decoded run). Then:

```bash
gh run list --limit 5                       # find the run id
python3 tools/decode_frames.py <run-id>     # writes frames/*.png
python3 tools/visual_diff.py                # compare with tests/frames/baseline_*.png
python3 tools/visual_diff.py --write-bases  # after REVIEWING the images by eye
```

`frames/*.png` and `build/frames/` are gitignored; the reviewed baselines in
`tests/frames/` are committed. If a frame arrives with missing chunks — an
annotation cap, or a job that died mid-capture — `decode_frames.py` reports it
as incomplete rather than writing a truncated PNG. The harness verdict and any
failed assertions are also published as annotations, because the raw job log
itself is on a blocked host.

## Observed results (2026-11-05)

- Run `41978406540`: first render. Five PNGs and a `frames` artifact were
  produced, but every `WICFRAME` notice was truncated to 4096 characters, so
  nothing could be decoded. Fixed by 3500-character chunks spread over eight
  steps, and by quantising the transport copy to 64 colours (~7 KB/frame).
  (The chunk size is now 3800, the palette 48 and the step count 14, to fit
  fourteen frames under GitHub's ~50-annotation cap; see the capability
  section above.)
- Run `41980997515`: the visual job went green
  (`input_routed=true parsed_opens=true direct=false` — a parsed
  `InputEventAction` really reaches `Node._unhandled_input` and opens a
  conversation). All five frames decoded. The harness had left the journal panel
  drawn over the Bethlehem shot; fixed by calling `Journal.close_panel()`.
- Run `41981486351`: five frames decoded and **inspected by eye**: the valley
  with HUD/tents/NPCs, the prologue box, Corin's conversation box, the journal
  page, and the Bethlehem place card over a second map. Five reviewed captures
  were promoted to `tests/frames/baseline_*.png`; `tools/visual_diff.py` then
  reported `visual_diff: clean` (diff 0.0000 on all five, tautologically — the
  baselines are those same reviewed captures). From here the coarse-grid
  comparison runs inside the engine on every CI render.
- Runs `41981915709` and `41983194255`: the whole workflow went green —
  `run_all: ALL CHECKS PASSED`, `smoke: PASS — the slice played start to
  finish`, `deep: PASS — 114 checks hold`, and `visual: PASS — 6 rendered
  frames`. The sixth beat (`06_flock`) drives the game's own BECOME cut and
  renders the shepherd fold, the sheep and the live `0/3` objective; it was
  decoded and inspected by eye. After the Bethlehem dialogue rewrite,
  `visual_diff.py` measured 0.0004–0.0164 for frames 01–05 against the
  committed baselines (limit 0.18) — the gate tolerates real content change
  but would catch a blank or wrong scene. **Six** reviewed baselines are now
  committed, and the engine's own in-run comparison ran green on `41981915709`.
- Not verified by any of this: a real phone in two aspect ratios, a single
  audio sample, tactile feel, a camp close-up, or a browser opening the
  web export. The duel and the post-fall valley were added as rendered
  frames in the 2026-11-06 pass (see below). See `docs/DEVICE-CHECKLIST.md` and
  `docs/DEVELOPMENT_BACKLOG.md`.

## Honest limits

- These are **real engine frames**, not mock-ups: they prove the scenes render
  and that a wholesale visual change is caught. They do **not** prove the art is
  good, that 10 px Chinese is legible on a 6.1" phone, or that the mix sounds
  right.
- Software GL is not the player's GPU. Colour management and filtering can
  differ from a real device.
- `Image.load_from_file` baselines are compared with a coarse grid on purpose;
  a single glyph, a bobbing marker or an animation frame will not (and should
  not) fail the gate.
- **Nothing here replaces the device pass.** Every score in
  `docs/PROJECT_AUDIT.md` that is capped by "no frame has ever been looked at"
  is only partly lifted: a frame has now been rendered and inspected, but not
  by a human on the target hardware.

## Reviewed baselines (2026-11-05, LIVING WORLD pass)

Twelve frames from the green run `42019960134` (`2bf8dc4`) were decoded,
upscaled and inspected by eye, then promoted with
`PYTHONPATH=/home/user/.cache/pillow_check python3 tools/visual_diff.py
--write-bases`. A plain `tools/visual_diff.py` reported `diff 0.0000` for all
twelve; `tests/visual.gd` now compares each fresh capture against them in the
engine (coarse 32×18 grid, `DIFF_LIMIT 0.18`). Variation between two
consecutive green runs was 0.0000–0.0171, so they are stable enough for that
limit.

| Frame | What it proves |
|---|---|
| `01_boot_world` | control is immediate, no forced prologue/briefing pages |
| `02_valley` | the boot horn beat and bilingual first-call toast |
| `03_dialogue` | a real parsed interact action opens a conversation |
| `04_journal` | the book is opaque and its rows are legible |
| `05_bethlehem` | the second region renders with its place card |
| `06_flock` | the slope with living sheep, no bubble slab, no stray toast |
| `07_sheep_near` | a live animal and the quest toast |
| `08_quest_update` | the objective counter advances; one quiet opaque bubble |
| `09_chinese_2x` | Chinese at 2× with a conversation box |
| `10_layout_4x3` | a taller *logical* 4:3 viewport, not a stretched picture |
| `11_transition` | a real `ScreenFade` caught mid-fade |
| `12_journal_before` | 「来路」 / "How you came here" is reachable by scrolling |

These are **wrong-scene detectors, not an art-quality verdict.** Three of the
five defects listed in `docs/ITERATION.md` §8 were invisible to this grid diff
and were found only by looking at upscaled PNGs.

## Premium-art / climax pass (2026-11-06)

`tests/visual.gd` grew from twelve to **fourteen** rendered states. Two new
frames close the biggest blind spot in the old suite:

| Frame | What it proves |
|---|---|
| `13_duel` | the shipped `GoliathFight` renders its own drawn 64px Goliath and 32px David, the directed dusk valley, the gold aim band and the timing marker; the harness stages the real setpiece at a near-frozen clock, it draws nothing itself |
| `14_aftermath` | after `goliath_down` the ridge is empty, the HUD role has changed back and the chapter aftermath objective is on screen |

`13_duel` also asserts the giant's texture is larger than 16 px, so a silent
reversion to the old 8×-upscaled map sprite fails the render job. The two new
frames plus the twelve reviewed baselines are re-promoted together once their
PNGs have been decoded and looked at by eye. The camp close-up, real handset,
browser execution and every sound remain unverified.
