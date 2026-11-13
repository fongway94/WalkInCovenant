extends Node
## Staged framebuffer and movement evidence, not a playthrough or art approval.
## The same fixture runs against the pre-pass source and current source. It
## uses production Region, Player and Npc nodes with isolated save data. The
## walking crops follow actual physics steps. Other actors are frozen and the
## camera follows the moving figure so the gait is easy to inspect.

const CAPTURE_DIR := "res://build/refinement-frames"
const FRAME_SECONDS := 1.0 / 24.0
var main = null
var failures := 0


func _ready() -> void:
	_run()


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _image() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _save(image: Image, name: String) -> void:
	var dir := ProjectSettings.globalize_path(CAPTURE_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	if image == null or image.save_png(dir + "/" + name + ".png") != OK:
		printerr("could not capture " + name)
		failures += 1


func _shot(name: String) -> void:
	await _frames(3)
	_save(await _image(), name)
	print("captured " + name)


func _freeze(r: Region) -> void:
	r.set_process(false)
	r.player.set_physics_process(false)
	r.player.velocity = Vector2.ZERO
	r.cam.set_process(false)
	for npc in r.npcs:
		npc.set_process(false)
		npc.set_physics_process(false)
		# Freeze patrollers at their authored map anchors so old and new runs
		# differ in art, not in the random timing of an ambient patrol.
		if r.shepherd_field == null and npc.data.has("at"):
			var at: Array = npc.data["at"]
			npc.global_position = Vector2(int(at[0]) * 16.0 + 8.0, (int(at[1]) + 1) * 16.0 - 2.0)
			npc.facing = Vector2i(0, 1)
			if npc.human_visual != null:
				npc.human_visual.set_pose(npc.facing, false, 0.0, 0.2)
			if npc.david_visual != null:
				npc.david_visual.set_pose(npc.facing, false, 0.0, 0.2)
		if npc._bubble != null:
			npc._bubble.visible = false


func _crop_actor(actor: Node2D) -> Image:
	var image := await _image()
	var logical := get_viewport().get_visible_rect().size
	var pixel_scale := Vector2(float(image.get_width()) / logical.x,
		float(image.get_height()) / logical.y)
	var feet := actor.get_global_transform_with_canvas().origin * pixel_scale
	var x := clampi(roundi(feet.x) - 64, 0, image.get_width() - 128)
	var y := clampi(roundi(feet.y) - 100, 0, image.get_height() - 128)
	return image.get_region(Rect2i(x, y, 128, 128))


func _walk_player(r: Region, label: String, start: Vector2, direction: Vector2,
		magnitude := 0.80, capture_stop := false) -> void:
	var p := r.player
	p.global_position = start
	p.velocity = Vector2.ZERO
	# A full push runs; 0.8 is the ordinary analog walk. Both use real
	# physics steps rather than manually posing a stationary sprite.
	p.external_intent = direction * magnitude
	p.facing = Vector2i(int(direction.x), int(direction.y))
	var rig = p.david_visual if p.char_id == "david" else p.human_visual
	rig.phase = 0.0
	rig.gait_amount = 0.0
	r.cam.global_position = r.cam._clamp(start)
	for i in range(23):
		p._physics_process(FRAME_SECONDS)
		if r.shepherd_field != null:
			r._update_field_depth()
		r.cam.global_position = r.cam._clamp(p.global_position)
		await _frames(1)
		if i >= 5:
			_save(await _crop_actor(p), "%s-%02d" % [label, i - 5])
	var distance := (p.global_position - start).dot(direction)
	p.external_intent = Vector2.ZERO
	if capture_stop:
		var amount_before: float = rig.gait_amount
		var amount_first := -1.0
		for i in range(5):
			p._physics_process(FRAME_SECONDS)
			r.cam.global_position = r.cam._clamp(p.global_position)
			await _frames(1)
			_save(await _crop_actor(p), "%s-stop-%02d" % [label, i])
			if i == 0:
				amount_first = rig.gait_amount
		if amount_first <= 0.0 or amount_first >= amount_before or not is_zero_approx(rig.gait_amount):
			printerr("gait did not ease to idle during " + label)
			failures += 1
		print("captured eased stop " + label)
	else:
		p._physics_process(0.2)
	if distance < 8.0:
		printerr("player did not actually move during " + label)
		failures += 1
	print("captured real player steps " + label + " from " + str(start) + " to " + str(p.global_position))


func _walk_patrol(r: Region, npc: Npc, label: String) -> void:
	npc.global_position = Vector2(230, 600)
	npc.state = Npc.State.PATROL
	# The woman is stationary in the story; a short fixture-only patrol lets us
	# inspect the long-garment gait using the same production NPC movement.
	if not npc.data.has("patrol"):
		npc.data["patrol"] = [[14, 37], [19, 37]]
	npc._path = PackedVector2Array()
	npc._path.append(Vector2(310, 600))
	npc._path_i = 0
	npc.human_visual.phase = 0.0
	npc.human_visual.gait_amount = 0.0
	r.cam.global_position = r.cam._clamp(npc.global_position)
	for i in range(23):
		npc._physics_process(FRAME_SECONDS)
		r.cam.global_position = r.cam._clamp(npc.global_position)
		await _frames(1)
		if i >= 5:
			_save(await _crop_actor(npc), "%s-%02d" % [label, i - 5])
	if npc.global_position.x - 230.0 < 10.0:
		printerr(label + " did not actually patrol during the motion capture")
		failures += 1
	print("captured real NPC patrol " + label + " to " + str(npc.global_position))


func _run() -> void:
	Engine.time_scale = 6.0
	GameState.new_game()
	GameState.data["settings"]["reduce_motion"] = true
	I18n.set_lang("en")
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _frames(55)
	main.card.hide_now()
	main.set_process(false)
	var r: Region = main.region
	_freeze(r)
	r.cam.global_position = r.cam._clamp(Vector2(272, 688))
	await _shot("camp")

	main._spawn_saul()
	_freeze(r)
	var king: Npc = null
	var elder: Npc = null
	var woman: Npc = null
	for npc in r.npcs:
		if npc.npc_id() == "saul":
			king = npc
		elif npc.npc_id() == "elder":
			elder = npc
		elif npc.npc_id() == "woman":
			woman = npc
	if king == null or elder == null or woman == null:
		printerr("missing real camp actors")
		get_tree().quit(1)
		return
	r.player.global_position = king.global_position + Vector2(-30, 12)
	r.cam.global_position = r.cam._clamp(king.global_position)
	await _shot("saul")

	# Frame tree pairs, the stream, and the dry ridge at authored world points.
	r.player.global_position = Vector2(264, 536)
	r.cam.global_position = r.cam._clamp(Vector2(264, 536))
	await _shot("trees")
	r.player.global_position = Vector2(264, 448)
	r.cam.global_position = r.cam._clamp(Vector2(264, 432))
	await _shot("crossing")
	# The two Elah texture halves meet at y=384 world units. Centre the join
	# in a real frame so filtering or placement seams can be reviewed by eye.
	r.player.global_position = Vector2(264, 384)
	r.cam.global_position = r.cam._clamp(Vector2(264, 384))
	await _shot("elah-seam")
	r.player.global_position = Vector2(240, 174)
	r.cam.global_position = r.cam._clamp(Vector2(264, 145))
	await _shot("ridge")

	for item in [["front", Vector2.DOWN], ["right", Vector2.RIGHT],
			["left", Vector2.LEFT], ["back", Vector2.UP]]:
		await _walk_player(r, "witness-" + str(item[0]), Vector2(264, 600), item[1],
			0.80, str(item[0]) == "right")
	await _walk_player(r, "witness-run-right", Vector2(264, 600), Vector2.RIGHT, 1.0)
	await _walk_patrol(r, elder, "patrol-right")
	# Keep the earlier patroller out of the second actor's inspection crop.
	elder.visible = false
	await _walk_patrol(r, woman, "woman-right")
	elder.visible = true

	# The shepherd stage is a separate reference painting, not the new terrain.
	r.enter_shepherd_field()
	main._start_flock()
	_freeze(r)
	for item in r.pickups:
		var sheep = item.get("node")
		if is_instance_valid(sheep):
			sheep.set_process(false)
	main.hud.set_role("David", 1)
	main.hud.set_prompt("")
	main.hud.set_objective("Before dark, bring the three strays back to the fold. 0/3")
	r.player.facing = Vector2i(0, 1)
	r.player.mode = Player.Mode.IDLE
	r.player._update_anim(0.0, 0.2)
	await _shot("field")
	var field_start: Vector2 = r.shepherd_field.world(r.shepherd_field.START)
	for item in [["front", Vector2.DOWN], ["right", Vector2.RIGHT],
			["left", Vector2.LEFT], ["back", Vector2.UP]]:
		await _walk_player(r, "david-" + str(item[0]), field_start, item[1],
			0.80, str(item[0]) == "right")
	r.leave_shepherd_field()
	_freeze(r)
	# The armour overlay is a separate production node. Inspect its alignment
	# during the actual slowed and staggered David movement, in three views.
	r.player.set_armour(true)
	for item in [["front", Vector2.DOWN], ["right", Vector2.RIGHT], ["back", Vector2.UP]]:
		await _walk_player(r, "david-armour-" + str(item[0]), Vector2(264, 600), item[1],
			0.80, str(item[0]) == "right")
	r.player.set_armour(false)
	main.hud.clear_role()

	main._swap_region("bethlehem")
	await _frames(12)
	main.card.hide_now()
	r = main.region
	r.dialogue.hide_box()
	_freeze(r)
	r.player.global_position = Vector2(264, 240)
	r.cam.global_position = Vector2(264, 190)
	await _shot("bethlehem")
	# Bethlehem's corresponding texture join is at y=256 world units.
	r.player.global_position = Vector2(264, 256)
	r.cam.global_position = r.cam._clamp(Vector2(264, 256))
	await _shot("bethlehem-seam")
	r.player.global_position = Vector2(264, 208)
	r.cam.global_position = r.cam._clamp(Vector2(264, 132))
	await _shot("houses")
	r.player.global_position = Vector2(240, 352)
	r.cam.global_position = r.cam._clamp(Vector2(210, 320))
	await _shot("well")
	print("refinement visual fixture finished (%d failures)" % failures)
	get_tree().quit(1 if failures > 0 else 0)
