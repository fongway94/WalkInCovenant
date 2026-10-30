extends Node2D
class_name Region
## Region — turns data/regions/<id>.json into a walkable place.
##
## Owns: terrain, props, the player, NPCs, pickups, triggers, exits, the camera,
## day/night light, and the interact query. It owns NO story logic — story lives
## in data and in DialogueRunner; the region only reports what the player
## touched, via EventBus.

const TILE := 16.0
const PICK_RANGE := 10.0
const TALK_RANGE := 20.0
## How long after a box closes the A button is ignored. Long enough to swallow
## the tap that closed it (one tap can arrive as a touch AND an action), short
## enough that nobody waiting to talk again ever notices.
const INTERACT_LOCK := 0.35

@export var region_id := "elah"

var model: RegionModel = null
var terrain: TerrainLayer = null
var player: Player = null
var cam: CameraRig = null
# Typed on purpose. With a plain Array, `for n in npcs` yields a Variant, so
# `var d := (n.global_position - ...).length()` infers from a Variant — which is
# an ERROR-level warning in Godot 4.7 and stops the script compiling.
var npcs: Array[Npc] = []
var pickups: Array = []         # {id, kind, node, got}
var triggers: Array = []        # {id, kind, data, spent, armed}
var dialogue: DialogueBox = null

var _ys: Node2D = null
var _mod: CanvasModulate = null
var _props_meta: Dictionary = {}
var _tiles_meta: Dictionary = {}
var _paused := false
var _interact_lock := 0.0
var _mark_t := 0.0
var _curio_done := {}
var _curio_cool := 0.0

signal region_ready
signal pickup_taken(id: String)
signal curio_seen(id: String, lines: Array)
signal trigger_fired(id: String)
signal exit_taken(to: String)


func _ready() -> void:
	_load_meta()
	_build()
	region_ready.emit()


func _load_meta() -> void:
	var tf := FileAccess.open("res://data/tiles.json", FileAccess.READ)
	_tiles_meta = JSON.parse_string(tf.get_as_text())
	tf.close()
	var pf := FileAccess.open("res://data/props.json", FileAccess.READ)
	var pj: Dictionary = JSON.parse_string(pf.get_as_text())
	pf.close()
	for p in pj.get("props", []):
		_props_meta[p["key"]] = {
			"w_tiles": p["footprint"][0], "h_tiles": p["footprint"][1],
			"solid": p["solid"], "frames": p["frames"],
			"w": p["w"], "h": p["h"],
		}


func _build() -> void:
	model = RegionModel.new()
	var raw := _read_json("res://data/regions/%s.json" % region_id)
	# attach prop footprints before the model builds collision
	for p in raw.get("props", []):
		p["_meta"] = _props_meta.get(p["type"], {"w_tiles": 1, "h_tiles": 1, "solid": true})
	model._init_from(raw, _tiles_meta)

	terrain = TerrainLayer.new()
	var tex := load("res://art/tiles/terrain.png")
	terrain.setup(model, tex, int(_tiles_meta.get("columns", 16)))
	add_child(terrain)

	# Before anything that talks. Npc.setup() is handed the dialogue box by
	# reference, and it used to be built after _spawn_npcs() — so every person in
	# the valley held null, talk() hit its guard and returned, and pressing A
	# next to anybody did nothing at all. The one interaction the game is built
	# on, dead, with a green compile and a green boot check.
	dialogue = DialogueBox.new()
	add_child(dialogue)
	dialogue.hide_box()
	dialogue.closed.connect(func(): _interact_lock = INTERACT_LOCK)

	_ys = Node2D.new()
	_ys.y_sort_enabled = true
	add_child(_ys)

	_spawn_props()
	_spawn_player()
	_spawn_npcs()
	_spawn_pickups()
	_spawn_triggers()
	_setup_camera()
	_setup_light()


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	return d


func _spawn_props() -> void:
	for p in model.props:
		var key: String = p["type"]
		var meta: Dictionary = _props_meta.get(key, {})
		var tex := load("res://art/props/%s.png" % key)
		if tex == null:
			continue
		var s := Sprite2D.new()
		s.texture = tex
		var fr: int = int(meta.get("frames", 1))
		s.hframes = fr
		var w: float = float(meta.get("w", 16))
		var h: float = float(meta.get("h", 16))
		var tx: int = int(p["at"][0]); var ty: int = int(p["at"][1])
		# anchor: bottom-left tile of footprint → centre the sprite over it
		var cx: float = (tx + float(meta.get("w_tiles", 1)) * 0.5) * TILE
		var cy: float = (ty + 1) * TILE
		s.position = Vector2(cx, cy - h * 0.5)
		s.z_index = 0
		_ys.add_child(s)
		if fr > 1:
			var t := Timer.new()
			t.wait_time = 0.35
			t.autostart = true
			t.timeout.connect(func(): s.frame = (s.frame + 1) % fr)
			add_child(t)


func _spawn_player() -> void:
	player = Player.new()
	var sp := model.nearest_open(model.spawn)
	player.global_position = Vector2(sp.x * TILE + TILE * 0.5, (sp.y + 1) * TILE - 2)
	player.setup(model, "pilgrim")
	_ys.add_child(player)


func _spawn_npcs() -> void:
	for nd in model.npcs:
		var n := Npc.new()
		# player / dialogue / set_paused are injected so Npc never needs a typed
		# reference back to Region — that reference was a class_name cycle.
		n.setup(model, nd, player, dialogue, set_paused)
		_ys.add_child(n)
		npcs.append(n)


## Add one person after load. Saul is not standing in the camp when the chapter
## opens — he arrives when the story does, which is also how a campaign adds a
## character without editing the map.
func spawn_npc(d: Dictionary) -> Npc:
	var n := Npc.new()
	n.setup(model, d, player, dialogue, set_paused)
	_ys.add_child(n)
	npcs.append(n)
	return n


func _spawn_pickups() -> void:
	for it in model.items:
		spawn_pickup(str(it["id"]), str(it.get("kind", "item")), str(it.get("sprite", "rock")),
			int(it["at"][0]), int(it["at"][1]), it)


## Add one pickup to the world after load. The David act lays out the provisions
## in his father's hand this way — they belong to a scene that has not happened
## yet when the valley is first built.
func spawn_pickup(id: String, kind: String, sprite: String, tx: int, ty: int,
		extra: Dictionary = {}) -> void:
	var node := Node2D.new()
	node.global_position = Vector2(tx * TILE + 8, ty * TILE + 12)
	var tex := load("res://art/props/%s.png" % sprite)
	if tex != null:
		var sp := Sprite2D.new()
		sp.texture = tex
		sp.scale = Vector2(0.85, 0.85)
		node.add_child(sp)
	_ys.add_child(node)
	pickups.append({"id": id, "kind": kind, "node": node,
		"got": false, "ref": extra.get("ref", ""), "data": extra})


func _spawn_triggers() -> void:
	for td in model.triggers:
		var d: Dictionary = td
		triggers.append({
			"id": str(d.get("id", "")),
			"kind": str(d.get("kind", "")),
			"data": d,
			"spent": false,
			"armed": true,
		})


func _setup_camera() -> void:
	cam = CameraRig.new()
	add_child(cam)
	cam.bounds = Rect2(0, 0, model.width * TILE, model.height * TILE)
	cam.set_follow(player)


func _setup_light() -> void:
	_mod = CanvasModulate.new()
	add_child(_mod)
	_apply_time(GameState.data.get("time_of_day", "morning"))


func _apply_time(tod: String) -> void:
	var col := Color(1, 1, 1)
	match tod:
		"dawn":    col = Color(0.85, 0.75, 0.72)
		"morning": col = Color(1.0, 0.98, 0.92)
		"noon":    col = Color(1.0, 1.0, 0.98)
		"dusk":    col = Color(0.80, 0.62, 0.55)
		"night":   col = Color(0.35, 0.40, 0.55)
	_mod.color = col


func set_time_of_day(tod: String) -> void:
	GameState.data["time_of_day"] = tod
	_apply_time(tod)
	EventBus.time_of_day_changed.emit(tod)


# ── per-frame world simulation ──────────────────────────────────────────
func _process(delta: float) -> void:
	_mark_t += delta
	if _interact_lock > 0.0:
		_interact_lock = maxf(0.0, _interact_lock - delta)
	if _paused or model == null or player == null:
		return
	if _unclaimed():
		queue_redraw()
	_check_curios(delta)
	_check_pickups()
	_check_triggers()
	_check_exits()


func _check_pickups() -> void:
	for p in pickups:
		if p["got"]:
			continue
		var node: Node2D = p["node"]
		var d: float = (node.global_position - player.global_position).length()
		if d < PICK_RANGE:
			p["got"] = true
			p["node"].queue_free()
			pickup_taken.emit(p["id"])
			EventBus.item_picked_up.emit(p["id"])


## Standing somewhere quietly is allowed to be interesting. Each curio fires
## once and never again, and nothing depends on it.
func _check_curios(delta: float) -> void:
	_curio_cool = maxf(0.0, _curio_cool - delta)
	if _curio_cool > 0.0:
		return
	for c in model.curios:
		var id := str(c.get("id", ""))
		if id == "" or _curio_done.has(id):
			continue
		if bool(GameState.flag("curio_" + id)):
			_curio_done[id] = true
			continue
		var at: Array = c.get("at", [0, 0])
		var p := Vector2(int(at[0]) * TILE + 8, int(at[1]) * TILE + 8)
		if p.distance_to(player.global_position) <= float(c.get("r", 2)) * TILE:
			_curio_done[id] = true
			_curio_cool = 1.0
			GameState.set_flag("curio_" + id, true)
			curio_seen.emit(id, c.get("lines", []))
			return


func _check_triggers() -> void:
	for t in triggers:
		if bool(t["spent"]):
			continue
		if _trigger_hit(t):
			# Edge-triggered, not level-triggered: fire on ENTERING the area.
			# A beat that sends you back (five stones missing) has to be able to
			# happen again once you have gone and got them, and a beat that has
			# played must not replay every frame you stand inside it.
			if bool(t["armed"]):
				t["armed"] = false
				if bool(t["data"].get("once", false)):
					t["spent"] = true
				trigger_fired.emit(str(t["id"]))
		else:
			# Re-arm only once the player has genuinely LEFT the area. A beat
			# that pushes you back a few tiles while your thumb is still
			# pressing north re-fires the instant you arrive, and the player
			# reads an endless wall of the same two lines as a soft-lock
			# (playtest 4). `rearm_row` names how far out you must be.
			var td: Dictionary = t["data"]
			var rr := int(td.get("rearm_row", -99999))
			if rr != -99999:
				var py := int(floor(player.global_position.y / TILE))
				if py < rr:
					continue
			t["armed"] = true


func _trigger_hit(t: Dictionary) -> bool:
	var d: Dictionary = t["data"]
	var px := int(floor(player.global_position.x / TILE))
	var py := int(floor(player.global_position.y / TILE))
	match d.get("kind", ""):
		"row":      return py <= int(d["row"])
		"row_above": return py < int(d["row"])
		"tile":     return px == int(d["at"][0]) and py == int(d["at"][1])
		"radius":
			var c := Vector2(int(d["at"][0]) * TILE + 8, int(d["at"][1]) * TILE + 8)
			return (c - player.global_position).length() < float(d.get("r", 2)) * TILE
	return false


func _check_exits() -> void:
	for e in model.exits:
		var c := Vector2(int(e["at"][0]) * TILE + 8, int(e["at"][1]) * TILE + 8)
		if (c - player.global_position).length() < TILE * 0.8:
			if Input.is_action_just_pressed("interact"):
				exit_taken.emit(e["to"])


# ── interaction ─────────────────────────────────────────────────────────
## The single interact query: nearest NPC in range and roughly in front.
## Returns Npc, not Variant: a Variant return makes every `var x := call()`
## at the call site an ERROR-level inference in Godot 4.7.
func nearest_interactable() -> Npc:
	# Two passes: someone standing still first, an escort second. Corin follows
	# you for the whole chapter, so with one pass he was always the nearest
	# person and the A button re-opened him instead of the villager you had
	# walked up to.
	for pass_ in range(2):
		var best: Npc = null
		var bd := TALK_RANGE
		for n in npcs:
			if (pass_ == 0) == (n.state == Npc.State.FOLLOW):
				continue
			var d := (n.global_position - player.global_position).length()
			if d < bd:
				bd = d; best = n
		if best != null:
			return best
	return null


func _unhandled_input(event: InputEvent) -> void:
	if _paused or _interact_lock > 0.0:
		return
	if event.is_action_pressed("interact"):
		var n := nearest_interactable()
		if n != null:
			player.face_toward(n.global_position)
			n.talk()
			get_viewport().set_input_as_handled()


## True while any pickup is still out there. Drives the marker redraw.
func _unclaimed() -> bool:
	for it in pickups:
		if not bool(it.get("got", false)):
			return true
	return false


## Put the camera where the player is, with no glide. Used after a story
## teleport (David's errand begins in Bethlehem, not at the line).
func snap_camera() -> void:
	if cam != null and player != null:
		cam.set_follow(player)


## Markers over unclaimed pickups: a gold chevron for quest items, a pale one
## for stones. Playtest 8: "the required item cannot be seen on the map" — the
## sprite is 10 px on grass, so it needs to announce itself.
func _draw() -> void:
	for it in pickups:
		if bool(it.get("got", false)):
			continue
		var node: Node2D = it["node"]
		if not is_instance_valid(node):
			continue
		var p := node.global_position
		var bob := sin(_mark_t * 2.6 + p.x * 0.11) * 1.5
		var quest: bool = str(it.get("kind", "")) != "stone"
		var col := Color(0.98, 0.86, 0.55, 0.95) if quest else Color(0.80, 0.92, 0.96, 0.9)
		# a faint ring on the ground, so the item reads as "stand here"
		draw_arc(p + Vector2(0, 4), 5.0, 0.0, TAU, 14, Color(col, col.a * 0.45), 1.0)
		var ty := p.y - 13.0 + bob
		var pts := PackedVector2Array()
		pts.append(Vector2(p.x - 3, ty))
		pts.append(Vector2(p.x + 3, ty))
		pts.append(Vector2(p.x, ty + 4))
		draw_colored_polygon(pts, col)


func is_paused() -> bool:
	return _paused


func set_paused(v: bool) -> void:
	_paused = v
	if player:
		player.set_process(!v)
		player.set_physics_process(!v)
	for n in npcs:
		n.set_physics_process(!v)
