extends Node3D
class_name WorldBuilder

## Builds the whole island: sky + lighting, chunked terrain with collision, sea,
## instanced forest and ground cover, modular villages, distant islands, clouds.

const TREE_TILE := 150.0
const CHUNK_SIZE := 50.0
## Godot measures visibility range to the centre of a MultiMesh's bounds, so a
## tile's range must cover its own half-diagonal or it pops out in big squares.
const TREE_HALF_DIAG := TREE_TILE * 0.7072
const GROUND_HALF_DIAG := CHUNK_SIZE * 0.7072

var terrain: Terrain
var villages: Villages
var loot_points: Array[Dictionary] = []
var spawn_points: Array[Vector3] = []
var minimap_texture: ImageTexture
var rng := RandomNumberGenerator.new()

var _nature_cache: Dictionary = {}
var _terrain_material: ShaderMaterial
var _mat_water: ShaderMaterial
var road_image: Image
## Spatial index for "is this near a settlement / road" checks during scatter.
const GRID := 50.0
var _pad_grid: Dictionary = {}
var _road_grid: Dictionary = {}
var _chunk_pads: Array = []

var falls_sound_pos := Vector3.ZERO
## Parking spots for jeeps: [Vector3 position, float yaw].
var vehicle_spawns: Array = []

var sun: DirectionalLight3D
var fill_light: DirectionalLight3D
var environment: Environment
var world_env: WorldEnvironment
var sky_material: ProceduralSkyMaterial
var weather := "clear"

var stats := {
	"trees": 0, "ground": 0, "rocks": 0, "houses": 0, "loot": 0, "colliders": 0,
	"build_ms": 0,
}


func build(p_seed: int) -> void:
	var started := Time.get_ticks_msec()
	rng.seed = p_seed
	terrain = Terrain.new(p_seed)
	print("[world] terrain generated in %d ms" % (Time.get_ticks_msec() - started))

	var marks: Array = []
	var tick := func(label: String) -> void:
		marks.append("%s %d" % [label, Time.get_ticks_msec() - started])
	_build_lighting()
	villages = Villages.new()
	villages.name = "Villages"
	add_child(villages)
	villages.build(terrain, p_seed)
	loot_points.append_array(villages.loot_points)
	stats.houses = villages._stat.houses
	tick.call("villages")
	_build_grids()
	_build_terrain()
	tick.call("terrain")
	_build_water()
	_build_inland_water()
	_scatter_trees()
	tick.call("trees")
	_scatter_ground_cover()
	tick.call("cover")
	_fill_gaps()
	tick.call("gaps")
	_scatter_rocks()
	tick.call("rocks")
	_build_wild_loot()
	_build_spawn_points()
	_build_vehicle_spawns()
	_build_distant_islands()
	_build_clouds()
	_build_minimap()
	_build_water_audio()
	tick.call("minimap")
	print("[world] timing: ", ", ".join(marks))
	stats.loot = loot_points.size()
	stats.build_ms = Time.get_ticks_msec() - started
	print("[world] built in %d ms — %s" % [stats.build_ms, str(stats)])


# ---------------------------------------------------------------- environment

func _build_lighting() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-46.0, -34.0, 0.0)
	sun.light_color = Color(1.0, 0.955, 0.87)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 130.0
	sun.directional_shadow_split_1 = 0.10
	sun.directional_shadow_split_2 = 0.22
	sun.directional_shadow_split_3 = 0.48
	sun.shadow_bias = 0.02
	sun.shadow_normal_bias = 0.9
	sun.directional_shadow_fade_start = 0.85
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.rotation_degrees = Vector3(-24.0, 146.0, 0.0)
	fill.light_color = Color(0.62, 0.76, 0.98)
	fill.light_energy = 0.32
	fill.shadow_enabled = false
	add_child(fill)
	fill_light = fill

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.16, 0.34, 0.66)
	sky_mat.sky_horizon_color = Color(0.62, 0.76, 0.90)
	sky_mat.sky_curve = 0.13
	sky_mat.sky_energy_multiplier = 1.05
	# Below the horizon is open sea, so the sky's "ground" matches the water.
	sky_mat.ground_bottom_color = Color(0.36, 0.52, 0.64)
	sky_mat.ground_horizon_color = Color(0.60, 0.73, 0.87)
	sky_mat.ground_curve = 0.08
	sky_mat.sun_angle_max = 22.0
	sky_mat.sun_curve = 0.12
	sky.sky_material = sky_mat
	sky_material = sky_mat
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.62
	env.ambient_light_sky_contribution = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0

	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.74, 0.88)
	env.fog_light_energy = 0.95
	env.fog_density = 0.00032
	env.fog_sky_affect = 0.15
	env.fog_aerial_perspective = 0.3

	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12

	# Soft bloom: muzzle flashes, tracers and the sun on water get a halo.
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 0.9
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	we.environment = env
	add_child(we)
	environment = env
	world_env = we


# ------------------------------------------------------------------- terrain

func _build_terrain() -> void:
	_terrain_material = ShaderMaterial.new()
	_terrain_material.shader = load("res://shaders/terrain.gdshader")
	_terrain_material.set_shader_parameter("tex_grass", load("res://assets/textures/tex_grass.png"))
	_terrain_material.set_shader_parameter("tex_dirt", load("res://assets/textures/tex_dirt.png"))
	_terrain_material.set_shader_parameter("tex_sand", load("res://assets/textures/tex_sand.png"))
	_terrain_material.set_shader_parameter("tex_rock", load("res://assets/textures/tex_rock.png"))
	_terrain_material.set_shader_parameter("tex_macro", load("res://assets/textures/tex_macro.png"))
	_terrain_material.set_shader_parameter("road_mask", _build_road_mask())
	_terrain_material.set_shader_parameter("map_half", Terrain.HALF)

	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	var main := Node3D.new()
	main.name = "TerrainChunks"
	add_child(main)

	for cz in Terrain.CHUNKS:
		for cx in Terrain.CHUNKS:
			var mesh := _chunk_mesh(cx, cz)
			if mesh == null:
				continue
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [cx, cz]
			mi.mesh = mesh
			mi.material_override = _terrain_material
			# The ground is lit by its own normals; letting a 900 m surface feed
			# the shadow map only ever produced acne bands that read as holes in
			# the floor. Objects still cast onto the terrain.
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.extra_cull_margin = 3.0
			main.add_child(mi)

	# One heightfield for the whole island: far cheaper than triangle meshes
	# for walking bodies and bullet rays, and built from the same samples as
	# the render mesh.
	var hm := HeightMapShape3D.new()
	hm.map_width = Terrain.RES
	hm.map_depth = Terrain.RES
	hm.map_data = terrain.heights
	var shape := CollisionShape3D.new()
	shape.shape = hm
	shape.scale = Vector3(Terrain.STEP, 1.0, Terrain.STEP)
	body.add_child(shape)
	stats.colliders += 1


func _chunk_mesh(cx: int, cz: int) -> ArrayMesh:
	var cells := Terrain.CHUNK_CELLS
	var origin_x := -Terrain.HALF + float(cx * cells) * Terrain.STEP
	var origin_z := -Terrain.HALF + float(cz * cells) * Terrain.STEP
	var verts: Array[Vector3] = []
	var normals: Array[Vector3] = []
	var colors: Array[Color] = []
	var canopy: Array[float] = []
	# Only the settlements that can touch this chunk tint its ground.
	_chunk_pads.clear()
	var span := float(cells) * Terrain.STEP
	var cc := Vector2(origin_x + span * 0.5, origin_z + span * 0.5)
	for v in villages.village_pads:
		if (v.center as Vector2).distance_to(cc) < span * 0.75 + float(v.radius) + 4.0:
			_chunk_pads.append(v)
	for iz in cells + 1:
		for ix in cells + 1:
			var x := origin_x + float(ix) * Terrain.STEP
			var z := origin_z + float(iz) * Terrain.STEP
			var h := terrain.height_at(x, z)
			var n := terrain.normal_at(x, z)
			verts.append(Vector3(x, h, z))
			normals.append(n)
			colors.append(_ground_weights(x, z, h, n))
			var cw := 0.0
			if h > Terrain.WATER_LEVEL + 1.2 and 1.0 - n.y < 0.5:
				cw = smoothstep(0.36, 0.72, terrain.forest_density(x, z))
			canopy.append(cw)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var row := cells + 1
	for iz in cells:
		for ix in cells:
			var i00 := iz * row + ix
			var i10 := i00 + 1
			var i01 := i00 + row
			var i11 := i01 + 1
			_add_tri(st, verts, normals, colors, canopy, [i00, i10, i01])
			_add_tri(st, verts, normals, colors, canopy, [i10, i11, i01])
	st.index()
	return st.commit()


func _add_tri(st: SurfaceTool, verts: Array[Vector3], normals: Array[Vector3], colors: Array[Color], canopy: Array[float], idx: Array) -> void:
	for i in idx:
		st.set_color(colors[i])
		st.set_normal(normals[i])
		st.set_uv(Vector2(verts[i].x, verts[i].z) * 0.02)
		st.set_uv2(Vector2(canopy[i], 0.0))
		st.add_vertex(verts[i])


func _ground_weights(x: float, z: float, h: float, n: Vector3) -> Color:
	var slope := 1.0 - n.y
	var sand := smoothstep(3.6, 1.2, h)
	# Pebble shore round the plateau lake.
	if Vector2(x, z).distance_to(Terrain.LAKE_C) < Terrain.LAKE_R + 45.0:
		sand = maxf(sand, smoothstep(terrain.lake_level + 2.4, terrain.lake_level + 0.6, h))
	var rock := smoothstep(0.30, 0.52, slope) * 0.9
	var macro := terrain.macro.get_noise_2d(x, z) * 0.5 + 0.5
	var dirt := 0.0
	# Village pads: keep the worn-earth ring but let it fade out instead of
	# ending in a hard 0.8 disc. Widened 30 -> 34 so the edge is softer.
	for v in _chunk_pads:
		var c: Vector2 = v.center
		var d := Vector2(x, z).distance_to(c)
		var vr: float = v.radius
		dirt = maxf(dirt, smoothstep(vr + 3.0, vr * 0.5, d) * (0.45 if v.type == "town" else 0.62))
	# Worn earth belongs under the canopy, not in free-floating blobs. The old
	# smoothstep(0.62, 0.86) term only fired in the top quarter of the woods
	# noise band, which produced discrete 30-80 m dirt discs with no cover on
	# them -- the bald patches. Gate it on actual forest density and keep the
	# value low so it tints the ground instead of replacing it.
	var woods := smoothstep(0.30, 0.75, terrain.forest_density(x, z))
	dirt += woods * smoothstep(0.35, 0.85, terrain.woods.get_noise_2d(x * 1.7, z * 1.7) * 0.5 + 0.5) * 0.10
	dirt *= 0.70 + macro * 0.30
	rock = clampf(rock, 0.0, 1.0)
	sand = clampf(sand, 0.0, 1.0)
	dirt = clampf(dirt, 0.0, 0.75)

	var grass := clampf(1.0 - sand - rock - dirt, 0.0, 1.0)
	var total := grass + sand + rock + dirt
	if total <= 0.001:
		grass = 1.0
		total = 1.0
	return Color(grass / total, sand / total, rock / total, dirt / total)


const ROAD_RES := 2048


## Crisp dirt roads: segments rasterised into a mask the terrain shader blends.
func _build_road_mask() -> ImageTexture:
	var img := Image.create(ROAD_RES, ROAD_RES, false, Image.FORMAT_L8)
	var k := float(ROAD_RES) / Terrain.SIZE
	for r in villages.roads:
		if r.get("bridge", false):
			continue
		var a: Vector2 = r.a
		var b: Vector2 = r.b
		var w: float = r.w
		var lo := (Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * (w + 2.0) + Vector2.ONE * Terrain.HALF) * k
		var hi := (Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * (w + 2.0) + Vector2.ONE * Terrain.HALF) * k
		var ab := b - a
		var len2 := maxf(0.001, ab.length_squared())
		for py in range(maxi(0, int(lo.y)), mini(ROAD_RES, int(hi.y) + 1)):
			for px in range(maxi(0, int(lo.x)), mini(ROAD_RES, int(hi.x) + 1)):
				var p := Vector2(px + 0.5, py + 0.5) / k - Vector2.ONE * Terrain.HALF
				var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
				var d := p.distance_to(a + ab * t)
				# Wheel ruts: two darker lines either side of the centre.
				var v := smoothstep(w, w * 0.55, d)
				if v <= 0.0:
					continue
				var cur := img.get_pixel(px, py).r
				img.set_pixel(px, py, Color(maxf(cur, v), 0, 0))
	road_image = img
	return ImageTexture.create_from_image(img)


func road_at(x: float, z: float) -> float:
	if road_image == null:
		return 0.0
	var px := clampi(int((x + Terrain.HALF) / Terrain.SIZE * ROAD_RES), 0, ROAD_RES - 1)
	var py := clampi(int((z + Terrain.HALF) / Terrain.SIZE * ROAD_RES), 0, ROAD_RES - 1)
	return road_image.get_pixel(px, py).r


func _build_water() -> void:
	_mat_water = ShaderMaterial.new()
	_mat_water.shader = load("res://shaders/water.gdshader")
	for i in 2:
		var nt := NoiseTexture2D.new()
		nt.width = 512
		nt.height = 512
		nt.seamless = true
		nt.as_normal_map = true
		nt.bump_strength = 6.0 if i == 0 else 3.0
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.frequency = 0.012 if i == 0 else 0.03
		fn.fractal_octaves = 3
		fn.seed = 11 + i
		nt.noise = fn
		_mat_water.set_shader_parameter("normal_a" if i == 0 else "normal_b", nt)
	var plane := PlaneMesh.new()
	plane.size = Vector2(24000.0, 24000.0)
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	var mi := MeshInstance3D.new()
	mi.name = "Sea"
	mi.mesh = plane
	mi.material_override = _mat_water
	mi.position.y = Terrain.WATER_LEVEL
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Plateau lake, its outlet, the waterfall and the plunge pool's foam, mist
## and roar.
func _build_inland_water() -> void:
	var lake := SurfaceTool.new()
	lake.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lc := Terrain.LAKE_C
	var lr := Terrain.LAKE_R + 22.0
	var y := terrain.lake_level
	var segs := 48
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		lake.set_normal(Vector3.UP)
		lake.add_vertex(Vector3(lc.x, y, lc.y))
		lake.add_vertex(Vector3(lc.x + cos(a1) * lr, y, lc.y + sin(a1) * lr))
		lake.add_vertex(Vector3(lc.x + cos(a0) * lr, y, lc.y + sin(a0) * lr))
	# Outlet channel to the lip.
	var ca := terrain.channel_a
	var cb := terrain.channel_b
	var side := (cb - ca).normalized().orthogonal() * 8.0
	var q := [ca - side, ca + side, cb + side, cb - side]
	for idx in [[0, 2, 1], [0, 3, 2]]:
		for j in idx:
			var v: Vector2 = q[j]
			lake.set_normal(Vector3.UP)
			lake.add_vertex(Vector3(v.x, y, v.y))
	var lmi := MeshInstance3D.new()
	lmi.name = "Lake"
	lmi.mesh = lake.commit()
	lmi.material_override = _mat_water
	lmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lmi)

	# Streak texture shared by the falls and the foam.
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_CELLULAR
	fn.frequency = 0.035
	fn.fractal_type = FastNoiseLite.FRACTAL_FBM
	fn.fractal_octaves = 3
	fn.seed = 404
	nt.noise = fn

	# The fall: free-falling where the cliff drops away faster than the water,
	# clinging to the rock where it does not.
	var dir := terrain.falls_dir
	var lip := Vector2(terrain.falls_top.x, terrain.falls_top.z)
	var top := terrain.falls_top.y + 0.15
	var perp := dir.orthogonal()
	var pts: Array[Vector3] = []
	var s := -3.0
	while s < 90.0:
		var p := lip + dir * s
		var ground := terrain.height_at(p.x, p.y)
		var free := top - 0.24 * maxf(0.0, s) * maxf(0.0, s)
		var yy := maxf(free, ground + 0.7) if s > 0.0 else top
		pts.append(Vector3(p.x, yy, p.y))
		if yy <= Terrain.WATER_LEVEL + 0.3:
			break
		s += 0.75 if free > ground else 1.5
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/waterfall.gdshader")
	mat.set_shader_parameter("streaks", nt)
	for layer in 2:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var acc := 0.0
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		var prev_v := 0.0
		for i in pts.size():
			var p: Vector3 = pts[i]
			if i > 0:
				acc += p.distance_to(pts[i - 1])
			var f := float(i) / float(maxi(1, pts.size() - 1))
			var hw := lerpf(5.0, 8.5, f) * (1.0 if layer == 0 else 1.25)
			var off := Vector3(dir.x, 0.0, dir.y) * (0.0 if layer == 0 else 0.5)
			var l := p - Vector3(perp.x, 0, perp.y) * hw + off
			var r := p + Vector3(perp.x, 0, perp.y) * hw + off
			var v := acc / 6.0
			if i > 0:
				var n := (Vector3(dir.x, 0.0, dir.y) * -1.0).normalized()
				for tri in [[prev_l, prev_v, 0.0], [r, v, 1.0], [prev_r, prev_v, 1.0], [prev_l, prev_v, 0.0], [l, v, 0.0], [r, v, 1.0]]:
					st.set_normal(n)
					st.set_uv(Vector2(float(tri[2]), float(tri[1])))
					st.add_vertex(tri[0])
			prev_l = l
			prev_r = r
			prev_v = v
		var mi := MeshInstance3D.new()
		mi.name = "Waterfall_%d" % layer
		mi.mesh = st.commit()
		var m: ShaderMaterial = mat if layer == 0 else (mat.duplicate() as ShaderMaterial)
		if layer == 1:
			m.set_shader_parameter("opacity", 0.45)
			m.set_shader_parameter("foam_bias", 0.35)
			m.set_shader_parameter("speed", 1.1)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

	# Plunge pool foam and mist.
	var bottom: Vector3 = pts[pts.size() - 1]
	var foam := MeshInstance3D.new()
	var fp := PlaneMesh.new()
	fp.size = Vector2(34, 34)
	foam.mesh = fp
	var fm := ShaderMaterial.new()
	fm.shader = load("res://shaders/foam.gdshader")
	fm.set_shader_parameter("streaks", nt)
	foam.material_override = fm
	foam.position = Vector3(bottom.x, Terrain.WATER_LEVEL + 0.06, bottom.z)
	foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(foam)
	var mist := CPUParticles3D.new()
	mist.name = "FallsMist"
	mist.amount = 36
	mist.lifetime = 4.0
	mist.preprocess = 4.0
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	mist.emission_sphere_radius = 7.0
	mist.direction = Vector3(dir.x, 1.0, dir.y)
	mist.spread = 40.0
	mist.initial_velocity_min = 1.5
	mist.initial_velocity_max = 4.0
	mist.gravity = Vector3(0, 0.25, 0)
	mist.scale_amount_min = 5.0
	mist.scale_amount_max = 11.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(1.0, 1.0))
	mist.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.0))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	grad.add_point(0.25, Color(1, 1, 1, 0.32))
	mist.color_ramp = grad
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE
	var pm := StandardMaterial3D.new()
	pm.albedo_texture = _cloud_texture()
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.vertex_color_use_as_albedo = true
	qm.material = pm
	mist.mesh = qm
	mist.position = bottom + Vector3(0, 2.0, 0)
	mist.visibility_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 60, 80))
	add_child(mist)
	falls_sound_pos = bottom + Vector3(0, 6.0, 0)


## Time of day and weather for a match. Every preset keeps the island
## readable; they change mood, shadow length and how far you can see.
const WEATHERS := ["clear", "golden", "misty", "overcast"]


func set_weather(kind: String) -> void:
	weather = kind
	if sun == null or environment == null or sky_material == null:
		return
	var env := environment
	var sm := sky_material
	# [sun pitch, sun yaw, sun colour, sun energy, sky top, sky horizon,
	#  ground horizon, ground bottom, fog colour, fog density, ambient, exposure]
	var presets := {
		"clear": [-46.0, -34.0, Color(1.0, 0.955, 0.87), 1.35, Color(0.26, 0.44, 0.72), Color(0.66, 0.79, 0.91),
			Color(0.60, 0.73, 0.87), Color(0.36, 0.52, 0.64), Color(0.62, 0.74, 0.88), 0.00032, 0.62, 1.05],
		"golden": [-17.0, -62.0, Color(1.0, 0.76, 0.52), 1.45, Color(0.22, 0.32, 0.58), Color(0.98, 0.72, 0.52),
			Color(0.86, 0.66, 0.54), Color(0.32, 0.36, 0.44), Color(0.94, 0.72, 0.56), 0.00042, 0.68, 1.1],
		"misty": [-28.0, 20.0, Color(0.96, 0.95, 0.9), 0.95, Color(0.42, 0.52, 0.62), Color(0.78, 0.82, 0.85),
			Color(0.76, 0.8, 0.83), Color(0.5, 0.56, 0.6), Color(0.78, 0.82, 0.86), 0.0016, 0.72, 1.1],
		"overcast": [-58.0, -10.0, Color(0.86, 0.88, 0.92), 0.7, Color(0.4, 0.45, 0.52), Color(0.66, 0.7, 0.75),
			Color(0.62, 0.66, 0.7), Color(0.4, 0.45, 0.5), Color(0.64, 0.68, 0.73), 0.0007, 0.85, 1.15],
	}
	var p: Array = presets.get(kind, presets["clear"])
	sun.rotation_degrees = Vector3(float(p[0]), float(p[1]), 0.0)
	sun.light_color = p[2]
	sun.light_energy = float(p[3])
	sm.sky_top_color = p[4]
	sm.sky_horizon_color = p[5]
	sm.ground_horizon_color = p[6]
	sm.ground_bottom_color = p[7]
	env.fog_light_color = p[8]
	env.fog_density = float(p[9])
	env.volumetric_fog_albedo = (p[8] as Color).lightened(0.25)
	env.ambient_light_energy = float(p[10])
	env.tonemap_exposure = float(p[11])


## The falls roar from far off; the river babbles along its banks.
func _build_water_audio() -> void:
	var falls := _loop_stream("waterfall_loop")
	if falls != null:
		var p := AudioStreamPlayer3D.new()
		p.name = "FallsAudio"
		p.stream = falls
		p.unit_size = 38.0
		p.max_distance = 420.0
		p.volume_db = 2.0
		p.position = falls_sound_pos
		p.autoplay = true
		add_child(p)
	var river := _loop_stream("river_loop")
	if river == null:
		return
	var s := 80.0
	while s < terrain.river_len - 60.0:
		var c := terrain._river_point(s)
		if terrain.height_at(c.x, c.y) < Terrain.WATER_LEVEL:
			var p := AudioStreamPlayer3D.new()
			p.stream = river
			p.unit_size = 9.0
			p.max_distance = 110.0
			p.volume_db = -6.0
			p.position = Vector3(c.x, Terrain.WATER_LEVEL + 1.0, c.y)
			p.autoplay = true
			add_child(p)
		s += 140.0


func _loop_stream(name: String) -> AudioStream:
	var path := "res://assets/audio/gen/%s.wav" % name
	if not ResourceLoader.exists(path):
		return null
	var st: AudioStream = load(path)
	if st is AudioStreamWAV:
		var w := st as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	return st


# ------------------------------------------------------------------- scatter

func _nature_mesh(name: String) -> Dictionary:
	if _nature_cache.has(name):
		return _nature_cache[name]
	var path := "res://assets/nature/%s.gltf" % name
	if not ResourceLoader.exists(path):
		_nature_cache[name] = {}
		return {}
	var packed: PackedScene = load(path)
	var inst := packed.instantiate()
	var mi: MeshInstance3D = _find_mesh(inst)
	if mi == null:
		inst.free()
		_nature_cache[name] = {}
		return {}
	var mesh: Mesh = mi.mesh
	var aabb: AABB = mi.transform * mesh.get_aabb()
	var albedo: Texture2D = null
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s)
		if mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture != null:
			if albedo == null:
				albedo = (mat as StandardMaterial3D).albedo_texture
	inst.free()
	var data := {"mesh": mesh, "aabb": aabb, "albedo": albedo}
	_nature_cache[name] = data
	return data


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for c in node.get_children():
		var found := _find_mesh(c)
		if found != null:
			return found
	return null


func _scatter_trees() -> void:
	var species := [
		{"name": "CommonTree_3", "w": 0.26, "scale": Vector2(0.85, 1.35)},
		{"name": "CommonTree_4", "w": 0.24, "scale": Vector2(0.85, 1.30)},
		{"name": "CommonTree_5", "w": 0.18, "scale": Vector2(0.80, 1.20)},
		{"name": "Pine_4", "w": 0.18, "scale": Vector2(0.80, 1.25)},
		{"name": "Pine_5", "w": 0.10, "scale": Vector2(0.80, 1.20)},
		{"name": "DeadTree_5", "w": 0.02, "scale": Vector2(0.42, 0.62)},
	]
	var picks: Dictionary = {}
	for s in species:
		picks[s.name] = {"mesh": _nature_mesh(s.name), "list": [], "scale": s.scale, "w": s.w}

	var placements: Array[Dictionary] = []
	var grid: Dictionary = {}
	var attempts := 210000
	for i in attempts:
		var x := rng.randf_range(-Terrain.HALF + 12.0, Terrain.HALF - 12.0)
		var z := rng.randf_range(-Terrain.HALF + 12.0, Terrain.HALF - 12.0)
		var h := terrain.height_at(x, z)
		if h < Terrain.WATER_LEVEL + 1.2:
			continue
		if terrain.slope_at(x, z) > 0.52:
			continue
		if _near_village(x, z, 38.0) or _road_distance(x, z) < 3.0:
			continue
		var forest := terrain.forest_density(x, z)
		# Real woods where the forest map is high, open meadows elsewhere.
		var chance := smoothstep(0.40, 0.70, forest) * 0.95 + 0.025
		chance = clampf(chance, 0.0, 0.92)
		if rng.randf() > chance:
			continue
		var spacing := 4.4 if forest > 0.62 else 6.5
		var cell := "%d_%d_%d" % [int(x / spacing), int(z / spacing), int(spacing)]
		if grid.has(cell):
			continue
		grid[cell] = true
		var r := rng.randf()
		var chosen: String = "CommonTree_3"
		var acc := 0.0
		for s in species:
			acc += float(s.w)
			if r <= acc:
				chosen = s.name
				break
		placements.append({"name": chosen, "pos": Vector3(x, h - 0.15, z), "rot": rng.randf_range(0.0, TAU),
			"scale": rng.randf_range(picks[chosen].scale.x, picks[chosen].scale.y)})

	# Batch into 300 m tiles per species so frustum culling can do its job.
	for p in placements:
		var tile_x := int(floor((p.pos.x + Terrain.HALF) / TREE_TILE))
		var tile_z := int(floor((p.pos.z + Terrain.HALF) / TREE_TILE))
		p["tile"] = "%d_%d" % [tile_x, tile_z]

	# group keyed by species+tile
	var groups: Dictionary = {}
	for p in placements:
		var key := "%s|%s" % [p.name, p.tile]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(p)

	var trunk_body := StaticBody3D.new()
	trunk_body.name = "TreeCollision"
	trunk_body.collision_layer = 1
	trunk_body.collision_mask = 0

	for key in groups:
		var parts: PackedStringArray = key.split("|")
		var data: Dictionary = picks[parts[0]].mesh
		if data.is_empty():
			continue
		var list: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = data.mesh
		mm.instance_count = list.size()
		for i in list.size():
			var it: Dictionary = list[i]
			var b := Basis(Vector3.UP, it.rot).scaled(Vector3.ONE * it.scale)
			mm.set_instance_transform(i, Transform3D(b, it.pos))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "T_" + key
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mmi.visibility_range_end = 650.0 + TREE_HALF_DIAG
		add_child(mmi)
		stats.trees += list.size()

		# Trunks collide only where gameplay actually happens.
		for it in list:
			var sc: float = it.scale
			var shape := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = maxf(0.22, 0.30 * sc)
			cyl.height = 4.4 * sc
			shape.shape = cyl
			shape.position = it.pos + Vector3(0, 2.2 * sc, 0)
			trunk_body.add_child(shape)
			stats.colliders += 1
	# Into the tree only once every shape is attached: adding shapes to a live
	# body rebuilds its compound shape each time.
	add_child(trunk_body)


func _scatter_ground_cover() -> void:
	var kinds := [
		{"name": "Grass_Common_Short", "w": 0.44, "view": 55.0, "scale": Vector2(0.75, 1.45), "wind": 0.16},
		{"name": "Grass_Common_Tall", "w": 0.20, "view": 60.0, "scale": Vector2(0.75, 1.25), "wind": 0.18},
		{"name": "Fern_1", "w": 0.11, "view": 75.0, "scale": Vector2(0.34, 0.55), "wind": 0.09},
		{"name": "Bush_Common", "w": 0.17, "view": 160.0, "scale": Vector2(0.6, 1.15), "wind": 0.06},
		{"name": "Bush_Common_Flowers", "w": 0.05, "view": 140.0, "scale": Vector2(0.55, 0.90), "wind": 0.06},
		{"name": "Flower_4_Group", "w": 0.06, "view": 90.0, "scale": Vector2(0.55, 0.85), "wind": 0.10},
	]
	var buckets: Dictionary = {}
	for k in kinds:
		buckets[k.name] = []

	for i in 60000:
		var x := rng.randf_range(-Terrain.HALF + 8.0, Terrain.HALF - 8.0)
		var z := rng.randf_range(-Terrain.HALF + 8.0, Terrain.HALF - 8.0)
		var h := terrain.height_at(x, z)
		if h < Terrain.WATER_LEVEL + 0.6:
			continue
		if terrain.slope_at(x, z) > 0.5:
			continue
		if _near_village(x, z, 14.0) or _road_distance(x, z) < 1.0:
			continue
		var forest := terrain.forest_density(x, z)
		var r := rng.randf()
		var acc := 0.0
		var chosen := ""
		for k in kinds:
			acc += float(k.w)
			if r <= acc:
				chosen = k.name
				break
		if chosen == "":
			continue
		# Flowers are happiest in the open; the forest floor is ferns and bush.
		if chosen == "Flower_4_Group" and forest > 0.6:
			continue
		if forest > 0.62 and rng.randf() < 0.55:
			chosen = "Fern_1" if rng.randf() < 0.6 else "Bush_Common"
		var cf: Dictionary = {}
		for k in kinds:
			if k.name == chosen:
				cf = k
				break
		var srange: Vector2 = cf.scale
		buckets[chosen].append({
			"pos": Vector3(x, h - 0.02, z), "rot": rng.randf_range(0.0, TAU),
			"scale": rng.randf_range(srange.x, srange.y),
		})

	for k in kinds:
		var list: Array = buckets[k.name]
		if list.is_empty():
			continue
		var data := _nature_mesh(k.name)
		if data.is_empty():
			continue

		# Wind material built from the kit's own albedo so colours stay authored.
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/foliage.gdshader")
		if data.albedo != null:
			mat.set_shader_parameter("albedo_tex", data.albedo)
		else:
			mat.set_shader_parameter("albedo_tex", load("res://assets/textures/tex_grass.png"))
		mat.set_shader_parameter("wind_strength", k.wind)
		mat.set_shader_parameter("sway_height", 1.4)
		mat.set_shader_parameter("alpha_cut", 0.32)

		# 150 m tiles keep draw calls frustum-culled.
		var tiles: Dictionary = {}
		for it in list:
			var tx := int(floor((it.pos.x + Terrain.HALF) / CHUNK_SIZE))
			var tz := int(floor((it.pos.z + Terrain.HALF) / CHUNK_SIZE))
			var key := "%d_%d" % [tx, tz]
			if not tiles.has(key):
				tiles[key] = []
			tiles[key].append(it)
		for key in tiles:
			var arr: Array = tiles[key]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = data.mesh
			mm.instance_count = arr.size()
			for i in arr.size():
				var it: Dictionary = arr[i]
				mm.set_instance_transform(i, Transform3D(
					Basis(Vector3.UP, it.rot).scaled(Vector3.ONE * it.scale), it.pos))
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "G_%s_%s" % [k.name, key]
			mmi.multimesh = mm
			mmi.material_override = mat
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = float(k.view) + GROUND_HALF_DIAG
			add_child(mmi)
			stats.ground += arr.size()


func _scatter_rocks() -> void:
	var kinds := ["Rock_Medium_1", "Rock_Medium_2", "Pebble_Round_1"]
	var groups: Dictionary = {}
	for k in kinds:
		groups[k] = []
	for i in 7000:
		var x := rng.randf_range(-Terrain.HALF + 8.0, Terrain.HALF - 8.0)
		var z := rng.randf_range(-Terrain.HALF + 8.0, Terrain.HALF - 8.0)
		var h := terrain.height_at(x, z)
		if h < Terrain.WATER_LEVEL + 0.4:
			continue
		var slope := terrain.slope_at(x, z)
		if slope < 0.12 and rng.randf() > 0.22:
			continue
		if _near_village(x, z, 10.0):
			continue
		var k: String = kinds[0]
		if slope > 0.4:
			k = kinds[1] if rng.randf() < 0.7 else kinds[0]
		elif rng.randf() < 0.55:
			k = kinds[2]
		var base := 0.75 if k == "Rock_Medium_1" else (0.6 if k == "Rock_Medium_2" else 0.55)
		groups[k].append({
			"pos": Vector3(x, h - 0.05, z), "rot": rng.randf_range(0.0, TAU),
			"scale": rng.randf_range(base * 0.65, base * 1.5),
		})
	# Boulders: big enough to hide behind, scattered through the open fields
	# where cover is otherwise scarce.
	for i in 5000:
		if groups["Rock_Medium_1"].size() + groups["Rock_Medium_2"].size() > 2400:
			break
		var x := rng.randf_range(-Terrain.HALF + 20.0, Terrain.HALF - 20.0)
		var z := rng.randf_range(-Terrain.HALF + 20.0, Terrain.HALF - 20.0)
		var h := terrain.height_at(x, z)
		if h < Terrain.WATER_LEVEL + 1.0 or terrain.slope_at(x, z) > 0.35:
			continue
		if terrain.forest_density(x, z) > 0.55 or rng.randf() > 0.35:
			continue
		if _near_village(x, z, 16.0):
			continue
		# Boulders come in small clusters.
		var n := rng.randi_range(1, 3)
		for j in n:
			var ox := x + rng.randf_range(-3.5, 3.5) * float(j)
			var oz := z + rng.randf_range(-3.5, 3.5) * float(j)
			var kk: String = kinds[0] if rng.randf() < 0.5 else kinds[1]
			groups[kk].append({
				"pos": Vector3(ox, terrain.height_at(ox, oz) - 0.25, oz), "rot": rng.randf_range(0.0, TAU),
				"scale": rng.randf_range(1.6, 3.0),
			})

	for k in kinds:
		var list: Array = groups[k]
		if list.is_empty():
			continue
		var data := _nature_mesh(k)
		if data.is_empty():
			continue
		var tiles: Dictionary = {}
		for it in list:
			var key := "%d_%d" % [int(floor((it.pos.x + Terrain.HALF) / TREE_TILE)), int(floor((it.pos.z + Terrain.HALF) / TREE_TILE))]
			if not tiles.has(key):
				tiles[key] = []
			tiles[key].append(it)
		for key in tiles:
			var arr: Array = tiles[key]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = data.mesh
			mm.instance_count = arr.size()
			for i in arr.size():
				var it: Dictionary = arr[i]
				mm.set_instance_transform(i, Transform3D(
					Basis(Vector3.UP, it.rot).scaled(Vector3.ONE * it.scale), it.pos))
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "R_%s_%s" % [k, key]
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mmi.visibility_range_end = (120.0 if k == "Pebble_Round_1" else 420.0) + TREE_HALF_DIAG
			add_child(mmi)
		stats.rocks += list.size()
		# Rocks stop bullets and bodies. Pebbles do not.
		if k == "Pebble_Round_1":
			continue
		var body := StaticBody3D.new()
		body.name = "RockCollision_" + k
		body.collision_layer = 1
		body.collision_mask = 0
		var aabb: AABB = data.aabb
		for it in list:
			var sc: float = it.scale
			if sc < 0.6:
				continue
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = aabb.size * sc * Vector3(0.82, 0.92, 0.82)
			cs.shape = box
			var b := Basis(Vector3.UP, it.rot)
			cs.transform = Transform3D(b, Vector3(it.pos) + b * (aabb.get_center() * sc))
			body.add_child(cs)
			stats.colliders += 1
		add_child(body)


func _build_wild_loot() -> void:
	# Weapons out in the open so a bad drop still has a chance.
	var lrng := RandomNumberGenerator.new()
	lrng.seed = rng.seed + 77
	for i in 230:
		var c := terrain.random_land_point(lrng, Terrain.WATER_LEVEL + 1.4, 0.35)
		if _near_village(c.x, c.y, 6.0):
			continue
		loot_points.append({"pos": Vector3(c.x, terrain.height_at(c.x, c.y) + 0.08, c.y),
			"kind": "weapon" if i % 5 < 2 else "gear", "village": false})


func _build_spawn_points() -> void:
	var srng := RandomNumberGenerator.new()
	srng.seed = rng.seed + 78
	for i in 60:
		var c := terrain.random_land_point(srng, Terrain.WATER_LEVEL + 1.4, 0.35)
		if _near_village(c.x, c.y, 6.0):
			continue
		spawn_points.append(Vector3(c.x, terrain.height_at(c.x, c.y) + 0.2, c.y))


## Jeeps parked on the verge of roads, nose along the road.
func _build_vehicle_spawns() -> void:
	var vrng := RandomNumberGenerator.new()
	vrng.seed = rng.seed + 79
	for r in villages.roads:
		if r.get("bridge", false):
			continue
		var a: Vector2 = r.a
		var b: Vector2 = r.b
		var len := a.distance_to(b)
		if len < 40.0:
			continue
		var dir := (b - a) / len
		var s := vrng.randf_range(10.0, 60.0)
		while s < len - 10.0:
			var side := 1.0 if vrng.randf() < 0.5 else -1.0
			var p := a + dir * s + dir.orthogonal() * side * (float(r.w) + 2.6)
			s += vrng.randf_range(110.0, 220.0)
			if terrain.slope_at(p.x, p.y) > 0.22 or terrain.is_water(p.x, p.y):
				continue
			# A jeep is ~4.4 m long: keep it off walls and out of doorways.
			if villages.blocks_house(p, 2.6):
				continue
			var yaw := atan2(-dir.x, -dir.y) + (PI if vrng.randf() < 0.5 else 0.0)
			vehicle_spawns.append([Vector3(p.x, terrain.height_at(p.x, p.y), p.y), yaw])


## Coarse buckets of settlements, POIs and landmark yards, and of road
## segments, so scatter checks only look at what is nearby.
func _build_grids() -> void:
	var add := func(grid: Dictionary, c: Vector2, reach: float, item: Variant) -> void:
		var x0 := int(floor((c.x - reach) / GRID))
		var x1 := int(floor((c.x + reach) / GRID))
		var z0 := int(floor((c.y - reach) / GRID))
		var z1 := int(floor((c.y + reach) / GRID))
		for gz in range(z0, z1 + 1):
			for gx in range(x0, x1 + 1):
				var k := Vector2i(gx, gz)
				if not grid.has(k):
					grid[k] = []
				grid[k].append(item)
	for v in villages.village_pads:
		add.call(_pad_grid, v.center, float(v.radius) + 45.0, {"center": v.center, "radius": float(v.radius), "kind": "village"})
	for p in villages.poi_pads:
		add.call(_pad_grid, p.center, float(p.radius) + 12.0, {"center": p.center, "radius": float(p.radius), "kind": "poi"})
	for a in villages.landmarks.clear_areas:
		add.call(_pad_grid, a.center, float(a.radius) + 12.0, {"center": a.center, "radius": float(a.radius), "kind": "poi"})
	for r in villages.roads:
		var a: Vector2 = r.a
		var b: Vector2 = r.b
		var w: float = r.w
		var n := int(a.distance_to(b) / (GRID * 0.5)) + 1
		var seen := {}
		for i in n + 1:
			var p := a.lerp(b, float(i) / float(n))
			var k := Vector2i(int(floor(p.x / GRID)), int(floor(p.y / GRID)))
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var kk := k + Vector2i(dx, dz)
					if seen.has(kk):
						continue
					seen[kk] = true
					if not _road_grid.has(kk):
						_road_grid[kk] = []
					_road_grid[kk].append(r)


func _road_distance(x: float, z: float) -> float:
	var k := Vector2i(int(floor(x / GRID)), int(floor(z / GRID)))
	if not _road_grid.has(k):
		return 1e9
	var p := Vector2(x, z)
	var best := 1e9
	for r in _road_grid[k]:
		var a: Vector2 = r.a
		var b: Vector2 = r.b
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(0.001, ab.length_squared()), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t) - float(r.w))
	return best


func _near_village(x: float, z: float, radius: float) -> bool:
	var k := Vector2i(int(floor(x / GRID)), int(floor(z / GRID)))
	if not _pad_grid.has(k):
		return false
	var p := Vector2(x, z)
	for it in _pad_grid[k]:
		var c: Vector2 = it.center
		if it.kind == "village":
			# `radius` is tuned for a standard 31 m village; scale for towns/farms,
			# but never closer than the settlement's own yard.
			if p.distance_to(c) < maxf(radius + float(it.radius) - 31.0, float(it.radius) + minf(radius, 4.0)):
				return true
		elif p.distance_to(c) < float(it.radius) + minf(radius, 6.0):
			return true
	return false


# -------------------------------------------------------------- set dressing

func _build_distant_islands() -> void:
	# Low green hills on the horizon with a sand ring at the waterline, so the
	# sea does not just end at the sky.
	var green := StandardMaterial3D.new()
	green.albedo_color = Color(0.22, 0.36, 0.22)
	green.roughness = 1.0
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color(0.72, 0.68, 0.52)
	sand.roughness = 1.0
	for i in 9:
		var ang := TAU * float(i) / 9.0 + rng.randf_range(-0.2, 0.2)
		var dist := rng.randf_range(2100.0, 3000.0)
		var height := rng.randf_range(50.0, 150.0)
		var radius := rng.randf_range(200.0, 420.0)
		var c := Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
		var parts := rng.randi_range(3, 6)
		for j in parts:
			var cone := CylinderMesh.new()
			var r := radius * rng.randf_range(0.45, 0.9)
			var h := height * rng.randf_range(0.5, 1.0)
			cone.top_radius = r * 0.12
			cone.bottom_radius = r
			cone.height = h
			cone.radial_segments = 24
			cone.rings = 2
			var mi := MeshInstance3D.new()
			mi.mesh = cone
			mi.material_override = green
			var off := Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5)) * radius
			mi.position = c + off + Vector3(0, h * 0.5 - 2.0, 0)
			mi.scale = Vector3(1.0, 1.0, rng.randf_range(0.6, 1.0))
			mi.rotation.y = rng.randf() * TAU
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
		var beach := CylinderMesh.new()
		beach.top_radius = radius * 0.86
		beach.bottom_radius = radius * 0.95
		beach.height = 3.0
		beach.radial_segments = 32
		var bi := MeshInstance3D.new()
		bi.mesh = beach
		bi.material_override = sand
		bi.position = c + Vector3(0, -0.8, 0)
		bi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(bi)


func _cloud_texture() -> Texture2D:
	# Soft cauliflower puff: fbm noise inside a radial falloff, shaded a little
	# darker underneath.
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 0.045
	noise.fractal_octaves = 4
	for y in n:
		for x in n:
			var p := Vector2(x - n * 0.5, y - n * 0.5) / (n * 0.5)
			var r := p.length()
			var nv := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf((1.0 - r * r) * 1.6 - 0.25 + (nv - 0.5) * 0.9, 0.0, 1.0)
			a = smoothstep(0.0, 1.0, a)
			var shade := lerpf(1.0, 0.78, clampf(p.y * 0.8 + 0.3, 0.0, 1.0))
			img.set_pixel(x, y, Color(shade, shade, shade * 1.02, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _build_clouds() -> void:
	var tex := _cloud_texture()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.disable_receive_shadows = true
	mat.vertex_color_use_as_albedo = true
	for i in 64:
		var dist := rng.randf_range(200.0, 2600.0)
		var ang := rng.randf() * TAU
		var base := Vector3(cos(ang) * dist, rng.randf_range(330.0, 460.0), sin(ang) * dist)
		var size := rng.randf_range(60.0, 140.0)
		# A cloud is a cluster of overlapping puffs.
		for j in rng.randi_range(4, 7):
			var s := Sprite3D.new()
			s.texture = tex
			s.material_override = mat
			s.pixel_size = 1.0 / 128.0
			s.modulate = Color(1, 1, 1, rng.randf_range(0.55, 0.85))
			s.position = base + Vector3(rng.randf_range(-1.0, 1.0) * size, rng.randf_range(-0.15, 0.25) * size, rng.randf_range(-0.6, 0.6) * size)
			s.scale = Vector3.ONE * size * rng.randf_range(0.7, 1.3)
			s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(s)


func _build_minimap() -> void:
	# Shade straight from the height samples (one pixel per 6 m grid point),
	# then upscale and draw roads and buildings at full resolution on top.
	var n := Terrain.RES
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var hs := terrain.heights
	var light := Vector3(-0.6, 0.75, -0.5).normalized()
	for iz in n:
		var z := -Terrain.HALF + float(iz) * Terrain.STEP
		for ix in n:
			var x := -Terrain.HALF + float(ix) * Terrain.STEP
			var h: float = hs[iz * n + ix]
			var hl: float = hs[iz * n + maxi(ix - 1, 0)]
			var hr: float = hs[iz * n + mini(ix + 1, n - 1)]
			var hd: float = hs[maxi(iz - 1, 0) * n + ix]
			var hu: float = hs[mini(iz + 1, n - 1) * n + ix]
			var nrm := Vector3(hl - hr, 2.0 * Terrain.STEP, hd - hu).normalized()
			var slope := 1.0 - nrm.y
			var wl := terrain.water_surface_at(x, z)
			var c: Color
			if h < wl:
				var depth := clampf((wl - h) / 9.0, 0.0, 1.0)
				c = Color(0.16, 0.36, 0.46).lerp(Color(0.07, 0.18, 0.28), depth)
			elif h < wl + 1.6:
				c = Color(0.78, 0.72, 0.55)
			elif slope > 0.45:
				c = Color(0.46, 0.44, 0.40)
			else:
				var hv := clampf((h - 2.0) / 70.0, 0.0, 1.0)
				c = Color(0.31, 0.44, 0.22).lerp(Color(0.50, 0.55, 0.33), hv)
				if terrain.forest_density(x, z) > 0.62:
					c = c.lerp(Color(0.17, 0.31, 0.15), 0.4)
			if h >= wl:
				var shade := 0.55 + clampf(nrm.dot(light), 0.0, 1.0) * 0.6
				if fmod(h, 10.0) < 0.6 and h > 3.0 and slope < 0.45:
					shade *= 0.9
				c = Color(c.r * shade, c.g * shade, c.b * shade)
			img.set_pixel(ix, iz, Color(c.r, c.g, c.b, 1.0))
	var res := 1024
	img.resize(res, res, Image.INTERPOLATE_BILINEAR)
	# Roads.
	var k := float(res) / Terrain.SIZE
	var road_col := Color(0.64, 0.54, 0.40)
	for r in villages.roads:
		var a: Vector2 = r.a
		var b: Vector2 = r.b
		var w: float = r.w + (1.0 if r.get("bridge", false) else 0.4)
		var col: Color = Color(0.78, 0.74, 0.66) if r.get("bridge", false) else road_col
		var steps := int(a.distance_to(b) * k) + 1
		for i in steps + 1:
			var p := a.lerp(b, float(i) / float(steps))
			var px := (p + Vector2.ONE * Terrain.HALF) * k
			var rad := maxf(1.0, w * k)
			for oy in range(int(-rad), int(rad) + 1):
				for ox in range(int(-rad), int(rad) + 1):
					var qx := int(px.x) + ox
					var qy := int(px.y) + oy
					if qx >= 0 and qy >= 0 and qx < res and qy < res and ox * ox + oy * oy <= rad * rad + 0.5:
						img.set_pixel(qx, qy, col)
	# Buildings as small dark blocks, like a real map.
	for h in villages.houses:
		var hc: Vector2 = h.center
		_map_rect(img, res, hc, Vector2(float(h.w), float(h.d)) * 0.5, Color(0.36, 0.30, 0.26))
	for t in villages.towers:
		_map_rect(img, res, t.center, Vector2(3.5, 3.5), Color(0.22, 0.20, 0.20))
	for p in villages.poi_pads:
		if p.type == "ruin":
			_map_rect(img, res, p.center, Vector2(4.0, 3.0), Color(0.45, 0.42, 0.38))
	var lm := Color(0.30, 0.27, 0.25)
	_map_rect(img, res, terrain.castle_c, Vector2(24.0, 24.0), lm)
	_map_rect(img, res, terrain.temple_c, Vector2(16.0, 16.0), lm)
	_map_rect(img, res, terrain.lighthouse_c, Vector2(4.0, 4.0), Color(0.85, 0.82, 0.78))
	_map_rect(img, res, terrain.henge_c, Vector2(5.0, 5.0), Color(0.6, 0.58, 0.55))
	minimap_texture = ImageTexture.create_from_image(img)


func _map_rect(img: Image, res: int, c: Vector2, half: Vector2, col: Color) -> void:
	var k := float(res) / Terrain.SIZE
	var x0 := int((c.x - half.x + Terrain.HALF) * k)
	var x1 := int((c.x + half.x + Terrain.HALF) * k)
	var y0 := int((c.y - half.y + Terrain.HALF) * k)
	var y1 := int((c.y + half.y + Terrain.HALF) * k)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if x >= 0 and y >= 0 and x < res and y < res:
				img.set_pixel(x, y, col)



# ------------------------------------------------------------------ gap fill
# Closes bare patches the random scatters left behind, so the map reads as
# continuous ground cover instead of grass with bald spots. Placement is
# deterministic (same seed -> same map) and batched into CHUNK_SIZE tiles per
# species, exactly like _scatter_ground_cover, so it costs no extra draw calls
# at distance.
func _fill_gaps() -> void:
	const CELL := 45.0
	const MIN_PER_CELL := 6
	const MAX_PER_CELL := 14
	const VIEW := 130.0
	var kinds := [
		{"name": "Grass_Common_Short", "w": 0.46, "scale": Vector2(0.60, 0.95)},
		{"name": "Grass_Common_Tall", "w": 0.22, "scale": Vector2(0.65, 1.05)},
		{"name": "Fern_1", "w": 0.12, "scale": Vector2(0.60, 0.95)},
		{"name": "Bush_Common", "w": 0.12, "scale": Vector2(0.55, 0.90)},
		{"name": "Flower_4_Group", "w": 0.08, "scale": Vector2(0.55, 0.85)},
	]
	# Cumulative weights, so the pick stays deterministic against rng.randf().
	var offsets: Array[float] = []
	var acc := 0.0
	for k in kinds:
		acc += k.w
		offsets.append(acc)

	var span := Terrain.HALF - 8.0
	var cells := int(ceil((span * 2.0) / CELL))
	var buckets: Dictionary = {}
	for k in kinds:
		buckets[k.name] = []

	for cz in cells:
		for cx in cells:
			var ox := -span + cx * CELL
			var oz := -span + cz * CELL
			for i in MAX_PER_CELL:
				var x := ox + rng.randf_range(0.0, CELL)
				var z := oz + rng.randf_range(0.0, CELL)
				if absf(x) > span or absf(z) > span:
					continue
				var h := terrain.height_at(x, z)
				if h < Terrain.WATER_LEVEL + 0.4:
					continue
				if terrain.slope_at(x, z) > 0.55:
					continue
				if _near_village(x, z, 16.0):
					continue
				# Everything past MIN_PER_CELL is thinned out on bare rock, so
				# exposed stone keeps reading as stone.
				if i >= MIN_PER_CELL and terrain.slope_at(x, z) > 0.30 and rng.randf() > 0.35:
					continue
				var roll := rng.randf()
				var pick: int = kinds.size() - 1
				for ki in offsets.size():
					if roll < offsets[ki]:
						pick = ki
						break
				var kind: Dictionary = kinds[pick]
				if kind.name.begins_with("Flower") and terrain.forest_density(x, z) > 0.45:
					kind = kinds[0]
				var sr: Vector2 = kind.scale
				buckets[kind.name].append({
					"pos": Vector3(x, h - 0.02, z), "rot": rng.randf_range(0.0, TAU),
					"scale": rng.randf_range(sr.x, sr.y),
				})

	for k in kinds:
		var list: Array = buckets[k.name]
		if list.is_empty():
			continue
		var data := _nature_mesh(k.name)
		if data.is_empty():
			continue
		# Same wind material construction as _scatter_ground_cover, so the
		# top-up is visually identical to the cover it is filling around.
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/foliage.gdshader")
		if data.albedo != null:
			mat.set_shader_parameter("albedo_tex", data.albedo)
		else:
			mat.set_shader_parameter("albedo_tex", load("res://assets/textures/tex_grass.png"))
		mat.set_shader_parameter("wind_strength", 0.14)
		mat.set_shader_parameter("sway_height", 1.4)
		mat.set_shader_parameter("alpha_cut", 0.32)

		var tiles: Dictionary = {}
		for it in list:
			var tx := int(floor((it.pos.x + Terrain.HALF) / CHUNK_SIZE))
			var tz := int(floor((it.pos.z + Terrain.HALF) / CHUNK_SIZE))
			var key := "%d_%d" % [tx, tz]
			if not tiles.has(key):
				tiles[key] = []
			tiles[key].append(it)
		for key in tiles:
			var arr: Array = tiles[key]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = data.mesh
			mm.instance_count = arr.size()
			for i in arr.size():
				var it: Dictionary = arr[i]
				mm.set_instance_transform(i, Transform3D(
					Basis(Vector3.UP, it.rot).scaled(Vector3.ONE * it.scale), it.pos))
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Gf_%s_%s" % [k.name, key]
			mmi.multimesh = mm
			mmi.material_override = mat
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = VIEW + GROUND_HALF_DIAG
			add_child(mmi)
			stats.ground += arr.size()
