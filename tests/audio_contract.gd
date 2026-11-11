extends Node
## Audio contracts that run with Godot's headless dummy driver. They exercise
## real player/bus state and resource lifetime, not audible quality or hardware.

var checks := 0
var failures := 0


func _ready() -> void:
	_run()


func _run() -> void:
	GameState.new_game()
	var settings: Dictionary = GameState.data["settings"]
	var director: Node = AudioDirector
	AudioDirector._muted_by_focus = false
	AudioDirector.apply_settings()
	var music_bus := AudioServer.get_bus_index("Music")
	var sfx_bus := AudioServer.get_bus_index("SFX")
	_check(music_bus >= 0 and sfx_bus >= 0, "both named audio buses exist")

	# A rejected blip must not repitch an unrelated pooled player.
	AudioDirector.play_sfx("hit", -6.0, 0.0)
	var last: AudioStreamPlayer = AudioDirector._sfx_players[AudioDirector._round_robin]
	_check(last.stream != null and last.stream.resource_path.ends_with("/hit.wav"),
		"an enabled sound obtains a pool player")
	last.pitch_scale = 1.7
	var previous_index: int = AudioDirector._round_robin
	settings["sound"] = false
	AudioDirector.blip("corin")
	_check(AudioDirector._round_robin == previous_index and is_equal_approx(last.pitch_scale, 1.7),
		"a muted dialogue blip leaves the previous sound untouched")
	settings["sound"] = true
	AudioDirector.play_sfx("no_such_sound_for_test", -6.0, 0.0)
	_check(AudioDirector._round_robin == previous_index and is_equal_approx(last.pitch_scale, 1.7),
		"a missing effect leaves the previous sound untouched")
	AudioDirector.blip("corin")
	var blip: AudioStreamPlayer = AudioDirector._sfx_players[AudioDirector._round_robin]
	var expected_pitch := 0.9 + (hash("corin") % 7) * 0.06
	_check(AudioDirector._round_robin != previous_index and blip.stream != null
		and blip.stream.resource_path.ends_with("/blip.wav")
		and is_equal_approx(blip.pitch_scale, expected_pitch),
		"an enabled dialogue blip gets its speaker's pitch")

	# A settings signal received in the background must not unmute either bus.
	director.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(AudioServer.is_bus_mute(music_bus) and AudioServer.is_bus_mute(sfx_bus),
		"losing focus mutes both buses")
	EventBus.settings_changed.emit("sound", true)
	_check(AudioServer.is_bus_mute(music_bus) and AudioServer.is_bus_mute(sfx_bus),
		"a settings change while unfocused keeps both buses muted")
	director.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(not AudioServer.is_bus_mute(music_bus) and not AudioServer.is_bus_mute(sfx_bus),
		"regaining focus restores enabled settings")
	director.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	settings["sound"] = false
	EventBus.settings_changed.emit("sound", false)
	director.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(AudioServer.is_bus_mute(music_bus) and AudioServer.is_bus_mute(sfx_bus),
		"regaining focus respects a user mute selected in the background")
	settings["sound"] = true
	EventBus.settings_changed.emit("sound", true)
	settings["music"] = false
	EventBus.settings_changed.emit("music", false)
	_check(AudioServer.is_bus_mute(music_bus) and not AudioServer.is_bus_mute(sfx_bus),
		"music can be disabled without disabling sound effects")
	settings["music"] = true
	EventBus.settings_changed.emit("music", true)

	# Crossfading must retain the original playback object. Re-starting the same
	# stream on the other player jumps the outgoing music back to its first beat.
	AudioDirector.play_music("valley", 0.0)
	await get_tree().create_timer(0.2).timeout
	var original: AudioStreamPlayer = AudioDirector._music
	var playback: AudioStreamPlayback = original.get_stream_playback() if original.playing else null
	_check(original.playing and playback != null, "the valley track is playing before the handover")
	var position_before := original.get_playback_position() if playback != null else 0.0
	var playback_ref: WeakRef = weakref(playback) if playback != null else null
	AudioDirector.play_music("bethlehem", 0.25)
	_check(AudioDirector._music_old == original and original.playing
		and original.get_stream_playback() == playback
		and original.get_playback_position() >= position_before - 0.02,
		"crossfade preserves the outgoing player and playback position")
	_check(AudioDirector._music.playing and AudioDirector._music.stream != null
		and AudioDirector._music.stream.resource_path.ends_with("/bethlehem.wav"),
		"the incoming track plays while the outgoing track fades")
	playback = null
	await get_tree().create_timer(0.8).timeout
	_check(AudioDirector._music_old.stream == null and not AudioDirector._music_old.playing,
		"a finished fade releases the outgoing player")
	_check(playback_ref != null and playback_ref.get_ref() == null,
		"the finished outgoing playback is released while the game is still running")

	# Switching again in the middle of a fade should preserve the new outgoing
	# playback and reuse the two existing nodes rather than restarting it.
	AudioDirector.play_music("battle", 0.7)
	await get_tree().create_timer(0.1).timeout
	var outgoing: AudioStreamPlayer = AudioDirector._music
	var spare: AudioStreamPlayer = AudioDirector._music_old
	var midway: AudioStreamPlayback = outgoing.get_stream_playback() if outgoing.playing else null
	AudioDirector.play_music("valley", 0.2)
	_check(midway != null and AudioDirector._music_old == outgoing and outgoing.playing
		and outgoing.get_stream_playback() == midway and AudioDirector._music == spare,
		"a mid-fade handover preserves playback and reuses the two players")
	midway = null
	AudioDirector.play_music("bethlehem", 0.0)
	_check(AudioDirector._music_old.stream == null and not AudioDirector._music_old.playing,
		"an immediate cut clears any older fading track")

	var before_silence: AudioStreamPlayer = AudioDirector._music
	var before_silence_playback: AudioStreamPlayback = before_silence.get_stream_playback() \
		if before_silence.playing else null
	AudioDirector.play_music("no_such_track_for_test", 0.2)
	_check(before_silence_playback != null and AudioDirector._music.stream == null
		and AudioDirector._music_old == before_silence and before_silence.playing
		and before_silence.get_stream_playback() == before_silence_playback,
		"a missing track fades the existing playback instead of restarting it")
	before_silence_playback = null
	await get_tree().create_timer(0.5).timeout
	_check(AudioDirector._music_old.stream == null and not AudioDirector._music_old.playing,
		"a missing track completes its requested fade to silence")
	AudioDirector.play_music("valley", 0.0)
	AudioDirector.play_music("no_such_track_for_cut", 0.0)
	_check(AudioDirector._music.stream == null and AudioDirector._music_old.stream == null
		and not AudioDirector._music.playing and not AudioDirector._music_old.playing,
		"a zero-duration transition to silence stops both players")

	# Repeated transitions must not retain old playback objects during play.
	var retired: Array[WeakRef] = []
	for i in range(10):
		AudioDirector.play_music("valley" if i % 2 == 0 else "bethlehem", 0.15)
		await get_tree().create_timer(0.08).timeout
		var current: AudioStreamPlayer = AudioDirector._music
		if i < 9 and current.playing:
			var current_playback: AudioStreamPlayback = current.get_stream_playback()
			retired.append(weakref(current_playback))
			current_playback = null
	await get_tree().create_timer(0.8).timeout
	var still_alive := 0
	for ref in retired:
		if ref.get_ref() != null:
			still_alive += 1
	_check(retired.size() == 9 and still_alive == 0,
		"repeated handovers release all nine retired playback objects during play")

	# The mixer tears down asynchronously. This is test-harness shutdown, not a
	# production fix for exit warnings: stop and allow it time to drain before
	# quitting so live-resource assertions above are not confused with teardown.
	for player in AudioDirector._sfx_players:
		player.stop()
		player.stream = null
	for player in [AudioDirector._music, AudioDirector._music_old, AudioDirector._amb]:
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.5).timeout
	print("audio contract: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("PASS audio: " + message)
	else:
		failures += 1
		printerr("FAIL audio: " + message)
