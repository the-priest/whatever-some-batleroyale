extends Node
class_name Net

## LAN multiplayer. The host runs the authoritative match: bots, storm,
## loot rolls, airdrops, eliminations and the win check. Every machine runs
## its own player (movement, shooting, hit detection) and tells the owner of
## whatever it hit. Games announce themselves with UDP broadcasts so the join
## screen lists them without typing an address.

signal roster_changed
signal status(text: String)
signal games_found(list: Array)
signal left_session(reason: String)

const PORT := 24555
const DISCOVERY_PORT := 24556
const VERSION := "br-2"
const SNAP_RATE := 12.0
const STATE_RATE := 20.0

var game: Node
var peer: ENetMultiplayerPeer
var active := false
var hosting := false
var my_name := "PLAYER"
## peer id -> name, including the host (id 1).
var roster: Dictionary = {}
var squad := true
var match_running := false

var _beacon: PacketPeerUDP
var _listener: PacketPeerUDP
var _beacon_t := 0.0
var _found: Dictionary = {}
var _snap_t := 0.0
var _state_t := 0.0
var _shots: Array = []
var _loot_out: Array = []
var _loot_seq := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)
	var user := OS.get_environment("USERNAME")
	if user == "":
		user = OS.get_environment("USER")
	if user != "":
		my_name = user.to_upper().substr(0, 14)


func my_id() -> int:
	return multiplayer.get_unique_id() if active else 1


func my_key() -> String:
	return "p%d" % my_id()


func is_client() -> bool:
	return active and not hosting


# ------------------------------------------------------------ session setup --

func host() -> bool:
	leave("")
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 8)
	if err != OK:
		status.emit("COULD NOT HOST ON PORT %d (%s)" % [PORT, error_string(err)])
		peer = null
		return false
	multiplayer.multiplayer_peer = peer
	active = true
	hosting = true
	roster = {1: my_name}
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	_beacon.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	status.emit("HOSTING  ·  %s" % ", ".join(local_addresses()))
	roster_changed.emit()
	return true


func join(address: String) -> void:
	leave("")
	stop_discovery()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address.strip_edges(), PORT)
	if err != OK:
		status.emit("COULD NOT CONNECT (%s)" % error_string(err))
		peer = null
		return
	multiplayer.multiplayer_peer = peer
	active = true
	hosting = false
	status.emit("CONNECTING TO %s ..." % address)


func leave(reason := "") -> void:
	if active and hosting and match_running:
		_abort.rpc()
	if peer != null:
		peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	peer = null
	var was := active
	active = false
	hosting = false
	match_running = false
	roster.clear()
	_beacon = null
	if was and reason != "":
		left_session.emit(reason)


func local_addresses() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254"):
			out.append(a)
	if out.is_empty():
		out.append("127.0.0.1")
	return out


# ---------------------------------------------------------------- discovery --

func start_discovery() -> void:
	stop_discovery()
	_listener = PacketPeerUDP.new()
	var err := _listener.bind(DISCOVERY_PORT)
	if err != OK:
		_listener = null
		status.emit("LAN SEARCH UNAVAILABLE  ·  TYPE THE HOST ADDRESS")
	_found.clear()


func stop_discovery() -> void:
	if _listener != null:
		_listener.close()
	_listener = null


func _process(delta: float) -> void:
	if _beacon != null and hosting:
		_beacon_t -= delta
		if _beacon_t <= 0.0:
			_beacon_t = 1.0
			var info := {"game": "blockroyale", "v": VERSION, "name": my_name, "players": roster.size(), "running": match_running}
			_beacon.put_packet(JSON.stringify(info).to_utf8_buffer())
	if _listener != null:
		var changed := false
		while _listener.get_available_packet_count() > 0:
			var pkt := _listener.get_packet()
			var ip := _listener.get_packet_ip()
			var data = JSON.parse_string(pkt.get_string_from_utf8())
			if data is Dictionary and data.get("game", "") == "blockroyale":
				data["ip"] = ip
				data["seen"] = Time.get_ticks_msec()
				_found[ip] = data
				changed = true
		var now := Time.get_ticks_msec()
		for ip in _found.keys():
			if now - int(_found[ip]["seen"]) > 4000:
				_found.erase(ip)
				changed = true
		if changed:
			games_found.emit(_found.values())
	if active and match_running:
		_tick_match(delta)


# ------------------------------------------------------------------- lobby --

func _on_peer_connected(id: int) -> void:
	if hosting:
		status.emit("%s JOINED" % ("PLAYER %d" % id))


func _on_peer_disconnected(id: int) -> void:
	if not hosting:
		return
	var name: String = roster.get(id, "PLAYER")
	roster.erase(id)
	_send_roster()
	status.emit("%s LEFT" % name)
	if match_running and game != null:
		game.net_player_left(id)


func _on_connected() -> void:
	status.emit("CONNECTED  ·  WAITING FOR THE HOST")
	_hello.rpc_id(1, my_name, VERSION)


func _on_failed() -> void:
	leave("")
	status.emit("CONNECTION FAILED")
	left_session.emit("CONNECTION FAILED")


func _on_server_gone() -> void:
	leave("")
	left_session.emit("THE HOST LEFT THE GAME")


@rpc("any_peer", "reliable")
func _hello(name: String, version: String) -> void:
	if not hosting:
		return
	var id := multiplayer.get_remote_sender_id()
	if version != VERSION:
		_kick.rpc_id(id, "VERSION MISMATCH  ·  HOST RUNS %s" % VERSION)
		return
	var n := name.strip_edges().to_upper().substr(0, 14)
	if n == "":
		n = "PLAYER"
	# Keep names unique so the kill feed makes sense.
	var base := n
	var k := 2
	while n in roster.values():
		n = "%s %d" % [base, k]
		k += 1
	roster[id] = n
	_send_roster()


@rpc("authority", "reliable")
func _kick(reason: String) -> void:
	leave("")
	left_session.emit(reason)


func set_squad(v: bool) -> void:
	squad = v
	if hosting:
		_send_roster()


func _send_roster() -> void:
	var list: Array = []
	for id in roster:
		list.append([id, roster[id]])
	var seed_v: int = game.seed_value if game != null else 0
	var size: int = game.match_size if game != null else 64
	_roster.rpc(list, squad, seed_v, size)
	roster_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _roster(list: Array, p_squad: bool, seed_v: int, size: int) -> void:
	roster.clear()
	for e in list:
		roster[int(e[0])] = str(e[1])
	squad = p_squad
	roster_changed.emit()
	if game != null:
		game.net_lobby_update(seed_v, size)


# ------------------------------------------------------------------- match --

## Host: everything a client needs to build the same match.
func send_setup(setup: Dictionary) -> void:
	match_running = true
	_shots.clear()
	_loot_out.clear()
	_setup.rpc(setup)


@rpc("authority", "call_remote", "reliable")
func _setup(setup: Dictionary) -> void:
	match_running = true
	_shots.clear()
	_loot_out.clear()
	if game != null:
		game.net_start_match(setup)


@rpc("authority", "call_remote", "reliable")
func _abort() -> void:
	match_running = false
	if game != null:
		game.net_abort()


func _tick_match(delta: float) -> void:
	if game == null:
		return
	if hosting:
		_snap_t -= delta
		if _snap_t <= 0.0:
			_snap_t = 1.0 / SNAP_RATE
			var snap: Array = game.net_snapshot()
			_snap.rpc(snap[0], snap[1], snap[2])
	_state_t -= delta
	if _state_t <= 0.0:
		_state_t = 1.0 / STATE_RATE
		var st = game.net_player_state()
		if st != null:
			_pstate.rpc(st)
	if not _shots.is_empty():
		_shot_batch.rpc(_shots)
		_shots = []
	if not _loot_out.is_empty():
		_loot_spawned.rpc(_loot_out)
		_loot_out = []


@rpc("authority", "call_remote", "unreliable_ordered")
func _snap(bots: PackedFloat32Array, zone: PackedFloat32Array, misc: PackedFloat32Array) -> void:
	if game != null:
		game.net_apply_snapshot(bots, zone, misc)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _pstate(st: Array) -> void:
	if game != null:
		game.net_apply_player_state(multiplayer.get_remote_sender_id(), st)


func queue_shot(key: String, from: Vector3, dir: Vector3, weapon: String, vis: Vector3, shot_id: int) -> void:
	_shots.append([key, from, dir, weapon, vis, shot_id])


@rpc("any_peer", "call_remote", "reliable")
func _shot_batch(list: Array) -> void:
	if game != null:
		game.net_remote_shots(list)


func send_grenade(key: String, from: Vector3, vel: Vector3) -> void:
	_grenade.rpc(key, from, vel)


@rpc("any_peer", "call_remote", "reliable")
func _grenade(key: String, from: Vector3, vel: Vector3) -> void:
	if game != null:
		game.net_remote_grenade(key, from, vel)


## A client hit a bot: the host applies it to the real one.
func send_bot_hit(bot_index: int, dmg: float, pos: Vector3, headshot: bool) -> void:
	_bot_hit.rpc_id(1, bot_index, dmg, pos, headshot)


@rpc("any_peer", "reliable")
func _bot_hit(bot_index: int, dmg: float, pos: Vector3, headshot: bool) -> void:
	if hosting and game != null:
		game.net_bot_hit(multiplayer.get_remote_sender_id(), bot_index, dmg, pos, headshot)


## Someone hit a human: tell that human's machine.
func send_player_hit(peer_id: int, dmg: float, pos: Vector3, headshot: bool, source_key: String) -> void:
	if peer_id == my_id():
		return
	_player_hit.rpc_id(peer_id, dmg, pos, headshot, source_key)


@rpc("any_peer", "reliable")
func _player_hit(dmg: float, pos: Vector3, headshot: bool, source_key: String) -> void:
	if game != null:
		game.net_player_hit(dmg, pos, headshot, source_key)


func report_death(killer_key: String, killer_name: String, weapon: String) -> void:
	if hosting:
		game.net_human_died(1, killer_key, killer_name, weapon)
	else:
		_died.rpc_id(1, killer_key, killer_name, weapon)


@rpc("any_peer", "reliable")
func _died(killer_key: String, killer_name: String, weapon: String) -> void:
	if hosting and game != null:
		game.net_human_died(multiplayer.get_remote_sender_id(), killer_key, killer_name, weapon)


func send_elim(e: Dictionary) -> void:
	_elim.rpc(e)


@rpc("authority", "call_remote", "reliable")
func _elim(e: Dictionary) -> void:
	if game != null:
		game.net_elim(e)


func new_loot_id() -> int:
	_loot_seq += 1
	return (my_id() % 2000) * 1000000 + _loot_seq


func queue_loot(entry: Array) -> void:
	_loot_out.append(entry)


@rpc("any_peer", "call_remote", "reliable")
func _loot_spawned(list: Array) -> void:
	if game != null:
		game.net_loot_spawned(list)


func send_loot_taken(id: int) -> void:
	_loot_taken.rpc(id)


@rpc("any_peer", "call_remote", "reliable")
func _loot_taken(id: int) -> void:
	if game != null:
		game.net_loot_taken(id)


func send_airdrop(p: Vector2, ground: float) -> void:
	_airdrop.rpc(p, ground)


@rpc("authority", "call_remote", "reliable")
func _airdrop(p: Vector2, ground: float) -> void:
	if game != null:
		game.net_airdrop(p, ground)


func send_match_over(winner_key: String, winner_name: String, squad_win: bool) -> void:
	_match_over.rpc(winner_key, winner_name, squad_win)


@rpc("authority", "call_remote", "reliable")
func _match_over(winner_key: String, winner_name: String, squad_win: bool) -> void:
	if game != null:
		game.net_match_over(winner_key, winner_name, squad_win)
