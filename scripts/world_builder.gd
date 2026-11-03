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

var stats := {
	"trees": 0, "ground": 0, "rocks": 0, "houses": 0, "loot": 0, "colliders": 0,
	"build_ms": 0,
}


func build(p_seed: int) -> void:
	var started := Time.get_ticks_msec()
	rng.seed = p_seed
	terrain = Terrain.new(p_seed)

	_build_lighting()
	villages = Villages.new()
	villages.name = "Villages"
	add_child(villages)
	villages.build(terrain, p_seed)
	loot_points.append_array(villages.loot_points)
	stats.houses = villages._stat.houses

	_build_terrain()
	_build_water()
	_scatter_trees()
	_scatter_ground_cover()
	_fill_gaps()
	_scatter_rocks()
	_build_wild_loot()
	_build_spawn_points()
	_build_distant_islands()
	_build_clouds()
	_build_minimap()
	stats.loot = loot_points.size()
	stats.build_ms = Time.get_ticks_msec() - started
	print("[world] built in %d ms — %s" % [stats.build_ms, str(stats)])


# ---------------------------------------------------------------- environment

func _build_lighting() -> void:
	var sun := DirectionalLight3D.new()
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
	sky_mat.ground_bottom_color = Color(0.10, 0.26, 0.34)
	sky_mat.ground_horizon_color = Color(0.56, 0.71, 0.84)
	sky_mat.ground_curve = 0.08
	sky_mat.sun_angle_max = 22.0
	sky_mat.sun_curve = 0.12
	sky.sky_material = sky_mat
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
	env.fog_density = 0.0009
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


# ------------------------------------------------------------------- terrain

func _build_terrain() -> void:
	_terrain_material = ShaderMaterial.new()
	_terrain_material.shader = load("res://shaders/terrain.gdshader")
	_terrain_material.set_shader_parameter("tex_grass", load("res://assets/textures/tex_grass.png"))
	_terrain_material.set_shader_parameter("tex_dirt", load("res://assets/textures/tex_dirt.png"))
	_terrain_material.set_shader_parameter("tex_sand", load("res://assets/textures/tex_sand.png"))
	_terrain_material.set_shader_parameter("tex_rock", load("res://assets/textures/tex_rock.png"))
	_terrain_material.set_shader_parameter("tex_macro", load("res://assets/textures/tex_macro.png"))

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

			var shape := CollisionShape3D.new()
			var tri := mesh.create_trimesh_shape()
			tri.backface_collision = true
			shape.shape = tri
			body.add_child(shape)
	stats.colliders += Terrain.CHUNKS * Terrain.CHUNKS


func _chunk_mesh(cx: int, cz: int) -> ArrayMesh:
	var cells := Terrain.CHUNK_CELLS
	var origin_x := -Terrain.HALF + float(cx * cells) * Terrain.STEP
	var origin_z := -Terrain.HALF + float(cz * cells) * Terrain.STEP
	var verts: Array[Vector3] = []
	var normals: Array[Vector3] = []
	var colors: Array[Color] = []
	for iz in cells + 1:
		for ix in cells + 1:
			var x := origin_x + float(ix) * Terrain.STEP
			var z := origin_z + float(iz) * Terrain.STEP
			var h := terrain.height_at(x, z)
			verts.append(Vector3(x, h, z))
			normals.append(terrain.normal_at(x, z))
			colors.append(_ground_weights(x, z, h, terrain.normal_at(x, z)))

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
			_add_tri(st, verts, normals, colors, [i00, i10, i01])
			_add_tri(st, verts, normals, colors, [i10, i11, i01])
	st.index()
	return st.commit()


func _add_tri(st: SurfaceTool, verts: Array[Vector3], normals: Array[Vector3], colors: Array[Color], idx: Array) -> void:
	for i in idx:
		st.set_color(colors[i])
		st.set_normal(normals[i])
		st.set_uv(Vector2(verts[i].x, verts[i].z) * 0.02)
		st.add_vertex(verts[i])


func _ground_weights(x: float, z: float, h: float, n: Vector3) -> Color:
	var slope := 1.0 - n.y
	var sand := smoothstep(3.6, 1.2, h)
	var rock := smoothstep(0.30, 0.52, slope) * 0.9 + smoothstep(33.0, 45.0, h) * 0.55
	var macro := terrain.macro.get_noise_2d(x, z) * 0.5 + 0.5
	var dirt := 0.0
	# Village pads: keep the worn-earth ring but let it fade out instead of
	# ending in a hard 0.8 disc. Widened 30 -> 34 so the edge is softer.
	for v in villages.village_pads:
		var c: Vector2 = v.center
		var d := Vector2(x, z).distance_to(c)
		dirt = maxf(dirt, smoothstep(34.0, 16.0, d) * 0.62)
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
	plane.size = Vector2(16000.0, 16000.0)
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	var mi := MeshInstance3D.new()
	mi.name = "Sea"
	mi.mesh = plane
	mi.material_override = _mat_water
	mi.position.y = Terrain.WATER_LEVEL
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


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
	var attempts := 5200
	for i in attempts:
		var x := rng.randf_range(-Terrain.HALF + 12.0, Terrain.HALF - 12.0)
		var z := rng.randf_range(-Terrain.HALF + 12.0, Terrain.HALF - 12.0)
		var h := terrain.height_at(x, z)
		if h < Terrain.WATER_LEVEL + 1.2:
			continue
		if terrain.slope_at(x, z) > 0.52:
			continue
		if _near_village(x, z, 38.0):
			continue
		var forest := terrain.forest_density(x, z)
		var chance := smoothstep(0.36, 0.72, forest) * 0.85 + 0.06
		chance = clampf(chance, 0.0, 0.62)
		if rng.randf() > chance:
			continue
		var cell := "%d_%d" % [int(x / 7.0), int(z / 7.0)]
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
	add_child(trunk_body)

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
		mmi.visibility_range_end = 430.0 + TREE_HALF_DIAG
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


func _scatter_ground_cover() -> void:
	var kinds := [
		{"name": "Grass_Common_Short", "w": 0.44, "view": 55.0, "scale": Vector2(0.75, 1.45), "wind": 0.16},
		{"name": "Grass_Common_Tall", "w": 0.20, "view": 60.0, "scale": Vector2(0.75, 1.25), "wind": 0.18},
		{"name": "Fern_1", "w": 0.11, "view": 75.0, "scale": Vector2(0.34, 0.55), "wind": 0.09},
		{"name": "Bush_Common", "w": 0.14, "view": 140.0, "scale": Vector2(0.55, 0.95), "wind": 0.06},
		{"name": "Bush_Common_Flowers", "w": 0.05, "view": 140.0, "scale": Vector2(0.55, 0.90), "wind": 0.06},
		{"name": "Flower_4_Group", "w": 0.06, "view": 90.0, "scale": Vector2(0.55, 0.85), "wind": 0.10},
	]
	var buckets: Dictionary = {}
	for k in kinds:
		buckets[k.name] = []

	for i in 8000:
		var x := rng.randf_range(-Terrain.HALF + 8.0, Terrain.HALF - 8.0)
		var z := rng.randf_range(-Terrain.HALF + 8.0, Terrain.HALF - 8.0)
		var h := terrain.height_at(x, z)
		if h < Terrain.WATER_LEVEL + 0.6:
			continue
		if terrain.slope_at(x, z) > 0.5:
			continue
		if _near_village(x, z, 14.0):
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
		# Flowers are happiest in the open, tall grass in the trees.
		if chosen == "Flower_4_Group" and forest > 0.6:
			continue
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
	for i in 1300:
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
	for i in 900:
		if groups["Rock_Medium_1"].size() + groups["Rock_Medium_2"].size() > 420:
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
		add_child(body)
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


func _build_wild_loot() -> void:
	# A few weapons out in the open so a bad drop still has a chance.
	for i in 26:
		var spot := _random_land_point(30.0, 380.0)
		if spot == Vector3.ZERO:
			continue
		loot_points.append({"pos": spot + Vector3(0, 0.08, 0), "kind": "weapon", "village": false})
	for i in 34:
		var spot := _random_land_point(20.0, 400.0)
		if spot == Vector3.ZERO:
			continue
		loot_points.append({"pos": spot + Vector3(0, 0.08, 0), "kind": "gear", "village": false})


func _build_spawn_points() -> void:
	for i in 40:
		var spot := _random_land_point(0.0, 300.0)
		if spot == Vector3.ZERO:
			continue
		if _near_village(spot.x, spot.z, 6.0):
			continue
		spawn_points.append(spot + Vector3(0, 0.2, 0))


func _random_land_point(min_dist: float, max_dist: float) -> Vector3:
	for attempt in 60:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(min_dist, max_dist)
		var x := cos(ang) * dist
		var z := sin(ang) * dist
		var h := terrain.height_at(x, z)
		if h < Terrain.WATER_LEVEL + 1.4:
			continue
		if terrain.slope_at(x, z) > 0.35:
			continue
		return Vector3(x, h, z)
	return Vector3.ZERO


func _near_village(x: float, z: float, radius: float) -> bool:
	for v in villages.village_pads:
		var c: Vector2 = v.center
		if Vector2(x, z).distance_to(c) < radius:
			return true
	# Towers and ruins keep a clear yard of their own.
	for p in villages.poi_pads:
		var c: Vector2 = p.center
		if Vector2(x, z).distance_to(c) < float(p.radius) + minf(radius, 6.0):
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
		var dist := rng.randf_range(900.0, 1500.0)
		var height := rng.randf_range(30.0, 90.0)
		var radius := rng.randf_range(120.0, 260.0)
		var c := Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
		var parts := rng.randi_range(2, 4)
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
		beach.top_radius = radius * 1.08
		beach.bottom_radius = radius * 1.15
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
	for i in 26:
		var dist := rng.randf_range(150.0, 1100.0)
		var ang := rng.randf() * TAU
		var base := Vector3(cos(ang) * dist, rng.randf_range(150.0, 230.0), sin(ang) * dist)
		var size := rng.randf_range(50.0, 110.0)
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
	var res := 512
	var img := Image.create(res, res, false, Image.FORMAT_RGBA8)
	for py in res:
		for px in res:
			var x := (float(px) / float(res - 1) - 0.5) * Terrain.SIZE
			var z := (float(py) / float(res - 1) - 0.5) * Terrain.SIZE
			var h := terrain.height_at(x, z)
			var n := terrain.normal_at(x, z)
			var slope := 1.0 - n.y
			var c: Color
			if h < Terrain.WATER_LEVEL:
				var depth := clampf((Terrain.WATER_LEVEL - h) / 9.0, 0.0, 1.0)
				c = Color(0.13, 0.30, 0.40).lerp(Color(0.07, 0.18, 0.28), depth)
			elif h < Terrain.WATER_LEVEL + 1.8:
				c = Color(0.78, 0.72, 0.55)
			elif slope > 0.42:
				c = Color(0.42, 0.41, 0.38)
			else:
				var hv := clampf((h - 2.0) / 40.0, 0.0, 1.0)
				c = Color(0.31, 0.44, 0.22).lerp(Color(0.46, 0.53, 0.30), hv)
			var shade := 1.0 + (terrain.macro.get_noise_2d(x, z)) * 0.06
			if h >= Terrain.WATER_LEVEL:
				# Hillshade from the north-west so ridges and high ground read.
				var light := Vector3(-0.6, 0.75, -0.5).normalized()
				var ndl := clampf(n.dot(light), 0.0, 1.0)
				shade *= 0.55 + ndl * 0.6
				# Faint contour every 8 m.
				if fmod(h, 8.0) < 0.45 and h > 3.0:
					shade *= 0.88
				# Forest tint.
				if terrain.forest_density(x, z) > 0.62:
					c = c.lerp(Color(0.18, 0.32, 0.16), 0.35)
			c = Color(c.r * shade, c.g * shade, c.b * shade, 1.0)
			img.set_pixel(px, py, c)
	# Buildings as small dark blocks, like a real map.
	for h in villages.houses:
		var hc: Vector2 = h.center
		_map_rect(img, res, hc, Vector2(float(h.w), float(h.d)) * 0.5, Color(0.36, 0.30, 0.26))
	for t in villages.towers:
		_map_rect(img, res, t.center, Vector2(3.5, 3.5), Color(0.22, 0.20, 0.20))
	for p in villages.poi_pads:
		if p.type == "ruin":
			_map_rect(img, res, p.center, Vector2(4.0, 3.0), Color(0.45, 0.42, 0.38))
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
