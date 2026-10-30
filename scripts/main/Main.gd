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
var _in_battle := false


func _ready() -> void:
	region = Region.new()
	region.region_id = "elah"
	add_child(region)
	region.region_ready.connect(_on_region_ready)

	become = BecomeController.new()
	add_child(become)

	hud = Hud.new()
	add_child(hud)

	touch = TouchControls.new()
	add_child(touch)

	region.pickup_taken.connect(_on_pickup)
	region.trigger_fired.connect(_on_trigger)


func _on_region_ready() -> void:
	touch.bind(region.player)
	hud.bind(region)
	AudioDirector.play_music(region.model.music)
	EventBus.player_entered_region.emit(region.region_id)


func _on_pickup(id: String) -> void:
	if id.begins_with("stone"):
		stones += 1
		GameState.record_way("notice")
		EventBus.toast_requested.emit(I18n.t({
			"en": "A smooth stone · %d/5" % stones,
			"zh": "一块光滑的石子 · %d/5" % stones}))
		AudioDirector.play_sfx("pickup", -4.0)


func _on_trigger(id: String) -> void:
	if id != "challenge" or _in_battle:
		return
	if stones >= 5:
		_begin_become()
	else:
		# No fail state: he simply will not let you past without them.
		region.set_paused(true)
		region.dialogue.show_lines([
			{"who": "", "text": {"en": "You reach the line, and your hand closes on an empty pouch. Five stones. The brook is behind you.",
				"zh": "你走到界线前，手在袋子里摸了个空。要五块石子。溪水在你身后。"}},
		], func(_w): return {}, func():
			region.set_paused(false)
			region.player.global_position.y += 16.0 * 3)


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
	# walk back down to the exact stone you were standing on
	region.player.global_position = Vector2(16 * 16 + 8, 13 * 16)
