extends CanvasLayer
class_name GoliathFight
## GoliathFight — the fight itself, not a quiz about the fight.
##
## Playtest 7 said the confrontation "should be more interesting like fighting
## goliath. throw stone to attack goliath and avoid its attack". So the loop has
## two halves and they alternate:
##
##   HE WINDS UP   a red bar starts growing from his side. He is committed.
##   HE STRIKES      the bar runs at you. Press A / tap before it reaches you and
##                   you step aside. Too late and the spear opens your shoulder.
##   YOU THROW       a marker sweeps across his forehead. Press inside the gold
##                   band and the stone lands. Outside it the stone goes wide.
##
## Three stones in the forehead and it is over; five stones in the pouch, and he
## hands you more when you run dry. There is no game-over screen in this game and
## the fight it retells has a fixed ending (docs/WORLD.md, pillars).
##
## Drawn entirely with _draw: no scene to wire, no animation player to keep in
## step with the state machine. The device is a phone held sideways, so the two
## halves are told apart by COLOUR (red = move, gold = throw) as well as by shape.

signal finished

const HITS_TO_WIN := 3
const STONES := 5
const NERVE := 3

const TELEGRAPH_TIME := 0.9
const STRIKE_TIME := 0.85
const RESOLVE_TIME := 0.85
const DODGE_WINDOW := 0.78      # press before the bar is this far across

enum Phase { TELEGRAPH, STRIKE, AIM, RESOLVE, DONE }

var phase: Phase = Phase.TELEGRAPH
var hits := 0
var stones := STONES
var nerve := NERVE
var round_no := 0

var _t := 0.0
var _strike := 0.0
var _marker := 0.0
var _marker_dir := 1.0
var _band := 0.16
var _dodged := false
var _msg := ""
var _msg_t := 0.0
var _flash := 0.0
var _shake := 0.0
var _layer: Control = null
var _david: TextureRect = null
var _gol: TextureRect = null


func _ready() -> void:
	layer = 22
	_build()


func _frame(path: String) -> AtlasTexture:
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
	_layer.draw.connect(_redraw)
	_layer.gui_input.connect(_on_gui)

	_david = _actor("res://art/characters/%s_idle.png" % CampaignModel.current_hero(), 44, 44)
	_gol = _actor("res://art/characters/goliath_idle.png", 96, 96)


func _actor(path: String, w: float, h: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = _frame(path)
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.anchor_left = 1.0; t.anchor_right = 1.0
	t.anchor_top = 1.0; t.anchor_bottom = 1.0
	t.offset_left = -w - 12.0; t.offset_right = -12.0
	t.offset_top = -h - 14.0; t.offset_bottom = -14.0
	_layer.add_child(t)
	return t


func start() -> void:
	hits = 0
	stones = STONES
	nerve = NERVE
	round_no = 0
	_begin_round()


func _begin_round() -> void:
	phase = Phase.TELEGRAPH
	_t = 0.0
	_strike = 0.0
	_dodged = false
	round_no += 1


# ── the loop ─────────────────────────────────────────────────────────────
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
		Phase.STRIKE:
			_t += delta
			var speed := 1.0 / maxf(0.55, STRIKE_TIME - float(round_no - 1) * 0.05)
			_strike = minf(1.0, _strike + delta * speed)
			if _strike >= 1.0 and not _dodged:
				_take_hit()
		Phase.AIM:
			_t += delta
			_marker += delta * _marker_dir * 2.2
			if _marker >= 1.0:
				_marker = 1.0
				_marker_dir = -1.0
			elif _marker <= -1.0:
				_marker = -1.0
				_marker_dir = 1.0
		Phase.RESOLVE:
			_t += delta
			if _t >= RESOLVE_TIME:
				if hits >= HITS_TO_WIN:
					_finish()
				elif stones <= 0:
					_resupply()
				else:
					_begin_aim()


func _begin_aim() -> void:
	phase = Phase.AIM
	_t = 0.0
	_marker = -1.0
	_marker_dir = 1.0
	# the band tightens as he starts to read you
	_band = maxf(0.09, 0.20 - float(hits) * 0.03)


func _on_gui(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		press()
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		press()


## The one button. It means "step aside" while he is striking and "let go" while
## you are aiming — the same thumb, two different reads.
func press() -> void:
	if phase == Phase.STRIKE and not _dodged:
		if _strike < DODGE_WINDOW:
			_dodged = true
			_shake = 0.6
			AudioDirector.play_sfx("dodge", -4.0)
			_say(I18n.t({"en": "You step aside. The spear bites the dust.",
				"zh": "你侧身让开。枪尖扎进土里。"}), 0.9)
			phase = Phase.RESOLVE
			_t = 0.0
		else:
			_take_hit()
		return
	if phase != Phase.AIM:
		return
	_throw()


func aim_perfect() -> void:
	## Test seam: put the marker in the middle of the band.
	_marker = 0.0


func _take_hit() -> void:
	nerve -= 1
	_shake = 1.0
	_flash = 0.8
	AudioDirector.play_sfx("hit", -3.0)
	if nerve <= 0:
		# No game over. He is a giant; you are a boy with a stone. Getting hit
		# costs you your footing, never the story.
		nerve = 1
		_say(I18n.t({"en": "The shaft throws you back. You get up. He is still shouting.",
			"zh": "枪杆把你掀翻。你爬起来。他还在骂。"}), 1.6)
	else:
		_say(I18n.t({"en": "The shaft catches you. Nerve left: %d",
			"zh": "枪杆扫到你。胆气还剩 %d。"}) % nerve, 1.4)
	phase = Phase.RESOLVE
	_t = 0.0


func _throw() -> void:
	stones -= 1
	var landed := absf(_marker) <= _band
	if landed:
		hits += 1
		_flash = 1.0
		_shake = 0.9
		AudioDirector.play_sfx("hit", -2.0)
		_say(I18n.t({"en": "The stone finds his forehead. %d of %d.",
			"zh": "石子正中他的额头。%d／%d。"}) % [hits, HITS_TO_WIN], 1.2)
	else:
		AudioDirector.play_sfx("miss", -5.0)
		_say(I18n.t({"en": "Wide. The stone is gone into the dust.",
			"zh": "偏了。石子落在土里。"}), 1.1)
	phase = Phase.RESOLVE
	_t = 0.0


func _resupply() -> void:
	stones = 2
	_say(I18n.t({"en": "Your pouch is empty. You take two more from the brook.",
		"zh": "袋子空了。你从溪里又摸了两块。"}), 1.6)
	_begin_aim()


func _finish() -> void:
	phase = Phase.DONE
	finished.emit()


func _say(text: String, secs: float) -> void:
	_msg = text
	_msg_t = secs


# ── drawing ──────────────────────────────────────────────────────────────
func _redraw() -> void:
	var vs: Vector2 = _layer.size
	if vs.x <= 0.0:
		return
	var font := ThemeDB.fallback_font
	# the valley floor and the two hills, at dusk
	_layer.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.08, 0.10, 0.14, 0.86))
	_layer.draw_rect(Rect2(Vector2(0, vs.y * 0.62), Vector2(vs.x, vs.y * 0.38)),
		Color(0.16, 0.15, 0.13, 0.92))
	_layer.draw_rect(Rect2(Vector2(0, vs.y * 0.62), Vector2(vs.x, 2)),
		Color(0.30, 0.26, 0.20, 0.9))

	var jitter := Vector2.ZERO
	if _shake > 0.0:
		jitter = Vector2(sin(_shake * 42.0) * 2.5 * _shake, 0.0)
	_gol.position = jitter
	_david.position = -jitter

	# his pips, your nerve
	for i in range(HITS_TO_WIN):
		var c := Color(0.97, 0.87, 0.65, 0.95) if i < hits else Color(1, 1, 1, 0.18)
		_layer.draw_circle(Vector2(vs.x - 30, 16 + i * 9), 3.0, c)
	for i in range(NERVE):
		var c2 := Color(0.90, 0.45, 0.40, 0.95) if i < nerve else Color(1, 1, 1, 0.16)
		_layer.draw_circle(Vector2(16 + i * 9, 16), 3.0, c2)

	match phase:
		Phase.TELEGRAPH:
			var lean := sin(_t * 20.0) * 2.0
			_gol.rotation = lean * 0.01
			_layer.draw_circle(Vector2(vs.x - 52, 40), 8.0 + sin(_t * 12.0) * 2.0,
				Color(0.92, 0.35, 0.30, 0.35))
			_layer.draw_string(font, Vector2(vs.x - 56, 44), "!",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.86, 0.7, 1.0))
		Phase.STRIKE:
			_gol.rotation = 0.0
			# the spear, coming at you: red means move
			var reach := vs.x * 0.62
			var tip := reach * _strike
			_layer.draw_rect(Rect2(Vector2(vs.x - 60 - tip, vs.y * 0.62 - 5),
				Vector2(tip, 4)), Color(0.85, 0.25, 0.22, 0.55))
			_layer.draw_rect(Rect2(Vector2(vs.x - 62 - tip, vs.y * 0.62 - 7),
				Vector2(6, 8)), Color(1, 0.85, 0.6, 0.95))
		Phase.AIM:
			_gol.rotation = 0.0
			_target(vs.x - 54, vs.y * 0.30)
		Phase.RESOLVE, Phase.DONE:
			_gol.rotation = 0.0

	if _flash > 0.0:
		_layer.draw_rect(Rect2(Vector2.ZERO, vs), Color(1, 0.95, 0.85, 0.30 * _flash))

	# the line that tells you which half of the fight you are in
	var hint := ""
	match phase:
		Phase.TELEGRAPH:
			hint = I18n.t({"en": "He is winding up…", "zh": "他举起枪，在蓄力……"})
		Phase.STRIKE:
			hint = I18n.t({"en": "A / tap — step aside", "zh": "按 A 或点屏幕 —— 让开"})
		Phase.AIM:
			hint = I18n.t({"en": "A / tap — release the stone", "zh": "按 A 或点屏幕 —— 放手"})
	if hint != "":
		_layer.draw_multiline_string(font, Vector2(12, vs.y - 26), hint,
			HORIZONTAL_ALIGNMENT_LEFT, vs.x - 24, 8, 2, Color(0.86, 0.86, 0.8, 0.9))
	_layer.draw_string(font, Vector2(12, vs.y - 12),
		I18n.t({"en": "stones %d" % stones, "zh": "石子 %d 块" % stones}),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.8, 0.82, 0.8, 0.85))
	if _msg != "" and _msg_t > 0.0:
		_layer.draw_multiline_string(font, Vector2(12, 34), _msg,
			HORIZONTAL_ALIGNMENT_LEFT, vs.x - 24, 9, 2, Color(0.97, 0.87, 0.65, 0.95))


## The gold band on his forehead, and the marker that has to be inside it.
func _target(cx: float, cy: float) -> void:
	var half := 26.0
	var band := half * _band / 0.2
	_layer.draw_rect(Rect2(Vector2(cx - half, cy - 7), Vector2(half * 2, 14)),
		Color(0.97, 0.87, 0.65, 0.20))
	_layer.draw_rect(Rect2(Vector2(cx - band, cy - 7), Vector2(band * 2, 14)),
		Color(0.97, 0.87, 0.65, 0.45))
	_layer.draw_rect(Rect2(Vector2(cx + _marker * half - 1, cy - 11), Vector2(2, 22)),
		Color(1, 0.97, 0.9, 1.0))
