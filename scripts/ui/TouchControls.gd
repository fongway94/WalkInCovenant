extends CanvasLayer
class_name TouchControls
## TouchControls — a FLOATING virtual stick plus A / run, for phones.
##
## The stick appears where your thumb lands, not at a fixed point: a fixed
## joystick forces the player to look at their thumb, which is the single most
## common failure of phone ports of this genre (docs/FEEL.md §7).
##
## Implemented here rather than relying on an engine widget so there is no
## version-dependent node to discover. It synthesises the same input actions
## the keyboard uses, so Player never knows the difference.
##
## Analog magnitude drives speed exactly as Covenant's field.js did:
##     push = min(1, distance / 44)
## so a gentle tilt walks and a full tilt runs, making the run button a
## convenience rather than a requirement.

const DEADZONE := 12.0
const FULL := 44.0

var player: Player = null
var viz: Control = null

var _stick_id := -1
var _origin := Vector2.ZERO
var _vec := Vector2.ZERO
var _run_held := false
var _a_held := false


func _ready() -> void:
	layer = 12
	viz = Control.new()
	viz.set_anchors_preset(Control.PRESET_FULL_RECT)
	viz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viz.set_script(null)
	add_child(viz)
	viz.draw.connect(_draw_viz)


func bind(p: Player) -> void:
	player = p


func _zone_a(p: Vector2, vs: Vector2) -> bool:
	return p.x > vs.x - 64 and p.y > vs.y - 44


func _zone_run(p: Vector2, vs: Vector2) -> bool:
	return p.x > vs.x - 108 and p.x <= vs.x - 64 and p.y > vs.y - 44


func _input(event: InputEvent) -> void:
	if player == null:
		return
	var vs := get_viewport_rect().size

	if event is InputEventScreenTouch or event is InputEventMouseButton:
		var pressed: bool = event.pressed
		var pos: Vector2 = event.position
		if pressed:
			if _zone_a(pos, vs):
				_a_held = true
				Input.action_press("interact")
			elif _zone_run(pos, vs):
				_run_held = true
				Input.action_press("run")
			elif pos.x < vs.x * 0.5:
				_stick_id = event.index if event is InputEventScreenTouch else 99
				_origin = pos
				_vec = Vector2.ZERO
		else:
			var idx = event.index if event is InputEventScreenTouch else 99
			if idx == _stick_id:
				_stick_id = -1
				_vec = Vector2.ZERO
				player.external_intent = Vector2.ZERO
			if _a_held:
				_a_held = false
				Input.action_release("interact")
			if _run_held:
				_run_held = false
				Input.action_release("run")
		viz.queue_redraw()
		return

	if event is InputEventScreenDrag and event.index == _stick_id:
		var d := event.position - _origin
		var m := d.length()
		if m < DEADZONE:
			_vec = Vector2.ZERO
		else:
			var push := minf(1.0, m / FULL)
			_vec = (d / m) * push
		player.external_intent = _vec
		viz.queue_redraw()


func _draw_viz() -> void:
	if _stick_id == -1:
		return
	# base ring + knob, drawn under the thumb
	viz.draw_circle(_origin, 20, Color(1, 1, 1, 0.08))
	viz.draw_arc(_origin, 20, 0, TAU, 24, Color(1, 1, 1, 0.18), 1.0)
	viz.draw_circle(_origin + _vec * 16, 7, Color(0.97, 0.87, 0.65, 0.35))
	# A / run hints
	var vs := viz.get_viewport_rect().size
	viz.draw_circle(Vector2(vs.x - 32, vs.y - 22), 12, Color(1, 1, 1, 0.10))
	viz.draw_string(ThemeDB.fallback_font, Vector2(vs.x - 36, vs.y - 18), "A",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.5))
	viz.draw_string(ThemeDB.fallback_font, Vector2(vs.x - 92, vs.y - 18), "»",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.5))
