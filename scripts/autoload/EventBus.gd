extends Node
## EventBus — the seam that keeps content decoupled from engine.
##
## Direct descendant of Covenant's `src/core/bus.js`. Every signal here is a
## contract: content emits, systems listen, and neither knows the other exists.
##
## Two rules when adding a signal:
##   1. Past tense. Signals describe what HAPPENED, never what should be done.
##   2. No node references in payloads. IDs and data only, so a chapter JSON can
##      trigger them without holding a pointer into the scene tree.
##
## ── A note on `hint_used` ────────────────────────────────────────────────
## In Covenant v0.7 a real analytics bug was fixed: requesting a hint was being
## recorded into `adventure.ways`, which polluted the statistics that feed the
## Journey Mirror. `addHintUse()` was separated out so the Mirror could honestly
## claim to reflect unaided choices. That separation is preserved here as a
## distinct signal. Do not fold it back into `way_recorded`.

## ── World ───────────────────────────────────────────────────────────────
signal player_entered_region(region_id: String)
signal player_left_region(region_id: String)
signal player_interacted_with(target_id: String, kind: String)
signal item_picked_up(item_id: String)
## A verse handed over by a person on the road. In the Valley of Elah these four
## become the four moves in the fight — the game does not give you a weapon the
## walk did not earn.
signal verse_received(word_id: String, ref: String)
signal time_of_day_changed(phase: String)

## ── Story ───────────────────────────────────────────────────────────────
signal chapter_started(chapter_id: String)
signal chapter_completed(chapter_id: String)
signal dialogue_started(node_id: String)
signal dialogue_finished(node_id: String)
signal choice_made(node_id: String, choice_index: int)
signal moment_completed(moment_id: String, kind: String)
signal moment_skipped(moment_id: String, kind: String)

## ── The signature transition ────────────────────────────────────────────
## "You hear your own heartbeat, and then it stops being yours. You look down:
##  the hands holding the sling are not your hands."
## Then, afterwards: "You are yourself again."
signal become_requested(biblical_character: String)
signal become_active(biblical_character: String)
signal become_ended(biblical_character: String)

## ── Progression ─────────────────────────────────────────────────────────
signal virtue_changed(virtue: String, value: int)
## step / notice / stay / wait — the four "ways of walking" that feed the Mirror.
signal way_recorded(way: String)
## Tracked separately, on purpose. See the note at the top of this file.
signal hint_used()
signal xp_gained(amount: int)
signal level_changed(new_level: int)
signal relic_granted(relic_id: String)
signal fruit_gathered(fruit_id: String)
signal seal_earned(seal_id: String)
signal guidance_changed(amount: int)
signal prayer_offered(chapter_id: String)

## ── Quests ──────────────────────────────────────────────────────────────
signal quest_started(quest_id: String)
signal quest_objective_met(quest_id: String, objective_id: String)
signal quest_completed(quest_id: String)
signal npc_escort_started(npc_id: String)
signal npc_escort_ended(npc_id: String)

## ── System ──────────────────────────────────────────────────────────────
signal language_changed(lang: String)
signal settings_changed(key: String, value: Variant)
signal game_saved()
signal game_loaded()
signal toast_requested(text: String)


## Convenience: is reduced motion in effect? Every shake, flash and time-scale
## effect in the project gates on this. Pillar 5 — formation over winning — and
## a game churches hand to children and elderly players must honour it.
func reduced_motion() -> bool:
	var explicit: bool = get_meta("reduce_motion", false)
	if explicit:
		return true
	# Godot has no direct prefers-reduced-motion binding; on web export the
	# shell can push the OS preference in via JS. Absent that, respect our own
	# accessibility toggle, which is the one that matters on a phone.
	return false


## Emit with a guard so a typo'd signal name fails loudly in debug and never
## crashes a shipping build mid-chapter.
func safe_emit(sig: StringName, args: Array = []) -> void:
	if not has_signal(sig):
		push_error("EventBus: no such signal '%s'" % sig)
		return
	match args.size():
		0: emit_signal(sig)
		1: emit_signal(sig, args[0])
		2: emit_signal(sig, args[0], args[1])
		3: emit_signal(sig, args[0], args[1], args[2])
		4: emit_signal(sig, args[0], args[1], args[2], args[3])
		_: push_error("EventBus.safe_emit: too many args for '%s'" % sig)
