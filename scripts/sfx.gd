class_name Sfx
extends Node

# Small pooled positional audio player. Streams are optional: if a file is
# missing the call is silently ignored, so the game runs without audio assets.

const POOL := 40
const DIR := "res://assets/audio/gen/"

var players: Array[AudioStreamPlayer3D] = []
var ui: AudioStreamPlayer
var flat: Array[AudioStreamPlayer] = []
var _next_flat := 0
var cache: Dictionary = {}
var _next := 0
var _missing: Dictionary = {}


func _ready() -> void:
	for i in range(POOL):
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 14.0
		p.max_distance = 260.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.panning_strength = 1.0
		p.bus = "Master"
		add_child(p)
		players.append(p)
	ui = AudioStreamPlayer.new()
	ui.bus = "Master"
	add_child(ui)
	for i in 8:
		var f := AudioStreamPlayer.new()
		f.bus = "Master"
		add_child(f)
		flat.append(f)
	_preload_all()


## Load every sound up front on background threads: loading a WAV the first
## time it plays (first shot of a gun, first step on gravel) hitches a frame.
var _loading: Dictionary = {}


func _preload_all() -> void:
	var names: PackedStringArray = ResourceLoader.list_directory(DIR)
	for f in names:
		var file := f.trim_suffix(".import").trim_suffix(".remap")
		if not file.ends_with(".wav"):
			continue
		var nm := file.get_basename()
		if cache.has(nm) or _loading.has(nm):
			continue
		var path := DIR + file
		if ResourceLoader.load_threaded_request(path) == OK:
			_loading[nm] = path


func _process(_delta: float) -> void:
	if _loading.is_empty():
		set_process(false)
		return
	var done: Array = []
	for nm in _loading:
		var st := ResourceLoader.load_threaded_get_status(_loading[nm])
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			cache[nm] = ResourceLoader.load_threaded_get(_loading[nm])
			done.append(nm)
		elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			done.append(nm)
	for nm in done:
		_loading.erase(nm)


## Non-positional one-shots that may overlap (your own footsteps, cloth).
func play_2d(name: String, db := 0.0, pitch_jitter := 0.06) -> void:
	var s := stream(name)
	if s == null:
		return
	var p := flat[_next_flat]
	_next_flat = (_next_flat + 1) % flat.size()
	p.stream = s
	p.volume_db = db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


func stream(name: String) -> AudioStream:
	if cache.has(name):
		return cache[name]
	var path := DIR + name + ".wav"
	if _loading.has(name):
		# Still streaming in on a thread: take it now (rare, early on).
		var r = ResourceLoader.load_threaded_get(_loading[name])
		_loading.erase(name)
		cache[name] = r
		return r
	if not ResourceLoader.exists(path):
		_missing[name] = true
		cache[name] = null
		return null
	var s: AudioStream = load(path)
	cache[name] = s
	return s


func play_at(name: String, pos: Vector3, db := 0.0, pitch_jitter := 0.08) -> void:
	if _missing.has(name):
		return
	var s := stream(name)
	if s == null:
		return
	var p := players[_next]
	_next = (_next + 1) % players.size()
	p.stream = s
	p.global_position = pos
	p.volume_db = db
	if name.ends_with("_far") or name.begins_with("tail_"):
		# Distant gunfire and echoes: the game already scaled them by
		# distance, so keep them audible across the island.
		p.unit_size = 400.0
		p.max_distance = 1500.0
		p.attenuation_filter_cutoff_hz = 20500.0
		p.attenuation_filter_db = 0.0
	elif name.begins_with("shot_") or name == "explosion":
		# Gunfire carries across the island and loses its top end with distance.
		p.unit_size = 45.0
		p.max_distance = 950.0
		p.attenuation_filter_cutoff_hz = 2600.0
		p.attenuation_filter_db = -20.0
	else:
		p.unit_size = 14.0
		p.max_distance = 260.0
		p.attenuation_filter_cutoff_hz = 9000.0
		p.attenuation_filter_db = -6.0
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


func play_ui(name: String, db := -4.0) -> void:
	if _missing.has(name):
		return
	var s := stream(name)
	if s == null:
		return
	ui.stream = s
	ui.volume_db = db
	ui.play()
