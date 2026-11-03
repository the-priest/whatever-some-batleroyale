class_name Sfx
extends Node

# Small pooled positional audio player. Streams are optional: if a file is
# missing the call is silently ignored, so the game runs without audio assets.

const POOL := 24
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
