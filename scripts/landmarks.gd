extends Node3D
class_name Landmarks

## The island's set pieces: Skyreach Bridge to the east isle, Kingsbridge over
## the gorge, Stormkeep castle, the Old Henge, Gull Point lighthouse, the
## Sunspire temple and the Elder Oak. Built from textured masonry primitives
## batched into one mesh per material per landmark, with box/cylinder
## collision matching what you see.

const TEX := "res://assets/village/T_%s_%s.png"
## Materials drawn with the board shader (see Wood).
const WOODS := ["wood", "wood_dark"]

var terrain: Terrain
var villages: Villages
var rng := RandomNumberGenerator.new()
## [name, Vector2 position] for the map.
var labels: Array = []
## {center: Vector2, radius: float} areas scatter should leave clear.
var clear_areas: Array[Dictionary] = []

var _mats: Dictionary = {}
var _st: Dictionary = {}
var _group: Node3D
var _body: StaticBody3D
var _stat := {"shapes": 0}
var fantasy: Fantasy
## The oak's treehouse stair: [centre, radius, start angle, end angle, deck height].
var oak_stair: Array = []


func build(p_terrain: Terrain, p_villages: Villages, p_seed: int) -> void:
	terrain = p_terrain
	villages = p_villages
	rng.seed = p_seed + 9001
	_body = StaticBody3D.new()
	_body.name = "LandmarkCollision"
	_body.collision_layer = 1
	_body.collision_mask = 0
	_make_materials()

	_build_skyreach()
	_build_kingsbridge()
	_build_castle()
	_build_henge()
	_build_lighthouse()
	_build_temple()
	_build_oak()
	fantasy = Fantasy.new()
	fantasy.build(self, p_seed)
	labels.append(["HIGHFALLS", Terrain.PLATEAU_C + Vector2(0.0, -40.0)])
	add_child(_body)
	print("[landmarks] %d labels, %d collision shapes" % [labels.size(), _stat.shapes])


# ----------------------------------------------------------------- materials

func _make_materials() -> void:
	_mats["stone"] = _tex_mat("UnevenBrick", 0.32, Color(1, 1, 1))
	_mats["block"] = _tex_mat("Brick", 0.4, Color(0.95, 0.93, 0.9))
	_mats["trim"] = _tex_mat("RockTrim", 0.3, Color(0.92, 0.92, 0.9))
	_mats["dark"] = _tex_mat("UnevenBrick", 0.32, Color(0.62, 0.6, 0.6))
	_mats["wood"] = Wood.material(false)
	_mats["wood_dark"] = Wood.material(true)
	_mats["roof"] = _tex_mat("RoundTiles", 0.45, Color(1, 1, 1))
	_mats["plaster"] = _tex_mat("Plaster", 0.3, Color(1, 1, 1))
	_mats["redbrick"] = _tex_mat("RedBrick", 0.4, Color(1, 1, 1))
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.86, 0.66, 0.26)
	gold.metallic = 0.85
	gold.roughness = 0.32
	_mats["gold"] = gold
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(1.0, 0.82, 0.5)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.72, 0.36)
	lamp.emission_energy_multiplier = 2.2
	_mats["lamp"] = lamp
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.16, 0.16, 0.17)
	iron.metallic = 0.6
	iron.roughness = 0.5
	_mats["iron"] = iron
	for key in ["banner_red", "banner_blue"]:
		var b := StandardMaterial3D.new()
		b.albedo_color = Color(0.50, 0.07, 0.09) if key == "banner_red" else Color(0.13, 0.20, 0.46)
		b.roughness = 0.9
		b.cull_mode = BaseMaterial3D.CULL_DISABLED
		b.backlight_enabled = true
		b.backlight = b.albedo_color.lightened(0.1)
		_mats[key] = b


func _tex_mat(name: String, scale: float, tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX % [name, "BaseColor"])
	m.albedo_color = tint
	var nrm := TEX % [name, "Normal"]
	if ResourceLoader.exists(nrm):
		m.normal_enabled = true
		m.normal_texture = load(nrm)
		m.normal_scale = 0.8
	m.roughness = 0.88
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.uv1_triplanar_sharpness = 4.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


# ---------------------------------------------------------------- primitives

func _begin(name: String) -> void:
	_group = Node3D.new()
	_group.name = name
	add_child(_group)
	_st.clear()


func _end(view := 1600.0) -> void:
	for key in _st:
		var st: SurfaceTool = _st[key]
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _mats[key]
		mi.visibility_range_end = view
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_group.add_child(mi)
	_st.clear()


func _surface(mat: String) -> SurfaceTool:
	if not _st.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		if mat in WOODS:
			Wood.begin(st)
		_st[mat] = st
	return _st[mat]


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	_tri(st, a, b, c, n)
	_tri(st, a, c, d, n)


## Godot's front faces wind clockwise; fix the order to match the normal.
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	st.set_normal(n)
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


## Right-handed basis with local +z along `fwd` and local +x along `side`
## (or horizontal when not given).
func _frame(fwd: Vector3, side := Vector3.ZERO) -> Basis:
	var f := fwd.normalized()
	var right := side
	if right == Vector3.ZERO:
		right = Vector3.UP.cross(f)
		if right.length() < 0.01:
			right = Vector3.RIGHT
	right = (right - f * right.dot(f)).normalized()
	var up := f.cross(right).normalized()
	if up.y < 0.0:
		right = -right
		up = -up
	return Basis(right, up, f)


## Box with an arbitrary basis (columns are the box's local axes).
func box_b(b: Basis, c: Vector3, size: Vector3, mat := "stone", collide := true) -> void:
	var st := _surface(mat)
	if mat in WOODS:
		# Boards: grain along the piece, seams across it, sawn ends.
		Wood.box(st, b, c, size)
	else:
		var h := size * 0.5
		var x := b.x * h.x
		var y := b.y * h.y
		var z := b.z * h.z
		var nx := b.x.normalized()
		var ny := b.y.normalized()
		var nz := b.z.normalized()
		_quad(st, c + x - y - z, c + x + y - z, c + x + y + z, c + x - y + z, nx)
		_quad(st, c - x - y + z, c - x + y + z, c - x + y - z, c - x - y - z, -nx)
		_quad(st, c - x + y - z, c - x + y + z, c + x + y + z, c + x + y - z, ny)
		_quad(st, c - x - y + z, c - x - y - z, c + x - y - z, c + x - y + z, -ny)
		_quad(st, c - x - y + z, c + x - y + z, c + x + y + z, c - x + y + z, nz)
		_quad(st, c + x - y - z, c - x - y - z, c - x + y - z, c + x + y - z, -nz)
	if collide:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		cs.transform = Transform3D(b.orthonormalized(), c)
		_body.add_child(cs)
		_stat.shapes += 1


func box(c: Vector3, size: Vector3, yaw := 0.0, mat := "stone", collide := true) -> void:
	box_b(Basis(Vector3.UP, yaw), c, size, mat, collide)


## Slab whose top surface runs from `a` to `b` (both on the walking surface).
func ramp(a: Vector3, b: Vector3, width: float, mat := "stone", thick := 0.5, steps := false) -> void:
	var d := b - a
	var flat := Vector3(d.x, 0.0, d.z)
	var fb := _frame(d)
	var right := fb.x
	var up := fb.y
	var fwd := fb.z
	var center := (a + b) * 0.5 - up * thick * 0.5
	if steps:
		# Visual treads, invisible smooth slope underneath for walking.
		var n := maxi(2, int(ceil(absf(d.y) / 0.24)))
		var run := flat.length() / float(n)
		var rise := d.y / float(n)
		var fdir := flat.normalized()
		for i in n:
			var top := a.y + rise * float(i + 1)
			var p := Vector3(a.x, 0.0, a.z) + fdir * run * (float(i) + 0.5)
			var hgt := maxf(0.3, top - a.y + 0.3)
			box_b(_frame(fdir), Vector3(p.x, top - hgt * 0.5, p.z), Vector3(width, hgt, run + 0.02), mat, false)
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(width, thick, d.length() + 0.1)
		cs.shape = shape
		cs.transform = Transform3D(fb, center)
		_body.add_child(cs)
		_stat.shapes += 1
		return
	box_b(fb, center, Vector3(width, thick, d.length() + 0.1), mat, true)


## Vertical cylinder (or cone when r_top is 0) standing on `base`.
func cyl(base: Vector3, r_bottom: float, r_top: float, h: float, mat := "stone", sides := 16, collide := true, cap := true) -> void:
	var st := _surface(mat)
	var woody := mat in WOODS
	if woody:
		# A log: grain runs up it, no board seams.
		Wood.grain(st, Vector3.UP, true)
	var slope := (r_bottom - r_top) / h
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var n := (Vector3(cos((a0 + a1) * 0.5), slope, sin((a0 + a1) * 0.5))).normalized()
		_quad(st, base + d1 * r_bottom, base + d0 * r_bottom, base + d0 * r_top + Vector3(0, h, 0), base + d1 * r_top + Vector3(0, h, 0), n)
		if cap and r_top > 0.01:
			var top := base + Vector3(0, h, 0)
			_tri(st, top, top + d0 * r_top, top + d1 * r_top, Vector3.UP)
	if woody:
		Wood.begin(st)
	if collide:
		# Exactly the drawn frustum (tapers and cones included).
		var pts := PackedVector3Array()
		for i in sides:
			var a := TAU * float(i) / float(sides)
			var d := Vector3(cos(a), 0.0, sin(a))
			pts.append(base + d * r_bottom)
			pts.append(base + d * maxf(r_top, 0.001) + Vector3(0, h, 0))
		var cs := CollisionShape3D.new()
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		cs.shape = shape
		_body.add_child(cs)
		_stat.shapes += 1


## Crenellations along a line at height `y`: solid merlons with embrasures.
func merlons(a: Vector2, b: Vector2, y: float, thick := 0.7, mat := "stone", height := 1.3) -> void:
	var len := a.distance_to(b)
	var dir := (b - a) / maxf(0.001, len)
	var yaw := atan2(dir.x, dir.y)
	# Low continuous parapet with merlons on top.
	var mid := (a + b) * 0.5
	box(Vector3(mid.x, y + 0.5, mid.y), Vector3(thick, 1.0, len), yaw, mat)
	var n := int(len / 1.8)
	for i in n:
		var t := (float(i) + 0.5) / float(n)
		var p := a.lerp(b, t)
		if i % 2 == 0:
			box(Vector3(p.x, y + 1.0 + (height - 1.0) * 0.5 + 0.35, p.y), Vector3(thick, height - 0.3, len / float(n)), yaw, mat)


func merlon_ring(c: Vector3, r: float, count: int, mat := "stone", thick := 0.7, skip: Array = []) -> void:
	for i in count:
		var a0 := TAU * float(i) / float(count)
		var a1 := TAU * float(i + 1) / float(count)
		var am := Vector2(cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5))
		var skipped := false
		for sd in skip:
			if am.dot((sd as Vector2).normalized()) > 0.55:
				skipped = true
		if skipped:
			continue
		var p0 := Vector2(c.x + cos(a0) * r, c.z + sin(a0) * r)
		var p1 := Vector2(c.x + cos(a1) * r, c.z + sin(a1) * r)
		var mid := (p0 + p1) * 0.5
		var yaw := atan2(p1.x - p0.x, p1.y - p0.y)
		var l := p0.distance_to(p1) + 0.12
		box(Vector3(mid.x, c.y + 0.5, mid.y), Vector3(thick, 1.0, l), yaw, mat)
		if i % 2 == 0:
			box(Vector3(mid.x, c.y + 1.35, mid.y), Vector3(thick, 0.7, l), yaw, mat)


## A straight wall in local space of a frame (origin, yaw), from local a to b,
## with openings: [centre along wall (m), width, sill, top].
func wall(o: Vector3, yaw: float, a: Vector2, b: Vector2, y0: float, h: float, thick: float, mat := "stone", openings: Array = []) -> void:
	var bs := Basis(Vector3.UP, yaw)
	var len := a.distance_to(b)
	var dir := (b - a) / maxf(0.001, len)
	var wyaw := yaw + atan2(dir.x, dir.y)
	var cuts: Array = openings.duplicate()
	cuts.sort_custom(func(p, q): return float(p[0]) < float(q[0]))
	var at := 0.0
	var pieces: Array = []
	for op in cuts:
		var c0 := float(op[0]) - float(op[1]) * 0.5
		var c1 := float(op[0]) + float(op[1]) * 0.5
		if c0 > at:
			pieces.append([at, c0, 0.0, h])
		var sill := float(op[2])
		var top := float(op[3])
		if sill > 0.0:
			pieces.append([c0, c1, 0.0, sill])
		if top < h:
			pieces.append([c0, c1, top, h])
		at = c1
	if at < len:
		pieces.append([at, len, 0.0, h])
	for pc in pieces:
		var s0: float = pc[0]
		var s1: float = pc[1]
		var lo: float = pc[2]
		var hi: float = pc[3]
		if s1 - s0 < 0.01 or hi - lo < 0.01:
			continue
		var mid2 := a + dir * ((s0 + s1) * 0.5)
		var world := o + bs * Vector3(mid2.x, y0 + (lo + hi) * 0.5, mid2.y)
		box(world, Vector3(thick, hi - lo, s1 - s0), wyaw, mat)


## Dressed stone (or timber) round one opening of a wall() built with the
## same arguments: jambs, a lintel, and a sill under windows.
func opening_frame(o: Vector3, yaw: float, a: Vector2, b: Vector2, y0: float, thick: float, op: Array, mat := "trim") -> void:
	var bs := Basis(Vector3.UP, yaw)
	var len := a.distance_to(b)
	var dir := (b - a) / maxf(0.001, len)
	var wyaw := yaw + atan2(dir.x, dir.y)
	var oc := float(op[0])
	var ow := float(op[1])
	var sill := float(op[2])
	var top := float(op[3])
	var at := func(along: float, y: float) -> Vector3:
		var q := a + dir * along
		return o + bs * Vector3(q.x, y0 + y, q.y)
	var deep := thick + 0.22
	for sd: float in [-1.0, 1.0]:
		box(at.call(oc + sd * (ow * 0.5 + 0.09), (sill + top) * 0.5), Vector3(deep, top - sill + 0.36, 0.2), wyaw, mat, false)
	box(at.call(oc, top + 0.11), Vector3(deep + 0.06, 0.24, ow + 0.6), wyaw, mat, false)
	if sill > 0.0:
		box(at.call(oc, sill - 0.09), Vector3(deep + 0.12, 0.18, ow + 0.5), wyaw, mat, false)


## A coopered barrel standing on `base`.
func barrel(base: Vector3, r := 0.42, h := 1.05) -> void:
	cyl(base, r * 0.9, r, h * 0.5, "wood_dark", 10, false)
	cyl(base + Vector3(0, h * 0.5, 0), r, r * 0.9, h * 0.5, "wood_dark", 10, false)
	for hy: float in [0.16, 0.5, 0.84]:
		cyl(base + Vector3(0, h * hy - 0.03, 0), r * 1.03, r * 1.03, 0.06, "iron", 10, false, false)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = h
	cs.shape = shape
	cs.position = base + Vector3(0, h * 0.5, 0)
	_body.add_child(cs)
	_stat.shapes += 1


func banner(top: Vector3, out: Vector3, width: float, length: float, mat := "banner_red") -> void:
	var yaw := atan2(out.x, out.z)
	var b := Basis(Vector3.UP, yaw)
	var face := top + out * 0.12
	# The cloth, cut to a swallowtail, with a gold band, hem and device.
	var body := length * 0.84
	box(face - Vector3(0, body * 0.5, 0), Vector3(width, body, 0.06), yaw, mat, false)
	for sx: float in [-1.0, 1.0]:
		box(face + b * Vector3(sx * width * 0.31, 0, 0) - Vector3(0, body + (length - body) * 0.5, 0), Vector3(width * 0.38, length - body, 0.06), yaw, mat, false)
	box(face - Vector3(0, 0.42, 0), Vector3(width, 0.16, 0.075), yaw, "gold", false)
	box(face - Vector3(0, body - 0.16, 0), Vector3(width, 0.09, 0.075), yaw, "gold", false)
	var dev := width * 0.44
	box_b(b * Basis(Vector3.BACK, PI * 0.25), face - Vector3(0, body * 0.46, 0), Vector3(dev, dev, 0.075), "gold", false)
	box_b(b * Basis(Vector3.BACK, PI * 0.25), face - Vector3(0, body * 0.46, 0), Vector3(dev * 0.52, dev * 0.52, 0.09), mat, false)
	box(top + out * 0.2 + Vector3(0, 0.1, 0), Vector3(width + 0.4, 0.12, 0.12), yaw, "iron", false)
	for sx: float in [-1.0, 1.0]:
		box(top + out * 0.2 + Vector3(0, 0.1, 0) + b * Vector3(sx * (width * 0.5 + 0.2), 0, 0), Vector3(0.16, 0.2, 0.2), yaw, "gold", false)


func lantern(base: Vector3, post_h := 2.2) -> void:
	box(base + Vector3(0, post_h * 0.5, 0), Vector3(0.22, post_h, 0.22), 0.0, "iron", false)
	box(base + Vector3(0, post_h + 0.26, 0), Vector3(0.42, 0.5, 0.42), 0.0, "lamp", false)
	cyl(base + Vector3(0, post_h + 0.5, 0), 0.36, 0.0, 0.4, "iron", 4, false)


func _loot(p: Vector3, kind: String, hi := false) -> void:
	var lp := {"pos": p + Vector3(0, 0.08, 0), "kind": kind, "village": true}
	if hi:
		lp["tier"] = "hi"
	villages.loot_points.append(lp)


func _prop(key: String, p: Vector3, yaw: float) -> void:
	villages._place(key, p, yaw)
	if key == "Prop_Crate":
		villages._add_box_collider(p + Vector3(0, 0.53, 0), Vector3(1.06, 1.06, 1.06), yaw)
	elif key == "Prop_Wagon":
		villages._add_box_collider(p + Vector3(0, 0.7, 0), Vector3(1.7, 1.4, 3.4), yaw)


# ---------------------------------------------------------- Skyreach Bridge

func _build_skyreach() -> void:
	_begin("SkyreachBridge")
	var a: Vector2 = terrain.bridge_a
	var b: Vector2 = terrain.bridge_b
	var H: float = terrain.bridge_h
	var dir := (b - a).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var yaw := atan2(dir.x, dir.y)
	var L := a.distance_to(b)
	var W := 9.0
	var d3 := Vector3(dir.x, 0, dir.y)
	var p3 := Vector3(perp.x, 0, perp.y)
	var at := func(t: float, side: float, y: float) -> Vector3:
		var q := a + dir * t + perp * side
		return Vector3(q.x, y, q.y)

	# Deck, run 14 m into each headland so it meets the ground.
	var mid := (a + b) * 0.5
	box(Vector3(mid.x, H - 0.8, mid.y), Vector3(W, 1.6, L + 28.0), yaw, "block")
	# Kerbs and parapets with lantern posts.
	for side: float in [-1.0, 1.0]:
		var off: float = side * (W * 0.5 - 0.35)
		box(at.call(L * 0.5, off, H + 0.6), Vector3(0.7, 1.2, L + 16.0), yaw, "trim")
		var n := int((L + 10.0) / 16.0)
		for i in n + 1:
			var t := -5.0 + float(i) * (L + 10.0) / float(n)
			var post: Vector3 = at.call(t, side * (W * 0.5 - 0.35), H)
			box(post + Vector3(0, 0.8, 0), Vector3(0.95, 1.6, 0.95), yaw, "trim")
			lantern(post + Vector3(0, 1.6, 0), 1.1)
	# Piers and arches: four spans, the middle pier carrying the sky gate.
	var spans := 4
	var pier_t: Array[float] = [0.0]
	for i in range(1, spans):
		pier_t.append(L * float(i) / float(spans))
	pier_t.append(L)
	for i in range(1, spans):
		var t: float = pier_t[i]
		var big := i == spans / 2
		var pw := W + (7.0 if big else 3.0)
		var pd := 9.0 if big else 7.0
		var c: Vector3 = at.call(t, 0.0, 0.0)
		box(Vector3(c.x, (H - 1.6 - 16.0) * 0.5 - 8.0 + 8.0, c.z), Vector3(pw, H - 1.6 + 16.0, pd), yaw, "stone")
		# Cutwaters and a plinth at the waterline.
		for side: float in [-1.0, 1.0]:
			var cw: Vector3 = at.call(t, side * (pw * 0.5 + 0.2), 0.0)
			box_b(Basis(Vector3.UP, yaw + PI * 0.25), Vector3(cw.x, 4.0, cw.z), Vector3(pd * 0.62, 24.0, pd * 0.62), "stone", false)
		box(Vector3(c.x, 1.2, c.z), Vector3(pw + 3.0, 3.0, pd + 3.0), yaw, "dark", false)
		box(Vector3(c.x, H - 2.2, c.z), Vector3(pw + 0.8, 1.2, pd + 0.8), yaw, "trim", false)
	for i in spans:
		var t0: float = pier_t[i] + (0.0 if i == 0 else 3.5)
		var t1: float = pier_t[i + 1] - (0.0 if i == spans - 1 else 3.5)
		_arch(at, t0, t1, H - 1.6, (t1 - t0) * 0.42, W - 0.6)

	# Sky gate on the middle pier: twin towers and a lintel over the road.
	var gate_t: float = pier_t[spans / 2]
	for side: float in [-1.0, 1.0]:
		var tc: Vector3 = at.call(gate_t, side * (W * 0.5 + 2.4), H)
		box(tc + Vector3(0, 7.9, 0), Vector3(4.6, 20.2, 4.6), yaw, "stone")
		box(tc + Vector3(0, 18.3, 0), Vector3(5.4, 0.6, 5.4), yaw, "trim", false)
		cyl(tc + Vector3(0, 18.6, 0), 3.6, 0.0, 8.5, "roof", 4, false)
		cyl(tc + Vector3(0, 27.0, 0), 0.12, 0.12, 3.0, "iron", 6, false)
		box(tc + Vector3(0, 29.2, 0) + p3 * side * 0.9, Vector3(0.05, 1.0, 1.7), yaw, "banner_red", false)
		banner(tc + Vector3(0, 15.5, 0) + p3 * side * 2.3, p3 * side, 2.2, 9.0, "banner_red")
		banner(tc + Vector3(0, 15.5, 0) + d3 * 2.3, d3, 1.6, 6.0, "banner_blue")
		banner(tc + Vector3(0, 15.5, 0) - d3 * 2.3, -d3, 1.6, 6.0, "banner_blue")
	var lintel: Vector3 = at.call(gate_t, 0.0, H + 8.6)
	box(lintel, Vector3(W + 1.0, 2.4, 3.4), yaw, "stone", false)
	box(lintel + Vector3(0, 1.4, 0), Vector3(W + 1.6, 0.5, 3.8), yaw, "trim", false)
	_arch_frame(at, gate_t, H, W, 7.4)

	# Gatehouses where the bridge meets each headland.
	for end_t: float in [-3.0, L + 3.0]:
		for side: float in [-1.0, 1.0]:
			var tc: Vector3 = at.call(end_t, side * (W * 0.5 + 2.2), H)
			box(tc + Vector3(0, 5.5, 0), Vector3(4.2, 11.0 + 4.0, 4.2), yaw, "stone")
			merlon_ring(tc + Vector3(0, 13.0, 0), 2.2, 8)
			lantern(tc + Vector3(0, 0, 0) - p3 * side * 2.3, 2.6)
		var lt: Vector3 = at.call(end_t, 0.0, H + 7.2)
		box(lt, Vector3(W + 0.2, 2.0, 3.0), yaw, "stone", false)
		_arch_frame(at, end_t, H, W, 6.2)

	# Abandoned carts and crates: the only cover on the span.
	var cover_t := [L * 0.16, L * 0.36, L * 0.62, L * 0.84]
	for i in cover_t.size():
		var t: float = cover_t[i]
		var side := -1.0 if i % 2 == 0 else 1.0
		var p: Vector3 = at.call(t, side * 2.0, H)
		if i % 2 == 0:
			_prop("Prop_Wagon", p, yaw + rng.randf_range(-0.25, 0.25))
		else:
			_prop("Prop_Crate", p, yaw + 0.3)
			_prop("Prop_Crate", p + d3 * 1.2, yaw - 0.2)
			_prop("Prop_Crate", p + d3 * 0.6 + Vector3(0, 1.06, 0), yaw)
		_loot(at.call(t + 2.5, -side * 1.6, H), "weapon" if i % 2 == 0 else "gear")
	_loot(at.call(gate_t - 2.0, 2.5, H), "gear", true)
	_loot(at.call(gate_t + 2.0, -2.5, H), "weapon", true)
	_end(2400.0)
	labels.append(["SKYREACH BRIDGE", mid + perp * 40.0])
	clear_areas.append({"center": a, "radius": 26.0})
	clear_areas.append({"center": b, "radius": 26.0})


## Masonry arch ring under a deck between t0 and t1 along the frame `at`.
func _arch(at: Callable, t0: float, t1: float, deck_bottom: float, rise: float, width: float) -> void:
	var span := t1 - t0
	var spring := deck_bottom - rise
	var segs := 16
	var ring := 1.8
	var prev: Vector3 = Vector3.ZERO
	for i in segs + 1:
		var th := PI * float(i) / float(segs)
		var t := t0 + span * 0.5 * (1.0 - cos(th))
		var y := spring + sin(th) * rise - ring * 0.5
		var p: Vector3 = at.call(t, 0.0, y)
		if i > 0:
			var d := p - prev
			var deck_dir: Vector3 = at.call(t1, 0.0, 0.0) - at.call(t0, 0.0, 0.0)
			var side := Vector3.UP.cross(deck_dir).normalized()
			box_b(_frame(d, side), (p + prev) * 0.5, Vector3(width, ring, d.length() + 0.5), "block", false)
		prev = p
	# Spandrel fill near the piers so the arch reads as carrying the deck.
	for side: float in [0.0, 1.0]:
		var tt := t0 + span * (0.09 if side == 0.0 else 0.91)
		var top := deck_bottom
		var bottom := spring + rise * 0.35
		var p2: Vector3 = at.call(tt, 0.0, (top + bottom) * 0.5)
		var dirv: Vector3 = (at.call(t1, 0.0, 0.0) - at.call(t0, 0.0, 0.0)).normalized()
		box(p2, Vector3(width, top - bottom, span * 0.18), atan2(dirv.x, dirv.z), "stone", false)


## Decorative arch frame over the road at `t` (visual only).
func _arch_frame(at: Callable, t: float, deck: float, width: float, top: float) -> void:
	var c: Vector3 = at.call(t, 0.0, deck)
	var e: Vector3 = at.call(t + 1.0, 0.0, deck) - c
	var yaw := atan2(e.x, e.z)
	var segs := 9
	var r := width * 0.5
	var spring := top - r * 0.75
	var right := Basis(Vector3.UP, yaw) * Vector3.RIGHT
	var prev := Vector3.ZERO
	for i in segs + 1:
		var th := PI * float(i) / float(segs)
		var p := c + right * cos(th) * r + Vector3(0, spring + sin(th) * r * 0.75, 0)
		if i > 0:
			var d := p - prev
			var fb := Basis(Vector3.UP, yaw) * Vector3.BACK
			box_b(_frame(d, fb), (p + prev) * 0.5, Vector3(2.6, 0.9, d.length() + 0.3), "trim", false)
		prev = p


# ------------------------------------------------------------- Kingsbridge

func _build_kingsbridge() -> void:
	_begin("Kingsbridge")
	var g: Vector2 = terrain.gorge_bridge
	var gd: Vector2 = terrain.gorge_bridge_dir.normalized()
	var q := terrain.river_query(g)
	var prof := terrain.river_profile(q.y)
	var reach := prof.x + prof.y + 8.0
	var a := g - gd * reach
	var b := g + gd * reach
	var ha := terrain.height_at(a.x, a.y)
	var hb := terrain.height_at(b.x, b.y)
	var W := 6.0
	var A := Vector3(a.x, ha + 0.05, a.y)
	var B := Vector3(b.x, hb + 0.05, b.y)
	# Deck as a sloped slab; parapets follow it.
	var d := B - A
	var flat := Vector3(d.x, 0, d.z).normalized()
	var bs := _frame(d)
	var right := bs.x
	var up := bs.y
	box_b(bs, (A + B) * 0.5 - up * 0.6, Vector3(W, 1.2, d.length() + 8.0), "block")
	for side: float in [-1.0, 1.0]:
		box_b(bs, (A + B) * 0.5 + right * side * (W * 0.5 - 0.3) + up * 0.55, Vector3(0.6, 1.1, d.length() + 4.0), "trim")
		for i in 5:
			var t := float(i) / 4.0
			var p := A.lerp(B, t) + right * side * (W * 0.5 - 0.3)
			box(p + Vector3(0, 0.75, 0), Vector3(0.8, 1.5, 0.8), atan2(flat.x, flat.z), "trim")
			if i % 2 == 0:
				lantern(p + Vector3(0, 1.5, 0), 1.0)
	# Two piers rising from the gorge floor and three arches.
	var at := func(t: float, side: float, y: float) -> Vector3:
		var p2 := a.lerp(b, t / (2.0 * reach)) + Vector2(right.x, right.z) * side
		return Vector3(p2.x, y, p2.y)
	var L := 2.0 * reach
	var deck_at := func(t: float) -> float:
		return lerpf(ha, hb, t / L) - 1.2
	var piers := [L * 0.36, L * 0.64]
	for t in piers:
		var top: float = deck_at.call(t)
		var c: Vector3 = at.call(t, 0.0, 0.0)
		var bottom := -2.5
		box(Vector3(c.x, (top + bottom) * 0.5, c.z), Vector3(W + 1.5, top - bottom, 4.0), atan2(flat.x, flat.z), "stone")
		box(Vector3(c.x, 1.0, c.z), Vector3(W + 3.0, 2.4, 6.0), atan2(flat.x, flat.z), "dark", false)
	var edges := [0.0, L * 0.36 + 2.0, L * 0.64 + 2.0]
	var ends := [L * 0.36 - 2.0, L * 0.64 - 2.0, L]
	for i in 3:
		var t0: float = edges[i]
		var t1: float = ends[i]
		var dk: float = minf(deck_at.call(t0), deck_at.call(t1))
		_arch(at, t0, t1, dk, minf((t1 - t0) * 0.5, maxf(4.0, dk - 1.0)), W - 0.4)
	_loot(A.lerp(B, 0.5) + right * 1.5, "weapon")
	_end(1800.0)
	labels.append(["KINGSBRIDGE", g + gd * (reach + 30.0)])


# ----------------------------------------------------------------- Stormkeep

func _build_castle() -> void:
	_begin("Stormkeep")
	var c: Vector2 = terrain.castle_c
	var gy: float = terrain.castle_h
	var yaw := rng.randf() * TAU
	# The gate (+z) faces the track that comes up to the castle, so the road
	# runs in through the gate and not into a curtain wall.
	for r in villages.roads:
		var ra: Vector2 = r.a
		var rb: Vector2 = r.b
		var other := Vector2.INF
		if rb.distance_to(c) < 0.5:
			other = ra
		elif ra.distance_to(c) < 0.5:
			other = rb
		if other != Vector2.INF:
			var d := other - c
			yaw = atan2(d.x, d.y)
			break
	var bs := Basis(Vector3.UP, yaw)
	var o := Vector3(c.x, gy, c.y)
	var L := func(x: float, y: float, z: float) -> Vector3:
		return o + bs * Vector3(x, y, z)
	var half := 23.0
	var wh := 7.0
	var wt := 2.6
	# Curtain walls: gate on +z, postern on -z.
	var sides := [
		[Vector2(-half, half), Vector2(half, half), [[half, 4.6, 0.0, 4.8]]],
		[Vector2(half, half), Vector2(half, -half), []],
		[Vector2(half, -half), Vector2(-half, -half), [[half, 2.0, 0.0, 3.0]]],
		[Vector2(-half, -half), Vector2(-half, half), []],
	]
	for s in sides:
		var a2: Vector2 = s[0]
		var b2: Vector2 = s[1]
		wall(o, yaw, a2, b2, 0.0, wh, wt, "stone", s[2])
		# Outer merlons along the walkway.
		var out := (a2 + b2) * 0.5
		out = out.normalized()
		var along2 := (b2 - a2).normalized()
		var ma := a2 + out * (wt * 0.5 - 0.35) + along2 * 4.4
		var mb := b2 + out * (wt * 0.5 - 0.35) - along2 * 4.4
		var wa: Vector3 = L.call(ma.x, 0, ma.y)
		var wb: Vector3 = L.call(mb.x, 0, mb.y)
		merlons(Vector2(wa.x, wa.z), Vector2(wb.x, wb.z), gy + wh, 0.7)
	# Foundation skirt so the walls sit into the motte.
	for s in sides:
		var a2: Vector2 = s[0]
		var b2: Vector2 = s[1]
		var m2 := (a2 + b2) * 0.5
		var wc: Vector3 = L.call(m2.x * 1.02, -1.4, m2.y * 1.02)
		var along: Vector2 = (b2 - a2)
		box(wc, Vector3(wt + 1.2, 3.2, along.length() + 2.0), yaw + atan2(along.x, along.y), "dark", false)
	# Corner bastions, walkable at walkway level.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var tc: Vector3 = L.call(sx * half, -2.0, sz * half)
			cyl(tc, 5.0, 4.6, wh + 2.0, "stone", 16)
			var in_x := bs * Vector3(-sx, 0, 0)
			var in_z := bs * Vector3(0, 0, -sz)
			merlon_ring(tc + Vector3(0, wh + 2.0, 0), 4.3, 14, "stone", 0.7, [Vector2(in_x.x, in_x.z), Vector2(in_z.x, in_z.z)])
			cyl(tc + Vector3(0, wh + 2.0 + 1.3, 0), 0.1, 0.1, 5.0, "iron", 4, false)
			box(tc + Vector3(0, wh + 2.0 + 5.6, 0) + bs * Vector3(0.75, 0, 0), Vector3(1.5, 0.9, 0.04), yaw, "banner_red", false)
	# Gate towers flanking the entrance.
	for sx: float in [-1.0, 1.0]:
		var gc: Vector3 = L.call(sx * 4.6, 0, half + 1.0)
		box(gc + Vector3(0, wh * 0.5 - 0.7, 0), Vector3(4.6, wh + 1.4, 4.8), yaw, "stone")
		var f0: Vector3 = L.call(sx * 2.3, 0, half + 3.05)
		var f1: Vector3 = L.call(sx * 6.9, 0, half + 3.05)
		var f2: Vector3 = L.call(sx * 6.55, 0, half + 1.3)
		merlons(Vector2(f0.x, f0.z), Vector2(f1.x, f1.z), gy + wh, 0.7)
		merlons(Vector2(f1.x, f1.z), Vector2(f2.x, f2.z), gy + wh, 0.7)
		banner(gc + Vector3(0, wh - 1.0, 0) + bs * Vector3(0, 0, 2.45), bs * Vector3.BACK, 2.0, 5.0, "banner_red")
	box(L.call(0, 5.4, half + 0.2), Vector3(4.8, 0.4, 0.3), yaw, "iron", false)
	lantern(L.call(-3.3, 0, half + 3.6), 2.6)
	lantern(L.call(3.3, 0, half + 3.6), 2.6)
	# Stairs up to the wall walk on the east and west inner faces.
	for sx: float in [-1.0, 1.0]:
		var x := sx * (half - wt * 0.5 - 1.15)
		ramp(L.call(x, 0.0, 10.0), L.call(x, wh, -6.0), 2.2, "stone", 0.5, true)
		box(L.call(x, wh - 0.25, -8.0), Vector3(2.3, 0.5, 4.0), yaw, "stone")
	# Inner wall walk planks bridging the stair heads to the wall top.
	# The keep: 14 x 14, two floors and a roof terrace.
	_keep(o + bs * Vector3(0, 0, -5.0), yaw)
	# Cobbled courtyard.
	var inner_h := half - wt * 0.5
	box(L.call(0, 0.04, 0), Vector3(inner_h * 2.0, 0.12, inner_h * 2.0), yaw, "block")
	# Torches along the inner walls.
	for k in 8:
		var side_i := k % 4
		var tpos: Vector3 = [L.call(-8.0 + float(k / 4) * 16.0, 3.4, half - wt * 0.5 - 0.15), L.call(half - wt * 0.5 - 0.15, 3.4, -8.0 + float(k / 4) * 16.0), L.call(8.0 - float(k / 4) * 16.0, 3.4, -half + wt * 0.5 + 0.15), L.call(-half + wt * 0.5 + 0.15, 3.4, 8.0 - float(k / 4) * 16.0)][side_i]
		box(tpos, Vector3(0.12, 0.5, 0.12), yaw, "iron", false)
		box(tpos + Vector3(0, 0.38, 0), Vector3(0.22, 0.26, 0.22), yaw, "lamp", false)
		if k % 2 == 0:
			var tl := OmniLight3D.new()
			tl.light_color = Color(1.0, 0.66, 0.32)
			tl.light_energy = 1.6
			tl.omni_range = 10.0
			tl.shadow_enabled = false
			tl.distance_fade_enabled = true
			tl.distance_fade_begin = 150.0
			tl.distance_fade_length = 50.0
			tl.position = tpos + Vector3(0, 0.5, 0)
			_group.add_child(tl)
	# Training yard: straw dummies and weapon racks.
	if not _mats.has("straw"):
		var straw := StandardMaterial3D.new()
		straw.albedo_color = Color(0.86, 0.72, 0.4)
		straw.albedo_texture = load("res://assets/textures/tex_sand.png")
		straw.uv1_triplanar = true
		straw.uv1_world_triplanar = true
		straw.uv1_scale = Vector3.ONE * 1.8
		straw.roughness = 1.0
		_mats["straw"] = straw
	for k in 3:
		var dp: Vector3 = L.call(9.0 + float(k) * 2.6, 0, 5.0)
		box(dp + Vector3(0, 0.9, 0), Vector3(0.14, 1.8, 0.14), yaw, "wood")
		box(dp + Vector3(0, 1.35, 0), Vector3(0.5, 0.8, 0.32), yaw + 0.2 * float(k), "straw")
		box(dp + Vector3(0, 1.45, 0), Vector3(1.2, 0.1, 0.1), yaw + 0.2 * float(k), "wood", false)
		box(dp + Vector3(0, 1.95, 0), Vector3(0.3, 0.32, 0.3), yaw + 0.2 * float(k), "straw", false)
	for k in 2:
		var rp: Vector3 = L.call(-6.0 + float(k) * 3.4, 0, 18.5)
		box(rp + Vector3(0, 0.35, 0), Vector3(2.6, 0.12, 0.5), yaw, "wood", false)
		box(rp + Vector3(0, 1.2, 0), Vector3(2.6, 0.12, 0.5), yaw, "wood", false)
		for sx2: float in [-1.2, 1.2]:
			box(rp + bs * Vector3(sx2, 0.8, 0), Vector3(0.12, 1.6, 0.12), yaw, "wood", false)
		for j in 4:
			var spear := rp + bs * Vector3(-0.9 + float(j) * 0.6, 1.1, 0.0)
			box_b(bs * Basis(Vector3.RIGHT, 0.12), spear, Vector3(0.05, 2.2, 0.05), "wood", false)
			box_b(bs * Basis(Vector3.RIGHT, 0.12), spear + Vector3(0, 1.15, 0.13), Vector3(0.08, 0.26, 0.02), "iron", false)
		var cs2 := CollisionShape3D.new()
		var sh2 := BoxShape3D.new()
		sh2.size = Vector3(2.6, 1.6, 0.5)
		cs2.shape = sh2
		cs2.transform = Transform3D(bs, rp + Vector3(0, 0.8, 0))
		_body.add_child(cs2)
	# A lean-to stable against the west wall: posts, a plank roof, hay.
	var sx0 := -half + wt * 0.5
	for k in 3:
		box(L.call(sx0 + 3.6, 1.4, -20.0 + float(k) * 4.0), Vector3(0.24, 2.8, 0.24), yaw, "wood_dark")
	box(L.call(sx0 + 3.6, 2.86, -16.0), Vector3(0.26, 0.24, 8.6), yaw, "wood_dark", false)
	box(L.call(sx0 + 0.16, 3.5, -16.0), Vector3(0.24, 0.24, 8.6), yaw, "wood_dark", false)
	var r0: Vector3 = L.call(sx0 + 0.05, 3.72, -16.0)
	var r1: Vector3 = L.call(sx0 + 4.2, 2.96, -16.0)
	var rx := (r1 - r0).normalized()
	box_b(Basis(rx, rx.cross(bs.z).normalized() * -1.0, bs.z), (r0 + r1) * 0.5, Vector3(r0.distance_to(r1), 0.1, 9.0), "wood")
	for k in 5:
		var rz := -20.0 + float(k) * 2.0
		var q0: Vector3 = L.call(sx0 + 0.1, 3.6, rz)
		var q1: Vector3 = L.call(sx0 + 4.1, 2.86, rz)
		box_b(Basis(rx, rx.cross(bs.z).normalized() * -1.0, bs.z), (q0 + q1) * 0.5, Vector3(q0.distance_to(q1), 0.16, 0.14), "wood_dark", false)
	for hb: Vector3 in [Vector3(sx0 + 1.0, 0.45, -19.2), Vector3(sx0 + 1.0, 0.45, -17.9), Vector3(sx0 + 1.05, 1.25, -18.5), Vector3(sx0 + 2.3, 0.45, -19.3)]:
		box(L.call(hb.x, hb.y + 0.1, hb.z), Vector3(1.1, 0.8, 1.2), yaw + hb.z * 0.07, "straw")
	box(L.call(sx0 + 1.2, 0.42, -13.4), Vector3(0.7, 0.64, 2.2), yaw, "wood")
	box(L.call(sx0 + 1.2, 0.71, -13.4), Vector3(0.5, 0.08, 2.0), yaw, "iron", false)
	# Barrels by the gate, the keep and the stair.
	for bp: Vector3 in [Vector3(6.6, 0.1, 19.0), Vector3(7.5, 0.1, 19.3), Vector3(7.0, 0.1, 18.2), Vector3(-8.6, 0.1, 2.6), Vector3(-9.5, 0.1, 3.0), Vector3(16.0, 0.1, -17.5), Vector3(16.9, 0.1, -17.0), Vector3(-15.6, 0.1, 15.6)]:
		barrel(L.call(bp.x, bp.y, bp.z))
	# The quartermaster's stall: a striped awning over a trestle table.
	var stall: Vector3 = L.call(-9.0, 0.1, -3.4)
	for px: float in [-1.5, 1.5]:
		for pz: float in [-0.9, 0.9]:
			box(stall + bs * Vector3(px, 1.25 if pz > 0.0 else 1.05, pz), Vector3(0.12, 2.5 if pz > 0.0 else 2.1, 0.12), yaw, "wood_dark", false)
	var a0: Vector3 = stall + bs * Vector3(0, 2.52, 1.1)
	var a1: Vector3 = stall + bs * Vector3(0, 2.08, -1.15)
	var az := (a1 - a0).normalized()
	for k in 6:
		var ax := -1.5 + float(k) * 0.6
		box_b(Basis(bs.x, bs.x.cross(az).normalized() * -1.0, az), (a0 + a1) * 0.5 + bs.x * ax + Vector3(0, 0.02, 0), Vector3(0.6, 0.05, a0.distance_to(a1)), "banner_red" if k % 2 == 0 else "plaster", false)
	box(stall + bs * Vector3(0, 0.9, 0), Vector3(3.0, 0.1, 1.2), yaw, "wood")
	for px: float in [-1.3, 1.3]:
		box(stall + bs * Vector3(px, 0.45, 0), Vector3(0.12, 0.9, 1.0), yaw, "wood_dark", false)
	var cs3 := CollisionShape3D.new()
	var sh3 := BoxShape3D.new()
	sh3.size = Vector3(3.0, 0.95, 1.2)
	cs3.shape = sh3
	cs3.transform = Transform3D(bs, stall + Vector3(0, 0.475, 0))
	_body.add_child(cs3)
	_loot(stall + bs * Vector3(0.6, 1.0, 0), "gear")
	# Courtyard: a well, carts and crates for cover.
	var well: Vector3 = L.call(-11.0, 0, 9.0)
	cyl(well, 1.6, 1.6, 1.0, "stone", 12)
	cyl(well + Vector3(0, 1.0, 0), 1.25, 1.25, 0.02, "iron", 12, false)
	for sx: float in [-1.0, 1.0]:
		box(well + Vector3(0, 1.8, 0) + bs * Vector3(sx * 1.4, 0, 0), Vector3(0.2, 1.6, 0.2), yaw, "wood", false)
	box(well + Vector3(0, 2.65, 0), Vector3(3.2, 0.2, 0.3), yaw, "wood", false)
	_prop("Prop_Wagon", L.call(11.0, 0.1, 11.0), yaw + 0.4)
	_prop("Prop_Crate", L.call(12.5, 0.1, -12.0), yaw)
	_prop("Prop_Crate", L.call(13.6, 0.1, -11.4), yaw + 0.5)
	_prop("Prop_Crate", L.call(-13.0, 0.1, -13.0), yaw)
	_prop("Prop_Crate", L.call(5.0, 0.1, 15.0), yaw + 0.2)
	# (On the cobbles, which sit 0.1 m proud of the ground.)
	for p: Vector3 in [Vector3(-9, 0.1, 14), Vector3(9, 0.1, 4), Vector3(-13, 0.1, -2), Vector3(13, 0.1, -14), Vector3(0, 0.1, 17)]:
		_loot(L.call(p.x, p.y, p.z), "gear")
	for p: Vector3 in [Vector3(-15, 0.1, 6), Vector3(15, 0.1, 16)]:
		_loot(L.call(p.x, p.y, p.z), "weapon")
	# Walkway loot near the bastions.
	for sx: float in [-1.0, 1.0]:
		_loot(L.call(sx * half, wh + 0.0, sx * half), "gear", true)
	_end(2200.0)
	labels.append(["STORMKEEP", c + Vector2(0, -44.0)])
	clear_areas.append({"center": c, "radius": 40.0})


func _keep(o: Vector3, yaw: float) -> void:
	var bs := Basis(Vector3.UP, yaw)
	var L := func(x: float, y: float, z: float) -> Vector3:
		return o + bs * Vector3(x, y, z)
	var hf := 7.0
	var fh := 4.5
	var wt := 1.2
	var win := func(at: float) -> Array:
		return [at, 1.3, 1.1, 2.6]
	for lvl in 2:
		var y0 := fh * float(lvl)
		var front: Array = [win.call(3.5), win.call(10.5)]
		if lvl == 0:
			front = [[7.0, 2.4, 0.0, 3.3]]
		var faces: Array = [
			[Vector2(-hf, hf), Vector2(hf, hf), front],
			[Vector2(hf, hf), Vector2(hf, -hf), [win.call(7.0)]],
			[Vector2(hf, -hf), Vector2(-hf, -hf), [win.call(4.0), win.call(10.0)]],
			[Vector2(-hf, -hf), Vector2(-hf, hf), [win.call(7.0)]],
		]
		for f in faces:
			wall(o, yaw, f[0], f[1], y0, fh, wt, "stone", f[2])
			# Every window and the door get dressed stone round them.
			for op in f[2]:
				opening_frame(o, yaw, f[0], f[1], y0, wt, op, "trim")
	# Dressed corners, a string course between the floors and a corbel
	# table under the battlements.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			box(L.call(sx * hf, fh, sz * hf), Vector3(wt + 0.36, fh * 2.0, wt + 0.36), yaw, "trim", false)
	for cy: float in [fh, fh * 2.0 - 0.2]:
		for sz: float in [-1.0, 1.0]:
			box(L.call(0, cy, sz * hf), Vector3(hf * 2.0 + wt + 0.5, 0.34, wt + 0.3), yaw, "trim", false)
			box(L.call(sz * hf, cy, 0), Vector3(wt + 0.3, 0.34, hf * 2.0 + wt + 0.5), yaw, "trim", false)
	for k in 12:
		for sz: float in [-1.0, 1.0]:
			var cx := -hf + 0.9 + float(k) * (hf * 2.0 - 1.8) / 11.0
			box(L.call(cx, fh * 2.0 - 0.55, sz * (hf + wt * 0.5 + 0.12)), Vector3(0.34, 0.4, 0.3), yaw, "trim", false)
			box(L.call(sz * (hf + wt * 0.5 + 0.12), fh * 2.0 - 0.55, cx), Vector3(0.3, 0.4, 0.34), yaw, "trim", false)
	# The great door: two iron-bound leaves standing open into the hall.
	for sx: float in [-1.0, 1.0]:
		var leaf: Vector3 = L.call(sx * 1.28, 1.7, hf - wt * 0.5 - 0.68)
		box(leaf, Vector3(0.14, 3.2, 1.24), yaw, "wood_dark")
		for by: float in [-1.0, 0.0, 1.0]:
			box(leaf + Vector3(0, by * 1.15, 0), Vector3(0.18, 0.12, 1.26), yaw, "iron", false)
		# Torch beside the door outside.
		var tp: Vector3 = L.call(sx * 2.3, 2.5, hf + wt * 0.5 + 0.14)
		box(tp, Vector3(0.12, 0.5, 0.12), yaw, "iron", false)
		box(tp + Vector3(0, 0.38, 0), Vector3(0.22, 0.26, 0.22), yaw, "lamp", false)
	# Floors with stairwell holes (see the stair layout below).
	var inner := hf - wt * 0.5
	var slab := func(x0: float, x1: float, z0: float, z1: float, y: float, mat: String) -> void:
		box(L.call((x0 + x1) * 0.5, y - 0.2, (z0 + z1) * 0.5), Vector3(x1 - x0, 0.4, z1 - z0), yaw, mat)
	slab.call(-inner, inner, -inner, inner, 0.15, "block")
	# First floor: hole over the east stair (x 3.6..inner, z -5..0).
	slab.call(-inner, 3.6, -inner, inner, fh, "wood")
	slab.call(3.6, inner, 0.0, inner, fh, "wood")
	slab.call(3.6, inner, -inner, -5.0, fh, "wood")
	# Roof: hole over the west stair (x -inner..-3.6, z 0..5).
	slab.call(-3.6, inner, -inner, inner, fh * 2.0, "stone")
	slab.call(-inner, -3.6, -inner, 0.0, fh * 2.0, "stone")
	slab.call(-inner, -3.6, 5.0, inner, fh * 2.0, "stone")
	# Stairs: ground -> first along the east wall, first -> roof along the west.
	ramp(L.call(4.6, 0.15, 4.2), L.call(4.6, fh, -5.0), 1.9, "stone", 0.4, true)
	ramp(L.call(-4.6, fh, -4.2), L.call(-4.6, fh * 2.0, 5.0), 1.9, "stone", 0.4, true)
	# Roof terrace crenellations and a turret flag.
	var top := fh * 2.0
	for s in [[Vector2(-hf, hf), Vector2(hf, hf)], [Vector2(hf, hf), Vector2(hf, -hf)], [Vector2(hf, -hf), Vector2(-hf, -hf)], [Vector2(-hf, -hf), Vector2(-hf, hf)]]:
		var a2: Vector2 = s[0]
		var b2: Vector2 = s[1]
		var wa: Vector3 = L.call(a2.x, 0, a2.y)
		var wb: Vector3 = L.call(b2.x, 0, b2.y)
		merlons(Vector2(wa.x, wa.z), Vector2(wb.x, wb.z), o.y + top, 0.8)
	var tur: Vector3 = L.call(hf - 1.0, top, -hf + 1.0)
	cyl(tur, 2.2, 2.2, 4.5, "stone", 12)
	cyl(tur + Vector3(0, 4.5, 0), 2.8, 0.0, 4.0, "roof", 12, false)
	cyl(tur + Vector3(0, 8.3, 0), 0.08, 0.08, 3.0, "iron", 4, false)
	box(tur + Vector3(0, 10.6, 0) + bs * Vector3(0.9, 0, 0), Vector3(1.8, 1.0, 0.04), yaw, "banner_red", false)
	# Banners between the windows and the corners, not over the windows.
	for sx: float in [-1.0, 1.0]:
		banner(L.call(sx * 5.5, top - 0.5, hf + 0.62), bs * Vector3.BACK, 1.5, 6.0, "banner_red")
	# Two more corner turrets (clear of the roof stair's head at -x, +z).
	for tc2: Vector3 in [L.call(hf - 1.0, top, hf - 1.0), L.call(-hf + 1.0, top, -hf + 1.0)]:
		cyl(tc2, 1.6, 1.6, 3.4, "stone", 12)
		cyl(tc2 + Vector3(0, 3.4, 0), 2.1, 0.0, 3.4, "roof", 12, false)
		cyl(tc2 + Vector3(0, 6.6, 0), 0.06, 0.06, 1.6, "iron", 4, false)
	# Loot: the keep is the prize.
	for p: Vector3 in [Vector3(-3, 0.2, 2), Vector3(2, 0.2, -3), Vector3(-4, 0.2, -4)]:
		_loot(L.call(p.x, p.y, p.z), "weapon" if p.x < 0 else "gear")
	for p: Vector3 in [Vector3(-2, fh, 3), Vector3(1, fh, -2), Vector3(-5, fh, 5.5)]:
		_loot(L.call(p.x, p.y, p.z), "gear", true)
	_loot(L.call(0, fh, 0), "weapon", true)
	_loot(L.call(2, top, 2), "weapon", true)
	_loot(L.call(-1, top, -3), "gear", true)


# ------------------------------------------------------------------ Old Henge

func _build_henge() -> void:
	_begin("OldHenge")
	var c: Vector2 = terrain.henge_c
	var gy: float = terrain.henge_h
	var o := Vector3(c.x, gy, c.y)
	var n := 16
	var r := 13.0
	var standing: Array = []
	for i in n:
		var a := TAU * float(i) / float(n) + rng.randf_range(-0.04, 0.04)
		var p := o + Vector3(cos(a) * r, 0, sin(a) * r)
		var yaw := -a + PI * 0.5
		if rng.randf() < 0.18:
			# Fallen: lying on its side.
			box(p + Vector3(0, 0.55, 0), Vector3(4.6, 1.1, 1.7), yaw + rng.randf_range(-0.4, 0.4), "trim")
			standing.append(false)
			continue
		var h := rng.randf_range(4.0, 5.4)
		var lean := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, rng.randf_range(-0.08, 0.08))
		box_b(lean, p + Vector3(0, h * 0.5 - 0.4, 0), Vector3(1.9, h, 1.05), "trim")
		standing.append(h)
	# Lintels across neighbouring standing stones.
	for i in n:
		if i % 2 == 1:
			continue
		var j := (i + 1) % n
		if typeof(standing[i]) == TYPE_BOOL or typeof(standing[j]) == TYPE_BOOL:
			continue
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(j) / float(n)
		var am := (a0 + a1) * 0.5
		var top := minf(float(standing[i]), float(standing[j])) - 0.4
		box(o + Vector3(cos(am) * r, top + 0.45, sin(am) * r), Vector3(1.4, 0.9, r * TAU / float(n) + 1.6), -am, "trim")
	# Inner horseshoe of tall trilithons and the altar stone.
	for i in 5:
		var a := PI * 0.2 + PI * 1.6 * float(i) / 4.0
		var p := o + Vector3(cos(a) * 6.0, 0, sin(a) * 6.0)
		box(p + Vector3(0, 2.6, 0), Vector3(1.4, 6.0, 0.9), -a + PI * 0.5, "trim")
	box(o + Vector3(0, 0.45, 0), Vector3(3.4, 0.9, 1.6), rng.randf() * PI, "dark")
	_loot(o + Vector3(0, 0.9, 0), "weapon", true)
	_loot(o + Vector3(2.5, 0, 2.0), "gear")
	_loot(o + Vector3(-9.0, 0, 3.0), "gear")
	_loot(o + Vector3(4.0, 0, -9.5), "weapon")
	_end(1600.0)
	labels.append(["OLD HENGE", c + Vector2(0, -26.0)])
	clear_areas.append({"center": c, "radius": 18.0})


# ---------------------------------------------------------------- Gull Point

func _build_lighthouse() -> void:
	_begin("GullPoint")
	var c: Vector2 = terrain.lighthouse_c
	var gy: float = terrain.lighthouse_h
	var o := Vector3(c.x, gy, c.y)
	var height := 24.0
	cyl(o - Vector3(0, 1.0, 0), 6.0, 6.0, 1.6, "dark", 20)
	# Striped tower: plaster and red brick bands.
	var bands := 6
	for i in bands:
		var y0 := height * float(i) / float(bands)
		var r0 := lerpf(4.2, 3.2, float(i) / float(bands))
		var r1 := lerpf(4.2, 3.2, float(i + 1) / float(bands))
		cyl(o + Vector3(0, y0, 0), r0, r1, height / float(bands), "plaster" if i % 2 == 0 else "redbrick", 20, false)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 3.8
	shape.height = height
	cs.shape = shape
	cs.position = o + Vector3(0, height * 0.5, 0)
	_body.add_child(cs)
	# Gallery deck and railing.
	var deck := height + 0.5
	cyl(o + Vector3(0, height, 0), 5.3, 5.3, 0.5, "trim", 24)
	# Helical stair winding up around the outside: two turns.
	var turns := 2.0
	var segs := 64
	var hr := 6.15
	var start_a := rng.randf() * TAU
	var end_a := start_a + TAU * turns
	for i in segs:
		var a0 := lerpf(start_a, end_a, float(i) / float(segs))
		var a1 := lerpf(start_a, end_a, float(i + 1) / float(segs))
		var y0 := lerpf(0.0, deck, float(i) / float(segs))
		var y1 := lerpf(0.0, deck, float(i + 1) / float(segs))
		var p0 := o + Vector3(cos(a0) * hr, y0, sin(a0) * hr)
		var p1 := o + Vector3(cos(a1) * hr, y1, sin(a1) * hr)
		var dv := p1 - p0
		var hb := _frame(dv)
		var up := hb.y
		box_b(hb, (p0 + p1) * 0.5 - up * 0.18, Vector3(1.7, 0.36, dv.length() + 0.25), "trim")
		# A handrail and a knee rail between the posts, all the way up.
		var o0 := Vector3(cos(a0), 0, sin(a0)) * 0.8
		var o1 := Vector3(cos(a1), 0, sin(a1)) * 0.8
		for rh: float in [1.08, 0.56]:
			var q0 := p0 + o0 + Vector3(0, rh, 0)
			var q1 := p1 + o1 + Vector3(0, rh, 0)
			box_b(_frame(q1 - q0), (q0 + q1) * 0.5, Vector3(0.07, 0.07, q0.distance_to(q1) + 0.03), "iron", false)
		# Outer rail post and support bracket every other step.
		if i % 2 == 0:
			var outer := Vector3(cos(a0), 0, sin(a0))
			box(p0 + outer * 0.8 + Vector3(0, 0.55, 0), Vector3(0.12, 1.1, 0.12), -a0, "iron", false)
			var tr := lerpf(4.2, 3.2, clampf(y0 / height, 0.0, 1.0))
			var bl := hr - 0.85 - tr
			if bl > 0.05:
				box(o + outer * (tr + bl * 0.5) + Vector3(0, y0 - 0.3, 0), Vector3(bl + 0.2, 0.3, 0.3), -a0, "iron", false)
	# Gallery railing with a gap where the stair arrives.
	var rail_n := 24
	for i in rail_n:
		var a0 := TAU * float(i) / float(rail_n)
		var gap := absf(wrapf(a0 - end_a, -PI, PI))
		if gap < 0.5:
			continue
		var a1 := TAU * float(i + 1) / float(rail_n)
		var p0 := Vector2(c.x + cos(a0) * 5.1, c.y + sin(a0) * 5.1)
		var p1 := Vector2(c.x + cos(a1) * 5.1, c.y + sin(a1) * 5.1)
		var m := (p0 + p1) * 0.5
		box(Vector3(m.x, gy + deck + 0.55, m.y), Vector3(0.14, 1.1, p0.distance_to(p1) + 0.05), atan2(p1.x - p0.x, p1.y - p0.y), "iron")
	# Lantern room.
	cyl(o + Vector3(0, deck, 0), 2.4, 2.4, 0.8, "plaster", 16)
	cyl(o + Vector3(0, deck + 0.8, 0), 2.1, 2.1, 2.4, "lamp", 12, true)
	cyl(o + Vector3(0, deck + 3.2, 0), 2.7, 0.2, 2.4, "roof", 12, false)
	cyl(o + Vector3(0, deck + 5.5, 0), 0.25, 0.0, 1.0, "gold", 8, false)
	# Keeper's cottage at the foot.
	var cot := o + Vector3(cos(start_a + PI) * 12.0, 0, sin(start_a + PI) * 12.0)
	var cyaw := -start_a
	wall(cot, cyaw, Vector2(-4, 3), Vector2(4, 3), 0.0, 3.2, 0.6, "plaster", [[4.0, 1.4, 0.0, 2.3]])
	wall(cot, cyaw, Vector2(4, 3), Vector2(4, -3), 0.0, 3.2, 0.6, "plaster", [[3.0, 1.2, 1.0, 2.2]])
	wall(cot, cyaw, Vector2(4, -3), Vector2(-4, -3), 0.0, 3.2, 0.6, "plaster", [[4.0, 1.2, 1.0, 2.2]])
	wall(cot, cyaw, Vector2(-4, -3), Vector2(-4, 3), 0.0, 3.2, 0.6, "plaster", [])
	var cb := Basis(Vector3.UP, cyaw)
	box(cot + Vector3(0, 3.35, 0), Vector3(9.2, 0.3, 7.2), cyaw, "roof")
	_loot(o + Vector3(0, deck, 0) + Vector3(cos(end_a + 1.6) * 3.6, 0, sin(end_a + 1.6) * 3.6), "weapon", true)
	_loot(o + Vector3(0, deck, 0) + Vector3(cos(end_a + 3.0) * 3.6, 0, sin(end_a + 3.0) * 3.6), "gear", true)
	_loot(cot + cb * Vector3(-2.0, 0.1, 0.0), "weapon")
	_loot(cot + cb * Vector3(2.0, 0.1, -1.0), "gear")
	_end(2400.0)
	labels.append(["GULL POINT", c + Vector2(0, -26.0)])
	clear_areas.append({"center": c, "radius": 20.0})


# ------------------------------------------------------------------ Sunspire

func _build_temple() -> void:
	_begin("Sunspire")
	var c: Vector2 = terrain.temple_c
	var gy: float = terrain.temple_h
	var yaw := rng.randf() * TAU
	var bs := Basis(Vector3.UP, yaw)
	var o := Vector3(c.x, gy, c.y)
	var L := func(x: float, y: float, z: float) -> Vector3:
		return o + bs * Vector3(x, y, z)
	# Two-tier platform with a ramp stair on every side.
	box(L.call(0, 0.0, 0), Vector3(34, 2.4, 34), yaw, "trim")
	box(L.call(0, 1.8, 0), Vector3(29, 1.2, 29), yaw, "trim")
	for k in 4:
		var rot := Basis(Vector3.UP, yaw + PI * 0.5 * float(k))
		var foot := o + rot * Vector3(0, 0.0, 23.0)
		var head := o + rot * Vector3(0, 2.4, 14.5)
		ramp(foot, head, 5.0, "trim", 0.5, true)
	# Colonnade on the upper tier.
	var colr := 12.8
	for k in 4:
		var rot := Basis(Vector3.UP, yaw + PI * 0.5 * float(k))
		for i in 8:
			var along := -colr + float(i) * (colr * 2.0 / 7.0)
			if absf(along) < 2.5:
				continue
			var p := o + rot * Vector3(along, 2.4, colr)
			cyl(p, 0.75, 0.62, 7.0, "plaster", 12)
			box(p + Vector3(0, 7.15, 0), Vector3(1.7, 0.3, 1.7), yaw, "trim", false)
		# Architrave beam over the columns.
		box(o + rot * Vector3(0, 9.85, colr), Vector3(colr * 2.0 + 1.8, 0.9, 1.6), yaw + PI * 0.5 * float(k), "trim", false)
	# Sanctum: 10 x 10 with a door on every side.
	var hs := 5.0
	for k in 4:
		var rot_yaw := yaw + PI * 0.5 * float(k)
		wall(o + Vector3(0, 2.4, 0), rot_yaw, Vector2(-hs, hs), Vector2(hs, hs), 0.0, 6.0, 1.0, "stone", [[hs, 2.2, 0.0, 3.4]])
	box(L.call(0, 2.4 + 6.25, 0), Vector3(11.5, 0.5, 11.5), yaw, "trim")
	# The spire.
	var base: Vector3 = L.call(0, 8.9, 0)
	var tiers := [[7.0, 6.0], [5.4, 7.0], [4.0, 8.0]]
	var y := 0.0
	for t in tiers:
		var w: float = t[0]
		var h: float = t[1]
		box(base + Vector3(0, y + h * 0.5, 0), Vector3(w, h, w), yaw, "stone", false)
		box(base + Vector3(0, y + h + 0.2, 0), Vector3(w + 0.8, 0.4, w + 0.8), yaw, "trim", false)
		y += h + 0.4
	cyl(base + Vector3(0, y, 0), 2.6, 0.0, 9.0, "gold", 4, false)
	cyl(base + Vector3(0, y + 9.0, 0), 0.5, 0.0, 1.5, "gold", 8, false)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(7.0, y, 7.0)
	cs.shape = shape
	cs.transform = Transform3D(bs, base + Vector3(0, y * 0.5, 0))
	_body.add_child(cs)
	# Altar inside and braziers at the doors.
	box(L.call(0, 2.4 + 0.5, 0), Vector3(2.6, 1.0, 1.4), yaw, "dark")
	for k in 4:
		var rot := Basis(Vector3.UP, yaw + PI * 0.5 * float(k))
		lantern(o + rot * Vector3(3.2, 2.4, hs + 1.6), 1.3)
		lantern(o + rot * Vector3(-3.2, 2.4, hs + 1.6), 1.3)
	_loot(L.call(0, 3.4, 0), "weapon", true)
	_loot(L.call(2.5, 2.4, 2.5), "gear", true)
	_loot(L.call(-2.5, 2.4, -2.5), "gear", true)
	for p: Vector3 in [Vector3(9, 2.4, 9), Vector3(-9, 2.4, 9), Vector3(9, 2.4, -9), Vector3(-9, 2.4, -9)]:
		_loot(L.call(p.x, p.y, p.z), "weapon" if p.x > 0 else "gear")
	_end(2400.0)
	labels.append(["SUNSPIRE", c + Vector2(0, -34.0)])
	clear_areas.append({"center": c, "radius": 30.0})


# ----------------------------------------------------------------- Elder Oak

func _build_oak() -> void:
	_begin("ElderOak")
	var c: Vector2 = terrain.oak_c
	var gy: float = terrain.oak_h
	var o := Vector3(c.x, gy - 0.3, c.y)
	if not _mats.has("bark"):
		var bark := StandardMaterial3D.new()
		bark.albedo_texture = load("res://assets/nature/Bark_NormalTree.png")
		bark.albedo_color = Color(0.92, 0.85, 0.8)
		bark.roughness = 0.9
		bark.uv1_triplanar = true
		bark.uv1_world_triplanar = true
		bark.uv1_scale = Vector3.ONE * 0.35
		_mats["bark"] = bark
	# A great flared trunk.
	var prof := [[3.4, 0.0], [2.5, 1.2], [2.05, 3.0], [1.85, 6.0], [1.65, 9.0], [1.4, 12.0]]
	for k in prof.size() - 1:
		cyl(o + Vector3(0, float(prof[k][1]), 0), float(prof[k][0]), float(prof[k + 1][0]), float(prof[k + 1][1]) - float(prof[k][1]), "bark", 16, true, false)
	# Where the stair starts, chosen first so no root lands across its foot.
	var start_a := rng.randf() * TAU
	# Root buttresses spreading into the ground.
	for i in 7:
		var a := TAU * float(i) / 7.0 + rng.randf() * 0.3
		# Not across the stair's foot, nor under its first low steps.
		var off := wrapf(a - start_a, -PI, PI)
		if off > -1.0 and off < 1.6:
			continue
		var dir := Vector3(cos(a), 0, sin(a))
		var p0 := o + dir * 2.2 + Vector3.UP * 1.3
		var p1 := o + dir * rng.randf_range(5.0, 6.5) - Vector3.UP * 0.3
		box_b(_frame(p1 - p0), (p0 + p1) * 0.5, Vector3(0.9, 0.8, p0.distance_to(p1) + 0.4), "bark")
	# Thick branches out to the crown, each carrying a kit tree crown.
	var crowns := [["CommonTree_4", 2.9, Vector3(0, 9.5, 0), 0.0]]
	for i in 5:
		var a := TAU * float(i) / 5.0 + 0.4
		var dir := Vector3(cos(a), 0, sin(a))
		var b0 := o + Vector3.UP * 9.0 + dir * 1.2
		var b1 := o + Vector3.UP * rng.randf_range(10.0, 11.5) + dir * rng.randf_range(7.0, 8.8)
		box_b(_frame(b1 - b0), (b0 + b1) * 0.5, Vector3(0.8, 0.8, b0.distance_to(b1) + 0.3), "bark", false)
		crowns.append([["CommonTree_3", "CommonTree_5", "CommonTree_4"][i % 3], rng.randf_range(2.1, 2.6), b1 - o - Vector3.UP * 0.6, a])
	for spec in crowns:
		var packed: PackedScene = load("res://assets/nature/%s.gltf" % spec[0])
		var tree := packed.instantiate() as Node3D
		tree.scale = Vector3.ONE * float(spec[1])
		tree.position = o + (spec[2] as Vector3)
		tree.rotation.y = float(spec[3]) + rng.randf() * TAU
		_group.add_child(tree)
		for mi in tree.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).visibility_range_end = 2400.0
	# The treehouse: a ring deck round the trunk, a railing, lanterns.
	var deck_y := 7.0
	var inner := 1.95
	var outer := 5.3
	var segs := 18
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var am := (a0 + a1) * 0.5
		var r := (inner + outer) * 0.5
		var chord := 2.0 * outer * sin(PI / float(segs)) + 0.12
		box(o + Vector3(cos(am) * r, deck_y - 0.15, sin(am) * r), Vector3(outer - inner, 0.3, chord), -am, "wood")
		# Brackets under the deck.
		if i % 3 == 0:
			var p0 := o + Vector3(cos(am) * 1.9, deck_y - 2.6, sin(am) * 1.9)
			var p1 := o + Vector3(cos(am) * (outer - 0.4), deck_y - 0.35, sin(am) * (outer - 0.4))
			box_b(_frame(p1 - p0), (p0 + p1) * 0.5, Vector3(0.25, 0.25, p0.distance_to(p1)), "wood", false)
	# Spiral plank stair outside the deck, arriving at its edge.
	var hr := 6.2
	var turns := 1.15
	var end_a := start_a + TAU * turns
	var steps := 46
	# Start at the ground where the stair begins (the pad's edge can sit a
	# metre lower than its middle), not at a step you would have to climb.
	var sp0 := o + Vector3(cos(start_a) * hr, 0, sin(start_a) * hr)
	var y_start := minf(0.5, terrain.height_at(sp0.x, sp0.z) - o.y + 0.08)
	var stair_prev_y := -INF
	for i in steps:
		var t0 := float(i) / float(steps)
		var t1 := float(i + 1) / float(steps)
		var a0 := lerpf(start_a, end_a, t0)
		var a1 := lerpf(start_a, end_a, t1)
		var p0 := o + Vector3(cos(a0) * hr, lerpf(y_start, deck_y, t0), sin(a0) * hr)
		var p1 := o + Vector3(cos(a1) * hr, lerpf(y_start, deck_y, t1), sin(a1) * hr)
		# Never under the ground, and never stepping down: where the ground
		# rises along the way the stair rides on it.
		p0.y = maxf(maxf(p0.y, terrain.height_at(p0.x, p0.z) + 0.05), stair_prev_y)
		p1.y = maxf(maxf(p1.y, terrain.height_at(p1.x, p1.z) + 0.05), p0.y)
		stair_prev_y = p1.y
		var dv := p1 - p0
		var hb := _frame(dv)
		box_b(hb, (p0 + p1) * 0.5 - hb.y * 0.12, Vector3(1.8, 0.24, dv.length() + 0.2), "wood")
		if i % 3 == 0:
			var outdir := Vector3(cos(a0), 0, sin(a0))
			box(p0 + outdir * 0.85 + Vector3(0, 0.5, 0), Vector3(0.12, 1.0, 0.12), -a0, "wood", false)
			if p0.y - (o.y + 0.3) > 1.2:
				var gp := Vector3(p0.x, terrain.height_at(p0.x, p0.z), p0.z)
				box(Vector3(gp.x, (gp.y + p0.y) * 0.5 - 0.2, gp.z) + outdir * 0.6, Vector3(0.22, p0.y - gp.y, 0.22), -a0, "wood", false)
	# Where the ground falls away before the first step (the tree stands on a
	# hillside on some islands), a short ramp up to it instead of a ledge.
	var first := o + Vector3(cos(start_a) * hr, maxf(y_start, terrain.height_at(o.x + cos(start_a) * hr, o.z + sin(start_a) * hr) - o.y + 0.05), sin(start_a) * hr)
	for back in [0.3, 0.45]:
		var pa := start_a - float(back)
		var pre := o + Vector3(cos(pa) * hr, 0, sin(pa) * hr)
		pre.y = terrain.height_at(pre.x, pre.z) + 0.04
		if first.y - pre.y > 0.25:
			ramp(pre, first, 1.8, "wood", 0.3)
			break
	# Deck railing with a gap where the stair arrives.
	var rn := 24
	for i in rn:
		var a0 := TAU * float(i) / float(rn)
		if absf(wrapf(a0 - end_a, -PI, PI)) < 0.42:
			continue
		var a1 := TAU * float(i + 1) / float(rn)
		var q0 := Vector2(c.x + cos(a0) * (outer - 0.1), c.y + sin(a0) * (outer - 0.1))
		var q1 := Vector2(c.x + cos(a1) * (outer - 0.1), c.y + sin(a1) * (outer - 0.1))
		var m := (q0 + q1) * 0.5
		box(Vector3(m.x, o.y + deck_y + 0.5, m.y), Vector3(0.14, 1.0, q0.distance_to(q1) + 0.05), atan2(q1.x - q0.x, q1.y - q0.y), "wood")
	for i in 6:
		var a := TAU * float(i) / 6.0 + 0.2
		var lp := o + Vector3(cos(a) * 4.6, deck_y + 2.6, sin(a) * 4.6)
		box(lp + Vector3(0, 0.6, 0), Vector3(0.04, 1.2, 0.04), 0.0, "iron", false)
		box(lp, Vector3(0.32, 0.42, 0.32), a, "lamp", false)
		if i % 2 == 0:
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.75, 0.42)
			l.light_energy = 1.4
			l.omni_range = 9.0
			l.shadow_enabled = false
			l.distance_fade_enabled = true
			l.distance_fade_begin = 140.0
			l.distance_fade_length = 50.0
			l.position = lp
			_group.add_child(l)
	# An old shrine ring round the tree, with mushrooms.
	# Standing stones: a plinth, a shaft narrowing as it rises and leaning a
	# little with age, a cap of moss, and a faint rune facing the tree.
	if not _mats.has("oak_rune"):
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color(0.45, 0.9, 0.75)
		rm.emission_enabled = true
		rm.emission = Color(0.35, 0.95, 0.7)
		rm.emission_energy_multiplier = 1.6
		_mats["oak_rune"] = rm
		var mm := StandardMaterial3D.new()
		mm.albedo_color = Color(0.24, 0.36, 0.14)
		mm.roughness = 1.0
		_mats["oak_moss"] = mm
	for i in 9:
		var a := TAU * float(i) / 9.0
		var p := Vector3(c.x + cos(a) * 11.5, 0, c.y + sin(a) * 11.5)
		p.y = terrain.height_at(p.x, p.z) - 0.3
		var lean := Basis(Vector3.UP, -a) * Basis(Vector3(1, 0, rng.randf_range(-0.4, 0.4)).normalized(), rng.randf_range(-0.07, 0.07))
		var hgt := rng.randf_range(2.3, 3.1)
		box(p + Vector3(0, 0.25, 0), Vector3(1.4, 0.6, 1.1), -a, "trim")
		box_b(lean, p + lean * Vector3(0, 0.55 + hgt * 0.3, 0), Vector3(1.0, hgt * 0.6, 0.72), "trim")
		box_b(lean, p + lean * Vector3(0, 0.55 + hgt * 0.6 + hgt * 0.2, 0), Vector3(0.78, hgt * 0.4, 0.6), "trim")
		box_b(lean, p + lean * Vector3(0, 0.55 + hgt + 0.04, 0), Vector3(0.82, 0.1, 0.64), "oak_moss", false)
		# The rune on the face toward the tree (the stone's local -x points in).
		box_b(lean, p + lean * Vector3(0, 0.55 + hgt * 0.45, 0) - Vector3(cos(a), 0, sin(a)) * 0.515, Vector3(0.05, 0.5, 0.22), "oak_rune", false)
	var shroom: PackedScene = load("res://assets/nature/Mushroom_Common.gltf")
	for i in 14:
		var a := rng.randf() * TAU
		var m := shroom.instantiate() as Node3D
		var r := rng.randf_range(4.0, 9.0)
		m.position = Vector3(c.x + cos(a) * r, terrain.height_at(c.x + cos(a) * r, c.y + sin(a) * r) - 0.05, c.y + sin(a) * r)
		m.scale = Vector3.ONE * rng.randf_range(0.8, 1.8)
		m.rotation.y = rng.randf() * TAU
		_group.add_child(m)
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).visibility_range_end = 90.0
	_loot(o + Vector3(cos(end_a + 2.0) * 3.6, deck_y + 0.3, sin(end_a + 2.0) * 3.6), "weapon", true)
	_loot(o + Vector3(cos(end_a + 3.6) * 3.6, deck_y + 0.3, sin(end_a + 3.6) * 3.6), "gear", true)
	_loot(o + Vector3(7.5, 0.4, 0), "gear")
	_loot(o + Vector3(-6.0, 0.4, 5.0), "weapon")
	oak_stair = [o, hr, start_a, end_a, deck_y, y_start]
	_end(2000.0)
	labels.append(["ELDER OAK", c + Vector2(0, -22.0)])
	clear_areas.append({"center": c, "radius": 14.0})
