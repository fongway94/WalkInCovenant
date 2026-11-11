# Shepherd-field prototype — continuation

- **Branch:** `arena/905f79d4-walkincovenant`; do not merge or deploy without approval.
- **Base:** `cec25b525d44dff3b96970415fa2232a13e9d676`, the `main` merge containing prototype commit `048321b`.
- **Latest fully verified implementation commit:** `d876660`. Later fence/alignment experiments `9a77db9`, `2a2a3f3`, and `8f4fa9e` are pushed but their prototype jobs failed; the next working change removes nested overlay transforms and must be rendered and reviewed.
- **Milestone:** playable isolated field, now using actors matted from the approved reference. The visual target is not met; this is not a completion claim.
- **Latest reviewed CI:** [42948421904](https://github.com/fongway94/WalkInCovenant/actions/runs/42948421904), commit `8f4fa9e`: **prototype test failed** on residual tree/background mismatch. Lint, visual, and both frame publishers passed; deploy/browser were not complete at review. All frames and the diagnostic map were decoded because the overflow publisher now runs even on a failed prototype job. The last fully green run is [42946192012](https://github.com/fongway94/WalkInCovenant/actions/runs/42946192012) at `d876660`, deploy skipped. The baseline was main run [42942725993](https://github.com/fongway94/WalkInCovenant/actions/runs/42942725993): prototype passed, overall lint failed due to the prototype test's misleading `Node2D` type; that check now passes.

## Verified work

- [x] Reviewed all four baseline frames: cramped view, bright oversized white repeat sheep, incongruous David, invisible contacts, crowded white top-left HUD, near-total occlusion, and successful `1/6` interaction.
- [x] Fixed centered-sprite origins and shadow z-order, added cool down-right cast/contact shadows, `SHEEP_SCALE = 0.66`, compact outlined top-right HUD and wider composition.
- [x] Replaced the inadequate keyed sprites with two hand-matted sheep and a shepherd taken directly from the **user-supplied approved reference**, using explicit, reproducible contours in `tools/proto/extract_reference_sprites.py`. The source palette/light is preserved rather than recoloured; the edited field remains a distinct image, not a pixel-identical reconstruction.
- [x] Replaced the filled foreground polygon with a silhouette/stone matte derived from that region (`tools/proto/build_foreground_mask.py`). In the real `proto_03_occlusion` frame, David's head and torso are visible while individual foreground blades and stones obscure parts of his lower body. It is still an approximate matte, not a complete scene-depth system.
- [x] Compared actual 320×180 and 640×360 logical-size renders at a frozen camera, both captured at 1280×720 and distributed as 640×360 WebP. The 640 UI/placement is somewhat cleaner; field detail is broadly similar, so increased logical size is not a miracle fix. The isolated prototype uses 640; browser performance of this scene has **not** been measured.
- [x] Added a second camera view and measured actual backdrop image translation, not only node hierarchy: run `42945065335` predicted `(-25.54, 0)` pixels and the best image match was `(-26, 0)` (0.46px discrepancy; aligned residual 5.34 vs 28.17 unaligned). This does not prove every obstacle/depth edge.
- [x] Latest log: walk `dx=67.7`, independent sheep movement `13.4`, boot-layer stride `2.00`, rock stop `x=612.0`, tree trunk stop `x=1148.0`, near interaction true/count `1`, repeat remains `1`, distant interaction false; harness requires an explicit PASS. The gait is a small layered motion, not directional sprite animation.
- [x] An upper-tree copy partly obscures David behind it; the fence experiment also shows boots behind the rails. In `8f4fa9e` both objects passed actor-specific front/behind checks and fence background checks, but the tree still changed 16 sampled background pixels at one camera; its alignment gate failed. Those layers are not yet fully verified.
- [x] Five higher-detail frames forced WebP quality down to 48 under one job's annotation cap. A second publisher job now transports the very same real Godot captures at quality 78; latest run used 46+42 frame notices for six frames across the two jobs and one joined log.

## Latest real-frame review and current failure

Decode `python3 tools/proto/decode_proto.py 42948421904 build/proto_8f4fa9e`. The six actual Godot frames and sparse difference diagnostic were decoded; the two fence positions, diagnostic and camera pair were inspected. David is visibly behind the rails at the northern position and in front at the southern position, with the tree partly hiding him at the behind position. The fence remains an approximate hand trace, and these positions do not constitute a complete occlusion audit.

- `9a77db9` run `42947152963` failed its tree toggle test (raw behind/front 139/52), despite adding an origin-aligned tree and fence.
- `2a2a3f3` run `42947581848` diagnosed tree raw/background changes `139/52` and `52/52`, and its fence actor metric failed. That subtraction metric could count a front actor covering a mismatched background; `8f4fa9e` instead checks direct on/off changes in actor-visible pixels while gating background mismatches separately.
- `8f4fa9e` run `42948421904` used full-backdrop-sized overlay images. Tree actor changes were behind/front `103/0`, but its background changed `16/16` samples (failure); fence actor changes `23/0` and fence background `0/0` passed. Whole-frame sparse alignment counts at two cameras were `2` and `3`; they do not supersede the denser tree-region failure. Camera image alignment still passed, predicted `(-60.87,0)`, observed `(-62,0)`, error `1.13px`. Walk, sheep, gait, rock, trunk and interaction checks passed.
- The current working change keeps each depth sprite at the backdrop's exact origin and extent and assigns actors to z-bands by foot y; actors still y-sort within a band. This removes the nested `(ground_y, -ground_y)` transforms, a suspected source of snap-related sampling differences. It also adds two-sided fence collision checks. This is a hypothesis pending the next real render, not a claimed fix.
- The last fully green run `42946192012` had walk `dx=67.7`, sheep movement `13.4`, boot stride `2.00`, rock stop `x=612`, trunk stop `x=1148`, and correct once-only/nearby interaction. Its camera translation predicted `(-32.39,0)` and measured `(-33,0)`, 0.61px error.

The reference is `docs/art-reset/user_selected_reference.png` (681×348). Its bottom viewer arrow/right strip are not world art. The edited 1440×666 backdrop is not pixel-identical, and the new camera still crops its sides. The reference includes another figure absent from the prototype; most of the background is still a flat painting with approximate colliders and only limited depth layers. Sheep flip their baked lighting when changing direction; material edges and contact shadows need continued scrutiny. Neither professional directional animation nor browser performance is established.

## First unfinished tasks

- [ ] Push the exact-origin/z-band change after the required gates; decode **all** frames and diagnostics, verify the stronger background-alignment, actor-depth and two-sided fence collision tests, and inspect the fence front/behind views. Fix any failure rather than relaxing the tests to hide a visible issue.
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
