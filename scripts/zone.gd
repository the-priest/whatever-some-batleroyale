class_name Zone
extends Node3D

signal phase_changed(phase: int, warning: bool)

# Shrinking storm circle. Each phase holds (next circle already known and shown
# on the map), then closes onto it. Anyone outside takes ramping damage.

# Roughly 11-12 minutes from landing to the last circle.
const HOLD := [100.0, 80.0, 65.0, 55.0, 45.0, 35.0, 25.0]
const SHRINK := [75.0, 60.0, 50.0, 42.0, 35.0, 28.0, 22.0]
const FRACTION := [0.62, 0.60, 0.55, 0.52, 0.48, 0.42, 0.0]
const DAMAGE := [1.0, 2.0, 3.0, 5.0, 8.0, 11.0, 15.0, 20.0]

var terrain: Terrain = null

var center := Vector2.ZERO
var radius := 430.0
var target_center := Vector2.ZERO
var target_radius := 430.0
var start_radius := 430.0
var start_center := Vector2.ZERO

var phase := 0
var state := "hold"          # hold | shrink | done
var timer := 45.0
var phase_duration := 40.0
var warning := false
var finished := false

var wall: MeshInstance3D
var ring: MeshInstance3D
var _wall_mat: ShaderMaterial


func _ready() -> void:
	_build_wall()


func _build_wall() -> void:
	wall = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 2.0
	cyl.radial_segments = 128
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	wall.mesh = cyl
	_wall_mat = ShaderMaterial.new()
	_wall_mat.shader = load("res://shaders/zone.gdshader")
	wall.material_override = _wall_mat
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wall.position.y = 60.0
	add_child(wall)

	ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.985
	torus.outer_radius = 1.0
	torus.rings = 128
	torus.ring_segments = 4
	ring.mesh = torus
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(0.72, 0.5, 1.0, 0.9)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# A thin glowing ribbon on the ground must never write depth, or it fights
	# the terrain at grazing angles.
	rm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	_apply_wall()


func start(p_island_radius: float) -> void:
	radius = p_island_radius
	start_radius = radius
	center = Vector2.ZERO
	start_center = center
	phase = 0
	state = "hold"
	timer = HOLD[0]
	finished = false
	warning = false
	_choose_next()
	_apply_wall()


func _choose_next() -> void:
	var idx := clampi(phase, 0, FRACTION.size() - 1)
	target_radius = radius * float(FRACTION[idx])
	if target_radius < 1.0:
		target_radius = 0.0
		target_center = center
		return
	# The new circle sits fully inside the old one, and its middle is on land.
	var drift := maxf(0.0, radius - target_radius) * 0.85
	var best := center
	var best_score := -1e9
	for i in 24:
		var a := randf() * TAU
		var c := center + Vector2(cos(a), sin(a)) * sqrt(randf()) * drift
		var score := randf() * 4.0
		if terrain != null:
			var h := terrain.height_at(c.x, c.y)
			if h < Terrain.WATER_LEVEL + 1.0:
				score -= 100.0
			score -= maxf(0.0, c.length() + target_radius - 400.0) * 0.5
		if score > best_score:
			best_score = score
			best = c
	target_center = best


func _process(delta: float) -> void:
	if finished:
		return
	if state == "hold":
		timer -= delta
		warning = timer < 8.0
		if timer <= 0.0:
			_begin_shrink()
	else:
		timer -= delta
		var k: float = clampf(1.0 - timer / maxf(0.5, phase_duration), 0.0, 1.0)
		radius = lerpf(start_radius, target_radius, k)
		center = start_center.lerp(target_center, k)
		warning = true
		if timer <= 0.0:
			radius = target_radius
			center = target_center
			phase += 1
			if phase >= FRACTION.size() or radius < 1.0:
				finished = true
				state = "done"
				radius = maxf(radius, 0.0)
			else:
				state = "hold"
				timer = float(HOLD[mini(phase, HOLD.size() - 1)])
				warning = false
				_choose_next()
			phase_changed.emit(phase, warning)
	_apply_wall()


func _begin_shrink() -> void:
	state = "shrink"
	start_radius = radius
	start_center = center
	phase_duration = float(SHRINK[mini(phase, SHRINK.size() - 1)])
	timer = phase_duration
	warning = true
	phase_changed.emit(phase, warning)


func _apply_wall() -> void:
	if wall == null:
		return
	var r := maxf(radius, 0.05)
	wall.scale = Vector3(r, 100.0, r)
	wall.position = Vector3(center.x, 60.0, center.y)
	ring.scale = Vector3(r, 0.6, r)
	ring.position = Vector3(center.x, 0.8, center.y)
	ring.visible = radius > 0.5
	if _wall_mat != null:
		_wall_mat.set_shader_parameter("radius", r)


func damage_per_second() -> float:
	return float(DAMAGE[clampi(phase, 0, DAMAGE.size() - 1)])


func is_outside(pos: Vector3) -> bool:
	return Vector2(pos.x, pos.z).distance_to(center) > radius


func distance_outside(pos: Vector3) -> float:
	return Vector2(pos.x, pos.z).distance_to(center) - radius


func time_left() -> float:
	return maxf(0.0, timer) if not finished else 0.0


func next_radius() -> float:
	if finished:
		return radius
	return target_radius


func next_center() -> Vector2:
	if finished:
		return center
	return target_center


func label() -> String:
	if finished:
		return "FINAL ZONE"
	if state == "hold":
		return "ZONE HOLDING"
	return "ZONE CLOSING"
