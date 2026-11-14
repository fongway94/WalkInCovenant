extends CanvasLayer
class_name Journal
## Journal — the pilgrim's book, and the only screen in the game that is yours.
##
## The master brief asks for a quest journal, an inventory and achievements as
## separate systems. They are the same question a player asks on a phone at the
## bus stop: *what am I carrying, and what am I doing?* So it is one panel:
## the chapter's own objective, the verses in the bag, the stones, and the marks
## earned. Everything it prints comes from data — `data/ui.json` for the labels,
## the region for the verses, `data/achievements.json` for the marks.

signal closed
## The book only asks; Main captures the live position and switches saves.
signal journey_requested

const UI_PATH := "res://data/ui.json"
const CONFIRM_DELAY_MS := 550

var _panel: PanelContainer = null
var _title: Label = null
var _body: VBoxContainer = null
var _labels: Dictionary = {}
var _open := false
var _close_btn: Button = null
var _journey_btn: Button = null
var _confirming := false
var _confirm_ready_at := 0
var _journey_error := false
## What the panel was opened with, kept so it can be printed again in another
## language. The book is read at leisure; the switch sits on the HUD around it.
var _args: Dictionary = {}


func _ready() -> void:
	layer = 26
	_load_labels()
	_build()
	hide_panel()
	if not I18n.language_changed.is_connected(_on_language_changed):
		I18n.language_changed.connect(_on_language_changed)


func is_open() -> bool:
	return _open


func _load_labels() -> void:
	if not FileAccess.file_exists(UI_PATH):
		return
	var f := FileAccess.open(UI_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		_labels = (parsed as Dictionary).get("journal", {})


func _t(key: String) -> String:
	return I18n.t(_labels.get(key, {"en": key, "zh": key}))


func _build() -> void:
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	# Fully opaque. At 0.97 the HUD and any dialogue box still on screen showed
	# through as grey ghost text behind 9 px rows — visible in CI frames
	# 04_journal and 12_journal_before once the transport copy was quantised.
	sb.bg_color = Color(0.06, 0.08, 0.10, 1.0)
	sb.border_color = Color(0.79, 0.64, 0.36, 0.9)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(8)
	sb.set_corner_radius_all(3)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.anchor_left = 0.0; _panel.anchor_right = 1.0
	_panel.anchor_top = 0.0; _panel.anchor_bottom = 1.0
	_panel.offset_left = 12; _panel.offset_right = -12
	# Keep the HUD's language/sound buttons completely above the panel. Their
	# centres used to be covered, so the advertised live translation could not
	# actually be tapped while the book was open on a phone.
	_panel.offset_top = 24; _panel.offset_bottom = -8
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 11)
	_title.add_theme_color_override("font_color", Color(0.97, 0.87, 0.65))
	vbox.add_child(_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 3)
	scroll.add_child(_body)

	# The journey control stays visible even on a short landscape screen; it is
	# not buried under the scrollable verses and background.
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	vbox.add_child(buttons)
	_journey_btn = Button.new()
	_journey_btn.custom_minimum_size = Vector2(0, 24)
	_journey_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_journey_btn.add_theme_font_size_override("font_size", 9)
	_journey_btn.pressed.connect(_on_journey_button)
	buttons.add_child(_journey_btn)
	_close_btn = Button.new()
	_close_btn.custom_minimum_size = Vector2(0, 24)
	_close_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_close_btn.add_theme_font_size_override("font_size", 10)
	_close_btn.pressed.connect(close_panel)
	buttons.add_child(_close_btn)


func _row(text: String, size: int, col: Color, indent: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if indent > 0:
		l.add_theme_constant_override("line_spacing", 1)
		l.text = "  " + text
	_body.add_child(l)
	return l


func _heading(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 9)
	l.add_theme_color_override("font_color", Color(0.79, 0.64, 0.36))
	_body.add_child(l)


## Everything the panel shows is passed in: this node owns the furniture, not
## the story. `verse_refs` are resolved by the caller from the region data.
func open_panel(title: String, objective: String, verse_refs: Array,
		stones: int, stones_total: int, seals: Array, seal_titles: Dictionary,
		background: Array = [], has_replay: bool = false, replay_active: bool = false) -> void:
	if not _open:
		_confirming = false
		_journey_error = false
	_args = {
		"title": title, "objective": objective, "refs": verse_refs,
		"stones": stones, "total": stones_total,
		"seals": seals, "titles": seal_titles, "background": background,
		"has_replay": has_replay, "replay_active": replay_active,
	}
	_render()


## Print the book again from what it was handed. Called on open, and again when
## the language changes underneath a page that is already open — without this the
## panel stayed in the language the player had just left, including its own close
## button (BUG-029).
func _render() -> void:
	if _args.is_empty():
		return
	var title := str(_args.get("title", ""))
	var objective := str(_args.get("objective", ""))
	var verse_refs: Array = _args.get("refs", [])
	var stones := int(_args.get("stones", 0))
	var stones_total := int(_args.get("total", 0))
	var seals: Array = _args.get("seals", [])
	var seal_titles: Dictionary = _args.get("titles", {})
	_title.text = title
	var replay_active := bool(_args.get("replay_active", false))
	var has_replay := bool(_args.get("has_replay", false))
	var action_key := "return_original" if replay_active else ("resume_replay" if has_replay else "start_replay")
	_close_btn.text = _t("cancel") if _confirming else _t("close")
	_journey_btn.text = _t("confirm") if _confirming else _t(action_key)
	_journey_btn.disabled = GameState.save_protected()
	# Detach before freeing: queue_free() leaves the old rows in the layout until
	# the frame ends, so a reprint showed the page twice for one frame and the
	# panel jumped while the text under it changed.
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()

	if _confirming:
		_heading(_t("journey"))
		_row(_t(action_key + "_question"), 10, Color(0.95, 0.93, 0.86))
		_panel.visible = true
		_open = true
		return
	if GameState.save_protected():
		_heading(_t("save_protected_title"))
		_row(_t("save_protected_note"), 9, Color(1.0, 0.78, 0.68))
	if _journey_error:
		_row(_t("journey_error"), 9, Color(1.0, 0.75, 0.65))
	_heading(_t("objective"))
	_row(objective, 10, Color(0.90, 0.93, 0.94))
	_heading(_t("journey"))
	var note_key := "replay_active_note" if replay_active else "original_note"
	_row(_t(note_key), 9, Color(0.85, 0.88, 0.86))

	_heading(_t("verses"))
	if verse_refs.is_empty():
		_row(_t("empty"), 9, Color(0.6, 0.62, 0.62), 1)
	else:
		for r in verse_refs:
			# An entry is {ref, text} now. It used to be the citation alone, so
			# the one reward the whole game is built on — a verse someone gave
			# you — was a string you could not read (BUG-028). A plain string is
			# still accepted, so an old caller (or a test) cannot break this.
			if r is Dictionary:
				var e: Dictionary = r
				_row("★  " + str(e.get("ref", "")), 9, Color(0.97, 0.87, 0.65))
				var body := str(e.get("text", ""))
				if body != "":
					_row(body, 8, Color(0.85, 0.88, 0.86), 1)
			else:
				_row("★  " + str(r), 9, Color(0.97, 0.87, 0.65))

	_heading(_t("stones"))
	_row("%d / %d" % [stones, stones_total], 10, Color(0.80, 0.92, 0.96), 1)

	_heading(_t("seals"))
	if seals.is_empty():
		_row(_t("empty"), 9, Color(0.6, 0.62, 0.62), 1)
	else:
		for id in seals:
			var nm: Dictionary = seal_titles.get(str(id), {})
			var label := I18n.t(nm) if not nm.is_empty() else str(id)
			_row("◆  " + label, 9, Color(0.86, 0.90, 0.86))

	# Optional background. The opening used to force these lines in front of a
	# new player; now they are here, at the bottom of the page, for the curious.
	# A line is either the region's {who, text:{en,zh}} shape or a bare {en,zh}.
	var bg: Array = _args.get("background", [])
	_heading(_t("before"))
	if bg.is_empty():
		_row(_t("empty"), 9, Color(0.6, 0.62, 0.62), 1)
	else:
		for b in bg:
			var d: Dictionary = b
			var txt: Variant = d.get("text", d)
			# Optional does not mean unreadable. These are the words the boot
			# no longer forces on a player; at 8 px and 0.72 grey they were
			# the dimmest thing in the book (CI frame 12_journal_before).
			# No shadow either: at 9 px a 1 px solid black shadow sits *under*
			# every CJK stroke and reads as a black blotch behind the row.
			_row(I18n.t(txt), 9, Color(0.88, 0.90, 0.88), 1)

	_panel.visible = true
	_open = true


## The book must always have a way out. It pauses the world and blocks the touch
## controls, and its only exit was a small button in the corner: a keyboard
## player had no way back to the game at all, and the same tap-first/keys-second
## rule that every dialogue box follows was not applied here (BUG-012). Escape
## and the pad's B close it, exactly as they close a conversation.
func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_panel()
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close_panel()


func _on_language_changed(_lang: String) -> void:
	if _open:
		_render()


func _on_journey_button() -> void:
	if not _open or GameState.save_protected():
		return
	if not _confirming:
		_journey_error = false
		_confirming = true
		# One physical tap can be followed by an emulated mouse event. It must
		# never both ask and confirm a switch of journeys.
		_confirm_ready_at = Time.get_ticks_msec() + CONFIRM_DELAY_MS
		_render()
		return
	if Time.get_ticks_msec() >= _confirm_ready_at:
		journey_requested.emit()


## Keep the book open with an explanation when storage is unavailable.
func journey_switch_failed() -> void:
	_confirming = false
	_journey_error = true
	_render()


func close_panel() -> void:
	if not _open:
		return
	if _confirming:
		_confirming = false
		_render()
		return
	hide_panel()
	closed.emit()


func hide_panel() -> void:
	_open = false
	_confirming = false
	if _panel:
		_panel.visible = false
