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
		# get_supported_chars()/has_char() walk the freetype cmap when the
		# render path is warm, but a cold headless boot can answer from the
		# glyphs shaped so far — one run knew 谷 (seen in the briefing) yet
		# denied 石 (not yet drawn). So the table is asserted only when it IS
		# the whole table; the diag line above says which world this was.
		if supported.length() >= 400:
			var gu: int = "谷".to_utf32_buffer()[0]
			var shi: int = "石".to_utf32_buffer()[0]
			_check(bool(face.has_char(gu)) and bool(face.has_char(shi)),
					"the font's char table carries hanzi")
	_check(ThemeDB.fallback_font != null, "ThemeDB has a fallback font registered")
	if ThemeDB.fallback_font != null:
		print("  diag  fallback font: %s" % ThemeDB.fallback_font.resource_path)
		_check(ThemeDB.fallback_font.resource_path == "res://fonts/game.ttf",
				"the theme falls back to the bundled font")

	# ── 2. a first-time player is told what to do ────────────────────────
	_check(region.dialogue._open, "the valley opens with a briefing")
	_check(region._paused, "the briefing holds the world still")
	_drain(region.dialogue)
	_check(not region._paused, "the briefing releases the world")
	_check(bool(GameState.flag("elah_briefed")), "the briefing is marked as seen")
	main._brief_once()
	_check(not region.dialogue._open, "the briefing does not repeat on a second visit")

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
		_drain(region.dialogue)
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
	await _frames(3)
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
	_check(int(main.stones) == 5, "five stones gathered (got %d)" % int(main.stones))

	var level_before := int(GameState.data["level"])

	# ── 6. BECOME ────────────────────────────────────────────────────────
	await _stand(region, 16, 10, 4)
	_check(bool(main._in_battle), "crossing with five stones begins BECOME")
	_check(region._paused, "the world holds still while you become David")
	var waited := 0
	while main.battle == null and waited < FRAME_GUARD:
		await get_tree().process_frame
		waited += 1
	_check(main.battle != null, "the word battle exists after BECOME (waited %d frames)" % waited)
	if main.battle == null:
		_finish_run()
		return
	var battle = main.battle
	_check(battle.hand.size() >= 1, "you carry verses into the fight (%d)" % battle.hand.size())

	# ── 7. five rounds of shouting back ──────────────────────────────────
	var rounds := 0
	while main.battle != null and rounds < 12:
		rounds += 1
		_drain(region.dialogue)
		if region.dialogue._in_choices:
			var pick := _answer_index(region.dialogue, battle)
			_check(pick >= 0, "round %d can be answered with a verse you carry" % rounds)
			if pick < 0:
				break
			region.dialogue._pick(pick)
		await _frames(3)
	_check(main.battle == null, "the battle ended and was cleaned up (took %d rounds)" % rounds)

	# ── 8. RETURN, and what it left in the save ──────────────────────────
	var settle := 0
	while bool(main._in_battle) and settle < FRAME_GUARD:
		_drain(region.dialogue)
		await get_tree().process_frame
		settle += 1
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
	_check(not region._paused, "the valley is unpaused after RETURN")
	_check(region.player != null, "you are still yourself after RETURN")
	_check(_tile_of(region.player) == Vector2i(16, 13), "you are stood back where the line is")

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
