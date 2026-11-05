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
signal chat(from_id: int, name: String, text: String, system: bool)
signal countdown(seconds: int)
signal pings_updated
signal marker(from_id: int, pos: Vector3)

const PORT := 24555
const DISCOVERY_PORT := 24556
const VERSION := "br-4"
const SNAP_RATE := 12.0
const STATE_RATE := 20.0
const MAX_PLAYERS := 8
## Shots further than this from a player are not sent to them at all.
const SHOT_RANGE := 600.0
## One colour per player slot: lobby cards, name tags, map dots, markers.
const COLORS := [
	Color(0.96, 0.66, 0.24), Color(0.36, 0.80, 0.98), Color(0.52, 0.92, 0.44), Color(0.96, 0.42, 0.62),
	Color(0.76, 0.56, 1.00), Color(1.00, 0.88, 0.30), Color(0.30, 0.92, 0.80), Color(1.00, 0.52, 0.36),
]

var game: Node
var peer: ENetMultiplayerPeer
var active := false
var hosting := false
var my_name := "PLAYER"
## peer id -> name, including the host (id 1).
var roster: Dictionary = {}
var squad := true
var match_running := false
## Per player: {"ready": bool, "color": int, "ping": int}.
var info: Dictionary = {}
## Host-controlled match settings, mirrored to everyone.
var settings := {"squad": true, "bots": 63, "loadout": true}
var _ping_t := 0.0
var _countdown_left := -1.0

var _beacon: PacketPeerUDP
var _listener: PacketPeerUDP
var _beacon_t := 0.0
var _found: Dictionary = {}
var _snap_t := 0.0
var _state_t := 0.0
var _shots: Array = []
var _loot_out: Array = []
var _loot_seq := 0
var _veh_t := 0.0
var _veh_fast := 0.0


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
	var err := peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		status.emit("COULD NOT HOST ON PORT %d (%s)" % [PORT, error_string(err)])
		peer = null
		return false
	multiplayer.multiplayer_peer = peer
	active = true
	hosting = true
	roster = {1: my_name}
	info = {1: {"ready": true, "color": 0, "ping": 0}}
	if game != null:
		settings["bots"] = game.MAX_BOTS
		settings["loadout"] = game.loadout_enabled
	settings["squad"] = squad
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
	# "host" or "host:port".
	var addr := address.strip_edges()
	var port := PORT
	if addr.count(":") == 1:
		port = int(addr.get_slice(":", 1))
		addr = addr.get_slice(":", 0)
	var err := peer.create_client(addr, port)
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
	info.clear()
	_countdown_left = -1.0
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
			var beacon := {"game": "blockroyale", "v": VERSION, "name": my_name, "players": roster.size(),
				"max": MAX_PLAYERS, "running": match_running, "squad": squad, "bots": int(settings.get("bots", 63))}
			_beacon.put_packet(JSON.stringify(beacon).to_utf8_buffer())
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
	if active:
		_ping_t -= delta
		if _ping_t <= 0.0:
			_ping_t = 1.0
			_update_pings()
	if hosting and _countdown_left > 0.0:
		_countdown_left -= delta
		if _countdown_left <= 0.0:
			_countdown_left = -1.0
			if game != null:
				game._net_host_start()


# ------------------------------------------------------------------- lobby --

func _on_peer_connected(id: int) -> void:
	if hosting:
		status.emit("%s JOINED" % ("PLAYER %d" % id))


func _on_peer_disconnected(id: int) -> void:
	if not hosting:
		return
	var name: String = roster.get(id, "PLAYER")
	roster.erase(id)
	info.erase(id)
	_send_roster()
	status.emit("%s LEFT" % name)
	_chat.rpc(0, "", "%s LEFT THE LOBBY" % name, true)
	chat.emit(0, "", "%s LEFT THE LOBBY" % name, true)
	if _countdown_left > 0.0:
		cancel_countdown()
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
	var used: Array = []
	for other in info:
		used.append(int(info[other]["color"]))
	var col := 0
	while col in used and col < COLORS.size() - 1:
		col += 1
	info[id] = {"ready": false, "color": col, "ping": 0}
	_send_roster()
	_chat.rpc(0, "", "%s JOINED THE LOBBY" % n, true)
	chat.emit(0, "", "%s JOINED THE LOBBY" % n, true)


@rpc("authority", "reliable")
func _kick(reason: String) -> void:
	leave("")
	left_session.emit(reason)


func set_squad(v: bool) -> void:
	squad = v
	settings["squad"] = v
	if hosting:
		_send_roster()


## Host: change a match setting (mode, bots, loadout).
func set_setting(key: String, value: Variant) -> void:
	if not hosting:
		return
	settings[key] = value
	if key == "squad":
		squad = bool(value)
	_send_roster()


func color_of(id: int) -> Color:
	var i := int(info.get(id, {}).get("color", 0))
	return COLORS[i % COLORS.size()]


func ping_of(id: int) -> int:
	return int(info.get(id, {}).get("ping", 0))


func is_ready(id: int) -> bool:
	return id == 1 or bool(info.get(id, {}).get("ready", false))


func all_ready() -> bool:
	for id in roster:
		if not is_ready(int(id)):
			return false
	return true


func ready_count() -> int:
	var n := 0
	for id in roster:
		if is_ready(int(id)):
			n += 1
	return n


func set_ready(v: bool) -> void:
	if hosting or not active:
		return
	if info.has(my_id()):
		info[my_id()]["ready"] = v
	roster_changed.emit()
	_ready_state.rpc_id(1, v)


@rpc("any_peer", "reliable")
func _ready_state(v: bool) -> void:
	if not hosting:
		return
	var id := multiplayer.get_remote_sender_id()
	if info.has(id):
		info[id]["ready"] = v
		_send_roster()
		if not v and _countdown_left > 0.0:
			cancel_countdown()


func _send_roster() -> void:
	var list: Array = []
	for id in roster:
		var i: Dictionary = info.get(id, {"ready": false, "color": 0, "ping": 0})
		list.append([id, roster[id], bool(i["ready"]), int(i["color"]), int(i["ping"])])
	var seed_v: int = game.seed_value if game != null else 0
	if game != null:
		game.net_apply_settings(settings)
	_roster.rpc(list, settings, seed_v)
	roster_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _roster(list: Array, p_settings: Dictionary, seed_v: int) -> void:
	roster.clear()
	info.clear()
	for e in list:
		roster[int(e[0])] = str(e[1])
		info[int(e[0])] = {"ready": bool(e[2]), "color": int(e[3]), "ping": int(e[4])}
	settings = p_settings
	squad = bool(settings.get("squad", true))
	# The host may have renamed us to keep names unique.
	if roster.has(my_id()):
		my_name = str(roster[my_id()])
	roster_changed.emit()
	if game != null:
		game.net_lobby_update(seed_v, int(settings.get("bots", 63)) + 1)
		game.net_apply_settings(settings)


func _update_pings() -> void:
	if peer == null:
		return
	if hosting:
		var pings := {}
		for id in roster:
			if int(id) == 1:
				continue
			var pp := peer.get_peer(int(id))
			if pp != null:
				var rtt := int(pp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
				if info.has(id):
					info[id]["ping"] = rtt
				pings[id] = rtt
		if not pings.is_empty():
			_pings.rpc(pings)
		pings_updated.emit()
	else:
		var hp := peer.get_peer(1)
		if hp != null and info.has(my_id()):
			info[my_id()]["ping"] = int(hp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
			pings_updated.emit()


@rpc("authority", "call_remote", "unreliable", 5)
func _pings(pings: Dictionary) -> void:
	for id in pings:
		if info.has(id) and int(id) != my_id():
			info[id]["ping"] = int(pings[id])
	pings_updated.emit()


# -------------------------------------------------------------------- chat --

func send_chat(text: String) -> void:
	var t := text.strip_edges().substr(0, 140)
	if t == "" or not active:
		return
	_chat.rpc(my_id(), my_name, t, false)
	chat.emit(my_id(), my_name, t, false)


@rpc("any_peer", "call_remote", "reliable")
func _chat(from_id: int, name: String, text: String, system: bool) -> void:
	var sender := multiplayer.get_remote_sender_id()
	# Only the host may speak for the system or for someone else.
	if sender != 1:
		from_id = sender
		name = str(roster.get(sender, name))
		system = false
	chat.emit(from_id, name, text, system)


# --------------------------------------------------------------- countdown --

func start_countdown(seconds := 5) -> void:
	if not hosting:
		return
	_countdown_left = float(seconds)
	_countdown.rpc(seconds)
	countdown.emit(seconds)


func cancel_countdown() -> void:
	if not hosting:
		return
	_countdown_left = -1.0
	_countdown.rpc(-1)
	countdown.emit(-1)


func counting_down() -> bool:
	return _countdown_left > 0.0


@rpc("authority", "call_remote", "reliable")
func _countdown(seconds: int) -> void:
	countdown.emit(seconds)


# ----------------------------------------------------------------- markers --

func send_marker(pos: Vector3) -> void:
	if active:
		_marker.rpc(pos)
	marker.emit(my_id(), pos)


@rpc("any_peer", "call_remote", "reliable")
func _marker(pos: Vector3) -> void:
	marker.emit(multiplayer.get_remote_sender_id(), pos)


# ------------------------------------------------------------------- match --

## Host: everything a client needs to build the same match.
func send_setup(setup: Dictionary) -> void:
	match_running = true
	_countdown_left = -1.0
	# Everyone readies up again for the next one.
	for id in info:
		if int(id) != 1:
			info[id]["ready"] = false
	_shots.clear()
	_loot_out.clear()
	_setup.rpc(setup)


@rpc("authority", "call_remote", "reliable")
func _setup(setup: Dictionary) -> void:
	match_running = true
	for id in info:
		if int(id) != 1:
			info[id]["ready"] = false
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
			# Under the MTU per packet: 32 bots (8 floats each) at a time, so a
			# lost packet only costs half the bots one update, not everyone.
			var bp: PackedFloat32Array = snap[0]
			var per := 32 * 8
			var off := 0
			while off < bp.size() or off == 0:
				_snap.rpc(bp.slice(off, off + per), off / 8, snap[1] if off == 0 else PackedFloat32Array(), snap[2] if off == 0 else PackedFloat32Array())
				off += per
				if off >= bp.size():
					break
	_state_t -= delta
	if _state_t <= 0.0:
		_state_t = 1.0 / STATE_RATE
		var st = game.net_player_state()
		if st != null:
			_pstate.rpc(st)
	# Shot effects (tracers, sound) at up to 30 Hz, unreliable, and each
	# client only hears shots within earshot of where they are.
	_shot_t -= delta
	if _shot_t <= 0.0 and (not _shots.is_empty() or not _relay.is_empty()):
		_shot_t = 1.0 / 30.0
		if hosting:
			for id in roster:
				var pid := int(id)
				if pid == 1:
					continue
				var where: Vector3 = game.net_peer_position(pid)
				var out: Array = []
				for e in _shots:
					if where == Vector3.INF or (e[1] as Vector3).distance_to(where) < SHOT_RANGE:
						out.append(e)
				for r in _relay:
					if int(r[0]) != pid and (where == Vector3.INF or (r[1][1] as Vector3).distance_to(where) < SHOT_RANGE):
						out.append(r[1])
				var j := 0
				while j < out.size():
					_shot_batch.rpc_id(pid, out.slice(j, j + 12))
					j += 12
		elif not _shots.is_empty():
			var j2 := 0
			while j2 < _shots.size():
				_shot_batch.rpc_id(1, _shots.slice(j2, j2 + 12))
				j2 += 12
		_shots = []
		_relay = []
	if not _loot_out.is_empty():
		_loot_spawned.rpc(_loot_out)
		_loot_out = []
	_veh_t -= delta
	var full := _veh_t <= 0.0
	if full:
		_veh_t = 1.0
	_veh_fast -= delta
	if _veh_fast <= 0.0 or full:
		_veh_fast = 1.0 / 20.0
		var vs: Array = game.net_vehicle_states(full)
		# A dozen jeeps per packet keeps each one under the MTU.
		var i := 0
		while i < vs.size():
			_vstate.rpc(vs.slice(i, i + 12))
			i += 12


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _snap(bots: PackedFloat32Array, first: int, zone: PackedFloat32Array, misc: PackedFloat32Array) -> void:
	if game != null:
		game.net_apply_snapshot(bots, zone, misc, first)


@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _pstate(st: Array) -> void:
	if game != null:
		game.net_apply_player_state(multiplayer.get_remote_sender_id(), st)


var _relay: Array = []
var _shot_t := 0.0


func queue_shot(key: String, from: Vector3, dir: Vector3, weapon: String, vis: Vector3, shot_id: int) -> void:
	_shots.append([key, from, dir, weapon, vis, shot_id])


@rpc("any_peer", "call_remote", "unreliable", 4)
func _shot_batch(list: Array) -> void:
	if game != null:
		game.net_remote_shots(list)
	# The host passes a client's shots on to the other clients near them.
	if hosting:
		var from := multiplayer.get_remote_sender_id()
		for e in list:
			_relay.append([from, e])


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


@rpc("any_peer", "call_remote", "unreliable_ordered", 3)
func _vstate(list: Array) -> void:
	if game != null:
		game.net_apply_vehicle_states(list)


func send_vehicle_owner(id: int) -> void:
	_vowner.rpc(id)


@rpc("any_peer", "call_remote", "reliable")
func _vowner(id: int) -> void:
	if game != null:
		game.net_vehicle_owner(id, multiplayer.get_remote_sender_id())


func send_vehicle_hit(id: int, amount: float) -> void:
	_vhit.rpc(id, amount)


@rpc("any_peer", "call_remote", "reliable")
func _vhit(id: int, amount: float) -> void:
	if game != null:
		game.net_vehicle_hit_received(id, amount)


func send_vehicle_destroyed(id: int) -> void:
	_vdestroyed.rpc(id)


@rpc("any_peer", "call_remote", "reliable")
func _vdestroyed(id: int) -> void:
	if game != null:
		game.net_vehicle_destroyed_received(id)


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
