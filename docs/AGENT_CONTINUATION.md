# Shepherd-field prototype — continuation

- **Branch:** `arena/905f79d4-walkincovenant`. Do not merge or deploy without approval.
- **Base:** `cec25b525d44dff3b96970415fa2232a13e9d676`, the `main` merge containing prototype commit `048321b`.
- **Latest verified implementation commit:** `96b790a` (the next commit contains an unverified reference-cutout art experiment; inspect its real CI render before judging it).
- **Milestone:** isolated field is playable; art quality remains below the approved reference. This is not a completion claim.
- **Latest reviewed CI:** [42944117226](https://github.com/fongway94/WalkInCovenant/actions/runs/42944117226), commit `96b790a`: overall success, including `proto-frames`, lint, visual and browser; deploy skipped. The earlier main baseline was [42942725993](https://github.com/fongway94/WalkInCovenant/actions/runs/42942725993), whose prototype job passed but overall lint failed on false prototype `Node2D` API errors. That static-check issue is now fixed in the test.

## Completed and verified

- [x] Inspected all four latest baseline frames. Field and walk showed tightly cropped grass, an oversized white repeat-sheep sprite, an incongruous dark/narrow David, imperceptible contacts and crowded white top-left HUD; occlusion hid all but a sliver of David; interaction showed `1/6` but exaggerated the size/style mismatch.
- [x] Corrected centered-sprite offsets so feet meet their body origins; stopped drawing shadows behind the opaque background, added cool down-right cast/contact shadows; set `SHEEP_SCALE` to 0.66; moved the smaller outlined HUD to a dark top-right panel.
- [x] Widened the viewport and compared 320×180 with 640×360 logical sizes at the same frozen camera/framing. Both were rendered by Godot at 1280×720 and encoded to 640×360. World texture detail is broadly similar; 640 gives cleaner UI/subpixel placement, not a dramatic recovery of lost background detail. Chosen for this isolated prototype only; browser performance of this scene has **not** been measured.
- [x] `proto_03_occlusion` now shows David's head/torso with his lower body intersecting foreground grass rather than almost completely hidden. The old filled polygon still hides some path pixels; a silhouette-matte experiment is pending render review.
- [x] Captured a second camera position in `proto_05_camera`. Actual image matching predicts `(-44.76, 0)` pixels and finds `(-45, 0)` (0.24-pixel discrepancy); the unaligned residual was 31.47 versus 6.42 aligned. This verifies the common visible backdrop, **not** every collision or depth edge.
- [x] CI log: walk `dx=81.7`, independent sheep movement `22.0`, rock stop `x=612.0`, interaction `true`, count `1`, repeat remains `1`. Harness now requires an explicit PASS, so a timeout/empty capture cannot be green.

## Screenshots and critique

Decode with `python3 tools/proto/decode_proto.py 42944117226 build/proto_96b790a`:

- `proto_01_field_640` / `proto_02_field_320`: wall, path and trees are visible together; the sheep have become tiny bright white flecks, not the shaded sheep in the reference. David and wool remain different in material, outline and pixel density. The position/lighting of contacts is improved, but they are not convincing artwork yet.
- `proto_03_occlusion`: a partial foreground intersection is visible at `(310,610)`, although the polygon includes non-occluding ground and can cut figures along an artificial edge.
- `proto_04_sheep`: counting works, but sheep still look like identical white stickers and are now too small relative to the reference at the wider camera.
- `proto_05_camera`: wider view shifts as David walks; static painted landmarks translate coherently by the measured camera offset.

The single-job annotation limit forced these five detailed frames to WebP quality **48**, which itself obscures detail. The next commit splits frame annotations across two jobs (same real captures, eight publish steps each, ≤46 frame notices/job) to try to retain quality 78. The approved 681×348 image is `docs/art-reset/user_selected_reference.png`: compare with its bottom viewer arrow cropped, and note the edited 1440×666 backdrop is not pixel-identical.

## Current experiment / exact next steps

- [ ] Push and render the new **hand-matted reference-pixel** David and two sheep variants; source/contours and nearest-neighbour scaling are documented in `tools/proto/extract_reference_sprites.py`. This deliberately changes asset production instead of recolouring the old keyed sprites. They are still static cutouts with simple bobbing, not professional directional animation.
- [ ] Inspect all five new Godot CI frames, especially whether the reference cutouts are grounded and appropriately scaled, and whether the new brightness/stone-based foreground matte (`tools/proto/build_foreground_mask.py`) produces believable partial grass occlusion instead of a diagonal invisible wall.
- [ ] Re-run `check_camera_alignment.py` using the new run's `PROTOLOG` camera coordinates; inspect collision/interaction and both annotation publisher jobs. Compare 640/320 again at the higher WebP quality.
- [ ] Produce a reference / previous render / new render comparison at equal display dimensions and similar framing; label the baseline's tighter camera honestly. Describe major remaining gaps and implement the highest-impact feasible next improvement.
- [ ] Update this file after verified progress, run gates, commit and push only this branch. Check deploy remains skipped.

## Commands and constraints

```sh
export PATH=/home/user/.venv/bin:$PATH  # this sandbox session's Pillow + PyYAML
python3 tools/gd_lint.py
python3 tools/xref_check.py
python3 tools/api_check.py
python3 -c 'import yaml; yaml.safe_load(open(".github/workflows/build-web.yml")); print("workflow YAML OK")'
python3 tools/proto/decode_proto.py <run-id> build/proto_frames_<run-id>
python3 tools/proto/check_camera_alignment.py <field.webp> <camera.webp> --cam-a <x> <y> --cam-b <x> <y> --zoom 0.55
gh run view <run-id> --json status,conclusion,jobs,url
```

Godot cannot run locally; CI/Xvfb is the only renderer. Direct artifact downloads redirect to an inaccessible Azure blob host, but the Actions runners can transfer the frame-chunk artifact between jobs and this sandbox can read check annotations. Preserve 640×360 WebP transport and one joined log annotation. The deploy condition is `main` or an explicitly requested `publish_preview` dispatch; ordinary branch pushes do not deploy. Production scenes, David chapter, saves and release workflow behaviour are out of scope.
