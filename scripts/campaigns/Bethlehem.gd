extends Node
## Bethlehem — 1 Samuel 16:1-13, from the witness's side.
##
## This is the campaign contract made concrete. Nothing in `Main.gd` knows the
## name Bethlehem, Samuel, or an anointing: the region file names this script,
## and everything below is that story's own business. It talks to the shared
## machinery through four doors only —
##
##   `region.dialogue`   the box, with portraits and pagination
##   `region.set_paused` the world's brake, so a scene owns the picture
##   `region.model`      this region's data (lines, verses, objectives)
##   `GameState`         flags, which is how the mission runner hears about it
##
## and reports the next step through `guidance()`, which `Main` renders. If this
## file were deleted, the region would still load and walk; it would simply have
## no story. That is the seam the brief asks for.
##
## Scripture: 16:7, 16:10, 16:11, 16:12 and 16:13 are quoted verbatim in
## KJV and 和合本 from `data/regions/bethlehem.json`. The townspeople — the
## elder, the woman at the well, Jesse's household as they wait — are invented,
## and none of them says anything Scripture contradicts.

var main: Node = null
var region: Region = null
var runner: MissionRunner = null

## A scene is on screen. One beat at a time: the box cannot open twice.
var _busy := false


func setup(m: Node, r: Region, run: MissionRunner) -> void:
	main = m
	region = r
	runner = run


# ── arrival ───────────────────────────────────────────────────────────────
## Called by Main when the player walks in from another region. Not a resume:
## arriving somewhere new begins with being told where you have arrived.
func arrived() -> void:
	var lines: Array = _scene("arrival")
	if lines.is_empty():
		_card()
		return
	_say(lines, _card)


func _card() -> void:
	if main == null or main.card == null or region == null:
		return
	main.card.show_card(region.model.display_name, region.model.display_sub)


# ── the next step, in one sentence ────────────────────────────────────────
## The HUD's objective and arrow. `Main` calls this before its own guidance, so
## a campaign that knows its own story never has to teach the shared layer the
## words "elder", "field" or "anoint".
func guidance() -> Dictionary:
	if region == null or runner == null or region.player == null:
		return {}
	var here: Vector2 = region.player.global_position
	var key := "done"
	var target := here
	var point := false
	match runner.current_id():
		"beth_gate":
			key = "gate"
			var e := _npc("elder")
			if e != null:
				target = e.global_position
				point = true
		"beth_sons":
			key = "house"
			var s := _npc("samuel")
			if s != null:
				target = s.global_position
				point = true
		"beth_call":
			key = "field"
			var d := _npc("david")
			if d != null:
				target = d.global_position
				point = true
		"beth_anoint":
			key = "return"
			var s2 := _npc("samuel")
			if s2 != null:
				target = s2.global_position
				point = true
		_:
			# The chapter is over: the only thing left to want is the road home.
			key = "done"
			var ex := _exit_point()
			if ex != Vector2.ZERO:
				target = ex
				point = true
	var obj: Dictionary = region.model.objectives
	return {"line": I18n.t(obj.get(key, {})), "target": target, "point": point}


# ── what people do when you speak to them ─────────────────────────────────
## Runs AFTER the NPC's own box has closed (Main wires it to
## `EventBus.player_interacted_with`). Returns true when this chapter has taken
## the beat and wants no further shared handling.
func on_interact(id: String) -> bool:
	if _busy:
		return true
	if id == "elder":
		if not bool(GameState.flag("beth_met_elder")):
			GameState.set_flag("beth_met_elder", true)
			_toast({"en": "Jesse's house is up by the wall.",
				"zh": "耶西的家在城墙边上。"})
		return true
	if id == "david":
		if bool(GameState.flag("beth_sons_seen")) and not bool(GameState.flag("beth_called")):
			GameState.set_flag("beth_called", true)
			_toast({"en": "He comes with you. The sheep follow him.",
				"zh": "他跟着你走。羊跟着他。"})
		return true
	if id == "samuel":
		if not bool(GameState.flag("beth_met_elder")):
			return true
		if not bool(GameState.flag("beth_sons_seen")):
			_sons_scene()
			return true
		if bool(GameState.flag("beth_called")) and not bool(GameState.flag("beth_anointed")):
			_anoint_scene()
			return true
		return true
	if id == "jesse" or id == "eliab" or id == "woman":
		return false
	return false


## The procession of the sons, 16:7-11. This is the beat the chapter exists to
## make the player hear: seven men, and the prophet says no to every one.
func _sons_scene() -> void:
	_say(_scene("sons"), func():
		GameState.set_flag("beth_sons_seen", true)
		region.follow_player(0.5)
		_toast({"en": "Someone is missing from the house. He is with the sheep.",
			"zh": "这家里少了一个人。他在羊那里。"}))


## 16:12-13. The anointing is spoken, not performed: what the game shows is the
## horn, the oil, and the boy it lands on in front of seven brothers.
func _anoint_scene() -> void:
	var d := _npc("david")
	region.set_paused(true)
	if d != null:
		region.pan_to(d.global_position, 0.6)
	_say(_scene("anoint"), func():
		GameState.set_flag("beth_anointed", true)
		region.follow_player(0.6)
		region.dialogue.show_lines([_line({
			"en": "The prophet does not look at the brothers. He looks at the one who came in from the field with dust on his feet.",
			"zh": "先知没有看那几个兄长。他看的，是那个脚上还带着土、刚从田里回来的人。"})],
			func(_w): return {}, func():
				region.set_paused(false)
				_card()))


# ── plumbing ──────────────────────────────────────────────────────────────
func _say(lines: Array, done: Callable) -> void:
	if lines.is_empty():
		done.call()
		return
	_busy = true
	region.set_paused(true)
	region.dialogue.show_lines(lines, _speaker, func():
		_busy = false
		region.set_paused(false)
		done.call())


## A speaker id resolves through THIS region's cast, so a line can say
## `"who": "samuel"` and get Samuel's name and portrait without a script change.
func _speaker(who: String) -> Dictionary:
	if who == "":
		return {}
	for n in region.npcs:
		if n.npc_id() == who:
			return {"name": n.display_name(), "actor": str(n.data.get("actor", who))}
	var table: Dictionary = region.model.david_act.get("speakers", {})
	if table.has(who):
		var nm: Dictionary = table[who]
		return {"name": I18n.t(nm), "actor": str(nm.get("actor", who))}
	return {"name": I18n.t(who), "actor": who}


func _scene(key: String) -> Array:
	var scenes: Dictionary = region.model.scenes
	return scenes.get(key, [])


func _line(text: Dictionary) -> Dictionary:
	return {"who": "", "text": text}


func _npc(id: String) -> Npc:
	for n in region.npcs:
		if n.npc_id() == id:
			return n
	return null


func _exit_point() -> Vector2:
	for e in region.model.exits:
		var at: Array = e.get("at", [])
		if at.size() == 2:
			return Vector2(float(at[0]) * 16.0 + 8.0, float(at[1]) * 16.0 + 8.0)
	return Vector2.ZERO


func _toast(text: Dictionary) -> void:
	EventBus.toast_requested.emit(I18n.t(text))
