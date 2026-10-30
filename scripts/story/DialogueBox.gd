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
## Nothing may hold the player hostage. If a box sits open this long with no
## input at all, it closes itself and hands the controls back (playtest 5: "i
## stuck at here cant get out"). Long enough that a slow reader never sees it.
const HANG_SECS := 40.0

var panel: PanelContainer = null
var portrait: TextureRect = null
var name_lbl: Label = null
var text_lbl: Label = null
var adv: Label = null
var choice_box: VBoxContainer = null
var skip_btn: Button = null

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
var _box_id := 0          # increments every time a new beat opens
var _idle := 0.0          # seconds since the last input while open


func _ready() -> void:
	layer = 20
	_build_ui()
	hide_box()


func _build_ui() -> void:
	# ── the panel ─────────────────────────────────────────────────────────
	# Full width minus a margin, anchored to the bottom, and GROWING UPWARD to
	# fit its content. It used to be a fixed 312x78 rectangle, so any line longer
	# than about two rows simply ran out of the box — that is the "dialog box
	# sometimes goes over the screen" report, and it hit the longest and most
	# important lines (the verses) first.
	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.09, 0.12, 0.93)
	sb.border_color = Color(0.79, 0.64, 0.36, 0.8)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(5)
	sb.set_corner_radius_all(3)
	panel.add_theme_stylebox_override("panel", sb)
	panel.anchor_left = 0.0; panel.anchor_right = 1.0
	panel.anchor_top = 1.0; panel.anchor_bottom = 1.0
	panel.offset_left = 5; panel.offset_right = -5
	panel.offset_top = -5; panel.offset_bottom = -5
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 5)
	panel.add_child(hbox)

	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(30, 38)
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# Nearest, so a 16x16 face stays crisp when the box scales it up. This
	# belongs on the CanvasItem: AtlasTexture has no `filter` property, and
	# assigning one is a runtime error that aborts the function it sits in —
	# which is how every portrait after the first line silently vanished.
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hbox.add_child(portrait)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 1)
	hbox.add_child(vbox)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	vbox.add_child(head)

	name_lbl = Label.new()
	name_lbl.add_theme_font_size_override("font_size", 9)
	name_lbl.add_theme_color_override("font_color", Color(0.97, 0.87, 0.65))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_lbl)

	# Playtests 6 and 7 both said the same thing: "every dialogue box must always
	# have an escape." Tapping is one, but a tap is invisible — this is the button.
	# It SKIPS the rest of the beat rather than cancelling it, so the beat's
	# on_done still runs: skipping a verse must never eat the fight that follows.
	skip_btn = Button.new()
	skip_btn.text = "»»"
	skip_btn.flat = true
	skip_btn.add_theme_font_size_override("font_size", 9)
	skip_btn.custom_minimum_size = Vector2(22, 16)
	skip_btn.tooltip_text = "skip"
	skip_btn.pressed.connect(func(): _skip_rest())
	head.add_child(skip_btn)

	text_lbl = Label.new()
	text_lbl.add_theme_font_size_override("font_size", 10)
	text_lbl.add_theme_color_override("font_color", Color(0.90, 0.93, 0.94))
	text_lbl.add_theme_constant_override("line_spacing", 2)
	text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(text_lbl)

	# Choices live INSIDE the same panel, under the line they answer. As a
	# separate bottom-anchored box they overlapped the text they belonged to and
	# hung off the screen edge once there were four of them.
	choice_box = VBoxContainer.new()
	choice_box.add_theme_constant_override("separation", 3)
	choice_box.visible = false
	vbox.add_child(choice_box)

	adv = Label.new()
	adv.text = "▼"
	adv.add_theme_font_size_override("font_size", 8)
	adv.add_theme_color_override("font_color", Color(0.79, 0.64, 0.36))
	adv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(adv)


func is_open() -> bool:
	return _open


func hide_box() -> void:
	_open = false
	_in_choices = false
	_idle = 0.0
	if panel:
		panel.visible = false
	if choice_box:
		_clear_choices()
		choice_box.visible = false
	AudioDirector.duck(false)


func show_lines(lines: Array, speaker_fn: Callable, on_done: Callable) -> void:
	_box_id += 1
	_lines = lines
	_i = 0
	_shown = 0.0
	_speaker_fn = speaker_fn
	_on_done = on_done
	_open = true
	_in_choices = false     # MUST clear: a stale choice flag locks all input out
	_idle = 0.0
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
	at.region = Rect2(0, 0, 16, 16)      # row 0 (down), frame 0
	portrait.texture = at
	portrait.visible = true


func _process(delta: float) -> void:
	if not _open:
		return
	_idle += delta
	if _idle >= HANG_SECS:
		_force_close()
		return
	if _in_choices:
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
	_idle = 0.0
	if _in_choices:
		# A choice box must never be a trap either: keyboard players get the
		# first option, and Escape always closes the beat outright.
		if event is InputEventKey and (event as InputEventKey).pressed \
				and not (event as InputEventKey).echo:
			var code := (event as InputEventKey).keycode
			if code != KEY_ESCAPE and not _choices.is_empty() and _on_pick.is_valid():
				_pick(0)      # the default way forward
			else:
				_finish()
			get_viewport().set_input_as_handled()
		return
	# Every way a player can say "next". Touch is listed explicitly: the phone
	# build used to rely on the browser synthesising a mouse event from a touch,
	# and when that conversion does not happen the box simply stopped advancing
	# — the single reported way to get stuck in this game (playtest 5).
	var advance := false
	if event is InputEventScreenTouch:
		advance = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton:
		advance = (event as InputEventMouseButton).pressed
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			_skip_rest()
			get_viewport().set_input_as_handled()
			return
		advance = k.pressed and not k.echo
	elif event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		advance = true
	if advance:
		_advance()
		get_viewport().set_input_as_handled()


## Jump to the last line of this beat and show it whole. A second press closes
## the beat, which still runs its on_done — the story cannot be skipped into a
## broken state, only read faster.
func _skip_rest() -> void:
	if not _open:
		return
	_idle = 0.0
	if _in_choices:
		_finish()
		return
	if _lines.is_empty():
		_finish()
		return
	if _i >= _lines.size() - 1 and _shown >= 1.0:
		_finish()
		return
	_i = _lines.size() - 1
	var last: Dictionary = _lines[_i]
	if last.has("choices"):
		_i = maxi(0, _i - 1)
		_render_line()
		_shown = 1e9
		return
	_render_line()
	var full: String = I18n.t(last.get("text", ""))
	_shown = float(full.length())
	text_lbl.text = full
	adv.visible = true


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
	_in_choices = false
	_idle = 0.0
	panel.visible = false
	choice_box.visible = false
	_clear_choices()
	AudioDirector.duck(false)
	var done := _on_done
	_on_done = Callable()          # one shot: never unpause twice, never leak
	if done.is_valid():
		done.call()


func _force_close() -> void:
	# The watchdog's exit. A pending choice resolves to its first option (that is
	# the story's default way forward); anything else simply ends the beat.
	if _in_choices and _on_pick.is_valid() and not _choices.is_empty():
		_pick(0)
		return
	_finish()


# ── choices ─────────────────────────────────────────────────────────────
func _open_choices(options: Array) -> void:
	_in_choices = true
	_choices = options
	_clear_choices()
	choice_box.visible = true
	for idx in range(options.size()):
		var opt: Dictionary = options[idx]
		var b := Button.new()
		b.text = I18n.t(opt.get("t", ""))
		b.add_theme_font_size_override("font_size", 10)
		b.custom_minimum_size = Vector2(0, 26)   # a thumb, not a pixel
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	var opened := _box_id
	if _on_pick.is_valid():
		_on_pick.call(idx, _choices[idx])
	# The callback usually opens the next beat itself (the word battle shows a
	# feedback line, an NPC continues). If it did, this box is already a new
	# one: advancing here would instantly finish a line the player never saw and
	# fire its on_done early, which skipped every single-line follow-up — the
	# battle's "the sling takes a stone" beat among them.
	if _box_id != opened:
		return
	# continue after the chosen reply, if the node defines one
	_i += 1
	if _i >= _lines.size():
		_finish()
	else:
		_render_line()


func show_choices_standalone(options: Array, on_pick: Callable) -> void:
	_box_id += 1
	_open = true
	_in_choices = true
	# The line the choice answers must stay on screen. _finish() hides the panel
	# before its callback runs, so a standalone choice box opened the question
	# into an empty screen.
	panel.visible = text_lbl != null and text_lbl.text != ""
	_on_pick = on_pick
	_open_choices(options)


func _clear_choices() -> void:
	for ch in choice_box.get_children():
		ch.queue_free()
