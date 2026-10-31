extends Node2D
## Main — boots the world and wires the loop.
##
## Overworld → talk / gather / cross the line → BECOME → the fight → RETURN.
## Story logic stays in data; Main only routes the moments between systems.

var region: Region = null
var hud: Hud = null
var touch: TouchControls = null
var become: BecomeController = null
var fight: GoliathFight = null

var stones := 0
var _stones_total := 0
var _refusals := 0
var _in_battle := false
## Act I you are the witness; Act II you are David, and the story rewinds to his
## father's errand before it lets you fight. Playtest 7 asked for exactly this:
## "being told by father to send provision, collect provision, then walk walk
## then go to the place then properly then talk.. then fight goliath".
## Act I is the witness's: the valley, the forty days, the people who live
## beside the line. Act II is David's, and it runs in the order 1 Samuel 17
## gives it — the sheep, the father's errand, the brothers, the king, and only
## then five stones out of the brook (v.40) and the line.
enum Act { WITNESS, SHEPHERD, ERRAND, SAUL, STONES, READY, FIGHT, AFTERMATH, DONE }
var act: int = Act.WITNESS
var provisions := 0
var practice: SlingPractice = null
var fade: ScreenFade = null
var journal: Journal = null
var card: PlaceCard = null
var _brothers_met := false
var _provision_total := 3
## Seconds the world has been paused with nothing on screen able to end it. This
## is the belt to the dialogue box's braces: a beat that pauses the valley and
## then fails to open (or to close) its own box used to leave the player standing
## in a frozen world with no key that did anything (playtest 5).
var _dead_pause := 0.0
const DEAD_PAUSE_SECS := 6.0
## Autosave. Wall-clock, not delta: the tests run at 24x and a delta-based
## timer would write the save file eight times a second.
var _save_due := 0
var _saved_act := ""
const SAVE_EVERY_MS := 3000

## The act as a word, for the smoke test and for anything that needs to print
## where the chapter is. An enum's integer value is an implementation detail;
## "shepherd" is not.
const ACT_NAMES := ["witness", "shepherd", "errand", "saul", "stones", "ready",
	"fight", "aftermath", "done"]


func act_id() -> String:
	return str(ACT_NAMES[clampi(act, 0, ACT_NAMES.size() - 1)])


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

	fade = ScreenFade.new()
	add_child(fade)
	fade.open_up(0.7)

	journal = Journal.new()
	add_child(journal)
	journal.closed.connect(_close_journal)

	hud = Hud.new()
	add_child(hud)
	hud.journal_requested.connect(_open_journal)

	card = PlaceCard.new()
	add_child(card)

	touch = TouchControls.new()
	add_child(touch)

	# Receiving a verse is the one reward the game never announced: the HUD's ☆
	# ticked up and nothing else. A player who never noticed the counter has no
	# reason to think the people they meet are worth meeting.
	EventBus.verse_received.connect(_on_verse)
	EventBus.player_interacted_with.connect(_on_interacted)

	region = Region.new()
	# Which story this is comes from the registry, not from a line of code.
	region.region_id = CampaignModel.current_region()
	region.region_ready.connect(_on_region_ready)
	region.pickup_taken.connect(_on_pickup)
	region.trigger_fired.connect(_on_trigger)
	region.curio_seen.connect(_on_curio)
	add_child(region)


func _process(delta: float) -> void:
	if region == null or region.dialogue == null:
		return
	var stuck: bool = region.is_paused() and not region.dialogue.is_open() \
		and not _in_battle and fight == null and practice == null \
		and not (journal != null and journal.is_open())
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
	_update_touch_ownership()
	_autosave()


## Who owns the screen right now. One derived truth, recomputed every frame,
## rather than a signal wired from each place that can take the picture — that
## way a path that forgets to restore it cannot leave the stick dead.
func _update_touch_ownership() -> void:
	if touch == null or region == null:
		return
	var owned := region.is_paused() or fight != null or practice != null \
		or (journal != null and journal.is_open())
	touch.set_blocked(owned)


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
		Act.SHEPHERD:
			key = "shepherd"
		Act.SAUL:
			key = "saul"
			var king := _npc("saul")
			if king != null:
				target = king.global_position
				point = true
		Act.STONES:
			key = "stones"
			target = _nearest_pickup("stone", p.global_position)
			point = stones < _stones_total
			line = "%s  %d／%d" % [I18n.t(obj.get(key, {})), stones, _stones_total]
		Act.READY:
			key = "ready"
			var rrow := int(region.model.trigger_data("challenge").get("row", 11))
			target = Vector2(p.global_position.x, float(rrow * 16))
			point = true
		Act.AFTERMATH:
			var co := _npc("corin")
			key = "aftermath"
			if co != null:
				target = co.global_position
				point = true
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
				# While he is walking, the arrow points at HIM — the objective
				# says "follow Corin", so the arrow had better mean Corin. Once
				# he has arrived and is waiting, it points at the person he
				# brought you to.
				target = corin.global_position if corin.is_leading() else nxt.global_position
				point = true
				line = I18n.t(obj.get(key, {})) % nxt.display_name()
				if corin.lead_target != nxt:
					corin.lead_to(nxt, func(): _lead_arrived())
			elif GameState.flag("elah_saw_him") != true:
				key = "firstsight"
				var g: Vector2i = region.model.goliath
				target = Vector2(float(g.x) * 16.0 + 8.0, float(g.y) * 16.0 + 18.0)
				point = true
			elif not bool(GameState.flag("goliath_down")):
				key = "line_witness"
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
	var near := region.nearest_interactable()
	if near != null and near.can_talk():
		hud.set_prompt(I18n.t({"en": "A  ·  talk", "zh": "A  ·  交谈"}))
	else:
		hud.set_prompt("")


## Save the chapter where it stands. Written whenever the act changes (that is
## a story beat, and a story beat is the worst thing to lose) and every few
## seconds while the player is free to walk, so a tab closed mid-valley comes
## back to the same valley.
func _autosave() -> void:
	if region == null or region.player == null or region.model == null:
		return
	if region.dialogue != null and region.dialogue.is_open():
		return
	if fight != null or practice != null or _in_battle:
		return
	if journal != null and journal.is_open():
		return
	var now := Time.get_ticks_msec()
	if act_id() == _saved_act and now < _save_due:
		return
	_save_due = now + SAVE_EVERY_MS
	_saved_act = act_id()
	_save_progress()


func _save_progress() -> void:
	var t := _tile_of(region.player.global_position)
	GameState.data["pos"] = [t.x, t.y]
	GameState.data["progress"] = {
		"act": act_id(),
		"stones": stones,
		"provisions": provisions,
		"brothers": _brothers_met,
		"pos": [t.x, t.y],
	}
	GameState.save_game()


func _tile_of(pos: Vector2) -> Vector2i:
	return Vector2i(int(floorf(pos.x / 16.0)), int(floorf(pos.y / 16.0)))


## Names for the people who only exist inside the errand. They come from the
## same data as their words, so a translator never has to open a script.
func _speaker(who: String) -> Dictionary:
	if who == "":
		return {}
	var table: Dictionary = region.model.david_act.get("speakers", {})
	var nm: Dictionary = table.get(who, {})
	if nm.is_empty():
		return {}
	return {"name": I18n.t(nm), "actor": str(nm.get("actor", who))}


## The brothers see him arrive with bread and want him gone. This is the last
## beat before the fight and it is straight out of 1 Samuel 17:28.
func _brothers_beat() -> void:
	if _brothers_met:
		return
	_brothers_met = true
	region.set_paused(true)
	var lines: Array = region.model.david_act.get("brothers", [])
	region.dialogue.show_lines(lines, _speaker, _summon_saul)


## 1 Samuel 17:31-39: they bring him to Saul, who is a person in a tent you have
## to walk to, not a card that appears. His lines are the chapter's own data.
func _summon_saul() -> void:
	act = Act.SAUL
	region.set_paused(false)
	if _npc("saul") != null:
		return
	_spawn_saul()
	EventBus.toast_requested.emit(I18n.t({
		"en": "The king's tent is east of the brothers' post.",
		"zh": "王的帐棚在哥哥们那边往东。"}))


## The king is not standing in the camp when the chapter opens: he is summoned
## by 17:31, and a resumed save has to put him back on the map.
func _spawn_saul() -> void:
	var sd: Dictionary = region.model.david_act.get("saul", {})
	var sp: Dictionary = region.model.david_act.get("speakers", {})
	var king: Dictionary = sp.get("saul", {})
	var dave: Dictionary = sp.get("david", {})
	var d := {
		"id": "saul",
		"name": {"en": str(king.get("en", "Saul")), "zh": str(king.get("zh", "扫罗"))},
		"actor": str(king.get("actor", "king")),
		"at": sd.get("at", [21, 41]),
		"lines": sd.get("lines", []),
		"cast": {"david": {
			"name": {"en": str(dave.get("en", "David")), "zh": str(dave.get("zh", "大卫"))},
			"actor": str(dave.get("actor", "david"))}},
	}
	region.spawn_npc(d)


## 1 Samuel 17:39-40. He takes the king's armour off, and the next thing he
## picks up is not a sword: it is five stones out of the brook. That verse is
## the whole point of the chapter, so it is played here — as the reason the
## stones appear on the map — instead of being handed to the witness before he
## ever became David.
func _brook_beat() -> void:
	if act == Act.STONES or act == Act.READY:
		return
	act = Act.STONES
	var br: Dictionary = region.model.david_act.get("brook", {})
	var lines: Array = br.get("lines", [])
	if lines.is_empty():
		_start_brook()
		return
	region.set_paused(true)
	region.dialogue.show_lines(lines, _speaker, _start_brook)


## Put the five stones in the shallow water, where the player can see them.
func _start_brook() -> void:
	act = Act.STONES
	region.set_paused(false)
	var br: Dictionary = region.model.david_act.get("brook", {})
	var items: Array = br.get("items", [])
	_stones_total = items.size()
	stones = 0
	for it in items:
		var at: Array = it.get("at", [0, 0])
		region.spawn_pickup(str(it.get("id", "stone")), "stone",
			str(it.get("sprite", "rock")), int(at[0]), int(at[1]), it)
	if hud != null:
		hud.set_stones(0, _stones_total)
	EventBus.toast_requested.emit(I18n.t({
		"en": "The brook is north-west, below the tents.",
		"zh": "溪水在西北边，帐棚下面。"}))


func _ready_for_the_line() -> void:
	act = Act.READY
	region.set_paused(false)
	hud.set_objective(I18n.t(region.model.objectives.get("ready", {})))
	EventBus.toast_requested.emit(I18n.t({
		"en": "The line is north. They have stopped shouting.",
		"zh": "界线在北边。他们不喊了。"}))


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
	# The five stones are laid out in the brook when David walks down to it
	# (1 Samuel 17:40), not at load: the HUD's pouch counter must not be on
	# screen while the witness is still watching the valley.
	var brook: Dictionary = region.model.david_act.get("brook", {})
	_stones_total = int((brook.get("items", []) as Array).size())
	hud.set_stones(0, 0)
	AudioDirector.play_music(region.model.music)
	EventBus.player_entered_region.emit(region.region_id)
	_resume_story()
	_prologue_once()


## A saved valley has to boot into the chapter it left. Reloading after the win
## used to drop you back into Act.WITNESS with the giant already dead, the line
## triggering `_memory_beat()` and Corin's ending unreachable — the one way a
## player could lose a finished chapter by refreshing the page.
func _resume_story() -> void:
	var pr: Dictionary = GameState.data.get("progress", {})
	# The giant is down. If the ending never played, Corin still owes it to you.
	if bool(GameState.flag("goliath_down")):
		act = Act.DONE if bool(GameState.flag("elah_ended")) else Act.AFTERMATH
		if act == Act.AFTERMATH:
			_restore_pos(pr)
		return
	var was := str(pr.get("act", "witness"))
	if was == "" or was == "witness" or was == "done":
		# Act I replays from the valley's own flags: the prologue, the briefing
		# and the card each fire once and are remembered by the save.
		return
	# A resumed save is honest about what it can restore: the chapter, not the
	# frame. The act's opening beat plays again — the drill, the errand, the
	# brook — rather than dropping the player into the middle of a scene whose
	# first half never happened on this screen.
	stones = int(pr.get("stones", 0))
	provisions = int(pr.get("provisions", 0))
	_brothers_met = bool(pr.get("brothers", false))
	_restore_pos(pr)
	match was:
		"shepherd":
			_start_david_act()
		"errand":
			_start_errand()
		"saul", "stones", "ready":
			_resume_david_late(was)
		"fight", "aftermath":
			_resume_david_late("ready")


func _restore_pos(pr: Dictionary) -> void:
	var pos: Array = pr.get("pos", [])
	if pos.size() == 2:
		_place_at(pos)


## The second half of David's act, put back together: the king's tent, the
## brook, and however many stones of the five the save had already gathered.
func _resume_david_late(was: String) -> void:
	act = Act.SAUL
	if _npc("saul") == null:
		_spawn_saul()
	if hud != null:
		hud.set_role(I18n.t(CampaignModel.current_hero_name()), 1)
	if was == "ready" or (stones > 0 and stones >= _stones_total):
		_ready_for_the_line()
		return
	# `saul` and `stones` both continue at the brook's opening: 17:40 is the
	# verse that puts the stones on the map, and it is cheap to hear again.
	_brook_beat()


## Chapter 1. The witness is not from here, and saying so once, at the top, in
## their own century, is the difference between a setting and a story. Then the
## valley explains itself (the briefing).
func _prologue_once() -> void:
	if GameState.flag(str(region.region_id) + "_opened") == true:
		_brief_once()
		return
	if region.model.prologue.is_empty():
		_brief_once()
		return
	GameState.set_flag(str(region.region_id) + "_opened", true)
	region.set_paused(true)
	region.dialogue.show_lines(region.model.prologue, func(_w): return {}, func():
		_brief_once())


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
		region.set_paused(false)
		_card_once())


## The caption. Once per region, after the valley has explained itself, so it
## lands on a player who already knows what they are looking at.
func _card_once() -> void:
	if GameState.flag(str(region.region_id) + "_card") == true:
		return
	GameState.set_flag(str(region.region_id) + "_card", true)
	card.show_card(region.model.display_name, region.model.display_sub)


func _on_verse(_id: String, ref: String) -> void:
	GameState.grant_seal("first_verse")
	EventBus.toast_requested.emit(I18n.t({
		"en": "A verse to carry · %s", "zh": "记住了一句经文 · %s"}) % ref)


func _on_pickup(id: String) -> void:
	if id.begins_with("prov"):
		provisions += 1
		EventBus.toast_requested.emit(I18n.t({
			"en": "Your father's errand · %d/%d", "zh": "父亲的托付 · %d／%d"})
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
		if stones >= _stones_total and _stones_total > 0:
			GameState.grant_seal("five_stones")
			_stones_chosen()


## The fifth stone closes the brook scene and puts the objective back on the
## line. This is the one place the chapter turns around: from here David walks
## up, and nothing else in the valley is asked of him.
func _stones_chosen() -> void:
	var br: Dictionary = region.model.david_act.get("brook", {})
	var lines: Array = br.get("done_lines", [])
	region.set_paused(true)
	region.dialogue.show_lines(lines, _speaker, _ready_for_the_line)


func _on_trigger(id: String) -> void:
	if id == "firstsight":
		_first_sight()
		return
	if id != "challenge" or _in_battle:
		return
	if act == Act.READY:
		# You crossed that line once as a witness and were told it was not your
		# fight. Now you cross it as the boy who said it was not his either.
		_start_battle()
		return
	if act == Act.STONES:
		# A silent nothing at the most important line in the chapter reads as a
		# broken game. He is not ready, and the valley says so.
		EventBus.toast_requested.emit(I18n.t({
			"en": "Not with an empty pouch. Five stones, down at the brook.",
			"zh": "空着手不行。五块石子，在下面的溪边。"}))
		return
	if act != Act.WITNESS and act != Act.DONE:
		return
	if bool(GameState.flag("goliath_down")):
		_memory_beat()
		return
	# Act I ends at this line. The witness is not turned back because he is
	# carrying the wrong number of stones — he is turned back because he does
	# not yet know what he is watching. Four people in the camp can tell him.
	if int(GameState.data["words"].size()) >= 4:
		_witness_at_the_line()
	else:
		_refuse(id)


## The shot the chapter has been promising: the witness walks up the ridge and
## finally sees the man everybody has been talking about. The camera holds him
## for the duration of the beat and then hands itself back — the same "scripted
## shot, then play" grammar every later scene uses, built once and reusable.
func _first_sight() -> void:
	if GameState.flag("elah_saw_him") == true:
		return
	if _in_battle or (region.dialogue != null and region.dialogue.is_open()):
		return
	GameState.set_flag("elah_saw_him", true)
	var lines: Array = _beat_lines("firstsight", "firstsight")
	if lines.is_empty():
		return
	region.set_paused(true)
	var g: Vector2i = region.model.goliath
	region.pan_to(Vector2(float(g.x) * 16.0 + 8.0, float(g.y) * 16.0 + 18.0), 0.9)
	region.dialogue.show_lines(lines, _speaker, func():
		region.follow_player(0.7)
		region.set_paused(false))


## The witness's last beat in the valley: he crosses the line, and nothing
## happens to him — the fight is not his. The story then hands him over to the
## boy who is actually walking down the ridge with bread in his hands.
func _witness_at_the_line() -> void:
	if _in_battle:
		return
	_in_battle = true
	region.set_paused(true)
	var lines: Array = _beat_lines("challenge", "witness")
	if lines.is_empty():
		_begin_become()
		return
	region.dialogue.show_lines(lines, _speaker, _begin_become)


func _beat_lines(id: String, key: String) -> Array:
	## Story beats live in the region file, never in here.
	var td := region.model.trigger_data(id)
	var lines: Array = td.get(key, [])
	return lines


## Act I has no fail state, only a line you are not ready for. The witness is
## stepped back south of the trigger so the walk can be tried again, and the
## objective stays on whoever has not spoken to him yet.
##
## The pushback is anchored to the challenge row rather than to whatever pixel
## the player was standing on: hold up, get pushed back, walk straight back in,
## forever was a playtest-4 defect.
func _refuse(id: String) -> void:
	_refusals += 1
	region.set_paused(true)
	var lines: Array = [{
		"who": "",
		"text": {
			"en": "You reach the line. Behind you, an army is standing very still, and you still do not know why.",
			"zh": "你走到界线前。身后一支军队站着一动不动，而你仍然不知道是为了什么。"
		}
	}]
	lines.append_array(_beat_lines(id, "refuse"))
	region.dialogue.show_lines(lines, _speaker, func():
		region.set_paused(false)
		region.player.external_intent = Vector2.ZERO
		region.player.velocity = Vector2.ZERO
		var row := int(region.model.trigger_data(id).get("row", 11))
		region.player.global_position = Vector2(
			region.player.global_position.x, float((row + 3) * 16))
		if _refusals >= 2:
			var nxt: Npc = _next_unspoken()
			if nxt != null:
				EventBus.toast_requested.emit(I18n.t({
					"en": "%s has not spoken to you yet." % nxt.display_name(),
					"zh": "%s还没和你说过话。" % nxt.display_name()}))
			else:
				EventBus.toast_requested.emit(I18n.t({
					"en": "Go back to the camp. Look at the tents, the bread, the men.",
					"zh": "回营地去。看看那些帐棚、那些饼、那些人。"})))


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
	become.begin(CampaignModel.current_hero(), CampaignModel.current_hero_plate(),
		_start_david_act)


## Act II opens three days earlier, on the slope where David kept his father's
## sheep. The drill is here for one reason: the fight asks exactly one input in
## its aim phase, and nothing in the game taught it before the giant was already
## standing in front of you (playtest 8: "throw stone to attack goliath").
func _start_david_act() -> void:
	# `_in_battle` guarded the line while BECOME played. From here the act
	# itself guards it (SHEPHERD/ERRAND/SAUL ignore the line, READY answers it),
	# so leaving the flag set made the one crossing that matters — the one that
	# starts the fight — the one crossing `_on_trigger` refused.
	_in_battle = false
	hud.set_role(I18n.t(CampaignModel.current_hero_name()), 1)
	var da: Dictionary = region.model.david_act
	if da.is_empty():
		# A region may not have the act at all: then becoming David goes straight
		# to the line, exactly as it did before any of this existed.
		_start_battle()
		return
	act = Act.SHEPHERD
	var sh: Dictionary = da.get("shepherd", {})
	var st: Array = sh.get("start_at", [])
	region.set_paused(true)
	# A cut, not a jump: black, the slope, then the words.
	fade.run(0.45, func(): _place_at(st), 0.35, func():
		region.dialogue.show_lines(sh.get("lines", []), _speaker, _start_practice))


## Put the player on a tile and take the camera with them, with no glide.
## A place that says one thing when you stand in it. Optional by construction:
## no marker, no reward, nothing in the journal, and it never blocks a walk.
func _on_curio(_id: String, lines: Array) -> void:
	if lines.is_empty() or _in_battle or fight != null or practice != null:
		return
	if region.dialogue != null and region.dialogue.is_open():
		return
	region.set_paused(true)
	region.dialogue.show_lines(lines, func(_w): return {}, func():
		region.set_paused(false))


## ── the book ────────────────────────────────────────────────────────────
## One screen for the three things a player asks while walking: what am I
## doing, what am I carrying, and what have I done.
func _open_journal() -> void:
	if journal == null or journal.is_open() or region == null:
		return
	if region.dialogue != null and region.dialogue.is_open():
		return
	if _in_battle or fight != null or practice != null:
		return
	var refs: Array = []
	for id in (GameState.data.get("words", []) as Array):
		for w in region.model.words:
			if str(w.get("id", "")) == str(id):
				refs.append(str(w.get("ref", "")))
				break
	var titles := {}
	var seals: Array = GameState.data.get("seals", [])
	for sid in seals:
		titles[str(sid)] = GameState.seal_title(str(sid))
	var c: Dictionary = CampaignModel.current()
	region.set_paused(true)
	journal.open_panel(I18n.t(c.get("title", {})), hud.objective_lbl.text, refs,
		stones, _stones_total, seals, titles)


func _close_journal() -> void:
	if region != null:
		region.set_paused(false)


func _place_at(tile: Array) -> void:
	if tile.size() != 2 or region.player == null:
		return
	region.player.global_position = Vector2(float(tile[0]) * 16.0 + 8.0,
		float(tile[1]) * 16.0 + 8.0)
	region.snap_camera()


## The drill. Three jars, the same sweeping marker the fight uses, no penalty
## for missing — the band narrows instead, so the third throw is nearly the
## fight's timing.
func _start_practice() -> void:
	var sh: Dictionary = region.model.david_act.get("shepherd", {})
	practice = SlingPractice.new()
	add_child(practice)
	practice.finished.connect(func():
		if practice != null:
			practice.queue_free()
			practice = null
		_practice_done())
	practice.start(int(sh.get("targets", 3)))


func _practice_done() -> void:
	GameState.grant_seal("the_drill")
	region.set_paused(true)
	var sh: Dictionary = region.model.david_act.get("shepherd", {})
	region.dialogue.show_lines(sh.get("done_lines", []), _speaker, _start_errand)


## Jesse's errand: the provisions, the walk, the brothers who do not want him
## there. Without this beat the stones and the fight arrive with no story under
## them (1 Samuel 17:17-28).
func _start_errand() -> void:
	act = Act.ERRAND
	provisions = 0
	_brothers_met = false
	var da: Dictionary = region.model.david_act
	var items: Array = da.get("items", [])
	_provision_total = items.size()
	# Stand him where the errand happens, with the camera already there: the
	# provisions are small props, and making the player walk 35 tiles to find
	# them was reported as "the quest item cannot be seen on the map".
	var st: Array = da.get("start_at", [])
	region.set_paused(true)
	fade.run(0.45, func():
		_place_at(st)
		for it in items:
			var at: Array = it.get("at", [0, 0])
			region.spawn_pickup(str(it.get("id", "prov")), "provision",
				str(it.get("sprite", "jar")), int(at[0]), int(at[1]))
		, 0.35, func():
			region.dialogue.show_lines(da.get("lines", []), _speaker, func():
				region.set_paused(false)))


## Chapter 5: the fight. Not a quiz about the fight — a sling, five stones, and
## a giant who swings a spear at you.
##
## The verses still matter, and they are still the point: they are what the
## valley gave you, they sit in the book, and they open and close the scene. What
## changed is that the player now has to THROW and DODGE to finish the chapter,
## instead of picking the right sentence from four options.
func _start_battle() -> void:
	act = Act.FIGHT
	_in_battle = true
	region.set_paused(true)
	# The nameplate is the whole promise of this chapter: for the length of the
	# fight the hands on the sling are David's (docs/FEEL.md §3).
	hud.set_role(I18n.t(CampaignModel.current_hero_name()), 1)
	hud.set_objective(I18n.t(region.model.objectives.get("fight", {})))
	AudioDirector.play_sfx("sling", -6.0)
	var da: Dictionary = region.model.david_act
	var intro: Array = da.get("battle_intro", [])
	if intro.is_empty():
		_open_fight()
		return
	# 1 Samuel 17:44-45 spoken at the line, verbatim, then the sling comes out.
	region.dialogue.show_lines(intro, _speaker, _open_fight)


func _open_fight() -> void:
	GameState.grant_seal("the_argument")
	GameState.record_way("stand")
	# A cut, not a pop. The words end, the valley goes dark for a heartbeat, and
	# the light comes back on the ground where the duel is fought — the same
	# grammar as every other scene change in the chapter (docs/RESET-REPORT.md
	# Phase 6: no abrupt swaps).
	fade.run(0.28, _spawn_fight, 0.30)


func _spawn_fight() -> void:
	fight = GoliathFight.new()
	add_child(fight)
	fight.finished.connect(_on_win)
	fight.start()


## He is down. The valley reacts before you do — 1 Samuel 17:47 is the line the
## chapter closes on, and it is spoken here, over the dust, while you are still
## David.
func _on_win() -> void:
	# The duel stays on screen. `finished` fires after the giant has actually
	# fallen, and the fight's layer sits under the dialogue box, so 1 Samuel
	# 17:47 is spoken over him instead of over a valley the duel has already
	# vanished from.
	region.set_paused(true)
	var da: Dictionary = region.model.david_act
	var victory: Array = da.get("victory", [])
	if victory.is_empty():
		_dismiss_fight()
		become.end("david", _after_return)
		return
	AudioDirector.play_sfx("hit", -2.0)
	region.dialogue.show_lines(victory, _speaker, func():
		_dismiss_fight()
		become.end("david", _after_return))


func _dismiss_fight() -> void:
	if fight != null:
		fight.queue_free()
		fight = null


func _after_return() -> void:
	if fight:
		fight.queue_free()
		fight = null
	_in_battle = false
	# the valley is quiet: he will not shout again
	GameState.set_flag("goliath_down", true)
	GameState.grant_seal("giant_down")
	GameState.grant_seal("chapter_one")
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
	# Chapter 6 is witnessed, not narrated: the army's reaction is a person you
	# can still walk up to. Corin's `after_win` lines are the aftermath; the
	# ending card follows them.
	if _npc("corin") != null:
		act = Act.AFTERMATH
		hud.set_objective(I18n.t(region.model.objectives.get("aftermath", {})))
	else:
		act = Act.DONE
		_play_ending()


## Corin is the one who has to hear it. When he finishes his lines the chapter
## closes — the same ending card either way, but now it comes after a person.
func _on_interacted(id: String, _kind: String) -> void:
	if act == Act.SAUL and id == "saul":
		_brook_beat()
		return
	if act != Act.AFTERMATH or id != "corin":
		return
	act = Act.DONE
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
	GameState.set_flag("elah_ended", true)
	# walk back down past the re-arm row, not just past the line: the trigger
	# stays disarmed inside the dead band (see Region._check_triggers), and a
	# return that lands inside it would leave the line permanently silent.
	region.set_paused(false)
	region.player.external_intent = Vector2.ZERO
	region.player.velocity = Vector2.ZERO
	region.player.global_position = Vector2(16 * 16 + 8, 14 * 16)
	hud.set_objective(I18n.t(region.model.objectives.get("done", {})))
