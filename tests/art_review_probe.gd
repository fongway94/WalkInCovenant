extends Node
## Real in-game frames for the river, tall-tree and north-figure review.
##
## This is a staged capture, not a playthrough and not art approval. It boots
## the production Main scene, freezes ambient motion so two runs differ only in
## art, and frames exactly the same world points the previous session used for
## its "before" framebuffers (tools/art/sources/pending_river_tree_soldier/
## evidence). That makes the before/after pairs comparable at identical camera
## positions. The frames are written to build/art-review and are too large to
## publish in the main frame-annotation budget, so the workflow uploads them as
## an artifact and a separate job reprints them.

const CAPTURE_DIR := "res://build/art-review"
var main = null
var failures := 0


func _ready() -> void:
	_run()


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _save(image: Image, name: String) -> void:
	var dir := ProjectSettings.globalize_path(CAPTURE_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	if image == null or image.save_png(dir + "/" + name + ".png") != OK:
		printerr("could not capture " + name)
		failures += 1


func _freeze(r: Region) -> void:
	r.set_process(false)
	r.player.set_physics_process(false)
	r.player.velocity = Vector2.ZERO
	r.cam.set_process(false)
	for npc in r.npcs:
		npc.set_process(false)
		npc.set_physics_process(false)
		if npc.data.has("at"):
			var at: Array = npc.data["at"]
			npc.global_position = Vector2(int(at[0]) * 16.0 + 8.0, (int(at[1]) + 1) * 16.0 - 2.0)
			npc.facing = Vector2i(0, 1)
			if npc.human_visual != null:
				npc.human_visual.set_pose(npc.facing, false, 0.0, 0.2)
		if npc._bubble != null:
			npc._bubble.visible = false


func _shot(r: Region, name: String, player: Vector2, camera: Vector2,
		facing: Vector2i = Vector2i(0, 1)) -> void:
	r.player.global_position = player
	r.player.facing = facing
	r.cam.global_position = r.cam._clamp(camera)
	for _i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save(get_viewport().get_texture().get_image(), name)
	print("captured " + name + " at " + str(player))


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
	if r.terrain == null or r.terrain.painted_ground == null:
		printerr("painted ground was not applied; review frames would be invalid")
		failures += 1
	if r.goliath_sprite == null:
		printerr("the ridge figure is missing")
		failures += 1

	# 1. The ford: same player/camera as the saved before framebuffer.
	await _shot(r, "01_river", Vector2(264, 448), Vector2(264, 432), Vector2i.DOWN)
	# 2. Trees beside people: same framing as the saved before framebuffer.
	await _shot(r, "02_trees", Vector2(264, 536), Vector2(264, 536), Vector2i.DOWN)
	# 3. A person standing at an olive trunk, for a direct height comparison.
	await _shot(r, "03_tree_scale", Vector2(416, 552), Vector2(352, 520), Vector2i.LEFT)
	# 4. Walking north: the figure on the ridge, same framing as "before".
	await _shot(r, "04_north_figure", Vector2(240, 164), Vector2(264, 100), Vector2i.UP)

	print("art review fixture finished (%d failures)" % failures)
	get_tree().quit(1 if failures > 0 else 0)
