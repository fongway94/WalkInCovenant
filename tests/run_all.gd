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
##   4. every NPC line and every word/shout has BOTH languages
##   5. every shout kind has at least one matching word kind in the same
##      region, so no word-battle round can be unwinnable

const RegionModelScript = preload("res://scripts/systems/RegionModel.gd")

var failures := 0


func _init() -> void:
	var tiles := _read_json("res://data/tiles.json")
	var props := _read_json("res://data/props.json")
	var pmeta := {}
	for p in props.get("props", []):
		pmeta[p["key"]] = {"w_tiles": p["footprint"][0], "h_tiles": p["footprint"][1],
			"solid": p["solid"]}

	_check_display()
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
	for s in m.shouts:
		_has_both(s.get("line"), "%s:shout line" % rid)
		_has_both(s.get("tell"), "%s:shout tell" % rid)
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

	# 5. no unwinnable shout
	var word_kinds := {}
	for w in m.words:
		word_kinds[w.get("kind")] = true
	for s in m.shouts:
		if not word_kinds.has(s.get("kind")):
			_fail("%s: shout kind '%s' has no matching verse — unwinnable round" % [rid, s.get("kind")])
	_ok("every shout is answerable")
