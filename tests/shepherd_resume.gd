extends Node
## Cold-boot a real Main from a partial flock save, then cold-boot again after
## the last sheep but before the drill. Dialogues are advanced by the harness;
## these assertions cover persistence/lifecycle, not a continuous player walk.

var checks := 0
var failures := 0


func _ready() -> void:
	_run()


func _run() -> void:
	Engine.time_scale = 8.0
	GameState.new_game()
	GameState.data["settings"]["reduce_motion"] = true
	GameState.set_flag("elah_met_the_line", true)
	GameState.set_flag("beth_anointed", true)
	GameState.data["progress"] = {"act": "shepherd", "pos": [16, 35]}
	GameState.save_game()
	var main = _new_main()
	var loaded := await _wait_for(main, "flock")
	_check(loaded, "a saved shepherd mission enters the real field")
	if not loaded:
		_finish()
		return
	_check(main.sheep_home == 0 and main.region.shepherd_field != null,
		"a fresh shepherd save starts at zero in the painted field")
	var first := _live_sheep(main.region)[0] as FlockSheep
	first._startle = 0.0
	first.set_process(false)
	main.region.player.global_position = first.global_position + Vector2(4, 0)
	main.region._interact_lock = 0.0
	TapGate.reset()
	var action := InputEventAction.new()
	action.action = "interact"
	action.pressed = true
	main.region._unhandled_input(action)
	_check(main.sheep_home == 1, "a deliberate action counts exactly one sheep")
	var first_id := first.sheep_id
	main.queue_free()
	await get_tree().process_frame
	GameState.new_game()
	_check(GameState.load_game(), "the partial-flock save is readable after restart")
	_check(str(GameState.data["progress"].get("act", "")) == "shepherd"
		and bool(GameState.flag(Region.pickup_key("elah", first_id))),
		"the immediate save contains both the act and counted flag")
	main = _new_main()
	loaded = await _wait_for(main, "flock")
	_check(loaded and main.region.shepherd_field != null, "cold boot reinstalls the painted field")
	if not loaded:
		_finish()
		return
	_check(main.sheep_home == 1 and _live_sheep(main.region).size() == 2,
		"partial progress returns with one home and only two still out")
	var left := _live_sheep(main.region)
	for animal in left:
		main.region.collect_pickup(animal.sheep_id)
	_check(main.sheep_home == 3 and bool(GameState.flag("elah_flock_done")),
		"counting the remaining sheep closes the task")
	_check(main.region.dialogue.is_open(), "the last count can open its home dialogue immediately")
	main.queue_free()
	await get_tree().process_frame
	GameState.new_game()
	_check(GameState.load_game() and bool(GameState.flag("elah_flock_done")),
		"the last count is saved even before its dialogue is dismissed")
	main = _new_main()
	var practice_ready := await _wait_for(main, "practice")
	_check(practice_ready and main.sheep_home == 3 and _live_sheep(main.region).is_empty(),
		"reloading a completed flock opens practice rather than respawning sheep")
	# Check that switching away and back preserves a selected skin even when
	# David's conventional themed sheet does not exist.
	var p: Player = main.region.player
	p.apply_art_theme("cinematic")
	p.setup(main.region.model, "david")
	_check(p.art_dir.ends_with("characters_cinematic") and p.david_visual.visible,
		"David uses the painted rig without erasing the requested theme")
	p.setup(main.region.model, "pilgrim")
	_check(p.human_visual != null and p.human_visual.visible and not p.sprite.visible
		and p.idle_tex.resource_path.ends_with("characters_cinematic/pilgrim_idle.png"),
		"returning to pilgrim restores the selected painted rig and sheet fallback")
	p.setup(main.region.model, "david")
	main.queue_free()
	await get_tree().process_frame
	_finish()


func _new_main():
	var node = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	add_child(node)
	return node


func _live_sheep(region: Region) -> Array:
	var out: Array = []
	for item in region.pickups:
		if str(item.get("kind", "")) == "flock" and not bool(item.get("got", false)):
			var animal = item.get("node")
			if is_instance_valid(animal):
				out.append(animal)
	return out


func _wait_for(main, wanted: String) -> bool:
	for i in range(900):
		if main.region != null and main.region.dialogue.is_open():
			main.region.dialogue._advance()
		if wanted == "flock" and main._flock_active:
			return true
		if wanted == "practice" and main.practice != null:
			return true
		await get_tree().process_frame
	return false


func _check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("PASS shepherd resume: " + message)
	else:
		failures += 1
		printerr("FAIL shepherd resume: " + message)


func _finish() -> void:
	print("shepherd resume: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
