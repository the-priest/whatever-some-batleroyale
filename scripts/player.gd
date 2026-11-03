class_name Player
extends CharacterBody3D

signal health_changed(hp: float, armor: float)
signal weapon_changed(id: String, mag: int, reserve: int)
signal ammo_changed(mag: int, reserve: int)
signal hitmarker(headshot: bool, killed: bool)
signal died(killer: String)
signal damaged(amount: float, from_dir: Vector3)
signal notice(text: String)
signal fired(id: String, from: Vector3, to: Vector3, hit: bool)

enum Mode { PLANE, FREEFALL, CHUTE, GROUND }

const WALK := 5.6
const SPRINT := 8.4
const CROUCH := 2.7
const ACCEL := 42.0
const AIR_ACCEL := 9.0
const GRAVITY := 24.0
const JUMP := 5.0
const EYE := 1.62
const CROUCH_EYE := 1.05
const TERMINAL := -58.0
const CHUTE_FALL := -9.0

var mode: int = Mode.PLANE
var game: Node = null
var camera: Camera3D
var view: Node3D
var gun_holder: Node3D

var hp: float = 100.0
var armor: float = 0.0
var alive := true
var kills := 0

var mouse_sens := 0.0022
var yaw := 0.0
var pitch := 0.0
var recoil_pitch := 0.0
var recoil_yaw := 0.0
var bob := 0.0
var sway := Vector2.ZERO
var look_delta := Vector2.ZERO

var loadout: Array[String] = []
var slot := 0
var mags: Dictionary = {}      # id -> rounds in mag
var reserves: Dictionary = {}  # id -> reserve
var fire_timer := 0.0
var reload_timer := 0.0
var reloading := false
var aiming := false
var aim_blend := 0.0
var shots_fired := 0
var shots_hit := 0
var last_shot := 0.0
var chute_open := false
var freefall_speed := 0.0
var landed := false
var spawn_protect := 0.0

var flash: MeshInstance3D
var flash_light: OmniLight3D
var flash_time := 0.0
var muzzle: Node3D
var chute_mesh: MeshInstance3D
var cam_base := Vector3(0, EYE, 0)

var _gun_scale := 1.0
var _step_dist := 0.0
var _damage_flash := 0.0
var _coyote := 0.0


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 4
	floor_max_angle = deg_to_rad(50.0)

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.75
	col.shape = cap
	col.position.y = 0.875
	add_child(col)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 82.0
	camera.near = 0.08
	camera.far = 1200.0
	camera.position = cam_base
	camera.cull_mask = 0xFFFFF
	add_child(camera)
	camera.make_current()

	view = Node3D.new()
	view.name = "Viewmodel"
	camera.add_child(view)
	gun_holder = Node3D.new()
	view.add_child(gun_holder)

	flash = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.30, 0.30)
	flash.mesh = q
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.albedo_color = Color(1.0, 0.82, 0.42, 0.95)
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.no_depth_test = true
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	flash.material_override = fm
	flash.visible = false
	flash.layers = 4
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.add_child(flash)

	flash_light = OmniLight3D.new()
	flash_light.light_color = Color(1.0, 0.78, 0.42)
	flash_light.light_energy = 0.0
	flash_light.omni_range = 3.2
	flash_light.shadow_enabled = false
	view.add_child(flash_light)

	chute_mesh = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(5.4, 4.2)
	chute_mesh.mesh = pm
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.86, 0.88, 0.92)
	cm.roughness = 0.85
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	cm.emission_enabled = true
	cm.emission = Color(0.30, 0.36, 0.46)
	cm.emission_energy_multiplier = 0.25
	chute_mesh.material_override = cm
	chute_mesh.position = Vector3(0, 2.6, 0.4)
	chute_mesh.rotation.x = deg_to_rad(-12)
	chute_mesh.visible = false
	add_child(chute_mesh)
	_emit_health()
	_emit_weapon()


func _unhandled_input(event: InputEvent) -> void:
	if not alive:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm: InputEventMouseMotion = event
		look_delta += mm.relative
		yaw -= mm.relative.x * mouse_sens * (0.55 if aiming else 1.0)
		pitch -= mm.relative.y * mouse_sens * (0.55 if aiming else 1.0)
		pitch = clampf(pitch, deg_to_rad(-89.0), deg_to_rad(89.0))
		sway += mm.relative * 0.00012
		sway = sway.clamp(Vector2(-0.06, -0.06), Vector2(0.06, 0.06))


func _physics_process(delta: float) -> void:
	if not alive:
		return
	flash_time = maxf(0.0, flash_time - delta)
	flash.visible = flash_time > 0.0
	flash_light.light_energy = 3.6 if flash_time > 0.0 else 0.0
	spawn_protect = maxf(0.0, spawn_protect - delta)

	match mode:
		Mode.PLANE:
			_passenger(delta)
		Mode.FREEFALL:
			_freefall(delta)
		Mode.CHUTE:
			_chute(delta)
		Mode.GROUND:
			_ground(delta)

	_update_camera(delta)
	_update_weapon(delta)


func _passenger(_delta: float) -> void:
	velocity = Vector3.ZERO
	if game != null and game.has_method("plane_seat_position"):
		global_position = game.plane_seat_position()
	elif game != null and game.get("plane") != null:
		global_position = game.plane.global_position + Vector3(0, 1.0, 0)
	rotation.y = 0.0


func _freefall(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var basis_yaw := Basis(Vector3.UP, yaw)
	var wish := basis_yaw * Vector3(input.x, 0.0, input.y)
	var dive := 1.0 + (0.55 if Input.is_action_pressed("move_forward") else 0.0)
	freefall_speed = move_toward(freefall_speed, TERMINAL * dive, 90.0 * delta)
	var target := wish * (26.0 if not Input.is_action_pressed("sprint") else 34.0)
	velocity.x = move_toward(velocity.x, target.x, 30.0 * delta)
	velocity.z = move_toward(velocity.z, target.z, 30.0 * delta)
	velocity.y = freefall_speed
	if game != null and game.has_method("clamp_airborne"):
		velocity = game.clamp_airborne(global_position, velocity, delta)
	move_and_slide()
	if Input.is_action_just_pressed("jump"):
		open_chute()
	# Auto-deploy as a safety net so a first-time player does not splat while sightseeing.
	if mode == Mode.FREEFALL and game != null and game.terrain != null:
		var agl: float = global_position.y - float(game.terrain.height_at(global_position.x, global_position.z))
		if agl < 68.0 and agl > -2.0:
			open_chute()
	_check_ground_contact()


func _chute(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var basis_yaw := Basis(Vector3.UP, yaw)
	var wish := basis_yaw * Vector3(input.x, 0.0, input.y)
	var target := wish * 11.0
	velocity.x = move_toward(velocity.x, target.x, 8.0 * delta)
	velocity.z = move_toward(velocity.z, target.z, 8.0 * delta)
	velocity.y = move_toward(velocity.y, CHUTE_FALL, 30.0 * delta)
	move_and_slide()
	chute_mesh.rotation.y = sin(Time.get_ticks_msec() * 0.001) * 0.1
	if is_on_floor():
		_land()


func _ground(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var crouch := Input.is_action_pressed("crouch")
	var speed := CROUCH if crouch else (SPRINT if Input.is_action_pressed("sprint") else WALK)
	if aiming:
		speed *= 0.62
	if reloading:
		speed *= 0.92
	var basis_yaw := Basis(Vector3.UP, yaw)
	var wish := basis_yaw * Vector3(input.x, 0.0, input.y)
	var target := wish * speed * (0.55 if not is_on_floor() else 1.0)
	var accel := ACCEL if is_on_floor() else AIR_ACCEL
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
		_coyote = 0.12
	else:
		_coyote = maxf(0.0, _coyote - delta)
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP
			_coyote = 0.0
		elif _coyote > 0.0 and Input.is_action_just_pressed("jump"):
			velocity.y = JUMP
	velocity = velocity.limit_length(60.0)
	move_and_slide()
	# Terrain mesh vs bilinear height can differ by up to a metre on a slope, and a
	# one-sided trimesh lets a buried capsule fall straight through the island.
	if game != null and game.terrain != null:
		var gy: float = float(game.terrain.height_at(global_position.x, global_position.z))
		if bool(game.terrain.is_water(global_position.x, global_position.z)):
			var surface: float = Terrain.WATER_LEVEL + 0.15
			if global_position.y < surface:
				global_position.y = surface
				velocity.y = maxf(velocity.y, 0.0)
		elif global_position.y < gy - 0.6:
			global_position.y = gy + 1.2
			velocity.y = 0.0
	# Wall-less cliff safety: never let the player fall out of the island.
	if global_position.y < -18.0:
		force_respawn()

	# Footsteps + bob.
	var planar := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and planar > 1.2:
		bob += delta * planar * 1.5
		_step_dist += planar * delta
		if _step_dist > (2.4 if Input.is_action_pressed("sprint") else 3.1):
			_step_dist = 0.0
			_footstep()
	if Input.is_action_just_pressed("reload"):
		start_reload()
	if Input.is_action_just_pressed("swap_weapon"):
		cycle_weapon()
	if Input.is_action_just_pressed("slot_1"):
		select_slot(0)
	if Input.is_action_just_pressed("slot_2"):
		select_slot(1)
	if Input.is_action_just_pressed("interact"):
		_try_pickup()
	aiming = Input.is_action_pressed("aim") and not reloading
	fire_timer = maxf(0.0, fire_timer - delta)
	if reloading:
		reload_timer -= delta
		if reload_timer <= 0.0:
			_finish_reload()
	if Input.is_action_pressed("fire") and fire_timer <= 0.0 and not reloading:
		if has_gun():
			if aiming or true:
				_try_fire()
		else:
			if Input.is_action_just_pressed("fire"):
				notice.emit("NO WEAPON  —  PRESS E TO PICK ONE UP")


func _check_ground_contact() -> void:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 0.2
	var to := from + Vector3.DOWN * 3.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty() or is_on_floor():
		_land()


func _land() -> void:
	if not chute_open and mode == Mode.FREEFALL:
		var terrain_y := -100.0
		if game != null and game.terrain != null:
			terrain_y = game.terrain.height_at(global_position.x, global_position.z)
		if global_position.y - terrain_y > 14.0:
			hp = 0.0
			_emit_health()
			died.emit("THE GROUND")
			alive = false
			return
	mode = Mode.GROUND
	chute_open = false
	chute_mesh.visible = false
	landed = true
	velocity.y = 0.0
	spawn_protect = 1.0
	notice.emit("LOOT A WEAPON  —  E")
	if game != null and game.has_method("on_player_landed"):
		game.on_player_landed()


func open_chute() -> void:
	if mode != Mode.FREEFALL:
		return
	mode = Mode.CHUTE
	chute_open = true
	chute_mesh.visible = true
	notice.emit("PARACHUTE DEPLOYED")


func _update_camera(delta: float) -> void:
	# Recoil decay.
	recoil_pitch = lerpf(recoil_pitch, 0.0, clampf(delta * 7.0, 0.0, 1.0))
	recoil_yaw = lerpf(recoil_yaw, 0.0, clampf(delta * 7.0, 0.0, 1.0))
	camera.rotation.x = pitch + recoil_pitch
	camera.rotation.y = yaw + recoil_yaw
	camera.rotation.z = clampf(-Vector2(velocity.x, velocity.z).length() * 0.0, -0.02, 0.02)

	if mode == Mode.FREEFALL or mode == Mode.CHUTE:
		var fall_tilt := 0.0
		if mode == Mode.FREEFALL:
			fall_tilt = deg_to_rad(-18.0)
		camera.rotation.x = clampf(pitch, deg_to_rad(-80.0), deg_to_rad(70.0)) + fall_tilt
		camera.fov = lerpf(camera.fov, 96.0 if mode == Mode.FREEFALL else 80.0, delta * 4.0)
		cam_base = Vector3(0, EYE - 0.30, 0.0)
	else:
		var target_fov := 82.0
		if aiming and has_gun():
			target_fov = 82.0 / float(Weapons.def(loadout[slot]).get("zoom", 1.0))
		camera.fov = lerpf(camera.fov, target_fov, delta * 11.0)

	# Smooth crouch + land dip + foot bob.
	var crouching := Input.is_action_pressed("crouch") and mode == Mode.GROUND
	var target_y := CROUCH_EYE if crouching else EYE
	if mode == Mode.FREEFALL or mode == Mode.CHUTE:
		target_y = cam_base.y
	cam_base.y = lerpf(cam_base.y, target_y, delta * 12.0)
	var bob_y := 0.0
	var bob_x := 0.0
	if mode == Mode.GROUND:
		var planar := Vector2(velocity.x, velocity.z).length()
		var amt := clampf(planar / SPRINT, 0.0, 1.0) * (0.4 if aiming else 1.0)
		bob_y = sin(bob * 2.0) * 0.022 * amt
		bob_x = cos(bob) * 0.020 * amt
	camera.position = camera.position.lerp(Vector3(bob_x, cam_base.y + bob_y, 0.0), clampf(delta * 18.0, 0.0, 1.0))
	_damage_flash = maxf(0.0, _damage_flash - delta)

	# Head hit feedback is a HUD concern; nothing 3D here.


func _update_weapon(delta: float) -> void:
	if not has_gun():
		gun_holder.visible = false
		return
	gun_holder.visible = true
	var d: Dictionary = Weapons.def(loadout[slot])
	var want_ads := 1.0 if (aiming and not reloading) else 0.0
	aim_blend = lerpf(aim_blend, want_ads, clampf(delta * 13.0, 0.0, 1.0))
	var hip: Vector3 = d["hip"]
	var ads: Vector3 = d["ads"]
	var target: Vector3 = hip.lerp(ads, aim_blend)
	# Sway + movement bob on the viewmodel.
	var planar := Vector2(velocity.x, velocity.z).length()
	var idle := sin(Time.get_ticks_msec() * 0.0016) * 0.0035
	target += Vector3(-sway.x * 0.55 + cos(bob) * 0.010 * clampf(planar / SPRINT, 0, 1), idle + sin(bob * 2.0) * 0.008 * clampf(planar / SPRINT, 0, 1) - sway.y * 0.4, 0.0)
	if reloading:
		var t := 1.0 - clampf(reload_timer / maxf(0.01, float(d["reload"])), 0.0, 1.0)
		var dip := sin(t * PI)
		target += Vector3(0.02, -0.16 * dip, -0.02)
		target.z += 0.03 * dip
		gun_holder.rotation.x = -0.55 * dip
		gun_holder.rotation.z = 0.25 * dip
	else:
		gun_holder.rotation.x = lerpf(gun_holder.rotation.x, -recoil_pitch * 1.4, delta * 16.0)
		gun_holder.rotation.z = lerpf(gun_holder.rotation.z, 0.0, delta * 12.0)
	gun_holder.position = gun_holder.position.lerp(target, clampf(delta * 17.0, 0.0, 1.0))
	sway = sway.lerp(Vector2.ZERO, clampf(delta * 6.0, 0.0, 1.0))
	# Muzzle world position for tracers.
	if muzzle != null:
		muzzle.global_position = gun_holder.global_position + gun_holder.global_basis * Vector3(0.0, 0.0, -0.52 * _gun_scale)


func has_gun() -> bool:
	return loadout.size() > 0 and slot < loadout.size()


func current_id() -> String:
	if not has_gun():
		return ""
	return loadout[slot]


func current_mag() -> int:
	if not has_gun():
		return 0
	return int(mags.get(current_id(), 0))


func current_reserve() -> int:
	if not has_gun():
		return 0
	return int(reserves.get(current_id(), 0))


# ------------------------------------------------------------------ combat --
func _try_fire() -> void:
	if not has_gun():
		return
	var id := current_id()
	var d: Dictionary = Weapons.def(id)
	if current_mag() <= 0:
		fire_timer = 0.35
		notice.emit("EMPTY  —  R TO RELOAD")
		if game != null and game.has_method("play_sfx_at"):
			game.play_sfx_at("empty_click", global_position)
		return
	if current_mag() == 1 and current_reserve() <= 0:
		pass
	mags[id] = current_mag() - 1
	fire_timer = 60.0 / float(d["rpm"])
	recoil_pitch += deg_to_rad(float(d["recoil"]) * 0.55 * (0.6 if aim_blend > 0.5 else 1.0))
	recoil_yaw += deg_to_rad(randf_range(-1.0, 1.0) * float(d["recoil"]) * 0.22)
	flash_time = 0.045
	flash.visible = true
	flash.position = gun_holder.position + Vector3(0.0, 0.0, -0.50 * _gun_scale)
	flash.rotation.z = randf() * TAU
	flash_light.position = flash.position
	flash_light.light_energy = 4.5
	gun_holder.position.z += float(d["kick"]) * 0.9
	shake(0.0)
	shots_fired += 1

	var from := camera.global_position
	var dir := -camera.global_basis.z
	var spread_deg := float(d["ads_spread"]) if aim_blend > 0.6 else float(d["spread"])
	spread_deg *= 1.0 + (2.0 if not is_on_floor() else 0.0)
	var pellets := int(d["pellets"])
	var hit_any := false
	var killed_any := false
	var last_to := from + dir * 30.0
	for p in range(pellets):
		var s := spread_deg
		if pellets > 1:
			s *= randf_range(0.4, 1.5)
		var ang := randf() * TAU
		var rad := deg_to_rad(s) * sqrt(randf())
		var offset := camera.global_basis * Vector3(cos(ang) * rad, sin(ang) * rad, 0.0)
		var shot_dir := (dir + offset).normalized()
		var to := from + shot_dir * float(d["range"])
		var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4)
		q.exclude = [get_rid()]
		q.collide_with_areas = true
		var space := get_world_3d().direct_space_state
		var hit := space.intersect_ray(q)
		last_to = to
		if not hit.is_empty():
			var col: Object = hit["collider"]
			var pos: Vector3 = hit["position"]
			last_to = pos
			var headshot := false
			if col != null and col.has_method("head_y"):
				headshot = pos.y >= float(col.call("head_y"))
			var falloff := clampf(1.0 - (from.distance_to(pos) / maxf(1.0, float(d["range"]))) * 0.45, 0.45, 1.0)
			var dmg := float(d["damage"]) * falloff
			if headshot:
				dmg *= float(d["head"])
			if col != null and col.has_method("take_damage"):
				var res = col.call("take_damage", dmg, pos, headshot, self)
				hit_any = true
				shots_hit += 1
				if res is bool and res:
					killed_any = true
			elif col != null and col.has_method("impact"):
				col.call("impact", pos, shot_dir)
			spawn_impact(pos, hit.get("normal", Vector3.UP), col)
	fired.emit(id, from, last_to, hit_any)
	if hit_any:
		hitmarker.emit(false, killed_any)
	if game != null and game.has_method("play_sfx_at"):
		game.play_sfx_at(str(d["sound"]), from, 1.0)
	if game != null and game.has_method("shake"):
		game.shake(float(d["kick"]) * 20.0)
	_emit_ammo()


func spawn_impact(pos: Vector3, normal: Vector3, col: Object) -> void:
	if game != null and game.has_method("spawn_impact"):
		game.spawn_impact(pos, normal, col)


func start_reload() -> void:
	if not has_gun() or reloading:
		return
	var id := current_id()
	var d: Dictionary = Weapons.def(id)
	if current_mag() >= int(d["mag"]) or current_reserve() <= 0:
		if current_reserve() <= 0:
			notice.emit("NO AMMO")
		return
	reloading = true
	reload_timer = float(d["reload"])
	if game != null and game.has_method("play_sfx_at"):
		game.play_sfx_at("reload_out", global_position, 0.6)


func _finish_reload() -> void:
	reloading = false
	var id := current_id()
	var d: Dictionary = Weapons.def(id)
	var need := int(d["mag"]) - current_mag()
	var take := mini(need, current_reserve())
	mags[id] = current_mag() + take
	reserves[id] = current_reserve() - take
	if game != null and game.has_method("play_sfx_at"):
		game.play_sfx_at("reload_in", global_position, 0.8)
	_emit_ammo()


func cycle_weapon() -> void:
	if loadout.size() < 2:
		return
	select_slot((slot + 1) % loadout.size())


func select_slot(i: int) -> void:
	if i < 0 or i >= loadout.size():
		return
	if i == slot:
		return
	slot = i
	reloading = false
	reload_timer = 0.0
	fire_timer = 0.25
	_rebuild_viewmodel()
	_emit_weapon()


func give_weapon(id: String, start_mag: int = -1) -> bool:
	if not Weapons.DEFS.has(id):
		return false
	if loadout.has(id):
		var d: Dictionary = Weapons.def(id)
		reserves[id] = mini(int(d["reserve"]), current_reserve() + int(d["mag"]))
		_emit_ammo()
		return false
	var d: Dictionary = Weapons.def(id)
	mags[id] = int(d["mag"]) if start_mag < 0 else start_mag
	reserves[id] = int(d["reserve"])
	if loadout.size() < 2:
		loadout.append(id)
		slot = loadout.size() - 1
	else:
		# Replace the current slot.
		loadout[slot] = id
	_rebuild_viewmodel()
	_emit_weapon()
	return true


func add_ammo(id: String, amount: int) -> void:
	if not loadout.has(id):
		return
	var d: Dictionary = Weapons.def(id)
	reserves[id] = mini(int(d["reserve"]), int(reserves.get(id, 0)) + amount)
	_emit_ammo()


func add_armor(amount: float) -> void:
	armor = minf(100.0, armor + amount)
	_emit_health()


func heal(amount: float) -> void:
	hp = minf(100.0, hp + amount)
	_emit_health()


func take_damage(amount: float, from_pos: Vector3 = Vector3.ZERO, headshot: bool = false, source: Node = null) -> bool:
	if not alive or spawn_protect > 0.0:
		return false
	var dmg := amount
	if armor > 0.0:
		var absorbed := minf(armor, dmg * 0.55)
		armor -= absorbed
		dmg -= absorbed
	hp -= dmg
	_damage_flash = 1.0
	var dir := (from_pos - global_position).normalized() if from_pos != Vector3.ZERO else Vector3.FORWARD
	damaged.emit(dmg, dir)
	if game != null and game.has_method("on_player_damaged"):
		game.on_player_damaged(dmg, from_pos)
	_emit_health()
	if hp <= 0.0:
		alive = false
		var killer := "THE ZONE"
		if source != null and source.has_method("display_name"):
			killer = source.call("display_name")
		died.emit(killer)
	return true


func force_respawn() -> void:
	if game != null and game.has_method("respawn_player"):
		game.respawn_player()


func _try_pickup() -> void:
	if game != null and game.has_method("try_pickup"):
		game.try_pickup(self)


# ------------------------------------------------------------------ helpers --
func _rebuild_viewmodel() -> void:
	for c in gun_holder.get_children():
		c.queue_free()
	if not has_gun():
		return
	var id := current_id()
	var node := Weapons.build_view_model(id)
	gun_holder.add_child(node)
	_gun_scale = float(Weapons.def(id)["scale"])
	node.scale = Vector3.ONE * _gun_scale
	gun_holder.position = Weapons.def(id)["hip"]
	muzzle = Node3D.new()
	gun_holder.add_child(muzzle)
	muzzle.position = Vector3(0, 0, -0.5 * _gun_scale)


func _emit_health() -> void:
	health_changed.emit(hp, armor)


func _emit_weapon() -> void:
	if not has_gun():
		weapon_changed.emit("", 0, 0)
		return
	weapon_changed.emit(current_id(), current_mag(), current_reserve())


func _emit_ammo() -> void:
	ammo_changed.emit(current_mag(), current_reserve())
	weapon_changed.emit(current_id(), current_mag(), current_reserve())


func _footstep() -> void:
	if game != null and game.has_method("play_sfx_at"):
		game.play_sfx_at("footstep_%d" % (randi() % 4 + 1), global_position, 0.22)


func shake(_amt: float) -> void:
	pass


func display_name() -> String:
	return "YOU"


func reset_for_match() -> void:
	alive = true
	hp = 100.0
	armor = 0.0
	kills = 0
	loadout.clear()
	mags.clear()
	reserves.clear()
	slot = 0
	reloading = false
	reload_timer = 0.0
	fire_timer = 0.0
	chute_open = false
	landed = false
	spawn_protect = 0.0
	velocity = Vector3.ZERO
	freefall_speed = 0.0
	mode = Mode.PLANE
	process_mode = Node.PROCESS_MODE_INHERIT
	_emit_health()
	_rebuild_viewmodel()
	_emit_weapon()


func set_plane_mode() -> void:
	mode = Mode.PLANE
	alive = true


func jump_from_plane() -> void:
	mode = Mode.FREEFALL
	freefall_speed = -8.0
	velocity = Vector3(0, -8, 0)
	notice.emit("W TO DIVE  ·  SPACE TO DEPLOY CHUTE")
