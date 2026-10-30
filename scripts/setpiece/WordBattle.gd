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

var region: Region = null
var hand: Array = []            # word dicts you actually carry
var shout: Dictionary = {}
var pips := PIPS
var hearts := HEARTS
var _round := 0

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
	EventBus.become_active.emit("david")
	region.dialogue.show_lines([
		{"who": "", "text": {"en": "The rough of the cord is in your hand, and it is not your hand. For the length of this fight the name above you is not yours.",
			"zh": "绳子粗粝，握在手里，可那不是你的手。这一场打完以前，你头上的名字不是你的。"}},
		{"who": "goliath", "text": {"en": "He plants the butt of his spear in the dust and waits for you to be afraid first.",
			"zh": "他把枪杆的末端插进土里，等你先害怕。"}},
	], _speaker, _next_round)


# ── round loop ──────────────────────────────────────────────────────────
func _next_round() -> void:
	_round += 1
	shout = _pick_shout()
	_lines([
		{"who": "goliath", "text": shout["line"]},
		{"who": "", "text": shout["tell"]},
	])


func _pick_shout() -> Dictionary:
	# Only shout something you can actually answer. A taunt with no matching
	# verse in your hand would be an unwinnable round, and this game does not
	# do unwinnable.
	var kinds := []
	for w in hand:
		kinds.append(w.get("kind"))
	var pool := []
	for s in region.model.shouts:
		if s.get("kind") in kinds:
			pool.append(s)
	if pool.is_empty():
		pool = region.model.shouts
	return pool[_round % pool.size()]


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
		_win()
		return
	region.dialogue.show_lines([
		{"who": "", "text": {"en": "You answer him with his own kind of shout, and something in him steps back. The sling takes a stone. %d of his bluster left." % pips,
			"zh": "你把他那种口气原样还了回去，他退了半步。石子扣进皮兜。他的气焰还剩 %d 分。" % pips}},
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
				"zh": "错的话出了口，整条山谷都听见。你的手在抖。于是你停下来，呼吸，让绳子松着，直到心跳重新只是你自己的。"}},
			{"who": "", "text": {"en": "Nerve returns, one breath at a time.", "zh": "胆气一口一口回来了。"}},
		], _speaker, _next_round)
		return
	region.dialogue.show_lines([
		{"who": "", "text": {"en": "That was not the shout he made. The cord bites your palm. Nerve %d of %d." % [hearts, HEARTS],
			"zh": "他喊的不是这一句。绳子勒进掌心。胆气还剩 %d／%d。" % [hearts, HEARTS]}},
	], _speaker, _next_round)


func _win() -> void:
	region.dialogue.show_lines([
		{"who": "", "text": {"en": "The fifth answer leaves you and the stone is already gone. The valley goes very quiet, in the way a room goes quiet when the largest thing in it falls.",
			"zh": "第五句答完，石子已经出手。山谷静了下来——像一个房间里最大的东西倒下时，那种静。"}},
		{"who": "goliath", "text": {"en": "…", "zh": "……"}},
		{"who": "", "text": {"en": "1 Samuel 17:47 — “And all this assembly shall know that the LORD saveth not with sword and spear: for the battle is the LORD’s, and he will give you into our hands.”",
			"zh": "撒母耳记上 17:47 ——「又使这众人知道耶和华使人得胜，不是用刀用枪，因为争战的胜败全在乎耶和华。他必将你们交在我们手里。」"}},
	], _speaker, func():
		if on_win.is_valid():
			on_win.call())
