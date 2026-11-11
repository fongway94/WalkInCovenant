# Shepherd-field prototype: visual review

This is an isolated, playable art prototype, not a production game scene. **It has not been deployed or merged.** Deployment remains paused pending visual approval.

## Compare

- [Reference, earlier prototype and current Godot render](comparison/shepherd_field_ci_comparison.png) — the views use different framing, and the edited backdrop is not identical to the reference.
- [Sheep shadow detail: reference, before and after](comparison/shepherd_field_shadow_ci.png) — enlarged, staged crops from real Godot frames, not gameplay screenshots.
- [Right-edge cleanup: before and after](comparison/shepherd_field_edge_ci.png) — real native frames and enlarged edge crops.

The reference's bottom arrow and right strip are viewer interface, not intended scene art.

## Try it locally

With Godot 4.7.2 installed, run from the repository root:

```sh
godot --path . res://scenes/proto/ShepherdFieldProto.tscn
```

Use the arrow keys to move. Press Space near a sheep to make it hop and count it once. This prototype does not yet include dedicated touch controls.

## What has been checked

The [native CI render](https://github.com/fongway94/WalkInCovenant/actions/runs/42960525168) exercised movement, interaction, camera tracking, rock/trunk/fence collisions, sampled tree/fence occlusion and background alignment, including a 960×540 window. It also checked both sheep stride poses, idle, blocking, hopping and sampled shadow contact in both facing directions. Pixel checks cover only the tested views and positions.

The [same-runner browser experiment](https://github.com/fongway94/WalkInCovenant/actions/runs/42960525168) loaded and moved the prototype in headless Chromium/SwiftShader. Its clipped depth layers rendered faster than full quads in short software-rendered trials; this is **not** a phone, hardware-GPU or production performance measurement. All applicable validation jobs passed, and deployment was skipped. The separate production-browser suite passed 30/30 checks, including a seeded duel and an independently seeded post-victory ending; this is not a continuous full-game playthrough.

The previously visible viewer strip at the backdrop's right edge has an approximate 40-pixel paint-over. The new native and Web pan frames were inspected; the cleaned edge is visible in the comparison above.

## Still needed

- Directional, authored character and sheep animation; the current gait is made from limited reference-derived poses and flips baked lighting.
- More traversal and overlap testing, plus better collision/depth contours for objects still painted into the background; the edge paint-over is approximate.
- Real-device and touch testing, broader resize coverage, and visual approval before any deployment.
