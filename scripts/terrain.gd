extends RefCounted
class_name Terrain

## Deterministic world heightfield: a large main island, a smaller east island
## across a strait (joined by a bridge), sea cliffs on the south coast and a
## high plateau with a lake that spills over a waterfall. All world queries go
## through this class so spawning, loot, AI and collision agree on the ground.

const SIZE := 2400.0
const HALF := 1200.0
const RES := 401
const STEP := SIZE / float(RES - 1)   # 6 m
const WATER_LEVEL := 0.9
const CHUNK_CELLS := 40
const CHUNKS := 10

# Island layout.
const MAIN_C := Vector2(-260.0, 30.0)
const MAIN_R := 760.0
const EAST_C := Vector2(905.0, -150.0)
const EAST_R := 250.0

# Highfalls plateau: cliff walls all round, a lake on top, a waterfall off the
# south-east edge into a pool.
const PLATEAU_C := Vector2(-560.0, -300.0)
const PLATEAU_R := 165.0
const PLATEAU_H := 78.0
const LAKE_C := Vector2(-530.0, -280.0)
const LAKE_R := 58.0
const BAY_C := Vector2(-760.0, 560.0)
const BAY_R := 230.0

var heights := PackedFloat32Array()
var hills := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var ridge := FastNoiseLite.new()
var macro := FastNoiseLite.new()
var woods := FastNoiseLite.new()
var ridgelines := FastNoiseLite.new()
var coast := FastNoiseLite.new()
var warp := FastNoiseLite.new()
var peaks: Array[Vector3] = []  # x, z, amplitude
var seed_value: int = 20261101

## Landmark data filled in during generation, read by the builders.
var bridge_a := Vector2.ZERO
var bridge_b := Vector2.ZERO
var bridge_h := 0.0
var lake_level := 0.0
var falls_top := Vector3.ZERO
var falls_bottom := Vector3.ZERO
var pool_c := Vector2.ZERO
var pool_r := 22.0
var pool_level := 0.0
var falls_dir := Vector2.RIGHT
var channel_a := Vector2.ZERO
var channel_b := Vector2.ZERO
## River centre line and cumulative arc length.
var river: Array[Vector2] = []
var river_s: Array[float] = []
var river_len := 0.0
var fords: Array[Vector2] = []
var gorge_bridge := Vector2.ZERO
var gorge_bridge_dir := Vector2.RIGHT
var trails: Array[Vector2] = []
var castle_c := Vector2.ZERO
var castle_h := 0.0
var henge_c := Vector2.ZERO
var henge_h := 0.0
var lighthouse_c := Vector2.ZERO
var lighthouse_h := 0.0
var temple_c := Vector2.ZERO
var temple_h := 0.0
var oak_c := Vector2.ZERO
var oak_h := 0.0
## Areas the town planner must keep clear of: [Vector2 centre, radius].
var reserved: Array = []


func _init(p_seed: int = 20261101) -> void:
	seed_value = p_seed

	hills.seed = p_seed
	hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hills.frequency = 0.0024
	hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	hills.fractal_octaves = 4
	hills.fractal_gain = 0.52

	detail.seed = p_seed + 91
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail.frequency = 0.0125
	detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail.fractal_octaves = 3

	ridge.seed = p_seed + 501
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.frequency = 0.0055
	ridge.fractal_octaves = 4

	macro.seed = p_seed + 7
	macro.noise_type = FastNoiseLite.TYPE_SIMPLEX
	macro.frequency = 0.0032
	macro.fractal_octaves = 3

	woods.seed = p_seed + 313
	woods.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	woods.frequency = 0.0030
	woods.fractal_octaves = 4

	ridgelines.seed = p_seed + 777
	ridgelines.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridgelines.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridgelines.frequency = 0.0032
	ridgelines.fractal_octaves = 3

	coast.seed = p_seed + 4040
	coast.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	coast.frequency = 0.0028
	coast.fractal_octaves = 3

	warp.seed = p_seed + 5150
	warp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	warp.frequency = 0.0011
	warp.fractal_octaves = 2

	# Hills: a fixed backbone plus seed-placed ones, so every map differs.
	peaks = [
		Vector3(-200.0, 380.0, 46.0),
		Vector3(160.0, -260.0, 38.0),
		Vector3(-760.0, 260.0, 34.0),
		Vector3(240.0, 420.0, 30.0),
		Vector3(880.0, -40.0, 26.0),
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed + 99
	for i in 8:
		var a := rng.randf() * TAU
		var r := rng.randf_range(80.0, MAIN_R * 0.75)
		peaks.append(Vector3(MAIN_C.x + cos(a) * r, MAIN_C.y + sin(a) * r, rng.randf_range(16.0, 32.0)))
	heights.resize(RES * RES)
	_generate()
	_carve_landmarks()


func _island_mask(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var n := coast.get_noise_2d(x, z)
	# Domain warp so the coast wanders into bays and headlands instead of
	# tracing a circle.
	var w := Vector2(warp.get_noise_2d(x, z), warp.get_noise_2d(x + 913.0, z - 377.0)) * 120.0
	var q := p + w
	var dm := q - MAIN_C
	var rm := Vector2(dm.x / (MAIN_R * 0.99), dm.y / (MAIN_R * 0.95)).length() + n * 0.12
	# Kestrel Bay bites into the south-west coast.
	var bay := 1.0 - smoothstep(BAY_R * 0.75, BAY_R * 1.15, q.distance_to(BAY_C))
	rm += bay * 0.45
	var de := q - EAST_C
	var re := Vector2(de.x / (EAST_R * 1.12), de.y / (EAST_R * 0.9)).length() + n * 0.16
	# South coast of the main island ends in sheer cliffs: a much narrower
	# land-to-sea transition there.
	var cliff := _south_cliff(x, z)
	var width := lerpf(0.15, 0.022, cliff)
	var main := smoothstep(1.0, 1.0 - width, rm)
	var east := smoothstep(1.0, 0.86, re)
	return maxf(main, east)


func _south_cliff(x: float, z: float) -> float:
	var ang := (Vector2(x, z) - MAIN_C).angle()
	return smoothstep(0.55, 0.8, sin(ang))


func _generate() -> void:
	for iz in RES:
		var z := -HALF + float(iz) * STEP
		for ix in RES:
			var x := -HALF + float(ix) * STEP
			var land := _island_mask(x, z)
			var h := -14.0
			if land > 0.0:
				var r := ridge.get_noise_2d(x, z)
				var lh := 12.0 + hills.get_noise_2d(x, z) * 22.0 + detail.get_noise_2d(x, z) * 4.5
				for p in peaks:
					var dx := x - p.x
					var dz := z - p.y
					var d2 := dx * dx + dz * dz
					if d2 > 270.0 * 270.0:
						continue
					var m := 1.0 - sqrt(d2) / 270.0
					m = m * m * (3.0 - 2.0 * m)
					lh += p.z * m * (0.55 + 0.45 * r)
				var rl := ridgelines.get_noise_2d(x, z) * 0.5 + 0.5
				lh += pow(clampf((rl - 0.55) / 0.45, 0.0, 1.0), 1.6) * 12.0
				# Cliff coast: hold the land up right to the edge so the drop
				# is sheer.
				var cliff := _south_cliff(x, z) * smoothstep(MAIN_R * 0.5, MAIN_R * 0.8, Vector2(x, z).distance_to(MAIN_C))
				lh += cliff * 20.0
				lh = maxf(lh, 3.0)
				h = lerpf(-14.0, lh, land)
			heights[iz * RES + ix] = h


## Rim radius of the plateau in a given direction: a lumpy massif, not a disc.
func plateau_rim(ang: float) -> float:
	return PLATEAU_R + coast.get_noise_2d(cos(ang) * 260.0, sin(ang) * 260.0) * 60.0 \
		+ detail.get_noise_2d(cos(ang) * 900.0, sin(ang) * 900.0) * 8.0


func _plateau_top(x: float, z: float) -> float:
	# Rises toward the back (north-west) so the top is not a table.
	var back := Vector2(x, z) - PLATEAU_C
	return PLATEAU_H + 1.5 + back.dot(Vector2(-0.7, -0.7)) * 0.025 + absf(detail.get_noise_2d(x, z)) * 3.0


## Plateau, lake, waterfall, river gorge, bridge headlands and landmark sites.
## Done after the base terrain so they can read and reshape it.
func _carve_landmarks() -> void:
	# --- Highfalls: a cliff-walled massif with a lake on top.
	_apply(PLATEAU_C, PLATEAU_R + 150.0, func(x: float, z: float, h: float) -> float:
		var v := Vector2(x, z) - PLATEAU_C
		var rim := plateau_rim(v.angle())
		var d := v.length()
		var t := smoothstep(rim + 22.0, rim - 2.0, d)
		# A talus apron at the cliff foot.
		var apron := smoothstep(rim + 70.0, rim + 18.0, d) * 10.0
		return lerpf(maxf(h, h + apron), maxf(h, _plateau_top(x, z)), t))
	reserved.append([PLATEAU_C, PLATEAU_R + 70.0])

	# Two ledge trails wind up the cliff face so the top can be reached on foot.
	for spec in [[0.75, -1.1], [2.9, 1.0]]:
		_carve_trail(float(spec[0]), float(spec[1]))

	lake_level = PLATEAU_H - 3.5
	_apply(LAKE_C, LAKE_R + 30.0, func(x: float, z: float, h: float) -> float:
		var v := Vector2(x, z) - LAKE_C
		var lr := LAKE_R + coast.get_noise_2d(v.x * 4.0, v.y * 4.0) * 10.0
		var t := smoothstep(lr + 12.0, lr * 0.4, v.length())
		return lerpf(h, PLATEAU_H - 10.0, t))

	# Outlet channel from the lake to the rim, then a long fall into the gorge.
	falls_dir = Vector2(0.35, 0.94).normalized()
	var p := LAKE_C
	for i in 200:
		p += falls_dir * 2.0
		if height_at(p.x, p.y) < PLATEAU_H - 6.0 and p.distance_to(PLATEAU_C) > PLATEAU_R * 0.6:
			break
	var lip := p - falls_dir * 10.0
	_carve_channel(LAKE_C + falls_dir * (LAKE_R - 10.0), lip, 6.0, 2.2)
	channel_a = LAKE_C + falls_dir * (LAKE_R - 10.0)
	channel_b = lip
	falls_top = Vector3(lip.x, lake_level, lip.y)
	pool_c = lip + falls_dir * 55.0
	pool_level = WATER_LEVEL

	# --- The river: from the plunge pool, through a gorge, out to the north sea.
	_plan_river()
	_carve_river()
	falls_bottom = Vector3(lip.x + falls_dir.x * 14.0, WATER_LEVEL, lip.y + falls_dir.y * 14.0)

	# --- Bridge headlands: raised bluffs at each end so the span runs high
	# above the strait.
	var dir := (EAST_C - MAIN_C).normalized()
	bridge_a = _coast_point(MAIN_C, dir, 1.0) - dir * 25.0
	bridge_b = _coast_point(EAST_C, -dir, 1.0) + dir * 25.0
	bridge_h = 34.0
	for c in [bridge_a, bridge_b]:
		_apply(c, 75.0, func(x: float, z: float, h: float) -> float:
			var d := Vector2(x, z).distance_to(c)
			var t := smoothstep(75.0, 30.0, d)
			return lerpf(h, maxf(h, bridge_h - 0.3), t))
		reserved.append([c, 65.0])
	# Keep towns off the strait line itself.
	reserved.append([(bridge_a + bridge_b) * 0.5, bridge_a.distance_to(bridge_b) * 0.5 + 20.0])

	# --- Landmark sites.
	castle_c = _settle(Vector2(-150.0, 330.0), 34.0)
	castle_h = _raise_mound(castle_c, 34.0, 26.0, 6.0)
	reserved.append([castle_c, 85.0])
	henge_c = _settle(Vector2(-830.0, 170.0), 18.0)
	henge_h = flatten_circle(henge_c.x, henge_c.y, 18.0, 16.0)
	reserved.append([henge_c, 50.0])
	# Lighthouse on the south cliffs, a few metres in from the edge.
	var sdir := Vector2(0.25, 1.0).normalized()
	lighthouse_c = _coast_point(MAIN_C, sdir, 1.0) - sdir * 16.0
	lighthouse_h = flatten_circle(lighthouse_c.x, lighthouse_c.y, 9.0, 10.0)
	reserved.append([lighthouse_c, 40.0])
	temple_c = _settle(EAST_C + Vector2(40.0, 10.0), 24.0)
	temple_h = flatten_circle(temple_c.x, temple_c.y, 24.0, 18.0)
	reserved.append([temple_c, 60.0])
	oak_c = _settle(Vector2(140.0, -380.0), 12.0)
	oak_h = flatten_circle(oak_c.x, oak_c.y, 12.0, 14.0)
	reserved.append([oak_c, 35.0])


## Walk from `from` along `dir` until the ground drops under `above` metres.
func _coast_point(from: Vector2, dir: Vector2, above: float) -> Vector2:
	# The last land before at least 60 m of open sea.
	var p := from
	var last_land := from
	var sea_run := 0.0
	for i in 1200:
		p += dir * 2.0
		if height_at(p.x, p.y) < above:
			sea_run += 2.0
			if sea_run >= 60.0:
				return last_land
		else:
			sea_run = 0.0
			last_land = p
	return last_land


## Nudge a site toward the island centre until it is on usable land.
func _settle(c: Vector2, radius: float) -> Vector2:
	var p := c
	for i in 40:
		if height_at(p.x, p.y) > 5.0 and roughness(p.x, p.y, radius) < 14.0 and not _near_river(p, radius + 30.0):
			return p
		p = p.lerp(MAIN_C if p.distance_to(MAIN_C) < p.distance_to(EAST_C) else EAST_C, 0.08)
	return p


## Castle motte: a flat top a little above the local ground with steep sides.
func _raise_mound(c: Vector2, radius: float, shoulder: float, lift: float) -> float:
	var top := 0.0
	for i in 12:
		var a := TAU * float(i) / 12.0
		top = maxf(top, height_at(c.x + cos(a) * radius, c.y + sin(a) * radius))
	top += lift
	return flatten_circle(c.x, c.y, radius, shoulder, top)


## A ledge trail cut into the plateau cliff, rising as it winds round.
func _carve_trail(start_ang: float, sweep: float) -> void:
	var steps := 90
	var ground0 := 0.0
	var pts: Array = []
	for i in steps + 1:
		var t := float(i) / float(steps)
		var ang := start_ang + sweep * t
		var rim := plateau_rim(ang)
		var r := lerpf(rim + 26.0, rim - 10.0, smoothstep(0.0, 1.0, t))
		var c := PLATEAU_C + Vector2(cos(ang), sin(ang)) * r
		if i == 0:
			ground0 = height_at(c.x, c.y)
		pts.append([c, t])
	var top := PLATEAU_H - 1.0
	for e in pts:
		var c: Vector2 = e[0]
		var t: float = e[1]
		var y := lerpf(ground0, top, t)
		_apply(c, 12.0, func(x: float, z: float, h: float) -> float:
			var d := Vector2(x, z).distance_to(c)
			var k := smoothstep(11.0, 5.0, d)
			return lerpf(h, y, k))
	trails.append(pts[0][0])


func _carve_channel(a: Vector2, b: Vector2, width: float, depth: float) -> void:
	var len := a.distance_to(b)
	var steps := int(len / 3.0) + 1
	for i in steps + 1:
		var c := a.lerp(b, float(i) / float(steps))
		_apply(c, width + 4.0, func(x: float, z: float, h: float) -> float:
			var d := Vector2(x, z).distance_to(c)
			var t := smoothstep(width + 3.0, width * 0.4, d)
			return lerpf(h, minf(h, lake_level - depth), t))


## River centre line: from the plunge pool, bending north to the sea.
func _plan_river() -> void:
	var ctrl: Array[Vector2] = [
		pool_c,
		pool_c + falls_dir * 50.0,
		Vector2(-400.0, 110.0),
		Vector2(-450.0, 270.0),
		Vector2(-570.0, 390.0),
		Vector2(-700.0, 480.0),
		Vector2(-860.0, 640.0),
	]
	# Catmull-Rom through the control points, then meander.
	river.clear()
	for i in ctrl.size() - 1:
		var p0: Vector2 = ctrl[maxi(i - 1, 0)]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[i + 1]
		var p3: Vector2 = ctrl[mini(i + 2, ctrl.size() - 1)]
		var n := int(p1.distance_to(p2) / 12.0) + 1
		for j in n:
			var t := float(j) / float(n)
			var t2 := t * t
			var t3 := t2 * t
			var q := 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
			river.append(q)
	river.append(ctrl[ctrl.size() - 1])
	# Meander perpendicular to the flow.
	var s := 0.0
	for i in river.size():
		if i > 0:
			s += river[i].distance_to(river[i - 1])
		river_s.append(s)
		if i > 4 and i < river.size() - 1:
			var fwd := (river[i + 1] - river[i - 1]).normalized()
			river[i] += fwd.orthogonal() * detail.get_noise_1d(s * 0.4) * 28.0
	river_len = s
	# Crossings: two shallow fords and a gorge bridge between them.
	for f in [0.28, 0.68]:
		fords.append(_river_point(f * river_len))
	gorge_bridge = _river_point(0.48 * river_len)
	gorge_bridge_dir = _river_dir(0.48 * river_len).orthogonal()
	var k := 0.0
	while k < river_len:
		reserved.append([_river_point(k), 45.0])
		k += 35.0


func _river_point(s: float) -> Vector2:
	for i in range(1, river.size()):
		if river_s[i] >= s:
			var t := (s - river_s[i - 1]) / maxf(0.001, river_s[i] - river_s[i - 1])
			return river[i - 1].lerp(river[i], t)
	return river[river.size() - 1]


func _river_dir(s: float) -> Vector2:
	return (_river_point(s + 6.0) - _river_point(s - 6.0)).normalized()


## Nearest point on the river: returns [distance, arc length].
func river_query(p: Vector2) -> Vector2:
	var best := 1e9
	var best_s := 0.0
	for i in range(1, river.size()):
		var a: Vector2 = river[i - 1]
		var b: Vector2 = river[i]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(0.001, ab.length_squared()), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best:
			best = d
			best_s = lerpf(river_s[i - 1], river_s[i], t)
	return Vector2(best, best_s)


## Unit vector across the river at the nearest point to `p`.
func river_across(p: Vector2) -> Vector2:
	return _river_dir(river_query(p).y).orthogonal()


func _near_river(p: Vector2, margin: float) -> bool:
	if river.is_empty():
		return false
	return river_query(p).x < margin


## Bed half-width, bank width and bed depth along the river.
func river_profile(s: float) -> Vector3:
	var bed := 8.0 + detail.get_noise_1d(s * 0.9 + 50.0) * 3.0
	var bank := 40.0 + detail.get_noise_1d(s * 0.6 + 400.0) * 16.0
	var floor_y := -1.7
	# The plunge pool under the falls.
	var pool := smoothstep(70.0, 10.0, s)
	bed = lerpf(bed, 24.0, pool)
	bank = lerpf(bank, 22.0, pool)
	# Shallow, wide fords.
	for f in [0.28, 0.68]:
		var k := smoothstep(70.0, 10.0, absf(s - f * river_len))
		bank = lerpf(bank, 95.0, k)
		floor_y = lerpf(floor_y, -0.25, k)
	# A narrow rock gorge where the old bridge spans it.
	var g := smoothstep(70.0, 15.0, absf(s - 0.48 * river_len))
	bank = lerpf(bank, 15.0, g)
	bed = lerpf(bed, 7.0, g)
	# Widening into an estuary at the sea.
	var mouth := smoothstep(river_len - 120.0, river_len, s)
	bed = lerpf(bed, 30.0, mouth)
	return Vector3(bed, bank, floor_y)


func _carve_river() -> void:
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for p in river:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var pad := 120.0
	var x0 := clampi(int(floor((lo.x - pad + HALF) / STEP)), 0, RES - 1)
	var x1 := clampi(int(ceil((hi.x + pad + HALF) / STEP)), 0, RES - 1)
	var z0 := clampi(int(floor((lo.y - pad + HALF) / STEP)), 0, RES - 1)
	var z1 := clampi(int(ceil((hi.y + pad + HALF) / STEP)), 0, RES - 1)
	for iz in range(z0, z1 + 1):
		var wz := -HALF + float(iz) * STEP
		for ix in range(x0, x1 + 1):
			var wx := -HALF + float(ix) * STEP
			var q := river_query(Vector2(wx, wz))
			if q.x > 115.0:
				continue
			var prof := river_profile(q.y)
			var t := smoothstep(prof.x + prof.y, prof.x, q.x)
			if t <= 0.0:
				continue
			# Rock gorges are steep-sided: sharpen the profile there.
			var idx := iz * RES + ix
			heights[idx] = lerpf(heights[idx], minf(heights[idx], prof.z), t * t * (3.0 - 2.0 * t))


## Runs `f(x, z, h) -> h` over every grid sample within `radius` of `c`.
func _apply(c: Vector2, radius: float, f: Callable) -> void:
	var x0 := clampi(int(floor((c.x - radius + HALF) / STEP)), 0, RES - 1)
	var x1 := clampi(int(ceil((c.x + radius + HALF) / STEP)), 0, RES - 1)
	var z0 := clampi(int(floor((c.y - radius + HALF) / STEP)), 0, RES - 1)
	var z1 := clampi(int(ceil((c.y + radius + HALF) / STEP)), 0, RES - 1)
	for iz in range(z0, z1 + 1):
		var wz := -HALF + float(iz) * STEP
		for ix in range(x0, x1 + 1):
			var wx := -HALF + float(ix) * STEP
			var idx := iz * RES + ix
			heights[idx] = f.call(wx, wz, heights[idx])


func height_at(x: float, z: float) -> float:
	var fx := (x + HALF) / STEP
	var fz := (z + HALF) / STEP
	var ix := clampi(int(floor(fx)), 0, RES - 2)
	var iz := clampi(int(floor(fz)), 0, RES - 2)
	var tx := clampf(fx - float(ix), 0.0, 1.0)
	var tz := clampf(fz - float(iz), 0.0, 1.0)
	var h00 := heights[iz * RES + ix]
	var h10 := heights[iz * RES + ix + 1]
	var h01 := heights[(iz + 1) * RES + ix]
	var h11 := heights[(iz + 1) * RES + ix + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## Height of the rendered triangle under (x, z). Cells are split along the
## 10-01 diagonal, matching WorldBuilder._chunk_mesh.
func mesh_height_at(x: float, z: float) -> float:
	var fx := (x + HALF) / STEP
	var fz := (z + HALF) / STEP
	var ix := clampi(int(floor(fx)), 0, RES - 2)
	var iz := clampi(int(floor(fz)), 0, RES - 2)
	var tx := clampf(fx - float(ix), 0.0, 1.0)
	var tz := clampf(fz - float(iz), 0.0, 1.0)
	var h00 := heights[iz * RES + ix]
	var h10 := heights[iz * RES + ix + 1]
	var h01 := heights[(iz + 1) * RES + ix]
	var h11 := heights[(iz + 1) * RES + ix + 1]
	if tx + tz <= 1.0:
		return h00 + (h10 - h00) * tx + (h01 - h00) * tz
	return h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz)


func normal_at(x: float, z: float) -> Vector3:
	var e := STEP
	var hl := height_at(x - e, z)
	var hr := height_at(x + e, z)
	var hd := height_at(x, z - e)
	var hu := height_at(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


func slope_at(x: float, z: float) -> float:
	return 1.0 - normal_at(x, z).y


## Water surface height at a point: the sea, or the plateau lake / falls pool.
func water_surface_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	if p.distance_to(LAKE_C) < LAKE_R + 22.0:
		return lake_level
	var ab := channel_b - channel_a
	var t := clampf((p - channel_a).dot(ab) / maxf(0.001, ab.length_squared()), 0.0, 1.0)
	if p.distance_to(channel_a + ab * t) < 9.0:
		return lake_level
	return WATER_LEVEL


## Walking grid for bots on the 6 m height grid: cells too steep to walk up
## are shut, water costs more (swimming is slow). Paths only go round cliffs;
## houses, rocks and trees are left to the bots' own steering.
var nav: AStarGrid2D
const NAV_STEEP_NY := 0.7
const NAV_SEARCHES_PER_FRAME := 3
var _nav_frame := -1
var nav_blocked := 0
var _nav_calls := 0


func build_nav() -> void:
	nav = AStarGrid2D.new()
	nav.region = Rect2i(0, 0, RES, RES)
	nav.cell_size = Vector2(STEP, STEP)
	nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	nav.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	nav.update()
	nav_blocked = 0
	var e2 := 2.0 * STEP
	for iz in RES:
		var r0 := maxi(iz - 1, 0) * RES
		var r1 := mini(iz + 1, RES - 1) * RES
		var row := iz * RES
		for ix in RES:
			var dx: float = heights[row + maxi(ix - 1, 0)] - heights[row + mini(ix + 1, RES - 1)]
			var dz: float = heights[r0 + ix] - heights[r1 + ix]
			if e2 / sqrt(dx * dx + e2 * e2 + dz * dz) < NAV_STEEP_NY:
				nav.set_point_solid(Vector2i(ix, iz))
				nav_blocked += 1
			else:
				var x := -HALF + float(ix) * STEP
				var z := -HALF + float(iz) * STEP
				if heights[row + ix] < water_surface_at(x, z):
					nav.set_point_weight_scale(Vector2i(ix, iz), 4.0)


func _nav_cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(round((p.x + HALF) / STEP)), 0, RES - 1), clampi(int(round((p.y + HALF) / STEP)), 0, RES - 1))


func _nav_open_near(c: Vector2i) -> Vector2i:
	if not nav.is_point_solid(c):
		return c
	for r in range(1, 5):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var q := Vector2i(clampi(c.x + dx, 0, RES - 1), clampi(c.y + dz, 0, RES - 1))
				if not nav.is_point_solid(q):
					return q
	return c


## Points to walk through to get from one place to another without walking
## into a cliff. Empty when the straight line is fine. Returns null (as
## an empty array with ok = false) when this frame's search budget is spent.
func walk_path(from: Vector2, to: Vector2) -> Dictionary:
	if nav == null:
		build_nav()
	var d := from.distance_to(to)
	var n := int(d / (STEP * 0.7)) + 1
	var clear := true
	for i in range(1, n + 1):
		if nav.is_point_solid(_nav_cell(from.lerp(to, float(i) / float(n)))):
			clear = false
			break
	if clear:
		return {"ok": true, "path": PackedVector2Array()}
	var f := Engine.get_physics_frames()
	if f != _nav_frame:
		_nav_frame = f
		_nav_calls = 0
	if _nav_calls >= NAV_SEARCHES_PER_FRAME:
		return {"ok": false, "path": PackedVector2Array()}
	_nav_calls += 1
	var ids := nav.get_id_path(_nav_open_near(_nav_cell(from)), _nav_open_near(_nav_cell(to)), true)
	var out := PackedVector2Array()
	for k in range(1, ids.size()):
		var c: Vector2i = ids[k]
		out.append(Vector2(-HALF + float(c.x) * STEP, -HALF + float(c.y) * STEP))
	if out.is_empty() or out[out.size() - 1].distance_to(to) > STEP * 1.5:
		return {"ok": true, "path": out}
	out[out.size() - 1] = to
	return {"ok": true, "path": out}


func is_water(x: float, z: float) -> bool:
	return height_at(x, z) < water_surface_at(x, z)


func flatness_ok(x: float, z: float, max_slope: float = 0.30) -> bool:
	return slope_at(x, z) < max_slope


func forest_density(x: float, z: float) -> float:
	return woods.get_noise_2d(x, z) * 0.5 + 0.5


func is_reserved(c: Vector2, margin: float) -> bool:
	for r in reserved:
		if c.distance_to(r[0]) < float(r[1]) + margin:
			return true
	return false


## A random spot on dry, walkable land.
func random_land_point(rng: RandomNumberGenerator, min_h := 2.0, max_slope := 0.35) -> Vector2:
	for i in 80:
		var c := Vector2(rng.randf_range(-HALF + 30.0, HALF - 30.0), rng.randf_range(-HALF + 30.0, HALF - 30.0))
		var h := height_at(c.x, c.y)
		if h < min_h or is_water(c.x, c.y) or slope_at(c.x, c.y) > max_slope:
			continue
		return c
	return MAIN_C


## Soft circular terrace used for villages and POIs.
func flatten_circle(cx: float, cz: float, radius: float, shoulder: float = 22.0, target: float = NAN) -> float:
	var goal := target
	if is_nan(goal):
		var sum := 0.0
		var count := 0
		var step := 4.0
		var s := -radius
		while s <= radius:
			var t := -radius
			while t <= radius:
				if s * s + t * t <= radius * radius:
					sum += height_at(cx + s, cz + t)
					count += 1
				t += step
			s += step
		goal = sum / maxf(1.0, float(count))
		# A terrace by the shore averages in the sea bed: never level ground
		# to below the water it stands beside (that drowned a whole city), and
		# keep it above the beach so it grows grass, not sand.
		var dry := water_surface_at(cx, cz) + 2.9
		if goal < dry - 1.6:
			print("[terrain] terrace at (%.0f, %.0f) r=%.0f raised from %.2f to %.2f to stay dry" % [cx, cz, radius, goal, dry])
			goal = dry

	var outer := radius + shoulder
	var x0 := int(floor((cx - outer + HALF) / STEP))
	var x1 := int(ceil((cx + outer + HALF) / STEP))
	var z0 := int(floor((cz - outer + HALF) / STEP))
	var z1 := int(ceil((cz + outer + HALF) / STEP))
	x0 = clampi(x0, 0, RES - 1)
	x1 = clampi(x1, 0, RES - 1)
	z0 = clampi(z0, 0, RES - 1)
	z1 = clampi(z1, 0, RES - 1)
	for iz in range(z0, z1 + 1):
		var wz := -HALF + float(iz) * STEP
		for ix in range(x0, x1 + 1):
			var wx := -HALF + float(ix) * STEP
			var d := Vector2(wx - cx, wz - cz).length()
			if d > outer:
				continue
			var t := 1.0 - smoothstep(radius, outer, d)
			t = t * t * (3.0 - 2.0 * t)
			var idx := iz * RES + ix
			heights[idx] = lerpf(heights[idx], goal, t)
	return goal


## Local height variation used to reject lumpy building lots.
func roughness(cx: float, cz: float, radius: float) -> float:
	var lo := 1e9
	var hi := -1e9
	for i in 9:
		var a := TAU * float(i) / 9.0
		var h := height_at(cx + cos(a) * radius, cz + sin(a) * radius)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	return hi - lo
