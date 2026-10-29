class_name AudioDirector
extends Node
## Music, ambience loops and pooled one-shot SFX. All sounds are synthesised offline by
## tools/audio/make_audio.py (CC0). Static helpers are no-ops when no director exists
## (headless tests), so gameplay code can call AudioDirector.sfx() freely.

const DIR := "res://assets/audio/"
const SFX := ["ui_click", "ui_open", "ui_close", "ui_error", "build", "chop", "plant", "dig", "water",
	"notify", "warn", "win", "lose", "star"]
const POOL := 6

static var current: AudioDirector

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var music: AudioStreamPlayer
var sea: AudioStreamPlayer
var rain: AudioStreamPlayer
var _rain_target := 0.0
var _last_play := {}


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null
	shutdown()


## Stops and drops every stream so no playback objects outlive the audio server at quit.
## Call a frame before quitting (the mixer releases playbacks on its next pass).
func shutdown() -> void:
	for p in _pool + [music, sea, rain]:
		if p != null:
			p.stop()
			p.stream = null
	_streams.clear()


func _ready() -> void:
	for n in SFX:
		var s := _load(n)
		if s != null:
			_streams[n] = s
	for k in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_pool.append(p)
	music = _loop_player("music_island", &"Music", -4.0)
	sea = _loop_player("amb_sea", &"Ambience", -6.0)
	rain = _loop_player("amb_rain", &"Ambience", -60.0)


func _load(n: String) -> AudioStream:
	var path := DIR + n + ".ogg"
	return load(path) as AudioStream if ResourceLoader.exists(path) else null


func _loop_player(n: String, bus: StringName, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.volume_db = db
	var s := _load(n)
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	p.stream = s
	add_child(p)
	return p


func start_loops() -> void:
	for p in [music, sea, rain]:
		if p.stream != null and not p.playing:
			p.play()


## 0..1 rain intensity fades the rain loop in and out.
func set_rain(amount: float) -> void:
	_rain_target = clampf(amount, 0.0, 1.0)


func _process(delta: float) -> void:
	if rain == null:
		return
	var target_db := linear_to_db(maxf(_rain_target, 0.001)) - 2.0
	rain.volume_db = move_toward(rain.volume_db, target_db, delta * 18.0)


func play(n: String, pitch: float = 1.0, db: float = 0.0) -> void:
	if not _streams.has(n):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_play.get(n, -1000)) < 45:
		return # avoid machine-gun stacking of the same sound
	_last_play[n] = now
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _streams[n]
	p.pitch_scale = pitch
	p.volume_db = db
	p.play()


static func sfx(n: String, pitch: float = 1.0, db: float = 0.0) -> void:
	if current != null:
		current.play(n, pitch, db)
