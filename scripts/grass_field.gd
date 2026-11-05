extends Node3D
class_name GrassField

## Dense meadow grass that exists only around the camera. The island is far
## too big to carpet with instances, so world-anchored 16 m chunks are built
## (one per frame) as they come into range and freed as they leave it. The
## placement in each chunk is seeded by its coordinates, so grass never
## shuffles when you walk back. Off on LOW quality.

const CHUNK := 16.0
const SPACING := 0.62

var world: WorldBuilder
var radius := 38.0
var _chunks: Dictionary = {}
var _mesh: ArrayMesh
var _mat: ShaderMaterial


func setup(p_world: WorldBuilder) -> void:
	world = p_world
	_mesh = _tuft_mesh()
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/grass.gdshader")
	_mat.set_shader_parameter("tex_grass", load("res://assets/textures/tex_grass.png"))
	# Build the lazy house lookup here, before worker threads read it.
	world.villages.house_at(Vector2.ZERO)
	set_radius(radius)


func set_radius(r: float) -> void:
	radius = r
	if _mat != null:
		_mat.set_shader_parameter("fade_end", maxf(1.0, r))
	if r <= 0.0:
		for k in _chunks:
			(_chunks[k] as Node).queue_free()
		_chunks.clear()


## Seven blades, each a bent two-segment strip with a pointed tip.
func _tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rr := RandomNumberGenerator.new()
	rr.seed = 99
	for b in 7:
		var a := TAU * float(b) / 7.0 + rr.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var root := dir * rr.randf_range(0.0, 0.12)
		var h := rr.randf_range(0.32, 0.6)
		var lean := rr.randf_range(0.08, 0.22)
		var w := rr.randf_range(0.035, 0.055)
		var p0 := root
		var p1 := root + Vector3.UP * h * 0.55 + dir * lean * 0.35
		var p2 := root + Vector3.UP * h + dir * lean
		var v := [
			[p0 - side * w, 0.0], [p0 + side * w, 0.0], [p1 + side * w * 0.7, 0.55],
			[p0 - side * w, 0.0], [p1 + side * w * 0.7, 0.55], [p1 - side * w * 0.7, 0.55],
			[p1 - side * w * 0.7, 0.55], [p1 + side * w * 0.7, 0.55], [p2, 1.0],
		]
		for e in v:
			st.set_uv(Vector2(0.5, float(e[1])))
			st.set_normal(Vector3.UP)
			st.add_vertex(e[0])
	return st.commit()


func _process(_delta: float) -> void:
	if Prof.on:
		var t0 := Time.get_ticks_usec()
		_process_body(_delta)
		Prof.add("grass", Time.get_ticks_usec() - t0)
	else:
		_process_body(_delta)


func _process_body(_delta: float) -> void:
	if world == null or radius <= 0.0:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	# Nothing to see from the plane or high up under a parachute.
	var ground: float = world.terrain.height_at(cp.x, cp.z)
	var far := cp.y - ground > radius
	var reach := radius + CHUNK * 0.75
	var c0 := Vector2i(int(floor(cp.x / CHUNK)), int(floor(cp.z / CHUNK)))
	var n := int(ceil(reach / CHUNK))
	# Ask worker threads for the nearest missing chunks; place finished ones.
	if not far:
		var want: Array = []
		for dz in range(-n, n + 1):
			for dx in range(-n, n + 1):
				var k := Vector2i(c0.x + dx, c0.y + dz)
				if _chunks.has(k) or _pending.has(k):
					continue
				var cc := Vector2((float(k.x) + 0.5) * CHUNK, (float(k.y) + 0.5) * CHUNK)
				var d := cc.distance_to(Vector2(cp.x, cp.z))
				if d < reach:
					want.append([d, k])
		want.sort_custom(func(x, y): return x[0] < y[0])
		for w in want:
			if _pending.size() >= 4:
				break
			var k: Vector2i = w[1]
			_pending[k] = WorkerThreadPool.add_task(_compute_chunk.bind(k))
	_collect_done()
	# Drop chunks well out of range.
	var drop: Array = []
	for k in _chunks:
		var kk: Vector2i = k
		var cc := Vector2((float(kk.x) + 0.5) * CHUNK, (float(kk.y) + 0.5) * CHUNK)
		if far or cc.distance_to(Vector2(cp.x, cp.z)) > reach + CHUNK * 1.5:
			drop.append(k)
	for k in drop:
		(_chunks[k] as Node).queue_free()
		_chunks.erase(k)


var _pending: Dictionary = {}
var _done: Dictionary = {}
var _mutex := Mutex.new()


func _exit_tree() -> void:
	for k in _pending:
		WorkerThreadPool.wait_for_task_completion(_pending[k])
	_pending.clear()


## Worker thread: placement for one chunk as a MultiMesh buffer (3x4
## transform + colour per instance). Only reads the terrain and the
## settlement grids, which are fixed after the island is built.
func _compute_chunk(k: Vector2i) -> void:
	var rr := RandomNumberGenerator.new()
	rr.seed = hash(k)
	var t: Terrain = world.terrain
	var buf := PackedFloat32Array()
	var steps := int(CHUNK / SPACING)
	var x0 := float(k.x) * CHUNK
	var z0 := float(k.y) * CHUNK
	var count := 0
	for iz in steps:
		for ix in steps:
			var x := x0 + (float(ix) + rr.randf()) * SPACING
			var z := z0 + (float(iz) + rr.randf()) * SPACING
			var h := t.height_at(x, z)
			if h < Terrain.WATER_LEVEL + 2.6 or t.is_water(x, z):
				continue
			# The ground shader blends sand between 6 m terrain vertices, so a
			# beach can show sand a little above the height cut-off: match it.
			var sand := _vertex_sand(t, x, z)
			if sand > 0.2 or (sand > 0.06 and rr.randf() < sand * 5.0):
				continue
			if t.slope_at(x, z) > 0.36:
				continue
			var forest := t.forest_density(x, z)
			if forest > 0.6 and rr.randf() < 0.6:
				continue
			if world._road_distance(x, z) < 0.9 or world.grass_blocked(x, z):
				continue
			var s := rr.randf_range(0.75, 1.35)
			var b := Basis(Vector3.UP, rr.randf() * TAU).scaled(Vector3(s, s * rr.randf_range(0.8, 1.35), s))
			var tint := rr.randf_range(0.88, 1.12)
			buf.append_array([b.x.x, b.y.x, b.z.x, x, b.x.y, b.y.y, b.z.y, h - 0.03, b.x.z, b.y.z, b.z.z, z,
				tint, tint * rr.randf_range(0.97, 1.05), tint * 0.95, 1.0])
			count += 1
	_mutex.lock()
	_done[k] = [count, buf]
	_mutex.unlock()


## Sand weight as the terrain mesh shows it: the per-vertex beach blend
## (see WorldBuilder._ground_weights) interpolated across the grid cell.
static func _vertex_sand(t: Terrain, x: float, z: float) -> float:
	var gx := (x + Terrain.HALF) / Terrain.STEP
	var gz := (z + Terrain.HALF) / Terrain.STEP
	var ix := floorf(gx)
	var iz := floorf(gz)
	var fx := gx - ix
	var fz := gz - iz
	var w := [0.0, 0.0, 0.0, 0.0]
	for i in 4:
		var vx := (ix + float(i % 2)) * Terrain.STEP - Terrain.HALF
		var vz := (iz + float(i >> 1)) * Terrain.STEP - Terrain.HALF
		var vh := t.height_at(vx, vz)
		var s := smoothstep(3.6, 1.2, vh)
		if Vector2(vx, vz).distance_to(Terrain.LAKE_C) < Terrain.LAKE_R + 45.0:
			s = maxf(s, smoothstep(t.lake_level + 2.4, t.lake_level + 0.6, vh))
		w[i] = s
	return lerpf(lerpf(w[0], w[1], fx), lerpf(w[2], w[3], fx), fz)


func _collect_done() -> void:
	_mutex.lock()
	var ready := _done.duplicate()
	_done.clear()
	_mutex.unlock()
	for k in ready:
		if _pending.has(k):
			WorkerThreadPool.wait_for_task_completion(_pending[k])
			_pending.erase(k)
		if radius <= 0.0 or _chunks.has(k):
			continue
		var e: Array = ready[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _mesh
		mm.instance_count = int(e[0])
		if int(e[0]) > 0:
			mm.buffer = e[1]
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_chunks[k] = mmi
