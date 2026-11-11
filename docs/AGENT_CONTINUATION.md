# Shepherd-field prototype — continuation

- **Branch:** `arena/905f79d4-walkincovenant`; do not merge or deploy without approval.
- **Base:** `cec25b525d44dff3b96970415fa2232a13e9d676`, the `main` merge containing prototype commit `048321b`.
- **Latest verified implementation commit:** `82afd91`. A subsequent working change adds a small layered boot gait and corrects the test staging; it must be rendered and reviewed before it is considered verified.
- **Milestone:** playable isolated field, now using actors matted from the approved reference. The visual target is not met; this is not a completion claim.
- **Latest reviewed CI:** [42945065335](https://github.com/fongway94/WalkInCovenant/actions/runs/42945065335), commit `82afd91`: `proto-frames`, `proto-frame-overflow`, lint and visual jobs passed; deploy skipped (browser was still in progress at review). Prior cycle [42944117226](https://github.com/fongway94/WalkInCovenant/actions/runs/42944117226) was fully green with deploy skipped. The baseline was main run [42942725993](https://github.com/fongway94/WalkInCovenant/actions/runs/42942725993): prototype passed, overall lint failed due to the prototype test's misleading `Node2D` type; that check now passes.

## Verified work

- [x] Reviewed all four baseline frames: cramped view, bright oversized white repeat sheep, incongruous David, invisible contacts, crowded white top-left HUD, near-total occlusion, and successful `1/6` interaction.
- [x] Fixed centered-sprite origins and shadow z-order, added cool down-right cast/contact shadows, `SHEEP_SCALE = 0.66`, compact outlined top-right HUD and wider composition.
- [x] Replaced the inadequate keyed sprites with two hand-matted sheep and a shepherd taken directly from the **user-supplied approved reference**, using explicit, reproducible contours in `tools/proto/extract_reference_sprites.py`. The source palette/light is preserved rather than recoloured; the edited field remains a distinct image, not a pixel-identical reconstruction.
- [x] Replaced the filled foreground polygon with a silhouette/stone matte derived from that region (`tools/proto/build_foreground_mask.py`). In the real `proto_03_occlusion` frame, David's head and torso are visible while individual foreground blades and stones obscure parts of his lower body. It is still an approximate matte, not a complete scene-depth system.
- [x] Compared actual 320×180 and 640×360 logical-size renders at a frozen camera, both captured at 1280×720 and distributed as 640×360 WebP. The 640 UI/placement is somewhat cleaner; field detail is broadly similar, so increased logical size is not a miracle fix. The isolated prototype uses 640; browser performance of this scene has **not** been measured.
- [x] Added a second camera view and measured actual backdrop image translation, not only node hierarchy: run `42945065335` predicted `(-25.54, 0)` pixels and the best image match was `(-26, 0)` (0.46px discrepancy; aligned residual 5.34 vs 28.17 unaligned). This does not prove every obstacle/depth edge.
- [x] Latest log: walk `dx=47.8`, independent sheep movement `12.7`, rock stop `x=612.0`, interaction true and count `1`, repeat remains `1`; harness requires an explicit PASS. The first follow-up run previously found `dx=81.7`, sheep moved `22.0` and collision `612.0`.
- [x] Five higher-detail frames forced WebP quality down to 48 under one job's annotation cap. A second publisher job now transports the very same real Godot captures at quality 78; latest run used 46+29 frame notices across the two jobs and one joined log.

## Latest real-frame review

Decode `python3 tools/proto/decode_proto.py 42945065335 build/proto_82afd91`:

- `proto_01_field_640`: the foliage, path, sheep wool and character share much more of the reference's warm/cool palette than the old white-sticker sprites. The sheep are no longer tiny flecks. **Defect:** one sheep sits directly behind David's head because the harness stages him at `(700,360)` just below a sheep home. The next test uses the actual `(700,470)` scene spawn instead.
- `proto_02_field_320`: comparable same-world view; still no dramatic field-detail difference versus 640, although text/edge placement changes slightly.
- `proto_03_occlusion`: grass blades now partly cover David's legs and torso rather than a diagonal filled polygon hiding him in empty space; inspect more positions later for matte bleed and depth correctness.
- `proto_04_sheep`: the interaction works and wool has shaded form, but David's staff overlaps the sheep because the old interaction staging is too close for the larger reference-derived sprites. The next revision increases interaction distance and spaces the test pair.
- `proto_05_camera`: moving camera retains matching scenery; sheep have limited pose variation and are still effectively static cutouts with bobbing.

The reference is `docs/art-reset/user_selected_reference.png` (681×348). Its bottom viewer arrow/right strip are not world art. The edited 1440×666 backdrop is not pixel-identical, and the new camera still crops its sides. The reference includes another figure absent from the prototype; current background is a flat painting with approximate colliders and only one foreground matte, so trees/fences are not complete depth-aware layers. Sheep flip their baked lighting when changing direction; material edges and contact shadows need continued scrutiny. Neither professional directional animation nor browser performance is established.

## First unfinished tasks

- [ ] Render and inspect the next commit's corrected spawn/interaction spacing and layered boot gait; verify walking, sheep movement, collision, near/far interaction and camera in CI. The idle layers are verified locally to reconstruct the same reference pixels exactly; that is not a Godot animation review.
- [ ] Decode all five captures from **both** prototype publisher jobs, run `check_camera_alignment.py` with that run's logged coordinates, and check deploy remains skipped.
- [ ] Produce a visual reference / previous Godot prototype / improved Godot prototype comparison at equal pane sizes with honest framing labels; supplement with a matched-background detail crop where possible. Inspect and document the largest remaining defects.
- [ ] If capacity remains, address the most visible remaining defect and retest, then update this file, run gates, commit and push only this branch.

## Commands and constraints

```sh
export PATH=/home/user/.venv/bin:$PATH  # this session's Pillow + PyYAML
python3 tools/gd_lint.py
python3 tools/xref_check.py
python3 tools/api_check.py
python3 -c 'import yaml; yaml.safe_load(open(".github/workflows/build-web.yml")); print("workflow YAML OK")'
python3 tools/proto/decode_proto.py <run-id> build/proto_frames_<run-id>
python3 tools/proto/check_camera_alignment.py <field.webp> <camera.webp> --cam-a <x> <y> --cam-b <x> <y> --zoom 0.55
gh run view <run-id> --json status,conclusion,jobs,url
```

Godot cannot run locally; CI/Xvfb is the only renderer. Direct artifact downloads redirect to an inaccessible Azure blob host, but Actions runners transfer frame chunks between jobs and check annotations are accessible here. Keep the 640×360 WebP transport and one joined log annotation. The deploy condition remains `main` or an explicitly requested `publish_preview` dispatch; ordinary branch pushes do not deploy. Production scenes, David chapter, saves and release deployment are out of scope.
