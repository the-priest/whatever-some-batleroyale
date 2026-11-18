class_name Revenant
extends Bot
## A Revenant: a named champion who never left the island's old places. It
## holds an arena at a landmark and will not be drawn far from it.
##
##   - takes a fifth of the damage a soldier would, behind level 3 plate
##   - telegraphs its grenade volleys: red rings on the ground where they
##     will land, a moment before they come
##   - at half health it rages: faster to react, deadlier aim, and every armed
##     soldier nearby answers its call
##   - leashed: lure it too far and it turns back home, healing as it goes
##   - its fall tolls a bell across the island; it drops a fortune
##
## Revenants are not players: they do not count toward who is left alive.

const NAMES := [
	["MAELIS", "THE ASH WARDEN"], ["ORVEN", "THE HOLLOW KNIGHT"], ["SERA VANE", "THE GRAVE-SINGER"],
	["THRAIN", "THE IRON OATH"], ["KESSA", "THE PALE HUNTRESS"], ["DORIAN", "THE LAST CAPTAIN"],
	["VELKA", "WHO WALKS IN SMOKE"], ["ABBOT GREL", "THE UNBURIED"],
]
const DAMAGE_TAKEN := 0.2
const LEASH := 55.0
const REGEN := 6.0
const VOLLEY_EVERY := 13.0
const VOLLEY_WINDUP := 1.4

var title := ""
var arena := Vector3.ZERO
## Tuning a bigger boss can change.
var damage_taken := DAMAGE_TAKEN
var leash := LEASH
var volleys := true
var regen_rate := REGEN
var glow_base := 0.9
var calm_before_regen := 5.0
var raged := false
var _volley_t := 6.0
var _calm := 0.0
var _rings: Array[Node3D] = []
var _glow: OmniLight3D


func setup_revenant(p_name: String, p_title: String, p_arena: Vector3, p_game: Node) -> void:
	setup(p_name, Vector2(p_arena.x, p_arena.z), p_game, randi())
	title = p_title
	arena = p_arena
	shoot_skill = 0.78
	reaction = 0.3
	sight = 140.0
	aggression = 0.85
	vest_level = 3
	armor = 100.0
	helmet_level = 3
	meds = 2
	grenades = 99
	state = State.GROUND
	landed = true
	set_meta("revenant", title)


func display_name() -> String:
	return "%s, %s" % [bot_name, title]


func _ready() -> void:
	super._ready()
	visible = true
	roam_point = Vector2(arena.x, arena.z)
	calm_t = 0.0
	# Black and crimson, a little taller than a soldier, with a dull red glow.
	if body != null and body.model != null:
		body.model.scale = Vector3.ONE * 1.12
		for mi in body.model.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var sm := m.get_surface_override_material(0)
			if sm is ShaderMaterial:
				var camo := (sm as ShaderMaterial).duplicate() as ShaderMaterial
				camo.set_shader_parameter("c_base", Color(0.17, 0.16, 0.16))
				camo.set_shader_parameter("c_a", Color(0.48, 0.07, 0.05))
				camo.set_shader_parameter("c_b", Color(0.26, 0.24, 0.23))
				camo.set_shader_parameter("c_c", Color(0.07, 0.065, 0.065))
				m.set_surface_override_material(0, camo)
		# Eyes that burn in the dark of the helmet.
		var k := 1.12
		var eyes := body._attach("Head", Transform3D(Basis.IDENTITY, Vector3(0, 1.62 * k, 0.11 * k)))
		var em := StandardMaterial3D.new()
		em.albedo_color = Color(1.0, 0.3, 0.12)
		em.emission_enabled = true
		em.emission = Color(1.0, 0.25, 0.08)
		em.emission_energy_multiplier = 6.0
		em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		for sx: float in [-0.036, 0.036]:
			var e := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.03, 0.012, 0.01)
			e.mesh = bm
			e.material_override = em
			e.position = Vector3(sx, 0, 0)
			e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			eyes.add_child(e)
		body.helmet.visible = true
	head_offset = 1.66
	if _cap != null:
		_cap.radius = 0.4
		_cap.height = 1.98
		_col.position.y = 0.99
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.25, 0.15)
	_glow.light_energy = 0.9
	_glow.omni_range = 3.5
	_glow.position = Vector3(0, 1.4, 0)
	_glow.shadow_enabled = false
	add_child(_glow)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not alive or puppet:
		return
	var here := Vector2(global_position.x, global_position.z)
	var home := Vector2(arena.x, arena.z)
	var storm: bool = game != null and game.zone != null and game.zone.is_outside(arena)
	# Leashed to its arena (unless the storm has taken it).
	if not storm and here.distance_to(home) > leash:
		enemy = null
		loot_target = null
		roam_point = home
		alert_timer = 0.0
	var fighting := enemy != null and is_instance_valid(enemy) and bool(enemy.get("alive"))
	_calm = 0.0 if fighting else _calm + delta
	if _calm > calm_before_regen and hp < 100.0 and not raged:
		hp = minf(100.0, hp + regen_rate * delta)
	# Lobs its volley where it saw you last, over walls if need be.
	if volleys and fighting and (enemy_visible() or _last_seen_t < 5.0):
		_volley_t -= delta
		if _volley_t <= 0.0:
			_volley_t = VOLLEY_EVERY * (0.7 if raged else 1.0)
			_volley((enemy as Node3D).global_position)
	_glow.light_energy = glow_base + (0.5 * glow_base if raged else 0.0) + sin(Time.get_ticks_msec() * 0.004) * 0.2 * glow_base


func _pick_roam_point() -> void:
	# Pace the arena.
	var a := randf() * TAU
	roam_point = Vector2(arena.x, arena.z) + Vector2(cos(a), sin(a)) * randf_range(4.0, 18.0)


func _find_loot() -> LootPickup:
	return null


func take_damage(amount: float, pos: Vector3 = Vector3.ZERO, headshot: bool = false, source: Node = null) -> bool:
	if puppet:
		return super.take_damage(amount, pos, headshot, source)
	# The storm burns it like anyone; bullets and blasts barely scratch it.
	var scaled := amount * (damage_taken if source != null else 1.0)
	var killed := super.take_damage(scaled, pos, headshot, source)
	if alive and not raged and hp <= 50.0:
		_rage()
	return killed


func _rage() -> void:
	raged = true
	shoot_skill = 0.9
	reaction = 0.18
	aggression = 1.0
	_volley_t = 2.0
	# The pack answers.
	if game != null:
		var n := 0
		for b in game.bots:
			if n >= 5:
				break
			if is_instance_valid(b) and b != self and b.alive and b.armed and not b.is_human and not b.puppet \
					and b.state == State.GROUND and not (b is Revenant) and b.global_position.distance_to(global_position) < 300.0:
				b.roam_point = Vector2(global_position.x, global_position.z) + Vector2(randf_range(-12, 12), randf_range(-12, 12))
				b.heard_pos = global_position
				b.alert_timer = 15.0
				n += 1


## Three grenades at and around the target, with the landing spots marked
## on the ground first, so you can see it coming and move.
func _volley(at: Vector3) -> void:
	var spots: Array[Vector3] = []
	for i in 3:
		var off := Vector3.ZERO if i == 0 else Vector3(randf_range(-4.0, 4.0), 0, randf_range(-4.0, 4.0))
		var p: Vector3 = game.ground_at(at + off + Vector3.UP * 2.0)
		spots.append(p)
		_mark_ring(p)
	if game.has_method("play_sfx_at"):
		game.play_sfx_at("writ_fail", global_position, 1.0)
	await get_tree().create_timer(VOLLEY_WINDUP).timeout
	if not alive or not is_inside_tree():
		_clear_rings()
		return
	for p in spots:
		_throw_nade(p)
		_nade_cd = 0.0
		await get_tree().create_timer(0.18).timeout
		if not alive or not is_inside_tree():
			break
	await get_tree().create_timer(2.2).timeout
	_clear_rings()


func _mark_ring(p: Vector3) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.6
	tm.outer_radius = 3.0
	tm.rings = 24
	tm.ring_segments = 6
	ring.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.18, 0.1, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = false
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(1, 0.1, 1)
	game.add_child(ring)
	ring.global_position = p + Vector3.UP * 0.08
	_rings.append(ring)


func _clear_rings() -> void:
	for r in _rings:
		if is_instance_valid(r):
			r.queue_free()
	_rings.clear()


func _die(source: Node) -> void:
	_clear_rings()
	super._die(source)
