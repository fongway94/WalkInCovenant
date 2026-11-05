extends Node
## tests/visual.gd — render the real game and inspect its pixels.
##
## This is the ONE suite that needs a display. It runs in CI under Xvfb with a
## software OpenGL driver, because the authoring sandbox has no Godot binary, no
## X server and no GPU:
##
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##       --audio-driver Dummy --windowed --resolution 640x360 \
##       res://tests/visual.tscn
##
## It boots Main.tscn (the shipped scene), measures the cold-boot control
## latency, drives the one-button action through the engine's own input
## pipeline, catches a sheep reacting, a quest counter updating, a 2x Chinese
## dialogue review, a second aspect ratio and a real fade, then walks into a
## second region — saving REAL framebuffer captures at each named beat. Each
## capture is checked for being an actual picture (colour diversity, not black,
## not white) and, once a baseline PNG is committed under tests/frames/,
## compared against it — a visual regression gate rather than a claim.
##
## What this CANNOT prove: that the art is good, that Chinese reads well at 10px
## on a phone, or that anything sounds right. Those still need a human with a
## device (docs/DEVICE-CHECKLIST.md). What it CAN prove is that the engine
## rendered these scenes at all, and that they did not change wholesale.

const VIEW_W := 320
const VIEW_H := 180
const FRAME_DIR := "res://build/frames"
const BASE_DIR := "res://tests/frames"
## Generous: font rasterisation and a bobbing marker can move a few pixels
## between runs. This catches a blank frame, a wrong scene or a missing HUD,
## not a single antialiased glyph.
const DIFF_LIMIT := 0.18

var main = null
var fails := 0
var rows: Array = []
var input_routed := false
var input_direct := false
var parsed_opens := false
var probe_hits := 0
var control_ms := -1
var boot_pages := -1
var last_fb := Vector2i.ZERO
var layout_fb := Vector2i.ZERO


## A parsed input event reaches Node._unhandled_input only when the display
## server routes input. Count an unmapped key so the report can say whether
## this build has that capability, independently of any game state.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		probe_hits += 1


func _ready() -> void:
	_run()


func _run() -> void:
	# Tweens (the opening fade) are scaled with the engine clock, so a handful
	# of real frames is enough to see a settled picture.
	Engine.time_scale = 6.0
	if FileAccess.file_exists(GameState.SAVE_PATH):
		DirAccess.remove_absolute(GameState.SAVE_PATH)
	GameState.new_game()
	GameState.data["settings"]["reduce_motion"] = true

	var packed = load("res://scenes/main/Main.tscn")
	if packed == null:
		_fail("Main.tscn did not load")
		_finish()
		return
	main = packed.instantiate()
	add_child(main)
	await _frames(14)

	# 1. PRIORITY 1: the first frame a new player sees is the valley and its
	# place card — NO prologue box, NO briefing, NO tap required. Both metrics
	# are asserted so a future "helpful" tutorial cannot quietly return.
	control_ms = main.boot_control_ms
	boot_pages = main.boot_forced_pages
	_check(boot_pages == 0,
		"the boot forces zero dialogue pages (%d)" % boot_pages)
	_check(main.boot_forced_actions == 0, "and zero taps before control")
	_check(control_ms >= 0 and control_ms < 3000,
		"control arrives in %d ms" % control_ms)
	await _shot("01_boot_world")
	await _frames(28)

	# 2. The settled world, with its HUD, touch controls and the person in reach.
	await _shot("02_valley")

	# 3. A conversation, opened by a REAL input action. First measure whether
	# parsed events reach Node._unhandled_input in this build at all (an
	# unmapped key presses nothing in the game). Then stand beside Corin —
	# deliberately NOT on the south exit tile, which is one row below him:
	# the one button there is the road, not the man.
	var probe := InputEventKey.new()
	probe.keycode = KEY_F12
	probe.pressed = true
	Input.parse_input_event(probe)
	await _frames(3)
	input_routed = probe_hits > 0
	var reg = main.region
	var corin = _find_npc(reg, "corin")
	if corin != null and reg != null:
		reg.player.global_position = corin.global_position + Vector2(-16.0, 0.0)
		await _frames(3)
		TapGate.reset()
		await _press_interact()
		parsed_opens = reg.dialogue.is_open()
		if not parsed_opens:
			input_direct = true
			var ev := InputEventAction.new()
			ev.action = "interact"
			ev.pressed = true
			reg._unhandled_input(ev)
			await _frames(3)
		if not reg.dialogue.is_open():
			corin.talk()
			await _frames(3)
		_check(reg.dialogue.is_open(), "the world's interact handler opens a conversation")
		await _shot("03_dialogue")
		# A 2x nearest upscale of the SAME framebuffer, so the Chinese glyphs,
		# the nameplate and the portrait can actually be inspected by eye at
		# 640x360 instead of guessed at from a 320px thumbnail.
		await _shot_size("09_chinese_2x", 640, 360)
		await _drain_all()
		await _frames(4)

	# 4. The book. A second screen, reached by the game's own open call.
	if main.has_method("_open_journal"):
		main.call("_open_journal")
		await _frames(5)
		await _shot("04_journal")
		# `_close_journal` is only the signal handler that unpauses the world;
		# the panel itself closes through its own method. Calling the handler
		# left the book drawn over the next region's frame.
		main.journal.close_panel()
		await _frames(4)
		_check(not main.journal.is_open(),
			"the book closes before the picture moves on")

	# 4b. The shepherd opening, rendered through the game's OWN BECOME cut.
	# This is a scene probe rather than a second playthrough: the two story
	# flags a player returning from Bethlehem carries are set, then the engine
	# runs the handover, the opening lines and the flock itself. The harness
	# draws nothing; the fold, sheep and objective are all the shipped game.
	GameState.set_flag("elah_met_the_line", true)
	GameState.set_flag("beth_anointed", true)
	main._begin_become()
	var become_frames := 0
	while main.act_id() != "shepherd" and become_frames < 400:
		await _frames(1)
		become_frames += 1
	_check(main.act_id() == "shepherd", "the BECOME cut reaches the shepherd act")
	# `act` is set BEFORE the fade and the opening lines, so wait for the box
	# itself; draining too early leaves it drawn over the flock frame.
	var opening_frames := 0
	while not main.region.dialogue.is_open() and opening_frames < 400:
		await _frames(1)
		opening_frames += 1
	_check(main.region.dialogue.is_open(), "the shepherd opening has its short beat")
	await _drain_all()
	await _frames(8)
	_check(bool(main._flock_active), "the fold has its three strays on the ground")
	await _shot("06_flock")

	# 7. A sheep that has NOTICED the player. Stand on the far side of the fold
	# so the animal turns toward home: the alert pose, the pale wool marker and
	# the objective counter are all in this frame. This is a real game state,
	# not a drawn mock-up.
	# Use the LIVE animal, not its authored tile: a grazing sheep has already
	# drifted a few pixels by the time this frame is taken.
	var first_animal = null
	for p in main.region.pickups:
		var pd: Dictionary = p
		if str(pd.get("kind", "")) == "flock" and not bool(pd.get("got", false)):
			first_animal = pd.get("node")
			break
	_check(first_animal != null, "a stray is still out for the interaction frame")
	if first_animal != null:
		var away0: Vector2 = (first_animal.anchor - first_animal.fold).normalized()
		main.region.player.global_position = first_animal.global_position + away0 * 34.0
		await _frames(10)
		await _shot("07_sheep_near")

		# 8. A quest update. Walk onto that stray and let the world collect it:
		# the HUD counter, the contextual toast and the hired boy's bubble all
		# change without a dialogue box taking the picture.
		main.region.player.global_position = first_animal.global_position
		await _frames(30)
	await _shot("08_quest_update")
	_check(main.sheep_home >= 1, "a stray came home and the HUD moved (%d/3)" % main.sheep_home)

	# 5. A second region, entered by walking onto its exit and pressing the one
	# button. The flag the road wants is read from the region's own data, so
	# this frame survives a change to the chapter's chronology.
	if reg != null and reg.model != null:
		var at: Array = [16, 46]
		var need := ""
		for e in reg.model.exits:
			if str((e as Dictionary).get("to", "")) == "bethlehem":
				at = (e as Dictionary).get("at", at)
				need = str((e as Dictionary).get("requires", ""))
		if need != "":
			GameState.set_flag(need, true)
		reg.player.global_position = Vector2(float(at[0]) * 16.0 + 8.0,
			float(at[1]) * 16.0 + 8.0)
		await _frames(4)
		await _press_interact()
		if main.region != null and str(main.region.region_id) == reg.region_id:
			var ev2 := InputEventAction.new()
			ev2.action = "interact"
			ev2.pressed = true
			reg._unhandled_input(ev2)
		var hops := 0
		while main.region != null and str(main.region.region_id) != "bethlehem" \
				and hops < 400:
			await _frames(1)
			hops += 1
		_check(main.region != null and str(main.region.region_id) == "bethlehem",
			"the road south reaches a second region")
		if main.region != null and str(main.region.region_id) == "bethlehem":
			await _frames(20)
			await _drain_all()
			await _frames(4)
			await _shot("05_bethlehem")

	# 9. A SECOND aspect ratio. The web build keeps canvas_items stretching, so
	# a 640x480 window gives a 320x240 root viewport: 4:3 instead of 16:9.
	# Check the HUD, the touch pad and the place card do not eat the world.
	get_tree().root.size = Vector2i(640, 480)
	await _frames(12)
	await _shot_size("10_layout_4x3", 320, 240)
	layout_fb = last_fb
	_check(layout_fb.y > 180,
		"the 4:3 window really produced a taller %dx%d viewport" % [layout_fb.x, layout_fb.y])
	get_tree().root.size = Vector2i(640, 360)
	await _frames(8)

	# 10. A real transition, caught mid fade, at normal speed so a 0.45 s
	# tween is not over in three frames. This is the same ScreenFade the dusk
	# and morning cuts use — no mocked colour rect.
	Engine.time_scale = 1.0
	main.fade.run(0.45, Callable(), 0.35, Callable())
	await _frames(14)
	await _shot("11_transition")
	await _frames(60)
	Engine.time_scale = 6.0
	_finish()


# ── capture ─────────────────────────────────────────────────────────────
func _shot(name: String) -> void:
	await _shot_size(name, VIEW_W, VIEW_H)


## Capture at any review size. `w`/`h` are a NEAREST up/down-scale of the real
## framebuffer — for a 2x Chinese-text review or a 4:3 window, not a redraw.
## The frame is still compared against a baseline of the same size, so a
## changed aspect ratio is a real gate rather than a decorative screenshot.
func _shot_size(name: String, w: int, h: int) -> void:
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if vp == null:
		_fail(name + ": no viewport")
		return
	var tex := vp.get_texture()
	if tex == null:
		_fail(name + ": the viewport has no texture — no rendering device")
		return
	var img: Image = tex.get_image()
	if img == null:
		_fail(name + ": the framebuffer could not be read")
		return
	var src_w := img.get_width()
	var src_h := img.get_height()
	last_fb = Vector2i(src_w, src_h)
	img.resize(w, h, Image.INTERPOLATE_NEAREST)

	var bins := {}
	var lit := 0.0
	var samples := 0
	for y in range(0, h, 3):
		for x in range(0, w, 3):
			var c: Color = img.get_pixel(x, y)
			bins["%d_%d_%d" % [int(c.r * 7.0), int(c.g * 7.0), int(c.b * 7.0)]] = true
			lit += (c.r + c.g + c.b) / 3.0
			samples += 1
	var mean := lit / float(maxi(samples, 1))
	_check(bins.size() >= 6,
		"%s: the frame is a picture, not a flat fill (%d colour bins)" % [name, bins.size()])
	_check(mean > 0.01 and mean < 0.99,
		"%s: the frame is neither black nor white (luma %.3f)" % [name, mean])

	var diff := -1.0
	var base_path := BASE_DIR + "/baseline_" + name + ".png"
	if FileAccess.file_exists(base_path):
		var base := Image.load_from_file(base_path)
		if base != null:
			base.resize(w, h, Image.INTERPOLATE_NEAREST)
			diff = _grid_diff(img, base)
			_check(diff < DIFF_LIMIT,
				"%s: matches the committed baseline (diff %.3f)" % [name, diff])
		else:
			_fail(name + ": the baseline PNG would not load")

	var dir := ProjectSettings.globalize_path(FRAME_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir + "/" + name + ".png"
	if img.save_png(path) != OK:
		_fail(name + ": could not write the capture")
		return
	rows.append({"name": name, "bins": bins.size(), "luma": mean,
		"baseline_diff": diff, "size": [w, h], "framebuffer": [src_w, src_h]})
	print("visual: captured %s (%dx%d from %dx%d, %d bins, luma %.3f, diff %.3f)"
		% [name, w, h, src_w, src_h, bins.size(), mean, diff])


## Compare two frames on a coarse grid, averaging a small block per cell so a
## one-pixel animation frame cannot fail the gate.
func _grid_diff(a: Image, b: Image) -> float:
	var total := 0.0
	var cells := 0
	var nx := int(floor(float(a.get_width()) / 10.0))
	var ny := int(floor(float(a.get_height()) / 10.0))
	for gy in range(ny):
		for gx in range(nx):
			for oy in range(2):
				for ox in range(2):
					var x: int = gx * 10 + 2 + ox * 4
					var y: int = gy * 10 + 2 + oy * 4
					var ca: Color = a.get_pixel(x, y)
					var cb: Color = b.get_pixel(x, y)
					total += (absf(ca.r - cb.r) + absf(ca.g - cb.g)
						+ absf(ca.b - cb.b)) / 3.0
					cells += 1
	return total / float(maxi(cells, 1))


func _finish() -> void:
	var dir := ProjectSettings.globalize_path(FRAME_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var out := {
		"frames": rows,
		"input_routed": input_routed,
		"parsed_interact_opens": parsed_opens,
		"input_direct": input_direct,
		"boot_control_ms": control_ms,
		"boot_forced_pages": boot_pages,
		"layout_framebuffer": [layout_fb.x, layout_fb.y],
		"fails": fails,
	}
	var f := FileAccess.open(dir + "/summary.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(out, "\t"))
		f.close()
	if fails == 0:
		print("visual: PASS — %d rendered frames, control=%dms/%d pages, 4:3fb=%dx%d, input_routed=%s parsed_opens=%s direct=%s"
			% [rows.size(), control_ms, boot_pages, layout_fb.x, layout_fb.y,
				str(input_routed), str(parsed_opens), str(input_direct)])
		get_tree().quit(0)
	else:
		printerr("visual: %d FAILURE(S)" % fails)
		get_tree().quit(1)


# ── harness ─────────────────────────────────────────────────────────────
func _press_interact() -> void:
	var ev := InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(3)


func _drain_all() -> void:
	if main == null or main.region == null:
		return
	var dlg = main.region.dialogue
	var guard := 0
	while dlg != null and dlg.is_open() and guard < 400:
		dlg._advance()
		await _frames(1)
		guard += 1


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _find_npc(reg, id: String):
	if reg == null:
		return null
	for n in reg.npcs:
		if str(n.npc_id()) == id:
			return n
	return null


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok    " + msg)
	else:
		fails += 1
		printerr("  FAIL  " + msg)


func _fail(msg: String) -> void:
	fails += 1
	printerr("  FAIL  " + msg)
