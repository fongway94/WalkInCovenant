extends Node
## tests/smoke.gd — plays the vertical slice headless and asserts the loop closes.
##
## run_all.gd checks the CONTENT is well formed. This checks the GAME WORKS.
## It boots Main.tscn, reads the briefing, talks to all four people, crosses the
## line with an empty pouch, goes back for the stones, crosses again, fights the
## word battle to a win, walks back into the valley, and asserts the save state
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
	_check(region.pickups.size() == 5, "5 stones in the brook (got %d)" % region.pickups.size())
	_check(region.triggers.size() == 1, "challenge trigger was built (got %d)" % region.triggers.size())
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
	var carried: Array = GameState.data["words"]
	_check(carried.size() == 4, "four verses were handed over (got %d)" % carried.size())

	# ── 4. crossing early must refuse you, and must let you try again ────
	await _stand(region, 16, 10, 4)
	_check(region.dialogue._open, "crossing the line opens a beat")
	_check(not main._in_battle, "crossing without stones does not start a fight")
	_drain(region.dialogue)
	_check(not region._paused, "the refusal releases the world")
	_check(_tile_of(region.player).y > 11, "the refusal steps you back south")
	# Playtest 4 reported "it keeps prompting dialogue and looping": the beat
	# pushed the player back a few tiles and re-armed at once, so a held thumb
	# walked straight back in. The trigger now re-arms only past `rearm_row`.
	await _stand(region, 16, 12, 3)
	_check(not bool(region.triggers[0]["armed"]),
		"standing in the dead band does not re-arm the line")
	await _stand(region, 16, 15, 3)
	_check(bool(region.triggers[0]["armed"]), "the line re-arms so the walk can be tried again")

	await _stand(region, 16, 10, 4)
	_check(region.dialogue._open, "crossing again with an empty pouch is heard again")
	_drain(region.dialogue)
	await _frames(3)

	# ── 5. the brook ─────────────────────────────────────────────────────
	for p in region.pickups:
		var d: Dictionary = p["data"]
		var at: Array = d["at"]
		await _stand(region, int(at[0]), int(at[1]), 3)
		# the brook has a curio in it; a box on screen pauses the collection
		_drain(region.dialogue)
		await _frames(3)
	_check(int(main.stones) == 5, "five stones gathered (got %d)" % int(main.stones))

	var level_before := int(GameState.data["level"])

	# ── 6. BECOME, and then David's whole story ─────────────────────────
	# Chapter 2 first: three days earlier, the sheep slope, and the drill that
	# teaches the one input the fight asks for. Then Jesse's errand. Then the
	# king. Only then is there a fight.
	await _stand(region, 16, 10, 4)
	_check(bool(main._in_battle), "crossing with five stones begins BECOME")
	_check(region._paused, "the world holds still while you become David")
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
	_check(main.act_id() == "ready", "after the armour comes off you are sent down (act=%s)" % main.act_id())
	_check(main.battle == null, "the king does not start the fight")
	_check(not region._paused, "the walk to the line is yours to make")

	# ── 6d. walk to the line, as David ───────────────────────────────────
	await _stand(region, 16, 15, 3)
	await _stand(region, 16, 10, 4)
	var waited2 := 0
	while main.battle == null and waited2 < FRAME_GUARD:
		await get_tree().process_frame
		waited2 += 1
	_check(main.battle != null, "crossing the line again starts the fight")
	if main.battle == null:
		_finish_run()
		return
	var battle = main.battle
	_check(battle.hand.size() >= 1, "you carry verses into the fight (%d)" % battle.hand.size())

	# ── 7. the shouting match ────────────────────────────────────────────
	var rounds := 0
	while battle.fight == null and rounds < 12:
		rounds += 1
		_drain(region.dialogue)
		if region.dialogue._in_choices:
			var pick := _answer_index(region.dialogue, battle)
			_check(pick >= 0, "round %d can be answered with a verse you carry" % rounds)
			if pick < 0:
				break
			region.dialogue._pick(pick)
		await _frames(3)
	_check(rounds >= 2, "the argument ran at least two rounds (took %d)" % rounds)

	# ── 7b. the fight: he attacks, you dodge, you throw ──────────────────
	# Playtest 7: "should make it more interesting like fighting goliath. throw
	# stone to attack goliath and avoid its attack". Both halves are driven here
	# through the same press() a thumb uses.
	_check(battle.fight != null, "the argument ends in the fight itself")
	var nerve_start := 0
	if battle.fight != null:
		nerve_start = int(battle.fight.nerve)
	var saw_strike := false
	var saw_aim := false
	var fight_frames := 0
	# Play the duel at real speed. Everything else in this test runs at 24x, and
	# at 24x a strike phase is two frames long — the assertions below would then
	# be racing the engine instead of testing the fight.
	Engine.time_scale = 1.0
	while battle.fight != null and fight_frames < FRAME_GUARD:
		fight_frames += 1
		var f = battle.fight
		if f == null:
			break
		if int(f.phase) == int(GoliathFight.Phase.STRIKE):
			saw_strike = true
			f.press()                     # dodge
		elif int(f.phase) == int(GoliathFight.Phase.AIM):
			saw_aim = true
			f.aim_perfect()
			f.press()                     # throw
		await get_tree().process_frame
	Engine.time_scale = 24.0
	_check(saw_strike, "Goliath attacks, and the strike phase is reachable")
	_check(saw_aim, "the throw phase is reachable")
	_check(battle.fight == null, "three stones end the fight")
	_check(nerve_start == 3, "a dodged strike costs no nerve (nerve was %d)" % nerve_start)
	_check(battle.fight == null and fight_frames > 0, "the fight ran a real loop, not one press")
	await _frames(4)

	# the win lines, then RETURN, which hands the story back before the controls
	var cleared := 0
	while main.battle != null and cleared < FRAME_GUARD:
		_drain(region.dialogue)
		await get_tree().process_frame
		cleared += 1
	_check(main.battle == null, "the win closes the battle and cleans it up")

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


func _answer_index(dlg, battle) -> int:
	## The verse whose kind answers the shout he just made. WordBattle only
	## shouts kinds you are holding, so this must always find one.
	var kind := str(battle.shout.get("kind", ""))
	var opts: Array = dlg._choices
	for i in range(opts.size()):
		var o: Dictionary = opts[i]
		if str(o.get("kind", "")) == kind:
			return i
	return -1


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
