extends RefCounted
class_name Fantasy

## Fantasy set pieces scattered over the island: the Arcane Spire (a mage
## tower with a floating crystal), Crystal Hollows, Dragon's Rest (a giant
## skeleton to fight through) and the Faerie Grove (giant mushrooms you can
## climb cap to cap). Built with the landmark primitives; every collider is
## the exact shape you see (convex hulls of the same vertices).

var lm: Landmarks
var terrain: Terrain
var villages: Villages
var rng := RandomNumberGenerator.new()
var sites: Array = []
## Where each set piece stands: name -> [centre, ground height].
var poi: Dictionary = {}
## Treetop Town, the giant tree (null if the island had no room for it).
var tree_town: TreeTown


func build(p_lm: Landmarks, p_seed: int) -> void:
	lm = p_lm
	terrain = lm.terrain
	villages = lm.villages
	rng.seed = p_seed + 7777
	_materials()
	var spire := _site(16.0, 10.0)
	if spire != Vector2.INF:
		_build_spire(spire)
	for i in 2:
		var hc := _site(22.0, 3.0)
		if hc != Vector2.INF:
			_build_crystals(hc, i)
	var dragon := _site(26.0, 3.0)
	if dragon != Vector2.INF:
		_build_dragon(dragon)
	var grove := _site(20.0, 3.0)
	if grove != Vector2.INF:
		_build_grove(grove)
	var town := _site(46.0, 4.0)
	if town == Vector2.INF:
		town = _site(38.0, 3.0)
	if town != Vector2.INF:
		tree_town = TreeTown.new()
		tree_town.build(self, town)
	_build_farms()


# ------------------------------------------------------------------ helpers

func _materials() -> void:
	var defs := {
		"crystal_cyan": [Color(0.12, 0.62, 0.95), Color(0.08, 0.55, 1.0), 1.25],
		"crystal_violet": [Color(0.5, 0.2, 0.92), Color(0.5, 0.18, 1.0), 1.35],
		"rune": [Color(0.4, 0.85, 1.0), Color(0.3, 0.75, 1.0), 3.0],
		"glowcap": [Color(0.1, 0.85, 0.7), Color(0.05, 0.9, 0.7), 0.9],
		"eye": [Color(0.75, 0.3, 1.0), Color(0.7, 0.2, 1.0), 4.0],
	}
	for k in defs:
		var d: Array = defs[k]
		var m := StandardMaterial3D.new()
		m.albedo_color = d[0]
		m.emission_enabled = true
		m.emission = d[1]
		m.emission_energy_multiplier = float(d[2])
		m.metallic = 0.2
		m.roughness = 0.12
		m.rim_enabled = true
		m.rim = 0.6
		lm._mats[k] = m
	var bone := StandardMaterial3D.new()
	bone.albedo_color = Color(0.97, 0.94, 0.86)
	bone.roughness = 0.55
	bone.albedo_texture = load("res://assets/village/T_Plaster_BaseColor.png")
	bone.uv1_triplanar = true
	bone.uv1_world_triplanar = true
	bone.uv1_scale = Vector3.ONE * 0.8
	lm._mats["bone"] = bone
	var slate := lm._tex_mat("RoundTiles", 0.45, Color(1, 1, 1))
	# The tile texture is red: use its relief only, coloured deep arcane blue.
	slate.albedo_texture = null
	slate.albedo_color = Color(0.2, 0.26, 0.56)
	slate.roughness = 0.62
	slate.metallic = 0.15
	lm._mats["roof_arcane"] = slate
	for k in ["cap_red", "cap_spot", "stem", "gill"]:
		var m := StandardMaterial3D.new()
		m.albedo_color = {"cap_red": Color(0.8, 0.12, 0.1), "cap_spot": Color(0.98, 0.96, 0.9), "stem": Color(0.96, 0.9, 0.78), "gill": Color(0.62, 0.46, 0.4)}[k]
		m.roughness = 0.7 if k != "cap_red" else 0.45
		if k == "cap_red":
			m.clearcoat_enabled = true
			m.clearcoat = 0.4
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * 0.5
		lm._mats[k] = m


## A clear, gentle spot of land away from towns, landmarks and roads.
## Strict first, then a little less picky so every set piece gets a home.
func _site(radius: float, min_h: float) -> Vector2:
	for pass_i in 3:
		var c := _site_pass(radius, min_h, 1.0 - float(pass_i) * 0.25)
		if c != Vector2.INF:
			return c
	push_warning("Fantasy: no site for radius %.0f" % radius)
	return Vector2.INF


func _site_pass(radius: float, min_h: float, k: float) -> Vector2:
	for i in 3000:
		var c := terrain.random_land_point(rng, min_h, 0.22)
		if c == Vector2.INF or terrain.is_reserved(c, radius + 25.0):
			continue
		if villages._too_close(c, (radius + 70.0) * k, (radius + 80.0) * k):
			continue
		if terrain.roughness(c.x, c.y, radius) > 3.2 / k or villages.road_distance(c.x, c.y) < radius + 6.0:
			continue
		if bool(terrain.is_water(c.x, c.y)):
			continue
		var ok := true
		for a in lm.clear_areas:
			if c.distance_to(a.center) < (radius + float(a.radius) + 60.0) * k:
				ok = false
				break
		for s in sites:
			if c.distance_to(s) < (radius + 220.0) * k:
				ok = false
				break
		if not ok:
			continue
		sites.append(c)
		return c
	return Vector2.INF


func _claim(c: Vector2, radius: float, label: String, type: String) -> float:
	var pad := terrain.flatten_circle(c.x, c.y, radius * 0.8, radius * 0.7)
	poi[type + ("2" if poi.has(type) else "")] = [c, pad]
	lm.labels.append([label, c + Vector2(0, -radius - 10.0)])
	lm.clear_areas.append({"center": c, "radius": radius})
	villages.poi_pads.append({"center": c, "radius": radius, "type": type})
	return pad


## Convex collider made of exactly these points (matches the drawn hull).
func _hull(points: PackedVector3Array) -> void:
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	cs.shape = shape
	lm._body.add_child(cs)
	lm._stat.shapes += 1


## Pointed prism (crystal) standing on `base` along basis.y.
func prism(base: Vector3, b: Basis, r: float, h: float, tip: float, sides: int, mat: String, collide := true) -> void:
	var st := lm._surface(mat)
	var bot: Array[Vector3] = []
	var top: Array[Vector3] = []
	var pts := PackedVector3Array()
	var ax := b.y.normalized()
	for i in sides:
		var a := TAU * float(i) / float(sides)
		var d := (b.x.normalized() * cos(a) + b.z.normalized() * sin(a))
		bot.append(base + d * r)
		top.append(base + d * r * 0.92 + ax * h)
	var apex := base + ax * (h + tip)
	for i in sides:
		var j := (i + 1) % sides
		var am := TAU * (float(i) + 0.5) / float(sides)
		var n := (b.x.normalized() * cos(am) + b.z.normalized() * sin(am)).normalized()
		lm._quad(st, bot[j], bot[i], top[i], top[j], n)
		var tn := (top[i] - apex).cross(top[j] - apex).normalized()
		if tn.dot(n + ax) < 0.0:
			tn = -tn
		lm._tri(st, apex, top[i], top[j], tn)
		lm._tri(st, base, bot[j], bot[i], -ax)
		pts.append(bot[i])
		pts.append(top[i])
	pts.append(apex)
	if collide:
		_hull(pts)


## Round solid of revolution from a profile of [radius, height] pairs
## (bottom to top), e.g. a mushroom cap. Convex profiles collide exactly.
func lathe(base: Vector3, profile: Array, sides: int, mat: String, collide := true) -> void:
	var st := lm._surface(mat)
	var pts := PackedVector3Array()
	for k in profile.size() - 1:
		var r0 := float(profile[k][0])
		var y0 := float(profile[k][1])
		var r1 := float(profile[k + 1][0])
		var y1 := float(profile[k + 1][1])
		for i in sides:
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			var dm := Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
			var n := (dm * (y1 - y0) + Vector3.UP * (r0 - r1)).normalized()
			var p00 := base + d0 * r0 + Vector3.UP * y0
			var p01 := base + d1 * r0 + Vector3.UP * y0
			var p10 := base + d0 * r1 + Vector3.UP * y1
			var p11 := base + d1 * r1 + Vector3.UP * y1
			if r1 < 0.001:
				lm._tri(st, p00, p01, p10, n)
			else:
				lm._quad(st, p01, p00, p10, p11, n)
	for k in profile.size():
		for i in sides:
			var a := TAU * float(i) / float(sides)
			pts.append(base + Vector3(cos(a) * float(profile[k][0]), float(profile[k][1]), sin(a) * float(profile[k][0])))
	# Underside.
	var r0b := float(profile[0][0])
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		lm._tri(st, base, base + Vector3(cos(a1), 0, sin(a1)) * r0b, base + Vector3(cos(a0), 0, sin(a0)) * r0b, Vector3.DOWN)
	if collide:
		_hull(pts)


func _light(p: Vector3, color: Color, energy: float, rng_m: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng_m
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = 160.0
	l.distance_fade_length = 60.0
	l.position = p
	lm._group.add_child(l)


## A node that turns slowly and bobs (for floating crystals).
func _floater(p: Vector3, spin_s: float, bob: float) -> Node3D:
	var n := Node3D.new()
	n.position = p
	lm._group.add_child(n)
	var tw := n.create_tween().set_loops()
	tw.tween_property(n, "rotation:y", TAU, spin_s).from(0.0)
	var tb := n.create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tb.tween_property(n, "position:y", p.y + bob, spin_s * 0.25)
	tb.tween_property(n, "position:y", p.y, spin_s * 0.25)
	return n


## Mesh of a crystal for a floater (not batched: it moves).
func _crystal_mesh(r: float, h: float, tip: float, mat: String) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 6
	for half in [1.0, -1.0]:
		for i in sides:
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			var b0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
			var b1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
			var t0 := b0 * 0.9 + Vector3.UP * h * 0.5 * float(half)
			var t1 := b1 * 0.9 + Vector3.UP * h * 0.5 * float(half)
			var apex := Vector3.UP * (h * 0.5 + tip) * float(half)
			var n := Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
			lm._quad(st, b1, b0, t0, t1, n)
			lm._tri(st, apex, t0, t1, (n + Vector3.UP * float(half)).normalized())
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = lm._mats[mat]
	mi.visibility_range_end = 900.0
	return mi


# -------------------------------------------------------------- Arcane Spire

func _build_spire(c: Vector2) -> void:
	lm._begin("ArcaneSpire")
	var gy := _claim(c, 16.0, "ARCANE SPIRE", "spire")
	var o := Vector3(c.x, gy, c.y)
	var height := 26.0
	# Plinth with a ring of glowing runes.
	lm.cyl(o - Vector3(0, 1.2, 0), 8.0, 8.0, 1.9, "dark", 24)
	for i in 16:
		var a := TAU * float(i) / 16.0
		lm.box(o + Vector3(cos(a) * 7.0, 0.72, sin(a) * 7.0), Vector3(0.9, 0.05, 0.35), -a, "rune", false)
	# The tower: banded stone tapering upward.
	var bands := 8
	for i in bands:
		var y0 := height * float(i) / float(bands)
		var r0 := lerpf(3.8, 3.0, float(i) / float(bands))
		var r1 := lerpf(3.8, 3.0, float(i + 1) / float(bands))
		lm.cyl(o + Vector3(0, y0, 0), r0, r1, height / float(bands), "stone" if i % 3 != 2 else "trim", 20, false)
		# Narrow glowing slits.
		if i % 2 == 1:
			for k in 4:
				var a := TAU * float(k) / 4.0 + float(i) * 0.4
				var rr := (r0 + r1) * 0.5 + 0.02
				lm.box_b(Basis(Vector3.UP, -a + PI * 0.5), o + Vector3(cos(a) * rr, y0 + 1.6, sin(a) * rr), Vector3(0.3, 1.2, 0.08), "crystal_violet", false)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 3.7
	shape.height = height
	cs.shape = shape
	cs.position = o + Vector3(0, height * 0.5, 0)
	lm._body.add_child(cs)
	# A spiral stair around the outside, two and a half turns.
	var deck := height + 0.5
	var turns := 2.5
	var segs := 80
	var hr := 5.3
	var start_a := rng.randf() * TAU
	var end_a := start_a + TAU * turns
	for i in segs:
		var a0 := lerpf(start_a, end_a, float(i) / float(segs))
		var a1 := lerpf(start_a, end_a, float(i + 1) / float(segs))
		var y0 := lerpf(0.75, deck, float(i) / float(segs))
		var y1 := lerpf(0.75, deck, float(i + 1) / float(segs))
		var p0 := o + Vector3(cos(a0) * hr, y0, sin(a0) * hr)
		var p1 := o + Vector3(cos(a1) * hr, y1, sin(a1) * hr)
		var dv := p1 - p0
		var hb := lm._frame(dv)
		lm.box_b(hb, (p0 + p1) * 0.5 - hb.y * 0.18, Vector3(1.8, 0.36, dv.length() + 0.25), "trim")
		if i % 2 == 0:
			var outer := Vector3(cos(a0), 0, sin(a0))
			lm.box(p0 + outer * 0.85 + Vector3(0, 0.55, 0), Vector3(0.12, 1.1, 0.12), -a0, "iron", false)
			if i % 4 == 0:
				lm.box(p0 + outer * 0.85 + Vector3(0, 1.15, 0), Vector3(0.22, 0.22, 0.22), -a0, "crystal_cyan", false)
			var tr := lerpf(3.8, 3.0, clampf(y0 / height, 0.0, 1.0))
			var bl := hr - 0.9 - tr
			if bl > 0.05:
				lm.box(o + outer * (tr + bl * 0.5) + Vector3(0, y0 - 0.32, 0), Vector3(bl + 0.2, 0.3, 0.3), -a0, "iron", false)
	# Top: a round deck and an open pavilion under a pointed blue roof.
	poi["spire_stair"] = [o, hr, start_a, end_a, deck]
	# The deck stops at the stair's inner edge so the flight arrives beside it,
	# not underneath it.
	lm.cyl(o + Vector3(0, height, 0), 4.7, 4.7, 0.5, "trim", 28)
	var rail_n := 28
	for i in rail_n:
		var a0 := TAU * float(i) / float(rail_n)
		if absf(wrapf(a0 - end_a, -PI, PI)) < 0.45:
			continue
		var a1 := TAU * float(i + 1) / float(rail_n)
		var q0 := Vector2(c.x + cos(a0) * 4.55, c.y + sin(a0) * 4.55)
		var q1 := Vector2(c.x + cos(a1) * 4.55, c.y + sin(a1) * 4.55)
		var m := (q0 + q1) * 0.5
		lm.box(Vector3(m.x, gy + deck + 0.5, m.y), Vector3(0.3, 1.0, q0.distance_to(q1) + 0.08), atan2(q1.x - q0.x, q1.y - q0.y), "trim")
	for i in 6:
		var a := TAU * float(i) / 6.0 + 0.3
		lm.cyl(o + Vector3(cos(a) * 3.85, deck, sin(a) * 3.85), 0.28, 0.24, 4.2, "trim", 10)
	lm.cyl(o + Vector3(0, deck + 4.2, 0), 4.5, 4.3, 0.5, "trim", 24)
	lm.cyl(o + Vector3(0, deck + 4.7, 0), 5.2, 0.0, 9.0, "roof_arcane", 24, false)
	lm.cyl(o + Vector3(0, deck + 13.5, 0), 0.22, 0.0, 1.6, "gold", 8, false)
	# Pedestal with the floating crystal.
	lm.cyl(o + Vector3(0, deck, 0), 0.9, 0.6, 1.1, "dark", 12)
	var fl := _floater(o + Vector3(0, deck + 2.6, 0), 9.0, 0.35)
	fl.add_child(_crystal_mesh(0.55, 1.4, 0.7, "crystal_violet"))
	_light(o + Vector3(0, deck + 2.6, 0), Color(0.7, 0.45, 1.0), 2.6, 16.0)
	_light(o + Vector3(0, 1.6, 0) + Vector3(cos(start_a) * 7.0, 0, sin(start_a) * 7.0), Color(0.4, 0.8, 1.0), 1.4, 10.0)
	# Loot: the best on top, more at the foot.
	lm._loot(o + Vector3(2.4, deck, 0), "weapon", true)
	lm._loot(o + Vector3(-2.0, deck, 1.1), "gear", true)
	lm._loot(o + Vector3(0.7, deck, -2.3), "gear", true)
	lm._loot(o + Vector3(cos(start_a + PI) * 9.5, 0.75, sin(start_a + PI) * 9.5), "weapon")
	lm._loot(o + Vector3(cos(start_a + 2.0) * 9.5, 0.75, sin(start_a + 2.0) * 9.5), "gear")
	# Standing stones with crystals around the plinth.
	for i in 5:
		var a := TAU * float(i) / 5.0 + 0.6
		var p := o + Vector3(cos(a) * 12.5, -0.3, sin(a) * 12.5)
		p.y = terrain.height_at(p.x, p.z) - 0.2
		lm.box(p + Vector3(0, 1.5, 0), Vector3(1.1, 3.4, 0.8), -a, "dark")
		prism(p + Vector3(0, 3.2, 0), Basis(Vector3.UP, a), 0.32, 0.7, 0.5, 6, "crystal_cyan", false)
	lm._end(2400.0)


# ------------------------------------------------------------ Crystal Hollow

func _build_crystals(c: Vector2, idx: int) -> void:
	lm._begin("CrystalHollow%d" % idx)
	var gy := _claim(c, 22.0, ["CRYSTAL HOLLOW", "SHIMMERDEEP"][idx % 2], "crystals")
	var o := Vector3(c.x, gy, c.y)
	var mats := ["crystal_cyan", "crystal_violet"]
	var clusters := 13
	for k in clusters:
		var a := TAU * float(k) / float(clusters) + rng.randf_range(-0.2, 0.2)
		var d := rng.randf_range(4.0, 18.0) if k > 0 else 0.0
		var p := o + Vector3(cos(a) * d, 0, sin(a) * d)
		p.y = terrain.height_at(p.x, p.z) - 0.3
		var big := k == 0 or rng.randf() < 0.3
		var mat: String = mats[(k + idx) % 2]
		var n := rng.randi_range(4, 7)
		for j in n:
			var tilt := rng.randf_range(0.0, 0.55) if j > 0 else rng.randf_range(0.0, 0.12)
			var spin := rng.randf() * TAU
			var b := Basis(Vector3.UP, spin) * Basis(Vector3.RIGHT, tilt)
			var r := rng.randf_range(0.5, 1.1) * (1.7 if big and j == 0 else 1.0)
			var h := rng.randf_range(2.4, 5.5) * (2.1 if big and j == 0 else 1.0)
			prism(p + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6)), b, r, h, r * 1.6, 6, mat)
		# Little shards around the base (no collision).
		for j in 5:
			var sa := rng.randf() * TAU
			var sp := p + Vector3(cos(sa), 0, sin(sa)) * rng.randf_range(1.2, 2.6)
			sp.y = terrain.height_at(sp.x, sp.z) - 0.1
			prism(sp, Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(0.1, 0.7)), 0.1, rng.randf_range(0.25, 0.6), 0.15, 5, mat, false)
		if k % 4 == 0:
			_light(p + Vector3(0, 2.5, 0), Color(0.4, 0.85, 1.0) if mat == "crystal_cyan" else Color(0.7, 0.45, 1.0), 1.8, 14.0)
		if k % 3 == 0:
			lm._loot(p + Vector3(cos(a) * 2.4, 0.4, sin(a) * 2.4), "weapon" if k % 2 == 0 else "gear", k == 0)
	# A floating crystal over the heart of the hollow.
	var fl := _floater(o + Vector3(0, 11.0, 0), 12.0, 0.6)
	fl.add_child(_crystal_mesh(0.9, 2.6, 1.2, mats[idx % 2]))
	_light(o + Vector3(0, 10.0, 0), Color(0.5, 0.8, 1.0), 2.0, 22.0)
	lm._end(1800.0)


# -------------------------------------------------------------- Dragon's Rest

func _build_dragon(c: Vector2) -> void:
	lm._begin("DragonsRest")
	var gy := _claim(c, 26.0, "DRAGON'S REST", "dragon")
	var yaw := rng.randf() * TAU
	var fwd := Vector3(cos(yaw), 0, sin(yaw))
	var side := Vector3(-fwd.z, 0, fwd.x)
	var o := Vector3(c.x, gy, c.y)
	# Spine: an arch over the ribcage, falling away into a long curled tail.
	var n := 46
	var spine: Array[Vector3] = []
	for i in n:
		var t := float(i) / float(n - 1)
		var along := lerpf(18.0, -24.0, t)
		var curl := sin(t * PI * 1.4) * 5.0 * t
		var hgt := 0.0
		if t < 0.12:
			hgt = lerpf(1.6, 4.2, t / 0.12)
		elif t < 0.45:
			hgt = 4.2 + sin((t - 0.12) / 0.33 * PI) * 1.2
		else:
			hgt = lerpf(4.2, 0.35, clampf((t - 0.45) / 0.4, 0.0, 1.0))
		spine.append(o + fwd * along + side * curl + Vector3.UP * hgt)
	for i in n - 1:
		var a := spine[i]
		var b := spine[i + 1]
		var sz := lerpf(1.1, 0.35, float(i) / float(n - 1))
		var fb := lm._frame(b - a)
		lm.box_b(fb, (a + b) * 0.5, Vector3(sz, sz, a.distance_to(b) * 0.82), "bone")
		# Dorsal spikes.
		if i % 2 == 0 and i < n - 6:
			prism((a + b) * 0.5 + fb.y * sz * 0.4, fb, sz * 0.22, sz * 0.9, sz * 0.5, 4, "bone", false)
	# Ribs: curved bones from the spine down to the ground, both sides.
	for i in range(4, 17):
		var s := spine[i]
		var rib_len := lerpf(6.5, 3.5, absf(float(i) - 9.0) / 8.0)
		for sgn in [-1.0, 1.0]:
			var prev := s
			var segs := 7
			for k in segs:
				var t := float(k + 1) / float(segs)
				var out := sin(t * PI * 0.62) * rib_len * 0.75
				var down := (1.0 - cos(t * PI * 0.5)) * (s.y - gy + 0.25)
				var p := s + side * float(sgn) * out - Vector3.UP * down
				var th := lerpf(0.42, 0.22, t)
				lm.box_b(lm._frame(p - prev), (p + prev) * 0.5, Vector3(th, th, prev.distance_to(p) + 0.12), "bone")
				prev = p
	# Skull at the head end: cranium, long snout, open jaw, horns.
	var head := spine[0] + fwd * 2.2 - Vector3.UP * 0.6
	var hb := Basis(side, Vector3.UP, fwd)
	lm.box_b(hb, head, Vector3(2.4, 1.9, 2.6), "bone")
	# Long tapering snout and lower jaw (four-sided prisms, point forward).
	prism(head + fwd * 1.0 + Vector3.UP * 0.1, Basis(side.rotated(fwd, PI * 0.25), fwd, Vector3.UP.rotated(fwd, PI * 0.25)), 1.0, 2.6, 1.2, 4, "bone")
	prism(head + fwd * 0.9 - Vector3.UP * 0.95, Basis(side, (fwd - Vector3.UP * 0.25).normalized(), Vector3.UP), 0.7, 2.8, 0.8, 4, "bone")
	# Brow ridge.
	lm.box_b(hb, head + Vector3.UP * 0.95 + fwd * 0.4, Vector3(2.7, 0.35, 1.1), "bone")
	for sgn in [-1.0, 1.0]:
		# Eye sockets and horns sweeping back.
		lm.box_b(hb, head + side * float(sgn) * 0.95 + Vector3.UP * 0.35 + fwd * 0.6, Vector3(0.6, 0.55, 0.6), "dark", false)
		lm.box_b(hb, head + side * float(sgn) * 1.24 + Vector3.UP * 0.35 + fwd * 0.6, Vector3(0.05, 0.28, 0.3), "eye", false)
		var hbase := head + side * float(sgn) * 0.9 + Vector3.UP * 0.8 - fwd * 0.6
		# Horns sweep back and out from the brow.
		var hdir := (-fwd * 1.0 + Vector3.UP * 0.32 + side * float(sgn) * 0.45).normalized()
		var hbs := Basis(hdir.cross(Vector3.UP).normalized(), hdir, hdir.cross(Vector3.UP).normalized().cross(hdir))
		prism(hbase, hbs, 0.36, 2.8, 1.6, 6, "bone")
		# Teeth.
		for k in 4:
			prism(head + fwd * (1.3 + float(k) * 0.6) + side * float(sgn) * (0.55 - float(k) * 0.08) - Vector3.UP * 0.55, Basis(Vector3.RIGHT, PI), 0.1, 0.25, 0.3, 4, "bone", false)
	# A half-buried wing: arm bones and fanned finger bones.
	for sgn in [-1.0, 1.0]:
		var shoulder := spine[6] + side * float(sgn) * 1.0
		var elbow := shoulder + side * float(sgn) * 6.0 + fwd * 2.0 + Vector3.UP * (2.5 if sgn > 0.0 else -2.0)
		elbow.y = maxf(elbow.y, gy + 0.4)
		lm.box_b(lm._frame(elbow - shoulder), (shoulder + elbow) * 0.5, Vector3(0.55, 0.55, shoulder.distance_to(elbow)), "bone")
		for k in 4:
			var tip := elbow + side * float(sgn) * (5.0 + float(k)) - fwd * (float(k) * 3.2 - 2.0)
			tip.y = gy + 0.2
			lm.box_b(lm._frame(tip - elbow), (elbow + tip) * 0.5, Vector3(0.3, 0.3, elbow.distance_to(tip)), "bone")
	# Claws and scattered bones, a few stones half sunk in the earth.
	for k in 8:
		var a := rng.randf() * TAU
		var p := o + Vector3(cos(a), 0, sin(a)) * rng.randf_range(8.0, 20.0)
		p.y = terrain.height_at(p.x, p.z)
		lm.box(p + Vector3(0, 0.25, 0), Vector3(0.45, 0.45, rng.randf_range(1.2, 2.6)), rng.randf() * TAU, "bone")
	_light(head + Vector3.UP * 0.4 + fwd * 0.6, Color(0.7, 0.3, 1.0), 1.6, 7.0)
	lm._loot(spine[9] - Vector3.UP * (spine[9].y - gy) + side * 1.5 + Vector3.UP * 0.1, "weapon", true)
	lm._loot(spine[13] - Vector3.UP * (spine[13].y - gy) - side * 1.8 + Vector3.UP * 0.1, "gear", true)
	lm._loot(head - Vector3.UP * (head.y - gy) - side * 3.0 + Vector3.UP * 0.1, "gear")
	lm._loot(o - fwd * 10.0 + side * 4.0 + Vector3.UP * 0.1, "weapon")
	lm._end(2000.0)


# -------------------------------------------------------------- Faerie Grove

## Cap height above its rim.
const CAP_H := 1.12


## Cap profile: steep rim you can grab, then a gentle top you can stand on.
func _cap(base: Vector3, r: float, mat_spots := true) -> void:
	lathe(base, [[r, 0.0], [r * 0.96, 0.7], [r * 0.7, 0.95], [r * 0.35, 1.08], [0.0, CAP_H]], 20, "cap_red")
	lm.cyl(base - Vector3(0, 0.06, 0), r * 0.92, r * 0.92, 0.06, "gill", 20, false)
	if mat_spots:
		for i in int(r * 3.0):
			var a := rng.randf() * TAU
			var t := rng.randf_range(0.25, 0.85)
			var rr := lerpf(r * 0.4, r * 0.92, t)
			var yy := lerpf(1.08, 0.72, t)
			var sr := clampf(r * 0.13, 0.12, 0.55)
			lathe(base + Vector3(cos(a) * rr, yy - 0.04, sin(a) * rr), [[sr, 0.0], [sr * 0.7, 0.07], [0.0, 0.1]], 8, "cap_spot", false)


func _build_grove(c: Vector2) -> void:
	lm._begin("FaerieGrove")
	var gy := _claim(c, 20.0, "FAERIE GROVE", "grove")
	var o := Vector3(c.x, gy, c.y)
	# The great mushroom in the middle: its cap is the lookout.
	var step_tops: Array[float] = []
	for k in 6:
		step_tops.append(1.3 + float(k) * (CAP_H + 0.1))
	var top_c := step_tops[5] + 0.1 + CAP_H
	var big_r := 5.0
	lm.cyl(o, 1.6, 1.25, top_c - CAP_H, "stem", 16)
	_cap(o + Vector3(0, top_c - CAP_H, 0), big_r)
	# A spiral of steps: each cap's rim sits just above the last cap's top,
	# so you climb by vaulting from one to the next.
	var start := rng.randf() * TAU
	var sr := 1.6
	var ring := big_r + sr + 0.45
	var arc := (2.0 * sr + 0.45) / ring
	var climb: Array = []
	for k in step_tops.size():
		var a := start + arc * float(k)
		var p := o + Vector3(cos(a) * ring, 0, sin(a) * ring)
		p.y = gy
		var tp: float = step_tops[k]
		lm.cyl(p, 0.55, 0.45, tp - CAP_H, "stem", 12)
		_cap(p + Vector3(0, tp - CAP_H, 0), sr)
		climb.append([p + Vector3(0, tp, 0), sr])
	climb.append([o + Vector3(0, top_c, 0), big_r])
	poi["grove_climb"] = climb
	# Wild mushrooms around, some glowing.
	for k in 18:
		var a := rng.randf() * TAU
		var d := rng.randf_range(9.5, 19.0)
		var p := o + Vector3(cos(a) * d, 0, sin(a) * d)
		p.y = terrain.height_at(p.x, p.z) - 0.05
		var glow := rng.randf() < 0.45
		var hgt := rng.randf_range(0.6, 3.2) if not glow else rng.randf_range(0.4, 1.4)
		var cr := hgt * rng.randf_range(0.45, 0.7) + 0.3
		# (Always solid: its cap is, and a cap needs something under it.)
		lm.cyl(p, cr * 0.22, cr * 0.18, hgt, "stem", 10, not glow)
		if glow:
			lathe(p + Vector3(0, hgt, 0), [[cr, 0.0], [cr * 0.8, cr * 0.35], [0.0, cr * 0.5]], 12, "glowcap", false)
		else:
			_cap(p + Vector3(0, hgt, 0), cr, hgt > 1.5)
	for k in 4:
		var a := TAU * float(k) / 4.0 + 0.4
		_light(o + Vector3(cos(a) * 12.0, 1.2, sin(a) * 12.0), Color(0.4, 1.0, 0.8), 1.2, 9.0)
	# A fairy ring of little glowing toadstools.
	for k in 28:
		var a := TAU * float(k) / 28.0 + rng.randf_range(-0.05, 0.05)
		var p := o + Vector3(cos(a) * 15.5, 0, sin(a) * 15.5)
		p.y = terrain.height_at(p.x, p.z) - 0.03
		var hh := rng.randf_range(0.25, 0.5)
		lm.cyl(p, 0.06, 0.05, hh, "stem", 6, false)
		lathe(p + Vector3(0, hh, 0), [[0.2, 0.0], [0.15, 0.08], [0.0, 0.12]], 8, "glowcap", false)
	lm._loot(o + Vector3(1.5, top_c, 0.8), "weapon", true)
	lm._loot(o + Vector3(-1.8, top_c, -0.6), "gear", true)
	lm._loot(o + Vector3(cos(start + PI) * 3.0, 0.1, sin(start + PI) * 3.0), "gear")
	lm._loot(o + Vector3(cos(start + 2.4) * 11.0, 0.1, sin(start + 2.4) * 11.0), "weapon")
	lm._end(1800.0)


# ------------------------------------------------------------------- farms

func _wheat_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rr := RandomNumberGenerator.new()
	rr.seed = 5
	for b in 5:
		var a := TAU * float(b) / 5.0 + rr.randf_range(-0.4, 0.4)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var root := dir * rr.randf_range(0.0, 0.08)
		var h := rr.randf_range(0.85, 1.15)
		var top := root + Vector3.UP * h + dir * rr.randf_range(0.05, 0.15)
		var w := 0.02
		# Stem.
		for e in [[root - side * w, 0.0], [root + side * w, 0.0], [top + side * w * 0.5, 0.8], [root - side * w, 0.0], [top + side * w * 0.5, 0.8], [top - side * w * 0.5, 0.8]]:
			st.set_uv(Vector2(0.5, float(e[1])))
			st.add_vertex(e[0])
		# Ear: a slim diamond at the top.
		var ew := 0.05
		var e0 := top
		var e1 := top + Vector3.UP * 0.16 + dir * 0.03
		var e2 := top + Vector3.UP * 0.3 + dir * 0.06
		for e in [[e0, 0.85], [e1 + side * ew, 0.95], [e2, 1.0], [e0, 0.85], [e2, 1.0], [e1 - side * ew, 0.95]]:
			st.set_uv(Vector2(0.5, float(e[1])))
			st.add_vertex(e[0])
	st.generate_normals()
	return st.commit()


func _build_farms() -> void:
	var wheat := _wheat_mesh()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/wheat.gdshader")
	var bale := StandardMaterial3D.new()
	bale.albedo_color = Color(0.93, 0.78, 0.42)
	bale.albedo_texture = load("res://assets/textures/tex_sand.png")
	bale.uv1_triplanar = true
	bale.uv1_world_triplanar = true
	bale.uv1_scale = Vector3.ONE * 1.8
	bale.roughness = 1.0
	lm._mats["hay"] = bale
	var pump := StandardMaterial3D.new()
	pump.albedo_color = Color(0.93, 0.5, 0.12)
	pump.roughness = 0.6
	lm._mats["pumpkin"] = pump
	var burlap := StandardMaterial3D.new()
	burlap.albedo_color = Color(0.6, 0.48, 0.32)
	burlap.roughness = 1.0
	lm._mats["burlap"] = burlap
	var n := 0
	for v in villages.village_pads:
		if v.type != "farm":
			continue
		var c: Vector2 = v.center
		var vr := float(v.radius)
		var placed := false
		for attempt in 8:
			var ang := float(v.axis) + float(attempt) * TAU / 8.0
			var dir := Vector2(cos(ang), sin(ang))
			var fc := c + dir * (vr + 7.5)
			if villages.road_distance(fc.x, fc.y) < 8.5 or villages.blocks_house(fc, 7.0):
				continue
			if bool(terrain.is_water(fc.x, fc.y)) or terrain.roughness(fc.x, fc.y, 6.5) > 1.8:
				continue
			var near := false
			for a in lm.clear_areas:
				if fc.distance_to(a.center) < float(a.radius) + 8.0:
					near = true
			for p in villages.poi_pads:
				if fc.distance_to(p.center) < float(p.radius) + 8.0:
					near = true
			if near:
				continue
			_wheat_field(fc, ang, wheat, mat, n)
			placed = true
			break
		# Hay bales and a scarecrow inside the paddock.
		lm._begin("FarmYard%d" % n)
		var hp := c + Vector2(cos(float(v.axis) + 2.4), sin(float(v.axis) + 2.4)) * (vr - 5.0)
		if not villages.blocks_house(hp, 1.8):
			_hay_stack(Vector3(hp.x, terrain.height_at(hp.x, hp.y), hp.y), float(v.axis))
		lm._end(900.0)
		n += 1
		if placed:
			pass


func _wheat_field(fc: Vector2, ang: float, wheat: ArrayMesh, mat: ShaderMaterial, idx: int) -> void:
	var fw := 12.0
	var fd := 9.0
	var b := Basis(Vector3.UP, -ang)
	var xs: Array[Transform3D] = []
	var cols: Array[Color] = []
	var rows := int(fd / 0.42)
	var per := int(fw / 0.3)
	for r in rows:
		for k in per:
			var lx := -fw * 0.5 + (float(k) + rng.randf_range(0.0, 0.8)) * 0.3
			var lz := -fd * 0.5 + float(r) * 0.42 + rng.randf_range(-0.05, 0.05)
			var wp := Vector3(fc.x, 0, fc.y) + b * Vector3(lx, 0, lz)
			wp.y = terrain.height_at(wp.x, wp.z) - 0.04
			var sc := rng.randf_range(0.85, 1.15)
			xs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.9, 1.1), sc)), wp))
			var tnt := rng.randf_range(0.9, 1.08)
			cols.append(Color(tnt, tnt, tnt * rng.randf_range(0.9, 1.0)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = wheat
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Wheat%d" % idx
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 260.0
	lm.add_child(mmi)
	# A low fence round the field, open at one end.
	lm._begin("Field%d" % idx)
	var fy := terrain.height_at(fc.x, fc.y)
	for side in 4:
		if side == 0:
			continue
		var a0 := [Vector3(-fw * 0.5 - 0.4, 0, -fd * 0.5 - 0.4), Vector3(fw * 0.5 + 0.4, 0, -fd * 0.5 - 0.4), Vector3(fw * 0.5 + 0.4, 0, fd * 0.5 + 0.4), Vector3(-fw * 0.5 - 0.4, 0, fd * 0.5 + 0.4)]
		var p0: Vector3 = Vector3(fc.x, 0, fc.y) + b * (a0[side] as Vector3)
		var p1: Vector3 = Vector3(fc.x, 0, fc.y) + b * (a0[(side + 1) % 4] as Vector3)
		var segs := int(p0.distance_to(p1) / 2.0)
		for k in segs + 1:
			var q := p0.lerp(p1, float(k) / float(segs))
			q.y = terrain.height_at(q.x, q.z)
			lm.box(q + Vector3(0, 0.5, 0), Vector3(0.14, 1.0, 0.14), 0.0, "wood", false)
			if k < segs:
				var q2 := p0.lerp(p1, float(k + 1) / float(segs))
				q2.y = terrain.height_at(q2.x, q2.z)
				for hh in [0.45, 0.85]:
					lm.box_b(lm._frame(q2 - q), (q + q2) * 0.5 + Vector3(0, float(hh), 0), Vector3(0.06, 0.1, q.distance_to(q2)), "wood", false)
	# Scarecrow in the middle of the wheat.
	var sp := Vector3(fc.x, fy, fc.y)
	lm.box(sp + Vector3(0, 1.2, 0), Vector3(0.14, 2.4, 0.14), -ang, "wood", false)
	lm.box(sp + Vector3(0, 1.75, 0), Vector3(1.6, 0.1, 0.1), -ang, "wood", false)
	lm.box(sp + Vector3(0, 1.45, 0), Vector3(0.55, 0.75, 0.3), -ang, "burlap", false)
	lathe(sp + Vector3(0, 2.0, 0), [[0.14, 0.0], [0.27, 0.12], [0.3, 0.27], [0.24, 0.42], [0.0, 0.5]], 10, "pumpkin", false)
	lm.cyl(sp + Vector3(0, 2.45, 0), 0.42, 0.42, 0.04, "dark", 12, false)
	lm.cyl(sp + Vector3(0, 2.48, 0), 0.22, 0.05, 0.42, "dark", 10, false)
	lm._end(500.0)
	lm.clear_areas.append({"center": fc, "radius": 7.5})
	if not poi.has("field"):
		poi["field"] = [fc, fy]


func _hay_stack(p: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, -yaw)
	for layer in 3:
		var count := 3 - layer
		for k in count:
			var lx := (float(k) - float(count - 1) * 0.5) * 1.25
			lm.box_b(b, p + b * Vector3(lx, 0.33 + float(layer) * 0.64, 0), Vector3(1.2, 0.62, 0.7), "hay")
