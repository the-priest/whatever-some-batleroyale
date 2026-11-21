class_name Bellkeeper
extends Revenant
## The Bellkeeper: a pale knight under a great bronze bell that hangs over it
## from nothing. It does not need to see you to hurt you.
##
##   - the toll: the bell swings, and rings of sound roll out along the ground
##     from it, one after another. Jump as a ring reaches you; anyone with
##     their feet on the ground when it passes is struck and thrown
##   - the peal: a fan of five slow balls of pale fire, thrown wide
##   - at half health it rages: three rings to a toll, the peal more often

const TOLL_EVERY := 9.0
const TOLL_WINDUP := 0.9
const TOLL_SPEED := 12.0
const TOLL_MAX := 44.0
const TOLL_DMG := 30.0
const TOLL_BAND := 0.9
const PEAL_EVERY := 7.5
const PEAL_DMG := 20.0

var _toll_t := 4.0
var _toll_in := -1.0
var _tolls_left := 0
var _toll_gap := 0.0
var _peal_t := 6.0
## Rings rolling out: [origin, radius, {victim: true}]
var _rings_out: Array = []
var _bell: Node3D
## Rings that have struck the local player (for the checks).
var toll_hits := 0


func setup_bell(p_arena: Vector3, p_game: Node) -> void:
	setup_revenant("MOURNE", "THE BELLKEEPER", p_arena, p_game)
	damage_taken = 0.14
	leash = 60.0
	volleys = false
	regen_rate = 4.0
	shoot_skill = 0.62
	sight = 130.0
	set_meta("bell", true)
	aura_color = Color(1.0, 0.82, 0.45)
	aura_size = 1.2
	cloak_color = Color(0.24, 0.21, 0.17)
	cloak_long = 1.3
	crown = "hood"


func display_name() -> String:
	return "%s, %s" % [bot_name, title]


func _ready() -> void:
	super._ready()
	if body != null and body.model != null:
		body.model.scale = Vector3.ONE * 1.18
		for mi in body.model.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var sm := m.get_surface_override_material(0)
			if sm is ShaderMaterial:
				var camo := (sm as ShaderMaterial).duplicate() as ShaderMaterial
				# Robes the colour of old ash and dried blood.
				camo.set_shader_parameter("c_base", Color(0.11, 0.1, 0.09))
				camo.set_shader_parameter("c_a", Color(0.17, 0.15, 0.12))
				camo.set_shader_parameter("c_b", Color(0.2, 0.08, 0.06))
				camo.set_shader_parameter("c_c", Color(0.07, 0.06, 0.05))
				m.set_surface_override_material(0, camo)
	if _glow != null:
		_glow.light_color = Color(1.0, 0.85, 0.55)
		glow_base = 0.25
	_build_bell()
	# The bell can be struck: above its head, so every hit there is a
	# headshot, and it rings.
	var bs := SphereShape3D.new()
	bs.radius = 0.62
	add_hit_shape(bs, Vector3(0, 3.25, 0))


func _build_bell() -> void:
	_bell = Node3D.new()
	_bell.position = Vector3(0, 3.7, 0)
	add_child(_bell)
	var bronze := StandardMaterial3D.new()
	bronze.albedo_color = Color(0.55, 0.38, 0.18)
	bronze.metallic = 0.85
	bronze.roughness = 0.35
	var cm := CylinderMesh.new()
	cm.top_radius = 0.32
	cm.bottom_radius = 0.62
	cm.height = 0.95
	cm.radial_segments = 16
	var shell := MeshInstance3D.new()
	shell.mesh = cm
	shell.material_override = bronze
	shell.position = Vector3(0, -0.45, 0)
	_bell.add_child(shell)
	var lip := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.58
	tm.outer_radius = 0.7
	tm.rings = 20
	tm.ring_segments = 6
	lip.mesh = tm
	lip.material_override = bronze
	lip.position = Vector3(0, -0.92, 0)
	_bell.add_child(lip)
	var crown := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.32
	sm.height = 0.4
	sm.is_hemisphere = true
	crown.mesh = sm
	crown.material_override = bronze
	_bell.add_child(crown)
	# A pale light inside it.
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.85, 0.55)
	l.light_energy = 1.2
	l.omni_range = 4.0
	l.shadow_enabled = false
	l.position = Vector3(0, -0.7, 0)
	_bell.add_child(l)


func _process(delta: float) -> void:
	super._process(delta)
	if _bell == null:
		return
	# It hangs and turns slowly; it swings when it tolls.
	var t := Time.get_ticks_msec() * 0.001
	var swing := 0.6 if _toll_in >= 0.0 or _tolls_left > 0 else 0.06
	_bell.rotation.z = sin(t * (9.0 if swing > 0.1 else 1.3)) * swing
	_bell.position.y = 3.7 + sin(t * 1.1) * 0.12


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if puppet or not alive:
		return
	_roll_rings(delta)
	if _toll_in >= 0.0:
		_toll_in -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		if _toll_in < 0.0:
			_toll()
		return
	if _tolls_left > 0:
		_toll_gap -= delta
		if _toll_gap <= 0.0:
			_toll()
		return
	var tgt: Node3D = enemy as Node3D if enemy != null and is_instance_valid(enemy) and bool(enemy.get("alive")) else null
	if tgt == null:
		return
	_toll_t -= delta
	_peal_t -= delta
	var d := tgt.global_position.distance_to(global_position)
	if _toll_t <= 0.0 and d < TOLL_MAX - 4.0:
		_toll_t = TOLL_EVERY * (0.7 if raged else 1.0)
		_toll_in = TOLL_WINDUP
		_tolls_left = 3 if raged else 2
		game.play_sfx_at("event_horn", global_position + Vector3.UP * 3.0, 4.0)
	elif _peal_t <= 0.0 and d > 8.0:
		_peal_t = PEAL_EVERY * (0.6 if raged else 1.0)
		_peal(tgt)


func _toll() -> void:
	_tolls_left -= 1
	_toll_gap = 0.85
	var at := global_position
	_rings_out.append([at, 0.6, {}])
	game.boss_fx({"k": "toll", "p": at, "s": TOLL_SPEED, "m": TOLL_MAX})
	game.play_sfx_at("thunder", at + Vector3.UP * 3.0, -2.0)
	game.shake(8.0)


func _roll_rings(delta: float) -> void:
	if _rings_out.is_empty():
		return
	var victims := _victims()
	for ring in _rings_out:
		ring[1] = float(ring[1]) + TOLL_SPEED * delta
		var o: Vector3 = ring[0]
		var r: float = ring[1]
		var hit: Dictionary = ring[2]
		for v in victims:
			if hit.has(v):
				continue
			var vp: Vector3 = (v as Node3D).global_position
			var d := Vector2(vp.x - o.x, vp.z - o.z).length()
			if absf(d - r) > TOLL_BAND:
				continue
			if not _grounded(v):
				hit[v] = true
				continue
			hit[v] = true
			v.take_damage(TOLL_DMG, o, false, self)
			if v == game.player and game.player.iframes <= 0.0:
				toll_hits += 1
				var away := vp - o
				away.y = 0.0
				game.player.velocity += away.normalized() * 7.0 + Vector3.UP * 6.0
	_rings_out = _rings_out.filter(func(rg): return float(rg[1]) < TOLL_MAX)


## Feet on the ground (so the ring catches them).
func _grounded(v: Node) -> bool:
	if v == game.player:
		return game.player.is_on_floor()
	var p: Vector3 = (v as Node3D).global_position
	var g: Vector3 = game.ground_at(p + Vector3.UP * 0.5)
	return p.y - g.y < 0.45


func _victims() -> Array:
	var out: Array = []
	if game.player != null and game.player.alive and game.player.mode == Player.Mode.GROUND:
		out.append(game.player)
	for b in game.bots:
		if is_instance_valid(b) and b != self and b.alive and b.state == State.GROUND and not (b is Revenant):
			out.append(b)
	for id in game.humans:
		var h = game.humans[id]
		if h != null and is_instance_valid(h) and (h as Bot).alive:
			out.append(h)
	return out


func _peal(tgt: Node3D) -> void:
	var from := global_position + Vector3.UP * 2.4
	var aim := tgt.global_position + Vector3.UP * 1.0
	var base := (aim - from).normalized()
	for i in 5:
		var ang := deg_to_rad(-26.0 + 13.0 * float(i))
		var dir := base.rotated(Vector3.UP, ang)
		BossOrb.launch(game, from, dir, 17.0, PEAL_DMG, self, true, 0.75, false)
		game.boss_fx({"k": "orb", "p": from, "d": dir, "s": 17.0, "z": 0.75, "f": false})
	game.play_sfx_at("jump_whoosh", from, 3.0)


func _die(source: Node) -> void:
	_rings_out.clear()
	super._die(source)
