extends Node2D
class_name Npc
## Npc — a person in the world who can stand, patrol, follow, and talk.
##
## Covenant's NPCs never moved: `entities = NPCS.map(n => ({...n}))`, positions
## static forever, and its reachability BFS ran only in tests. Here the same
## content data drives real movement over an AStarGrid2D, which is what makes
## "follow me" and walk-and-talk escorts possible at all.

const TILE := 16.0
const PATROL_SPEED := 34.0
const FOLLOW_SPEED := 62.0
const FOLLOW_KEEPUP := 26.0      # stop this close to the player
const REPATH_EVERY := 0.6

enum State { IDLE, PATROL, FOLLOW, TALK }

var model: RegionModel = null
var data: Dictionary = {}
# Injected, not held as a typed Region. Region spawns Npc, so a typed
# back-reference is a class_name CYCLE (Region -> Npc -> Region). Godot 4
# reports that as "Could not resolve external class member" in whichever script
# happened to trigger the compile — here Main.gd, two files away from the cause.
# Npc only ever needed the player, the dialogue box and a way to pause.
var player: Player = null
var dialogue: DialogueBox = null
var pause_fn: Callable = Callable()
var state: State = State.IDLE

var sprite: Sprite2D = null
var facing := Vector2i(0, 1)
var _path := PackedVector2Array()
var _path_i := 0
var _patrol_i := 0
var _wait := 0.0
var _repath := 0.0
var _frame := 0.0
var _moving := false
var _talked := false

# ── escort/lead ──────────────────────────────────────────────────────────
# Playtest 7: "when they bring you along, they should lead you to talk to the
# others." Following the player is a bodyguard; leading is a guide. A guide
# walks to the next person, stops there, and waits for you to catch up — so the
# chapter is a walk through people, not a list of fetch markers.
var lead_target: Npc = null
var lead_arrive_fn: Callable = Callable()
var _lead_arrived := false


func setup(m: RegionModel, d: Dictionary, p: Player, dlg: DialogueBox,
		pause: Callable) -> void:
	model = m
	data = d
	player = p
	dialogue = dlg
	pause_fn = pause
	var actor: String = d.get("actor", "villager_a")
	sprite = Sprite2D.new()
	sprite.centered = true
	sprite.offset = Vector2(0, -8)
	sprite.texture = load("res://art/characters/%s_idle.png" % actor)
	sprite.hframes = 2
	sprite.vframes = 4
	add_child(sprite)
	var at: Array = d.get("at", [1, 1])
	global_position = Vector2(int(at[0]) * TILE + 8, (int(at[1]) + 1) * TILE - 2)
	if (d.get("patrol", []) as Array).size() > 0:
		state = State.PATROL


func npc_id() -> String:
	return data.get("id", "npc")


## The citation for a verse id, from the region's word list. Kept next to the
## verse in data so a reviewer can check the reference against the line.
func word_ref(word: String) -> String:
	if model == null:
		return ""
	for w in model.words:
		if w.get("id") == word:
			return str(w.get("ref", ""))
	return ""


func word_text(word: String) -> Dictionary:
	if model == null:
		return {}
	for w in model.words:
		if w.get("id") == word:
			return w.get("text", {})
	return {}


func display_name() -> String:
	return I18n.t(data.get("name", npc_id()))


# ── movement ─────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	match state:
		State.IDLE:
			_moving = false
		State.PATROL:
			_do_patrol(delta)
		State.FOLLOW:
			_do_follow(delta)
		State.TALK:
			_moving = false
	_update_anim(delta)


func _tile_here() -> Vector2i:
	return Vector2i(int(floor(global_position.x / TILE)),
		int(floor((global_position.y - 2) / TILE)))


func _do_patrol(delta: float) -> void:
	var pts: Array = data.get("patrol", [])
	if pts.is_empty():
		state = State.IDLE
		return
	if _path_i >= _path.size():
		if _wait <= 0:
			_wait = randf_range(0.6, 1.6)
			_moving = false
			return
		_wait -= delta
		if _wait > 0:
			_moving = false
			return
		_patrol_i = (_patrol_i + 1) % pts.size()
		var target := Vector2i(int(pts[_patrol_i][0]), int(pts[_patrol_i][1]))
		_path = model.path(_tile_here(), model.nearest_open(target))
		_path_i = 0
		return
	_step_toward(_path[_path_i], PATROL_SPEED, delta)


func _do_follow(delta: float) -> void:
	if lead_target != null and is_instance_valid(lead_target) and not _lead_arrived:
		_do_lead(delta)
		return
	var d := (player.global_position - global_position).length()
	if d < FOLLOW_KEEPUP:
		_moving = false
		_path = PackedVector2Array()
		face_toward(player.global_position)
		return
	_repath -= delta
	if _repath <= 0 or _path_i >= _path.size():
		_repath = REPATH_EVERY
		var to := model.nearest_open(_tile_behind_player())
		_path = model.path(_tile_here(), to)
		_path_i = 0
	if _path_i < _path.size():
		_step_toward(_path[_path_i], FOLLOW_SPEED, delta)


## Walk to the person we are introducing, then stand there facing the player.
func _do_lead(delta: float) -> void:
	var goal := lead_target.global_position
	if global_position.distance_to(goal) < 30.0:
		_moving = false
		_path = PackedVector2Array()
		_lead_arrived = true
		face_toward(player.global_position)
		if lead_arrive_fn.is_valid():
			var cb := lead_arrive_fn
			lead_arrive_fn = Callable()
			cb.call()
		return
	_repath -= delta
	if _repath <= 0 or _path_i >= _path.size():
		_repath = REPATH_EVERY
		var there := Vector2i(int(floor(goal.x / TILE)),
			int(floor((goal.y - 2) / TILE)))
		# one tile short of them, so the guide never stands inside the person
		if there == _tile_here():
			there = model.nearest_open(there + Vector2i(0, 1))
		_path = model.path(_tile_here(), model.nearest_open(there))
		_path_i = 0
	if _path_i < _path.size():
		_step_toward(_path[_path_i], FOLLOW_SPEED * 1.15, delta)


func lead_to(n: Npc, on_arrive: Callable) -> void:
	lead_target = n
	lead_arrive_fn = on_arrive
	_lead_arrived = false
	_repath = 0.0
	_path = PackedVector2Array()
	_path_i = 0
	state = State.FOLLOW


func clear_lead() -> void:
	lead_target = null
	lead_arrive_fn = Callable()
	_lead_arrived = false


func has_arrived() -> bool:
	return _lead_arrived


func _tile_behind_player() -> Vector2i:
	# stand one tile behind the player relative to their facing, so an escort
	# walks *with* you rather than into you
	var f: Vector2i = player.facing
	var t := Vector2i(int(floor(player.global_position.x / TILE)),
		int(floor(player.global_position.y / TILE)))
	return model.nearest_open(t - f)


func _step_toward(world_pt: Vector2, speed: float, delta: float) -> void:
	var d := world_pt - global_position
	if d.length() < 2.0:
		_path_i += 1
		return
	var dir := d.normalized()
	global_position += dir * speed * delta
	facing = _dir_from(dir)
	_moving = true


func _dir_from(v: Vector2) -> Vector2i:
	if absf(v.x) > absf(v.y):
		return Vector2i(1, 0) if v.x > 0 else Vector2i(-1, 0)
	return Vector2i(0, -1) if v.y < 0 else Vector2i(0, 1)


func face_toward(target: Vector2) -> void:
	var d := target - global_position
	facing = _dir_from(d)


# ── conversation ─────────────────────────────────────────────────────────
func talk() -> void:
	if player == null or dialogue == null:
		return
	if dialogue.is_open():
		# One beat at a time. A second call while a box is up used to replace
		# the box underneath the player's finger, which is what "the dialogue
		# repeats" looked like.
		return
	state = State.TALK
	_moving = false
	face_toward(player.global_position)
	pause_fn.call(true)
	GameState.record_way("stay")          # stopping to listen is a way of walking

	var lines: Array = (data.get("after", []) if _talked else data.get("lines", []))
	if lines.is_empty():
		lines = data.get("lines", [])
	dialogue.show_lines(lines, _speaker_for, _on_done)


func _speaker_for(who: String) -> Dictionary:
	# resolve a speaker id to {name, actor} for the nameplate + portrait
	if who == "" or who == null:
		return {"name": "", "actor": ""}
	if who == npc_id():
		return {"name": display_name(), "actor": data.get("actor", "")}
	var cast: Dictionary = data.get("cast", {})
	if cast.has(who):
		var c: Dictionary = cast[who]
		return {"name": I18n.t(c.get("name", who)), "actor": c.get("actor", "")}
	return {"name": I18n.t(who), "actor": data.get("actor", "")}


func _on_done() -> void:
	queue_redraw()          # the mark over the head goes away once you have spoken
	# UNPAUSE FIRST. This used to run after the word handout, so any error in
	# receive_word / word_ref (or in a listener of verse_received) left the world
	# paused for ever — the player stood in front of a finished dialogue with a
	# dead character and no way out (playtest 5). Nothing in a reward path is
	# allowed to be able to take the controls away.
	pause_fn.call(false)
	if not _talked:
		_talked = true
		var word: String = data.get("word", "")
		if word != "":
			GameState.receive_word(word, word_ref(word))
	state = State.PATROL if (data.get("patrol", []) as Array).size() > 0 else State.IDLE
	if data.get("follow_after_talk", false):
		state = State.FOLLOW
	EventBus.player_interacted_with.emit(npc_id(), "npc")


func has_talked() -> bool:
	return _talked


func start_follow() -> void:
	state = State.FOLLOW
	EventBus.npc_escort_started.emit(npc_id())


func stop_follow() -> void:
	state = State.IDLE
	EventBus.npc_escort_ended.emit(npc_id())


# ── animation ───────────────────────────────────────────────────────────
func _dir_row() -> int:
	match facing:
		Vector2i(0, 1): return 0
		Vector2i(-1, 0): return 1
		Vector2i(1, 0): return 2
		_: return 3


func _update_anim(delta: float) -> void:
	if sprite == null:
		return
	var row := _dir_row()
	if _moving:
		var base: Texture2D = sprite.texture
		var walk_path := "res://art/characters/%s_walk.png" % data.get("actor", "villager_a")
		if base == null or base.resource_path != walk_path:
			sprite.texture = load(walk_path)
			sprite.hframes = 4
		_frame += delta * 6.0
		sprite.frame = int(row * 4 + int(_frame) % 4)
	else:
		var idle_path := "res://art/characters/%s_idle.png" % data.get("actor", "villager_a")
		if sprite.texture == null or sprite.texture.resource_path != idle_path:
			sprite.texture = load(idle_path)
			sprite.hframes = 2
		_frame += delta * 2.0
		sprite.frame = int(row * 2 + int(_frame) % 2)
	sprite.vframes = 4


func _draw() -> void:
	draw_rect(Rect2(-5, -2, 10, 3), Color(0.05, 0.08, 0.10, 0.35))
	# A mark over every person you have not spoken to yet. Playtest 6 walked past
	# four people who each held a verse and never knew they were worth stopping
	# for: the HUD prompt only appears once you are already in range, and a mark
	# over the head is visible from across the camp.
	if _talked or sprite == null:
		return
	var y := -20.0
	var pts := PackedVector2Array()
	pts.append(Vector2(0, y + 4))
	pts.append(Vector2(-3, y))
	pts.append(Vector2(3, y))
	draw_colored_polygon(pts, Color(0.97, 0.87, 0.65, 0.95))
	draw_rect(Rect2(Vector2(-1, y - 3), Vector2(2, 2)), Color(0.97, 0.87, 0.65, 0.95))
