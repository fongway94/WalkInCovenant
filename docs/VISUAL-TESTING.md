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
| Scene-by-scene | n/a | **Yes.** `tests/visual.tscn` boots the shipped `Main.tscn` and captures five named beats: boot dialogue, the valley, a conversation, the journal, and Bethlehem. |
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
each PNG as base64 `::notice::WICFRAME|name|chunk|total|data` lines (50 KB per
chunk), and:

```bash
gh run list --limit 5                       # find the run id
python3 tools/decode_frames.py <run-id>     # writes frames/*.png
python3 tools/visual_diff.py                # compare with tests/frames/baseline_*.png
python3 tools/visual_diff.py --write-bases  # after REVIEWING the images by eye
```

`frames/*.png` and `build/frames/` are gitignored; the reviewed baselines in
`tests/frames/` are committed. GitHub caps notice annotations per step, so if a
run produces more than ~10 chunks the tail is dropped — `decode_frames.py`
reports incomplete frames rather than writing a truncated PNG.

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
