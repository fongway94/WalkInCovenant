extends Node
## Browser-only inspection of the real Main/save lifecycle. `?seed=1` stages a
## shepherd save once; the next page must boot without that parameter. Apart
## from the initial fixture, this probe only publishes state: movement, dialogue,
## counting, practice, transitions and persistence go through the real game.

var main = null
var poll := 0.0
var map_region := ""
var map_rows: Array = []


func _ready() -> void:
	var seed := false
	if OS.has_feature("web"):
		seed = bool(JavaScriptBridge.eval("new URLSearchParams(location.search).get('seed') === '1'", true))
	if seed:
		GameState.new_game()
		GameState.data["settings"]["reduce_motion"] = true
		GameState.set_flag("elah_met_the_line", true)
		GameState.set_flag("beth_anointed", true)
		GameState.data["progress"] = {"act": "shepherd", "pos": [16, 35]}
		GameState.save_game()
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	_publish()


func _process(delta: float) -> void:
	poll += delta
	if poll >= 0.08:
		poll = 0.0
		_publish()


func _publish() -> void:
	if not OS.has_feature("web") or main == null or main.region == null:
		return
	var r: Region = main.region
	var p: Player = r.player
	if p == null or r.dialogue == null:
		return
	if map_region != r.region_id:
		map_region = r.region_id
		map_rows.clear()
		for y in range(r.model.height):
			var row := ""
			for x in range(r.model.width):
				row += "#" if r.model.solid_at_tile(x, y) else "."
			map_rows.append(row)
	var animals: Array = []
	var departing: Array = []
	var pickups: Array = []
	var people: Array = []
	var provision_count := 0
	for person in r.npcs:
		if person.visible:
			people.append({"id": person.npc_id(),
				"pos": [person.global_position.x, person.global_position.y],
				"can_talk": person.can_talk()})
	for item in r.pickups:
		var entry: Dictionary = item
		var node = entry.get("node")
		if str(entry.get("kind", "")) != "flock":
			if not bool(entry.get("got", false)) and is_instance_valid(node):
				pickups.append({"id": str(entry.get("id", "")), "kind": str(entry.get("kind", "")),
					"pos": [node.global_position.x, node.global_position.y]})
				if str(entry.get("kind", "")) == "provision":
					provision_count += 1
			continue
		var animal = entry.get("node")
		if not is_instance_valid(animal):
			continue
		var detail := {"id": animal.sheep_id,
			"pos": [animal.global_position.x, animal.global_position.y],
			"mood": animal.mood_name()}
		if bool(entry.get("got", false)):
			departing.append(detail)
		else:
			animals.append(detail)
	var target := r.context_target()
	var bubble := {}
	for person in r.npcs:
		if person.npc_id() != "hired_boy" or person._bubble == null or not person._bubble.visible:
			continue
		var canvas := person.get_global_transform_with_canvas()
		var top_left: Vector2 = canvas * person._bubble.position
		var extent := Vector2(canvas.x.length() * person._bubble.size.x,
			canvas.y.length() * person._bubble.size.y)
		var player_body: Rect2 = person._player_canvas_rect()
		bubble = {"rect": [top_left.x, top_left.y, extent.x, extent.y],
			"player_rect": [player_body.position.x, player_body.position.y, player_body.size.x, player_body.size.y]}
	var status := {
		"ready": true, "act": main.act_id(), "region": r.region_id,
		"mission": main.runner.current_id() if main.runner != null else "",
		"field": r.shepherd_field != null, "flock_active": main._flock_active,
		"player": [p.global_position.x, p.global_position.y], "armour": p.armour,
		"armour_visible": p.armour_visual != null and p.armour_visual.visible,
		"armour_painted": p.armour_visual.painted if p.armour_visual != null else false,
		"speed_scale": p.speed_scale(), "stagger": p.sprite.offset.x,
		"dialogue": r.dialogue.is_open(), "choices": r.dialogue._in_choices, "paused": r.is_paused(),
		"count": main.sheep_home, "total": main._sheep_total,
		"target": str(target.get("id", "")), "target_kind": str(target.get("kind", "")),
		"animals": animals, "departing": departing, "pickups": pickups, "people": people,
		"bubble": bubble, "map": map_rows, "exits": r.model.exits,
		"word_count": (GameState.data.get("words", []) as Array).size(),
		"saw_giant": bool(GameState.flag("elah_saw_him")),
		"met_line": bool(GameState.flag("elah_met_the_line")),
		"beth_elder": bool(GameState.flag("beth_met_elder")),
		"beth_sons": bool(GameState.flag("beth_sons_seen")),
		"beth_called": bool(GameState.flag("beth_called")),
		"beth_anointed": bool(GameState.flag("beth_anointed")),
		"brothers_at": r.model.david_act.get("brothers_at", [16, 40]),
		"brook_at": (r.model.david_act.get("brook", {}) as Dictionary).get("at", [16, 27]),
		"challenge_row": r.model.challenge_row,
		"flock_done": bool(GameState.flag("elah_flock_done")),
		"drill_done": bool(GameState.flag("elah_drill_done")),
		"brothers_met": bool(GameState.flag("elah_brothers_met")),
		"armour_off": bool(GameState.flag("elah_armour_off")),
		"goliath_down": bool(GameState.flag("goliath_down")),
		"talked_corin": bool(GameState.flag("talked:elah:corin")),
		"ended": bool(GameState.flag("elah_ended")),
		"stones": main.stones, "provisions": main.provisions, "provision_count": provision_count,
		"progress": GameState.data.get("progress", {}),
	}
	if main.practice != null:
		status["practice"] = {"phase": int(main.practice.phase),
			"marker": float(main.practice._marker), "band": float(main.practice._band),
			"hits": int(main.practice.hits)}
	else:
		status["practice"] = null
	if main.stones_panel != null:
		status["stone_choice"] = {"chosen": main.stones_panel.chosen_count(),
			"full": main.stones_panel.is_full(), "cursor": main.stones_panel._cursor}
	else:
		status["stone_choice"] = null
	if main.fight != null:
		status["fight"] = {"phase": int(main.fight.phase), "marker": float(main.fight._marker),
			"band": float(main.fight._band), "strike": float(main.fight._strike),
			"hits": int(main.fight.hits), "nerve": int(main.fight.nerve),
			"stones": int(main.fight.stones)}
	else:
		status["fight"] = null
	JavaScriptBridge.eval("window.__shepherdResumeProbe=" + JSON.stringify(status) + ";", true)
