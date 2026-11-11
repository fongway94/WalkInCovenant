# Shepherd-field prototype — continuation

- **Branch:** `arena/905f79d4-walkincovenant` (isolated prototype; do not merge or deploy without approval).
- **Base:** `cec25b525d44dff3b96970415fa2232a13e9d676`, the current `main` merge containing prototype commit `048321b`.
- **Milestone:** playable field, but the visual target is not met. Work in progress: ground the actors, revise framing/UI, and verify camera/occlusion with real Godot frames.
- **Last reviewed CI:** main run [42942725993](https://github.com/fongway94/WalkInCovenant/actions/runs/42942725993), `proto-frames` passed. Overall run failed `lint`: the prototype test typed `field` as `Node2D`, so `api_check` rejects its script-specific members. The previous run was `42940320688` at `048321b`. Deploy was skipped in both; branch pushes do not satisfy the deploy condition.

## Baseline review — all four actual Godot captures

Decoded with `python3 tools/proto/decode_proto.py 42942725993 build/proto_frames_main`. These are 640×360 lossy WebP captures, not concept art.

- `proto_01_field`: the central grass is enlarged and the wall, trees and wider reference composition are mostly out of frame. David is narrow against enlarged rocks/grass; the flock's bright, strongly outlined cream wool contrasts sharply with the scene. White top-left instructions overlap the scene. Shadows do not visibly ground the feet.
- `proto_02_walk`: David and the camera moved to the right (67.7 world pixels reported), but the frame alone does not prove that background landmarks stay aligned. Sheep repeat the same bright silhouette and appear large relative to David; the image is much more tightly cropped than the reference.
- `proto_03_occlusion`: at `(236,606)` only a sliver of David's head is visible behind the lower-left foreground, so this cannot demonstrate useful partial overlap. The foreground is a polygonal copy of the backdrop rather than a carefully isolated silhouette.
- `proto_04_sheep`: interaction increments the HUD to `1/6` and places David next to a sheep. The sheep looks nearly as tall and substantially wider than the character, has a pale flat center, dark outlines and visible keying artifacts in the source; its feet do not convincingly touch the ground. Background foliage/fence look softer than the reference at this crop.

Reference `docs/art-reset/user_selected_reference.png` is 681×348: small warm-edged figures and muted, shaded sheep sit within an expansive wall/path/tree composition. Its native sheep silhouette is roughly 30×25 pixels versus a shepherd roughly 30×46; the edited 1440×666 backdrop is not pixel-identical to it. The reference's bottom arrow and right strip are UI, not field art.

## Checklist

- [x] Confirm branch/base and inspect all four latest baseline frames against the approved image.
- [x] Identify an additional grounding defect: sprite offsets are applied while `centered` is still true; feet are displaced from the body/contact origin. The shadow node's negative z-index can also put it behind the opaque background.
- [ ] Fix grounding, reduce sheep scale, compact/outline the HUD, widen the composition and compare 320 vs 640 logical resolution in real renders.
- [ ] Capture convincing partial occlusion and a second camera position; check static landmarks in actual frames, not just node structure.
- [ ] If the rendered source sprites still look inferior, replace the art-production approach rather than repeatedly recolouring them.
- [ ] Run gates, push, inspect CI frames, compare reference/baseline/new render, iterate, and update this file.

## Commands and constraints

```sh
python3 tools/gd_lint.py
python3 tools/xref_check.py
python3 tools/api_check.py
python3 -c 'import yaml; yaml.safe_load(open(".github/workflows/build-web.yml")); print("workflow YAML OK")'
python3 tools/proto/decode_proto.py <run-id> build/proto_frames_<run-id>
gh run view <run-id> --json status,conclusion,jobs,url
```

Godot is unavailable locally; the `proto-frames` CI job is the renderer. GitHub annotation transport is limited to roughly 50 notices per job, so keep the captured frames 640×360 WebP and logs joined. Direct artifact downloads redirect to an inaccessible Azure blob host in this sandbox; annotations are usable. `Pillow` and `PyYAML` were installed for this session in `/home/user/.venv` (put its `bin` first on `PATH` if needed). The production scene, David chapter, saves and release deployment are outside this prototype's scope.
