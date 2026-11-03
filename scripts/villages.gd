extends Node3D
class_name Villages

## Modular medieval village builder. Walls are 2 m modules from the kit, roofs are
## matched to each footprint, and every house gets interior loot points + box
## collision. Geometry is batched into MultiMeshes (one per piece type) so the
## whole archipelago of villages costs a handful of draw calls.

const MODEL_PATH := "res://assets/village/%s.gltf"
const WALL_HEIGHT := 3.123
const DOOR_WIDTH := 1.30

const TOWN_NAMES := ["MOSSFORD", "HOLLOWMERE", "BRIARWICK", "STONEHELM", "ASHVALE", "THORNBY",
	"KESTREL BAY", "OLDHAVEN", "DUNMORE", "REDWATER"]

## Footprints that have a matching roof piece in the kit.
const LOTS := [
	Vector2i(4, 6), Vector2i(6, 6), Vector2i(6, 8),
	Vector2i(4, 8), Vector2i(8, 8), Vector2i(8, 10),
]

var terrain: Terrain
var rng := RandomNumberGenerator.new()
var houses: Array[Dictionary] = []
var village_pads: Array[Dictionary] = []
var roads: Array[Dictionary] = []
var loot_points: Array[Dictionary] = []
var towers: Array[Dictionary] = []
var poi_pads: Array[Dictionary] = []

var _cache: Dictionary = {}
var _batches: Dictionary = {}
var _colliders: Array[Dictionary] = []
var _stat := {"houses": 0, "pieces": 0, "village_count": 0, "towers": 0, "ruins": 0}


func build(p_terrain: Terrain, p_seed: int) -> void:
	terrain = p_terrain
	rng.seed = p_seed + 4242

	_plan_villages()
	for h in houses:
		_build_house(h)
	_build_village_extras()
	_plan_towers()
	_plan_ruins()
	_commit_batches()
	_commit_colliders()
	print("[villages] %d villages, %d houses, %d towers, %d ruins, %d pieces, %d loot points, %d colliders" % [
		_stat.village_count, _stat.houses, _stat.towers, _stat.ruins, _stat.pieces, loot_points.size(), _colliders.size()
	])


func _plan_villages() -> void:
	# Settlements are placed per seed: three street towns, four villages and a
	# handful of farmsteads, spread out over flat-enough land.
	var specs: Array = ["town", "town", "town", "village", "village", "village", "village",
		"farm", "farm", "farm", "farm", "farm", "farm"]
	var size := {"town": 44.0, "village": 30.0, "farm": 15.0}
	var spacing := {"town": 175.0, "village": 120.0, "farm": 75.0}
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = rng.seed + 11
	var name_i := 0
	for type in specs:
		var radius: float = size[type]
		var site := Vector2.INF
		for attempt in 400:
			var a := rng2.randf() * TAU
			var r := sqrt(rng2.randf()) * (370.0 - radius)
			var c := Vector2(cos(a), sin(a)) * r
			if terrain.height_at(c.x, c.y) < 4.0 or terrain.slope_at(c.x, c.y) > 0.3:
				continue
			if terrain.roughness(c.x, c.y, radius * 0.7) > maxf(6.0, radius * 0.3):
				continue
			var ok := true
			for v in village_pads:
				if c.distance_to(v.center) < maxf(float(spacing[type]), float(v.spacing)) * (0.5 if type == "farm" or v.type == "farm" else 1.0) + radius + float(v.radius) - 40.0:
					ok = false
					break
			if ok:
				site = c
				break
		if site == Vector2.INF:
			continue
		var pad := terrain.flatten_circle(site.x, site.y, radius, radius * 0.8)
		var axis := rng2.randf() * PI
		var town_name := ""
		if type != "farm":
			town_name = TOWN_NAMES[name_i % TOWN_NAMES.size()]
			name_i += 1
		village_pads.append({"center": site, "pad": pad, "name": town_name, "radius": radius,
			"type": type, "spacing": spacing[type], "axis": axis})
		_stat.village_count += 1
		match type:
			"town":
				_plan_street(site, pad, radius, axis)
			"village":
				_plan_ring(site, pad, rng.randi_range(4, 6), 9.0, radius - 4.0)
			"farm":
				_plan_ring(site, pad, rng.randi_range(1, 2), 3.0, radius - 3.0)
	_plan_roads()


## Houses on both sides of a main street, doors to the road, a plaza mid-way.
func _plan_street(site: Vector2, pad: float, radius: float, axis: float) -> void:
	var dir := Vector2(cos(axis), sin(axis))
	var perp := Vector2(-dir.y, dir.x)
	roads.append({"a": site - dir * (radius + 6.0), "b": site + dir * (radius + 6.0), "w": 3.6})
	var n := int((radius - 8.0) / 12.0)
	for k in range(-n, n + 1):
		var along := float(k) * 12.0
		if absf(along) < 7.0:
			continue  # plaza
		for side in [-1.0, 1.0]:
			if rng.randf() > 0.88:
				continue
			var lot: Vector2i = LOTS[rng.randi() % LOTS.size()]
			var w := float(lot.x)
			var d := float(lot.y)
			if w > 10.0:
				var tmp := w
				w = d
				d = tmp
			var c: Vector2 = site + dir * along + perp * side * (6.2 + d * 0.5)
			var hr := maxf(w, d) * 0.5
			if c.distance_to(site) + hr > radius - 1.0:
				continue
			_add_house(c, w, d, -axis, pad, site + dir * along)
	# Side street across the plaza for bigger towns.
	roads.append({"a": site - perp * (radius * 0.6), "b": site + perp * (radius * 0.6), "w": 2.8})


## Houses scattered around a centre, doors facing it.
func _plan_ring(site: Vector2, pad: float, count: int, min_d: float, max_r: float) -> void:
	var placed := 0
	var tries := 0
	while placed < count and tries < 120:
		tries += 1
		var lot: Vector2i = LOTS[rng.randi() % LOTS.size()]
		var w := float(lot.x)
		var d := float(lot.y)
		if rng.randf() < 0.5:
			var tmp := w
			w = d
			d = tmp
		var radius := maxf(w, d) * 0.5
		var ang := rng.randf() * TAU
		var c := site + Vector2(cos(ang), sin(ang)) * rng.randf_range(min_d, max_r)
		if c.distance_to(site) + radius > max_r:
			continue
		if _add_house(c, w, d, float(rng.randi_range(0, 3)) * PI * 0.5, pad, site):
			placed += 1


func _add_house(c: Vector2, w: float, d: float, yaw_house: float, pad: float, face_to: Vector2) -> bool:
	var radius := maxf(w, d) * 0.5
	for h in houses:
		var hc: Vector2 = h.center
		if c.distance_to(hc) < radius + float(h.radius) + 2.2:
			return false
	houses.append({
		"center": c, "w": w, "d": d, "yaw": yaw_house, "pad": pad,
		"radius": radius, "door_side": _door_for(face_to - c, yaw_house),
		"style": "Plaster" if rng.randf() < 0.72 else "UnevenBrick",
	})
	return true


## Dirt roads between neighbouring settlements (each links to its nearest two).
func _plan_roads() -> void:
	var done := {}
	for i in village_pads.size():
		var a: Vector2 = village_pads[i].center
		var near: Array = []
		for j in village_pads.size():
			if i != j:
				near.append([a.distance_to(village_pads[j].center), j])
		near.sort_custom(func(x, y): return x[0] < y[0])
		for e in near.slice(0, 2):
			var j: int = e[1]
			var key := "%d_%d" % [mini(i, j), maxi(i, j)]
			if done.has(key) or float(e[0]) > 330.0:
				continue
			done[key] = true
			# A gentle bend through a midpoint so roads do not look ruled.
			var b: Vector2 = village_pads[j].center
			var mid := (a + b) * 0.5 + (b - a).orthogonal().normalized() * rng.randf_range(-25.0, 25.0)
			roads.append({"a": a, "b": mid, "w": 2.6})
			roads.append({"a": mid, "b": b, "w": 2.6})


## Distance from a point to the nearest road centre line.
func road_distance(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := 1e9
	for r in roads:
		var a: Vector2 = r.a
		var b: Vector2 = r.b
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(0.001, ab.length_squared()), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t) - float(r.w))
	return best


func _door_for(to_center: Vector2, yaw_house: float) -> int:
	# Rotate the direction into house space, then pick the side it points at.
	var local := to_center.rotated(-yaw_house)
	if absf(local.x) > absf(local.y):
		return 1 if local.x > 0.0 else 3
	return 0 if local.y > 0.0 else 2


func _build_house(h: Dictionary) -> void:
	var center: Vector2 = h.center
	var yaw_house: float = h.yaw
	var pad: float = h.pad
	var w: float = h.w
	var d: float = h.d
	var style: String = h.style
	var house_basis := Basis(Vector3.UP, yaw_house)
	var origin := Vector3(center.x, pad, center.y)

	# Floor tiles.
	var floor_key := "Floor_Brick" if rng.randf() < 0.45 else "Floor_WoodDark"
	var fx := -w * 0.5 + 1.0
	while fx < w * 0.5 - 0.1:
		var fz := -d * 0.5 + 1.0
		while fz < d * 0.5 - 0.1:
			_place(floor_key, origin + house_basis * Vector3(fx, 0.012, fz), yaw_house)
			fz += 2.0
		fx += 2.0

	# Walls, one 2 m module at a time.
	for side in 4:
		var horizontal := side == 0 or side == 2
		var cells := int(w * 0.5) if horizontal else int(d * 0.5)
		var door_index := cells / 2
		for i in cells:
			var along := -((cells - 1) * 0.5) * 2.0 + float(i) * 2.0
			var local := Vector3.ZERO
			var wall_yaw := 0.0
			match side:
				0:
					local = Vector3(along, 0.0, d * 0.5)
					wall_yaw = 0.0
				1:
					local = Vector3(w * 0.5, 0.0, along)
					wall_yaw = PI * 0.5
				2:
					local = Vector3(-along, 0.0, -d * 0.5)
					wall_yaw = PI
				3:
					local = Vector3(-w * 0.5, 0.0, -along)
					wall_yaw = -PI * 0.5

			var key := ""
			var is_door := side == int(h.door_side) and i == door_index
			if is_door:
				key = "Wall_%s_Door_Flat" % style
			elif rng.randf() < 0.42:
				key = "Wall_%s_Window_%s" % [style, "Wide_Round" if rng.randf() < 0.6 else "Thin_Round"]
			else:
				key = "Wall_%s_Straight" % style

			var world_pos: Vector3 = origin + house_basis * local
			_place(key, world_pos, yaw_house + wall_yaw)
			_add_wall_collider(world_pos, yaw_house + wall_yaw, is_door)

	# Roof matched to the footprint, eaves overlapping the wall head.
	var roof_key := "Roof_RoundTiles_%dx%d" % [int(w), int(d)]
	if not _has_model(roof_key):
		roof_key = "Roof_RoundTiles_%dx%d" % [int(d), int(w)]
	var roof_pos := Vector3(center.x, pad + WALL_HEIGHT - 0.62, center.y)
	_place(roof_key, roof_pos, yaw_house, false)

	# A chimney-ish crate stack + a couple of interior props.
	if rng.randf() < 0.75:
		var crate_local := Vector3(rng.randf_range(-w * 0.5 + 1.4, w * 0.5 - 1.4), 0.0,
			rng.randf_range(-d * 0.5 + 1.4, d * 0.5 - 1.4))
		var crate_pos: Vector3 = origin + house_basis * crate_local
		_place("Prop_Crate", crate_pos, yaw_house + rng.randf_range(-0.4, 0.4))
		_add_box_collider(crate_pos + Vector3(0, 0.53, 0), Vector3(1.06, 1.06, 1.06), yaw_house)

	# Loot spots inside; at least one gun guaranteed per house by the loot manager.
	var gun_spots := rng.randi_range(2, 3)
	for i in gun_spots:
		var p := Vector3(
			center.x + rng.randf_range(-w * 0.5 + 1.3, w * 0.5 - 1.3),
			pad + 0.06,
			center.y + rng.randf_range(-d * 0.5 + 1.3, d * 0.5 - 1.3)
		)
		loot_points.append({"pos": p, "kind": "weapon", "village": true})
	for i in rng.randi_range(2, 3):
		loot_points.append({
			"pos": Vector3(center.x + rng.randf_range(-w * 0.5 + 1.0, w * 0.5 - 1.0), pad + 0.06,
				center.y + rng.randf_range(-d * 0.5 + 1.0, d * 0.5 - 1.0)),
			"kind": "gear", "village": true,
		})

	_stat.houses += 1


func _build_village_extras() -> void:
	for v in village_pads:
		var site: Vector2 = v.center
		var pad: float = v.pad
		var vr: float = v.radius
		var is_farm: bool = v.type == "farm"

		# Plaza loot (open air crates) + cover.
		for i in (rng.randi_range(2, 3) if is_farm else rng.randi_range(3, 6)):
			var ang := rng.randf() * TAU
			var dist := rng.randf_range(4.0, maxf(6.0, vr * 0.3))
			var p := Vector3(site.x + cos(ang) * dist, pad, site.y + sin(ang) * dist)
			if rng.randf() < 0.55:
				_place("Prop_Crate", p, rng.randf_range(0.0, TAU))
				_add_box_collider(p + Vector3(0, 0.53, 0), Vector3(1.06, 1.06, 1.06), 0.0)
				loot_points.append({"pos": p + Vector3(0.0, 0.06, 0.9), "kind": "weapon", "village": true})
			else:
				_place("Prop_Wagon", p, rng.randf_range(0.0, TAU))
				_add_box_collider(p + Vector3(0, 0.7, 0), Vector3(1.7, 1.4, 3.4), 0.0)
				loot_points.append({"pos": p + Vector3(1.4, 0.06, 0.0), "kind": "gear", "village": true})

		# Perimeter fence posts, broken up so they read as an old village edge.
		# Farms get a near-complete paddock fence, towns a broken edge.
		var posts := 28 if is_farm else rng.randi_range(6, 12)
		for i in posts:
			var ang := (TAU * float(i) / float(posts)) if is_farm else rng.randf() * TAU
			if is_farm and rng.randf() < 0.12:
				continue
			var dist := vr - 1.0 if is_farm else rng.randf_range(vr - 6.0, vr - 2.0)
			var p := Vector3(site.x + cos(ang) * dist, pad, site.y + sin(ang) * dist)
			_place("Prop_WoodenFence_Single", p, ang + PI * 0.5 + rng.randf_range(-0.15, 0.15))

		# Vines climbing a couple of house walls.
		for h in houses:
			var hc: Vector2 = h.center
			if hc.distance_to(site) > vr:
				continue
			if rng.randf() < 0.5:
				var side_dir := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
				var p := Vector3(hc.x, h.pad, hc.y) + side_dir * (float(h.w) * 0.5 + 0.25)
				_place("Prop_Vine2", p, rng.randf_range(0.0, TAU))

		# A few shamble walls to give the plaza silhouette some verticality.
		for i in (0 if is_farm else rng.randi_range(1, 3)):
			var ang := rng.randf() * TAU
			var dist := rng.randf_range(vr * 0.4, vr * 0.7)
			var p := Vector3(site.x + cos(ang) * dist, pad, site.y + sin(ang) * dist)
			_place("Wall_UnevenBrick_Straight", p, ang)
			_add_wall_collider(p, ang, false)


func _place(key: String, bottom_center: Vector3, yaw: float, _align := true, pivot := Vector3.INF) -> void:
	var data := _model(key)
	if data.is_empty():
		return
	var aabb: AABB = data.aabb
	var basis := Basis(Vector3.UP, yaw)
	var offset := Vector3(-aabb.get_center().x, -aabb.position.y, -aabb.get_center().z)
	if pivot != Vector3.INF:
		# Use the mesh's own origin, nudged by `pivot`, instead of re-centring it.
		offset = pivot
	var xform := Transform3D(basis, bottom_center + basis * offset)
	if not _batches.has(key):
		_batches[key] = []
	_batches[key].append(xform)
	_stat.pieces += 1


func _add_wall_collider(pos: Vector3, yaw: float, has_door: bool) -> void:
	var basis := Basis(Vector3.UP, yaw)
	if not has_door:
		_colliders.append({
			"xform": Transform3D(basis, pos + Vector3(0, WALL_HEIGHT * 0.5, 0)),
			"size": Vector3(1.98, WALL_HEIGHT, 0.42),
		})
		return
	var side := (2.0 - DOOR_WIDTH) * 0.5
	for sx in [-1.0, 1.0]:
		_colliders.append({
			"xform": Transform3D(basis, pos + basis * Vector3(sx * (DOOR_WIDTH + side) * 0.5, WALL_HEIGHT * 0.5, 0)),
			"size": Vector3(side, WALL_HEIGHT, 0.42),
		})
	var top_h := WALL_HEIGHT - 2.10
	_colliders.append({
		"xform": Transform3D(basis, pos + Vector3(0, WALL_HEIGHT - top_h * 0.5, 0)),
		"size": Vector3(DOOR_WIDTH, top_h, 0.42),
	})


func _add_box_collider(center: Vector3, size: Vector3, yaw: float) -> void:
	_colliders.append({"xform": Transform3D(Basis(Vector3.UP, yaw), center), "size": size})


func _has_model(key: String) -> bool:
	return ResourceLoader.exists(MODEL_PATH % key)


func _model(key: String) -> Dictionary:
	if _cache.has(key):
		return _cache[key]
	var path := MODEL_PATH % key
	if not ResourceLoader.exists(path):
		push_warning("Missing village model: " + path)
		_cache[key] = {}
		return {}
	var packed: PackedScene = load(path)
	var inst := packed.instantiate()
	var mi := _find_mesh(inst)
	if mi == null:
		inst.free()
		_cache[key] = {}
		return {}
	var mesh: Mesh = mi.mesh.duplicate()
	# Double-sided: modular walls/roofs must be visible from inside.
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s)
		if mat is BaseMaterial3D:
			var copy := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
			copy.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh.surface_set_material(s, copy)
	var aabb: AABB = mi.transform * mesh.get_aabb()
	var data := {"mesh": mesh, "aabb": aabb}
	inst.free()
	_cache[key] = data
	return data


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for c in node.get_children():
		var found := _find_mesh(c)
		if found != null:
			return found
	return null


func _commit_batches() -> void:
	for key in _batches:
		var data := _model(key)
		if data.is_empty():
			continue
		var transforms: Array = _batches[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = data.mesh
		mm.instance_count = transforms.size()
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "V_" + key
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# One batch spans the whole island, so no distance cut-off: Godot would
		# measure it from the batch centre and hide whole villages at random.
		mmi.visibility_range_end = 0.0
		add_child(mmi)


func _commit_colliders() -> void:
	var body := StaticBody3D.new()
	body.name = "VillageCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for c in _colliders:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = c.size
		shape.shape = box
		shape.transform = c.xform
		body.add_child(shape)


# ------------------------------------------------------------ lookout towers --
## Two-storey stone towers on high ground: interior stair, windows on every
## side of the upper floor, the best loot up top. Places worth fighting over.
func _plan_towers() -> void:
	var cands: Array = []
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = rng.seed + 31
	for i in 500:
		var a := rng2.randf() * TAU
		var r := sqrt(rng2.randf()) * 360.0
		var c := Vector2(cos(a), sin(a)) * r
		var h := terrain.height_at(c.x, c.y)
		if h < 8.0 or terrain.slope_at(c.x, c.y) > 0.32 or terrain.roughness(c.x, c.y, 5.0) > 3.5:
			continue
		cands.append([h + rng2.randf() * 4.0, c])
	cands.sort_custom(func(a, b): return a[0] > b[0])
	for e in cands:
		if towers.size() >= 5:
			break
		var c: Vector2 = e[1]
		if _too_close(c, 75.0, 150.0):
			continue
		var pad := terrain.flatten_circle(c.x, c.y, 5.5, 9.0)
		towers.append({"center": c, "pad": pad})
		poi_pads.append({"center": c, "radius": 9.0, "type": "tower"})
	for t in towers:
		_build_tower(t)


func _too_close(c: Vector2, from_villages: float, from_pois: float) -> bool:
	for v in village_pads:
		if c.distance_to(v.center) < from_villages:
			return true
	for p in poi_pads:
		if c.distance_to(p.center) < from_pois:
			return true
	return false


func _build_tower(t: Dictionary) -> void:
	var c: Vector2 = t.center
	var pad: float = t.pad
	var yaw := float(rng.randi_range(0, 3)) * PI * 0.5
	var b := Basis(Vector3.UP, yaw)
	var origin := Vector3(c.x, pad, c.y)
	var half := 3.0
	t["yaw"] = yaw
	var door_side := rng.randi_range(0, 3)
	# Never put the door behind the stair (side 1 is +x, where the stair runs).
	if door_side == 1:
		door_side = 3
	for level in 2:
		var y0 := WALL_HEIGHT * float(level)
		for side in 4:
			for i in 3:
				var along := -2.0 + float(i) * 2.0
				var local := Vector3.ZERO
				var wall_yaw := 0.0
				match side:
					0:
						local = Vector3(along, y0, half)
						wall_yaw = 0.0
					1:
						local = Vector3(half, y0, along)
						wall_yaw = PI * 0.5
					2:
						local = Vector3(-along, y0, -half)
						wall_yaw = PI
					3:
						local = Vector3(-half, y0, -along)
						wall_yaw = -PI * 0.5
				var pos: Vector3 = origin + b * local
				var key := "Wall_UnevenBrick_Straight"
				var hole := ""
				if level == 0 and side == door_side and i == 1:
					key = "Wall_UnevenBrick_Door_Round"
					hole = "door"
				elif level == 1 and i == 1:
					key = "Wall_UnevenBrick_Window_Wide_Round"
					hole = "window"
				elif level == 0 and i != 1 and rng.randf() < 0.3:
					key = "Wall_UnevenBrick_Window_Thin_Round"
				_place(key, pos, yaw + wall_yaw)
				if hole == "window":
					_add_window_collider(pos, yaw + wall_yaw)
				else:
					_add_wall_collider(pos, yaw + wall_yaw, hole == "door")
	# Floors: brick downstairs, timber upstairs with a hole for the stair.
	for fx in [-2.0, 0.0, 2.0]:
		for fz in [-2.0, 0.0, 2.0]:
			_place("Floor_Brick", origin + b * Vector3(fx, 0.012, fz), yaw)
			if not (fx == 2.0 and fz > -1.0):
				_place("Floor_WoodDark", origin + b * Vector3(fx, WALL_HEIGHT + 0.012, fz), yaw)
	_add_box_collider(origin + b * Vector3(-1.0, WALL_HEIGHT - 0.1, 0.0), Vector3(4.0, 0.2, 6.0), yaw)
	_add_box_collider(origin + b * Vector3(2.0, WALL_HEIGHT - 0.1, -2.0), Vector3(2.0, 0.2, 2.0), yaw)
	# Stair along the +x wall, climbing toward -z.
	_place("Stair_Interior_Simple", origin + b * Vector3(1.9, 0.0, 2.3), yaw, false, Vector3.ZERO)
	var run := 4.58
	var rise := WALL_HEIGHT
	var ang := atan2(rise, run)
	var ramp_center := origin + b * Vector3(1.9, rise * 0.5 - 0.12, 0.01)
	_colliders.append({
		"xform": Transform3D(b * Basis(Vector3.RIGHT, ang), ramp_center),
		"size": Vector3(1.6, 0.2, sqrt(run * run + rise * rise) + 0.2),
	})
	# Roof with eaves over the upper walls.
	_place("Roof_RoundTiles_6x6", origin + Vector3(0, WALL_HEIGHT * 2.0 - 0.62, 0), yaw)
	# Loot: the good stuff is upstairs.
	for i in 3:
		var lp := origin + b * Vector3(rng.randf_range(-2.2, 0.6), WALL_HEIGHT + 0.08, rng.randf_range(-2.2, 2.2))
		loot_points.append({"pos": lp, "kind": "weapon" if i == 0 else "gear", "village": true, "tier": "hi"})
	loot_points.append({"pos": origin + b * Vector3(-1.5, 0.08, rng.randf_range(-1.5, 1.5)), "kind": "gear", "village": true})
	_stat.towers += 1


func _add_window_collider(pos: Vector3, yaw: float) -> void:
	# Solid below the sill and above the lintel, open in between to shoot through.
	var basis := Basis(Vector3.UP, yaw)
	var sill := 1.05
	var top := 2.35
	_colliders.append({"xform": Transform3D(basis, pos + Vector3(0, sill * 0.5, 0)), "size": Vector3(1.98, sill, 0.42)})
	_colliders.append({"xform": Transform3D(basis, pos + Vector3(0, (top + WALL_HEIGHT) * 0.5, 0)), "size": Vector3(1.98, WALL_HEIGHT - top, 0.42)})
	for sx in [-1.0, 1.0]:
		_colliders.append({"xform": Transform3D(basis, pos + basis * Vector3(sx * 0.85, (sill + top) * 0.5, 0)), "size": Vector3(0.28, top - sill, 0.42)})


# ------------------------------------------------------------------- ruins --
## Broken walls, arches and crates out in the open fields: cover between
## towns, with a little loot to make the detour worth it.
func _plan_ruins() -> void:
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = rng.seed + 57
	var placed := 0
	for i in 400:
		if placed >= 14:
			break
		var a := rng2.randf() * TAU
		var r := sqrt(rng2.randf()) * 380.0
		var c := Vector2(cos(a), sin(a)) * r
		if terrain.height_at(c.x, c.y) < 3.0 or terrain.slope_at(c.x, c.y) > 0.22:
			continue
		if terrain.roughness(c.x, c.y, 8.0) > 3.0:
			continue
		if _too_close(c, 60.0, 70.0):
			continue
		var pad := terrain.flatten_circle(c.x, c.y, 8.0, 10.0)
		poi_pads.append({"center": c, "radius": 11.0, "type": "ruin"})
		_build_ruin(c, pad)
		placed += 1


func _build_ruin(c: Vector2, pad: float) -> void:
	var yaw := rng.randf() * TAU
	var b := Basis(Vector3.UP, yaw)
	var origin := Vector3(c.x, pad, c.y)
	var w := 4 if rng.randf() < 0.5 else 3
	var d := 3
	# Perimeter of a ruined building: some modules standing, some gone.
	for side in 4:
		var cells := w if side % 2 == 0 else d
		for i in cells:
			if rng.randf() < 0.4:
				continue
			var along := -float(cells - 1) + float(i) * 2.0
			var local := Vector3.ZERO
			var wall_yaw := 0.0
			match side:
				0:
					local = Vector3(along, 0, float(d))
				1:
					local = Vector3(float(w), 0, along)
					wall_yaw = PI * 0.5
				2:
					local = Vector3(-along, 0, -float(d))
					wall_yaw = PI
				3:
					local = Vector3(-float(w), 0, -along)
					wall_yaw = -PI * 0.5
			var pos: Vector3 = origin + b * local
			var roll := rng.randf()
			if roll < 0.2:
				_place("Wall_Arch", pos, yaw + wall_yaw)
				_add_arch_collider(pos, yaw + wall_yaw)
			elif roll < 0.45:
				_place("Wall_UnevenBrick_Window_Wide_Round", pos, yaw + wall_yaw)
				_add_window_collider(pos, yaw + wall_yaw)
			else:
				_place("Wall_UnevenBrick_Straight", pos, yaw + wall_yaw)
				_add_wall_collider(pos, yaw + wall_yaw, false)
	# Rubble and crates for low cover.
	for i in rng.randi_range(2, 4):
		var p := origin + b * Vector3(rng.randf_range(-w, w), 0, rng.randf_range(-d - 3.0, d + 3.0))
		if rng.randf() < 0.6:
			_place("Prop_Crate", p, rng.randf() * TAU)
			_add_box_collider(p + Vector3(0, 0.53, 0), Vector3(1.06, 1.06, 1.06), 0.0)
		else:
			_place("Prop_Brick%d" % rng.randi_range(1, 4), p, rng.randf() * TAU)
	for i in rng.randi_range(2, 4):
		var lp := origin + b * Vector3(rng.randf_range(-w + 1.0, w - 1.0), 0.08, rng.randf_range(-d + 1.0, d - 1.0))
		loot_points.append({"pos": lp, "kind": "weapon" if i == 0 else "gear", "village": false})
	_stat.ruins += 1


func _add_arch_collider(pos: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	for sx in [-1.0, 1.0]:
		_colliders.append({"xform": Transform3D(basis, pos + basis * Vector3(sx * 0.82, 1.5, 0.03)), "size": Vector3(0.36, 3.0, 0.3)})
	_colliders.append({"xform": Transform3D(basis, pos + basis * Vector3(0, 2.75, 0.03)), "size": Vector3(2.0, 0.5, 0.3)})
