extends CanvasLayer
class_name ScreenFade
## ScreenFade — the two-line proof that a scene changed on purpose.
##
## The chapter teleports twice (to the sheep slope, to Bethlehem) and once at the
## end. Without a cut, a teleport reads as a bug: the world is one frame older and
## you are sixty tiles away. A half-second of black between them is the cheapest
## cinematic there is, and it is reusable by every campaign.
##
## It is deliberately NOT a scene transition: no loading, no scene tree surgery.
## The region stays built; only the camera and the player move.

var _rect: ColorRect = null
var _busy := false
## A fade is a third of a second of black. If one is interrupted, or its tween is
## killed with the node behind it, the screen stays black and the game looks
## frozen. This is the guarantee that it cannot: after a run completes, or after
## MAX_BLACK seconds, the rect is transparent (docs/AUDIT.md A8).
const MAX_BLACK := 3.0
var _black_for := 0.0


func _ready() -> void:
	layer = 45
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.color = Color(0.03, 0.04, 0.05, 0.0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)


## fade out → `mid` (where the teleport happens) → fade in → `done`.
func run(out_t: float, mid: Callable, in_t: float, done: Callable = Callable()) -> void:
	if _busy:
		# A second transition inside a first one used to leave two tweens
		# fighting over the same alpha, which reads as a stutter or a stuck
		# black frame. Finish the old one first.
		clear()
	_busy = true
	_black_for = 0.0
	var tw := create_tween()
	tw.tween_property(_rect, "color:a", 1.0, maxf(0.01, out_t))
	tw.tween_callback(func(): if mid.is_valid(): mid.call())
	tw.tween_property(_rect, "color:a", 0.0, maxf(0.01, in_t))
	tw.tween_callback(func():
		_busy = false
		_black_for = 0.0
		clear()
		if done.is_valid():
			done.call())


## Make the fade transparent, whatever state it is in. Never changes resolution,
## never changes the canvas — only this rect's alpha.
func clear() -> void:
	if _rect == null:
		return
	_rect.color.a = 0.0


func is_black() -> bool:
	return _rect != null and _rect.color.a > 0.98


func _process(delta: float) -> void:
	if _rect == null:
		return
	if _rect.color.a > 0.98:
		_black_for += delta
		if _black_for >= MAX_BLACK:
			_black_for = 0.0
			_busy = false
			clear()
			push_warning("ScreenFade: black frame exceeded MAX_BLACK and was cleared")
	else:
		_black_for = 0.0


## Boot: come up out of black rather than popping into a field.
func open_up(t: float = 0.6) -> void:
	_rect.color = Color(0.03, 0.04, 0.05, 1.0)
	var tw := create_tween()
	tw.tween_property(_rect, "color:a", 0.0, maxf(0.01, t))
