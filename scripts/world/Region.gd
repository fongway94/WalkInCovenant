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

@export var region_id := "elah"

var model: RegionModel = null
var terrain: TerrainLayer = null
var player: Player = null
var cam: CameraRig = null
var npcs: Array = []            # Npc nodes
var pickups: Array = []         # {id, kind, node, got}
var triggers: Array = []        # {id, kind, data, fired}
var dialogue: DialogueBox = null

var _ys: Node2D = null
var _mod: CanvasModulate = null
var _props_meta: Dictionary = {}
var _tiles_meta: Dictionary = {}
var _paused := false

signal region_ready
signal pickup_taken(id: String)
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

	_ys = Node2D.new()
	_ys.y_sort_enabled = true
	add_child(_ys)

	_spawn_props()
	_spawn_player()
	_spawn_npcs()
	_spawn_pickups()
	_setup_camera()
	_setup_light()

	dialogue = DialogueBox.new()
	add_child(dialogue)
	dialogue.hide_box()


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
		n.setup(model, nd, self)
		_ys.add_child(n)
		npcs.append(n)


func _spawn_pickups() -> void:
	for it in model.items:
		var node := Node2D.new()
		node.global_position = Vector2(int(it["at"][0]) * TILE + 8, int(it["at"][1]) * TILE + 12)
		var tex := load("res://art/props/%s.png" % it.get("sprite", "rock"))
		if tex != null:
			var s := Sprite2D.new()
			s.texture = tex
			s.scale = Vector2(0.6, 0.6)
			node.add_child(s)
		_ys.add_child(node)
		pickups.append({"id": it["id"], "kind": it.get("kind", "item"), "node": node,
			"got": false, "ref": it.get("ref", ""), "data": it})


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
func _process(_delta: float) -> void:
	if _paused or model == null or player == null:
		return
	_check_pickups()
	_check_triggers()
	_check_exits()


func _check_pickups() -> void:
	for p in pickups:
		if p["got"]:
			continue
		var d := (p["node"].global_position - player.global_position).length()
		if d < PICK_RANGE:
			p["got"] = true
			p["node"].queue_free()
			pickup_taken.emit(p["id"])
			EventBus.item_picked_up.emit(p["id"])


func _check_triggers() -> void:
	for t in triggers:
		if t["fired"]:
			continue
		if _trigger_hit(t):
			t["fired"] = true
			trigger_fired.emit(t["id"])


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
func nearest_interactable() -> Variant:
	var best: Variant = null
	var bd := TALK_RANGE
	for n in npcs:
		var d := (n.global_position - player.global_position).length()
		if d < bd:
			bd = d; best = n
	return best


func _unhandled_input(event: InputEvent) -> void:
	if _paused:
		return
	if event.is_action_pressed("interact"):
		var n := nearest_interactable()
		if n != null:
			player.face_toward(n.global_position)
			n.talk()
			get_viewport().set_input_as_handled()


func set_paused(v: bool) -> void:
	_paused = v
	if player:
		player.set_process(!v)
		player.set_physics_process(!v)
	for n in npcs:
		n.set_physics_process(!v)
