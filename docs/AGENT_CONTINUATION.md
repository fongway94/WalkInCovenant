# Shepherd-field prototype — continuation

- **Branch:** `arena/905f79d4-walkincovenant`. Do not merge or deploy without approval.
- **Base:** `cec25b525d44dff3b96970415fa2232a13e9d676` on `main`.
- **Latest renderer-verified implementation:** `13288c1`, tested in [run 42948968783](https://github.com/fongway94/WalkInCovenant/actions/runs/42948968783). At review, prototype, overflow, lint, visual and web export jobs had passed, production browser was running, and deploy was skipped. The last fully green run was [42946192012](https://github.com/fongway94/WalkInCovenant/actions/runs/42946192012) (`d876660`).
- **Milestone:** an isolated playable field with independent, reference-matted shepherd and sheep, interaction, movement and selected depth layers. It is closer to the approved reference but **not visually complete or production-ready**.
- **In progress:** a temporary, isolated Web launcher and Chromium/SwiftShader performance probe are in the working tree and need their first CI run. They do not change the production scene or the exported artifact. Until that run passes, browser performance of this prototype remains unmeasured.

## Completed and verified

- [x] Reviewed all four baseline frames from main run `42942725993`: the tight camera, bright oversized repeated sheep, dark small David, weak contacts, busy white top-left HUD, and near-total occlusion were visually inadequate.
- [x] Fixed actor origins and contact/cast shadow order, set sheep scale to `0.66`, widened the view, and moved a compact, outlined flock HUD to the top right.
- [x] Replaced inadequate keyed sprites with contours matted from the user's approved reference. `tools/proto/extract_reference_sprites.py` reproduces the two sheep variants and David/body/boot layers. The boot layers give a small alternating stride, not authored directional animation.
- [x] Replaced the filled foreground polygon with a silhouette/stone matte. The real `proto_03_occlusion` frame shows David's head and torso, with grass/stone partially covering his lower body. The matte is approximate and needs broader traversal review.
- [x] Added a world-aligned upper-tree copy and one traced fence. Actors select depth bands by foot y; y-sort still orders actors inside a band. The copies share the backdrop's exact world origin and full quad, avoiding the nested-transform pixel-snap mismatch found in the previous attempts.
- [x] Latest render log: walk `dx=119.0`, sheep movement `22.2`, boot stride `2.00`, rock stop `x=612.0`, trunk stop `x=1148.0`, fence stops `y=226.0/280.0` from opposite sides; near interaction counts once and a distant interaction is rejected. The harness explicitly requires `PROTO PASS`.
- [x] Renderer toggles in the latest run changed **104/0** sampled actor pixels behind/in front of the tree and **23/0** behind/in front of the fence; each object's sampled background difference was **0/0**. Two additional empty-scene checks at different camera positions both found zero significant sampled differences. These are sampled checks, not proof for every location.
- [x] Actual camera-frame registration predicted a horizontal shift of `-60.78px`, measured `-61px` (error `0.22px`); aligned background residual `6.18` versus `33.37` unaligned. This is a landmark check, not a complete depth/collision audit.
- [x] Frozen 320×180 versus 640×360 logical renders were compared in `42945561632`. Both were captured at 1280×720 and transported at 640×360; the 640 UI/placement was somewhat cleaner, with broadly similar field detail. Filtering is nearest in the scene and the WebP evidence is lossy. No performance conclusion follows from stills.
- [x] Higher-detail native frames use 640×360 WebP at quality 78, a single joined `PROTOLOG`, and two annotation publishers. The latest native run used 88 frame notices split 46/42; the overflow publisher also works on failed visual tests for diagnosis.
- [x] `docs/art-reset/comparison/shepherd_field_ci_comparison.png` was rebuilt and inspected using only the approved reference and decoded real Godot frames from baseline `42942725993` and improved run `42948968783`. It labels the different framing and includes an approximately matched field crop.

## Latest real-frame review

Decode `python3 tools/proto/decode_proto.py 42948968783 build/proto_13288c1`. All six gameplay frames and the sparse tree-difference diagnostic were inspected:

- `proto_01_field_640`: the palette, wool and character lighting fit the edited field more closely than the baseline's white stickers and dark David. Composition remains narrower than the complete reference and the extra figure in the reference is absent.
- `proto_02_tree_front`: David is in front of the tree but behind the upper fence rail; only part of his boots/legs is covered. The fence contour is a manual approximation.
- `proto_03_occlusion`: foreground blades partly cover David rather than hiding nearly all of him. The foreground remains a fixed approximate matte.
- `proto_04_fence_front`: David is in front of the fence at the southern position. Two-sided collision was also exercised through movement, not only teleports.
- `proto_05_camera`: scenery tracks with the camera and sheep remain independent. A sheep still comes close to David in this short walk; the elliptical flee rule does not prove that all paths avoid awkward visual overlaps.
- `proto_06_tree_behind`: tree foliage partially covers David. `proto_07_tree_delta` is a black, sparse diagnostic map, not a gameplay frame; the tested front position had no significant sampled overlay/background change.

Experiments `9a77db9`, `2a2a3f3`, and `8f4fa9e` had failing prototype jobs. `8f4fa9e` reduced but did not remove tree-background differences (16 sampled pixels); `13288c1` removed the nested transform and passed the stronger tests. Keep this history when interpreting earlier frames.

## Remaining work and quality limitations

- [ ] Commit/push and run the isolated Web prototype performance probe. It uses a temporary `proto.html` plus a preloaded `override.cfg` beside a downloaded Web artifact; it must prove that the prototype actually loaded, drew, and responded to keyboard movement at both widths. Decode and inspect its two screenshots, and read its joined `PROTOBROWSER` result.
- [ ] Treat its four short Chromium/SwiftShader draw-active animation-frame trials as a software-rendered CI observation only. The two logical widths still use the same 1280×720 browser canvas in `canvas_items` mode; they are not a comparison of two physical render targets or evidence of mobile performance.
- [ ] Check the new full CI outcome, especially both browser jobs and skipped deploy, then update this document with measured results and the exact next task. Do not claim parity or a device-performance target without evidence.
- [ ] Further art work: author genuinely directional/walking sheep and David animation rather than flipping baked highlights; inspect edge halos and shadows; stress sheep clearance across paths; and add only justified depth/collision layers for remaining trees, fence and foreground. The backdrop is still mostly a flat edited painting, so some world objects cannot yet occlude actors correctly.

The reference is `docs/art-reset/user_selected_reference.png` (681×348); its bottom arrow and right strip are viewer UI, not world art. The 1440×666 edited backdrop is not pixel-identical. Two full-world transparent depth textures increase texture memory/fill work, which needs real-device profiling. No production gameplay scene, chapter, save or live deployment is in scope.

## Commands and constraints

```sh
export PATH=/home/user/.venv/bin:$PATH  # recreate a venv with Pillow + PyYAML if absent
python3 tools/gd_lint.py
python3 tools/xref_check.py
python3 tools/api_check.py
python3 -c 'import yaml; d=yaml.safe_load(open(".github/workflows/build-web.yml")); assert d["jobs"]["deploy"]["if"] == "github.ref == '\''refs/heads/main'\'' || (github.event_name == '\''workflow_dispatch'\'' && inputs.publish_preview)"; print("YAML/deploy guard OK")'
python3 tools/proto/decode_proto.py <run-id> build/proto_<run-id>
python3 tools/proto/decode_proto.py <run-id> build/proto_browser_<run-id> --browser
python3 tools/proto/check_camera_alignment.py <field.webp> <camera.webp> --cam-a <x> <y> --cam-b <x> <y> --zoom 0.55
python3 tools/proto/build_comparison.py <baseline.webp> <current.webp> docs/art-reset/comparison/shepherd_field_ci_comparison.png --baseline-run <id> --current-run <id>
gh run view <run-id> --json status,conclusion,jobs,url
```

Godot cannot run locally: CI/Xvfb or CI/Chromium are the actual renderers. Direct artifact downloads redirect to an inaccessible Azure blob host; check-run annotations work, and runner-to-runner artifact transfer works. The release deploy guard remains automatic for `main` and explicit `publish_preview` dispatch only; ordinary working-branch pushes do not deploy. GitHub read/push authentication is valid; attempting to cancel an already-failed old Actions run returned 403 (the run finished on its own), so do not assume this integration can cancel runs.
