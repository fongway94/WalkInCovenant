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


func _ready() -> void:
	layer = 45
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.color = Color(0.03, 0.04, 0.05, 0.0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)


## fade out → `mid` (where the teleport happens) → fade in → `done`.
func run(out_t: float, mid: Callable, in_t: float, done: Callable = Callable()) -> void:
	var tw := create_tween()
	tw.tween_property(_rect, "color:a", 1.0, maxf(0.01, out_t))
	tw.tween_callback(func(): if mid.is_valid(): mid.call())
	tw.tween_property(_rect, "color:a", 0.0, maxf(0.01, in_t))
	if done.is_valid():
		tw.tween_callback(func(): done.call())


## Boot: come up out of black rather than popping into a field.
func open_up(t: float = 0.6) -> void:
	_rect.color = Color(0.03, 0.04, 0.05, 1.0)
	var tw := create_tween()
	tw.tween_property(_rect, "color:a", 0.0, maxf(0.01, t))
