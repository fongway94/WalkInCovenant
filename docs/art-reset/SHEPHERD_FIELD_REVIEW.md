# Shepherd-field prototype: visual review

This is an isolated, playable art prototype, not a production game scene. **It has not been deployed or merged.** Deployment remains paused pending visual approval.

## Compare

- [Reference, earlier prototype and current Godot render](comparison/shepherd_field_ci_comparison.png) — the views use different framing, and the edited backdrop is not identical to the reference.
- [Sheep shadow detail: reference, before and after](comparison/shepherd_field_shadow_ci.png) — enlarged, staged crops from real Godot frames, not gameplay screenshots.

The reference's bottom arrow and right strip are viewer interface, not intended scene art.

## Try it locally

With Godot 4.7.2 installed, run from the repository root:

```sh
godot --path . res://scenes/proto/ShepherdFieldProto.tscn
```

Use the arrow keys to move. Press Space near a sheep to make it hop and count it once. This prototype does not yet include dedicated touch controls.

## What has been checked

The [native CI render](https://github.com/fongway94/WalkInCovenant/actions/runs/42955805136) exercised movement, interaction, camera tracking, rock/trunk/fence collisions, sampled tree/fence occlusion and background alignment, including a 960×540 window. It also checked both sheep stride poses, idle, blocking, hopping and sampled shadow contact in both facing directions. Pixel checks cover only the tested views and positions.

The [same-runner browser experiment](https://github.com/fongway94/WalkInCovenant/actions/runs/42955805136) loaded and moved the prototype in headless Chromium/SwiftShader. Its clipped depth layers rendered faster than full quads in short software-rendered trials; this is **not** a phone, hardware-GPU or production performance measurement. The overall run failed in a separate production-browser test because its post-victory seed was not loaded; a test-setup correction is awaiting another CI run.

## Still needed

- Directional, authored character and sheep animation; the current gait is made from limited reference-derived poses and flips baked lighting.
- More traversal and overlap testing, plus better collision/depth contours for objects still painted into the background.
- Real-device and touch testing, broader resize coverage, and visual approval before any deployment.
