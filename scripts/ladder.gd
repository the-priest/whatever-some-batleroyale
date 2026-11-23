class_name Ladder
extends Node3D
## A rope-and-timber ladder up a cliff. Walk into it holding forward (or
## jump) and you climb; at the top it sets you on the ground past the lip.
## Lanterns at the foot and the top, so you can find them from afar.

static var all: Array = []

var foot := Vector3.ZERO
var top := Vector3.ZERO
var lip := Vector3.ZERO
var facing := Vector3.FORWARD


func setup(p_foot: Vector3, top_y: float, p_dir: Vector3, p_lip: Vector3) -> void:
	foot = p_foot
	lip = p_lip
	facing = p_dir.normalized()
	# Straight up from the foot, then over the lip.
	top = Vector3(foot.x, top_y, foot.z)
	_build()
	all.append(self)


func _exit_tree() -> void:
	all.erase(self)


func _build() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.29, 0.17)
	wood.roughness = 0.9
	var rope := StandardMaterial3D.new()
	rope.albedo_color = Color(0.6, 0.52, 0.36)
	var h := top.y - foot.y
	var side := facing.cross(Vector3.UP).normalized()
	var root := Node3D.new()
	add_child(root)
	root.global_position = foot
	for s: float in [-0.32, 0.32]:
		var r := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.08, h + 0.6, 0.08)
		r.mesh = bm
		r.material_override = wood
		r.position = side * s + Vector3.UP * (h * 0.5 + 0.2)
		root.add_child(r)
	var rung := BoxMesh.new()
	rung.size = Vector3(0.7, 0.05, 0.06)
	var steps := int(h / 0.4)
	for k in steps:
		var m := MeshInstance3D.new()
		m.mesh = rung
		m.material_override = rope if k % 5 == 4 else wood
		m.position = Vector3.UP * (0.3 + float(k) * 0.4)
		m.basis = Basis(Vector3.UP, atan2(side.x, side.z) - PI * 0.5)
		root.add_child(m)
	for at: Vector3 in [Vector3.UP * 2.2, Vector3.UP * (h + 0.4)]:
		var lamp := MeshInstance3D.new()
		var lm := SphereMesh.new()
		lm.radius = 0.12
		lm.height = 0.24
		lamp.mesh = lm
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.albedo_color = Color(1.0, 0.75, 0.4)
		gm.emission_enabled = true
		gm.emission = Color(1.0, 0.6, 0.25)
		gm.emission_energy_multiplier = 4.0
		lamp.material_override = gm
		lamp.position = at + side * 0.5 - facing * 0.1
		root.add_child(lamp)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.65, 0.3)
		l.light_energy = 1.2
		l.omni_range = 6.0
		l.distance_fade_enabled = true
		l.distance_fade_begin = 90.0
		l.position = lamp.position
		root.add_child(l)


## How far a point is from the climb (the vertical line of the ladder).
func distance_to(p: Vector3) -> float:
	var flat := Vector2(p.x - foot.x, p.z - foot.z).length()
	if p.y < foot.y - 0.8 or p.y > top.y + 1.0:
		return INF
	return flat


static func near(p: Vector3, r := 1.1) -> Ladder:
	for l in all:
		var lad := l as Ladder
		if is_instance_valid(lad) and lad.distance_to(p) < r:
			return lad
	return null
