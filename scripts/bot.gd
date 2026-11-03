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
var gun_node: Node3D
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
var strafe_dir := 1.0
var strafe_timer := 0.0
var fall_speed := -12.0
var landed := false
var roam_point := Vector2.ZERO
var chute_mesh: MeshInstance3D
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
var heal_timer := 0.0
var _roam_wait := 0.0
var _progress_t := 0.0
var _progress_pos := Vector3.ZERO
var _step := 0.0
var _burst := 0
var _see_cache := {}

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
	reaction = rng.randf_range(0.25, 0.65)
	sight = rng.randf_range(95.0, 165.0)
	aggression = rng.randf_range(0.2, 0.95)


func _ready() -> void:
	add_to_group("bots")
	add_to_group("damageable")
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

	var ps: PackedScene = load("res://assets/characters/mannequin.glb")
	if ps != null:
		rig = ps.instantiate()
		# Slight per-bot tint so a crowd does not look like clones.
		_tint_rig(rig)
		add_child(rig)
		rig.rotation.y = PI
		var aps := rig.find_children("*", "AnimationPlayer", true, false)
		if aps.size() > 0:
			anim = aps[0]
			anim.play("Idle")
		for mi in rig.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).layers = 1
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	gun_node = Node3D.new()
	gun_node.position = Vector3(0.30, 1.32, -0.34)
	gun_node.rotation.y = PI
	gun_node.visible = false
	add_child(gun_node)

	_muzzle_flash = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.34, 0.34)
	_muzzle_flash.mesh = q
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.albedo_color = Color(1.0, 0.8, 0.4, 0.95)
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.no_depth_test = true
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_muzzle_flash.material_override = fm
	_muzzle_flash.visible = false
	_muzzle_flash.position = Vector3(0.30, 1.32, -0.95)
	add_child(_muzzle_flash)

	chute_mesh = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(5.0, 3.9)
	chute_mesh.mesh = pm
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.82, 0.85, 0.90)
	cm.roughness = 0.9
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	chute_mesh.material_override = cm
	chute_mesh.position = Vector3(0, 3.2, 0)
	chute_mesh.visible = false
	add_child(chute_mesh)


func _tint_rig(n: Node) -> void:
	var tint := Color.from_hsv(randf(), 0.30, 0.70)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := mi as MeshInstance3D
		if mesh_inst.mesh == null:
			continue
		for si in range(mesh_inst.mesh.get_surface_count()):
			var base := mesh_inst.get_active_material(si)
			if base is BaseMaterial3D:
				var dup: BaseMaterial3D = (base as BaseMaterial3D).duplicate()
				dup.albedo_color = tint
				dup.roughness = 0.68
				dup.metallic = 0.04
				mesh_inst.set_surface_override_material(si, dup)


func _bot_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var hue := randf()
	m.albedo_color = Color.from_hsv(hue, 0.35, 0.62)
	m.roughness = 0.7
	m.metallic = 0.05
	return m


func head_y() -> float:
	return global_position.y + head_offset


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


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		dead_timer += delta
		velocity.x = move_toward(velocity.x, 0.0, 6.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 6.0 * delta)
		move_and_slide()
		if dead_timer > 9.0:
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
			chute_mesh.visible = true
			_play("Jump_Start")
	move_and_slide()
	if chute:
		chute_mesh.rotation.y = sin(Time.get_ticks_msec() * 0.0009 + randf()) * 0.08
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
	chute_mesh.visible = false
	velocity = Vector3.ZERO
	global_position.y = game_ground_y() + 1.4
	_play("Jump_Land")
	roam_point = drop_target
	if game != null and game.has_method("on_bot_landed"):
		game.on_bot_landed(self)


func _ground(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	alert_timer = maxf(0.0, alert_timer - delta)
	_shoot_logic(delta)
	if heal_timer > 0.0:
		heal_timer -= delta
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
		if heal_timer <= 0.0 and meds > 0:
			meds -= 1
			hp = minf(100.0, hp + 50.0)
		move_and_slide()
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
			strafe_timer -= delta
			if strafe_timer <= 0.0:
				strafe_timer = randf_range(0.7, 1.7)
				strafe_dir = -strafe_dir
			var to_e := (enemy.global_position - global_position).normalized()
			var side := Vector3(-to_e.z, 0, to_e.x) * strafe_dir
			var hold := 16.0
			if d > hold + 6.0:
				target_pos = enemy.global_position
				stop_dist = hold
				want_sprint = true
			elif d < hold - 8.0:
				target_pos = global_position - to_e * 6.0 + side * 4.0
				stop_dist = 0.0
			else:
				target_pos = global_position + side * 4.0
				stop_dist = 0.0
		else:
			enemy = null
			var here := Vector2(global_position.x, global_position.z)
			if game != null and game.zone != null:
				var zc: Vector2 = game.zone.center
				var r: float = game.zone.radius
				# Head for safety early, not when the storm is already on top of us.
				var nr: float = game.zone.next_radius()
				var nc: Vector2 = game.zone.next_center()
				if roam_point.distance_to(nc) > nr * 0.9 or (here.distance_to(zc) > r * 0.85 and roam_point.distance_to(zc) > r * 0.85):
					roam_point = nc + (here - nc).normalized() * (nr * randf_range(0.2, 0.6))
					roam_point += Vector2(randf_range(-10, 10), randf_range(-10, 10))
			if alert_timer > 0.0 and aggression > 0.45 and heard_pos.distance_to(global_position) > 10.0:
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
		# Simple obstacle probe.
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.0, global_position + Vector3.UP * 1.0 + dir * 1.6, 1)
		q.exclude = [get_rid()]
		if not space.intersect_ray(q).is_empty():
			dir = dir.rotated(Vector3.UP, deg_to_rad(70.0))
		if game != null and game.terrain != null and bool(game.terrain.is_water(global_position.x, global_position.z)):
			speed *= 0.6
		velocity.x = move_toward(velocity.x, dir.x * speed, 26.0 * delta)
		velocity.z = move_toward(velocity.z, dir.z * speed, 26.0 * delta)
		if not fighting:
			rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), clampf(delta * 8.0, 0.0, 1.0))
		_blocked -= delta
		if _blocked <= 0.0 and is_on_floor() and dist > 3.0:
			var q2 := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.4, global_position + Vector3.UP * 0.4 + dir * 0.9, 1)
			q2.exclude = [get_rid()]
			if not space.intersect_ray(q2).is_empty():
				velocity.y = 5.2
				_blocked = 1.2

	move_and_slide()
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
			if game != null and game.player != null and game.player.global_position.distance_to(global_position) < 32.0:
				game.play_sfx_at("footstep_%d" % (randi() % 4 + 1), global_position, -3.0)
	if is_on_floor() and planar > 0.4:
		var want := "Sprint" if planar > 5.6 else "Jog_Fwd"
		if want != speed_anim:
			speed_anim = want
			_play(want)
		if anim != null:
			anim.speed_scale = clampf(planar / (6.2 if want == "Sprint" else 4.0), 0.65, 1.5)
	elif state == State.GROUND:
		if speed_anim != "Idle":
			speed_anim = "Idle"
			_play("Idle")


func _pick_roam_point() -> void:
	var c := Vector2(global_position.x, global_position.z)
	var r := 60.0
	if game != null and game.zone != null:
		c = game.zone.next_center()
		r = game.zone.next_radius() * 0.75
	for i in 8:
		var a := randf() * TAU
		var p := c + Vector2(cos(a), sin(a)) * sqrt(randf()) * r
		if game == null or game.terrain == null or not bool(game.terrain.is_water(p.x, p.y)):
			roam_point = p
			return
	roam_point = c


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


func _play(name: String) -> void:
	if anim == null:
		return
	if anim.current_animation == name and anim.is_playing():
		return
	anim.speed_scale = 1.0
	anim.play(name, 0.25)


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
			return armed and armor < 60.0
		"med":
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
		armor = minf(100.0, armor + 50.0)
	elif l.kind == "med":
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
	if gun_node != null:
		for c in gun_node.get_children():
			c.queue_free()
		var gun := Weapons.make_drop_node(id)
		gun.scale = Vector3.ONE * float(d["scale"]) * 0.9
		gun.rotation.y = PI
		gun_node.add_child(gun)
		gun_node.visible = true
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
	rotation.y = lerp_angle(rotation.y, atan2(-aim.x, -aim.z), clampf(delta * 9.0, 0.0, 1.0))
	if fire_timer > 0.0:
		return
	if mag <= 0:
		mag = int(d["mag"])
		fire_timer = float(d["reload"])
		return
	fire_timer = 60.0 / float(d["rpm"]) * (1.0 if dist < 45.0 else 1.35)
	mag -= 1
	_flash = 0.05
	_muzzle_flash.visible = true
	_muzzle_flash.rotation.z = randf() * TAU
	var from := _shot_origin()
	# Aim error: skill, range, target movement and the first shots of a burst.
	var tvel := Vector3.ZERO
	if enemy is CharacterBody3D:
		tvel = (enemy as CharacterBody3D).velocity
	var spread_deg := 0.9 + (1.0 - shoot_skill) * 3.4
	spread_deg += dist * 0.010
	spread_deg += Vector2(tvel.x, tvel.z).length() * 0.20
	spread_deg += maxf(0.0, 3.0 - float(_burst)) * 0.55
	spread_deg *= float(d["spread"]) / 1.35 * 0.5 + 0.5
	_burst += 1
	var spread := deg_to_rad(spread_deg)
	var dir := aim.normalized()
	dir = (dir + Vector3(randf_range(-spread, spread), randf_range(-spread, spread), randf_range(-spread, spread))).normalized()
	var to := from + dir * max_range
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | 4)
	q.exclude = [get_rid()]
	q.collide_with_areas = false
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		var col: Object = hit["collider"]
		to = hit["position"]
		if col != null and col.has_method("take_damage") and col != self:
			var pellets := int(d["pellets"])
			var dmg := float(d["damage"]) * randf_range(0.8, 1.0)
			if pellets > 1:
				# One ray stands in for the whole shotgun spread.
				dmg *= float(pellets) * clampf(1.0 - dist / float(d["range"]), 0.25, 0.8)
			if col is Player:
				dmg *= 0.8
			var hs := false
			if col.has_method("head_y"):
				hs = hit["position"].y >= float(col.call("head_y"))
				if hs:
					dmg *= 1.8
			col.call("take_damage", dmg, hit["position"], hs, self)
			if game != null and game.has_method("spawn_blood"):
				game.spawn_blood(hit["position"])
		elif game != null and game.has_method("spawn_impact"):
			game.spawn_impact(hit["position"], hit.get("normal", Vector3.UP), col)
	if game != null and game.has_method("play_sfx_at"):
		game.play_sfx_at("shot_" + str(d["sound"]), from, 0.85)
	if game != null and game.has_method("bot_shot_fired"):
		game.bot_shot_fired(from, to)
	if game != null and game.has_method("on_gunshot"):
		game.on_gunshot(from, self)


func _shot_origin() -> Vector3:
	return global_position + Vector3(0, 1.30, 0) + -global_basis.z * 0.55


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
		if d > sight:
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
	if armor > 0.0:
		var abs := minf(armor, dmg * 0.5)
		armor -= abs
		dmg -= abs
	hp -= dmg
	hit_flash = 0.25
	if anim != null:
		_play("Hit_Head" if headshot else "Hit_Chest")
		anim.seek(0.0, true)
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
	chute_mesh.visible = false
	gun_node.visible = false
	if anim != null:
		anim.speed_scale = 1.0
		anim.play("Death01", 0.15)
		anim.seek(0.0, true)
	last_killer_node = source if source != null and is_instance_valid(source) else null
	var killer := ""
	if source != null and source.has_method("display_name"):
		killer = str(source.call("display_name"))
	eliminated.emit(self, killer)

