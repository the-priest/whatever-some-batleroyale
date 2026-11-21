class_name Unkindled
extends Bellkeeper
## The Unkindled: what kneels at the heart of the Ordeal, for those who have
## endured it once. A tall black knight crowned with a cold iron bell. It fights
## in three parts:
##
##   I   the toll and the peal (as the Bellkeeper)
##   II  below two thirds: the ash nova and the ashen step (as the Warden)
##   III below one third: it burns. Everything comes faster, and it calls two
##       echoes of the Revenants it has outlasted into the ring, once.

const NOVA_R := 9.0
const NOVA_DMG := 42.0
const NOVA_WINDUP := 1.1
const STEP_DELAY := 0.8

var part := 1
var _nova_t := 3.0
var _nova_in := -1.0
var _step_t := 5.0
var _step_in := -1.0
var _step_to := Vector3.ZERO
var _echoes_called := false


func setup_unkindled(p_arena: Vector3, p_game: Node) -> void:
	setup_bell(p_arena, p_game)
	bot_name = "THE UNKINDLED"
	skin = Revenant.SKINS["THE UNKINDLED"]
	title = "WHO KNELT AT THE HEART OF THE ORDEAL"
	damage_taken = 0.085
	regen_rate = 0.0
	shoot_skill = 0.75
	set_meta("unkindled", true)
	aura_color = Color(0.6, 0.78, 1.0)
	aura_size = 1.6
	cloak_color = Color(0.03, 0.03, 0.04)
	cloak_long = 1.25
	crown = "great_horns"


func _ready() -> void:
	super._ready()
	if body != null and body.model != null:
		body.model.scale = Vector3.ONE * 1.36
		for mi in body.model.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var sm := m.get_surface_override_material(0)
			if sm is ShaderMaterial:
				var camo := (sm as ShaderMaterial).duplicate() as ShaderMaterial
				camo.set_shader_parameter("c_base", Color(0.06, 0.055, 0.06))
				camo.set_shader_parameter("c_a", Color(0.16, 0.15, 0.17))
				camo.set_shader_parameter("c_b", Color(0.55, 0.45, 0.22))
				camo.set_shader_parameter("c_c", Color(0.03, 0.03, 0.035))
				m.set_surface_override_material(0, camo)
	head_offset = 1.5 * 1.36
	if _cap != null:
		_cap.radius = 0.36 * 1.36
		_cap.height = 1.78 * 1.36
		_col.position.y = 0.89 * 1.36
	if _glow != null:
		_glow.light_color = Color(0.7, 0.8, 1.0)
		glow_base = 0.8
	# A cold iron bell for a crown.
	if _bell != null:
		_bell.scale = Vector3.ONE * 0.8
		for c in _bell.find_children("*", "MeshInstance3D", true, false):
			var iron := StandardMaterial3D.new()
			iron.albedo_color = Color(0.12, 0.12, 0.14)
			iron.metallic = 0.9
			iron.roughness = 0.3
			(c as MeshInstance3D).material_override = iron
		for l in _bell.find_children("*", "OmniLight3D", true, false):
			(l as OmniLight3D).light_color = Color(0.6, 0.75, 1.0)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if puppet or not alive:
		return
	_check_part()
	if part < 2:
		return
	if _nova_in >= 0.0:
		_nova_in -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		if _nova_in < 0.0:
			_nova()
		return
	if _step_in >= 0.0:
		_step_in -= delta
		if _step_in < 0.0:
			_arrive()
		return
	var tgt: Node3D = enemy as Node3D if enemy != null and is_instance_valid(enemy) and bool(enemy.get("alive")) else null
	if tgt == null:
		return
	var fast := 0.6 if part == 3 else 1.0
	_nova_t -= delta
	_step_t -= delta
	var d := tgt.global_position.distance_to(global_position)
	if d < NOVA_R + 4.0 and _nova_t <= 0.0:
		_nova_t = 7.0 * fast
		_nova_in = NOVA_WINDUP * fast
		game.boss_fx({"k": "slam", "p": global_position, "r": NOVA_R, "w": _nova_in})
		game.play_sfx_at("warden_whisper", global_position, 6.0)
	elif d > 16.0 and _step_t <= 0.0:
		_step_t = 9.0 * fast
		_begin_step(tgt)


func _check_part() -> void:
	var want := 3 if hp <= 33.0 else (2 if hp <= 66.0 else 1)
	if want <= part:
		return
	part = want
	game.shake(25.0)
	game.spawn_smoke(global_position + Vector3.UP, 2.5)
	if part == 2:
		game.hud.show_big("THE UNKINDLED RISES", Color(0.7, 0.8, 1.0), 2.6)
		game.hud.show_notice("ASH AND SMOKE  —  IT WILL COME TO YOU NOW", 3.0)
	else:
		raged = true
		game.hud.show_big("THE UNKINDLED BURNS", HUD.DANGER, 2.8)
		game.hud.show_notice("ITS ECHOES ANSWER  —  END IT", 3.0)
		if not _echoes_called and game.ordeal != null:
			_echoes_called = true
			game.ordeal.call_echoes(2)
	game.sfx.play_ui("event_horn", -2.0)


func _nova() -> void:
	var at := global_position
	game.spawn_smoke(at + Vector3.UP * 0.5, 2.0)
	game.shake(22.0)
	game.play_sfx_at("explosion", at, 2.0)
	for v in _victims():
		var dd := (v as Node3D).global_position.distance_to(at)
		if dd < NOVA_R:
			v.take_damage(NOVA_DMG * (1.0 - (dd / NOVA_R) * 0.4), at, false, self)
			if v == game.player and game.player.iframes <= 0.0:
				var away := (v as Node3D).global_position - at
				away.y = 0.0
				game.player.velocity += away.normalized() * 8.0 + Vector3.UP * 5.0


func _begin_step(tgt: Node3D) -> void:
	var side := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
	var to: Vector3 = tgt.global_position + side * 5.0
	if Vector2(to.x - arena.x, to.z - arena.z).length() > leash - 6.0:
		to = tgt.global_position.lerp(arena, 0.3)
	var g: Vector3 = game.ground_at(to + Vector3.UP * 20.0)
	_step_to = g + Vector3.UP * 0.3
	_step_in = STEP_DELAY
	velocity = Vector3.ZERO
	game.spawn_smoke(global_position + Vector3.UP, 1.4)
	game.spawn_smoke(_step_to + Vector3.UP, 1.0)
	game.play_sfx_at("warden_whisper", _step_to, 4.0)


func _arrive() -> void:
	global_position = _step_to
	velocity = Vector3.ZERO
	game.spawn_smoke(global_position + Vector3.UP, 1.4)
	_nova_t = minf(_nova_t, 1.0)
