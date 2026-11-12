extends Node
## Runtime contracts for the painterly chapter. This suite exercises real
## Region/Player/Npc/setpiece objects headlessly; it does not judge pixels or
## replace rendered review, a complete playthrough, or a physical-device test.

var checks := 0
var failures := 0


func _ready() -> void:
	_run()


func _run() -> void:
	GameState.new_game()
	GameState.data["settings"]["reduce_motion"] = true
	var main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().process_frame
	main.set_process(false)
	var r: Region = main.region
	r.set_process(false)
	var player: Player = r.player
	player.set_physics_process(false)
	var solid_before := r.model._solid.duplicate()
	var original_giant_pos := r.goliath_sprite.position
	_check(ArtDirection.current() == "cinematic" and r._art_theme == "cinematic",
		"the shared production default applies to Main on this platform")
	_check(r.terrain.painted_ground != null and r.terrain.painted_ground_bottom != null
		and r.terrain.painted_ground.resource_path.ends_with("world_elah_refined_top.png")
		and r.terrain.painted_ground_bottom.resource_path.ends_with("world_elah_refined_bottom.png")
		and r.terrain.painted_ground.get_size() == Vector2(2048, 1536)
		and r.terrain.painted_ground_bottom.get_size() == Vector2(2048, 1536),
		"default Elah uses both aligned, phone-sized refined ground pieces")
	_check(r.model._solid == solid_before, "art selection does not alter collision")
	_check(player.human_visual != null and player.human_visual.visible and not player.sprite.visible,
		"the witness uses the painted rig")
	_check(player.human_visual != null and player.human_visual._poses.has("front")
		and (player.human_visual._poses["front"][0] as Texture2D).resource_path.ends_with(
			"characters_reference/pilgrim_front_body.png"),
		"the runtime loads the reference-direction witness assets")
	if player.human_visual != null:
		_check(is_equal_approx(player.human_visual.scale.x, Player.WORLD_RIG_SCALE),
			"the witness is scaled for the tile world")
		var directions := [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]
		var poses := ["front", "profile", "profile", "back"]
		for i in range(directions.size()):
			player.facing = directions[i]
			player.mode = Player.Mode.MOVING
			player._update_anim(60.0, 0.1)
			_check(player.human_visual._pose_name == poses[i]
				and player.human_visual.body.flip_h == (directions[i] == Vector2i(-1, 0))
				and player.human_visual.body.texture.resource_path.ends_with(
					"characters_reference/pilgrim_%s_body.png" % poses[i]),
				"witness direction %s selects the correct pose" % str(directions[i]))
	var corin: Npc = null
	var boy: Npc = null
	var woman: Npc = null
	for n in r.npcs:
		if n.npc_id() == "corin":
			corin = n
		elif n.npc_id() == "hired_boy":
			boy = n
		elif n.npc_id() == "woman":
			woman = n
	_check(corin != null and corin.human_visual != null and corin.human_visual.visible
		and not corin.sprite.visible, "Corin is an independent painted actor")
	_check_gait_contract(r, player)
	for spec in [[boy, "boy", Vector2i(1, 0), "profile"],
			[boy, "boy", Vector2i(-1, 0), "profile"],
			[boy, "boy", Vector2i(0, -1), "back"],
			[woman, "woman", Vector2i(1, 0), "profile"],
			[woman, "woman", Vector2i(-1, 0), "profile"],
			[woman, "woman", Vector2i(0, -1), "back"]]:
		var person: Npc = spec[0]
		var actor: String = spec[1]
		var direction: Vector2i = spec[2]
		var view: String = spec[3]
		if person == null or person.human_visual == null:
			_check(false, "%s has a directional rig" % actor)
			continue
		person.human_visual.set_pose(direction, false, 0.0, 0.1)
		_check(person.human_visual._pose_name == view
			and person.human_visual.body.flip_h == (direction.x < 0)
			and person.human_visual.body.texture.resource_path.ends_with(
				"characters_reference/%s_%s_body.png" % [actor, view]),
			"%s %s uses the generated %s pose" % [actor, str(direction), view])
	# Saul is spawned later by the story. Exercise that production spawn and
	# original map position, not a moved stand-in, including all directions.
	main._spawn_saul()
	var test_king: Npc = null
	for n in r.npcs:
		if n.npc_id() == "saul":
			test_king = n
			break
	_check(test_king != null, "the production Saul spawn is present")
	if test_king == null:
		get_tree().quit(1)
		return
	var king_anchor := test_king.global_position
	var royal_tent: Sprite2D = null
	var royal_shadow: Dictionary = {}
	for entry in r._prop_sprites:
		if str(entry["key"]) == "tent" and entry["at"] == Region.ROYAL_TENT_AT:
			royal_tent = entry["sprite"]
			royal_shadow = entry["shadow"]
			break
	_check(king_anchor == Vector2(344, 670) and royal_tent != null
		and royal_tent.texture.resource_path.ends_with("/tent_royal_open.png")
		and royal_tent.get_parent() == r._ys and royal_tent.position.y < king_anchor.y
		and royal_tent.z_index == test_king.z_index,
		"Saul stays at his story position and the open tent sorts behind him")
	_check(royal_tent != null and is_equal_approx(
		royal_tent.position.y + (royal_tent.offset.y + royal_tent.texture.get_height() * 0.5)
		* royal_tent.scale.y, float(Region.ROYAL_TENT_AT.y + 1) * Region.TILE)
		and royal_shadow.get("offset", Vector2.ZERO) == Vector2(0, Region.ROYAL_TENT_SORT_RAISE)
		and royal_tent.position + Vector2(royal_shadow.get("offset", Vector2.ZERO))
			== Vector2(336, 688),
		"the open tent's visual base and shadow retain the authored ground anchor")
	var player_before_king := player.global_position
	player.global_position = king_anchor + Vector2(-19, 0)
	var king_target := r.context_target()
	_check(str(king_target.get("kind", "")) == "npc" and str(king_target.get("id", "")) == "saul"
		and player.global_position.distance_to(king_anchor) <= Region.TALK_RANGE,
		"Saul can be selected from beside the open doorway without changing interaction range")
	if woman != null:
		woman.emote("「水烧上了。坐会儿。」")
		var ct := woman.get_global_transform_with_canvas()
		var panel := Rect2(ct * woman._bubble.position,
			Vector2(ct.x.length() * woman._bubble.size.x, ct.y.length() * woman._bubble.size.y))
		var king_body := woman._actor_canvas_rect(test_king.get_global_transform_with_canvas(),
			test_king.visual_height()).grow(3.0)
		_check(woman._bubble.visible and not panel.intersects(king_body)
			and not panel.intersects(woman._player_canvas_rect())
			and not panel.intersects(woman._speaker_canvas_rect(ct)),
			"nearby ambient chatter leaves Saul, its speaker and the player visible")
		woman._bubble.visible = false
	else:
		_check(false, "the camp woman is present to test chatter")
	player.global_position = player_before_king
	for item in [[Vector2i(0, 1), "front"], [Vector2i(1, 0), "profile"],
			[Vector2i(-1, 0), "profile"], [Vector2i(0, -1), "back"]]:
		var direction: Vector2i = item[0]
		var pose: String = item[1]
		test_king.face_toward(king_anchor + Vector2(direction) * 50.0)
		_check(test_king.human_visual != null and test_king.human_visual._pose_name == pose
			and test_king.human_visual.body.flip_h == (direction.x < 0)
			and test_king.human_visual.body.texture.resource_path.ends_with(
				"characters_reference/king_%s_body.png" % pose)
			and test_king.global_position == king_anchor,
			"dynamically spawned Saul keeps his anchor and uses his %s pose" % pose)
	test_king.apply_art_theme("classic")
	_check(test_king.sprite.visible and not test_king.human_visual.visible
		and test_king.sprite.texture.resource_path.ends_with("characters/king_idle.png")
		and test_king.global_position == king_anchor,
		"Saul returns to classic art without changing position")
	test_king.apply_art_theme(ArtDirection.current())
	_check(test_king.human_visual.visible and not test_king.sprite.visible
		and test_king.human_visual.body.texture.resource_path.ends_with("characters_reference/king_back_body.png"),
		"Saul's directional reference art survives a classic round trip")
	r.npcs.erase(test_king)
	r._shadow_layer.call("remove_target", test_king)
	test_king.queue_free()
	var opening_target := r.context_target()
	_check(str(opening_target.get("kind", "")) == "npc" and str(opening_target.get("id", "")) == "corin"
		and absf(player.global_position.x - corin.global_position.x) >= 12.0,
		"the opening puts the first person in reach without overlapping or selecting the exit")
	if corin != null and corin.human_visual != null:
		corin.human_visual.set_pose(Vector2i(0, -1), true, 34.0, 0.1)
		_check(corin.human_visual._pose_name == "back", "moving Corin can face away")
		_check(is_equal_approx(corin.visual_height(), 98.0 * Player.WORLD_RIG_SCALE),
			"NPC markers use the displayed rig height")
		corin.emote("“The ink ran out on day nineteen.”")
		_check(corin._bubble_pages.size() == 1 or corin._bubble_pages[-1].contains(" "),
			"an avoidable final-word orphan is kept with its preceding word")
		var long_line := "A deliberately long line that must remain readable without covering the world."
		corin.emote(long_line)
		_check(corin._bubble.size.x <= Npc.BUBBLE_W and corin._bubble_lbl.clip_text \
			and corin._bubble_pages.size() > 1 \
			and " ".join(corin._bubble_pages) == long_line,
			"long chatter stays bounded and keeps every word across pages")
		var first_page: String = corin._bubble_lbl.text
		corin._bubble_until = 0
		corin._process(0.0)
		_check(corin._bubble.visible and corin._bubble_page == 1 \
			and corin._bubble_lbl.text != first_page,
			"ambient chatter advances to its next page without input")
		for _page in range(corin._bubble_pages.size() + 1):
			if not corin._bubble.visible:
				break
			corin._bubble_until = 0
			corin._process(0.0)
		_check(not corin._bubble.visible, "ambient chatter hides after its final page")
		var short_line := "「水烧上了。坐会儿。」"
		corin.emote(short_line)
		var label: Label = corin._bubble_lbl
		var width := label.get_theme_font("font").get_string_size(short_line,
			HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
		_check(corin._bubble_pages.size() == 1 and corin._bubble.size.x < Npc.BUBBLE_W \
			and width <= label.size.x,
			"short overworld chatter shrinks after a long line without clipping")
		corin._bubble.visible = false
	# The actual bilingual data, not just a synthetic example, must survive the
	# narrow one-line bubble. Before paging, most authored English lines lost
	# their endings even though the Chinese screenshots appeared correct.
	var chatter_count := 0
	var chatter_fits := true
	var chatter_complete := true
	for n in r.npcs:
		var person: Npc = n
		for line in person.data.get("chatter", []):
			var entry: Dictionary = line
			for lang in ["zh", "en"]:
				var text := str(entry.get(lang, ""))
				person.emote(text)
				chatter_count += 1
				chatter_complete = chatter_complete \
					and "".join(person._bubble_pages).replace(" ", "") == text.replace(" ", "")
				for page in range(person._bubble_pages.size()):
					person._show_bubble_page(page)
					var lbl: Label = person._bubble_lbl
					var text_width := lbl.get_theme_font("font").get_string_size(lbl.text,
						HORIZONTAL_ALIGNMENT_LEFT, -1, lbl.get_theme_font_size("font_size")).x
					chatter_fits = chatter_fits and text_width <= lbl.size.x \
						and person._bubble.size.x <= Npc.BUBBLE_W
				person._bubble.visible = false
	_check(chatter_count >= 14 and chatter_complete and chatter_fits,
		"all %d authored English and Chinese chatter lines retain their words and fit" % chatter_count)
	_check(r.goliath_sprite.position == original_giant_pos
		and is_equal_approx(r.goliath_sprite.scale.x, 0.40)
		and r.goliath_sprite.offset == Vector2(0, -64),
		"the larger champion retains his original foot anchor")
	for key in ["tent", "olive_tree", "rock", "boulder", "jar", "well"]:
		var prop: Sprite2D = null
		var expected_path := ""
		for entry in r._prop_sprites:
			if str(entry["key"]) == key:
				prop = entry["sprite"]
				expected_path = r._map_prop_texture_path(key, "cinematic", entry["at"])
				break
		_check(prop != null and prop.texture.resource_path == expected_path
			and expected_path.begins_with("res://art/props_painted/"),
			"%s selects its painted map prop" % key)
	var tent_variants := {}
	for entry in r._prop_sprites:
		if str(entry["key"]) == "tent":
			var path: String = (entry["sprite"] as Sprite2D).texture.resource_path
			tent_variants[path] = int(tent_variants.get(path, 0)) + 1
	_check(tent_variants.get("res://art/props_painted/tent.png", 0) == 2
		and tent_variants.get("res://art/props_painted/tent_camp_a.png", 0) == 2
		and tent_variants.get("res://art/props_painted/tent_camp_b.png", 0) == 1
		and tent_variants.get("res://art/props_painted/tent_royal_open.png", 0) == 1,
		"the camp includes five varied tents and the single open royal tent")
	var missing_props: Array = []
	var anchors_ok := true
	var world_sizes_ok := true
	var geometry_file := FileAccess.open("res://tests/fixtures/painted_prop_geometry.json", FileAccess.READ)
	_check(geometry_file != null, "the pre-detail prop geometry fixture exists")
	var geometry: Dictionary = JSON.parse_string(geometry_file.get_as_text())["props"] if geometry_file else {}
	for entry in r._prop_sprites:
		var sprite: Sprite2D = entry["sprite"]
		var key := str(entry["key"])
		if sprite.texture.resource_path != r._map_prop_texture_path(key, "cinematic", entry["at"]) \
				or not sprite.texture.resource_path.begins_with("res://art/props_painted/"):
			missing_props.append(key)
		var is_royal: bool = key == "tent" and entry["at"] == Region.ROYAL_TENT_AT
		var sort_raise := Region.ROYAL_TENT_SORT_RAISE if is_royal else 0.0
		anchors_ok = anchors_ok and is_equal_approx(sprite.offset.y,
			-sprite.texture.get_height() * 0.5 + sort_raise / sprite.scale.y)
		if not geometry.has(key):
			world_sizes_ok = false
			continue
		var old_size: Array = geometry[key]["size"]
		var old_scale := float(Region.PAINTED_PROP_SCALE.get(key, 1.0))
		var expected := Vector2(float(old_size[0]) / sprite.hframes, float(old_size[1])) * old_scale
		if is_royal:
			expected = Vector2(252, 210) * sprite.scale
		var actual := sprite.texture.get_size() / Vector2(sprite.hframes, sprite.vframes) * sprite.scale
		world_sizes_ok = world_sizes_ok and actual.is_equal_approx(expected)
	_check(missing_props.is_empty(), "every actual Elah map prop has painted art: %s" % str(missing_props))
	_check(anchors_ok and world_sizes_ok,
		"map props retain foot anchors and their expected sizes, including the larger open tent")
	var examples := {}
	for entry in r._prop_sprites:
		var key := str(entry["key"])
		if not examples.has(key) and not (key == "tent" and entry["at"] == Region.ROYAL_TENT_AT):
			examples[key] = entry["sprite"]
	var person_h := player.visual_height()
	_check(_visible_prop_height(examples.get("olive_tree")) > person_h * 1.8
		and _visible_prop_height(examples.get("fig_tree")) > person_h * 1.3
		and _visible_prop_height(examples.get("tent")) > person_h * 1.25,
		"mature trees and ordinary tent peaks read larger than a person")
	_check(_visible_prop_height(examples.get("jar")) < person_h * 0.5
		and _visible_prop_height(examples.get("well")) > _visible_prop_height(examples.get("jar")) * 1.6
		and _visible_prop_height(examples.get("bush")) < person_h,
		"jar, well and shrub have deliberately different person-relative heights")
	_check(examples.get("fig_tree") != null
		and (examples["fig_tree"] as Sprite2D).texture.resource_path.ends_with("fig_tree_refined.png")
		and is_equal_approx(royal_tent.scale.x, 0.30),
		"the detailed fig uses its six-times canvas while Saul's doorway retains its calibrated scale")
	var sort_ok := r._ys.y_sort_enabled and r._prop_sprites.size() == r.model.props.size()
	var shadows_ok := true
	var fire: Sprite2D = null
	for i in range(r._prop_sprites.size()):
		var prop_entry: Dictionary = r._prop_sprites[i]
		var placed: Dictionary = r.model.props[i]
		var visual: Sprite2D = prop_entry["sprite"]
		var meta: Dictionary = placed["_meta"]
		var expected_x := (float(placed["at"][0]) + float(meta["w_tiles"]) * 0.5) * 16.0
		var expected_y := (float(placed["at"][1]) + 1.0) * 16.0
		var is_royal: bool = str(prop_entry["key"]) == "tent" and prop_entry["at"] == Region.ROYAL_TENT_AT
		var sort_raise := Region.ROYAL_TENT_SORT_RAISE if is_royal else 0.0
		sort_ok = sort_ok and visual.get_parent() == r._ys \
			and absf(visual.position.x - expected_x) <= 0.81 \
			and absf(visual.position.y + sort_raise - expected_y) <= 0.41
		var shadow: Dictionary = prop_entry["shadow"]
		var expected_width := float(visual.texture.get_width()) / float(visual.hframes) * visual.scale.x * 0.42
		shadows_ok = shadows_ok and shadow["node"] == visual and shadow["offset"] == Vector2(0, sort_raise) \
			and is_equal_approx(float(shadow["w"]), expected_width)
		if str(prop_entry["key"]) == "fire":
			fire = visual
	_check(sort_ok, "props sort at their feet except for the open tent's back wall, including sway")
	_check(shadows_ok and bool(r._shadow_layer.get("enabled"))
		and str(r._shadow_layer.get("mode")) == "painted_world",
		"painted-world shadows follow scaled props at their feet")
	_check(r.model.solid_at_tile(7, 43) and r.model.solid_at_tile(8, 43)
		and r.model.solid_at_tile(15, 45) and r.model.solid_at_tile(12, 45)
		and not r.model.solid_at_tile(27, 37),
		"tent, fire and altar footprints block movement while the decorative bush does not")
	var fire_timer: Timer = null
	for child in r.get_children():
		if child is Timer:
			fire_timer = child
	_check(fire != null and fire_timer != null and fire.hframes == 2
		and fire.texture.get_size() == Vector2(64, 24) * ArtDirection.PAINTED_PROP_DETAIL_FACTOR,
		"the higher-detail camp fire is still a two-frame sheet")
	if fire != null and fire_timer != null:
		var previous_frame := fire.frame
		await fire_timer.timeout
		_check(fire.frame == (previous_frame + 1) % 2, "the camp fire advances through its painted frames")
	var saved_model: RegionModel = r.model
	r.model = null
	r.set_paused(false)
	var sway_sprite: Sprite2D = r._swayers[0]["sprite"]
	var sway_start := sway_sprite.position
	r._process(0.7)
	var sway_moved := sway_sprite.position
	r.set_paused(true)
	r._process(0.7)
	_check(not sway_moved.is_equal_approx(sway_start) and sway_sprite.position.is_equal_approx(sway_moved),
		"vegetation sways in the world and freezes while dialogue pauses it")
	r.model = saved_model
	r.set_paused(false)
	var sheep := FlockSheep.new()
	sheep.setup("painted_test", [20, 35], [24, 34], "calm", player, r)
	add_child(sheep)
	sheep.apply_art_theme("cinematic")
	_check(sheep._up_tex.resource_path.ends_with("props_painted/sheep.png")
		and sheep._graze_tex.resource_path.ends_with("props_painted/sheep_graze.png")
		and sheep._alert_tex.resource_path.ends_with("props_painted/sheep_alert.png"),
		"a dynamically spawned flock animal uses all three painted poses")
	_check(sheep._sprite.scale.is_equal_approx(
		Vector2.ONE * (0.425 / ArtDirection.PAINTED_PROP_DETAIL_FACTOR))
		and sheep._sprite.offset == Vector2(0, -float(sheep._up_tex.get_height()) * 0.5)
		and (sheep._up_tex.get_size() * sheep._sprite.scale).is_equal_approx(Vector2(28, 24) * 0.425),
		"a live sheep keeps its previous displayed size and foot anchor")
	sheep.apply_art_theme("classic")
	_check(sheep._up_tex.resource_path.ends_with("art/props/sheep.png")
		and sheep._sprite.scale == Vector2.ONE * 0.85 and sheep._sprite.offset == Vector2.ZERO,
		"the flock animal restores its original classic appearance")
	sheep.queue_free()
	r.spawn_pickup("painted_contract_jar", "provision", "jar", 19, 39)
	var item: Node2D = r.pickups.back()["node"]
	var item_sprite: Sprite2D = item.get_child(0)
	_check(item_sprite.texture.resource_path.ends_with("props_painted/jar.png"),
		"a later-spawned provision inherits the painted theme")
	r.spawn_pickup("painted_contract_wheat", "provision", "wheat_sheaf", 19, 38)
	var wheat_sprite: Sprite2D = (r.pickups.back()["node"] as Node2D).get_child(0)
	_check(wheat_sprite.texture.resource_path.ends_with("props_painted/wheat_sheaf.png")
		and is_equal_approx(wheat_sprite.scale.x, 0.425 / ArtDirection.PAINTED_PROP_DETAIL_FACTOR),
		"the later-spawned wheat provision uses its higher-resolution painted prop")
	player.setup(r.model, "david")
	r.enter_shepherd_field()
	_check(is_equal_approx(player.david_visual.scale.x, Player.FIELD_RIG_SCALE)
		and boy.field_sprite.visible and not boy.human_visual.visible
		and boy.field_sprite.texture.resource_path.ends_with("characters_reference/boy_front_idle.png"),
		"the field keeps its approved scale and independent reference-styled hired boy")
	_check(str(r._shadow_layer.get("mode")) == "painted_field",
		"the approved field keeps its separate shadow treatment")
	r.leave_shepherd_field()
	_check(is_equal_approx(player.david_visual.scale.x, Player.WORLD_RIG_SCALE)
		and boy.human_visual.visible and not boy.field_sprite.visible,
		"leaving the field restores the painted world actor scale and boy")
	_check(str(r._shadow_layer.get("mode")) == "painted_world",
		"leaving the field restores the overworld shadow treatment")
	player.set_armour(true)
	_check(player.armour_visual != null and player.armour_visual.visible
		and player.armour_visual.painted and player.armour_visual.scale == player.david_visual.scale
		and player.armour_visual.get_index() > player.david_visual.get_index(),
		"painted armour is drawn above David at his rig scale")
	player.external_intent = Vector2.RIGHT
	player._physics_process(0.10)
	var expected_overlay: Vector2 = player.david_visual.position \
		+ player.david_visual.body.position * player.david_visual.scale
	_check(absf(player.david_visual.position.x) > 0.5
		and player.armour_visual.position.is_equal_approx(expected_overlay)
		and is_equal_approx(player.armour_visual.rotation, player.david_visual.body.rotation)
		and is_equal_approx(player.speed_scale(), 0.42),
		"walking in armour staggers the painted body and its overlay together at reduced speed")
	player.external_intent = Vector2.ZERO
	player._physics_process(0.10)
	_check(is_zero_approx(player.david_visual.position.x), "the painted stagger settles when standing still")
	player.facing = Vector2i(-1, 0)
	player._update_anim(0.0, 0.0)
	_check(player.armour_visual.facing == player.facing,
		"armour follows the left-facing body pose")
	player._set_stagger(1.2)
	r.apply_art_theme("classic")
	_check(player.armour_visual.visible and not player.armour_visual.painted
		and player.armour_visual.scale == Vector2.ONE
		and is_equal_approx(player.armour_visual.position.x, player.sprite.offset.x)
		and player.armour_visual.get_index() > player.sprite.get_index(),
		"switching themes mid-stagger preserves a correctly layered classic outfit")
	player.set_armour(false)
	_check(not player.armour_visual.visible and player.sprite.offset == Vector2(0, -8)
		and is_zero_approx(player.david_visual.position.x) and is_equal_approx(player.speed_scale(), 1.0),
		"removing armour restores both visual anchors and full speed")
	_check(r.terrain.painted_ground == null and r.terrain.painted_ground_bottom == null
		and player.sprite.visible and not player.david_visual.visible,
		"classic theme restores the classic ground and David")
	_check(not bool(r._shadow_layer.get("enabled")) and fire != null and fire.hframes == 2
		and fire.texture.resource_path.ends_with("art/props/fire.png"),
		"classic restores the original animated fire and disables painted shadows")
	_check(corin.sprite.visible and not corin.human_visual.visible
		and item_sprite.texture.resource_path.ends_with("art/props/jar.png")
		and wheat_sprite.texture.resource_path.ends_with("art/props/wheat_sheaf.png")
		and is_equal_approx(wheat_sprite.scale.x, 0.85),
		"classic restores NPC and late-spawned item textures and scales")
	_check(r.goliath_sprite.position == original_giant_pos
		and r.goliath_sprite.scale == Vector2(2.0, 2.0)
		and r.goliath_sprite.offset == Vector2(0, -8),
		"classic restores the champion's original geometry")
	_check(r.model._solid == solid_before, "theme and field round trips preserve collision")
	var classic_tents := true
	for entry in r._prop_sprites:
		if str(entry["key"]) == "tent":
			classic_tents = classic_tents and (entry["sprite"] as Sprite2D).texture.resource_path \
				== "res://art/props/tent.png"
	_check(classic_tents, "all tent variants revert to the original classic texture")
	_check(royal_tent != null and is_equal_approx(royal_tent.position.y, 688.0)
		and is_equal_approx(royal_tent.offset.y, -royal_tent.texture.get_height() * 0.5)
		and royal_shadow.get("offset", Vector2.ZERO) == Vector2.ZERO,
		"classic restores the royal tent's original sort point and shadow")
	r.apply_art_theme("cinematic")
	var restored_tents := {}
	for entry in r._prop_sprites:
		if str(entry["key"]) == "tent":
			var path: String = (entry["sprite"] as Sprite2D).texture.resource_path
			restored_tents[path] = int(restored_tents.get(path, 0)) + 1
	_check(restored_tents == tent_variants and r.model._solid == solid_before
		and royal_tent != null and is_equal_approx(royal_tent.position.y, 688.0 - Region.ROYAL_TENT_SORT_RAISE)
		and royal_shadow.get("offset", Vector2.ZERO) == Vector2(0, Region.ROYAL_TENT_SORT_RAISE),
		"a theme round trip restores the open tent and its sort without changing collision")
	main.queue_free()
	await get_tree().process_frame

	# Bethlehem's house keeps the canvas that Region uses for the anchor.
	var beth := Region.new()
	beth.region_id = "bethlehem"
	add_child(beth)
	beth.set_process(false)
	var beth_solid := beth.model._solid.duplicate()
	beth.apply_art_theme("cinematic")
	_check(beth.terrain.painted_ground != null and beth.terrain.painted_ground_bottom != null
		and beth.terrain.painted_ground.resource_path.ends_with("world_bethlehem_refined_top.png")
		and beth.terrain.painted_ground_bottom.resource_path.ends_with("world_bethlehem_refined_bottom.png")
		and beth.terrain.painted_ground.get_size() == Vector2(2048, 1024)
		and beth.terrain.painted_ground_bottom.get_size() == Vector2(2048, 1024),
		"Bethlehem also uses two contiguous refined ground pieces")
	var house: Sprite2D = null
	for entry in beth._prop_sprites:
		if str(entry["key"]) == "house":
			house = entry["sprite"]
			break
	_check(house != null and house.texture.resource_path.ends_with("props_painted/house.png")
		and house.texture.get_size() == Vector2(66, 83) * ArtDirection.PAINTED_PROP_DETAIL_FACTOR
		and (house.texture.get_size() * house.scale).is_equal_approx(Vector2(66, 83) * 1.12),
		"Bethlehem's larger house keeps its bottom-anchored source canvas")
	var beth_missing: Array = []
	var house_paths := {}
	for entry in beth._prop_sprites:
		var sprite: Sprite2D = entry["sprite"]
		var key := str(entry["key"])
		if sprite.texture.resource_path != beth._map_prop_texture_path(key, "cinematic", entry["at"]) \
				or not sprite.texture.resource_path.begins_with("res://art/props_painted/"):
			beth_missing.append(key)
		if key == "house":
			house_paths[sprite.texture.resource_path] = true
	_check(beth_missing.is_empty(), "every Bethlehem map prop has painted art: %s" % str(beth_missing))
	_check(house_paths.has("res://art/props_painted/house.png")
		and house_paths.has("res://art/props_painted/house_reference_alt.png") and house_paths.size() == 2,
		"Bethlehem's two houses use distinct cosmetic images at their original footprints")
	var samuel: Npc = null
	var jesse: Npc = null
	var eliab: Npc = null
	for n in beth.npcs:
		if n.npc_id() == "samuel":
			samuel = n
		elif n.npc_id() == "jesse":
			jesse = n
		elif n.npc_id() == "eliab":
			eliab = n
	_check(samuel != null and jesse != null and eliab != null
		and samuel.human_visual != null and jesse.human_visual != null and eliab.human_visual != null
		and (samuel.human_visual._poses["front"][0] as Texture2D).resource_path.ends_with(
			"characters_reference/samuel_front_body.png")
		and (jesse.human_visual._poses["front"][0] as Texture2D).resource_path.ends_with(
			"characters_reference/jesse_front_body.png")
		and (eliab.human_visual._poses["front"][0] as Texture2D).resource_path.ends_with(
			"characters_reference/eliab_front_body.png"),
		"Samuel, Jesse and Eliab use their own generated front appearances")
	for spec in [[samuel, "samuel"], [jesse, "jesse"], [eliab, "eliab"]]:
		var person: Npc = spec[0]
		var actor: String = spec[1]
		if person == null or person.human_visual == null:
			_check(false, "%s has a directional rig" % actor)
			continue
		var anchor := person.global_position
		for turn in [[Vector2i(0, 1), "front"], [Vector2i(1, 0), "profile"],
				[Vector2i(-1, 0), "profile"], [Vector2i(0, -1), "back"]]:
			var direction: Vector2i = turn[0]
			var pose: String = turn[1]
			person.face_toward(anchor + Vector2(direction) * 50.0)
			_check(person.human_visual._pose_name == pose
				and person.human_visual.body.flip_h == (direction.x < 0)
				and person.human_visual.body.texture.resource_path.ends_with(
					"characters_reference/%s_%s_body.png" % [actor, pose])
				and person.global_position == anchor,
				"%s keeps his anchor and uses his %s pose" % [actor, pose])
	if samuel != null and samuel.human_visual != null:
		_check(is_equal_approx(samuel.visual_height(), 76.0 * Player.WORLD_RIG_SCALE)
			and samuel.human_visual.boot_left.texture.get_image().get_used_rect().size == Vector2i.ZERO
			and samuel.human_visual.boot_right.texture.get_image().get_used_rect().size == Vector2i.ZERO,
			"seated Samuel's marker uses his shorter silhouette and his stool stays intact")
		samuel.human_visual.set_pose(Vector2i(1, 0), true, 60.0, 0.25)
		_check(not samuel.human_visual.moving and samuel.human_visual.gait_amount == 0.0
			and samuel.human_visual.body.position == Vector2.ZERO,
			"a walking request cannot animate Samuel's seated figure or stool")
	for person in [samuel, jesse, eliab]:
		if person == null or person.human_visual == null:
			continue
		var anchor: Vector2 = person.global_position
		person.apply_art_theme("classic")
		_check(person.sprite.visible and not person.human_visual.visible
			and person.sprite.texture.resource_path.ends_with("characters/%s_idle.png" % person.actor_id)
			and person.global_position == anchor,
			"%s returns to classic art at the same position" % person.actor_id)
		person.apply_art_theme(ArtDirection.current())
		_check(person.human_visual.visible and not person.sprite.visible
			and person.human_visual.body.texture.resource_path.ends_with(
				"characters_reference/%s_%s_body.png" % [person.actor_id, person.human_visual._pose_name]),
			"%s restores dedicated reference art after a classic round trip" % person.actor_id)
	_check(beth.model._solid == beth_solid, "painted Bethlehem retains its original collision")
	beth.queue_free()
	await get_tree().process_frame

	var practice := SlingPractice.new()
	add_child(practice)
	_check(practice.art_theme == ArtDirection.current(), "practice inherits the shared default")
	_check(SlingPractice.PAINTED_JAR.resource_path.ends_with("props_painted/jar.png"),
		"practice targets use the painted jar while retaining their timing")
	practice.start(3)
	_check(practice._player.expand_mode == TextureRect.EXPAND_IGNORE_SIZE
		and practice._player.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"practice sizes its figure and does not block taps")
	TapGate.reset()
	practice.aim_perfect()
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	practice._on_gui(touch)
	var verdict := practice._msg
	var twin := InputEventMouseButton.new()
	twin.pressed = true
	twin.button_index = MOUSE_BUTTON_LEFT
	practice._on_gui(twin)
	_check(practice.hits == 1 and practice._msg == verdict,
		"one touch and its emulated mouse event produce one practice action")
	practice.queue_free()
	var brook := StoneChoice.new()
	add_child(brook)
	_check(brook.art_theme == ArtDirection.current(), "brook inherits the shared default")
	_check(StoneChoice.PAINTED_STONES.size() == 3
		and (StoneChoice.PAINTED_STONES[0] as Texture2D).resource_path.ends_with("brook_stone_a.png")
		and (StoneChoice.PAINTED_STONES[1] as Texture2D).resource_path.ends_with("brook_stone_b.png")
		and (StoneChoice.PAINTED_STONES[2] as Texture2D).resource_path.ends_with("brook_stone_c.png"),
		"brook has three preloaded selectable-stone appearances")
	brook.start(5, 9)
	var max_y := 0.0
	for stone in brook.stones:
		max_y = maxf(max_y, (stone["pos"] as Vector2).y)
	_check(max_y < 0.60, "brook stones clear the bottom instruction and pouch")
	# The painted brook's timed feedback must stay readable without covering a
	# selectable stone or its keyboard-focus ring. Check the real messages in
	# both languages at the logical sizes corresponding to several aspects.
	var messages := ["Five is what he takes. Not six.", "Five. That is the number.",
		"Five in your hand. Keep these?", "他拿的就是五块。不是六块。",
		"五块。就这个数。", "手里有五块了。就要这些？"]
	var panels_safe := true
	var panels_clear := true
	var font := ThemeDB.fallback_font
	for viewport in [Vector2(320, 180), Vector2(320, 240), Vector2(389.5, 180)]:
		var vs: Vector2 = viewport
		var e := ScreenFit.edge(vs)
		var radius := clampf(vs.x * 0.020, 5.0, 9.0) + 3.0
		for message in messages:
			var text: String = message
			var panel := brook._message_backdrop(vs, text, font)
			var measured := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
				vs.x - e * 2.0 - 4.0, 8, 2)
			panels_safe = panels_safe and panel.position.x >= e and panel.end.x <= vs.x - e \
				and panel.position.y >= e + 26.0 and panel.end.y < vs.y - 62.0 \
				and panel.size.x >= measured.x + 3.9 and panel.size.y >= measured.y + 3.9
			for stone in brook.stones:
				var unit: Vector2 = stone["pos"]
				var p := Vector2(unit.x * vs.x, unit.y * vs.y)
				var focus := Rect2(p - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
				panels_clear = panels_clear and not panel.intersects(focus)
	_check(panels_safe, "brook bilingual feedback fits its backing inside the safe area")
	_check(panels_clear, "brook feedback does not cover stones or their focus rings")
	var hints := ["Tap a stone to take it. Tap it again to put it back.",
		"Five. Press A to keep these five.", "点一块石头就拿起来。再点一下放回去。",
		"五块了。按 A 就要这五块。"]
	var hints_safe := true
	var hints_clear := true
	for viewport in [Vector2(320, 180), Vector2(320, 240), Vector2(389.5, 180)]:
		var vs: Vector2 = viewport
		var e := ScreenFit.edge(vs)
		var radius := clampf(vs.x * 0.020, 5.0, 9.0) + 3.0
		for entry in hints:
			var text: String = entry
			var panel := brook._hint_backdrop(vs, text, font)
			var measured := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
				vs.x - e * 2.0 - 4.0, 8, 2)
			hints_safe = hints_safe and panel.position.x >= e and panel.end.x <= vs.x - e \
				and panel.end.y <= vs.y - 40.0 and panel.size.x >= measured.x + 3.9 \
				and panel.size.y >= measured.y + 3.9
			for stone in brook.stones:
				var unit: Vector2 = stone["pos"]
				var p := Vector2(unit.x * vs.x, unit.y * vs.y)
				var focus := Rect2(p - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
				hints_clear = hints_clear and not panel.intersects(focus)
	_check(hints_safe, "brook bilingual instructions fit above the pouch")
	_check(hints_clear, "brook instructions do not cover stones or their focus rings")
	brook.queue_free()
	var duel := GoliathFight.new()
	add_child(duel)
	_check(duel.art_theme == ArtDirection.current(), "duel inherits the shared default")
	_check(duel._gol.expand_mode == TextureRect.EXPAND_IGNORE_SIZE
		and duel._david.expand_mode == TextureRect.EXPAND_IGNORE_SIZE,
		"duel figures respect their layout sizes")
	var idle := GoliathFight.PAINTED_GOLIATH.get_image()
	var striking := GoliathFight.PAINTED_GOLIATH_STRIKING.get_image()
	_check(idle.get_pixel(34, 5).a > 0.9 and striking.get_pixel(34, 5).a == 0.0
		and striking.get_pixel(36, 49).a > 0.9,
		"striking pose removes the baked spear while retaining the hand")
	duel.queue_free()
	await get_tree().process_frame
	print("painted world: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _check_gait_contract(r: Region, player: Player) -> void:
	var rig = load("res://scripts/world/HumanVisual.gd").new()
	rig.scale = Vector2.ONE * Player.WORLD_RIG_SCALE
	add_child(rig)
	rig.build("pilgrim")
	var root_before: Vector2 = rig.position
	rig.set_pose(Vector2i(1, 0), false, 0.0, 0.1)
	_check(rig.body.position == Vector2.ZERO and is_zero_approx(rig.body.rotation)
		and rig.boot_left.position == Vector2.ZERO and rig.boot_right.modulate.a == 0.0,
		"idle side art reconstructs the still figure without a duplicate far foot")
	rig.set_pose(Vector2i(1, 0), true, 60.0, 0.1)
	var fast_phase: float = rig.phase
	var near_swing: float = rig.boot_left.rotation - rig.body.rotation
	var far_swing: float = rig.boot_right.rotation - rig.body.rotation
	_check(rig.gait_amount > 0.0 and rig.gait_amount < 1.0
		and absf(rig.body.rotation) > 0.001 and rig.body.position.y < 0.0
		and near_swing * far_swing < 0.0 and rig.boot_right.modulate.a > 0.0,
		"gait eases in, leans and swings the two side feet in opposition")
	_check(rig.position == root_before, "animated posture never shifts the actor's foot anchor")
	rig.phase = 0.0
	rig.set_pose(Vector2i(1, 0), true, 30.0, 0.1)
	_check(is_equal_approx(fast_phase, rig.phase * 2.0),
		"one gait cycle is tied to distance rather than a fixed frame rate")
	rig.set_pose(Vector2i(-1, 0), false, 0.0, 0.2)
	_check(not rig.moving and rig.gait_amount == 0.0 and rig.direction == Vector2i(-1, 0)
		and rig.body.position == Vector2.ZERO and is_zero_approx(rig.body.rotation)
		and rig.boot_left.position == Vector2.ZERO and rig.boot_right.modulate.a == 0.0,
		"stopping smoothly returns all parts to idle and retains the last facing")
	rig.queue_free()

	for actor in ["elder", "woman"]:
		var dressed = load("res://scripts/world/HumanVisual.gd").new()
		dressed.scale = Vector2.ONE * Player.WORLD_RIG_SCALE
		add_child(dressed)
		dressed.build(actor)
		dressed.set_pose(Vector2i(1, 0), true, 34.0, 0.2)
		_check(dressed.boot_left.texture != dressed.boot_right.texture
			and dressed.boot_right.modulate == Color.WHITE,
			"%s's two visible profile feet are not duplicated" % actor)
		dressed.queue_free()
	var seated = load("res://scripts/world/HumanVisual.gd").new()
	add_child(seated)
	seated.build("samuel")
	seated.set_pose(Vector2i(1, 0), true, 60.0, 0.2)
	_check(not seated.moving and seated.gait_amount == 0.0 and is_zero_approx(seated.body.rotation),
		"the seated prophet never leans or walks when asked to move")
	seated.queue_free()

	# Exercise real NPC movement: compare phase advance against displacement,
	# not against the patrol constant when this same person follows faster.
	var actor := Npc.new()
	actor.setup(r.model, {"id": "gait_probe", "actor": "corin", "at": [16, 34],
		"patrol": [[16, 34], [17, 34]]}, player, r.dialogue, Callable(r, "set_paused"))
	r._ys.add_child(actor)
	actor.set_physics_process(false)
	actor.apply_art_theme("cinematic")
	actor.state = Npc.State.PATROL
	actor._path = PackedVector2Array()
	actor._path.append(actor.global_position + Vector2(100, 0))
	actor._path_i = 0
	var previous := actor.global_position
	actor._physics_process(0.1)
	var patrol_distance := actor.global_position.distance_to(previous)
	var patrol_phase: float = actor.human_visual.phase
	var saved_player := player.global_position
	player.global_position = actor.global_position + Vector2(200, 0)
	actor.state = Npc.State.FOLLOW
	actor._path = PackedVector2Array()
	actor._path.append(actor.global_position + Vector2(100, 0))
	actor._path_i = 0
	actor._repath = 10.0
	previous = actor.global_position
	actor._physics_process(0.1)
	var follow_distance := actor.global_position.distance_to(previous)
	var follow_phase: float = actor.human_visual.phase - patrol_phase
	_check(follow_distance > patrol_distance
		and is_equal_approx(patrol_phase, patrol_distance * TAU / 42.0)
		and is_equal_approx(follow_phase, follow_distance * TAU / 42.0),
		"patrol and follow gait speeds track their real different distances")
	player.global_position = saved_player
	actor.queue_free()


func _visible_prop_height(sprite: Sprite2D) -> float:
	if sprite == null or sprite.texture == null:
		return 0.0
	return float(sprite.texture.get_image().get_used_rect().size.y) * sprite.scale.y


func _check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("PASS painted world: " + message)
	else:
		failures += 1
		printerr("FAIL painted world: " + message)
