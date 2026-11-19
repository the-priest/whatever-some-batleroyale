class_name LanternWitch
extends Revenant
## Isolde, the Lantern Witch: a tall pale figure in a lantern's light, who
## floats a hand's breadth over the ground.
##
##   - the sweep: long beams of light wheel round her, one full turn.
##       amber, low to the ground: JUMP it
##       violet, at the chest:    CROUCH under it
##     Each shows dim for a breath before it burns.
##   - lanterns: three slow lights drift after you and burst when they reach
##     you (shoot them down: they are frail)
##   - she blinks away when you come too close
##   - raging (half health): two beams at once, one of each, turning faster

const BEAM_LEN := 19.0
const BEAM_SPIN := 2.1
const BEAM_WARN := 0.85
const BEAM_DMG := 28.0
const LOW_H := 0.45
const HIGH_H := 1.45
const SWEEP_EVERY := 7.5
const LANTERN_EVERY := 9.0
const BLINK_EVERY := 6.0

var _sweep_t := 3.5
var _lantern_t := 6.0
var _blink_t := 4.0
## Beams in play: {a0, spin, high, t, warn, last}
var _beams: Array = []
var _hit_by: Dictionary = {}
## Beams that struck the local player (for the checks).
var beam_hits := 0
var _lamp: OmniLight3D


func setup_witch(p_arena: Vector3, p_game: Node) -> void:
	setup_revenant("ISOLDE", "THE LANTERN WITCH", p_arena, p_game)
	damage_taken = 0.15
	leash = 50.0
	volleys = false
	regen_rate = 3.0
	shoot_skill = 0.55
	set_meta("witch", true)


func display_name() -> String:
	return "%s, %s" % [bot_name, title]


func _ready() -> void:
	super._ready()
	if body != null and body.model != null:
		body.model.scale = Vector3.ONE * 1.2
		for mi in body.model.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var sm := m.get_surface_override_material(0)
			if sm is ShaderMaterial:
				var camo := (sm as ShaderMaterial).duplicate() as ShaderMaterial
				camo.set_shader_parameter("c_base", Color(0.78, 0.76, 0.8))
				camo.set_shader_parameter("c_a", Color(0.6, 0.55, 0.75))
				camo.set_shader_parameter("c_b", Color(0.9, 0.88, 0.9))
				camo.set_shader_parameter("c_c", Color(0.35, 0.3, 0.45))
				m.set_surface_override_material(0, camo)
	# Her lantern, held high.
	var lan := Node3D.new()
	lan.position = Vector3(0.45, 2.45, -0.2)
	add_child(lan)
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(1.0, 0.85, 0.5)
	gm.emission_enabled = true
	gm.emission = Color(1.0, 0.8, 0.45)
	gm.emission_energy_multiplier = 5.0
	var cm := CylinderMesh.new()
	cm.top_radius = 0.12
	cm.bottom_radius = 0.16
	cm.height = 0.3
	var g := MeshInstance3D.new()
	g.mesh = cm
	g.material_override = gm
	lan.add_child(g)
	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(1.0, 0.82, 0.5)
	_lamp.light_energy = 2.0
	_lamp.omni_range = 9.0
	_lamp.shadow_enabled = false
	lan.add_child(_lamp)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if puppet or not alive:
		return
	_tick_beams(delta)
	var tgt: Node3D = enemy as Node3D if enemy != null and is_instance_valid(enemy) and bool(enemy.get("alive")) else null
	if tgt == null:
		return
	var d := tgt.global_position.distance_to(global_position)
	_sweep_t -= delta
	_lantern_t -= delta
	_blink_t -= delta
	if _sweep_t <= 0.0 and d < BEAM_LEN - 2.0 and _beams.is_empty():
		_sweep_t = SWEEP_EVERY * (0.7 if raged else 1.0)
		_sweep()
	elif _lantern_t <= 0.0 and d > 7.0:
		_lantern_t = LANTERN_EVERY * (0.7 if raged else 1.0)
		_lanterns(tgt)
	elif _blink_t <= 0.0 and d < 5.0:
		_blink_t = BLINK_EVERY
		_blink_away(tgt)


func _sweep() -> void:
	var spin := BEAM_SPIN * (1.25 if raged else 1.0) * (1.0 if randf() < 0.5 else -1.0)
	var kinds: Array = [true, false] if raged else [randf() < 0.5]
	var a0 := randf() * TAU
	for i in kinds.size():
		var high: bool = kinds[i]
		var a := a0 + PI * float(i)
		_beams.append({"a0": a, "spin": spin, "high": high, "t": 0.0, "last": a})
		game.boss_fx({"k": "beam", "p": global_position, "a": a, "s": spin, "h": HIGH_H if high else LOW_H, "l": BEAM_LEN, "w": BEAM_WARN, "d": TAU / absf(spin), "c": high})
	_hit_by.clear()
	game.play_sfx_at("warden_whisper", global_position, 6.0)


func _tick_beams(delta: float) -> void:
	if _beams.is_empty():
		return
	var victims := _victims()
	var dur := TAU / absf(BEAM_SPIN * (1.25 if raged else 1.0))
	var keep: Array = []
	for b in _beams:
		b.t = float(b.t) + delta
		var t: float = b.t
		if t < BEAM_WARN:
			keep.append(b)
			continue
		var turned := (t - BEAM_WARN) * float(b.spin)
		var now := float(b.a0) + turned
		var prev: float = b.last
		b.last = now
		for v in victims:
			var key := str(v.get_instance_id()) + ("h" if b.high else "l")
			if _hit_by.has(key):
				continue
			var vp: Vector3 = (v as Node3D).global_position
			var off := Vector2(vp.x - global_position.x, vp.z - global_position.z)
			if off.length() > BEAM_LEN or off.length() < 0.6:
				continue
			var av := atan2(off.y, off.x)
			if not _swept(prev, now, av):
				continue
			if _avoids(v, bool(b.high)):
				continue
			_hit_by[key] = true
			v.take_damage(BEAM_DMG, global_position, false, self)
			if v == game.player and game.player.iframes <= 0.0:
				beam_hits += 1
		if t - BEAM_WARN < dur:
			keep.append(b)
	_beams = keep


## Did a beam turning from `a` to `b` pass the angle `x`?
static func _swept(a: float, b: float, x: float) -> bool:
	var lo := minf(a, b)
	var hi := maxf(a, b)
	var k: float = floorf((lo - x) / TAU) + 1.0
	var xx: float = x + k * TAU
	return xx >= lo and xx <= hi


## A low beam passes under the airborne; a high one over the crouching.
func _avoids(v: Node, high: bool) -> bool:
	if v == game.player:
		var p: Player = game.player
		if high:
			return p.crouching() or p.downed
		return not p.is_on_floor()
	var vp: Vector3 = (v as Node3D).global_position
	if high:
		return (v as Bot).crouching if "crouching" in v else false
	return vp.y - game.ground_at(vp + Vector3.UP * 0.5).y > 0.45


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


func _lanterns(tgt: Node3D) -> void:
	for i in 3:
		var from := global_position + Vector3(randf_range(-1.5, 1.5), 2.6, randf_range(-1.5, 1.5))
		var dir := (tgt.global_position + Vector3.UP - from).normalized().rotated(Vector3.UP, deg_to_rad(-20.0 + 20.0 * i))
		BossOrb.launch(game, from, dir, 7.5, 24.0, self, true, 0.9, false)
		game.boss_fx({"k": "orb", "p": from, "d": dir, "s": 7.5, "z": 0.9, "f": false})
	game.play_sfx_at("beacon_light", global_position, 4.0)


func _blink_away(tgt: Node3D) -> void:
	var away := global_position - tgt.global_position
	away.y = 0.0
	var to := global_position + away.normalized().rotated(Vector3.UP, randf_range(-0.8, 0.8)) * 12.0
	if Vector2(to.x - arena.x, to.z - arena.z).length() > leash - 4.0:
		to = arena
	var g: Vector3 = game.ground_at(to + Vector3.UP * 20.0)
	game.spawn_smoke(global_position + Vector3.UP, 1.0)
	global_position = g + Vector3.UP * 0.3
	velocity = Vector3.ZERO
	game.spawn_smoke(global_position + Vector3.UP, 1.0)


func _die(source: Node) -> void:
	_beams.clear()
	super._die(source)
