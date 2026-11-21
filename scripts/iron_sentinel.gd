class_name IronSentinel
extends Revenant
## The Iron Sentinel: a walking engine of war in black iron plate. Bullets
## ring off it.
##
##   - its plate: closed, it takes almost nothing
##   - the vent: every so often it stops, and steam pours from the glowing
##     vents on its back. For those seconds it takes full harm. Strike then.
##   - mortars: rings on the ground round you, then the shells come down
##   - the stomp: come too close and a red ring at its feet, then a blow that
##     throws you
##   - raging (half health): the vents stay open for less time, the mortars
##     come more often

const SCALE := 1.5
const CLOSED_TAKEN := 0.025
const OPEN_TAKEN := 0.22
const VENT_EVERY := 12.0
const VENT_TIME := 4.0
const STOMP_R := 6.0
const STOMP_DMG := 38.0
const STOMP_WINDUP := 0.9

var venting := false
var _vent_t := 8.0
var _stomp_t := 3.0
var _stomp_in := -1.0
var _vents: Array[MeshInstance3D] = []
var _vent_mat: StandardMaterial3D


func setup_sentinel(p_arena: Vector3, p_game: Node) -> void:
	setup_revenant("THE IRON SENTINEL", "", p_arena, p_game)
	title = "ENGINE OF THE OLD WAR"
	damage_taken = CLOSED_TAKEN
	leash = 55.0
	volleys = true
	regen_rate = 2.5
	shoot_skill = 0.55
	set_meta("sentinel", true)
	aura_color = Color(1.0, 0.55, 0.18)
	aura_size = 1.5
	cloak_color = Color(0, 0, 0, 0)
	crown = "spikes"
	# The furnace inside it shows through the seams of its plate.
	embers = true


func display_name() -> String:
	return "%s, %s" % [bot_name, title]


func _ready() -> void:
	super._ready()
	if body != null and body.model != null:
		body.model.scale = Vector3.ONE * SCALE
		for mi in body.model.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var sm := m.get_surface_override_material(0)
			if sm is ShaderMaterial:
				var camo := (sm as ShaderMaterial).duplicate() as ShaderMaterial
				camo.set_shader_parameter("c_base", Color(0.1, 0.1, 0.11))
				camo.set_shader_parameter("c_a", Color(0.2, 0.2, 0.22))
				camo.set_shader_parameter("c_b", Color(0.32, 0.3, 0.28))
				camo.set_shader_parameter("c_c", Color(0.05, 0.05, 0.05))
				m.set_surface_override_material(0, camo)
	head_offset = 1.5 * SCALE
	if _cap != null:
		_cap.radius = 0.36 * SCALE
		_cap.height = 1.78 * SCALE
		_col.position.y = 0.89 * SCALE
	if _glow != null:
		_glow.light_color = Color(1.0, 0.5, 0.2)
		glow_base = 0.3
	# Vents on its back: dull until it opens them.
	_vent_mat = StandardMaterial3D.new()
	_vent_mat.albedo_color = Color(0.25, 0.1, 0.05)
	_vent_mat.emission_enabled = true
	_vent_mat.emission = Color(1.0, 0.45, 0.12)
	_vent_mat.emission_energy_multiplier = 0.0
	for k in 3:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.22, 0.12, 0.08)
		var v := MeshInstance3D.new()
		v.mesh = bm
		v.material_override = _vent_mat
		v.position = Vector3(-0.25 + 0.25 * k, 1.35 * SCALE, 0.24 * SCALE)
		add_child(v)
		_vents.append(v)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if puppet or not alive:
		return
	var tgt: Node3D = enemy as Node3D if enemy != null and is_instance_valid(enemy) and bool(enemy.get("alive")) else null
	if venting:
		velocity.x = 0.0
		velocity.z = 0.0
		_vent_t -= delta
		_vent_mat.emission_energy_multiplier = 3.0 + sin(Time.get_ticks_msec() * 0.02) * 1.0
		if _vent_t <= 0.0:
			_close_vents()
		return
	if _stomp_in >= 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		_stomp_in -= delta
		if _stomp_in < 0.0:
			_stomp()
		return
	if tgt == null:
		return
	_vent_t -= delta
	_stomp_t -= delta
	if _vent_t <= 0.0:
		_open_vents()
	elif _stomp_t <= 0.0 and tgt.global_position.distance_to(global_position) < STOMP_R + 1.0:
		_stomp_t = 5.0
		_stomp_in = STOMP_WINDUP
		game.boss_fx({"k": "slam", "p": global_position, "r": STOMP_R, "w": STOMP_WINDUP})
		game.play_sfx_at("land_thud", global_position, 6.0)


func _open_vents() -> void:
	venting = true
	_vent_t = VENT_TIME * (0.75 if raged else 1.0)
	damage_taken = OPEN_TAKEN
	game.boss_fx({"k": "steam", "p": global_position + Vector3.UP * (1.4 * SCALE), "t": _vent_t})
	game.play_sfx_at("explosion", global_position, -4.0)


func _close_vents() -> void:
	venting = false
	damage_taken = CLOSED_TAKEN
	_vent_t = VENT_EVERY * (0.8 if raged else 1.0)
	_vent_mat.emission_energy_multiplier = 0.0


func _stomp() -> void:
	var at := global_position
	game.spawn_explosion(at + Vector3.UP * 0.2)
	game.shake(24.0)
	for v in _victims():
		var d := (v as Node3D).global_position.distance_to(at)
		if d < STOMP_R:
			v.take_damage(STOMP_DMG * (1.0 - d / STOMP_R * 0.4), at, false, self)
			if v == game.player and game.player.iframes <= 0.0:
				var away := (v as Node3D).global_position - at
				away.y = 0.0
				game.player.velocity += away.normalized() * 9.0 + Vector3.UP * 6.0


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
