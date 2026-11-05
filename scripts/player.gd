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
signal inventory_changed

const MAX_MEDS := 3
const MAX_BANDAGES := 10
const MAX_ENERGY := 4
const MAX_GRENADES := 3

enum Mode { PLANE, FREEFALL, CHUTE, GROUND, VEHICLE }

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
const CHUTE_FALL := -7.5

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
var base_fov := 82.0
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
var ammo: Dictionary = {}      # calibre -> rounds carried
var fire_single: Dictionary = {}  # id -> true when switched to single fire
var zeroing: Dictionary = {}   # id -> metres
var breath := 100.0
var holding_breath := false
var lean := 0.0
var _spray_n := 0
var _since_shot := 9.0
var _scope_sway := Vector2.ZERO
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
var chute_mesh: Node3D
var cam_base := Vector3(0, EYE, 0)

var _gun_scale := 1.0
var _step_dist := 0.0
var _damage_flash := 0.0
var _coyote := 0.0
var trauma := 0.0
var land_dip := 0.0
var sprinting := false
var sprint_blend := 0.0
var equip_t := 1.0
var bloom := 0.0
var bolt_t := -1.0
var kick := Vector3.ZERO
var kick_vel := Vector3.ZERO
var kick_rot := Vector3.ZERO
var kick_rot_vel := Vector3.ZERO
var _cam_roll := 0.0
var _bolt_sound := false
var _reload_dur := 1.0
var _reload_need := 1
var _reload_was_empty := false
var _reload_events: Dictionary = {}
var _mag_node: MeshInstance3D = null
var _mag_rest := Vector3.ZERO
var _was_on_floor := true
var _fall_speed := 0.0
var _sprint_lock := 0.0
var _optic_id := ""
var _freefall_t := 0.0
var _shot_seq := 0
var _pending_hits: Dictionary = {}
var meds := 0
var bandages := 0
var energy := 0
var grenades := 0
var boost := 0.0
var vest_level := 0
var helmet_level := 0
var helmet_hp := 0.0
var attachments: Array = [{}, {}]
var heal_item := ""
var heal_dur := 1.0
var _boost_acc := 0.0
var _throw_cd := 0.0
var heal_timer := 0.0
var healing := false
var in_water := false


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
	camera.fov = base_fov
	camera.near = 0.08
	camera.far = 4000.0
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
	q.size = Vector2(0.22, 0.22)
	flash.mesh = q
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.albedo_color = Color(1.0, 0.85, 0.55, 1.0)
	fm.albedo_texture = Weapons.flash_texture()
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
	# Light the world, not our own gun (it sits 30 cm from the bulb).
	flash_light.light_cull_mask = 0xFFFFF & ~2
	view.add_child(flash_light)

	# Lines run to the shoulders, above and behind the eye, so they frame the
	# view instead of slicing through it.
	chute_mesh = Parachute.build(0, 4.2, Vector3(0.28, 1.75, 0.22))
	chute_mesh.position = Vector3(0, 0.4, 0.3)
	chute_mesh.visible = false
	add_child(chute_mesh)
	_emit_health()
	_emit_weapon()


## Chat (or any text box) owns the keyboard while it is open.
func _locked() -> bool:
	return game != null and game.get("input_locked") == true


## Tests hold actions down with this.
var test_hold: Dictionary = {}


func _ap(action: String) -> bool:
	if test_hold.has(action):
		return true
	return not _locked() and Input.is_action_pressed(action)


func _ajp(action: String) -> bool:
	if action == "jump" and test_jump:
		test_jump = false
		return true
	return not _locked() and Input.is_action_just_pressed(action)


## Tests press jump with this.
var test_jump := false


## Tests drive the player with this instead of the keyboard.
var test_input := Vector2.INF


func _vec(a: String, b: String, c: String, d: String) -> Vector2:
	if test_input != Vector2.INF:
		return test_input
	return Vector2.ZERO if _locked() else Input.get_vector(a, b, c, d)


func _unhandled_input(event: InputEvent) -> void:
	if not alive:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm: InputEventMouseMotion = event
		look_delta += mm.relative
		var k := mouse_sens * _ads_sens_scale()
		yaw -= mm.relative.x * k
		pitch -= mm.relative.y * k
		pitch = clampf(pitch, deg_to_rad(-89.0), deg_to_rad(89.0))
		sway += mm.relative * 0.00012
		sway = sway.clamp(Vector2(-0.06, -0.06), Vector2(0.06, 0.06))


func _ads_sens_scale() -> float:
	if not aiming or not has_gun():
		return 1.0
	return clampf(0.8 / cur_zoom(), 0.1, 0.75)


func _physics_process(delta: float) -> void:
	if Prof.on:
		var t0 := Time.get_ticks_usec()
		_physics_process_body(delta)
		Prof.add("player", Time.get_ticks_usec() - t0)
	else:
		_physics_process_body(delta)


func _physics_process_body(delta: float) -> void:
	if not _pending_hits.is_empty():
		_flush_hits()
	if not alive:
		return
	flash_time = maxf(0.0, flash_time - delta)
	flash.visible = flash_time > 0.0
	flash_light.light_energy = 2.2 if flash_time > 0.0 else 0.0
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
		Mode.VEHICLE:
			_seated(delta)
			_update_weapon(delta)
			return

	_update_camera(delta)
	_update_weapon(delta)
	_update_casings(delta)


func _passenger(_delta: float) -> void:
	velocity = Vector3.ZERO
	if game != null and game.has_method("plane_seat_position"):
		global_position = game.plane_seat_position()
	elif game != null and game.get("plane") != null:
		global_position = game.plane.global_position + Vector3(0, 1.0, 0)
	rotation.y = 0.0


func _freefall(delta: float) -> void:
	var input := _vec("move_left", "move_right", "move_forward", "move_back")
	var basis_yaw := Basis(Vector3.UP, yaw)
	var wish := basis_yaw * Vector3(input.x, 0.0, input.y)
	var dive := 1.0 + (0.55 if _ap("move_forward") else 0.0)
	freefall_speed = move_toward(freefall_speed, TERMINAL * dive, 90.0 * delta)
	var target := wish * (32.0 if not _ap("sprint") else 42.0)
	velocity.x = move_toward(velocity.x, target.x, 30.0 * delta)
	velocity.z = move_toward(velocity.z, target.z, 30.0 * delta)
	velocity.y = freefall_speed
	if game != null and game.has_method("clamp_airborne"):
		velocity = game.clamp_airborne(global_position, velocity, delta)
	move_and_slide()
	# Wind buffet that builds with fall speed.
	trauma = maxf(trauma, clampf(-velocity.y / 62.0, 0.0, 1.0) * 0.42)
	_freefall_t += delta
	# The Space press that jumped out of the plane must not also pull the cord.
	if _ajp("jump") and _freefall_t > 0.6:
		open_chute()
	# Auto-deploy as a safety net so a first-time player does not splat while sightseeing.
	if mode == Mode.FREEFALL and game != null and game.terrain != null:
		var agl: float = global_position.y - float(game.terrain.height_at(global_position.x, global_position.z))
		if agl < 110.0 and agl > -2.0:
			open_chute()
	_check_ground_contact()


func _chute(delta: float) -> void:
	var input := _vec("move_left", "move_right", "move_forward", "move_back")
	var basis_yaw := Basis(Vector3.UP, yaw)
	var wish := basis_yaw * Vector3(input.x, 0.0, input.y)
	# Ram-air canopy: W pushes the nose down for speed, S flares to stretch
	# the glide.
	var fwd_in := -input.y
	var target := wish * (14.0 + maxf(0.0, fwd_in) * 4.0)
	var sink := CHUTE_FALL - maxf(0.0, fwd_in) * 2.5 + maxf(0.0, -fwd_in) * 2.0
	velocity.x = move_toward(velocity.x, target.x, 8.0 * delta)
	velocity.z = move_toward(velocity.z, target.z, 8.0 * delta)
	velocity.y = move_toward(velocity.y, sink, 30.0 * delta)
	if game != null and game.has_method("clamp_airborne"):
		velocity = game.clamp_airborne(global_position, velocity, delta)
	move_and_slide()
	chute_mesh.rotation.y = sin(Time.get_ticks_msec() * 0.001) * 0.1
	if is_on_floor():
		_land()


## Vault / climb in progress: [from, to, t, duration], or empty.
var _mantle: Array = []


## Swimming: afloat chest-deep with your eyes just over the water, weapon
## away. Hold crouch to dive, jump to climb out onto a bank or jetty.
const FLOAT_DEPTH := 1.38
const SWIM_SPEED := 2.9
const SWIM_SPRINT := 4.2
var swimming := false
var diving := false
var _was_wading := false
var air := 100.0
var _stroke_t := 0.0
var _gasp_ok := false
var _drown_t := 0.0


## Water surface under the player, or INF on dry land.
func water_surface() -> float:
	if game == null or game.terrain == null:
		return INF
	var t: Terrain = game.terrain
	var s: float = t.water_surface_at(global_position.x, global_position.z)
	if t.height_at(global_position.x, global_position.z) >= s:
		return INF
	return s


func _swim(delta: float, surf: float, gy: float) -> void:
	if not swimming:
		swimming = true
		var hard := _fall_speed < -7.0
		if game != null:
			game.water_splash(Vector3(global_position.x, surf, global_position.z), hard)
		if hard:
			add_trauma(0.15)
	in_water = true
	sprinting = false
	aiming = false
	# Weapon lowered out of sight while you swim; it comes back up on land.
	equip_t = 0.0
	if reloading:
		reloading = false
	if healing:
		cancel_heal()
	var input := _vec("move_left", "move_right", "move_forward", "move_back")
	var fast := _ap("sprint") and input.y < -0.3
	diving = _ap("crouch")
	var spd := SWIM_SPRINT if fast else SWIM_SPEED
	if diving:
		spd *= 0.8
	var wish := Basis(Vector3.UP, yaw) * Vector3(input.x, 0.0, input.y) * spd
	velocity.x = move_toward(velocity.x, wish.x, 9.0 * delta)
	velocity.z = move_toward(velocity.z, wish.z, 9.0 * delta)
	# Float at the surface (gentle bob), sink while diving.
	var bobv := sin(Time.get_ticks_msec() * 0.0021) * 0.05
	var target_y := surf - FLOAT_DEPTH + bobv
	if diving:
		target_y = maxf(gy + 0.15, global_position.y - 3.0)
	velocity.y = clampf((target_y - global_position.y) * 3.2, -2.0 if diving else -3.5, 2.2)
	_fall_speed = 0.0
	# Climb out: vault onto whatever is in front (bank, jetty, rock).
	if _ajp("jump") and not diving and global_position.y > surf - FLOAT_DEPTH - 0.3:
		if _try_mantle():
			swimming = false
			return
		velocity.y = 2.6
	move_and_slide()
	# Strokes, ripples.
	var planar := Vector2(velocity.x, velocity.z).length()
	_stroke_t -= delta
	var under := camera.global_position.y < surf - 0.05
	if planar > 0.8 and _stroke_t <= 0.0:
		_stroke_t = 0.62 if fast else 0.9
		if not under and game != null:
			if game.sfx != null:
				game.sfx.play_2d("swim_stroke_%d" % (randi() % 3 + 1), -9.0, 0.08)
			game.water_ripple(Vector3(global_position.x, surf + 0.02, global_position.z), 1.0 if fast else 0.8)
	bob += delta * planar * 0.9
	# Air.
	if under:
		air = maxf(0.0, air - delta * 7.0)
		_gasp_ok = true
		if air <= 0.0:
			_drown_t -= delta
			if _drown_t <= 0.0:
				_drown_t = 1.0
				take_damage(10.0, global_position, false, null)
	else:
		if _gasp_ok and air < 70.0 and game != null and game.sfx != null:
			game.sfx.play_2d("gasp", -6.0, 0.05)
		_gasp_ok = false
		air = minf(100.0, air + delta * 35.0)
	if game != null and game.hud != null:
		game.hud.set_swim(under, air, air < 99.0)
	if game != null:
		game.set_underwater(under)


func _ground(delta: float) -> void:
	if not _mantle.is_empty():
		_do_mantle(delta)
		return
	# Deep enough to swim?
	var surf := water_surface()
	if surf != INF and game != null:
		var gy0: float = game.terrain.height_at(global_position.x, global_position.z)
		if surf - gy0 > FLOAT_DEPTH + 0.05 and global_position.y < surf - 0.35:
			_swim(delta, surf, gy0)
			return
	if swimming:
		swimming = false
		diving = false
		if game != null:
			game.set_underwater(false)
			if game.hud != null:
				game.hud.set_swim(false, air, false)
	var input := _vec("move_left", "move_right", "move_forward", "move_back")
	var crouch := _ap("crouch")
	_sprint_lock = maxf(0.0, _sprint_lock - delta)
	sprinting = _ap("sprint") and input.y < -0.3 and not crouch and not aiming and not healing and _sprint_lock <= 0.0 and is_on_floor() and absf(lean) < 0.2
	var speed := CROUCH if crouch else (SPRINT if sprinting else WALK)
	if aiming:
		speed *= 0.62
	if reloading:
		speed *= 0.92
	if healing:
		speed *= 0.45
	if absf(lean) > 0.2:
		speed *= 0.75
	if in_water:
		# Wading: the deeper it is, the slower you go.
		var ws := water_surface()
		var depth := (ws - global_position.y) if ws != INF else 0.0
		speed *= clampf(1.0 - depth * 0.45, 0.45, 0.9)
	if boost > 50.0:
		speed *= 1.06
	var basis_yaw := Basis(Vector3.UP, yaw)
	var wish := basis_yaw * Vector3(input.x, 0.0, input.y)
	var target := wish * speed * (0.55 if not is_on_floor() else 1.0)
	var accel := ACCEL if is_on_floor() else AIR_ACCEL
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)
	if is_on_floor():
		_coyote = 0.12
	else:
		velocity.y -= GRAVITY * delta
		_coyote = maxf(0.0, _coyote - delta)
	if _ajp("jump") and not in_water and velocity.y > -6.0 and _try_mantle():
		return
	if _ajp("jump") and _coyote > 0.0 and not in_water:
		velocity.y = JUMP
		_coyote = 0.0
		if game != null and game.sfx != null:
			game.sfx.play_2d("jump", -12.0, 0.08)
	velocity = velocity.limit_length(60.0)
	if not is_on_floor():
		_fall_speed = minf(_fall_speed, velocity.y)
	var wish_h := Vector3(target.x, 0.0, target.z)
	var grounded_before := is_on_floor()
	move_and_slide()
	_step_up(wish_h, grounded_before, delta)
	if is_on_floor() and not _was_on_floor:
		var impact := clampf(-_fall_speed / 12.0, 0.0, 1.0)
		if impact > 0.15:
			land_dip = impact
			add_trauma(impact * 0.25)
			if impact > 0.4:
				_sfx("land_thud", -10.0)
			elif game != null and game.sfx != null:
				game.sfx.play_2d("step_%s_%d" % [game.surface_at(global_position), randi() % 4 + 1], -6.0, 0.05)
		_fall_speed = 0.0
	_was_on_floor = is_on_floor()
	_was_wading = in_water
	# Terrain mesh vs bilinear height can differ by up to a metre on a slope, and a
	# one-sided trimesh lets a buried capsule fall straight through the island.
	in_water = false
	if game != null and game.terrain != null:
		var gy: float = float(game.terrain.height_at(global_position.x, global_position.z))
		var ws2 := water_surface()
		if ws2 != INF:
			# Wading in the shallows (deep water is handled by _swim).
			in_water = global_position.y < ws2 - 0.05
			if in_water and not _was_wading and game != null:
				game.water_splash(Vector3(global_position.x, ws2, global_position.z), false)
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
		if _step_dist > (2.6 if sprinting else 2.1 if _ap("crouch") else 3.0):
			_step_dist = 0.0
			_footstep()
	if _ajp("reload"):
		start_reload()
	if _ajp("swap_weapon"):
		cycle_weapon()
	if _ajp("fire_mode"):
		toggle_fire_mode()
	if _ajp("zero_up"):
		adjust_zero(100)
	if _ajp("zero_down"):
		adjust_zero(-100)
	_update_lean(delta)
	_update_breath(delta)
	if _ajp("slot_1"):
		select_slot(0)
	if _ajp("slot_2"):
		select_slot(1)
	if _ajp("interact"):
		_try_pickup()
	if _ajp("heal"):
		start_heal()
	if _ajp("use_bandage"):
		use_item("bandage")
	if _ajp("use_med"):
		use_item("med")
	if _ajp("use_energy"):
		use_item("energy")
	_throw_cd = maxf(0.0, _throw_cd - delta)
	if _ajp("grenade"):
		throw_grenade()
	_tick_boost(delta)
	aiming = _ap("aim") and not reloading and not healing and not swimming
	fire_timer = maxf(0.0, fire_timer - delta)
	if reloading:
		reload_timer -= delta
		if reload_timer <= 0.0:
			_finish_reload()
	if healing:
		heal_timer -= delta
		if heal_timer <= 0.0:
			_finish_heal()
	var want_fire := false
	_since_shot += delta
	if _since_shot > 0.32:
		_spray_n = 0
	if has_gun() and not swimming:
		want_fire = _ap("fire") if is_auto() else _ajp("fire")
	if want_fire and healing:
		cancel_heal()
	if want_fire and sprinting:
		# Firing breaks a sprint; the gun needs a moment to come up.
		_sprint_lock = 0.4
		sprinting = false
		fire_timer = maxf(fire_timer, 0.12 * sprint_blend)
	if want_fire and fire_timer <= 0.0 and not reloading and equip_t > 0.75 and bolt_t < 0.0:
		_try_fire()
	elif not has_gun() and _ajp("fire"):
		notice.emit("NO WEAPON  —  PRESS F TO PICK ONE UP")


## Riding in a jeep: the body sits in the seat, the game drives the camera.
var vehicle: Vehicle = null
var seat := -1


func _seated(_delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		mode = Mode.GROUND
		vehicle = null
		return
	var xf := vehicle.seat_transform(seat)
	global_position = xf.origin - xf.basis.y * 0.55
	velocity = vehicle.linear_velocity


## Walk up small ledges (stair edges, kerbs, rubble, floor boards) instead
## of stopping dead against them. Anything taller is a vault.
func _step_up(wish: Vector3, grounded: bool, _delta: float) -> void:
	if not grounded or wish.length() < 0.5:
		return
	# Only when we are actually being held back (wall or a slab lip we ride against).
	var got := Vector2(velocity.x, velocity.z).length()
	if got > wish.length() * 0.6 and not is_on_wall():
		return
	var dir := wish.normalized()
	var probe := dir * 0.25
	if not test_move(global_transform, probe):
		return
	for h in [0.16, 0.3, 0.45]:
		var up := Vector3.UP * float(h)
		if test_move(global_transform, up):
			return
		var raised := global_transform.translated(up)
		if test_move(raised, probe):
			continue
		# Only step onto something solid, not into thin air.
		var space := get_world_3d().direct_space_state
		# Land with the capsule centre well over the ledge, not balanced on its lip.
		var land := global_position + up + dir * 0.48
		if test_move(raised, dir * 0.48):
			continue
		var q := PhysicsRayQueryParameters3D.create(land + Vector3.UP * 0.05, land - Vector3.UP * (float(h) + 0.1), 1 | 4)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		global_position = Vector3(land.x, float(hit["position"].y) + 0.02, land.z)
		velocity.y = 0.0
		return


## PUBG-style vault: a low obstacle in front, a top to stand on and room
## for your body up there -> climb over it.
func _try_mantle() -> bool:
	var space := get_world_3d().direct_space_state
	var fwd := Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)
	var feet := global_position
	var ex: Array[RID] = [get_rid()]
	var q := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 0.55, feet + Vector3.UP * 0.55 + fwd * 1.15, 1 | 4)
	q.exclude = ex
	var wall := space.intersect_ray(q)
	if wall.is_empty():
		q = PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 1.25, feet + Vector3.UP * 1.25 + fwd * 1.15, 1 | 4)
		q.exclude = ex
		wall = space.intersect_ray(q)
		if wall.is_empty():
			return false
	var n: Vector3 = wall.get("normal", -fwd)
	if absf(n.y) > 0.5:
		return false
	var dist: float = (Vector3(wall["position"]) - feet).dot(fwd)
	var probe := feet + fwd * (dist + 0.4) + Vector3.UP * 2.4
	var dq := PhysicsRayQueryParameters3D.create(probe, probe - Vector3.UP * 2.3, 1 | 4)
	dq.exclude = ex
	var top := space.intersect_ray(dq)
	if top.is_empty():
		return false
	var h: float = float(top["position"].y) - feet.y
	if h < 0.45 or h > 2.05:
		return false
	if Vector3(top.get("normal", Vector3.UP)).y < 0.7:
		return false
	# Room to stand (or crouch) up there.
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.5
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = cap
	sq.transform = Transform3D(Basis.IDENTITY, Vector3(top["position"]) + Vector3.UP * 0.85)
	sq.collision_mask = 1 | 4
	sq.exclude = ex
	if not space.intersect_shape(sq, 1).is_empty():
		return false
	# Nothing over your head on the way up.
	var hq := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 1.6, feet + Vector3.UP * (1.7 + h), 1 | 4)
	hq.exclude = ex
	if not space.intersect_ray(hq).is_empty():
		return false
	var to := Vector3(top["position"]) + fwd * 0.25 + Vector3.UP * 0.06
	_mantle = [feet, to, 0.0, 0.28 + h * 0.2]
	velocity = Vector3.ZERO
	cancel_heal()
	add_trauma(0.12)
	land_dip = 0.35
	if game != null and game.sfx != null:
		game.sfx.play_2d("gear_rattle", -6.0, 0.1)
		game.sfx.play_2d("step_stone_%d" % (randi() % 4 + 1), -6.0, 0.05)
	return true


func _do_mantle(delta: float) -> void:
	var from: Vector3 = _mantle[0]
	var to: Vector3 = _mantle[1]
	var dur: float = _mantle[3]
	var t: float = minf(1.0, float(_mantle[2]) + delta / dur)
	_mantle[2] = t
	# Up first, then over the top.
	var up := smoothstep(0.0, 0.7, t)
	var over := smoothstep(0.35, 1.0, t)
	var p := Vector3(lerpf(from.x, to.x, over), lerpf(from.y, to.y + 0.08, up), lerpf(from.z, to.z, over))
	global_position = p
	velocity = Vector3.ZERO
	if t >= 1.0:
		_mantle = []
		global_position = to
		_was_on_floor = true


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
	notice.emit("LOOT A WEAPON  —  F")
	if game != null and game.has_method("on_player_landed"):
		game.on_player_landed()


func open_chute() -> void:
	if mode != Mode.FREEFALL:
		return
	mode = Mode.CHUTE
	chute_open = true
	chute_mesh.visible = true
	# The canopy snaps open: hard jolt, the view punches in, then settles.
	add_trauma(0.7)
	camera.fov -= 10.0
	pitch = clampf(pitch + 0.12, deg_to_rad(-89.0), deg_to_rad(89.0))
	if game != null and game.sfx != null:
		game.sfx.play_2d("chute_snap", -2.0, 0.05)
	notice.emit("PARACHUTE DEPLOYED")


func _update_camera(delta: float) -> void:
	# Recoil: the visual kick recovers, a fraction of it stays as muzzle climb.
	recoil_pitch = lerpf(recoil_pitch, 0.0, clampf(delta * 9.0, 0.0, 1.0))
	recoil_yaw = lerpf(recoil_yaw, 0.0, clampf(delta * 9.0, 0.0, 1.0))
	trauma = maxf(0.0, trauma - delta * 1.8)
	var t := Time.get_ticks_msec() * 0.001
	var shake_amt := trauma * trauma
	var sx := (sin(t * 37.0) + sin(t * 23.0 + 1.3)) * 0.5 * shake_amt * 0.035
	var sy := (sin(t * 31.0 + 0.7) + sin(t * 19.0)) * 0.5 * shake_amt * 0.035
	var sz := sin(t * 27.0 + 2.1) * shake_amt * 0.03
	camera.rotation.x = pitch + recoil_pitch + sx + _scope_sway.y
	camera.rotation.y = yaw + recoil_yaw + sy + _scope_sway.x
	# Lean slightly into strafes.
	var side_speed := (Basis(Vector3.UP, yaw).inverse() * velocity).x if mode == Mode.GROUND else 0.0
	_cam_roll = lerpf(_cam_roll, -side_speed * 0.0035, clampf(delta * 8.0, 0.0, 1.0))
	camera.rotation.z = _cam_roll + sz - lean * 0.22

	if mode == Mode.FREEFALL or mode == Mode.CHUTE:
		var fall_tilt := 0.0
		if mode == Mode.FREEFALL:
			fall_tilt = deg_to_rad(-18.0)
		camera.rotation.x = clampf(pitch, deg_to_rad(-80.0), deg_to_rad(70.0)) + fall_tilt
		camera.fov = lerpf(camera.fov, 96.0 if mode == Mode.FREEFALL else 80.0, delta * 4.0)
		cam_base = Vector3(0, EYE - 0.30, 0.0)
	else:
		var target_fov := base_fov
		if has_gun():
			var zoom := cur_zoom()
			# Optics snap in at the end of the raise instead of zooming smoothly.
			var k := aim_blend if zoom < 1.9 else smoothstep(0.75, 1.0, aim_blend)
			target_fov = lerpf(base_fov, base_fov / zoom, k)
		target_fov += sprint_blend * 6.0
		camera.fov = lerpf(camera.fov, target_fov, clampf(delta * 14.0, 0.0, 1.0))

	# Smooth crouch + land dip + foot bob.
	var crouching := _ap("crouch") and mode == Mode.GROUND
	var target_y := CROUCH_EYE if crouching else EYE
	if mode == Mode.FREEFALL or mode == Mode.CHUTE:
		target_y = cam_base.y
	cam_base.y = lerpf(cam_base.y, target_y, delta * 12.0)
	land_dip = lerpf(land_dip, 0.0, clampf(delta * 7.0, 0.0, 1.0))
	var bob_y := 0.0
	var bob_x := 0.0
	if mode == Mode.GROUND:
		var planar := Vector2(velocity.x, velocity.z).length()
		var amt := clampf(planar / SPRINT, 0.0, 1.0) * lerpf(1.0, 0.25, aim_blend)
		bob_y = sin(bob * 2.0) * 0.024 * amt
		bob_x = cos(bob) * 0.020 * amt
	var lean_off := Basis(Vector3.UP, yaw) * Vector3(lean * 0.45, -absf(lean) * 0.06, 0.0)
	camera.position = camera.position.lerp(Vector3(bob_x, cam_base.y + bob_y - land_dip * 0.12, 0.0) + lean_off, clampf(delta * 18.0, 0.0, 1.0))
	_damage_flash = maxf(0.0, _damage_flash - delta)


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


## Current cone of fire in degrees, the same number the shot code uses.
func current_spread_deg() -> float:
	if not has_gun():
		return 3.0
	var d: Dictionary = Weapons.def(current_id())
	var s := lerpf(float(d["spread"]), float(d["ads_spread"]), aim_blend)
	var planar := Vector2(velocity.x, velocity.z).length()
	s *= 1.0 + clampf(planar / WALK, 0.0, 1.6) * 0.55 * (1.0 - aim_blend * 0.7)
	if _ap("crouch") and is_on_floor():
		s *= 0.8
	if not is_on_floor():
		s = s * 2.2 + 1.0
	s += bloom * float(d["spread"]) * (1.0 - aim_blend * 0.55)
	return s


func current_spread_px() -> float:
	var s := current_spread_deg()
	var h := get_viewport().get_visible_rect().size.y
	return tan(deg_to_rad(s)) / tan(deg_to_rad(camera.fov * 0.5)) * h * 0.5


static func _seg(t: float, a: float, b: float) -> float:
	return smoothstep(a, b, t)


static func _bump(t: float, a: float, b: float) -> float:
	return sin(clampf((t - a) / (b - a), 0.0, 1.0) * PI)


func _update_weapon(delta: float) -> void:
	if not has_gun() or mode != Mode.GROUND or not alive:
		gun_holder.visible = false
		if game != null and game.hud != null:
			game.hud.set_scope(false)
			game.hud.set_reddot(false, false)
		return
	var id := current_id()
	var d: Dictionary = Weapons.def(id)
	var want_ads := 1.0 if (aiming and not reloading and equip_t > 0.6) else 0.0
	aim_blend = move_toward(aim_blend, want_ads, delta * (1.0 / maxf(0.08, float(d.get("ads_time", 0.18)))))
	var ads_e := aim_blend * aim_blend * (3.0 - 2.0 * aim_blend)
	var planar := Vector2(velocity.x, velocity.z).length()
	sprint_blend = lerpf(sprint_blend, 1.0 if sprinting else 0.0, clampf(delta * 10.0, 0.0, 1.0))
	equip_t = minf(1.0, equip_t + delta / 0.38)
	bloom = maxf(0.0, bloom - delta * float(d.get("bloom_recover", 3.2)))

	var hip: Vector3 = Weapons.hip_pos(id)
	var ads: Vector3 = Weapons.ads_pos(id, _optic_id)
	var pos: Vector3 = hip.lerp(ads, ads_e)
	var rot := Vector3.ZERO

	# Idle breathing, walk bob and mouse sway, all damped while aiming.
	var move_k := clampf(planar / SPRINT, 0.0, 1.0) * (1.0 - ads_e * 0.85)
	var tt := Time.get_ticks_msec() * 0.001
	var breathe := (1.0 - ads_e * 0.8)
	pos.y += sin(tt * 1.6) * 0.0035 * breathe
	pos.x += cos(bob) * 0.012 * move_k
	pos.y += -absf(sin(bob)) * 0.014 * move_k
	rot.z += cos(bob) * 0.02 * move_k
	pos.x += -sway.x * 0.55 * (1.0 - ads_e * 0.7)
	pos.y += -sway.y * 0.40 * (1.0 - ads_e * 0.7)
	rot.y += -sway.x * 1.2 * (1.0 - ads_e * 0.7)
	rot.x += -sway.y * 0.8 * (1.0 - ads_e * 0.7)
	sway = sway.lerp(Vector2.ZERO, clampf(delta * 7.0, 0.0, 1.0))

	# Sprint: gun swings down and across.
	var sb := sprint_blend * (1.0 - ads_e)
	pos += Vector3(-0.05, -0.06, 0.04) * sb
	rot += Vector3(-0.30, 0.65, 0.30) * sb
	pos.y += sin(bob * 2.0) * 0.012 * sb

	# Equip: raise from below.
	var e := equip_t * equip_t * (3.0 - 2.0 * equip_t)
	pos.y -= (1.0 - e) * 0.28
	rot.x -= (1.0 - e) * 0.9
	rot.z += (1.0 - e) * 0.4

	# Landing dip.
	pos.y -= land_dip * 0.05
	rot.x -= land_dip * 0.15

	# Reload choreography.
	if reloading:
		var rt := 1.0 - clampf(reload_timer / maxf(0.01, _reload_dur), 0.0, 1.0)
		var pose := _reload_pose(rt, id)
		pos += pose[0]
		rot += pose[1]
	elif _mag_node != null:
		_mag_node.position = _mag_rest
		_mag_node.rotation = Vector3.ZERO

	# Bolt-action cycle after each sniper shot.
	if bolt_t >= 0.0:
		bolt_t += delta / 0.95
		var b := _bump(bolt_t, 0.2, 0.85)
		pos += Vector3(0.015, -0.035, 0.035) * b
		rot += Vector3(0.12, 0.0, 0.42) * b
		if not _bolt_sound and bolt_t > 0.32:
			_bolt_sound = true
			_sfx("bolt", -1.0)
			_eject_casing(false)
		if bolt_t >= 1.0:
			bolt_t = -1.0

	# Recoil springs.
	var k := 210.0
	var damp := 2.0 * sqrt(k) * 0.62
	kick_vel += (-kick * k - kick_vel * damp) * delta
	kick += kick_vel * delta
	kick_rot_vel += (-kick_rot * k - kick_rot_vel * damp) * delta
	kick_rot += kick_rot_vel * delta
	pos += kick * (1.0 - ads_e * 0.45)
	rot += kick_rot * (1.0 - ads_e * 0.5)

	gun_holder.position = pos
	gun_holder.rotation = rot

	# Sniper scope: hide the gun and let the HUD draw the scope.
	var scoped := cur_zoom() >= 1.9 and aim_blend > 0.92
	gun_holder.visible = not scoped
	if game != null and game.hud != null:
		game.hud.set_scope(scoped, cur_scope(), float(d.get("velocity", 700.0)))
		# Red dot and iron sights are real 3D sights now: nothing drawn on the HUD.
		game.hud.set_reddot(false, false)


## Offsets (position, rotation) for a reload at normalised time t.
## Also drives the magazine prop and the timed reload sounds.
func _reload_pose(t: float, id: String) -> Array:
	var pos := Vector3.ZERO
	var rot := Vector3.ZERO
	var tilt := _seg(t, 0.0, 0.14) * (1.0 - _seg(t, 0.84, 1.0))
	if Weapons.cls(id) == "shotgun":
		# Roll the gun over, feed shells one by one, then rack the pump.
		pos += Vector3(-0.02, -0.035, 0.02) * tilt
		rot += Vector3(0.22, 0.10, -0.55) * tilt
		var shells := clampi(_reload_need, 1, 8)
		var span := 0.62 / float(shells)
		for i in shells:
			var a := 0.14 + span * float(i)
			pos.y += _bump(t, a, a + span * 0.8) * 0.018
			rot.x -= _bump(t, a, a + span * 0.8) * 0.05
			_reload_event("shell%d" % i, t >= a + span * 0.5, "reload_in", -6.0)
		var pump := _bump(t, 0.80, 0.94)
		pos.z += pump * 0.05
		rot.x += pump * 0.05
		_reload_event("pump", t >= 0.84, "bolt", 0.0)
		return [pos, rot]

	# Magazine weapons: tilt, mag out, new mag in, slap, charge.
	pos += Vector3(-0.045, -0.015, 0.015) * tilt
	rot += Vector3(0.22, 0.18, 0.26) * tilt
	if _mag_node != null:
		var out := _seg(t, 0.16, 0.30)
		var back_in := _seg(t, 0.40, 0.58)
		var drop := out * (1.0 - back_in)
		_mag_node.position = _mag_rest + Vector3(0.0, -0.42 * drop, 0.05 * drop)
		_mag_node.rotation.x = 0.4 * drop
	_reload_event("out", t >= 0.18, "reload_out", -2.0)
	# Hand reaching for the new mag: the gun dips a touch.
	pos.y -= _bump(t, 0.30, 0.50) * 0.012
	# Slap it home.
	var slap := _bump(t, 0.56, 0.66)
	pos.y += slap * 0.022
	rot.x += slap * 0.06
	_reload_event("in", t >= 0.58, "reload_in", 0.0)
	# Charging handle when the gun ran dry.
	if _reload_was_empty:
		var rack := _bump(t, 0.68, 0.84)
		pos.z += rack * 0.035
		rot.z -= rack * 0.30
		rot.y += rack * 0.12
		_reload_event("rack", t >= 0.74, "bolt", -3.0)
	return [pos, rot]


func _reload_event(key: String, cond: bool, sound: String, db: float) -> void:
	if cond and not _reload_events.has(key):
		_reload_events[key] = true
		_sfx(sound, db)


func _sfx(name: String, db: float) -> void:
	if game != null and game.has_method("play_sfx_at"):
		game.play_sfx_at(name, global_position + Vector3(0, 1.4, 0), db)


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
	return int(ammo.get(Weapons.caliber(current_id()), 0))


func ammo_of(cal: String) -> int:
	return int(ammo.get(cal, 0))


func is_auto() -> bool:
	if not has_gun():
		return false
	return bool(Weapons.def(current_id()).get("auto", false)) and not bool(fire_single.get(current_id(), false))


func cur_zero() -> int:
	if not has_gun():
		return 100
	return int(zeroing.get(current_id(), 100))


# ------------------------------------------------------------------ combat --
func _try_fire() -> void:
	if not has_gun():
		return
	var id := current_id()
	var d: Dictionary = Weapons.def(id)
	if current_mag() <= 0:
		fire_timer = 0.35
		if game != null and game.has_method("play_sfx_at"):
			game.play_sfx_at("empty_click", global_position)
		if current_reserve() > 0:
			start_reload()
		else:
			notice.emit("OUT OF AMMO  —  FIND AMMO OR SWAP (Q)")
		return
	mags[id] = current_mag() - 1
	fire_timer = 60.0 / float(d["rpm"])
	# Spread is measured before this shot adds its own bloom.
	var spread_deg := current_spread_deg()
	var rec := float(d["recoil"]) * (0.62 if aim_blend > 0.5 else 1.0) * recoil_mult()
	if _ap("crouch"):
		rec *= 0.85
	var kick_up := deg_to_rad(rec * 0.55)
	recoil_pitch += kick_up * 0.65
	pitch = clampf(pitch + kick_up * 0.35, deg_to_rad(-89.0), deg_to_rad(89.0))
	var step := Weapons.recoil_step(id, _spray_n)
	kick_up *= step.y * randf_range(0.92, 1.08)
	var side := (step.x + randf_range(-0.08, 0.08)) * rec
	recoil_yaw -= deg_to_rad(side) * 0.35
	yaw -= deg_to_rad(side) * 0.65
	_spray_n += 1
	_since_shot = 0.0
	bloom = minf(float(d.get("bloom_max", 1.4)), bloom + float(d.get("bloom", 0.22)))
	var kick_amt := float(d["kick"]) * (0.8 if recoil_mult() < 1.0 else 1.0)
	kick_vel += Vector3(randf_range(-0.6, 0.6) * kick_amt, kick_amt * 3.0, kick_amt * 26.0)
	kick_rot_vel += Vector3(kick_amt * 34.0, randf_range(-1.0, 1.0) * kick_amt * 6.0, randf_range(-1.0, 1.0) * kick_amt * 10.0)
	flash_time = 0.05
	flash.visible = true
	flash.position = gun_holder.position + gun_holder.basis * Vector3(0.0, 0.01, -0.52 * _gun_scale)
	flash.rotation.z = randf() * TAU
	flash.scale = Vector3.ONE * randf_range(0.8, 1.3) * (1.6 if Weapons.cls(id) in ["shotgun", "sniper"] else 1.0)
	flash_light.position = flash.position
	flash_light.light_energy = 2.2
	add_trauma(clampf(kick_amt * 2.2, 0.02, 0.3))
	shots_fired += 1
	if not bool(d.get("bolt", false)):
		_eject_casing(Weapons.cls(id) == "shotgun")
	if game != null and game.has_method("spawn_smoke") and muzzle != null:
		game.spawn_smoke(muzzle.global_position, 1.4 if Weapons.cls(id) in ["shotgun", "sniper"] else 0.8)
	if bool(d.get("bolt", false)):
		bolt_t = 0.0
		_bolt_sound = false

	var from := camera.global_position
	var dir := -camera.global_basis.z
	var zero_k := Weapons.zero_angle(id, float(cur_zero()))
	dir = dir.rotated(camera.global_basis.x, zero_k).normalized()
	var pellets := int(d["pellets"])
	_shot_seq += 1
	var muzzle_pos := muzzle.global_position if muzzle != null else from
	for p in range(pellets):
		var s := spread_deg
		if pellets > 1:
			s *= randf_range(0.4, 1.5)
		var ang := randf() * TAU
		var rad := deg_to_rad(s) * sqrt(randf())
		var offset := camera.global_basis * Vector3(cos(ang) * rad, sin(ang) * rad, 0.0)
		var shot_dir := (dir + offset).normalized()
		if game != null and game.ballistics != null:
			game.ballistics.fire(self, from, shot_dir, id, muzzle_pos, _shot_seq)
	if game != null and game.has_method("on_gunshot"):
		game.on_gunshot(from, self)
	if game != null and game.has_method("play_sfx_at"):
		game.play_sfx_at("shot_" + str(d["sound"]), from, 1.0)
	_emit_ammo()


## Called by the ballistics system when one of our bullets lands.
func on_bullet_hit(shot_id: int, pos: Vector3, dmg: float, headshot: bool, killed: bool) -> void:
	if not _pending_hits.has(shot_id):
		_pending_hits[shot_id] = {"dmg": 0.0, "pos": pos, "head": false, "killed": false}
		shots_hit += 1
	var h: Dictionary = _pending_hits[shot_id]
	h["dmg"] = float(h["dmg"]) + dmg
	h["pos"] = pos
	h["head"] = bool(h["head"]) or headshot
	h["killed"] = bool(h["killed"]) or killed


func _flush_hits() -> void:
	# Shotgun pellets of one shot land on the same tick: report them as one hit.
	for k in _pending_hits:
		var h: Dictionary = _pending_hits[k]
		hitmarker.emit(bool(h["head"]), bool(h["killed"]))
		if game != null and game.has_method("on_player_hit"):
			game.on_player_hit(h["pos"], float(h["dmg"]), bool(h["head"]))
	_pending_hits.clear()


func start_reload() -> void:
	if not has_gun() or reloading:
		return
	var id := current_id()
	var d: Dictionary = Weapons.def(id)
	if current_mag() >= mag_size() or current_reserve() <= 0:
		if current_reserve() <= 0:
			notice.emit("NO AMMO")
		return
	cancel_heal()
	reloading = true
	_reload_was_empty = current_mag() == 0
	_reload_need = mag_size() - current_mag()
	_reload_dur = float(d["reload"]) * (1.0 if _reload_was_empty else 0.82)
	if Weapons.cls(id) == "shotgun":
		_reload_need = mini(_reload_need, current_reserve())
		_reload_dur = float(d["reload"]) * clampf(float(_reload_need) / float(d["mag"]), 0.35, 1.0)
	reload_timer = _reload_dur
	_reload_events.clear()
	bolt_t = -1.0


func _finish_reload() -> void:
	reloading = false
	var id := current_id()
	var d: Dictionary = Weapons.def(id)
	var need := mag_size() - current_mag()
	var take := mini(need, current_reserve())
	mags[id] = current_mag() + take
	ammo[Weapons.caliber(id)] = current_reserve() - take
	bloom = 0.0
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
	cancel_heal()
	fire_timer = 0.25
	_rebuild_viewmodel()
	_emit_weapon()
	inventory_changed.emit()
	if game != null and game.has_method("play_sfx_at"):
		game.play_sfx_at("equip", global_position, -6.0)


func give_weapon(id: String, start_mag: int = -1, start_reserve: int = -1) -> bool:
	if not Weapons.DEFS.has(id):
		return false
	var d: Dictionary = Weapons.def(id)
	if loadout.has(id):
		# Duplicate gun: strip the magazine for ammo instead.
		var extra := maxi(1, start_mag if start_mag >= 0 else int(d["mag"]))
		add_ammo_cal(Weapons.caliber(id), extra)
		notice.emit("+%d  %s" % [extra, Weapons.caliber(id).to_upper()])
		return true
	if loadout.size() >= 2:
		# Full: the gun in hand goes on the floor.
		var old := current_id()
		if game != null and game.has_method("drop_weapon"):
			game.drop_weapon(old, current_mag(), current_reserve(), global_position + Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, -1.2))
		mags.erase(old)
		loadout[slot] = id
	else:
		loadout.append(id)
		slot = loadout.size() - 1
	_validate_attachments(loadout.find(id))
	mags[id] = mag_size(id) if start_mag < 0 else mini(start_mag, mag_size(id))
	if start_reserve > 0:
		add_ammo_cal(Weapons.caliber(id), start_reserve)
	reloading = false
	cancel_heal()
	fire_timer = 0.3
	_rebuild_viewmodel()
	_emit_weapon()
	inventory_changed.emit()
	if game != null and game.has_method("play_sfx_at"):
		game.play_sfx_at("equip", global_position, -2.0)
	return true


func add_ammo(id: String, amount: int) -> void:
	add_ammo_cal(Weapons.caliber(id), amount)


func add_ammo_cal(cal: String, amount: int) -> int:
	var cap := int(Weapons.AMMO_CAP.get(cal, 200))
	var before := ammo_of(cal)
	ammo[cal] = mini(cap, before + amount)
	_emit_ammo()
	inventory_changed.emit()
	return ammo_of(cal) - before


## Ammo box of one calibre (item_id); an untyped box feeds the gun in hand.
func add_ammo_box(cal: String = "") -> void:
	if cal == "":
		cal = Weapons.caliber(current_id()) if has_gun() else "9mm"
	add_ammo_cal(cal, int(Weapons.AMMO_BOX.get(cal, 30)))


# ---------------------------------------------------------------- loot rules --
func loot_block_reason(l: LootPickup) -> String:
	match l.kind:
		"ammo":
			var cal := l.item_id if l.item_id != "" else (Weapons.caliber(current_id()) if has_gun() else "9mm")
			if ammo_of(cal) >= int(Weapons.AMMO_CAP.get(cal, 200)):
				return "%s FULL" % cal.to_upper()
		"armor":
			var lv := int(l.item_id)
			if vest_level > lv or (vest_level == lv and armor >= 99.0):
				return "YOUR VEST IS BETTER"
		"helmet":
			var lv := int(l.item_id)
			if helmet_level > lv or (helmet_level == lv and helmet_hp >= 99.0):
				return "YOUR HELMET IS BETTER"
		"bandage":
			if bandages >= MAX_BANDAGES:
				return "BANDAGES FULL"
		"med":
			if meds >= MAX_MEDS:
				return "MEDKITS FULL  —  5 TO USE ONE"
		"energy":
			if energy >= MAX_ENERGY:
				return "ENERGY DRINKS FULL"
		"grenade":
			if grenades >= MAX_GRENADES:
				return "GRENADES FULL"
		"scope", "extmag", "comp":
			if _attach_slot_for(l.kind, l.item_id) < 0:
				return "NO WEAPON CAN TAKE THIS" if loadout.size() > 0 else "NEED A WEAPON FIRST"
	return ""


func take_loot(l: LootPickup) -> bool:
	if loot_block_reason(l) != "":
		return false
	match l.kind:
		"weapon":
			give_weapon(l.item_id, l.mag_override, l.reserve_override)
		"ammo":
			var cal := l.item_id if l.item_id != "" else (Weapons.caliber(current_id()) if has_gun() else "9mm")
			var got := add_ammo_cal(cal, int(Weapons.AMMO_BOX.get(cal, 30)))
			notice.emit("+%d  %s" % [got, cal.to_upper()])
		"armor":
			vest_level = int(l.item_id)
			armor = 100.0
			notice.emit("VEST LV%d EQUIPPED" % vest_level)
		"helmet":
			helmet_level = int(l.item_id)
			helmet_hp = 100.0
			notice.emit("HELMET LV%d EQUIPPED" % helmet_level)
		"bandage":
			bandages = mini(MAX_BANDAGES, bandages + l.amount)
		"med":
			meds += 1
		"energy":
			energy += 1
		"grenade":
			grenades += 1
		"scope", "extmag", "comp":
			var s := _attach_slot_for(l.kind, l.item_id)
			var att: Dictionary = attachments[s]
			if l.kind == "scope":
				var old := str(att.get("scope", ""))
				if old != "" and game != null and game.has_method("drop_item"):
					game.drop_item("scope", old, global_position + Basis(Vector3.UP, yaw) * Vector3(0.6, 0, -1.0))
				att["scope"] = l.item_id
				if s == slot:
					_rebuild_viewmodel()
			else:
				att[l.kind] = true
				if l.kind == "extmag" and s < loadout.size():
					_emit_ammo()
			notice.emit("%s  →  %s" % [l.display_name(), str(Weapons.def(loadout[s])["short"])])
	_emit_health()
	inventory_changed.emit()
	return true


## Attachments live on a weapon slot; ones that do not fit a new gun drop off.
func _validate_attachments(s: int) -> void:
	if s < 0 or s >= loadout.size():
		return
	var w: String = loadout[s]
	var att: Dictionary = attachments[s]
	var drop_at := global_position + Basis(Vector3.UP, yaw) * Vector3(-0.7, 0, -1.0)
	var sc := str(att.get("scope", ""))
	if sc != "" and not Weapons.scope_fits(w, sc):
		att.erase("scope")
		if game != null:
			game.drop_item("scope", sc, drop_at)
	for k in ["extmag", "comp"]:
		if bool(att.get(k, false)) and not Weapons.attachment_fits(w, k):
			att.erase(k)
			if game != null:
				game.drop_item(k, "", drop_at)


## Which slot an attachment goes on: the gun in hand first, then the other one.
func _attach_slot_for(kind: String, id: String) -> int:
	var order := [slot, 1 - slot]
	for s in order:
		if s < 0 or s >= loadout.size():
			continue
		var w: String = loadout[s]
		var att: Dictionary = attachments[s]
		if kind == "scope":
			if not Weapons.scope_fits(w, id):
				continue
			var cur := str(att.get("scope", ""))
			if cur == id:
				continue
			return s
		elif not bool(att.get(kind, false)) and Weapons.attachment_fits(w, kind):
			return s
	return -1


# ------------------------------------------------------- per-gun modifiers --
func cur_att() -> Dictionary:
	return attachments[slot] if slot < attachments.size() else {}


func mag_size(id: String = "") -> int:
	if id == "":
		id = current_id()
	var base := int(Weapons.def(id)["mag"])
	var s := loadout.find(id)
	if s >= 0 and bool(attachments[s].get("extmag", false)):
		return int(round(base * 1.5))
	return base


func cur_zoom() -> float:
	if not has_gun():
		return 1.0
	var z := float(Weapons.def(current_id()).get("zoom", 1.0))
	var sc := cur_scope()
	if sc != "":
		z = maxf(z, float(Weapons.SCOPE_ZOOM.get(sc, 1.0)))
	return z


func cur_scope() -> String:
	if not has_gun():
		return ""
	var sc := str(cur_att().get("scope", ""))
	if sc == "":
		return Weapons.builtin_scope(current_id())
	return sc


func recoil_mult() -> float:
	return 0.68 if bool(cur_att().get("comp", false)) else 1.0


# -------------------------------------------------------------- consumables --
const USE_TIME := {"bandage": 2.2, "med": 4.0, "energy": 1.6}


func use_item(item: String) -> void:
	if healing:
		if heal_item == item:
			return
		cancel_heal()
	var have := {"bandage": bandages, "med": meds, "energy": energy}
	if int(have.get(item, 0)) <= 0:
		notice.emit("NO %s" % {"bandage": "BANDAGES", "med": "MEDKITS", "energy": "ENERGY DRINKS"}[item])
		return
	if item == "bandage" and hp >= 75.0:
		notice.emit("BANDAGES ONLY HEAL TO 75")
		return
	if item == "med" and hp >= 100.0:
		notice.emit("ALREADY AT FULL HEALTH")
		return
	if item == "energy" and boost >= 95.0:
		notice.emit("BOOST ALREADY FULL")
		return
	reloading = false
	healing = true
	heal_item = item
	heal_dur = float(USE_TIME[item])
	heal_timer = heal_dur
	_sfx("heal", -2.0)


## H: the sensible item for the situation.
func start_heal() -> void:
	if hp < 60.0 and meds > 0:
		use_item("med")
	elif hp < 75.0 and bandages > 0:
		use_item("bandage")
	elif meds > 0 and hp < 100.0:
		use_item("med")
	elif energy > 0:
		use_item("energy")
	elif bandages > 0:
		use_item("bandage")
	else:
		notice.emit("NO HEALING ITEMS")


func cancel_heal() -> void:
	healing = false
	heal_timer = 0.0


func _finish_heal() -> void:
	healing = false
	match heal_item:
		"bandage":
			if bandages > 0:
				bandages -= 1
				hp = minf(maxf(hp, 75.0) if hp >= 75.0 else 75.0, hp + 15.0)
		"med":
			if meds > 0:
				meds -= 1
				hp = minf(100.0, hp + 60.0)
		"energy":
			if energy > 0:
				energy -= 1
				boost = minf(100.0, boost + 40.0)
	_emit_health()
	inventory_changed.emit()


func heal_progress() -> float:
	if not healing:
		return -1.0
	return 1.0 - clampf(heal_timer / maxf(0.01, heal_dur), 0.0, 1.0)


func heal_label() -> String:
	return {"bandage": "BANDAGING", "med": "USING MEDKIT", "energy": "DRINKING"}.get(heal_item, "HEALING")


func _tick_boost(delta: float) -> void:
	if boost <= 0.0:
		return
	boost = maxf(0.0, boost - delta * 2.0)
	if hp < 100.0:
		_boost_acc += delta
		if _boost_acc >= 1.0:
			_boost_acc -= 1.0
			hp = minf(100.0, hp + 1.5)
			_emit_health()


func reload_progress() -> float:
	if not reloading or not has_gun():
		return -1.0
	return 1.0 - clampf(reload_timer / maxf(0.01, _reload_dur), 0.0, 1.0)


func add_armor(amount: float) -> void:
	vest_level = maxi(vest_level, 1)
	armor = minf(100.0, armor + amount)
	_emit_health()


func heal(amount: float) -> void:
	hp = minf(100.0, hp + amount)
	_emit_health()


const ABSORB := [0.0, 0.30, 0.40, 0.55]


func take_damage(amount: float, from_pos: Vector3 = Vector3.ZERO, headshot: bool = false, source: Node = null) -> bool:
	if not alive or spawn_protect > 0.0:
		return false
	var dmg := amount
	if source != null:
		# The storm ignores armour; bullets and blasts do not.
		if headshot and helmet_level > 0:
			dmg *= 1.0 - ABSORB[helmet_level]
			helmet_hp -= amount * 0.6
			if helmet_hp <= 0.0:
				helmet_level = 0
				helmet_hp = 0.0
				notice.emit("HELMET DESTROYED")
				inventory_changed.emit()
		elif not headshot and vest_level > 0:
			dmg *= 1.0 - ABSORB[vest_level]
			armor -= amount * 0.45
			if armor <= 0.0:
				vest_level = 0
				armor = 0.0
				notice.emit("VEST DESTROYED")
				inventory_changed.emit()
	hp -= dmg
	_damage_flash = 1.0
	if source != null and source != self:
		cancel_heal()
	var dir := (from_pos - global_position).normalized() if from_pos != Vector3.ZERO else Vector3.FORWARD
	damaged.emit(dmg, dir)
	if game != null and game.has_method("on_player_damaged"):
		game.on_player_damaged(dmg, from_pos)
	_emit_health()
	if hp <= 0.0:
		alive = false
		cancel_heal()
		reloading = false
		flash.visible = false
		gun_holder.visible = false
		var killer := "THE STORM"
		if source != null and source.has_method("display_name"):
			killer = source.call("display_name")
		last_killer = source
		died.emit(killer)
	return true


var last_killer: Node = null


# ---------------------------------------------------------------- grenades --
func throw_grenade() -> void:
	if grenades <= 0:
		notice.emit("NO GRENADES")
		return
	if _throw_cd > 0.0:
		return
	grenades -= 1
	_throw_cd = 0.9
	inventory_changed.emit()
	var dir := -camera.global_basis.z
	var g := Grenade.new()
	g.game = game
	g.thrower = self
	game.add_child(g)
	g.global_position = camera.global_position + dir * 0.6 + Vector3(0, -0.1, 0)
	g.linear_velocity = dir * 17.0 + Vector3(0, 3.5, 0) + velocity * 0.5
	g.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	if game.has_method("net_grenade_thrown"):
		game.net_grenade_thrown(g.global_position, g.linear_velocity)
	kick_vel += Vector3(0.0, -0.6, 0.4)
	equip_t = 0.35
	_sfx("equip", -4.0)


func force_respawn() -> void:
	if game != null and game.has_method("respawn_player"):
		game.respawn_player()


func _try_pickup() -> void:
	if game != null and game.has_method("try_pickup"):
		game.try_pickup(self)


# ------------------------------------------------------------------ helpers --
func _rebuild_viewmodel() -> void:
	for c in gun_holder.get_children():
		gun_holder.remove_child(c)
		c.queue_free()
	_mag_node = null
	if not has_gun():
		return
	var id := current_id()
	var node := Weapons.build_view_model(id)
	gun_holder.add_child(node)
	_gun_scale = Weapons.view_scale(id)
	node.scale = Vector3.ONE * _gun_scale
	muzzle = Node3D.new()
	gun_holder.add_child(muzzle)
	muzzle.position = Vector3(0, 0.01, -0.5 * _gun_scale)
	# The gun's own magazine, cut from the model, animated during reloads.
	_mag_node = node.get_node_or_null("Mag") as MeshInstance3D
	if _mag_node != null:
		_mag_rest = _mag_node.position
	# Mounted optic, built in metres and placed on the top rail.
	_optic_id = str(cur_att().get("scope", ""))
	if _optic_id != "" and Weapons.optic_kind(_optic_id) != "":
		var oy := Weapons.optic_center_y(id, _optic_id)
		var top := float(Weapons.model(id).get("sight_y", 0.08)) * _gun_scale
		var optic := Weapons.build_optic(_optic_id, oy - top)
		optic.position = Vector3(0.0, oy, -0.02 if Weapons.cls(id) != "pistol" else 0.01)
		gun_holder.add_child(optic)
	equip_t = 0.0
	aim_blend = 0.0
	bolt_t = -1.0
	bloom = 0.0


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
	if game == null or game.sfx == null:
		return
	var surf: String = game.surface_at(global_position)
	var db := -9.0
	if sprinting:
		db = -5.0
	elif _ap("crouch"):
		db = -18.0
	game.sfx.play_2d("step_%s_%d" % [surf, randi() % 4 + 1], db, 0.07)
	if sprinting and randf() < 0.45:
		game.sfx.play_2d("gear_rattle", db - 9.0, 0.1)


func shake(_amt: float) -> void:
	pass


func display_name() -> String:
	if game != null and game.net != null and game.net.active:
		return game.net.my_name
	return "YOU"


func crouching() -> bool:
	return mode == Mode.GROUND and _ap("crouch")


func reset_for_match() -> void:
	alive = true
	hp = 100.0
	armor = 0.0
	kills = 0
	loadout.clear()
	mags.clear()
	ammo.clear()
	fire_single.clear()
	zeroing.clear()
	breath = 100.0
	lean = 0.0
	slot = 0
	reloading = false
	reload_timer = 0.0
	fire_timer = 0.0
	chute_open = false
	chute_mesh.visible = false
	landed = false
	spawn_protect = 0.0
	meds = 0
	bandages = 0
	energy = 0
	grenades = 0
	boost = 0.0
	vest_level = 0
	helmet_level = 0
	helmet_hp = 0.0
	attachments = [{}, {}]
	healing = false
	heal_timer = 0.0
	shots_fired = 0
	shots_hit = 0
	last_killer = null
	velocity = Vector3.ZERO
	freefall_speed = 0.0
	mode = Mode.PLANE
	process_mode = Node.PROCESS_MODE_INHERIT
	# Feel/animation state from the last match must not leak into this one.
	trauma = 0.0
	land_dip = 0.0
	sprinting = false
	sprint_blend = 0.0
	aiming = false
	aim_blend = 0.0
	bloom = 0.0
	bolt_t = -1.0
	kick = Vector3.ZERO
	kick_vel = Vector3.ZERO
	kick_rot = Vector3.ZERO
	kick_rot_vel = Vector3.ZERO
	recoil_pitch = 0.0
	recoil_yaw = 0.0
	holding_breath = false
	in_water = false
	swimming = false
	diving = false
	air = 100.0
	if game != null:
		game.set_underwater(false)
		if game.hud != null:
			game.hud.set_swim(false, 100.0, false)
	_scope_sway = Vector2.ZERO
	_pending_hits.clear()
	_spray_n = 0
	_fall_speed = 0.0
	_was_on_floor = true
	_sprint_lock = 0.0
	_throw_cd = 0.0
	pitch = 0.0
	cam_base = Vector3(0, EYE, 0)
	camera.fov = base_fov
	flash_time = 0.0
	flash.visible = false
	for c in _casings:
		if is_instance_valid(c["node"]):
			c["node"].queue_free()
	_casings.clear()
	_emit_health()
	_rebuild_viewmodel()
	_emit_weapon()
	inventory_changed.emit()


func set_plane_mode() -> void:
	mode = Mode.PLANE
	alive = true


func jump_from_plane() -> void:
	_freefall_t = 0.0
	add_trauma(0.35)
	mode = Mode.FREEFALL
	freefall_speed = -8.0
	velocity = Vector3(0, -8, 0)
	notice.emit("W TO DIVE  ·  SPACE TO DEPLOY CHUTE")


# ------------------------------------------------------------ gun handling --
func toggle_fire_mode() -> void:
	if not has_gun():
		return
	var id := current_id()
	if not bool(Weapons.def(id).get("auto", false)) or Weapons.cls(id) == "lmg":
		notice.emit("%s HAS ONE FIRE MODE" % str(Weapons.def(id)["short"]))
		return
	fire_single[id] = not bool(fire_single.get(id, false))
	notice.emit("FIRE MODE  —  %s" % ("SINGLE" if fire_single[id] else "AUTO"))
	_sfx("empty_click", -4.0)
	inventory_changed.emit()


func adjust_zero(step: int) -> void:
	if not has_gun():
		return
	var id := current_id()
	var mx := Weapons.zero_max(id)
	if mx <= 100:
		notice.emit("NO ZEROING ON THIS WEAPON")
		return
	var z := clampi(cur_zero() + step, 100, mx)
	zeroing[id] = z
	notice.emit("ZEROING  %d M" % z)
	_sfx("empty_click", -8.0)
	inventory_changed.emit()


func _update_lean(delta: float) -> void:
	var want := 0.0
	if _ap("lean_left"):
		want -= 1.0
	if _ap("lean_right"):
		want += 1.0
	if sprinting:
		want = 0.0
	# Do not lean the camera into a wall.
	if want != 0.0:
		var side := Basis(Vector3.UP, yaw) * Vector3(want, 0, 0)
		var head := global_position + Vector3(0, cam_base.y, 0)
		var q := PhysicsRayQueryParameters3D.create(head, head + side * 0.62, 1)
		q.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			want = 0.0
	lean = move_toward(lean, want, delta * 6.0)


## Scoped aim drifts with breathing; hold Shift to steady it for a few seconds.
func _update_breath(delta: float) -> void:
	var scoped := aiming and cur_zoom() >= 1.9 and aim_blend > 0.7
	var was_holding := holding_breath
	holding_breath = scoped and _ap("sprint") and breath > 0.0
	if holding_breath != was_holding and game != null and game.sfx != null:
		game.sfx.play_2d("breath_in" if holding_breath else "breath_out", -10.0, 0.05)
	if holding_breath:
		breath = maxf(0.0, breath - delta * 22.0)
	else:
		breath = minf(100.0, breath + delta * (14.0 if not scoped else 9.0))
	if not scoped:
		_scope_sway = _scope_sway.lerp(Vector2.ZERO, clampf(delta * 8.0, 0.0, 1.0))
		return
	var t := Time.get_ticks_msec() * 0.001
	var amp := deg_to_rad(0.10 + cur_zoom() * 0.022)
	var planar := Vector2(velocity.x, velocity.z).length()
	amp *= 1.0 + clampf(planar / WALK, 0.0, 1.5) * 1.6
	if _ap("crouch"):
		amp *= 0.6
	if breath <= 0.5:
		amp *= 1.9
	if holding_breath:
		amp *= 0.12
	var want := Vector2(sin(t * 0.83) + 0.35 * sin(t * 2.1), 0.6 * sin(t * 1.27 + 0.6) + 0.25 * sin(t * 2.9)) * amp
	_scope_sway = _scope_sway.lerp(want, clampf(delta * 4.0, 0.0, 1.0))



# ---------------------------------------------------------------- casings --
var _casings: Array = []
static var _brass_mat: StandardMaterial3D
static var _hull_mat: StandardMaterial3D


## Spent brass flies out of the ejection port, spins, drops and tinkles.
func _eject_casing(shell: bool) -> void:
	if _brass_mat == null:
		_brass_mat = StandardMaterial3D.new()
		_brass_mat.albedo_color = Color(0.86, 0.66, 0.28)
		_brass_mat.metallic = 0.7
		_brass_mat.roughness = 0.28
		_brass_mat.emission_enabled = true
		_brass_mat.emission = Color(0.25, 0.18, 0.06)
		_hull_mat = StandardMaterial3D.new()
		_hull_mat.albedo_color = Color(0.7, 0.12, 0.1)
		_hull_mat.roughness = 0.5
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0065 if shell else 0.0032
	cm.bottom_radius = cm.top_radius
	cm.height = 0.055 if shell else 0.026
	cm.radial_segments = 8
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = _hull_mat if shell else _brass_mat
	mi.layers = 2
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.add_child(mi)
	mi.position = gun_holder.position + gun_holder.basis * Vector3(0.025, 0.035, -0.02 * _gun_scale)
	mi.rotation = Vector3(randf() * TAU, 0, PI * 0.5)
	var vel := Vector3(randf_range(1.3, 1.9), randf_range(1.1, 1.7), randf_range(0.1, 0.5))
	_casings.append({"node": mi, "vel": vel, "spin": Vector3(randf_range(-30, 30), randf_range(-30, 30), randf_range(10, 25)), "t": 0.0})
	if _casings.size() > 14:
		var old: Dictionary = _casings.pop_front()
		if is_instance_valid(old["node"]):
			old["node"].queue_free()
	# The tinkle when it lands at your feet.
	if game != null and game.sfx != null and randf() < 0.7:
		var tw := create_tween()
		tw.tween_interval(randf_range(0.35, 0.6))
		tw.tween_callback(func(): if game != null: game.sfx.play_2d("shell_hull" if shell else "casing_%d" % (randi() % 3 + 1), -15.0, 0.12))


func _update_casings(delta: float) -> void:
	for c in _casings.duplicate():
		var n: MeshInstance3D = c["node"]
		if not is_instance_valid(n):
			_casings.erase(c)
			continue
		c["t"] = float(c["t"]) + delta
		var v: Vector3 = c["vel"]
		v.y -= 9.8 * delta
		c["vel"] = v
		n.position += v * delta
		n.rotation += Vector3(c["spin"]) * delta
		if float(c["t"]) > 0.5:
			n.queue_free()
			_casings.erase(c)


func refresh_viewmodel() -> void:
	_rebuild_viewmodel()
