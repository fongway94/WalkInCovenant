extends RefCounted
class_name TapGate
## TapGate — one physical tap means one thing.
##
## Why this exists (docs/AUDIT.md §2). Three nodes read the input stream while a
## conversation is open, and a phone tap arrives as MORE THAN ONE event:
##
##   touch  ->  InputEventScreenTouch   (the real one)
##          ->  InputEventMouseButton   (emulated: emulate_mouse_from_touch)
##
## plus TouchControls synthesises an InputEventAction("interact") for the A
## button, which is a third event for the same thumb. DialogueBox advanced on
## every one of them, so one tap moved two or three lines — the "dialogue appears
## three times" report.
##
## The fix is not "make each handler careful". It is to decide once, for the
## whole game, whether this instant is a new tap. Every consumer asks here and
## exactly one of them gets `true`.
##
## Spacing is deliberately short: a player reading fast taps twice a second, and
## 180 ms only has to be longer than the gap between the sibling events of one
## physical press (measured in single-digit milliseconds).

const SPACING_MS := 180

static var _last_ms := -1000000
static var _taken := 0


## True if this is a NEW tap. Call it only on press events (never on release).
static func take(now_ms: int = -1) -> bool:
	var t := now_ms if now_ms >= 0 else Time.get_ticks_msec()
	if t - _last_ms < SPACING_MS:
		return false
	_last_ms = t
	_taken += 1
	return true


## How many taps have been granted since the last reset — used by tests to prove
## a gesture produced exactly one action.
static func count() -> int:
	return _taken


static func reset() -> void:
	_last_ms = -1000000
	_taken = 0
