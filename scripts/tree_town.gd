extends RefCounted
class_name TreeTown

## Treetop Town: one gigantic tree, ~110 m to the top of its crown, with a
## town built round its trunk. Three ring decks of huts (18, 38 and 58 m up)
## and a crow's nest deck at 74 m whose rope bridges run out to lookouts on
## the big branches. One spiral stair climbs the trunk past every deck from
## the roots to the crow's nest. Everything you can see is solid: the trunk,
## roots, decks, hut walls and roofs, railings and stair.

const TRUNK := [[0.0, 15.0], [2.5, 11.4], [7.0, 9.6], [20.0, 8.7], [40.0, 7.7], [60.0, 6.7], [76.0, 5.6], [88.0, 4.4]]
const DECKS := [[18.0, 13.0, 5], [38.0, 11.0, 4], [58.0, 9.0, 3], [74.0, 6.0, 0]]
const STAIR_W := 3.0
const STAIR_GAP := 0.3
const NEST_Y := 74.0
const LOOKOUT_R := 26.0

var ft: Fantasy
var lm: Landmarks
var terrain: Terrain
var rng: RandomNumberGenerator
var c := Vector2.ZERO
var o := Vector3.ZERO
var stair_a0 := 0.0
var stair_turns := 0.0
## Points up the spiral stair, bottom to top: [Vector3, ...] (for bots).
var helix: Array = []
## Huts for bots finding the door: {level, a, r, w, d}.
var huts: Array = []


static func trunk_r(y: float) -> float:
	for k in TRUNK.size() - 1:
		var y0: float = TRUNK[k][0]
		var y1: float = TRUNK[k + 1][0]
		if y <= y1:
			return lerpf(float(TRUNK[k][1]), float(TRUNK[k + 1][1]), clampf((y - y0) / (y1 - y0), 0.0, 1.0))
	return float(TRUNK[TRUNK.size() - 1][1])


# ------------------------------------------------------------- for bots --
## Deck height (above the base) a point stands on, or -1 on the stair/ground.
func level_of(p: Vector3) -> float:
	var y := p.y - o.y
	for d in DECKS:
		if absf(y - float(d[0])) < 0.6:
			return float(d[0])
	return -1.0


func angle_of(p: Vector3) -> float:
	return atan2(p.z - o.z, p.x - o.x)


## The walkway round a deck: just outside the stair lane, inside the huts.
func walk_r(level: float) -> float:
	return trunk_r(level) + STAIR_GAP + STAIR_W + 0.85


func ring_points(level: float, a_from: float, a_to: float) -> Array:
	var da := wrapf(a_to - a_from, -PI, PI)
	var n := maxi(1, int(ceil(absf(da) / 0.3)))
	var r := walk_r(level)
	var out: Array = []
	for k in range(1, n + 1):
		var a := a_from + da * float(k) / float(n)
		out.append(o + Vector3(cos(a) * r, level + 0.1, sin(a) * r))
	return out


## The hut a point is inside, or {}.
func hut_at(p: Vector3) -> Dictionary:
	var lv := level_of(p)
	if lv < 0.0:
		return {}
	var a := angle_of(p)
	var r := Vector2(p.x - o.x, p.z - o.z).length()
	for h in huts:
		if absf(float(h.level) - lv) > 0.5:
			continue
		var tang := wrapf(a - float(h.a), -PI, PI) * r
		if absf(r - float(h.r)) < float(h.d) * 0.5 + 0.15 and absf(tang) < float(h.w) * 0.5 + 0.15:
			return h
	return {}


## Just inside and just outside a hut's door (it faces the trunk).
func hut_door(h: Dictionary) -> Array:
	var ri := float(h.r) - float(h.d) * 0.5
	var dir := Vector3(cos(float(h.a)), 0, sin(float(h.a)))
	var up := Vector3.UP * (float(h.level) + 0.1)
	return [o + dir * (ri + 0.75) + up, o + dir * (ri - 0.7) + up]


## Index of the first point up the stair at or above `level`.
func helix_index(level: float) -> int:
	for i in helix.size():
		if (helix[i] as Vector3).y > o.y + level + 0.15:
			return i
	return helix.size() - 1


func build(p_ft: Fantasy, p_c: Vector2) -> void:
	ft = p_ft
	lm = ft.lm
	terrain = ft.terrain
	rng = ft.rng
	c = p_c
	var pad := ft._claim(c, 46.0, "TREETOP TOWN", "treetown")
	o = Vector3(c.x, pad - 0.4, c.y)
	lm._begin("TreetopTown")
	_bark_mat()
	stair_a0 = rng.randf() * TAU
	_build_stair_table()
	_trunk()
	_roots()
	_stair()
	for i in DECKS.size():
		_deck(i)
	_lookouts()
	_crowns()
	lm._end(3200.0)
	lm.clear_areas.append({"center": c, "radius": 46.0})


func _bark_mat() -> void:
	if lm._mats.has("bark"):
		return
	var bark := StandardMaterial3D.new()
	bark.albedo_texture = load("res://assets/nature/Bark_NormalTree.png")
	bark.albedo_color = Color(0.92, 0.85, 0.8)
	bark.roughness = 0.9
	bark.uv1_triplanar = true
	bark.uv1_world_triplanar = true
	bark.uv1_scale = Vector3.ONE * 0.35
	lm._mats["bark"] = bark


func _trunk() -> void:
	for k in TRUNK.size() - 1:
		var y0: float = TRUNK[k][0]
		var y1: float = TRUNK[k + 1][0]
		lm.cyl(o + Vector3(0, y0, 0), float(TRUNK[k][1]), float(TRUNK[k + 1][1]), y1 - y0, "bark", 28, true, k == TRUNK.size() - 2)


## The stair keeps one comfortable slope along its middle line, so it winds
## tighter as the trunk narrows (a fixed rise per turn made the top, round the
## thin part of the trunk, too steep to walk). Height of the walking surface
## at angle `a` (unwrapped from the start angle), and the angle at height `y`,
## from a table built once.
const STAIR_SLOPE := 30.0
const STAIR_Y0 := 0.35
const TAB_DY := 0.25
var _tab_a := PackedFloat32Array()


func _build_stair_table() -> void:
	_tab_a.clear()
	var a := stair_a0
	var y := STAIR_Y0
	var k := 1.0 / tan(deg_to_rad(STAIR_SLOPE))
	_tab_a.append(a)
	while y < NEST_Y:
		a += TAB_DY * k / stair_mid_r(y + TAB_DY * 0.5)
		y += TAB_DY
		_tab_a.append(a)
	stair_turns = (a - stair_a0) / TAU


func stair_angle(y: float) -> float:
	var f := clampf((y - STAIR_Y0) / TAB_DY, 0.0, float(_tab_a.size() - 1))
	var i := mini(int(f), _tab_a.size() - 2)
	return lerpf(_tab_a[i], _tab_a[i + 1], f - float(i))


func stair_y(a: float) -> float:
	if a <= _tab_a[0]:
		return STAIR_Y0
	if a >= _tab_a[_tab_a.size() - 1]:
		return minf(NEST_Y, STAIR_Y0 + TAB_DY * float(_tab_a.size() - 1))
	var lo := 0
	var hi := _tab_a.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if _tab_a[mid] <= a:
			lo = mid
		else:
			hi = mid
	var t := (a - _tab_a[lo]) / maxf(_tab_a[hi] - _tab_a[lo], 0.00001)
	return minf(NEST_Y, STAIR_Y0 + TAB_DY * (float(lo) + t))


func stair_mid_r(y: float) -> float:
	return trunk_r(y) + STAIR_GAP + STAIR_W * 0.5


func _roots() -> void:
	for i in 11:
		var a := TAU * float(i) / 11.0 + rng.randf_range(-0.12, 0.12)
		# Keep the foot of the stair clear.
		if absf(wrapf(a - stair_a0, -PI, PI)) < 0.55:
			continue
		var dir := Vector3(cos(a), 0, sin(a))
		var p0 := o + dir * 10.5 + Vector3.UP * 4.0
		var reach := rng.randf_range(20.0, 26.0)
		var p1 := Vector3(o.x, 0, o.z) + dir * reach
		p1.y = terrain.height_at(p1.x, p1.z) - 0.6
		_limb(p0, p1, 2.6, 0.9, true)


func _stair() -> void:
	var a_end := stair_angle(NEST_Y)
	var steps := int(ceil(stair_turns * 150.0))
	helix.clear()
	for i in steps:
		var a0 := lerpf(stair_a0, a_end, float(i) / float(steps))
		var a1 := lerpf(stair_a0, a_end, float(i + 1) / float(steps))
		var y0 := stair_y(a0)
		var y1 := stair_y(a1)
		var r0 := stair_mid_r(y0)
		var r1 := stair_mid_r(y1)
		var p0 := o + Vector3(cos(a0) * r0, y0, sin(a0) * r0)
		var p1 := o + Vector3(cos(a1) * r1, y1, sin(a1) * r1)
		_ramp_piece(a0, a1, y0, y1)
		if i % 4 == 0:
			helix.append(p0 + Vector3.UP * 0.1)
		# Outer handrail: posts and a solid rail, so a sprint up does not end
		# with a fall. Not where the stair passes a deck: you step off there.
		var on_deck := false
		for d in DECKS:
			if absf(y0 - float(d[0])) < 1.6:
				on_deck = true
		if not on_deck:
			var outd0 := Vector3(cos(a0), 0, sin(a0))
			var outd1 := Vector3(cos(a1), 0, sin(a1))
			var q0 := p0 + outd0 * (STAIR_W * 0.5 - 0.1) + Vector3.UP * 1.0
			var q1 := p1 + outd1 * (STAIR_W * 0.5 - 0.1) + Vector3.UP * 1.0
			lm.box_b(lm._frame(q1 - q0), (q0 + q1) * 0.5, Vector3(0.1, 0.1, q0.distance_to(q1) + 0.06), "wood")
			if i % 6 == 0:
				lm.box(q0 - Vector3.UP * 0.5, Vector3(0.12, 1.0, 0.12), -a0, "wood", false)
	# A flat landing past the top step, under the part of the nest deck that
	# was opened for the stair.
	for k in 3:
		_ramp_piece(a_end + 0.1 * float(k), a_end + 0.1 * float(k + 1), NEST_Y, NEST_Y)
	helix.append(o + Vector3(cos(a_end) * stair_mid_r(NEST_Y), NEST_Y + 0.45, sin(a_end) * stair_mid_r(NEST_Y)))


## One piece of the spiral ramp, built on the exact corners its neighbours
## share (straight slabs on a curve leave a lip at every joint on the inner
## edge, and a lip on a slope is a wall to whoever walks up it).
func _ramp_piece(a0: float, a1: float, y0: float, y1: float) -> void:
	var d0 := Vector3(cos(a0), 0, sin(a0))
	var d1 := Vector3(cos(a1), 0, sin(a1))
	var i0 := trunk_r(y0) + STAIR_GAP
	var i1 := trunk_r(y1) + STAIR_GAP
	var up0 := Vector3.UP * y0
	var up1 := Vector3.UP * y1
	var t := Vector3.UP * 0.3
	var in0 := o + d0 * i0 + up0
	var out0 := o + d0 * (i0 + STAIR_W) + up0
	var in1 := o + d1 * i1 + up1
	var out1 := o + d1 * (i1 + STAIR_W) + up1
	var st := lm._surface("wood")
	var nrm := (out0 - in0).cross(in1 - in0).normalized()
	if nrm.y < 0.0:
		nrm = -nrm
	lm._quad(st, in0, out0, out1, in1, nrm)
	lm._quad(st, in0 - t, in1 - t, out1 - t, out0 - t, -nrm)
	lm._quad(st, out0, out0 - t, out1 - t, out1, d0)
	lm._quad(st, in0, in1, in1 - t, in0 - t, -d0)
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([in0, out0, in1, out1, in0 - t, out0 - t, in1 - t, out1 - t])
	cs.shape = shape
	lm._body.add_child(cs)
	lm._stat.shapes += 1


## A ring deck round the trunk, cut where the stair comes through, its outer
## part carrying huts, with a railing and lanterns.
func _deck(idx: int) -> void:
	var y: float = DECKS[idx][0]
	var width: float = DECKS[idx][1]
	var huts: int = DECKS[idx][2]
	var tr := trunk_r(y)
	var inner := tr - 0.4
	var lane := tr + STAIR_GAP + STAIR_W + 0.15
	var outer := tr + width
	var segs := 64
	var arrive := stair_angle(y)
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var am := (a0 + a1) * 0.5
		# Inner lane: open wherever the stair is within head height of the
		# deck, so it climbs through. The deck top is the stair surface there.
		var ys := _stair_y_near(am, y)
		var clash := ys > y - 4.4 and ys < y + 2.4
		if not clash:
			_ring_piece(y, inner, lane, am, a1 - a0)
		_ring_piece(y, lane, outer, am, a1 - a0)
		# Brackets under the outer edge, back to the trunk.
		if i % 8 == 0:
			var b0 := o + Vector3(cos(am) * (tr + 0.2), y - 6.0, sin(am) * (tr + 0.2))
			var b1 := o + Vector3(cos(am) * (outer - 0.6), y - 0.45, sin(am) * (outer - 0.6))
			lm.box_b(lm._frame(b1 - b0), (b0 + b1) * 0.5, Vector3(0.45, 0.45, b0.distance_to(b1)), "wood", false)
	# Railing round the outer edge, open where a rope bridge leaves.
	var bridges := bridge_angles() if idx == DECKS.size() - 1 else []
	var rn := 96
	for i in rn:
		var a0 := TAU * float(i) / float(rn)
		var a1 := TAU * float(i + 1) / float(rn)
		var skip := false
		for ba in bridges:
			# Open just the bridge's own width.
			if absf(wrapf((a0 + a1) * 0.5 - float(ba), -PI, PI)) < 1.0 / outer:
				skip = true
		if skip:
			continue
		var q0 := Vector3(cos(a0), 0, sin(a0)) * (outer - 0.12)
		var q1 := Vector3(cos(a1), 0, sin(a1)) * (outer - 0.12)
		var m := o + (q0 + q1) * 0.5 + Vector3(0, y + 0.55, 0)
		lm.box(m, Vector3(0.14, 1.1, q0.distance_to(q1) + 0.05), atan2(q1.x - q0.x, q1.z - q0.z), "wood")
	# Huts round the outer part, doors facing the trunk, none over the stair.
	var hut_r := (lane + outer) * 0.5 + 0.2
	for k in huts:
		var a := arrive + PI / float(huts) + TAU * float(k) / float(huts)
		if absf(wrapf(a - arrive, -PI, PI)) < 0.5:
			a += 0.55
		_hut(o + Vector3(cos(a) * hut_r, y, sin(a) * hut_r), a, minf(width - STAIR_W - 2.2, 5.2), idx)
	# Lanterns hanging off the trunk.
	for i in 6:
		var a := TAU * float(i) / 6.0 + 0.3 + float(idx)
		var lp := o + Vector3(cos(a) * (tr + 0.5), y + 2.8, sin(a) * (tr + 0.5))
		lm.box(lp, Vector3(0.36, 0.46, 0.36), a, "lamp", false)
		if i % 2 == 0:
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.74, 0.42)
			l.light_energy = 1.6
			l.omni_range = 11.0
			l.shadow_enabled = false
			l.distance_fade_enabled = true
			l.distance_fade_begin = 160.0
			l.distance_fade_length = 60.0
			l.position = lp + Vector3(cos(a) * 0.4, 0, sin(a) * 0.4)
			lm._group.add_child(l)
	if idx == DECKS.size() - 1:
		lm._loot(o + Vector3(cos(arrive + 1.4) * (tr + 3.0), y + 0.3, sin(arrive + 1.4) * (tr + 3.0)), "weapon", true)
		lm._loot(o + Vector3(cos(arrive + 3.3) * (tr + 3.0), y + 0.3, sin(arrive + 3.3) * (tr + 3.0)), "gear", true)


func _stair_y_near(a: float, y: float) -> float:
	# The stair passes this angle once per turn: the pass nearest `y`.
	var best := INF
	var k := stair_angle(y)
	for t in [-1, 0, 1]:
		var aa: float = a + TAU * float(t) + TAU * round((k - a) / TAU)
		# A piece just past the top of the stair still covers its last
		# stretch: it counts as over the stair's end.
		if aa < stair_a0 or aa > stair_angle(NEST_Y) + 0.16:
			continue
		var ys := stair_y(minf(aa, stair_angle(NEST_Y)))
		if absf(ys - y) < absf(best - y):
			best = ys
	return best


func _ring_piece(y: float, r0: float, r1: float, am: float, da: float) -> void:
	var rm := (r0 + r1) * 0.5
	var chord := 2.0 * r1 * sin(da * 0.5) + 0.1
	# Local X runs out from the trunk (Basis(UP, -am) turns X onto the radius).
	lm.box(o + Vector3(cos(am) * rm, y - 0.25, sin(am) * rm), Vector3(r1 - r0, 0.5, chord), -am, "wood")


## A small timber house on the deck: door to the walkway, a window on each
## side and at the back, a gabled roof, loot inside.
func _hut(p: Vector3, a: float, size: float, level: int) -> void:
	var w := size
	var d := size * 0.9
	huts.append({"level": p.y - o.y, "a": a, "r": Vector2(p.x - o.x, p.z - o.z).length(), "w": w, "d": d})
	var h := 2.9
	# Local frame: +Z points out from the trunk; the door is on -Z.
	var yaw := -a + PI * 0.5
	var bs := Basis(Vector3.UP, yaw)
	var walls := [
		[Vector2(-w * 0.5, -d * 0.5), Vector2(w * 0.5, -d * 0.5), [[w * 0.5, 1.3, 0.0, 2.2]]],
		[Vector2(w * 0.5, -d * 0.5), Vector2(w * 0.5, d * 0.5), [[d * 0.5, 1.1, 1.0, 1.9]]],
		[Vector2(w * 0.5, d * 0.5), Vector2(-w * 0.5, d * 0.5), [[w * 0.5, 1.4, 1.0, 1.9]]],
		[Vector2(-w * 0.5, d * 0.5), Vector2(-w * 0.5, -d * 0.5), [[d * 0.5, 1.1, 1.0, 1.9]]],
	]
	var mat := "plaster" if level % 2 == 0 else "wood"
	for wl in walls:
		lm.wall(p, yaw, wl[0], wl[1], 0.0, h, 0.22, mat, wl[2])
	# Corner posts.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			lm.box(p + bs * Vector3(sx * w * 0.5, h * 0.5, sz * d * 0.5), Vector3(0.3, h, 0.3), yaw, "wood", false)
	# Gable roof: two slabs meeting at a ridge over the long side.
	var rise := 1.5
	for side in [-1.0, 1.0]:
		var e0 := p + bs * Vector3(side * (w * 0.5 + 0.45), h - 0.15, 0)
		var e1 := p + bs * Vector3(0, h + rise, 0)
		var across := (e1 - e0)
		var fwd := bs.z
		var bx := across.normalized()
		var by := bx.cross(fwd).normalized()
		if by.y < 0.0:
			by = -by
		lm.box_b(Basis(bx, by, fwd), (e0 + e1) * 0.5, Vector3(across.length() + 0.15, 0.2, d + 0.9), "roof")
	# Gable ends.
	for sz in [-1.0, 1.0]:
		lm.box(p + bs * Vector3(0, h + rise * 0.35, sz * d * 0.5), Vector3(w * 0.55, rise * 0.7, 0.2), yaw, mat)
	lm._loot(p + bs * Vector3(-w * 0.2, 0.25, d * 0.15), "weapon" if (level + int(a * 10.0)) % 2 == 0 else "gear", level >= 2)
	lm._loot(p + bs * Vector3(w * 0.22, 0.25, d * 0.2), "gear" if level == 0 else "weapon", level >= 2)


func bridge_angles() -> Array:
	# Clear of the stair's last stretch below the nest (it climbs the
	# quarter-turn before `arrive`), so no branch crosses over someone on it.
	var arrive := stair_angle(NEST_Y)
	return [arrive + 1.2, arrive + 2.9, arrive + 4.6]


## Lookouts on the three great branches at crow's-nest height, each reached
## by a rope bridge from the nest deck.
func _lookouts() -> void:
	var outer := trunk_r(NEST_Y) + float(DECKS[DECKS.size() - 1][1])
	for ba in bridge_angles():
		var a := float(ba)
		var dir := Vector3(cos(a), 0, sin(a))
		var center := o + dir * LOOKOUT_R + Vector3.UP * NEST_Y
		var pr := 5.0
		# The branch carrying it, from the trunk out under the platform.
		var b0 := o + dir * (trunk_r(NEST_Y - 2.6) - 0.5) + Vector3.UP * (NEST_Y - 2.6)
		var b1 := center - Vector3.UP * 1.5 + dir * 2.0
		_limb(b0, b1, 1.6, 1.1, true)
		# Round platform.
		lm.cyl(center - Vector3.UP * 0.5, pr, pr, 0.5, "wood", 16, true)
		for i in 32:
			var q0 := Vector3(cos(TAU * i / 32.0), 0, sin(TAU * i / 32.0)) * (pr - 0.1)
			var q1 := Vector3(cos(TAU * (i + 1) / 32.0), 0, sin(TAU * (i + 1) / 32.0)) * (pr - 0.1)
			var mid := (q0 + q1) * 0.5
			# Gap facing the bridge, as wide as the bridge.
			if acos(clampf(mid.normalized().dot(-dir), -1.0, 1.0)) < 1.0 / pr:
				continue
			lm.box(center + mid + Vector3.UP * 0.55, Vector3(0.14, 1.1, q0.distance_to(q1) + 0.05), atan2(q1.x - q0.x, q1.z - q0.z), "wood")
		# A little roof on posts: shade, and something to see from far off.
		for k in 4:
			var pa := a + PI * 0.25 + TAU * float(k) / 4.0
			lm.box(center + Vector3(cos(pa), 0, sin(pa)) * (pr - 0.8) + Vector3.UP * 1.4, Vector3(0.25, 2.8, 0.25), 0.0, "wood", false)
		lm.cyl(center + Vector3.UP * 2.8, pr + 0.4, 0.0, 2.2, "roof", 12, true)
		# Rope bridge: planks and two rope rails from the nest edge across.
		var s0 := o + dir * (outer - 0.3) + Vector3.UP * NEST_Y
		var s1 := center - dir * (pr - 0.2)
		var n := int(s0.distance_to(s1) / 0.7)
		var side := Vector3(-dir.z, 0, dir.x)
		# Posts at both ends close the corners between bridge and railings.
		for e in [s0, s1]:
			for sd in [-1.0, 1.0]:
				lm.box((e as Vector3) + side * float(sd) * 1.05 + Vector3.UP * 0.55, Vector3(0.16, 1.1, 0.16), -a, "wood")
		for k in n:
			var t0 := float(k) / float(n)
			var t1 := float(k + 1) / float(n)
			var sag0 := sin(t0 * PI) * 0.35
			var sag1 := sin(t1 * PI) * 0.35
			var q0 := s0.lerp(s1, t0) - Vector3.UP * sag0
			var q1 := s0.lerp(s1, t1) - Vector3.UP * sag1
			lm.box_b(lm._frame(q1 - q0), (q0 + q1) * 0.5 - Vector3.UP * 0.1, Vector3(2.0, 0.12, q0.distance_to(q1) + 0.04), "wood")
			for sd in [-1.0, 1.0]:
				var r0: Vector3 = q0 + side * float(sd) + Vector3.UP * 1.0
				var r1: Vector3 = q1 + side * float(sd) + Vector3.UP * 1.0
				lm.box_b(lm._frame(r1 - r0), (r0 + r1) * 0.5, Vector3(0.07, 0.07, r0.distance_to(r1) + 0.03), "wood")
		lm._loot(center + dir * 1.5 + Vector3.UP * 0.05, "weapon", true)


## A tapered round limb from `a` (radius r0) to `b` (radius r1).
func _limb(a: Vector3, b: Vector3, r0: float, r1: float, collide := false, sides := 10) -> void:
	var axis := (b - a).normalized()
	var u := axis.cross(Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT).normalized()
	var v := axis.cross(u).normalized()
	var st := lm._surface("bark")
	var pts := PackedVector3Array()
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		var n := (u * cos((a0 + a1) * 0.5) + v * sin((a0 + a1) * 0.5)).normalized()
		lm._quad(st, a + d0 * r0, a + d1 * r0, b + d1 * r1, b + d0 * r1, n)
		pts.append(a + d0 * r0)
		pts.append(b + d0 * r1)
	# Cap the thin end so a limb seen end-on is not hollow.
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		lm._tri(st, b, b + (u * cos(a0) + v * sin(a0)) * r1, b + (u * cos(a1) + v * sin(a1)) * r1, axis)
	if collide:
		var cs := CollisionShape3D.new()
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		cs.shape = shape
		lm._body.add_child(cs)
		lm._stat.shapes += 1


## Just the leaves of a kit tree, centred on themselves: a foliage cluster.
func _leaf_mesh(name: String) -> ArrayMesh:
	var packed: PackedScene = load("res://assets/nature/%s.gltf" % name)
	var inst := packed.instantiate()
	var out := ArrayMesh.new()
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		for si in m.get_surface_count():
			var mat := m.surface_get_material(si)
			if mat == null or not mat.resource_name.contains("Leaves"):
				continue
			var arr := m.surface_get_arrays(si)
			for p in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				lo = lo.min(p)
				hi = hi.max(p)
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			out.surface_set_material(out.get_surface_count() - 1, mat)
	inst.free()
	# Re-centre on the cluster so it can be placed by its middle.
	var ctr := (lo + hi) * 0.5
	var shifted := ArrayMesh.new()
	for si in out.get_surface_count():
		var arr := out.surface_get_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for k in vs.size():
			vs[k] -= ctr
		arr[Mesh.ARRAY_VERTEX] = vs
		shifted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		shifted.surface_set_material(si, out.surface_get_material(si))
	return shifted


func _crowns() -> void:
	# A dome of foliage ~80 m across over the crow's nest, carried by great
	# limbs from the top of the trunk: the town lives in its shade.
	var meshes := [_leaf_mesh("CommonTree_4"), _leaf_mesh("CommonTree_3"), _leaf_mesh("CommonTree_5")]
	var top := o + Vector3.UP * 84.0
	var clusters: Array = [[Vector3(0, 104, 0), 9.5]]
	for i in 6:
		var a := TAU * float(i) / 6.0 + 0.3
		clusters.append([Vector3(cos(a) * 15.0, rng.randf_range(97.0, 102.0), sin(a) * 15.0), rng.randf_range(8.0, 9.0)])
	for i in 11:
		var a := TAU * float(i) / 11.0 + rng.randf_range(-0.1, 0.1)
		var r := rng.randf_range(28.0, 34.0)
		clusters.append([Vector3(cos(a) * r, rng.randf_range(87.0, 93.0), sin(a) * r), rng.randf_range(7.0, 8.2)])
	for i in 9:
		var a := TAU * float(i) / 9.0 + 0.35
		var r := rng.randf_range(37.0, 41.0)
		clusters.append([Vector3(cos(a) * r, rng.randf_range(81.0, 85.0), sin(a) * r), rng.randf_range(5.5, 6.5)])
	var k := 0
	for cl in clusters:
		var at: Vector3 = o + (cl[0] as Vector3)
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[k % meshes.size()]
		k += 1
		mi.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.0, 0.8, 1.0) * float(cl[1])), at)
		mi.visibility_range_end = 3400.0
		lm._group.add_child(mi)
		# A limb out to every cluster beyond the middle, from the top of the
		# trunk, thick at the trunk and thinning out.
		var flat := Vector3((cl[0] as Vector3).x, 0, (cl[0] as Vector3).z)
		if flat.length() > 10.0:
			var start := top + flat.normalized() * 3.2 + Vector3.UP * rng.randf_range(-6.0, 2.0)
			_limb(start, at - Vector3.UP * 4.0, 2.2 if flat.length() < 30.0 else 1.6, 0.5)
	# The trunk carries on up into the crown.
	_limb(o + Vector3.UP * 87.0, o + Vector3.UP * 100.0, 4.4, 2.2)
