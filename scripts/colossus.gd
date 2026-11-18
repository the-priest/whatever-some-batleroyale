class_name Colossus
extends Revenant
## A Colossus: one of the island's great bosses. Two and a half times the
## height of a man, armoured in cooling lava, and very hard to kill.
##
##   SLAM      it rears up (a red ring grows round its feet) and brings the
##             ground down: everything inside the ring is hurt and thrown
##   BARRAGE   it hurls balls of fire that fly dead straight: sidestep them,
##             or put a wall between you
##   CHARGE    it roars, lowers its head and runs you down
##
## Three phases: below two thirds it is quicker; below a third it is furious,
## throws more fire, and slams more often. It hunts players over soldiers.
## Hide from it long enough and it heals, slowly.
##
## Whoever helps bring one down is given a Gift: a power for the rest of the
## match (see Gifts in writs.gd).

const GIANT_NAMES := [
	["VARGHUL", "THE ASHEN COLOSSUS"], ["ORGRATH", "THE MOUNTAIN THAT WALKS"],
	["MOTHER OF CINDERS", "WHO BURNS THE WORLD"], ["THE DROWNED KING", "CROWNED IN STORM"],
]
const SCALE := 2.6
const SLAM_R := 9.0
const SLAM_DMG := 85.0
const SLAM_WINDUP := 1.25
const CHARGE_DMG := 60.0
const CHARGE_SPEED := 17.0
const CHARGE_TIME := 1.5
const ORB_DMG := 28.0
const SEEK := 85.0

var stage := 1
var _attack_t := 4.0
var _busy := ""
var _busy_t := 0.0
var _charge_dir := Vector3.ZERO
var _charge_hit: Dictionary = {}
var _seek_t := 0.0
var _orbs_left := 0
var _orb_t := 0.0
var _target: Node3D = null


func setup_colossus(p_name: String, p_title: String, p_arena: Vector3, p_game: Node) -> void:
	setup_revenant(p_name, p_title, p_arena, p_game)
	damage_taken = 0.045
	leash = 75.0
	volleys = false
	regen_rate = 1.5
	calm_before_regen = 12.0
	shoot_skill = 0.6
	sight = 170.0
	meds = 0
	grenades = 0
	set_meta("colossus", true)


func _ready() -> void:
	super._ready()
	if body != null and body.model != null:
		body.model.scale = Vector3.ONE * SCALE
		# Black stone with cracks of fire.
		for mi in body.model.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var sm := m.get_surface_override_material(0)
			if sm is ShaderMaterial:
				var camo := (sm as ShaderMaterial).duplicate() as ShaderMaterial
				camo.set_shader_parameter("c_base", Color(0.09, 0.08, 0.08))
				camo.set_shader_parameter("c_a", Color(0.95, 0.38, 0.08))
				camo.set_shader_parameter("c_b", Color(0.16, 0.13, 0.12))
				camo.set_shader_parameter("c_c", Color(0.04, 0.035, 0.035))
				camo.set_shader_parameter("scale", 4.0)
				m.set_surface_override_material(0, camo)
	head_offset = 1.5 * SCALE
	if _cap != null:
		_cap.radius = 0.36 * SCALE
		_cap.height = 1.78 * SCALE
		_col.position.y = 0.89 * SCALE
	if _glow != null:
		# Embers in its cracks: a low orange glow, not a pool of red.
		_glow.light_color = Color(1.0, 0.5, 0.2)
		_glow.omni_range = 5.5
		glow_base = 0.7
		_glow.position = Vector3(0, 2.6, 0)


func _physics_process(delta: float) -> void:
	if puppet or not alive:
		super._physics_process(delta)
		return
	if _busy == "charge":
		_charge_step(delta)
		return
	super._physics_process(delta)
	if not alive:
		return
	# Phases.
	var want := 3 if hp <= 33.0 else (2 if hp <= 66.0 else 1)
	if want > stage:
		stage = want
		_attack_t = minf(_attack_t, 1.0)
		if game.has_method("boss_stage"):
			game.boss_stage(self, stage)
	# It wants players: the nearest one in reach is its enemy.
	_seek_t -= delta
	if _seek_t <= 0.0:
		_seek_t = 1.5
		_target = _nearest_player()
		if _target != null:
			enemy = _target
			alert_timer = 6.0
			heard_pos = _target.global_position
	if _target != null and (not is_instance_valid(_target) or not bool(_target.get("alive"))):
		_target = null
	# Throwing fire, one ball after another.
	if _orbs_left > 0:
		_orb_t -= delta
		if _orb_t <= 0.0:
			_orb_t = 0.16 if stage < 3 else 0.11
			_orbs_left -= 1
			_throw_orb()
	if _busy == "slam":
		_busy_t -= delta
		if _busy_t <= 0.0:
			_busy = ""
			_slam_land()
		return
	if _busy == "windup":
		_busy_t -= delta
		velocity = Vector3.ZERO
		if _busy_t <= 0.0:
			_busy = "charge"
			_busy_t = CHARGE_TIME
			_charge_hit.clear()
		return
	_attack_t -= delta
	if _attack_t <= 0.0 and _target != null and _orbs_left == 0:
		var d := global_position.distance_to(_target.global_position)
		_attack_t = [0.0, 4.6, 3.4, 2.4][stage] + randf() * 1.2
		if d < SLAM_R * 0.95:
			_start_slam()
		elif d < 38.0 and randf() < (0.35 + 0.1 * stage):
			_start_charge()
		elif d < 95.0:
			_orbs_left = [0, 5, 7, 10][stage]
			_orb_t = 0.4
			game.play_sfx_at("event_horn", global_position + Vector3.UP * 3.0, 2.0)


## It does not shoot: everything it does to you, you can see coming.
func _shoot_logic(_delta: float) -> void:
	pass


func arm_weapon(id: String) -> void:
	super.arm_weapon(id)
	if body != null:
		body.set_gun("")


func _nearest_player() -> Node3D:
	var best: Node3D = null
	var best_d := SEEK
	var cands: Array = []
	if game.player != null and game.player.alive and game.player.mode == Player.Mode.GROUND:
		cands.append(game.player)
	for id in game.humans:
		var h = game.humans[id]
		if h != null and is_instance_valid(h) and (h as Bot).alive and (h as Bot).state == State.GROUND:
			cands.append(h)
	for c in cands:
		var d := (c as Node3D).global_position.distance_to(global_position)
		if d < best_d and (c as Node3D).global_position.distance_to(arena) < leash + 25.0:
			best_d = d
			best = c
	return best


## Everyone who can be hurt by its blows: players and soldiers.
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


# ------------------------------------------------------------------ slam --
func _start_slam() -> void:
	_busy = "slam"
	_busy_t = SLAM_WINDUP * (0.85 if stage == 3 else 1.0)
	velocity = Vector3.ZERO
	game.boss_fx({"k": "slam", "p": global_position, "r": SLAM_R, "w": _busy_t})
	game.play_sfx_at("writ_fail", global_position, 6.0)


func _slam_land() -> void:
	var at := global_position
	game.spawn_explosion(at + Vector3.UP * 0.3)
	game.shake(30.0)
	for v in _victims():
		var d := (v as Node3D).global_position.distance_to(at)
		if d < SLAM_R:
			var k := 1.0 - (d / SLAM_R) * 0.5
			v.take_damage(SLAM_DMG * k, at, false, self)
			if v == game.player:
				var away := ((v as Node3D).global_position - at)
				away.y = 0.0
				game.player.velocity += away.normalized() * 9.0 + Vector3.UP * 7.0


# ---------------------------------------------------------------- charge --
func _start_charge() -> void:
	_busy = "windup"
	_busy_t = 0.75 if stage < 3 else 0.5
	var to := _target.global_position - global_position
	to.y = 0.0
	_charge_dir = to.normalized()
	rotation.y = atan2(-_charge_dir.x, -_charge_dir.z)
	game.play_sfx_at("event_horn", global_position + Vector3.UP * 3.0, 5.0)
	game.boss_fx({"k": "roar", "p": global_position})


func _charge_step(delta: float) -> void:
	_busy_t -= delta
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	velocity.x = _charge_dir.x * CHARGE_SPEED
	velocity.z = _charge_dir.z * CHARGE_SPEED
	rotation.y = atan2(-_charge_dir.x, -_charge_dir.z)
	move_and_slide()
	_play("Sprint", 1.2)
	for v in _victims():
		if _charge_hit.has(v):
			continue
		if (v as Node3D).global_position.distance_to(global_position) < 3.2:
			_charge_hit[v] = true
			v.take_damage(CHARGE_DMG, global_position + Vector3.UP, false, self)
			if v == game.player:
				game.player.velocity += _charge_dir * 14.0 + Vector3.UP * 6.0
				game.shake(20.0)
	# Into a wall: it stops, stunned for a moment (your opening).
	if get_slide_collision_count() > 0 and Vector2(velocity.x, velocity.z).length() < CHARGE_SPEED * 0.4:
		_busy_t = 0.0
		_attack_t = maxf(_attack_t, 2.5)
	if _busy_t <= 0.0:
		_busy = ""
		velocity = Vector3.ZERO


# ------------------------------------------------------------------- fire --
func _throw_orb() -> void:
	if _target == null or not is_instance_valid(_target):
		_orbs_left = 0
		return
	var from := global_position + Vector3.UP * (1.3 * SCALE) - global_basis.z * 1.2
	var aim: Vector3 = _target.global_position + Vector3.UP * 1.1
	# Spread grows with each phase; the first ball goes straight at you.
	var spread := 2.5 * float(stage)
	aim += Vector3(randf_range(-spread, spread), randf_range(-0.6, 0.8), randf_range(-spread, spread))
	var dir := (aim - from).normalized()
	var spd := 22.0 + 3.0 * float(stage)
	BossOrb.launch(game, from, dir, spd, ORB_DMG, self, true)
	game.boss_fx({"k": "orb", "p": from, "d": dir, "s": spd})
	game.play_sfx_at("jump_whoosh", from, 2.0)


## Clients: the picture of a slam's warning ring (and a roar's dust).
static func show_fx(game: Node, fx: Dictionary) -> void:
	match str(fx.get("k", "")):
		"slam":
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.92
			tm.outer_radius = 1.0
			tm.rings = 48
			tm.ring_segments = 6
			ring.mesh = tm
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(1.0, 0.15, 0.08, 0.9)
			ring.material_override = m
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			game.add_child(ring)
			var r := float(fx.get("r", SLAM_R))
			ring.global_position = (fx["p"] as Vector3) + Vector3.UP * 0.12
			ring.scale = Vector3(0.5, 0.05, 0.5)
			# The ring grows out to the edge of the blow, then the ground breaks.
			var tw := ring.create_tween()
			tw.tween_property(ring, "scale", Vector3(r, 0.05, r), float(fx.get("w", SLAM_WINDUP))).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_callback(ring.queue_free)
			# A filled disc too, so the danger area is unmistakable.
			var disc := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = r
			cm.bottom_radius = r
			cm.height = 0.02
			cm.radial_segments = 40
			disc.mesh = cm
			var dm := StandardMaterial3D.new()
			dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			dm.albedo_color = Color(1.0, 0.1, 0.05, 0.11)
			disc.material_override = dm
			disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			game.add_child(disc)
			disc.global_position = (fx["p"] as Vector3) + Vector3.UP * 0.1
			var tw2 := disc.create_tween()
			tw2.tween_interval(float(fx.get("w", SLAM_WINDUP)))
			tw2.tween_callback(disc.queue_free)
		"orb":
			BossOrb.launch(game, fx["p"], fx["d"], float(fx["s"]), 0.0, null, false)
		"roar":
			game.spawn_smoke((fx["p"] as Vector3) + Vector3.UP * 0.5, 2.0)
