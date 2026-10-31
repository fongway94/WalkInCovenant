extends Node
class_name MissionRunner
## MissionRunner — the chapter's spine, and the reason `Main.gd` does not have
## to be the chapter.
##
## A mission is DATA (see `missions` in `data/regions/*.json`):
##
##   {
##     "id": "brook_stones",
##     "act": "stones",                       # which guidance branch to use
##     "objective": "stones",                 # a key in the region's objectives
##     "enter": "brook",                      # optional campaign mechanic to run
##     "complete": {"kind": "count", "key": "stones", "at_least": 5},
##     "rewards": {"xp": 0, "seal": "", "relic": "", "fruit": ""},
##     "brief": [ ...lines... ]               # optional, spoken before `enter`
##   }
##
## What the runner owns — the whole lifecycle, in one place:
##
##   briefing → objective activation → tracking → completion → rewards →
##   transition → next mission
##
## What the runner does NOT own — anything that makes this chapter *this*
## chapter: the sling drill, Saul's armour, the brook, the duel. Those are
## registered by name (`enter`) and live in the campaign's own script. That is
## the split the brief asks for: reuse the framework, keep the missions unique.
##
## Completion conditions are deliberately tiny, because a condition language is
## where mission systems go to die:
##
##   {"kind": "flag",  "key": "elah_brothers_met"}            a save flag is true
##   {"kind": "count", "key": "stones", "at_least": 5}        a counter reached n
##
## Anything richer than that is an interaction, not a condition — it belongs in
## the mission's `enter` handler, which is free to do whatever the story needs
## and then set a flag for the runner to notice.

signal entered(mission: Dictionary)
signal completed(mission: Dictionary)
signal finished_all()

const REWARD_PREFIX := "mission:"

var missions: Array = []
var index := -1
var running := false
## Set while a mission's completion beat is being played, so a second tick in
## the same frame cannot complete it twice.
var _closing := false

## Injected by the owner, so the runner never touches the HUD, the dialogue box
## or the fade itself. `say(lines, done)` and `cut(done)` are the entire
## contract with the presentation layer.
var _say: Callable = Callable()
var _cut: Callable = Callable()


func setup(list: Array, say: Callable = Callable(), cut: Callable = Callable()) -> void:
	missions = list
	_say = say
	_cut = cut


func current() -> Dictionary:
	if index < 0 or index >= missions.size():
		return {}
	return missions[index]


func current_id() -> String:
	return str(current().get("id", ""))


func count() -> int:
	return missions.size()


func index_of(id: String) -> int:
	for i in range(missions.size()):
		if str((missions[i] as Dictionary).get("id", "")) == id:
			return i
	return -1


## Begin at a mission index (0 for a new chapter). A resumed save starts at the
## mission its act belongs to, which is why this takes an index and not just
## `start()`.
func start_at(i: int) -> void:
	if missions.is_empty():
		finished_all.emit()
		return
	index = clampi(i, 0, missions.size() - 1)
	running = true
	_closing = false
	_enter_current()


func start() -> void:
	start_at(0)


func _enter_current() -> void:
	var m := current()
	if m.is_empty():
		return
	# A mission may open with a brief. The runner does not know what a dialogue
	# box is — it hands the lines to whatever the owner injected, and waits for
	# that owner to say the beat is over.
	var brief: Array = m.get("brief", [])
	if not brief.is_empty() and _say.is_valid():
		_say.call(brief, func(): entered.emit(m))
		return
	entered.emit(m)


## Called by the owner every frame with a small, honestly-named context:
## the counters and flags the conditions are allowed to look at. Keeping the
## context a plain dictionary means the runner can be tested with a dictionary
## literal and no scene at all.
func tick(ctx: Dictionary) -> void:
	if not running or _closing:
		return
	var m := current()
	if m.is_empty():
		return
	if _meets(m.get("complete", {}), ctx):
		complete()


func _meets(cond: Dictionary, ctx: Dictionary) -> bool:
	if cond.is_empty():
		return false
	match str(cond.get("kind", "")):
		"flag":
			return bool(ctx.get(str(cond.get("key", "")), false)) == bool(cond.get("is", true))
		"count":
			var v := int(ctx.get(str(cond.get("key", "")), 0))
			return v >= int(cond.get("at_least", 1))
	return false


## Finish the current mission. Rewards are granted here and exactly once: the
## guard is a save flag, so reloading a chapter cannot pay out twice.
func complete() -> void:
	if _closing or not running:
		return
	var m := current()
	if m.is_empty():
		return
	_closing = true
	_grant_rewards(m)
	completed.emit(m)


## Leave the mission that just completed and enter the next one. The owner calls
## this when its completion beat (lines, fade, cut scene) has finished — the
## runner does not guess how long a beat takes.
func advance() -> void:
	if not running:
		return
	_closing = false
	index += 1
	if index >= missions.size():
		running = false
		finished_all.emit()
		return
	_enter_current()


func _grant_rewards(m: Dictionary) -> void:
	var r: Dictionary = m.get("rewards", {})
	if r.is_empty():
		return
	var guard := REWARD_PREFIX + str(m.get("id", "")) + ":rewarded"
	if bool(GameState.flag(guard, false)):
		return
	GameState.set_flag(guard, true)
	var xp := int(r.get("xp", 0))
	if xp > 0:
		GameState.add_xp(xp)
	var seal := str(r.get("seal", ""))
	if seal != "":
		GameState.grant_seal(seal)
	var relic := str(r.get("relic", ""))
	if relic != "":
		GameState.grant_relic(relic)
	var fruit := str(r.get("fruit", ""))
	if fruit != "":
		GameState.gather_fruit(fruit)
