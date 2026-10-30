extends CanvasLayer
class_name Hud
## HUD
signal journal_requested
## Hud — the thin always-on layer: who you are, where you are, what you carry.
## Deliberately small. In an exploration game the world is the interface; the
## HUD must never compete with it.

var bar: HBoxContainer = null
var name_lbl: Label = null
var place_lbl: Label = null
var verses_lbl: Label = null
var stones_lbl: Label = null
var time_lbl: Label = null
var toast_lbl: Label = null
var objective_lbl: Label = null
var prompt_lbl: Label = null
var arrow: WaypointArrow = null
var journal_btn: Button = null
var region: Region = null
var _toast_t := 0.0
var _objective := ""
var _prompt := ""


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
	# Stones get their own counter because the player cannot read a pouch.
	# Playtest 4 walked to the line short of five and the refusal was the first
	# time anything named the number — a goal you cannot see is a wall.
	stones_lbl = _label(Color(0.62, 0.74, 0.86))
	stones_lbl.visible = false
	bar.add_child(stones_lbl)
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
		if stones_lbl != null and stones_lbl.visible:
			# re-render the counter in the new language without waiting for the
			# next pickup
			stones_lbl.text = I18n.t({"en": "◆%s", "zh": "◆%s"}) % stones_lbl.text.substr(1)
		_refresh())
	bar.add_child(lang)

	# ── objective line ────────────────────────────────────────────────────
	# Always on screen, always one sentence, always the CURRENT task. Playtest 6
	# ended in "i just keep talk with goliath with nothing going on then suddenly
	# nothing to do": a game with no stated goal cannot be finished by a player
	# who does not already know the story.
	objective_lbl = Label.new()
	objective_lbl.anchor_left = 0.0
	objective_lbl.anchor_right = 1.0
	objective_lbl.offset_left = 5
	# Wrapped and bounded: the objective is a whole sentence now (an errand, a
	# person's name), and an unbounded Label at 320 px simply ran off the screen.
	objective_lbl.offset_right = -30
	objective_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_lbl.offset_top = 20
	objective_lbl.add_theme_font_size_override("font_size", 8)
	objective_lbl.add_theme_color_override("font_color", Color(0.93, 0.88, 0.74))
	objective_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	objective_lbl.add_theme_constant_override("shadow_offset_x", 1)
	objective_lbl.add_theme_constant_override("shadow_offset_y", 1)
	add_child(objective_lbl)

	# The book. Top-left, small, above the objective line — it is a thing to
	# open when you are lost, not a thing that competes with the objective.
	journal_btn = Button.new()
	journal_btn.text = "≡"
	journal_btn.add_theme_font_size_override("font_size", 9)
	# 28x18 is the smallest thing a thumb reliably hits; it sits above the
	# objective line, which starts at y=16.
	journal_btn.offset_left = 2
	journal_btn.offset_top = 0
	journal_btn.offset_right = 30
	journal_btn.offset_bottom = 18
	journal_btn.flat = true
	journal_btn.focus_mode = Control.FOCUS_NONE
	journal_btn.pressed.connect(func(): journal_requested.emit())
	add_child(journal_btn)

	arrow = WaypointArrow.new()
	arrow.anchor_left = 1.0
	arrow.anchor_right = 1.0
	arrow.offset_left = -26
	arrow.offset_right = -6
	arrow.offset_top = 15
	arrow.offset_bottom = 35
	add_child(arrow)

	# ── context prompt ────────────────────────────────────────────────────
	prompt_lbl = Label.new()
	prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_lbl.anchor_left = 0.5; prompt_lbl.anchor_right = 0.5
	prompt_lbl.anchor_top = 1.0; prompt_lbl.anchor_bottom = 1.0
	prompt_lbl.offset_left = -110; prompt_lbl.offset_right = 110
	prompt_lbl.offset_top = -22; prompt_lbl.offset_bottom = -8
	prompt_lbl.add_theme_font_size_override("font_size", 9)
	prompt_lbl.add_theme_color_override("font_color", Color(0.97, 0.87, 0.65))
	prompt_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	prompt_lbl.add_theme_constant_override("shadow_offset_x", 1)
	prompt_lbl.add_theme_constant_override("shadow_offset_y", 1)
	prompt_lbl.visible = false
	add_child(prompt_lbl)

	toast_lbl = Label.new()
	toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_lbl.anchor_left = 0.0; toast_lbl.anchor_right = 1.0
	toast_lbl.anchor_top = 0.0
	toast_lbl.offset_left = 12; toast_lbl.offset_right = -12
	toast_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	# "pilgrim · Lv1" showed in English even in Chinese mode: the name is game
	# data, so it needs the same {en,zh} treatment as everything else.
	# No ternary here: Player.gd records that a ternary split across a line
	# continuation inside a declaration is a parser edge case in GDScript, and
	# one such line once made five unrelated scripts fail to compile.
	var who := str(GameState.data.get("name", "pilgrim"))
	if who == "pilgrim":
		who = I18n.t({"en": "pilgrim", "zh": "朝圣者"})
	var lvl: int = int(GameState.data.get("level", 1))
	var fmt := I18n.t({"en": "%s · Lv%d", "zh": "%s · %d 级"})
	name_lbl.text = fmt % [who, lvl]
	var n: int = (GameState.data.get("words", []) as Array).size()
	verses_lbl.text = "☆%d" % n
	time_lbl.text = I18n.t({
		"morning": {"en": "morning", "zh": "清晨"},
		"noon": {"en": "noon", "zh": "正午"},
		"dusk": {"en": "dusk", "zh": "黄昏"},
		"night": {"en": "night", "zh": "夜晚"},
		"dawn": {"en": "dawn", "zh": "黎明"},
	}.get(GameState.data.get("time_of_day", "morning"), {"en": "", "zh": ""}))


## Set by Main: the current task, in one sentence.
func set_objective(text: String) -> void:
	if text == _objective:
		return
	_objective = text
	objective_lbl.text = text
	objective_lbl.visible = text != ""


## Set by Main: a world-space direction to the current task.
func point_at(delta_world: Vector2, on: bool) -> void:
	if arrow == null:
		return
	if on:
		arrow.point_at(delta_world)
	else:
		arrow.hide_arrow()


## Set by Main: "A · talk" when a person is close enough to speak to.
func set_prompt(text: String) -> void:
	if text == _prompt:
		return
	_prompt = text
	prompt_lbl.text = text
	prompt_lbl.visible = text != ""


## Set by Main when the player BECOMES someone: the nameplate must say whose
## hands are holding the sling (docs/FEEL.md §3).
func set_role(who: String, level: int) -> void:
	var fmt := I18n.t({"en": "%s · Lv%d", "zh": "%s · %d 级"})
	name_lbl.text = fmt % [who, level]


## Set by Main: how many stones are in the pouch, out of how many exist.
func set_stones(n: int, total: int) -> void:
	if stones_lbl == null:
		return
	stones_lbl.visible = total > 0
	stones_lbl.text = I18n.t({"en": "◆%d/%d", "zh": "◆%d／%d"}) % [n, total]


func _toast(text: String) -> void:
	toast_lbl.text = text
	_toast_t = 2.2
	var tw := create_tween()
	tw.tween_property(toast_lbl, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.6)
	tw.tween_property(toast_lbl, "modulate:a", 0.0, 0.45)
