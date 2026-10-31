extends CanvasLayer
class_name GoliathFight
## GoliathFight — the fight itself, played with a sling, not with a quiz.
##
## Playtest 8 asked for exactly this: "throw stone to attack goliath and avoid
## its attack". The chapter used to hand the confrontation to a multiple-choice
## verse quiz and only then play a two-minute duel; the duel was the epilogue of
## the real thing. Now it is the whole thing (docs/RESET-REPORT.md, feedback #2).
##
## The loop, and it alternates every round:
##
##   HE WINDS UP    a red ring pulses at his shoulder. He is committed.
##   HE STRIKES     a red spear runs at you. Press A / tap / any direction
##                  BEFORE it reaches you and you step aside.
##   YOU THROW      a marker sweeps across his forehead. Press inside the gold
##                  band and the stone lands.
##
## Three stones in the forehead and it is over. Five in the pouch, and two more
## come up from the brook when you run dry. There is no game-over screen: the
## fight this retells has a fixed ending, and a boy who keeps getting hit loses
## his footing, never the story.
##
## Everything is drawn with _draw and re-laid out from ScreenFit on resize, so it
## frames itself the same way on a 320x180 canvas and on a 2400x1080 browser.

signal finished

const HITS_TO_WIN := 3
const STONES := 5
const NERVE := 3

const TELEGRAPH_TIME := 0.80
const STRIKE_TIME := 0.80
const RESOLVE_TIME := 0.55
const DODGE_WINDOW := 0.86      # press before the spear is this far across
const MARKER_SPEED := 1.9

enum Phase { TELEGRAPH, STRIKE, AIM, RESOLVE, DONE }

var phase: Phase = Phase.TELEGRAPH
var hits := 0
var stones := STONES
var nerve := NERVE
var round_no := 0

var _t := 0.0
var _strike := 0.0
var _marker := 0.0
var _marker_dir := 1.0
var _band := 0.26
var _dodged := false
var _thrown := false
var _msg := ""
var _msg_t := 0.0
var _flash := 0.0
var _shake := 0.0
var _layer: Control = null
var _david: TextureRect = null
var _gol: TextureRect = null
## Resting positions, so the shake can jitter around a known point instead of
## walking the sprites off the screen a pixel at a time.
var _gol_base := Vector2.ZERO
var _david_base := Vector2.ZERO
## Where he ends this round, so RESOLVE knows what comes next.
var _after_resolve := "aim"
## He does not disappear the instant the third stone lands. The win plays out on
## the same screen for a beat, and only then does the chapter move on.
const FALL_TIME := 1.0

## How long a press stays queued when it lands in a phase that cannot use it.
## A player presses when they see the threat, which is a fraction of a second
## before the phase that answers it opens; a press that is simply thrown away
## reads as a dead game (BUG-016).
const BUFFER_SECS := 0.45
var _buffer := 0.0
## The A badge this screen draws for itself. See _press_at().
var _fall := 0.0
var _emitted := false


func _ready() -> void:
	# Below the dialogue box (20) but above the world and the stick (12): the
	# lines that close the chapter are spoken over the fallen giant, not over a
	# valley the duel has already vanished from.
	layer = 14
	_build()
	_apply_layout()
	var vp := get_viewport()
	if vp != null:
		vp.size_changed.connect(_apply_layout)


func _frame(path: String) -> AtlasTexture:
	var tex := load(path)
	if tex == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(0, 0, 16, 16)
	return at


func _build() -> void:
	_layer = Control.new()
	_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_layer)
	_layer.draw.connect(_redraw)
	_layer.gui_input.connect(_on_layer_gui)

	_gol = TextureRect.new()
	_gol.texture = _frame("res://art/characters/goliath_idle.png")
	_gol.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_gol.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_gol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_gol)

	_david = TextureRect.new()
	_david.texture = _frame("res://art/characters/%s_idle.png" % CampaignModel.current_hero())
	_david.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_david.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_david.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_david)


## Positions in one place, from the same layout maths the rest of the game uses.
func _apply_layout() -> void:
	var vs := _view_size()
	var ground := vs.y * 0.66
	var gol_w := clampf(vs.x * 0.30, 72.0, 128.0)
	var dav_w := clampf(vs.x * 0.14, 34.0, 60.0)
	_gol.size = Vector2(gol_w, gol_w)
	_gol_base = Vector2(vs.x * 0.74 - gol_w * 0.5, ground - gol_w + 6.0)
	_david.size = Vector2(dav_w, dav_w)
	_david_base = Vector2(vs.x * 0.22 - dav_w * 0.5, ground - dav_w + 6.0)
	_gol.position = _gol_base
	_david.position = _david_base
	_layer.queue_redraw()


func _view_size() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return ScreenFit.BASE
	return vp.get_visible_rect().size


func start() -> void:
	hits = 0
	stones = STONES
	nerve = NERVE
	round_no = 0
	_msg = ""
	_msg_t = 0.0
	_fall = 0.0
	_emitted = false
	_begin_round()


# ── the loop ─────────────────────────────────────────────────────────────
## The first spear is the one that teaches the rule: it comes slower than every
## spear after it, and it says so on screen. A player who has never seen the
## fight must not lose the first exchange to the clock.
func _telegraph_time() -> float:
	return TELEGRAPH_TIME + (0.9 if round_no <= 1 else 0.0)


func _begin_round() -> void:
	phase = Phase.TELEGRAPH
	_t = 0.0
	_strike = 0.0
	_dodged = false
	_thrown = false
	_after_resolve = "aim"
	round_no += 1


func _begin_aim() -> void:
	phase = Phase.AIM
	_t = 0.0
	_marker = -1.0
	_marker_dir = 1.0
	_thrown = false
	# his forehead is a smaller target once you have already hit it
	_band = maxf(0.14, 0.26 - float(hits) * 0.04)


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 3.0)
	_shake = maxf(0.0, _shake - delta * 3.0)
	_msg_t = maxf(0.0, _msg_t - delta)
	_buffer = maxf(0.0, _buffer - delta)
	match phase:
		Phase.TELEGRAPH:
			_t += delta
			if _t >= _telegraph_time():
				phase = Phase.STRIKE
				_t = 0.0
				_strike = 0.0
				# A press made while he was winding up is not wasted: the spear
				# is live now, so it counts as the dodge. This is the whole
				# point of the buffer — the player pressed because they saw the
				# threat, a hair before the game was ready to accept it.
				if _buffer > 0.0:
					_buffer = 0.0
					press()
		Phase.STRIKE:
			_t += delta
			var speed := 1.0 / maxf(0.58, STRIKE_TIME - float(round_no - 1) * 0.04)
			_strike = minf(1.0, _strike + delta * speed)
			if _strike >= 1.0 and not _dodged:
				_take_hit()
		Phase.AIM:
			_t += delta
			_marker += delta * _marker_dir * MARKER_SPEED
			if _marker >= 1.0:
				_marker = 1.0
				_marker_dir = -1.0
			elif _marker <= -1.0:
				_marker = -1.0
				_marker_dir = 1.0
		Phase.RESOLVE:
			_t += delta
			if _t >= RESOLVE_TIME:
				_after_resolve_step()
		Phase.DONE:
			if not _emitted:
				_fall = minf(1.0, _fall + delta / FALL_TIME)
				if _fall >= 1.0:
					_emitted = true
					finished.emit()
	# The fight animates itself: without this the layer is drawn once and the
	# spear never travels, the marker never sweeps, and the whole thing looks
	# like a still picture with a working state machine behind it.
	_layer.queue_redraw()


func _after_resolve_step() -> void:
	if hits >= HITS_TO_WIN:
		_finish()
		return
	if _after_resolve == "round":
		_begin_round()
		return
	if stones <= 0:
		_resupply()
		return
	_begin_aim()


# ── input ────────────────────────────────────────────────────────────────
## Every way a player can mean "the one button", reduced to a bool. Kept as its
## own function because TWO engine paths call it (see below) and they must agree
## exactly.
func _is_press(event: InputEvent) -> bool:
	var pressed := false
	if event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		pressed = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return false
		if k.keycode == KEY_ESCAPE:
			return false
		# A dodge is a direction as much as a button: on a phone the thumb is
		# already on the stick, and the first thing a player tries when a spear
		# comes at them is to move.
		pressed = k.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_LEFT, KEY_RIGHT,
			KEY_A, KEY_D, KEY_UP, KEY_DOWN, KEY_W, KEY_S] \
			or event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") \
			or event.is_action_pressed("move_left") or event.is_action_pressed("move_right") \
			or event.is_action_pressed("move_up") or event.is_action_pressed("move_down")
	else:
		pressed = event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") \
			or event.is_action_pressed("move_left") or event.is_action_pressed("move_right") \
			or event.is_action_pressed("move_up") or event.is_action_pressed("move_down")
	return pressed


## The world path. `_input` runs before the GUI, so the fight hears a click even
## though its own full-screen layer would otherwise claim it.
func _input(event: InputEvent) -> void:
	_try_press(event)


## The GUI path, on the full-screen Control this scene draws on. If the layer
## has the pointer, the click is still a press — and TapGate is what stops the
## same physical click being counted twice by the two paths (BUG-016).
func _on_layer_gui(event: InputEvent) -> void:
	_try_press(event)


func _try_press(event: InputEvent) -> void:
	if phase == Phase.DONE or not _is_press(event):
		return
	if not TapGate.take():
		# The other engine path already had this physical press.
		get_viewport().set_input_as_handled()
		return
	get_viewport().set_input_as_handled()
	_press_at()


## A press, in whatever phase it arrives. Every one of them is answered: the two
## phases that cannot use a press queue it briefly and say so on screen, because
## a tap that produces nothing at all is indistinguishable from a broken game —
## and this was the reported "cant click anything to fight" (BUG-016).
func _press_at() -> void:
	match phase:
		Phase.TELEGRAPH, Phase.RESOLVE:
			_buffer = BUFFER_SECS
			_say(I18n.t({"en": "Not yet — he is winding up. Wait for the spear.",
				"zh": "还不行 —— 他在蓄力。等枪尖过来。"}), 1.0)
			AudioDirector.play_sfx("blip", -12.0)
		Phase.STRIKE:
			press()
		Phase.AIM:
			press()


## The one button. It means "step aside" while he is striking and "let go" while
## you are aiming — the same thumb, two different reads.
func press() -> void:
	if phase == Phase.STRIKE and not _dodged:
		if _strike < DODGE_WINDOW:
			_dodged = true
			_after_resolve = "aim"
			_shake = 0.7
			AudioDirector.play_sfx("dodge", -4.0)
			_say(I18n.t({"en": "You step aside. The spear bites the dust.",
				"zh": "你侧身让开。枪尖扎进土里。"}), 0.9)
			phase = Phase.RESOLVE
			_t = 0.0
		else:
			_take_hit()
		return
	if phase != Phase.AIM or _thrown:
		return
	_throw()


## Test seam: put the marker in the middle of the band.
func aim_perfect() -> void:
	_marker = 0.0


func _take_hit() -> void:
	nerve -= 1
	_shake = 1.0
	_flash = 0.8
	AudioDirector.play_sfx("hit", -3.0)
	if nerve <= 0:
		# No game over. He is a giant; you are a boy with a stone. Getting hit
		# costs you your footing, never the story.
		nerve = 1
		_say(I18n.t({"en": "The shaft throws you back. You get up. He is still shouting.",
			"zh": "枪杆把你掀翻。你爬起来。他还在骂。"}), 1.6)
	else:
		_say(I18n.t({"en": "The shaft catches you. Nerve left: %d",
			"zh": "枪杆扫到你。胆气还剩 %d。"}) % nerve, 1.4)
	_dodged = true          # the strike is spent either way
	_after_resolve = "aim"  # you get your throw while he recovers
	phase = Phase.RESOLVE
	_t = 0.0


func _throw() -> void:
	_thrown = true
	stones -= 1
	var landed := absf(_marker) <= _band
	if landed:
		hits += 1
		_flash = 1.0
		_shake = 0.9
		AudioDirector.play_sfx("hit", -2.0)
		_say(I18n.t({"en": "The stone finds his forehead. %d of %d.",
			"zh": "石子正中他的额头。%d／%d。"}) % [hits, HITS_TO_WIN], 1.2)
	else:
		AudioDirector.play_sfx("miss", -5.0)
		_say(I18n.t({"en": "Wide. The stone is gone into the dust.",
			"zh": "偏了。石子落在土里。"}), 1.1)
	# after a throw he winds up again — the fight has to stay a fight
	_after_resolve = "round"
	phase = Phase.RESOLVE
	_t = 0.0


func _resupply() -> void:
	stones = 2
	_say(I18n.t({"en": "Your pouch is empty. You take two more from the brook.",
		"zh": "袋子空了。你从溪里又摸了两块。"}), 1.6)
	_begin_round()


## The giant goes down, and stays down on screen while the chapter's last lines
## are spoken. `finished` fires when the fall has played, not when the stone
## lands, so nothing cuts away mid-beat.
func _finish() -> void:
	phase = Phase.DONE
	_t = 0.0
	_fall = 0.0
	_emitted = false
	_layer.queue_redraw()


func _say(text: String, secs: float) -> void:
	_msg = text
	_msg_t = secs


# ── drawing ──────────────────────────────────────────────────────────────
func _redraw() -> void:
	var vs: Vector2 = _layer.size
	if vs.x <= 0.0:
		return
	var font := ThemeDB.fallback_font
	var e := ScreenFit.edge(vs)
	var ground := vs.y * 0.66

	# dusk in the valley of Elah
	_layer.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.08, 0.10, 0.14, 0.90))
	_layer.draw_rect(Rect2(Vector2(0, ground), Vector2(vs.x, vs.y - ground)),
		Color(0.16, 0.15, 0.13, 0.95))
	_layer.draw_rect(Rect2(Vector2(0, ground), Vector2(vs.x, 1.5)),
		Color(0.30, 0.26, 0.20, 0.9))
	# the two ridges, so it does not read as a flat backdrop
	for i in range(9):
		var rw := vs.x / 9.0
		var h := 10.0 + 16.0 * absf(sin(float(i) * 2.1))
		_layer.draw_rect(Rect2(Vector2(i * rw, ground - h), Vector2(rw + 1, h)),
			Color(0.12, 0.13, 0.12, 0.85))

	var jitter := Vector2.ZERO
	if _shake > 0.0:
		jitter = Vector2(sin(_shake * 42.0) * 2.5 * _shake, 0.0)
	_gol.position = _gol_base + jitter
	_david.position = _david_base - jitter
	if _fall > 0.0:
		var drop := ease(_fall, 0.45)
		_gol.position += Vector2(-7.0 * drop, 11.0 * drop)
		_gol.modulate = Color(1.0, 1.0 - 0.28 * drop, 1.0 - 0.34 * drop, 1.0 - 0.12 * drop)
		for i in range(5):
			var dx := -18.0 + float(i) * 9.0
			_layer.draw_circle(
				Vector2(_gol_base.x + _gol.size.x * 0.5 + dx,
					_gol_base.y + _gol.size.y + 2.0),
				3.0 + 4.0 * drop, Color(0.55, 0.50, 0.40, 0.22 * drop))

	# your nerve, his forehead
	for i in range(NERVE):
		var c2 := Color(0.90, 0.45, 0.40, 0.95) if i < nerve else Color(1, 1, 1, 0.16)
		_layer.draw_circle(Vector2(e + 5 + i * 9, e + 6), 3.0, c2)
	for i in range(HITS_TO_WIN):
		var c := Color(0.97, 0.87, 0.65, 0.95) if i < hits else Color(1, 1, 1, 0.18)
		_layer.draw_circle(Vector2(vs.x - e - 5 - i * 9, e + 6), 3.0, c)

	var head := _head()
	match phase:
		Phase.TELEGRAPH:
			var pulse := 0.5 + 0.5 * sin(_t * 16.0)
			_layer.draw_circle(head + Vector2(-18, 10), 10.0 + pulse * 3.0,
				Color(0.92, 0.35, 0.30, 0.22 + 0.25 * pulse))
			_layer.draw_string(font, head + Vector2(-26, 4), "!",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.90, 0.75, 1.0))
		Phase.STRIKE:
			# the spear: red means move, and it comes from him to you
			var from := head + Vector2(-10, 26)
			var to := _david.position + Vector2(_david.size.x * 0.5, -6)
			var at := from.lerp(to, clampf(_strike / DODGE_WINDOW, 0.0, 1.0))
			_layer.draw_line(from, at, Color(0.20, 0.14, 0.10, 0.95), 5.0)
			_layer.draw_line(from, at, Color(0.92, 0.30, 0.24, 0.85), 2.0)
			var tip := PackedVector2Array()
			tip.append(at + Vector2(0, -5))
			tip.append(at + Vector2(-7, 0))
			tip.append(at + Vector2(0, 5))
			_layer.draw_colored_polygon(tip, Color(1, 0.88, 0.62, 0.95))
		Phase.AIM:
			_band_marker(head)

	if _flash > 0.0:
		_layer.draw_rect(Rect2(Vector2.ZERO, vs), Color(1, 0.95, 0.85, 0.28 * _flash))

	# ── the line that tells you which half of the fight you are in ──────
	var hint := ""
	var hint_col := Color(0.86, 0.86, 0.8, 0.95)
	match phase:
		Phase.TELEGRAPH:
			if round_no <= 1:
				hint = I18n.t({
					"en": "He lifts the spear. When the red tip comes, step aside — A, or a tap.",
					"zh": "他举起枪。枪尖过来时让开 —— 按 A，或点屏幕。"})
			else:
				hint = I18n.t({"en": "He is winding up…", "zh": "他举起枪，在蓄力……"})
			hint_col = Color(0.95, 0.72, 0.60, 0.95)
		Phase.STRIKE:
			hint = I18n.t({"en": "A / tap / any direction — STEP ASIDE",
				"zh": "按 A、点屏幕、或往两边推 —— 让开"})
			hint_col = Color(1.0, 0.55, 0.45, 1.0)
		Phase.AIM:
			hint = I18n.t({"en": "A / tap — RELEASE the stone",
				"zh": "按 A 或点屏幕 —— 放手"})
			hint_col = Color(0.98, 0.88, 0.62, 1.0)
	if hint != "":
		_layer.draw_multiline_string(font, Vector2(e + 4, vs.y - 22), hint,
			HORIZONTAL_ALIGNMENT_LEFT, vs.x - e * 2.0 - 8.0, 8, 2, hint_col)
	_layer.draw_string(font, Vector2(e + 4, vs.y - 8),
		I18n.t({"en": "stones %d" % stones, "zh": "石子 %d 块" % stones}),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.80, 0.82, 0.80, 0.9))
	if _msg != "" and _msg_t > 0.0:
		_layer.draw_multiline_string(font, Vector2(e + 4, e + 16), _msg,
			HORIZONTAL_ALIGNMENT_LEFT, vs.x - e * 2.0 - 8.0, 9, 2,
			Color(0.97, 0.87, 0.65, 0.95))

	# ── the button, on the screen that asks for it ─────────────────────
	# TouchControls hides the A button while a setpiece owns the screen, so the
	# hint "A / tap" was telling a phone player to press something that was not
	# there (BUG-017). Every scene that takes the screen draws its own.
	if phase != Phase.DONE:
		var a_c := Vector2(vs.x - 30.0, vs.y - 26.0)
		var live: bool = phase == Phase.STRIKE or phase == Phase.AIM
		var tint := Color(0.97, 0.87, 0.65, 0.40 if live else 0.16)
		var edge := Color(0.97, 0.87, 0.65, 0.85 if live else 0.35)
		if _buffer > 0.0:
			tint = Color(0.97, 0.87, 0.65, 0.55)
		_layer.draw_circle(a_c, 15.0, tint)
		_layer.draw_arc(a_c, 15.0, 0.0, TAU, 28, edge, 1.0)
		_layer.draw_string(font, a_c + Vector2(-4, 4), "A",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.85 if live else 0.45))


func _head() -> Vector2:
	return _gol_base + Vector2(_gol.size.x * 0.5, _gol.size.y * 0.30)


## The gold band on his forehead, and the marker that has to be inside it.
func _band_marker(head: Vector2) -> void:
	var half := clampf(_gol.size.x * 0.30, 18.0, 36.0)
	var band := half * (_band / 0.26)
	var cy := head.y
	_layer.draw_rect(Rect2(Vector2(head.x - half, cy - 8), Vector2(half * 2.0, 16)),
		Color(0.97, 0.87, 0.65, 0.18))
	_layer.draw_rect(Rect2(Vector2(head.x - band, cy - 8), Vector2(band * 2.0, 16)),
		Color(0.97, 0.87, 0.65, 0.42))
	_layer.draw_rect(Rect2(Vector2(head.x + _marker * half - 1.0, cy - 12), Vector2(2, 24)),
		Color(1, 0.97, 0.9, 1.0))
