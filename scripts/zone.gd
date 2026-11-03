class_name Zone
extends Node3D

signal phase_changed(phase: int, warning: bool)

# Shrinking circle. Phases hold, then close; anyone outside takes ramping damage.

var center := Vector2(0, 0)
var radius := 430.0
var target_center := Vector2(0, 0)
var target_radius := 430.0
var start_radius := 430.0
var start_center := Vector2(0, 0)

var phase := 0
var state := "hold"          # hold | shrink
var timer := 22.0
var hold_time := 22.0
var shrink_time := 18.0
var warning := false
var finished := false

var wall: MeshInstance3D
var ring: MeshInstance3D
var damage_table := [1.0, 2.0, 4.0, 7.0, 10.0, 14.0]
var island_radius := 430.0

# Each phase target as a fraction of the previous radius.
var targets := [0.62, 0.58, 0.55, 0.50, 0.46, 0.02]


func _ready() -> void:
	_build_wall()


func _build_wall() -> void:
	wall = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 2.0
	cyl.radial_segments = 96
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	wall.mesh = cyl
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/zone.gdshader")
	wall.material_override = mat
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wall.position.y = 60.0
	add_child(wall)

	ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.985
	torus.outer_radius = 1.0
	torus.rings = 96
	torus.ring_segments = 4
	ring.mesh = torus
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(0.4, 0.72, 1.0)
	rm.emission_enabled = true
	rm.emission = Color(0.35, 0.66, 1.0)
	rm.emission_energy_multiplier = 2.4
	rm.albedo_color.a = 0.9
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# A razor-thin glowing ribbon lying on the ground must never write depth, or
	# it fights the terrain/sea at grazing angles.
	rm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	rm.no_depth_test = false
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	_apply_wall()


func start(p_island_radius: float) -> void:
	island_radius = p_island_radius
	radius = p_island_radius
	start_radius = radius
	target_radius = radius
	center = Vector2.ZERO
	target_center = center
	phase = 0
	state = "hold"
	timer = 20.0
	finished = false
	warning = false
	_apply_wall()


func _process(delta: float) -> void:
	if finished:
		return
	if state == "hold":
		timer -= delta
		warning = timer < 6.0
		if timer <= 0.0:
			_begin_shrink()
	else:
		shrink_time -= delta
		var t := 1.0 - clampf(shrink_time / maxf(0.01, shrink_time + 0.0001), 0.0, 1.0)
		# Use elapsed ratio instead: recompute from stored duration.
		var dur: float = float(maxf(0.5, phase_duration))
		var k: float = clampf(1.0 - shrink_time / dur, 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)
		radius = lerpf(start_radius, target_radius, k)
		center = start_center.lerp(target_center, k)
		warning = true
		if shrink_time <= 0.0:
			radius = target_radius
			center = target_center
			phase += 1
			if phase >= targets.size() or radius < 3.0:
				finished = true
				radius = maxf(radius, 2.0)
			else:
				state = "hold"
				timer = maxf(8.0, hold_time * pow(0.86, phase))
				warning = false
			phase_changed.emit(phase, warning)
	_apply_wall()


var phase_duration := 18.0


func _begin_shrink() -> void:
	state = "shrink"
	start_radius = radius
	start_center = center
	var idx: int = clampi(phase, 0, targets.size() - 1)
	target_radius = maxf(2.0, radius * float(targets[idx]))
	# New circle must sit inside the old one.
	var drift: float = maxf(0.0, (radius - target_radius) * 0.7)
	var ang := randf() * TAU
	var d := randf() * drift
	target_center = center + Vector2(cos(ang), sin(ang)) * d
	phase_duration = maxf(10.0, shrink_time_max() * pow(0.9, phase))
	shrink_time = phase_duration
	warning = true
	phase_changed.emit(phase, warning)


func shrink_time_max() -> float:
	return 20.0


func _apply_wall() -> void:
	if wall == null:
		return
	wall.scale = Vector3(radius, 100.0, radius)
	wall.position = Vector3(center.x, 60.0, center.y)
	ring.scale = Vector3(radius, 0.6, radius)
	ring.position = Vector3(center.x, 0.8, center.y)


func damage_per_second() -> float:
	return float(damage_table[clampi(phase, 0, damage_table.size() - 1)])


func is_outside(pos: Vector3) -> bool:
	return Vector2(pos.x, pos.z).distance_to(center) > radius


func time_left() -> float:
	return timer if state == "hold" else shrink_time


func next_radius() -> float:
	if state == "hold":
		var idx: int = clampi(phase, 0, targets.size() - 1)
		return maxf(2.0, radius * float(targets[idx]))
	return target_radius


func label() -> String:
	if state == "hold":
		return "ZONE HOLDING"
	return "ZONE CLOSING"
