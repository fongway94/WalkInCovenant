extends Node
class_name WordBattle
## WordBattle — the confrontation at the bottom of the valley. Turn-based, but
## nobody throws a punch.
##
## Goliath presses with a shout. You answer with one of the lines you collected
## on the walk up. Answer the shout he actually made and the sling loads; answer
## wrong and it costs you nerve. Five right answers empty his bluster — and five
## stones are exactly what the brook gave you.
##
## Ported from Covenant's world/battle.js: same rules, same five pips, same
## three hearts, same refusal to let you lose permanently. There is no
## game-over screen in this game (pillar 5); running out of nerve becomes a
## moment to breathe, which is recorded as the "wait" way.
##
## Driven entirely through DialogueBox — no second UI system to maintain.

const PIPS := 5
const HEARTS := 3
## The argument is as long as the verses you actually carry — one exchange per
## verse, two at minimum — and then it stops and the sling comes out. It used to
## be a fixed five rounds regardless, so a player who had spoken to one person
## answered the same single option five times: "i just keep talk with goliath
## with nothing going on" (playtest 6).
const MIN_ROUNDS := 2
const MAX_ROUNDS := 4

var region: Region = null
var hand: Array = []            # word dicts you actually carry
var shout: Dictionary = {}
var pips := PIPS
var hearts := HEARTS
var _round := 0
var _rounds := MIN_ROUNDS
var _queue: Array = []          # shouts still to be answered, no repeats
var fight: GoliathFight = null

var on_win: Callable = Callable()


func setup(r: Region) -> void:
	region = r
	hand = _collect_hand()


func _collect_hand() -> Array:
	var carried: Array = []
	for id in GameState.data.get("words", []):
		for w in region.model.words:
			if w.get("id") == id:
				carried.append(w)
	# Anyone who somehow arrives empty-handed still gets a fair fight.
	if carried.is_empty():
		carried = region.model.words.duplicate(true)
		if carried.size() > 1:
			carried = carried.slice(0, 1)
	return carried


func _speaker(who: String) -> Dictionary:
	if who == "goliath":
		return {"name": I18n.t({"en": "Goliath", "zh": "歌利亚"}), "actor": "goliath"}
	return {"name": "", "actor": ""}


func _lines(arr: Array) -> void:
	region.dialogue.show_lines(arr, _speaker, _after_shout)


func start() -> void:
	pips = PIPS
	hearts = HEARTS
	_round = 0
	_rounds = clampi(hand.size(), MIN_ROUNDS, MAX_ROUNDS)
	_queue = _shout_queue()
	pips = _rounds
	EventBus.become_active.emit("david")
	region.dialogue.show_lines([
		{"who": "", "text": {"en": "The rough of the cord is in your hand, and it is not your hand. For the length of this fight the name above you is not yours.",
			"zh": "绳子在你手里。可那不是你的手。\n\n他靠的是刀、枪、盾牌。你靠的是万军之耶和华的名。"}},
		{"who": "goliath", "text": {"en": "He plants the butt of his spear in the dust and waits for you to be afraid first.",
			"zh": "「我岂是狗呢，你竟拿杖来攻击我？」\n\n他把枪杆插进土里，等你先害怕。"}},
	], _speaker, _next_round)


# ── round loop ──────────────────────────────────────────────────────────
func _next_round() -> void:
	_round += 1
	if _round > _rounds:
		_begin_fight()
		return
	shout = _pick_shout()
	_lines([
		{"who": "goliath", "text": shout["line"]},
		{"who": "", "text": shout["tell"]},
	])


func _shout_queue() -> Array:
	# Only shouts you hold an answer for. An unanswerable taunt would be an
	# unwinnable round, and this game does not do unwinnable.
	var kinds := []
	for w in hand:
		kinds.append(str(w.get("kind", "")))
	var pool := []
	for s in region.model.shouts:
		if str(s.get("kind", "")) in kinds:
			pool.append(s)
	if pool.is_empty():
		pool = region.model.shouts.duplicate()
	pool.shuffle()
	return pool


func _pick_shout() -> Dictionary:
	if _queue.is_empty():
		_queue = _shout_queue()
	return _queue.pop_front()


func _after_shout() -> void:
	var options := []
	for w in hand:
		options.append({"t": w.get("text", {}), "kind": w.get("kind"), "id": w.get("id")})
	region.dialogue.show_choices_standalone(options, _resolve)


func _resolve(idx: int, opt: Dictionary) -> void:
	if opt.get("kind") == shout.get("kind"):
		_correct(opt)
	else:
		_wrong(opt)


func _correct(opt: Dictionary) -> void:
	pips -= 1
	EventBus.way_recorded.emit("step")
	AudioDirector.play_sfx("sling", -4.0)
	if pips <= 0:
		_begin_fight()
		return
	region.dialogue.show_lines([
		{"who": "", "text": {"en": "You answer him with his own kind of shout, and something in him steps back. The sling takes a stone. %d of his bluster left." % pips,
			"zh": "你把这句话还了回去。他退了半步。石子扣进皮兜。他的气焰还剩 %d 分。" % pips}},
	], _speaker, _next_round)


func _wrong(opt: Dictionary) -> void:
	hearts -= 1
	AudioDirector.play_sfx("miss", -6.0)
	if hearts <= 0:
		# No game-over. Running out of nerve becomes a moment to breathe, and
		# breathing is recorded as the "wait" way — the Mirror will notice.
		hearts = 1
		GameState.record_way("wait")
		region.dialogue.show_lines([
			{"who": "", "text": {"en": "The wrong word leaves your mouth and the valley hears it. Your hand shakes. So you stop, and you breathe, and you let the cord go slack until your heartbeat is only yours again.",
				"zh": "说错了。整条山谷都听见了。你的手在抖。\n\n停下来，呼吸。让绳子松着，直到心跳重新是你自己的。"}},
			{"who": "", "text": {"en": "Nerve returns, one breath at a time.", "zh": "胆气一口一口回来了。"}},
		], _speaker, _next_round)
		return
	region.dialogue.show_lines([
		{"who": "", "text": {"en": "That was not the shout he made. The cord bites your palm. Nerve %d of %d." % [hearts, HEARTS],
			"zh": "这句话不对。绳子勒进掌心。胆气还剩 %d／%d。" % [hearts, HEARTS]}},
	], _speaker, _next_round)


## The argument is over; now the throw. This is the beat the whole chapter is
## named after, and it was missing from the game entirely.
func _begin_fight() -> void:
	GameState.grant_seal("the_argument")
	region.dialogue.show_lines([
		{"who": "", "text": {"en": "He has run out of words. So have you.",
			"zh": "他没话说了。你也没有。"}},
		{"who": "", "text": {"en": "His spear comes down off his shoulder. Five smooth stones. One of them goes in the sling.",
			"zh": "他把枪从肩上放下来。你手里有五块光滑的石子。这一块扣进皮兜。"}},
	], _speaker, func():
		fight = GoliathFight.new()
		add_child(fight)
		fight.start()
		fight.finished.connect(func():
			if fight != null:
				fight.queue_free()
				fight = null
			_win()))


func _win() -> void:
	region.dialogue.show_lines([
		{"who": "", "text": {"en": "The fifth answer leaves you and the stone is already gone. The valley goes very quiet, in the way a room goes quiet when the largest thing in it falls.",
			"zh": "石子陷进巨人的额头。\n\n歌利亚脸朝下，扑倒在他骂了四十天的那片尘土里。"}},
		{"who": "goliath", "text": {"en": "…", "zh": "非利士人的阵线一下子散了。以色列全军在同一刻喊了出来。"}},
		{"who": "", "text": {"en": "This was never the story of a boy beating a giant. It is the story of a God who keeps covenant, and a boy who knew the battle was not his.",
			"zh": "这从来不是「小男孩打败大巨人」的故事。\n\n这是一位守约的神，和一个知道这场仗不属于自己的少年。"}},
		{"who": "", "text": {"en": "1 Samuel 17:47 — “And all this assembly shall know that the LORD saveth not with sword and spear: for the battle is the LORD’s, and he will give you into our hands.”",
			"zh": "撒母耳记上 17:47\n「又使这众人知道耶和华使人得胜，不是用刀用枪，因为争战的胜败全在乎耶和华。他必将你们交在我们手里。」"}},
	], _speaker, func():
		if on_win.is_valid():
			on_win.call())
