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
## Analog magnitude drives speed:
##     push = min(1, distance / 40)
## A gentle tilt walks (never below 72% of walk speed — a stick that crawls
## for its first centimetre reads as lag), a tilt of 0.9+ runs, so the run
## button is a convenience rather than a requirement. The dead zone is 8 px:
## wide enough to ignore thumb tremor, narrow enough that the very first
## nudge already moves the pilgrim.

const MOUSE_ID := 99   # synthetic touch id for mouse input
const DEADZONE := 8.0
const FULL := 40.0

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
	# CanvasLayer is not a CanvasItem, so it has no get_viewport_rect();
	# ask the viewport for its visible rect instead.
	var vs: Vector2 = get_viewport().get_visible_rect().size

	# One branch per concrete event type, each cast before use. GDScript cannot
	# narrow a type across `or`, and InputEventMouseButton has no `index` at
	# all, so reading .pressed/.position/.index off a base InputEvent is a
	# runtime failure — the whole control layer would go dead on device.
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		_press(t.pressed, t.position, t.index, vs)
	elif event is InputEventMouseButton:
		var b := event as InputEventMouseButton
		_press(b.pressed, b.position, MOUSE_ID, vs)
	elif event is InputEventScreenDrag:
		var dr := event as InputEventScreenDrag
		if dr.index == _stick_id:
			_drag(dr.position)
	elif event is InputEventMouseMotion:
		# lets the stick be driven with a mouse on desktop, which is how this
		# gets tested without a phone in hand
		var mm := event as InputEventMouseMotion
		if _stick_id == MOUSE_ID:
			_drag(mm.position)


func _press(pressed: bool, pos: Vector2, idx: int, vs: Vector2) -> void:
	if pressed:
		if _zone_a(pos, vs):
			_a_held = true
			Input.action_press("interact")
		elif _zone_run(pos, vs):
			_run_held = true
			Input.action_press("run")
		elif pos.x < vs.x * 0.5:
			_stick_id = idx
			_origin = pos
			_vec = Vector2.ZERO
	else:
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


func _drag(pos: Vector2) -> void:
	var d := pos - _origin
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
