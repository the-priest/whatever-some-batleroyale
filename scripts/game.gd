extends Node3D

# BLOCK ROYALE — match orchestrator.
# menu -> plane -> freefall -> ground -> win / eliminated

const MAX_BOTS := 19
const BOT_NAMES := [
	"RAVEN", "GHOST", "BOLT", "VEX", "SABLE", "NOMAD", "CINDER", "HALO",
	"TALON", "DRIFT", "ECHO", "FLINT", "ONYX", "PIKE", "RUNE", "SLATE",
	"THORN", "VOID", "WREN", "ZERO", "ASH", "BRICK", "COBRA", "DUSK",
]
const WEAPON_DROP_WEIGHTS := {
	"pistol": 12, "m1911": 9, "smg": 14, "grease": 10, "shotgun": 11, "autoshotgun": 4,
	"rifle": 13, "carbine": 12, "bullpup": 6, "lmg": 3, "dmr": 5, "m24": 4, "axmc": 1,
}
const AIRDROP_WEAPONS := ["sniper", "sniper", "axmc", "lmg"]
const HI_WEAPONS := ["dmr", "m24", "carbine", "bullpup", "rifle", "lmg", "axmc"]
const HI_GEAR := [["scope", "4x"], ["scope", "8x"], ["armor", "2"], ["helmet", "2"], ["armor", "3"], ["med", ""], ["scope", "2x"], ["ammo", "7.62"], ["ammo", "5.56"]]
## Floor loot table for non-weapon spots: [kind, id, weight].
const GEAR_TABLE := [
	["ammo", "", 16.0], ["bandage", "", 15.0], ["med", "", 7.0], ["energy", "", 7.0],
	["armor", "1", 8.0], ["armor", "2", 4.0], ["armor", "3", 1.2],
	["helmet", "1", 8.0], ["helmet", "2", 4.0], ["helmet", "3", 1.2],
	["scope", "reddot", 6.0], ["scope", "2x", 5.0], ["scope", "4x", 3.0], ["scope", "8x", 1.2],
	["extmag", "", 4.5], ["comp", "", 4.5], ["grenade", "", 7.0],
]
const SETTINGS_PATH := "user://settings.cfg"
const HEAR_RANGE := 70.0
const PING_RANGE := 160.0

var world: WorldBuilder
var terrain: Terrain
var player: Player
var plane: DropPlane
var zone: Zone
var hud: HUD
var sfx: Sfx
var ballistics: Ballistics
var menu_cam: Camera3D

var phase := "boot"      # boot | menu | plane | playing | end
var lobby_ready := false
var seed_value := 20261101
var loot_pool: Array = []
var bots: Array = []
var airdrops: Array = []
var alive := 1
var total_players := 1
var player_kills := 0
var damage_dealt := 0.0
var match_time := 0.0
var survive_time := 0.0
var zone_acc := 0.0
var zone_was_warning := false
var winner := false
var plane_start := Vector3.ZERO
var plane_end := Vector3.ZERO
var menu_angle := 0.0
var tracers: Array = []
var impacts: Array = []
var cam_shake := 0.0
var menu_t := 0.0
var last_hud_alive := -1
var end_cam_target: Node3D = null
var end_cam_spot := Vector3.ZERO
var end_cam_angle := 0.0
var mouse_sens := 1.0
var volume := 0.8
var fov := 82.0
var loadout_primary := "carbine"
var loadout_secondary := "pistol"
var loadout_optic := "reddot"
var loadout_enabled := true
var _loot_label_t := 0.0
var _last_best: LootPickup = null
var _wind: AudioStreamPlayer3D = null


func _ready() -> void:
	randomize()
	seed_value = 100000 + int(Time.get_unix_time_from_system()) % 899999
	sfx = Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)
	ballistics = Ballistics.new()
	ballistics.name = "Ballistics"
	ballistics.game = self
	add_child(ballistics)
	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.play_pressed.connect(_start_match)
	hud.resume_pressed.connect(_resume)
	hud.quit_pressed.connect(_quit_to_menu)
	hud.settings_changed.connect(_on_settings_changed)
	hud.loadout_changed.connect(_on_loadout_changed)
	hud.show_menu("GENERATING ISLAND ...")
	_load_settings()

	menu_cam = Camera3D.new()
	menu_cam.fov = 68.0
	menu_cam.near = 0.1
	menu_cam.far = 6000.0
	add_child(menu_cam)
	menu_cam.make_current()

	await get_tree().process_frame
	_build_world()
	_create_player()
	lobby_ready = true
	phase = "menu"
	_show_menu()
	hud.set_minimap(world.minimap_texture)
	var places: Array = []
	for v in world.villages.village_pads:
		places.append([v.name, v.center, "town"])
	for t in world.villages.towers:
		places.append(["LOOKOUT", t.center, "tower"])
	for p in world.villages.poi_pads:
		if p.type == "ruin":
			places.append(["RUINS", p.center, "ruin"])
	hud.set_places(places)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if OS.get_cmdline_user_args().has("--smoke"):
		_run_smoke()
	elif OS.get_cmdline_user_args().has("--sim"):
		_run_sim()
	elif OS.get_cmdline_user_args().has("--shot"):
		_run_shot()


func _show_menu() -> void:
	hud.show_menu("SEED  %d   ·   %d LOOT SPOTS   ·   %d PLAYERS" % [seed_value, world.loot_points.size(), MAX_BOTS + 1])


func _build_world() -> void:
	var t0 := Time.get_ticks_msec()
	world = WorldBuilder.new()
	world.name = "World"
	add_child(world)
	world.build(seed_value)
	terrain = world.terrain
	print("[game] world seed %d built in %d ms, loot=%d" % [seed_value, Time.get_ticks_msec() - t0, world.loot_points.size()])


func _create_player() -> void:
	player = Player.new()
	player.name = "Player"
	player.game = self
	add_child(player)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.health_changed.connect(_on_health_changed)
	player.weapon_changed.connect(_on_weapon_changed)
	player.ammo_changed.connect(_on_ammo_changed)
	player.hitmarker.connect(_on_hitmarker)
	player.damaged.connect(_on_player_damaged)
	player.died.connect(_on_player_died)
	player.notice.connect(_on_notice)
	player.inventory_changed.connect(_on_inventory_changed)
	player.mouse_sens = 0.0022 * mouse_sens
	menu_cam.make_current()


# ----------------------------------------------------------------- settings --
func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		mouse_sens = float(cfg.get_value("input", "sensitivity", 1.0))
		volume = float(cfg.get_value("audio", "volume", 0.8))
		fov = float(cfg.get_value("video", "fov", 82.0))
		loadout_primary = str(cfg.get_value("loadout", "primary", loadout_primary))
		loadout_secondary = str(cfg.get_value("loadout", "secondary", loadout_secondary))
		loadout_optic = str(cfg.get_value("loadout", "optic", loadout_optic))
		loadout_enabled = bool(cfg.get_value("loadout", "enabled", loadout_enabled))
	if not Weapons.DEFS.has(loadout_primary):
		loadout_primary = "carbine"
	if not Weapons.DEFS.has(loadout_secondary):
		loadout_secondary = "pistol"
	hud.set_settings(mouse_sens, volume, fov)
	hud.set_loadout(loadout_primary, loadout_secondary, loadout_optic, loadout_enabled)
	_apply_settings()


func _apply_settings() -> void:
	if player != null:
		player.mouse_sens = 0.0022 * mouse_sens
		player.base_fov = fov
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, volume)))


func _on_settings_changed(sens: float, vol: float, p_fov: float) -> void:
	mouse_sens = sens
	volume = vol
	fov = p_fov
	_apply_settings()
	_save_settings()


func _on_loadout_changed(p: String, s: String, o: String, e: bool) -> void:
	loadout_primary = p
	loadout_secondary = s
	loadout_optic = o
	loadout_enabled = e
	_save_settings()


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "sensitivity", mouse_sens)
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("loadout", "primary", loadout_primary)
	cfg.set_value("loadout", "secondary", loadout_secondary)
	cfg.set_value("loadout", "optic", loadout_optic)
	cfg.set_value("loadout", "enabled", loadout_enabled)
	cfg.save(SETTINGS_PATH)


## Drop-in kit: your chosen guns, a few boxes of their ammo, the optic.
func _give_loadout() -> void:
	if not loadout_enabled or player == null:
		return
	player.give_weapon(loadout_primary)
	player.give_weapon(loadout_secondary)
	var prim_slot := player.loadout.find(loadout_primary)
	for i in 3:
		player.add_ammo_cal(Weapons.caliber(loadout_primary), int(Weapons.AMMO_BOX.get(Weapons.caliber(loadout_primary), 30)))
	for i in 2:
		player.add_ammo_cal(Weapons.caliber(loadout_secondary), int(Weapons.AMMO_BOX.get(Weapons.caliber(loadout_secondary), 30)))
	if loadout_optic != "" and prim_slot >= 0 and Weapons.scope_fits(loadout_primary, loadout_optic):
		player.attachments[prim_slot]["scope"] = loadout_optic
	if prim_slot >= 0:
		player.select_slot(prim_slot)
	player.refresh_viewmodel()
	player.inventory_changed.emit()


func _resume() -> void:
	hud.show_pause(false)
	get_tree().paused = false
	if phase == "playing" or phase == "plane":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _quit_to_menu() -> void:
	hud.show_pause(false)
	get_tree().paused = false
	_cleanup_match()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.alive = false
	hud.pause_allowed = false
	hud.set_plane_path(Vector3.ZERO, Vector3.ZERO)
	phase = "menu"
	menu_cam.make_current()
	_show_menu()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# -------------------------------------------------------------------- match --
func _start_match() -> void:
	if not lobby_ready:
		return
	sfx.play_ui("ui_click", -6.0)
	hud.hide_menu()
	hud.hide_end()
	hud.clear_killfeed()
	hud.set_spectate("")
	_cleanup_match()
	player.reset_for_match()
	player.global_position = Vector3(0, 120, 0)

	# Flight path across the island, offset so it does not always cross centre.
	var ang := randf() * TAU
	var dir := Vector3(cos(ang), 0.0, sin(ang))
	var side := Vector3(-dir.z, 0.0, dir.x) * randf_range(-110.0, 110.0)
	plane_start = -dir * 600.0 + side + Vector3(0, 198.0, 0)
	plane_end = dir * 600.0 + side + Vector3(0, 188.0, 0)
	plane = DropPlane.new()
	plane.name = "Plane"
	add_child(plane)
	plane.setup(plane_start, plane_end)
	hud.set_plane_path(plane_start, plane_end)

	menu_cam.make_current()
	phase = "plane"
	player.global_position = plane.seat_position()

	# Loot.
	loot_pool.clear()
	for p in world.loot_points:
		var kind := str(p.get("kind", "weapon"))
		var base := Vector3(p["pos"])
		var hi := str(p.get("tier", "")) == "hi"
		if kind == "weapon":
			_spawn_loot("weapon", HI_WEAPONS[randi() % HI_WEAPONS.size()] if hi else _weighted_weapon(), base)
			# Guns come with something beside them: usually ammo.
			var gun_id: String = loot_pool[loot_pool.size() - 1].item_id
			var a := randf() * TAU
			if randf() < 0.85:
				_spawn_loot("ammo", Weapons.caliber(gun_id), base + Vector3(cos(a), 0.0, sin(a)) * 0.9)
			if randf() < 0.35:
				var extra := _roll_gear()
				_spawn_loot(extra[0], extra[1], base + Vector3(cos(a + 2.0), 0.0, sin(a + 2.0)) * 0.9)
		else:
			var g: Array = HI_GEAR[randi() % HI_GEAR.size()] if hi else _roll_gear()
			_spawn_loot(g[0], g[1], base)
			if bool(p.get("village", false)) and randf() < 0.5:
				var a := randf() * TAU
				var g2 := _roll_gear()
				_spawn_loot(g2[0], g2[1], base + Vector3(cos(a), 0.0, sin(a)) * 0.9)

	# Bots: most drop near a weapon so the first minute has real fights.
	var weapon_spots: Array = []
	for l in loot_pool:
		if is_instance_valid(l) and l.kind == "weapon" and l.global_position.y > 0.0:
			weapon_spots.append(l.global_position)
	bots.clear()
	var route := plane_end - plane_start
	var route_len2 := maxf(1.0, route.x * route.x + route.z * route.z)
	for i in range(MAX_BOTS):
		var b := Bot.new()
		var target := _random_ground_point(390.0)
		var jump_t := randf_range(0.05, 0.90)
		if weapon_spots.size() > 0 and randf() < 0.6:
			var best_spot: Vector3
			var best_cost := 1.0e9
			for attempt in 10:
				var cand: Vector3 = weapon_spots[randi() % weapon_spots.size()]
				var tt := clampf(((cand.x - plane_start.x) * route.x + (cand.z - plane_start.z) * route.z) / route_len2, 0.05, 0.90)
				var rp := plane_start + route * tt
				var d_route := Vector2(cand.x - rp.x, cand.z - rp.z).length()
				if d_route < best_cost:
					best_cost = d_route
					best_spot = cand
					jump_t = tt
				if d_route < 55.0:
					break
			if best_cost <= 150.0:
				var a := randf() * TAU
				var r := randf_range(10.0, 45.0)
				target = Vector3(best_spot.x + cos(a) * r, best_spot.y, best_spot.z + sin(a) * r)
		b.setup(BOT_NAMES[i % BOT_NAMES.size()] + ("" if i < BOT_NAMES.size() else str(i)), Vector2(target.x, target.z), self, seed_value + i * 977 + randi() % 1000)
		add_child(b)
		b.global_position = plane.seat_position() + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
		b.set_meta("jump_at", clampf(jump_t + randf_range(-0.02, 0.02), 0.03, 0.93))
		b.eliminated.connect(_on_bot_eliminated)
		bots.append(b)

	# Zone.
	zone = Zone.new()
	zone.name = "Zone"
	zone.terrain = terrain
	add_child(zone)
	zone.start(430.0)
	zone.set_process(false)
	zone.phase_changed.connect(_on_zone_phase)
	zone_was_warning = false

	alive = MAX_BOTS + 1
	total_players = alive
	player_kills = 0
	damage_dealt = 0.0
	match_time = 0.0
	survive_time = 0.0
	zone_acc = 0.0
	winner = false
	last_hud_alive = -1
	end_cam_target = null
	hud.set_gameplay_visible(true)
	hud.set_crosshair_visible(false)
	hud.pause_allowed = true
	hud.set_kills(0)
	hud.set_alive(alive, total_players)
	hud.set_prompt("")
	hud.set_storm(false)
	_hud_zone()
	_on_inventory_changed()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_attach_plane_audio()


func _spawn_loot(kind: String, id: String, pos: Vector3, mag := -1, reserve := -1) -> LootPickup:
	var l := LootPickup.new()
	l.setup(kind, id, 1)
	l.mag_override = mag
	l.reserve_override = reserve
	l.position = pos
	add_child(l)
	loot_pool.append(l)
	return l


func _cleanup_match() -> void:
	for l in loot_pool:
		if is_instance_valid(l):
			l.queue_free()
	loot_pool.clear()
	for b in bots:
		if is_instance_valid(b):
			b.queue_free()
	bots.clear()
	for a in airdrops:
		if is_instance_valid(a):
			a.queue_free()
	airdrops.clear()
	if plane != null and is_instance_valid(plane):
		plane.queue_free()
	plane = null
	if zone != null and is_instance_valid(zone):
		zone.queue_free()
	zone = null
	if _wind != null and is_instance_valid(_wind):
		_wind.queue_free()
	_wind = null
	for n in [_cabin, _wind2d]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_cabin = null
	_wind2d = null
	for t in tracers:
		if is_instance_valid(t):
			t.queue_free()
	tracers.clear()
	ballistics.clear()
	for i in impacts:
		if is_instance_valid(i):
			i.queue_free()
	impacts.clear()
	if player != null:
		player.mode = Player.Mode.PLANE
	hud.set_storm(false)


func _roll_gear() -> Array:
	var total := 0.0
	for e in GEAR_TABLE:
		total += float(e[2])
	var roll := randf() * total
	for e in GEAR_TABLE:
		roll -= float(e[2])
		if roll <= 0.0:
			if e[0] == "ammo":
				return ["ammo", _random_caliber()]
			return [e[0], e[1]]
	return ["ammo", _random_caliber()]


func _random_caliber() -> String:
	var r := randf()
	return "5.56" if r < 0.34 else ("9mm" if r < 0.62 else ("7.62" if r < 0.84 else "12ga"))


func _weighted_weapon() -> String:
	var total := 0
	for k in WEAPON_DROP_WEIGHTS:
		total += int(WEAPON_DROP_WEIGHTS[k])
	var roll := randi_range(1, total)
	for k in WEAPON_DROP_WEIGHTS:
		roll -= int(WEAPON_DROP_WEIGHTS[k])
		if roll <= 0:
			return str(k)
	return "pistol"


func _random_ground_point(max_r: float) -> Vector3:
	for i in range(40):
		var a := randf() * TAU
		var r := sqrt(randf()) * max_r
		var x := cos(a) * r
		var z := sin(a) * r
		if terrain == null:
			return Vector3(x, 40, z)
		var h := terrain.height_at(x, z)
		if h > 1.4 and terrain.slope_at(x, z) < 0.45:
			return Vector3(x, h, z)
	return Vector3(0, 60, 0)


## What the ground under a point is made of, for footsteps.
func surface_at(pos: Vector3) -> String:
	if terrain == null:
		return "grass"
	if terrain.is_water(pos.x, pos.z) and pos.y < Terrain.WATER_LEVEL + 0.8:
		return "water"
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.4, pos + Vector3.DOWN * 1.2, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var col: Object = hit["collider"]
		if col is Node:
			var n := (col as Node).name
			if n.begins_with("Village"):
				return "wood"
			if n.begins_with("Rock"):
				return "stone"
	var h := terrain.height_at(pos.x, pos.z)
	if h < 3.6 or terrain.slope_at(pos.x, pos.z) > 0.35:
		return "stone"
	return "grass"


## Ground height under a point, including houses and props.
func ground_at(pos: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 1.5, pos + Vector3.DOWN * 30.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return Vector3(pos.x, terrain.height_at(pos.x, pos.z), pos.z)
	return hit["position"]


# ------------------------------------------------------------------- update --
func _process(delta: float) -> void:
	match phase:
		"menu":
			menu_t += delta
			menu_angle += delta * 0.045
			var r := 300.0
			var cam_pos := Vector3(cos(menu_angle) * r, 138.0 + sin(menu_t * 0.25) * 10.0, sin(menu_angle) * r)
			menu_cam.global_position = cam_pos
			menu_cam.look_at(Vector3(0, 18.0, 0), Vector3.UP)
			menu_cam.fov = lerpf(menu_cam.fov, 62.0, delta * 0.8)
		"plane":
			_follow_plane_cam(delta)
			_update_airborne_bots()
			_update_prompt()
			_update_minimap()
			if plane != null and plane.active and plane.progress() >= 0.985 and player.mode == Player.Mode.PLANE:
				_player_jump(true)
			if plane != null and not plane.active and player.mode == Player.Mode.PLANE:
				_player_jump(true)
		"playing":
			_update_play(delta)
		"end":
			_update_end_cam(delta)
			_update_world_sim(delta)
	_update_mouse_capture()


func _follow_plane_cam(delta: float) -> void:
	if plane == null:
		return
	# Orbit the plane with the mouse (the player's look angles drive it).
	var orbit := Basis(Vector3.UP, player.yaw) * Basis(Vector3.RIGHT, clampf(player.pitch, deg_to_rad(-60.0), deg_to_rad(25.0)) - 0.18)
	var focus := plane.global_position + Vector3(0, 1.5, 0)
	var want := focus + orbit * Vector3(0, 0, 34.0)
	menu_cam.global_position = menu_cam.global_position.lerp(want, clampf(delta * 6.0, 0.0, 1.0))
	menu_cam.look_at(focus, Vector3.UP)
	menu_cam.fov = lerpf(menu_cam.fov, 62.0, delta * 2.0)


func _update_airborne_bots() -> void:
	if plane == null:
		return
	var prog := plane.progress()
	for b in bots:
		if not is_instance_valid(b):
			continue
		if b.state == Bot.State.PLANE and prog >= float(b.get_meta("jump_at", 0.5)):
			b.jump_from_plane()


func _update_play(delta: float) -> void:
	match_time += delta
	survive_time += delta
	_update_wind(delta)
	if player == null or not is_instance_valid(player):
		return
	_update_airborne_bots()
	if zone != null and not zone.is_processing() and (player.landed or match_time > 50.0):
		zone.set_process(true)
	hud.set_crosshair_visible(player.mode == Player.Mode.GROUND and player.has_gun() and player.aim_blend < 0.6)
	_update_world_sim(delta)
	if zone != null and zone.is_processing():
		if zone.warning and not zone_was_warning:
			zone_was_warning = true
			sfx.play_ui("zone_warn", -8.0)
		elif not zone.warning:
			zone_was_warning = false
		_hud_zone()
	hud.set_storm(zone != null and player.alive and zone.is_outside(player.global_position) and player.mode == Player.Mode.GROUND)

	_hud_player()
	_update_prompt()
	_update_minimap()
	_update_progress()
	hud.set_crosshair_spread(_crosshair_spread())

	if alive <= 1 and player.alive and phase == "playing":
		_win()


## Zone damage for everyone; keeps running behind the end screen so the
## spectated fight still plays out.
func _update_world_sim(delta: float) -> void:
	if zone == null or not zone.is_processing():
		return
	zone_acc += delta
	if zone_acc < 1.0:
		return
	zone_acc -= 1.0
	var dps := zone.damage_per_second()
	if phase == "playing" and player.alive and zone.is_outside(player.global_position) and player.mode == Player.Mode.GROUND:
		player.take_damage(dps, Vector3.ZERO, false, null)
		hud.show_notice("YOU ARE IN THE STORM  —  FOLLOW THE ARROW ON THE COMPASS", 1.4)
	for b in bots:
		if is_instance_valid(b) and b.alive and b.state == Bot.State.GROUND and zone.is_outside(b.global_position):
			b.take_damage(dps, b.global_position, false, null)


func _on_zone_phase(p: int, warning: bool) -> void:
	if phase != "playing":
		return
	if warning:
		hud.show_big("THE STORM IS CLOSING", _storm_color(), 2.4)
		sfx.play_ui("zone_warn", -6.0)
	elif not zone.finished:
		hud.show_notice("NEXT SAFE ZONE MARKED  —  PRESS M FOR THE MAP", 3.0)
		if p == 1 or p == 3:
			_spawn_airdrop()


func _storm_color() -> Color:
	return HUD.STORM.lightened(0.25)


func _hud_zone() -> void:
	if zone == null:
		return
	hud.set_zone(zone.time_left(), zone.radius, zone.phase, zone.warning, zone.label())


func _hud_player() -> void:
	if player == null:
		return
	var deg := wrapf(-rad_to_deg(player.yaw), 0.0, 360.0)
	hud.set_heading(deg)
	if last_hud_alive != alive:
		last_hud_alive = alive
		hud.set_alive(alive, total_players)


func _crosshair_spread() -> float:
	if player == null or not player.has_gun():
		return 14.0
	return player.current_spread_px()


func _update_progress() -> void:
	hud.set_boost(player.boost)
	hud.set_breath(player.breath, player.holding_breath, player.aiming and player.cur_zoom() >= 1.9)
	var hp := player.heal_progress()
	if hp >= 0.0:
		hud.set_progress(player.heal_label(), hp)
		return
	var rp := player.reload_progress()
	if rp >= 0.0:
		hud.set_progress("RELOADING", rp)
		return
	hud.set_progress("", -1.0)


func _nearest_loot(pos: Vector3, max_d: float) -> LootPickup:
	# Prefer what the player is looking at, then what is closest.
	var best: LootPickup = null
	var best_score := 1e9
	var fwd := -player.camera.global_basis.z
	for l in loot_pool:
		if not is_instance_valid(l) or l.taken:
			continue
		var to: Vector3 = l.global_position - pos
		var d := to.length()
		if d > max_d:
			continue
		var facing := fwd.dot(to.normalized()) if d > 0.01 else 1.0
		var score := d - facing * 1.2
		if score < best_score:
			best_score = score
			best = l
	return best


func _update_prompt() -> void:
	if player == null:
		hud.set_prompt("")
		return
	if player.mode == Player.Mode.PLANE:
		hud.set_prompt("SPACE  —  JUMP FROM THE PLANE")
		return
	if player.mode == Player.Mode.FREEFALL:
		hud.set_prompt("W  DIVE  ·  SPACE  DEPLOY PARACHUTE")
		return
	if player.mode == Player.Mode.CHUTE:
		hud.set_prompt("STEER WITH WASD  —  PICK YOUR LANDING SPOT")
		return
	if player.mode != Player.Mode.GROUND:
		hud.set_prompt("")
		return
	var best := _nearest_loot(player.global_position, 3.0)
	if best != null:
		var why := best.block_reason(player)
		hud.set_prompt(best.prompt_text() if why == "" else why)
	else:
		hud.set_prompt("")
	_loot_label_t -= get_process_delta_time()
	if _loot_label_t <= 0.0 or best != _last_best:
		_loot_label_t = 0.12
		_last_best = best
		var pp := player.global_position
		for l in loot_pool:
			if is_instance_valid(l) and not l.taken:
				var dd: float = l.global_position.distance_to(pp)
				# Only the item you are about to take gets a name tag; light shafts
				# fade out up close so a pile of loot does not become a wall of light.
				l.label.visible = l == best
				l.beacon.visible = false
				l.ring.visible = dd < 14.0


func _update_minimap() -> void:
	var marks: Array = []
	for a in airdrops:
		if is_instance_valid(a):
			marks.append(a.global_position)
	var zc := zone.center if zone != null else Vector2.ZERO
	var zr := zone.radius if zone != null else 430.0
	var nc := zone.next_center() if zone != null else zc
	var nr := zone.next_radius() if zone != null else zr
	hud.update_minimap(player.global_position, zc, zr, nc, nr, marks)


func _update_mouse_capture() -> void:
	if get_tree().paused:
		return
	if phase == "playing" or phase == "plane":
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and Input.is_action_just_pressed("fire"):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif phase == "menu" or phase == "end":
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _update_end_cam(delta: float) -> void:
	var focus := end_cam_spot
	if end_cam_target != null and is_instance_valid(end_cam_target) and bool(end_cam_target.get("alive")):
		focus = end_cam_target.global_position
		end_cam_spot = focus
	end_cam_angle += delta * 0.25
	var want := focus + Vector3(cos(end_cam_angle) * 9.0, 4.5, sin(end_cam_angle) * 9.0)
	menu_cam.global_position = menu_cam.global_position.lerp(want, clampf(delta * 2.5, 0.0, 1.0))
	menu_cam.look_at(focus + Vector3(0, 1.2, 0), Vector3.UP)


func _begin_end_cam(target: Node3D, spot: Vector3) -> void:
	end_cam_target = target
	end_cam_spot = spot
	end_cam_angle = player.yaw + PI * 0.5
	menu_cam.global_position = player.camera.global_position
	menu_cam.fov = 70.0
	menu_cam.make_current()
	if target != null and target is Bot and (target as Bot).alive:
		hud.set_spectate("SPECTATING  %s" % (target as Bot).bot_name)
	else:
		hud.set_spectate("")


# -------------------------------------------------------------------- input --
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump"):
		if phase == "menu":
			_start_match()
			return
		if phase == "plane" and player != null and player.mode == Player.Mode.PLANE:
			_player_jump(false)
		elif phase == "end":
			_start_match()
		return
	if phase == "end" and event.is_action_pressed("pause"):
		_quit_to_menu()


func _player_jump(auto: bool) -> void:
	if player == null or player.mode != Player.Mode.PLANE:
		return
	player.jump_from_plane()
	player.velocity += plane.jump_velocity() if plane != null else Vector3.ZERO
	player.camera.make_current()
	phase = "playing"
	if not auto:
		sfx.play_ui("jump_whoosh", -6.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_fade_cabin()
	_attach_wind_audio()


# ------------------------------------------------------------------ signals --
func _on_health_changed(hp: float, armor: float) -> void:
	hud.update_health(hp, armor)


func _on_weapon_changed(id: String, mag: int, reserve: int) -> void:
	hud.update_weapon(id, mag, reserve)


func _on_ammo_changed(mag: int, reserve: int) -> void:
	hud.update_ammo(mag, reserve)


func _on_inventory_changed() -> void:
	if player != null:
		hud.set_inventory(player)
		if player.has_gun():
			hud.update_weapon(player.current_id(), player.current_mag(), player.current_reserve())


func _on_hitmarker(headshot: bool, killed: bool) -> void:
	hud.show_hitmarker(headshot, killed)
	sfx.play_ui("headshot" if headshot else "hitmarker", -9.0 if headshot else -11.0)


func _on_player_damaged(amount: float, from_dir: Vector3) -> void:
	hud.show_damage(from_dir)
	sfx.play_ui("hit_flesh", -8.0)
	cam_shake = minf(1.4, cam_shake + amount * 0.02)
	player.add_trauma(clampf(amount * 0.015, 0.05, 0.5))


func _on_player_died(killer: String) -> void:
	if phase == "end":
		return
	phase = "end"
	player.alive = false
	hud.pause_allowed = false
	hud.set_storm(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var placement := maxi(1, alive)
	alive = maxi(0, alive - 1)
	hud.killfeed("%s   >   YOU" % killer, HUD.DANGER)
	hud.show_death(killer, placement, _stats())
	sfx.play_ui("defeat", -4.0)
	hud.set_prompt("")
	var k = player.last_killer
	_begin_end_cam(k as Node3D if k != null and is_instance_valid(k) and k is Node3D else null, player.global_position)


func _stats() -> Dictionary:
	var acc := 0
	if player.shots_fired > 0:
		acc = int(round(100.0 * float(player.shots_hit) / float(player.shots_fired)))
	return {"kills": player_kills, "damage": damage_dealt, "accuracy": acc, "time": survive_time}


func _on_notice(text: String) -> void:
	hud.show_notice(text, 2.0)


func _on_bot_eliminated(victim: Bot, killer: String) -> void:
	alive = maxi(0, alive - 1)
	var k := killer if killer != "" else "THE STORM"
	var weapon := ""
	var src = victim.last_killer_node
	if src is Bot and is_instance_valid(src):
		weapon = str(Weapons.def((src as Bot).weapon_id)["short"]) if (src as Bot).weapon_id != "" else ""
	elif src is Player and player.has_gun():
		weapon = str(Weapons.def(player.current_id())["short"])
	if killer == "YOU":
		player_kills += 1
		hud.set_kills(player_kills)
		sfx.play_ui("elim", -4.0)
		hud.show_big("ELIMINATED  %s" % victim.bot_name, HUD.WHITE, 2.0)
		hud.show_notice("%d KILL%s" % [player_kills, "" if player_kills == 1 else "S"], 1.6)
	var col := HUD.ACCENT if killer == "YOU" else HUD.MUTED
	var mid := ("  [%s]  " % weapon) if weapon != "" else "   >   "
	hud.killfeed("%s%s%s" % [k, mid, victim.bot_name], col)
	hud.set_alive(alive, total_players)
	last_hud_alive = alive
	_drop_bot_loot(victim)
	if phase == "end" and end_cam_target == victim:
		# Follow whoever got them, so the spectate cam keeps showing the fight.
		if src is Bot and is_instance_valid(src) and (src as Bot).alive:
			end_cam_target = src
			hud.set_spectate("SPECTATING  %s" % (src as Bot).bot_name)
		else:
			hud.set_spectate("")
	if alive <= 1 and player != null and player.alive and phase == "playing":
		_win()


func _drop_bot_loot(b: Bot) -> void:
	var base := ground_at(b.global_position)
	if b.armed and b.weapon_id != "":
		_spawn_loot("weapon", b.weapon_id, base + Vector3(0.0, 0.08, 0.0), int(Weapons.def(b.weapon_id)["mag"]))
	var extras: Array = [["ammo", Weapons.caliber(b.weapon_id) if b.armed else _random_caliber()]]
	if b.meds > 0:
		extras.append(["med", ""])
	if randf() < 0.6:
		extras.append(["bandage", ""])
	if b.vest_level > 0:
		extras.append(["armor", str(b.vest_level)])
	if b.helmet_level > 0:
		extras.append(["helmet", str(b.helmet_level)])
	if randf() < 0.35:
		extras.append(_roll_gear())
	for i in extras.size():
		var a := TAU * float(i) / float(extras.size()) + randf() * 0.5
		var p := ground_at(b.global_position + Vector3(cos(a), 0.0, sin(a)) * 1.2)
		_spawn_loot(extras[i][0], extras[i][1], p + Vector3(0, 0.08, 0))


func _win() -> void:
	if phase == "end":
		return
	phase = "end"
	winner = true
	hud.pause_allowed = false
	hud.set_storm(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_victory(_stats())
	sfx.play_ui("victory", -3.0)
	hud.set_prompt("")
	_begin_end_cam(player, player.global_position)


func on_player_landed() -> void:
	sfx.play_ui("land_thud", -6.0)
	hud.set_plane_path(Vector3.ZERO, Vector3.ZERO)
	if loadout_enabled:
		_give_loadout()
		hud.show_notice("LOADOUT READY  —  FIND ARMOR AND MEDS", 3.0)
	else:
		hud.show_notice("FIND A WEAPON  —  CHECK THE HOUSES", 3.0)
	player.add_trauma(0.35)


func on_bot_landed(bot: Bot) -> void:
	# With loadouts on, bots get a kit too so nobody lands defenceless.
	if loadout_enabled and not bot.armed:
		bot.arm_weapon(_weighted_weapon())


func on_player_damaged(_amount: float, _from: Vector3) -> void:
	pass


func on_player_hit(_pos: Vector3, dmg: float, _headshot: bool) -> void:
	# No floating numbers: the hitmarker and sound are the feedback.
	damage_dealt += dmg


## Every gunshot: nearby bots hear it, distant ones show on the map.
func on_gunshot(pos: Vector3, shooter: Node) -> void:
	for b in bots:
		if is_instance_valid(b) and b != shooter and b.alive and b.global_position.distance_to(pos) < HEAR_RANGE:
			b.hear_shot(pos, shooter)
	if shooter != player and player != null:
		var d := pos.distance_to(player.global_position)
		if d < PING_RANGE and d > 8.0 and randf() < 0.35:
			hud.add_ping(pos)


# --------------------------------------------------------------------- loot --
func try_pickup(p: Player) -> void:
	if p == null or p.mode != Player.Mode.GROUND:
		return
	var best := _nearest_loot(p.global_position, 3.2)
	if best == null:
		return
	var why := best.block_reason(p)
	if why != "":
		p.notice.emit(why)
		return
	var kind := best.kind
	if best.pickup(p):
		var snd := "pickup"
		if kind == "ammo":
			snd = "ammo_pickup"
		elif kind == "armor":
			snd = "armor_pickup"
		sfx.play_at(snd, best.global_position, -4.0)
		loot_pool.erase(best)
		hud.set_prompt("")


func drop_item(kind: String, id: String, pos: Vector3) -> void:
	_spawn_loot(kind, id, ground_at(pos) + Vector3(0, 0.08, 0)).dropped = true


func drop_weapon(id: String, mag: int, reserve: int, pos: Vector3) -> void:
	if id == "":
		return
	var g := ground_at(pos)
	_spawn_loot("weapon", id, g + Vector3(0, 0.08, 0), mag, reserve).dropped = true


func _spawn_airdrop() -> void:
	if zone == null:
		return
	var c := zone.next_center()
	var r := zone.next_radius() * 0.7
	for i in 12:
		var a := randf() * TAU
		var p := c + Vector2(cos(a), sin(a)) * sqrt(randf()) * r
		var h := terrain.height_at(p.x, p.y)
		if h > Terrain.WATER_LEVEL + 1.0 and terrain.slope_at(p.x, p.y) < 0.4:
			var drop := Airdrop.new()
			drop.setup(self, p, ground_at(Vector3(p.x, h + 20.0, p.y)).y)
			add_child(drop)
			airdrops.append(drop)
			hud.show_big("SUPPLY DROP INCOMING", Color(1.0, 0.45, 0.3), 2.6)
			hud.show_notice("HIGH-TIER LOOT  —  MARKED ON THE MAP", 3.0)
			sfx.play_ui("zone_warn", -10.0)
			return


func on_airdrop_landed(drop: Airdrop) -> void:
	var base := drop.global_position
	var gun: String = AIRDROP_WEAPONS[randi() % AIRDROP_WEAPONS.size()]
	var items: Array = [["weapon", gun], ["armor", "3"], ["helmet", "3"], ["med", ""], ["scope", "8x" if Weapons.cls(gun) in ["sniper", "dmr"] else "4x"], ["ammo", Weapons.caliber(gun)], ["ammo", Weapons.caliber(gun)]]
	for i in items.size():
		var a := TAU * float(i) / float(items.size())
		var p := ground_at(base + Vector3(cos(a), 0.0, sin(a)) * 1.9) + Vector3(0, 0.08, 0)
		if items[i][0] == "weapon":
			_spawn_loot("weapon", gun, p)
		else:
			_spawn_loot(items[i][0], items[i][1], p)
	# Armed bots nearby want it too.
	for b in bots:
		if is_instance_valid(b) and b.alive and b.armed and b.global_position.distance_to(base) < 140.0 and randf() < 0.6:
			b.roam_point = Vector2(base.x, base.z)


# ------------------------------------------------------------------- effects --
func spawn_impact(pos: Vector3, normal: Vector3, _col: Object, big := false) -> void:
	_puff(pos + normal * 0.04, Color(0.62, 0.58, 0.50, 0.8), 0.9 if big else 0.6, 4.0 if big else 2.2)
	if player != null and pos.distance_to(player.global_position) < 40.0:
		sfx.play_at("bullet_impact", pos, -12.0, 0.2)


func spawn_explosion(pos: Vector3) -> void:
	sfx.play_at("explosion", pos, 4.0, 0.1)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.65, 0.3)
	light.light_energy = 8.0
	light.omni_range = 14.0
	add_child(light)
	light.global_position = pos + Vector3.UP * 0.6
	var tl := light.create_tween()
	tl.tween_property(light, "light_energy", 0.0, 0.35)
	tl.tween_callback(light.queue_free)
	_puff(pos + Vector3.UP * 0.4, Color(1.0, 0.72, 0.35, 0.95), 4.0, 26.0)
	_puff(pos + Vector3.UP * 0.8, Color(0.25, 0.23, 0.21, 0.8), 6.0, 34.0)
	if player != null and player.alive:
		var d := pos.distance_to(player.global_position)
		if d < 30.0:
			player.add_trauma(clampf(1.0 - d / 30.0, 0.0, 1.0) * 0.9)
	# Bots nearby flinch toward the blast.
	on_gunshot(pos, null)


func spawn_blood(pos: Vector3) -> void:
	_puff(pos, Color(0.75, 0.08, 0.06, 0.9), 0.9, 2.6)


func _puff(pos: Vector3, col: Color, s0: float, s1: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	sm.radial_segments = 6
	sm.rings = 3
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * s0
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * s1, 0.22)
	tw.tween_property(mi, "transparency", 1.0, 0.22)
	tw.chain().tween_callback(mi.queue_free)
	impacts.append(mi)
	if impacts.size() > 40:
		impacts.pop_front()


func spawn_damage_number(pos: Vector3, dmg: float, headshot: bool) -> void:
	var l := Label3D.new()
	l.text = "%d" % int(round(dmg))
	l.font = load("res://assets/fonts/ui_bold.ttf")
	l.font_size = 48
	l.outline_size = 10
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.modulate = Color(1.0, 0.82, 0.3) if headshot else Color(1, 1, 1)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0009
	add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.3, 0.3), 0.4, randf_range(-0.3, 0.3))
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position", l.global_position + Vector3(0, 0.9, 0), 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tw.chain().tween_callback(l.queue_free)


func spawn_tracer(from: Vector3, to: Vector3, mine := false) -> void:
	var dist := from.distance_to(to)
	if dist < 1.0:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var w := 0.022 if mine else 0.03
	bm.size = Vector3(w, w, dist)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, 0.86, 0.52, 0.65) if mine else Color(1.0, 0.55, 0.35, 0.8)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = (from + to) * 0.5
	mi.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	var tw := mi.create_tween()
	tw.tween_property(mi, "transparency", 1.0, 0.08)
	tw.tween_callback(mi.queue_free)
	tracers.append(mi)
	if tracers.size() > 60:
		var old = tracers.pop_front()
		if is_instance_valid(old):
			old.queue_free()


func shake(amt: float) -> void:
	cam_shake = minf(1.6, cam_shake + amt * 0.03)


func plane_seat_position() -> Vector3:
	if plane != null:
		return plane.seat_position()
	return Vector3.ZERO


func play_sfx_at(name: String, pos: Vector3, vol := 0.0) -> void:
	sfx.play_at(name, pos, vol, 0.07)


func clamp_airborne(pos: Vector3, vel: Vector3, delta: float) -> Vector3:
	var flat := Vector2(pos.x, pos.z)
	var d := flat.length()
	if d > 420.0:
		var inward := -flat / d
		vel.x += inward.x * 30.0 * delta
		vel.z += inward.y * 30.0 * delta
	return vel


func respawn_player() -> void:
	if player == null:
		return
	var p := _random_ground_point(300.0)
	player.global_position = p + Vector3(0, 3, 0)
	player.velocity = Vector3.ZERO


# -------------------------------------------------------------------- audio --
func _attach_plane_audio() -> void:
	if plane == null:
		return
	var p := _loop_player("plane_loop", -2.0)
	if p != null:
		p.unit_size = 60.0
		p.max_distance = 1500.0
		plane.add_child(p)
		p.position = Vector3.ZERO
		p.play()
	_attach_cabin_audio()


var _cabin: AudioStreamPlayer = null
var _wind2d: AudioStreamPlayer = null


## Inside the hold: the engines through the hull, as a flat (non-positional) loop.
func _attach_cabin_audio() -> void:
	var s := sfx.stream("plane_interior")
	if s == null:
		return
	_make_loop(s)
	_cabin = AudioStreamPlayer.new()
	_cabin.stream = s
	_cabin.volume_db = -7.0
	add_child(_cabin)
	_cabin.play()


func _fade_cabin() -> void:
	if _cabin == null or not is_instance_valid(_cabin):
		return
	var c := _cabin
	_cabin = null
	var tw := c.create_tween()
	tw.tween_property(c, "volume_db", -50.0, 1.2)
	tw.tween_callback(c.queue_free)


## Freefall rush that follows your speed, softens under the canopy and stops
## on landing.
func _attach_wind_audio() -> void:
	var s := sfx.stream("wind_loop")
	if s == null:
		return
	_make_loop(s)
	_wind2d = AudioStreamPlayer.new()
	_wind2d.stream = s
	_wind2d.volume_db = -30.0
	add_child(_wind2d)
	_wind2d.play()


func _update_wind(delta: float) -> void:
	if _wind2d == null or not is_instance_valid(_wind2d) or player == null:
		return
	var want := -60.0
	if player.mode == Player.Mode.FREEFALL:
		want = lerpf(-16.0, -4.0, clampf(-player.velocity.y / 70.0, 0.0, 1.0))
	elif player.mode == Player.Mode.CHUTE:
		want = -20.0
	_wind2d.volume_db = lerpf(_wind2d.volume_db, want, clampf(delta * 3.0, 0.0, 1.0))
	_wind2d.pitch_scale = lerpf(_wind2d.pitch_scale, 1.15 if player.mode == Player.Mode.FREEFALL else 0.85, clampf(delta * 2.0, 0.0, 1.0))
	if player.mode == Player.Mode.GROUND and _wind2d.volume_db < -45.0:
		_wind2d.queue_free()
		_wind2d = null


func _make_loop(s: AudioStream) -> void:
	if s is AudioStreamWAV:
		var wav: AudioStreamWAV = s
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)


func _loop_player(name: String, db: float) -> AudioStreamPlayer3D:
	var s := sfx.stream(name)
	if s == null:
		return null
	if s is AudioStreamWAV:
		var wav: AudioStreamWAV = s
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = db
	p.unit_size = 18.0
	p.max_distance = 400.0
	return p


# ------------------------------------------------------------------- shots --
# Offscreen capture: renders the real scene through the real renderer with no
# window (headless display driver + vulkan) and writes a PNG. Used to actually
# look at the game instead of guessing.
func _run_shot() -> void:
	print("[shot] begin")
	var out := "/tmp/opencode/shot.png"
	var spot := Vector3(0, 0, 0)
	var ang := 0.6
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--at="):
			var parts := a.substr(5).split(",")
			if parts.size() == 2:
				spot = Vector3(float(parts[0]), 0.0, float(parts[1]))
		elif a.begins_with("--yaw="):
			ang = float(a.substr(6))
	if OS.get_cmdline_user_args().has("--menu"):
		if OS.get_cmdline_user_args().has("--loadout"):
			hud._open_loadout()
		for i in 30:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out)
		print("[shot] saved ", out)
		get_tree().quit()
		return
	print("[shot] starting match")
	_start_match()
	if OS.get_cmdline_user_args().has("--plane"):
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--yaw="):
				player.yaw = float(a.substr(6))
		player.pitch = -0.15
		plane.t = 0.3
		for i in 60:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out)
		print("[shot] saved ", out)
		get_tree().quit()
		return
	await get_tree().process_frame
	print("[shot] match up, player=", player)
	var p := player
	if OS.get_cmdline_user_args().has("--tower") and world.villages.towers.size() > 0:
		var tc: Vector2 = world.villages.towers[0].center
		spot = Vector3(tc.x + 14.0, 0.0, tc.y + 10.0)
		ang = atan2(14.0, 10.0)
	if OS.get_cmdline_user_args().has("--inside") and world.villages.towers.size() > 0:
		var tw: Dictionary = world.villages.towers[0]
		var tb := Basis(Vector3.UP, float(tw.yaw))
		var local := tb * Vector3(-1.6, 0, 2.0)
		spot = Vector3(tw.center.x + local.x, 0.0, tw.center.y + local.z)
		# Look toward the stair (+x side, climbing to -z).
		var look := tb * Vector3(1.0, 0, -0.35)
		ang = atan2(-look.x, -look.z)
	if p == null:
		print("[shot] no player")
		get_tree().quit()
		return
	p.mode = Player.Mode.GROUND
	p.alive = true
	var h: float = float(terrain.height_at(spot.x, spot.z))
	if h < Terrain.WATER_LEVEL + 0.5:
		spot = _random_ground_point(200.0)
		h = spot.y
	p.global_position = Vector3(spot.x, h + 2.4, spot.z)
	p.velocity = Vector3.ZERO
	p.yaw = ang
	p.pitch = -0.16
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pitch="):
			p.pitch = float(a.substr(8))
	p.camera.make_current()
	phase = "playing"
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--gun="):
			p.give_weapon(a.substr(6))
	for a in args:
		if a.begins_with("--optic="):
			p.attachments[p.slot]["scope"] = a.substr(8)
			p.refresh_viewmodel()
	if args.has("--hud"):
		p.landed = true
		hud.set_crosshair_visible(true)
	else:
		hud.root.visible = false
	if args.has("--map"):
		hud.toggle_map()
	if args.has("--aim"):
		p.aim_blend = 1.0
		Input.action_press("aim")
	hud.set_prompt("")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var wait := 10
	for a in args:
		if a.begins_with("--wait="):
			wait = int(a.substr(7))
	if args.has("--loot"):
		var kinds := [["armor", "3"], ["helmet", "2"], ["scope", "4x"], ["med", ""], ["weapon", "sniper"], ["energy", ""], ["grenade", ""], ["ammo", ""]]
		var fwd := Basis(Vector3.UP, p.yaw) * Vector3(0, 0, -1)
		var right := Basis(Vector3.UP, p.yaw) * Vector3(1, 0, 0)
		for i in kinds.size():
			var lp := p.global_position + fwd * (4.0 + float(i / 4) * 2.2) + right * (float(i % 4) - 1.5) * 1.6
			_spawn_loot(kinds[i][0], kinds[i][1], ground_at(lp) + Vector3(0, 0.08, 0)).label.visible = true
	for i in wait:
		await get_tree().process_frame
		if args.has("--fire") and i % 6 == 0 and i > 20:
			p.fire_timer = 0.0
			p._try_fire()
			# Some enemy fire crossing the view as well.
			var side := Basis(Vector3.UP, p.yaw) * Vector3(-30, 1.5, -60)
			ballistics.fire(null, p.global_position + side, (p.global_position + Basis(Vector3.UP, p.yaw) * Vector3(25, 1, -50) - (p.global_position + side)).normalized(), "rifle", p.global_position + side, 1)
	if args.has("--bot"):
		for b in bots:
			if is_instance_valid(b):
				var fwd := Basis(Vector3.UP, p.yaw) * Vector3(1.5, 0, -14.0)
				b.state = Bot.State.GROUND
				b.visible = true
				b.global_position = ground_at(p.global_position + fwd) + Vector3(0, 0.1, 0)
				b.arm_weapon("rifle")
				b.vest_level = 2
				b.set_physics_process(false)
				var to: Vector3 = p.global_position - b.global_position
				b.rotation.y = atan2(-to.x, -to.z) + 0.5
				break
		for i in 10:
			await get_tree().process_frame
	if args.has("--reload"):
		p.mags[p.current_id()] = 0
		p.ammo[Weapons.caliber(p.current_id())] = 60
		p.start_reload()
		# Freeze the pose at the moment the magazine is out.
		var at := 0.38
		for a in args:
			if a.begins_with("--at_t="):
				at = float(a.substr(7))
		p.reload_timer = p._reload_dur * (1.0 - at)
		p._update_weapon(0.0)
		p.set_physics_process(false)
	if args.has("--fire"):
		# One volley right before capture so tracers are in flight in the frame.
		get_tree().paused = false
		p.fire_timer = 0.0
		p._try_fire()
		for k in 4:
			var side := Basis(Vector3.UP, p.yaw) * Vector3(-40.0 + k * 3.0, 2.0 + k, -90.0)
			var tgt := Basis(Vector3.UP, p.yaw) * Vector3(30.0, 1.0 + k * 0.5, -40.0)
			ballistics.fire(null, p.global_position + side, (tgt - side).normalized(), "rifle", p.global_position + side, 1)
		# Advance the bullets a few metres without letting them leave the frame.
		for b in ballistics.bullets:
			b["pos"] = b["pos"] + Vector3(b["vel"]) * 0.035
			b["dist"] = float(b["dist"]) + float(b["speed"]) * 0.035
			b["trail"] = float(b["speed"]) * 0.035
			ballistics._place_tracer(b, p.camera)
		ballistics.set_physics_process(false)
		for b in ballistics.bullets:
			var mi: MeshInstance3D = b["mesh"]
			print("[shot] bullet pos=", b["pos"], " mesh vis=", mi.visible, " in_tree=", mi.is_inside_tree(), " xf=", mi.global_transform.origin, " scale=", mi.global_transform.basis.get_scale(), " cam=", p.camera.global_position)
	print("[shot] frames waited")
	await RenderingServer.frame_post_draw
	print("[shot] post draw")
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("[shot] no image")
	else:
		img.save_png(out)
		print("[shot] saved ", out, " size=", img.get_size())
		# Report what the frame actually contains so a blind run is still useful.
		var dark := 0
		var bright := 0
		for y in range(0, img.get_height(), 7):
			for x in range(0, img.get_width(), 7):
				var c := img.get_pixel(x, y)
				var l := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
				if l < 0.02:
					dark += 1
				elif l > 0.5:
					bright += 1
		print("[shot] samples dark=", dark, " bright=", bright)
	get_tree().quit()


# --------------------------------------------------------------- smoke test --
func _run_smoke() -> void:
	print("[smoke] lobby ready, world loot=", world.loot_points.size())
	await get_tree().process_frame
	var tb := world.get_node_or_null("TerrainCollision")
	print("[smoke] terrain node=", tb != null, " shapes=", (tb.get_child_count() if tb != null else -1), " layer=", (tb.collision_layer if tb != null else -1))
	var ray_hits := 0
	var ray_miss := 0
	for gi in range(-4, 4):
		for gj in range(-4, 4):
			var px := float(gi) * 100.0 + 37.0
			var pz := float(gj) * 100.0 + 53.0
			var q := PhysicsRayQueryParameters3D.create(Vector3(px, 300, pz), Vector3(px, -40, pz), 1)
			var hit := get_world_3d().direct_space_state.intersect_ray(q)
			if hit.is_empty():
				ray_miss += 1
			else:
				ray_hits += 1
	print("[smoke] terrain rays hit=", ray_hits, " miss=", ray_miss)
	_start_match()
	print("[smoke] match started plane=", plane != null, " bots=", bots.size(), " loot=", loot_pool.size())
	await get_tree().physics_frame
	await get_tree().physics_frame
	_player_jump(true)
	print("[smoke] jumped, player y=", player.global_position.y, " mode=", player.mode)
	# Fast-forward the drop: teleport to a landing spot and land.
	var drop := _random_ground_point(300.0)
	player.global_position = drop + Vector3(0, 2.0, 0)
	player.open_chute()
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.mode = Player.Mode.GROUND
	player.landed = true
	player.global_position = drop + Vector3(0, 0.4, 0)
	player.velocity = Vector3.ZERO
	player.give_weapon("rifle")
	player.add_armor(50.0)
	print("[smoke] armed=", player.current_id(), " mag=", player.current_mag(), " hp=", player.hp, " armor=", player.armor)
	await get_tree().create_timer(1.0).timeout
	print("[smoke] player after 1s mode=", player.mode, " y=", player.global_position.y, " floor=", player.is_on_floor() if player.has_method("is_on_floor") else "n/a", " vel=", player.velocity)
	var picked := 0
	for l in loot_pool:
		if is_instance_valid(l) and not l.taken and l.global_position.distance_to(player.global_position) < 3.0:
			player.global_position = l.global_position + Vector3(0, 0.3, 0)
			try_pickup(player)
			picked += 1
	print("[smoke] proximity pickups tested=", picked)
	print("[smoke] audio rifle=", sfx.stream("shot_rifle") != null, " ui=", sfx.stream("zone_warn") != null, " loop=", sfx.stream("plane_loop") != null)
	# Fast-forward the plane so every bot jumps, then let them descend.
	if plane != null:
		plane.t = 0.97
	# The plane runs 46 s end to end; for the smoke, drop each bot over its own target.
	for b in bots:
		if is_instance_valid(b) and b.state == Bot.State.PLANE:
			b.jump_from_plane()
			var gy: float = terrain.height_at(b.drop_target.x, b.drop_target.y)
			b.global_position = Vector3(b.drop_target.x, gy + 55.0, b.drop_target.y)
			b.velocity = Vector3.ZERO
	await get_tree().create_timer(0.4).timeout
	print("[smoke] bots jumping: plane=", _count_state(Bot.State.PLANE), " falling=", _count_state(Bot.State.FALL) + _count_state(Bot.State.CHUTE))
	# Force a bot to fight and die so the kill path is exercised.
	var victim: Bot = null
	for b in bots:
		if is_instance_valid(b):
			victim = b
			break
	if victim != null:
		victim.state = Bot.State.GROUND
		victim.global_position = player.global_position + Vector3(4, 1, 0)
		var before := alive
		victim.take_damage(500.0, victim.global_position, true, player)
		print("[smoke] bot killed alive ", before, " -> ", alive)
	if zone != null:
		zone.set_process(true)
		zone.timer = 1.0
		print("[smoke] zone phase=", zone.phase, " radius=", zone.radius, " dps=", zone.damage_per_second())
	await get_tree().create_timer(12.0).timeout
	print("[smoke] after 12s zone phase=", zone.phase if zone else -1, " radius=", zone.radius if zone else -1, " alive=", alive)
	print("[smoke] bots landed=", _count_landed_bots(), " player_kills=", player_kills, " armed_bots=", _count_armed_bots())
	var with_target := 0
	var moving := 0
	var grounded := 0
	var avg_nearest := 0.0
	var n_dbg := 0
	var sample: Bot = null
	for b in bots:
		if not is_instance_valid(b):
			continue
		if sample == null:
			sample = b
		n_dbg += 1
		if b.loot_target != null:
			with_target += 1
		if Vector2(b.velocity.x, b.velocity.z).length() > 0.5:
			moving += 1
		if b.is_on_floor():
			grounded += 1
		avg_nearest += _nearest_weapon(b)
	if n_dbg > 0:
		avg_nearest /= float(n_dbg)
	print("[smoke] bots n=", n_dbg, " with_target=", with_target, " moving=", moving, " on_floor=", grounded, " avg_nearest=", snappedf(avg_nearest, 0.1))
	if sample != null:
		print("[smoke] sample state=", sample.state, " pos=", sample.global_position, " armed=", sample.armed, " loot_scan=", sample._loot_scan, " vel=", sample.velocity, " nearest=", _nearest_weapon(sample))
	await get_tree().create_timer(12.0).timeout
	print("[smoke] after 24s alive=", alive, " armed_bots=", _count_armed_bots(), " kills=", player_kills, " bot_fights_ok=", alive < 19)
	print("[smoke] minimap=", world.minimap_texture)
	print("[smoke] OK")
	get_tree().quit()


func _nearest_weapon(b: Bot) -> float:
	var best := 9999.0
	for l in loot_pool:
		if is_instance_valid(l) and not l.taken and l.kind == "weapon":
			best = minf(best, l.global_position.distance_to(b.global_position))
	return best


func _count_state(st: int) -> int:
	var n := 0
	for b in bots:
		if is_instance_valid(b) and b.state == st:
			n += 1
	return n


func _count_armed_bots() -> int:
	var n := 0
	for b in bots:
		if is_instance_valid(b) and b.armed:
			n += 1
	return n


func _count_landed_bots() -> int:
	var n := 0
	for b in bots:
		if is_instance_valid(b) and b.state == Bot.State.GROUND:
			n += 1
	return n


# ----------------------------------------------------------------- sim test --
# Headless gameplay test: exercises loot, items, ballistics, then fast-forwards
# a whole match with an invulnerable observer. Run with --fixed-fps 60.
func _check(name: String, ok: bool) -> void:
	print("[sim] %s %s" % ["PASS" if ok else "FAIL", name])


func _run_sim() -> void:
	_start_match()
	await get_tree().physics_frame
	_player_jump(true)
	var spot := _random_ground_point(200.0)
	player.global_position = spot + Vector3(0, 1.0, 0)
	player.mode = Player.Mode.GROUND
	player.landed = true
	player.velocity = Vector3.ZERO
	for i in 5:
		await get_tree().physics_frame
	# Loot of every kind.
	var kinds := [["weapon", "rifle"], ["ammo", "5.56"], ["armor", "2"], ["helmet", "1"], ["bandage", ""], ["med", ""],
		["energy", ""], ["scope", "4x"], ["extmag", ""], ["comp", ""], ["grenade", ""], ["weapon", "sniper"], ["armor", "3"], ["ammo", "7.62"], ["ammo", "7.62"], ["ammo", "7.62"]]
	for k in kinds:
		var l := _spawn_loot(k[0], k[1], player.global_position)
		await get_tree().process_frame
		var why := l.block_reason(player)
		var ok := why == "" and l.pickup(player)
		_check("pickup %s %s %s" % [k[0], k[1], why], ok)
		loot_pool.erase(l)
	_check("loadout rifle+sniper", player.loadout.size() == 2 and player.loadout.has("sniper"))
	_check("vest lv3", player.vest_level == 3)
	_check("extmag mag size", player.mag_size("rifle") == 45)
	var att0: Dictionary = player.attachments[player.loadout.find("rifle")]
	_check("rifle has 4x", str(att0.get("scope", "")) == "4x")
	# Healing.
	player.hp = 40.0
	player.use_item("bandage")
	for i in 150:
		await get_tree().physics_frame
	_check("bandage heals 40->55 (%d)" % int(player.hp), absf(player.hp - 55.0) < 1.5)
	player.use_item("med")
	for i in 250:
		await get_tree().physics_frame
	_check("medkit heals (%d)" % int(player.hp), player.hp > 99.0)
	# Reload: empty the mag then reload.
	player.select_slot(player.loadout.find("rifle"))
	for i in 30:
		await get_tree().physics_frame
	player.mags["rifle"] = 0
	player.start_reload()
	for i in 200:
		await get_tree().physics_frame
	_check("reload fills ext mag (%d)" % player.current_mag(), player.current_mag() == 45)
	# Ballistics: a bot 250 m away, aim with holdover, check a hit lands.
	player.select_slot(player.loadout.find("sniper"))
	for i in 40:
		await get_tree().physics_frame
	var target: Bot = null
	for b in bots:
		if is_instance_valid(b):
			target = b
			break
	var dir2 := Vector2(1, 0)
	var tgt_pos := Vector3.ZERO
	for attempt in 30:
		var a := randf() * TAU
		dir2 = Vector2(cos(a), sin(a))
		var p2 := Vector2(player.global_position.x, player.global_position.z) + dir2 * 250.0
		var h := terrain.height_at(p2.x, p2.y)
		if h > 2.0:
			tgt_pos = Vector3(p2.x, h, p2.y)
			break
	target.state = Bot.State.GROUND
	target.set_physics_process(false)
	# Both up in clear air so nothing but the bullet's own drop matters.
	var sky := maxf(player.global_position.y, tgt_pos.y) + 70.0
	target.global_position = Vector3(tgt_pos.x, sky, tgt_pos.z)
	player.global_position = Vector3(player.global_position.x, sky, player.global_position.z)
	player.set_physics_process(false)
	var eye := player.global_position + Vector3(0, Player.EYE, 0)
	var aim := target.global_position + Vector3(0, 1.0, 0)
	var dist := eye.distance_to(aim)
	var tof := dist / float(Weapons.def("sniper")["velocity"])
	var hold := aim + Vector3(0, 0.5 * Ballistics.GRAVITY * tof * tof, 0)
	var hp_before := target.hp
	# Drop check: a level shot into open sky, sampled after ~0.35 s of flight.
	ballistics.fire(player, eye + Vector3(0, 60, 0), Vector3(dir2.x, 0, dir2.y), "sniper", eye, 999001)
	for i in 21:
		await get_tree().physics_frame
	if ballistics.bullets.size() > 0:
		var bp: Vector3 = ballistics.bullets[0]["pos"]
		var fell := eye.y + 60.0 - bp.y
		var flown := Vector2(bp.x - eye.x, bp.z - eye.z).length()
		_check("bullet drop %.2f m after %.0f m (expect ~0.58)" % [fell, flown], fell > 0.45 and fell < 0.75 and flown > 230.0)
	ballistics.clear()
	ballistics.fire(player, eye, (hold - eye).normalized(), "sniper", eye, 999002)
	for i in 40:
		await get_tree().physics_frame
	_check("250m shot with holdover hits (hp %d)" % int(target.hp), target.hp < hp_before)
	player.set_physics_process(true)
	target.set_physics_process(true)
	# Gun handling: recoil pattern is repeatable, fire mode, zeroing.
	player.select_slot(player.loadout.find("rifle"))
	for i in 30:
		await get_tree().physics_frame
	var seq_a: Array = []
	var seq_b: Array = []
	for i in 8:
		seq_a.append(Weapons.recoil_step("rifle", i))
		seq_b.append(Weapons.recoil_step("rifle", i))
	_check("recoil pattern deterministic", seq_a == seq_b and absf(seq_a[0].x) < 0.01 and seq_a[7].x != 0.0)
	_check("rifle starts auto", player.is_auto())
	player.toggle_fire_mode()
	_check("fire mode toggles to single", not player.is_auto())
	player.toggle_fire_mode()
	player.adjust_zero(100)
	player.adjust_zero(100)
	_check("rifle zero 300 (%d)" % player.cur_zero(), player.cur_zero() == 300)
	_check("zero angle sane", Weapons.zero_angle("rifle", 300.0) > 0.0005 and Weapons.zero_angle("rifle", 300.0) < 0.02)
	_check("ammo pools: 5.56=%d 7.62=%d" % [player.ammo_of("5.56"), player.ammo_of("7.62")], player.ammo_of("5.56") > 0 and player.ammo_of("7.62") > 0)
	# Grenade.
	player.global_position = spot + Vector3(0, 1.0, 0)
	var g_before := player.grenades
	player.throw_grenade()
	_check("grenade thrown", player.grenades == g_before - 1)
	for i in 240:
		await get_tree().physics_frame
	# Full match fast-forward.
	player.spawn_protect = 1.0e9
	var t0 := match_time
	var last_print := 0.0
	while alive > 1 and match_time - t0 < 700.0:
		await get_tree().physics_frame
		if match_time - last_print > 30.0:
			last_print = match_time
			print("[sim] t=%d alive=%d zone phase=%d r=%d armed=%d" % [int(match_time), alive, zone.phase, int(zone.radius), _count_armed_bots()])
	print("[sim] match over t=%d alive=%d bullets_live=%d" % [int(match_time), alive, ballistics.bullets.size()])
	_check("match finishes", alive <= 1)
	get_tree().quit()
