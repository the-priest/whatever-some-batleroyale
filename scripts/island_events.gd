class_name IslandEvents
extends Node
## The island is alive: things happen during a match, announced with a horn
## and a banner for everyone at once.
##
##   RELIQUARY   a golden supply crate falls in the next circle, with the best
##               loot of the match in it, and soldiers come for it
##   FOG BANK    thick fog rolls over the island for two minutes
##   THE HUNT    a Revenant leaves its ground and stalks the nearest player
##   BLOOD MOON  late in the match the sky turns red; soldiers hunt in packs
##               and every kill pays double Embers, until the end
##
## The host decides when (by storm phase) and tells everyone; each machine
## shows it, and the host runs the soldiers.

const FOG_TIME := 120.0
const HUNT_TIME := 120.0
const TITLES := {
	"reliquary": ["A RELIQUARY FALLS", "GOLD FROM THE SKY  —  THE BEST LOOT ON THE ISLAND. THEY WANT IT TOO"],
	"fog": ["A FOG BANK ROLLS IN", "YOU WILL NOT SEE THEM COMING  —  NOR THEY YOU"],
	"hunt": ["%s HUNTS", "A REVENANT HAS LEFT ITS GROUND. IT IS COMING FOR THE NEAREST OF YOU"],
	"blood": ["BLOOD MOON", "THE SKY TURNS RED  —  THEY HUNT IN PACKS. EVERY KILL PAYS DOUBLE"],
	"surge": ["THE STORM SURGES", "IT WILL NOT WAIT  —  THE CIRCLE CLOSES IN SECONDS. RUN"],
}
const SURGE_LEFT := 15.0

var game: Node
## Host: which storm phase each event comes at this match.
var _plan: Dictionary = {}
var _done: Dictionary = {}
var blood := false
var _blood_k := 0.0
var _fog_t := 0.0
var _fog_k := 0.0
var _hunter: Revenant = null
var _hunt_t := 0.0
var _hunt_tick := 0.0
var _blood_tick := 0.0
## Storm Surge: when the zone's hold timer falls to this, the surge comes.
var _surge_at := -1.0


func setup(p_game: Node) -> void:
	game = p_game


## A new match: decide this one's events (host), clear the sky.
func reset() -> void:
	_done.clear()
	_plan = {"fog": [1, 3][randi() % 2], "reliquary": 2, "hunt": [3, 4][randi() % 2], "blood": 5}
	# Now and then the storm will not wait.
	if randf() < 0.6:
		_plan["surge"] = [2, 3, 4][randi() % 3]
	blood = false
	_blood_k = 0.0
	_fog_t = 0.0
	_fog_k = 0.0
	_hunter = null
	_hunt_t = 0.0
	_surge_at = -1.0
	if game != null and game.world != null:
		game.world.set_blood_moon(0.0)
		game.world.set_fog_bank(0.0)


## Host: a storm phase began. Anything planned for it happens now.
func on_phase(p: int) -> void:
	if game.net_is_client():
		return
	for kind in _plan:
		if int(_plan[kind]) == p and not _done.has(kind):
			_done[kind] = true
			_start(kind)


func _start(kind: String) -> void:
	var data := {}
	match kind:
		"reliquary":
			var c: Vector2 = game.zone.next_center()
			var r: float = game.zone.next_radius() * 0.6
			for i in 40:
				var a := randf() * TAU
				var q := c + Vector2(cos(a), sin(a)) * sqrt(randf()) * r
				var h: float = game.terrain.height_at(q.x, q.y)
				if h > game.terrain.water_surface_at(q.x, q.y) + 1.0 and game.terrain.slope_at(q.x, q.y) < 0.4 and not game._on_building(q.x, q.y):
					game.reliquary_next = true
					game.spawn_airdrop_at(q, false)
					data["at"] = q
					# Soldiers near it want it.
					for b in game.bots:
						if is_instance_valid(b) and b.alive and b.armed and not b.is_human and not b.puppet and b.state == Bot.State.GROUND \
								and Vector2(b.global_position.x, b.global_position.z).distance_to(q) < 400.0 and randf() < 0.7:
							b.roam_point = q + Vector2(randf_range(-10, 10), randf_range(-10, 10))
					break
			if not data.has("at"):
				return
		"surge":
			# Mid-way through this phase's hold, cut it short.
			_surge_at = game.zone.timer * randf_range(0.35, 0.6)
			return
		"hunt":
			var alive_revs: Array = game.bots.filter(func(b): return is_instance_valid(b) and b is Revenant and (b as Bot).alive)
			if alive_revs.is_empty():
				return
			_hunter = alive_revs[randi() % alive_revs.size()]
			_hunt_t = HUNT_TIME
			_hunt_tick = 0.0
			data["name"] = _hunter.bot_name
	if game.net_on():
		game.net.send_island_event(kind, data)
	apply(kind, data)


## Host: the storm stops holding and closes within seconds.
func surge_now() -> void:
	if game.zone == null or game.zone.state != "hold":
		return
	game.zone.timer = minf(game.zone.timer, SURGE_LEFT)
	if game.net_on():
		game.net.send_island_event("surge", {})
	apply("surge", {})


## Everyone: show it, and change the sky.
func apply(kind: String, data: Dictionary) -> void:
	var t: Array = TITLES.get(kind, ["", ""])
	var title := str(t[0])
	if kind == "hunt":
		title = title % str(data.get("name", "A REVENANT"))
	var col := Color(1.0, 0.82, 0.38)
	match kind:
		"fog":
			_fog_t = FOG_TIME
			col = Color(0.82, 0.86, 0.9)
		"blood":
			blood = true
			col = HUD.DANGER
		"hunt", "surge":
			col = HUD.DANGER
	game.sfx.play_ui("event_horn", -2.0)
	game.hud.show_big(title, col, 3.6)
	game.hud.show_notice(str(t[1]), 5.0)
	game.hud.killfeed(title, col)
	if game.writs != null:
		game.writs.ember_mult = 2 if blood else 1


func _process(delta: float) -> void:
	if game == null or game.world == null or game.phase == "menu":
		return
	# The sky follows the events on every machine.
	var bk := 1.0 if blood else 0.0
	if absf(_blood_k - bk) > 0.001:
		_blood_k = move_toward(_blood_k, bk, delta / 25.0)
		game.world.set_blood_moon(_blood_k)
	_fog_t = maxf(0.0, _fog_t - delta)
	var fk := 1.0 if _fog_t > 0.0 else 0.0
	if absf(_fog_k - fk) > 0.001:
		_fog_k = move_toward(_fog_k, fk, delta / 12.0)
		game.world.set_fog_bank(_fog_k)
	if game.net_is_client() or game.phase != "playing":
		return
	if _surge_at > 0.0 and game.zone != null and game.zone.state == "hold" and game.zone.timer <= _surge_at:
		_surge_at = -1.0
		surge_now()
	# The Hunt: the Revenant's ground moves with its prey.
	if _hunter != null:
		if not is_instance_valid(_hunter) or not _hunter.alive:
			_hunter = null
		else:
			_hunt_t -= delta
			_hunt_tick -= delta
			if _hunt_t <= 0.0:
				_hunter.arena = _hunter.get_meta("home", _hunter.arena)
				_hunter = null
			elif _hunt_tick <= 0.0:
				_hunt_tick = 6.0
				if not _hunter.has_meta("home"):
					_hunter.set_meta("home", _hunter.arena)
				var prey := _nearest_player(_hunter.global_position)
				if prey != Vector3.INF:
					_hunter.arena = prey
					_hunter.roam_point = Vector2(prey.x, prey.z)
					_hunter.heard_pos = prey
					_hunter.alert_timer = 8.0
	# Blood Moon: every so often, packs go looking for the nearest player.
	if blood:
		_blood_tick -= delta
		if _blood_tick <= 0.0:
			_blood_tick = 20.0
			for b in game.bots:
				if is_instance_valid(b) and b.alive and b.armed and not b.is_human and not b.puppet and b.state == Bot.State.GROUND and not (b is Revenant):
					b.aggression = 1.0
					if randf() < 0.35:
						var prey := _nearest_player(b.global_position)
						if prey != Vector3.INF and prey.distance_to(b.global_position) < 450.0:
							b.roam_point = Vector2(prey.x, prey.z) + Vector2(randf_range(-20, 20), randf_range(-20, 20))
							b.heard_pos = prey
							b.alert_timer = 10.0


## The nearest living player (you or a joined friend) to a spot.
func _nearest_player(from: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	if game.player != null and game.player.alive and game.player.mode == Player.Mode.GROUND:
		best = game.player.global_position
		best_d = from.distance_to(best)
	for id in game.humans:
		var h = game.humans[id]
		if h != null and is_instance_valid(h) and (h as Bot).alive and (h as Bot).state == Bot.State.GROUND:
			var d := from.distance_to((h as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = (h as Node3D).global_position
	return best
