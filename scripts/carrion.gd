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
## Dives that struck the local player (for the checks).
var dive_hits := 0


func setup_carrion(p_arena: Vector3, p_game: Node) -> void:
	setup_revenant("VESPERA", "THE CARRION QUEEN", p_arena, p_game)
	damage_taken = 0.15
	leash = 55.0
	volleys = false
	regen_rate = 3.0
	set_meta("carrion", true)


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
	_build_body()


func _build_body() -> void:
	_rig = Node3D.new()
	_rig.position = Vector3(0, 1.4, 0)
	add_child(_rig)
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.07, 0.065, 0.075)
	black.roughness = 0.55
	black.metallic = 0.2
	var bone := StandardMaterial3D.new()
	bone.albedo_color = Color(0.85, 0.8, 0.68)
	# Body: long and lean.
	var bm := SphereMesh.new()
	bm.radius = 0.75
	bm.height = 1.5
	var bd := MeshInstance3D.new()
	bd.mesh = bm
	bd.material_override = black
	bd.scale = Vector3(0.9, 0.85, 1.9)
	_rig.add_child(bd)
	# Neck and head with a long pale beak.
	var hm := SphereMesh.new()
	hm.radius = 0.38
	hm.height = 0.76
	var hd := MeshInstance3D.new()
	hd.mesh = hm
	hd.material_override = black
	hd.position = Vector3(0, 0.45, -1.45)
	_rig.add_child(hd)
	var pm := PrismMesh.new()
	pm.size = Vector3(0.28, 0.9, 0.22)
	var bk := MeshInstance3D.new()
	bk.mesh = pm
	bk.material_override = bone
	bk.position = Vector3(0, 0.38, -2.05)
	bk.rotation.x = -PI * 0.5
	_rig.add_child(bk)
	var eye := StandardMaterial3D.new()
	eye.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye.albedo_color = Color(1.0, 0.3, 0.2)
	eye.emission_enabled = true
	eye.emission = Color(1.0, 0.25, 0.15)
	eye.emission_energy_multiplier = 6.0
	for sx: float in [-0.22, 0.22]:
		var em := SphereMesh.new()
		em.radius = 0.07
		em.height = 0.14
		var e := MeshInstance3D.new()
		e.mesh = em
		e.material_override = eye
		e.position = Vector3(sx, 0.55, -1.72)
		_rig.add_child(e)
	# A crown of bone spurs.
	for k in 5:
		var sp := PrismMesh.new()
		sp.size = Vector3(0.08, 0.36, 0.08)
		var s := MeshInstance3D.new()
		s.mesh = sp
		s.material_override = bone
		s.position = Vector3(-0.2 + 0.1 * k, 0.86, -1.4)
		_rig.add_child(s)
	# Wings: a pivot at each shoulder, three ragged feathered panels.
	for side: float in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.6 * side, 0.25, -0.2)
		_rig.add_child(pivot)
		for f in 3:
			var wm := BoxMesh.new()
			wm.size = Vector3(1.5, 0.06, 1.3 - 0.25 * f)
			var w := MeshInstance3D.new()
			w.mesh = wm
			w.material_override = black
			w.position = Vector3(side * (0.75 + 1.35 * f), -0.05 * f, 0.15 * f)
			pivot.add_child(w)
		_wings.append(pivot)
	# Tail fan.
	var tm := BoxMesh.new()
	tm.size = Vector3(1.1, 0.05, 1.2)
	var tl := MeshInstance3D.new()
	tl.mesh = tm
	tl.material_override = black
	tl.position = Vector3(0, 0.0, 1.9)
	_rig.add_child(tl)


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
			# Wings spread wide and still: now is the time.
			flap = 0.25 + sin(t * 1.5) * 0.05
	for i in _wings.size():
		_wings[i].rotation.z = flap * (1.0 if i == 0 else -1.0) * -1.0
	if _rig != null:
		_rig.rotation.x = -0.5 if phase == "dive" else 0.0


func _physics_process(delta: float) -> void:
	if puppet:
		super._physics_process(delta)
		return
	if not alive:
		return
	velocity = Vector3.ZERO
	collision_layer = 1
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
				_hit.clear()
				game.play_sfx_at("jump_whoosh", global_position, 8.0)
		"dive":
			var dir := (_to - _from)
			var step := DIVE_SPEED * delta
			var next := global_position.move_toward(_to, step)
			global_position = next
			_face(Vector3(dir.x, 0.0, dir.z))
			_strike_along()
			if global_position.distance_to(_to) < 0.3:
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
