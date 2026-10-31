extends SceneTree
## Headless content lint. Runs in CI with:
##     godot --headless --path . --script tests/run_all.gd
##
## This is the descendant of Covenant's twelve `check:*` scripts. It needs no
## GPU and no window: it validates the WORLD DATA — the thing volunteers and
## future-you will edit by hand — so a broken map or a half-translated line
## fails the build instead of failing a player.
##
## Checks:
##   1. every region file parses and its legend covers every grid character
##   2. spawn / npc / item tiles are walkable
##   3. a navigation path exists from spawn to every NPC and every item
##      (Covenant's reachable() BFS was test-only; here it gates the build)
##   4. every NPC line and every verse card has BOTH languages
##   5. the fight can be won (hits vs stones, dodge window inside the strike).
##      It replaced the verse quiz, so this replaced the quiz's check

const RegionModelScript = preload("res://scripts/systems/RegionModel.gd")
const ScreenFitScript = preload("res://scripts/systems/ScreenFit.gd")
const GoliathFightScript = preload("res://scripts/setpiece/GoliathFight.gd")

var failures := 0


func _init() -> void:
	var tiles := _read_json("res://data/tiles.json")
	var props := _read_json("res://data/props.json")
	var pmeta := {}
	for p in props.get("props", []):
		pmeta[p["key"]] = {"w_tiles": p["footprint"][0], "h_tiles": p["footprint"][1],
			"solid": p["solid"]}

	_check_display()
	_check_layout()
	_check_campaigns()
	var regions := ["elah"]
	for rid in regions:
		_check_region(rid, tiles, pmeta)

	if failures == 0:
		print("run_all: ALL CHECKS PASSED")
		quit(0)
	else:
		printerr("run_all: %d FAILURE(S)" % failures)
		quit(1)


## What the player's screen does is content too. Integer stretch scaling picks a
## whole-number factor, so a window that changes by a few pixels drops a whole
## step and the game shrinks into black bars mid-play (playtest 8, bug C). That
## is a one-line regression in project.godot, so it gets a one-line gate.
func _check_display() -> void:
	var mode := str(ProjectSettings.get_setting("display/window/stretch/scale_mode", "fractional"))
	if mode == "integer":
		_fail("stretch scale_mode is integer: the picture will shrink and letterbox on resize")
	else:
		_ok("display scales fractionally (no black bars on resize)")
	var aspect := str(ProjectSettings.get_setting("display/window/stretch/aspect", "keep"))
	if aspect != "expand":
		_fail("stretch aspect is '%s': tall phones get letterboxed" % aspect)
	else:
		_ok("display expands to fill tall screens")


## The screen, at forty sizes.
##
## Playtest 9: "the game becomes smaller and black borders appear". The stretch
## settings are asserted above; this asserts the LAYOUT — that at every screen
## shape a landscape phone can report, the dialogue box and the HUD bands stay on
## screen, the text column stays readable, the camera clamp stays inside the
## region, and the cinematic bars never take more than a tenth of the picture.
func _check_layout() -> void:
	var sizes := [
		Vector2(320, 180), Vector2(360, 180), Vector2(400, 180),   # 16:9, 2:1, 20:9
		Vector2(568, 320), Vector2(640, 360), Vector2(844, 390),   # phones
		Vector2(960, 540), Vector2(1024, 576), Vector2(1280, 720),
		Vector2(1024, 768), Vector2(1400, 720), Vector2(2400, 1080),
		Vector2(320, 240), Vector2(400, 300),                      # 4:3, 16:9 tall
	]
	var bad := 0
	for vs in sizes:
		var d: Dictionary = ScreenFitScript.dialogue(vs)
		var r: Rect2 = d["rect"]
		var why := ""
		if r.position.x < 0.0 or r.position.y < 0.0:
			why = "dialogue starts off screen"
		elif r.end.x > vs.x + 0.01 or r.end.y > vs.y + 0.01:
			why = "dialogue runs past the screen edge"
		elif float(d["max_h"]) > vs.y * 0.5:
			why = "dialogue takes more than half the height"
		elif float(d["text_w"]) < 80.0:
			why = "text column is too narrow to read"
		if why != "":
			bad += 1
			_fail("layout %dx%d: %s" % [int(vs.x), int(vs.y), why])
		# the top band the HUD's first two rows live in
		var band: Rect2 = ScreenFitScript.anchor_top_band(vs)
		if band.end.y > vs.y * 0.5:
			bad += 1
			_fail("HUD top band is more than half the screen at %dx%d"
				% [int(vs.x), int(vs.y)])
		# cinematic bars are a frame, not a crop
		var bar: float = ScreenFitScript.bar_height(vs)
		if bar > vs.y * 0.11:
			bad += 1
			_fail("letterbox at %dx%d takes %.0f%% of the picture"
				% [int(vs.x), int(vs.y), bar / vs.y * 100.0])
		# the camera never shows outside the region
		var bounds := Rect2(0, 0, 512, 768)
		for probe in [Vector2(-900, -900), Vector2(900, 900), Vector2(250, 380)]:
			var c: Vector2 = ScreenFitScript.clamp_camera(probe, vs, bounds, Vector2.ONE)
			var half: Vector2 = ScreenFitScript.camera_half(vs, Vector2.ONE)
			if half.x * 2.0 < bounds.size.x and (c.x - half.x < -0.5 or c.x + half.x > bounds.size.x + 0.5):
				bad += 1
				_fail("camera centre %.0f lets the view leave the region at %dx%d"
					% [c.x, int(vs.x), int(vs.y)])
	if bad == 0:
		_ok("layout holds at %d screen shapes (dialogue, HUD, letterbox, camera clamp)" % sizes.size())


## The platform registry. Adding a campaign is supposed to be a data change, so
## the gate is about the data agreeing with itself: an available campaign must
## point at a region file that exists, and every campaign must be readable in
## both languages.
func _check_campaigns() -> void:
	var reg := _read_json("res://data/campaigns.json")
	var list: Array = reg.get("campaigns", [])
	if list.is_empty():
		_fail("data/campaigns.json registers no campaigns")
		return
	var seen := {}
	for c in list:
		var id := str(c.get("id", ""))
		if id == "":
			_fail("a campaign has no id")
			continue
		if seen.has(id):
			_fail("campaign id '%s' is registered twice" % id)
		seen[id] = true
		_has_both(c.get("title"), "campaign %s title" % id)
		_has_both(c.get("subtitle"), "campaign %s subtitle" % id)
		_has_both(c.get("book"), "campaign %s book reference" % id)
		if bool(c.get("available", false)):
			var path := "res://data/regions/%s.json" % str(c.get("region", ""))
			if not FileAccess.file_exists(path):
				_fail("campaign %s is marked available but %s does not exist" % [id, path])
	_ok("campaign registry is consistent (%d registered)" % list.size())

	# Marks and UI labels are player-facing prose too, and they live outside the
	# region files, so the bilingual rule has to reach them here.
	var ach := _read_json("res://data/achievements.json")
	var seals: Array = ach.get("seals", [])
	if seals.is_empty():
		_fail("data/achievements.json has no marks")
	for s_ in seals:
		var sid := str(s_.get("id", ""))
		if sid == "":
			_fail("a mark has no id")
		_has_both(s_.get("title"), "mark %s title" % sid)
		_has_both(s_.get("desc"), "mark %s description" % sid)
	_ok("marks are bilingual (%d)" % seals.size())
	var ui := _read_json("res://data/ui.json")
	for k in (ui.get("journal", {}) as Dictionary):
		_has_both(ui["journal"][k], "ui.journal.%s" % k)
	_ok("journal labels are bilingual")


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_fail("missing file %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if d is Dictionary else {}


func _fail(msg: String) -> void:
	failures += 1
	printerr("  FAIL  %s" % msg)


func _ok(msg: String) -> void:
	print("  ok    %s" % msg)


func _has_both(d: Variant, what: String) -> void:
	if not (d is Dictionary):
		_fail("%s: text is not a {en,zh} object" % what)
		return
	if not d.has("en") or not d.has("zh") or str(d["en"]) == "" or str(d["zh"]) == "":
		_fail("%s: missing en or zh" % what)


func _check_region(rid: String, tiles: Dictionary, pmeta: Dictionary) -> void:
	print("region: %s" % rid)
	var raw := _read_json("res://data/regions/%s.json" % rid)
	if raw.is_empty():
		return
	for p in raw.get("props", []):
		p["_meta"] = pmeta.get(p["type"], {"w_tiles": 1, "h_tiles": 1, "solid": true})

	var m = RegionModelScript.new()
	if not m._init_from(raw, tiles):
		_fail("%s: model failed to initialise" % rid)
		return

	# 1. legend covers the grid
	var legend_keys := {}
	for k in m.legend:
		legend_keys[k] = true
	for y in range(m.height):
		var row: String = m.grid[y]
		for x in range(row.length()):
			if not legend_keys.has(row[x]):
				_fail("%s: grid char '%s' at (%d,%d) not in legend" % [rid, row[x], x, y])
	_ok("legend covers grid (%dx%d)" % [m.width, m.height])

	# 2. spawns / npcs / items walkable
	if m.solid_at_tile(m.spawn.x, m.spawn.y):
		_fail("%s: spawn %s is inside a solid tile" % [rid, m.spawn])
	for n in m.npcs:
		var t := Vector2i(int(n["at"][0]), int(n["at"][1]))
		if m.solid_at_tile(t.x, t.y):
			_fail("%s: npc %s at %s is inside a solid tile" % [rid, n.get("id"), t])
	for it in m.items:
		var t := Vector2i(int(it["at"][0]), int(it["at"][1]))
		if m.solid_at_tile(t.x, t.y):
			_fail("%s: item %s at %s is inside a solid tile" % [rid, it.get("id"), t])
	# David's provisions are spawned at runtime, so nothing at load time noticed
	# that one of them sat inside a solid altar prop: "the quest item cannot be
	# seen on the map". Same rule, same place, checked here instead.
	for it in (m.david_act.get("items", []) as Array):
		var t := Vector2i(int(it["at"][0]), int(it["at"][1]))
		if m.solid_at_tile(t.x, t.y):
			_fail("%s: provision %s at %s is inside a solid tile or prop" % [rid, it.get("id"), t])
		if m.path(m.spawn, t).is_empty():
			_fail("%s: no walkable path from spawn to provision %s" % [rid, it.get("id")])
	var ba: Array = m.david_act.get("brothers_at", [])
	if ba.size() == 2:
		var bt := Vector2i(int(ba[0]), int(ba[1]))
		if m.solid_at_tile(bt.x, bt.y):
			_fail("%s: the brothers' post %s is solid" % [rid, bt])
		if m.path(m.spawn, bt).is_empty():
			_fail("%s: no walkable path to the brothers' post" % rid)
	var sa: Array = m.david_act.get("start_at", [])
	if sa.size() == 2:
		var st := Vector2i(int(sa[0]), int(sa[1]))
		if m.solid_at_tile(st.x, st.y):
			_fail("%s: the errand starts on a solid tile %s" % [rid, st])
	# The shepherd beat teleports too, and a teleport into a solid tile is a
	# player standing inside a rock with no way to tell anyone why.
	var sh: Dictionary = m.david_act.get("shepherd", {})
	var sh_at: Array = sh.get("start_at", [])
	if sh_at.size() == 2:
		var sht := Vector2i(int(sh_at[0]), int(sh_at[1]))
		if m.solid_at_tile(sht.x, sht.y):
			_fail("%s: the shepherd chapter starts on a solid tile %s" % [rid, sht])
		if m.path(m.spawn, sht).is_empty():
			_fail("%s: the shepherd chapter is walled off from spawn" % rid)
	_ok("spawn / npcs / items / provisions all on walkable ground")

	# 3. reachability
	for n in m.npcs:
		var t := Vector2i(int(n["at"][0]), int(n["at"][1]))
		if m.path(m.spawn, t).is_empty():
			_fail("%s: no walkable path from spawn to npc %s" % [rid, n.get("id")])
	for it in m.items:
		var t := Vector2i(int(it["at"][0]), int(it["at"][1]))
		if m.path(m.spawn, t).is_empty():
			_fail("%s: no walkable path from spawn to item %s" % [rid, it.get("id")])
	_ok("every NPC and item reachable from spawn")

	# 4. bilingual completeness
	for n in m.npcs:
		_has_both(n.get("name"), "%s:npc %s name" % [rid, n.get("id")])
		for line in (n.get("lines", []) as Array) + (n.get("after", []) as Array):
			_has_both(line.get("text"), "%s:npc %s line" % [rid, n.get("id")])
	for w in m.words:
		_has_both(w.get("text"), "%s:word %s" % [rid, w.get("id")])
	# the beats a trigger speaks (refusing you, remembering the fight) and the
	# first-run briefing are player-facing prose too
	for t in m.triggers:
		var td: Dictionary = t
		for key in ["refuse", "memory"]:
			for line in (td.get(str(key), []) as Array):
				_has_both(line.get("text"), "%s:trigger %s %s" % [rid, td.get("id"), key])
	for line in m.briefing:
		_has_both(line.get("text"), "%s:briefing line" % rid)
	for line in m.prologue:
		_has_both(line.get("text"), "%s:prologue line" % rid)
	for c in m.curios:
		var cd: Dictionary = c
		if str(cd.get("id", "")) == "":
			_fail("%s: a curio has no id" % rid)
		var at: Array = cd.get("at", [0, 0])
		if m.solid_at_tile(int(at[0]), int(at[1])):
			_fail("%s: curio %s sits inside a solid tile" % [rid, cd.get("id")])
		if m.path(m.spawn, Vector2i(int(at[0]), int(at[1]))).is_empty():
			_fail("%s: curio %s cannot be walked to" % [rid, cd.get("id")])
		for line in (cd.get("lines", []) as Array):
			_has_both(line.get("text"), "%s:curio %s line" % [rid, cd.get("id")])
	for key in ["lines", "brothers"]:
		for line in (m.david_act.get(key, []) as Array):
			_has_both(line.get("text"), "%s:david_act %s" % [rid, key])
	for key in ["shepherd", "saul"]:
		for line in ((m.david_act.get(key, {}) as Dictionary).get("lines", []) as Array):
			_has_both(line.get("text"), "%s:david_act %s" % [rid, key])
	for line in ((m.david_act.get("shepherd", {}) as Dictionary).get("done_lines", []) as Array):
		_has_both(line.get("text"), "%s:david_act shepherd done" % rid)
	for n in m.npcs:
		for line in (n.get("after_win", []) as Array):
			_has_both(line.get("text"), "%s:npc %s after_win" % [rid, n.get("id")])
	for sp in (m.david_act.get("speakers", {}) as Dictionary).values():
		_has_both(sp, "%s:david_act speaker name" % rid)
	# The chapter ending and the HUD's objective lines are player-facing prose
	# too. They are the newest way text reaches a player and the easiest to leave
	# half-translated: one is shown once, at the very end, and the other is a
	# single string no dialogue ever repeats.
	for key in m.objectives:
		_has_both(m.objectives.get(key), "%s:objective %s" % [rid, key])
	for key in ["corin", "stones", "line", "done"]:
		if not m.objectives.has(key):
			_fail("%s: objectives is missing '%s' — the HUD would point at nothing" % [rid, key])
	for line in (m.ending.get("lines", []) as Array):
		_has_both(line.get("text"), "%s:ending line" % rid)
	_has_both(m.ending.get("ask"), "%s:ending question" % rid)
	for o in (m.ending.get("options", []) as Array):
		_has_both(o.get("t"), "%s:ending option" % rid)
		_has_both(o.get("insight"), "%s:ending insight" % rid)
	if (m.ending.get("lines", []) as Array).is_empty():
		_fail("%s: no ending — the chapter would stop the moment the giant falls" % rid)
	_ok("all dialogue, verses, objectives and the ending are bilingual")

	# 5. the fight is a fight, and it can be finished.
	# It used to be a verse quiz followed by a duel; the duel is now the whole
	# confrontation, so the gate is that its numbers still add up.
	if GoliathFightScript.HITS_TO_WIN < 1:
		_fail("%s: the fight needs at least one hit to win" % rid)
	if GoliathFightScript.STONES < GoliathFightScript.HITS_TO_WIN:
		_fail("%s: fewer stones than hits needed — unwinnable" % rid)
	if GoliathFightScript.DODGE_WINDOW <= 0.0 or GoliathFightScript.DODGE_WINDOW >= 1.0:
		_fail("%s: the dodge window must sit inside the strike" % rid)
	_ok("the fight is winnable and has a dodge window")
