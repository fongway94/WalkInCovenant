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
## Set while a conversation, a setpiece or the book owns the screen. While it is
## on, this layer takes no input at all: the panel on top of it gets the taps, and
## the stick cannot drag the player around a paused world. It also removes the
## ordering question — a thumb tap can no longer mean "advance" AND "press A"
## depending on which CanvasLayer sees the event first (AUDIT §2).
var blocked := false

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


## Hit areas are CIRCLES around the buttons that are actually drawn, with a
## generous radius for a thumb. The old rectangles covered a 64x44 corner that
## did not match either circle, so taps near the buttons did surprising things.
func _a_centre(vs: Vector2) -> Vector2:
	return Vector2(vs.x - 30.0, vs.y - 26.0)


func _run_centre(vs: Vector2) -> Vector2:
	return Vector2(vs.x - 84.0, vs.y - 26.0)


func _zone_a(p: Vector2, vs: Vector2) -> bool:
	return p.distance_to(_a_centre(vs)) <= 20.0


func _zone_run(p: Vector2, vs: Vector2) -> bool:
	return p.distance_to(_run_centre(vs)) <= 16.0


## Hand every button and the stick back to neutral. Called when the screen is
## taken over, so a drag that was in progress cannot outlive its owner.
func release_all() -> void:
	if _stick_id != -1:
		_stick_id = -1
		_vec = Vector2.ZERO
		if player != null:
			player.external_intent = Vector2.ZERO
	if _a_held:
		_a_held = false
		_emit_action("interact", false)
	if _run_held:
		_run_held = false
		_emit_action("run", false)
	if viz != null:
		viz.queue_redraw()


func set_blocked(v: bool) -> void:
	if v == blocked:
		return
	blocked = v
	if v:
		release_all()


func _input(event: InputEvent) -> void:
	if player == null or blocked:
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
		if _owns(t.position, t.pressed, t.index, vs):
			_press(t.pressed, t.position, t.index, vs)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var b := event as InputEventMouseButton
		if _owns(b.position, b.pressed, MOUSE_ID, vs):
			_press(b.pressed, b.position, MOUSE_ID, vs)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var dr := event as InputEventScreenDrag
		if dr.index == _stick_id:
			_drag(dr.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		# lets the stick be driven with a mouse on desktop, which is how this
		# gets tested without a phone in hand
		var mm := event as InputEventMouseMotion
		if _stick_id == MOUSE_ID:
			_drag(mm.position)


## Pressing an on-screen button must look EXACTLY like pressing the key.
##
## Input.action_press() only flips the internal action state; it does not put an
## InputEvent into the input pipeline. Region and DialogueBox listen for
## `event.is_action_pressed("interact")`, so on a phone the A button moved the
## player's thumb and nothing else — the reported "cant talk with npc", and the
## reason a conversation could stall with no way to advance it. Node._input sees
## what parse_input_event delivers, so synthesise the real event.
func _emit_action(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)


func _press(pressed: bool, pos: Vector2, idx: int, vs: Vector2) -> void:
	if pressed:
		if _zone_a(pos, vs):
			_a_held = true
			_emit_action("interact", true)
		elif _zone_run(pos, vs):
			_run_held = true
			_emit_action("run", true)
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
			_emit_action("interact", false)
		if _run_held:
			_run_held = false
			_emit_action("run", false)
	viz.queue_redraw()


## Is this event mine? A press belongs to this layer if it lands on a button, or
## on the stick half BELOW the top HUD band; a release belongs to it if it
## finishes something we started.
##
## The band matters: this layer consumes what it claims, and `_input` runs before
## the GUI system. The book (≡) and the language switch are real Buttons in the
## top left, so claiming the whole left half swallowed them — a tap that was
## meant to open the journal went to the stick instead. Above the band, the HUD's
## own controls get the tap.
const HUD_BAND := 0.22

func _owns(pos: Vector2, pressed: bool, idx: int, vs: Vector2) -> bool:
	if pressed:
		if _zone_a(pos, vs) or _zone_run(pos, vs):
			return true
		return pos.y > vs.y * HUD_BAND and pos.x < vs.x * 0.5
	if idx == _stick_id:
		return true
	return _a_held or _run_held


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
	# Buttons are hidden while a conversation or a setpiece owns the screen: the
	# tap that advances a box is the whole screen, and a hidden-but-live button
	# under the dialogue panel was a trap (AUDIT B5).
	if blocked:
		return
	# The stick is floating: it is drawn only while a thumb is on it.
	if _stick_id != -1:
		viz.draw_circle(_origin, 20, Color(1, 1, 1, 0.08))
		viz.draw_arc(_origin, 20, 0, TAU, 24, Color(1, 1, 1, 0.18), 1.0)
		viz.draw_circle(_origin + _vec * 16, 7, Color(0.97, 0.87, 0.65, 0.35))
	# The A and RUN buttons, on the other hand, are ALWAYS on screen. They used
	# to be drawn inside the stick branch, so they existed only while a thumb was
	# already on the screen — a player who had not yet touched anything could not
	# see the button the briefing told them to press (playtest 6).
	var vs := viz.get_viewport_rect().size
	var a_c := _a_centre(vs)
	var r_c := _run_centre(vs)
	# A: the biggest target on the screen, because it is the one button a player
	# cannot get through the game without.
	viz.draw_circle(a_c, 15, Color(0.97, 0.87, 0.65, 0.30 if _a_held else 0.16))
	viz.draw_arc(a_c, 15, 0, TAU, 28, Color(0.97, 0.87, 0.65, 0.55), 1.0)
	viz.draw_string(ThemeDB.fallback_font, a_c + Vector2(-4, 4), "A",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.75))
	viz.draw_circle(r_c, 11, Color(1, 1, 1, 0.16 if _run_held else 0.09))
	viz.draw_arc(r_c, 11, 0, TAU, 24, Color(1, 1, 1, 0.35), 1.0)
	viz.draw_string(ThemeDB.fallback_font, r_c + Vector2(-4, 3), "»",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.6))
