extends Node
## Tests the actual production Region's field lifecycle and the shared David
## rig. Headless checks geometry/state, not whether the picture looks good.

var failures := 0
var checks := 0


func _ready() -> void:
	_run()


func _run() -> void:
	GameState.new_game()
	var main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().process_frame
	# Exercise the reversible classic round trip independently of the default.
	main.apply_art_theme("classic")
	main.set_process(false)
	var region: Region = main.region
	region.set_process(false)
	var previous_bounds := region.cam.bounds
	var previous_zoom := region.cam.zoom
	var boy: Npc = null
	for npc in region.npcs:
		if npc.npc_id() == "hired_boy":
			boy = npc
	var old_boy := boy.global_position
	region.enter_shepherd_field()
	var field = region.shepherd_field
	var player := region.player
	player.set_physics_process(false)
	_check(field != null and field.get_node("Backdrop") != null, "approved backdrop installed in production")
	var backdrop: Sprite2D = field.get_node("Backdrop")
	var tree: Sprite2D = field.get_node("Tree")
	var fence: Sprite2D = field.get_node("Fence")
	var foreground: Sprite2D = field.get_node("Foreground")
	_check(backdrop.texture.resource_path.ends_with("shepherd_field_reference.png")
		and tree.texture.resource_path.ends_with("shepherd_field_reference_tree.png")
		and fence.texture.resource_path.ends_with("shepherd_field_reference_fence.png")
		and foreground.texture.resource_path.ends_with("shepherd_field_reference_foreground.png"),
		"production uses the restored backdrop and its matching depth layers")
	_check(backdrop.texture.get_size() == Vector2(1440, 666)
		and tree.texture.get_size() == backdrop.texture.get_size()
		and fence.texture.get_size() == backdrop.texture.get_size()
		and foreground.texture.get_size() == Vector2(440, 416)
		and foreground.position == Vector2(0, 250),
		"restored layers retain the approved painting coordinates")
	var bg_image := backdrop.texture.get_image()
	_check(_layer_matches(bg_image, tree.texture.get_image(), Vector2i.ZERO)
		and _layer_matches(bg_image, fence.texture.get_image(), Vector2i.ZERO)
		and _layer_matches(bg_image, foreground.texture.get_image(), Vector2i(0, 250)),
		"visible depth-layer samples match their registered backdrop pixels")
	_check(not region.terrain.visible and region.cam.bounds == field.world_bounds(),
		"painted field owns view bounds, with tile terrain hidden")
	var normal_zoom: float = field.camera_zoom_for(Vector2(320, 180))
	var tall_zoom: float = field.camera_zoom_for(Vector2(320, 240))
	var wide_zoom: float = field.camera_zoom_for(Vector2(640, 180))
	var field_size: Vector2 = field.world_bounds().size
	_check(is_equal_approx(normal_zoom, 0.9) and 320.0 / tall_zoom < field_size.x
		and 240.0 / tall_zoom < field_size.y and 640.0 / wide_zoom < field_size.x,
		"field framing fills 16:9, 4:3 and ultra-wide views without exposing empty space")
	_check(is_equal_approx(region.cam.zoom.x,
		field.camera_zoom_for(get_viewport().get_visible_rect().size)),
		"the live field camera uses the viewport-aware framing")
	_check(player.char_id == "david" and player.david_visual.visible and not player.sprite.visible,
		"player visibly becomes David")
	_check(boy.visible and boy.field_sprite.visible and not boy.sprite.visible,
		"hired boy is an independent field actor")
	boy.emote("Two more.")
	await get_tree().process_frame
	var bubble_transform := boy.get_global_transform_with_canvas()
	var bubble_top := (bubble_transform * boy._bubble.position).y
	var bubble_bottom := bubble_top + bubble_transform.y.length() * boy._bubble.size.y
	_check(bubble_top >= Npc.BUBBLE_SAFE_TOP - 0.01
		and bubble_bottom <= get_viewport().get_visible_rect().size.y - Npc.BUBBLE_SAFE_BOTTOM + 0.01,
		"the hired boy's reaction clears the HUD, toast and thumb controls")
	_check(boy._bubble.z_index > 4 and not boy._bubble.z_as_relative
		and boy._bubble.size.x < Npc.BUBBLE_W,
		"a short field reaction stays above actors and uses a compact bubble")
	var bpos: Vector2 = bubble_transform * boy._bubble.position
	var bsize := Vector2(bubble_transform.x.length() * boy._bubble.size.x,
		bubble_transform.y.length() * boy._bubble.size.y)
	_check(not Rect2(bpos, bsize).intersects(boy._speaker_canvas_rect(bubble_transform)),
		"a clamped reaction does not cover its speaker")
	# Reproduce a distant boy's panel landing over David at the edge of its
	# clamped position. The reaction should move without moving either actor.
	var player_before := player.global_position
	player.global_position = get_viewport().get_canvas_transform().affine_inverse() * (bpos + bsize * 0.5)
	_check(Rect2(bpos, bsize).intersects(boy._player_canvas_rect()),
		"the overlap fixture places David under the original reaction")
	boy._position_bubble()
	var moved: Vector2 = bubble_transform * boy._bubble.position
	_check(not Rect2(moved, bsize).intersects(boy._player_canvas_rect())
		and not Rect2(moved, bsize).intersects(boy._speaker_canvas_rect(bubble_transform)),
		"a clamped reaction avoids both David and its speaker")
	player.global_position = player_before
	boy._position_bubble()
	var fits := true
	for line in ["“Two more.”", "“Just the one down the slope.”", "“All in. I'll shut the rail.”",
			"「还有两只。」", "「就剩坡下那只了。」", "「都回来了。我把横木合上。」"]:
		boy.emote(line)
		var label: Label = boy._bubble_lbl
		var text_width := label.get_theme_font("font").get_string_size(line,
			HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
		fits = fits and text_width <= label.size.x
	_check(fits, "all six English and Chinese field reactions fit their single-line labels")
	_check(field.walkable(field.world(field.START)) and not field.walkable(field.world(Vector2(630, 240))),
		"field start is open and painted rock is solid")
	_check(player.collision_override.is_valid() and player.world_speed_scale < 1.0,
		"field collision and appropriately scaled movement are active")
	_check(is_equal_approx(player._surface_speed(), 1.0)
		and player._surface_sound() == "step_grass" and not player.clamp_to_model,
		"field footsteps, speed and bounds do not use the hidden valley")
	var rig = player.david_visual
	var expected := [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]
	var names := ["front", "profile", "profile", "back"]
	for i in range(expected.size()):
		player.facing = expected[i]
		player.mode = Player.Mode.MOVING
		player._update_anim(60.0, 0.16)
		_check(rig.direction == expected[i] and rig._pose_name == names[i] and rig.moving,
			"direction %s selects its walk pose" % str(expected[i]))
		_check(rig.body.flip_h == (expected[i] == Vector2i(-1, 0)),
			"direction %s has correct profile orientation" % str(expected[i]))
		player.mode = Player.Mode.IDLE
		player._update_anim(0.0, 0.2)
		_check(rig.direction == expected[i] and not rig.moving and rig.gait_amount == 0.0,
			"direction %s is retained at idle" % str(expected[i]))
	_check(rig.body.offset == Vector2(0, -49) and rig.boot_left.offset == rig.body.offset
		and rig.boot_right.offset == rig.body.offset, "all layers share a foot anchor")
	# Walk into the painted fence from the north using the real feet-box sweep.
	player.global_position = field.world(Vector2(920, 190))
	for i in range(90):
		player.velocity = Vector2(0, 30)
		player._move_with_collision(1.0 / 60.0)
	var stop_art: Vector2 = (player.global_position - field.ORIGIN) / field.PAINT_SCALE
	_check(stop_art.y < 228.0 and stop_art.y >= 215.0,
		"feet collide with fence rather than the hidden grid (y=%.1f)" % stop_art.y)
	player.global_position = field.world(Vector2(920, 190))
	player.velocity = Vector2(0, 90)
	player._move_with_collision(0.8)
	stop_art = (player.global_position - field.ORIGIN) / field.PAINT_SCALE
	_check(stop_art.y < 228.0 and player._box_free(player.global_position.x, player.global_position.y),
		"a slow-frame sweep cannot tunnel through the painted fence")
	# Existing quests and flags are still owned by Main/Region.
	main._start_flock()
	var live := 0
	for pickup in region.pickups:
		if str(pickup.get("kind", "")) != "flock":
			continue
		var animal: FlockSheep = pickup.get("node")
		live += 1
		_check(animal._field_frames.size() == 3 and animal.fold == field.world(field.FOLD),
			"%s is a live, field-scaled animal with fold" % animal.sheep_id)
		_check(field.walkable(animal.global_position), "%s starts clear of obstacles" % animal.sheep_id)
		animal.set_process(false)
		animal.arrived.disconnect(region._on_sheep_arrived)
		var home_signal := [false]
		animal.arrived.connect(func(_id, _guided): home_signal[0] = true)
		var route: PackedVector2Array = field.sheep_route(animal.global_position, animal.fold)
		var clear := not route.is_empty()
		var last := animal.global_position
		for point in route:
			clear = clear and field.segment_clear(last, point)
			last = point
		_check(clear and last.distance_to(animal.fold) < 0.1,
			"%s has a collision-safe route to the fold" % animal.sheep_id)
		var safe := true
		for i in range(2400):
			var before := animal.global_position
			animal._step_toward_fold(1.0 / 60.0)
			safe = safe and field.segment_clear(before, animal.global_position)
			if home_signal[0]:
				break
		_check(safe and home_signal[0], "%s follows its route and arrives" % animal.sheep_id)
	_check(live == 3 and main._flock_active, "production flock and quest are active")
	var departing: FlockSheep = null
	for pickup in region.pickups:
		if bool(pickup.get("field_flock", false)):
			departing = pickup.get("node")
			break
	departing.go_home()
	_check(departing._leaving, "a counted sheep begins its routed return")
	region.leave_shepherd_field()
	_check(departing.is_queued_for_deletion(),
		"leaving during a return removes the field-only animal immediately")
	await get_tree().process_frame
	var field_pickups := 0
	for pickup in region.pickups:
		if bool(pickup.get("field_flock", false)):
			field_pickups += 1
	_check(not is_instance_valid(departing) and field_pickups == 0,
		"field-only sheep cannot leak into the restored valley")
	_check(region.shepherd_field == null and region.terrain.visible,
		"leaving restores the original valley")
	_check(region.cam.bounds == previous_bounds and region.cam.zoom == previous_zoom,
		"leaving restores camera bounds and zoom")
	_check(not player.collision_override.is_valid() and player.world_speed_scale == 1.0
		and player.surface_speed_override < 0.0 and player.footstep_override == "" and player.clamp_to_model,
		"leaving restores normal grid movement, surface and bounds")
	_check(player.sprite.visible and not player.david_visual.visible,
		"classic theme restores the classic David sheet after the field")
	_check(boy.global_position == old_boy and boy.sprite.visible and not boy.field_sprite.visible,
		"leaving restores the NPC's original position and art")
	_finish()


## Opaque samples should have the same colours as the image below them; a
## mismatched old mask can otherwise leave a visible outline when actors move.
func _layer_matches(background: Image, layer: Image, offset: Vector2i) -> bool:
	var samples := 0
	for y in range(0, layer.get_height(), 9):
		for x in range(0, layer.get_width(), 9):
			var front := layer.get_pixel(x, y)
			if front.a < 0.99:
				continue
			var back := background.get_pixel(x + offset.x, y + offset.y)
			if absf(front.r - back.r) > 0.015 or absf(front.g - back.g) > 0.015 \
					or absf(front.b - back.b) > 0.015:
				return false
			samples += 1
	return samples > 10


func _check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("PASS stage: " + message)
	else:
		failures += 1
		printerr("FAIL stage: " + message)


func _finish() -> void:
	print("shepherd stage: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
