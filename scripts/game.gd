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
	"pistol": 22, "smg": 24, "rifle": 22, "shotgun": 14, "dmr": 8, "lmg": 6, "sniper": 4,
}

var world: WorldBuilder
var terrain: Terrain
var player: Player
var plane: DropPlane
var zone: Zone
var hud: HUD
var sfx: Sfx
var menu_cam: Camera3D

var phase := "boot"      # boot | menu | plane | playing | end
var lobby_ready := false
var seed_value := 20261101
var loot_pool: Array = []
var bots: Array = []
var alive := 1
var total_players := 1
var player_kills := 0
var damage_dealt := 0.0
var match_time := 0.0
var zone_delay := 16.0
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


func _ready() -> void:
	randomize()
	seed_value = 100000 + int(Time.get_unix_time_from_system()) % 899999
	sfx = Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)
	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.play_pressed.connect(_start_match)
	hud.show_menu("GENERATING ISLAND ...")

	menu_cam = Camera3D.new()
	menu_cam.fov = 68.0
	menu_cam.near = 0.1
	menu_cam.far = 2000.0
	add_child(menu_cam)
	menu_cam.make_current()

	await get_tree().process_frame
	_build_world()
	_create_player()
	lobby_ready = true
	phase = "menu"
	hud.show_menu("SEED  %d   ·   %d LOOT SPOTS   ·   %d DROPS" % [seed_value, world.loot_points.size(), MAX_BOTS + 1])
	hud.set_minimap(world.minimap_texture)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if OS.get_cmdline_user_args().has("--smoke"):
		_run_smoke()
	elif OS.get_cmdline_user_args().has("--shot"):
		_run_shot()


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
	player.fired.connect(_on_shot_fired)
	menu_cam.make_current()


# -------------------------------------------------------------------- match --
func _start_match() -> void:
	if not lobby_ready:
		return
	sfx.play_ui("ui_click", -6.0)
	hud.hide_menu()
	hud.hide_end()
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

	# Cinematic chase camera for the drop.
	menu_cam.make_current()
	phase = "plane"
	player.global_position = plane.seat_position()

	# Loot.
	loot_pool.clear()
	for p in world.loot_points:
		var kind := str(p.get("kind", "weapon"))
		var l := LootPickup.new()
		var id := ""
		var amount := 1
		if kind == "weapon":
			id = _weighted_weapon()
		elif kind == "gear":
			var r := randf()
			kind = "armor" if r < 0.34 else ("med" if r < 0.68 else "ammo")
		else:
			kind = "weapon"
			id = _weighted_weapon()
		l.setup(kind, id, amount)
		l.position = Vector3(p["pos"])
		add_child(l)
		loot_pool.append(l)

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
		if weapon_spots.size() > 0 and randf() < 0.80:
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
				var r := randf_range(7.0, 24.0)
				target = Vector3(best_spot.x + cos(a) * r, best_spot.y, best_spot.z + sin(a) * r)
		b.setup(BOT_NAMES[i % BOT_NAMES.size()] + ("" if i < BOT_NAMES.size() else str(i)), Vector2(target.x, target.z), self, seed_value + i * 977)
		add_child(b)
		b.global_position = plane.seat_position() + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
		b.set_meta("jump_at", clampf(jump_t + randf_range(-0.02, 0.02), 0.03, 0.93))
		b.eliminated.connect(_on_bot_eliminated)
		bots.append(b)

	# Zone.
	zone = Zone.new()
	zone.name = "Zone"
	add_child(zone)
	zone.start(430.0)
	zone.set_process(false)
	zone_was_warning = false

	alive = MAX_BOTS + 1
	total_players = alive
	player_kills = 0
	damage_dealt = 0.0
	match_time = 0.0
	zone_delay = 16.0
	zone_acc = 0.0
	winner = false
	last_hud_alive = -1
	hud.set_kills(0)
	hud.set_alive(alive, total_players)
	hud.set_zone(zone.time_left(), zone.radius, zone.phase, false)
	hud.set_prompt("")
	_hud_zone()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_attach_plane_audio()


func _cleanup_match() -> void:
	for l in loot_pool:
		if is_instance_valid(l):
			l.queue_free()
	loot_pool.clear()
	for b in bots:
		if is_instance_valid(b):
			b.queue_free()
	bots.clear()
	if plane != null and is_instance_valid(plane):
		plane.queue_free()
	plane = null
	if zone != null and is_instance_valid(zone):
		zone.queue_free()
	zone = null
	for t in tracers:
		if is_instance_valid(t):
			t.queue_free()
	tracers.clear()
	for i in impacts:
		if is_instance_valid(i):
			i.queue_free()
	impacts.clear()
	if player != null:
		player.mode = Player.Mode.PLANE


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
			if plane != null and plane.active and plane.progress() >= 0.985 and player.mode == Player.Mode.PLANE:
				_player_jump(true)
			if plane != null and not plane.active and player.mode == Player.Mode.PLANE:
				_player_jump(true)
		"playing":
			_update_play(delta)
		"end":
			pass
	_update_mouse_capture()


func _follow_plane_cam(delta: float) -> void:
	if plane == null:
		return
	var want := plane.chase_position()
	cam_shake = maxf(0.0, cam_shake - delta * 2.0)
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * cam_shake * 0.25
	menu_cam.global_position = menu_cam.global_position.lerp(want, clampf(delta * 3.0, 0.0, 1.0)) + jitter
	menu_cam.look_at(plane.global_position + plane.global_basis * Vector3(0, 0, -12.0), Vector3.UP)


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
	if player == null or not is_instance_valid(player):
		return
	_update_airborne_bots()
	if player.landed and zone != null and not zone.is_processing():
		zone.set_process(true)

	# Zone damage.
	if zone != null and zone.is_processing():
		zone_acc += delta
		if zone_acc >= 1.0:
			zone_acc -= 1.0
			var dps := zone.damage_per_second()
			if player.alive and zone.is_outside(player.global_position) and player.mode == Player.Mode.GROUND:
				player.take_damage(dps, player.global_position, false, null)
				hud.show_notice("OUTSIDE THE ZONE  —  MOVE TO SAFETY", 1.4)
			for b in bots:
				if is_instance_valid(b) and b.alive and b.state == Bot.State.GROUND and zone.is_outside(b.global_position):
					b.take_damage(dps, b.global_position, false, null)
		if zone.warning and not zone_was_warning:
			zone_was_warning = true
			sfx.play_ui("zone_warn", -8.0)
			hud.show_notice("THE ZONE IS CLOSING", 2.0)
		elif not zone.warning:
			zone_was_warning = false
		_hud_zone()

	_hud_player()
	_update_prompt()
	_update_minimap()
	hud.set_crosshair_spread(_crosshair_spread())

	if alive <= 1 and player.alive and phase == "playing":
		_win()


func _hud_zone() -> void:
	if zone == null:
		return
	hud.set_zone(zone.time_left(), zone.radius, zone.phase, zone.warning)


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
	var planar := Vector2(player.velocity.x, player.velocity.z).length()
	var s := 4.0 + planar * 0.55
	if player.aim_blend > 0.5:
		s *= 0.35
	if not player.is_on_floor():
		s += 10.0
	return clampf(s, 2.0, 30.0)


func _update_prompt() -> void:
	if player == null:
		hud.set_prompt("")
		return
	if player.mode == Player.Mode.PLANE:
		hud.set_prompt("SPACE  —  JUMP FROM THE PLANE")
		return
	if player.mode == Player.Mode.FREEFALL:
		hud.set_prompt("SPACE  —  DEPLOY PARACHUTE")
		return
	if player.mode == Player.Mode.CHUTE:
		hud.set_prompt("STEER WITH WASD  —  PICK YOUR LANDING SPOT")
		return
	if player.mode != Player.Mode.GROUND:
		hud.set_prompt("")
		return
	var best: LootPickup = null
	var best_d := 3.0
	for l in loot_pool:
		if not is_instance_valid(l) or l.taken:
			continue
		var d: float = l.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = l
	if best != null:
		hud.set_prompt(best.prompt_text())
		best.label.visible = true
	else:
		hud.set_prompt("")
	for l in loot_pool:
		if is_instance_valid(l) and not l.taken:
			l.label.visible = l.global_position.distance_to(player.global_position) < 9.0


func _update_minimap() -> void:
	var enemies: Array = []
	for b in bots:
		if is_instance_valid(b) and b.alive and b.global_position.distance_to(player.global_position) < 95.0:
			enemies.append(b.global_position)
	hud.update_minimap(player.global_position, zone.center if zone != null else Vector2.ZERO, zone.radius if zone != null else 100.0, enemies)


func _update_mouse_capture() -> void:
	if phase == "playing":
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and Input.is_action_just_pressed("fire"):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif phase == "menu" or phase == "end":
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


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
	if phase == "end" and event is InputEventMouseButton and event.pressed:
		_start_match()


func _player_jump(auto: bool) -> void:
	if player == null or player.mode != Player.Mode.PLANE:
		return
	player.jump_from_plane()
	player.velocity += plane.jump_velocity() if plane != null else Vector3.ZERO
	player.camera.make_current()
	phase = "playing"
	if not auto:
		sfx.play_ui("jump_whoosh", -6.0)
	if plane != null and plane.active:
		pass
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_attach_wind_audio()


# ------------------------------------------------------------------ signals --
func _on_health_changed(hp: float, armor: float) -> void:
	hud.update_health(hp, armor)


func _on_weapon_changed(id: String, mag: int, reserve: int) -> void:
	hud.update_weapon(id, mag, reserve)


func _on_ammo_changed(mag: int, reserve: int) -> void:
	hud.update_ammo(mag, reserve)


func _on_hitmarker(headshot: bool, killed: bool) -> void:
	hud.show_hitmarker(headshot, killed)
	sfx.play_ui("headshot" if headshot else "hitmarker", -10.0)


func _on_player_damaged(amount: float, from_dir: Vector3) -> void:
	hud.show_damage(from_dir)
	sfx.play_ui("hit_flesh", -8.0)
	cam_shake = minf(1.4, cam_shake + amount * 0.02)


func _on_player_died(killer: String) -> void:
	if phase == "end":
		return
	phase = "end"
	player.alive = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_death(killer, player_kills, maxi(1, alive))
	sfx.play_ui("defeat", -4.0)
	hud.set_prompt("")


func _on_notice(text: String) -> void:
	hud.show_notice(text, 2.0)


func _on_shot_fired(_id: String, from: Vector3, to: Vector3, _hit: bool) -> void:
	spawn_tracer(from, to)


func _on_bot_eliminated(victim: Bot, killer: String) -> void:
	alive = maxi(0, alive - 1)
	var k := killer if killer != "" else "THE ZONE"
	if killer == "YOU":
		player_kills += 1
		hud.set_kills(player_kills)
		sfx.play_ui("elim", -4.0)
		hud.show_notice("ELIMINATED  " + victim.bot_name, 1.6)
	var col := HUD.ACCENT if killer == "YOU" else HUD.MUTED
	hud.killfeed("%s   >   %s" % [k, victim.bot_name], col)
	hud.set_alive(alive, total_players)
	last_hud_alive = alive
	if alive <= 1 and player != null and player.alive:
		_win()


func _win() -> void:
	if phase == "end":
		return
	phase = "end"
	winner = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_victory(player_kills, int(damage_dealt))
	sfx.play_ui("victory", -3.0)
	hud.set_prompt("")


func on_player_landed() -> void:
	sfx.play_ui("land_thud", -6.0)
	hud.show_notice("FIND A WEAPON  —  LOOK FOR THE GLOW", 3.0)
	zone_delay = 14.0


func on_bot_landed(_bot: Bot) -> void:
	pass


func on_player_damaged(_amount: float, _from: Vector3) -> void:
	pass


# --------------------------------------------------------------------- loot --
func try_pickup(p: Player) -> void:
	if p == null or p.mode != Player.Mode.GROUND:
		return
	var best: LootPickup = null
	var best_d := 3.2
	for l in loot_pool:
		if not is_instance_valid(l) or l.taken:
			continue
		var d: float = l.global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = l
	if best == null:
		return
	if not best.can_pickup(p):
		p.notice.emit("NEED A WEAPON FIRST")
		return
	if best.pickup(p):
		sfx.play_at("pickup", best.global_position, -4.0)
		loot_pool.erase(best)
		hud.set_prompt("")


# ------------------------------------------------------------------- effects --
func spawn_impact(pos: Vector3, normal: Vector3, _col: Object) -> void:
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
	m.albedo_color = Color(0.62, 0.58, 0.50, 0.75)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos + normal * 0.04
	mi.scale = Vector3.ONE * 0.6
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 1.9, 0.22)
	tw.tween_property(mi, "transparency", 1.0, 0.22)
	tw.chain().tween_callback(mi.queue_free)
	impacts.append(mi)
	if impacts.size() > 40:
		impacts.pop_front()


func spawn_tracer(from: Vector3, to: Vector3) -> void:
	var dist := from.distance_to(to)
	if dist < 1.0:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.028, 0.028, dist)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, 0.86, 0.52, 0.75)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = (from + to) * 0.5
	if from.distance_to(to) > 0.01:
		mi.look_at(to, Vector3.UP)
	var tw := mi.create_tween()
	tw.tween_property(mi, "transparency", 1.0, 0.07)
	tw.tween_callback(mi.queue_free)
	tracers.append(mi)
	if tracers.size() > 60:
		var old = tracers.pop_front()
		if is_instance_valid(old):
			old.queue_free()


func bot_shot_fired(from: Vector3, to: Vector3) -> void:
	spawn_tracer(from, to)


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
	player.take_damage(15.0, p, false, null)


# -------------------------------------------------------------------- audio --
func _attach_plane_audio() -> void:
	if plane == null:
		return
	var p := _loop_player("plane_loop", -10.0)
	if p != null:
		plane.add_child(p)
		p.global_position = plane.global_position
		p.play()


func _attach_wind_audio() -> void:
	var p := _loop_player("wind_loop", -16.0)
	if p != null:
		add_child(p)
		p.global_position = player.global_position
		p.play()
		var tw := p.create_tween()
		tw.tween_property(p, "volume_db", -26.0, 6.0)


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
	print("[shot] starting match")
	_start_match()
	await get_tree().process_frame
	print("[shot] match up, player=", player)
	var p := player
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
	phase = "playing"
	hud.root.visible = false
	hud.set_prompt("")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for i in 10:
		await get_tree().process_frame
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
