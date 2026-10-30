class_name RegionModel
extends RefCounted
## RegionModel — a region as pure data, loaded from data/regions/*.json.
##
## This is Covenant's `world/elah.js` idea, promoted from code to content: the
## map is an ASCII grid a human can read and edit in a text editor, and the
## legend, spawns, NPCs, items and triggers travel with it. Nothing about the
## world's shape lives in GDScript.
##
## Prop footprints: the (tx, ty) you author is the BOTTOM-LEFT tile of the
## footprint, which extends (w-1) right and (h-1) up. Unambiguous to author.

const TILE := 16

var id: String = ""
var display_name: Dictionary = {}
var legend: Dictionary = {}          # char -> tile key
var grid: PackedStringArray = PackedStringArray()
var width: int = 0
var height: int = 0
var spawn := Vector2i.ZERO
var music: String = "valley"

var npcs: Array = []                 # raw dicts from json
var items: Array = []
var props: Array = []                # {type, at:[x,y]}
var triggers: Array = []             # {id, kind, ...}
var exits: Array = []                # {to, at:[x,y]}
var words: Array = []                # the verses people hand you; become your moves
var shouts: Array = []               # what the giant shouts at you
var goliath := Vector2i.ZERO
var challenge_row: int = -1

# derived
var _solid := PackedByteArray()      # width*height, 1 = blocks movement
var _tile_key := PackedStringArray() # width*height, terrain key per cell
var _speed := PackedFloat32Array()
var _sfx := PackedStringArray()
var _tile_index: Dictionary = {}     # terrain key -> base atlas index + variant count
var _walkable_map: Dictionary = {}   # terrain key -> bool
var astar: AStarGrid2D = null


func load_from(path: String, tiles_meta: Dictionary) -> bool:
	if not FileAccess.file_exists(path):
		push_error("RegionModel: missing %s" % path)
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return false
	return _init_from(parsed, tiles_meta)


func _init_from(d: Dictionary, tiles_meta: Dictionary) -> bool:
	id = d.get("id", id)
	display_name = d.get("name", {})
	legend = d.get("legend", {})
	# PackedStringArray has no (Array) constructor: build it row by row.
	grid = PackedStringArray()
	for row in (d.get("grid", []) as Array):
		grid.append(str(row))
	height = grid.size()
	width = 0
	for row in grid:
		width = maxi(width, row.length())
	if width == 0 or height == 0:
		return false
	var sp: Array = d.get("spawn", [1, 1])
	spawn = Vector2i(int(sp[0]), int(sp[1]))
	music = d.get("music", music)
	npcs = d.get("npcs", [])
	items = d.get("items", [])
	props = d.get("props", [])
	triggers = d.get("triggers", [])
	exits = d.get("exits", [])
	words = d.get("words", [])
	shouts = d.get("shouts", [])
	var gl: Array = d.get("goliath", [0, 0])
	goliath = Vector2i(int(gl[0]), int(gl[1]))
	challenge_row = int(d.get("challenge_row", -1))

	# index the terrain atlas metadata
	for t in tiles_meta.get("tiles", []):
		var k: String = t["key"]
		if not _tile_index.has(k):
			_tile_index[k] = {"base": t["atlas_index"], "count": 0}
		_tile_index[k]["count"] += 1
		_walkable_map[k] = t["walkable"]
	# per-key speed/sfx from SURFACE metadata
	var surf: Dictionary = tiles_meta.get("surface", {})

	_solid.resize(width * height)
	_tile_key.resize(width * height)
	_speed.resize(width * height)
	_sfx.resize(width * height)
	for y in range(height):
		var row: String = grid[y]
		for x in range(width):
			var ch: String = row[x] if x < row.length() else "."
			var key: String = legend.get(ch, "grass")
			var i := y * width + x
			_tile_key[i] = key
			_solid[i] = 1 if not _walkable_map.get(key, true) else 0
			var s: Dictionary = surf.get(key, {})
			_speed[i] = float(s.get("speed", 1.0))
			_sfx[i] = str(s.get("sfx", "step_dirt"))

	# props add solidity
	for p in props:
		var fp: Dictionary = _prop_footprint(p)
		for y in range(fp["y0"], fp["y1"] + 1):
			for x in range(fp["x0"], fp["x1"] + 1):
				if _in(x, y):
					_solid[y * width + x] = 1

	_build_astar()
	return true


func _prop_footprint(p: Dictionary) -> Dictionary:
	var meta: Dictionary = p.get("_meta", {})
	var w: int = int(meta.get("w_tiles", 1))
	var h: int = int(meta.get("h_tiles", 1))
	var solid: bool = bool(meta.get("solid", true))
	var tx: int = int(p["at"][0]); var ty: int = int(p["at"][1])
	return {"x0": tx, "x1": tx + w - 1, "y0": ty - h + 1, "y1": ty, "solid": solid}


func _in(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func _build_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, width, height)
	astar.cell_size = Vector2(TILE, TILE)
	# NOTE: the property is diagonal_mode, not diagonal_enabled. Assigning a
	# property that does not exist aborts this function at runtime, leaving the
	# grid dirty — and a dirty grid answers every query with
	# "Grid is not initialized", so NPCs silently stop pathing.
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.update()
	if astar.is_dirty():
		push_error("RegionModel: AStarGrid2D stayed dirty after update()")
		astar = null
		return
	for y in range(height):
		for x in range(width):
			if _solid[y * width + x] == 1:
				astar.set_point_solid(Vector2i(x, y), true)


func tile_key_at(x: int, y: int) -> String:
	if not _in(x, y):
		return "cliff"
	return _tile_key[y * width + x]


func solid_at_tile(x: int, y: int) -> bool:
	if not _in(x, y):
		return true
	return _solid[y * width + x] == 1


## Solid at a world pixel position (feet point).
func solid_at(px: float, py: float) -> bool:
	return solid_at_tile(int(floor(px / TILE)), int(floor(py / TILE)))


func speed_at(px: float, py: float) -> float:
	var x := int(floor(px / TILE)); var y := int(floor(py / TILE))
	if not _in(x, y):
		return 0.0
	return _speed[y * width + x]


func sfx_at(px: float, py: float) -> String:
	var x := int(floor(px / TILE)); var y := int(floor(py / TILE))
	if not _in(x, y):
		return "step_dirt"
	return _sfx[y * width + x]


func atlas_index_for(key: String, variant: int) -> int:
	var m: Dictionary = _tile_index.get(key, {"base": 0, "count": 1})
	var count: int = int(m["count"])
	if count <= 0:
		count = 1
	return int(m["base"]) + (variant % count)


func variant_count(key: String) -> int:
	return int(_tile_index.get(key, {"count": 1})["count"])


## Deterministic per-cell variant, so texture never crawls between frames.
static func cell_variant(x: int, y: int) -> int:
	var n := (x * 73856093) ^ (y * 19349663)
	n = (n ^ (n >> 13)) * 1274126177
	return absi(n) % 997


func path(from: Vector2i, to: Vector2i) -> PackedVector2Array:
	if not _in(from.x, from.y) or not _in(to.x, to.y):
		return PackedVector2Array()
	var ids: PackedVector2Array = PackedVector2Array()
	if astar != null and not astar.is_dirty():
		for p in astar.get_id_path(from, to):
			ids.append(Vector2(p.x, p.y))
	if ids.is_empty():
		ids = _bfs(from, to)
	var out := PackedVector2Array()
	for p in ids:
		out.append(Vector2(p.x * TILE + TILE * 0.5, p.y * TILE + TILE * 0.5))
	return out


## Breadth-first fallback and the reachability oracle for tests/run_all.gd.
## AStarGrid2D is the fast path for NPC steering; this is the guarantee that a
## grid problem degrades to "walks the obvious way" instead of "nobody moves".
## Covenant had this as a test-only reachable(); here it also ships.
func _bfs(from: Vector2i, to: Vector2i) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not _in(from.x, from.y) or not _in(to.x, to.y):
		return out
	if from == to:
		out.append(Vector2(from.x, from.y))
		return out
	var prev := {}
	var queue: Array[Vector2i] = [from]
	prev[from] = from
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := cur + d
			if not _in(n.x, n.y) or prev.has(n) or _solid[n.y * width + n.x] == 1:
				continue
			prev[n] = cur
			if n == to:
				var back := to
				while back != from:
					out.push_front(Vector2(back.x, back.y))
					back = prev[back]
				out.push_front(Vector2(from.x, from.y))
				return out
			queue.append(n)
	return out


## Nearest non-solid tile to `t`, spiralling outward. Used when an NPC's patrol
## point or a spawn lands inside a wall because the map was edited by hand.
func nearest_open(t: Vector2i) -> Vector2i:
	if not solid_at_tile(t.x, t.y):
		return t
	for r in range(1, 8):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var c := Vector2i(t.x + dx, t.y + dy)
				if not solid_at_tile(c.x, c.y):
					return c
	return t
