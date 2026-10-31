extends CanvasLayer
class_name BecomeController
## BecomeController — the signature moment of the whole game.
##
##   你听见自己的心跳。然后那不像是你的心跳了。你低头，看见一双不属于自己的手，
##   正握着一根甩石的绳子。
##   "You hear your own heartbeat, and then it stops being yours. You look down:
##    the hands holding the sling are not your hands."
##
## Four beats, in order:
##   1. letterbox bars slide in — the world becomes a scene
##   2. a warm gold wash and a push-in on the player
##   3. the nameplate changes from YOUR name to the Bible character's
##   4. control hands over; and later hands back with "You are yourself again."
##
## Rebuilt for the development reset (docs/AUDIT.md A1). The old version drew two
## fixed 16-unit black bars over a 180-unit screen — 18% of the picture — with no
## framing around them. On a phone that reads as the game having shrunk and
## sprouted black borders, which is exactly how it was reported. Three changes:
##
##   * the bars are a PERCENTAGE of the screen (ScreenFit.bar_height), so they
##     frame the picture rather than cut a strip off it;
##   * each bar carries a gold hairline on its inner edge, so it reads as a film
##     matte instead of a hole;
##   * the bars can never be left behind: `_retract()` runs on every exit path,
##     the watchdog retracts after MAX_HOLD seconds regardless, and a viewport
##     resize re-lays them out.
##
## Reduced motion collapses this to a quick fade. The beats are flavour, never
## information — skipping them must never lose the player anything.

var bar_top: ColorRect = null
var bar_bot: ColorRect = null
var edge_top: ColorRect = null
var edge_bot: ColorRect = null
var wash: ColorRect = null
var plate: Label = null
var sub: Label = null
var _busy := false
var _held := 0.0
var _bar_h := 14.0
## The live transition. Kept so a second request can CANCEL the first rather
## than be silently dropped.
var _tw: Tween = null

## A transition that never completed used to leave the world covered in black
## bars with `_busy` refusing every new call. This is the belt to that brace.
const MAX_HOLD := 9.0

signal became(character: String)
signal returned(character: String)


func _ready() -> void:
	layer = 30
	_build()
	_apply_layout()
	var vp := get_viewport()
	if vp != null:
		vp.size_changed.connect(_apply_layout)


func _make_bar(bottom: bool) -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(0.02, 0.03, 0.04, 1)
	add_child(c)
	return c


func _build() -> void:
	bar_top = _make_bar(false)
	bar_bot = _make_bar(true)
	# A hairline of gold on the inner edge: the difference between "a matte" and
	# "the renderer lost 16 pixels".
	edge_top = ColorRect.new()
	edge_top.color = Color(0.79, 0.64, 0.36, 0.55)
	add_child(edge_top)
	edge_bot = ColorRect.new()
	edge_bot.color = Color(0.79, 0.64, 0.36, 0.55)
	add_child(edge_bot)

	wash = ColorRect.new()
	wash.color = Color(0.97, 0.87, 0.65, 0)
	wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)

	plate = Label.new()
	plate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plate.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	plate.add_theme_font_size_override("font_size", 13)
	plate.add_theme_color_override("font_color", Color(0.97, 0.87, 0.65))
	plate.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	plate.add_theme_constant_override("shadow_offset_x", 1)
	plate.add_theme_constant_override("shadow_offset_y", 1)
	plate.modulate.a = 0
	add_child(plate)

	sub = Label.new()
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 8)
	sub.add_theme_color_override("font_color", Color(0.86, 0.78, 0.58))
	sub.modulate.a = 0
	add_child(sub)


func _apply_layout() -> void:
	var vs := _view_size()
	_bar_h = ScreenFit.bar_height(vs)
	var closed := not _busy and bar_top != null and bar_top.offset_bottom <= 0.5
	bar_top.anchor_left = 0.0; bar_top.anchor_right = 1.0
	bar_top.anchor_top = 0.0; bar_top.anchor_bottom = 0.0
	bar_top.offset_left = 0; bar_top.offset_right = 0
	if closed:
		bar_top.offset_top = 0; bar_top.offset_bottom = 0
	else:
		bar_top.offset_top = 0; bar_top.offset_bottom = _bar_h
	edge_top.anchor_left = 0.0; edge_top.anchor_right = 1.0
	edge_top.anchor_top = 0.0; edge_top.anchor_bottom = 0.0
	edge_top.offset_left = 0; edge_top.offset_right = 0
	edge_top.offset_top = bar_top.offset_bottom
	edge_top.offset_bottom = bar_top.offset_bottom + 0.5

	bar_bot.anchor_left = 0.0; bar_bot.anchor_right = 1.0
	bar_bot.anchor_top = 1.0; bar_bot.anchor_bottom = 1.0
	bar_bot.offset_left = 0; bar_bot.offset_right = 0
	if closed:
		bar_bot.offset_top = 0; bar_bot.offset_bottom = 0
	else:
		bar_bot.offset_top = -_bar_h; bar_bot.offset_bottom = 0
	edge_bot.anchor_left = 0.0; edge_bot.anchor_right = 1.0
	edge_bot.anchor_top = 1.0; edge_bot.anchor_bottom = 1.0
	edge_bot.offset_left = 0; edge_bot.offset_right = 0
	edge_bot.offset_top = bar_bot.offset_top - 0.5
	edge_bot.offset_bottom = bar_bot.offset_top

	# Caption and its sub-line sit in the middle of the Picture, not at an anchor
	# point: they are the only thing the player is meant to read.
	var e := ScreenFit.edge(vs)
	plate.anchor_left = 0.0; plate.anchor_right = 1.0
	plate.anchor_top = 0.5; plate.anchor_bottom = 0.5
	plate.offset_left = e + 10.0; plate.offset_right = -(e + 10.0)
	plate.offset_top = -16.0; plate.offset_bottom = 6.0
	sub.anchor_left = 0.0; sub.anchor_right = 1.0
	sub.anchor_top = 0.5; sub.anchor_bottom = 0.5
	sub.offset_left = e + 10.0; sub.offset_right = -(e + 10.0)
	sub.offset_top = 6.0; sub.offset_bottom = 18.0


func _view_size() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return ScreenFit.BASE
	return vp.get_visible_rect().size


func _hide_bars() -> void:
	if bar_top == null:
		return
	bar_top.offset_bottom = 0
	bar_bot.offset_top = 0
	edge_top.offset_top = 0
	edge_top.offset_bottom = 0
	edge_bot.offset_top = 0
	edge_bot.offset_bottom = 0
	wash.color.a = 0
	plate.modulate.a = 0
	sub.modulate.a = 0


## Bars in, with their hairlines. Kept as one call so nothing can open one
## without the other.
func _bars_in(t: float) -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(bar_top, "offset_bottom", _bar_h, t)
	tw.tween_property(bar_bot, "offset_top", -_bar_h, t)
	tw.tween_property(edge_top, "offset_top", _bar_h, t)
	tw.tween_property(edge_top, "offset_bottom", _bar_h + 0.5, t)
	tw.tween_property(edge_bot, "offset_top", -_bar_h - 0.5, t)
	tw.tween_property(edge_bot, "offset_bottom", -_bar_h, t)


func _bars_out(t: float) -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(bar_top, "offset_bottom", 0.0, t)
	tw.tween_property(bar_bot, "offset_top", 0.0, t)
	tw.tween_property(edge_top, "offset_top", 0.0, t)
	tw.tween_property(edge_top, "offset_bottom", 0.5, t)
	tw.tween_property(edge_bot, "offset_top", -0.5, t)
	tw.tween_property(edge_bot, "offset_bottom", 0.0, t)


func _process(delta: float) -> void:
	if not _busy:
		return
	_held += delta
	if _held >= MAX_HOLD:
		# Whatever was supposed to happen, stop covering the game.
		_held = 0.0
		_busy = false
		_tw = null
		_hide_bars()
		push_warning("BecomeController: transition exceeded MAX_HOLD and was cancelled")


## Making room for a new transition. The old controller returned early here,
## which meant a second `begin()`/`end()` was DROPPED — and its caller was the
## story itself, waiting for the callback to continue. A mission re-entered on a
## resume, or a win beat arriving while the bars were still in, left the chapter
## permanently unable to continue (BUG-006). A request to change the picture now
## cancels the picture, and the newest request wins.
func _make_room() -> void:
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = null
	_busy = false
	_held = 0.0
	_hide_bars()


## The forward transition. Calls on_entered once control has handed over.
func begin(character: String, display: Dictionary, on_entered: Callable) -> void:
	if _busy:
		_make_room()
	_busy = true
	_held = 0.0
	_apply_layout()
	EventBus.become_requested.emit(character)
	var rm: bool = GameState.data["settings"].get("reduce_motion", false)
	var t := 0.35 if rm else 0.9

	_bars_in(t * 0.6)
	plate.text = str(I18n.t(display))
	sub.text = str(I18n.t({"en": "You are not yourself any more.",
		"zh": "你不再是你了。"}))

	var tw := create_tween()
	_tw = tw
	tw.set_parallel(true)
	tw.tween_property(wash, "color:a", 0.30, t * 0.5)
	tw.chain().tween_property(wash, "color:a", 0.0, t * 0.5)
	tw.chain().tween_property(plate, "modulate:a", 1.0, t * 0.4)
	tw.parallel().tween_property(sub, "modulate:a", 1.0, t * 0.4)
	tw.chain().tween_interval(0.8 if not rm else 0.2)
	tw.chain().tween_property(plate, "modulate:a", 0.0, t * 0.3)
	tw.parallel().tween_property(sub, "modulate:a", 0.0, t * 0.3)
	tw.chain().tween_callback(func():
		_held = 0.0
		_busy = false
		_hide_bars()
		became.emit(character)
		on_entered.call())


## The return beat. "You are yourself again."
func end(character: String, on_returned: Callable) -> void:
	if _busy:
		_make_room()
	_busy = true
	_held = 0.0
	_apply_layout()
	var rm: bool = GameState.data["settings"].get("reduce_motion", false)
	var t := 0.3 if rm else 0.7
	_bars_in(t * 0.5)
	plate.text = str(I18n.t({"en": "The scroll turns a page. The road goes on.",
		"zh": "书卷自己翻过一页。前面的路还在。"}))
	sub.text = str(I18n.t({"en": "You are yourself again.", "zh": "你又回到了自己身上。"}))
	var tw := create_tween()
	_tw = tw
	tw.tween_property(plate, "modulate:a", 1.0, t * 0.4)
	tw.parallel().tween_property(sub, "modulate:a", 1.0, t * 0.4)
	tw.tween_interval(0.8 if not rm else 0.2)
	tw.tween_property(plate, "modulate:a", 0.0, t * 0.4)
	tw.parallel().tween_property(sub, "modulate:a", 0.0, t * 0.4)
	tw.tween_callback(func():
		_bars_out(t)
		_held = 0.0
		_busy = false
		returned.emit(character)
		on_returned.call())
