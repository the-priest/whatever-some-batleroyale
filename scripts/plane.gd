class_name DropPlane
extends Node3D

# A blocky cargo plane that carries the whole lobby across the island.
# The player rides in a cinematic chase view until they jump.

var speed := 26.0
var start := Vector3(-520, 190, -430)
var finish := Vector3(360, 182, 470)
var t := 0.0
var active := true
var length := 0.0
var propellers: Array[Node3D] = []
var ramp: Node3D


func setup(from: Vector3, to: Vector3) -> void:
	start = from
	finish = to
	length = start.distance_to(finish)
	_build()
	position = start
	look_at(finish, Vector3.UP)


func _build() -> void:
	var olive := StandardMaterial3D.new()
	olive.albedo_color = Color(0.235, 0.255, 0.205)
	olive.metallic = 0.45
	olive.roughness = 0.55
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.13, 0.13)
	dark.metallic = 0.6
	dark.roughness = 0.45
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.36, 0.47, 0.52)
	glass.metallic = 0.9
	glass.roughness = 0.12

	_box(Vector3(0, 0, 0), Vector3(2.6, 2.6, 15.0), olive)       # fuselage
	_box(Vector3(0, 0.85, 4.2), Vector3(1.5, 0.75, 5.0), olive)  # spine
	_box(Vector3(0, 0.0, -7.9), Vector3(2.2, 2.0, 2.0), olive)   # nose taper
	_box(Vector3(0, 0.05, 8.4), Vector3(1.6, 1.4, 0.7), dark)     # tail base
	_box(Vector3(0, 1.35, 8.6), Vector3(0.25, 2.4, 1.5), olive)   # fin
	_box(Vector3(0, 0.15, 8.6), Vector3(6.4, 0.22, 1.5), olive)   # tailplane

	# Wings: swept, thick, blocky.
	var wing_l := _box(Vector3(-7.2, 0.15, -0.6), Vector3(12.2, 0.5, 3.2), olive)
	wing_l.rotation.z = deg_to_rad(-2.0)
	wing_l.rotation.y = deg_to_rad(4.0)
	var wing_r := _box(Vector3(7.2, 0.15, -0.6), Vector3(12.2, 0.5, 3.2), olive)
	wing_r.rotation.z = deg_to_rad(2.0)
	wing_r.rotation.y = deg_to_rad(-4.0)

	# Engines with spinning props.
	for sx in [-4.6, 4.6]:
		_box(Vector3(sx, -0.05, -2.4), Vector3(1.4, 1.3, 3.4), dark)
		_box(Vector3(sx, -0.05, -4.2), Vector3(1.1, 1.05, 0.5), glass)
		var prop := Node3D.new()
		prop.position = Vector3(sx, -0.05, -4.45)
		add_child(prop)
		for a in range(4):
			var blade := _box(Vector3.ZERO, Vector3(0.16, 2.6, 0.08), dark)
			blade.reparent(prop, false)
			blade.rotation.z = deg_to_rad(45.0 * a)
		propellers.append(prop)

	# Cockpit glass.
	_box(Vector3(0, 0.55, -6.6), Vector3(2.2, 1.1, 1.4), glass)

	# Rear ramp, open, with a lip the player can see under.
	ramp = _box(Vector3(0, -0.15, 7.2), Vector3(2.4, 0.25, 2.6), dark)
	ramp.rotation.x = deg_to_rad(9.0)

	# Position lights.
	for sx in [-11.8, 11.8]:
		var light := OmniLight3D.new()
		light.position = Vector3(sx, 0.3, 0.0)
		light.light_color = Color(0.9, 0.15, 0.1) if sx < 0.0 else Color(0.15, 0.85, 0.3)
		light.light_energy = 1.2
		light.omni_range = 6.0
		add_child(light)


func _box(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	return mi


func _physics_process(delta: float) -> void:
	if not active:
		return
	t = minf(1.0, t + (speed * delta) / maxf(1.0, length))
	position = start.lerp(finish, t) + Vector3(0, sin(t * 9.0) * 1.1, 0)
	rotation.z = sin(t * 3.0) * 0.06
	rotation.x = sin(t * 4.0) * 0.012
	for p in propellers:
		p.rotation.z += delta * 55.0
	if t >= 1.0:
		active = false


func progress() -> float:
	return t


func seat_position() -> Vector3:
	return global_position + global_basis * Vector3(0, -0.4, 6.2)


func jump_velocity() -> Vector3:
	var forward := global_basis * Vector3(0, 0, -1)
	return forward * speed * 0.55


func chase_position() -> Vector3:
	return global_position + global_basis * Vector3(0, 6.5, 20.0)
