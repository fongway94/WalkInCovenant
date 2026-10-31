extends CanvasLayer
class_name PlaceCard
## PlaceCard — the caption that says where you are, and which chapter this is.
##
## The cinematic list in the brief is: objective → event → camera → sound →
## **caption** → fade. Everything on that list existed except the caption: the
## game cut into a valley without ever writing the valley's name on it, and the
## chapter title only existed in the browser tab.
##
## It is data, not copy: the words are `name` and `sub` from the region file, so
## a new campaign is captioned by its author, not by this script.

const HOLD := 2.4
const IN_T := 0.45
const OUT_T := 0.6

var _box: VBoxContainer = null
var title_lbl: Label = null
var sub_lbl: Label = null
var _busy := false

signal finished


func _ready() -> void:
	# Over the world, over the HUD, under the fades (45). A caption never appears
	# while a conversation is open, so it never competes with the dialogue box.
	layer = 41
	_build()
	_apply_layout()
	var vp := get_viewport()
	if vp != null:
		vp.size_changed.connect(_apply_layout)


## The caption sits in the lower-middle of the picture, clear of the top HUD and
## of the thumb strip, so it can be read over whatever the camera is showing.
func _apply_layout() -> void:
	if _box == null:
		return
	var vs := ScreenFit.BASE
	var vp := get_viewport()
	if vp != null:
		vs = vp.get_visible_rect().size
	var lower := 0.58
	_box.anchor_top = lower
	_box.anchor_bottom = lower
	_box.offset_top = 0
	_box.offset_bottom = clampf(vs.y * 0.22, 24.0, 56.0)


func _build() -> void:
	_box = VBoxContainer.new()
	var box := _box
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.anchor_left = 0.0
	box.anchor_right = 1.0
	box.anchor_top = 0.62
	box.anchor_bottom = 0.62
	box.offset_left = 10
	box.offset_right = -10
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	title_lbl = _line(box, 15, Color(0.98, 0.92, 0.76))
	sub_lbl = _line(box, 8, Color(0.86, 0.80, 0.64))
	title_lbl.modulate.a = 0.0
	sub_lbl.modulate.a = 0.0


func _line(box: VBoxContainer, size: int, col: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)
	return l


func is_busy() -> bool:
	return _busy


## Show the card. Never blocks the world: the player can walk while it fades, and
## a second call while one is playing is ignored rather than stacking.
func show_card(display_name: Dictionary, sub: Dictionary) -> void:
	if _busy:
		return
	var t := str(I18n.t(display_name))
	var s := str(I18n.t(sub))
	if t == "":
		return
	_busy = true
	title_lbl.text = t
	sub_lbl.text = s
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(title_lbl, "modulate:a", 1.0, IN_T)
	tw.tween_property(sub_lbl, "modulate:a", 1.0, IN_T * 1.6)
	tw.set_parallel(false)
	tw.tween_interval(HOLD)
	tw.set_parallel(true)
	tw.tween_property(title_lbl, "modulate:a", 0.0, OUT_T)
	tw.tween_property(sub_lbl, "modulate:a", 0.0, OUT_T)
	tw.set_parallel(false)
	tw.tween_callback(_done)


func _done() -> void:
	_busy = false
	finished.emit()
