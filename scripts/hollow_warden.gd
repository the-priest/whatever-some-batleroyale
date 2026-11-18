class_name HollowWarden
extends Revenant
## The Hollow Warden: an ashen knight kneeling before the Heart of the
## Hollow. The ward that covers the Heart covers it too; it wakes when the
## last brazier is lit, and the Heart cannot be taken while it stands.
##
##   - an ash nova: a grey ring on the ground round it, then a blast of ash
##     (step out of the ring)
##   - ashen step: when you keep your distance it goes up in smoke and comes
##     out of it beside you (the smoke shows where, a moment first)
##   - leashed to the Hollow; regains its strength when no one fights it
##   - at half health it rages: novas come faster, steps come sooner

const SCALE := 1.28
const NOVA_R := 8.5
const NOVA_DMG := 40.0
const NOVA_WINDUP := 1.25
const NOVA_EVERY := 8.0
const STEP_EVERY := 11.0
const STEP_DELAY := 0.9

var dormant := true
var _nova_t := 3.0
var _nova_in := -1.0
var _step_t := 6.0
var _step_in := -1.0
var _step_to := Vector3.ZERO


func setup_warden(p_arena: Vector3, p_game: Node) -> void:
	setup_revenant("THE HOLLOW WARDEN", "KEEPER OF THE ASH", p_arena, p_game)
	damage_taken = 0.11
	leash = 60.0
	volleys = false
	regen_rate = 3.0
	calm_before_regen = 8.0
	shoot_skill = 0.7
	sight = 120.0
	set_meta("warden", true)


func display_name() -> String:
	return "%s, %s" % [bot_name, title]


func _ready() -> void:
	super._ready()
	if body != null and body.model != null:
		body.model.scale = Vector3.ONE * SCALE
		# Ash-grey plate with pale embers in the seams.
		for mi in body.model.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var sm := m.get_surface_override_material(0)
			if sm is ShaderMaterial:
				var camo := (sm as ShaderMaterial).duplicate() as ShaderMaterial
				camo.set_shader_parameter("c_base", Color(0.24, 0.23, 0.22))
				camo.set_shader_parameter("c_a", Color(0.52, 0.5, 0.47))
				camo.set_shader_parameter("c_b", Color(0.36, 0.34, 0.32))
				camo.set_shader_parameter("c_c", Color(0.12, 0.11, 0.11))
				m.set_surface_override_material(0, camo)
	head_offset = 1.5 * SCALE
	if _cap != null:
		_cap.radius = 0.36 * SCALE
		_cap.height = 1.78 * SCALE
		_col.position.y = 0.89 * SCALE
	if _glow != null:
		_glow.light_color = Color(1.0, 0.7, 0.4)
		glow_base = 0.6


## The last brazier is lit: it rises.
func wake() -> void:
	if not dormant:
		return
	dormant = false
	_nova_t = 4.0
	_step_t = 7.0
	calm_t = 0.0
	if game != null:
		game.spawn_smoke(global_position + Vector3.UP, 1.6)
		game.boss_fx({"k": "roar", "p": global_position})


func _physics_process(delta: float) -> void:
	if puppet:
		super._physics_process(delta)
		return
	if dormant:
		# Kneeling before the Heart, still as the stone.
		if not alive:
			return
		velocity = Vector3.ZERO
		enemy = null
		_play("Crouch_Idle", 1.0)
		return
	super._physics_process(delta)
	if not alive:
		return
	# The blast of a nova that was called.
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
	var tgt := _target_near()
	if tgt == null:
		return
	var d := tgt.global_position.distance_to(global_position)
	_nova_t -= delta
	_step_t -= delta
	if d < NOVA_R + 4.0 and _nova_t <= 0.0:
		_nova_t = NOVA_EVERY * (0.65 if raged else 1.0)
		_nova_in = NOVA_WINDUP * (0.8 if raged else 1.0)
		game.boss_fx({"k": "slam", "p": global_position, "r": NOVA_R, "w": _nova_in})
		game.play_sfx_at("warden_whisper", global_position, 6.0)
	elif d > 18.0 and _step_t <= 0.0:
		_step_t = STEP_EVERY * (0.6 if raged else 1.0)
		_begin_step(tgt)


## Whoever it is fighting, if they are near enough to matter.
func _target_near() -> Node3D:
	if enemy != null and is_instance_valid(enemy) and bool(enemy.get("alive")):
		return enemy as Node3D
	return null


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


func _nova() -> void:
	var at := global_position
	game.spawn_smoke(at + Vector3.UP * 0.5, 2.0)
	game.shake(22.0)
	game.play_sfx_at("explosion", at, 2.0)
	for v in _victims():
		var dd := (v as Node3D).global_position.distance_to(at)
		if dd < NOVA_R:
			v.take_damage(NOVA_DMG * (1.0 - (dd / NOVA_R) * 0.4), at, false, self)
			if v == game.player:
				var away := (v as Node3D).global_position - at
				away.y = 0.0
				game.player.velocity += away.normalized() * 8.0 + Vector3.UP * 5.0


## Ashen step: smoke where it stands and where it will come out, then it is
## there, beside its prey (never outside the Hollow).
func _begin_step(tgt: Node3D) -> void:
	var side := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
	var to: Vector3 = tgt.global_position + side * 5.0
	var home := Vector2(arena.x, arena.z)
	if Vector2(to.x, to.z).distance_to(home) > leash - 6.0:
		to = tgt.global_position.lerp(arena, 0.3)
	var g: Vector3 = game.ground_at(to + Vector3.UP * 20.0)
	if g.y < game.terrain.water_surface_at(g.x, g.z) + 0.3:
		return
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
	_nova_t = minf(_nova_t, 1.2)


func take_damage(amount: float, pos: Vector3 = Vector3.ZERO, headshot: bool = false, source: Node = null) -> bool:
	if dormant and not puppet:
		# The ward holds it as it holds the Heart.
		return false
	return super.take_damage(amount, pos, headshot, source)


func _die(source: Node) -> void:
	super._die(source)
	if game != null and game.hollow != null and not puppet:
		game.hollow.on_warden_fell()
