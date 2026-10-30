extends CanvasLayer
class_name Hud
## Hud — the thin always-on layer: who you are, where you are, what you carry.
## Deliberately small. In an exploration game the world is the interface; the
## HUD must never compete with it.

var bar: HBoxContainer = null
var name_lbl: Label = null
var place_lbl: Label = null
var verses_lbl: Label = null
var time_lbl: Label = null
var toast_lbl: Label = null
var region: Region = null
var _toast_t := 0.0


func _ready() -> void:
	layer = 15
	_build()


func bind(r: Region) -> void:
	region = r
	place_lbl.text = I18n.t(r.model.display_name)
	_refresh()


func _build() -> void:
	bar = HBoxContainer.new()
	bar.anchor_right = 1.0
	bar.offset_bottom = 14
	bar.add_theme_constant_override("separation", 6)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 4)
	m.add_theme_constant_override("margin_right", 4)
	m.add_theme_constant_override("margin_top", 2)
	m.add_child(bar)
	add_child(m)

	name_lbl = _label(Color(0.97, 0.87, 0.65))
	bar.add_child(name_lbl)
	place_lbl = _label(Color(0.72, 0.78, 0.80))
	place_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(place_lbl)
	verses_lbl = _label(Color(0.79, 0.64, 0.36))
	bar.add_child(verses_lbl)
	time_lbl = _label(Color(0.55, 0.62, 0.66))
	bar.add_child(time_lbl)

	var lang := Button.new()
	lang.text = "EN"
	lang.flat = true
	lang.add_theme_font_size_override("font_size", 8)
	lang.pressed.connect(func():
		I18n.toggle()
		lang.text = "EN" if I18n.is_zh() else "中"
		if region: place_lbl.text = I18n.t(region.model.display_name)
		_refresh())
	bar.add_child(lang)

	toast_lbl = Label.new()
	toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_lbl.anchor_left = 0.5; toast_lbl.anchor_right = 0.5
	toast_lbl.anchor_top = 0.0
	toast_lbl.offset_left = -120; toast_lbl.offset_right = 120
	toast_lbl.offset_top = 18
	toast_lbl.add_theme_font_size_override("font_size", 9)
	toast_lbl.add_theme_color_override("font_color", Color(0.97, 0.87, 0.65))
	toast_lbl.modulate.a = 0
	add_child(toast_lbl)

	EventBus.verse_received.connect(func(_id, _ref): _refresh())
	EventBus.item_picked_up.connect(func(_id): _refresh())
	EventBus.time_of_day_changed.connect(func(_t): _refresh())
	EventBus.toast_requested.connect(_toast)


func _label(col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 8)
	l.add_theme_color_override("font_color", col)
	return l


func _refresh() -> void:
	if GameState == null:
		return
	name_lbl.text = "%s · Lv%d" % [GameState.data.get("name", "pilgrim"), GameState.data.get("level", 1)]
	var n: int = (GameState.data.get("words", []) as Array).size()
	verses_lbl.text = "✧%d" % n
	time_lbl.text = I18n.t({
		"morning": {"en": "morning", "zh": "清晨"},
		"noon": {"en": "noon", "zh": "正午"},
		"dusk": {"en": "dusk", "zh": "黄昏"},
		"night": {"en": "night", "zh": "夜晚"},
		"dawn": {"en": "dawn", "zh": "黎明"},
	}.get(GameState.data.get("time_of_day", "morning"), {"en": "", "zh": ""}))


func _toast(text: String) -> void:
	toast_lbl.text = text
	_toast_t = 2.2
	var tw := create_tween()
	tw.tween_property(toast_lbl, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.6)
	tw.tween_property(toast_lbl, "modulate:a", 0.0, 0.45)
