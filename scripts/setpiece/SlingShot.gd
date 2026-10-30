extends CanvasLayer
class_name SlingShot
## SlingShot — the last stone.
##
## The word-battle is the argument; this is the throw. Playtest 6: "no gameplay
## of David fight goliath... i just keep talk with goliath with nothing going
## on". The quiz alone was the whole fight, so the one action the story is
## actually famous for never happened.
##
## The interaction is one button, because one button is what David had:
##
##   a marker sweeps up a bar beside Goliath's head. Press A (or tap) and the
##   stone leaves. Inside the lit band it lands in his forehead; outside it goes
##   wide and you take the next stone.
##
## There is no losing. A miss costs a breath, not the story — this game has no
## game-over screen (docs/WORLD.md, pillar 5) and the fight it is retelling has
## a fixed ending. The band widens after each miss so a player who cannot time it
## still finishes.
##
## Input: the `interact` action, any mouse button, any screen touch, any key.
## All of them, because the target device is a phone held sideways and the whole
## point is that the button you have is the button that works.

signal released(hit: bool)
signal finished

const BAR_W := 5.0
const BAR_H := 96.0
const HIT_H := 16.0           # width of the lit band, in pixels of bar travel
const SWEEP := 0.95           # seconds to cross the bar once

var _t := 0.0
var _dir := 1.0
var _band_y := 0.0            # band centre, 0..1 of the bar
var _band_h := HIT_H
var _misses := 0
var _locked := false
var _done := false
var _layer: Control = null
var _gol: TextureRect = null


func _ready() -> void:
	layer = 22
	_build()


func _build() -> void:
	_layer = Control.new()
	_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_layer)
	_layer.draw.connect(_draw_all)
	_layer.gui_input.connect(_on_gui_input)

	# Goliath, huge, centred. Sprite is 16x16 and the viewport is 320x180, so
	# 7x puts him at 112 px tall — a third of the screen, which is the point.
	_gol = TextureRect.new()
	var sheet := load("res://art/characters/goliath_idle.png")
	if sheet != null:
		var at := AtlasTexture.new()
		at.atlas = sheet
		at.region = Rect2(0, 0, 16, 16)      # row 0 (down), frame 0
		_gol.texture = at
	_gol.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_gol.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_gol.anchor_left = 0.5; _gol.anchor_right = 0.5
	_gol.anchor_top = 0.5; _gol.anchor_bottom = 0.5
	_gol.offset_left = -70; _gol.offset_right = 70
	_gol.offset_top = -86; _gol.offset_bottom = 62
	_layer.add_child(_gol)


func start() -> void:
	_t = 0.0
	_dir = 1.0
	_misses = 0
	_band_h = HIT_H
	_band_y = 0.34 + randf() * 0.3
	_locked = false
	_done = false


func _process(delta: float) -> void:
	if _done or _locked:
		return
	_t += delta * _dir / SWEEP
	if _t >= 1.0:
		_t = 1.0
		_dir = -1.0
	elif _t <= 0.0:
		_t = 0.0
		_dir = 1.0
	_layer.queue_redraw()


func _input(event: InputEvent) -> void:
	if _done or _locked:
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
		_release()
		get_viewport().set_input_as_handled()


func _on_gui_input(event: InputEvent) -> void:
	if _done or _locked:
		return
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		_release()


## Align the marker with the band. A test seam: the headless playthrough has no
## thumb to time the shot with, and the alternative — retrying until the band
## widens — would make the build's green depend on chance.
func aim_perfect() -> void:
	_t = _band_y
	if _layer != null:
		_layer.queue_redraw()


## Fire. Public so the integration test can take the shot the same way a tap does.
func release() -> void:
	_release()


func _release() -> void:
	if _locked or _done:
		return
	_locked = true
	var hit := absf(_t - _band_y) <= _band_h * 0.5
	_layer.queue_redraw()
	released.emit(hit)
	AudioDirector.play_sfx("sling" if hit else "miss", -3.0)
	if hit:
		_done = true
		await get_tree().create_timer(0.55).timeout
		finished.emit()
		return
	_misses += 1
	# Mercy: a wider band each time. Never a fail state, only an easier throw.
	_band_h = minf(0.42, HIT_H * 2.0 + _misses * 14.0)
	await get_tree().create_timer(0.45).timeout
	_locked = false
	_t = 0.0
	_dir = 1.0
	_band_y = 0.3 + randf() * 0.4
	_layer.queue_redraw()


func _draw_all() -> void:
	var vs := _layer.size
	_layer.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.04, 0.05, 0.07, 0.55))
	# the bar, right in front of him
	var x := vs.x * 0.5 + 54.0
	var y0 := vs.y * 0.5 - BAR_H * 0.5
	_layer.draw_rect(Rect2(Vector2(x, y0), Vector2(BAR_W, BAR_H)), Color(1, 1, 1, 0.10))
	_layer.draw_rect(Rect2(Vector2(x - 1, y0 - 1), Vector2(BAR_W + 2, BAR_H + 2)),
		Color(0.97, 0.87, 0.65, 0.35), false, 1.0)
	var by := y0 + (_band_y - _band_h * 0.5) * BAR_H
	_layer.draw_rect(Rect2(Vector2(x, by), Vector2(BAR_W, _band_h * BAR_H)),
		Color(0.85, 0.62, 0.30, 0.55))
	var my := y0 + _t * BAR_H
	_layer.draw_rect(Rect2(Vector2(x - 4, my - 1.5), Vector2(BAR_W + 8, 3)),
		Color(0.99, 0.96, 0.86, 0.95))
	# crosshair over his forehead
	var hx := vs.x * 0.5
	var hy := vs.y * 0.5 - 52.0
	_layer.draw_arc(Vector2(hx, hy), 7, 0, TAU, 16, Color(0.99, 0.96, 0.86, 0.75), 1.0)
	_layer.draw_line(Vector2(hx - 10, hy), Vector2(hx - 4, hy), Color(0.99, 0.96, 0.86, 0.75))
	_layer.draw_line(Vector2(hx + 4, hy), Vector2(hx + 10, hy), Color(0.99, 0.96, 0.86, 0.75))
	var font := ThemeDB.fallback_font
	_layer.draw_string(font, Vector2(vs.x * 0.5 - 60, vs.y - 26),
		I18n.t({"en": "A / tap — release the stone", "zh": "按 A 或点屏幕 —— 放手"}),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.97, 0.87, 0.65, 0.9))
	if _misses > 0:
		_layer.draw_string(font, Vector2(vs.x * 0.5 - 60, vs.y - 14),
			I18n.t({"en": "The stone went wide. Another one.", "zh": "石子打偏了。再来一块。"}),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.85, 0.72, 0.55, 0.9))
