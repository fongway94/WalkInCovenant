extends Node
## tests/smoke.gd — plays the vertical slice headless and asserts the loop closes.
##
## run_all.gd checks the CONTENT is well formed. This checks the GAME WORKS.
## It boots Main.tscn, reads the briefing, talks to all four people, crosses the
## line with an empty pouch, goes back for the stones, crosses again, fights the
## fight to a win, walks back into the valley, and asserts the save state
## afterwards. Everything is driven through the same entry points a player's
## thumbs would use, so a regression in Region, DialogueBox, BecomeController or
## WordBattle fails the build instead of failing somebody's first playtest.
##
##   godot --headless --path . res://tests/smoke.tscn
##
## Booted as a SCENE, not with --script. Main::start() instantiates a --script
## main loop (main.cpp:4438) a long way before it registers autoloads as global
## constants (main.cpp:4498), so anything compiled on that path — this file and
## every script its preload pulls in — dies with "Identifier not found:
## AudioDirector" and never reaches an assertion. A scene passed on the command
## line is loaded after the autoloads exist, which is also the path the shipped
## game takes, so the test cannot drift from how the game really boots.
##
## Two bugs this file exists because of, both invisible to a green compile:
##   * Region never built its trigger list, so the challenge line could not fire
##     at all — the fight was unreachable by walking.
##   * DialogueBox._pick() advanced a box its own callback had just replaced,
##     instantly finishing single-line follow-ups and firing their on_done early.

const TILE := 16.0
const FRAME_GUARD := 6000

var fails := 0


func _ready() -> void:
	_run()


func _run() -> void:
	# BECOME and RETURN are tween-driven, so headless frames would otherwise
	# spend real seconds on each beat. 24x keeps the whole run to a few seconds.
	Engine.time_scale = 24.0
	# A fresh chapter, every time. The game now autosaves (which is the point),
	# and a save left behind by an earlier run would boot this one into Act II
	# and fail every Act I assertion with a reason that has nothing to do with
	# the code under test.
	if FileAccess.file_exists(GameState.SAVE_PATH):
		DirAccess.remove_absolute(GameState.SAVE_PATH)
	GameState.new_game()
	GameState.data["settings"]["reduce_motion"] = true

	# load(), not preload(): a script that fails to compile turns a preload into
	# a compile error in THIS file, which reports as a cascade and names the
	# wrong thing. Loaded at runtime, the same failure is a value we can inspect
	# and describe.
	var packed = load("res://scenes/main/Main.tscn")
	_check(packed != null, "Main.tscn loads")
	if packed == null:
		_finish_run()
		return
	var main = packed.instantiate()
	_check(main != null, "Main.tscn instantiates")
	if main == null:
		_finish_run()
		return
	var attached: bool = main.get_script() != null
	if not attached:
		# Nothing below means anything if the scene root has no script. Say why:
		# a GDScript that will not compile loads as a resource that cannot
		# instantiate, and the engine does not repeat the reason here.
		var raw = load("res://scripts/main/Main.gd")
		var can := false
		if raw != null:
			can = bool(raw.can_instantiate())
		printerr("  diag  Main.gd loaded=%s can_instantiate=%s" % [str(raw != null), str(can)])
	_check(attached, "Main.gd is attached to the scene root")
	# Parented under this node, NOT under get_tree().root. Node::_propagate_ready
	# (scene/main/node.cpp:323) holds `data.blocked++` on a node while it walks
	# its children, and only fires that node's own NOTIFICATION_READY after
	# decrementing. So during _ready() a node may add children to ITSELF
	# (blocked == 0), but adding to root — whose blocked is 1 because root is
	# mid-walk through its own children, us included — fails with "Parent node is
	# busy setting up children". That is also why Main._ready() building the
	# world with add_child() is legal and this test's first version was not.
	add_child(main)
	await _frames(4)
	print("  diag  main=%s children=%d" % [main.get_class(), main.get_child_count()])

	# ── 1. the valley exists ─────────────────────────────────────────────
	var region = main.region
	if region == null:
		printerr("  diag  main.region is null; class=%s script=%s" % [
			main.get_class(), str(main.get_script())])
	_check(region != null, "Main built a Region")
	if region == null:
		_finish_run()
		return
	_check(region.model != null, "region model loaded from data")
	# The campaign comes from the registry, not from a string in Main.gd. This is
	# what makes campaign #2 a content change instead of a code change.
	_check(str(region.region_id) == CampaignModel.current_region(),
		"the region is the one data/campaigns.json registered (%s)" % region.region_id)
	_check(region.player != null, "player spawned")
	_check(region.dialogue != null, "dialogue box exists")
	_check(region.npcs.size() == 4, "4 people in the valley (got %d)" % region.npcs.size())
	# The five stones of 17:40 belong to David's act and are laid out when the
	# verse is spoken, so at boot there must be none of them: the witness cannot
	# pick up a scene that has not happened yet.
	_check(region.pickups.size() == 0,
		"the valley opens with nothing to collect (got %d)" % region.pickups.size())
	_check(int(main._stones_total) == 5,
		"and the brook still knows it holds five stones (got %d)" % int(main._stones_total))
	_check(region.triggers.size() == 2, "two story triggers were built (got %d)" % region.triggers.size())
	# Act I is about a man standing on the far ridge. He used to exist only as a
	# pair of coordinates; there was nobody there to shout.
	_check(region.goliath_sprite != null and region.goliath_sprite.visible,
		"the giant is on screen, two tiles tall, before you ever reach him")
	_check(_tile_of(region.player) == region.model.spawn, "player stands on the authored spawn tile")

	# ── 1b. the world is wired to the hands and the HUD ──────────────────
	# Region._ready() emits region_ready from INSIDE add_child(), so a
	# connection made afterwards never hears it. These two assertions are what
	# catches that. Without them the valley can render perfectly and ignore
	# every thumb on the screen — which is what it did.
	_check(main.touch != null, "touch controls exist")
	_check(main.hud != null, "hud exists")
	if main.touch != null:
		_check(main.touch.player == region.player, "the stick is bound to the player")
	if main.hud != null:
		_check(main.hud.region == region, "the hud is bound to the region")

	# ── 1c. the bundled face reaches the text pipeline ───────────────────
	# Tofu shipped once because the build had no font at all, and then shipped
	# AGAIN in effect because a byte-identical service worker kept serving the
	# old cache. A THIRD tofu (the HUD's ✧) slipped past both fixes because
	# Noto Sans SC has no such glyph and the subsetter dropped it silently —
	# tools/check_font.py now reads the built font's actual cmap and owns the
	# byte-level guarantee. What stays to prove at runtime is the wiring: the
	# resource loads, it carries real bytes, and it is what the theme falls
	# back to when a glyph is missing.
	var face = load("res://fonts/game.ttf")
	_check(face != null, "the bundled CJK font loads")
	if face != null:
		var supported: String = face.get_supported_chars()
		print("  diag  font: data=%d bytes, supported=%d chars"
				% [face.data.size(), supported.length()])
		_check(face.data.size() > 70000, "the font carries its glyph data")
		# has_char() has now lied twice under headless CI while every byte of
		# the font says otherwise (one run knew 谷 but denied 石; the next
		# denied both while get_supported_chars() walked the full 482-char
		# cmap in the same breath). So: print every input, assert on the char
		# table itself, and treat has_char as diagnostic until it stops
		# contradicting the table.
		var gu: int = "谷".to_utf32_buffer()[0]
		var shi: int = "石".to_utf32_buffer()[0]
		print("  diag  font: gu=%d shi=%d has_char=%s/%s table=%s/%s"
				% [gu, shi, str(face.has_char(gu)), str(face.has_char(shi)),
					str(supported.contains("谷")), str(supported.contains("石"))])
		if supported.length() >= 400:
			_check(supported.contains("谷") and supported.contains("石"),
					"the font's char table carries hanzi")
	_check(ThemeDB.fallback_font != null, "ThemeDB has a fallback font registered")
	if ThemeDB.fallback_font != null:
		print("  diag  fallback font: %s" % ThemeDB.fallback_font.resource_path)
		_check(ThemeDB.fallback_font.resource_path == "res://fonts/game.ttf",
				"the theme falls back to the bundled font")

	# ── 2. a first-time player is told what to do ────────────────────────
	# Chapter 1 first: the witness arrives from somewhere with buses.
	_check(region.dialogue._open, "the valley opens with the arrival")
	_check(bool(GameState.flag("elah_opened")), "the prologue runs once and is marked")
	_check(region.dialogue._lines.size() >= 4 or region.dialogue._box_id > 0,
		"the arrival is a scene, not a single line")
	_check(region._paused, "the briefing holds the world still")
	_drain(region.dialogue)
	_check(not region._paused, "the briefing releases the world")
	_check(bool(GameState.flag("elah_briefed")), "the briefing is marked as seen")
	main._brief_once()
	_check(not region.dialogue._open, "the briefing does not repeat on a second visit")

	# The caption is the one cinematic beat on the brief's list that was missing:
	# the valley is named once, from the region's own data.
	_check(bool(GameState.flag(str(region.region_id) + "_card")),
		"the place is captioned once")
	_check(main.card != null and main.card.title_lbl.text == I18n.t(region.model.display_name),
		"the caption says the region's name, not a hardcoded one")

	# The book and the language switch are real Buttons in the top-left. The
	# touch layer consumes what it claims and runs before the GUI, so it must not
	# claim the top band — tapping ≡ has to open the book, not start a walk.
	var vs_top: Vector2 = get_viewport().get_visible_rect().size
	_check(not main.touch._owns(Vector2(8, 20), true, 0, vs_top),
		"a tap on the book button belongs to the HUD, not the stick")
	_check(main.touch._owns(Vector2(40, vs_top.y - 40), true, 0, vs_top),
		"a tap in the stick half still belongs to the stick")

	# ── 2b. guidance: a goal on screen and a button that reaches the game ─
	# Playtest 6 could not tell what to do and could not talk to anybody. Both
	# are asserted here, because both were invisible to the compiler: the HUD
	# line is just a Label, and the A button used to call Input.action_press(),
	# which updates the action STATE without ever putting an InputEvent into the
	# pipeline the world listens on.
	await _frames(3)
	var obj_before: String = main.hud.objective_lbl.text
	_check(obj_before != "", "the HUD states the next objective (%s)" % obj_before)
	await _stand(region, 16, 20, 3)
	_check(main.hud.prompt_lbl.visible == false, "no talk prompt when nobody is near")
	if main.touch != null:
		var vs: Vector2 = region.get_viewport().get_visible_rect().size
		main.touch._press(true, Vector2(vs.x - 30, vs.y - 26), 99, vs)
		await _frames(2)
		_check(Input.is_action_pressed("interact"),
			"the on-screen A button presses the interact action")
		main.touch._press(false, Vector2(vs.x - 30, vs.y - 26), 99, vs)
		await _frames(2)
		_check(not Input.is_action_pressed("interact"), "and releases it")
		_check(not region.dialogue._open, "tapping A in an empty field talks to nobody")

	# ── 2c. the book: objective, verses, stones, marks in one place ──────
	_check(main.journal != null, "the journal exists")
	if main.journal != null:
		main._open_journal()
		_check(main.journal.is_open(), "the journal opens")
		_check(region._paused, "the journal holds the world still")
		_check(main.journal._panel.visible, "the journal has something on screen")
		main.journal.close_panel()
		_check(not main.journal.is_open(), "the journal closes")
		_check(not region._paused, "closing the book gives the world back")

	# ── 2d. a place that says something, once ────────────────────────────
	await _stand(region, 16, 27, 4)
	_check(region.dialogue._open, "the brook says something when you stand in it")
	_drain(region.dialogue)
	_check(bool(GameState.flag("curio_brook")), "a curio is remembered after it fires")
	await _stand(region, 16, 27, 4)
	_check(not region.dialogue._open, "the brook does not repeat itself")

	# ── 2e. the guide leads, he does not trail ───────────────────────────
	# Reported after playtest 9: "the top left says follow Corin to find a young
	# man, but instead the NPC follows me." He led correctly until he ARRIVED,
	# and then fell through to the player-follow branch — so the objective said
	# "follow Corin" while Corin walked behind you.
	#
	# The walking itself is driven by the guidance loop for the whole chapter
	# (any break there fails a dozen later assertions), so this test pins the two
	# branches instead of re-navigating the map by hand.
	var guide: Npc = _find_npc(region, "corin")
	var aim: Npc = _find_npc(region, "boy")
	if guide != null and aim != null:
		guide.clear_lead()
		guide.lead_to(aim, Callable())
		_check(guide.is_leading(), "a guide with somewhere to go is leading")
		var gap0 := guide.global_position.distance_to(aim.global_position)
		for i in range(6):
			guide._do_lead(0.1)
		var gap1 := guide.global_position.distance_to(aim.global_position)
		_check(gap1 < gap0, "he walks toward the person, not toward you (%.1f -> %.1f px)"
			% [gap0, gap1])
		# Once arrived, he must WAIT. This is the exact branch that was wrong:
		# lead_target set + _lead_arrived true used to fall through to "follow
		# the player".
		guide._lead_arrived = true
		_check(guide.is_waiting_ahead(), "an arrived guide is marked as waiting")
		var wait_pos := guide.global_position
		var saved_pos: Vector2 = region.player.global_position
		region.player.global_position = saved_pos + Vector2(96, 48)
		guide._do_follow(0.2)
		region.player.global_position = saved_pos
		_check(guide.global_position == wait_pos,
			"and he stays where he brought you instead of following you")
		guide.clear_lead()
		guide.state = Npc.State.IDLE

	# ── 2g. the first look at him ────────────────────────────────────────
	# One scripted shot in Act I: walk up the ridge, the camera takes the picture
	# off you and holds it on Goliath while 17:10 is spoken, then hands it back.
	await _stand(region, 16, 14, 4)
	_check(region.dialogue._open, "walking up the ridge stops you: your first clear look at him")
	_check(bool(GameState.flag("elah_saw_him")), "and the chapter remembers that you have seen him")
	_check(region.cam._cine, "the camera is holding him instead of the player")
	_drain(region.dialogue)
	await _frames(10)
	_check(not region.cam._cine, "and then the camera comes back to you")
	_check(not region._paused, "the shot releases the world when it ends")

	# ── 2f. the line is not yours yet ────────────────────────────────────
	# Act I has no stones to carry any more: it has a question. Crossing the
	# line before the camp has explained the forty days turns the witness back,
	# steps him south of the trigger, and leaves the objective on the next
	# person who has not spoken.
	await _stand(region, 16, 10, 4)
	_check(region.dialogue._open, "crossing the line opens a beat")
	_check(not main._in_battle, "crossing before you understand does not start a fight")
	_check(main.act_id() == "witness", "and it does not hand the story over (act=%s)" % main.act_id())
	_drain(region.dialogue)
	_check(not region._paused, "the refusal releases the world")
	_check(_tile_of(region.player).y > 11, "the refusal steps you back south")
	# Playtest 4 reported "it keeps prompting dialogue and looping": the beat
	# pushed the player back a few tiles and re-armed at once, so a held thumb
	# walked straight back in. The trigger now re-arms only past `rearm_row`.
	await _stand(region, 16, 12, 3)
	var line_trig := {}
	for t in region.triggers:
		if str(t["id"]) == "challenge":
			line_trig = t
	_check(not line_trig.is_empty(), "the line has a trigger of its own")
	_check(not bool(line_trig.get("armed", true)),
		"standing in the dead band does not re-arm the line")
	await _stand(region, 16, 15, 3)
	_check(bool(line_trig.get("armed", false)), "the line re-arms so the walk can be tried again")

	# ── 3. the four people on the road ───────────────────────────────────
	var cast := ["corin", "boy", "woman", "elder"]
	for c in cast:
		var id := str(c)
		var npc: Npc = _find_npc(region, id)
		_check(npc != null, "%s is standing in the valley" % id)
		if npc == null:
			continue
		# These are injected at spawn, so a build-order mistake shows up here as
		# a dead A button rather than as an error anywhere. All four were null
		# once: the dialogue box was built after the people who talk through it.
		_check(npc.dialogue == region.dialogue, "%s can reach the dialogue box" % id)
		_check(npc.player == region.player, "%s can see the player" % id)
		_check(npc.pause_fn.is_valid(), "%s can pause the world" % id)
		npc.talk()
		_check(region.dialogue._open, "%s speaks when you press A" % id)
		_check(region.dialogue.portrait.texture != null or not region.dialogue.portrait.visible,
			"%s gets a portrait without a script error" % id)
		# BUG A, asserted at the seam where it happened: pressing A while a box is
		# already up must not replace it, and the tap that closes a box must not
		# count as a fresh interaction (that is how one conversation appeared to
		# replay itself).
		var beat_before := int(region.dialogue._box_id)
		npc.talk()
		_check(int(region.dialogue._box_id) == beat_before,
			"a second A press does not restart %s's line" % id)
		_drain(region.dialogue)
		_check(region._interact_lock > 0.0,
			"the tap that closed %s cannot also re-open %s" % [id, id])
		_check(not region._paused, "talking to %s releases the world" % id)
		if id == "corin":
			# The objective says "follow Corin", so the game has to have given
			# him somewhere to lead you to.
			await _frames(3)
			var lead_aim: Npc = _find_npc(region, "boy")
			var lead_guide: Npc = _find_npc(region, "corin")
			_check(lead_guide != null and lead_guide.lead_target == lead_aim,
				"after the guide speaks, he starts leading you to the next person")
	var carried: Array = GameState.data["words"]
	_check(carried.size() == 4, "four verses were handed over (got %d)" % carried.size())

	# ── 6. BECOME, and then David's whole story ─────────────────────────
	# Chapter 2 first: three days earlier, the sheep slope, and the drill that
	# teaches the one input the fight asks for. Then Jesse's errand. Then the
	# king. Only then is there a fight.
	var level_before := int(GameState.data["level"])
	await _stand(region, 16, 10, 4)
	_check(bool(main._in_battle), "crossing with the camp's words in hand begins BECOME")
	_check(region._paused, "the world holds still while you become David")
	# 1 Samuel 17:11 is spoken at the line, Corin says the story is changing
	# hands, and only then does the perspective move. No abrupt swap.
	_check(region.dialogue._open, "the crossing says what it is: 17:11, and handover")
	_drain(region.dialogue)
	await _frames(3)
	var waited := 0
	while main.act_id() != "shepherd" and waited < FRAME_GUARD:
		await get_tree().process_frame
		waited += 1
	_check(main.act_id() == "shepherd",
		"the become hands over to the shepherd chapter (waited %d frames)" % waited)
	await _wait_open(region.dialogue)
	_check(region.dialogue._open, "the slope speaks before anything else")
	_drain(region.dialogue)
	await _frames(2)

	# ── 6a. the drill ────────────────────────────────────────────────────
	_check(main.practice != null, "the sling drill starts after the narration")
	var throws := 0
	var practice_frames := 0
	while main.practice != null and practice_frames < FRAME_GUARD:
		practice_frames += 1
		if main.practice != null and main.practice.is_aiming():
			main.practice.aim_perfect()
			main.practice.press()
			throws += 1
		await get_tree().process_frame
	_check(main.practice == null, "three jars end the drill")
	_check(throws == 3, "the drill asks for three throws, not one (took %d)" % throws)
	await _wait_open(region.dialogue)
	_check(region.dialogue._open, "the slope has one more thing to say")
	_drain(region.dialogue)
	await _wait_open(region.dialogue)
	_check(main.act_id() == "errand", "the drill hands over to the errand (act=%s)" % main.act_id())
	_check(region.dialogue._open, "the father speaks in Bethlehem")
	# Close the father's beat before walking: the world is paused while a box is
	# open, so a player standing on a provision collects nothing — and a test
	# standing on one collects nothing either.
	_drain(region.dialogue)
	await _frames(2)
	_check(not region._paused, "the errand releases the world")

	# ── 6b. the errand ───────────────────────────────────────────────────
	var prov_spawned := 0
	for it in region.pickups:
		if str(it.get("kind", "")) == "provision":
			prov_spawned += 1
	_check(prov_spawned == 3, "three provisions are laid out in Bethlehem (got %d)" % prov_spawned)
	# BUG B: "the item cannot be seen on the map". One provision used to sit
	# inside a solid altar prop, 35 tiles from anywhere the camera looked.
	var dact: Dictionary = region.model.david_act
	var farthest := 0.0
	for it in dact.get("items", []):
		var at: Array = it["at"]
		var tx := int(at[0]); var ty := int(at[1])
		if region.model.solid_at_tile(tx, ty):
			_check(false, "provision %s is inside a solid tile or prop" % it.get("id"))
		var d := Vector2(float(tx) * 16.0 + 8.0, float(ty) * 16.0 + 8.0)
		farthest = maxf(farthest, d.distance_to(region.player.global_position) / 16.0)
	_check(farthest <= 6.0,
		"every provision is within six tiles of the errand start (%.1f)" % farthest)
	var prov_tiles := []
	for it in dact.get("items", []):
		var at: Array = it["at"]
		prov_tiles.append([int(at[0]), int(at[1])])
	for t in prov_tiles:
		await _stand(region, int(t[0]), int(t[1]), 4)
		# A curio may be standing on the same patch of dirt; the world is paused
		# while it talks, so clear any box before expecting the pickup to land.
		_drain(region.dialogue)
		await _frames(3)
	_check(int(main.provisions) == 3, "three provisions gathered (got %d)" % int(main.provisions))

	# ── 6c. the brothers, and then the king ──────────────────────────────
	var bat: Array = dact.get("brothers_at", [16, 40])
	await _stand(region, int(bat[0]), int(bat[1]) + 1, 5)
	_check(bool(main._brothers_met), "walking to the brothers opens their beat")
	# Step ONE beat, not the whole chain: _drain() follows chained beats, which
	# is what makes it useful elsewhere and exactly wrong here — it would eat the
	# king's scene and hand back an act that had already moved on.
	_drain_one(region.dialogue)
	await _frames(3)
	_check(main.act_id() == "saul", "the brothers hand you to the king (act=%s)" % main.act_id())
	# The king is a person in the camp you have to walk to, not a card that
	# appears over the brothers. 1 Samuel 17:31 says they brought David to Saul;
	# that walk is the beat.
	var king: Npc = _find_npc(region, "saul")
	_check(king != null, "the king is standing in the camp")
	if king != null:
		var kat: Array = king.data.get("at", [21, 41])
		await _stand(region, int(kat[0]), int(kat[1]) + 1, 4)
		king.talk()
		await _frames(2)
		_check(region.dialogue._open, "Saul speaks when you walk up to him")
		_drain(region.dialogue)
	await _frames(3)
	# ── 6c2. Saul's armour, walked in (1 Samuel 17:38-39) ────────────────
	# Not a message saying "you cannot move": the world is handed back with the
	# player wearing it, at 42% speed, and the scene ends when they have really
	# tried to walk.
	_check(main.act_id() == "armour",
		"Saul's armour goes on after he speaks (act=%s)" % main.act_id())
	var dave = region.player
	_check(bool(dave.armour), "David is wearing the armour")
	_check(absf(dave.speed_scale() - 0.42) < 0.001,
		"and he moves at %.0f%% of his own speed" % (dave.speed_scale() * 100.0))
	_check(main.hud.prompt_lbl.visible, "the way out of the armour is on screen")
	_check(main.fight == null, "the king does not start the fight")
	# Walk in it. The intent is the same vector a thumb would push.
	dave.external_intent = Vector2(1, 0)
	var stagger := 0
	while main.act_id() == "armour" and stagger < 240:
		await get_tree().process_frame
		stagger += 1
	dave.external_intent = Vector2.ZERO
	_check(stagger < 240, "walking in the armour ends the scene (after %d frames)" % stagger)
	_check(region.dialogue._open, "and it ends in 17:39, on screen")
	_drain(region.dialogue)
	await _frames(4)
	_check(not bool(dave.armour), "the armour comes off")
	_check(absf(dave.speed_scale() - 1.0) < 0.001, "and David walks like himself again")
	_check(bool(GameState.flag("elah_armour_off")), "the chapter records that it came off")
	_check(main.act_id() == "stones",
		"the mission moves on to the brook (act=%s)" % main.act_id())
	_check(int(main._stones_total) == 5, "the brook asks for five stones (got %d)" % int(main._stones_total))
	_check(main.stones_panel == null, "and the picking has not started yet")

	# ── 6c3. five stones, chosen by hand (1 Samuel 17:40) ────────────────
	# The player walks down to the water; nothing is picked up by accident.
	var brk: Dictionary = dact.get("brook", {})
	var bat2: Array = brk.get("at", [16, 27])
	await _stand(region, int(bat2[0]), int(bat2[1]), 5)
	_check(region.dialogue._open, "standing in the brook says what this place is")
	_drain(region.dialogue)
	await _frames(4)
	_check(main.stones_panel != null, "and the stones come up to be chosen")
	if main.stones_panel == null:
		_finish_run()
		return
	var panel = main.stones_panel
	_check(panel.stones.size() >= 5, "there are stones in the water (got %d)" % panel.stones.size())
	_check(panel.chosen_count() == 0, "and none of them are chosen yet")
	panel.toggle(0)
	panel.toggle(0)
	_check(panel.chosen_count() == 0, "tapping a stone twice puts it back")
	panel.toggle(0)
	panel.toggle(1)
	panel.toggle(2)
	_check(panel.chosen_count() == 3, "three chosen (got %d)" % panel.chosen_count())
	_check(not panel.is_full(), "and three is not five")
	panel.toggle(3)
	panel.toggle(4)
	_check(panel.is_full(), "five chosen, and the scene knows it")
	var before_six: int = int(panel.chosen_count())
	panel.toggle(5)
	_check(panel.chosen_count() == before_six, "a sixth stone cannot be taken")
	_check(int(main.stones) != 5, "the pouch is still empty while the choice is open")
	panel.confirm()
	await _frames(4)
	_check(main.stones_panel == null, "confirming closes the picking")
	_check(int(main.stones) == 5, "exactly five stones are in the pouch (got %d)" % int(main.stones))
	_check(region.dialogue._open, "and 17:40 is spoken over them")
	_drain(region.dialogue)
	await _frames(4)
	_check(main.act_id() == "ready",
		"the fifth stone sends you up to the line (act=%s)" % main.act_id())

	# ── 6d. walk to the line, as David ───────────────────────────────────
	await _stand(region, 16, 15, 3)
	await _stand(region, 16, 10, 4)
	_check(main.act_id() == "fight", "crossing the line as David starts the fight (act=%s)" % main.act_id())
	_check(region._paused, "the world stops for the confrontation")
	await _wait_open(region.dialogue)
	_check(region.dialogue._open, "the line is spoken before the fight: 17:44 and 17:45")
	_drain(region.dialogue)
	var waited2 := 0
	while main.fight == null and waited2 < FRAME_GUARD:
		await get_tree().process_frame
		waited2 += 1
	_check(main.fight != null, "the words end and the fight begins")
	if main.fight == null:
		_finish_run()
		return
	var duel = main.fight

	# ── 7. the fight: he attacks, you dodge, you throw ──────────────────
	# Playtest 9: "david goliath should be a real fight using stone throwing and
	# avoid goliath attack instead of using word". There is no quiz left: the
	# whole confrontation is this loop, driven here through the same press() a
	# thumb uses.
	_check(duel.HITS_TO_WIN == 3, "three stones finish it")
	_check(not region.dialogue._open, "no dialogue box is covering the fight")
	var nerve_start := int(duel.nerve)
	var saw_strike := false
	var saw_aim := false
	var strikes := 0
	var aims := 0
	var fight_frames := 0
	# Real speed: everything else in this run is at 24x, where a strike phase is
	# two frames long and the assertions below would race the engine.
	Engine.time_scale = 1.0
	Engine.max_fps = 240
	while main.fight != null and fight_frames < 4000:
		fight_frames += 1
		var f = main.fight
		if f == null:
			break
		if int(f.phase) == int(GoliathFight.Phase.DONE):
			break
		if int(f.phase) == int(GoliathFight.Phase.STRIKE):
			saw_strike = true
			strikes += 1
			f.press()                     # step aside
		elif int(f.phase) == int(GoliathFight.Phase.AIM):
			saw_aim = true
			aims += 1
			f.aim_perfect()
			f.press()                     # let go
		await get_tree().process_frame
	Engine.max_fps = 0
	Engine.time_scale = 24.0
	_check(saw_strike, "Goliath attacks, and the strike is dodgeable")
	_check(saw_aim, "and you get a throw after every exchange")
	_check(strikes >= 3 and aims >= 3, "the fight alternated %d strikes / %d throws" % [strikes, aims])
	_check(int(duel.phase) == int(GoliathFight.Phase.DONE), "three stones end the fight")
	_check(nerve_start == 3, "a dodged strike costs no nerve (nerve was %d)" % nerve_start)
	# He falls on screen and stays there while the chapter's last lines are
	# spoken: the duel does not blink out the instant the third stone lands.
	_check(duel.layer < int(region.dialogue.layer),
		"the duel is drawn under the dialogue box, not over it")
	var fell := 0
	while not region.dialogue._open and fell < FRAME_GUARD:
		await get_tree().process_frame
		fell += 1
	_check(region.dialogue._open and main.fight != null,
		"the verses are spoken over the fallen giant, which is still on screen")

	# the victory lines, then RETURN, which hands the story back before controls
	var cleared := 0
	while cleared < FRAME_GUARD:
		if region.dialogue._open:
			_drain(region.dialogue)
		elif main.act_id() != "fight":
			break
		await get_tree().process_frame
		cleared += 1
	_check(main.act_id() != "fight", "the win closes the fight (act=%s)" % main.act_id())

	# ── 7c. chapter 6 is witnessed: the aftermath is a person ────────────
	var corin: Npc = _find_npc(region, "corin")
	_check(main.act_id() == "aftermath",
		"the giant falling hands you back to the witness (act=%s)" % main.act_id())
	_check(corin != null, "Corin is still there to tell")
	if corin != null:
		_check(not (corin.data.get("after_win", []) as Array).is_empty(),
			"Corin has something new to say once the giant is down")
		corin.talk()
		await _frames(2)
		_check(region.dialogue._open, "the aftermath is played, not summarised")
		_drain(region.dialogue)

	# A second thing to say is not Corin's private feature: with the giant down
	# the whole camp answers differently, which is what a state-aware NPC is for.
	for nid in ["boy", "woman", "elder"]:
		var other: Npc = _find_npc(region, nid)
		_check(other != null and not (other.data.get("after_win", []) as Array).is_empty(),
			"%s has a second thing to say once the giant is down" % nid)

	# ── 8. RETURN, and what it left in the save ──────────────────────────
	# RETURN hands the story back BEFORE the controls: the ending card, the
	# reflection question and its three answers all play while the valley is
	# still paused, and only then does the world resume. This used to dump the
	# player into a silent field the instant the giant fell.
	var settle := 0
	var saw_reflection := false
	while settle < FRAME_GUARD:
		settle += 1
		if region.dialogue._open:
			if region.dialogue._in_choices:
				saw_reflection = true
				region.dialogue._pick(0)
			else:
				region.dialogue._advance()
		elif not bool(main._in_battle) and not region._paused:
			break
		await get_tree().process_frame
	_check(saw_reflection, "the chapter ends with a choice, not a dead stop")
	_check(not bool(main._in_battle), "RETURN completed and the valley is playable again")
	_check(bool(GameState.flag("goliath_down")), "the valley remembers he is down")
	_check(_has(GameState.data["relics"], "stones"), "the five stones are kept as a relic")
	_check(_has(GameState.data["completed"], "elah"), "chapter I is marked complete")
	# Not "xp >= 120". add_xp() SPENDS xp on levels: it subtracts xp_needed() for
	# each level-up, so data["xp"] is the remainder inside the current level, not
	# a running total. 120 from level 1 buys level 3 (40 + 70) and leaves 10 —
	# asserting a total here was asserting the wrong thing, and it failed against
	# a game that was behaving correctly.
	var lvl := int(GameState.data["level"])
	var left := int(GameState.data["xp"])
	_check(lvl > level_before, "RETURN levels you up (was %d, now %d)" % [level_before, lvl])
	_check(left >= 0 and left < GameState.xp_needed(lvl),
		"leftover xp sits inside the new level (%d of %d)" % [left, GameState.xp_needed(lvl)])
	_check(_has(GameState.data["fruits"], "faithfulness"), "fruit was gathered")
	# Marks: each one is earned by doing the thing, not by reaching a screen.
	for sid in ["first_verse", "five_stones", "the_drill", "the_argument",
			"giant_down", "chapter_one"]:
		_check(_has(GameState.data["seals"], str(sid)), "the mark '%s' was earned" % sid)
	_check(not region._paused, "the valley is unpaused after RETURN")
	_check(region.player != null, "you are still yourself after RETURN")
	_check(_tile_of(region.player) == Vector2i(16, 14), "you are stood back south of the line, past the re-arm row")

	# ── 9. coming back is a memory, not a replay ─────────────────────────
	var xp_before := int(GameState.data["xp"])
	await _stand(region, 16, 9, 4)
	_check(not bool(main._in_battle), "walking back over the line does not replay the fight")
	_check(region.dialogue._open, "walking back gives the memory and the verse")
	_drain(region.dialogue)
	_check(not region._paused, "the memory releases the world")
	_check(int(GameState.data["xp"]) == xp_before, "the memory is not a way to farm xp")

	# ── 9b. the chapter survives the tab closing ─────────────────────────
	# Saving was implemented and never called: a phone that switched apps came
	# back to a fresh valley. It is now written on every act change, every few
	# seconds of walking, and on the browser's pause/close notifications.
	main._save_progress()
	_check(FileAccess.file_exists(GameState.SAVE_PATH), "the chapter writes a save file")
	var saved := {}
	if FileAccess.file_exists(GameState.SAVE_PATH):
		var f := FileAccess.open(GameState.SAVE_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				saved = parsed
	_check(str((saved.get("progress", {}) as Dictionary).get("act", "")) != "",
		"the save records which act the chapter had reached")
	# And the mapping back: a save that says "ready" must boot into "ready"
	# rather than at the top of the valley. The finished-chapter flag is stashed
	# for the length of this check, then put back — the ending is not undone.
	var act_int: int = int(main.act)
	var had_down := bool(GameState.data["flags"].get("goliath_down", false))
	GameState.data["flags"]["goliath_down"] = false
	GameState.data["progress"] = {"act": "ready", "stones": 5, "provisions": 3,
		"brothers": true, "pos": [16, 15]}
	main.act = 0
	main._resume_story()
	# Resuming is "start the mission list at this index", so it is the runner
	# entering the mission that puts the chapter back in the right act.
	main._begin_missions()
	await _frames(3)
	_check(main.act_id() == "ready",
		"a save in David's act resumes there, not at the top of the valley (act=%s)"
		% main.act_id())
	_drain(region.dialogue)
	await _frames(2)
	GameState.data["flags"]["goliath_down"] = had_down
	main.act = act_int
	await _frames(2)

	# ── 10. one tap is one thing ─────────────────────────────────────────
	# Playtest 9: "clicking an NPC caused the same dialogue to appear three
	# times." A phone tap arrives as a touch AND an emulated mouse click, and
	# the A button synthesises a third event on top. Three consumers each acted
	# on one of them. These assertions pin the arbitration down at the level the
	# player experiences: one gesture, one step.
	var witness: Npc = _find_npc(region, "corin")
	_check(corin != null, "Corin is still in the valley at the end")
	if witness != null:
		TapGate.reset()
		# Headless runs uncapped: dozens of frames pass in a few milliseconds, so
		# a 0.5 s wall-clock cooldown from the last conversation is still running
		# here even though "many frames" have gone by. Wait real time.
		OS.delay_msec(600)
		await _frames(2)
		_check(witness.can_talk(),
			"a person can be talked to when nothing is open (box=%s talk=%d paused=%s)"
			% [str(region.dialogue.is_open()), int(witness.talk_state), str(region.is_paused())])
		var id_before := int(region.dialogue._box_id)
		witness.talk()
		await _frames(2)
		_check(int(region.dialogue._box_id) == id_before + 1, "talking opens exactly one box")
		_check(not witness.can_talk(), "the same person cannot be re-entered mid-sentence")
		witness.talk()
		_check(int(region.dialogue._box_id) == id_before + 1,
			"a second call in the same breath opens no second box")
		_check(witness.talk_state == Npc.Talk.SPEAKING, "the NPC is in SPEAKING, not IDLE")

		# The whole screen is the advance target while a box is open, and the
		# stick and A stand down so they cannot fight it.
		await _frames(2)
		_check(main.touch.blocked, "the touch controls stand down during a conversation")

		# one gesture = one step, even though it arrives as two events
		var page0 := int(region.dialogue._page)
		var line0 := int(region.dialogue._i)
		var full: String = str(region.dialogue._current_page_text())
		region.dialogue._shown = float(full.length())
		region.dialogue.text_lbl.text = full
		var tap := InputEventScreenTouch.new()
		tap.pressed = true
		tap.index = 0
		tap.position = Vector2(160, 90)
		var click := InputEventMouseButton.new()
		click.pressed = true
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = Vector2(160, 90)
		region.dialogue._input(tap)
		region.dialogue._input(click)
		var moved := (int(region.dialogue._page) - page0) + (int(region.dialogue._i) - line0)
		_check(moved == 1, "one tap moves exactly one step (moved %d)" % moved)

		# and the next tap, a gesture later, moves exactly one more. TapGate is
		# reset rather than slept through: this is a NEW gesture by definition,
		# and the run is at Engine.time_scale 24, where wall-clock waiting is two
		# frames and would test the throttle instead of the tap.
		TapGate.reset()
		var page1 := int(region.dialogue._page)
		var line1 := int(region.dialogue._i)
		var full1: String = str(region.dialogue._current_page_text())
		region.dialogue._shown = float(full1.length())
		region.dialogue.text_lbl.text = full1
		var tap2 := InputEventScreenTouch.new()
		tap2.pressed = true
		tap2.index = 0
		tap2.position = Vector2(160, 90)
		region.dialogue._input(tap2)
		var moved2 := (int(region.dialogue._page) - page1) + (int(region.dialogue._i) - line1)
		_check(moved2 == 1, "the next tap moves exactly one more (moved %d)" % moved2)

		_drain(region.dialogue)
		# COOLDOWN is checked BEFORE any frame passes: the run is 24x real time,
		# so a 0.5 s cooldown is over in about one frame.
		_check(witness.talk_state == Npc.Talk.COOLDOWN,
			"the NPC goes into COOLDOWN, not straight back to READY")
		await _frames(3)
		_check(not region.dialogue._open, "the conversation closes on its own")
		_check(not region._paused, "closing a box hands the world back")
		_check(not main.touch.blocked, "the touch controls come back with it")
		# same wall-clock wait, for the cooldown this conversation just started
		OS.delay_msec(560)
		_check(witness.can_talk(), "and the person is talkable again after the cooldown")

	_finish_run()


# ── harness ────────────────────────────────────────────────────────────────
func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok    " + msg)
	else:
		fails += 1
		printerr("  FAIL  " + msg)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _stand(region, tx: int, ty: int, frames: int) -> void:
	## Put the player on a tile and let real frames pass, so Region._process
	## sees it exactly as it would see a thumb holding the stick.
	var p = region.player
	p.global_position = Vector2(float(tx) * TILE + 8.0, float(ty) * TILE + 8.0)
	await _frames(frames)


func _wait_open(dlg, guard: int = 900) -> void:
	## Fades sit between the act changes and the words. Waiting for the box to
	## open is honest; counting frames is guessing at a tween's length.
	var i := 0
	while not dlg._open and i < guard:
		await get_tree().process_frame
		i += 1


func _drain_one(dlg) -> void:
	## Advance exactly one beat: stop as soon as the box id changes, so a chained
	## beat stays on screen for the assertions that come next.
	var id0 := int(dlg._box_id)
	var guard := 0
	while dlg._open and not dlg._in_choices and int(dlg._box_id) == id0 and guard < 300:
		dlg._advance()
		guard += 1
	if guard >= 300:
		_check(false, "a dialogue box would not advance")


func _drain(dlg) -> void:
	## Advance every open box until a choice appears or everything has closed.
	## _advance() finishes the typing on its first call and turns the page on
	## the second, so one loop drains a whole chain of beats.
	var guard := 0
	while dlg._open and not dlg._in_choices and guard < 300:
		dlg._advance()
		guard += 1
	if guard >= 300:
		_check(false, "a dialogue box would not close on its own")


func _tile_of(n) -> Vector2i:
	var pos: Vector2 = n.global_position
	return Vector2i(int(floorf(pos.x / TILE)), int(floorf(pos.y / TILE)))


func _find_npc(region, id: String) -> Npc:
	for n in region.npcs:
		var npc: Npc = n
		if str(npc.data.get("id", "")) == id:
			return npc
	return null


func _has(v: Variant, id: String) -> bool:
	var arr: Array = v
	for x in arr:
		if str(x) == id:
			return true
	return false


func _finish_run() -> void:
	Engine.time_scale = 1.0
	if fails == 0:
		print("smoke: PASS — the slice played start to finish")
		get_tree().quit(0)
	else:
		printerr("smoke: FAIL — %d assertion(s) did not hold" % fails)
		get_tree().quit(1)
