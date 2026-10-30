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

const RegionModelScript := preload("res://scripts/systems/RegionModel.gd")

var failures := 0


func _init() -> void:
	var tiles := _read_json("res://data/tiles.json")
	var props := _read_json("res://data/props.json")
	var pmeta := {}
	for p in props.get("props", []):
		pmeta[p["key"]] = {"w_tiles": p["footprint"][0], "h_tiles": p["footprint"][1],
			"solid": p["solid"]}

	var regions := ["elah"]
	for rid in regions:
		_check_region(rid, tiles, pmeta)

	if failures == 0:
		print("run_all: ALL CHECKS PASSED")
		quit(0)
	else:
		printerr("run_all: %d FAILURE(S)" % failures)
		quit(1)


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
	_ok("spawn / npcs / items all on walkable ground")

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
	_ok("all dialogue and verses bilingual")

	# 5. no unwinnable shout
	var word_kinds := {}
	for w in m.words:
		word_kinds[w.get("kind")] = true
	for s in m.shouts:
		if not word_kinds.has(s.get("kind")):
			_fail("%s: shout kind '%s' has no matching verse — unwinnable round" % [rid, s.get("kind")])
	_ok("every shout is answerable")
