class_name Wyrm
extends Revenant
## Skarn, the Wyrm Beneath: a great worm that swims through the ground.
##
##   - under: it is gone, deep in the earth (nothing can touch it), moving
##     beneath whoever it hunts
##   - the tell: a ring of cracked earth where it will come up, a breath first
##   - the eruption: it bursts up through the ring; anyone in it is struck and
##     thrown into the air
##   - exposed: for a few seconds it stands and spits acid, fans of green fire
##     that burn the ground where they land. Now it can be hurt.
##   - then it sinks, and it comes again
##   - at half health it rages: shorter under, a second eruption straight after
##     the first, wider fans
##
## Underground it really is underground: on a joined player's machine the
## earth hides it, with no extra word between host and client.

const DEPTH := 9.0
const UNDER_TIME := 3.2
const TELL := 1.15
const RISE := 0.35
const SINK := 0.6
const UP_TIME := 4.2
const ERUPT_R := 4.8
const ERUPT_DMG := 45.0
const SPIT_DMG := 18.0
const HEIGHT := 6.0

## "under", "tell", "rise", "up", "sink"
var phase := "under"
var _idle_t := 0.0
var _t := 1.5
var _at := Vector3.ZERO
var _spits := 0
var _spit_t := 0.0
var _encore := false
var _segs: Array[Node3D] = []
var _head: Node3D
## Eruptions that struck the local player (for the checks).
var erupt_hits := 0


func setup_wyrm(p_arena: Vector3, p_game: Node) -> void:
	setup_revenant("SKARN", "THE WYRM BENEATH", p_arena, p_game)
	damage_taken = 0.15
	leash = 55.0
	volleys = false
	regen_rate = 3.0
	set_meta("wyrm", true)


func display_name() -> String:
	return "%s, %s" % [bot_name, title]


func _ready() -> void:
	super._ready()
	if body != null:
		body.visible = false
	if _glow != null:
		_glow.light_color = Color(0.5, 1.0, 0.4)
		_glow.position = Vector3(0, HEIGHT - 0.8, 0)
		glow_base = 0.7
	head_offset = HEIGHT - 0.6
	if _cap != null:
		_cap.radius = 1.15
		_cap.height = HEIGHT + 0.4
		_col.position.y = (HEIGHT + 0.4) * 0.5
	_build_body()


func _build_body() -> void:
	var hide := StandardMaterial3D.new()
	hide.albedo_color = Color(0.32, 0.27, 0.22)
	hide.roughness = 0.75
	var belly := StandardMaterial3D.new()
	belly.albedo_color = Color(0.55, 0.45, 0.32)
	belly.roughness = 0.6
	var n := 7
	for i in n:
		var k := float(i) / float(n - 1)
		var seg := Node3D.new()
		seg.position = Vector3(0, k * (HEIGHT - 1.4), 0)
		add_child(seg)
		var sm := SphereMesh.new()
		var r := lerpf(1.25, 0.85, k)
		sm.radius = r
		sm.height = r * 1.7
		sm.radial_segments = 14
		sm.rings = 7
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		mi.material_override = hide if i % 2 == 0 else belly
		seg.add_child(mi)
		_segs.append(seg)
	# Broken earth heaped round where it stands.
	var dirt := StandardMaterial3D.new()
	dirt.albedo_color = Color(0.3, 0.22, 0.14)
	dirt.roughness = 1.0
	for j in 7:
		var a := TAU * float(j) / 7.0
		var rm := SphereMesh.new()
		rm.radius = randf_range(0.6, 1.0)
		rm.height = rm.radius * 1.2
		rm.radial_segments = 6
		rm.rings = 3
		var rk := MeshInstance3D.new()
		rk.mesh = rm
		rk.material_override = dirt
		rk.position = Vector3(cos(a) * 1.7, 0.1, sin(a) * 1.7)
		rk.scale = Vector3(1.0, 0.55, 1.0)
		add_child(rk)
	# The head: a blunt maw of plates, a ring of teeth, small green eyes.
	_head = Node3D.new()
	_head.position = Vector3(0, HEIGHT - 0.9, 0)
	add_child(_head)
	var hm := CylinderMesh.new()
	hm.top_radius = 0.75
	hm.bottom_radius = 1.05
	hm.height = 1.5
	hm.radial_segments = 10
	var hmi := MeshInstance3D.new()
	hmi.mesh = hm
	hmi.material_override = hide
	hmi.rotation.x = -0.5
	hmi.position = Vector3(0, 0.3, -0.25)
	_head.add_child(hmi)
	var tooth := StandardMaterial3D.new()
	tooth.albedo_color = Color(0.9, 0.88, 0.78)
	for t in 10:
		var a := TAU * float(t) / 10.0
		var tm := PrismMesh.new()
		tm.size = Vector3(0.14, 0.32, 0.1)
		var ti := MeshInstance3D.new()
		ti.mesh = tm
		ti.material_override = tooth
		ti.position = Vector3(cos(a) * 0.5, 0.95, -0.55 + sin(a) * 0.5)
		ti.rotation.x = PI
		_head.add_child(ti)
	var eye := StandardMaterial3D.new()
	eye.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye.albedo_color = Color(0.6, 1.0, 0.3)
	eye.emission_enabled = true
	eye.emission = Color(0.5, 1.0, 0.2)
	eye.emission_energy_multiplier = 5.0
	for sx: float in [-0.42, 0.42]:
		var em := SphereMesh.new()
		em.radius = 0.09
		em.height = 0.18
		var e := MeshInstance3D.new()
		e.mesh = em
		e.material_override = eye
		e.position = Vector3(sx, 0.35, -0.75)
		_head.add_child(e)


func _process(delta: float) -> void:
	super._process(delta)
	# It sways like something that is mostly muscle.
	var t := Time.get_ticks_msec() * 0.001
	# It arches forward over whatever it faces, like a snake about to strike.
	for i in _segs.size():
		var k := float(i) / float(maxi(1, _segs.size() - 1))
		_segs[i].position.x = sin(t * 2.2 + k * 2.5) * 0.35 * k
		_segs[i].position.z = -k * k * 2.2 + cos(t * 1.7 + k * 2.0) * 0.25 * k
		_segs[i].position.y = k * (HEIGHT - 1.4) - k * k * 0.6
	if _head != null and not _segs.is_empty():
		var top := _segs[_segs.size() - 1].position
		_head.position = Vector3(top.x, top.y + 0.7, top.z - 0.5)
		_head.rotation.x = -0.75 + sin(t * 1.3) * 0.08


func _physics_process(delta: float) -> void:
	if puppet:
		super._physics_process(delta)
		return
	if not alive:
		return
	# Its own way of moving; none of a soldier's.
	velocity = Vector3.ZERO
	# Nobody near: look about twice a second and otherwise rest (no scans
	# of every soldier, no rays, every frame, for a boss no one is fighting).
	_idle_t -= delta
	if enemy == null and phase == "under" and _idle_t > 0.0:
		return
	_idle_t = 0.5
	var tgt := _hunt()
	if not raged and hp <= 50.0:
		_rage()
	_t -= delta
	match phase:
		"under":
			collision_layer = 0
			var ground: Vector3 = _ground_at(global_position)
			var to := arena
			if tgt != null:
				to = tgt.global_position
			var flat := Vector3(to.x - global_position.x, 0.0, to.z - global_position.z)
			if flat.length() > 0.5:
				global_position += flat.normalized() * minf(flat.length(), 16.0 * delta)
			global_position.y = ground.y - DEPTH
			if _t <= 0.0 and tgt != null:
				_at = _ground_at(tgt.global_position)
				if Vector2(_at.x - arena.x, _at.z - arena.z).length() > leash:
					_at = _ground_at(arena)
				phase = "tell"
				_t = TELL * (0.8 if raged else 1.0)
				game.boss_fx({"k": "slam", "p": _at, "r": ERUPT_R, "w": _t})
				game.play_sfx_at("land_thud", _at, 6.0)
				game.shake(6.0)
			elif _t <= 0.0:
				_t = 1.0
		"tell":
			global_position = _at - Vector3.UP * DEPTH
			if _t <= 0.0:
				phase = "rise"
				_t = RISE
				collision_layer = 1
				_erupt()
		"rise":
			global_position = _at - Vector3.UP * (DEPTH * clampf(_t / RISE, 0.0, 1.0))
			if _t <= 0.0:
				global_position = _at
				if _encore:
					# Raging: straight back down for a second strike.
					_encore = false
					phase = "sink"
					_t = SINK * 0.5
				else:
					phase = "up"
					_t = UP_TIME
					_spits = 2
					_spit_t = 0.8
		"up":
			collision_layer = 1
			global_position = _at
			if tgt != null:
				var d := tgt.global_position - global_position
				rotation.y = atan2(-d.x, -d.z)
				_spit_t -= delta
				if _spits > 0 and _spit_t <= 0.0:
					_spits -= 1
					_spit_t = 1.4
					_spit(tgt)
			if _t <= 0.0:
				phase = "sink"
				_t = SINK
				game.spawn_smoke(_at + Vector3.UP * 0.5, 1.4)
		"sink":
			global_position = _at - Vector3.UP * (DEPTH * (1.0 - clampf(_t / SINK, 0.0, 1.0)))
			if _t <= 0.0:
				phase = "under"
				collision_layer = 0
				_t = UNDER_TIME * (0.6 if raged else 1.0)
				if raged and randf() < 0.6:
					_encore = true
					_t = 0.4


func _ground_at(p: Vector3) -> Vector3:
	return game.ground_at(Vector3(p.x, game.terrain.height_at(p.x, p.z) + 20.0, p.z))


## Who it hunts: its enemy, or the nearest player within the leash.
func _hunt() -> Node3D:
	if enemy != null and is_instance_valid(enemy) and bool(enemy.get("alive")):
		return enemy as Node3D
	var best: Node3D = null
	var bd := leash + 10.0
	for v in _victims():
		if not (v == game.player or (v is Bot and (v as Bot).is_human)):
			continue
		var d := Vector2((v as Node3D).global_position.x - arena.x, (v as Node3D).global_position.z - arena.z).length()
		if d < bd:
			bd = d
			best = v
	enemy = best
	return best


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


func _erupt() -> void:
	game.spawn_explosion(_at + Vector3.UP * 0.3)
	game.spawn_smoke(_at + Vector3.UP, 2.4)
	game.shake(26.0)
	for v in _victims():
		var vp: Vector3 = (v as Node3D).global_position
		var d := Vector2(vp.x - _at.x, vp.z - _at.z).length()
		if d < ERUPT_R:
			v.take_damage(ERUPT_DMG * (1.0 - d / ERUPT_R * 0.35), _at, false, self)
			if v == game.player and game.player.iframes <= 0.0:
				erupt_hits += 1
				var away := vp - _at
				away.y = 0.0
				game.player.velocity += away.normalized() * 6.0 + Vector3.UP * 10.0


func _spit(tgt: Node3D) -> void:
	var from := global_position + Vector3.UP * (HEIGHT - 0.6)
	var base := (tgt.global_position + Vector3.UP - from).normalized()
	var n := 5 if raged else 3
	for i in n:
		var ang := deg_to_rad((float(i) - float(n - 1) * 0.5) * 12.0)
		var dir := base.rotated(Vector3.UP, ang)
		BossOrb.launch(game, from, dir, 19.0, SPIT_DMG, self, true, 0.8, true)
		game.boss_fx({"k": "orb", "p": from, "d": dir, "s": 19.0, "z": 0.8, "f": true})
	game.play_sfx_at("jump_whoosh", from, 4.0)


func take_damage(amount: float, pos: Vector3 = Vector3.ZERO, headshot: bool = false, source: Node = null) -> bool:
	if not puppet and (phase == "under" or phase == "tell") and source != null:
		# Deep in the earth: nothing reaches it.
		return false
	return super.take_damage(amount, pos, headshot, source)


func _die(source: Node) -> void:
	super._die(source)
	# It goes down into the ground for the last time.
	var tw := create_tween()
	tw.tween_property(self, "global_position", global_position - Vector3.UP * DEPTH, 2.5).set_trans(Tween.TRANS_SINE)
