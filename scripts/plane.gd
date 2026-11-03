class_name DropPlane
extends Node3D

# Four-engine cargo turboprop that carries the lobby across the island.
# Built from primitives: rounded fuselage, tapered high wing, nacelles with
# spinning props, swept tail, windows and an open rear ramp. -Z is forward.

var speed := 26.0
var start := Vector3(-520, 190, -430)
var finish := Vector3(360, 182, 470)
var t := 0.0
var active := true
var length := 0.0
var propellers: Array[Node3D] = []
var prop_discs: Array[MeshInstance3D] = []
var ramp: Node3D
var strobe: OmniLight3D
var _t := 0.0

var _paint: StandardMaterial3D
var _belly: StandardMaterial3D
var _dark: StandardMaterial3D
var _metal: StandardMaterial3D
var _glass: StandardMaterial3D
var _stripe: StandardMaterial3D
var _interior: StandardMaterial3D


func setup(from: Vector3, to: Vector3) -> void:
	start = from
	finish = to
	length = start.distance_to(finish)
	_build()
	position = start
	look_at(finish, Vector3.UP)


func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _build() -> void:
	_paint = _mat(Color(0.36, 0.40, 0.33), 0.55, 0.25)      # olive drab
	_belly = _mat(Color(0.58, 0.61, 0.60), 0.5, 0.25)       # light grey underside
	_dark = _mat(Color(0.10, 0.11, 0.11), 0.5, 0.4)
	_metal = _mat(Color(0.45, 0.46, 0.47), 0.3, 0.8)
	_glass = _mat(Color(0.10, 0.16, 0.20), 0.08, 0.9)
	_stripe = _mat(Color(0.86, 0.62, 0.20), 0.5, 0.1)
	_interior = _mat(Color(0.05, 0.05, 0.055), 0.9, 0.0)
	_interior.cull_mode = BaseMaterial3D.CULL_DISABLED

	var along := Vector3(PI * 0.5, 0, 0)

	# Fuselage: main barrel, upper/lower halves in two colours, tapered nose
	# and a tail cone that sweeps up toward the fin.
	_cyl(Vector3(0, 0, 0), 1.55, 1.55, 15.0, _paint, along, 28)
	var belly := _cyl(Vector3(0, -0.35, 0), 1.45, 1.45, 15.0, _belly, along, 28)
	belly.scale = Vector3(1.0, 1.0, 0.82)
	_cyl(Vector3(0, -0.05, -8.6), 1.55, 1.05, 2.2, _paint, along, 28)
	var nose := _sphere(Vector3(0, -0.15, -9.65), 1.08, _paint)
	nose.scale = Vector3(1.0, 0.95, 1.25)
	var tail := _cyl(Vector3(0, 0.45, 9.6), 0.45, 1.55, 4.4, _paint, along, 24)
	tail.rotation.x = PI * 0.5 + 0.12
	_cyl(Vector3(0, 0.95, 12.0), 0.2, 0.45, 1.2, _paint, along, 16)

	# Livery stripe and fuselage band.
	var stripe := _box(Vector3(1.57, 0.12, 0.0), Vector3(0.02, 0.22, 17.0), _stripe)
	var stripe2 := _box(Vector3(-1.57, 0.12, 0.0), Vector3(0.02, 0.22, 17.0), _stripe)
	stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stripe2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Cockpit glazing: a wrap-around band of panes.
	for i in 5:
		var a := -0.9 + i * 0.45
		var pane := _box(Vector3(sin(a) * 1.08, 0.55, -9.75 + absf(a) * 0.25), Vector3(0.42, 0.34, 0.06), _glass)
		pane.rotation = Vector3(-0.45, a, 0)
	# Cabin windows.
	for side in [-1.0, 1.0]:
		for i in 8:
			_box(Vector3(side * 1.56, 0.55, -6.0 + i * 1.5), Vector3(0.04, 0.28, 0.32), _glass)
		# Para door near the back.
		_box(Vector3(side * 1.56, -0.1, 5.6), Vector3(0.05, 1.7, 0.9), _dark)

	# High wing: tapered in plan, slight dihedral, with flap track fairings.
	for side in [-1.0, 1.0]:
		var wing := Node3D.new()
		wing.position = Vector3(side * 1.2, 1.35, -1.6)
		wing.rotation.z = side * deg_to_rad(2.5)
		add_child(wing)
		for seg in 4:
			var span := 3.6
			var x: float = side * (span * 0.5 + seg * span)
			var chord := 4.2 - seg * 0.55
			var thick := 0.5 - seg * 0.07
			var w := _box(Vector3(x, 0, -0.3 + seg * 0.18), Vector3(span + 0.05, thick, chord), _paint, wing)
			w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# Wing tip light.
		var tip := OmniLight3D.new()
		tip.position = Vector3(side * 14.6, 0.0, 0.4)
		tip.light_color = Color(0.95, 0.15, 0.1) if side < 0.0 else Color(0.15, 0.95, 0.3)
		tip.light_energy = 1.4
		tip.omni_range = 5.0
		wing.add_child(tip)
		var lamp := _sphere(Vector3(side * 14.6, 0, 0.4), 0.12, _mat(tip.light_color, 0.2, 0.0), wing)
		(lamp.material_override as StandardMaterial3D).emission_enabled = true
		(lamp.material_override as StandardMaterial3D).emission = tip.light_color
		(lamp.material_override as StandardMaterial3D).emission_energy_multiplier = 3.0

		# Two engines per wing.
		for e in 2:
			var ex: float = side * (4.6 + e * 4.6)
			var nac := _cyl(Vector3(ex, -0.25, -2.6), 0.62, 0.72, 4.2, _paint, along, 20, wing)
			nac.position = Vector3(ex, -0.25, -2.4)
			_cyl(Vector3(ex, -0.25, -4.75), 0.72, 0.55, 0.3, _dark, along, 20, wing)
			_sphere(Vector3(ex, -0.25, -4.95), 0.32, _metal, wing)  # spinner
			_cyl(Vector3(ex, -0.6, -1.0), 0.25, 0.2, 1.2, _dark, along, 12, wing)  # exhaust
			var prop := Node3D.new()
			prop.position = Vector3(ex, -0.25, -5.0)
			wing.add_child(prop)
			for b in 4:
				var blade := _box(Vector3.ZERO, Vector3(0.22, 2.0, 0.06), _dark, prop)
				blade.position = Vector3(0, 1.0, 0).rotated(Vector3.FORWARD, b * PI * 0.5)
				blade.rotation = Vector3(0.25, 0, b * PI * 0.5)
			propellers.append(prop)
			# Motion-blur disc so a spinning prop reads at any frame rate.
			var disc := MeshInstance3D.new()
			var dm := CylinderMesh.new()
			dm.top_radius = 2.05
			dm.bottom_radius = 2.05
			dm.height = 0.02
			dm.radial_segments = 32
			disc.mesh = dm
			var dmat := StandardMaterial3D.new()
			dmat.albedo_color = Color(0.1, 0.1, 0.1, 0.18)
			dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			dmat.cull_mode = BaseMaterial3D.CULL_DISABLED
			disc.material_override = dmat
			disc.rotation.x = PI * 0.5
			disc.position = Vector3(ex, -0.25, -5.02)
			disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			wing.add_child(disc)
			prop_discs.append(disc)

	# Wing-to-body fairing.
	_box(Vector3(0, 1.3, -1.4), Vector3(2.6, 0.6, 4.6), _paint)

	# Tail: swept fin with rudder line, horizontal stabilisers.
	var fin := _box(Vector3(0, 3.4, 11.4), Vector3(0.28, 4.2, 2.6), _paint)
	fin.rotation.x = deg_to_rad(-22)
	var rudder := _box(Vector3(0, 3.3, 12.75), Vector3(0.26, 3.6, 0.7), _belly)
	rudder.rotation.x = deg_to_rad(-22)
	var fin_band := _box(Vector3(0, 4.3, 11.75), Vector3(0.3, 0.5, 2.0), _stripe)
	fin_band.rotation.x = deg_to_rad(-22)
	for side in [-1.0, 1.0]:
		var stab := _box(Vector3(side * 3.0, 1.15, 11.9), Vector3(5.6, 0.22, 2.0), _paint)
		stab.rotation.y = side * deg_to_rad(-10)

	# Open rear ramp with a dark cargo hold behind it, so the jump door reads.
	_cyl(Vector3(0, -0.1, 6.8), 1.35, 1.35, 3.0, _interior, along, 24)
	ramp = _box(Vector3(0, -1.45, 9.4), Vector3(2.4, 0.15, 3.2), _belly)
	ramp.rotation.x = deg_to_rad(18)

	# Landing gear sponsons.
	for side in [-1.0, 1.0]:
		var sp := _cyl(Vector3(side * 1.55, -1.1, 0.5), 0.55, 0.55, 5.0, _paint, along, 16)
		sp.scale = Vector3(0.8, 1.0, 0.7)

	# Anti-collision strobe on the belly.
	strobe = OmniLight3D.new()
	strobe.position = Vector3(0, -1.7, 0)
	strobe.light_color = Color(1.0, 0.2, 0.15)
	strobe.omni_range = 7.0
	add_child(strobe)


func _box(pos: Vector3, size: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	(parent if parent != null else self).add_child(mi)
	return mi


func _cyl(pos: Vector3, r_top: float, r_bot: float, h: float, mat: Material, rot: Vector3, seg := 20, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = seg
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	(parent if parent != null else self).add_child(mi)
	return mi


func _sphere(pos: Vector3, r: float, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 20
	sm.rings = 10
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	(parent if parent != null else self).add_child(mi)
	return mi


func _physics_process(delta: float) -> void:
	_t += delta
	for p in propellers:
		p.rotation.z += delta * 38.0
	for d in prop_discs:
		d.rotation.y += delta * 3.0
	strobe.light_energy = 3.0 if fmod(_t, 1.2) < 0.08 else 0.0
	if not active:
		return
	t = minf(1.0, t + (speed * delta) / maxf(1.0, length))
	position = start.lerp(finish, t) + Vector3(0, sin(t * 9.0) * 0.8, 0)
	# Gentle turbulence.
	rotation.z = sin(_t * 0.7) * 0.025 + sin(_t * 2.3) * 0.006
	rotation.x = sin(_t * 0.5) * 0.01
	if t >= 1.0:
		active = false


func progress() -> float:
	return t


## Inside the hold, just ahead of the ramp.
func seat_position() -> Vector3:
	return global_position + global_basis * Vector3(0, -0.3, 6.0)


func jump_velocity() -> Vector3:
	var forward := global_basis * Vector3(0, 0, -1)
	return forward * speed * 0.55


func chase_position() -> Vector3:
	return global_position + global_basis * Vector3(0, 6.5, 26.0)
