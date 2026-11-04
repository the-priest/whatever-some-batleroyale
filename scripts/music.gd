extends Node
class_name Music

## The soundtrack: original heavy metal tracks shuffled into a playlist that
## runs in the menu and (separately adjustable) during matches. Volume 0
## silences it completely.

signal track_started(title: String)

const DIR := "res://assets/music/"
const TRACKS := [
	["iron_tide", "IRON TIDE"],
	["stormkeep", "STORMKEEP"],
	["skyreach", "SKYREACH"],
	["highfalls", "HIGHFALLS"],
	["graveblade", "GRAVEBLADE"],
]

var menu_volume := 0.7
var match_volume := 0.35
var in_match := false

var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _order: Array = []
var _pos := -1
var _bus := -1
var _target_db := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bus = AudioServer.get_bus_index("Music")
	if _bus < 0:
		AudioServer.add_bus()
		_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus, "Music")
		AudioServer.set_bus_send(_bus, "Master")
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -80.0
		p.finished.connect(_next)
		add_child(p)
		_players.append(p)
	_order = range(TRACKS.size())
	_order.shuffle()
	_apply_volume()


func _level() -> float:
	return match_volume if in_match else menu_volume


func set_volumes(menu_v: float, match_v: float) -> void:
	menu_volume = menu_v
	match_volume = match_v
	_apply_volume()


func set_in_match(v: bool) -> void:
	in_match = v
	_apply_volume()


func _apply_volume() -> void:
	var lvl := _level()
	if _bus >= 0:
		AudioServer.set_bus_volume_db(_bus, linear_to_db(maxf(0.0001, lvl)))
		AudioServer.set_bus_mute(_bus, lvl <= 0.001)
	if lvl > 0.001 and not _players[_active].playing:
		_next()


## Skip to the next track (with a short crossfade).
func _next() -> void:
	if _level() <= 0.001:
		return
	_pos += 1
	if _pos >= _order.size():
		_pos = 0
		var last = _order[-1]
		_order.shuffle()
		if _order[0] == last and _order.size() > 1:
			_order.reverse()
	var t: Array = TRACKS[_order[_pos]]
	var path: String = DIR + t[0] + ".ogg"
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = false
	var old := _players[_active]
	_active = 1 - _active
	var p := _players[_active]
	p.stream = stream
	p.volume_db = -30.0
	p.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(p, "volume_db", 0.0, 1.5)
	if old.playing:
		tw.tween_property(old, "volume_db", -60.0, 1.5)
		tw.chain().tween_callback(old.stop)
	track_started.emit(str(t[1]))


func skip() -> void:
	_next()
