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
	var best := Vector2i(1 << 30, 0)
	var best_d := 1e9
	if not far:
		for dz in range(-n, n + 1):
			for dx in range(-n, n + 1):
				var k := Vector2i(c0.x + dx, c0.y + dz)
				if _chunks.has(k):
					continue
				var cc := Vector2((float(k.x) + 0.5) * CHUNK, (float(k.y) + 0.5) * CHUNK)
				var d := cc.distance_to(Vector2(cp.x, cp.z))
				if d < reach and d < best_d:
					best_d = d
					best = k
	if best.x != 1 << 30:
		_chunks[best] = _build_chunk(best)
		# A second one per frame when catching up (landing, driving fast).
		if not far:
			var nb := Vector2i(1 << 30, 0)
			var nd := 1e9
			for dz in range(-n, n + 1):
				for dx in range(-n, n + 1):
					var k2 := Vector2i(c0.x + dx, c0.y + dz)
					if _chunks.has(k2):
						continue
					var cc2 := Vector2((float(k2.x) + 0.5) * CHUNK, (float(k2.y) + 0.5) * CHUNK)
					var d2 := cc2.distance_to(Vector2(cp.x, cp.z))
					if d2 < reach and d2 < nd:
						nd = d2
						nb = k2
			if nb.x != 1 << 30:
				_chunks[nb] = _build_chunk(nb)
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


func _build_chunk(k: Vector2i) -> Node3D:
	var rr := RandomNumberGenerator.new()
	rr.seed = hash(k)
	var t: Terrain = world.terrain
	var xs: Array[Transform3D] = []
	var cols: Array[Color] = []
	var steps := int(CHUNK / SPACING)
	var x0 := float(k.x) * CHUNK
	var z0 := float(k.y) * CHUNK
	for iz in steps:
		for ix in steps:
			var x := x0 + (float(ix) + rr.randf()) * SPACING
			var z := z0 + (float(iz) + rr.randf()) * SPACING
			var h := t.height_at(x, z)
			if h < Terrain.WATER_LEVEL + 2.6 or t.is_water(x, z):
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
			xs.append(Transform3D(b, Vector3(x, h - 0.03, z)))
			var tint := rr.randf_range(0.88, 1.12)
			cols.append(Color(tint, tint * rr.randf_range(0.97, 1.05), tint * 0.95))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _mesh
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi
