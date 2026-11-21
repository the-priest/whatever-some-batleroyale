class_name ClassKit
extends Node3D
## The class weapon in your hands: the Knight's greatsword and shield, the
## Hunter's longbow, the Pyromancer's ember staff. It draws itself in first
## person, animates every swing, draw and cast, and does the striking.
##
## The player owns one; it lives in the viewmodel under the camera. While it
## is out the gun is put away.

const SWINGS := [
	# time, damage, reach, width, heavy
	[0.46, 34.0, 3.1, 2.6, false],
	[0.46, 36.0, 3.1, 2.6, false],
	[0.78, 64.0, 3.5, 1.8, true],
]
## How big each weapon sits in first person (its parts are built life-size).
const VIEW_SCALE := {"knight": 0.36, "hunter": 0.62, "pyro": 0.5}
const GUARD_TAKEN := 0.2
const PARRY_WINDOW := 0.22
const DRAW_TIME := 0.75
const EMBER_MAX := 100.0
const FIREBALL_COST := 20.0
const CONE_COST := 38.0
const CONE_RANGE := 8.0
const CONE_DPS := 75.0

var player: Player
var game: Node
var cls := ""
var out := false

# Knight.
var _swing := -1
var _swing_t := 0.0
var _swing_hit := false
var _queued := false
var _combo_t := 0.0
var guard := false
var guard_t := 0.0
var _parried_t := 0.0
# Hunter.
var draw := 0.0
var drawing := false
var focus := false
var _loose_t := 0.0
# Pyromancer.
var ember := EMBER_MAX
var _ember_rest := 0.0
var _cast_t := 0.0
var flaming := false
var _cone_tick := 0.0
# Ability.
var ability_cd := 0.0
var quick_shots := 0

var _pivot: Node3D
var _shield: Node3D
var _string_a: MeshInstance3D
var _string_b: MeshInstance3D
var _nocked: Node3D
var _bow_tips: Array[Vector3] = []
var _orb_mat: StandardMaterial3D
var _orb_light: OmniLight3D
var _flames: GPUParticles3D
var _trail: MeshInstance3D
var _trail_mat: StandardMaterial3D
var _trail_t := 0.0
var _equip := 0.0
var _kick := 0.0


func setup(p: Player) -> void:
	player = p
	game = p.game


## Build the weapon for this class (nothing for the Gunslinger).
func build(p_cls: String) -> void:
	cls = p_cls
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_pivot = Node3D.new()
	add_child(_pivot)
	_shield = null
	_flames = null
	match cls:
		"knight":
			_build_sword()
			_build_shield()
		"hunter":
			_build_bow()
		"pyro":
			_build_staff()
	_build_trail()
	for n in find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if g is MeshInstance3D:
			(g as MeshInstance3D).layers = 2
	visible = false


## Put away or drawn again: stop whatever was half done.
func reset_soft() -> void:
	_swing = -1
	_queued = false
	guard = false
	draw = 0.0
	drawing = false
	focus = false
	flaming = false
	_equip = 0.0
	if _flames != null:
		_flames.emitting = false


func reset() -> void:
	_swing = -1
	_queued = false
	guard = false
	draw = 0.0
	drawing = false
	focus = false
	flaming = false
	ember = EMBER_MAX
	ability_cd = 0.0
	quick_shots = 0
	if _flames != null:
		_flames.emitting = false


# --------------------------------------------------------------- models --
static func _mat(c: Color, metal := 0.0, rough := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


static func _cyl(top: float, bottom: float, h: float, seg := 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


## A gauntleted fist round a grip.
func _fist(parent: Node3D, at: Vector3) -> void:
	var iron := _mat(Color(0.16, 0.15, 0.15), 0.6, 0.45)
	_part(parent, _box(Vector3(0.085, 0.1, 0.11)), iron, at)
	_part(parent, _box(Vector3(0.09, 0.03, 0.12)), _mat(Color(0.3, 0.22, 0.14)), at + Vector3(0, -0.06, 0.0))
	_part(parent, _cyl(0.05, 0.06, 0.22), iron, at + Vector3(0.0, -0.06, 0.13), Vector3(PI * 0.5, 0, 0))


func _build_sword() -> void:
	var steel := _mat(Color(0.72, 0.72, 0.75), 0.85, 0.28)
	var dark := _mat(Color(0.12, 0.11, 0.1), 0.5, 0.5)
	var gold := _mat(Color(0.75, 0.55, 0.22), 0.8, 0.35)
	var leather := _mat(Color(0.28, 0.18, 0.11), 0.0, 0.85)
	var s := Node3D.new()
	s.name = "Sword"
	_pivot.add_child(s)
	# The blade runs up the pivot's +Y from the hand.
	_part(s, _cyl(0.018, 0.022, 0.24), leather, Vector3(0, 0.02, 0))
	_part(s, _box(Vector3(0.3, 0.035, 0.05)), gold, Vector3(0, 0.15, 0))
	_part(s, SphereMesh.new(), gold, Vector3(0, -0.12, 0)).scale = Vector3.ONE * 0.06
	_part(s, _box(Vector3(0.075, 1.05, 0.016)), steel, Vector3(0, 0.69, 0))
	_part(s, _box(Vector3(0.018, 1.0, 0.02)), dark, Vector3(0, 0.67, 0))
	var tip := PrismMesh.new()
	tip.size = Vector3(0.075, 0.16, 0.016)
	_part(s, tip, steel, Vector3(0, 1.29, 0))
	# Ember runes along the fuller.
	var rune := StandardMaterial3D.new()
	rune.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rune.albedo_color = Color(1.0, 0.5, 0.15)
	rune.emission_enabled = true
	rune.emission = Color(1.0, 0.4, 0.1)
	rune.emission_energy_multiplier = 3.0
	for k in 4:
		_part(s, _box(Vector3(0.012, 0.05, 0.022)), rune, Vector3(0, 0.35 + 0.18 * k, 0))
	_fist(s, Vector3(0, 0.0, 0))


func _build_shield() -> void:
	var iron := _mat(Color(0.14, 0.13, 0.13), 0.7, 0.4)
	var gold := _mat(Color(0.7, 0.5, 0.2), 0.8, 0.35)
	_shield = Node3D.new()
	_shield.name = "Shield"
	add_child(_shield)
	_part(_shield, _box(Vector3(0.46, 0.6, 0.04)), iron, Vector3.ZERO)
	var low := PrismMesh.new()
	low.size = Vector3(0.46, 0.2, 0.04)
	_part(_shield, low, iron, Vector3(0, -0.4, 0), Vector3(0, 0, PI))
	_part(_shield, _box(Vector3(0.5, 0.04, 0.05)), gold, Vector3(0, 0.3, 0))
	_part(_shield, _box(Vector3(0.04, 0.72, 0.05)), gold, Vector3(0, -0.04, 0.005))
	_part(_shield, _box(Vector3(0.46, 0.04, 0.05)), gold, Vector3(0, 0.02, 0.005))
	var boss := SphereMesh.new()
	boss.radius = 0.06
	boss.height = 0.08
	_part(_shield, boss, gold, Vector3(0, 0.02, -0.03))


func _build_bow() -> void:
	var wood := _mat(Color(0.36, 0.22, 0.12), 0.0, 0.55)
	var grip := _mat(Color(0.2, 0.13, 0.08), 0.0, 0.9)
	var b := Node3D.new()
	b.name = "Bow"
	_pivot.add_child(b)
	# Two limbs curving back from the grip, each in three pieces.
	_bow_tips.clear()
	for side: float in [1.0, -1.0]:
		var at := Vector3(0, 0.07 * side, 0)
		var ang := 0.0
		for j in 3:
			var ln := 0.2
			ang += 0.22
			var dirv := Vector3(0, cos(ang) * side, sin(ang))
			var mid := at + dirv * ln * 0.5
			var seg := _part(b, _box(Vector3(0.028 - j * 0.005, ln, 0.018)), wood, mid)
			seg.rotation.x = ang * side
			at += dirv * ln
		_bow_tips.append(at)
	_part(b, _cyl(0.022, 0.022, 0.16), grip, Vector3.ZERO)
	var str_m := _mat(Color(0.85, 0.82, 0.72))
	_string_a = _part(b, _cyl(0.002, 0.002, 1.0, 4), str_m, Vector3.ZERO)
	_string_b = _part(b, _cyl(0.002, 0.002, 1.0, 4), str_m, Vector3.ZERO)
	# The nocked arrow, drawn back with the string.
	_nocked = Node3D.new()
	b.add_child(_nocked)
	_part(_nocked, _cyl(0.006, 0.006, 0.72, 5), _mat(Color(0.45, 0.32, 0.2)), Vector3(0, 0, -0.36), Vector3(PI * 0.5, 0, 0))
	_part(_nocked, _cyl(0.0, 0.014, 0.06, 4), _mat(Color(0.6, 0.6, 0.62), 0.8), Vector3(0, 0, -0.74), Vector3(-PI * 0.5, 0, 0))
	_part(_nocked, _box(Vector3(0.04, 0.002, 0.08)), _mat(Color(0.85, 0.15, 0.1)), Vector3(0, 0, -0.04))
	# A gloved hand on the grip.
	_part(b, _box(Vector3(0.08, 0.11, 0.09)), _mat(Color(0.22, 0.16, 0.1)), Vector3(0.02, 0, 0.03))
	_update_string(0.0)


func _update_string(k: float) -> void:
	if _string_a == null or _bow_tips.size() < 2:
		return
	var nock := Vector3(0, 0, 0.04 + 0.42 * k)
	for i in 2:
		var s: MeshInstance3D = _string_a if i == 0 else _string_b
		var a: Vector3 = _bow_tips[i]
		var d := nock - a
		s.position = a + d * 0.5
		s.scale = Vector3(1, d.length(), 1)
		s.basis = Basis(Quaternion(Vector3.UP, d.normalized())).scaled(Vector3(1, d.length(), 1))
	_nocked.position = nock
	_nocked.visible = _loose_t <= 0.0


func _build_staff() -> void:
	var wood := _mat(Color(0.18, 0.11, 0.07), 0.0, 0.7)
	var iron := _mat(Color(0.2, 0.18, 0.17), 0.7, 0.4)
	var s := Node3D.new()
	s.name = "Staff"
	_pivot.add_child(s)
	_part(s, _cyl(0.02, 0.024, 1.3), wood, Vector3(0, 0.25, 0))
	for k in 3:
		_part(s, _cyl(0.027, 0.027, 0.03), iron, Vector3(0, -0.2 + 0.35 * k, 0))
	# A cage of iron prongs round a burning orb.
	for k in 4:
		var a := TAU * float(k) / 4.0
		var pr := _part(s, _cyl(0.004, 0.012, 0.2), iron, Vector3(cos(a) * 0.05, 1.0, sin(a) * 0.05))
		pr.rotation = Vector3(sin(a) * 0.35, 0, -cos(a) * 0.35)
	_orb_mat = StandardMaterial3D.new()
	_orb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_orb_mat.albedo_color = Color(1.0, 0.65, 0.25)
	_orb_mat.emission_enabled = true
	_orb_mat.emission = Color(1.0, 0.42, 0.1)
	_orb_mat.emission_energy_multiplier = 5.0
	var orb := SphereMesh.new()
	orb.radius = 0.055
	orb.height = 0.11
	_part(s, orb, _orb_mat, Vector3(0, 1.02, 0))
	_orb_light = OmniLight3D.new()
	_orb_light.light_color = Color(1.0, 0.5, 0.2)
	_orb_light.light_energy = 0.8
	_orb_light.omni_range = 1.6
	_orb_light.position = Vector3(0, 1.02, 0)
	s.add_child(_orb_light)
	_fist(s, Vector3(0, 0.0, 0))
	# The flame wall: a jet of fire from the orb.
	_flames = GPUParticles3D.new()
	_flames.amount = 90
	_flames.lifetime = 0.55
	_flames.local_coords = false
	_flames.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 14.0
	pm.initial_velocity_min = 11.0
	pm.initial_velocity_max = 15.0
	pm.gravity = Vector3(0, 1.5, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
	ramp.add_point(0.4, Color(1.0, 0.4, 0.1, 0.9))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.3, 0.1, 0.05, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.3))
	sc.add_point(Vector2(1, 1.6))
	var st := CurveTexture.new()
	st.curve = sc
	pm.scale_curve = st
	_flames.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.45, 0.45)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fm.vertex_color_use_as_albedo = true
	fm.albedo_texture = Revenant._mote_tex()
	q.material = fm
	_flames.draw_pass_1 = q
	_flames.position = Vector3(0, 1.05, 0)
	s.add_child(_flames)


## The bright arc a swing leaves in the air for an instant.
func _build_trail() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 16
	for i in n:
		var a0 := lerpf(-1.3, 1.3, float(i) / n)
		var a1 := lerpf(-1.3, 1.3, float(i + 1) / n)
		var r0 := 0.85
		var r1 := 1.25
		var p00 := Vector3(sin(a0) * r0, 0, -cos(a0) * r0)
		var p01 := Vector3(sin(a0) * r1, 0, -cos(a0) * r1)
		var p10 := Vector3(sin(a1) * r0, 0, -cos(a1) * r0)
		var p11 := Vector3(sin(a1) * r1, 0, -cos(a1) * r1)
		var al0 := sin(float(i) / n * PI)
		var al1 := sin(float(i + 1) / n * PI)
		for v: Array in [[p00, al0], [p01, al0], [p11, al1], [p00, al0], [p11, al1], [p10, al1]]:
			st.set_color(Color(1, 1, 1, float(v[1])))
			st.add_vertex(v[0])
	_trail = MeshInstance3D.new()
	_trail.mesh = st.commit()
	_trail_mat = StandardMaterial3D.new()
	_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_mat.vertex_color_use_as_albedo = true
	_trail_mat.albedo_color = Color(1.0, 0.75, 0.45, 0.0)
	_trail.material_override = _trail_mat
	_trail.visible = false
	add_child(_trail)


func _show_trail(swing: int) -> void:
	_trail.visible = true
	_trail_t = 0.16
	_trail.position = Vector3(0, -0.12, -0.15)
	_trail.scale = Vector3.ONE * 0.55
	match swing:
		0:
			_trail.rotation = Vector3(0.1, 0, 0.12)
		1:
			_trail.rotation = Vector3(-0.1, 0, -0.3)
		_:
			_trail.rotation = Vector3(0, 0, PI * 0.5)


# ---------------------------------------------------------------- input --
## Each physics tick while the kit is out and you are on your feet.
func tick(delta: float, can_act: bool) -> void:
	ability_cd = maxf(0.0, ability_cd - delta)
	_parried_t = maxf(0.0, _parried_t - delta)
	_loose_t = maxf(0.0, _loose_t - delta)
	_cast_t = maxf(0.0, _cast_t - delta)
	_ember_rest -= delta
	if _ember_rest <= 0.0 and not flaming:
		ember = minf(EMBER_MAX, ember + 16.0 * delta)
	var fire_p := can_act and player._ajp("fire")
	var fire_h := can_act and player._ap("fire")
	var alt_h := can_act and player._ap("aim")
	match cls:
		"knight":
			_tick_knight(delta, fire_p, alt_h)
		"hunter":
			_tick_hunter(delta, fire_h, alt_h)
		"pyro":
			_tick_pyro(delta, fire_h, alt_h)


func _tick_knight(delta: float, fire_p: bool, alt_h: bool) -> void:
	var was := guard
	guard = alt_h and _swing < 0
	if guard and not was:
		guard_t = 0.0
		player._sfx("gear_rattle", -8.0)
	if guard:
		guard_t += delta
	_combo_t = maxf(0.0, _combo_t - delta)
	if _swing >= 0:
		var dur := float(SWINGS[_swing][0])
		_swing_t += delta / dur
		if fire_p and _swing_t > 0.35:
			_queued = true
		if not _swing_hit and _swing_t >= 0.42:
			_swing_hit = true
			_strike(_swing)
		if _swing_t >= 1.0:
			var nxt := _swing + 1
			_swing = -1
			_combo_t = 0.5
			if _queued and nxt < SWINGS.size():
				_start_swing(nxt)
			_queued = false
	elif fire_p and not guard:
		_start_swing(0 if _combo_t <= 0.0 else 0)


func _start_swing(i: int) -> void:
	_swing = i
	_swing_t = 0.0
	_swing_hit = false
	_queued = false
	if game != null and game.has_method("net_kit_shot"):
		game.net_kit_shot(player, "swing", player.global_position + Vector3.UP * 1.2, Vector3.ZERO)
	player._sfx("jump_whoosh", -6.0 if i < 2 else -2.0)


## The blade lands: everything in the arc in front is struck, on its real
## hitbox (a big boss is easy to hit, a small one is not).
func _strike(i: int) -> void:
	var dmg := float(SWINGS[i][1])
	var reach := float(SWINGS[i][2])
	var width := float(SWINGS[i][3])
	var heavy := bool(SWINGS[i][4])
	_show_trail(i)
	var hits := melee_targets(reach, width)
	var any := false
	for h in hits:
		var col: Object = h[0]
		var pos: Vector3 = h[1]
		var mult := 1.15 if Talismans.wears("crown") else 1.0
		var killed = col.call("take_damage", dmg * mult, pos, false, player)
		any = true
		if game != null:
			game.spawn_blood(pos)
		if col is Bot and not (col is Revenant):
			(col as Bot).stagger(0.9 if heavy else 0.45)
		elif col is Revenant and heavy:
			(col as Bot).stagger(0.35)
		player.kit_hit(pos, dmg * mult, false, killed is bool and killed)
	if any:
		player.add_trauma(0.22 if heavy else 0.12)
		_kick = 1.0
		player._sfx("hit_armor" if heavy else "hit_body", 2.0)
	elif heavy:
		player.add_trauma(0.08)


## What a blow of this reach and width in front of the eye would strike:
## [[collider, point], ...], each body once.
func melee_targets(reach: float, width: float) -> Array:
	var out_hits: Array = []
	var cam := player.camera
	var fwd := -cam.global_basis.z
	fwd.y = clampf(fwd.y, -0.5, 0.5)
	fwd = fwd.normalized()
	var origin := cam.global_position - Vector3.UP * 0.35
	var box := BoxShape3D.new()
	box.size = Vector3(width, 2.4, reach)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = 2 | 4
	q.exclude = [player.get_rid()]
	var b := Basis.looking_at(fwd, Vector3.UP)
	q.transform = Transform3D(b, origin + fwd * (reach * 0.5))
	var res := player.get_world_3d().direct_space_state.intersect_shape(q, 24)
	var seen := {}
	for r in res:
		var col: Object = r.collider
		if col == null or seen.has(col) or col == player:
			continue
		if not col.has_method("take_damage") or col.get("alive") != true:
			continue
		if col.get("friendly") == true:
			continue
		seen[col] = true
		var at: Vector3 = (col as Node3D).global_position + Vector3.UP * 1.2 if col is Node3D else origin + fwd * reach
		# The point on the body nearest the blade, roughly: towards the eye.
		var to := at - origin
		at = origin + to.normalized() * maxf(0.5, minf(to.length(), reach))
		out_hits.append([col, at])
	return out_hits


func _tick_hunter(delta: float, fire_h: bool, alt_h: bool) -> void:
	focus = alt_h
	if fire_h and _loose_t <= 0.0:
		if not drawing:
			drawing = true
			draw = 0.0
			player._sfx("gear_rattle", -12.0)
		draw = minf(1.0, draw + delta / (DRAW_TIME * (0.8 if focus else 1.0)))
	elif drawing:
		drawing = false
		if draw > 0.12:
			_loose(draw, 1)
		draw = 0.0


func _loose(k: float, n: int) -> void:
	var cam := player.camera
	var from := cam.global_position + cam.global_basis * Vector3(0.0, -0.05, -0.4)
	var fwd := -cam.global_basis.z
	var speed := lerpf(28.0, 88.0, k)
	var dmg := lerpf(16.0, 74.0, k * k)
	var sway := 0.0 if focus else 1.4 * (1.0 - k)
	for i in n:
		var spread := (float(i) - float(n - 1) * 0.5) * deg_to_rad(4.0)
		var d := fwd.rotated(cam.global_basis.y, spread)
		if sway > 0.0:
			d = d.rotated(cam.global_basis.x, deg_to_rad(randf_range(-sway, sway))).rotated(cam.global_basis.y, deg_to_rad(randf_range(-sway, sway)))
		KitShot.launch(game, player, "arrow", from, d * speed, dmg)
		if game != null and game.has_method("net_kit_shot"):
			game.net_kit_shot(player, "arrow", from, d * speed)
	_loose_t = 0.35
	_kick = 0.6
	player._sfx("jump_whoosh", -4.0)


func _tick_pyro(delta: float, fire_h: bool, alt_h: bool) -> void:
	var want_flame := alt_h and ember > 2.0
	if want_flame != flaming:
		flaming = want_flame
		if _flames != null:
			_flames.emitting = flaming
	if flaming:
		ember = maxf(0.0, ember - CONE_COST * delta)
		_ember_rest = 0.9
		_cone_tick -= delta
		if _cone_tick <= 0.0:
			_cone_tick = 0.1
			_burn_cone(CONE_DPS * 0.1)
		return
	if fire_h and _cast_t <= 0.0:
		if ember >= FIREBALL_COST:
			ember -= FIREBALL_COST
			_ember_rest = 0.9
			_cast_t = 0.42
			var cam := player.camera
			var from := cam.global_position + cam.global_basis * Vector3(0.18, -0.08, -0.7)
			var aim_at := cam.global_position - cam.global_basis.z * 60.0
			var q := PhysicsRayQueryParameters3D.create(cam.global_position, aim_at, Ballistics.MASK)
			q.exclude = [player.get_rid()]
			var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty():
				aim_at = hit.position
			var d := (aim_at - from).normalized()
			KitShot.launch(game, player, "fire", from, d * 36.0, 42.0)
			if game != null and game.has_method("net_kit_shot"):
				game.net_kit_shot(player, "fire", from, d * 36.0)
			_kick = 0.8
			player._sfx("explosion", -16.0)
		else:
			_cast_t = 0.3
			player.notice.emit("NOT ENOUGH EMBER")


## Everything in a short cone in front catches fire.
func _burn_cone(dmg: float) -> void:
	var cam := player.camera
	var eye := cam.global_position
	var fwd := -cam.global_basis.z
	for t in KitShot._reach_targets(game, player):
		var n := t as Node3D
		var c := n.global_position + Vector3.UP * 1.0
		var to := c - eye
		var d := to.length() - KitShot._reach(n)
		if d > CONE_RANGE:
			continue
		if to.normalized().dot(fwd) < cos(deg_to_rad(28.0)) and d > 1.2:
			continue
		var q := PhysicsRayQueryParameters3D.create(eye, c, 1)
		if not player.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			continue
		var killed = n.call("take_damage", dmg, c, false, player)
		player.kit_hit(c, dmg, false, killed is bool and killed)


# --------------------------------------------------------------- ability --
func use_ability() -> bool:
	if ability_cd > 0.0:
		return false
	var cd := float(Classes.def(cls).get("cd", 8.0))
	match cls:
		"knight":
			player.start_charge()
		"hunter":
			_loose(1.0, 3)
		"pyro":
			player.blink_cd = 0.0
			player._blink()
		"gunslinger":
			if not player.has_gun():
				return false
			player.quickdraw()
	ability_cd = cd
	return true


func on_kill() -> void:
	if cls == "pyro":
		ember = minf(EMBER_MAX, ember + 45.0)


## A blow lands while you guard. Returns the share of it you still take.
func guard_taken(from_pos: Vector3) -> float:
	if not out or cls != "knight" or not guard:
		return 1.0
	var to := from_pos - player.global_position
	to.y = 0.0
	if to.length() < 0.05:
		return 1.0
	var fwd := -player.camera.global_basis.z
	fwd.y = 0.0
	if to.normalized().dot(fwd.normalized()) < cos(deg_to_rad(75.0)):
		return 1.0
	if guard_t <= PARRY_WINDOW:
		_parried_t = 0.25
		return 0.0
	return GUARD_TAKEN


func parried_now() -> bool:
	return _parried_t > 0.0


# ------------------------------------------------------------------ view --
func view_tick(delta: float) -> void:
	visible = out
	if not out:
		_equip = 0.0
		return
	_equip = minf(1.0, _equip + delta / 0.35)
	_kick = move_toward(_kick, 0.0, delta * 5.0)
	var tt := Time.get_ticks_msec() * 0.001
	var move_k := clampf(Vector2(player.velocity.x, player.velocity.z).length() / Player.SPRINT, 0.0, 1.0)
	var bob := Vector3(cos(player.bob) * 0.012, -absf(sin(player.bob)) * 0.014, 0.0) * move_k
	var breathe := Vector3(0, sin(tt * 1.6) * 0.004, 0)
	var sway := Vector3(-player.sway.x * 0.5, -player.sway.y * 0.35, 0)
	var e := _equip * _equip * (3.0 - 2.0 * _equip)
	var pos := Vector3.ZERO
	var rot := Vector3.ZERO
	match cls:
		"knight":
			var pr := _knight_pose()
			pos = pr[0]
			rot = pr[1]
			if _shield != null:
				var g := 1.0 if guard else 0.0
				var sp := Vector3(-0.42, -0.42, -0.5).lerp(Vector3(-0.08, -0.12, -0.42), g)
				var sr := Vector3(0.1, 0.5, 0.15).lerp(Vector3(0.0, 0.1, 0.0), g)
				if _parried_t > 0.0:
					sp += Vector3(0.03, 0.04, 0.05)
				_shield.scale = Vector3.ONE * 0.48
				_shield.position = _shield.position.lerp(sp + bob * 0.6 + sway * 0.5, clampf(delta * 14.0, 0.0, 1.0))
				_shield.rotation = _shield.rotation.lerp(sr, clampf(delta * 14.0, 0.0, 1.0))
		"hunter":
			var dk := draw * draw * (3.0 - 2.0 * draw)
			pos = Vector3(-0.05, -0.1, -0.55).lerp(Vector3(-0.02, -0.04, -0.5), dk)
			rot = Vector3(0.0, 0.05, 0.32).lerp(Vector3(0.0, 0.0, 0.12), dk)
			if focus:
				pos.x += 0.03
			pos.z += _kick * 0.06
			rot.x += _kick * 0.12
			# A full draw shivers.
			if draw >= 1.0:
				pos += Vector3(sin(tt * 38.0), cos(tt * 31.0), 0) * 0.0015
			_update_string(dk)
		"pyro":
			pos = Vector3(0.3, -0.62, -0.62)
			rot = Vector3(-0.15, 0.1, -0.1)
			var c := clampf(_cast_t / 0.42, 0.0, 1.0)
			var thrust := sin(c * PI)
			pos += Vector3(-0.05, 0.06, -0.12) * thrust
			rot += Vector3(-0.35, 0.0, 0.05) * thrust
			if flaming:
				pos += Vector3(-0.08, 0.1, -0.05) + Vector3(sin(tt * 40.0), cos(tt * 33.0), 0) * 0.004
				rot += Vector3(-0.85, 0.15, 0.1)
			if _orb_mat != null:
				var lvl := ember / EMBER_MAX
				_orb_mat.emission_energy_multiplier = 1.5 + lvl * 5.0 + sin(tt * 6.0) * 0.6
				_orb_light.light_energy = 0.3 + lvl * 0.8
	pos += bob + breathe + sway
	pos.y -= (1.0 - e) * 0.35
	rot.x -= (1.0 - e) * 0.8
	_pivot.position = pos
	_pivot.rotation = rot
	_pivot.scale = Vector3.ONE * VIEW_SCALE.get(cls, 0.5)
	if _trail_t > 0.0:
		_trail_t -= delta
		_trail_mat.albedo_color.a = clampf(_trail_t / 0.16, 0.0, 1.0) * 0.8
		if _trail_t <= 0.0:
			_trail.visible = false


## The sword's pose: at rest on the shoulder, or partway through a swing.
func _knight_pose() -> Array:
	var rest_p := Vector3(0.32, -0.42, -0.42)
	var rest_r := Vector3(-0.55, 0.0, 0.42)
	if guard:
		return [Vector3(0.36, -0.58, -0.36), Vector3(-1.0, 0.2, 1.05)]
	if _swing < 0:
		return [rest_p, rest_r]
	var t := _swing_t
	var keys: Array
	match _swing:
		0:
			# Right to left, flat.
			keys = [[0.0, rest_p, rest_r], [0.3, Vector3(0.48, -0.25, -0.35), Vector3(-1.25, 0.2, -1.55)],
				[0.55, Vector3(-0.32, -0.33, -0.55), Vector3(-1.35, -0.1, 1.45)], [1.0, rest_p, rest_r]]
		1:
			# Back from the left, rising a little.
			keys = [[0.0, rest_p, rest_r], [0.3, Vector3(-0.38, -0.42, -0.4), Vector3(-1.2, -0.2, 1.6)],
				[0.55, Vector3(0.42, -0.2, -0.55), Vector3(-1.5, 0.15, -1.35)], [1.0, rest_p, rest_r]]
		_:
			# Overhead, heavy.
			keys = [[0.0, rest_p, rest_r], [0.4, Vector3(0.12, -0.05, -0.2), Vector3(0.65, 0.0, 0.15)],
				[0.58, Vector3(0.05, -0.55, -0.65), Vector3(-2.0, 0.0, 0.05)], [1.0, rest_p, rest_r]]
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if t <= float(b[0]):
			var k := clampf((t - float(a[0])) / maxf(0.001, float(b[0]) - float(a[0])), 0.0, 1.0)
			# The cut itself is fast; wind-up and recovery are eased.
			k = k * k * (3.0 - 2.0 * k)
			return [(a[1] as Vector3).lerp(b[1], k), (a[2] as Vector3).lerp(b[2], k)]
	return [rest_p, rest_r]


func busy() -> bool:
	return _swing >= 0 or drawing or flaming or _cast_t > 0.0
