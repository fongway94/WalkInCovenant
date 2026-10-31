extends Node
## AudioDirector — one place every sound goes through.
##
## Covenant's world mode had NO footstep audio at all, and that single absence
## was one of the largest reasons it felt flat (docs/FEEL.md §4). So footsteps,
## UI blips and region music all route here, and missing files degrade silently
## rather than spamming errors while the audio pipeline is still being built.
##
## Mix targets: music -12dB, sfx -6dB, dialogue -3dB. Music ducks to -19dB
## under a dialogue box.
##
## Everything that changes the music's level — ducking under a box, one region's
## theme handing over to another's, the fight cue cutting in — goes through one
## `_process` ramp rather than assigning `volume_db`. Assigning it is a step in a
## signal, and a step is a click: on a phone speaker the duck used to be audible
## as a *tick* every time anyone spoke, and the walk from the valley into
## Bethlehem slammed one track into another. `crossfade` was accepted by
## `play_music` and then ignored.

var _sfx_players: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer = null
var _music_old: AudioStreamPlayer = null
var _amb: AudioStreamPlayer = null
var _current_music: String = ""
var _round_robin := 0
var _muted_by_focus := false

## Silence, in dB, for a player that is fading out or fading in.
const SILENT_DB := -60.0
const MUSIC_DB := -12.0
const DUCK_DB := -19.0
## Ducking is the small move (7 dB) and it should be quick but not a step:
## 40 dB/s puts it at about a sixth of a second.
const DUCK_RAMP_DB_PER_SEC := 40.0

## The rate the current level move is being made at, in dB per second. A cue
## change sets it from the caller's `crossfade`, so that argument finally means
## what it says: the fight cue cuts in over 0.4 s and the return to the valley's
## theme takes 1.2 s.
var _ramp := DUCK_RAMP_DB_PER_SEC
var _ducked := false

const SFX_POOL := 8
const SFX_DIR := "res://audio/sfx/"
const MUSIC_DIR := "res://audio/music/"


func _ready() -> void:
	for i in SFX_POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	# The outgoing track. Two players, not one: a crossfade needs both tracks
	# sounding at once for the length of the fade.
	_music_old = AudioStreamPlayer.new()
	_music_old.bus = "Music"
	add_child(_music_old)
	_amb = AudioStreamPlayer.new()
	_amb.bus = "Music"
	add_child(_amb)
	apply_settings()
	EventBus.settings_changed.connect(func(_key, _value): apply_settings())


## One switch for both beds, applied at the bus so nothing can slip past it —
## including sounds added later by someone who never read this file.
func apply_settings() -> void:
	var st: Dictionary = GameState.data["settings"]
	var on := bool(st.get("sound", true)) and bool(st.get("music", true))
	_mute_bus("Music", not on)
	_mute_bus("SFX", not bool(st.get("sound", true)))


func _mute_bus(bus_name: String, muted: bool) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		return
	AudioServer.set_bus_mute(i, muted)


## The one place a music level changes. `_process` is not affected by
## `Region.set_paused()` (that pauses the world's nodes, not the autoload), so a
## fade keeps running underneath a conversation.
func _process(delta: float) -> void:
	var step := _ramp * delta
	# Keyed on "a track is loaded", not on "a track is audible": the level is
	# intent, and in a headless run the audio driver may never report playback.
	# The same property is what the smoke test reads, so this stays honest.
	if _music.stream != null:
		_music.volume_db = move_toward(_music.volume_db, _music_target(), step)
	if _music_old.stream != null:
		_music_old.volume_db = move_toward(_music_old.volume_db, SILENT_DB, step)
		if _music_old.volume_db <= SILENT_DB + 0.5:
			_music_old.stop()
			_music_old.stream = null


func _music_target() -> float:
	return DUCK_DB if _ducked else MUSIC_DB


## A phone in a pocket, or a browser tab behind a spreadsheet, must go quiet.
## Coming back must not be silent for the rest of the session.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_muted_by_focus = true
		_mute_bus("Music", true)
		_mute_bus("SFX", true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and _muted_by_focus:
		_muted_by_focus = false
		apply_settings()


func play_sfx(name: String, db: float = -6.0, pitch_jitter: float = 0.04) -> void:
	if not GameState.data["settings"].get("sound", true):
		return
	var stream := _load(SFX_DIR + name + ".ogg")
	if stream == null:
		stream = _load(SFX_DIR + name + ".wav")
	if stream == null:
		return
	_round_robin = (_round_robin + 1) % SFX_POOL
	var p: AudioStreamPlayer = _sfx_players[_round_robin]
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


## Dialogue blip, pitched per speaker so characters are audible as distinct.
func blip(speaker_id: String) -> void:
	var pitch := 1.0
	var h := hash(speaker_id) % 7
	pitch = 0.9 + h * 0.06
	play_sfx("blip", -10.0, 0.0)
	# pitch override: reuse the last pool player
	var p: AudioStreamPlayer = _sfx_players[_round_robin]
	p.pitch_scale = pitch


func play_music(region_or_key: String, crossfade: float = 1.0) -> void:
	if _current_music == region_or_key:
		return
	_current_music = region_or_key
	if not GameState.data["settings"].get("music", true):
		_stop_music()
		return
	var stream := _load(MUSIC_DIR + region_or_key + ".ogg")
	if stream == null:
		stream = _load(MUSIC_DIR + region_or_key + ".wav")
	if stream == null:
		# A region with no track gets silence, not the last region's theme
		# playing on over the new place.
		_stop_music()
		return
	_loop(stream)
	var fade := crossfade > 0.0 and _music.stream != null
	if fade:
		# Two players moving at once, in opposite directions: the longer of the
		# two journeys is silence-to-mix, so that is what the caller's duration
		# has to cover.
		_ramp = maxf(1.0, absf(MUSIC_DB - SILENT_DB) / maxf(crossfade, 0.05))
	if fade:
		_start_fade_out()
	else:
		_music.stop()
		_music_old.stop()
	_music.stream = stream
	_music.volume_db = SILENT_DB if fade else _music_target()
	_music.play()


## Handing over: the track that is playing moves to the fade-out player and
## keeps sounding while `_process` walks it down; the caller then fills `_music`
## with whatever comes next. Two fixed roles, so a second call mid-fade has
## somewhere consistent to put things.
func _start_fade_out() -> void:
	_music_old.stop()
	_music_old.stream = _music.stream
	_music_old.volume_db = _music.volume_db
	_music_old.play()
	_music.stop()
	# Cleared, not just stopped: an empty `_music` is how `_process` knows there
	# is no current track, and how `music_db()` knows not to report a level for
	# silence.
	_music.stream = null


func _stop_music() -> void:
	# A track you are leaving fades; a track that was never there does not.
	if _music.stream != null:
		_start_fade_out()
	else:
		_music_old.stop()
		_music_old.stream = null


## Music under a dialogue box. This only names the target: `_process` walks
## there, so there is no step in the waveform and no click on the close.
## Idempotent, because a box that opens onto another box calls it twice.
func duck(on: bool) -> void:
	if on != _ducked:
		_ramp = DUCK_RAMP_DB_PER_SEC
	_ducked = on


## Read by the smoke test: the music is *actually* quieter than its mix level,
## which is the only part of ducking that can be proved without ears.
func is_ducked() -> bool:
	return _ducked


func music_db() -> float:
	# Silence has no level to report, so a stop reads as silence rather than as
	# the last track's level hanging around.
	if _music == null or _music.stream == null:
		return SILENT_DB
	return _music.volume_db


func music_key() -> String:
	return _current_music


## The importer's default is "do not loop", and a twenty-four-second valley that
## stops after twenty-four seconds is worse than no music at all. The WAV header
## does not have to say it; the director does.
func _loop(stream: AudioStream) -> void:
	var wav := stream as AudioStreamWAV
	if wav == null or wav.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		return
	var channels := 2 if wav.stereo else 1
	var bytes_per_sample := 2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1
	var frames := wav.data.size() / (bytes_per_sample * channels)
	if frames <= 0:
		return
	wav.loop_begin = 0
	wav.loop_end = int(frames)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD


func _load(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var r := load(path)
	return r as AudioStream
