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
var _refusals := 0
var _in_battle := false


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

	region = Region.new()
	region.region_id = "elah"
	region.region_ready.connect(_on_region_ready)
	region.pickup_taken.connect(_on_pickup)
	region.trigger_fired.connect(_on_trigger)
	add_child(region)


func _on_region_ready() -> void:
	touch.bind(region.player)
	hud.bind(region)
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


func _on_pickup(id: String) -> void:
	if id.begins_with("stone"):
		stones += 1
		GameState.record_way("notice")
		EventBus.toast_requested.emit(I18n.t({
			"en": "A smooth stone · %d/5" % stones,
			"zh": "一块光滑的石子 · %d／5" % stones}))
		AudioDirector.play_sfx("pickup", -4.0)


func _on_trigger(id: String) -> void:
	if id != "challenge" or _in_battle:
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
	become.begin("david", {"en": "DAVID", "zh": "大卫"}, _start_battle)


func _start_battle() -> void:
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
	region.set_paused(false)
	# the valley is quiet: he will not shout again
	GameState.set_flag("goliath_down", true)
	GameState.grant_relic("stones")
	GameState.complete_chapter("elah")
	GameState.add_xp(120)
	GameState.gather_fruit("faithfulness")
	EventBus.toast_requested.emit(I18n.t({
		"en": "Five smooth stones, kept", "zh": "五块光滑的石子，收下了"}))
	# walk back down past the re-arm row, not just past the line: the trigger
	# stays disarmed inside the dead band (see Region._check_triggers), and a
	# return that lands inside it would leave the line permanently silent.
	region.player.global_position = Vector2(16 * 16 + 8, 14 * 16)
