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
	# Region ids come from the shelf, not from this file. They used to be a
	# hand-written pair here, so a third chapter would have shipped unvalidated
	# while the gate still said "clean".
	for rid in _region_ids():
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


## A `const NAME := 3` out of a script, without compiling the script.
func _const_int(path: String, name: String, fallback: int) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return fallback
	var txt := f.get_as_text()
	f.close()
	var m := RegEx.create_from_string("const %s\\s*:?=\\s*(-?[0-9]+)" % name).search(txt)
	if m == null:
		return fallback
	return int(m.get_string(1))


func _const_float(path: String, name: String, fallback: float) -> float:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return fallback
	var txt := f.get_as_text()
	f.close()
	var m := RegEx.create_from_string("const %s\\s*:?=\\s*(-?[0-9.]+)" % name).search(txt)
	if m == null:
		return fallback
	return float(m.get_string(1))


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


## Every region file in data/regions, by id. Listing the shelf rather than naming
## regions by hand is what makes "adding a chapter is a data change" true of the
## gate as well as of the game.
func _region_ids() -> Array:
	var ids := []
	for f in DirAccess.get_files_at("res://data/regions"):
		if f.ends_with(".json"):
			ids.append(f.get_basename())
	ids.sort()
	return ids


## The platform registry. Adding a campaign is supposed to be a data change, so
## the gate is about the data agreeing with itself: an available campaign must
## point at a region file that exists, and every campaign must be readable in
## both languages.
##
## `chapters` is the campaign's regions in play order — the first one is where a
## new game boots. Every region file on the shelf must be claimed by exactly one
## campaign, or it is a place the platform cannot reach and nobody will notice
## when it rots.
func _check_campaigns() -> void:
	var reg := _read_json("res://data/campaigns.json")
	var list: Array = reg.get("campaigns", [])
	if list.is_empty():
		_fail("data/campaigns.json registers no campaigns")
		return
	var seen := {}
	var claimed := {}
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
		var chapters: Array = c.get("chapters", [])
		if chapters.is_empty():
			if bool(c.get("available", false)):
				_fail("campaign %s is playable but lists no chapters" % id)
			continue
		if str(chapters[0]) != str(c.get("region", "")):
			_fail("campaign %s boots into '%s' but its first chapter is '%s'"
				% [id, str(c.get("region", "")), str(chapters[0])])
		for ch in chapters:
			var cp := "res://data/regions/%s.json" % str(ch)
			if not FileAccess.file_exists(cp):
				_fail("campaign %s lists chapter '%s', which has no region file" % [id, str(ch)])
				continue
			if claimed.has(str(ch)):
				_fail("'%s' is a chapter of both %s and %s" % [str(ch), claimed[str(ch)], id])
			claimed[str(ch)] = id
	_ok("campaign registry is consistent (%d registered, %d chapter(s))"
		% [list.size(), claimed.size()])
	for rid in _region_ids():
		if not claimed.has(str(rid)):
			_fail("data/regions/%s.json belongs to no campaign — a place nobody can reach" % str(rid))

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


## Scripture in this game is spoken in 「」 (and “ ” in English) and split
## across boxes when it is long. A BEAT therefore has to carry both halves: an
## opening mark with nothing closing it anywhere in the beat is a truncated
## quotation — words put in Scripture's mouth that Scripture does not say.
func _check_verses(lines: Array, where: String) -> void:
	var zh := ""
	var en := ""
	for line in lines:
		var t: Dictionary = line.get("text", {})
		zh += str(t.get("zh", ""))
		en += str(t.get("en", ""))
	if zh.find("「") >= 0 and zh.find("」") < 0:
		_fail("%s: a verse opens with 「 and is never closed" % where)
	if en.find("\u201c") >= 0 and en.find("\u201d") < 0:
		_fail("%s: a verse opens with a quote mark and is never closed" % where)


## The campaign contract, as a check. Any region file must pass this before it
## counts as a place a player can stand in, let alone a story they can play:
## walkable spawn, people and things you can reach, exits that point at regions
## that exist, missions whose conditions the runner can evaluate and whose
## rewards exist, a chapter script if it names one, its own music, every
## player-facing string in both languages, and every verse quoted whole.
##
## This is what makes "add a Bible story without rebuilding the game" a claim
## with evidence behind it rather than an intention in a document.
func _check_region_any(m, rid: String) -> void:
	if m.solid_at_tile(m.spawn.x, m.spawn.y):
		_fail("%s: spawn %s is inside a solid tile" % [rid, m.spawn])
	if m.npcs.is_empty():
		_fail("%s: no people — a place with nobody in it is not a story" % rid)
	for n in m.npcs:
		var nd: Dictionary = n
		var t := Vector2i(int(nd["at"][0]), int(nd["at"][1]))
		if m.solid_at_tile(t.x, t.y):
			_fail("%s: npc %s at %s is inside a solid tile" % [rid, nd.get("id"), t])
		if m.path(m.spawn, t).is_empty():
			_fail("%s: no walkable path from spawn to npc %s" % [rid, nd.get("id")])
		_has_both(nd.get("name"), "%s:npc %s name" % [rid, nd.get("id")])
		for line in (nd.get("lines", []) as Array) + (nd.get("after", []) as Array) \
				+ (nd.get("after_win", []) as Array):
			_has_both(line.get("text"), "%s:npc %s line" % [rid, nd.get("id")])
		_check_verses(nd.get("lines", []), "%s:npc %s" % [rid, nd.get("id")])

	for it in m.items:
		var idict: Dictionary = it
		var it_t := Vector2i(int(idict["at"][0]), int(idict["at"][1]))
		if m.solid_at_tile(it_t.x, it_t.y):
			_fail("%s: item %s sits inside a solid tile" % [rid, idict.get("id")])
		if m.path(m.spawn, it_t).is_empty():
			_fail("%s: no walkable path from spawn to item %s" % [rid, idict.get("id")])

	# Exits are the only way out, so a typo here is a softlock.
	for e in m.exits:
		var ed: Dictionary = e
		var to := str(ed.get("to", ""))
		if to == "":
			_fail("%s: an exit has no destination" % rid)
		elif not FileAccess.file_exists("res://data/regions/%s.json" % to):
			_fail("%s: an exit points at '%s', which has no region file" % [rid, to])
		var at: Array = ed.get("at", [])
		if at.size() != 2:
			_fail("%s: exit to %s has no tile" % [rid, to])
			continue
		var et := Vector2i(int(at[0]), int(at[1]))
		if m.solid_at_tile(et.x, et.y):
			_fail("%s: the exit to %s is inside a solid tile" % [rid, to])
		if m.path(m.spawn, et).is_empty():
			_fail("%s: the exit to %s cannot be walked to" % [rid, to])
	if m.exits.is_empty():
		_fail("%s: no exits — the player can never leave" % rid)

	if m.chapter_script != "" and not FileAccess.file_exists(m.chapter_script):
		_fail("%s: names a chapter script that does not exist (%s)" % [rid, m.chapter_script])
	if m.music != "" and not FileAccess.file_exists("res://audio/music/%s.wav" % m.music):
		_fail("%s: asks for music '%s' and the shelf has no such track" % [rid, m.music])

	for key in m.objectives:
		_has_both(m.objectives.get(key), "%s:objective %s" % [rid, key])
	for line in m.briefing:
		_has_both(line.get("text"), "%s:briefing line" % rid)
	for line in m.prologue:
		_has_both(line.get("text"), "%s:prologue line" % rid)
	var scenes: Dictionary = m.scenes
	for skey in scenes:
		var lines: Array = scenes[skey]
		if lines.is_empty():
			_fail("%s: scene '%s' is empty" % [rid, skey])
		for line in lines:
			_has_both(line.get("text"), "%s:scene %s" % [rid, skey])
		_check_verses(lines, "%s:scene %s" % [rid, skey])

	var seals := {}
	var ad := _read_json("res://data/achievements.json")
	for sd in ad.get("seals", []):
		seals[str(sd.get("id", ""))] = true

	if m.missions.is_empty():
		_fail("%s: no missions — the chapter would never start" % rid)
	var seen := {}
	for mi in m.missions:
		var mm: Dictionary = mi
		var mid := str(mm.get("id", ""))
		if mid == "":
			_fail("%s: a mission has no id" % rid)
		if seen.has(mid):
			_fail("%s: mission '%s' appears twice" % [rid, mid])
		seen[mid] = true
		var obj_key := str(mm.get("objective", ""))
		if not m.objectives.has(obj_key):
			_fail("%s: mission '%s' points at objective '%s', which does not exist"
				% [rid, mid, obj_key])
		if str(mm.get("act", "")) == "":
			_fail("%s: mission '%s' has no act" % [rid, mid])
		var enter := str(mm.get("enter", ""))
		if enter != "" and m.chapter_script == "":
			_fail("%s: mission '%s' asks for mechanic '%s' but the region names no chapter script"
				% [rid, mid, enter])
		var cond: Dictionary = mm.get("complete", {})
		var kind := str(cond.get("kind", ""))
		if kind != "flag" and kind != "count":
			_fail("%s: mission '%s' has completion kind '%s'" % [rid, mid, kind])
		if str(cond.get("key", "")) == "":
			_fail("%s: mission '%s' has no completion key" % [rid, mid])
		var rewards: Dictionary = mm.get("rewards", {})
		var seal := str(rewards.get("seal", ""))
		if seal != "" and not seals.has(seal):
			_fail("%s: mission '%s' rewards seal '%s', which achievements.json does not define"
				% [rid, mid, seal])
		for bl in mm.get("brief", []):
			_has_both(bl.get("text"), "%s: mission '%s' brief line" % [rid, mid])
	_ok("%s: walkable, reachable, bilingual, verses whole, missions and exits valid" % rid)


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

	# A region that is not David's chapter gets the campaign CONTRACT and stops
	# there: nothing below this line is allowed to know what a brook or an
	# armour is, and a second Bible story must not have to satisfy David's gate.
	if rid != "elah":
		_check_region_any(m, rid)
		return

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
	# The five stones of 1 Samuel 17:40 are laid out in the brook when David
	# walks down to it, so nothing at load time can notice one of them sitting
	# inside a rock. Same gate as the provisions: walkable, and reachable.
	# 1 Samuel 17:40 is now a hand-picking scene (script/setpiece/StoneChoice.gd),
	# so the data only has to promise that the water is reachable and that the
	# numbers can make five: a pool of at least five, and exactly five wanted.
	var brook: Dictionary = m.david_act.get("brook", {})
	var need := int(brook.get("need", 0))
	var pool := int(brook.get("pool", 0))
	if need != 5:
		_fail("%s: the brook asks for %d stones, Scripture says five" % [rid, need])
	if pool < need:
		_fail("%s: the brook holds %d stones but wants %d — unwinnable" % [rid, pool, need])
	var bat: Array = brook.get("at", [0, 0])
	if bat.size() == 2:
		var bt := Vector2i(int(bat[0]), int(bat[1]))
		if m.solid_at_tile(bt.x, bt.y):
			_fail("%s: the brook itself at %s is solid" % [rid, bt])
		if m.path(m.spawn, bt).is_empty():
			_fail("%s: the brook cannot be walked to from spawn" % rid)
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
		for key in ["refuse", "memory", "witness"]:
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
	for key in ["arrive_lines", "verse_lines", "done_lines"]:
		for line in (brook.get(str(key), []) as Array):
			_has_both(line.get("text"), "%s:brook %s" % [rid, key])
	var arm: Dictionary = m.david_act.get("armour", {})
	for key in ["wear_lines", "stumble_lines", "take_off_lines"]:
		if (arm.get(str(key), []) as Array).is_empty():
			_fail("%s: david_act.armour.%s is empty" % [rid, key])
		for line in (arm.get(str(key), []) as Array):
			_has_both(line.get("text"), "%s:armour %s" % [rid, key])
	# Corin speaks in the witness's last beat and in David's act, so his name has
	# to be in the speakers table or the box would open nameless.
	for sid in ["corin", "david", "saul", "jesse", "eliab"]:
		if not (m.david_act.get("speakers", {}) as Dictionary).has(sid):
			_fail("%s: david_act.speakers has no '%s'" % [rid, sid])
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
	for key in ["corin", "stones", "line", "line_witness", "brook", "armour", "done"]:
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
	# Scripture in a dialogue line is written "book chapter:verse" on its own
	# line, then the verse in 「」. A line that opens a verse but never closes it
	# is a truncated quotation, which is the one thing this game may not do.
	var src: Dictionary = m.david_act
	for key in ["lines", "brothers", "battle_intro", "victory"]:
		_check_verses(src.get(str(key), []), "%s:david_act.%s" % [rid, key])
	for key in ["shepherd", "saul", "brook"]:
		var blk: Dictionary = src.get(str(key), {})
		for lk in ["lines", "done_lines"]:
			_check_verses(blk.get(str(lk), []), "%s:david_act.%s.%s" % [rid, key, lk])
	for td in m.triggers:
		var tdd: Dictionary = td
		for key in ["refuse", "memory", "witness", "firstsight"]:
			_check_verses(tdd.get(str(key), []), "%s:trigger.%s" % [rid, key])
	_ok("all dialogue, verses, objectives and the ending are bilingual")

	# 4b. the mission list — the chapter's spine is data, so it gets the same
	# gate as every other piece of data: ids unique, each mission's objective
	# exists, each completion condition is one the runner can actually evaluate,
	# and each `enter` names a mechanic this chapter implements.
	if m.missions.is_empty():
		_fail("%s: no missions — the chapter would never start" % rid)
	var seen := {}
	var enters := ["", "become_david", "errand", "saul", "brook", "ready"]
	for mi in m.missions:
		var mm: Dictionary = mi
		var mid := str(mm.get("id", ""))
		if mid == "":
			_fail("%s: a mission has no id" % rid)
		if seen.has(mid):
			_fail("%s: mission '%s' appears twice" % [rid, mid])
		seen[mid] = true
		var obj_key := str(mm.get("objective", ""))
		if not m.objectives.has(obj_key):
			_fail("%s: mission '%s' points at objective '%s', which does not exist"
				% [rid, mid, obj_key])
		var act_name := str(mm.get("act", ""))
		if act_name == "":
			_fail("%s: mission '%s' has no act" % [rid, mid])
		if not enters.has(str(mm.get("enter", ""))):
			_fail("%s: mission '%s' asks for mechanic '%s', which Main does not implement"
				% [rid, mid, mm.get("enter")])
		var cond: Dictionary = mm.get("complete", {})
		var kind := str(cond.get("kind", ""))
		if kind != "flag" and kind != "count":
			_fail("%s: mission '%s' has completion kind '%s'" % [rid, mid, kind])
		for bl in mm.get("brief", []):
			_has_both(bl.get("text"), "%s: mission '%s' brief line" % [rid, mid])
		if str(cond.get("key", "")) == "":
			_fail("%s: mission '%s' has no completion key" % [rid, mid])
	if not seen.has("the_line"):
		_fail("%s: the chapter has no mission for the line" % rid)
	_ok("the mission list is complete and every condition is evaluable")

	# 5. the fight is a fight, and it can be finished.
	# It used to be a verse quiz followed by a duel; the duel is now the whole
	# confrontation, so the gate is that its numbers still add up.
	# The numbers are read from the file rather than by loading it: run_all runs
	# under `--script`, before the autoloads exist, and GoliathFight references
	# AudioDirector the moment it compiles.
	var hits_need := _const_int("res://scripts/setpiece/GoliathFight.gd", "HITS_TO_WIN", -1)
	var stones_have := _const_int("res://scripts/setpiece/GoliathFight.gd", "STONES", -1)
	var dodge := _const_float("res://scripts/setpiece/GoliathFight.gd", "DODGE_WINDOW", -1.0)
	if hits_need < 1:
		_fail("%s: the fight needs at least one hit to win" % rid)
	if stones_have < hits_need:
		_fail("%s: fewer stones (%d) than hits needed (%d) — unwinnable"
			% [rid, stones_have, hits_need])
	if dodge <= 0.0 or dodge >= 1.0:
		_fail("%s: the dodge window (%.2f) must sit inside the strike" % [rid, dodge])
	_ok("the fight is winnable and has a dodge window")
