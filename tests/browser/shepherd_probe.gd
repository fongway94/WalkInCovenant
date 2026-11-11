extends Node
## Test-only entry point: starts the real Main shepherd act after staging its
## earlier story prerequisites, then exposes read-only state to browser tests.
## It draws nothing, does not alter the regular launch, and is not a full-game
## playthrough. All input still goes through the production keyboard/touch path.

var main = null
var ready_for_probe := false
var poll := 0.0
## An explicit test-only interruption of a live return tween. This is not a
## natural chapter transition: it exercises the cleanup boundary in the Web
## renderer, while ordinary gameplay remains covered by the resume probe.
var leave_on_return := false
var cleanup := {}


func _ready() -> void:
	GameState.new_game()
	GameState.data["settings"]["reduce_motion"] = true
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	# This probe stages one act rather than driving the whole mission runner.
	main.runner = null
	await get_tree().process_frame
	GameState.set_flag("elah_met_the_line", true)
	GameState.set_flag("beth_anointed", true)
	main._start_david_act()
	var frames := 0
	while not main._flock_active and frames < 900:
		if main.region.dialogue.is_open():
			main.region.dialogue._advance()
		await get_tree().process_frame
		frames += 1
	ready_for_probe = bool(main._flock_active)
	# Test-only camera variations exercise screen-space bubble placement. The
	# regular scene has its own fixed zoom and never reads this query parameter.
	if ready_for_probe and OS.has_feature("web"):
		leave_on_return = bool(JavaScriptBridge.eval(
			"new URLSearchParams(location.search).get('leave_on_return') === '1'", true))
		var zoom_arg = JavaScriptBridge.eval("new URLSearchParams(location.search).get('zoom')", true)
		if zoom_arg != null:
			var minimum: float = main.region.shepherd_field.camera_zoom_for(
				get_viewport().get_visible_rect().size)
			var zoom_value := maxf(minimum, clampf(float(str(zoom_arg)), 0.5, 1.5))
			main.region.cam.zoom = Vector2.ONE * zoom_value
			main.region.snap_camera()
	_publish()


func _process(delta: float) -> void:
	if not ready_for_probe:
		return
	if leave_on_return and cleanup.is_empty():
		_interrupt_return()
	poll += delta
	if poll >= 0.12:
		poll = 0.0
		_publish()


func _interrupt_return() -> void:
	var r: Region = main.region
	for item in r.pickups:
		var entry: Dictionary = item
		if str(entry.get("kind", "")) != "flock" or not bool(entry.get("got", false)):
			continue
		var animal = entry.get("node")
		if not is_instance_valid(animal) or not animal._leaving:
			continue
		var id := str(entry.get("id", ""))
		var ref: WeakRef = weakref(animal)
		var had_shadow := false
		for target in r._shadow_layer.targets:
			var target_node = target.get("node")
			if is_instance_valid(target_node) and target_node == animal:
				had_shadow = true
				break
		# Invoke the same production cleanup as the errand cut, deliberately
		# earlier than the normal narrative timing so the tween is still live.
		r.leave_shepherd_field()
		cleanup = {"id": id, "return_was_live": true, "had_shadow": had_shadow,
			"queued": animal.is_queued_for_deletion(), "verified": false}
		_finish_cleanup(ref, id)
		return


func _finish_cleanup(ref: WeakRef, id: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var r: Region = main.region
	var remaining := 0
	var sheep_shadows := 0
	for entry in r.pickups:
		if bool(entry.get("field_flock", false)):
			remaining += 1
	for target in r._shadow_layer.targets:
		var node = target.get("node")
		if is_instance_valid(node) and node is FlockSheep:
			sheep_shadows += 1
	cleanup["alive_after"] = ref.get_ref() != null
	cleanup["field_pickups"] = remaining
	cleanup["sheep_shadows"] = sheep_shadows
	cleanup["saved"] = bool(GameState.flag(Region.pickup_key(r.region_id, id)))
	cleanup["verified"] = true
	_publish()


func _publish() -> void:
	if not OS.has_feature("web") or main == null or main.region == null:
		return
	var r: Region = main.region
	var p: Player = r.player
	var target := r.context_target()
	var animals: Array = []
	var departing: Array = []
	var claimed: Array = []
	for it in r.pickups:
		if str(it.get("kind", "")) != "flock":
			continue
		if bool(it.get("got", false)):
			claimed.append({"id": str(it.get("id", "")), "guided": bool(it.get("guided", false))})
		var animal = it.get("node")
		if is_instance_valid(animal):
			var detail := {"id": animal.sheep_id,
				"pos": [animal.global_position.x, animal.global_position.y],
				"mood": animal.mood_name(), "leaving": animal._leaving}
			if bool(it.get("got", false)):
				departing.append(detail)
			else:
				animals.append(detail)
	var rig = p.david_visual
	var bubble := {}
	for person in r.npcs:
		if person.npc_id() != "hired_boy" or person._bubble == null or not person._bubble.visible:
			continue
		var canvas := person.get_global_transform_with_canvas()
		var top_left: Vector2 = canvas * person._bubble.position
		var extent := Vector2(canvas.x.length() * person._bubble.size.x,
			canvas.y.length() * person._bubble.size.y)
		var label: Label = person._bubble_lbl
		var text_width := label.get_theme_font("font").get_string_size(label.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
		var body: Rect2 = person._speaker_canvas_rect(canvas)
		var player_body: Rect2 = person._player_canvas_rect()
		bubble = {"rect": [top_left.x, top_left.y, extent.x, extent.y],
			"speaker_rect": [body.position.x, body.position.y, body.size.x, body.size.y],
			"player_rect": [player_body.position.x, player_body.position.y, player_body.size.x, player_body.size.y],
			"z": person._bubble.z_index, "relative": person._bubble.z_as_relative,
			"text_width": text_width, "label_width": label.size.x}
	var status := {
		"ready": ready_for_probe, "field": r.shepherd_field != null,
		"viewport": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		"camera": [r.cam.global_position.x, r.cam.global_position.y],
		"camera_zoom": r.cam.zoom.x,
		"field_bounds": [r.cam.bounds.position.x, r.cam.bounds.position.y,
			r.cam.bounds.size.x, r.cam.bounds.size.y],
		"bubble": bubble,
		"player": [p.global_position.x, p.global_position.y],
		"facing": [p.facing.x, p.facing.y], "moving": p.mode == Player.Mode.MOVING,
		"pose": str(rig._pose_name) if rig != null else "",
		"flip": bool(rig.body.flip_h) if rig != null else false,
		"target": str(target.get("id", "")), "target_kind": str(target.get("kind", "")),
		"prompt": main.hud.prompt_lbl.text, "count": int(main.sheep_home),
		"total": int(main._sheep_total), "animals": animals, "departing": departing,
		"claimed": claimed, "cleanup": cleanup, "paused": r.is_paused(),
	}
	JavaScriptBridge.eval("window.__shepherdProbe=" + JSON.stringify(status) + ";", true)
