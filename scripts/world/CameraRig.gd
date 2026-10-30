extends Camera2D
class_name CameraRig
## CameraRig — deadzone + lookahead + clamp + pixel snap (docs/FEEL.md §3).
##
## Deadzone kills micro-jitter: the player wanders inside a box and the camera
## does not chase every pixel. That calm is most of what reads as "professional".
## Smoothing is frame-rate independent exponential lerp — never the
## `pos += (target-pos)*0.1` form, which changes with frame rate.

@export var deadzone := Vector2(48, 32)
@export var lookahead := Vector2(24, 12)
@export var smooth_speed := 8.0
@export var shake_power := 2.0

var follow: Node2D = null
var bounds := Rect2()
var _look := Vector2.ZERO
var _shake := 0.0


func _ready() -> void:
	# Godot's built-in smoothing fights pixel snapping; we do our own.
	position_smoothing_enabled = false
	make_current()


func set_follow(n: Node2D) -> void:
	follow = n
	if follow:
		global_position = _clamp(follow.global_position)


func shake(amount: float = 1.0) -> void:
	if GameState.data["settings"].get("reduce_motion", false):
		return
	_shake = maxf(_shake, amount)


func _process(delta: float) -> void:
	if follow == null:
		return
	var fp := follow.global_position
	var diff := fp - global_position

	# deadzone: only chase what leaves the box
	var push := Vector2.ZERO
	if absf(diff.x) > deadzone.x * 0.5:
		push.x = diff.x - signf(diff.x) * deadzone.x * 0.5
	if absf(diff.y) > deadzone.y * 0.5:
		push.y = diff.y - signf(diff.y) * deadzone.y * 0.5

	# lookahead toward facing
	var want_look := Vector2.ZERO
	if follow is Player:
		var f: Vector2i = follow.facing
		want_look = Vector2(f.x, f.y) * lookahead
	_look = _look.lerp(want_look, 1.0 - exp(-6.0 * delta))

	var target := _clamp(fp + push + _look)
	global_position = global_position.lerp(target, 1.0 - exp(-smooth_speed * delta))

	# pixel-snap the camera or the whole world shimmers
	global_position = global_position.round()

	if _shake > 0.01:
		_shake = maxf(0.0, _shake - delta * 6.0)
		offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * shake_power
	else:
		offset = Vector2.ZERO


func _clamp(p: Vector2) -> Vector2:
	if bounds.size == Vector2.ZERO:
		return p
	var vs := get_viewport_rect().size
	var half := vs * 0.5 / maxf(0.0001, zoom.x)
	# if the region is smaller than the view, centre it (Covenant had this case)
	var x: float
	var y: float
	if bounds.size.x <= half.x * 2:
		x = bounds.position.x + bounds.size.x * 0.5
	else:
		x = clampf(p.x, bounds.position.x + half.x, bounds.end.x - half.x)
	if bounds.size.y <= half.y * 2:
		y = bounds.position.y + bounds.size.y * 0.5
	else:
		y = clampf(p.y, bounds.position.y + half.y, bounds.end.y - half.y)
	return Vector2(x, y)
