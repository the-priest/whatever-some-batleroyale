extends Node
class_name Net

## Multiplayer, hosted by a player (LAN or over the internet). The host runs
## the authoritative match: bots, storm, loot rolls, airdrops, eliminations
## and the win check. Every machine runs its own player (movement, shooting,
## hit detection) and reports to the host. Games announce themselves with UDP
## broadcasts so the join screen lists LAN games without typing an address.
##
## Security model:
##  - Clients talk to the host only (no relay between clients). Whatever a
##    client says about the world reaches the others through the host, which
##    checks who sent it, how often, and whether it is possible, and stamps
##    the sender's identity on it itself.
##  - Nobody is listened to before the handshake: version, the lobby password
##    (proved against a one-time challenge, never sent), ban list.
##  - A dropped player can only be resumed with the session token the host
##    gave them, not by typing their name.
##  - The connection is encrypted (DTLS).
##  - The host can kick and ban.

signal roster_changed
signal status(text: String)
signal games_found(list: Array)
signal left_session(reason: String)
signal chat(from_id: int, name: String, text: String, system: bool)
signal countdown(seconds: int)
signal pings_updated
signal marker(from_id: int, pos: Vector3)
## Connection lost mid-match: "" when back (or given up), else the banner text.
signal reconnect_state(text: String)

const PORT := 24555
const DISCOVERY_PORT := 24556
const VERSION := "br-6"
## A peer that connects has this long to finish the handshake.
const HELLO_TIMEOUT_MS := 10000
## Wrong passwords from one address before it is shut out for a while.
const MAX_PASSWORD_FAILS := 5
const FAIL_BAN_MS := 600000
## Messages per second a client may send, by kind: [sustained, burst].
const RATES := {
	"pstate": [30.0, 45.0], "vstate": [30.0, 45.0], "shots": [40.0, 70.0], "chat": [1.5, 5.0], "marker": [2.0, 6.0],
	"grenade": [1.5, 4.0], "hit": [30.0, 70.0], "loot": [12.0, 40.0], "veh": [20.0, 40.0], "misc": [4.0, 12.0], "inv": [1.0, 3.0],
}
## Dropped messages before a flooding client is kicked.
const FLOOD_KICK := 600
## A player who drops out of a running match keeps their place this long.
const GHOST_MS := 120000
## A client that loses the host mid-match keeps trying this long.
const RECONNECT_S := 75.0
const SNAP_RATE := 12.0
const STATE_RATE := 20.0
const MAX_PLAYERS := 8
## Shots further than this from a player are not sent to them at all.
const SHOT_RANGE := 1300.0
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
var last_address := ""
var reconnecting := false
var _reco_left := 0.0
var _reco_try := 0.0
## Host: players who dropped mid-match, by the name they asked for:
## {"id": old peer id, "until": msec}.
var _ghosts: Dictionary = {}
## Host: the name each peer asked for (before it was made unique).
var _asked_name: Dictionary = {}
var _inv_t := 0.0

## Host: the lobby password ("" = open). It never travels over the wire.
var password := ""
## Client: the password offered to the host being joined.
var join_password := ""
## Encrypt the connection (both sides must agree; on by default).
var secure := true
## Host: peers that connected but have not passed the handshake yet:
## id -> {"t": msec, "nonce": String, "ip": String}.
var _handshake: Dictionary = {}
## Host: peer id -> the session token they must show to resume their place.
var _tokens: Dictionary = {}
## Client: our token from the host.
var _session_token := ""
## Host: banned addresses (kept between sessions) and password failures.
var _bans: Dictionary = {}
var _fails: Dictionary = {}
## Host: per peer rate buckets and dropped-message counts.
var _rate: Dictionary = {}
var _flood: Dictionary = {}
var _flood_t := 0.0
## Host: peers on their way out: id -> msec to cut the line at.
var _dropping: Dictionary = {}
## Host: clients that have built the match and are sending their state. The
## stream of snapshots only starts once a client is ready to take it (a machine
## still loading would let it pile up and overflow).
var _loaded: Dictionary = {}
var _upnp_thread: Thread
## Host: address players on the internet can use, once the router answered.
var public_address := ""


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
		my_name = _clean_name(user)
	_load_bans()


var _my_id := 1


func my_id() -> int:
	if active:
		_my_id = multiplayer.get_unique_id()
		return _my_id
	# While dialling back in we are still who we were.
	return _my_id if reconnecting else 1


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
	if secure and not _dtls_server():
		status.emit("COULD NOT SET UP ENCRYPTION  ·  HOSTING WITHOUT IT")
		secure = false
	multiplayer.multiplayer_peer = peer
	# Clients talk to the host and nobody else.
	(multiplayer as SceneMultiplayer).server_relay = false
	active = true
	hosting = true
	_handshake.clear()
	_tokens.clear()
	_rate.clear()
	_flood.clear()
	_dropping.clear()
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
	last_address = addr
	var port := PORT
	if addr.count(":") == 1:
		port = int(addr.get_slice(":", 1))
		addr = addr.get_slice(":", 0)
	var err := peer.create_client(addr, port)
	if err != OK:
		status.emit("COULD NOT CONNECT (%s)" % error_string(err))
		peer = null
		return
	if secure:
		peer.host.dtls_client_setup(addr, TLSOptions.client_unsafe())
	multiplayer.multiplayer_peer = peer
	(multiplayer as SceneMultiplayer).server_relay = false
	active = true
	hosting = false
	_session_token = ""
	_session_token = str(_saved_sessions().get("%s|%s" % [last_address, my_name], "")).substr(0, 64)
	_host_said_bye = false
	status.emit("CONNECTING TO %s ..." % address)


func leave(reason := "") -> void:
	if active and peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		if hosting:
			if match_running:
				_abort.rpc()
			_bye.rpc()
		else:
			_client_bye.rpc_id(1)
		_drain()
	if peer != null:
		peer.close()
	_closing = false
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	peer = null
	var was := active
	active = false
	hosting = false
	match_running = false
	if reconnecting:
		reconnecting = false
		reconnect_state.emit("")
	roster.clear()
	info.clear()
	_ghosts.clear()
	_asked_name.clear()
	_handshake.clear()
	_tokens.clear()
	_rate.clear()
	_flood.clear()
	_dropping.clear()
	_countdown_left = -1.0
	_beacon = null
	_close_port()
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
				"max": MAX_PLAYERS, "running": match_running, "squad": squad, "bots": int(settings.get("bots", 63)),
				"locked": password != "", "secure": secure}
			_beacon.put_packet(JSON.stringify(beacon).to_utf8_buffer())
	if _listener != null:
		var changed := false
		while _listener.get_available_packet_count() > 0:
			var pkt := _listener.get_packet()
			var ip := _listener.get_packet_ip()
			if pkt.size() > 600:
				continue
			var data = JSON.parse_string(pkt.get_string_from_utf8())
			if data is Dictionary and data.get("game", "") == "blockroyale":
				data["name"] = _clean_name(str(data.get("name", "")))
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
	if reconnecting:
		_tick_reconnect(delta)
	if active and match_running:
		_tick_match(delta)
	if hosting and not _ghosts.is_empty():
		var now := Time.get_ticks_msec()
		for n in _ghosts.keys():
			if now > int(_ghosts[n]["until"]):
				var gid := int(_ghosts[n]["id"])
				_ghosts.erase(n)
				_system_chat("%s DID NOT COME BACK" % n)
				if game != null:
					game.net_player_left(gid)
	if hosting:
		_tick_guard(delta)
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

## ENet gives up on a peer after ~5 s without acks by default: a short WiFi
## dropout or a long hitch would end the match. Ride out up to ~20 s (and
## never more than 45 s) before calling the connection dead.
const TIMEOUT_LIMIT := 64
const TIMEOUT_MIN_MS := 20000
const TIMEOUT_MAX_MS := 45000


func _patient(pid: int) -> void:
	if peer == null:
		return
	var pp := peer.get_peer(pid)
	if pp != null:
		pp.set_timeout(TIMEOUT_LIMIT, TIMEOUT_MIN_MS, TIMEOUT_MAX_MS)


func _on_peer_connected(id: int) -> void:
	if not hosting:
		return
	_patient(id)
	var ip := _peer_ip(id)
	var now := Time.get_ticks_msec()
	if _bans.has(ip):
		_drop(id, "YOU ARE BANNED FROM THIS HOST")
		return
	if _fails.has(ip) and int(_fails[ip][0]) >= MAX_PASSWORD_FAILS and now < int(_fails[ip][1]):
		_drop(id, "TOO MANY WRONG PASSWORDS  ·  TRY AGAIN LATER")
		return
	# Nothing they say counts until they answer this.
	var nonce := _random_hex(16)
	_handshake[id] = {"t": now, "nonce": nonce, "ip": ip}
	_challenge.rpc_id(id, nonce, password != "")


func _on_peer_disconnected(id: int) -> void:
	if not hosting or _closing:
		return
	_handshake.erase(id)
	_rate.erase(id)
	_flood.erase(id)
	_dropping.erase(id)
	_loaded.erase(id)
	var token := str(_tokens.get(id, ""))
	_tokens.erase(id)
	if not roster.has(id):
		# Never got past the handshake: nobody to announce.
		return
	var name: String = roster.get(id, "PLAYER")
	var asked: String = _asked_name.get(id, name)
	_asked_name.erase(id)
	roster.erase(id)
	var old_info: Dictionary = info.get(id, {})
	info.erase(id)
	_send_roster()
	status.emit("%s LEFT" % name)
	if _countdown_left > 0.0:
		cancel_countdown()
	# Mid-match: hold their place for a while so they can come back (a
	# dropped connection reconnects on its own; a crashed game can rejoin).
	var meant := _leaving.has(id)
	_leaving.erase(id)
	if match_running and not meant and game != null and game.net_ghost_human(id):
		_ghosts[asked] = {"id": id, "until": Time.get_ticks_msec() + GHOST_MS, "name": name, "info": old_info, "token": token}
		_system_chat("%s LOST CONNECTION  ·  WAITING FOR THEM TO COME BACK" % name)
		return
	_system_chat("%s LEFT THE %s" % [name, "MATCH" if match_running else "LOBBY"])
	if match_running and game != null:
		game.net_player_left(id)


func _system_chat(text: String) -> void:
	_chat.rpc(0, "", text, true)
	chat.emit(0, "", text, true)


func _on_connected() -> void:
	_patient(1)
	# The host speaks first: it sends a challenge, we answer with _hello.
	if reconnecting:
		active = true
		status.emit("RECONNECTED  ·  CATCHING UP")
		return
	status.emit("CONNECTED  ·  WAITING FOR THE HOST")


## Client: the host's one-time challenge. Prove the password against it (the
## password itself is never sent) and introduce ourselves.
@rpc("authority", "call_remote", "reliable")
func _challenge(nonce: String, _locked: bool) -> void:
	if hosting or multiplayer.get_remote_sender_id() != 1:
		return
	var opts := {"proof": _proof(nonce.substr(0, 64), join_password), "token": _session_token}
	if reconnecting:
		# We kept playing while the line was down: only catch us up.
		opts["resume"] = true
		opts["match"] = _match_id
	_hello.rpc_id(1, my_name, VERSION, opts)


## Client: we are in. The token is our claim to this place if the line drops.
@rpc("authority", "call_remote", "reliable")
func _welcome(token: String) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_session_token = token.substr(0, 64)
	# Kept on disk too: a game that crashed can come back to its place.
	var all := _saved_sessions()
	all["%s|%s" % [last_address, my_name]] = _session_token
	var f := FileAccess.open("user://session.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(all))


## Tokens kept on disk, by "host|name" (several players may share a machine).
func _saved_sessions() -> Dictionary:
	var f := FileAccess.open("user://session.json", FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary and d.size() < 64:
			return d
	return {}


func _on_failed() -> void:
	if reconnecting:
		# Keep trying until the reconnect window runs out.
		if peer != null:
			peer.close()
		peer = null
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		return
	leave("")
	status.emit("CONNECTION FAILED")
	left_session.emit("CONNECTION FAILED")


var _host_said_bye := false
## Set while we shut our own connection down (no lobby updates then).
var _closing := false
## Host: clients that said they are leaving on purpose (no reconnect wait).
var _leaving: Dictionary = {}


## Let the goodbye actually arrive: ask every connection to close once its
## queued messages are through, and service the socket for a moment.
func _drain() -> void:
	if peer.host == null:
		return
	_closing = true
	var peers: Array = []
	for pp in peer.host.get_peers():
		if pp != null and (pp as ENetPacketPeer).is_active():
			(pp as ENetPacketPeer).peer_disconnect_later()
			peers.append(pp)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 700:
		peer.poll()
		var open := false
		for pp in peers:
			if (pp as ENetPacketPeer).get_state() != ENetPacketPeer.STATE_DISCONNECTED:
				open = true
		if not open:
			break
		OS.delay_msec(5)


@rpc("any_peer", "reliable")
func _client_bye() -> void:
	if hosting:
		_leaving[multiplayer.get_remote_sender_id()] = true


@rpc("authority", "call_remote", "reliable")
func _bye() -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_host_said_bye = true


func _on_server_gone() -> void:
	var why := "THE HOST LEFT THE GAME" if _host_said_bye else "LOST THE CONNECTION TO THE HOST"
	if not _host_said_bye and match_running and not reconnecting and game != null and game.net_can_reconnect():
		_begin_reconnect()
		return
	leave("")
	left_session.emit(why)


## Mid-match the host went quiet: keep playing locally and dial back in.
func _begin_reconnect() -> void:
	reconnecting = true
	_reco_left = RECONNECT_S
	_reco_try = 1.0
	if peer != null:
		peer.close()
	peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	# Nothing may be sent while the line is down.
	active = false
	match_running = false
	reconnect_state.emit("CONNECTION LOST  ·  RECONNECTING")


func _tick_reconnect(delta: float) -> void:
	_reco_left -= delta
	if _reco_left <= 0.0:
		reconnecting = false
		reconnect_state.emit("")
		leave("")
		left_session.emit("LOST THE CONNECTION TO THE HOST")
		return
	reconnect_state.emit("CONNECTION LOST  ·  RECONNECTING  %d" % int(ceil(_reco_left)))
	if peer != null:
		return
	_reco_try -= delta
	if _reco_try > 0.0:
		return
	_reco_try = 3.0
	peer = ENetMultiplayerPeer.new()
	var port := PORT
	var addr := last_address
	if addr.count(":") == 1:
		port = int(addr.get_slice(":", 1))
		addr = addr.get_slice(":", 0)
	if peer.create_client(addr, port) != OK:
		peer = null
		return
	if secure:
		peer.host.dtls_client_setup(addr, TLSOptions.client_unsafe())
	multiplayer.multiplayer_peer = peer
	(multiplayer as SceneMultiplayer).server_relay = false
	# Not "active" until the handshake completes: nothing may be sent before.
	hosting = false


@rpc("any_peer", "reliable")
func _hello(name: String, version: String, opts: Dictionary = {}) -> void:
	if not hosting:
		return
	var id := multiplayer.get_remote_sender_id()
	# Only someone we challenged, and only once.
	if not _handshake.has(id):
		return
	var hs: Dictionary = _handshake[id]
	_handshake.erase(id)
	if version != VERSION:
		_drop(id, "VERSION MISMATCH  ·  HOST RUNS %s" % VERSION)
		return
	if password != "" and not _same(str(opts.get("proof", "")), _proof(str(hs["nonce"]), password)):
		var ip := str(hs["ip"])
		var f: Array = _fails.get(ip, [0, 0])
		_fails[ip] = [int(f[0]) + 1, Time.get_ticks_msec() + FAIL_BAN_MS]
		_drop(id, "WRONG PASSWORD")
		return
	_fails.erase(str(hs["ip"]))
	if roster.size() >= MAX_PLAYERS:
		_drop(id, "THE GAME IS FULL")
		return
	var n := _clean_name(name)
	_patient(id)
	var token := _random_hex(16)
	# Coming back to a match in progress: take over the place we held. The
	# name alone is not enough; it takes the token we gave that player.
	var offered := str(opts.get("token", ""))
	# The same player dialling in again while their old line still looks
	# alive (their game crashed, or their network changed under them): the
	# token proves it is them, so the old line is dead. Close it now.
	if offered != "":
		for old in _tokens.keys():
			if int(old) != id and roster.has(old) and _same(offered, str(_tokens[old])):
				_on_peer_disconnected(int(old))
				_cut(int(old))
	if match_running and game != null:
		var gk := ""
		for k in _ghosts:
			if (k == n or str(_ghosts[k]["name"]) == n) and offered != "" and _same(offered, str(_ghosts[k].get("token", ""))):
				gk = k
		if gk != "":
			_tokens[id] = token
			_welcome.rpc_id(id, token)
			_resume(id, gk, bool(opts.get("resume", false)) and int(opts.get("match", 0)) == _match_id)
			return
		_asked_name[id] = n
	# Keep names unique so the kill feed makes sense.
	var base := n
	var k := 2
	while n in roster.values():
		n = "%s %d" % [base, k]
		k += 1
	if not _asked_name.has(id):
		_asked_name[id] = n
	roster[id] = n
	var used: Array = []
	for other in info:
		used.append(int(info[other]["color"]))
	var col := 0
	while col in used and col < COLORS.size() - 1:
		col += 1
	info[id] = {"ready": false, "color": col, "ping": 0}
	_tokens[id] = token
	_welcome.rpc_id(id, token)
	_send_roster()
	_chat.rpc(0, "", "%s JOINED THE LOBBY" % n, true)
	chat.emit(0, "", "%s JOINED THE LOBBY" % n, true)
	if match_running:
		_chat.rpc_id(id, 0, "", "A MATCH IS IN PROGRESS  ·  YOU WILL DROP IN WITH THE NEXT ONE", true)


## Host: a dropped player is back. Same name and colour, new peer id; a
## client that kept its game running just catches up, one that restarted
## gets the whole match rebuilt around its saved character.
func _resume(id: int, ghost_key: String, kept_state: bool) -> void:
	var g: Dictionary = _ghosts[ghost_key]
	_ghosts.erase(ghost_key)
	var old := int(g["id"])
	var n := str(g["name"])
	roster[id] = n
	_asked_name[id] = ghost_key
	var gi: Dictionary = g.get("info", {})
	info[id] = {"ready": true, "color": int(gi.get("color", 0)), "ping": 0}
	game.net_resume_human(old, id)
	_send_roster()
	_remap.rpc(old, id)
	if kept_state:
		_resync.rpc_id(id, game.net_resync_data())
	else:
		_setup.rpc_id(id, game.net_resume_setup(id))
	_system_chat("%s RECONNECTED" % n)
	if game.condemned_names.has(n):
		# Leaving does not shake the Warden off.
		var why := str(game.condemned_names[n])
		game.anticheat.mark_condemned(id, why)
		_ac_hunt.rpc_id(id, id, why)


@rpc("authority", "call_remote", "reliable")
func _remap(old: int, new: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	if game != null:
		game.net_remap_human(old, new)


@rpc("authority", "call_remote", "reliable")
func _resync(data: Dictionary) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	match_running = true
	if reconnecting:
		reconnecting = false
		reconnect_state.emit("")
	status.emit("")
	if game != null:
		game.net_apply_resync(data)


@rpc("authority", "reliable")
func _kick(reason: String) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_host_said_bye = true
	leave("")
	left_session.emit(reason.substr(0, 80))


# ------------------------------------------------------------- the guard --
## Host: is this a player we know, and are they within their message budget?
func _gate(id: int, kind: String) -> bool:
	if not roster.has(id) or _dropping.has(id):
		return false
	var now := Time.get_ticks_msec()
	var buckets: Dictionary = _rate.get(id, {})
	var lim: Array = RATES[kind]
	var b: Array = buckets.get(kind, [lim[1], now])
	var tokens := minf(float(lim[1]), float(b[0]) + float(now - int(b[1])) * 0.001 * float(lim[0]))
	var ok := tokens >= 1.0
	buckets[kind] = [tokens - 1.0 if ok else tokens, now]
	_rate[id] = buckets
	if not ok:
		_flood[id] = int(_flood.get(id, 0)) + 1
		if int(_flood[id]) > FLOOD_KICK:
			kick(id, "KICKED  ·  FLOODING THE HOST")
	return ok


## Host: every client but this one (the others a message is passed on to).
func _others(sender: int) -> Array:
	var out: Array = []
	for pid in roster:
		if int(pid) != 1 and int(pid) != sender and not _dropping.has(int(pid)):
			out.append(int(pid))
	return out


func _tick_guard(delta: float) -> void:
	var now := Time.get_ticks_msec()
	# Connected but silent: no handshake, no seat.
	for id in _handshake.keys():
		if now - int(_handshake[id]["t"]) > HELLO_TIMEOUT_MS:
			_handshake.erase(id)
			_cut(int(id))
	# Kicked peers get a moment to read why, then the line is cut.
	for id in _dropping.keys():
		if now >= int(_dropping[id]):
			_dropping.erase(id)
			_cut(int(id))
	_flood_t -= delta
	if _flood_t <= 0.0:
		_flood_t = 1.0
		for id in _flood.keys():
			_flood[id] = maxi(0, int(_flood[id]) - 30)


func _cut(id: int) -> void:
	if peer != null and peer.get_peer(id) != null:
		peer.disconnect_peer(id, true)


## Host: tell a peer why, then hang up on them.
func _drop(id: int, reason: String) -> void:
	_handshake.erase(id)
	_kick.rpc_id(id, reason)
	_dropping[id] = Time.get_ticks_msec() + 500


func _peer_ip(id: int) -> String:
	if peer == null:
		return ""
	var pp := peer.get_peer(id)
	return pp.get_remote_address() if pp != null else ""


## Host: remove a player. With `ban` their address stays shut out.
func kick(id: int, reason := "KICKED BY THE HOST", ban := false) -> void:
	if not hosting or id == 1 or not (roster.has(id) or _handshake.has(id)):
		return
	var who := str(roster.get(id, "PLAYER"))
	if ban:
		var ip := _peer_ip(id)
		if ip != "":
			_bans[ip] = who
			_save_bans()
	# They did not choose to go: no place is kept for them.
	_leaving[id] = true
	_drop(id, reason)
	_system_chat("%s WAS %s" % [who, "BANNED" if ban else "KICKED"])


func kick_name(n: String, ban := false) -> bool:
	var want := n.strip_edges().to_upper()
	for id in roster:
		if int(id) != 1 and str(roster[id]) == want:
			kick(int(id), "BANNED BY THE HOST" if ban else "KICKED BY THE HOST", ban)
			return true
	return false


func clear_bans() -> void:
	_bans.clear()
	_fails.clear()
	_save_bans()


func _load_bans() -> void:
	var f := FileAccess.open("user://bans.json", FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		_bans = d


func _save_bans() -> void:
	var f := FileAccess.open("user://bans.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_bans))


static func _random_hex(bytes: int) -> String:
	return Crypto.new().generate_random_bytes(bytes).hex_encode()


## Keyed hash of the host's challenge: proves the password without sending it.
static func _proof(nonce: String, pw: String) -> String:
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, ("blockroyale:" + pw).to_utf8_buffer(), nonce.to_utf8_buffer()).hex_encode()


## Compare without stopping at the first difference.
static func _same(a: String, b: String) -> bool:
	if a.length() != b.length():
		return false
	var diff := 0
	for i in a.length():
		diff |= a.unicode_at(i) ^ b.unicode_at(i)
	return diff == 0


## A name as it may appear anywhere: letters, digits, a few marks, 14 long.
static func _clean_name(raw: String) -> String:
	var out := ""
	for ch in raw.strip_edges().to_upper():
		var c := ch.unicode_at(0)
		if (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or ch in [" ", "_", "-", "."] or (c >= 0xC0 and c < 0x250):
			out += ch
	out = out.strip_edges().substr(0, 14)
	return out if out != "" else "PLAYER"


## Free text from a player: printable, no markup, limited length.
static func _clean_text(raw: String, limit: int) -> String:
	var out := ""
	for ch in raw.strip_edges().substr(0, limit * 2):
		var c := ch.unicode_at(0)
		if c < 32 or c == 127 or ch == "[" or ch == "]":
			continue
		out += ch
	return out.substr(0, limit)


static func _finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z) and absf(v.x) < 4000.0 and absf(v.z) < 4000.0 and absf(v.y) < 4000.0


## Host: a self-signed certificate (made once, kept) and encrypted transport.
func _dtls_server() -> bool:
	var key := CryptoKey.new()
	var cert := X509Certificate.new()
	var kp := "user://host.key"
	var cp := "user://host.crt"
	var have := FileAccess.file_exists(kp) and FileAccess.file_exists(cp) and key.load(kp) == OK and cert.load(cp) == OK
	if not have:
		var crypto := Crypto.new()
		key = crypto.generate_rsa(2048)
		cert = crypto.generate_self_signed_certificate(key, "CN=blockroyale,O=Block Royale,C=US", "20240101000000", "20540101000000")
		if key == null or cert == null:
			return false
		key.save(kp)
		cert.save(cp)
	return peer.host.dtls_server_setup(TLSOptions.server(key, cert)) == OK


# --------------------------------------------------------- internet play --
## Host: ask the router to pass our port through (UPnP), off the main thread.
## Sets public_address when it works; the lobby shows it.
func open_port() -> void:
	if _upnp_thread != null or not hosting:
		return
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_work.bind(true))


func _close_port() -> void:
	public_address = ""
	if _upnp_thread != null:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
		# Take the mapping down again, without holding the game up.
		var t := Thread.new()
		t.start(_upnp_work.bind(false))
		_upnp_closers.append(t)


var _upnp_closers: Array = []


func _upnp_work(open: bool) -> void:
	var upnp := UPNP.new()
	if upnp.discover(1500, 2, "InternetGatewayDevice") != UPNP.UPNP_RESULT_SUCCESS:
		if open:
			_upnp_done.call_deferred("")
		return
	var gw := upnp.get_gateway()
	if gw == null or not gw.is_valid_gateway():
		if open:
			_upnp_done.call_deferred("")
		return
	if not open:
		upnp.delete_port_mapping(PORT, "UDP")
		return
	var res := upnp.add_port_mapping(PORT, PORT, "Block Royale", "UDP", 0)
	_upnp_done.call_deferred(upnp.query_external_address() if res == UPNP.UPNP_RESULT_SUCCESS else "")


func _upnp_done(addr: String) -> void:
	if not hosting:
		return
	public_address = addr
	status.emit(("OPEN TO THE INTERNET  ·  %s" % addr) if addr != "" else "ROUTER DID NOT OPEN THE PORT  ·  FORWARD UDP %d BY HAND" % PORT)
	roster_changed.emit()


func _exit_tree() -> void:
	if _upnp_thread != null:
		_upnp_thread.wait_to_finish()
	for t in _upnp_closers:
		(t as Thread).wait_to_finish()


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
	if not _gate(id, "misc"):
		return
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
	if multiplayer.get_remote_sender_id() != 1:
		return
	roster.clear()
	info.clear()
	for e in list:
		roster[int(e[0])] = _clean_name(str(e[1]))
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
	if multiplayer.get_remote_sender_id() != 1:
		return
	for id in pings:
		if info.has(id) and int(id) != my_id():
			info[id]["ping"] = int(pings[id])
	pings_updated.emit()


# -------------------------------------------------------------------- chat --

func send_chat(text: String) -> void:
	var t := text.strip_edges().substr(0, 140)
	if t == "" or not active:
		return
	t = _clean_text(t, 140)
	if t == "":
		return
	if hosting and t.begins_with("/"):
		_host_command(t)
		return
	if hosting:
		_chat.rpc(my_id(), my_name, t, false)
	else:
		_chat.rpc_id(1, my_id(), my_name, t, false)
	chat.emit(my_id(), my_name, t, false)


## Host commands typed into the chat: /kick NAME, /ban NAME, /unban,
## /password [NEW], /open.
func _host_command(t: String) -> void:
	var cmd := t.get_slice(" ", 0).to_lower()
	var arg := t.substr(cmd.length()).strip_edges()
	var say := ""
	match cmd:
		"/kick":
			say = "" if kick_name(arg) else "NOBODY CALLED %s" % arg.to_upper()
		"/ban":
			say = "" if kick_name(arg, true) else "NOBODY CALLED %s" % arg.to_upper()
		"/unban":
			clear_bans()
			say = "BAN LIST CLEARED"
		"/password":
			password = arg.substr(0, 32)
			say = "PASSWORD SET" if password != "" else "PASSWORD REMOVED  ·  THE LOBBY IS OPEN"
			roster_changed.emit()
		"/open":
			open_port()
			say = "ASKING THE ROUTER TO OPEN UDP %d ..." % PORT
		_:
			say = "COMMANDS:  /KICK NAME   /BAN NAME   /UNBAN   /PASSWORD [NEW]   /OPEN"
	if say != "":
		chat.emit(0, "", say, true)


@rpc("any_peer", "call_remote", "reliable")
func _chat(from_id: int, name: String, text: String, system: bool) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if hosting:
		# A client speaks for itself only, in plain text, and not too often.
		if not _gate(sender, "chat"):
			return
		from_id = sender
		name = str(roster.get(sender, "PLAYER"))
		text = _clean_text(text, 140)
		system = false
		if text == "":
			return
		for pid in _others(sender):
			_chat.rpc_id(pid, from_id, name, text, false)
	elif sender != 1:
		return
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
	if multiplayer.get_remote_sender_id() != 1:
		return
	countdown.emit(seconds)


# ----------------------------------------------------------------- markers --

func send_marker(pos: Vector3) -> void:
	if active:
		if hosting:
			_marker.rpc(my_id(), pos)
		else:
			_marker.rpc_id(1, my_id(), pos)
	marker.emit(my_id(), pos)


@rpc("any_peer", "call_remote", "reliable")
func _marker(who: int, pos: Vector3) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if hosting:
		if not _gate(sender, "marker") or not _finite(pos):
			return
		who = sender
		for pid in _others(sender):
			_marker.rpc_id(pid, who, pos)
	elif sender != 1:
		return
	marker.emit(who, pos)


# ------------------------------------------------------------------- match --

## Host: everything a client needs to build the same match.
func send_setup(setup: Dictionary) -> void:
	match_running = true
	_ghosts.clear()
	_match_id = int(setup.get("match_id", 0))
	_countdown_left = -1.0
	# Everyone readies up again for the next one.
	for id in info:
		if int(id) != 1:
			info[id]["ready"] = false
	_shots.clear()
	_loot_out.clear()
	_loaded.clear()
	_setup.rpc(setup)


var _match_id := 0


@rpc("authority", "call_remote", "reliable")
func _setup(setup: Dictionary) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	match_running = true
	_match_id = int(setup.get("match_id", 0))
	if reconnecting:
		reconnecting = false
		reconnect_state.emit("")
	for id in info:
		if int(id) != 1:
			info[id]["ready"] = false
	_shots.clear()
	_loot_out.clear()
	if game != null:
		game.net_start_match(setup)


@rpc("authority", "call_remote", "reliable")
func _abort() -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	match_running = false
	if game != null:
		game.net_abort()


func _tick_match(delta: float) -> void:
	if game == null:
		return
	# Clients keep the host up to date with what they carry, so a player
	# whose game crashes can rejoin with their kit.
	if not hosting:
		_inv_t -= delta
		if _inv_t <= 0.0:
			_inv_t = 3.0
			var inv: Dictionary = game.net_inventory()
			if not inv.is_empty():
				_inv.rpc_id(1, inv)
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
				for pid in _loaded:
					if roster.has(pid):
						_snap.rpc_id(int(pid), bp.slice(off, off + per), off / 8, snap[1] if off == 0 else PackedFloat32Array(), snap[2] if off == 0 else PackedFloat32Array())
				off += per
				if off >= bp.size():
					break
	_state_t -= delta
	if _state_t <= 0.0:
		_state_t = 1.0 / STATE_RATE
		var st = game.net_player_state()
		if st != null:
			if hosting:
				for pid in _loaded:
					if roster.has(pid):
						_pstate.rpc_id(int(pid), 1, st)
			else:
				_pstate.rpc_id(1, my_id(), st)
	# Shot effects (tracers, sound) at up to 30 Hz, unreliable, and each
	# client only hears shots within earshot of where they are.
	_shot_t -= delta
	if _shot_t <= 0.0 and (not _shots.is_empty() or not _relay.is_empty()):
		_shot_t = 1.0 / 30.0
		if hosting:
			for id in roster:
				var pid := int(id)
				if pid == 1 or not _loaded.has(pid):
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
		if hosting:
			_loot_spawned.rpc(1, _loot_out)
		else:
			_loot_spawned.rpc_id(1, my_id(), _loot_out)
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
			if hosting:
				for pid in _loaded:
					if roster.has(pid):
						_vstate.rpc_id(int(pid), 1, vs.slice(i, i + 12))
			else:
				_vstate.rpc_id(1, my_id(), vs.slice(i, i + 12))
			i += 12


@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _inv(d: Dictionary) -> void:
	if not hosting or game == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if _gate(sender, "inv") and var_to_bytes(d).size() < 4096:
		game.net_store_inventory(sender, d)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _snap(bots: PackedFloat32Array, first: int, zone: PackedFloat32Array, misc: PackedFloat32Array) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	if game != null:
		game.net_apply_snapshot(bots, zone, misc, first)


@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _pstate(who: int, st: Array) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if hosting:
		if not _gate(sender, "pstate") or not _pstate_ok(st):
			return
		who = sender
		_loaded[sender] = true
		for pid in _others(sender):
			if _loaded.has(pid):
				_pstate.rpc_id(pid, who, st)
	elif sender != 1:
		return
	if game != null:
		game.net_apply_player_state(who, st)


## The shape of a player state: [pos, yaw, pitch, state, flags, weapon, vest,
## helmet, hp, kills, damage, vehicle, seat], all of it sane.
static func _pstate_ok(st: Array) -> bool:
	if st.size() != 13:
		return false
	if typeof(st[0]) != TYPE_VECTOR3 or not _finite(st[0]):
		return false
	for i in [1, 2, 8, 10]:
		if not (typeof(st[i]) in [TYPE_FLOAT, TYPE_INT]) or not is_finite(float(st[i])):
			return false
	for i in [3, 4, 6, 7, 9, 11, 12]:
		if typeof(st[i]) != TYPE_INT:
			return false
	if typeof(st[5]) != TYPE_STRING or (st[5] as String).length() > 24:
		return false
	return float(st[8]) <= 100.5 and int(st[6]) >= 0 and int(st[6]) <= 3 and int(st[7]) >= 0 and int(st[7]) <= 3


var _relay: Array = []
var _shot_t := 0.0


func queue_shot(key: String, from: Vector3, dir: Vector3, weapon: String, vis: Vector3, shot_id: int) -> void:
	if not active:
		return
	_shots.append([key, from, dir, weapon, vis, shot_id])


@rpc("any_peer", "call_remote", "unreliable", 4)
func _shot_batch(list: Array) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if hosting:
		if not _gate(sender, "shots") or list.size() > 12:
			return
		# A client fires as itself and nobody else.
		var mine := "p%d" % sender
		var clean: Array = []
		for e in list:
			if not (e is Array) or (e as Array).size() != 6:
				return
			if typeof(e[1]) != TYPE_VECTOR3 or typeof(e[2]) != TYPE_VECTOR3 or typeof(e[4]) != TYPE_VECTOR3 or typeof(e[3]) != TYPE_STRING or typeof(e[5]) != TYPE_INT:
				return
			if not _finite(e[1]) or not _finite(e[4]) or not is_finite((e[2] as Vector3).length()) or not Weapons.ORDER.has(e[3]):
				return
			clean.append([mine, e[1], (e[2] as Vector3).normalized(), e[3], e[4], e[5]])
		list = clean
		# The host passes a client's shots on to the other clients near them.
		for e in list:
			_relay.append([sender, e])
	elif sender != 1:
		return
	if game != null:
		game.net_remote_shots(list)


func send_grenade(key: String, from: Vector3, vel: Vector3) -> void:
	if not active:
		return
	if hosting:
		_grenade.rpc(key, from, vel)
	else:
		_grenade.rpc_id(1, key, from, vel)


@rpc("any_peer", "call_remote", "reliable")
func _grenade(key: String, from: Vector3, vel: Vector3) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if hosting:
		if not _gate(sender, "grenade") or not _finite(from) or not is_finite(vel.length()) or vel.length() > 70.0:
			return
		# Thrown by the sender, from where the sender is.
		key = "p%d" % sender
		var where: Vector3 = game.net_peer_position(sender) if game != null else Vector3.INF
		if where != Vector3.INF and where.distance_to(from) > 12.0:
			return
		for pid in _others(sender):
			_grenade.rpc_id(pid, key, from, vel)
	elif sender != 1:
		return
	if game != null:
		game.net_remote_grenade(key, from, vel)


## A client hit a bot: the host applies it to the real one.
func send_bot_hit(bot_index: int, dmg: float, pos: Vector3, headshot: bool) -> void:
	if not active:
		return
	_bot_hit.rpc_id(1, bot_index, dmg, pos, headshot)


@rpc("any_peer", "reliable")
func _bot_hit(bot_index: int, dmg: float, pos: Vector3, headshot: bool) -> void:
	if not hosting or game == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if _gate(sender, "hit") and is_finite(dmg) and dmg > 0.0 and _finite(pos):
		game.net_bot_hit(sender, bot_index, dmg, pos, headshot)


## Someone hit a human: tell that human's machine.
func send_player_hit(peer_id: int, dmg: float, pos: Vector3, headshot: bool, source_key: String) -> void:
	if not active:
		return
	if peer_id == my_id():
		return
	if hosting:
		_player_hit.rpc_id(peer_id, peer_id, dmg, pos, headshot, source_key)
	else:
		# Through the host, who checks the hit before the victim hears of it.
		_player_hit.rpc_id(1, peer_id, dmg, pos, headshot, source_key)


@rpc("any_peer", "reliable")
func _player_hit(victim: int, dmg: float, pos: Vector3, headshot: bool, source_key: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if hosting:
		if game == null or not _gate(sender, "hit") or not is_finite(dmg) or not _finite(pos):
			return
		# The host decides how much of the claimed hit stands.
		dmg = game.net_check_hit(sender, victim, dmg, pos)
		if dmg <= 0.0:
			return
		source_key = "p%d" % sender
		if victim != 1:
			if roster.has(victim):
				_player_hit.rpc_id(victim, victim, dmg, pos, headshot, source_key)
			return
	elif sender != 1:
		return
	if game != null:
		game.net_player_hit(dmg, pos, headshot, source_key)


var _pending: Array = []


## Sent once the line is back up after a reconnect.
func flush_pending() -> void:
	var p := _pending
	_pending = []
	for e in p:
		if e[0] == "death":
			report_death(e[1], e[2], e[3])
		elif e[0] == "taken":
			send_loot_taken(int(e[1]))


func report_death(killer_key: String, killer_name: String, weapon: String) -> void:
	if not active:
		if reconnecting:
			_pending.append(["death", killer_key, killer_name, weapon])
		return
	if hosting:
		game.net_human_died(1, killer_key, killer_name, weapon)
	else:
		_died.rpc_id(1, killer_key, killer_name, weapon)


@rpc("any_peer", "reliable")
func _died(killer_key: String, killer_name: String, weapon: String) -> void:
	if not hosting or game == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if _gate(sender, "misc"):
		game.net_human_died(sender, _clean_text(killer_key, 12), _clean_name(killer_name) if killer_name != "" else "", _clean_text(weapon, 20))


func send_elim(e: Dictionary) -> void:
	if not active:
		return
	_elim.rpc(e)


@rpc("authority", "call_remote", "reliable")
func _elim(e: Dictionary) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	if game != null:
		game.net_elim(e)


func new_loot_id() -> int:
	_loot_seq += 1
	return (my_id() % 2000) * 1000000 + _loot_seq


func queue_loot(entry: Array) -> void:
	if not active:
		return
	_loot_out.append(entry)


@rpc("any_peer", "call_remote", "reliable")
func _loot_spawned(who: int, list: Array) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if hosting:
		if game == null or not _gate(sender, "loot") or list.size() > 64:
			return
		# Drops carry ids from the sender's own range and land near them.
		var lo := (sender % 2000) * 1000000
		var where: Vector3 = game.net_peer_position(sender)
		for e in list:
			if not (e is Array) or (e as Array).size() < 6 or typeof(e[0]) != TYPE_INT or typeof(e[3]) != TYPE_VECTOR3:
				return
			if int(e[0]) <= lo or int(e[0]) >= lo + 1000000 or not _finite(e[3]):
				return
			if typeof(e[1]) != TYPE_STRING or typeof(e[2]) != TYPE_STRING or (e[1] as String).length() > 24 or (e[2] as String).length() > 32:
				return
			if where != Vector3.INF and where.distance_to(e[3]) > 40.0:
				return
		who = sender
		for pid in _others(sender):
			_loot_spawned.rpc_id(pid, who, list)
	elif sender != 1:
		return
	if game != null:
		game.net_loot_spawned(list)


func send_loot_taken(id: int) -> void:
	if not active:
		if reconnecting:
			_pending.append(["taken", id])
		return
	if hosting:
		_loot_taken.rpc(1, id)
	else:
		_loot_taken.rpc_id(1, my_id(), id)


@rpc("any_peer", "call_remote", "reliable")
func _loot_taken(who: int, id: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if hosting:
		# Only what exists, and only from within reach.
		if game == null or not _gate(sender, "loot") or not game.net_loot_reachable(sender, id):
			return
		who = sender
		for pid in _others(sender):
			_loot_taken.rpc_id(pid, who, id)
	elif sender != 1:
		return
	if game != null:
		game.net_loot_taken(id)


@rpc("any_peer", "call_remote", "unreliable_ordered", 3)
func _vstate(who: int, list: Array) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if hosting:
		if game == null or not _gate(sender, "vstate") or list.size() > 16:
			return
		# Only the jeeps this client is in charge of.
		list = game.net_own_vehicle_states(sender, list)
		if list.is_empty():
			return
		who = sender
		for pid in _others(sender):
			if _loaded.has(pid):
				_vstate.rpc_id(pid, who, list)
	elif sender != 1:
		return
	if game != null:
		game.net_apply_vehicle_states(list)


func send_vehicle_owner(id: int) -> void:
	if not active:
		return
	if hosting:
		_vowner.rpc(1, id)
	else:
		_vowner.rpc_id(1, my_id(), id)


@rpc("any_peer", "call_remote", "reliable")
func _vowner(who: int, id: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if hosting:
		# You take the wheel of a jeep you are standing at.
		if game == null or not _gate(sender, "veh") or not game.net_vehicle_reachable(sender, id):
			return
		who = sender
		for pid in _others(sender):
			_vowner.rpc_id(pid, who, id)
	elif sender != 1:
		return
	if game != null:
		game.net_vehicle_owner(id, who)


func send_vehicle_hit(id: int, amount: float) -> void:
	if not active:
		return
	if hosting:
		_vhit.rpc(id, amount)
	else:
		_vhit.rpc_id(1, id, amount)


@rpc("any_peer", "call_remote", "reliable")
func _vhit(id: int, amount: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if hosting:
		if not _gate(sender, "veh") or not is_finite(amount) or amount <= 0.0:
			return
		amount = minf(amount, 400.0)
		for pid in _others(sender):
			_vhit.rpc_id(pid, id, amount)
	elif sender != 1:
		return
	if game != null:
		game.net_vehicle_hit_received(id, amount)


func send_vehicle_destroyed(id: int) -> void:
	if not active:
		return
	if hosting:
		_vdestroyed.rpc(id)
	else:
		_vdestroyed.rpc_id(1, id)


@rpc("any_peer", "call_remote", "reliable")
func _vdestroyed(id: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if hosting:
		# Only the machine simulating a jeep can say it blew up.
		if game == null or not _gate(sender, "veh") or not game.net_vehicle_owned_by(sender, id):
			return
		for pid in _others(sender):
			_vdestroyed.rpc_id(pid, id)
	elif sender != 1:
		return
	if game != null:
		game.net_vehicle_destroyed_received(id)


## Anti-cheat: we caught ourselves (our own machine saw the cheat).
func send_self_condemned(reason: String) -> void:
	if not active:
		return
	if hosting:
		_announce_hunt(1, reason)
	else:
		_ac_self.rpc_id(1, reason)


@rpc("any_peer", "reliable")
func _ac_self(reason: String) -> void:
	if not hosting or game == null:
		return
	var pid := multiplayer.get_remote_sender_id()
	if not _gate(pid, "misc"):
		return
	reason = _clean_text(reason, 60)
	game.anticheat.mark_condemned(pid, reason)
	game.condemned_names[str(roster.get(pid, ""))] = reason
	_announce_hunt(pid, reason)
	game._hunt_other(pid, reason)


func _announce_hunt(pid: int, reason: String) -> void:
	for id in multiplayer.get_peers():
		if id != pid:
			_ac_hunt.rpc_id(id, pid, reason)


## Host: the anti-cheat caught a client. Everyone is told; the cheater's own
## machine sends the Warden.
func send_hunt(pid: int, reason: String) -> void:
	if not active or not hosting:
		return
	for id in multiplayer.get_peers():
		_ac_hunt.rpc_id(id, pid, reason)


@rpc("authority", "call_remote", "reliable")
func _ac_hunt(pid: int, reason: String) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	if game == null:
		return
	if pid == my_id():
		game.anticheat.mark_condemned(0, reason)
		game._hunt_me(reason)
	else:
		game.anticheat.mark_condemned(pid, reason)
		game._hunt_other(pid, reason)


func send_airdrop(p: Vector2, ground: float) -> void:
	if not active:
		return
	_airdrop.rpc(p, ground)


@rpc("authority", "call_remote", "reliable")
func _airdrop(p: Vector2, ground: float) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	if game != null:
		game.net_airdrop(p, ground)


func send_match_over(winner_key: String, winner_name: String, squad_win: bool) -> void:
	if not active:
		return
	_match_over.rpc(winner_key, winner_name, squad_win)


@rpc("authority", "call_remote", "reliable")
func _match_over(winner_key: String, winner_name: String, squad_win: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	if game != null:
		game.net_match_over(winner_key, winner_name, squad_win)
