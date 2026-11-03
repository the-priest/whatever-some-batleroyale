class_name Grenade
extends RigidBody3D

## Frag grenade: bounces, then explodes after the fuse. Damage falls off with
## distance and is blocked by walls and terrain.

const FUSE := 3.2
const RADIUS := 8.0
const DAMAGE := 125.0

var game: Node = null
var thrower: Node = null
var _t := 0.0
var _done := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	mass = 0.4
	continuous_cd = true
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = 0.35
	physics_material_override.friction = 0.8
	angular_damp = 1.5
	linear_damp = 0.15
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.08
	cs.shape = sp
	add_child(cs)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.08
	sm.height = 0.17
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.28, 0.34, 0.20)
	m.roughness = 0.6
	mi.material_override = m
	add_child(mi)
	var pin := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.03, 0.06, 0.05)
	pin.mesh = bm
	pin.position.y = 0.09
	pin.material_override = m
	add_child(pin)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= FUSE and not _done:
		_explode()


func _explode() -> void:
	_done = true
	var pos := global_position
	var space := get_world_3d().direct_space_state
	var victims: Array = []
	if game != null:
		if game.player != null:
			victims.append(game.player)
		for b in game.bots:
			if is_instance_valid(b):
				victims.append(b)
	for v in victims:
		if not bool(v.get("alive")):
			continue
		var target: Vector3 = (v as Node3D).global_position + Vector3(0, 1.0, 0)
		var d := pos.distance_to(target)
		if d > RADIUS:
			continue
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.2, target, 1)
		if not space.intersect_ray(q).is_empty():
			continue
		var f := 1.0 - d / RADIUS
		var dmg := DAMAGE * f * f + 10.0 * f
		v.call("take_damage", dmg, pos, false, thrower if is_instance_valid(thrower) else null)
		if thrower != null and thrower == game.player and v != thrower:
			game.on_player_hit(target, dmg, false)
	if game != null:
		game.spawn_explosion(pos)
	queue_free()
