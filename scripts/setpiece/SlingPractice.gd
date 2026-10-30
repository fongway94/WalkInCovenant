extends CanvasLayer
class_name SlingPractice
## SlingPractice — chapter 2's drill, and the lesson that makes the boss fair.
##
## The fight asks exactly one input in its aim phase: press A inside a lit band
## of a sweeping marker. Nothing in the game taught that input before the giant
## was already in front of you, which is why the first throw read as luck.
##
## So: three clay jars on a wall, the same sweeping marker, a wider band, and no
## consequence for missing. Hit three and the beat ends. This is a DRILL, not an
## event in 1 Samuel 17 — the data says so in the narration ("This is not war.
## This is practice."), because a game may add practice and may not add history.
##
## The band narrows a little with each jar, so the third throw is closer to the
## fight's timing than the first.

signal finished

const SWEEP := 1.20            # seconds for one pass of the marker
const RESOLVE_TIME := 0.70     # how long the verdict stays up
const BAND_START := 0.26       # generous: half the world is not a test
const BAND_STEP := 0.03

enum Phase { AIM, RESOLVE, DONE }

var phase: Phase = Phase.AIM
var targets := 3               # how many jars; the data may ask for more
var hits := 0
var misses := 0

var _marker := 0.0
var _dir := 1.0
var _band := BAND_START
var _msg := ""
var _msg_t := 0.0
var _flash := 0.0
var _hold := 0.0
var _layer: Control = null
var _player: TextureRect = null


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
	_layer.draw.connect(_draw_all)
	_layer.gui_input.connect(_on_gui)

	_player = TextureRect.new()
	_player.texture = _frame("res://art/characters/david_idle.png")
	_player.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_player.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_player.anchor_left = 0.0; _player.anchor_right = 0.0
	_player.anchor_top = 1.0; _player.anchor_bottom = 1.0
	_player.offset_left = 22; _player.offset_right = 22 + 44
	_player.offset_top = -74; _player.offset_bottom = -30
	_layer.add_child(_player)


func start(count: int = 3) -> void:
	targets = maxi(1, count)
	hits = 0
	misses = 0
	_band = BAND_START
	_msg = ""
	_msg_t = 0.0
	_marker = 0.0
	_dir = 1.0
	phase = Phase.AIM


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 3.0)
	_msg_t = maxf(0.0, _msg_t - delta)
	match phase:
		Phase.AIM:
			_marker += delta * _dir / SWEEP
			if _marker >= 1.0:
				_marker = 1.0
				_dir = -1.0
			elif _marker <= 0.0:
				_marker = 0.0
				_dir = 1.0
		Phase.RESOLVE:
			_hold -= delta
			if _hold <= 0.0:
				if hits >= targets:
					phase = Phase.DONE
					finished.emit()
				else:
					phase = Phase.AIM
					_band = maxf(0.12, _band - BAND_STEP)


func _on_gui(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		press()
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		press()


## The one button. Dodging is not a thing here; every press is a release.
func press() -> void:
	if phase != Phase.AIM:
		return
	if absf(_marker - 0.5) <= _band:
		hits += 1
		_flash = 1.0
		AudioDirector.play_sfx("hit", -4.0)
		_say(I18n.t({"en": "It breaks.", "zh": "碎了。"}))
	else:
		misses += 1
		AudioDirector.play_sfx("miss", -6.0)
		_say(I18n.t({"en": "Wide. Try another stone.", "zh": "偏了。再来一块。"}))
	phase = Phase.RESOLVE
	_hold = RESOLVE_TIME


## Test seam: put the marker in the middle of the band before pressing.
func aim_perfect() -> void:
	_marker = 0.5


func is_aiming() -> bool:
	return phase == Phase.AIM


func _say(text: String, secs: float = 1.4) -> void:
	_msg = text
	_msg_t = secs


# ── drawing ──────────────────────────────────────────────────────────────
func _draw_all() -> void:
	var vs: Vector2 = _layer.size
	if vs.x <= 0.0:
		return
	var font := ThemeDB.fallback_font
	_layer.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.10, 0.12, 0.14, 0.82))
	var ground := vs.y - 30.0
	_layer.draw_rect(Rect2(Vector2(0, ground), Vector2(vs.x, 30)),
		Color(0.22, 0.24, 0.15, 0.9))
	# the wall the jars stand against
	var wall := Rect2(Vector2(vs.x * 0.5 - 92, ground - 46), Vector2(184, 46))
	_layer.draw_rect(wall, Color(0.32, 0.29, 0.24, 0.95))
	_layer.draw_rect(Rect2(wall.position, Vector2(wall.size.x, 2)),
		Color(0.44, 0.40, 0.32, 0.95))

	var left := 22.0
	var right := vs.x - 22.0
	for i in range(targets):
		var cx := wall.position.x + 26.0 + i * ((wall.size.x - 52.0) / maxf(1.0, float(targets - 1)))
		if i < hits:
			# broken: shards on the wall's lip
			_layer.draw_rect(Rect2(Vector2(cx - 3, ground - 4), Vector2(6, 4)),
				Color(0.55, 0.50, 0.42, 0.9))
			_layer.draw_rect(Rect2(Vector2(cx - 9, ground - 2), Vector2(4, 2)),
				Color(0.48, 0.44, 0.38, 0.9))
		else:
			var body := Rect2(Vector2(cx - 5, ground - 20), Vector2(10, 20))
			_layer.draw_rect(body, Color(0.62, 0.42, 0.30, 1.0))
			_layer.draw_rect(Rect2(body.position, Vector2(3, 20)),
				Color(0.74, 0.52, 0.38, 1.0))
			_layer.draw_rect(Rect2(Vector2(cx - 3, ground - 24), Vector2(6, 4)),
				Color(0.52, 0.34, 0.24, 1.0))

	if phase == Phase.AIM:
		# the lit band: press while the marker is inside it
		var band_l := lerpf(left, right, 0.5 - _band)
		var band_r := lerpf(left, right, 0.5 + _band)
		_layer.draw_rect(Rect2(Vector2(band_l, ground - 60), Vector2(band_r - band_l, 52)),
			Color(0.97, 0.87, 0.65, 0.16))
		_layer.draw_rect(Rect2(Vector2(band_l, ground - 60), Vector2(1, 52)),
			Color(0.97, 0.87, 0.65, 0.55))
		_layer.draw_rect(Rect2(Vector2(band_r, ground - 60), Vector2(1, 52)),
			Color(0.97, 0.87, 0.65, 0.55))
		# the marker
		var mx := lerpf(left, right, _marker)
		_layer.draw_rect(Rect2(Vector2(mx - 1, ground - 64), Vector2(2, 56)),
			Color(1, 0.96, 0.86, 0.95))
		_layer.draw_circle(Vector2(mx, ground - 66), 2.5, Color(1, 0.96, 0.86, 1.0))
	elif phase == Phase.RESOLVE:
		var hit_band := Color(0.7, 0.95, 0.7, 0.35)
		_layer.draw_rect(Rect2(Vector2(left, ground - 60), Vector2(right - left, 52)), hit_band)

	if _flash > 0.0:
		_layer.draw_rect(Rect2(Vector2.ZERO, vs), Color(1, 0.95, 0.85, 0.3 * _flash))

	# jars broken / to go
	_layer.draw_string(font, Vector2(22, 22),
		I18n.t({"en": "jars %d of %d" % [hits, targets], "zh": "陶罐 %d／%d" % [hits, targets]}),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.93, 0.88, 0.74, 0.9))
	if _msg != "" and _msg_t > 0.0:
		_layer.draw_multiline_string(font, Vector2(22, vs.y - 44), _msg,
			HORIZONTAL_ALIGNMENT_LEFT, vs.x - 44, 9, 2, Color(0.97, 0.87, 0.65, 0.95))
	if phase == Phase.AIM:
		_layer.draw_multiline_string(font, Vector2(22, vs.y - 16),
			I18n.t({"en": "A / tap — release the stone", "zh": "按 A 或点屏幕 —— 放手"}),
			HORIZONTAL_ALIGNMENT_LEFT, vs.x - 44, 8, 2, Color(0.85, 0.85, 0.8, 0.85))
