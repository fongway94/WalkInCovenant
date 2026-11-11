# Shepherd-field prototype — continuation

- **Branch:** `arena/905f79d4-walkincovenant`. Do not merge or deploy without approval.
- **Base:** `cec25b525d44dff3b96970415fa2232a13e9d676` on `main`.
- **Latest fully verified implementation:** `b83c753`, tested in [run 42953016636](https://github.com/fongway94/WalkInCovenant/actions/runs/42953016636). Native prototype, both frame publishers, lint, visual, web export, isolated prototype browser and production browser passed; deploy was skipped.
- **Milestone:** an isolated playable field with independent, reference-matted shepherd and sheep, interaction, movement and selected depth layers. It is closer to the approved reference but **not visually complete or production-ready**.
- **In progress:** `b9686d2` broadens/softens the sheep contact and reduces body bob after the inspected `b83c753` frame exposed detached dark ovals. Its native and isolated-Web jobs passed and their real frames were inspected in [run 42955805136](https://github.com/fongway94/WalkInCovenant/actions/runs/42955805136), but the overall run failed in the separate production-browser job. The post-victory test loaded a default save (`[16,45]`, no `goliath_down`) instead of its seeded state; this is consistent with the known live-page IDBFS race. A test-harness-only fix and unit tests are awaiting CI.

## Completed and verified

- [x] Reviewed all four baseline frames from main run `42942725993`: the tight camera, bright oversized repeated sheep, dark small David, weak contacts, busy white top-left HUD, and near-total occlusion were visually inadequate.
- [x] Fixed actor origins and contact/cast shadow order, set sheep scale to `0.66`, widened the view, and moved a compact, outlined flock HUD to the top right.
- [x] Replaced inadequate keyed sprites with contours matted from the user's approved reference. `tools/proto/extract_reference_sprites.py` reproduces the two sheep variants and David/body/boot layers. The boot layers give a small alternating stride, not authored directional animation. Two baked sheep stride extremes change only reference-derived feet, without additional sprite draws.
- [x] Replaced the filled foreground polygon with a silhouette/stone matte. The real `proto_03_occlusion` frame shows David's head and torso, with grass/stone partially covering his lower body. The matte is approximate and needs broader traversal review.
- [x] Added a world-aligned upper-tree copy and one traced fence. Actors select depth bands by foot y; y-sort still orders actors inside a band. Each full-size texture shares the backdrop's exact origin; the draw regions clip transparent horizontal margins while retaining the full height. The renderer checks show no significant sampled background drift at the tested views, including a 960×540 window.
- [x] Latest render log: walk `dx=73.5`, sheep movement `14.7`, boot stride `2.00`, rock stop `x=612.0`, trunk stop `x=1148.0`, fence stops `y=226.0/280.0` from opposite sides; near interaction counts once and a distant interaction is rejected. The harness explicitly requires `PROTO PASS`.
- [x] Renderer toggles in the latest run changed **104/0** sampled actor pixels behind/in front of the tree and **23/0** behind/in front of the fence; each object's sampled background difference was **0/0**. Empty-scene checks at two camera positions and a 960×540 physical window each found zero significant sampled differences. These are sampled checks, not proof for every location.
- [x] Actual camera-frame registration predicted a horizontal shift of `-35.33px`, measured `-36px` (error `0.67px`); aligned background residual `5.04` versus `30.35` unaligned. This is a landmark check, not a complete depth/collision audit.
- [x] Frozen 320×180 versus 640×360 logical renders were compared in `42945561632`. Both were captured at 1280×720 and transported at 640×360; the 640 UI/placement was somewhat cleaner, with broadly similar field detail. Filtering is nearest in the scene and the WebP evidence is lossy. No performance conclusion follows from stills.
- [x] Higher-detail native frames use 640×360 WebP, a single joined `PROTOLOG`, and two annotation publishers. The latest native run used quality 75 and 85 frame notices split 46/39; the overflow publisher also works on failed visual tests for diagnosis.
- [x] `docs/art-reset/comparison/shepherd_field_ci_comparison.png` was rebuilt and inspected using only the approved reference and decoded real Godot frames from baseline `42942725993` and improved run `42955805136`. It labels the different framing and includes an approximately matched field crop. `shepherd_field_shadow_ci.png` separately compares staged real-frame sheep crops against the reference and prior run `42953016636`.

## Latest real-frame review

Decode `python3 tools/proto/decode_proto.py 42955805136 build/proto_b9686d2`. All six gameplay frames and both diagnostics were inspected:

- `proto_01_field_640`: the palette, wool and character lighting fit the edited field more closely than the baseline's white stickers and dark David. Composition remains narrower than the complete reference and the extra figure in the reference is absent.
- `proto_02_tree_front`: David is in front of the tree but behind the upper fence rail; only part of his boots/legs is covered. The fence contour is a manual approximation.
- `proto_03_occlusion`: foreground blades partly cover David rather than hiding nearly all of him. The foreground remains a fixed approximate matte.
- `proto_04_fence_front`: David is in front of the fence at the southern position. Two-sided collision was also exercised through movement, not only teleports.
- `proto_05_camera`: scenery tracks with the camera and sheep remain independent. A sheep still comes close to David in this short walk; the elliptical flee rule does not prove that all paths avoid awkward visual overlaps.
- `proto_06_tree_behind`: tree foliage partially covers David. `proto_07_tree_delta` is a black, sparse diagnostic map, not a gameplay frame; the tested front position had no significant sampled overlay/background change.
- `proto_08_sheep_gait`: a staged 2×2 diagnostic assembled from real viewport crops (variants across, opposing strides down), not a gameplay frame. Both poses changed visible rendered pixels (504/626 for the two variants). The new broad, softer shadow looks less detached in the actual before/after crops; it remains an approximation.

Experiments `9a77db9`, `2a2a3f3`, and `8f4fa9e` had failing prototype jobs. `8f4fa9e` reduced but did not remove tree-background differences (16 sampled pixels); `13288c1` removed the nested transform and passed the stronger tests. Keep this history when interpreting earlier frames.

## Remaining work and quality limitations

- [x] The isolated Web prototype loaded, drew and responded to keyboard movement at both logical widths. Four short, sequential headless Chromium 158 / ANGLE SwiftShader trials on an AMD EPYC 7763 CI runner measured draw-active animation-frame cadence of **15.3 and 16.4 fps at 320**, **15.9 and 16.4 fps at 640**, with p95 intervals of approximately 83–100 ms. Both screenshots were decoded and inspected. These are software-rendered CI observations with WebGL draw-call instrumentation, not mobile/hardware FPS: both widths use the same 1280×720 canvas in `canvas_items` mode.
- [x] The clipped-region experiment `1188315` passed its native depth/background tests at both camera positions and the 960×540 resized window; its six native frames and both Web frames were inspected. A subsequent Chromium/SwiftShader run measured 28.5–36.1 fps, but it used an AMD EPYC 9V45 rather than the prior EPYC 7763. The difference is **not** evidence that clipping caused a speedup.
- [x] Same-runner full-versus-clipped A/B in `42951874896`: after the first four trials, four 640-logical-width, 1280×720 canvas trials in full/clipped/clipped/full order measured **16.1 / 23.3 / 23.3 / 16.3 fps**, respectively, on AMD EPYC 7763 with Chromium 158/ANGLE SwiftShader. The clipped average was about 44% higher than the full average in this short, instrumented software-rendering experiment; p95 frame intervals were 83.3/100 ms full versus 66.6/66.7 ms clipped. Three Web screenshots were decoded and inspected; movement and rendering passed. This is evidence for the CI software renderer only, not a mobile or hardware performance claim.
- [x] `42953016636` verified sheep stride selection during independent movement and both staged variants, plus idle, blocked and hop states. The real gait diagnostic and native/Web gameplay frames were inspected. Both browser jobs succeeded and deploy was skipped.
- [x] The same run's 640-width full/clipped/clipped/full trials were 19.1 / 27.3 / 27.0 / 19.1 fps on AMD EPYC 9V74 / Chromium SwiftShader. Like the earlier run, these are short instrumented software-renderer observations, not physical-device FPS.
- [x] The `b9686d2` native render passed left/right shadow on/off sampling for both variants and both facing directions: `44/91`, `51/84`, `49/91`, and `53/87` changed samples. All native gameplay frames and the staged gait comparison were inspected; the detached black oval is reduced. These sampled checks do not guarantee quality for every pose.
- [x] The `b9686d2` isolated-Web job passed with movement at both logical widths; all three decoded browser screenshots were inspected. Its 640-width full/clipped/clipped/full sequence measured 25.3 / 35.6 / 35.9 / 25.4 fps on an AMD EPYC 9V45 with Chromium/SwiftShader. The full and clipped p95 intervals were about 66.7 ms and 33.4 ms, respectively. These short instrumented trials do not represent mobile or hardware-GPU FPS.
- [ ] Push and validate the production-browser test fix: close the live game page before rewriting the seed from a non-game page, then open a fresh game page and require the actual expected post-victory save, with up to three attempts. Run `node --test tests/browser/seeded_boot.test.cjs`, inspect the new full CI outcome and production-browser checks, and do not weaken the real ending assertion. Deploy in `42955805136` was skipped.
- [ ] Further art work: author genuinely directional/walking sheep and David animation rather than flipping baked highlights; inspect edge halos and shadows; stress sheep clearance across paths; and add only justified depth/collision layers for remaining trees, fence and foreground. The backdrop is still mostly a flat edited painting, so some world objects cannot yet occlude actors correctly.

The reference is `docs/art-reset/user_selected_reference.png` (681×348); its bottom arrow and right strip are viewer UI, not world art. The 1440×666 edited backdrop is not pixel-identical. The two full-world transparent depth textures still consume texture memory, and clipping has only been sampled at the tested window sizes. Real-device profiling and more resize/path coverage are still needed. No production gameplay scene, chapter, save or live deployment is in scope.

## Commands and constraints

```sh
export PATH=/home/user/.venv/bin:$PATH  # recreate a venv with Pillow + PyYAML if absent
python3 tools/gd_lint.py
python3 tools/xref_check.py
python3 tools/api_check.py
node --test tests/browser/seeded_boot.test.cjs
python3 -c 'import yaml; d=yaml.safe_load(open(".github/workflows/build-web.yml")); assert d["jobs"]["deploy"]["if"] == "github.ref == '\''refs/heads/main'\'' || (github.event_name == '\''workflow_dispatch'\'' && inputs.publish_preview)"; print("YAML/deploy guard OK")'
python3 tools/proto/decode_proto.py <run-id> build/proto_<run-id>
python3 tools/proto/decode_proto.py <run-id> build/proto_browser_<run-id> --browser
python3 tools/proto/check_camera_alignment.py <field.webp> <camera.webp> --cam-a <x> <y> --cam-b <x> <y> --zoom 0.55
python3 tools/proto/build_comparison.py <baseline.webp> <current.webp> docs/art-reset/comparison/shepherd_field_ci_comparison.png --baseline-run <id> --current-run <id>
python3 tools/proto/build_shadow_comparison.py <before-gait.webp> <after-gait.webp> docs/art-reset/comparison/shepherd_field_shadow_ci.png --before-run <id> --after-run <id>
godot --path . res://scenes/proto/ShepherdFieldProto.tscn  # on a machine with Godot installed
gh run view <run-id> --json status,conclusion,jobs,url
```

The native joined PROTOLOG is already ~3,680 bytes; split its annotation transport before adding many more checks. Godot cannot run locally: CI/Xvfb or CI/Chromium are the actual renderers. Direct artifact downloads redirect to an inaccessible Azure blob host; check-run annotations work, and runner-to-runner artifact transfer works. A new turn can recreate the Git checkout at the base while reapplying workspace changes: inspect and fetch the session branch before committing, and never discard user changes. The release deploy guard remains automatic for `main` and explicit `publish_preview` dispatch only; ordinary working-branch pushes do not deploy. GitHub read/push authentication is valid; attempting to cancel an already-failed old Actions run returned 403 (the run finished on its own), so do not assume this integration can cancel runs.
