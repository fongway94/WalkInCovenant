extends CanvasLayer
class_name DialogueBox
## DialogueBox — the voice in the scene.
##
## Rebuilt for the development reset (docs/AUDIT.md §3). What changed and why:
##
##  * **One tap, one advance.** It no longer treats every input event as its own
##    press: presses go through TapGate, so the touch + emulated mouse + synthetic
##    A-button action of a single thumb-tap move exactly one line (AUDIT B1).
##  * **Keys are not all "next".** Only interact / accept / enter / space advance,
##    and Escape skips. Movement keys used to advance the box, so walking into a
##    conversation jumped two lines (AUDIT B6).
##  * **It paginates.** Lines are split into pages that fit a hard height cap, so
##    the panel can never grow over the game or off the screen. The old design
##    grew upward and relied on a lint to keep lines short (AUDIT C4).
##  * **It is quieter.** 80% opacity instead of 93%, a fraction of the screen
##    instead of a full-width sheet, a framed portrait, a gold rule between the
##    speaker and the speech, and a page counter (AUDIT C1-C3).
##
## UI chrome lives here; the WORDS live in data (no content strings in scripts/).
## Audio: music ducks while the box is open, and each speaker gets a pitched blip
## so voices are audible as distinct (docs/FEEL.md §4).

const TYPE_CPS := 34.0          # characters per second
const BLIP_EVERY := 3           # blip every N characters, not every character
## Nothing may hold the player hostage. If a box sits open this long with no
## input at all, it closes itself and hands the controls back (playtest 5: "i
## stuck at here cant get out"). Long enough that a slow reader never sees it.
const HANG_SECS := 40.0

## Emitted when a beat ends, however it ends. Region listens so that the very
## tap which closes a box cannot also count as "talk to this person" — that is
## the dialogue-repeats bug (playtest 8: "the dialogue appears three times").
signal closed
## Emitted when a beat opens. Main uses it to hand the touch controls over to
## the box, so a thumb on the stick cannot fight the conversation.
signal opened

var panel: PanelContainer = null
var portrait: TextureRect = null
var name_lbl: Label = null
var text_lbl: Label = null
var adv: Label = null
var page_lbl: Label = null
var choice_box: VBoxContainer = null
var skip_btn: Button = null
var rule: ColorRect = null

var _lines: Array = []
var _pages: Array = []
var _page := 0
var _i := 0
var _shown := 0.0
var _speaker_fn: Callable = Callable()
var _on_done: Callable = Callable()
var _open := false
var _in_choices := false
var _choices: Array = []
var _on_pick: Callable = Callable()
var _choice_i := 0        # which answer has the highlight (BUG-019)
var _blip_acc := 0
var _box_id := 0          # increments every time a new beat opens
var _idle := 0.0          # seconds since the last input while open
var _bob := 0.0


func _ready() -> void:
	layer = 20
	_build_ui()
	hide_box()
	var vp := get_viewport()
	if vp != null:
		vp.size_changed.connect(_apply_layout)


func is_open() -> bool:
	return _open


# ── construction ─────────────────────────────────────────────────────────
func _build_ui() -> void:
	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	# 80%, not 93%: the world has to stay legible behind a conversation — the
	# whole point of a conversation in this game is that you are looking at it.
	sb.bg_color = Color(0.04, 0.07, 0.10, 0.80)
	sb.border_color = Color(0.79, 0.64, 0.36, 0.70)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(5)
	sb.set_corner_radius_all(3)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 3
	panel.add_theme_stylebox_override("panel", sb)
	panel.anchor_left = 0.0; panel.anchor_right = 1.0
	panel.anchor_top = 1.0; panel.anchor_bottom = 1.0
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 5)
	panel.add_child(hbox)

	# ── portrait, framed ──────────────────────────────────────────────────
	var frame := PanelContainer.new()
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0.02, 0.04, 0.06, 0.85)
	fsb.border_color = Color(0.60, 0.49, 0.28, 0.75)
	fsb.set_border_width_all(1)
	fsb.set_content_margin_all(1)
	fsb.set_corner_radius_all(2)
	frame.add_theme_stylebox_override("panel", fsb)
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(frame)

	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(30, 30)
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# Nearest, so a 16x16 face stays crisp when the box scales it up. This
	# belongs on the CanvasItem: AtlasTexture has no `filter` property, and
	# assigning one is a runtime error that aborts the function it sits in —
	# which is how every portrait after the first line silently vanished.
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(portrait)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 1)
	hbox.add_child(vbox)

	# ── head: who is speaking, and the way out ───────────────────────────
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	vbox.add_child(head)

	name_lbl = Label.new()
	name_lbl.add_theme_font_size_override("font_size", 9)
	name_lbl.add_theme_color_override("font_color", Color(0.97, 0.87, 0.65))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_lbl)

	# Playtests 6 and 7 both said the same thing: "every dialogue box must always
	# have an escape." Tapping is one, but a tap is invisible — this is the
	# button. It SKIPS the rest of the beat rather than cancelling it, so the
	# beat's on_done still runs: skipping a verse must never eat the fight.
	skip_btn = Button.new()
	skip_btn.text = "»"
	skip_btn.flat = true
	skip_btn.add_theme_font_size_override("font_size", 9)
	skip_btn.add_theme_color_override("font_color", Color(0.79, 0.64, 0.36, 0.85))
	skip_btn.custom_minimum_size = Vector2(18, 12)
	skip_btn.focus_mode = Control.FOCUS_NONE
	skip_btn.tooltip_text = "skip"
	skip_btn.pressed.connect(func(): _skip_rest())
	head.add_child(skip_btn)

	# A hairline under the name: the speaker and the speech are different kinds
	# of text and used to look like one paragraph.
	rule = ColorRect.new()
	rule.color = Color(0.79, 0.64, 0.36, 0.35)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(rule)

	text_lbl = Label.new()
	text_lbl.add_theme_font_size_override("font_size", 10)
	text_lbl.add_theme_color_override("font_color", Color(0.92, 0.94, 0.95))
	text_lbl.add_theme_constant_override("line_spacing", 3)
	text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(text_lbl)

	# Choices live INSIDE the same panel, under the line they answer. As a
	# separate bottom-anchored box they overlapped the text they belonged to and
	# hung off the screen edge once there were four of them.
	choice_box = VBoxContainer.new()
	choice_box.add_theme_constant_override("separation", 3)
	choice_box.visible = false
	vbox.add_child(choice_box)

	# ── foot: page n of m, and the"you may continue" cue ─────────────────
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 4)
	vbox.add_child(foot)

	page_lbl = Label.new()
	page_lbl.add_theme_font_size_override("font_size", 7)
	page_lbl.add_theme_color_override("font_color", Color(0.62, 0.66, 0.68))
	page_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(page_lbl)

	adv = Label.new()
	adv.text = "▼"
	adv.add_theme_font_size_override("font_size", 8)
	adv.add_theme_color_override("font_color", Color(0.79, 0.64, 0.36))
	adv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	adv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(adv)


## Everything that depends on the screen size is applied here, once, and again
## whenever the viewport changes (rotation, browser chrome, fullscreen).
func _apply_layout() -> void:
	var vs := _view_size()
	var m := ScreenFit.dialogue(vs)
	var e: float = float(m["rect"].position.x)
	panel.offset_left = e
	panel.offset_right = -e
	panel.offset_bottom = -e
	panel.offset_top = -e          # zero height; grow_vertical=BEGIN grows up
	if _open:
		# the text column changed, so the pages have to be recomputed
		_paginate_current()


func _view_size() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return ScreenFit.BASE
	return vp.get_visible_rect().size


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
	_apply_layout()
	panel.visible = true
	choice_box.visible = false
	AudioDirector.duck(true)
	_render_line()
	opened.emit()


# ── pages ────────────────────────────────────────────────────────────────
func _rows_per_page() -> int:
	var font: Font = text_lbl.get_theme_font("font")
	var fs: int = text_lbl.get_theme_font_size("font_size")
	if font == null:
		return 3
	var row_h: float = font.get_height(fs) + 3.0
	var m := ScreenFit.dialogue(_view_size())
	var room: float = float(m["max_h"]) - float(m["overhead"])
	return clampi(int(room / maxf(1.0, row_h)), 1, 8)


static func _is_word_char(c: String) -> bool:
	if c.length() != 1:
		return false
	var n := c.unicode_at(0)
	return (n >= 48 and n <= 57) or (n >= 65 and n <= 90) or (n >= 97 and n <= 122) \
		or n == 39 or n == 45


## Split one line into pages that fit the box. Measured with the real font, so
## the guarantee is geometric rather than a character-count guess.
func _paginate(text: String) -> Array:
	var font: Font = text_lbl.get_theme_font("font")
	var fs: int = text_lbl.get_theme_font_size("font_size")
	var out: Array = []
	if font == null or text.length() == 0:
		out.append(text)
		return out
	var m := ScreenFit.dialogue(_view_size())
	# 4 px of slack: the wrap engine breaks at word boundaries, this does not.
	var max_w: float = float(m["text_w"]) - 4.0
	var rows_max := _rows_per_page()
	var n := text.length()
	var start := 0
	var i := 0
	var line_w := 0.0
	var rows := 1
	while i < n:
		var ch := text.substr(i, 1)
		if ch == "\n":
			rows += 1
			line_w = 0.0
			i += 1
			continue
		var w: float = font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if line_w + w > max_w:
			rows += 1
			line_w = 0.0
			# never cut a Latin word in half: back up to its first letter
			if _is_word_char(ch) and i - start > 2 and _is_word_char(text.substr(i - 1, 1)):
				var back := i
				while back > start + 1 and _is_word_char(text.substr(back - 1, 1)) and i - back < 14:
					back -= 1
				if back > start:
					i = back
		if rows > rows_max and i > start:
			var cut := i
			while cut > start and text.substr(cut - 1, 1) == " ":
				cut -= 1
			out.append(text.substr(start, cut - start))
			start = i
			while start < n and text.substr(start, 1) == " ":
				start += 1
			rows = 1
			line_w = 0.0
			continue
		line_w += w
		i += 1
	if start < n:
		out.append(text.substr(start))
	if out.is_empty():
		out.append(text)
	return out


func _paginate_current() -> void:
	var line: Dictionary = _lines[_i] if _i < _lines.size() else {}
	_pages = _paginate(I18n.t(line.get("text", "")))
	_page = clampi(_page, 0, maxi(0, _pages.size() - 1))
	_render_page()


func _render_page() -> void:
	text_lbl.text = ""
	_shown = 0.0
	adv.visible = false
	_bob = 0.0
	if page_lbl != null:
		if _pages.size() > 1:
			page_lbl.text = "%d/%d" % [_page + 1, _pages.size()]
		else:
			page_lbl.text = ""


func _current_page_text() -> String:
	if _page < 0 or _page >= _pages.size():
		return ""
	return str(_pages[_page])


# ── rendering ────────────────────────────────────────────────────────────
func _render_line() -> void:
	var line: Dictionary = _lines[_i] if _i < _lines.size() else {}
	var who: String = str(line.get("who", ""))
	var sp: Dictionary = _speaker_fn.call(who) if _speaker_fn.is_valid() else {}
	name_lbl.text = str(sp.get("name", ""))
	name_lbl.visible = name_lbl.text != ""
	rule.visible = name_lbl.visible
	_set_portrait(str(sp.get("actor", "")))
	_page = 0
	_paginate_current()


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
	var full := _current_page_text()
	if _shown < full.length():
		_shown = minf(full.length(), _shown + delta * TYPE_CPS)
		text_lbl.text = full.substr(0, int(_shown))
		_blip_acc += 1
		if _blip_acc >= BLIP_EVERY:
			_blip_acc = 0
			var line: Dictionary = _lines[_i] if _i < _lines.size() else {}
			AudioDirector.blip(str(line.get("who", "")))
	elif not adv.visible and full.length() > 0:
		adv.visible = true
	if adv.visible:
		# a slow bob, so the cue reads as "waiting for you" rather than a glyph
		_bob += delta * 3.0
		adv.position.y = 0.0
		adv.modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(_bob))


# ── input: exactly one meaning per tap ───────────────────────────────────
func _input(event: InputEvent) -> void:
	if not _open:
		return
	_idle = 0.0

	if _in_choices:
		# A choice box must never be a trap either: Escape closes the beat, the
		# number keys pick, and — since an answer could otherwise only be given
		# with a mouse or a thumb — the d-pad moves the highlight and the same
		# one button that advances every other line answers. The A button on the
		# phone, the pad, and Space/Enter all arrive as "interact"/"ui_accept";
		# before this they reached nothing at all while answers were on screen
		# (BUG-019). It is still NOT "any key picks the first option" — walking
		# away with W picked an answer for the player (AUDIT B5), so W and A are
		# only ever a direction here.
		var want := -1
		var step := 0
		if event is InputEventKey:
			var k := event as InputEventKey
			if not k.pressed or k.echo:
				return
			var code := k.keycode
			if code == KEY_ESCAPE:
				_finish()
				get_viewport().set_input_as_handled()
				return
			elif code >= KEY_1 and code <= KEY_9:
				var idx := code - KEY_1
				if idx < _choices.size():
					want = idx
			elif code in [KEY_UP, KEY_LEFT]:
				step = -1
			elif code in [KEY_DOWN, KEY_RIGHT]:
				step = 1
			elif code in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] \
					or event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
				want = _choice_i
			else:
				return
		elif event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
			want = _choice_i
		else:
			# Taps and clicks belong to the answer buttons themselves.
			return
		if step != 0:
			_move_choice(step)
		elif want >= 0 and want < _choices.size():
			_pick(want)
		get_viewport().set_input_as_handled()
		return

	# Touch and mouse are the same gesture as far as this box is concerned; the
	# emulated twin of a touch is dropped by TapGate, not by guessing here.
	var pressed := false
	var pos := Vector2.ZERO
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		pressed = t.pressed
		pos = t.position
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		pressed = mb.pressed
		pos = mb.position
	elif event is InputEventKey:
		# Only keys that MEAN "next". W/A/S/D used to advance the box, so
		# walking into a conversation skipped two lines (AUDIT B6).
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		if k.keycode == KEY_ESCAPE:
			if TapGate.take():
				_skip_rest()
			get_viewport().set_input_as_handled()
			return
		if k.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			pressed = true
		elif event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
			pressed = true
		else:
			return
	elif event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		# Gamepad buttons and the synthetic action the touch A button emits.
		# Without this branch the pad could not advance a line at all, and the
		# phone's A press only worked because a raw touch happened to arrive
		# with it.
		pressed = true
	else:
		return

	if not pressed:
		return

	# A tap on the skip button or on an answer belongs to that button. Without
	# this the same tap skipped the beat AND advanced a line underneath it.
	if pos != Vector2.ZERO and _over_control(pos):
		return
	if not TapGate.take():
		return
	get_viewport().set_input_as_handled()
	_advance()


func _over_control(pos: Vector2) -> bool:
	if skip_btn != null and skip_btn.visible and skip_btn.get_global_rect().has_point(pos):
		return true
	if choice_box != null and choice_box.visible:
		for ch in choice_box.get_children():
			var c := ch as Control
			if c != null and c.visible and c.get_global_rect().has_point(pos):
				return true
	return false


## Jump to the end of this beat: last line, last page, shown whole. A second
## press closes it, which still runs its on_done — the story cannot be skipped
## into a broken state, only read faster.
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
	if _i >= _lines.size() - 1 and _shown >= float(_current_page_text().length()):
		_finish()
		return
	_i = _lines.size() - 1
	var last: Dictionary = _lines[_i]
	if last.has("choices"):
		_i = maxi(0, _i - 1)
		_render_line()
		return
	_render_line()
	_page = maxi(0, _pages.size() - 1)
	var full := _current_page_text()
	_shown = float(full.length())
	text_lbl.text = full
	adv.visible = true


func _advance() -> void:
	var full := _current_page_text()
	if _shown < float(full.length()):
		# finish the page first — never skip a line the player has not read
		_shown = float(full.length())
		text_lbl.text = full
		adv.visible = true
		return
	if _page < _pages.size() - 1:
		_page += 1
		_render_page()
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
	closed.emit()
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
		b.add_theme_color_override("font_color", Color(0.95, 0.91, 0.80))
		b.custom_minimum_size = Vector2(0, 24)   # a thumb, not a pixel
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_stylebox_override("normal", _choice_style(0.62))
		b.add_theme_stylebox_override("hover", _choice_style(0.95))
		b.add_theme_stylebox_override("pressed", _choice_style(1.0))
		b.add_theme_stylebox_override("focus", _choice_style(0.95))
		var picked := idx
		b.pressed.connect(func(): _pick(picked))
		choice_box.add_child(b)
	_choice_i = 0
	_focus_choice()
	if _pages.size() > 0:
		# the question stays whole behind the answers
		_shown = float(_current_page_text().length())
		text_lbl.text = _current_page_text()
		adv.visible = false


## Put the ring on an answer, so a keyboard or pad player can see what A will do.
func _focus_choice() -> void:
	if choice_box == null or not _in_choices:
		return
	var kids := choice_box.get_children()
	if kids.is_empty():
		return
	_choice_i = clampi(_choice_i, 0, kids.size() - 1)
	var b: Button = kids[_choice_i] as Button
	if b != null:
		b.grab_focus()


## Wrap-around, because a two-answer question at the bottom of the screen is not
## the place to teach a player that the list does not wrap.
func _move_choice(step: int) -> void:
	var n := choice_box.get_child_count()
	if n <= 0:
		return
	_choice_i = ((_choice_i + step) % n + n) % n
	_focus_choice()


## Choices used the engine's default theme and were the one place the pixel style
## broke. They now match the panel: dark, gold-edge, flat.
func _choice_style(alpha: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.10, 0.14, 0.17, 0.92)
	s.border_color = Color(0.79, 0.64, 0.36, alpha)
	s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	s.set_content_margin_all(3)
	s.content_margin_left = 6
	return s


func _pick(idx: int) -> void:
	# The answer can arrive twice — the game's input path and the button's own
	# signal — and picking an ending twice must not run its callback twice.
	if not _in_choices or idx < 0 or idx >= _choices.size():
		return
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
	opened.emit()


func _clear_choices() -> void:
	for ch in choice_box.get_children():
		ch.queue_free()
