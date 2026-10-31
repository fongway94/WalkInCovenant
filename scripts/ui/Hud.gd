extends CanvasLayer
class_name Hud
## Hud — the thin always-on layer: who you are, where you are, what you carry.
##
## Deliberately small. In an exploration game the world is the interface; the
## HUD must never compete with it.
##
## Rebuilt for the development reset (docs/AUDIT.md §1). Two things were wrong:
## every offset was a constant chosen at 320x180 (so the objective line ran off
## a narrow screen and the toast landed on top of it), and nothing re-laid out
## when the viewport changed. All of it now comes from ScreenFit, applied by
## `_apply_layout()` on the first frame and on every `size_changed`.

signal journal_requested

## Vertical bands, in logical units. They are the same on every screen because
## the viewport is always in design units (see ScreenFit).
const BAR_H := 13.0
const ROW2_Y := 15.0
## Two rows of the objective font (8 px), not one-and-a-bit. Several objectives
## are a full sentence in English — the longest is 74 characters — and the band
## was sized for a single line, so the wrapped second line rendered over the
## toast band and into the world (BUG-020). Sized from the font, and asserted
## against the real font metrics in tests/deep.gd.
const OBJECTIVE_H := 26.0
const TOAST_Y := 43.0
const PROMPT_H := 12.0

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
var lang_btn: Button = null
var sound_btn: Button = null
var region: Region = null

var _stones_n := 0
var _stones_total := 0
var _objective := ""
var _prompt := ""


func _ready() -> void:
	layer = 15
	_build()
	_apply_layout()
	var vp := get_viewport()
	if vp != null:
		vp.size_changed.connect(_apply_layout)


func bind(r: Region) -> void:
	region = r
	place_lbl.text = I18n.t(r.model.display_name)
	_refresh()


# ── construction ─────────────────────────────────────────────────────────
func _build() -> void:
	bar = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	add_child(bar)

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

	lang_btn = Button.new()
	lang_btn.text = "EN"
	lang_btn.flat = true
	lang_btn.focus_mode = Control.FOCUS_NONE
	lang_btn.add_theme_font_size_override("font_size", 8)
	lang_btn.pressed.connect(_toggle_language)
	bar.add_child(lang_btn)

	# Sound. A phone game with footsteps and music and no way to silence either
	# is a phone game you close on the bus. Two glyphs, no menu: 音 is on, 静 is
	# off, and a toast says which just happened.
	sound_btn = Button.new()
	sound_btn.text = "音" if bool(GameState.data["settings"].get("sound", true)) else "静"
	sound_btn.flat = true
	sound_btn.focus_mode = Control.FOCUS_NONE
	sound_btn.add_theme_font_size_override("font_size", 8)
	sound_btn.pressed.connect(_toggle_sound)
	bar.add_child(sound_btn)

	# ── objective line ────────────────────────────────────────────────────
	# Always on screen, always one sentence, always the CURRENT task. Playtest 6
	# ended in "i just keep talk with goliath with nothing going on then suddenly
	# nothing to do": a game with no stated goal cannot be finished by a player
	# who does not already know the story.
	objective_lbl = Label.new()
	objective_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_lbl.add_theme_font_size_override("font_size", 8)
	objective_lbl.add_theme_color_override("font_color", Color(0.93, 0.88, 0.74))
	objective_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	objective_lbl.add_theme_constant_override("shadow_offset_x", 1)
	objective_lbl.add_theme_constant_override("shadow_offset_y", 1)
	add_child(objective_lbl)

	# The book. Top-left, small — a thing to open when you are lost, not a thing
	# that competes with the objective.
	journal_btn = Button.new()
	journal_btn.text = "≡"
	journal_btn.add_theme_font_size_override("font_size", 9)
	journal_btn.flat = true
	journal_btn.focus_mode = Control.FOCUS_NONE
	journal_btn.pressed.connect(func(): journal_requested.emit())
	add_child(journal_btn)

	arrow = WaypointArrow.new()
	add_child(arrow)

	# ── context prompt ────────────────────────────────────────────────────
	prompt_lbl = Label.new()
	prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_lbl.add_theme_font_size_override("font_size", 9)
	prompt_lbl.add_theme_color_override("font_color", Color(0.97, 0.87, 0.65))
	prompt_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	prompt_lbl.add_theme_constant_override("shadow_offset_x", 1)
	prompt_lbl.add_theme_constant_override("shadow_offset_y", 1)
	prompt_lbl.visible = false
	add_child(prompt_lbl)

	toast_lbl = Label.new()
	toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_lbl.add_theme_font_size_override("font_size", 9)
	toast_lbl.add_theme_color_override("font_color", Color(0.97, 0.87, 0.65))
	toast_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	toast_lbl.add_theme_constant_override("shadow_offset_x", 1)
	toast_lbl.add_theme_constant_override("shadow_offset_y", 1)
	toast_lbl.modulate.a = 0
	add_child(toast_lbl)

	EventBus.verse_received.connect(func(_id, _ref): _refresh())
	EventBus.item_picked_up.connect(func(_id): _refresh())
	EventBus.time_of_day_changed.connect(func(_t): _refresh())
	EventBus.toast_requested.connect(_toast)


## Every offset on this layer, in one place, from one source of truth.
func _apply_layout() -> void:
	var vs := _view_size()
	var e := ScreenFit.edge(vs)

	# top bar (full width, inset)
	bar.anchor_left = 0.0; bar.anchor_right = 1.0
	bar.anchor_top = 0.0; bar.anchor_bottom = 0.0
	bar.offset_left = e
	bar.offset_right = -e
	bar.offset_top = e * 0.5
	bar.offset_bottom = e * 0.5 + BAR_H

	# book button: left of the objective, above it
	journal_btn.anchor_left = 0.0; journal_btn.anchor_right = 0.0
	journal_btn.anchor_top = 0.0; journal_btn.anchor_bottom = 0.0
	journal_btn.offset_left = e
	journal_btn.offset_top = ROW2_Y
	journal_btn.offset_right = e + 26.0
	journal_btn.offset_bottom = ROW2_Y + 17.0

	# objective: to the right of the book, ending before the waypoint arrow
	objective_lbl.anchor_left = 0.0; objective_lbl.anchor_right = 1.0
	objective_lbl.anchor_top = 0.0; objective_lbl.anchor_bottom = 0.0
	objective_lbl.offset_left = e + 30.0
	objective_lbl.offset_right = -(e + 26.0)
	objective_lbl.offset_top = ROW2_Y + 1.0
	objective_lbl.offset_bottom = ROW2_Y + 1.0 + OBJECTIVE_H

	# waypoint arrow: top-right, level with the objective
	arrow.anchor_left = 1.0; arrow.anchor_right = 1.0
	arrow.anchor_top = 0.0; arrow.anchor_bottom = 0.0
	arrow.offset_left = -(e + 22.0)
	arrow.offset_right = -e
	arrow.offset_top = ROW2_Y
	arrow.offset_bottom = ROW2_Y + 20.0

	# toast: its own band UNDER the objective. It used to start at y=18, which is
	# where the objective line lives, so every toast printed on top of the task.
	toast_lbl.anchor_left = 0.0; toast_lbl.anchor_right = 1.0
	toast_lbl.anchor_top = 0.0; toast_lbl.anchor_bottom = 0.0
	toast_lbl.offset_left = e + 12.0
	toast_lbl.offset_right = -(e + 12.0)
	toast_lbl.offset_top = TOAST_Y
	toast_lbl.offset_bottom = TOAST_Y + 22.0

	# prompt: bottom centre, above the thumb strip, never touching the edges
	prompt_lbl.anchor_left = 0.5; prompt_lbl.anchor_right = 0.5
	prompt_lbl.anchor_top = 1.0; prompt_lbl.anchor_bottom = 1.0
	prompt_lbl.offset_left = -minf(120.0, vs.x * 0.4)
	prompt_lbl.offset_right = minf(120.0, vs.x * 0.4)
	prompt_lbl.offset_top = -(ScreenFit.thumb_strip(vs) * 0.55 + PROMPT_H)
	prompt_lbl.offset_bottom = -(ScreenFit.thumb_strip(vs) * 0.55)


func _view_size() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return ScreenFit.BASE
	return vp.get_visible_rect().size


func _label(col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 8)
	l.add_theme_color_override("font_color", col)
	return l


## One button, both beds — a player who wants quiet wants quiet, not a course in
## mixing. The setting is saved with the rest of the save file.
func _toggle_sound() -> void:
	var st: Dictionary = GameState.data["settings"]
	var on := not bool(st.get("sound", true))
	st["sound"] = on
	st["music"] = on
	AudioDirector.apply_settings()
	sound_btn.text = "音" if on else "静"
	var note_en := "Sound on · 音" if on else "Sound off · 静"
	var note_zh := "声音开着" if on else "已静音"
	EventBus.toast_requested.emit(I18n.t({"en": note_en, "zh": note_zh}))
	GameState.save_game()


func _toggle_language() -> void:
	I18n.toggle()
	lang_btn.text = "EN" if I18n.is_zh() else "中"
	if region != null:
		place_lbl.text = I18n.t(region.model.display_name)
	set_stones(_stones_n, _stones_total)
	_refresh()


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
	_stones_n = n
	_stones_total = total
	if stones_lbl == null:
		return
	stones_lbl.visible = total > 0
	stones_lbl.text = I18n.t({"en": "◆%d/%d", "zh": "◆%d／%d"}) % [n, total]


## One toast at a time. Two toasts within a second used to leave two tweens
## animating `modulate:a`, and whichever finished last decided what the player
## saw: the newer line could be erased half a frame after it appeared, or an old
## one could sit there at 40% alpha (BUG-009). The old tween is killed first.
var _toast_tw: Tween = null


func _toast(text: String) -> void:
	if toast_lbl == null:
		return
	if _toast_tw != null and _toast_tw.is_valid():
		_toast_tw.kill()
	toast_lbl.text = text
	toast_lbl.modulate.a = 0.0
	var tw := create_tween()
	_toast_tw = tw
	tw.tween_property(toast_lbl, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.6)
	tw.tween_property(toast_lbl, "modulate:a", 0.0, 0.45)
