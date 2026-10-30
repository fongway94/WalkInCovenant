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
## Reduced motion collapses this to a quick fade. The beats are flavour, never
## information — skipping them must never lose the player anything.

const BAR_H := 16.0

var bar_top: ColorRect = null
var bar_bot: ColorRect = null
var wash: ColorRect = null
var plate: Label = null
var _busy := false

signal became(character: String)
signal returned(character: String)


func _ready() -> void:
	layer = 30
	_build()


func _build() -> void:
	bar_top = ColorRect.new()
	bar_top.color = Color(0, 0, 0, 1)
	bar_top.anchor_right = 1.0
	bar_top.offset_bottom = 0
	add_child(bar_top)
	bar_bot = ColorRect.new()
	bar_bot.color = Color(0, 0, 0, 1)
	bar_bot.anchor_left = 0; bar_bot.anchor_right = 1.0
	bar_bot.anchor_top = 1.0; bar_bot.anchor_bottom = 1.0
	bar_bot.offset_top = 0
	add_child(bar_bot)
	wash = ColorRect.new()
	wash.color = Color(0.97, 0.87, 0.65, 0)
	wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)
	plate = Label.new()
	plate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plate.set_anchors_preset(Control.PRESET_CENTER)
	plate.add_theme_font_size_override("font_size", 14)
	plate.add_theme_color_override("font_color", Color(0.97, 0.87, 0.65))
	plate.modulate.a = 0
	add_child(plate)
	_hide_bars()


func _hide_bars() -> void:
	bar_top.offset_bottom = 0
	bar_bot.offset_top = 0
	wash.color.a = 0
	plate.modulate.a = 0


## The forward transition. Calls on_entered once control has handed over.
func begin(character: String, display: Dictionary, on_entered: Callable) -> void:
	if _busy:
		return
	_busy = true
	EventBus.become_requested.emit(character)
	var rm: bool = GameState.data["settings"].get("reduce_motion", false)
	var t := 0.35 if rm else 0.9

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(bar_top, "offset_bottom", BAR_H, t * 0.6)
	tw.tween_property(bar_bot, "offset_top", -BAR_H, t * 0.6)
	tw.tween_property(wash, "color:a", 0.35, t * 0.5)
	tw.chain().tween_property(wash, "color:a", 0.0, t * 0.5)
	tw.chain().tween_property(plate, "modulate:a", 1.0, t * 0.4)
	tw.chain().tween_interval(0.7 if not rm else 0.2)
	tw.chain().tween_property(plate, "modulate:a", 0.0, t * 0.3)
	tw.chain().tween_callback(func():
		_busy = false
		became.emit(character)
		on_entered.call())
	plate.text = I18n.t(display)


## The return beat. "You are yourself again."
func end(character: String, on_returned: Callable) -> void:
	if _busy:
		return
	_busy = true
	var rm: bool = GameState.data["settings"].get("reduce_motion", false)
	var t := 0.3 if rm else 0.7
	plate.text = I18n.t({"en": "You are yourself again.", "zh": "你又是你自己了。"})
	var tw := create_tween()
	tw.tween_property(plate, "modulate:a", 1.0, t * 0.4)
	tw.tween_interval(0.8 if not rm else 0.2)
	tw.tween_property(plate, "modulate:a", 0.0, t * 0.4)
	tw.parallel().tween_property(bar_top, "offset_bottom", 0.0, t)
	tw.parallel().tween_property(bar_bot, "offset_top", 0.0, t)
	tw.chain().tween_callback(func():
		_busy = false
		_hide_bars()
		returned.emit(character)
		on_returned.call())
