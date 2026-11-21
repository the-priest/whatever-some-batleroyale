class_name Beast
extends CharacterBody3D
## An Ash Beetle: man-sized, armoured, quick. It wanders its patch of the
## wilds until it sees you, rears up, then charges and strikes. Its shell
## turns most of a blow from the front; from the side or behind it is soft.
## It drops Embers when it dies.

const B := "res://assets/creatures/insects/"
const MODELS := ["TitanBeetle.glb", "Manticora.glb", "Minotaurbeetle.glb", "AtlasBeetle.glb", "HarlequinBeetle.glb"]
const NAMES := ["ASH BEETLE", "EMBER MANTICORE", "HORNED ASH BEETLE", "ATLAS BEETLE", "HARLEQUIN BEETLE"]
const LENGTH := 2.6
const SIGHT := 28.0
const SPEED := 7.5
const STRIKE_R := 2.9
const STRIKE_DMG := 24.0
const FRONT_TAKEN := 0.3

var game: Node
var hp := 160.0
var alive := true
var home := Vector3.ZERO
var beast_name := "ASH BEETLE"
var _anim: AnimationPlayer
var _model: Node3D
var _state := "idle"
var _t := 2.0
var _to := Vector3.ZERO
var _clip := ""
var _struck := false
var _dead_t := 0.0
## Blows that struck the local player (for the checks).
var strikes := 0


func setup(p_game: Node, at: Vector3, kind: int) -> void:
	game = p_game
	home = at
	beast_name = NAMES[kind % NAMES.size()]
	collision_layer = 4
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(1.5, 1.1, LENGTH)
	cs.shape = bx
	cs.position.y = 0.6
	add_child(cs)
	_model = (load(B + MODELS[kind % MODELS.size()]) as PackedScene).instantiate() as Node3D
	add_child(_model)
	var box := SoldierRig.skin_box(_model)
	if box.size.z > 0.00001:
		var k := LENGTH / box.size.z
		_model.scale = Vector3.ONE * k
		_model.position.y = -box.position.y * k
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visibility_range_end = 260.0
	# Embers smouldering in the cracks of its shell: it reads in the dark.
	var ember := StandardMaterial3D.new()
	ember.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember.albedo_color = Color(1.0, 0.5, 0.15)
	ember.emission_enabled = true
	ember.emission = Color(1.0, 0.4, 0.08)
	ember.emission_energy_multiplier = 4.0
	for k in 5:
		var e := MeshInstance3D.new()
		var em := BoxMesh.new()
		em.size = Vector3(0.05, 0.03, 0.5 - 0.06 * k)
		e.mesh = em
		e.material_override = ember
		e.position = Vector3((float(k) - 2.0) * 0.18, 1.02 - absf(float(k) - 2.0) * 0.07, -0.1 + 0.05 * k)
		e.rotation.y = (float(k) - 2.0) * 0.25
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(e)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.45, 0.15)
	glow.light_energy = 1.3
	glow.omni_range = 3.5
	glow.position = Vector3(0, 1.3, 0)
	glow.distance_fade_enabled = true
	glow.distance_fade_begin = 60.0
	add_child(glow)
	var aps := _model.find_children("*", "AnimationPlayer", true, false)
	_anim = aps[0] as AnimationPlayer if not aps.is_empty() else null
	if _anim != null:
		for nm in ["idle", "walk", "run"]:
			if _anim.has_animation(nm):
				_anim.get_animation(nm).loop_mode = Animation.LOOP_LINEAR
	_play("idle")
	set_meta("beast", true)


func display_name() -> String:
	return beast_name


func head_y() -> float:
	# No head to aim for: the shell is the target.
	return global_position.y + 99.0


func _play(clip: String, speed := 1.0) -> void:
	if _anim == null:
		return
	_anim.speed_scale = speed
	if clip != _clip and _anim.has_animation(clip):
		_clip = clip
		_anim.play(clip, 0.15)


func take_damage(amount: float, pos: Vector3 = Vector3.ZERO, _headshot: bool = false, source: Node = null) -> bool:
	if not alive:
		return false
	var dmg := amount
	if pos != Vector3.ZERO:
		var to := pos - global_position
		to.y = 0.0
		var fwd := global_basis.z
		fwd.y = 0.0
		if to.length() > 0.05 and to.normalized().dot(fwd.normalized()) > 0.35:
			dmg *= FRONT_TAKEN
			if game != null:
				game.spawn_impact(pos, Vector3.UP, null, false)
	hp -= dmg
	if source == game.player and _state in ["idle", "walk"]:
		_state = "chase"
	if hp <= 0.0:
		_die(source)
		return true
	if _anim != null and _state != "strike" and randf() < 0.3:
		_play("hit")
		_t = 0.25
	return false


func _die(source: Node) -> void:
	alive = false
	_state = "dead"
	_dead_t = 25.0
	collision_layer = 0
	_play("dead")
	if source == game.player and game.writs != null:
		game.writs.award(0, 60, "%s SLAIN" % beast_name)
	game.play_sfx_at("hit_armor", global_position, 2.0)


func _physics_process(delta: float) -> void:
	if game == null or game.player == null:
		return
	if not alive:
		_dead_t -= delta
		if _dead_t <= 0.0:
			queue_free()
		return
	var p: Player = game.player
	var to_p := p.global_position - global_position
	var flat := Vector2(to_p.x, to_p.z)
	var d := flat.length()
	# Far from anyone: asleep, cheap.
	if d > 160.0:
		return
	_t -= delta
	var want := Vector3.ZERO
	match _state:
		"idle":
			_play("idle")
			if _sees(p, d):
				_state = "alert"
				_t = 0.7
			elif _t <= 0.0:
				var a := randf() * TAU
				_to = home + Vector3(cos(a), 0, sin(a)) * randf_range(3.0, 12.0)
				_state = "walk"
				_t = 6.0
		"walk":
			_play("walk")
			var tw := _to - global_position
			tw.y = 0.0
			if tw.length() < 1.0 or _t <= 0.0:
				_state = "idle"
				_t = randf_range(2.0, 5.0)
			else:
				want = tw.normalized() * 2.0
			if _sees(p, d):
				_state = "alert"
				_t = 0.7
		"alert":
			# Rears up: a moment to see it coming.
			_play("threat")
			_face(to_p, delta * 6.0)
			if _t <= 0.0:
				_state = "chase"
		"chase":
			_play("run", 1.3)
			_face(to_p, delta * 5.0)
			want = Vector3(to_p.x, 0, to_p.z).normalized() * SPEED
			if d < STRIKE_R:
				_state = "strike"
				_t = 0.75
				_struck = false
			elif d > SIGHT * 1.8 or global_position.distance_to(home) > 80.0 or not p.alive:
				_state = "walk"
				_to = home
				_t = 10.0
		"strike":
			_play("attack", 1.2)
			_face(to_p, delta * 2.0)
			if not _struck and _t <= 0.38:
				_struck = true
				var fwd := global_basis.z
				if d < STRIKE_R + 0.6 and Vector2(fwd.x, fwd.z).normalized().dot(flat.normalized()) > 0.4 and p.mode == Player.Mode.GROUND:
					var before := p.hp
					p.take_damage(STRIKE_DMG, global_position + Vector3.UP, false, self)
					if p.hp < before:
						strikes += 1
						p.velocity += Vector3(flat.x, 0, flat.y).normalized() * 6.0 + Vector3.UP * 3.0
			if _t <= 0.0:
				_state = "chase"
	velocity.x = move_toward(velocity.x, want.x, 30.0 * delta)
	velocity.z = move_toward(velocity.z, want.z, 30.0 * delta)
	if not is_on_floor():
		velocity.y -= 24.0 * delta
	else:
		velocity.y = 0.0
	move_and_slide()


func _sees(p: Player, d: float) -> bool:
	return p.alive and p.mode == Player.Mode.GROUND and d < SIGHT


func _face(to: Vector3, k: float) -> void:
	var yaw := atan2(to.x, to.z)
	rotation.y = lerp_angle(rotation.y, yaw, clampf(k, 0.0, 1.0))
