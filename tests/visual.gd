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
## It boots Main.tscn (the shipped scene), drives the one-button action through
## the engine's own input pipeline, walks into a second region, and saves REAL
## framebuffer captures at named beats. Each capture is checked for being an
## actual picture (colour diversity, not black, not white) and, once a baseline
## PNG is committed under tests/frames/, compared against it — a visual
## regression gate rather than a claim.
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
	await _frames(40)

	# 1. The first frame a new player sees: the prologue box over the valley.
	await _shot("01_boot_dialogue")
	await _drain_all()
	await _frames(6)

	# 2. The world, with its HUD and touch controls, after the words are gone.
	await _shot("02_valley")

	# 3. A conversation, opened by a REAL input action. On a headless engine
	# Input.parse_input_event does not reach Node._unhandled_input, so the
	# fallback calls the same handler directly and the report says which path
	# worked. That distinction is itself a capability check.
	var reg = main.region
	var corin = _find_npc(reg, "corin")
	if corin != null and reg != null:
		reg.player.global_position = corin.global_position + Vector2(0, 15)
		await _frames(3)
		await _press_interact()
		if not reg.dialogue.is_open():
			input_direct = true
			var ev := InputEventAction.new()
			ev.action = "interact"
			ev.pressed = true
			reg._unhandled_input(ev)
			await _frames(3)
		else:
			input_routed = true
		_check(reg.dialogue.is_open(), "an interact action opens a conversation")
		await _shot("03_dialogue")
		await _drain_all()
		await _frames(4)

	# 4. The book. A second screen, reached by the game's own open call.
	if main.has_method("_open_journal"):
		main.call("_open_journal")
		await _frames(5)
		await _shot("04_journal")
		main.call("_close_journal")
		await _frames(4)

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

	_finish()


# ── capture ─────────────────────────────────────────────────────────────
func _shot(name: String) -> void:
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
	img.resize(VIEW_W, VIEW_H, Image.INTERPOLATE_NEAREST)

	var bins := {}
	var lit := 0.0
	var samples := 0
	for y in range(0, VIEW_H, 3):
		for x in range(0, VIEW_W, 3):
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
			base.resize(VIEW_W, VIEW_H, Image.INTERPOLATE_NEAREST)
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
	rows.append({"name": name, "bins": bins.size(), "luma": mean, "baseline_diff": diff})
	print("visual: captured %s (%d bins, luma %.3f, diff %.3f)"
		% [name, bins.size(), mean, diff])


## Compare two frames on a coarse grid, averaging a small block per cell so a
## one-pixel animation frame cannot fail the gate.
func _grid_diff(a: Image, b: Image) -> float:
	var total := 0.0
	var cells := 0
	for gy in range(18):
		for gx in range(32):
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
		"input_direct": input_direct,
		"fails": fails,
	}
	var f := FileAccess.open(dir + "/summary.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(out, "\t"))
		f.close()
	if fails == 0:
		print("visual: PASS — %d rendered frames, input_routed=%s input_direct=%s"
			% [rows.size(), str(input_routed), str(input_direct)])
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
