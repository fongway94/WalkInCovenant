extends Node2D
## Main — boots the world and wires the loop.
##
## Overworld → talk / gather / cross the line → BECOME → word-battle → RETURN.
## Story logic stays in data; Main only routes the moments between systems.

var region: Region = null
var hud: Hud = null
var touch: TouchControls = null
var become: BecomeController = null
var battle: WordBattle = null

var stones := 0
var _stones_total := 0
var _refusals := 0
var _in_battle := false
## Act I you are the witness; Act II you are David, and the story rewinds to his
## father's errand before it lets you fight. Playtest 7 asked for exactly this:
## "being told by father to send provision, collect provision, then walk walk
## then go to the place then properly then talk.. then fight goliath".
enum Act { WITNESS, ERRAND, FIGHT, DONE }
var act: int = Act.WITNESS
var provisions := 0
var _brothers_met := false
var _provision_total := 3
## Seconds the world has been paused with nothing on screen able to end it. This
## is the belt to the dialogue box's braces: a beat that pauses the valley and
## then fails to open (or to close) its own box used to leave the player standing
## in a frozen world with no key that did anything (playtest 5).
var _dead_pause := 0.0
const DEAD_PAUSE_SECS := 6.0


func _ready() -> void:
	# Order matters twice over here.
	#
	# 1. Region._ready() builds the world and emits region_ready, and _ready()
	#    runs synchronously INSIDE add_child(). A connection made after
	#    add_child(region) therefore never hears it: the stick was never bound to
	#    the player and the HUD never bound to the region, so the game booted
	#    into a valley that looked right and could not be walked in. Connect
	#    first, add last.
	#
	# 2. _on_region_ready() calls hud.bind() and touch.bind(), so both must
	#    already exist when region_ready fires. Build them first.
	become = BecomeController.new()
	add_child(become)

	hud = Hud.new()
	add_child(hud)

	touch = TouchControls.new()
	add_child(touch)

	# Receiving a verse is the one reward the game never announced: the HUD's ☆
	# ticked up and nothing else. A player who never noticed the counter has no
	# reason to think the people they meet are worth meeting.
	EventBus.verse_received.connect(_on_verse)

	region = Region.new()
	region.region_id = "elah"
	region.region_ready.connect(_on_region_ready)
	region.pickup_taken.connect(_on_pickup)
	region.trigger_fired.connect(_on_trigger)
	add_child(region)


func _process(delta: float) -> void:
	if region == null or region.dialogue == null:
		return
	var stuck: bool = region.is_paused() and not region.dialogue.is_open() \
		and not _in_battle and battle == null
	if stuck:
		_dead_pause += delta
	else:
		_dead_pause = 0.0
	if _dead_pause >= DEAD_PAUSE_SECS:
		_dead_pause = 0.0
		region.set_paused(false)
		EventBus.toast_requested.emit(I18n.t({
			"en": "The valley lets go of you. Walk on.",
			"zh": "山谷松开了手。继续走吧。"}))
	_update_guidance()


## The objective line and the arrow. One sentence, one direction, always.
##
## Playtest 6: "no story telling, user not understand what to do". Everything
## the game needed a player to know was in a dialogue that had already been
## dismissed, so the valley was a field with five rocks in it. The chain is
## deliberately short and always names the NEXT single action:
##   Corin → the brook → the line → the fight → the ending.
func _update_guidance() -> void:
	if hud == null or region == null or region.player == null:
		return
	if region.dialogue != null and region.dialogue.is_open():
		hud.set_prompt("")
		return
	var p: Player = region.player
	var obj: Dictionary = region.model.objectives
	var target := p.global_position
	var point := false
	var key := "done"
	var line := ""

	match act:
		Act.ERRAND:
			var da: Dictionary = region.model.david_act
			var bat: Array = da.get("brothers_at", [16, 40])
			var brothers := Vector2(float(bat[0]) * 16.0 + 8.0, float(bat[1]) * 16.0 + 8.0)
			if provisions < _provision_total:
				key = "provision"
				target = _nearest_pickup("provision", p.global_position)
				point = true
				line = "%s  %d／%d" % [I18n.t(obj.get(key, {})), provisions, _provision_total]
			else:
				key = "brothers"
				target = brothers
				point = true
				# Arriving is the trigger: no extra button to find.
				if not _brothers_met and p.global_position.distance_to(brothers) < 26.0:
					_brothers_beat()
		Act.FIGHT:
			key = "fight"
		_:
			var corin: Npc = _npc("corin")
			if corin != null and not corin.has_talked():
				key = "corin"
				target = corin.global_position
				point = true
			elif corin != null and corin.has_talked() and _next_unspoken() != null:
				# He walks you to the next person. Not a marker on a map: an
				# escort who stops beside the villager and waits for you.
				var nxt: Npc = _next_unspoken()
				key = "npc"
				target = nxt.global_position
				point = true
				line = I18n.t(obj.get(key, {})) % nxt.display_name()
				if corin.lead_target != nxt:
					corin.lead_to(nxt, func(): _lead_arrived())
			elif stones < _stones_total:
				key = "stones"
				target = _nearest_pickup("stone", p.global_position)
				point = stones < _stones_total
				line = "%s  %d／%d" % [I18n.t(obj.get(key, {})), stones, _stones_total]
			elif not bool(GameState.flag("goliath_down")):
				key = "line"
				var row := int(region.model.trigger_data("challenge").get("row", 11))
				target = Vector2(p.global_position.x, float(row * 16))
				point = true

	if key != "npc":
		var co: Npc = _npc("corin")
		if co != null and co.lead_target != null:
			co.clear_lead()
	if line == "":
		line = I18n.t(obj.get(key, {}))
	hud.set_objective(line)
	hud.point_at(target - p.global_position, point and target.distance_to(p.global_position) > 24.0)

	# Teach the one button that matters, at the moment it matters: standing next
	# to a person. This is the on-screen equivalent of the Z key the old
	# briefing told a phone player to press (playtest 6).
	if region.nearest_interactable() != null:
		hud.set_prompt(I18n.t({"en": "A  ·  talk", "zh": "A  ·  交谈"}))
	else:
		hud.set_prompt("")


## Names for the people who only exist inside the errand. They come from the
## same data as their words, so a translator never has to open a script.
func _errand_speaker(who: String) -> Dictionary:
	if who == "":
		return {}
	var table: Dictionary = region.model.david_act.get("speakers", {})
	var nm: Dictionary = table.get(who, {})
	if nm.is_empty():
		return {}
	return {"name": I18n.t(nm), "actor": who}


## The brothers see him arrive with bread and want him gone. This is the last
## beat before the fight and it is straight out of 1 Samuel 17:28.
func _brothers_beat() -> void:
	if _brothers_met:
		return
	_brothers_met = true
	region.set_paused(true)
	var lines: Array = region.model.david_act.get("brothers", [])
	region.dialogue.show_lines(lines, _errand_speaker, func(): _start_battle())


## The first person in the camp you have not spoken to yet. The order is the
## order the content gives, so the story's own sequence decides the walk.
func _next_unspoken() -> Npc:
	for n in region.npcs:
		var npc: Npc = n
		if npc.npc_id() == "corin" or npc.has_talked():
			continue
		if str(npc.data.get("word", "")) == "":
			continue
		return npc
	return null


## He has brought you to someone. One line, then it is your turn to speak.
func _lead_arrived() -> void:
	var co: Npc = _npc("corin")
	if co == null:
		return
	var note: Dictionary = co.data.get("lead_note", {})
	if note.is_empty():
		return
	EventBus.toast_requested.emit(I18n.t(note))


## Nearest uncollected pickup of a kind, or the player's own feet if there is
## none left (so the arrow simply switches off instead of pointing at nothing).
func _nearest_pickup(kind: String, from: Vector2) -> Vector2:
	var best := from
	var bd := 1e20
	for it in region.pickups:
		if str(it.get("kind", "")) != kind or bool(it.get("got", false)):
			continue
		var node: Node2D = it["node"]
		if not is_instance_valid(node):
			continue
		var d := node.global_position.distance_to(from)
		if d < bd:
			bd = d
			best = node.global_position
	return best


func _npc(id: String) -> Npc:
	for n in region.npcs:
		if n.npc_id() == id:
			return n
	return null


func _on_region_ready() -> void:
	touch.bind(region.player)
	hud.bind(region)
	_stones_total = 0
	for it in region.model.items:
		if str(it.get("kind", "")) == "stone":
			_stones_total += 1
	hud.set_stones(stones, _stones_total)
	AudioDirector.play_music(region.model.music)
	EventBus.player_entered_region.emit(region.region_id)
	_brief_once()


func _brief_once() -> void:
	## First time in the valley, say what the place is and what the hands do.
	## After that the region is just a place to walk in (docs/WORLD.md §4).
	if GameState.flag(str(region.region_id) + "_briefed") == true:
		return
	if region.model.briefing.is_empty():
		return
	GameState.set_flag(str(region.region_id) + "_briefed", true)
	region.set_paused(true)
	region.dialogue.show_lines(region.model.briefing, func(_w): return {}, func():
		region.set_paused(false))


func _on_verse(_id: String, ref: String) -> void:
	EventBus.toast_requested.emit(I18n.t({
		"en": "A verse to carry · %s", "zh": "记住了一句经文 · %s"}) % ref)


func _on_pickup(id: String) -> void:
	if id.begins_with("prov"):
		provisions += 1
		EventBus.toast_requested.emit(I18n.t({
			"en": "Your father's provision · %d/%d", "zh": "父亲给的东西 · %d／%d"})
			% [provisions, _provision_total])
		AudioDirector.play_sfx("pickup", -4.0)
		if provisions >= _provision_total:
			EventBus.toast_requested.emit(I18n.t({
				"en": "That is everything. Your brothers are at the edge of the camp.",
				"zh": "东西都齐了。哥哥们在营地边上。"}))
		return
	if id.begins_with("stone"):
		stones += 1
		if hud != null:
			hud.set_stones(stones, _stones_total)
		GameState.record_way("notice")
		EventBus.toast_requested.emit(I18n.t({
			"en": "A smooth stone · %d/5" % stones,
			"zh": "一块光滑的石子 · %d／5" % stones}))
		AudioDirector.play_sfx("pickup", -4.0)


func _on_trigger(id: String) -> void:
	if id != "challenge" or _in_battle or act == Act.ERRAND or act == Act.FIGHT:
		return
	if stones >= 5:
		var down := bool(GameState.flag("goliath_down"))
		if down:
			_memory_beat()
		else:
			_begin_become()
	else:
		_refuse(id)


func _beat_lines(id: String, key: String) -> Array:
	## Story beats live in the region file, never in here.
	var td := region.model.trigger_data(id)
	var lines: Array = td.get(key, [])
	return lines


func _refuse(id: String) -> void:
	# No fail state: he simply will not let you past without them. Step the
	# player back south so the trigger re-arms and the walk can be tried again.
	#
	# Two things were missing and both cost a playtester the game (playtest 4):
	# the refusal never said HOW MANY stones you were carrying, so there was no
	# way to know you were three short of anything; and the pushback fought the
	# thumb — hold up, get pushed back, walk straight back in, forever. Now the
	# count is spoken first, the stick is dropped, and the pushback is anchored
	# to the challenge row rather than to whatever pixel you were standing on.
	_refusals += 1
	region.set_paused(true)
	var lines: Array = [{
		"who": "",
		"text": {
			"en": "You reach the line with %d of five in your pouch." % stones,
			"zh": "你走到界线前，袋子里只有 %d 块。" % stones
		}
	}]
	lines.append_array(_beat_lines(id, "refuse"))
	region.dialogue.show_lines(lines, func(_w): return {}, func():
		region.set_paused(false)
		region.player.external_intent = Vector2.ZERO
		region.player.velocity = Vector2.ZERO
		var row := int(region.model.trigger_data(id).get("row", 11))
		region.player.global_position = Vector2(
			region.player.global_position.x, float((row + 3) * 16))
		if _refusals >= 2:
			EventBus.toast_requested.emit(I18n.t({
				"en": "The stones are at the brook, south past the tents.",
				"zh": "石子在下游溪边，过了帐篷就是。"})))


func _memory_beat() -> void:
	## The valley is quiet and the fight is over. Coming back is a memory, not a
	## replay: two lines and the verse, then you are free to keep walking.
	## Only once — re-crossing the line afterwards must not stop the player
	## every time they walk north.
	if GameState.flag("elah_memory_shown") == true:
		return
	GameState.set_flag("elah_memory_shown", true)
	region.set_paused(true)
	region.dialogue.show_lines(_beat_lines("challenge", "memory"), func(_w): return {}, func():
		region.set_paused(false))


func _begin_become() -> void:
	_in_battle = true
	region.set_paused(true)
	hud.set_objective(I18n.t({"en": "You are David. The line is behind you.",
		"zh": "你就是大卫。界线在你身后。"}))
	become.begin("david", {"en": "DAVID", "zh": "大卫"}, _start_david_act)


## Act II opens on the errand that put David in the valley at all: Jesse's
## provisions, the walk, the brothers who do not want him there. Without this
## beat the stones and the fight arrive with no story under them.
func _start_david_act() -> void:
	act = Act.ERRAND
	provisions = 0
	_brothers_met = false
	hud.set_role(I18n.t({"en": "David", "zh": "大卫"}), 1)
	var da: Dictionary = region.model.david_act
	if da.is_empty():
		# A region may not have the act at all. Then becoming David goes straight
		# to the line, exactly as it did before the act existed.
		_start_battle()
		return
	var items: Array = da.get("items", [])
	_provision_total = items.size()
	for it in items:
		var at: Array = it.get("at", [0, 0])
		region.spawn_pickup(str(it.get("id", "prov")), "provision",
			str(it.get("sprite", "jar")), int(at[0]), int(at[1]))
	region.set_paused(true)
	region.dialogue.show_lines(da.get("lines", []), _errand_speaker, func():
		region.set_paused(false))


func _start_battle() -> void:
	act = Act.FIGHT
	# The nameplate is the whole promise of this chapter: for the length of the
	# fight the hands on the sling are David's (docs/FEEL.md §3).
	hud.set_role(I18n.t({"en": "David", "zh": "大卫"}), 1)
	hud.set_objective(I18n.t({
		"en": "Answer him with what you carry. Then throw.",
		"zh": "用你带着的经文回答他。然后，放手。"}))
	battle = WordBattle.new()
	add_child(battle)
	battle.setup(region)
	battle.on_win = _on_win
	battle.start()


func _on_win() -> void:
	become.end("david", _after_return)


func _after_return() -> void:
	if battle:
		battle.queue_free()
		battle = null
	_in_battle = false
	# the valley is quiet: he will not shout again
	GameState.set_flag("goliath_down", true)
	GameState.grant_relic("stones")
	GameState.complete_chapter("elah")
	GameState.add_xp(120)
	GameState.gather_fruit("faithfulness")
	EventBus.toast_requested.emit(I18n.t({
		"en": "Five smooth stones, kept", "zh": "五块光滑的石子，收下了"}))
	# The chapter has an ENDING, and it is played, not implied. This used to drop
	# the player back into a silent valley the instant the giant fell — the
	# "suddenly nothing to do" of playtest 6, on a screen with no words on it.
	hud.set_role(I18n.t({"en": "pilgrim", "zh": "朝圣者"}),
		int(GameState.data.get("level", 1)))
	_play_ending()


# ── chapter ending ────────────────────────────────────────────────────────
func _play_ending() -> void:
	var e: Dictionary = region.model.ending
	var lines: Array = e.get("lines", [])
	if lines.is_empty():
		_end_and_free_roam()
		return
	region.set_paused(true)
	region.dialogue.show_lines(lines, func(_w): return {}, _ending_ask)


func _ending_ask() -> void:
	var e: Dictionary = region.model.ending
	var ask: Dictionary = e.get("ask", {})
	var raw: Array = e.get("options", [])
	if raw.is_empty():
		_end_and_free_roam()
		return
	var options: Array = []
	for o in raw:
		options.append({"t": o.get("t", {})})
	# The question goes first, as its own line, so the three ways forward are not
	# read as a menu of nothing.
	region.dialogue.show_lines([{"who": "", "text": ask}], func(_w): return {},
		func(): region.dialogue.show_choices_standalone(options, _ending_pick))


func _ending_pick(idx: int, _opt: Dictionary) -> void:
	var raw: Array = region.model.ending.get("options", [])
	if idx >= 0 and idx < raw.size():
		var ins: Dictionary = raw[idx].get("insight", {})
		region.dialogue.show_lines([{"who": "", "text": ins}], func(_w): return {},
			_end_and_free_roam)
	else:
		_end_and_free_roam()


func _end_and_free_roam() -> void:
	act = Act.DONE
	# walk back down past the re-arm row, not just past the line: the trigger
	# stays disarmed inside the dead band (see Region._check_triggers), and a
	# return that lands inside it would leave the line permanently silent.
	region.set_paused(false)
	region.player.external_intent = Vector2.ZERO
	region.player.velocity = Vector2.ZERO
	region.player.global_position = Vector2(16 * 16 + 8, 14 * 16)
	hud.set_objective(I18n.t(region.model.objectives.get("done", {})))
