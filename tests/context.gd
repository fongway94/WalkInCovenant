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
	_check_dialogue_objective_locales(main, region)
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
	main._update_guidance()
	_check(str(main.hud.objective_lbl.text).ends_with("2/3"), "guided progress reaches the HUD")
	main.hud.point_at(Vector2(100, 0), true)
	region._on_sheep_arrived(c.sheep_id, true)
	_check(main.sheep_home == 3 and region.dialogue.is_open()
		and str(main.hud.objective_lbl.text).ends_with("3/3") and not main.hud.arrow._on,
		"the final guided arrival updates the HUD before the home dialogue")
	main.queue_free()
	await get_tree().process_frame
	await _check_bethlehem_arrival_locale()
	await _check_bethlehem_dialogue_locale()
	await _check_bethlehem_resume_locale()
	I18n.set_lang("zh")
	_finish()


## Dialogue freezes the current task, not the language it is printed in. Cover
## a plain objective, a named-person template and a counted objective without
## ticking the mission runner or advancing the dialogue.
func _check_dialogue_objective_locales(main, region: Region) -> void:
	var lines := [{"who": "", "text": {"en": "A moment.", "zh": "等一等。"}}]
	I18n.set_lang("zh")
	_check(I18n.t_for({"en": "Quiet", "zh": "安静"}, "en") == "Quiet" \
		and I18n.t_for({"zh": "安静"}, "en") == "安静" and I18n.lang == "zh",
		"resolving another language is pure and retains normal fallback")
	main.act = main.Act.WITNESS
	main._update_guidance()
	_check(main.hud.objective_lbl.text == str(region.model.objectives["corin"]["zh"]),
		"fresh witness guidance starts in Chinese")
	region.dialogue.show_lines(lines, func(_w): return {}, func(): pass)
	var box_id: int = region.dialogue._box_id
	I18n.set_lang("en")
	_check(region.dialogue.is_open() and region.dialogue._box_id == box_id \
		and region.dialogue._i == 0 and main.hud.objective_lbl.text \
		== str(region.model.objectives["corin"]["en"]),
		"a witness objective translates without advancing its open dialogue")
	region.dialogue.hide_box()
	I18n.set_lang("zh")

	var corin: Npc = main._npc("corin")
	var old_state: int = corin.state
	corin._talked = true
	main._update_guidance()
	var next: Npc = main._next_unspoken()
	var zh_line := str(region.model.objectives["npc"]["zh"]) % str(next.data["name"]["zh"])
	_check(main.hud.objective_lbl.text == zh_line and corin.lead_target == next,
		"the current witness objective includes the next person's Chinese name")
	region.dialogue.show_lines(lines, func(_w): return {}, func(): pass)
	I18n.set_lang("en")
	var en_line := str(region.model.objectives["npc"]["en"]) % str(next.data["name"]["en"])
	_check(region.dialogue.is_open() and main.hud.objective_lbl.text == en_line \
		and corin.lead_target == next,
		"a named objective translates without restarting the escort under dialogue")
	region.dialogue.hide_box()
	corin._talked = false
	corin.clear_lead()
	corin.state = old_state
	I18n.set_lang("zh")

	main.act = main.Act.ERRAND
	main.provisions = 1
	main._provision_total = 3
	main._update_guidance()
	region.dialogue.show_lines(lines, func(_w): return {}, func(): pass)
	I18n.set_lang("en")
	_check(region.dialogue.is_open() and main.provisions == 1 and main.hud.objective_lbl.text \
		== str(region.model.objectives["provision"]["en"]) + "  1／3",
		"a frozen provision objective translates without losing its count")
	region.dialogue.hide_box()
	main.provisions = 0
	main._provision_total = 0
	I18n.set_lang("zh")


## Stage a real region swap, not a save in Bethlehem: its arrival opens a box
## synchronously, before the next guidance frame could discard the old task.
func _check_bethlehem_arrival_locale() -> void:
	GameState.new_game()
	I18n.set_lang("zh")
	var main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().process_frame
	main.set_process(false)
	main._update_guidance()
	main._swap_region("bethlehem")
	var region: Region = main.region
	var box_id: int = region.dialogue._box_id
	_check(region.dialogue.is_open() and main.runner.current_id() == "beth_gate" \
		and main.hud.objective_lbl.text == str(region.model.objectives["gate"]["zh"]),
		"Bethlehem arrival replaces the old region's objective before dialogue")
	I18n.set_lang("en")
	_check(region.dialogue.is_open() and region.dialogue._box_id == box_id \
		and main.runner.current_id() == "beth_gate" and main.hud.objective_lbl.text \
		== str(region.model.objectives["gate"]["en"]),
		"Bethlehem arrival translates the new objective without advancing the story")
	main.queue_free()
	await get_tree().process_frame


## A cold-booted Bethlehem Main supplies its own campaign guidance. Its frozen
## task must also re-letter without the runner entering the next mission.
func _check_bethlehem_dialogue_locale() -> void:
	GameState.new_game()
	GameState.data["region"] = "bethlehem"
	var main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().process_frame
	main.set_process(false)
	var region: Region = main.region
	region.set_process(false)
	region.set_paused(false)
	if region.dialogue.is_open():
		region.dialogue.hide_box()
	I18n.set_lang("zh")
	main._update_guidance()
	var mission: String = main.runner.current_id()
	_check(mission == "beth_gate" and main.hud.objective_lbl.text \
		== str(region.model.objectives["gate"]["zh"]),
		"Bethlehem supplies its own Chinese guidance")
	region.dialogue.show_lines([{"who": "", "text": {"en": "A moment.", "zh": "等一等。"}}],
		func(_w): return {}, func(): pass)
	var box_id: int = region.dialogue._box_id
	I18n.set_lang("en")
	_check(region.dialogue.is_open() and region.dialogue._box_id == box_id \
		and main.runner.current_id() == mission and main.hud.objective_lbl.text \
		== str(region.model.objectives["gate"]["en"]),
		"Bethlehem's frozen objective translates without changing the mission")
	main.queue_free()
	await get_tree().process_frame


## A save in a later Bethlehem mission opens its brief before the first frame.
## The HUD should not stay blank while that box is displayed.
func _check_bethlehem_resume_locale() -> void:
	GameState.new_game()
	GameState.data["region"] = "bethlehem"
	GameState.set_flag("beth_met_elder", true)
	I18n.set_lang("zh")
	var main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().process_frame
	main.set_process(false)
	var region: Region = main.region
	var box_id: int = region.dialogue._box_id
	_check(region.dialogue.is_open() and main.runner.current_id() == "beth_sons" \
		and main.hud.objective_lbl.text == str(region.model.objectives["house"]["zh"]),
		"a resumed Bethlehem brief starts with its current Chinese objective")
	I18n.set_lang("en")
	_check(region.dialogue.is_open() and region.dialogue._box_id == box_id \
		and main.runner.current_id() == "beth_sons" and main.hud.objective_lbl.text \
		== str(region.model.objectives["house"]["en"]),
		"a resumed Bethlehem brief translates without changing the mission")
	main.queue_free()
	await get_tree().process_frame


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
