class_name BossOrb
extends Node3D
## A ball of fire a Colossus throws. It flies dead straight (so it can be
## read and sidestepped), bursts on the first wall, ground or person it meets,
## and burns whoever is close. On the host it does the damage; on a joined
## player's machine it is only the picture.

const RADIUS := 0.55
const HIT_RANGE := 1.7
const SPLASH := 3.2

var game: Node
var thrower: Node = null
var dir := Vector3.FORWARD
var speed := 26.0
var life := 3.0
var damage := 28.0
var harmful := true
## Bigger, slower, wider blast (a boulder of burning rock).
var size := 1.0
var splash := SPLASH
## Leaves the ground burning where it bursts.
var fire_field := false
var _light: OmniLight3D


static func launch(p_game: Node, from: Vector3, p_dir: Vector3, p_speed: float, p_damage: float, p_thrower: Node, p_harmful: bool, p_size := 1.0, p_fire := false) -> BossOrb:
	var o := BossOrb.new()
	o.size = p_size
	o.splash = SPLASH * p_size
	o.fire_field = p_fire
	o.game = p_game
	o.dir = p_dir.normalized()
	o.speed = p_speed
	o.damage = p_damage
	o.thrower = p_thrower
	o.harmful = p_harmful
	p_game.add_child(o)
	o.global_position = from
	return o


func _ready() -> void:
	scale = Vector3.ONE * size
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = RADIUS
	sm.height = RADIUS * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	core.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.62, 0.22)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.45, 0.12)
	m.emission_energy_multiplier = 5.0
	core.material_override = m
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)
	# A dimmer, larger shell so it reads as a ball of flame, not a bead.
	var shell := MeshInstance3D.new()
	var sm2 := SphereMesh.new()
	sm2.radius = RADIUS * 1.7
	sm2.height = RADIUS * 3.4
	sm2.radial_segments = 12
	sm2.rings = 6
	shell.mesh = sm2
	var m2 := StandardMaterial3D.new()
	m2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m2.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m2.albedo_color = Color(1.0, 0.35, 0.1, 0.35)
	shell.material_override = m2
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shell)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.light_energy = 2.5
	_light.omni_range = 7.0
	add_child(_light)


func _physics_process(delta: float) -> void:
	life -= delta
	var from := global_position
	var to := from + dir * speed * delta
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		_burst(hit.position)
		return
	global_position = to
	if harmful and game != null:
		for t in _targets():
			if (t as Node3D).global_position.distance_to(global_position - Vector3.UP * 1.0) < HIT_RANGE * size:
				_burst(global_position)
				return
	if life <= 0.0:
		_burst(global_position)


## Who a fireball can hurt: you, the other players, and soldiers.
func _targets() -> Array:
	var out: Array = []
	if game.player != null and game.player.alive and game.player.mode == Player.Mode.GROUND:
		out.append(game.player)
	for b in game.bots:
		if is_instance_valid(b) and b != thrower and b.alive and b.state == Bot.State.GROUND and not (b is Revenant):
			out.append(b)
	for id in game.humans:
		var h = game.humans[id]
		if h != null and is_instance_valid(h) and (h as Bot).alive:
			out.append(h)
	return out


func _burst(at: Vector3) -> void:
	if harmful and game != null:
		for t in _targets():
			var d := (t as Node3D).global_position.distance_to(at - Vector3.UP * 1.0)
			if d < splash:
				var k := 1.0 - clampf(d / splash, 0.0, 1.0) * 0.6
				t.take_damage(damage * k, at, false, thrower if thrower != null and is_instance_valid(thrower) else null)
	if game != null:
		game.spawn_explosion(at)
		if fire_field:
			FirePatch.spawn(game, game.ground_at(at + Vector3.UP * 0.5), harmful, thrower)
	queue_free()
