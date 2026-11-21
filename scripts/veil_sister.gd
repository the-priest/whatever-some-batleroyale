class_name VeilSister
extends Revenant
## The Veil Sisters, Ellan and Moira: two pale duellists in grey veils who
## never fight apart.
##
##   - crossfire: both throw a line of fire at you at once, from two sides;
##     stand where the lines cross and you take both
##   - the swap: smoke at both their feet, a breath, and they have traded
##     places (whoever you were chasing is now behind you)
##   - when one falls the other grieves: she rages, faster and deadlier, and
##     the crossfire comes from her alone, twice as often
##
## The elder keeps the time for both; on a joined player's machine they are
## only where the host says.

const CROSS_EVERY := 8.5
const SWAP_EVERY := 11.0
const SWAP_DELAY := 0.75
const ORB_DMG := 20.0

var sister: VeilSister = null
var elder := false
var _cross_t := 4.0
var _swap_t := 7.0
var _swap_in := -1.0
var grieving := false


func setup_sister(p_name: String, p_arena: Vector3, p_game: Node, p_elder: bool) -> void:
	setup_revenant(p_name, "OF THE VEIL", p_arena, p_game)
	elder = p_elder
	damage_taken = 0.17
	leash = 50.0
	volleys = false
	regen_rate = 2.0
	shoot_skill = 0.7
	reaction = 0.25
	set_meta("sister", true)
	aura_color = Color(0.72, 0.82, 1.0)
	cloak_color = Color(0.7, 0.72, 0.78)
	crown = ""
	helmet_level = 0
	if not elder:
		_cross_t = 4.0
		_swap_t = 999.0


func display_name() -> String:
	return "%s %s" % [bot_name, title]


func _ready() -> void:
	super._ready()
	if body != null and body.model != null:
		body.model.scale = Vector3.ONE * 1.05
		for mi in body.model.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var sm := m.get_surface_override_material(0)
			if sm is ShaderMaterial:
				var camo := (sm as ShaderMaterial).duplicate() as ShaderMaterial
				var tint := Color(0.75, 0.78, 0.82) if elder else Color(0.62, 0.64, 0.7)
				camo.set_shader_parameter("c_base", tint)
				camo.set_shader_parameter("c_a", tint.lightened(0.15))
				camo.set_shader_parameter("c_b", tint.darkened(0.25))
				camo.set_shader_parameter("c_c", tint.darkened(0.35))
				m.set_surface_override_material(0, camo)
	if _glow != null:
		_glow.light_color = Color(0.7, 0.8, 1.0)
		glow_base = 0.6
	# No helmet: a veil of grey gauze from crown to shoulders.
	if body != null and body.skin == null:
		if body.helmet != null:
			body.helmet.visible = false
		var k := 1.05
		var head := body._attach("Head", Transform3D(Basis.IDENTITY, Vector3(0, 1.62 * k, 0.0)))
		var vm := StandardMaterial3D.new()
		vm.albedo_color = Color(0.85, 0.86, 0.9, 0.62)
		vm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		vm.cull_mode = BaseMaterial3D.CULL_DISABLED
		vm.roughness = 1.0
		var cm := CylinderMesh.new()
		cm.top_radius = 0.11
		cm.bottom_radius = 0.3
		cm.height = 0.62
		cm.radial_segments = 14
		cm.cap_top = true
		cm.cap_bottom = false
		var veil := MeshInstance3D.new()
		veil.mesh = cm
		veil.material_override = vm
		veil.position = Vector3(0, 0.02, -0.01)
		veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		head.add_child(veil)


static func link(a: VeilSister, b: VeilSister) -> void:
	a.sister = b
	b.sister = a
	a.elder = true
	b.elder = false


func _alive_sister() -> VeilSister:
	if sister != null and is_instance_valid(sister) and sister.alive:
		return sister
	return null


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if puppet or not alive:
		return
	var other := _alive_sister()
	if other == null and sister != null and not grieving:
		_grieve()
	var tgt: Node3D = enemy as Node3D if enemy != null and is_instance_valid(enemy) and bool(enemy.get("alive")) else null
	if tgt == null and other != null and other.enemy != null and is_instance_valid(other.enemy):
		enemy = other.enemy
		tgt = enemy as Node3D
	if tgt == null:
		return
	# The swap, called by the elder (or by the one left).
	if _swap_in >= 0.0:
		_swap_in -= delta
		if _swap_in < 0.0:
			_do_swap()
		return
	if elder or grieving:
		_cross_t -= delta
		_swap_t -= delta
		if _cross_t <= 0.0:
			_cross_t = CROSS_EVERY * (0.5 if grieving else (0.75 if raged else 1.0))
			_crossfire(tgt)
			if other != null:
				other._crossfire(tgt)
		elif _swap_t <= 0.0 and other != null:
			_swap_t = SWAP_EVERY * (0.7 if raged else 1.0)
			_begin_swap()


## A line of three balls of pale fire, straight at the target.
func _crossfire(tgt: Node3D) -> void:
	var from := global_position + Vector3.UP * 1.6
	var dir := (tgt.global_position + Vector3.UP - from).normalized()
	var n := 4 if grieving else 3
	for i in n:
		var off := dir.rotated(Vector3.UP, deg_to_rad((float(i) - float(n - 1) * 0.5) * 5.0))
		var spd := 21.0 + 2.0 * float(i)
		BossOrb.launch(game, from, off, spd, ORB_DMG, self, true, 0.7, false)
		game.boss_fx({"k": "orb", "p": from, "d": off, "s": spd, "z": 0.7, "f": false})
	game.play_sfx_at("jump_whoosh", from, 3.0)


func _begin_swap() -> void:
	var other := _alive_sister()
	if other == null:
		return
	_swap_in = SWAP_DELAY
	other._swap_in = -1.0
	game.spawn_smoke(global_position + Vector3.UP, 1.3)
	game.spawn_smoke(other.global_position + Vector3.UP, 1.3)
	game.play_sfx_at("warden_whisper", global_position, 4.0)


func _do_swap() -> void:
	var other := _alive_sister()
	if other == null:
		return
	var a := global_position
	var b := other.global_position
	global_position = b
	other.global_position = a
	velocity = Vector3.ZERO
	other.velocity = Vector3.ZERO
	game.spawn_smoke(a + Vector3.UP, 1.0)
	game.spawn_smoke(b + Vector3.UP, 1.0)


func _grieve() -> void:
	grieving = true
	raged = true
	shoot_skill = 0.92
	reaction = 0.15
	damage_taken *= 0.8
	_cross_t = 1.5
	if game != null and game.hud != null and game.player != null and game.player.global_position.distance_to(global_position) < 120.0:
		game.hud.show_big("%s GRIEVES" % bot_name, HUD.DANGER, 2.4)
		game.hud.show_notice("HER SISTER IS DEAD  —  SHE WILL NOT STOP NOW", 3.0)
		game.sfx.play_ui("writ_fail", -3.0)
