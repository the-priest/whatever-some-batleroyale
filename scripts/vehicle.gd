extends RigidBody3D
class_name Vehicle

## Off-road jeep. Arcade raycast suspension: four springs push the chassis
## off the ground, tyres grip sideways and drive the rear wheels, the
## handbrake breaks the rear loose for slides. Four seats, takes bullet and
## crash damage, burns out and explodes at zero.
##
## In a LAN game one machine "owns" each jeep (whoever last drove it) and
## simulates it; everyone else shows it as a kinematic puppet that follows
## the owner's snapshots.

const MAX_HP := 900.0
const WHEEL_R := 0.46
const REST := 0.42
const SPRING := 52000.0
const DAMP := 5200.0
const ENGINE := 12500.0
const BRAKE := 14000.0
const TOP_SPEED := 33.0
const REVERSE_SPEED := 9.0
const GRIP := 9.5
const STEER_MAX := 0.55
const SEATS := [Vector3(-0.42, 1.02, 0.12), Vector3(0.42, 1.02, 0.12), Vector3(-0.42, 1.06, 1.05), Vector3(0.42, 1.06, 1.05)]
const WHEELS := [Vector3(-0.92, 0.84, -1.38), Vector3(0.92, 0.84, -1.38), Vector3(-0.92, 0.84, 1.32), Vector3(0.92, 0.84, 1.32)]
const PALETTE := [Color(0.36, 0.42, 0.24), Color(0.72, 0.60, 0.40), Color(0.62, 0.16, 0.14), Color(0.20, 0.32, 0.52),
	Color(0.85, 0.85, 0.82), Color(0.16, 0.17, 0.18)]

var game: Node
var net_id := 0
var hp := MAX_HP
var alive := true
var wrecked := false
## Seat index -> occupant node (Player or remote human puppet) or null.
var seats: Array = [null, null, null, null]
## Peer id that simulates this jeep (1 = host / single player).
var owner_peer := 1

# Driver input, set by the game each frame for the local driver.
var throttle := 0.0
var steer_in := 0.0
var handbrake := false

var steer := 0.0
var speed := 0.0
var _wheel_nodes: Array[Node3D] = []
var _wheel_spin := 0.0
var _compress: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _grounded := 0
var _engine: AudioStreamPlayer3D
var _skid: AudioStreamPlayer3D
var _slip := 0.0
var _crash_cd := 0.0
var _burn_t := -1.0
var _smoke_t := 0.0
var _body_mats: Array[StandardMaterial3D] = []
var _lights: Array[MeshInstance3D] = []
var _flip_t := 0.0
var _last_vel := Vector3.ZERO

# Puppet interpolation.
var _net_pos := Vector3.ZERO
var _net_rot := Quaternion.IDENTITY
var _net_vel := Vector3.ZERO
var _net_seen := false


func setup(p_game: Node, id: int, color_i: int) -> void:
	game = p_game
	net_id = id
	set_meta("color", color_i)


func _ready() -> void:
	add_to_group("vehicles")
	add_to_group("damageable")
	mass = 1250.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.35, 0.05)
	angular_damp = 1.6
	linear_damp = 0.05
	collision_layer = 1
	collision_mask = 1 | 2 | 4
	contact_monitor = true
	max_contacts_reported = 6
	continuous_cd = true
	body_entered.connect(_on_body_entered)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
	pm.bounce = 0.05
	physics_material_override = pm
	_build_collision()
	_build_model(PALETTE[int(get_meta("color", 0)) % PALETTE.size()])
	_build_audio()


# ------------------------------------------------------------------- model --

func _mat(c: Color, rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material, rot := Vector3.ZERO, sides := 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = sides
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _build_collision() -> void:
	var a := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(1.9, 0.7, 4.1)
	a.shape = b
	a.position = Vector3(0, 0.95, 0)
	add_child(a)
	var c := CollisionShape3D.new()
	var cb := BoxShape3D.new()
	cb.size = Vector3(1.7, 0.5, 1.4)
	c.shape = cb
	c.position = Vector3(0, 1.5, 0.75)
	add_child(c)


func _build_model(paint: Color) -> void:
	var body := Node3D.new()
	body.name = "Body"
	add_child(body)
	var p := _mat(paint, 0.55, 0.15)
	_body_mats.append(p)
	var dark := _mat(Color(0.10, 0.10, 0.11), 0.8)
	_body_mats.append(dark)
	var trim := _mat(Color(0.22, 0.22, 0.23), 0.6, 0.4)
	var chrome := _mat(Color(0.78, 0.78, 0.8), 0.25, 0.9)
	var seat_m := _mat(Color(0.28, 0.20, 0.14), 0.9)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.6, 0.75, 0.85, 0.35)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic = 0.3
	# Chassis rails and tub.
	_box(body, Vector3(1.5, 0.22, 4.0), Vector3(0, 0.62, 0), dark)
	_box(body, Vector3(1.86, 0.55, 2.4), Vector3(0, 1.0, 0.6), p)
	# Hood sloping down to the grille.
	_box(body, Vector3(1.8, 0.42, 1.55), Vector3(0, 1.06, -1.25), p)
	_box(body, Vector3(1.78, 0.08, 1.5), Vector3(0, 1.3, -1.22), p, Vector3(deg_to_rad(-4.0), 0, 0))
	_box(body, Vector3(1.5, 0.48, 0.08), Vector3(0, 1.0, -2.02), trim)
	for i in 7:
		_box(body, Vector3(0.05, 0.38, 0.06), Vector3(-0.6 + i * 0.2, 1.0, -2.06), chrome)
	# Fenders over each wheel.
	for w in WHEELS:
		_box(body, Vector3(0.42, 0.1, 1.15), Vector3(w.x * 1.02, 1.08, w.z), p)
		_box(body, Vector3(0.42, 0.26, 0.1), Vector3(w.x * 1.02, 0.97, w.z - 0.58), p)
		_box(body, Vector3(0.42, 0.26, 0.1), Vector3(w.x * 1.02, 0.97, w.z + 0.58), p)
	# Bumpers.
	_box(body, Vector3(2.0, 0.2, 0.22), Vector3(0, 0.78, -2.12), dark)
	_box(body, Vector3(2.0, 0.2, 0.22), Vector3(0, 0.78, 2.0), dark)
	# Headlights and tail lights.
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(1.0, 0.96, 0.85)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.92, 0.75)
	lamp.emission_energy_multiplier = 1.6
	var tail := StandardMaterial3D.new()
	tail.albedo_color = Color(0.9, 0.1, 0.08)
	tail.emission_enabled = true
	tail.emission = Color(1.0, 0.08, 0.05)
	tail.emission_energy_multiplier = 0.8
	for sx in [-0.62, 0.62]:
		_cyl(body, 0.13, 0.08, Vector3(sx, 1.06, -2.04), chrome, Vector3(PI * 0.5, 0, 0))
		_lights.append(_cyl(body, 0.1, 0.09, Vector3(sx, 1.06, -2.06), lamp, Vector3(PI * 0.5, 0, 0)))
		_box(body, Vector3(0.22, 0.14, 0.06), Vector3(sx * 1.25, 1.02, 1.82), tail)
	# Windshield frame and glass.
	_box(body, Vector3(1.76, 0.07, 0.07), Vector3(0, 1.95, -0.48), trim)
	for sx in [-0.86, 0.86]:
		_box(body, Vector3(0.07, 0.68, 0.07), Vector3(sx, 1.62, -0.42), trim, Vector3(deg_to_rad(-12.0), 0, 0))
	_box(body, Vector3(1.66, 0.62, 0.03), Vector3(0, 1.62, -0.42), glass, Vector3(deg_to_rad(-12.0), 0, 0))
	# Roll cage.
	for sx in [-0.84, 0.84]:
		_box(body, Vector3(0.08, 0.95, 0.08), Vector3(sx, 1.72, 0.62), trim)
		_box(body, Vector3(0.08, 0.08, 1.35), Vector3(sx, 2.18, 1.22), trim)
		_box(body, Vector3(0.08, 0.72, 0.08), Vector3(sx, 1.8, 1.85), trim, Vector3(deg_to_rad(-14.0), 0, 0))
	_box(body, Vector3(1.76, 0.08, 0.08), Vector3(0, 2.18, 0.62), trim)
	# Seats and dash.
	for s in SEATS:
		_box(body, Vector3(0.62, 0.14, 0.6), s + Vector3(0, -0.12, 0.05), seat_m)
		_box(body, Vector3(0.62, 0.68, 0.14), s + Vector3(0, 0.22, 0.38), seat_m)
	_box(body, Vector3(1.7, 0.28, 0.28), Vector3(0, 1.38, -0.6), dark)
	var wheel_s := _cyl(body, 0.2, 0.04, Vector3(-0.42, 1.48, -0.42), dark, Vector3(deg_to_rad(-60.0), 0, 0), 14)
	wheel_s.name = "SteeringWheel"
	# Spare tyre on the tailgate and a jerry can.
	_cyl(body, 0.4, 0.26, Vector3(0, 1.25, 2.18), dark, Vector3(PI * 0.5, 0, 0))
	_cyl(body, 0.2, 0.28, Vector3(0, 1.25, 2.22), trim, Vector3(PI * 0.5, 0, 0))
	_box(body, Vector3(0.22, 0.42, 0.32), Vector3(0.86, 1.38, 1.7), _mat(Color(0.25, 0.32, 0.18), 0.6))
	# Wheels.
	var tyre := _mat(Color(0.07, 0.07, 0.075), 0.95)
	var hub := _mat(Color(0.55, 0.55, 0.56), 0.35, 0.7)
	for w in WHEELS:
		var pivot := Node3D.new()
		pivot.position = w
		add_child(pivot)
		var spin := Node3D.new()
		pivot.add_child(spin)
		_cyl(spin, WHEEL_R, 0.36, Vector3.ZERO, tyre, Vector3(0, 0, PI * 0.5), 20)
		# Tread blocks so spinning reads.
		for k in 10:
			var a := TAU * float(k) / 10.0
			_box(spin, Vector3(0.38, 0.06, 0.12), Vector3(0, cos(a) * WHEEL_R, sin(a) * WHEEL_R), tyre, Vector3(a, 0, 0))
		_cyl(spin, 0.26, 0.38, Vector3.ZERO, hub, Vector3(0, 0, PI * 0.5), 10)
		_wheel_nodes.append(pivot)
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visibility_range_end = 900.0


func _build_audio() -> void:
	_engine = AudioStreamPlayer3D.new()
	_engine.stream = _loop("engine_loop")
	_engine.unit_size = 9.0
	_engine.max_distance = 180.0
	_engine.volume_db = -80.0
	add_child(_engine)
	_skid = AudioStreamPlayer3D.new()
	_skid.stream = _loop("tire_skid")
	_skid.unit_size = 7.0
	_skid.max_distance = 110.0
	_skid.volume_db = -80.0
	add_child(_skid)


func _loop(name: String) -> AudioStream:
	var path := "res://assets/audio/gen/%s.wav" % name
	if not ResourceLoader.exists(path):
		return null
	var s: AudioStream = load(path)
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	return s


# --------------------------------------------------------------- simulation --

func is_local() -> bool:
	return game == null or game.net == null or not game.net.active or owner_peer == game.net.my_id()


func driver() -> Node:
	return seats[0]


func set_puppet(v: bool) -> void:
	_asleep = false
	_parked_t = 0.0
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = v


## A parked jeep that has settled is frozen in place so the physics engine
## and its suspension raycasts stop costing anything; it wakes when someone
## gets in, shoots it, or drives into it.
var _asleep := false
var _parked_t := 0.0


func wake() -> void:
	if not _asleep:
		return
	_asleep = false
	_parked_t = 0.0
	freeze = false


func _park() -> void:
	_asleep = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if Prof.on:
		var t0 := Time.get_ticks_usec()
		_physics_process_body(delta)
		Prof.add("vehicles", Time.get_ticks_usec() - t0)
	else:
		_physics_process_body(delta)


## Rolling it back did not work (wedged against a trunk or a wall): stand
## it back on its wheels where it lies, if there is room for it there.
func _set_upright() -> bool:
	var yaw := atan2(-global_basis.z.x, -global_basis.z.z)
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var b := Basis.looking_at(fwd, Vector3.UP)
	var box := BoxShape3D.new()
	box.size = Vector3(1.9, 1.3, 4.1)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = 1 | 2 | 4
	q.exclude = [get_rid()]
	var space := get_world_3d().direct_space_state
	var side := Vector3(fwd.z, 0, -fwd.x)
	var at := Vector3.INF
	# Where it lies, or a step or two clear of whatever it is wedged on.
	for off in [Vector3.ZERO, side * 1.6, -side * 1.6, fwd * 2.2, -fwd * 2.2, side * 3.0, -side * 3.0]:
		var p: Vector3 = global_position + (off as Vector3)
		var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 4.0, 1, [get_rid()]))
		if down.is_empty():
			continue
		var g: Vector3 = down["position"]
		q.transform = Transform3D(b, g + Vector3.UP * 1.65)
		if space.intersect_shape(q, 1).is_empty():
			at = g + Vector3.UP * 0.9
			break
	if at == Vector3.INF:
		return false
	global_transform = Transform3D(b, at)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_last_vel = Vector3.ZERO
	_crash_cd = maxf(_crash_cd, 1.5)
	return true


## Someone getting out keeps passing through the jeep until they are clear
## of it. Dropping that the moment they leave the seat, while their body
## is still in it, makes the physics shove the jeep aside: a lurch on every
## exit, and a launch if they are moved across it.
var _leaving: Array = []  # [body, physics frames since leaving]


func release_rider(b: PhysicsBody3D) -> void:
	if b == null or not is_instance_valid(b):
		return
	for e in _leaving:
		if e[0] == b:
			e[1] = 0
			return
	_leaving.append([b, 0])


func _tick_leaving() -> void:
	for i in range(_leaving.size() - 1, -1, -1):
		var e: Array = _leaving[i]
		var b = e[0]
		if not is_instance_valid(b):
			_leaving.remove_at(i)
			continue
		e[1] = int(e[1]) + 1
		if seats.has(b):
			# Got back in: the seat keeps the exception.
			_leaving.remove_at(i)
			continue
		var l: Vector3 = global_transform.affine_inverse() * ((b as Node3D).global_position + Vector3.UP * 0.9)
		var c := Vector3(clampf(l.x, -0.95, 0.95), clampf(l.y, 0.6, 1.75), clampf(l.z, -2.05, 2.05))
		var clear := l.distance_to(c) > 0.55
		if (clear and int(e[1]) >= 3) or int(e[1]) > 180:
			(b as PhysicsBody3D).remove_collision_exception_with(self)
			remove_collision_exception_with(b)
			_leaving.remove_at(i)


func _physics_process_body(delta: float) -> void:
	_crash_cd = maxf(0.0, _crash_cd - delta)
	if not _leaving.is_empty():
		_tick_leaving()
	speed = linear_velocity.dot(-global_basis.z)
	if wrecked:
		_burn(delta)
		_sound(delta)
		return
	if not is_local():
		_puppet_follow(delta)
		_animate_wheels(delta, null)
		_sound(delta)
		_dust(delta, true)
		return
	var has_driver: bool = seats[0] != null
	if has_driver:
		wake()
	elif _asleep:
		return
	if not has_driver:
		throttle = 0.0
		steer_in = 0.0
		handbrake = true
		if linear_velocity.length() < 0.3 and angular_velocity.length() < 0.3:
			_parked_t += delta
			# Only an upright jeep parks: one on its side (two wheels touching)
			# keeps trying to roll back onto its wheels.
			if _parked_t > 2.0 and _grounded >= 2 and global_basis.y.y > 0.8:
				_park()
				_sound(delta)
				return
		else:
			_parked_t = 0.0
	var space := get_world_3d().direct_space_state
	var b := global_basis
	var up := b.y
	var fwd := -b.z
	var right := b.x
	var target_steer := steer_in * STEER_MAX * lerpf(1.0, 0.35, clampf(absf(speed) / TOP_SPEED, 0.0, 1.0))
	steer = move_toward(steer, target_steer, delta * 2.6)
	_grounded = 0
	var hits: Array = []
	_slip = 0.0
	for i in 4:
		var mount: Vector3 = global_transform * (WHEELS[i] as Vector3)
		var q := PhysicsRayQueryParameters3D.create(mount + up * 0.2, mount - up * (REST + WHEEL_R), 1)
		q.exclude = [get_rid()]
		for s in seats:
			if s != null and is_instance_valid(s) and s is CollisionObject3D:
				q.exclude.append((s as CollisionObject3D).get_rid())
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			_compress[i] = move_toward(_compress[i], 0.0, delta * 3.0)
			hits.append(null)
			continue
		_grounded += 1
		var dist: float = (mount + up * 0.2).distance_to(hit["position"]) - 0.2 - WHEEL_R
		var comp := clampf(REST - dist, 0.0, REST + 0.1)
		var pt: Vector3 = hit["position"]
		var vel_at := linear_velocity + angular_velocity.cross(pt - global_position)
		var spring := comp * SPRING - vel_at.dot(up) * DAMP
		spring = maxf(0.0, spring)
		apply_force(up * spring, pt - global_position)
		_compress[i] = comp
		hits.append([pt, spring, hit.get("normal", Vector3.UP)])
	# Tyre forces.
	for i in 4:
		if hits[i] == null:
			continue
		var pt: Vector3 = hits[i][0]
		var load_n: float = hits[i][1]
		var front := i < 2
		var wfwd := fwd.rotated(up, -steer) if front else fwd
		var wright := right.rotated(up, -steer) if front else right
		var vel_at := linear_velocity + angular_velocity.cross(pt - global_position)
		var v_lat := vel_at.dot(wright)
		var v_long := vel_at.dot(wfwd)
		var mu := 1.05
		var grip := GRIP
		if not front and handbrake:
			grip *= 0.32
			mu *= 0.55
		var f_lat := -v_lat * grip * mass * 0.25
		var f_long := 0.0
		if not front:
			if throttle > 0.0 and speed < TOP_SPEED:
				f_long += ENGINE * 0.5 * throttle * clampf(1.15 - speed / TOP_SPEED, 0.2, 1.0)
			elif throttle < 0.0:
				if speed > 1.0:
					f_long -= BRAKE * 0.5 * -throttle
				elif speed > -REVERSE_SPEED:
					f_long += ENGINE * 0.35 * throttle
		if throttle < 0.0 and front and speed > 1.0:
			f_long -= BRAKE * 0.5 * -throttle
		if handbrake and not front:
			f_long -= signf(v_long) * minf(absf(v_long) * mass * 0.8, BRAKE * 0.35)
		elif absf(throttle) < 0.05 and absf(speed) < 2.5:
			# Hill hold: off the pedals at walking pace the jeep stops and stays
			# put instead of rolling away down a slope.
			f_long -= signf(v_long) * minf(absf(v_long) * mass * 1.6, BRAKE * 0.3)
		# Rolling resistance.
		f_long -= v_long * 22.0
		var f := Vector2(f_lat, f_long)
		var cap := mu * load_n
		if f.length() > cap:
			_slip = maxf(_slip, clampf((f.length() - cap) / maxf(1.0, cap), 0.0, 1.0))
			f = f.normalized() * cap
		if absf(v_lat) > 3.5:
			_slip = maxf(_slip, clampf((absf(v_lat) - 3.5) / 6.0, 0.0, 1.0))
		apply_force(wright * f.x + wfwd * f.y, pt - global_position)
	# Air control and anti-flip: a little stabilising torque.
	if _grounded == 0:
		apply_torque(-angular_velocity * mass * 0.6)
	# How long it has been on its side counts on regardless of the little hops
	# the assist itself gives it (those used to reset it, forever).
	if up.y < 0.35:
		_flip_t += delta
		if _flip_t > 7.0 and linear_velocity.length() < 4.0 and _set_upright():
			_flip_t = 0.0
		elif _flip_t > 2.5 and linear_velocity.length() < 2.5:
			# Roll it back onto its wheels (and do not let the roll count as
			# a crash).
			var axis := up.cross(Vector3.UP).normalized()
			if axis.length() > 0.1:
				apply_torque(axis * mass * 9.0)
			linear_velocity.y = maxf(linear_velocity.y, 2.5)
			_crash_cd = maxf(_crash_cd, 1.5)
	else:
		_flip_t = 0.0
	# Crash damage from sudden velocity changes.
	var dv := (linear_velocity - _last_vel).length()
	if dv > 9.0 and _crash_cd <= 0.0:
		_crash(dv)
	_last_vel = linear_velocity
	# Deep water drowns the engine.
	if game != null and game.terrain != null:
		var wl: float = game.terrain.water_surface_at(global_position.x, global_position.z)
		if global_position.y + 0.6 < wl:
			throttle = 0.0
			hp -= delta * 40.0
			if hp <= 0.0:
				destroy()
	_sweep_people()
	_animate_wheels(delta, hits)
	_sound(delta)
	_dust(delta)


## Anyone in the jeep's path gets hit and thrown aside; the jeep ploughs on
## instead of stopping dead against them.
var _hit_recent: Dictionary = {}


func _sweep_people() -> void:
	var now := Time.get_ticks_msec()
	for k in _hit_recent.keys():
		if now - int(_hit_recent[k][0]) > 1500:
			var o = _hit_recent[k][1]
			if is_instance_valid(o):
				remove_collision_exception_with(o)
			_hit_recent.erase(k)
	if absf(speed) < 4.0:
		return
	var dir := -global_basis.z * signf(speed)
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.3, 1.6, 1.4)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(global_basis, global_position + Vector3(0, 1.1, 0) + dir * (2.4 + absf(speed) * 0.04))
	q.collision_mask = 2 | 4
	var ex: Array[RID] = [get_rid()]
	for st in seats:
		if st != null and is_instance_valid(st) and st is CollisionObject3D:
			ex.append((st as CollisionObject3D).get_rid())
	q.exclude = ex
	for r in get_world_3d().direct_space_state.intersect_shape(q, 8):
		var o = r.get("collider")
		if o == null or not is_instance_valid(o) or _hit_recent.has(o.get_instance_id()):
			continue
		if not (o is Bot or o is Player) or not bool(o.get("alive")):
			continue
		if o is Bot and (o as Bot).seated_in != null:
			continue
		_hit_recent[o.get_instance_id()] = [now, o]
		add_collision_exception_with(o)
		var v := absf(speed)
		var dmg := v * v * 0.8
		var drv = seats[0]
		var src: Node = drv if drv != null and is_instance_valid(drv) else null
		if o is Bot:
			(o as Bot).velocity += dir * v * 0.6 + Vector3.UP * 4.0
			(o as Bot).take_damage(dmg, (o as Node3D).global_position + Vector3.UP, false, src)
		elif o is Player and o != drv:
			(o as Player).velocity += dir * v * 0.6 + Vector3.UP * 4.0
			(o as Player).take_damage(dmg, global_position, false, src)
		if game != null:
			game.spawn_blood((o as Node3D).global_position + Vector3.UP)
			game.play_sfx_at("hit_body", (o as Node3D).global_position, 2.0)
		# A body still slows you down a little.
		linear_velocity *= 0.93


func _animate_wheels(delta: float, hits) -> void:
	_wheel_spin += speed / WHEEL_R * delta
	for i in 4:
		var w := _wheel_nodes[i]
		var comp: float = _compress[i]
		w.position = (WHEELS[i] as Vector3) + Vector3(0, comp - REST, 0)
		w.rotation.y = -steer if i < 2 else 0.0
		(w.get_child(0) as Node3D).rotation.x = -_wheel_spin
	var sw := get_node_or_null("Body/SteeringWheel") as Node3D
	if sw != null:
		sw.rotation = Vector3(deg_to_rad(-60.0), 0, 0)
		sw.rotate_object_local(Vector3.UP, steer * 2.2)


## Dust off the rear wheels at speed (more when sliding), spray in water.
var _dust_t := 0.0


func _dust(delta: float, puppet := false) -> void:
	if game == null or game.player == null or (_grounded < 2 and not puppet) or absf(speed) < 6.0:
		return
	if global_position.distance_to(game.player.global_position) > 90.0:
		return
	_dust_t -= delta * (absf(speed) / 12.0 + _slip * 3.0)
	if _dust_t > 0.0:
		return
	_dust_t = 0.09
	for i in [2, 3]:
		var wp := global_transform * ((WHEELS[i] as Vector3) + Vector3(0, -REST - WHEEL_R * 0.6, 0.25))
		var surf: String = game.surface_at(wp + Vector3.UP * 0.5)
		if surf in ["dirt", "grass", "water"]:
			game.step_puff(wp, surf == "water")


func _sound(delta: float) -> void:
	if _engine.stream == null:
		return
	var running := seats[0] != null and not wrecked
	if running and not _engine.playing:
		_engine.play()
	var rpm := clampf(absf(speed) / TOP_SPEED, 0.0, 1.0)
	var gear_rpm := fmod(rpm * 3.2, 1.0) * 0.35 + rpm * 0.55
	_engine.pitch_scale = lerpf(_engine.pitch_scale, 0.62 + gear_rpm * 1.3 + absf(throttle) * 0.12, clampf(delta * 6.0, 0.0, 1.0))
	var want := (-6.0 + absf(throttle) * 4.0) if running else -80.0
	_engine.volume_db = lerpf(_engine.volume_db, want, clampf(delta * 4.0, 0.0, 1.0))
	if not running and _engine.volume_db < -60.0 and _engine.playing:
		_engine.stop()
	if _skid.stream != null:
		var skid_on := _slip > 0.25 and absf(speed) > 4.0 and _grounded >= 2
		if skid_on and not _skid.playing:
			_skid.play()
		_skid.volume_db = lerpf(_skid.volume_db, (-14.0 + _slip * 10.0) if skid_on else -70.0, clampf(delta * 8.0, 0.0, 1.0))
		if not skid_on and _skid.volume_db < -60.0 and _skid.playing:
			_skid.stop()


func _crash(dv: float) -> void:
	_crash_cd = 0.6
	if game != null:
		game.play_sfx_at("car_crash", global_position, clampf(dv / 3.0 - 2.0, -6.0, 6.0))
		if dv > 14.0:
			game.spawn_impact(global_position + Vector3.UP, Vector3.UP, null, true)
	var dmg := (dv - 9.0) * 22.0
	apply_damage(dmg, null)
	# Occupants feel a hard crash.
	for s in seats:
		if s != null and is_instance_valid(s) and s is Player:
			(s as Player).add_trauma(clampf(dv / 25.0, 0.2, 0.9))
			if dv > 18.0:
				(s as Player).take_damage((dv - 18.0) * 3.0, global_position, false, null)


func _on_body_entered(other: Node) -> void:
	# Ploughing into a parked jeep shoves it.
	if other is Vehicle:
		(other as Vehicle).wake()


# ------------------------------------------------------------------ damage --

## Bullets: the jeep soaks them; a little goes through to whoever is inside.
func take_damage(amount: float, pos: Vector3 = Vector3.ZERO, _headshot := false, source: Node = null) -> bool:
	if wrecked:
		return false
	if game != null:
		game.play_sfx_at("impact_metal", pos if pos != Vector3.ZERO else global_position, -3.0)
		game.spawn_impact(pos if pos != Vector3.ZERO else global_position, (pos - global_position).normalized(), self, false)
	apply_damage(amount * 0.8, source)
	return false


func apply_damage(amount: float, source: Node) -> void:
	if wrecked or amount <= 0.0:
		return
	wake()
	if not is_local():
		if game != null and game.has_method("net_vehicle_hit"):
			game.net_vehicle_hit(self, amount)
		return
	hp -= amount
	if hp <= 0.0:
		destroy(source)


## Owner side: blow it up and tell everyone.
func destroy(source: Node = null) -> void:
	if wrecked:
		return
	if game != null and game.has_method("net_vehicle_destroyed"):
		game.net_vehicle_destroyed(self)
	explode(source)


func explode(source: Node = null) -> void:
	if wrecked:
		return
	wake()
	wrecked = true
	alive = false
	hp = 0.0
	throttle = 0.0
	if game != null:
		game.spawn_explosion(global_position + Vector3.UP)
		game.vehicle_exploded(self, source)
	for m in _body_mats:
		m.albedo_color = m.albedo_color.darkened(0.75)
	for l in _lights:
		l.visible = false
	_burn_t = 25.0
	if is_local():
		apply_central_impulse(Vector3.UP * mass * 5.0)
		apply_torque_impulse(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * mass * 2.0)


## Already burnt out when we caught up with the match (no blast).
func wreck_quiet() -> void:
	if wrecked:
		return
	wrecked = true
	alive = false
	hp = 0.0
	throttle = 0.0
	for m in _body_mats:
		m.albedo_color = m.albedo_color.darkened(0.75)
	for l in _lights:
		l.visible = false


func _burn(delta: float) -> void:
	if _burn_t <= 0.0:
		return
	_burn_t -= delta
	_smoke_t -= delta
	if _smoke_t <= 0.0 and game != null:
		_smoke_t = 0.35
		game.spawn_smoke(global_position + Vector3(0, 1.4, -0.8), 2.0)


# --------------------------------------------------------------- networking --

func net_state() -> Array:
	return [net_id, global_position, global_basis.get_rotation_quaternion(), linear_velocity, hp, steer, speed, throttle]


func apply_net_state(st: Array) -> void:
	_net_pos = st[1]
	_net_rot = st[2]
	_net_vel = st[3]
	hp = float(st[4])
	steer = float(st[5])
	speed = float(st[6])
	throttle = float(st[7])
	if not _net_seen:
		global_position = _net_pos
		global_basis = Basis(_net_rot)
	_net_seen = true


func _puppet_follow(delta: float) -> void:
	if not _net_seen:
		return
	# Lead the snapshot a touch by its velocity so fast jeeps do not trail.
	var target := _net_pos + _net_vel * 0.05
	var k := clampf(delta * 14.0, 0.0, 1.0)
	if global_position.distance_to(target) > 12.0:
		global_position = target
	else:
		global_position = global_position.lerp(target, k)
	global_basis = Basis(global_basis.get_rotation_quaternion().slerp(_net_rot, k))
	for i in 4:
		_compress[i] = 0.08


func seat_transform(i: int) -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, SEATS[i])


func free_seat() -> int:
	for i in 4:
		if seats[i] == null or not is_instance_valid(seats[i]):
			seats[i] = null
			return i
	return -1
