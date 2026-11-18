class_name FirePatch
extends Node3D
## Burning ground left by the Mother of Cinders' fire: a few seconds of
## flame that hurts whoever stands in it. Only the host's copy does damage.

const RADIUS := 2.6
const LIFE := 6.0
const DPS := 14.0

var game: Node
var harmful := true
var source: Node = null
var _t := LIFE
var _tick := 0.0
var _light: OmniLight3D


static func spawn(p_game: Node, at: Vector3, p_harmful: bool, p_source: Node) -> FirePatch:
	var f := FirePatch.new()
	f.game = p_game
	f.harmful = p_harmful
	f.source = p_source
	p_game.add_child(f)
	f.global_position = at
	return f


func _ready() -> void:
	var flame := StandardMaterial3D.new()
	flame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flame.cull_mode = BaseMaterial3D.CULL_DISABLED
	flame.albedo_color = Color(1.0, 0.45, 0.12, 0.7)
	for i in 7:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(randf_range(0.8, 1.4), randf_range(0.9, 1.7))
		q.mesh = qm
		q.material_override = flame
		var a := randf() * TAU
		var r := randf() * RADIUS * 0.8
		q.position = Vector3(cos(a) * r, qm.size.y * 0.5, sin(a) * r)
		q.rotation.y = randf() * PI
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(q)
	var scorch := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = RADIUS
	cm.bottom_radius = RADIUS
	cm.height = 0.02
	scorch.mesh = cm
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0.9, 0.3, 0.05, 0.22)
	scorch.material_override = sm
	scorch.position.y = 0.05
	scorch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(scorch)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.5, 0.18)
	_light.light_energy = 1.6
	_light.omni_range = 6.0
	_light.position.y = 1.0
	add_child(_light)


func _physics_process(delta: float) -> void:
	_t -= delta
	_light.light_energy = 1.4 + sin(_t * 17.0) * 0.3
	if _t < 1.0:
		scale = Vector3.ONE * maxf(_t, 0.05)
	if _t <= 0.0:
		queue_free()
		return
	if not harmful or game == null:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.5
	var victims: Array = []
	if game.player != null and game.player.alive:
		victims.append(game.player)
	for b in game.bots:
		if is_instance_valid(b) and b.alive and b.state == Bot.State.GROUND and not (b is Revenant):
			victims.append(b)
	for id in game.humans:
		var h = game.humans[id]
		if h != null and is_instance_valid(h) and (h as Bot).alive:
			victims.append(h)
	for v in victims:
		var d := Vector2((v as Node3D).global_position.x - global_position.x, (v as Node3D).global_position.z - global_position.z).length()
		if d < RADIUS and absf((v as Node3D).global_position.y - global_position.y) < 2.5:
			v.take_damage(DPS * 0.5, global_position + Vector3.UP, false, source if source != null and is_instance_valid(source) else null)
