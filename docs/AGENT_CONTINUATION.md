# Shepherd-field prototype — continuation

- **Branch:** `arena/905f79d4-walkincovenant`; do not merge or deploy without approval.
- **Base:** `cec25b525d44dff3b96970415fa2232a13e9d676`, the `main` merge containing prototype commit `048321b`.
- **Latest fully verified implementation commit:** `d876660`. `9a77db9` added a fence layer; `2a2a3f3` added deeper diagnostics after the render gate failed. Both are pushed but **not verified**. The next working change tests full-world-sized layer quads; its CI result must be reviewed.
- **Milestone:** playable isolated field, now using actors matted from the approved reference. The visual target is not met; this is not a completion claim.
- **Latest reviewed CI:** [42947581848](https://github.com/fongway94/WalkInCovenant/actions/runs/42947581848), commit `2a2a3f3`: **prototype test failed**, lint and visual passed, deploy skipped; browser was running at review. All six rendered frames and the diagnostic map were decoded and inspected because the overflow publisher now runs even on a failed prototype job. The last fully green run is [42946192012](https://github.com/fongway94/WalkInCovenant/actions/runs/42946192012) at `d876660`, deploy skipped. The baseline was main run [42942725993](https://github.com/fongway94/WalkInCovenant/actions/runs/42942725993): prototype passed, overall lint failed due to the prototype test's misleading `Node2D` type; that check now passes.

## Verified work

- [x] Reviewed all four baseline frames: cramped view, bright oversized white repeat sheep, incongruous David, invisible contacts, crowded white top-left HUD, near-total occlusion, and successful `1/6` interaction.
- [x] Fixed centered-sprite origins and shadow z-order, added cool down-right cast/contact shadows, `SHEEP_SCALE = 0.66`, compact outlined top-right HUD and wider composition.
- [x] Replaced the inadequate keyed sprites with two hand-matted sheep and a shepherd taken directly from the **user-supplied approved reference**, using explicit, reproducible contours in `tools/proto/extract_reference_sprites.py`. The source palette/light is preserved rather than recoloured; the edited field remains a distinct image, not a pixel-identical reconstruction.
- [x] Replaced the filled foreground polygon with a silhouette/stone matte derived from that region (`tools/proto/build_foreground_mask.py`). In the real `proto_03_occlusion` frame, David's head and torso are visible while individual foreground blades and stones obscure parts of his lower body. It is still an approximate matte, not a complete scene-depth system.
- [x] Compared actual 320×180 and 640×360 logical-size renders at a frozen camera, both captured at 1280×720 and distributed as 640×360 WebP. The 640 UI/placement is somewhat cleaner; field detail is broadly similar, so increased logical size is not a miracle fix. The isolated prototype uses 640; browser performance of this scene has **not** been measured.
- [x] Added a second camera view and measured actual backdrop image translation, not only node hierarchy: run `42945065335` predicted `(-25.54, 0)` pixels and the best image match was `(-26, 0)` (0.46px discrepancy; aligned residual 5.34 vs 28.17 unaligned). This does not prove every obstacle/depth edge.
- [x] Latest log: walk `dx=67.7`, independent sheep movement `13.4`, boot-layer stride `2.00`, rock stop `x=612.0`, tree trunk stop `x=1148.0`, near interaction true/count `1`, repeat remains `1`, distant interaction false; harness requires an explicit PASS. The gait is a small layered motion, not directional sprite animation.
- [x] A separately y-sorted upper-tree copy partly obscures David behind it; the fence experiment also shows boots behind the rails in the rendered frame. However, the latest renderer tests exposed copy/background misalignment: at `2a2a3f3` the tree raw on/off changes included 52 background samples, and the fence's front/behind metric failed. Those layers are not yet fully verified.
- [x] Five higher-detail frames forced WebP quality down to 48 under one job's annotation cap. A second publisher job now transports the very same real Godot captures at quality 78; latest run used 46+42 frame notices for six frames across the two jobs and one joined log.

## Latest real-frame review and current failure

Decode `python3 tools/proto/decode_proto.py 42947581848 build/proto_2a2a3f3`. All six actual Godot frames plus a sparse difference diagnostic were inspected. The normal overview, grass occlusion, interaction and camera frames remain visually similar to the last green cycle. The upper-tree behind frame visibly covers part of David; in `proto_02_tree_front` the newly matted fence rails cover his boots, while his upper body stays in front of the tree. The fence remains an approximate hand trace, and this is one fixed position, not a complete occlusion audit.

- `9a77db9` run `42947152963` failed its tree toggle test (raw behind/front 139/52), despite adding an origin-aligned tree and fence.
- `2a2a3f3` run `42947581848` diagnosed tree actor change behind/front `101/0`, raw `139/52`, and background `52/52`; so raw differences were not all actor occlusion. Fence values were actor `11/13`, raw `33/6`, background `23/19`, and its test failed. **Do not treat either test as solved.** The diagnostic's subtraction formula can also count a front actor covering a mismatched background; the next change tests direct on/off differences in actor-visible pixels while separately requiring the background match.
- The latest local hypothesis makes both transparent copies the **same 1440×666 quad as the backdrop**, rather than merely sharing an origin: with vertex snapping, differing quad extents may cause different sampling. The source RGB values of all nontransparent pixels are identical and asset generation is deterministic, but only CI can confirm what Godot renders. It also adds two camera-position empty-background comparison gates and a fence-front capture, replacing the interaction capture slot (available in the preceding run).
- The prior fully green run `42946192012` had walk `dx=67.7`, sheep movement `13.4`, boot stride `2.00`, rock stop `x=612`, trunk stop `x=1148`, and correct once-only/nearby interaction. Its camera translation predicted `(-32.39,0)` and measured `(-33,0)`, 0.61px error.

The reference is `docs/art-reset/user_selected_reference.png` (681×348). Its bottom viewer arrow/right strip are not world art. The edited 1440×666 backdrop is not pixel-identical, and the new camera still crops its sides. The reference includes another figure absent from the prototype; most of the background is still a flat painting with approximate colliders and only limited depth layers. Sheep flip their baked lighting when changing direction; material edges and contact shadows need continued scrutiny. Neither professional directional animation nor browser performance is established.

## First unfinished tasks

- [ ] Push the full-quad change after the required gates; decode **all** frames and diagnostics, verify the stronger background-alignment and actor-depth tests, and inspect the fence front/behind views. Fix any failure rather than relaxing the tests to hide a visible issue.
- [ ] Check the run's deploy is skipped and run `check_camera_alignment.py` against its two real overview frames with its logged coordinates. A passing screenshot test does not establish behavior along every path.
- [ ] Update and inspect `docs/art-reset/comparison/shepherd_field_ci_comparison.png` with the newest **verified** CI frame and honest run labels. The 320-vs-640 comparison remains in run `42945561632`; interaction capture is in `42946192012`.
- [ ] Update this file with exact outcome, commit, push only the isolated branch, check CI, and disclose remaining visual/animation/performance limitations.

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
