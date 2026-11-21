class_name KitShot
extends Node3D
## An arrow or a fireball loosed by a player. It flies (arrows drop), and on
## the first thing it meets it strikes: an arrow sticks and hurts what it hit,
## headshots counting; a fireball bursts, burning everyone near and leaving
## the ground alight. It hits the real hitboxes, the same ones bullets do.

const GRAVITY := 9.8

var game: Node
var shooter: Node3D
var kind := "arrow"
var vel := Vector3.ZERO
var damage := 40.0
var head_mult := 2.0
var splash := 0.0
var life := 4.0
## Someone else's shot, mirrored over LAN: only the picture.
var visual := false
var _stuck := -1.0
var _light: OmniLight3D = null


static func launch(p_game: Node, p_shooter: Node3D, p_kind: String, from: Vector3, p_vel: Vector3, p_dmg: float, p_visual := false) -> KitShot:
	var s := KitShot.new()
	s.game = p_game
	s.shooter = p_shooter
	s.kind = p_kind
	s.vel = p_vel
	s.damage = p_dmg
	s.visual = p_visual
	if p_kind == "fire":
		s.splash = 3.0
		s.life = 2.5
	p_game.add_child(s)
	s.global_position = from
	s._face()
	return s


func _ready() -> void:
	if kind == "arrow":
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color(0.45, 0.32, 0.2)
		var shaft := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.008
		cm.bottom_radius = 0.008
		cm.height = 0.75
		cm.radial_segments = 5
		cm.rings = 1
		shaft.mesh = cm
		shaft.material_override = wood
		shaft.rotation.x = PI * 0.5
		add_child(shaft)
		var tip := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 0.0
		tm.bottom_radius = 0.018
		tm.height = 0.07
		tm.radial_segments = 4
		tm.rings = 1
		tip.mesh = tm
		var steel := StandardMaterial3D.new()
		steel.albedo_color = Color(0.6, 0.6, 0.62)
		steel.metallic = 0.8
		tip.material_override = steel
		tip.rotation.x = -PI * 0.5
		tip.position = Vector3(0, 0, -0.4)
		add_child(tip)
		var fl := StandardMaterial3D.new()
		fl.albedo_color = Color(0.85, 0.15, 0.1)
		fl.cull_mode = BaseMaterial3D.CULL_DISABLED
		for k in 2:
			var f := MeshInstance3D.new()
			var fm := BoxMesh.new()
			fm.size = Vector3(0.05, 0.002, 0.1)
			f.mesh = fm
			f.material_override = fl
			f.position = Vector3(0, 0, 0.32)
			f.rotation.z = PI * 0.5 * k
			add_child(f)
	else:
		var core := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.22
		sm.height = 0.44
		sm.radial_segments = 10
		sm.rings = 5
		core.mesh = sm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.7, 0.3)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.45, 0.1)
		m.emission_energy_multiplier = 6.0
		core.material_override = m
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(core)
		var halo := MeshInstance3D.new()
		var hm := SphereMesh.new()
		hm.radius = 0.38
		hm.height = 0.76
		hm.radial_segments = 10
		hm.rings = 5
		halo.mesh = hm
		var h2 := StandardMaterial3D.new()
		h2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		h2.albedo_color = Color(1.0, 0.35, 0.05, 0.35)
		h2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		halo.material_override = h2
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(halo)
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.5, 0.2)
		_light.light_energy = 1.6
		_light.omni_range = 5.0
		add_child(_light)


func _face() -> void:
	if vel.length() > 0.1:
		var f := vel.normalized()
		var up := Vector3.UP if absf(f.y) < 0.98 else Vector3.RIGHT
		global_basis = Basis.looking_at(f, up)


func _physics_process(delta: float) -> void:
	if _stuck >= 0.0:
		_stuck -= delta
		if _stuck <= 0.0:
			queue_free()
		return
	life -= delta
	if life <= 0.0:
		if kind == "fire":
			_burst(global_position, null)
		queue_free()
		return
	if kind == "arrow":
		vel.y -= GRAVITY * delta
	var a := global_position
	var b := a + vel * delta
	var q := PhysicsRayQueryParameters3D.create(a, b, Ballistics.MASK)
	if shooter != null and is_instance_valid(shooter) and shooter is CollisionObject3D:
		q.exclude = [(shooter as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		global_position = b
		_face()
		return
	var pos: Vector3 = hit.position
	var col: Object = hit.collider
	global_position = pos
	if kind == "fire":
		_burst(pos, col)
		queue_free()
		return
	_strike(col, pos)
	# The arrow stays where it struck for a while.
	_stuck = 6.0
	if col is Node3D and (col as Node3D).has_method("take_damage"):
		var n := col as Node3D
		var xf := global_transform
		get_parent().remove_child(self)
		n.add_child(self)
		global_transform = xf
		_stuck = 3.0


func _hurtable(col: Object) -> bool:
	return col != null and col != shooter and col.has_method("take_damage") and col.get("alive") == true and not (col.get("friendly") == true and shooter is Player)


func _strike(col: Object, pos: Vector3) -> void:
	if _hurtable(col):
		if visual:
			game.spawn_blood(pos)
			return
		var head := false
		if col.has_method("head_y"):
			head = pos.y >= float(col.call("head_y"))
		var dmg := damage * (head_mult if head else 1.0)
		var killed = col.call("take_damage", dmg, pos, head, shooter if is_instance_valid(shooter) else null)
		game.spawn_blood(pos)
		game.play_sfx_at("hit_body", pos, 2.0)
		if shooter is Player:
			(shooter as Player).kit_hit(pos, dmg, head, killed is bool and killed)
	else:
		game.play_sfx_at("impact_wood", pos, -4.0)


## Fire: everyone within the splash is burnt, more so near the middle; a
## direct hit hurts the most. The ground stays burning a few seconds.
func _burst(at: Vector3, direct: Object) -> void:
	game.spawn_explosion(at)
	if visual:
		return
	var hit_any := false
	var killed_any := false
	var done := {}
	if _hurtable(direct):
		var k1 = direct.call("take_damage", damage, at, false, shooter if is_instance_valid(shooter) else null)
		done[direct] = true
		hit_any = true
		killed_any = k1 is bool and k1
	for t in _targets():
		if done.has(t):
			continue
		var d := (t as Node3D).global_position.distance_to(at - Vector3.UP * 0.8)
		if d < splash + _reach(t):
			var k := 1.0 - clampf((d - _reach(t)) / splash, 0.0, 1.0) * 0.6
			var kl = t.take_damage(damage * 0.5 * k, at, false, shooter if is_instance_valid(shooter) else null)
			hit_any = true
			killed_any = killed_any or (kl is bool and kl)
	FirePatch.spawn(game, game.ground_at(at + Vector3.UP * 0.5), true, shooter)
	if hit_any and shooter is Player:
		(shooter as Player).kit_hit(at, damage, false, killed_any)


## How far from its feet a body reaches (a colossus is a big target).
static func _reach(t: Node) -> float:
	if t is Colossus or t is Wyrm or t is Carrion:
		return 2.0
	if t is Revenant:
		return 0.8
	return 0.4


func _targets() -> Array:
	return KitShot._reach_targets(game, shooter)


## Everyone a player's fire can hurt: soldiers, bosses and other players.
static func _reach_targets(g: Node, who: Node) -> Array:
	var out: Array = []
	for b in g.bots:
		if is_instance_valid(b) and b != who and b.alive and b.state == Bot.State.GROUND and not (b.friendly and who is Player):
			out.append(b)
	for id in g.humans:
		var h = g.humans[id]
		if h != null and is_instance_valid(h) and h != who and (h as Bot).alive and not ((h as Bot).friendly and who is Player):
			out.append(h)
	return out
