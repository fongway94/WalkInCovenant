# Shepherd field: visual review

The user played the isolated prototype and **approved its painterly field direction**. That art approval is for the prototype, not for the later chapter-wide art. They later requested a one-time public deployment of the current build for phone playtesting; this does not constitute broader art approval or authorization for future deployments.

The field is integrated into the production shepherd act: David and the hired boy are independent actors, strays can be counted and returned, and field camera/collision and save state are restored on exit. A later, unpublished [detail pass](QUALITY_REVIEW.md) restores pixels from the full attached reference in the integrated field; it does not change the isolated prototype. The prototype remains available for comparison:

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

The latest local Chromium journey started with a fresh save, used real keyboard input through the witness and Bethlehem, returned to the field, counted one sheep, reloaded and restored 1/3, and continued through the ending: **33 checks passed** without browser page or console errors, including a separately staged cleanup interruption. The last sheep updates the HUD to 3/3 before its dialogue; that count follows real language-button clicks without advancing the box. Bethlehem arrival and elder dialogue also switch the visible objective without advancing the story, and a separate witness probe checks the same. Field reactions were checked for safe bounds, text fit and speaker/player clearance at four viewport/zoom combinations; a staged probe resized the field and used emulated touch to move and count a sheep. It also exercised mouse and emulated-touch HUD switches during an opening dialogue, and checked rendered Chinese and English brook feedback. These are automated checks, not a human or physical-device playtest.

The native rendered suite passed all **18 frames** under software OpenGL. It stages the duel and aftermath, and the committed baselines predate the intentional art changes. No baseline was replaced: the coarse comparator can miss the wrong scene, so state assertions and human inspection still matter. See `docs/AGENT_CONTINUATION.md` for commands and exact scope.

The field still uses approximate depth/collision contours and limited reference-derived sheep poses. The newly generated overworld, people, setpieces, UI, physical touch, sound and real-device performance need broader human review. Do not promote new baselines or make further deployments without the appropriate review and approval.
