extends CanvasLayer
class_name GoliathFight
## GoliathFight — the fight itself, not a quiz about the fight.
##
## Playtest 6: "no gameplay of David fight goliath... i just keep talk with
## goliath with nothing going on". Playtest 7: "should make it more interesting
## like fighting goliath. throw stone to attack goliath and avoid its attack".
##
## One button, two different skills, alternating — the smallest loop that still
## contains both halves of a fight:
##
##   HE WINDS UP   he leans back on his spear (a telegraph you can see)
##   HE STRIKES    a red bar runs from his side toward you. Press A / tap while
##                 it is still short: you step aside. Too late or not at all:
##                 the spear opens your shoulder, nerve -1.
##   YOU THROW     a marker sweeps across his forehead. Press inside the lit band
##                 and the stone lands. Outside it the stone goes wide.
##
## Three stones in the forehead end it. Five stones in the pouch, and he hands
## you more if you run dry — this game has no game-over screen (docs/WORLD.md
## pillar 5) and the fight it retells has a fixed ending.
##
## Everything is drawn here with _draw: no sprite animation, no scene to wire.
## The target device is a phone held sideways, so every hitbox is a third of the
## screen wide and the two phases are told apart by COLOUR (red = move, gold =
## throw) as well as by shape.

signal finished

const MAX_HITS := 3
const STONES := 5
const NERVE := 3

enum Phase { TELEGRAPH, STRIKE, AIM, RESOLVE, DONE }

const TELEGRAPH_TIME := 0.85
const STRIKE_TIME := 1.05
const AIM_SWEEP := 0.85

var phase: Phase = Phase.TELEGRAPH
var hits := 0
var stones := STONES
var nerve := NERVE
var round_no := 0

var _t := 0.0                 # phase timer
var _strike := 0.0            # 0..1, how far the strike has travelled
var _marker := 0.0            # 0..1 across his head
var _marker_dir := 1.0
var _band := 0.22             # half-width of the lit band, 0..0.5 of travel
var _dodged := false
var _flash := 0.0             # white flash on impact
var _shake := 0.0
var _msg := ""                # short verdict line, drawn bottom-centre
var _msg_t := 0.0
var _layer: Control = null
var _david: TextureRect = null
var _gol: TextureRect = null


func _ready() -> void:
	layer = 22
	_build()


func _frame(path: String) -> AtlasTexture:
	## A sprite sheet crop: frame 0 of row 0. The sheets are 32x64 (2 cols x 4
	## rows of 16x16), so handing the TextureRect the whole sheet draws four tiny
	## frames of nothing.
	var tex := load(path)
	if tex == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(0, 0, 16, 16)
	return at


func _build() -> void:
	_layer = Control.new()
	_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_layer)
	_layer.draw.connect(_draw_all)
	_layer.gui_input.connect(_on_gui)

	_david = TextureRect.new()
	_david.texture = _frame("res://art/characters/david_idle.png")
	_david.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_david.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_david.anchor_left = 0.0; _david.anchor_right = 0.0
	_david.anchor_top = 1.0; _david.anchor_bottom = 1.0
	_david.offset_left = 26; _david.offset_right = 26 + 48
	_david.offset_top = -78; _david.offset_bottom = -30
	_layer.add_child(_david)

	_gol = TextureRect.new()
	_gol.texture = _frame("res://art/characters/goliath_idle.png")
	_gol.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_gol.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_gol.anchor_left = 1.0; _gol.anchor_right = 1.0
	_gol.anchor_top = 1.0; _gol.anchor_bottom = 1.0
	_gol.offset_left = -116; _gol.offset_right = -12
	_gol.offset_top = -118; _gol.offset_bottom = -18
	_layer.add_child(_gol)


func start() -> void:
	hits = 0
	stones = STONES
	nerve = NERVE
	round_no = 0
	_begin_telegraph()


func _begin_telegraph() -> void:
	phase = Phase.TELEGRAPH
	_t = 0.0
	_dodged = false
	round_no += 1


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 3.0)
	_shake = maxf(0.0, _shake - delta * 3.0)
	_msg_t = maxf(0.0, _msg_t - delta)
	match phase:
		Phase.TELEGRAPH:
			_t += delta
			if _t >= TELEGRAPH_TIME:
				phase = Phase.STRIKE
				_t = 0.0
				_strike = 0.0
				_say("", 0.0)
		Phase.STRIKE:
			_t += delta
			# Faster every round, and never faster than a human can answer.
			var speed := 1.0 / maxf(0.62, STRIKE_TIME - float(round_no) * 0.07)
			_strike = minf(1.0, _strike + delta * speed)
			if _strike >= 1.0:
				_hit_by_spear()
		Phase.AIM:
			_t += delta
			_marker += _marker_dir * delta / AIM_SWEEP
			if _marker >= 1.0:
				_marker = 1.0
				_marker_dir = -1.0
			elif _marker <= 0.0:
				_marker = 0.0
				_marker_dir = 1.0
		Phase.RESOLVE:
			_t += delta
			if _t > 0.55:
				_next_round()
		Phase.DONE:
			pass
	_layer.queue_redraw()


func _next_round() -> void:
	if hits >= MAX_HITS:
		_finish()
		return
	if stones <= 0:
		# Never a dead end: he laughs, you pick up what the brook gave you.
		stones = 2
		_say(I18n.t({"en": "Out of stones? Two more in the pouch.",
			"zh": "石子用完了？袋里又多了两块。"}), 2.0)
	_begin_telegraph()


func _finish() -> void:
	phase = Phase.DONE
	_layer.queue_redraw()
	await get_tree().create_timer(0.7).timeout
	finished.emit()


# ── input: one button, two meanings ───────────────────────────────────────
func _input(event: InputEvent) -> void:
	if phase == Phase.DONE:
		return
	var fire := false
	if event is InputEventScreenTouch:
		fire = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton:
		fire = (event as InputEventMouseButton).pressed
	elif event is InputEventKey:
		var k := event as InputEventKey
		fire = k.pressed and not k.echo
	elif event.is_action_pressed("interact"):
		fire = true
	if fire:
		press()
		get_viewport().set_input_as_handled()


func _on_gui(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		press()


## Public so the headless playthrough can fight the same fight a thumb fights.
func press() -> void:
	match phase:
		Phase.STRIKE:
			# Dodging counts any time before the spear has crossed 80% of the
			# ground. That window is the whole skill of this half of the fight.
			if _strike < 0.8 and not _dodged:
				_dodged = true
				_say(I18n.t({"en": "You step aside. The spear bites the dust.",
					"zh": "你侧身让开。枪尖扎进土里。"}), 0.9)
		Phase.AIM:
			_throw()
		_:
			pass


func is_striking() -> bool:
	return phase == Phase.STRIKE


func is_aiming() -> bool:
	return phase == Phase.AIM


## Test seam: put the marker inside the band before pressing.
func aim_perfect() -> void:
	if phase == Phase.AIM:
		_marker = _target_centre()


func _target_centre() -> float:
	return 0.5


func _hit_by_spear() -> void:
	if _dodged:
		phase = Phase.AIM
		_t = 0.0
		_marker = 0.0
		_marker_dir = 1.0
		_band = maxf(0.10, 0.22 - float(round_no) * 0.01)
		return
	nerve -= 1
	_shake = 1.0
	if nerve <= 0:
		# No game over. He draws blood, you find your feet again.
		nerve = 1
		_say(I18n.t({"en": "The shaft opens your shoulder. Breathe.",
			"zh": "枪杆划开了你的肩膀。呼吸。"}), 2.2)
	else:
		_say(I18n.t({"en": "Too slow — the shaft catches you. Nerve %d of %d.",
			"zh": "慢了一步，枪杆打中了你。胆气还剩 %d／%d。" % [nerve, NERVE]}), 1.8)
	phase = Phase.RESOLVE
	_t = 0.0


func _throw() -> void:
	stones -= 1
	var off := absf(_marker - _target_centre())
	var band := _band
	if off <= band:
		hits += 1
		_flash = 1.0
		AudioDirector.play_sfx("sling", -3.0)
		if hits >= MAX_HITS:
			_say(I18n.t({"en": "The stone finds his forehead.", "zh": "石子陷进他的额头。"}), 1.4)
		else:
			_say(I18n.t({"en": "It lands! He staggers. %d more.", "zh": "打中了！他晃了一下。还差 %d 块。" % (MAX_HITS - hits)}), 1.4)
	else:
		AudioDirector.play_sfx("miss", -5.0)
		_say(I18n.t({"en": "The stone goes wide into the dust.", "zh": "石子打偏了，落进土里。"}), 1.2)
	if hits >= MAX_HITS:
		phase = Phase.RESOLVE
		_t = 0.0
		return
	phase = Phase.RESOLVE
	_t = 0.0


func _say(text: String, secs: float) -> void:
	_msg = text
	_msg_t = secs


# ── drawing ───────────────────────────────────────────────────────────────
func _draw_all() -> void:
	var vs := _layer.size
	var font := ThemeDB.fallback_font
	# the ground he is standing on, and the light behind him
	_layer.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.10, 0.12, 0.14, 0.82))
	var horizon := vs.y - 26.0
	_layer.draw_rect(Rect2(Vector2(0, horizon), Vector2(vs.x, 26)),
		Color(0.24, 0.20, 0.15, 0.9))
	if _shake > 0.0:
		var sx := sin(_shake * 40.0) * 3.0 * _shake
		_layer.position = Vector2(sx, 0)
	else:
		_layer.position = Vector2.ZERO

	# stone pips over his head, nerve pips beside David
	for i in range(MAX_HITS):
		var c := Color(0.97, 0.87, 0.65, 0.95) if i < hits else Color(1, 1, 1, 0.18)
		_layer.draw_circle(Vector2(vs.x - 64 + i * 12, 20), 3.0, c)
	for i in range(NERVE):
		var c2 := Color(0.90, 0.45, 0.40, 0.95) if i < nerve else Color(1, 1, 1, 0.16)
		_layer.draw_circle(Vector2(34 + i * 10, 20), 3.0, c2)
	_layer.draw_string(font, Vector2(24, 34), I18n.t({"en": "you", "zh": "你"}),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.85, 0.85, 0.8, 0.8))
	_layer.draw_string(font, Vector2(vs.x - 92, 34), I18n.t({"en": "goliath", "zh": "歌利亚"}),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.85, 0.85, 0.8, 0.8))

	var hint := ""
	match phase:
		Phase.TELEGRAPH:
			# he leans back on the spear: the tell
			var lean := sin(_t * 18.0) * 3.0
			_gol.rotation = lean * 0.012
			hint = I18n.t({"en": "He is winding up…", "zh": "他举起枪，在蓄力……"})
			_layer.draw_circle(Vector2(vs.x - 64, 96), 9.0 + sin(_t * 10.0) * 2.0,
				Color(0.92, 0.35, 0.30, 0.35))
			_layer.draw_string(font, Vector2(vs.x - 70, 100), "!",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.85, 0.7, 0.95))
		Phase.STRIKE:
			# the danger sweeping toward you; red = move
			var w := _strike * (vs.x - 140.0)
			_layer.draw_rect(Rect2(Vector2(vs.x - 130 - w, horizon - 16),
				Vector2(w, 16)), Color(0.85, 0.25, 0.22, 0.55))
			_layer.draw_rect(Rect2(Vector2(vs.x - 130 - w, horizon - 16),
				Vector2(3, 16)), Color(1, 0.75, 0.55, 0.95))
			hint = I18n.t({"en": "A / tap — step aside", "zh": "按 A 或点屏幕 —— 让开"})
		Phase.AIM:
			# the target band over his forehead
			var hx := vs.x - 64.0
			var hy := 96.0
			_target_draw(hx, hy, font)
			hint = I18n.t({"en": "A / tap — release the stone", "zh": "按 A 或点屏幕 —— 放手"})
		Phase.RESOLVE, Phase.DONE:
			hint = ""

	if _flash > 0.0:
		_layer.draw_rect(Rect2(Vector2.ZERO, vs), Color(1, 0.95, 0.85, 0.35 * _flash))
	if _msg != "" and _msg_t > 0.0:
		_layer.draw_multiline_string(font, Vector2(16, vs.y - 46), _msg,
			HORIZONTAL_ALIGNMENT_LEFT, vs.x - 32, 9, 2, Color(0.97, 0.87, 0.65, 0.95))
	if hint != "":
		_layer.draw_multiline_string(font, Vector2(16, vs.y - 18), hint,
			HORIZONTAL_ALIGNMENT_LEFT, vs.x - 32, 8, 2, Color(0.85, 0.85, 0.8, 0.85))
	_layer.draw_string(font, Vector2(16, vs.y - 4), I18n.t({
		"en": "stones %d" % stones, "zh": "石子 %d 块" % stones}),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.7, 0.72, 0.7, 0.8))


func _target_draw(hx: float, hy: float, font: Font) -> void:
	# a vertical band around the forehead, with the marker crossing it
	var top := hy - 16.0
	var h := 32.0
	_layer.draw_rect(Rect2(Vector2(hx - 9, top), Vector2(18, h)), Color(1, 1, 1, 0.10))
	var band_h := (top + h * (0.5 - _band)) 
	_layer.draw_rect(Rect2(Vector2(hx - 9, band_h), Vector2(18, h * _band * 2.0)),
		Color(0.97, 0.87, 0.65, 0.35))
	var my := top + h * _marker
	_layer.draw_rect(Rect2(Vector2(hx - 13, my - 1.5), Vector2(26, 3)),
		Color(0.99, 0.96, 0.86, 0.95))
	_layer.draw_string(font, Vector2(hx - 8, top - 4), "◎",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.97, 0.87, 0.65, 0.9))
