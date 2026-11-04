class_name Bot
extends CharacterBody3D

signal eliminated(victim: Bot, killer_name: String)

enum State { PLANE, FALL, CHUTE, GROUND, DEAD }

const WALK := 4.2
const RUN := 7.0
const GRAVITY := 24.0

var bot_name := "BOT"
var game: Node = null
var state: int = State.PLANE
var hp := 100.0
var armor := 0.0
var alive := true

var rig: Node3D
var anim: AnimationPlayer
var weapon_id := ""
var mag := 0
var armed := false
var kills := 0

var drop_target := Vector2.ZERO
var loot_target: LootPickup = null
var enemy: Node3D = null
var fire_timer := 0.0
var think_timer := 0.0
var shoot_skill := 0.55
var reaction := 0.35
var sight := 130.0
var fall_speed := -12.0
var landed := false
var roam_point := Vector2.ZERO
var chute_node: Node3D
var body: SoldierRig
var speed_anim := "Idle"
var hit_flash := 0.0
var dead_timer := 0.0
var head_offset := 1.50

var _loot_scan := 0.0
var _skip_loot: Array[int] = []
var _last_loot_d := 9999.0
var _loot_stuck := 0.0
var _blocked := 0.0
var _muzzle_flash: MeshInstance3D
var _flash := 0.0

# Awareness.
var alert_timer := 0.0
var heard_pos := Vector3.ZERO
var aggression := 0.5
var meds := 0
var vest_level := 0
var helmet_level := 0
var heal_timer := 0.0
var _roam_wait := 0.0
var _progress_t := 0.0
var _progress_pos := Vector3.ZERO
var _step := 0.0
var _burst := 0
var _see_cache := {}
var _shot_seq := 0
var _col: CollisionShape3D
var _cap: CapsuleShape3D
var crouched := false
var calm_t := 0.0
var fight_moving := false
var _probe_t := 0
var _probe_blocked := false
var _fight_t := 0.0
var _fight_dir := Vector3.FORWARD
var _posture_t := 0.0
var _reload_t := 0.0

var last_killer_node: Node = null

const FOV_COS := 0.42      # ~130 degree cone
const CLOSE_SENSE := 13.0  # always noticed this close


func setup(p_name: String, p_target: Vector2, p_game: Node, seed_n: int) -> void:
	bot_name = p_name
	drop_target = p_target
	game = p_game
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_n
	shoot_skill = rng.randf_range(0.30, 0.82)
	reaction = rng.randf_range(0.35, 0.85)
	sight = rng.randf_range(85.0, 150.0)
	aggression = rng.randf_range(0.2, 0.95)


func _ready() -> void:
	add_to_group("bots")
	add_to_group("damageable")
	# Passengers are inside the hold: nobody should see them through the hull.
	visible = state != State.PLANE
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	floor_max_angle = deg_to_rad(55.0)

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = 1.78
	col.shape = cap
	col.position.y = 0.89
	add_child(col)
	_col = col
	_cap = cap

	body = SoldierRig.new()
	add_child(body)
	rig = body
	anim = body.anim

	_muzzle_flash = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	_muzzle_flash.mesh = q
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.albedo_color = Color(1.0, 0.85, 0.55, 1.0)
	fm.albedo_texture = Weapons.flash_texture()
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.no_depth_test = true
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_muzzle_flash.material_override = fm
	_muzzle_flash.visible = false
	_muzzle_flash.position = Vector3(0.30, 1.32, -0.95)
	add_child(_muzzle_flash)

	chute_node = Parachute.build()
	chute_node.position = Vector3(0, 0.6, 0)
	chute_node.visible = false
	add_child(chute_node)


func head_y() -> float:
	return global_position.y + (1.0 if crouched else head_offset)


func _set_crouch(v: bool) -> void:
	if v == crouched:
		return
	crouched = v
	# Shrink the hitbox with the pose so bullets miss the empty space above.
	_cap.height = 1.2 if v else 1.78
	_col.position.y = _cap.height * 0.5


func display_name() -> String:
	return bot_name


# ------------------------------------------------------------------ states --
func jump_from_plane() -> void:
	if state != State.PLANE:
		return
	state = State.FALL
	fall_speed = -10.0
	velocity = Vector3(randf_range(-2, 2), -10.0, randf_range(-2, 2))
	if game != null and game.plane != null:
		velocity += game.plane.jump_velocity()
	visible = true
	_play("Jump_Start")


var _lod_skip := 0.0
var _lod_mult := 1.0
var _lod_odd := false


## Bodies moved with a bigger step when ticking at half rate far away.
func _move() -> void:
	if _lod_mult > 1.0:
		velocity *= _lod_mult
		move_and_slide()
		velocity /= _lod_mult
	else:
		move_and_slide()


func _physics_process(delta: float) -> void:
	# Far from the player (and out of sight range) bots think and move every
	# other tick with a double step: same behaviour, half the cost.
	_lod_mult = 1.0
	if state == State.GROUND or state == State.DEAD:
		var far: bool = game != null and game.player != null and game.player.global_position.distance_squared_to(global_position) > 180.0 * 180.0
		if far:
			_lod_odd = not _lod_odd
			if _lod_odd:
				_lod_skip = delta
				return
			delta += _lod_skip
			_lod_mult = 2.0
	_lod_skip = 0.0
	if state == State.DEAD:
		dead_timer += delta
		velocity.x = move_toward(velocity.x, 0.0, 6.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 6.0 * delta)
		_move()
		if dead_timer > 7.0:
			# Settle into the ground rather than vanish.
			position.y -= delta * 0.6
		if dead_timer > 10.0:
			queue_free()
		return

	fire_timer = maxf(0.0, fire_timer - delta)
	think_timer -= delta
	_flash = maxf(0.0, _flash - delta)
	_muzzle_flash.visible = _flash > 0.0
	if hit_flash > 0.0:
		hit_flash = maxf(0.0, hit_flash - delta)

	match state:
		State.PLANE:
			_follow_plane(delta)
		State.FALL:
			_fall(delta, false)
		State.CHUTE:
			_fall(delta, true)
		State.GROUND:
			_ground(delta)


func _follow_plane(delta: float) -> void:
	velocity = Vector3.ZERO
	if game != null and game.plane != null:
		var p: DropPlane = game.plane
		var seat := p.seat_position() + p.global_basis * Vector3(randf_range(-0.9, 0.9), -0.1, randf_range(-1.2, 0.4))
		global_position = global_position.lerp(seat, clampf(delta * 6.0, 0.0, 1.0))
		rotation.y = lerp_angle(rotation.y, p.rotation.y, delta * 3.0)


func _fall(delta: float, chute: bool) -> void:
	var to := Vector2(drop_target.x - global_position.x, drop_target.y - global_position.z)
	var dist := to.length()
	var move := to.normalized() * (9.0 if chute else 20.0)
	velocity.x = move_toward(velocity.x, move.x, 16.0 * delta)
	velocity.z = move_toward(velocity.z, move.y, 16.0 * delta)
	if chute:
		velocity.y = move_toward(velocity.y, -8.5, 30.0 * delta)
	else:
		fall_speed = move_toward(fall_speed, -52.0, 80.0 * delta)
		velocity.y = fall_speed
		if global_position.y < game_ground_y() + 95.0 or dist < 18.0:
			state = State.CHUTE
			chute_node.visible = true
			_play("Jump_Start")
	move_and_slide()
	if chute:
		chute_node.rotation.y = sin(Time.get_ticks_msec() * 0.0009 + randf()) * 0.08
	rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.y), delta * 2.0)
	_play("Jump" if not chute else "Idle")
	if is_on_floor() or global_position.y <= game_ground_y() + 0.6:
		_land()


func game_ground_y() -> float:
	if game != null and game.terrain != null:
		return float(game.terrain.height_at(global_position.x, global_position.z))
	return 0.0


func _land() -> void:
	if state == State.GROUND:
		return
	state = State.GROUND
	landed = true
	chute_node.visible = false
	velocity = Vector3.ZERO
	global_position.y = game_ground_y() + 1.4
	_play("Jump_Land")
	roam_point = drop_target
	# Fresh off the plane, people loot first and only fight what is in their face.
	calm_t = randf_range(60.0, 150.0)
	if game != null and game.has_method("on_bot_landed"):
		game.on_bot_landed(self)


func _ground(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	alert_timer = maxf(0.0, alert_timer - delta)
	calm_t = maxf(0.0, calm_t - delta)
	_shoot_logic(delta)
	if heal_timer > 0.0:
		heal_timer -= delta
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
		if heal_timer <= 0.0 and meds > 0:
			meds -= 1
			hp = minf(100.0, hp + 50.0)
		_move()
		_ground_safety()
		_animate_ground()
		return
	if armed and meds > 0 and hp < 55.0 and (enemy == null or not is_instance_valid(enemy)):
		heal_timer = 3.0
		return

	var target_pos := global_position
	var want_sprint := false
	var stop_dist := 0.0

	var fighting := armed and enemy != null and is_instance_valid(enemy) and enemy_visible()
	if not fighting:
		if loot_target == null or not is_instance_valid(loot_target) or loot_target.taken:
			loot_target = null
			_loot_scan -= delta
			if _loot_scan <= 0.0:
				_loot_scan = 0.8 if not armed else 1.6
				loot_target = _find_loot()
	if not armed or (not fighting and loot_target != null):
		if loot_target != null:
			target_pos = loot_target.global_position
			stop_dist = 1.8
			want_sprint = true
		else:
			if Vector2(global_position.x, global_position.z).distance_to(roam_point) < 3.5:
				_pick_roam_point()
			target_pos = Vector3(roam_point.x, global_position.y, roam_point.y)
			stop_dist = 3.0
	else:
		if enemy != null and is_instance_valid(enemy) and enemy_visible():
			var d := global_position.distance_to(enemy.global_position)
			var to_e := (enemy.global_position - global_position)
			to_e.y = 0.0
			to_e = to_e.normalized()
			# Fight at the range the weapon is made for.
			var hold := 45.0
			match Weapons.cls(weapon_id):
				"smg", "pistol":
					hold = 16.0
				"shotgun":
					hold = 8.0
				"dmr", "sniper":
					hold = 90.0
				"lmg":
					hold = 55.0
			# Fire and move in bounds: hold still (standing or crouched) and
			# shoot, then dash to a new spot facing the way you run, then shoot
			# again. Nobody moonwalks.
			_fight_t -= delta
			if _fight_t <= 0.0:
				fight_moving = not fight_moving
				if fight_moving:
					_set_crouch(false)
					_fight_t = randf_range(0.7, 1.5) * (1.6 if d > hold + 10.0 else 1.0)
					var side := Vector3(-to_e.z, 0, to_e.x) * (1.0 if randf() < 0.5 else -1.0)
					var push := 0.0
					if d > hold + 6.0:
						push = 1.0
					elif d < hold - 8.0:
						push = -0.8
					_fight_dir = (side * (1.0 - absf(push) * 0.6) + to_e * push).normalized()
				else:
					_fight_t = randf_range(1.4, 3.4)
					_set_crouch(d > 30.0 and randf() < 0.4 + shoot_skill * 0.35)
			if fight_moving:
				target_pos = global_position + _fight_dir * 6.0
				stop_dist = 0.0
				want_sprint = true
			else:
				target_pos = global_position
				stop_dist = 1.0
		else:
			enemy = null
			_set_crouch(false)
			fight_moving = false
			var here := Vector2(global_position.x, global_position.z)
			if game != null and game.zone != null:
				var zc: Vector2 = game.zone.center
				var r: float = game.zone.radius
				# Head for safety early, not when the storm is already on top of us.
				var nr: float = game.zone.next_radius()
				var nc: Vector2 = game.zone.next_center()
				# Rotate when the storm is coming or we are well outside the
				# next circle; otherwise keep to our own area.
				var must_move: bool = here.distance_to(zc) > r * 0.8 or (game.zone.warning and here.distance_to(nc) > nr * 0.9)
				if must_move and roam_point.distance_to(nc) > nr * 0.85:
					roam_point = nc + (here - nc).normalized() * (nr * randf_range(0.45, 0.8))
					roam_point += Vector2(randf_range(-10, 10), randf_range(-10, 10))
			if alert_timer > 0.0 and aggression > 0.6 and heard_pos.distance_to(global_position) > 10.0:
				# Go and see who is shooting.
				roam_point = Vector2(heard_pos.x, heard_pos.z)
			if here.distance_to(roam_point) < 3.0:
				_roam_wait -= delta
				if _roam_wait <= 0.0:
					_roam_wait = randf_range(1.0, 5.0)
					_pick_roam_point()
			target_pos = Vector3(roam_point.x, global_position.y, roam_point.y)
			stop_dist = 2.5
			want_sprint = alert_timer <= 0.0

	var flat := Vector3(target_pos.x - global_position.x, 0, target_pos.z - global_position.z)
	var dist := flat.length()
	var speed := RUN if want_sprint else WALK
	if crouched:
		speed = 1.8
	if loot_target != null and target_pos.is_equal_approx(loot_target.global_position):
		if dist < _last_loot_d - 0.5:
			_last_loot_d = dist
			_loot_stuck = 0.0
		else:
			_loot_stuck += delta
		if _loot_stuck > 3.5:
			_skip_loot.append(loot_target.get_instance_id())
			loot_target = null
			_loot_stuck = 0.0
			_last_loot_d = 9999.0
			dist = 9999.0
	if dist <= stop_dist:
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
		if loot_target != null and is_instance_valid(loot_target) and not loot_target.taken:
			if loot_target.global_position.distance_to(global_position) < 2.8:
				_take_loot(loot_target)
	else:
		var dir := flat.normalized()
		# Obstacle probe, refreshed every few ticks: walls do not move.
		var space := get_world_3d().direct_space_state
		_probe_t -= 1
		if _probe_t <= 0:
			_probe_t = 4
			var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.0, global_position + Vector3.UP * 1.0 + dir * 1.6, 1)
			q.exclude = [get_rid()]
			_probe_blocked = not space.intersect_ray(q).is_empty()
		if _probe_blocked:
			dir = dir.rotated(Vector3.UP, deg_to_rad(70.0))
		if game != null and game.terrain != null and bool(game.terrain.is_water(global_position.x, global_position.z)):
			speed *= 0.6
		velocity.x = move_toward(velocity.x, dir.x * speed, 26.0 * delta)
		velocity.z = move_toward(velocity.z, dir.z * speed, 26.0 * delta)
		if not fighting or fight_moving:
			rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), clampf(delta * 10.0, 0.0, 1.0))
		_blocked -= delta
		if _blocked <= 0.0 and _probe_t == 4 and is_on_floor() and dist > 3.0:
			var q2 := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.4, global_position + Vector3.UP * 0.4 + dir * 0.9, 1)
			q2.exclude = [get_rid()]
			if not space.intersect_ray(q2).is_empty():
				velocity.y = 5.2
				_blocked = 1.2

	_move()
	_ground_safety()
	_animate_ground()
	# Stuck detection: if we have barely moved in a while, try somewhere else.
	_progress_t += delta
	if _progress_t > 3.0:
		if global_position.distance_to(_progress_pos) < 1.2 and dist > stop_dist + 1.0:
			_pick_roam_point()
			if loot_target != null:
				_skip_loot.append(loot_target.get_instance_id())
				loot_target = null
			if is_on_floor():
				velocity.y = 5.2
		_progress_pos = global_position
		_progress_t = 0.0


func _ground_safety() -> void:
	# Safety net: bilinear height and the collision mesh differ on steep slopes, so a
	# body that ends up buried gets lifted back out instead of falling forever.
	var gy := game_ground_y()
	if game != null and game.terrain != null and bool(game.terrain.is_water(global_position.x, global_position.z)):
		var surface: float = Terrain.WATER_LEVEL + 0.15
		if global_position.y < surface:
			global_position.y = surface
			velocity.y = maxf(velocity.y, 0.0)
	elif global_position.y < gy - 0.4:
		global_position.y = gy + 1.4
		velocity.y = 0.0
	if global_position.y < -20.0:
		global_position = Vector3(roam_point.x, game_ground_y() + 2.0, roam_point.y)


func _animate_ground() -> void:
	var planar := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and planar > 1.0:
		_step += planar * get_physics_process_delta_time()
		if _step > 2.9:
			_step = 0.0
			if game != null and game.player != null and game.player.global_position.distance_to(global_position) < 42.0:
				game.play_sfx_at("step_%s_%d" % [game.surface_at(global_position), randi() % 4 + 1], global_position, 1.0 if planar > 5.5 else -3.0)
	if is_on_floor() and planar > 0.4:
		var want := "Sprint" if planar > 5.6 else ("Jog_Fwd" if planar > 2.6 else "Walk")
		if crouched:
			want = "Crouch_Fwd"
		speed_anim = want
		var ref := 6.2 if want == "Sprint" else (4.0 if want == "Jog_Fwd" else 1.6)
		_play(want, clampf(planar / ref, 0.7, 1.4))
	elif state == State.GROUND:
		speed_anim = "Crouch_Idle" if crouched else "Idle"
		_play(speed_anim)
	# Arms: gun up while fighting, held low otherwise.
	if body != null:
		if armed:
			var fighting_now := enemy != null and is_instance_valid(enemy) and enemy_visible() and not fight_moving
			_reload_t = maxf(0.0, _reload_t - get_physics_process_delta_time())
			body.set_arms("reload" if _reload_t > 0.0 else ("aim" if fighting_now else "idle"))
			var aim_to: Vector3 = (enemy.global_position + Vector3(0, 1.2, 0) - _shot_origin()) if fighting_now else -global_basis.z
			body.aim_dir = aim_to
		else:
			body.set_arms("")
		body.set_gear(vest_level, helmet_level)


func _pick_roam_point() -> void:
	# Wander your own patch of the safe area rather than its centre, so the
	# lobby does not funnel into one spot.
	var here := Vector2(global_position.x, global_position.z)
	var nc := here
	var nr := 1e9
	if game != null and game.zone != null:
		nc = game.zone.next_center()
		nr = maxf(8.0, game.zone.next_radius())
	for i in 10:
		var a := randf() * TAU
		var p := here + Vector2(cos(a), sin(a)) * randf_range(15.0, 70.0)
		if p.distance_to(nc) > nr * 0.85:
			# Outside the next circle: aim for its near edge instead.
			p = nc + (p - nc).normalized() * nr * randf_range(0.45, 0.8)
		if game == null or game.terrain == null or not bool(game.terrain.is_water(p.x, p.y)):
			roam_point = p
			return
	roam_point = nc


## Someone fired a gun nearby.
func hear_shot(pos: Vector3, shooter: Node) -> void:
	if state != State.GROUND or not alive or shooter == self:
		return
	if enemy != null and is_instance_valid(enemy) and enemy_visible():
		return
	alert_timer = 5.0
	heard_pos = pos
	var to := pos - global_position
	rotation.y = atan2(-to.x, -to.z)
	think_timer = minf(think_timer, reaction)


func _play(name: String, speed := 1.0) -> void:
	if body == null:
		return
	var legs := name
	match name:
		"Jump_Start", "Jump_Land":
			legs = "Jump" if name == "Jump_Start" else "Idle"
	body.set_legs(legs, speed)


# ------------------------------------------------------------------- loot ---
func _find_loot() -> LootPickup:
	if game == null or game.loot_pool == null:
		return null
	var best: LootPickup = null
	var best_d := 130.0 if not armed else 28.0
	var my_tier := int(Weapons.def(weapon_id).get("tier", 0)) if armed else 0
	for l in game.loot_pool:
		if not is_instance_valid(l) or l.taken:
			continue
		if not _wants(l, my_tier):
			continue
		if _skip_loot.has(l.get_instance_id()):
			continue
		var d: float = l.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = l
	return best


func _wants(l: LootPickup, my_tier: int) -> bool:
	match l.kind:
		"weapon":
			return not armed or int(Weapons.def(l.item_id).get("tier", 1)) > my_tier
		"armor":
			return armed and int(l.item_id) > vest_level
		"helmet":
			return armed and int(l.item_id) > helmet_level
		"med", "bandage":
			return armed and meds < 2
	return false


func _take_loot(l: LootPickup) -> void:
	if l == null or l.taken:
		return
	if l.kind == "weapon":
		if armed and game != null and game.has_method("drop_weapon"):
			game.drop_weapon(weapon_id, -1, -1, global_position + Vector3(0.6, 0, 0.6))
		arm_weapon(l.item_id)
	elif l.kind == "armor":
		vest_level = int(l.item_id)
		armor = 100.0
	elif l.kind == "helmet":
		helmet_level = int(l.item_id)
	elif l.kind == "med" or l.kind == "bandage":
		meds += 1
	l.consume()
	if game != null and game.has_method("play_sfx_at"):
		game.play_sfx_at("pickup", global_position, 0.7)
	loot_target = null


func arm_weapon(id: String) -> void:
	weapon_id = id
	armed = true
	var d: Dictionary = Weapons.def(id)
	mag = int(d["mag"])
	if body != null:
		body.set_gun(id)
	speed_anim = ""
	_play("Idle")


# ------------------------------------------------------------------ combat --
func _shoot_logic(delta: float) -> void:
	if not armed or weapon_id == "":
		return
	if think_timer <= 0.0:
		think_timer = randf_range(0.22, 0.45)
		var prev := enemy
		var found := _find_enemy()
		if found != null:
			enemy = found
			if found != prev:
				# Reaction time before the first shot on a new target.
				fire_timer = maxf(fire_timer, reaction * randf_range(0.8, 1.4))
				_burst = 0
		elif enemy != null and (not is_instance_valid(enemy) or not bool(enemy.get("alive"))):
			enemy = null
	if enemy == null or not is_instance_valid(enemy) or not bool(enemy.get("alive")):
		enemy = null
		return
	if not enemy_visible():
		return
	var d: Dictionary = Weapons.def(weapon_id)
	var dist := global_position.distance_to(enemy.global_position)
	var max_range: float = minf(float(d["range"]), sight)
	if dist > max_range:
		return
	var aim_h := 1.15
	if randf() < shoot_skill * 0.18:
		aim_h = 1.55
	var aim := (enemy.global_position + Vector3(0, aim_h, 0)) - _shot_origin()
	if fight_moving:
		# Running between positions: no shooting, and the next stop needs a
		# moment to bring the gun back on target.
		fire_timer = maxf(fire_timer, 0.25)
		return
	rotation.y = lerp_angle(rotation.y, atan2(-aim.x, -aim.z), clampf(delta * 9.0, 0.0, 1.0))
	if fire_timer > 0.0:
		return
	if mag <= 0:
		mag = int(d["mag"])
		fire_timer = float(d["reload"])
		_reload_t = float(d["reload"])
		if game != null and game.player != null and game.player.global_position.distance_to(global_position) < 30.0:
			game.play_sfx_at("reload_out", global_position, -6.0)
		return
	fire_timer = 60.0 / float(d["rpm"]) * (1.15 if dist < 45.0 else 1.6)
	# Fire in bursts with short pauses, like a person re-acquiring the target.
	if bool(d["auto"]) and _burst > 0 and _burst % randi_range(4, 7) == 0:
		fire_timer += randf_range(0.35, 0.8)
	mag -= 1
	_flash = 0.05
	_muzzle_flash.visible = true
	_muzzle_flash.rotation.z = randf() * TAU
	if body != null:
		_muzzle_flash.global_position = body.muzzle_position()
		if game != null and game.player != null and game.player.global_position.distance_to(global_position) < 60.0:
			game.spawn_smoke(_muzzle_flash.global_position, 0.6)
	var from := _shot_origin()
	# Aim error: skill, range, target movement and the first shots of a burst.
	var tvel := Vector3.ZERO
	if enemy is CharacterBody3D:
		tvel = (enemy as CharacterBody3D).velocity
	var spread_deg := 1.2 + (1.0 - shoot_skill) * 3.8
	spread_deg += dist * 0.010
	spread_deg += Vector2(tvel.x, tvel.z).length() * 0.20
	spread_deg += maxf(0.0, 3.0 - float(_burst)) * 0.55
	spread_deg *= float(d["spread"]) / 1.35 * 0.5 + 0.5
	_burst += 1
	var spread := deg_to_rad(spread_deg)
	# Lead the target and hold over for drop, as well as this bot is able to.
	var speed := float(d.get("velocity", 500.0))
	var tof := dist / speed
	var comp := clampf(shoot_skill * 1.15, 0.0, 1.0)
	var aim_pt := enemy.global_position + Vector3(0, aim_h, 0) + tvel * tof * comp
	aim_pt.y += 0.5 * Ballistics.GRAVITY * tof * tof * comp
	var base_dir := (aim_pt - from).normalized()
	var mult := 0.62 if enemy is Player else 0.2
	var pellets := int(d["pellets"])
	_shot_seq += 1
	for i in pellets:
		var s := spread if pellets == 1 else deg_to_rad(float(d["spread"])) * randf_range(0.4, 1.5)
		var dir := (base_dir + Vector3(randf_range(-s, s), randf_range(-s, s), randf_range(-s, s))).normalized()
		if game != null and game.ballistics != null:
			game.ballistics.fire(self, from, dir, weapon_id, _muzzle_flash.global_position, _shot_seq, mult)
	if game != null and game.has_method("play_sfx_at"):
		game.play_sfx_at("shot_" + str(d["sound"]), from, 0.85)
	if game != null and game.has_method("on_gunshot"):
		game.on_gunshot(from, self)


func _shot_origin() -> Vector3:
	return global_position + Vector3(0, 0.95 if crouched else 1.30, 0) + -global_basis.z * 0.55


func _find_enemy() -> Node3D:
	if game == null:
		return null
	var candidates: Array = []
	var p = game.player
	if p != null and p.alive and (p.mode == Player.Mode.GROUND or p.mode == Player.Mode.CHUTE):
		candidates.append(p)
	for b in get_tree().get_nodes_in_group("bots"):
		if b != self and is_instance_valid(b) and (b as Bot).alive and ((b as Bot).state == State.GROUND or (b as Bot).state == State.CHUTE):
			candidates.append(b)
	var fwd := -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var scored: Array = []
	for c in candidates:
		var to: Vector3 = (c as Node3D).global_position - global_position
		var d := to.length()
		# Bots pick fights with each other at shorter range than with you, and
		# barely at all while still looting after the drop.
		var reach := sight if c is Player else sight * 0.5
		if calm_t > 0.0 and c != enemy:
			# Only the aggressive ones start a fight while still looting.
			reach = 18.0 if aggression > 0.72 else 0.0
		if d > reach:
			continue
		var flat := Vector3(to.x, 0, to.z).normalized()
		var in_view: bool = d < CLOSE_SENSE or alert_timer > 0.0 or fwd.dot(flat) > FOV_COS or c == enemy
		if not in_view:
			continue
		# Crouching targets in the distance are harder to spot.
		if c is Player and Input.is_action_pressed("crouch") and d > 55.0:
			continue
		scored.append([d, c])
	scored.sort_custom(func(a, b): return a[0] < b[0])
	var checks := 0
	for e in scored:
		if checks >= 4:
			break
		checks += 1
		if _can_see(e[1]):
			return e[1]
	return null


func _can_see(target: Node3D) -> bool:
	var from := _shot_origin()
	var to := target.global_position + Vector3(0, 1.2, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | 4)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return false
	return hit["collider"] == target


func enemy_visible() -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	var key := enemy.get_instance_id()
	var now := Engine.get_physics_frames()
	if _see_cache.get("id", -1) == key and now - int(_see_cache.get("f", -99)) < 6:
		return bool(_see_cache.get("v", false))
	var from := _shot_origin()
	var to := (enemy as Node3D).global_position + Vector3(0, 1.2, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | 4)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var vis := false
	if not hit.is_empty():
		var col: Object = hit["collider"]
		vis = col == enemy or (col is Node and (col as Node).is_ancestor_of(enemy))
	_see_cache = {"id": key, "f": now, "v": vis}
	return vis


# ------------------------------------------------------------------ damage --
func take_damage(amount: float, _pos: Vector3 = Vector3.ZERO, headshot: bool = false, source: Node = null) -> bool:
	if not alive:
		return false
	var dmg := amount
	if source != null:
		if headshot and helmet_level > 0:
			dmg *= 1.0 - Player.ABSORB[helmet_level]
		elif not headshot and vest_level > 0 and armor > 0.0:
			dmg *= 1.0 - Player.ABSORB[vest_level]
			armor -= amount * 0.45
			if armor <= 0.0:
				vest_level = 0
	hp -= dmg
	hit_flash = 0.25
	if body != null:
		body.flinch(1.4 if headshot else 1.0)
	heal_timer = 0.0
	# Being shot at makes bots fight back.
	if source != null and is_instance_valid(source) and source != self:
		alert_timer = 6.0
		heard_pos = (source as Node3D).global_position
		if enemy == null or not is_instance_valid(enemy) or not enemy_visible():
			enemy = source as Node3D
			var to: Vector3 = heard_pos - global_position
			rotation.y = atan2(-to.x, -to.z)
			think_timer = reaction
	if hp <= 0.0:
		_die(source)
		return true
	return false


func _die(source: Node) -> void:
	if not alive:
		return
	alive = false
	state = State.DEAD
	dead_timer = 0.0
	collision_layer = 0
	collision_mask = 1
	chute_node.visible = false
	if body != null:
		body.die()
	last_killer_node = source if source != null and is_instance_valid(source) else null
	var killer := ""
	if source != null and source.has_method("display_name"):
		killer = str(source.call("display_name"))
	eliminated.emit(self, killer)

