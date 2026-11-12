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
## A sheep is a moving animal, not a coin on a tile. Its catch radius is wider
## so the wandering never turns "stand here" into "chase it". The authored tile
## stays the place the objective points at (docs/ART_DIRECTION.md §3).
const FLOCK_PICK_RANGE := 26.0
const TALK_RANGE := 22.0
## Props that breathe. One pixel, slow, phase-offset per instance; frozen while
## a dialogue box owns the picture. No marker, no reward, no gameplay meaning.
const SWAY_KEYS := ["wheat_sheaf", "bush", "wool_tuft"]
## Painted props may have a higher-resolution canvas or a larger visual than
## their legacy sheet. These are visual scales only; collision still comes from
## data/props.json. Every sprite is bottom anchored at its original map tile.
const PAINTED_PROP_SCALE := {
	"tent": 0.90, "jar": 0.72, "well": 1.25,
	"fire": 0.50, "altar_stones": 0.50, "fold": 0.50,
	"trough": 0.50, "staff": 0.50, "wheat_sheaf": 0.50,
	"bush": 0.50, "wool_tuft": 0.50, "signpost": 0.50,
	"sheep": 0.50, "sheep_graze": 0.50, "sheep_alert": 0.50,
}
## Anything within this radius of an exit tile can be left through it.
const EXIT_RANGE := 13.0
## How long after a box closes the A button is ignored. Long enough to swallow
## the tap that closed it (one tap can arrive as a touch AND an action), short
## enough that nobody waiting to talk again ever notices.
const INTERACT_LOCK := 0.35

@export var region_id := "elah"
## Where the player came from, when this region was entered by travelling. Empty
## on a cold boot. The exit that points back decides where they stand.
var from_region := ""

var model: RegionModel = null
var terrain: TerrainLayer = null
var player: Player = null
var cam: CameraRig = null
# Typed on purpose. With a plain Array, `for n in npcs` yields a Variant, so
# `var d := (n.global_position - ...).length()` infers from a Variant — which is
# an ERROR-level warning in Godot 4.7 and stops the script compiling.
var npcs: Array[Npc] = []
var pickups: Array = []         # {id, kind, node, got}
## Optional object/discovery interactions share the same resolver as sheep,
## people and exits. Registrations are scoped to this region instance.
var context_targets: Array = []
var triggers: Array = []        # {id, kind, data, spent, armed}
var dialogue: DialogueBox = null
## Kept so a cinematic can frame him, and so a test can see that he is on screen.
var goliath_sprite: Sprite2D = null

var _ys: Node2D = null
var _shadow_layer: Node2D = null
var _rim_layer: Node2D = null
## {sprite: Sprite2D, key: String} — kept so the opt-in art direction can swap
## prop textures without rebuilding the world (which would drop quest state).
var _prop_sprites: Array = []
var _mod: CanvasModulate = null
## The opt-in B scene gets its own golden-hour daylight tint. GameState's
## time_of_day, save data and story beats are untouched; this is a visual theme.
var _art_theme := "classic"
var _props_meta: Dictionary = {}
var _tiles_meta: Dictionary = {}
var _paused := false
## The chapter's act, pushed down by `Main` every frame. An NPC does not know
## what an act is, but a person in a camp does know what is happening in it, and
## this is the one word it needs to say the right thing (`Npc._lines_now()`).
var act_name := ""
var _interact_lock := 0.0
var _mark_t := 0.0
var _curio_done := {}
var _curio_cool := 0.0
## {sprite, x, y, phase} — ambient sway, updated once a frame in _process.
var _swayers: Array = []
var _sway_t := 0.0
## The painted field is temporary scene dressing around the real production
## Region. Null outside the shepherd act; no save schema changes.
var shepherd_field = null
var _field_npcs: Array = []
var _field_camera_bounds := Rect2()
var _field_camera_zoom := Vector2.ONE
var _field_magnet := 0.0
var _field_giant_visible := false

signal region_ready
signal pickup_taken(id: String)
## A stray noticed (or was driven by) the player. Main decides the one line of
## context feedback; Region owns no prose.
signal flock_reacted(id: String, mood: int)
signal curio_seen(id: String, lines: Array)
signal trigger_fired(id: String)
signal exit_taken(to: String)


func _ready() -> void:
	_load_meta()
	_build()
	# A field is a finite painting. Refit on browser resize or device rotation,
	# while the camera's regular bounds still govern the tile-world regions.
	get_viewport().size_changed.connect(_fit_field_camera)
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

	# Ground shade belongs BETWEEN the tiles and the y-sorted sprites. It is
	# disabled in the classic build; apply_art_theme() enables it for the one
	# integrated scene (docs/ART-RESET.md §6).
	_shadow_layer = load("res://scripts/world/ContactShadowLayer.gd").new()
	add_child(_shadow_layer)

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

	# Direction B's rim light sits AFTER the y-sorted sprites but BEFORE the
	# CanvasLayer UI. It shares the shadow layer's live target array, so every
	# walking figure keeps its highlight and shadow in the same light.
	_rim_layer = load("res://scripts/world/GoldenRimLayer.gd").new()
	add_child(_rim_layer)
	var shadow_targets = _shadow_layer.get("targets")
	_rim_layer.call("set_targets", shadow_targets)

	_spawn_props()
	_spawn_goliath()
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


## The same selection must be used for map props and items spawned later by a
## mission. Each painted image keeps the source prop's canvas and footprint.
func _prop_texture_path(key: String, theme: String) -> String:
	var chosen := "res://art/props/%s.png" % key
	var crafted := "res://art/props_%s/%s.png" % [theme, key]
	var painted := "res://art/props_painted/%s.png" % key
	if (theme == "storybook" or theme == "cinematic") and ResourceLoader.exists(crafted):
		chosen = crafted
	if theme == "cinematic" and ResourceLoader.exists(painted):
		chosen = painted
	return chosen


func _prop_visual_scale(key: String, theme: String, path: String) -> float:
	if theme == "cinematic" and path.begins_with("res://art/props_painted/"):
		return float(PAINTED_PROP_SCALE.get(key, 1.0)) / ArtDirection.PAINTED_PROP_DETAIL_FACTOR
	return 1.0


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
		# Y-sort at the feet, not at the image centre. Larger art can then
		# overlap the scenery naturally without moving the actual footprint.
		s.position = Vector2(cx, cy)
		s.offset = Vector2(0, -h * 0.5)
		s.z_index = 0
		_ys.add_child(s)
		_shadow_layer.call("add_target", s, w * 0.42, 2.6)
		var targets: Array = _shadow_layer.get("targets")
		_prop_sprites.append({"sprite": s, "key": key, "shadow": targets.back()})
		if SWAY_KEYS.has(key):
			_swayers.append({"sprite": s, "x": cx, "y": cy,
				"phase": float(tx) * 0.37 + float(ty) * 0.19})
		if fr > 1:
			var t := Timer.new()
			t.wait_time = 0.35
			t.autostart = true
			t.timeout.connect(func(): s.frame = (s.frame + 1) % fr)
			add_child(t)


## Keep the ridge champion independent from the ground and restore the exact
## original sheet geometry when the classic theme is selected.
func _apply_giant_theme(theme: String) -> void:
	if goliath_sprite == null or not is_instance_valid(goliath_sprite):
		return
	var s := goliath_sprite
	if theme == "cinematic":
		s.texture = load("res://art/scenes_painted/goliath.png")
		s.hframes = 1
		s.vframes = 1
		# Roughly twice the height of a painted overworld person, while its
		# node and contact shadow stay at the same original foot position.
		s.offset = Vector2(0, -64)
		s.scale = Vector2.ONE * 0.40
	else:
		s.texture = load("res://art/characters/goliath_idle.png")
		s.hframes = 2
		s.vframes = 4
		s.offset = Vector2(0, -8)
		s.scale = Vector2.ONE * 2.0
	s.frame = 0


## He is not decoration and he is not an NPC: the witness cannot reach him, and
## he has no lines to give away as verses. But he has to be VISIBLE across the
## valley, because everything the witness is told in Act I is about a man
## standing on that ridge. He used to exist only as a pair of coordinates in the
## data — "somebody is shouting over there" with nobody there to shout.
func _spawn_goliath() -> void:
	if model.goliath == Vector2i.ZERO:
		return
	# Once he has fallen, the ridge is empty. Leaving the standing sprite there
	# after the duel was a story contradiction a player could see from anywhere
	# in the valley (found while staging the aftermath frame).
	if bool(GameState.flag("goliath_down")):
		return
	var tex := load("res://art/characters/goliath_idle.png")
	if tex == null:
		return
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = true
	s.offset = Vector2(0, -8)  # node position is the middle of his feet
	# ONE frame of the sheet, not the sheet. The character PNGs are 2 columns by
	# 4 rows of 16x16 cells (idle: two frames per direction, four directions);
	# a Sprite2D with the defaults draws the entire image, so the ridge used to
	# hold eight tiny Goliaths tiled in a 2x4 block (BUG-003). Frame 0 is the
	# down-facing idle.
	s.hframes = 2
	s.vframes = 4
	s.frame = 0
	# Two tiles tall against a one-tile player: the first thing the witness
	# notices about him is the size, and it should be true on screen.
	s.scale = Vector2(2.0, 2.0)
	s.position = Vector2(model.goliath.x * TILE + 16.0, (model.goliath.y + 1) * TILE)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ys.add_child(s)
	goliath_sprite = s
	_shadow_layer.call("add_target", s, 18.0, 3.0)


## The duel's result reaches the WORLD, not just the HUD and the save. Called
## from Main._after_return(); also safe on a reload (the sprite is never
## spawned at all when the flag is already set).
func set_giant_down() -> void:
	if goliath_sprite != null and is_instance_valid(goliath_sprite):
		goliath_sprite.visible = false


func _spawn_player() -> void:
	player = Player.new()
	var sp := model.nearest_open(model.spawn)
	player.global_position = Vector2(sp.x * TILE + TILE * 0.5, (sp.y + 1) * TILE - 2)
	player.setup(model, "pilgrim")
	_ys.add_child(player)
	_shadow_layer.call("add_target", player, 12.0, 2.4)


func _spawn_npcs() -> void:
	for nd in model.npcs:
		var n := Npc.new()
		# player / dialogue / set_paused are injected so Npc never needs a typed
		# reference back to Region — that reference was a class_name cycle.
		n.setup(model, nd, player, dialogue, set_paused)
		_ys.add_child(n)
		npcs.append(n)
		_shadow_layer.call("add_target", n, 12.0, 2.4)


## Add one person after load. Saul is not standing in the camp when the chapter
## opens — he arrives when the story does, which is also how a campaign adds a
## character without editing the map.
func spawn_npc(d: Dictionary) -> Npc:
	var n := Npc.new()
	n.setup(model, d, player, dialogue, set_paused)
	_ys.add_child(n)
	npcs.append(n)
	_shadow_layer.call("add_target", n, 12.0, 2.4)
	n.apply_art_theme(_art_theme)
	return n


func _spawn_pickups() -> void:
	for it in model.items:
		spawn_pickup(str(it["id"]), str(it.get("kind", "item")), str(it.get("sprite", "rock")),
			int(it["at"][0]), int(it["at"][1]), it)


## Add one pickup to the world after load. The David act lays out the provisions
## in his father's hand this way — they belong to a scene that has not happened
## yet when the valley is first built.
## The save key for "this region's copy of this item has been picked up".
## Region-scoped, like an NPC's `talked:` key, so two stories can both have bread
## (BUG-018).
static func pickup_key(rid: String, id: String) -> String:
	return "pickup:%s:%s" % [rid, id]


func spawn_pickup(id: String, kind: String, sprite: String, tx: int, ty: int,
		extra: Dictionary = {}) -> void:
	# An item that is already in the bag must not be lying on the ground again.
	# Without this, every reload put the provisions back and the errand's count
	# could be collected twice (BUG-018).
	if bool(GameState.flag(pickup_key(str(model.id), id))):
		return
	var node: Node2D
	if kind == "flock":
		# The stray is a live animal: it grazes, notices the player and can be
		# driven toward the hurdle. All of that is the sheep's own state; Region
		# keeps the one door into story progress (collect_pickup).
		var fs := FlockSheep.new()
		fs.setup(id, [tx, ty], extra.get("fold", [24, 34]),
			str(extra.get("temper", "calm")), player, self)
		fs.reacted.connect(_on_sheep_reacted)
		fs.arrived.connect(_on_sheep_arrived)
		if shepherd_field != null:
			fs.apply_shepherd_field(shepherd_field.stray_position(id),
				shepherd_field.world(shepherd_field.FOLD), pickups.size(),
				Callable(shepherd_field, "walkable"), Callable(shepherd_field, "sheep_route"))
			node = fs
			fs.z_index = shepherd_field.depth_at(fs.global_position)
		else:
			fs.apply_art_theme(_art_theme)
			node = fs
	else:
		node = Node2D.new()
		node.global_position = Vector2(tx * TILE + 8, ty * TILE + 12)
		var path := _prop_texture_path(sprite, _art_theme)
		var tex := load(path)
		if tex != null:
			var sp := Sprite2D.new()
			sp.texture = tex
			sp.scale = Vector2.ONE * (0.85 * _prop_visual_scale(sprite, _art_theme, path))
			node.add_child(sp)
	_ys.add_child(node)
	var shadow_width := 12.0 if kind == "flock" and shepherd_field != null else 10.0
	_shadow_layer.call("add_target", node, shadow_width, 2.0)
	var catch_range := PICK_RANGE
	if kind == "flock":
		catch_range = FLOCK_PICK_RANGE
	pickups.append({"id": id, "kind": kind, "node": node, "got": false,
			"guided": false, "range": catch_range, "sprite_key": sprite,
			"field_flock": kind == "flock" and shepherd_field != null,
			"ref": extra.get("ref", ""), "data": extra})


func _on_sheep_reacted(id: String, mood: int) -> void:
	flock_reacted.emit(id, mood)


func _on_sheep_arrived(id: String, guided: bool) -> void:
	collect_pickup(id, guided)


## The ONE door into "this is in the fold". Both walking up to a sheep and
## driving it all the way home arrive here, so the pickup flag, the HUD and the
## save can never disagree about how many sheep are in.
func collect_pickup(id: String, guided: bool = false) -> void:
	for p in pickups:
		if str(p.get("id", "")) != id or bool(p.get("got", false)):
			continue
		p["got"] = true
		p["guided"] = guided
		GameState.set_flag(pickup_key(str(model.id), id), true)
		var node: Node2D = p.get("node")
		if node != null and node.has_method("go_home"):
			node.call("go_home")
		elif node != null:
			node.queue_free()
		pickup_taken.emit(id)
		EventBus.item_picked_up.emit(id)
		return


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
	# The shepherd chapter is literally "before dark", and the classic dusk
	# modulate (0.80, 0.62, 0.55) made the B meadow read as night. Direction B
	# keeps the story's dusk but lets the low golden sun reach the field.
	if _art_theme == "cinematic" and tod == "dusk":
		col = Color(1.0, 0.90, 0.74)
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
	if not _paused:
		_sway_t += delta
		for s in _swayers:
			var d: Dictionary = s
			var sp: Sprite2D = d["sprite"]
			var ph := float(d["phase"])
			sp.position = Vector2(float(d["x"]) + sin(_sway_t * 0.9 + ph) * 0.8,
				float(d["y"]) + cos(_sway_t * 0.63 + ph) * 0.4)
	if _paused or model == null or player == null:
		return
	# A conversation owns the world. Nothing in here may fire under an open box:
	# a trigger used to open its scene ON TOP of whatever was already speaking
	# (replacing the box under the player's finger — the reported "the dialogue
	# appears three times"), and a curio used to set its "seen" flag and then be
	# dropped by Main because a box was open, so that place never spoke again
	# (BUG-013). Returning here leaves every trigger ARMED, so the beat plays the
	# moment the box closes instead of being eaten.
	if dialogue != null and dialogue.is_open():
		return
	queue_redraw()
	if shepherd_field != null:
		_update_field_depth()
	_check_curios(delta)
	_check_pickups()
	# The painted field is a distinct place; the valley's line triggers cannot
	# fire at coincident tile coordinates behind its backdrop.
	if shepherd_field == null:
		_check_triggers()


func _check_pickups() -> void:
	for p in pickups:
		if p["got"] or str(p.get("kind", "")) == "flock":
			# Sheep require a deliberate action, or may reach the fold by herding.
			# Other established quest pickups keep their original walk-over rule.
			continue
		var node: Node2D = p["node"]
		if not is_instance_valid(node):
			continue
		var d: float = node.global_position.distance_to(player.global_position)
		if d < float(p.get("range", PICK_RANGE)):
			collect_pickup(str(p["id"]))


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
		var radius := float(c.get("r", 2)) * TILE
		if shepherd_field != null:
			if id != "lions_ground":
				continue
			p = shepherd_field.world(shepherd_field.HURDLE_MEMORY)
			radius = 12.0
		if p.distance_to(player.global_position) <= radius:
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


## An exit the player is standing on, or empty. Movement used to be polled with
## Input.is_action_just_pressed() inside _process — a second, parallel input path
## that bypassed the action events every other system listens to (AUDIT B7).
## The tile a player arriving from `from_region` stands on: the region's own
## exit that points back where they came from, stepped one tile inland so the
## first thing under their feet is not the way home. Falls back to the spawn.
func entry_tile() -> Array:
	if from_region != "":
		for e in model.exits:
			if str(e.get("to", "")) != from_region:
				continue
			var at: Array = e.get("at", [])
			if at.size() != 2:
				continue
			var t := Vector2i(int(at[0]), int(at[1]))
			var mid := Vector2i(model.width / 2, model.height / 2)
			# One tile inland, toward the middle of the map. The first candidate
			# used to be `t + (0,0)` when the exit sat on the map's centre column,
			# which put the player straight back onto the way they came in.
			var dx := signi(mid.x - t.x)
			var dy := signi(mid.y - t.y)
			var tries: Array = []
			if dx != 0:
				tries.append(t + Vector2i(dx, 0))
			if dy != 0:
				tries.append(t + Vector2i(0, dy))
			if dx != 0:
				tries.append(t + Vector2i(-dx, 0))
			if dy != 0:
				tries.append(t + Vector2i(0, -dy))
			# A dead-centre exit (both deltas zero) steps north first, then south.
			if tries.is_empty():
				tries = [t + Vector2i(0, -1), t + Vector2i(0, 1), t + Vector2i(1, 0), t + Vector2i(-1, 0)]
			for c in tries:
				if c.x >= 0 and c.y >= 0 and c.x < model.width and c.y < model.height \
						and not model.solid_at_tile(c.x, c.y):
					return [c.x, c.y]
			return [t.x, t.y]
	return [model.spawn.x, model.spawn.y]


func _near_exit() -> Dictionary:
	if model == null or player == null:
		return {}
	for e in model.exits:
		var c := Vector2(int(e["at"][0]) * TILE + 8, int(e["at"][1]) * TILE + 8)
		if (c - player.global_position).length() < EXIT_RANGE:
			return e
	return {}


# ── interaction ─────────────────────────────────────────────────────────
## A scene may register an object or discovery without adding another input
## handler. `available` is optional; stale/freed nodes are ignored automatically.
## The callback must own its own one-shot/save state, just like collect_pickup.
func register_context_target(node: Node2D, id: String, label: Dictionary,
		radius: float, action: Callable, available: Callable = Callable()) -> void:
	context_targets.append({"node": node, "id": id, "label": label,
		"radius": radius, "action": action, "available": available})


## The same closest valid target drives the highlight, HUD and input. This is a
## fresh query, not a cached node: a sheep may move or leave between frames.
## Distances are measured from feet. Strict < gives deterministic ties.
func context_target() -> Dictionary:
	if _paused or model == null or player == null \
			or (dialogue != null and dialogue.is_open()):
		return {}
	var best: Dictionary = {}
	var best_distance := INF
	for it in pickups:
		var p: Dictionary = it
		if str(p.get("kind", "")) != "flock" or bool(p.get("got", false)):
			continue
		var node: Node2D = p.get("node")
		if not is_instance_valid(node) or not node.visible:
			continue
		var d := node.global_position.distance_to(player.global_position)
		if d < best_distance and node.has_method("wants_catch") \
				and bool(node.call("wants_catch", d, float(p.get("range", FLOCK_PICK_RANGE)))):
			best_distance = d
			best = {"kind": "flock", "id": str(p["id"]), "node": node,
				"position": node.global_position,
				"label": {"zh": "数羊", "en": "Count Sheep"}}
	for n in npcs:
		if not is_instance_valid(n) or not n.visible or not n.can_talk():
			continue
		var d := n.global_position.distance_to(player.global_position)
		if d < TALK_RANGE and d < best_distance:
			best_distance = d
			best = {"kind": "npc", "id": n.npc_id(), "node": n,
				"position": n.global_position, "label": {"zh": "交谈", "en": "Talk"}}
	if shepherd_field == null:
		for e in model.exits:
			var at: Array = e.get("at", [])
			if at.size() != 2:
				continue
			var point := Vector2(float(at[0]) * TILE + 8.0, float(at[1]) * TILE + 8.0)
			var d := point.distance_to(player.global_position)
			if d < EXIT_RANGE and d < best_distance:
				best_distance = d
				best = {"kind": "exit", "id": str(e.get("to", "")), "position": point,
					"label": {"zh": "出发", "en": "Travel"}}
	for entry in context_targets:
		var c: Dictionary = entry
		var node: Node2D = c.get("node")
		if not is_instance_valid(node) or not node.visible:
			continue
		var available: Callable = c.get("available", Callable())
		if available.is_valid() and not bool(available.call()):
			continue
		var action: Callable = c.get("action", Callable())
		if not action.is_valid():
			continue
		var d := node.global_position.distance_to(player.global_position)
		if d < float(c.get("radius", 0.0)) and d < best_distance:
			best_distance = d
			best = {"kind": "context", "id": str(c.get("id", "")), "node": node,
				"position": node.global_position, "label": c.get("label", {}), "action": action}
	return best


func context_prompt() -> String:
	var target := context_target()
	if target.is_empty():
		return ""
	return "A / Z  ·  %s" % I18n.t(target.get("label", {}))


## Compatibility helper for callers that need a person specifically. Unlike
## the old two-pass escort preference, this returns the genuinely nearest
## available person; the shared target query above also considers other kinds.
func nearest_interactable() -> Npc:
	var best: Npc = null
	var bd := TALK_RANGE
	for n in npcs:
		if not is_instance_valid(n) or not n.visible or not n.can_talk():
			continue
		var d := n.global_position.distance_to(player.global_position)
		if d < bd:
			bd = d
			best = n
	return best


func _unhandled_input(event: InputEvent) -> void:
	if _paused or _interact_lock > 0.0 or not event.is_action_pressed("interact"):
		return
	var target := context_target()
	if target.is_empty() or not TapGate.take():
		return
	match str(target.get("kind", "")):
		"flock":
			var animal: Node2D = target.get("node")
			player.face_toward(animal.global_position)
			# A button press is a deliberate count/carry; only an animal that
			# arrives on its own is marked guided by _on_sheep_arrived.
			AudioDirector.play_sfx("sheep", -12.0)
			collect_pickup(str(target.get("id", "")), false)
		"npc":
			var n: Npc = target.get("node")
			player.face_toward(n.global_position)
			n.talk()
		"exit":
			exit_taken.emit(str(target.get("id", "")))
		"context":
			var action: Callable = target.get("action", Callable())
			action.call()
	get_viewport().set_input_as_handled()


## True while any pickup is still out there. Drives the marker redraw.
func _unclaimed() -> bool:
	for it in pickups:
		if not bool(it.get("got", false)):
			return true
	return false


## Put the camera where the player is, with no glide. Used after a story
## teleport (David's errand begins in Bethlehem, not at the line).
## A scripted shot. The camera holds a point while the box speaks, then comes
## back to the player — used for the witness's first look at Goliath.
func pan_to(world: Vector2, secs: float) -> void:
	if cam != null:
		cam.pan_to(world, secs)


func follow_player(secs: float = 0.7) -> void:
	if cam != null:
		cam.resume_follow(secs)


func snap_camera() -> void:
	if cam != null and player != null:
		cam.set_follow(player)


## Markers over unclaimed pickups: a gold chevron for quest items, a pale one
## for stones. Playtest 8: "the required item cannot be seen on the map" — the
## sprite is 10 px on grass, so it needs to announce itself.
func _draw() -> void:
	# A broken ring and a chevron provide shape as well as colour. Only the
	# current target is selected; unselected sheep have no quest-dot clutter.
	var target := context_target()
	if not target.is_empty():
		var pos: Vector2 = target.get("position", Vector2.ZERO)
		var col := Color(1.0, 0.93, 0.72, 0.92)
		draw_arc(pos + Vector2(0, 2), 8.0, 0.15, PI - 0.15, 18, Color(col, 0.85), 1.2)
		draw_arc(pos + Vector2(0, 2), 8.0, PI + 0.15, TAU - 0.15, 18, Color(col, 0.5), 1.0)
		var target_node = target.get("node")
		var mark_height := 24.0 if str(target.get("kind", "")) == "flock" else 23.0
		if target_node is Npc:
			mark_height = target_node.visual_height() + 7.0
		var mark_y := pos.y - mark_height
		var chevron := PackedVector2Array()
		chevron.append(Vector2(pos.x - 3.0, mark_y))
		chevron.append(Vector2(pos.x, mark_y + 3.0))
		chevron.append(Vector2(pos.x + 3.0, mark_y))
		draw_polyline(chevron, col, 1.2)
	for it in pickups:
		if bool(it.get("got", false)) or str(it.get("kind", "")) == "flock":
			continue
		var node: Node2D = it["node"]
		if not is_instance_valid(node):
			continue
		var p := node.global_position
		var bob := sin(_mark_t * 2.6 + p.x * 0.11) * 1.5
		var kind := str(it.get("kind", ""))
		# Gold says "fetch this". Pale wool says "this is an animal, walk it
		# home". The distinction is the objective, drawn rather than explained.
		var col := Color(0.80, 0.92, 0.96, 0.9)
		if kind == "flock":
			col = Color(0.94, 0.92, 0.80, 0.95)
		elif kind != "stone":
			col = Color(0.98, 0.86, 0.55, 0.95)
		# a faint ring on the ground, so the item reads as "stand here"
		draw_arc(p + Vector2(0, 4), 5.0, 0.0, TAU, 14, Color(col, col.a * 0.45), 1.0)
		var ty := p.y - 13.0 + bob
		var pts := PackedVector2Array()
		pts.append(Vector2(p.x - 3, ty))
		pts.append(Vector2(p.x + 3, ty))
		pts.append(Vector2(p.x, ty + 4))
		draw_colored_polygon(pts, col)


## Cheap and idempotent: Main calls it every frame, and nothing downstream has
## to poll or unsubscribe.
func set_act(a: String) -> void:
	if a == act_name:
		return
	act_name = a
	for n in npcs:
		var npc: Npc = n
		npc.act_name = a


## Opt-in art direction for the ART DIRECTION RESET prototype. The classic atlas
## AND the classic props/sprites stay the default. The storybook (Direction C)
## and cinematic (user-selected Direction B) atlases have the SAME 16px cells,
## the SAME 49 indices and the SAME data/tiles.json, so collision, footstep
## surfaces, the water animation and every save file are untouched by the swap.
## Everything below is a TEXTURE / DRAW layer only.
##
## §6 of docs/ART-RESET.md demanded real craft, not another palette: the second
## pass adds hand-authored silhouettes, one shared contact-shadow light, and
## far/middle/near value planes drawn inside the terrain canvas. §12.7 adds B's
## golden-hour depth, animated rim light and long cast shadows.
func apply_art_theme(theme: String) -> void:
	if terrain == null or model == null:
		return
	_art_theme = theme
	# Re-evaluate the current time-of-day tint under the new theme; classic and
	# storybook restore their original daylight exactly.
	if _mod != null:
		_apply_time(str(GameState.data.get("time_of_day", "morning")))
	var themed := theme == "storybook" or theme == "cinematic"
	var path := "res://art/tiles/terrain.png"
	if themed:
		path = "res://art/tiles/terrain_%s.png" % theme
	var tex := load(path) as Texture2D
	if tex != null:
		terrain.setup(model, tex, int(_tiles_meta.get("columns", 16)))
	terrain.set_depth_mode(theme if themed else "none")
	var painted := "res://art/scenes_painted/world_%s.png" % region_id
	if theme == "cinematic" and ResourceLoader.exists(painted):
		terrain.set_painted_ground(load(painted) as Texture2D)
	else:
		terrain.set_painted_ground(null)
	_apply_giant_theme(theme)
	# A prop's texture and visual scale are reversible. Its bottom stays on
	# the original tile, and its shadow follows its displayed width.
	for p in _prop_sprites:
		var d: Dictionary = p
		var s: Sprite2D = d["sprite"]
		var key: String = d["key"]
		var prop_path := _prop_texture_path(key, theme)
		var pt := load(prop_path) as Texture2D
		if pt != null:
			s.texture = pt
			var visual_scale := _prop_visual_scale(key, theme, prop_path)
			s.scale = Vector2.ONE * visual_scale
			s.offset = Vector2(0, -float(pt.get_height()) / float(s.vframes) * 0.5)
			var shadow: Dictionary = d["shadow"]
			shadow["w"] = float(pt.get_width()) / float(s.hframes) * visual_scale * 0.42
	# The two actors in this scene have crafted 16px sheets. Other actors keep
	# their classic sheets (their own apply_art_theme checks for both files).
	if player != null and is_instance_valid(player):
		player.apply_art_theme(theme)
	for n in npcs:
		var npc: Npc = n
		npc.apply_art_theme(theme)
	# The three live sheep and any uncollected ground items are part of the
	# same picture; swap their textures too, without touching their state.
	for it in pickups:
		var p: Dictionary = it
		# Collected pickups remain as records after their nodes are freed. Check
		# the untyped reference before assigning it to a typed Node2D; assigning
		# a previously freed object itself raises a runtime error in Godot.
		var node = p.get("node")
		if not is_instance_valid(node):
			continue
		if node.has_method("apply_art_theme"):
			if shepherd_field == null or str(p.get("kind", "")) != "flock":
				node.call("apply_art_theme", theme)
		else:
			var key := str(p.get("sprite_key", "rock"))
			var chosen := _prop_texture_path(key, theme)
			for c in node.get_children():
				if c is Sprite2D:
					var sp: Sprite2D = c
					sp.texture = load(chosen)
					sp.scale = Vector2.ONE * (0.85 * _prop_visual_scale(key, theme, chosen))
	if _shadow_layer != null:
		_shadow_layer.call("set_enabled", themed)
		var shadow_mode := "painted_world" if terrain.painted_ground != null else (theme if themed else "storybook")
		_shadow_layer.call("set_mode", shadow_mode)
	if _rim_layer != null:
		_rim_layer.call("set_enabled", theme == "cinematic" and terrain.painted_ground == null)
	if shepherd_field != null:
		_apply_field_light()


## Enter the approved, uniformly scaled painterly field while retaining the
## production player, dialogue, interaction resolver and save flags.
func enter_shepherd_field() -> void:
	if shepherd_field != null:
		return
	shepherd_field = load("res://scripts/world/ShepherdFieldStage.gd").new()
	add_child(shepherd_field)
	shepherd_field.build()
	terrain.visible = false
	for p in _prop_sprites:
		(p["sprite"] as Sprite2D).visible = false
	_field_giant_visible = goliath_sprite != null and goliath_sprite.visible
	if goliath_sprite != null:
		goliath_sprite.visible = false
	_field_npcs.clear()
	for n in npcs:
		_field_npcs.append({"node": n, "position": n.global_position, "visible": n.visible,
			"z": n.z_index})
		if n.npc_id() == "hired_boy":
			n.global_position = shepherd_field.world(shepherd_field.HIRED_BOY)
			n.visible = true
			n.set_shepherd_field_appearance(true)
		else:
			n.visible = false
			n.set_physics_process(false)
			n.world_paused = true
	_field_camera_bounds = cam.bounds
	_field_camera_zoom = cam.zoom
	_field_magnet = player.magnet
	cam.bounds = shepherd_field.world_bounds()
	_fit_field_camera()
	player.setup(model, "david")
	player.set_field_visual(true)
	player.global_position = shepherd_field.world(shepherd_field.START)
	player.velocity = Vector2.ZERO
	player.collision_override = Callable(shepherd_field, "walkable")
	player.world_speed_scale = 0.45
	player.surface_speed_override = 1.0
	player.footstep_override = "step_grass"
	player.clamp_to_model = false
	player.magnet = 0.0
	_apply_field_light()
	_update_field_depth()
	snap_camera()


func _fit_field_camera() -> void:
	if shepherd_field == null or cam == null:
		return
	var zoom_value: float = shepherd_field.camera_zoom_for(get_viewport().get_visible_rect().size)
	cam.zoom = Vector2.ONE * zoom_value
	if player != null:
		cam.set_follow(player)


func _apply_field_light() -> void:
	# The painting already contains the late sunlight; do not double-tint it.
	if _mod != null:
		_mod.color = Color.WHITE
	player.external_shadow = true
	_shadow_layer.call("set_enabled", true)
	_shadow_layer.call("set_mode", "painted_field")
	_rim_layer.call("set_enabled", false)


func _update_field_depth() -> void:
	if shepherd_field == null:
		return
	player.z_index = shepherd_field.depth_at(player.global_position)
	for n in npcs:
		if n.visible:
			n.z_index = shepherd_field.depth_at(n.global_position)
	for p in pickups:
		var item = p.get("node")
		if str(p.get("kind", "")) == "flock" and is_instance_valid(item):
			var node: Node2D = item
			node.z_index = shepherd_field.depth_at(node.global_position)


## Restore the valley at the next story cut. Kept explicit so the old map's
## collision/camera/actors never remain hidden after the shepherd scene.
func leave_shepherd_field() -> void:
	if shepherd_field == null:
		return
	player.collision_override = Callable()
	player.world_speed_scale = 1.0
	player.surface_speed_override = -1.0
	player.footstep_override = ""
	player.clamp_to_model = true
	player.set_field_visual(false)
	player.magnet = _field_magnet
	player.z_index = 0
	cam.bounds = _field_camera_bounds
	cam.zoom = _field_camera_zoom
	terrain.visible = true
	for p in _prop_sprites:
		(p["sprite"] as Sprite2D).visible = true
	if goliath_sprite != null:
		goliath_sprite.visible = _field_giant_visible and not bool(GameState.flag("goliath_down"))
	for state in _field_npcs:
		var n: Npc = state["node"]
		if not is_instance_valid(n):
			continue
		n.global_position = state["position"]
		n.visible = bool(state["visible"])
		n.z_index = int(state["z"])
		if n.npc_id() == "hired_boy":
			n.set_shepherd_field_appearance(false)
		n.world_paused = _paused
		n.set_physics_process(not _paused)
	_field_npcs.clear()
	# The field is a different world, not an overlay on the valley. A last
	# sheep can still be in its short return animation when the story cuts
	# away; do not let it or its shadow remain on the restored tile map. Save
	# flags stay in GameState, and re-entering can spawn any unfinished sheep.
	var remaining: Array = []
	for item in pickups:
		var entry: Dictionary = item
		if not bool(entry.get("field_flock", false)):
			remaining.append(entry)
			continue
		var animal = entry.get("node")
		if is_instance_valid(animal):
			_shadow_layer.call("remove_target", animal)
			animal.queue_free()
	_shadow_layer.call("remove_target", null) # prune sheep that already finished their tween
	pickups = remaining
	shepherd_field.queue_free()
	shepherd_field = null
	_apply_time(str(GameState.data.get("time_of_day", "morning")))
	player.external_shadow = _art_theme != "classic"
	_shadow_layer.call("set_enabled", _art_theme != "classic")
	var shadow_mode := "painted_world" if terrain.painted_ground != null else (_art_theme if _art_theme != "classic" else "storybook")
	_shadow_layer.call("set_mode", shadow_mode)
	_rim_layer.call("set_enabled", _art_theme == "cinematic" and terrain.painted_ground == null)


func place_name() -> String:
	if shepherd_field != null:
		return I18n.t({"zh": "伯利恒牧场", "en": "Bethlehem Fields"})
	return I18n.t(model.display_name) if model != null else ""


func is_paused() -> bool:
	return _paused


func set_paused(v: bool) -> void:
	_paused = v
	if player:
		player.set_process(!v)
		player.set_physics_process(!v)
	for n in npcs:
		var hidden_in_field := shepherd_field != null and not n.visible
		n.set_physics_process(not v and not hidden_in_field)
		n.world_paused = v or hidden_in_field
