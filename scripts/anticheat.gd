extends Node
class_name AntiCheat

## Watches for cheating and sends the Warden after cheaters.
##
## Every machine watches its own player (a cheat runs on the cheater's own
## PC, so that is where it shows first):
##   * game clock against the system clock (speed hacks), engine time scale
##     and physics rate
##   * movement: sustained speed no legs can reach, teleports, hovering
##   * trigger: more shots per second than the gun cycles, magazines that
##     refill themselves, more rounds in a magazine than it holds
##   * health, armour, boost and items above their limits; weapon stats
##     edited in memory
##   * aim: the camera snapping onto a target and hitting, again and again
## The host also watches every client from the network: impossible speed
## and teleports, hits that are too strong, too far or through solid ground,
## and kill streaks no human manages.
##
## Blatant cheats are caught at once; anything a skilled or lucky player
## could do once has to repeat before it counts. Then the Warden comes.

signal condemned(who: int, reason: String)

var game: Node
var enabled := true
## Strikes per player (0 = us): [[msec, weight, reason], ...].
var _strikes: Dictionary = {}
var _condemned: Dictionary = {}
var _log: Array = []

# Local watch state.
var _hist: Array = []          # [msec, pos] of our player, ground mode only
var _last_pos := Vector3.INF
var _mode_t := 0.0
var _last_mode := -1
var _hover_t := 0.0
var _clock_ticks := 0
var _clock_unix := 0.0
var _clock_bad := 0
var _shots: Dictionary = {}    # weapon id -> [msec, ...]
var _mag_after: Dictionary = {}
var _inv_dirty := true
var _snap_events: Array = []
var _yaw_prev := 0.0
var _snap_at := -1.0
var _check_t := 0.0
var _weapon_sig := 0
var _grace := 0.0
## Simulated milliseconds (game time), for the local movement/trigger checks.
var _sim_ms := 0.0

# Host watch state per peer.
var _peer: Dictionary = {}


func setup(p_game: Node) -> void:
	game = p_game
	var args := OS.get_cmdline_user_args()
	# Automated tests teleport and fire on script: they would all be flagged.
	for a in args:
		if a.begins_with("--") and a != "--cheattest":
			enabled = false
	if OS.get_environment("ANTICHEAT") == "1" or args.has("--cheattest"):
		enabled = true
	_weapon_sig = _weapons_hash()
	_clock_ticks = Time.get_ticks_usec()
	_clock_unix = Time.get_unix_time_from_system()


func reset_match() -> void:
	_hist.clear()
	_last_pos = Vector3.INF
	_hover_t = 0.0
	_shots.clear()
	_mag_after.clear()
	_snap_events.clear()
	_peer.clear()
	_grace = 5.0
	_strikes.erase(0)
	if game != null and game.player != null and not game.player.inventory_changed.is_connected(_on_inv):
		game.player.inventory_changed.connect(_on_inv)


## A legitimate jump in position is coming (respawn, rejoin, getting out).
func grace(seconds: float) -> void:
	_grace = maxf(_grace, seconds)
	_hist.clear()
	_last_pos = Vector3.INF


func _on_inv() -> void:
	_mag_after.clear()


func is_condemned(who: int) -> bool:
	return _condemned.has(who)


# ------------------------------------------------------------------ strikes --
func strike(who: int, weight: int, reason: String) -> void:
	if not enabled or _condemned.has(who):
		return
	var now := Time.get_ticks_msec()
	if not _strikes.has(who):
		_strikes[who] = []
	var list: Array = _strikes[who]
	list.append([now, weight, reason])
	var score := 0
	for e in list.duplicate():
		if now - int(e[0]) > 90000:
			list.erase(e)
		else:
			score += int(e[1])
	_log.append("%s strike %d (%s) -> %d" % [_who_name(who), weight, reason, score])
	print("[anticheat] %s strike +%d: %s (score %d)" % [_who_name(who), weight, reason, score])
	if score >= 3:
		_condemn(who, reason)


func _who_name(who: int) -> String:
	if who == 0 or (game != null and game.net != null and who == game.net.my_id()):
		return "YOU"
	if game != null and game.net != null:
		return str(game.net.roster.get(who, "PLAYER %d" % who))
	return str(who)


func _condemn(who: int, reason: String) -> void:
	_condemned[who] = reason
	condemned.emit(who, reason)
	if game != null and game.has_method("on_cheater_condemned"):
		game.on_cheater_condemned(who, reason)


## Network: the host says this player is condemned (or we told it ourselves).
func mark_condemned(who: int, reason: String) -> void:
	_condemned[who] = reason


# ---------------------------------------------------------- local watching --
func _physics_process(delta: float) -> void:
	if not enabled or game == null or game.player == null:
		return
	if _condemned.has(0):
		return
	var p: Player = game.player
	if not p.alive or game.phase != "playing":
		_last_pos = Vector3.INF
		return
	_grace = maxf(0.0, _grace - delta)
	_sim_ms += delta * 1000.0
	if p.mode != _last_mode:
		_last_mode = p.mode
		_mode_t = 0.0
		_hist.clear()
		_last_pos = Vector3.INF
	_mode_t += delta
	_watch_clock()
	_watch_movement(p, delta)
	_watch_aim(p)
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 0.5
		_watch_state(p)


func _watch_clock() -> void:
	if Engine.time_scale < 0.99 or Engine.time_scale > 1.01:
		strike(0, 3, "time scale changed")
		return
	if Engine.physics_ticks_per_second != 60:
		strike(0, 3, "physics rate changed")
		return
	var now := Time.get_ticks_usec()
	var dt_ticks := float(now - _clock_ticks) / 1000000.0
	if dt_ticks < 3.0:
		return
	var nu := Time.get_unix_time_from_system()
	var dt_unix := nu - _clock_unix
	_clock_ticks = now
	_clock_unix = nu
	if dt_unix <= 0.0:
		return
	var ratio := dt_ticks / dt_unix
	# A speed hack makes the game's clock outrun the wall clock (or lag it).
	if ratio > 1.3 or ratio < 0.7:
		_clock_bad += 1
		if _clock_bad >= 2:
			strike(0, 3, "speed hack (game clock %.2fx)" % ratio)
	else:
		_clock_bad = 0


func _watch_movement(p: Player, delta: float) -> void:
	if p.mode != Player.Mode.GROUND or p.vehicle != null or not p._mantle.is_empty() or _grace > 0.0 or _mode_t < 1.0:
		_last_pos = Vector3.INF
		_hist.clear()
		return
	var pos := p.global_position
	var now := int(_sim_ms)
	if _last_pos != Vector3.INF:
		var step := Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length()
		# Nothing moves a body 6 m in one physics tick on foot.
		if step > 6.0:
			strike(0, 3, "teleport (%.0f m in one tick)" % step)
	_last_pos = pos
	_hist.append([now, pos])
	while _hist.size() > 0 and now - int(_hist[0][0]) > 2000:
		_hist.pop_front()
	if _hist.size() > 20 and now - int(_hist[0][0]) > 1500:
		var a: Vector3 = _hist[0][1]
		var span := float(now - int(_hist[0][0])) / 1000.0
		var v := Vector2(pos.x - a.x, pos.z - a.z).length() / span
		# Sprinting with full boost is under 10 m/s; give knock-backs room.
		if v > 15.0 and not p.swimming:
			strike(0, 3, "speed hack (%.1f m/s on foot)" % v)
			_hist.clear()
	# Hovering: off the ground, not falling, for seconds.
	if not p.is_on_floor() and not p.swimming and absf(p.velocity.y) < 1.2:
		var gy: float = game.terrain.height_at(pos.x, pos.z)
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.2, pos + Vector3.DOWN * 4.0, 1)
		q.exclude = [p.get_rid()]
		var floor_hit := p.get_world_3d().direct_space_state.intersect_ray(q)
		if floor_hit.is_empty() and pos.y - gy > 3.5:
			_hover_t += delta
			if _hover_t > 2.5:
				strike(0, 3, "flying")
				_hover_t = 0.0
		else:
			_hover_t = 0.0
	else:
		_hover_t = 0.0


func _watch_state(p: Player) -> void:
	if p.hp > 100.5 or p.armor > 100.5 or p.boost > 100.5:
		strike(0, 3, "health or armour edited")
	if p.meds > Player.MAX_MEDS or p.bandages > Player.MAX_BANDAGES or p.energy > Player.MAX_ENERGY or p.grenades > Player.MAX_GRENADES:
		strike(0, 3, "items over the limit")
	if p.has_gun() and p.current_mag() > p.mag_size():
		strike(0, 3, "magazine over capacity")
	for cal in p.ammo:
		if int(p.ammo[cal]) > 999:
			strike(0, 3, "ammo edited")
	var sig := _weapons_hash()
	if sig != _weapon_sig:
		strike(0, 3, "weapon stats edited")
		_weapon_sig = sig


func _weapons_hash() -> int:
	var h := 0
	for id in Weapons.ORDER:
		var d: Dictionary = Weapons.def(id)
		h = hash([h, d.get("damage"), d.get("rpm"), d.get("recoil"), d.get("spread"), d.get("mag"), d.get("velocity"), d.get("head")])
	return h


## The trigger: called by the player for every shot.
func on_shot(id: String, mag_before: int, mag_after: int) -> void:
	if not enabled or _condemned.has(0):
		return
	var now := int(_sim_ms)
	if not _shots.has(id):
		_shots[id] = []
	var list: Array = _shots[id]
	list.append(now)
	while list.size() > 0 and now - int(list[0]) > 1000:
		list.pop_front()
	var rpm := float(Weapons.def(id).get("rpm", 600.0))
	var allowed := rpm / 60.0 * 1.35 + 2.0
	if float(list.size()) > allowed:
		strike(0, 3, "rapid fire (%d shots/s, gun does %.0f)" % [list.size(), rpm / 60.0])
		list.clear()
	# The magazine must not refill itself between shots.
	if _mag_after.has(id) and mag_before > int(_mag_after[id]):
		strike(0, 3, "infinite ammo")
	_mag_after[id] = mag_after


func on_reload() -> void:
	_mag_after.clear()


## Aim snapping: the view jumps far in one tick and the shot lands.
func _watch_aim(p: Player) -> void:
	var dy := absf(wrapf(p.yaw - _yaw_prev, -PI, PI))
	_yaw_prev = p.yaw
	if dy > deg_to_rad(55.0):
		_snap_at = _sim_ms


func on_local_hit(dist: float, headshot: bool) -> void:
	if not enabled or _snap_at < 0.0:
		return
	var now := int(_sim_ms)
	if now - _snap_at < 120 and dist > 25.0 and headshot:
		_snap_events.append(now)
		_snap_at = -1.0
		while _snap_events.size() > 0 and now - int(_snap_events[0]) > 30000:
			_snap_events.pop_front()
		if _snap_events.size() >= 4:
			strike(0, 2, "aimbot (snap-to-head %d times)" % _snap_events.size())
			_snap_events.clear()


# ------------------------------------------------------- host-side watching --
func _pw(pid: int) -> Dictionary:
	if not _peer.has(pid):
		_peer[pid] = {"pos": Vector3.INF, "t": 0, "hist": [], "los": [], "kills": [], "grace": Time.get_ticks_msec() + 6000}
	return _peer[pid]


func peer_grace(pid: int, ms := 6000) -> void:
	var w := _pw(pid)
	w["grace"] = Time.get_ticks_msec() + ms
	w["hist"] = []
	w["pos"] = Vector3.INF


## Host: a client's reported position (ground state, not in a vehicle).
func host_peer_state(pid: int, pos: Vector3, on_ground: bool, seated: bool) -> void:
	if not enabled or _condemned.has(pid):
		return
	var w := _pw(pid)
	var now := Time.get_ticks_msec()
	if not on_ground or seated or now < int(w["grace"]):
		w["pos"] = Vector3.INF
		w["hist"] = []
		return
	var last: Vector3 = w["pos"]
	if last != Vector3.INF:
		var dt := float(now - int(w["t"])) / 1000.0
		var step := Vector2(pos.x - last.x, pos.z - last.z).length()
		if step > 40.0 and dt < 0.6:
			strike(pid, 3, "teleport (%.0f m)" % step)
	w["pos"] = pos
	w["t"] = now
	var hist: Array = w["hist"]
	hist.append([now, pos])
	while hist.size() > 0 and now - int(hist[0][0]) > 3000:
		hist.pop_front()
	if hist.size() > 30 and now - int(hist[0][0]) > 2500:
		var a: Vector3 = hist[0][1]
		var v := Vector2(pos.x - a.x, pos.z - a.z).length() / (float(now - int(hist[0][0])) / 1000.0)
		if v > 16.0:
			strike(pid, 3, "speed hack (%.1f m/s on foot)" % v)
			w["hist"] = []


## Host: a client says it hit one of our bots.
func host_peer_hit(pid: int, shooter_pos: Vector3, target_pos: Vector3, dmg: float, world: World3D) -> void:
	if not enabled or _condemned.has(pid):
		return
	if dmg > _max_hit():
		strike(pid, 3, "damage hack (%.0f in one hit)" % dmg)
		return
	if shooter_pos == Vector3.INF:
		return
	var d := shooter_pos.distance_to(target_pos)
	if d > 1750.0:
		strike(pid, 3, "hit from %.0f m away" % d)
		return
	# Through solid ground or walls: no line from anywhere the shooter could
	# have been (their position here lags, they may be leaning or peeking)
	# to the target's head or chest.
	var space := world.direct_space_state
	var side := (target_pos - shooter_pos).cross(Vector3.UP).normalized()
	var seen := false
	for off in [Vector3.ZERO, side * 1.2, -side * 1.2, Vector3.UP * 0.6]:
		var eye: Vector3 = shooter_pos + Vector3.UP * 1.55 + off
		for hgt in [1.1, 1.6]:
			var q := PhysicsRayQueryParameters3D.create(eye, target_pos + Vector3.UP * hgt, 1)
			var hit := space.intersect_ray(q)
			if hit.is_empty() or Vector3(hit["position"]).distance_to(target_pos) <= 2.5:
				seen = true
				break
		if seen:
			break
	if not seen and d > 15.0:
		var w := _pw(pid)
		var los: Array = w["los"]
		var now := Time.get_ticks_msec()
		los.append(now)
		while los.size() > 0 and now - int(los[0]) > 30000:
			los.pop_front()
		if los.size() >= 8:
			strike(pid, 1, "shooting through walls")
			w["los"] = []


## Host: kill credited to a client.
func host_peer_kill(pid: int) -> void:
	if not enabled or _condemned.has(pid):
		return
	var w := _pw(pid)
	var k: Array = w["kills"]
	var now := Time.get_ticks_msec()
	k.append(now)
	while k.size() > 0 and now - int(k[0]) > 10000:
		k.pop_front()
	if k.size() >= 7:
		strike(pid, 2, "%d kills in 10 seconds" % k.size())
		w["kills"] = []


## The hardest legal hit in the game (strongest gun, headshot), with room.
static var _max_hit_v := -1.0


static func _max_hit() -> float:
	if _max_hit_v < 0.0:
		for id in Weapons.ORDER:
			var d: Dictionary = Weapons.def(id)
			_max_hit_v = maxf(_max_hit_v, float(d.get("damage", 0.0)) * float(d.get("head", 1.0)))
		_max_hit_v *= 1.15
	return _max_hit_v


func report() -> Array:
	return _log
