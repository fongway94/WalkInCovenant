extends Node
## Production interaction regression: real Region, Main, FlockSheep, save
## flags and input handler. Run: godot --headless --path . res://tests/context.tscn

var failures := 0
var checks := 0


func _ready() -> void:
	_run()


func _run() -> void:
	GameState.new_game()
	var main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().process_frame
	main.set_process(false)
	var region: Region = main.region
	region.set_process(false)
	region.set_paused(false)
	region._interact_lock = 0.0
	for n in region.npcs:
		n.set_physics_process(false)
		n.global_position = Vector2(460, 730)
	main.act = main.Act.SHEPHERD
	main._start_flock()
	var flock: Array = []
	for p in region.pickups:
		if str(p.get("kind", "")) == "flock":
			var animal: FlockSheep = p.get("node")
			animal.set_process(false)
			animal._startle = 0.0
			flock.append(animal)
	_check(flock.size() == 3, "three living strays spawn")
	if flock.size() != 3:
		_finish()
		return
	var a: FlockSheep = flock[0]
	var b: FlockSheep = flock[1]
	var c: FlockSheep = flock[2]
	region.player.global_position = Vector2(120, 120)
	a.global_position = Vector2(128, 120)
	b.global_position = Vector2(136, 120)
	c.global_position = Vector2(300, 300)
	var key := Region.pickup_key("elah", a.sheep_id)
	region._check_pickups()
	_check(main.sheep_home == 0 and not bool(GameState.flag(key)),
		"walking close does not silently count")
	_check(str(region.context_target().get("id", "")) == a.sheep_id,
		"only the closest eligible sheep is selected")
	I18n.set_lang("zh")
	_check(region.context_prompt().contains("数羊"), "Chinese count prompt")
	I18n.set_lang("en")
	_check(region.context_prompt().contains("Count Sheep"), "English count prompt")
	a._startle = 0.5
	_check(str(region.context_target().get("id", "")) == b.sheep_id,
		"a temporarily invalid target is skipped")
	a._startle = 0.0
	region.set_paused(true)
	_check(region.context_target().is_empty(), "dialogue pause suppresses target")
	_send_action(region)
	_check(main.sheep_home == 0, "a paused action cannot count")
	region.set_paused(false)
	var sfx_before: int = AudioDirector._round_robin
	TapGate.reset()
	_send_action(region)
	_check(main.sheep_home == 1 and bool(GameState.flag(key)), "action counts and persists first sheep")
	_check(a._leaving and a._sprite.texture == a._alert_tex, "sheep starts its answering reaction")
	_check(AudioDirector._round_robin != sfx_before, "count requests supported audio feedback")
	_check(str(region.context_target().get("id", "")) == b.sheep_id,
		"selection transfers to the next valid sheep")
	_send_action(region)
	_check(main.sheep_home == 1, "duplicate delivery of one tap cannot count the next sheep")
	region.collect_pickup(a.sheep_id)
	_check(main.sheep_home == 1, "an already counted id cannot count twice")
	# Main saves immediately on the action; do not call save_game here.
	GameState.data["flags"].erase(key)
	_check(GameState.load_game() and bool(GameState.flag(key)), "count survives an immediate reload")
	region.spawn_pickup(a.sheep_id, "flock", "sheep", 7, 7)
	var unclaimed_a := 0
	for p in region.pickups:
		if str(p.get("id", "")) == a.sheep_id and not bool(p.get("got", false)):
			unclaimed_a += 1
	_check(unclaimed_a == 0, "saved sheep does not respawn")

	# Registration lets a door/object/discovery share the SAME resolver, with
	# a dynamic availability predicate and a caller-owned action.
	var object := Node2D.new()
	region.add_child(object)
	object.global_position = region.player.global_position + Vector2(3, 0)
	var enabled := [true]
	var calls := [0]
	region.register_context_target(object, "test_object", {"zh": "查看", "en": "Inspect"},
		16.0, func(): calls[0] += 1, func(): return enabled[0])
	_check(str(region.context_target().get("id", "")) == "test_object",
		"closer registered object wins over sheep")
	TapGate.reset()
	_send_action(region)
	_check(calls[0] == 1 and main.sheep_home == 1, "only that object's callback runs")
	enabled[0] = false
	_check(str(region.context_target().get("id", "")) == b.sheep_id,
		"disabled objects cannot steal the nearest target")
	# The guided arrival path keeps its original meaning and idempotence.
	region._on_sheep_arrived(b.sheep_id, true)
	_check(main.sheep_home == 2 and main._sheep_guided(b.sheep_id),
		"an animal that reaches the fold remains guided")
	region._on_sheep_arrived(b.sheep_id, true)
	_check(main.sheep_home == 2, "a duplicate arrival is harmless")
	I18n.set_lang("zh")
	_finish()


func _send_action(region: Region) -> void:
	var e := InputEventAction.new()
	e.action = "interact"
	e.pressed = true
	region._unhandled_input(e)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL context: " + message)
	else:
		print("PASS context: " + message)


func _finish() -> void:
	print("context interaction: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
