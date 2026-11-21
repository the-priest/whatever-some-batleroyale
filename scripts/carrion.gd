class_name Carrion
extends Revenant
## Vespera, the Carrion Queen: a great black bird of the old battlefields.
##
##   - aloft: she circles high over her prey, out of easy reach (bullets do
##     half), and lets fall volleys of fire from above
##   - the mark: a red strip across the ground, through where you stand
##   - the dive: she comes down along it at terrible speed; anything near her
##     path is struck
##   - perched: at the end of the dive she lands, for a few seconds, wings
##     spread. Now she can be hurt in earnest.
##   - raging (half health): two dives, one after the other, crossing; the
##     volleys come thicker
##
## She moves by her own rules (none of a soldier's); on a joined player's
## machine she is wherever the host says, so she flies there too.

const ALT := 15.0
const CIRCLE_R := 13.0
const SOAR_TIME := 5.5
const MARK_TIME := 1.05
const DIVE_SPEED := 32.0
const DIVE_LEN := 34.0
const DIVE_W := 2.6
const DIVE_DMG := 42.0
const PERCH_TIME := 3.4
const RISE_TIME := 1.1
const DROP_DMG := 16.0

## "soar", "mark", "dive", "perch", "rise"
var phase := "soar"
var _idle_t := 0.0
var _t := 3.0
var _ang := 0.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _hit: Dictionary = {}
var _drop_t := 1.5
var _second := false
var _wings: Array[Node3D] = []
var _rig: Node3D
var _wing_shapes: Array[CollisionShape3D] = []
var _fans: Array[Node3D] = []
var _dive_from := Vector3.ZERO
## Dives that struck the local player (for the checks).
var dive_hits := 0


func setup_carrion(p_arena: Vector3, p_game: Node) -> void:
	setup_revenant("VESPERA", "THE CARRION QUEEN", p_arena, p_game)
	damage_taken = 0.15
	leash = 55.0
	volleys = false
	regen_rate = 3.0
	set_meta("carrion", true)
	aura_color = Color(0.85, 0.15, 0.12)
	aura_size = 2.0


func display_name() -> String:
	return "%s, %s" % [bot_name, title]


func _ready() -> void:
	super._ready()
	if body != null:
		body.visible = false
	if _glow != null:
		_glow.light_color = Color(1.0, 0.4, 0.3)
		_glow.position = Vector3(0, 1.6, 0)
	head_offset = 2.2
	if _cap != null:
		_cap.radius = 1.0
		_cap.height = 2.8
		_col.position.y = 1.4
	# All of her: the long body, head to tail, and both wings tip to tip.
	var body_box := BoxShape3D.new()
	body_box.size = Vector3(1.9, 1.7, 5.2)
	add_hit_shape(body_box, Vector3(0, 1.6, -0.2))
	_build_body()
	# Each wing, shoulder to tip and the long feathers behind; the boxes
	# follow the wings as they beat.
	for i in 2:
		var wb := BoxShape3D.new()
		wb.size = Vector3(4.6, 0.7, 3.0)
		_wing_shapes.append(add_hit_shape(wb, Vector3.ZERO))
	_follow_wings()


func _build_body() -> void:
	_rig = Node3D.new()
	_rig.position = Vector3(0, 1.5, 0)
	_rig.scale = Vector3.ONE * 1.25
	add_child(_rig)
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.05, 0.045, 0.06)
	black.roughness = 0.42
	black.metallic = 0.35
	black.metallic_specular = 0.7
	var plume := StandardMaterial3D.new()
	plume.albedo_color = Color(0.09, 0.07, 0.11)
	plume.roughness = 0.5
	plume.metallic = 0.4
	plume.cull_mode = BaseMaterial3D.CULL_DISABLED
	black.cull_mode = BaseMaterial3D.CULL_DISABLED
	var bone := StandardMaterial3D.new()
	bone.albedo_color = Color(0.86, 0.82, 0.7)
	bone.roughness = 0.65
	var hollow := StandardMaterial3D.new()
	hollow.albedo_color = Color(0.02, 0.0, 0.0)
	hollow.roughness = 1.0
	var eye := StandardMaterial3D.new()
	eye.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye.albedo_color = Color(1.0, 0.25, 0.12)
	eye.emission_enabled = true
	eye.emission = Color(1.0, 0.2, 0.08)
	eye.emission_energy_multiplier = 8.0
	# Body: long, lean, ribbed with ragged plumage.
	var bm := SphereMesh.new()
	bm.radius = 0.75
	bm.height = 1.5
	var bd := MeshInstance3D.new()
	bd.mesh = bm
	bd.material_override = black
	bd.scale = Vector3(0.95, 0.95, 2.0)
	_rig.add_child(bd)
	# Bare ribs of bone showing through the plumage of her breast.
	for r in 4:
		var tm := TorusMesh.new()
		tm.inner_radius = 0.6
		tm.outer_radius = 0.66
		tm.rings = 14
		tm.ring_segments = 4
		var rb := MeshInstance3D.new()
		rb.mesh = tm
		rb.material_override = bone
		rb.position = Vector3(0, -0.05, -0.75 + 0.32 * float(r))
		rb.rotation.x = PI * 0.5
		rb.scale = Vector3(1.12, 1.0, 1.1) * (1.0 - 0.1 * absf(float(r) - 1.5))
		_rig.add_child(rb)
	# Ragged feathers bristling down her back and flanks.
	for r in 3:
		for k in 7:
			var a := lerpf(-1.9, 1.9, float(k) / 6.0)
			var fm := PrismMesh.new()
			fm.size = Vector3(0.22, 0.75, 0.05)
			var fe := MeshInstance3D.new()
			fe.mesh = fm
			fe.material_override = plume
			fe.position = Vector3(sin(a) * 0.62, cos(a) * 0.6, -0.6 + 0.65 * r)
			fe.rotation = Vector3(PI * 0.5 + 0.35, 0, -a)
			_rig.add_child(fe)
	# A ruff of black quills round her neck, flared like a hood.
	var neck := Node3D.new()
	neck.position = Vector3(0, 0.42, -1.25)
	_rig.add_child(neck)
	for k in 12:
		var a := TAU * float(k) / 12.0
		var qm := CylinderMesh.new()
		qm.top_radius = 0.0
		qm.bottom_radius = 0.07
		qm.height = 0.9 + 0.25 * float(k % 3)
		qm.radial_segments = 5
		qm.rings = 1
		var q := MeshInstance3D.new()
		q.mesh = qm
		q.material_override = plume
		var out := Vector3(cos(a), sin(a) * 0.9 + 0.25, 0.0)
		q.position = out * 0.35 + Vector3(0, 0, 0.15)
		q.basis = Basis(Quaternion(Vector3.UP, (out + Vector3(0, 0, 0.6)).normalized()))
		neck.add_child(q)
	# The head: a bare bird's skull, sockets lit from inside, a long hooked
	# beak hanging open.
	var skull := Node3D.new()
	skull.position = Vector3(0, 0.55, -1.6)
	_rig.add_child(skull)
	var sm := SphereMesh.new()
	sm.radius = 0.36
	sm.height = 0.72
	var sk := MeshInstance3D.new()
	sk.mesh = sm
	sk.material_override = bone
	sk.scale = Vector3(0.9, 0.85, 1.25)
	skull.add_child(sk)
	for sx: float in [-0.17, 0.17]:
		var hm := SphereMesh.new()
		hm.radius = 0.12
		hm.height = 0.24
		var so := MeshInstance3D.new()
		so.mesh = hm
		so.material_override = hollow
		so.position = Vector3(sx, 0.07, -0.3)
		skull.add_child(so)
		var em := SphereMesh.new()
		em.radius = 0.055
		em.height = 0.11
		var e := MeshInstance3D.new()
		e.mesh = em
		e.material_override = eye
		e.position = Vector3(sx, 0.07, -0.37)
		skull.add_child(e)
	# Upper beak, long and hooked at the tip; lower beak dropped open.
	var ub := PrismMesh.new()
	ub.size = Vector3(0.26, 1.15, 0.2)
	var u := MeshInstance3D.new()
	u.mesh = ub
	u.material_override = bone
	u.position = Vector3(0, 0.0, -0.95)
	u.rotation.x = -PI * 0.5 - 0.1
	skull.add_child(u)
	var hook := PrismMesh.new()
	hook.size = Vector3(0.1, 0.28, 0.12)
	var hk := MeshInstance3D.new()
	hk.mesh = hook
	hk.material_override = bone
	hk.position = Vector3(0, -0.12, -1.48)
	hk.rotation.x = PI
	skull.add_child(hk)
	var lb := PrismMesh.new()
	lb.size = Vector3(0.2, 0.85, 0.12)
	var lo := MeshInstance3D.new()
	lo.mesh = lb
	lo.material_override = bone
	lo.position = Vector3(0, -0.22, -0.78)
	lo.rotation.x = -PI * 0.5 + 0.35
	skull.add_child(lo)
	# A crown of long bone spurs, swept back.
	for k in 7:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.05
		cm.height = 0.55 + 0.35 * (1.0 - absf(float(k) - 3.0) / 3.0)
		cm.radial_segments = 5
		cm.rings = 1
		var c := MeshInstance3D.new()
		c.mesh = cm
		c.material_override = bone
		var x := (float(k) - 3.0) * 0.09
		c.position = Vector3(x, 0.32, 0.05)
		c.rotation = Vector3(-0.85, 0, -x * 1.6)
		skull.add_child(c)
	# Wings: a pivot at each shoulder; a bony arm in three joints, and long
	# ragged feathers fanned off it, longest at the hand.
	for side: float in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.6 * side, 0.3, -0.25)
		_rig.add_child(pivot)
		var x := 0.0
		for j in 3:
			var ln := [1.5, 1.4, 1.3][j] as float
			var am := CylinderMesh.new()
			am.top_radius = 0.07 - 0.015 * j
			am.bottom_radius = 0.11 - 0.02 * j
			am.height = ln
			am.radial_segments = 6
			am.rings = 1
			var arm := MeshInstance3D.new()
			arm.mesh = am
			arm.material_override = black
			arm.position = Vector3(side * (x + ln * 0.5), 0.0, 0.0)
			arm.rotation.z = PI * 0.5
			pivot.add_child(arm)
			# A claw of bone at each joint.
			var cl := CylinderMesh.new()
			cl.top_radius = 0.0
			cl.bottom_radius = 0.05
			cl.height = 0.35
			cl.radial_segments = 4
			cl.rings = 1
			var cw := MeshInstance3D.new()
			cw.mesh = cl
			cw.material_override = bone
			cw.position = Vector3(side * (x + ln), 0.08, -0.08)
			cw.rotation = Vector3(-1.1, 0, -side * 0.5)
			pivot.add_child(cw)
			x += ln
		# The feathers hang off a fan that swings: trailing behind in flight,
		# let down like a torn cloak when she stands.
		var fan := Node3D.new()
		fan.name = "Fan"
		pivot.add_child(fan)
		var nf := 11
		for f in nf:
			var k := float(f) / float(nf - 1)
			var fl := lerpf(1.3, 2.7, k * k) * (0.82 if f % 3 == 1 else 1.0)
			var fe := MeshInstance3D.new()
			fe.mesh = _feather(fl, 0.5)
			fe.material_override = plume
			var along := 0.3 + k * 3.95
			var spread := (lerpf(0.05, -0.6, k) + (0.07 if f % 2 == 0 else -0.05)) * side
			fe.basis = Basis(Vector3.UP, spread) * Basis(Vector3(0, 0, 1), side * (0.25 + 0.1 * float(f % 2)))
			fe.position = Vector3(side * along, -0.02 - 0.03 * float(f % 2), 0.0) + fe.basis * Vector3(0, 0, fl * 0.5 - 0.15)
			fan.add_child(fe)
		# A second, shorter row over the first: the coverts.
		for f in 8:
			var k := float(f) / 7.0
			var fl := lerpf(0.9, 1.3, k)
			var fe := MeshInstance3D.new()
			fe.mesh = _feather(fl, 0.55)
			fe.material_override = black
			var along := 0.35 + k * 3.2
			fe.basis = Basis(Vector3.UP, lerpf(0.0, -0.35, k) * side)
			fe.position = Vector3(side * along, 0.04, 0.0) + fe.basis * Vector3(0, 0, fl * 0.5 - 0.1)
			fan.add_child(fe)
		_fans.append(fan)
		var tip := Node3D.new()
		tip.name = "Tip"
		tip.position = Vector3(side * 4.2, 0.0, 0.6)
		fan.add_child(tip)
		_wings.append(pivot)
	# Tail fan: long ragged feathers.
	for k in 7:
		var a := lerpf(-0.6, 0.6, float(k) / 6.0)
		var tm := BoxMesh.new()
		tm.size = Vector3(0.24, 0.035, 1.5 + 0.3 * (1.0 - absf(a)))
		var tl := MeshInstance3D.new()
		tl.mesh = tm
		tl.material_override = plume
		tl.basis = Basis(Vector3.UP, a)
		tl.position = Vector3(0, 0.05, 1.3) + tl.basis * Vector3(0, 0, tm.size.z * 0.5)
		_rig.add_child(tl)
	# Talons, bone hooks, hanging below.
	for sx: float in [-0.3, 0.3]:
		for t in 3:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0
			cm.bottom_radius = 0.045
			cm.height = 0.45
			cm.radial_segments = 4
			cm.rings = 1
			var c := MeshInstance3D.new()
			c.mesh = cm
			c.material_override = bone
			c.position = Vector3(sx + (float(t) - 1.0) * 0.08, -0.85, -0.1 - 0.12 * float(t % 2))
			c.rotation = Vector3(PI - 0.5, 0, 0)
			_rig.add_child(c)


## A long feather: broad at the quill, narrowing to a ragged point, flat.
static var _feathers: Dictionary = {}
static func _feather(length: float, width: float) -> Mesh:
	var key := "%.2f_%.2f" % [length, width]
	if _feathers.has(key):
		return _feathers[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := width * 0.5
	# Outline down the feather (z from -L/2 to +L/2), widest a third along.
	var pts: Array[Vector3] = [
		Vector3(0, 0, -length * 0.5),
		Vector3(hw * 0.7, 0, -length * 0.3),
		Vector3(hw, 0, length * 0.05),
		Vector3(hw * 0.55, 0, length * 0.38),
		Vector3(hw * 0.2, 0, length * 0.44),
		Vector3(0, 0, length * 0.5),
		Vector3(-hw * 0.35, 0, length * 0.36),
		Vector3(-hw * 0.8, 0, length * 0.1),
		Vector3(-hw * 0.65, 0, -length * 0.3),
	]
	var c := Vector3(0, 0.02, 0)
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		st.set_normal(Vector3.UP)
		st.add_vertex(c)
		st.add_vertex(b)
		st.add_vertex(a)
	st.generate_normals()
	var m := st.commit()
	_feathers[key] = m
	return m


## Where a wingtip is now, in the world (for the checks).
func wing_tip(i: int) -> Vector3:
	return (_wings[i].get_node("Fan/Tip") as Node3D).global_position


func _process(delta: float) -> void:
	super._process(delta)
	var t := Time.get_ticks_msec() * 0.001
	var flap := 0.0
	match phase:
		"soar", "mark", "rise":
			flap = sin(t * 5.0) * 0.55
		"dive":
			flap = -0.9
		"perch":
			# Wings raised high and spread like a cloak: now is the time.
			flap = 0.5 + sin(t * 1.5) * 0.06
	var hang := 0.85 if phase == "perch" else (0.15 if phase == "dive" else 0.0)
	for i in _wings.size():
		_wings[i].rotation.z = flap * (1.0 if i == 0 else -1.0) * -1.0
		if i < _fans.size():
			_fans[i].rotation.x = lerpf(_fans[i].rotation.x, hang, clampf(delta * 5.0, 0.0, 1.0))
	if _rig != null:
		_rig.rotation.x = -0.5 if phase == "dive" else (0.3 if phase == "perch" else 0.0)
	_follow_wings()


## The wings' hit boxes go where the wings are.
func _follow_wings() -> void:
	if _wing_shapes.size() != _wings.size():
		return
	var inv := global_transform.affine_inverse()
	for i in _wings.size():
		var side := -1.0 if i == 0 else 1.0
		var fan: Node3D = _fans[i] if i < _fans.size() else _wings[i]
		var xf: Transform3D = inv * fan.global_transform * Transform3D(Basis.IDENTITY, Vector3(side * 2.4, 0.0, 1.1))
		# Shapes must not be scaled: keep the turn, drop the rig's scale.
		xf.basis = xf.basis.orthonormalized()
		_wing_shapes[i].transform = xf


func _physics_process(delta: float) -> void:
	if puppet:
		super._physics_process(delta)
		return
	if not alive:
		return
	velocity = Vector3.ZERO
	collision_layer = 4
	# Nobody near: look about twice a second and otherwise rest.
	_idle_t -= delta
	if enemy == null and phase == "soar" and _idle_t > 0.0:
		return
	_idle_t = 0.5
	var tgt := _hunt()
	_t -= delta
	match phase:
		"soar":
			var c := arena
			if tgt != null:
				c = tgt.global_position
			_ang += delta * 0.7
			var want := c + Vector3(cos(_ang) * CIRCLE_R, 0.0, sin(_ang) * CIRCLE_R)
			want.y = _ground_y(want) + ALT
			global_position = global_position.lerp(want, clampf(delta * 1.6, 0.0, 1.0))
			_face(Vector3(-sin(_ang), 0.0, cos(_ang)))
			_drop_t -= delta
			if tgt != null and _drop_t <= 0.0:
				_drop_t = 1.4 if raged else 2.2
				_drop(tgt)
			if _t <= 0.0 and tgt != null:
				_start_mark(tgt)
		"mark":
			# Gliding to the head of the strip, high, ready to fall on it.
			global_position = global_position.lerp(_from + Vector3.UP * 5.0, clampf(delta * 3.5, 0.0, 1.0))
			_face(_to - _from)
			if _t <= 0.0:
				phase = "dive"
				_dive_from = global_position
				_hit.clear()
				game.play_sfx_at("jump_whoosh", global_position, 8.0)
		"dive":
			var dir := (_to - _from)
			# Across the strip at speed; she swoops down in its first third
			# and rakes the rest of it at the height of a man.
			var flat := Vector2(_to.x - global_position.x, _to.z - global_position.z)
			var step := DIVE_SPEED * delta
			var hp2 := Vector2(global_position.x, global_position.z)
			hp2 = hp2 + flat.limit_length(step)
			var total := maxf(0.1, Vector2(_to.x - _dive_from.x, _to.z - _dive_from.z).length())
			var done := 1.0 - Vector2(_to.x - hp2.x, _to.z - hp2.y).length() / total
			var skim := _ground_y(Vector3(hp2.x, 0.0, hp2.y)) + 1.3
			var y := lerpf(_dive_from.y, skim, smoothstep(0.0, 0.33, done))
			global_position = Vector3(hp2.x, y, hp2.y)
			_face(Vector3(dir.x, 0.0, dir.z))
			_strike_along()
			if Vector2(_to.x - hp2.x, _to.z - hp2.y).length() < 0.3:
				if _second:
					_second = false
					var a2 := atan2(dir.z, dir.x) + PI * 0.5
					_line_through(tgt.global_position if tgt != null else _to, a2)
					phase = "mark"
					_t = MARK_TIME * 0.7
				else:
					phase = "perch"
					_t = PERCH_TIME
					game.spawn_smoke(global_position + Vector3.UP * 0.3, 1.2)
					game.play_sfx_at("land_thud", global_position, 6.0)
		"perch":
			global_position.y = _ground_y(global_position) + 0.1
			if tgt != null:
				_face(tgt.global_position - global_position)
			if _t <= 0.0:
				phase = "rise"
				_t = RISE_TIME
		"rise":
			var up := global_position
			up.y = _ground_y(up) + ALT
			global_position = global_position.lerp(up, clampf(delta * 2.5, 0.0, 1.0))
			if _t <= 0.0:
				phase = "soar"
				_t = SOAR_TIME * (0.6 if raged else 1.0)
				var off := global_position - (tgt.global_position if tgt != null else arena)
				_ang = atan2(off.z, off.x)


func _ground_y(p: Vector3) -> float:
	return game.ground_at(Vector3(p.x, game.terrain.height_at(p.x, p.z) + 25.0, p.z)).y


func _face(d: Vector3) -> void:
	if d.length() > 0.05:
		rotation.y = atan2(-d.x, -d.z)


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


## The strip on the ground through the target, and where she will dive from.
func _start_mark(tgt: Node3D) -> void:
	var tp := tgt.global_position
	var a := atan2(tp.z - global_position.z, tp.x - global_position.x)
	_line_through(tp, a)
	phase = "mark"
	_t = MARK_TIME * (0.8 if raged else 1.0)
	_second = raged
	game.play_sfx_at("writ_fail", tp, 4.0)


func _line_through(tp: Vector3, a: float) -> void:
	var d := Vector3(cos(a), 0.0, sin(a))
	var a0 := tp - d * DIVE_LEN * 0.5
	var b0 := tp + d * DIVE_LEN * 0.5
	# Keep the dive inside her ground.
	var hv := Vector2(arena.x, arena.z)
	for k in 2:
		var p := a0 if k == 0 else b0
		var pv := Vector2(p.x, p.z)
		if pv.distance_to(hv) > leash:
			pv = hv + (pv - hv).normalized() * leash
			p = Vector3(pv.x, p.y, pv.y)
		if k == 0:
			a0 = p
		else:
			b0 = p
	_from = Vector3(a0.x, _ground_y(a0) + 1.6, a0.z)
	_to = Vector3(b0.x, _ground_y(b0) + 1.2, b0.z)
	game.boss_fx({"k": "line", "a": _from, "b": _to, "w": DIVE_W, "t": MARK_TIME})


func _strike_along() -> void:
	for v in _victims():
		if _hit.has(v):
			continue
		var vp: Vector3 = (v as Node3D).global_position + Vector3.UP
		if vp.distance_to(global_position) < DIVE_W:
			_hit[v] = true
			v.take_damage(DIVE_DMG, global_position, false, self)
			if v == game.player and game.player.iframes <= 0.0:
				dive_hits += 1
				var away := vp - global_position
				away.y = 0.0
				game.player.velocity += away.normalized() * 8.0 + Vector3.UP * 4.0


## Fire let fall from above, at and round the prey.
func _drop(tgt: Node3D) -> void:
	var n := 3 if raged else 2
	for i in n:
		var aim: Vector3 = tgt.global_position + Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(-3.0, 3.0))
		var from := global_position + Vector3.DOWN * 0.5
		var dir := (aim - from).normalized()
		BossOrb.launch(game, from, dir, 22.0, DROP_DMG, self, true, 0.7, false)
		game.boss_fx({"k": "orb", "p": from, "d": dir, "s": 22.0, "z": 0.7, "f": false})


func take_damage(amount: float, pos: Vector3 = Vector3.ZERO, headshot: bool = false, source: Node = null) -> bool:
	if not puppet and phase != "perch" and source != null:
		# On the wing she is hard to hurt.
		amount *= 0.5
	return super.take_damage(amount, pos, headshot, source)


func _die(source: Node) -> void:
	super._die(source)
	var g := _ground_y(global_position)
	var tw := create_tween()
	tw.tween_property(self, "global_position:y", g, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
