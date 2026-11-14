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
	# Loading or switching a saved journey can replace the entire settings
	# dictionary without emitting individual settings_changed signals. The
	# persistent audio buses must reflect the destination journey immediately.
	EventBus.game_loaded.connect(apply_settings)


func _exit_tree() -> void:
	# Stop live streams before the audio server is torn down. On an immediate
	# process exit the mixer's queued playback may still be reported at shutdown;
	# stopping here does not wait for an audio-server tick.
	for player in _sfx_players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	for player in [_music, _music_old, _amb]:
		if is_instance_valid(player):
			player.stop()
			player.stream = null


## One switch for both beds, applied at the bus so nothing can slip past it —
## including sounds added later by someone who never read this file.
func apply_settings() -> void:
	var st: Dictionary = GameState.data["settings"]
	var sound_on := bool(st.get("sound", true))
	var on := sound_on and bool(st.get("music", true))
	# Settings changes can arrive while the app is in the background. They must
	# not override the focus mute until the focus-in notification restores it.
	_mute_bus("Music", not on or _muted_by_focus)
	_mute_bus("SFX", not sound_on or _muted_by_focus)
	# Coming back from mute. A track already playing becomes audible again at
	# the bus; a track requested while music was disabled was never loaded, but
	# its key was recorded. Load it now instead of waiting for another region
	# change (BUG-025).
	if on and _music.stream == null and _current_music != "":
		var key := _current_music
		_current_music = ""
		play_music(key, 0.0)


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
	_play_sfx_at_pitch(name, db, 1.0, pitch_jitter)


func _play_sfx_at_pitch(name: String, db: float, pitch: float, jitter: float) -> void:
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
	p.pitch_scale = pitch + randf_range(-jitter, jitter)
	p.play()


## Dialogue blip, pitched per speaker so characters are audible as distinct.
func blip(speaker_id: String) -> void:
	var h := hash(speaker_id) % 7
	var pitch := 0.9 + h * 0.06
	# Select pitch before starting playback. If sound is muted or the blip is
	# missing, leave the last unrelated pooled player completely untouched.
	_play_sfx_at_pitch("blip", -10.0, pitch, 0.0)


func play_music(region_or_key: String, crossfade: float = 1.0) -> void:
	if _current_music == region_or_key:
		return
	_current_music = region_or_key
	if not GameState.data["settings"].get("music", true):
		_stop_music(crossfade)
		return
	var stream := _load(MUSIC_DIR + region_or_key + ".ogg")
	if stream == null:
		stream = _load(MUSIC_DIR + region_or_key + ".wav")
	if stream == null:
		# A region with no track gets silence, not the last region's theme
		# playing on over the new place.
		_stop_music(crossfade)
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
		_music_old.stream = null
	_music.stream = stream
	_music.volume_db = SILENT_DB if fade else _music_target()
	_music.play()


## Handing over: swap the two player roles, not their streams. The current
## player keeps its playback and position while `_process` fades it out; the
## cleared spare becomes `_music` for the next track. Restarting the outgoing
## stream on the spare would jump it back to the beginning of the recording.
func _start_fade_out() -> void:
	var spare: AudioStreamPlayer = _music_old
	spare.stop()
	spare.stream = null
	_music_old = _music
	_music = spare


func _stop_music(crossfade: float = 1.0) -> void:
	# A track you are leaving fades for the requested time; an explicit zero
	# cuts both players immediately. No current track means no new fade.
	if _music.stream != null and crossfade > 0.0:
		_ramp = maxf(1.0, absf(MUSIC_DB - SILENT_DB) / maxf(crossfade, 0.05))
		_start_fade_out()
	else:
		_music.stop()
		_music.stream = null
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
