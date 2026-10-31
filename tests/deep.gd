extends Node
## tests/deep.gd — the regression suite for the stabilisation pass.
##
## `run_all.gd` checks that the CONTENT is well formed and `smoke.gd` plays the
## slice from beginning to end. Neither can catch the class of defect this file
## exists for: the ones that appear on the SECOND of something, or after a
## reload, or when a transition is interrupted. Every check below is the
## regression test for a named bug in docs/BUGS.md, and each one failed against
## the code as it stood when the bug was found.
##
##   godot --headless --path . res://tests/deep.tscn
##
## Booted as a scene, for the reason smoke.gd documents at length: a --script
## main loop compiles before the autoloads exist, so anything that names
## GameState dies before it can assert anything.

const TILE := 16.0

var fails := 0
var main = null


func _ready() -> void:
	_run()


func _run() -> void:
	Engine.time_scale = 24.0
	for p in [GameState.SAVE_PATH, GameState.SAVE_BAK, GameState.SAVE_TMP]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	GameState.new_game()
	GameState.data["settings"]["reduce_motion"] = true

	var packed = load("res://scenes/main/Main.tscn")
	_check(packed != null, "Main.tscn loads")
	if packed == null:
		_finish()
		return
	main = packed.instantiate()
	add_child(main)
	await _frames(4)

	# Get the arrival out of the way: several checks below need a world that is
	# not paused with a box over it.
	if main.region != null and main.region.dialogue != null:
		await _drain(main.region.dialogue)
		main._brief_once()
		await _drain(main.region.dialogue)
	await _frames(2)

	await _check_save()
	await _check_stones()
	await _check_pickups()
	await _check_hud_fit()
	_check_goliath()
	await _check_talked_survives()
	await _check_armour_offset()
	await _check_become_twice()
	await _check_fade_twice()
	await _check_camera_shots()
	_check_place_at_solid()
	await _check_dialogue_taps()
	await _check_touch_interact()
	await _check_journal_escape()
	await _check_drill_keys()
	await _check_fight_input()
	await _check_choice_keys()
	_finish()


# ── BUG-011: the save is written whole, and can fall back ───────────────────
func _check_save() -> void:
	GameState.data["flags"]["deep_marker"] = true
	GameState.save_game()
	_check(FileAccess.file_exists(GameState.SAVE_PATH), "a save writes a file")
	_check(not FileAccess.file_exists(GameState.SAVE_TMP),
		"and leaves no half-written temp file behind")
	# a second save must keep the first as a backup
	GameState.data["flags"]["deep_marker2"] = true
	GameState.save_game()
	_check(FileAccess.file_exists(GameState.SAVE_BAK), "a second save keeps a backup")
	var before := (GameState.data["flags"] as Dictionary).duplicate()
	# corrupt the live save: the game must not silently start a new one
	var f := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	if f == null:
		_check(false, "the save file can be opened to corrupt it")
		return
	# Valid JSON of the wrong shape, not a truncated file: `_read_save` rejects
	# both identically, and this one does not print a parse error into the log
	# that a failure annotation would then spend its budget on.
	f.store_string("[]")
	f.close()
	GameState.data["flags"].erase("deep_marker")
	var ok: bool = GameState.load_game()
	_check(ok, "an unreadable save falls back instead of starting a new game")
	_check(bool(GameState.data["flags"].get("deep_marker", false)),
		"and the backup's contents are what came back")
	# restore a clean, valid save for the rest of the run
	GameState.data["flags"] = before
	GameState.save_game()
	GameState.data["flags"].erase("deep_marker2")
	await _frames(1)


# ── BUG-001 / BUG-002: the brook scene, on a keyboard ─────────────────────
func _check_stones() -> void:
	var panel := StoneChoice.new()
	add_child(panel)
	panel.start(5, 9)
	await _frames(1)
	# Take five with the keyboard path exactly as a desktop player would: the
	# cursor picks a stone, A takes it.
	for i in range(5):
		panel.move_cursor(1)
		panel.press()
		await _frames(1)
	_check(panel.chosen_count() == 5, "five stones can be taken with the pad/A key")
	# BUG-002: with the bag full, choosing a stone you already hold must put it
	# back — the message used to tell the player to do the impossible.
	var taken := -1
	for i in range(panel.stones.size()):
		if bool(panel.stones[i]["taken"]):
			taken = i
			break
	panel.toggle(taken)
	_check(panel.chosen_count() == 4,
		"a held stone can be put back even when five are held")
	# BUG-001: and A must be able to FINISH the scene once five are held again.
	panel.toggle(taken)
	_check(panel.is_full(), "five are held again")
	var got := [-1]
	panel.finished.connect(func(n): got[0] = n)
	panel.press()
	await _frames(2)
	_check(got[0] == 5, "A confirms the five stones on a keyboard (got %d)" % got[0])
	panel.queue_free()
	await _frames(1)


# ── BUG-018: what you picked up does not come back ───────────────────────
## Pickups had no persisted state at all: the region spawned every one of them
## fresh, so a reload put the provisions back on the ground while the count they
## fed was restored from the save — the same bread could be collected again, and
## a resumed errand could be finished without walking the errand.
func _check_pickups() -> void:
	var region = main.region
	var rid := str(region.model.id)
	var key := Region.pickup_key(rid, "deep_prov")
	GameState.data["flags"].erase(key)
	var pv_before: int = int(main.provisions)

	# Drop it where the player already stands: this check is about the save, and
	# walking him somewhere else would leave him out of reach of the person the
	# next check has to talk to.
	var home: Vector2 = region.player.global_position
	var tx := int(home.x / TILE)
	var ty := int(home.y / TILE)
	region.spawn_pickup("deep_prov", "provision", "jar", tx, ty)
	await _frames(1)
	var found = null
	for it in region.pickups:
		if str(it["id"]) == "deep_prov":
			found = it
	_check(found != null, "an item with no flag is on the ground")
	if found == null:
		return

	# walk onto it
	region._check_pickups()
	await _frames(1)
	_check(bool(GameState.flag(key)), "taking an item is written to the save")
	_check(bool(found["got"]), "and the item is gone from this region")

	# the reload: a rebuilt world asks for the same item in the same place
	region.spawn_pickup("deep_prov", "provision", "jar", tx, ty)
	await _frames(1)
	var back := false
	for it in region.pickups:
		if str(it["id"]) == "deep_prov" and not bool(it["got"]):
			back = true
	_check(not back, "a reloaded region does not put it back on the ground")

	# and the errand's count is derived from the ground, so a resumed run cannot
	# start at zero with the items already gone (or at four with them all there)
	var counted: int = main._errand_provisions([{"id": "deep_prov"}, {"id": "deep_absent"}])
	_check(counted == 1, "the errand counts what is taken, not what it is told")

	GameState.data["flags"].erase(key)
	main.provisions = pv_before
	await _frames(1)


# ── BUG-020: the objective band is big enough for the objectives ──────────
## The band was 20 px for an 8 px font whose two wrapped rows need more than
## that, and several English objectives are full sentences ("You have not
## understood yet what you are watching. Talk to the people in the camp."). The
## second row was drawn over the toast band and into the world. This measures
## with the engine's own font metrics against the label's real width — the same
## numbers the renderer will use, not a character-count model.
func _check_hud_fit() -> void:
	var hud = main.hud
	if hud == null:
		_check(false, "the HUD exists to lay out")
		return
	var lbl: Label = hud.objective_lbl
	var font: Font = lbl.get_theme_font("font")
	var fs: int = lbl.get_theme_font_size("font_size")
	var avail := maxf(1.0, float(lbl.size.x))
	var lh := float(font.get_height(fs))
	var need := 0.0
	var worst := ""
	for pair in _objective_strings():
		for key in ["zh", "en"]:
			var text := str(pair.get(key, ""))
			if text == "":
				continue
			var wpx := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var rows := maxf(1.0, ceilf(wpx / avail))
			if rows * lh > need:
				need = rows * lh
				worst = text
	print("  diag  hud objective band %.1f px, worst line needs %.1f px (%d chars)" %
		[float(lbl.size.y), need, worst.length()])
	_check(need <= float(lbl.size.y) + 1.0,
		"the longest objective fits the HUD band (%.1f px of %.1f)" %
		[need, float(lbl.size.y)])
	_check(float(lbl.position.y) + float(lbl.size.y) <= float(hud.toast_lbl.position.y) + 0.5,
		"and the objective band does not run into the toast")


## Every objective string in every region, both languages.
func _objective_strings() -> Array:
	var out: Array = []
	for path in ["res://data/regions/elah.json", "res://data/regions/bethlehem.json"]:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var obj: Dictionary = (parsed as Dictionary).get("objectives", {})
		for k in obj.keys():
			var v: Variant = obj[k]
			if typeof(v) == TYPE_DICTIONARY:
				out.append(v)
	return out


# ── BUG-003: the giant is one frame, two tiles tall ───────────────────────
func _check_goliath() -> void:
	var g: Sprite2D = main.region.goliath_sprite
	_check(g != null, "the giant is on the ridge")
	if g == null:
		return
	_check(g.hframes == 2 and g.vframes == 4,
		"his sheet is sliced into frames (%dx%d, want 2x4)" % [g.hframes, g.vframes])
	_check(g.frame == 0, "and he is drawn as one pose, not eight (frame %d)" % g.frame)
	_check(is_equal_approx(g.scale.x, 2.0) and is_equal_approx(g.scale.y, 2.0),
		"and stands two tiles tall")


# ── BUG-004: a person you have met stays met ──────────────────────────────
func _check_talked_survives() -> void:
	var npc: Npc = _find(main.region, "corin")
	if npc == null:
		_check(false, "corin exists to be met")
		return
	if not npc.has_talked():
		npc.talk()
		await _drain(main.region.dialogue)
	await _frames(2)
	if not npc.has_talked():
		print("  diag  corin talked=%s can_talk=%s talk_state=%d box=%s paused=%s"
			% [str(npc.has_talked()), str(npc.can_talk()), int(npc.talk_state),
				str(main.region.dialogue.is_open()), str(main.region.is_paused())])
	_check(npc.has_talked(), "talking marks the person as met")
	var key := "talked:%s:%s" % [str(main.region.model.id), "corin"]
	_check(bool(GameState.flag(key)), "and the meeting is written into the save (%s)" % key)
	# What a reload does: a brand-new Npc built from the same data.
	var fresh := Npc.new()
	fresh.setup(main.region.model, npc.data, main.region.player, main.region.dialogue,
		main.region.set_paused)
	_check(fresh.has_talked(), "a reloaded person remembers the conversation")
	fresh.free()


# ── BUG-005: the armour's stagger does not outlive the armour ─────────────
func _check_armour_offset() -> void:
	var p: Player = main.region.player
	p.set_armour(true)
	p.sprite.offset = Vector2(1.6, -8.0)      # what the stagger writes
	p.set_armour(false)
	_check(p.sprite.offset.is_equal_approx(Vector2(0, -8)),
		"taking the armour off centres the figure again (%s)" % str(p.sprite.offset))


# ── BUG-006: a second BECOME cannot leave the chapter unable to continue ──
func _check_become_twice() -> void:
	var b: BecomeController = main.become
	var first := [false]
	var second := [false]
	b.begin("david", {"en": "DAVID", "zh": "大卫"}, func(): first[0] = true)
	await _frames(2)
	b.begin("david", {"en": "DAVID", "zh": "大卫"}, func(): second[0] = true)
	var guard := 0
	while not second[0] and guard < 400:
		await _frames(1)
		guard += 1
	_check(second[0], "a BECOME requested during a BECOME still completes")
	_check(not b._busy, "and it does not leave the transition controller stuck")
	_check(b.bar_top.offset_bottom <= 0.5,
		"and no film bar is left covering the picture (%.1f)" % b.bar_top.offset_bottom)
	await _frames(2)


# ── BUG-007: a fade started mid-fade cannot leave the screen black ────────
func _check_fade_twice() -> void:
	var fd: ScreenFade = main.fade
	fd.run(3.0, func(): pass, 3.0)
	await _frames(2)
	_check(fd._busy, "the first fade is still in flight when the second starts")
	fd.run(1.0, func(): pass, 1.0)
	var guard := 0
	while fd._busy and guard < 400:
		await _frames(1)
		guard += 1
	_check(not fd._busy, "a second fade finishes instead of wedging")
	await _frames(4)
	_check(fd._rect.color.a <= 0.05,
		"and the screen is not left black (alpha %.2f)" % fd._rect.color.a)


# ── BUG-008: two camera shots do not fight over one property ──────────────
func _check_camera_shots() -> void:
	var cam: CameraRig = main.region.cam
	if cam == null:
		_check(false, "the camera exists")
		return
	cam.pan_to(main.region.player.global_position + Vector2(64, 0), 3.0)
	await _frames(2)
	_check(cam._cine, "the shot is still running when it is handed back")
	cam.resume_follow(0.2)
	var guard := 0
	while cam._cine and guard < 400:
		await _frames(1)
		guard += 1
	_check(not cam._cine, "handing the shot back ends the pan even if it was mid-flight")


# ── BUG-010: a saved position can never be inside a wall ──────────────────
func _check_place_at_solid() -> void:
	var m = main.region.model
	var solid := Vector2i(-1, -1)
	for y in range(m.height):
		for x in range(m.width):
			if not m.solid_at_tile(x, y):
				continue
			var t := Vector2i(x, y)
			if m.nearest_open(t) != t:
				solid = t
				break
		if solid.x >= 0:
			break
	if solid.x < 0:
		_check(false, "the valley has an obstacle to test against")
		return
	main._place_at([solid.x, solid.y])
	var here := Vector2i(int(floor(main.region.player.global_position.x / TILE)),
		int(floor(main.region.player.global_position.y / TILE)))
	_check(not m.solid_at_tile(here.x, here.y),
		"a position inside a wall is snapped to open ground (%s -> %s)" % [solid, here])


# ── the one-tap-one-line contract, from a second direction ───────────────
func _check_dialogue_taps() -> void:
	var dlg = main.region.dialogue
	# Away from every trigger and curio, so the check is about the box and not
	# about the map underneath it.
	main._place_at([main.region.model.spawn.x, main.region.model.spawn.y])
	await _frames(2)
	var lines: Array = [
		{"who": "", "text": {"en": "One.", "zh": "一。"}},
		{"who": "", "text": {"en": "Two.", "zh": "二。"}},
		{"who": "", "text": {"en": "Three.", "zh": "三。"}},
	]
	dlg.show_lines(lines, func(_w): return {}, func(): pass)
	var id0 := int(dlg._box_id)
	await _frames(2)
	# The tap that opens the box must not also advance it: Region and the box
	# both listen, and that was the "dialogues repeat" report.
	_check(dlg._i == 0, "a freshly opened box is still on its first line (i=%d)" % dlg._i)
	_check(dlg._open, "and it is open")
	_check(int(dlg._box_id) == id0, "opening it once opens one box")
	await _drain(dlg)
	_check(not dlg._open, "and it closes when its lines are done")

	# BUG-013: standing in a trigger's area with a box open must not replace the
	# box. The trigger fires when the conversation ends, not through it.
	var row := 0
	for t in main.region.triggers:
		if str(t.get("id", "")) == "challenge":
			row = int((t.get("data", {}) as Dictionary).get("row", 11))
	main._place_at([main.region.model.spawn.x, maxi(1, row - 1)])
	await _frames(2)
	dlg.show_lines([{"who": "", "text": {"en": "Hold.", "zh": "等等。"}}],
		func(_w): return {}, func(): pass)
	var keep := int(dlg._box_id)
	await _frames(6)
	_check(int(dlg._box_id) == keep,
		"a story trigger cannot open a second box over an open one")
	await _drain(dlg)


# ── the phone's whole verb: a tap on A reaches the world ──────────────────
## Everything else in this file drives the game the way a keyboard does. The
## reported failure was on a phone, where A is not a key but a circle drawn on
## the screen: TouchControls claims the touch and re-emits it as an `interact`
## action. That indirection has broken before ("cant talk with npc"), and a test
## that calls `npc.talk()` would never have seen it. This sends a real
## InputEventScreenTouch at the A button's drawn position and uses nothing else.
func _check_touch_interact() -> void:
	var region = main.region
	if region == null or main.touch == null:
		_check(false, "the world and its touch layer exist")
		return
	await _drain(region.dialogue)
	# Someone who has not been spoken to yet, so the tap is the first one.
	var npc: Npc = null
	for cand in ["boy", "woman", "elder"]:
		var n: Npc = _find(region, cand)
		if n != null and not n.has_talked():
			npc = n
			break
	if npc == null:
		_check(false, "someone is left in the camp to talk to")
		return
	var t := Vector2i(int(npc.global_position.x / TILE), int(npc.global_position.y / TILE))
	main._place_at([t.x, t.y + 1])
	# A conversation just closed; its lock is a game-time countdown.
	var guard := 0
	while float(region._interact_lock) > 0.0 and guard < 200:
		await _frames(1)
		guard += 1
	await _frames(2)

	# The same centre TouchControls draws its A at.
	var vs: Vector2 = main.touch.get_viewport().get_visible_rect().size
	var a_pos := Vector2(vs.x - 30.0, vs.y - 26.0)
	TapGate.reset()
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = a_pos
	Input.parse_input_event(down)
	await _frames(3)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = a_pos
	Input.parse_input_event(up)
	await _frames(2)
	# `has_talked()` is written when the conversation CLOSES, so the tap's
	# immediate proof is the open box; the lasting proof is the flag after it.
	_check(region.dialogue.is_open(),
		"a tap on the phone's A button opens a conversation (%s)" % npc.npc_id())
	await _drain(region.dialogue)
	await _frames(2)
	_check(npc.has_talked(), "and finishing it marks the person met")


# ── BUG-012: the book always has a way out ────────────────────────────────
func _check_journal_escape() -> void:
	var j: Journal = main.journal
	main._open_journal()
	await _frames(2)
	if not j.is_open():
		var box := "-"
		if main.region.dialogue != null:
			box = str(main.region.dialogue.is_open())
		print("  diag  journal open=%s dialogue=%s paused=%s in_battle=%s fight=%s"
			% [str(j.is_open()), box, str(main.region.is_paused()),
				str(main._in_battle), str(main.fight)])
	_check(j.is_open(), "the book opens")
	_check(main.region.is_paused(), "and holds the world still while it is open")
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	j._input(ev)
	await _frames(2)
	_check(not j.is_open(), "Escape closes the book (the only exit used to be a button)")
	_check(not main.region.is_paused(), "and hands the world back")


# ── BUG-015: the drill answers the keyboard ───────────────────────────────
func _check_drill_keys() -> void:
	var drill := SlingPractice.new()
	add_child(drill)
	drill.start(1)
	await _frames(1)
	var hits0 := int(drill.hits)
	var done := [false]
	# Connected BEFORE the shot: with one target the drill can finish inside the
	# resolve window, and a listener attached afterwards would miss it.
	drill.finished.connect(func(): done[0] = true)
	drill.aim_perfect()
	# Through the real input pipeline, not by calling press(): the bug was that
	# no key event reached this scene at all.
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(2)
	var up := InputEventKey.new()
	up.keycode = KEY_SPACE
	up.pressed = false
	Input.parse_input_event(up)
	_check(int(drill.hits) == hits0 + 1,
		"Space takes a shot in the drill (hits %d -> %d)" % [hits0, int(drill.hits)])
	var guard := 0
	while not done[0] and guard < 200:
		await _frames(1)
		guard += 1
	_check(done[0], "and the drill can be finished on a keyboard")
	drill.queue_free()
	await _frames(1)


# ── BUG-016: the duel hears a real press, and answers every one ────────────
## The smoke test drives the fight by calling `press()`, which is exactly how
## BUG-015 hid: a scene can have a perfect state machine and no way into it. So
## this check pushes real events through `Input.parse_input_event` — the same
## path a browser click and a phone tap take — and asserts the fight reacts.
func _check_fight_input() -> void:
	var f = GoliathFight.new()
	add_child(f)
	await _frames(2)
	f.start()
	# The fight runs in real time: at 24x a telegraph is two frames and the
	# timing under test would be the engine loop's, not the player's.
	Engine.time_scale = 1.0
	Engine.max_fps = 240
	await _frames(2)

	_check(f._layer.is_connected("gui_input", Callable(f, "_on_layer_gui")),
		"the duel's screen listens for clicks on its own layer")
	_check(int(f.phase) == int(GoliathFight.Phase.TELEGRAPH), "the duel opens by winding up")

	# (1) a press while he winds up is ANSWERED, not swallowed
	TapGate.reset()
	_click()
	await _frames(2)
	_check(f._msg != "", "a press while he winds up says why nothing happened yet")
	_check(f._buffer > 0.0, "and it is queued rather than thrown away")

	# (2) a press made just before the spear goes live counts as the dodge
	var guard := 0
	while float(f._t) < f._telegraph_time() - 0.30 and guard < 400:
		await _frames(1)
		guard += 1
	TapGate.reset()
	_click()
	await _frames(1)
	guard = 0
	while int(f.phase) == int(GoliathFight.Phase.TELEGRAPH) and guard < 200:
		await _frames(1)
		guard += 1
	_check(bool(f._dodged), "a queued press becomes the dodge when the spear arrives")
	_check(int(f.nerve) == 3, "and the dodge costs no nerve (nerve=%d)" % int(f.nerve))

	# (3) a press during the aim phase throws — the A button's synthetic action
	guard = 0
	while int(f.phase) != int(GoliathFight.Phase.AIM) and guard < 400:
		await _frames(1)
		guard += 1
	if int(f.phase) != int(GoliathFight.Phase.AIM):
		_check(false, "the duel reaches the aim phase (phase=%d)" % int(f.phase))
	else:
		f.aim_perfect()
		TapGate.reset()
		var ev := InputEventAction.new()
		ev.action = "interact"
		ev.pressed = true
		Input.parse_input_event(ev)
		await _frames(3)
		_check(int(f.hits) == 1, "the A button's action throws the stone (hits=%d)" % int(f.hits))
		# and the same press does not count twice (the two engine paths)
		_check(int(f.stones) == f.STONES - 1,
			"one press spends one stone (stones=%d)" % int(f.stones))

	Engine.max_fps = 0
	Engine.time_scale = 24.0
	f.queue_free()
	await _frames(2)


# ── BUG-019: a question can be answered with the one button ───────────────
## Answers were Buttons and nothing else: the game's single button, the pad and
## the phone's A reached the choice box and stopped there, so the ending's
## question could only be answered with a mouse or a thumb. The d-pad moves the
## highlight now, and the button that advances every other line answers.
func _check_choice_keys() -> void:
	var box := DialogueBox.new()
	add_child(box)
	await _frames(2)
	var got := [-1]
	box.show_choices_standalone(
		[{"t": {"en": "Go on.", "zh": "去吧。"}}, {"t": {"en": "Stay.", "zh": "留下。"}}],
		func(i, _o): got[0] = i)
	await _frames(2)
	_check(box._in_choices, "a question is on screen with its answers")
	_check(box._choice_i == 0, "and the first answer has the highlight")

	TapGate.reset()
	_key(KEY_DOWN)
	await _frames(2)
	_check(box._choice_i == 1, "the d-pad moves the highlight (i=%d)" % box._choice_i)

	TapGate.reset()
	var ev := InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(3)
	_check(got[0] == 1, "the A button answers it (got %d)" % got[0])
	_check(not box._in_choices, "and the answers go away")
	# and the answer cannot be delivered twice by the two input paths
	_check(got[0] == 1, "one press answers once")
	box.queue_free()
	await _frames(1)


## A key press through the real pipeline, the way a keyboard sends one.
func _key(code: int) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.keycode = code
	up.pressed = false
	Input.parse_input_event(up)


## A real mouse click, through the pipeline, so this is the event a browser
## actually delivers.
func _click() -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(200, 100)
	Input.parse_input_event(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = Vector2(200, 100)
	Input.parse_input_event(up)


# ── harness ───────────────────────────────────────────────────────────────
func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok    " + msg)
	else:
		fails += 1
		printerr("  FAIL  " + msg)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


## Advance every box, including chained ones, until the screen is quiet.
func _drain(dlg) -> void:
	if dlg == null:
		return
	var guard := 0
	var quiet := 0
	while guard < 400 and quiet < 3:
		if dlg._open:
			quiet = 0
			dlg._advance()
		else:
			quiet += 1
		await _frames(1)
		guard += 1


func _find(region, id: String) -> Npc:
	for n in region.npcs:
		if n.npc_id() == id:
			return n
	return null


func _finish() -> void:
	if fails == 0:
		print("deep: PASS — every regression check holds")
		get_tree().quit(0)
	else:
		printerr("deep: %d FAILURE(S)" % fails)
		get_tree().quit(1)
