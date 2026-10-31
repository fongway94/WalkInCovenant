extends Camera2D
class_name CameraRig
## CameraRig — deadzone + lookahead + clamp + pixel snap (docs/FEEL.md §3).
##
## Deadzone kills micro-jitter: the player wanders inside a box and the camera
## does not chase every pixel. That calm is most of what reads as "professional".
## Smoothing is frame-rate independent exponential lerp — never the
## `pos += (target-pos)*0.1` form, which changes with frame rate.

# Tightened at playtest 3: a 48 px deadzone plus an 8/s lerp let the pilgrim
# wander three tiles before the world answered, which on a phone screen reads
# as the same lag the input path was blamed for. Still a deadzone — the calm
# is the point — but the camera now notices within about two tiles.
@export var deadzone := Vector2(36, 24)
@export var lookahead := Vector2(24, 12)
@export var smooth_speed := 11.0
@export var shake_power := 2.0

var follow: Node2D = null
var bounds := Rect2()
var _look := Vector2.ZERO
var _shake := 0.0
var _cine := false
var _cine_pos := Vector2.ZERO
var _cine_tw: Tween = null


func _ready() -> void:
	# Godot's built-in smoothing fights pixel snapping; we do our own.
	position_smoothing_enabled = false
	make_current()
	# The viewport changes size when a phone rotates, when the browser's address
	# bar slides away, and when the PWA enters fullscreen. Nothing used to react
	# (docs/AUDIT.md A3): the camera kept a clamp computed for the old shape and
	# the player could sit off-centre with the region edge in view.
	var vp := get_viewport()
	if vp != null:
		vp.size_changed.connect(_on_view_changed)


func set_follow(n: Node2D) -> void:
	follow = n
	if follow:
		global_position = _clamp(follow.global_position)


## A scripted shot: hold the camera on a world point for `secs`, ignoring the
## player. `resume_follow` hands it back. Nothing else in the camera changes —
## the clamp, the deadzone and the shake all behave exactly as before once the
## shot is over.
func pan_to(point: Vector2, secs: float) -> void:
	_cine = true
	_cine_pos = global_position
	_kill_cine()
	_cine_tw = create_tween()
	_cine_tw.tween_property(self, "_cine_pos", _clamp(point), maxf(0.05, secs))


## Handing the shot back. Both entrances kill whatever shot is running first: a
## `pan_to` followed quickly by `resume_follow` (dismiss a box faster than the
## pan takes) used to leave two tweens writing `_cine_pos`, and the camera
## jumped between them (BUG-008).
func resume_follow(secs: float = 0.7) -> void:
	if follow == null:
		_cine = false
		return
	_kill_cine()
	_cine_tw = create_tween()
	_cine_tw.tween_property(self, "_cine_pos", _clamp(follow.global_position),
		maxf(0.05, secs))
	_cine_tw.tween_callback(func(): _cine = false)


func _kill_cine() -> void:
	if _cine_tw != null and _cine_tw.is_valid():
		_cine_tw.kill()
	_cine_tw = null


func shake(amount: float = 1.0) -> void:
	if GameState.data["settings"].get("reduce_motion", false):
		return
	_shake = maxf(_shake, amount)


func _process(delta: float) -> void:
	if _cine:
		global_position = _cine_pos
		return
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
		var pl := follow as Player
		var f: Vector2i = pl.facing
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


## Godot's built-in smoothing fights pixel snapping; we do our own.
func _on_view_changed() -> void:
	if follow != null:
		global_position = _clamp(follow.global_position)


## Keep the camera centre inside the region, using the same maths the layout
## module uses everywhere else (docs/AUDIT.md A2).
func _clamp(p: Vector2) -> Vector2:
	return ScreenFit.clamp_camera(p, get_viewport_rect().size, bounds, zoom)
