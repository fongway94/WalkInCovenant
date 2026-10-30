extends Node
## AudioDirector — one place every sound goes through.
##
## Covenant's world mode had NO footstep audio at all, and that single absence
## was one of the largest reasons it felt flat (docs/FEEL.md §4). So footsteps,
## UI blips and region music all route here, and missing files degrade silently
## rather than spamming errors while the audio pipeline is still being built.
##
## Mix targets: music -12dB, sfx -6dB, dialogue -3dB.

var _sfx_players: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer = null
var _amb: AudioStreamPlayer = null
var _current_music: String = ""
var _round_robin := 0

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
	_amb = AudioStreamPlayer.new()
	_amb.bus = "Music"
	add_child(_amb)


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
		_music.stop()
		return
	var stream := _load(MUSIC_DIR + region_or_key + ".ogg")
	if stream == null:
		_music.stop()
		return
	_music.stream = stream
	_music.volume_db = -12.0
	_music.play()


func duck(on: bool) -> void:
	# duck music while a dialogue box is open — makes the game feel produced
	_music.volume_db = -18.0 if on else -12.0


func _load(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var r := load(path)
	return r as AudioStream
