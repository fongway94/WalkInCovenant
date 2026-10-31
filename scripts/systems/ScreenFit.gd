extends RefCounted
class_name ScreenFit
## ScreenFit — one place that answers "how big is the screen, and what may sit
## where on it".
##
## Why this exists (docs/AUDIT.md §1). Six subsystems each derived their own
## geometry from get_viewport_rect(): the dialogue box assumed a 320-wide
## canvas, the HUD assumed the objective line could be 285 wide, the touch
## controls put A at vs.x-30, the two setpieces drew at vs.x-54. Each was right
## at exactly one resolution. On a phone in a browser the "resolution" changes
## while the game runs — the address bar hides, the user rotates, the PWA enters
## fullscreen — and nothing re-laid itself out.
##
## Everything here is pure maths over a viewport size, so it can be tested at
## forty resolutions without a window (tests/run_all.gd: _check_layout).
##
## The engine is configured as: stretch mode canvas_items, aspect expand,
## scale_mode fractional. That means the ROOT viewport always reports a size in
## "logical" units: the design is 320x180 at 16:9, and a taller or wider screen
## simply sees more world in one axis. Nothing here letterboxes, ever — black
## bands around the picture would mean the stretch settings were changed, and
## tests/run_all.gd fails the build if they are.

const BASE := Vector2(320.0, 180.0)

## The frame around UI. Scaled so a 16:9 phone and a 4:3 tablet look related.
static func edge(vs: Vector2) -> float:
	return clampf(minf(vs.x, vs.y) * 0.025, 3.0, 12.0)


## The area UI may occupy: inset by `edge`, and never the bottom thumb strip.
static func safe_area(vs: Vector2) -> Rect2:
	var e := edge(vs)
	return Rect2(e, e, maxf(1.0, vs.x - e * 2.0), maxf(1.0, vs.y - e * 2.0))


## Height of the strip where the floating stick and the A button live. UI that
## must stay readable (the dialogue box) is allowed to cover it, because a
## conversation pauses the world and the buttons are hidden while it is open.
static func thumb_strip(vs: Vector2) -> float:
	return clampf(vs.y * 0.16, 18.0, 40.0)


## ── camera ───────────────────────────────────────────────────────────────────
## Half the visible world, in world pixels, for a camera at `zoom`.
static func camera_half(vs: Vector2, zoom: Vector2) -> Vector2:
	return vs * 0.5 / Vector2(maxf(0.0001, zoom.x), maxf(0.0001, zoom.y))


## Keep a camera centre inside a region. If the region is smaller than the view
## on an axis, centre the region on that axis instead of showing the void.
static func clamp_camera(p: Vector2, vs: Vector2, bounds: Rect2, zoom: Vector2) -> Vector2:
	if bounds.size == Vector2.ZERO:
		return p
	var half := camera_half(vs, zoom)
	var x: float
	var y: float
	if bounds.size.x <= half.x * 2.0:
		x = bounds.position.x + bounds.size.x * 0.5
	else:
		x = clampf(p.x, bounds.position.x + half.x, bounds.end.x - half.x)
	if bounds.size.y <= half.y * 2.0:
		y = bounds.position.y + bounds.size.y * 0.5
	else:
		y = clampf(p.y, bounds.position.y + half.y, bounds.end.y - half.y)
	return Vector2(x, y)


## ── dialogue ─────────────────────────────────────────────────────────────────
## The band the dialogue box occupies, and the text column inside it.
##
## `max_h` is a cap on CONTENT, not a clip: the box paginates to fit, so it can
## never grow past this and can never run off the top of the screen. Keeping it
## at 44% of the height is the difference between "a voice in the scene" and
## "a sheet over the game" (docs/AUDIT.md §3).
static func dialogue(vs: Vector2) -> Dictionary:
	var e := edge(vs)
	var w := maxf(120.0, vs.x - e * 2.0)
	var max_h := clampf(vs.y * 0.44, 56.0, 118.0)
	var pad := 5.0
	var portrait := 32.0
	var gap := 5.0
	return {
		"rect": Rect2(e, vs.y - e - max_h, w, max_h),
		"width": w,
		"max_h": max_h,
		"pad": pad,
		"portrait": portrait,
		"text_w": maxf(80.0, w - pad * 2.0 - portrait - gap),
		"overhead": 30.0,      # name row + footer row + the two content margins
	}


## ── cinematic ────────────────────────────────────────────────────────────────
## Letterbox height for the BECOME transition. It is a percentage of the screen,
## so it frames the picture the same way at every size, and it is small enough
## to read as a film bar rather than as the game having shrunk.
static func bar_height(vs: Vector2) -> float:
	return clampf(vs.y * 0.075, 8.0, 26.0)


## ── helpers used by the HUD and setpieces ────────────────────────────────────
static func anchor_top_band(vs: Vector2) -> Rect2:
	var e := edge(vs)
	return Rect2(e, e, vs.x - e * 2.0, clampf(vs.y * 0.16, 18.0, 34.0))


## True when the picture is at or past 16:9 in both axes (used by tests).
static func fills(vs: Vector2, tol: float = 0.5) -> bool:
	return vs.x >= BASE.x - tol and vs.y >= BASE.y - tol
