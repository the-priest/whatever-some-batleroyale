class_name Airdrop
extends Node3D

# Supply crate that floats down under a chute with a red smoke beacon, then
# spills high-tier loot around itself when it lands.

const FALL_SPEED := 6.5

var game: Node = null
var ground_y := 0.0
var landed := false
var crate: MeshInstance3D
var chute: MeshInstance3D
var smoke: GPUParticles3D
var beacon: MeshInstance3D
var _t := 0.0


func setup(p_game: Node, pos: Vector2, p_ground: float) -> void:
	game = p_game
	ground_y = p_ground
	position = Vector3(pos.x, p_ground + 150.0, pos.y)


func _ready() -> void:
	crate = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.6, 1.2, 1.6)
	crate.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.18, 0.30, 0.52)
	m.roughness = 0.55
	m.metallic = 0.3
	crate.material_override = m
	crate.position.y = 0.6
	add_child(crate)
	for i in 2:
		var band := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(1.64, 0.14, 1.64) if i == 0 else Vector3(0.18, 1.24, 1.64)
		band.mesh = bb
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(0.95, 0.62, 0.18)
		bmat.emission_enabled = true
		bmat.emission = Color(0.95, 0.55, 0.15)
		bmat.emission_energy_multiplier = 0.6
		band.material_override = bmat
		crate.add_child(band)

	chute = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 3.4
	sm.height = 3.0
	sm.is_hemisphere = true
	sm.radial_segments = 12
	sm.rings = 4
	chute.mesh = sm
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.92, 0.36, 0.22)
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	cm.roughness = 0.9
	chute.material_override = cm
	chute.position.y = 6.5
	add_child(chute)

	beacon = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.9
	cyl.height = 120.0
	cyl.radial_segments = 8
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	beacon.mesh = cyl
	var bm2 := StandardMaterial3D.new()
	bm2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm2.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm2.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm2.albedo_color = Color(1.0, 0.25, 0.15, 0.22)
	beacon.material_override = bm2
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beacon.visible = false
	add_child(beacon)

	smoke = GPUParticles3D.new()
	smoke.amount = 60
	smoke.lifetime = 6.0
	smoke.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3(0.6, 0.4, 0.0)
	pm.scale_min = 1.2
	pm.scale_max = 2.6
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.25, 0.18, 0.75))
	grad.set_color(1, Color(0.9, 0.4, 0.35, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	smoke.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.6, 1.6)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.vertex_color_use_as_albedo = true
	qm.albedo_texture = load("res://assets/textures/tex_cloud.png")
	q.material = qm
	smoke.draw_pass_1 = q
	smoke.visibility_aabb = AABB(Vector3(-20, -2, -20), Vector3(40, 60, 40))
	smoke.position.y = 1.3
	add_child(smoke)


func _process(delta: float) -> void:
	if Prof.on:
		var t0 := Time.get_ticks_usec()
		_process_body(delta)
		Prof.add("airdrop", Time.get_ticks_usec() - t0)
	else:
		_process_body(delta)


func _process_body(delta: float) -> void:
	_t += delta
	if landed:
		return
	position.y -= FALL_SPEED * delta
	rotation.y += delta * 0.3
	chute.rotation.z = sin(_t * 1.3) * 0.06
	if position.y <= ground_y:
		position.y = ground_y
		_land()


func _land() -> void:
	landed = true
	rotation.y = 0.0
	var tw := chute.create_tween()
	tw.tween_property(chute, "scale", Vector3(1.0, 0.05, 1.0), 0.8)
	tw.tween_callback(chute.queue_free)
	smoke.emitting = true
	beacon.visible = true
	beacon.position.y = 60.0
	if game != null and game.has_method("on_airdrop_landed"):
		game.on_airdrop_landed(self)
	# Solid crate to take cover behind.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 1.2, 1.6)
	cs.shape = box
	cs.position.y = 0.6
	body.add_child(cs)
	add_child(body)
