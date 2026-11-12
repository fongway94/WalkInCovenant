extends Node
## Manual review fixture, NOT a gameplay test or a claim of art approval.
## Run with an isolated XDG_DATA_HOME and a display. It stages the real region
## and camera at fixed positions and writes full framebuffer PNGs under build/.
## Before/after shots use the same live objects, camera, sizes and lighting;
## only the ground and human rig textures are swapped. Saves are not evidence
## of a real person playing or of a physical phone's rendering/performance.

const CAPTURE_DIR := "res://build/reference-pass-captures"
var main = null


func _ready() -> void:
	_run()


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _shot(label: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var dir := ProjectSettings.globalize_path(CAPTURE_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	if image == null or image.save_png(dir + "/" + label + ".png") != OK:
		printerr("could not capture " + label)
		get_tree().quit(1)
	else:
		print("captured %s %s" % [label, str(image.get_size())])


## Count changed framebuffer pixels in a character's lower silhouette. Unlike a
## sort-order property check, this fails if a foreground prop actually hides the
## body. The comparison uses the same camera and scene with only that NPC hidden.
func _lower_actor_delta(before: Image, after: Image, actor: Npc) -> Vector2i:
	var transform := actor.get_global_transform_with_canvas()
	# Canvas coordinates are logical pixels; the captured framebuffer can have
	# a larger device-scale backing (for example 400x180 -> 1000x450).
	var logical := get_viewport().get_visible_rect().size
	var pixel_scale := Vector2(float(after.get_width()) / logical.x, float(after.get_height()) / logical.y)
	var feet := transform.origin * pixel_scale
	var height := actor.visual_height() * transform.y.length() * pixel_scale.y
	var half_width: float = 35.0 * actor.human_visual.scale.x * transform.x.length() * pixel_scale.x
	var x0 := maxi(0, floori(feet.x - half_width))
	var x1 := mini(after.get_width(), ceili(feet.x + half_width))
	var y0 := maxi(0, floori(feet.y - height * 0.48))
	var y1 := mini(after.get_height(), ceili(feet.y - 1.0))
	var changed := 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.12:
				changed += 1
	return Vector2i(changed, maxi(0, x1 - x0) * maxi(0, y1 - y0))


func _freeze(r: Region) -> void:
	r.set_process(false)
	r.player.set_physics_process(false)
	r.player.velocity = Vector2.ZERO
	r.cam.set_process(false)
	for n in r.npcs:
		n.set_process(false)
		n.set_physics_process(false)
		if n._bubble != null:
			n._bubble.visible = false


func _rig_skin(rig, actor: String, reference: bool, facing: Vector2i) -> void:
	if rig == null or not rig.visible:
		return
	var directory := "res://art/characters_reference/" if reference else "res://art/characters_painted/"
	var poses := {}
	for pose in ["front", "profile", "back"]:
		var prefix: String = directory + actor + "_" + str(pose)
		if ResourceLoader.exists(prefix + "_body.png"):
			poses[pose] = [load(prefix + "_body.png"), load(prefix + "_boot_left.png"),
				load(prefix + "_boot_right.png")]
	if poses.is_empty():
		return
	rig._poses = poses
	rig._pose_name = ""
	rig.set_pose(facing, false, 0.0, 1.0)


func _skin(r: Region, reference: bool) -> void:
	var suffix := "_reference" if reference else ""
	r.terrain.set_painted_ground(load("res://art/scenes_painted/world_%s%s.png" % [r.region_id, suffix]))
	_rig_skin(r.player.human_visual, "pilgrim", reference, r.player.facing)
	for n in r.npcs:
		var actor := str(Npc.PAINTED_ACTORS.get(n.actor_id, ""))
		if not reference and actor in ["samuel", "jesse"]:
			actor = "elder" # The prior cast reused this figure for both.
		elif not reference and actor in ["king", "eliab"]:
			actor = "corin" # Saul and Eliab previously reused Corin's rig.
		if actor != "":
			_rig_skin(n.human_visual, actor, reference, n.facing)


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
	_skin(r, false)
	await _shot("camp-before")
	_skin(r, true)
	await _shot("camp-after")

	# The witness turns, at the same feet position, to reveal interim directions.
	for item in [["profile", Vector2i(1, 0)], ["back", Vector2i(0, -1)]]:
		r.player.facing = item[1]
		r.player.mode = Player.Mode.IDLE
		r.player._update_anim(0.0, 0.0)
		await _shot("witness-" + str(item[0]))
	r.player.facing = Vector2i(1, 0)
	r.player.mode = Player.Mode.MOVING
	for _i in range(4):
		r.player._update_anim(60.0, 0.08)
	await _shot("witness-walking")

	# Turn the actual camp cast together without moving their feet.
	for item in [["profile", Vector2i(1, 0)], ["back", Vector2i(0, -1)]]:
		r.player.facing = item[1]
		r.player.mode = Player.Mode.IDLE
		r.player._update_anim(0.0, 0.2)
		for n in r.npcs:
			if n.npc_id() in ["corin", "boy", "woman"] and n.human_visual != null:
				n.human_visual.set_pose(item[1], false, 0.0, 0.2)
		await _shot("camp-cast-" + str(item[0]))
	# The separate elder is north of the camp; frame him in the real map.
	for n in r.npcs:
		if n.npc_id() == "elder" and n.human_visual != null:
			r.cam.global_position = r.cam._clamp(n.global_position)
			for item in [["profile", Vector2i(1, 0)], ["back", Vector2i(0, -1)]]:
				n.human_visual.set_pose(item[1], false, 0.0, 0.2)
				await _shot("elder-" + str(item[0]))

	# A separate, genuine field fixture: David and animals are live game nodes.
	r.player.facing = Vector2i(0, 1)
	r.set_time_of_day("dusk")
	r.enter_shepherd_field()
	main._start_flock()
	_freeze(r)
	for item in r.pickups:
		var animal = item.get("node")
		if is_instance_valid(animal):
			animal.set_process(false)
	main.hud.set_role("David", 1)
	main.hud.set_prompt("")
	main.hud.set_objective("Before dark, bring the three strays back to the fold. 0/3")
	r.player.mode = Player.Mode.IDLE
	r.player._update_anim(0.0, 0.2)
	await _shot("shepherd-field")
	for item in [["profile", Vector2i(1, 0)], ["back", Vector2i(0, -1)]]:
		r.player.facing = item[1]
		r.player._update_anim(0.0, 0.2)
		await _shot("david-" + str(item[0]))
	r.player.facing = Vector2i(1, 0)
	r.player.mode = Player.Mode.MOVING
	for _i in range(4):
		r.player._update_anim(40.0, 0.08)
	await _shot("david-walking")
	# Sample the production depth layers from both sides. Coordinates are
	# staged in painting space; this is a render check, not a playthrough.
	r.player.mode = Player.Mode.IDLE
	r.player.facing = Vector2i(0, 1)
	r.player._update_anim(0.0, 0.2)
	for item in [["fence-back", Vector2(900, 215)], ["fence-front", Vector2(900, 280)],
			["tree-back", Vector2(1100, 145)], ["tree-front", Vector2(1100, 220)],
			["foreground", Vector2(210, 575)]]:
		r.player.global_position = r.shepherd_field.world(item[1])
		r._update_field_depth()
		r.cam.global_position = r.cam._clamp(r.player.global_position)
		await _shot("field-" + str(item[0]))
	r.leave_shepherd_field()
	main.hud.clear_role()
	r.set_time_of_day("morning")

	# Bethlehem positions are staged to show the houses and the actual named
	# people together. Neither the map nor the interact resolver is modified.
	main._swap_region("bethlehem")
	await _frames(12)
	main.card.hide_now()
	r = main.region
	r.dialogue.hide_box()
	_freeze(r)
	r.player.global_position = Vector2(264, 240)
	r.cam.global_position = Vector2(264, 190)
	_skin(r, false)
	await _shot("bethlehem-before")
	_skin(r, true)
	await _shot("bethlehem-after")
	# Review the seated prophet, Jesse and Eliab at their actual map positions.
	# These angles are staged directly, not a played conversation.
	for item in [["front", Vector2i(0, 1)], ["profile", Vector2i(1, 0)],
			["back", Vector2i(0, -1)]]:
		for n in r.npcs:
			if n.npc_id() in ["samuel", "jesse", "eliab"] and n.human_visual != null:
				n.human_visual.set_pose(item[1], false, 0.0, 0.2)
		await _shot("bethlehem-cast-" + str(item[0]))
	for n in r.npcs:
		if n.npc_id() in ["samuel", "jesse", "eliab"] and n.human_visual != null:
			n.human_visual.set_pose(Vector2i(0, 1), false, 0.0, 0.2)
	# A second camera position makes the two houses visible below the HUD.
	r.player.global_position = Vector2(264, 208)
	r.cam.global_position = r.cam._clamp(Vector2(264, 132))
	await _shot("bethlehem-houses")
	# Keep the witness clear of the well; the previous framing hid it behind
	# the character and under the HUD, defeating this specific review shot.
	r.player.global_position = Vector2(240, 352)
	r.cam.global_position = r.cam._clamp(Vector2(210, 320))
	await _shot("bethlehem-well")

	# Saul is normally spawned later by the story; explicitly stage that same
	# production spawn to inspect his new art without claiming a playthrough.
	main._swap_region("elah")
	await _frames(12)
	main.card.hide_now()
	r = main.region
	main._spawn_saul()
	_freeze(r)
	var king: Npc = null
	for n in r.npcs:
		if n.npc_id() == "saul":
			king = n
			break
	if king == null or king.human_visual == null:
		printerr("could not stage Saul's painted rig")
		get_tree().quit(1)
		return
	r.player.global_position = king.global_position + Vector2(-30, 12)
	r.cam.global_position = r.cam._clamp(king.global_position)
	for item in [["front", Vector2i(0, 1)], ["profile", Vector2i(1, 0)],
			["back", Vector2i(0, -1)]]:
		king.human_visual.set_pose(item[1], false, 0.0, 0.2)
		await _shot("saul-" + str(item[0]))
	king.human_visual.set_pose(Vector2i(0, 1), false, 0.0, 0.2)
	# Stage the woman's actual short camp chatter where it previously covered
	# the king, and verify its on-screen panel clears both people and the player.
	var woman: Npc = null
	for n in r.npcs:
		if n.npc_id() == "woman":
			woman = n
			break
	if woman == null:
		printerr("could not stage the camp woman's chatter")
		get_tree().quit(1)
		return
	woman.emote("「水烧上了。坐会儿。」")
	await _frames(3)
	var ct := woman.get_global_transform_with_canvas()
	var chat_rect := Rect2(ct * woman._bubble.position,
		Vector2(ct.x.length() * woman._bubble.size.x, ct.y.length() * woman._bubble.size.y))
	var king_rect := woman._actor_canvas_rect(king.get_global_transform_with_canvas(), king.visual_height()).grow(3.0)
	if not woman._bubble.visible or chat_rect.intersects(king_rect) \
			or chat_rect.intersects(woman._speaker_canvas_rect(ct)) \
			or chat_rect.intersects(woman._player_canvas_rect()):
		printerr("camp chatter is not visible or covers Saul, its speaker or the player")
		get_tree().quit(1)
		return
	await _shot("saul-chatter")
	woman._bubble.visible = false
	king.visible = false
	await _frames(3)
	await RenderingServer.frame_post_draw
	var without_king := get_viewport().get_texture().get_image()
	king.visible = true
	await _frames(3)
	await RenderingServer.frame_post_draw
	var with_king := get_viewport().get_texture().get_image()
	var delta := _lower_actor_delta(without_king, with_king, king)
	print("Saul's lower-body framebuffer delta: %s" % str(delta))
	if delta.y <= 0 or float(delta.x) / float(delta.y) < 0.35:
		printerr("Saul's lower body is not visible in the rendered tent")
		get_tree().quit(1)
		return
	# Negative control: temporarily restore the previously occluding tent and
	# its old foot sort point, without saving this staged frame. The same pixel
	# assertion must detect that the lower body has disappeared.
	var tent: Sprite2D = null
	for prop in r._prop_sprites:
		if prop["key"] == "tent" and prop["at"] == Region.ROYAL_TENT_AT:
			tent = prop["sprite"]
			break
	if tent == null:
		printerr("could not find Saul's tent for the render control")
		get_tree().quit(1)
		return
	var tent_texture := tent.texture
	var tent_position := tent.position
	var tent_offset := tent.offset
	tent.texture = load("res://art/props_painted/tent_camp_b.png")
	tent.position.y = float(Region.ROYAL_TENT_AT.y + 1) * Region.TILE
	tent.offset = Vector2(0, -tent.texture.get_height() * 0.5)
	king.visible = false
	await _frames(3)
	await RenderingServer.frame_post_draw
	without_king = get_viewport().get_texture().get_image()
	king.visible = true
	await _frames(3)
	await RenderingServer.frame_post_draw
	with_king = get_viewport().get_texture().get_image()
	var old_delta := _lower_actor_delta(without_king, with_king, king)
	tent.texture = tent_texture
	tent.position = tent_position
	tent.offset = tent_offset
	print("Previous occluded lower-body control: %s" % str(old_delta))
	if old_delta.y <= 0 or float(old_delta.x) / float(old_delta.y) >= 0.35:
		printerr("the render check did not detect the old tent occlusion")
		get_tree().quit(1)
		return
	# The tent remains visible. Also stage the player on either side of its
	# back-wall sort point to inspect real depth behavior, not just the doorway.
	king.human_visual.set_pose(Vector2i(0, 1), false, 0.0, 0.2)
	r.player.global_position = Vector2(310, 636)
	await _shot("saul-tent-behind")
	r.player.global_position = Vector2(310, 700)
	await _shot("saul-tent-front")

	# The shipped full-screen setpieces, staged for inspection. The harness
	# supplies state only; each scene paints its own art and controls.
	main.practice = SlingPractice.new()
	main.add_child(main.practice)
	main.practice.start(3)
	main.practice.set_process(false)
	main.practice.aim_perfect()
	main.practice._layer.queue_redraw()
	main._update_touch_ownership()
	await _shot("practice")
	main.practice.queue_free()
	main.practice = null
	await _frames(2)

	main.stones_panel = StoneChoice.new()
	main.add_child(main.stones_panel)
	main.stones_panel.start(5, 9)
	main.stones_panel._layer.queue_redraw()
	main._update_touch_ownership()
	await _shot("brook")
	main.stones_panel.queue_free()
	main.stones_panel = null
	await _frames(2)

	main.fight = GoliathFight.new()
	main.fight.objective_text = "Dodge the spear, then find the moment to throw."
	main.add_child(main.fight)
	main.fight.start()
	main.fight.set_process(false)
	main.fight.phase = GoliathFight.Phase.AIM
	main.fight._marker = 0.0
	main.fight._layer.queue_redraw()
	main._update_touch_ownership()
	await _shot("duel")
	print("reference visual fixture finished")
	get_tree().quit()
