extends CanvasLayer
class_name StoneChoice
## StoneChoice — 1 Samuel 17:40, as the one moment in the chapter where the
## player's own hands decide something that the story then uses.
##
## Nine stones lie in the shallow water. Five of them are wanted. A stone is
## chosen by touching it; touching it again puts it back. The count is always on
## screen, and the fifth one does not finish the scene — the player still has to
## say yes, because "choose five" and "keep these five" are two different acts.
##
## Deliberately NOT a grid inventory: the stones lie where the water is, in the
## same 16px pixel world the rest of the game is drawn in, and the ones taken
## lift out of the brook into the bag at the bottom of the screen. The scene is
## the map, not a menu over it.
##
## Input: touch, mouse, and the pad/stick. One thumb, one stone — the same
## TapGate arbitration the world uses, so a tap and its emulated mouse twin
## cannot take and untake a stone in the same instant.

signal finished(chosen: int)

const MAX_ON_SCREEN := 9
const TOUCH_SLOP := 14.0        # px around a stone that still counts as the stone

var need := 5
var pool := 9
## {pos: Vector2 (unit space), taken: bool, shade: int}
var stones: Array = []
var confirmed := false

var _layer: Control = null
var _msg := ""
var _msg_t := 0.0
var _cursor := -1


func _ready() -> void:
	layer = 24
	_build()


func _build() -> void:
	_layer = Control.new()
	_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_layer)
	_layer.draw.connect(_draw_all)
	_layer.gui_input.connect(_on_gui)


## Nine stones laid out in the water, with jitter so it reads as a brook floor
## rather than a row of buttons. The layout is unit-space; _stone_pos() scales
## it to whatever the screen actually is.
func start(want: int = 5, total: int = 9) -> void:
	need = maxi(1, want)
	pool = clampi(total, need, MAX_ON_SCREEN)
	stones = []
	for i in range(pool):
		var col := i % 5
		var row := i / 5
		var jx := 0.06 if (i % 2) == 0 else -0.05
		var jy := 0.03 if (i % 3) == 0 else -0.02
		stones.append({
			"pos": Vector2(0.16 + float(col) * 0.17 + jx, 0.46 + float(row) * 0.16 + jy),
			"taken": false,
			"shade": i % 3,
		})
	confirmed = false
	_msg = ""
	_msg_t = 0.0
	_cursor = -1


func chosen_count() -> int:
	var n := 0
	for s in stones:
		if bool(s["taken"]):
			n += 1
	return n


func is_full() -> bool:
	return chosen_count() >= need


func _view() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return ScreenFit.BASE
	return vp.get_visible_rect().size


func _stone_pos(i: int) -> Vector2:
	var vs := _view()
	var p: Vector2 = stones[i]["pos"]
	return Vector2(p.x * vs.x, p.y * vs.y)


func _confirm_rect() -> Rect2:
	var vs := _view()
	var w := clampf(vs.x * 0.30, 78.0, 132.0)
	var h := clampf(vs.y * 0.13, 18.0, 26.0)
	return Rect2(Vector2(vs.x * 0.5 - w * 0.5, vs.y - h - 12.0), Vector2(w, h))


# ── input ────────────────────────────────────────────────────────────────
func _on_gui(event: InputEvent) -> void:
	var at := Vector2.ZERO
	var hit := false
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		at = (event as InputEventMouseButton).position
		hit = true
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		at = (event as InputEventScreenTouch).position
		hit = true
	if not hit:
		return
	if not TapGate.take():
		return
	tap_at(at)


## Test seam and thumb seam at once: what a tap anywhere does.
func tap_at(at: Vector2) -> void:
	if confirmed:
		return
	if is_full() and _confirm_rect().has_point(at):
		confirm()
		return
	var i := nearest_stone(at)
	if i >= 0:
		toggle(i)
	elif is_full():
		_msg = I18n.t({"en": "Five is what he takes. Not six.",
			"zh": "他拿的就是五块。不是六块。"})
		_msg_t = 1.2


func nearest_stone(at: Vector2) -> int:
	var best := -1
	var bd := TOUCH_SLOP * maxf(1.0, _view().x / 320.0)
	for i in range(stones.size()):
		var d: float = _stone_pos(i).distance_to(at)
		if d < bd:
			bd = d
			best = i
	return best


## Take it, or put it back. A stone already in the bag cannot be taken twice:
## the bag is the count, so a double tap on the same stone is a no-op after the
## second one returns it.
func toggle(i: int) -> void:
	if i < 0 or i >= stones.size() or confirmed:
		return
	var s: Dictionary = stones[i]
	if bool(s["taken"]):
		# Putting one back is ALWAYS allowed, including when the bag is full —
		# that is exactly the moment the player needs it, and the old guard
		# refused here while the message told them to do the impossible
		# (BUG-002). The docstring always said "touching it again puts it back";
		# now the code does.
		s["taken"] = false
		AudioDirector.play_sfx("pickup", -8.0)
		_layer.queue_redraw()
		return
	if is_full():
		_msg = I18n.t({"en": "Five. That is the number.",
			"zh": "五块。就这个数。"})
		_msg_t = 1.1
		return
	s["taken"] = true
	AudioDirector.play_sfx("pickup", -4.0)
	GameState.record_way("notice")
	if is_full():
		_msg = I18n.t({"en": "Five in your hand. Keep these?",
			"zh": "手里有五块了。就要这些？"})
		_msg_t = 2.0
	_layer.queue_redraw()


## Pad/stick support, so the scene is playable without a touch screen.
func move_cursor(step: int) -> void:
	if stones.is_empty():
		return
	_cursor = clampi(_cursor + step, 0, stones.size() - 1)
	_layer.queue_redraw()


## One button, in this order: keep the five if there are five, otherwise take
## or return the stone the cursor is on. This used to try the cursor first, and
## once the cursor had ever been set it could never be unset — so on a keyboard
## the fifth stone was the last thing the player could do (BUG-001: the brook
## scene could not be finished without a mouse).
func press() -> void:
	if is_full():
		confirm()
	elif _cursor >= 0:
		toggle(_cursor)


func confirm() -> void:
	if confirmed or not is_full():
		return
	confirmed = true
	AudioDirector.play_sfx("sling", -6.0)
	_layer.queue_redraw()
	finished.emit(chosen_count())


func _input(event: InputEvent) -> void:
	if confirmed:
		return
	if event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_LEFT:
			move_cursor(-1)
			get_viewport().set_input_as_handled()
		elif k == KEY_RIGHT:
			move_cursor(1)
			get_viewport().set_input_as_handled()
		elif k in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_A]:
			press()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		press()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_msg_t = maxf(0.0, _msg_t - delta)
	_layer.queue_redraw()


# ── drawing ──────────────────────────────────────────────────────────────
func _draw_all() -> void:
	var vs: Vector2 = _layer.size
	if vs.x <= 0.0:
		return
	var font := ThemeDB.fallback_font
	var e := ScreenFit.edge(vs)

	# the brook: sky-ish dusk, then a band of shallow water over pale stones
	_layer.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.07, 0.09, 0.11, 0.94))
	var bank := vs.y * 0.33
	var water := vs.y * 0.62
	_layer.draw_rect(Rect2(Vector2(0, bank), Vector2(vs.x, water - bank)),
		Color(0.13, 0.20, 0.24, 0.96))
	_layer.draw_rect(Rect2(Vector2(0, bank), Vector2(vs.x, 2)), Color(0.34, 0.40, 0.36, 0.8))
	_layer.draw_rect(Rect2(Vector2(0, water), Vector2(vs.x, vs.y - water)),
		Color(0.20, 0.18, 0.15, 0.96))
	# ripples, so the water is water and not a rectangle
	for i in range(6):
		var y := bank + 6.0 + float(i) * ((water - bank) * 0.16)
		var w := vs.x * (0.30 + 0.06 * float(i % 3))
		_layer.draw_rect(Rect2(Vector2(vs.x * 0.10 + float(i % 2) * vs.x * 0.22, y),
			Vector2(w, 1.0)), Color(0.30, 0.42, 0.44, 0.35))

	# the nine stones
	var rad := clampf(vs.x * 0.020, 5.0, 9.0)
	for i in range(stones.size()):
		var s: Dictionary = stones[i]
		if bool(s["taken"]):
			continue
		var p := _stone_pos(i)
		var shade: int = int(s["shade"])
		var palette: Array[Color] = [Color(0.62, 0.60, 0.55), Color(0.55, 0.53, 0.50),
			Color(0.68, 0.66, 0.60)]
		var body: Color = palette[clampi(shade, 0, 2)]
		_layer.draw_circle(p + Vector2(1.0, 1.5), rad, Color(0.10, 0.14, 0.15, 0.45))
		_layer.draw_circle(p, rad, body)
		_layer.draw_circle(p + Vector2(-rad * 0.3, -rad * 0.3), rad * 0.45,
			Color(0.86, 0.85, 0.80, 0.7))
		if i == _cursor:
			_layer.draw_arc(p, rad + 3.0, 0.0, TAU, 20, Color(0.97, 0.87, 0.65, 0.9), 1.5)

	# the bag, filling up as stones are taken
	var n := chosen_count()
	var bag_w := clampf(vs.x * 0.34, 90.0, 150.0)
	var bag := Rect2(Vector2(vs.x * 0.5 - bag_w * 0.5, vs.y - 40.0), Vector2(bag_w, 22.0))
	_layer.draw_rect(bag, Color(0.24, 0.19, 0.14, 0.92))
	_layer.draw_rect(Rect2(bag.position, Vector2(bag.size.x, 1.5)), Color(0.62, 0.50, 0.30, 0.9))
	for i in range(need):
		var c := Vector2(bag.position.x + 10.0 + float(i) * (bag.size.x - 20.0) / float(need),
			bag.position.y + bag.size.y * 0.5)
		if i < n:
			_layer.draw_circle(c, 4.0, Color(0.78, 0.76, 0.70, 1.0))
			_layer.draw_circle(c + Vector2(-1.2, -1.2), 1.6, Color(0.93, 0.92, 0.86, 1.0))
		else:
			_layer.draw_arc(c, 4.0, 0.0, TAU, 14, Color(1, 1, 1, 0.22), 1.0)

	var head := I18n.t({"en": "Five smooth stones", "zh": "五块光滑的石子"})
	_layer.draw_string(font, Vector2(e + 2, e + 10), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
		Color(0.96, 0.90, 0.76, 1.0))
	_layer.draw_string(font, Vector2(e + 2, e + 24),
		I18n.t({"en": "%d / %d" % [n, need], "zh": "%d／%d" % [n, need]}),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.97, 0.87, 0.65, 1.0))

	var hint := I18n.t({"en": "Tap a stone to take it. Tap it again to put it back.",
		"zh": "点一块石头就拿起来。再点一下放回去。"})
	if is_full():
		hint = I18n.t({"en": "Five. Press A to keep these five.",
			"zh": "五块了。按 A 就要这五块。"})
	_layer.draw_multiline_string(font, Vector2(e + 2, vs.y - 58.0), hint,
		HORIZONTAL_ALIGNMENT_LEFT, vs.x - e * 2.0 - 4.0, 8, 2,
		Color(0.86, 0.86, 0.8, 0.95))

	if is_full():
		var r := _confirm_rect()
		_layer.draw_rect(r, Color(0.30, 0.24, 0.12, 0.96))
		_layer.draw_rect(Rect2(r.position, Vector2(r.size.x, 1.5)), Color(0.97, 0.87, 0.65, 0.9))
		_layer.draw_rect(Rect2(Vector2(r.position.x, r.position.y + r.size.y - 1.5),
			Vector2(r.size.x, 1.5)), Color(0.97, 0.87, 0.65, 0.9))
		_layer.draw_string(font, Vector2(r.position.x + 8.0, r.position.y + r.size.y * 0.72),
			I18n.t({"en": "KEEP THEM", "zh": "就要这些"}),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.94, 0.80, 1.0))

	if _msg != "" and _msg_t > 0.0:
		_layer.draw_multiline_string(font, Vector2(e + 2, vs.y * 0.30), _msg,
			HORIZONTAL_ALIGNMENT_LEFT, vs.x - e * 2.0 - 4.0, 8, 2,
			Color(0.95, 0.72, 0.60, 0.95))
