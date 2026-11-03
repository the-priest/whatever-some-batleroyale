extends RefCounted
class_name Terrain

## Deterministic island heightfield. All world queries go through this class so
## spawning, loot, AI and collision agree on where the ground is.

const SIZE := 900.0
const HALF := 450.0
const RES := 181
const STEP := SIZE / float(RES - 1)
const WATER_LEVEL := 0.9
const CHUNK_CELLS := 30
const CHUNKS := 6
const VILLAGE_RADIUS := 34.0

var heights := PackedFloat32Array()
var hills := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var ridge := FastNoiseLite.new()
var macro := FastNoiseLite.new()
var woods := FastNoiseLite.new()
var ridgelines := FastNoiseLite.new()
var peaks: Array[Vector3] = []  # x, z, amplitude
var seed_value: int = 20261101


func _init(p_seed: int = 20261101) -> void:
	seed_value = p_seed

	hills.seed = p_seed
	hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hills.frequency = 0.0031
	hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	hills.fractal_octaves = 4
	hills.fractal_gain = 0.52
	hills.fractal_lacunarity = 2.0

	detail.seed = p_seed + 91
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail.frequency = 0.0125
	detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail.fractal_octaves = 3

	ridge.seed = p_seed + 501
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.frequency = 0.0062
	ridge.fractal_octaves = 4

	macro.seed = p_seed + 7
	macro.noise_type = FastNoiseLite.TYPE_SIMPLEX
	macro.frequency = 0.0032
	macro.fractal_octaves = 3

	woods.seed = p_seed + 313
	woods.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	woods.frequency = 0.0042
	woods.fractal_octaves = 4

	ridgelines.seed = p_seed + 777
	ridgelines.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridgelines.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridgelines.frequency = 0.0045
	ridgelines.fractal_octaves = 3

	peaks = [
		Vector3(-120.0, -175.0, 30.0),
		Vector3(215.0, 195.0, 36.0),
		Vector3(-255.0, 215.0, 22.0),
		Vector3(60.0, 285.0, 18.0),
	]
	# A few more hills that move with the seed, so every island plays differently.
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed + 99
	for i in 4:
		var a := rng.randf() * TAU
		var r := rng.randf_range(60.0, 300.0)
		peaks.append(Vector3(cos(a) * r, sin(a) * r, rng.randf_range(14.0, 26.0)))
	heights.resize(RES * RES)
	_generate()


func _generate() -> void:
	for iz in RES:
		var z := -HALF + float(iz) * STEP
		for ix in RES:
			var x := -HALF + float(ix) * STEP
			var h := 11.0 + hills.get_noise_2d(x, z) * 19.0 + detail.get_noise_2d(x, z) * 4.5
			for p in peaks:
				var d := Vector2(x, z).distance_to(Vector2(p.x, p.y))
				var m := clampf(1.0 - d / 210.0, 0.0, 1.0)
				m = m * m * (3.0 - 2.0 * m)
				h += p.z * m * (0.55 + 0.45 * ridge.get_noise_2d(x, z))
			# Ridgelines: long crests to fight over and hide behind.
			var rl := ridgelines.get_noise_2d(x, z) * 0.5 + 0.5
			h += pow(clampf((rl - 0.55) / 0.45, 0.0, 1.0), 1.6) * 9.0
			# Coast falloff: land right out to the rim, sea only past it.
			# A short shelf just outside the square hides the seam.
			var r := maxf(absf(x), absf(z)) / HALF
			var edge := smoothstep(1.30, 1.02, r)
			h = lerpf(-11.0, h, edge)
			# A couple of gentle valleys for sight lines.
			h -= 3.0 * pow(clampf(1.0 - absf(hills.get_noise_2d(x + 900.0, z - 400.0)), 0.0, 1.0), 3.0)
			heights[iz * RES + ix] = h


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


func normal_at(x: float, z: float) -> Vector3:
	var e := STEP
	var hl := height_at(x - e, z)
	var hr := height_at(x + e, z)
	var hd := height_at(x, z - e)
	var hu := height_at(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


func slope_at(x: float, z: float) -> float:
	return 1.0 - normal_at(x, z).y


func is_water(x: float, z: float) -> bool:
	return height_at(x, z) < WATER_LEVEL


func flatness_ok(x: float, z: float, max_slope: float = 0.30) -> bool:
	return slope_at(x, z) < max_slope


func forest_density(x: float, z: float) -> float:
	return woods.get_noise_2d(x, z) * 0.5 + 0.5


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
