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
var _jaws: Array[Node3D] = []
## Eruptions that struck the local player (for the checks).
var erupt_hits := 0


func setup_wyrm(p_arena: Vector3, p_game: Node) -> void:
	setup_revenant("SKARN", "THE WYRM BENEATH", p_arena, p_game)
	damage_taken = 0.15
	leash = 55.0
	volleys = false
	regen_rate = 3.0
	set_meta("wyrm", true)
	aura_color = Color(0.55, 1.0, 0.35)
	aura_size = 2.0


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
	# Its head is the weak point: headshots from where the maw sits.
	head_offset = HEIGHT - 1.6
	if _cap != null:
		# The capsule holds the trunk; spheres follow the arch up to the head.
		_cap.radius = 1.2
		_cap.height = 3.4
		_col.position.y = 1.7
	for k: float in [0.45, 0.65, 0.82, 1.0]:
		var sp := SphereShape3D.new()
		sp.radius = lerpf(1.15, 0.9, k)
		add_hit_shape(sp, Vector3(0, k * (HEIGHT - 1.4) - k * k * 0.6, -k * k * 2.2))
	var hs := SphereShape3D.new()
	hs.radius = 0.95
	add_hit_shape(hs, Vector3(0, (HEIGHT - 1.4) - 0.6 + 0.7, -2.2 - 0.5))
	# And the open maw thrust out at you, jaws and all.
	var ms := SphereShape3D.new()
	ms.radius = 0.9
	add_hit_shape(ms, Vector3(0, (HEIGHT - 1.4) - 0.6 + 0.6, -3.9))
	_build_body()


func _build_body() -> void:
	var hide := StandardMaterial3D.new()
	hide.albedo_color = Color(0.15, 0.135, 0.115)
	hide.roughness = 0.38
	hide.metallic = 0.25
	hide.metallic_specular = 0.7
	var plate := StandardMaterial3D.new()
	plate.albedo_color = Color(0.2, 0.18, 0.15)
	plate.roughness = 0.5
	plate.metallic = 0.2
	var belly := StandardMaterial3D.new()
	belly.albedo_color = Color(0.38, 0.33, 0.25)
	belly.roughness = 0.7
	var bone := StandardMaterial3D.new()
	bone.albedo_color = Color(0.82, 0.78, 0.66)
	bone.roughness = 0.6
	var sick := StandardMaterial3D.new()
	sick.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sick.albedo_color = Color(0.55, 1.0, 0.25)
	sick.emission_enabled = true
	sick.emission = Color(0.45, 1.0, 0.15)
	sick.emission_energy_multiplier = 4.0
	var n := 8
	for i in n:
		var k := float(i) / float(n - 1)
		var seg := Node3D.new()
		seg.position = Vector3(0, k * (HEIGHT - 1.4), 0)
		add_child(seg)
		var r := lerpf(1.3, 0.85, k)
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 1.6
		sm.radial_segments = 14
		sm.rings = 7
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		mi.material_override = hide
		seg.add_child(mi)
		# A pale ribbed belly on the front of each ring.
		var bm := SphereMesh.new()
		bm.radius = r * 0.75
		bm.height = r * 1.2
		bm.radial_segments = 10
		bm.rings = 5
		var bl := MeshInstance3D.new()
		bl.mesh = bm
		bl.material_override = belly
		bl.position = Vector3(0, 0, -r * 0.42)
		bl.scale = Vector3(1.0, 0.8, 0.6)
		seg.add_child(bl)
		# Overlapping armour plates on its back, and a ridge of bone spines.
		var pm := BoxMesh.new()
		pm.size = Vector3(r * 1.5, r * 0.5, r * 0.9)
		var pl := MeshInstance3D.new()
		pl.mesh = pm
		pl.material_override = plate
		pl.position = Vector3(0, r * 0.15, r * 0.62)
		pl.rotation.x = -0.35
		seg.add_child(pl)
		for sx: float in [-0.35, 0.0, 0.35]:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0
			cm.bottom_radius = 0.11 * r
			cm.height = (0.95 if sx == 0.0 else 0.6) * r
			cm.radial_segments = 5
			cm.rings = 1
			var sp := MeshInstance3D.new()
			sp.mesh = cm
			sp.material_override = bone
			sp.position = Vector3(sx * r, r * 0.35, r * 0.95)
			sp.rotation = Vector3(1.05, 0, -sx * 1.2)
			seg.add_child(sp)
		# Weeping sores of green fire.
		if i % 3 == 1:
			for q in 2:
				var a := (float(q) - 0.5) * 2.1 + float(i)
				var gm := SphereMesh.new()
				gm.radius = 0.08
				gm.height = 0.16
				var g := MeshInstance3D.new()
				g.mesh = gm
				g.material_override = sick
				g.position = Vector3(sin(a) * r * 0.97, 0.05, cos(a) * r * 0.97)
				g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				seg.add_child(g)
		_segs.append(seg)
	# Broken earth and slabs of rock heaved up round where it stands.
	var dirt := StandardMaterial3D.new()
	dirt.albedo_color = Color(0.22, 0.17, 0.12)
	dirt.roughness = 1.0
	for j in 9:
		var a := TAU * float(j) / 9.0 + randf_range(-0.2, 0.2)
		var rm := BoxMesh.new()
		rm.size = Vector3(randf_range(0.9, 1.6), randf_range(0.25, 0.45), randf_range(0.8, 1.3))
		var rk := MeshInstance3D.new()
		rk.mesh = rm
		rk.material_override = dirt
		rk.position = Vector3(cos(a) * 1.9, 0.15, sin(a) * 1.9)
		rk.rotation = Vector3(randf_range(-0.2, 0.2), -a, 0.45 + randf_range(-0.15, 0.15))
		add_child(rk)
	# The head: an armoured skull whose maw splits into four hooked jaws,
	# rows of teeth spiralling into a throat of green fire.
	_head = Node3D.new()
	_head.position = Vector3(0, HEIGHT - 0.9, 0)
	add_child(_head)
	var hm := CylinderMesh.new()
	hm.top_radius = 0.9
	hm.bottom_radius = 1.0
	hm.height = 1.2
	hm.radial_segments = 12
	hm.cap_top = false
	var hmi := MeshInstance3D.new()
	hmi.mesh = hm
	hmi.material_override = hide
	_head.add_child(hmi)
	var cap := BoxMesh.new()
	cap.size = Vector3(1.6, 0.35, 1.3)
	var cp := MeshInstance3D.new()
	cp.mesh = cap
	cp.material_override = plate
	cp.position = Vector3(0, 0.2, 0.75)
	cp.rotation.x = 0.5
	_head.add_child(cp)
	var flesh := StandardMaterial3D.new()
	flesh.albedo_color = Color(0.26, 0.035, 0.03)
	flesh.roughness = 0.3
	flesh.metallic_specular = 0.9
	flesh.cull_mode = BaseMaterial3D.CULL_DISABLED
	var throat := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.72
	tm.bottom_radius = 0.2
	tm.height = 0.7
	tm.cap_top = false
	tm.radial_segments = 12
	throat.mesh = tm
	throat.material_override = flesh
	throat.position = Vector3(0, 0.3, 0)
	_head.add_child(throat)
	var core := MeshInstance3D.new()
	var co := SphereMesh.new()
	co.radius = 0.28
	co.height = 0.56
	core.mesh = co
	core.material_override = sick
	core.position = Vector3(0, 0.05, 0)
	_head.add_child(core)
	for row in 2:
		var rr := 0.62 - 0.22 * row
		var cnt := 12 - 3 * row
		for t in cnt:
			var a := TAU * (float(t) + 0.5 * row) / float(cnt)
			var tc := CylinderMesh.new()
			tc.top_radius = 0.0
			tc.bottom_radius = 0.06
			tc.height = 0.42 - 0.1 * row
			tc.radial_segments = 4
			tc.rings = 1
			var ti := MeshInstance3D.new()
			ti.mesh = tc
			ti.material_override = bone
			ti.position = Vector3(cos(a) * rr, 0.55 - 0.15 * row, sin(a) * rr)
			# Leaning inward, toward the throat.
			ti.basis = Basis(Quaternion(Vector3.UP, (Vector3(-cos(a), 0.9, -sin(a))).normalized()))
			_head.add_child(ti)
	_jaws.clear()
	for j in 4:
		var a := TAU * float(j) / 4.0 + PI * 0.25
		var hinge := Node3D.new()
		hinge.position = Vector3(cos(a) * 0.82, 0.55, sin(a) * 0.82)
		hinge.rotation.y = -a
		_head.add_child(hinge)
		var jm := PrismMesh.new()
		jm.size = Vector3(0.75, 1.5, 0.14)
		var jw := MeshInstance3D.new()
		jw.mesh = jm
		jw.material_override = plate
		jw.position = Vector3(0, 0.7, 0)
		jw.rotation.y = PI * 0.5
		hinge.add_child(jw)
		var inner := MeshInstance3D.new()
		var im := PrismMesh.new()
		im.size = Vector3(0.6, 1.3, 0.05)
		inner.mesh = im
		inner.material_override = flesh
		inner.position = Vector3(-0.08, 0.6, 0)
		inner.rotation.y = PI * 0.5
		hinge.add_child(inner)
		# A hooked fang on each jaw's tip.
		var fm := CylinderMesh.new()
		fm.top_radius = 0.0
		fm.bottom_radius = 0.08
		fm.height = 0.5
		fm.radial_segments = 4
		fm.rings = 1
		var fg := MeshInstance3D.new()
		fg.mesh = fm
		fg.material_override = bone
		fg.position = Vector3(-0.2, 1.35, 0)
		fg.rotation.z = 2.2
		hinge.add_child(fg)
		_jaws.append(hinge)
	# Six small eyes in a ring under the jaws, all green.
	for e6 in 6:
		var a := TAU * float(e6) / 6.0 + PI / 6.0
		var em := SphereMesh.new()
		em.radius = 0.1
		em.height = 0.2
		var e := MeshInstance3D.new()
		e.mesh = em
		e.material_override = sick
		e.position = Vector3(cos(a) * 0.97, 0.05, sin(a) * 0.97)
		_head.add_child(e)


func _process(delta: float) -> void:
	super._process(delta)
	var t := Time.get_ticks_msec() * 0.001
	# It arches forward over whatever it faces, like a snake about to strike,
	# and sways like something that is mostly muscle.
	for i in _segs.size():
		var k := float(i) / float(maxi(1, _segs.size() - 1))
		_segs[i].position.x = sin(t * 2.2 + k * 2.5) * 0.35 * k
		_segs[i].position.z = -k * k * 2.2 + cos(t * 1.7 + k * 2.0) * 0.25 * k
		_segs[i].position.y = k * (HEIGHT - 1.4) - k * k * 0.6
		_segs[i].rotation.x = -k * 0.9
	if _head != null and not _segs.is_empty():
		var top := _segs[_segs.size() - 1].position
		_head.position = Vector3(top.x, top.y + 0.6, top.z - 0.55)
		# The maw turned down at you.
		_head.rotation.x = -1.6 + sin(t * 1.3) * 0.08
	# The jaws gape when it is up and hungry, and snap when it spits.
	var open := 0.35
	match phase:
		"up":
			open = 0.7 + sin(t * 3.0) * 0.12
		"rise":
			open = 1.0
		"tell", "under":
			open = 0.1
	for jw in _jaws:
		jw.rotation.z = lerpf(jw.rotation.z, -open, clampf(delta * 8.0, 0.0, 1.0))


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
				collision_layer = 4
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
			collision_layer = 4
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
