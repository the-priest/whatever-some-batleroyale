extends Node3D
class_name Warden

## The anti-cheat's enforcer: a seven-metre cloaked thing with a bone mask,
## burning eyes and a jaw that drops to its chest. It hunts one cheater.
##
## On the cheater's machine it is real: the light drains away, a drone and
## a heartbeat build, it glides closer (faster whenever you are not looking
## at it, and it is never further than a short blink behind you), and when
## it reaches you its face fills the screen with a scream and you die.
## Everyone else sees it stalk that player (visual only).

signal caught

const HEIGHT := 7.0
const SPEED_SEEN := 4.0
const SPEED_UNSEEN := 11.0
const REACH := 3.6

var game: Node
var target: Node3D
var local_victim := false
var reason := ""
var _t := 0.0
var _jaw: Node3D
var _head: Node3D
var _arms: Array[Node3D] = []
var _cloak: Array[Node3D] = []
var _eyes: Array[MeshInstance3D] = []
var _eye_light: OmniLight3D
var _drone: AudioStreamPlayer
var _beat_t := 0.0
var _whisper_t := 4.0
var _done := false
var _scare_t := -1.0
var _twitch := Vector3.ZERO
var _twitch_t := 0.0
var _prey_last := Vector3.INF
var _prey_speed := 0.0
var _hunt_t := 0.0


func _ready() -> void:
	_build()
	if local_victim and game != null:
		_drone = AudioStreamPlayer.new()
		var st = game.sfx.stream("warden_drone")
		if st is AudioStreamWAV:
			var wav := (st as AudioStreamWAV).duplicate() as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_end = int(wav.get_length() * float(wav.mix_rate))
			st = wav
		_drone.stream = st
		_drone.volume_db = -30.0
		_drone.bus = "Master"
		add_child(_drone)
		if _drone.stream != null:
			_drone.play()


# ---------------------------------------------------------------- the body --
func _mat(c: Color, rough := 0.9, glow := 0.0, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = Color(c.r, c.g, c.b)
		m.emission_energy_multiplier = glow
	return m


func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, sc := Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation = rot
	m.scale = sc
	parent.add_child(m)
	return m


func _node(parent: Node3D, pos := Vector3.ZERO, rot := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation = rot
	parent.add_child(n)
	return n


static func _cone(r0: float, r1: float, h: float, seg := 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r0
	c.bottom_radius = r1
	c.height = h
	c.radial_segments = seg
	c.rings = 2
	return c


static func _ball(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 20
	s.rings = 12
	return s


func _build() -> void:
	var cloak := _mat(Color(0.035, 0.03, 0.04), 1.0)
	var rag := _mat(Color(0.06, 0.045, 0.05), 1.0)
	var bone := _mat(Color(0.86, 0.82, 0.72), 0.55)
	var dark := _mat(Color(0.0, 0.0, 0.0), 1.0)
	var gum := _mat(Color(0.35, 0.02, 0.03), 0.6, 0.3)
	var eye := _mat(Color(1.0, 0.06, 0.02), 0.3, 5.0)
	var body := _node(self)
	# Tattered cloak: layered cones, the hem ragged with hanging strips.
	for i in 3:
		var c := _mi(body, _cone(0.45 + i * 0.1, 1.5 - i * 0.18, 4.6 - i * 0.5), cloak if i == 0 else rag, Vector3(0, 2.3 + i * 0.25, 0), Vector3(0, i * 0.7, 0))
		_cloak.append(c)
	for k in 14:
		var a := TAU * float(k) / 14.0
		var strip := _mi(body, BoxMesh.new(), rag, Vector3(cos(a) * 1.3, 0.25, sin(a) * 1.3), Vector3(0, -a, randf_range(-0.2, 0.2)), Vector3(0.28, 0.9 + randf() * 0.7, 0.04))
		_cloak.append(strip)
	# Hunched shoulders and a long neck.
	_mi(body, _ball(0.75), cloak, Vector3(0, 4.9, 0.15), Vector3.ZERO, Vector3(1.5, 0.75, 1.0))
	_mi(body, _cone(0.16, 0.22, 1.2), bone, Vector3(0, 5.55, -0.35), Vector3(-0.7, 0, 0))
	# Head: a long bone skull in a black hood, brow overhanging deep black
	# sockets with burning eyes, ram horns curling back.
	_head = _node(body, Vector3(0, 6.05, -0.85), Vector3(0.35, 0, 0))
	# Hood: an open shell behind the skull, framing the face.
	var hm := SphereMesh.new()
	hm.radius = 0.62
	hm.height = 0.62
	hm.is_hemisphere = true
	hm.radial_segments = 20
	hm.rings = 8
	var hood_mat := cloak.duplicate() as StandardMaterial3D
	hood_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mi(_head, hm, hood_mat, Vector3(0, 0.12, 0.05), Vector3(PI * 0.5, 0, 0), Vector3(1.35, 1.0, 1.6))
	# Cranium wide on top, the face narrowing to a long chin.
	_mi(_head, _ball(0.5), bone, Vector3(0, 0.16, -0.1), Vector3.ZERO, Vector3(0.9, 0.95, 0.95))
	_mi(_head, _cone(0.3, 0.17, 0.5, 14), bone, Vector3(0, -0.22, -0.26), Vector3(-0.12, 0, 0), Vector3(1.0, 1.0, 0.75))
	for sx in [-1.0, 1.0]:
		_mi(_head, _ball(0.13), bone, Vector3(sx * 0.27, -0.2, -0.42), Vector3.ZERO, Vector3(1.0, 0.75, 0.8))
		# Angry brow: two ridges slanting down to the middle.
		_mi(_head, BoxMesh.new(), bone, Vector3(sx * 0.18, 0.27, -0.53), Vector3(0.3, 0, sx * -0.38), Vector3(0.34, 0.09, 0.18))
	for sx in [-1.0, 1.0]:
		_mi(_head, _ball(0.19), dark, Vector3(sx * 0.18, 0.08, -0.47), Vector3.ZERO, Vector3(1.1, 0.95, 0.5))
		var e := _mi(_head, _ball(0.055), eye, Vector3(sx * 0.18, 0.07, -0.55))
		_eyes.append(e)
		var horn := _node(_head, Vector3(sx * 0.32, 0.45, -0.05), Vector3(0.3, 0, sx * -0.9))
		_mi(horn, _cone(0.09, 0.15, 0.6, 8), bone, Vector3(0, 0.28, 0))
		var h2 := _node(horn, Vector3(0, 0.55, 0), Vector3(1.0, 0, 0))
		_mi(h2, _cone(0.05, 0.09, 0.55, 8), bone, Vector3(0, 0.26, 0))
		var h3 := _node(h2, Vector3(0, 0.52, 0), Vector3(1.2, 0, 0))
		_mi(h3, _cone(0.0, 0.05, 0.45, 6), bone, Vector3(0, 0.2, 0))
	# Nose cavity.
	_mi(_head, _ball(0.07), dark, Vector3(0, -0.12, -0.6), Vector3.ZERO, Vector3(0.7, 1.2, 0.5))
	# Jaw on a hinge at the back of the face: it drops, and drops, showing a
	# black throat and two rows of long teeth.
	_mi(_head, _ball(0.25), dark, Vector3(0, -0.46, -0.3), Vector3.ZERO, Vector3(0.8, 0.5, 0.9))
	_jaw = _node(_head, Vector3(0, -0.45, -0.05))
	_mi(_jaw, _cone(0.2, 0.11, 0.42, 12), bone, Vector3(0, -0.06, -0.28), Vector3(PI * 0.5 + 0.15, 0, 0), Vector3(1.0, 1.0, 0.55))
	_mi(_jaw, _ball(0.2), dark, Vector3(0, 0.0, -0.28), Vector3.ZERO, Vector3(0.75, 0.4, 1.1))
	var tooth := _cone(0.0, 0.035, 0.2, 5)
	for k in 7:
		var x := (float(k) - 3.0) * 0.055
		var z := -0.47 + absf(float(k) - 3.0) * 0.035
		_mi(_head, tooth, bone, Vector3(x, -0.5, z), Vector3(PI, 0, 0))
		_mi(_jaw, tooth, bone, Vector3(x * 0.85, 0.05, z + 0.03 - 0.0))
	# Arms: far too long, ending in hooked claws.
	for sx in [-1.0, 1.0]:
		var sh := _node(body, Vector3(sx * 0.95, 4.95, 0.0), Vector3(0.3, 0, sx * 0.25))
		_mi(sh, _cone(0.12, 0.2, 2.2), rag, Vector3(0, -1.1, 0))
		var el := _node(sh, Vector3(0, -2.15, 0), Vector3(-0.6, 0, 0))
		_mi(el, _cone(0.09, 0.14, 2.3), bone, Vector3(0, -1.15, 0))
		var hand := _node(el, Vector3(0, -2.3, 0))
		_mi(hand, _ball(0.2), bone, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.7, 1.2))
		for f in 4:
			var fa := (float(f) - 1.5) * 0.3
			var claw := _node(hand, Vector3(sin(fa) * 0.15, -0.05, -0.1), Vector3(-0.5, fa, 0))
			_mi(claw, _cone(0.0, 0.045, 0.9, 5), bone, Vector3(0, -0.44, 0), Vector3(PI, 0, 0))
		_arms.append(sh)
	_eye_light = OmniLight3D.new()
	_eye_light.light_color = Color(1.0, 0.12, 0.05)
	_eye_light.light_energy = 3.0
	_eye_light.omni_range = 9.0
	_eye_light.shadow_enabled = false
	_head.add_child(_eye_light)
	_eye_light.position = Vector3(0, 0.1, -0.9)
	for c in find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# A slow fall of black ash around it.
	var ash := CPUParticles3D.new()
	ash.amount = 60
	ash.lifetime = 3.0
	ash.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	ash.emission_sphere_radius = 2.5
	ash.gravity = Vector3(0, -0.4, 0)
	ash.initial_velocity_min = 0.1
	ash.initial_velocity_max = 0.5
	ash.scale_amount_min = 0.06
	ash.scale_amount_max = 0.16
	var q := QuadMesh.new()
	q.size = Vector2(0.4, 0.4)
	var am := _mat(Color(0.02, 0.02, 0.02, 0.8), 1.0)
	am.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	am.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = am
	ash.mesh = q
	ash.position = Vector3(0, 3.5, 0)
	add_child(ash)
	# Black smoke rolling off the hem.
	var smoke := CPUParticles3D.new()
	smoke.amount = 40
	smoke.lifetime = 4.0
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	smoke.emission_ring_axis = Vector3.UP
	smoke.emission_ring_radius = 1.6
	smoke.emission_ring_inner_radius = 0.6
	smoke.emission_ring_height = 0.2
	smoke.gravity = Vector3(0, 0.25, 0)
	smoke.initial_velocity_min = 0.2
	smoke.initial_velocity_max = 0.7
	smoke.scale_amount_min = 1.2
	smoke.scale_amount_max = 2.6
	var sq := QuadMesh.new()
	sq.size = Vector2(1.0, 1.0)
	var sm := _mat(Color(0.01, 0.0, 0.01, 0.55), 1.0)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.albedo_texture = _soft_dot()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sq.material = sm
	smoke.mesh = sq
	smoke.color_ramp = _fade_ramp()
	smoke.position = Vector3(0, 0.3, 0)
	add_child(smoke)
	# Bigger than anything on the island.
	scale = Vector3.ONE * 1.35


static func _soft_dot() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


static func _fade_ramp() -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	return g


# ----------------------------------------------------------------- the hunt --
func _process(delta: float) -> void:
	_t += delta
	if target == null or not is_instance_valid(target) or (target is Bot and not (target as Bot).alive):
		# Its work is done: it sinks back into the ground.
		global_position.y -= delta * 3.0
		if target == null or not is_instance_valid(target) or global_position.y < _ground(global_position) - 12.0:
			queue_free()
		return
	if _scare_t >= 0.0:
		_jumpscare(delta)
		return
	var tp := target.global_position
	var to := tp - global_position
	to.y = 0.0
	var d := to.length()
	# How fast the prey runs (speed hackers run very fast).
	if _prey_last != Vector3.INF and delta > 0.0:
		var v := Vector2(tp.x - _prey_last.x, tp.z - _prey_last.z).length() / delta
		_prey_speed = lerpf(_prey_speed, minf(v, 400.0), clampf(delta * 3.0, 0.0, 1.0))
	_prey_last = tp
	_hunt_t += delta
	# Faster when you are not looking, and always faster than you can run.
	var seen := _looked_at()
	var sp := SPEED_SEEN if seen else SPEED_UNSEEN
	sp = maxf(sp, _prey_speed * 1.4 + 3.0)
	if local_victim and _hunt_t > 20.0 and d > REACH:
		# It has played with you long enough: it is right behind you.
		global_position = _behind(target, REACH * 0.6)
		to = tp - global_position
		to.y = 0.0
		d = to.length()
	if d > 45.0 and not seen:
		var back := _behind(target, 22.0)
		global_position = back
		to = tp - global_position
		to.y = 0.0
		d = to.length()
	if d > 0.1:
		global_position += to.normalized() * minf(d, sp * delta)
	var gy := _ground(global_position)
	global_position.y = lerpf(global_position.y, gy + 0.15 + sin(_t * 1.3) * 0.12, clampf(delta * 4.0, 0.0, 1.0))
	look_at(Vector3(tp.x, global_position.y, tp.z), Vector3.UP)
	# Twitching head, swaying cloak, arms reaching as it closes in.
	_twitch_t -= delta
	if _twitch_t <= 0.0:
		_twitch_t = randf_range(0.2, 1.4)
		_twitch = Vector3(randf_range(-0.25, 0.25), randf_range(-0.5, 0.5), randf_range(-0.6, 0.6))
	_head.rotation = _head.rotation.lerp(Vector3(0.35, 0, 0) + _twitch, clampf(delta * 14.0, 0.0, 1.0))
	var reach := clampf(1.0 - (d - REACH) / 18.0, 0.0, 1.0)
	for i in _arms.size():
		var sx := -1.0 if i == 0 else 1.0
		_arms[i].rotation = Vector3(0.3 - reach * 1.5 + sin(_t * 2.0 + i) * 0.08, 0, sx * (0.25 - reach * 0.15))
	for i in _cloak.size():
		_cloak[i].rotation.z = sin(_t * 1.7 + i) * 0.05
	_jaw.rotation.x = -(0.25 + sin(_t * 3.0) * 0.08 + reach * 0.35)
	_eye_light.light_energy = 2.5 + sin(_t * 9.0) * 0.6 + reach * 4.0
	if local_victim:
		_haunt(d, delta, seen)
	if d < REACH and local_victim and not _done:
		_begin_scare()
	elif d < REACH and not local_victim:
		set_process(false)


func _looked_at() -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	var to := (global_position + Vector3.UP * 4.5) - cam.global_position
	return (-cam.global_basis.z).dot(to.normalized()) > 0.82


func _behind(n: Node3D, dist: float) -> Vector3:
	var fwd := -n.global_basis.z
	if n is Player:
		fwd = Basis(Vector3.UP, (n as Player).yaw) * Vector3(0, 0, -1)
	fwd.y = 0.0
	var spread := minf(6.0, dist * 0.25)
	var p := n.global_position - fwd.normalized() * dist + Vector3(randf_range(-spread, spread), 0, randf_range(-spread, spread))
	p.y = _ground(p)
	return p


func _ground(p: Vector3) -> float:
	if game != null and game.terrain != null:
		return float(game.terrain.height_at(p.x, p.z))
	return p.y


## The dread: darkness closing in, heartbeat, whispers.
func _haunt(d: float, delta: float, _seen: bool) -> void:
	var near := clampf(1.0 - d / 60.0, 0.0, 1.0)
	if _drone != null:
		_drone.volume_db = lerpf(-24.0, -3.0, near)
		_drone.pitch_scale = lerpf(0.9, 1.15, near)
	if game != null and game.hud != null:
		game.hud.set_dread(0.35 + near * 0.65)
	_beat_t -= delta
	if _beat_t <= 0.0:
		_beat_t = lerpf(1.1, 0.32, near)
		game.sfx.play_2d("heartbeat", lerpf(-6.0, 4.0, near), 0.0)
	_whisper_t -= delta
	if _whisper_t <= 0.0:
		_whisper_t = randf_range(3.0, 7.0)
		game.sfx.play_at("warden_whisper", global_position + Vector3.UP * 5.0, lerpf(0.0, 6.0, near), 0.1)


# --------------------------------------------------------------- jumpscare --
func _begin_scare() -> void:
	_done = true
	_scare_t = 0.0
	if target is Player:
		var p := target as Player
		p.set_physics_process(false)
		p.set_process_unhandled_input(false)
		p.hands.visible = false
		p.gun_holder.visible = false
	if _drone != null:
		_drone.stop()
	game.sfx.play_2d("warden_scream", 2.0, 0.0)
	if game.hud != null:
		game.hud.set_dread(1.0)


func _jumpscare(delta: float) -> void:
	_scare_t += delta
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# The face rushes the lens, jaw dropping, eyes flaring.
	var k := clampf(_scare_t / 0.32, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	var fwd := -cam.global_basis.z
	# Turn to face the camera, head level with it, then slide the whole body
	# so the face sits right in front of the lens.
	global_rotation = Vector3(0.0, atan2(fwd.x, fwd.z), 0.0)
	_head.rotation = Vector3(0.05 + randf_range(-0.05, 0.05), randf_range(-0.07, 0.07), randf_range(-0.1, 0.1))
	var head_target := cam.global_position + fwd * lerpf(5.0, 1.75, e) + Vector3.DOWN * 0.15
	global_position += head_target - _head.global_position
	_jaw.rotation.x = -lerpf(0.3, 0.95, e)
	_eye_light.light_energy = 10.0
	for ey in _eyes:
		ey.scale = Vector3.ONE * (1.0 + e * 0.35)
	if target is Player:
		(target as Player).add_trauma(1.0)
		cam.fov = lerpf(cam.fov, 58.0, clampf(delta * 10.0, 0.0, 1.0))
	if game.hud != null:
		game.hud.set_scare(clampf((_scare_t - 0.25) / 0.5, 0.0, 1.0))
	if _scare_t > 1.15:
		set_process(false)
		caught.emit()
		if target is Player:
			var p := target as Player
			p.set_physics_process(true)
			p.set_process_unhandled_input(true)
			p.spawn_protect = 0.0
			p.take_damage(10000.0, global_position, false, self)
		if game.hud != null:
			game.hud.set_scare(0.0)
			game.hud.set_dread(0.0)
		queue_free()


func display_name() -> String:
	return "THE WARDEN"
