# Shepherd field: visual review

The user played the isolated prototype and **approved its painterly field direction**. That approval is for the prototype, not for the later chapter-wide art or the current full build. Do not deploy the latter without separate approval.

The field is now integrated into the production shepherd act: David and the hired boy are independent actors, strays can be counted and returned, and field camera/collision and save state are restored on exit. The isolated prototype remains available for comparison:

```sh
godot --path . res://scenes/proto/ShepherdFieldProto.tscn
```

## Original comparisons

- [Reference, earlier prototype and Godot render](comparison/shepherd_field_ci_comparison.png) — views use different framing; the edited backdrop is not identical to the reference.
- [Sheep shadow detail: reference, before and after](comparison/shepherd_field_shadow_ci.png) — enlarged, staged crops from real Godot frames, not gameplay screenshots.
- [Right-edge cleanup: before and after](comparison/shepherd_field_edge_ci.png) — real native frames and enlarged edge crops.

The reference's bottom arrow and right strip are viewer interface, not intended world art. The edge paint-over and vegetation/fence occlusion are approximations.

## Current validation and limits

The earlier [native prototype run](https://github.com/fongway94/WalkInCovenant/actions/runs/42960525168) measured movement, collisions, camera tracking, sampled depth alignment and sheep movement. Its Chromium/SwiftShader timings are software-renderer observations, not device performance measurements.

The final local Chromium journey started with a fresh save, used real keyboard input through the witness and Bethlehem, returned to the field, counted one sheep, reloaded and restored 1/3, and continued through the ending: **24 checks passed** without browser page or console errors. A separate, deliberately staged test interrupted a live sheep return and checked cleanup. Field reactions were checked for safe bounds, text fit and speaker/player clearance at four viewport/zoom combinations; a second staged probe resized the live field between four viewport sizes and back, and used emulated touch to move and count a sheep. The expanded probe passed three consecutive runs and also checked rendered Chinese and English brook feedback. These are automated checks, not a human or physical-device playtest.

The native rendered suite passed all **18 frames** under software OpenGL. It stages the duel and aftermath, and the committed baselines predate the intentional art changes. No baseline was replaced: the coarse comparator can miss the wrong scene, so state assertions and human inspection still matter. See `docs/AGENT_CONTINUATION.md` for commands and exact scope.

The field still uses approximate depth/collision contours and limited reference-derived sheep poses. The newly generated overworld, people, setpieces, UI, physical touch, sound and real-device performance need broader human review. Do not promote new baselines or deploy the broader build without the appropriate review and approval.
