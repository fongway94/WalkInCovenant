extends CanvasLayer
class_name DialogueBox
## DialogueBox — typewriter dialogue with faceset portraits, nameplate,
## choices, and a backlog-free "advance on tap" contract.
##
## Built in code rather than a .tscn so the whole system is one file and there
## is no scene-wiring to get wrong. UI chrome lives here; the WORDS live in
## data (no content strings in scripts/ — enforced by test_i18n).
##
## Audio: music ducks while the box is open, and each speaker gets a pitched
## blip per character group so voices are audible as distinct (docs/FEEL.md §4).

const TYPE_CPS := 34.0          # characters per second
const BLIP_EVERY := 3           # blip every N characters, not every character

var panel: PanelContainer = null
var portrait: TextureRect = null
var name_lbl: Label = null
var text_lbl: Label = null
var adv: Label = null
var choice_box: VBoxContainer = null

var _lines: Array = []
var _i := 0
var _shown := 0.0
var _speaker_fn: Callable = Callable()
var _on_done: Callable = Callable()
var _open := false
var _in_choices := false
var _choices: Array = []
var _on_pick: Callable = Callable()
var _blip_acc := 0


func _ready() -> void:
	layer = 20
	_build_ui()
	hide_box()


func _build_ui() -> void:
	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.09, 0.12, 0.92)
	sb.border_color = Color(0.79, 0.64, 0.36, 0.8)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(6)
	sb.set_corner_radius_all(3)
	panel.add_theme_stylebox_override("panel", sb)
	panel.anchor_left = 0.5; panel.anchor_right = 0.5
	panel.anchor_top = 1.0; panel.anchor_bottom = 1.0
	panel.offset_left = -150; panel.offset_right = 150
	panel.offset_top = -64; panel.offset_bottom = -8
	add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	panel.add_child(hbox)

	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(28, 40)
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hbox.add_child(portrait)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)

	name_lbl = Label.new()
	name_lbl.add_theme_font_size_override("font_size", 8)
	name_lbl.add_theme_color_override("font_color", Color(0.97, 0.87, 0.65))
	vbox.add_child(name_lbl)

	text_lbl = Label.new()
	text_lbl.add_theme_font_size_override("font_size", 8)
	text_lbl.add_theme_color_override("font_color", Color(0.9, 0.93, 0.94))
	text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_lbl.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(text_lbl)

	adv = Label.new()
	adv.text = "▼"
	adv.add_theme_font_size_override("font_size", 7)
	adv.add_theme_color_override("font_color", Color(0.79, 0.64, 0.36))
	adv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(adv)

	choice_box = VBoxContainer.new()
	choice_box.anchor_left = 0.5; choice_box.anchor_right = 0.5
	choice_box.anchor_top = 1.0; choice_box.anchor_bottom = 1.0
	choice_box.offset_left = -120; choice_box.offset_right = 120
	choice_box.offset_top = -110; choice_box.offset_bottom = -70
	add_child(choice_box)


func hide_box() -> void:
	_open = false
	_in_choices = false
	if panel:
		panel.visible = false
	if choice_box:
		_clear_choices()
		choice_box.visible = false
	AudioDirector.duck(false)


func show_lines(lines: Array, speaker_fn: Callable, on_done: Callable) -> void:
	_lines = lines
	_i = 0
	_shown = 0.0
	_speaker_fn = speaker_fn
	_on_done = on_done
	_open = true
	panel.visible = true
	choice_box.visible = false
	AudioDirector.duck(true)
	_render_line()


func _render_line() -> void:
	var line: Dictionary = _lines[_i] if _i < _lines.size() else {}
	var who: String = str(line.get("who", ""))
	var sp: Dictionary = _speaker_fn.call(who) if _speaker_fn.is_valid() else {}
	name_lbl.text = str(sp.get("name", ""))
	name_lbl.visible = name_lbl.text != ""
	_set_portrait(str(sp.get("actor", "")))
	text_lbl.text = ""
	_shown = 0.0
	adv.visible = false


func _set_portrait(actor: String) -> void:
	if actor == "":
		portrait.visible = false
		return
	var tex := load("res://art/characters/%s_idle.png" % actor)
	if tex == null:
		portrait.visible = false
		return
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(0, 0, 16, 24)      # row 0 (down), frame 0
	portrait.texture = at
	portrait.visible = true
	portrait.texture.filter = 0          # nearest — keep it crisp


func _process(delta: float) -> void:
	if not _open or _in_choices:
		return
	var line: Dictionary = _lines[_i] if _i < _lines.size() else {}
	var full: String = I18n.t(line.get("text", ""))
	if _shown < full.length():
		_shown = minf(full.length(), _shown + delta * TYPE_CPS)
		text_lbl.text = full.substr(0, int(_shown))
		_blip_acc += 1
		if _blip_acc >= BLIP_EVERY:
			_blip_acc = 0
			AudioDirector.blip(str(line.get("who", "")))
	else:
		adv.visible = true


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if _in_choices:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") \
			or (event is InputEventMouseButton
				and (event as InputEventMouseButton).pressed):
		_advance()
		get_viewport().set_input_as_handled()


func _advance() -> void:
	var line: Dictionary = _lines[_i] if _i < _lines.size() else {}
	var full: String = I18n.t(line.get("text", ""))
	if _shown < full.length():
		_shown = float(full.length())
		text_lbl.text = full
		adv.visible = true
		return
	_i += 1
	if _i >= _lines.size():
		_finish()
		return
	var nxt: Dictionary = _lines[_i]
	if nxt.has("choices"):
		_open_choices(nxt["choices"])
	else:
		_render_line()


func _finish() -> void:
	_open = false
	panel.visible = false
	AudioDirector.duck(false)
	if _on_done.is_valid():
		_on_done.call()


# ── choices ─────────────────────────────────────────────────────────────
func _open_choices(options: Array) -> void:
	_in_choices = true
	_choices = options
	_clear_choices()
	choice_box.visible = true
	for idx in range(options.size()):
		var b := Button.new()
		b.text = I18n.t(options[idx].get("t", ""))
		b.add_theme_font_size_override("font_size", 8)
		b.flat = false
		var picked := idx
		b.pressed.connect(func(): _pick(picked))
		choice_box.add_child(b)


func _pick(idx: int) -> void:
	_in_choices = false
	_clear_choices()
	choice_box.visible = false
	GameState.record_way("notice")
	EventBus.choice_made.emit(str(_i), idx)
	if _on_pick.is_valid():
		_on_pick.call(idx, _choices[idx])
	# continue after the chosen reply, if the node defines one
	var opt: Dictionary = _choices[idx]
	_i += 1
	if _i >= _lines.size():
		_finish()
	else:
		_render_line()


func show_choices_standalone(options: Array, on_pick: Callable) -> void:
	_open = true
	_in_choices = true
	panel.visible = false
	_on_pick = on_pick
	_open_choices(options)


func _clear_choices() -> void:
	for ch in choice_box.get_children():
		ch.queue_free()
