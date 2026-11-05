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
	"OLDHAVEN", "DUNMORE", "REDWATER", "FENWICK", "GREYMARSH", "WILLOWDEEP", "CROWHOLLOW",
	"LARKSPUR", "MILLBROOK", "WESTERHOLT", "BRAMBLEGATE", "SALTCOMBE", "ELMSTEAD", "COLDHARBOUR"]
## Batches are split into cells so distant settlements can be culled.
const BATCH_CELL := 250.0

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
var landmarks: Landmarks
## City market squares: {center, pad, axis, size}.
var city_squares: Array = []

var _cache: Dictionary = {}
var _batches: Dictionary = {}
var _colliders: Array[Dictionary] = []
var _stat := {"houses": 0, "pieces": 0, "village_count": 0, "towers": 0, "ruins": 0}


func build(p_terrain: Terrain, p_seed: int) -> void:
	terrain = p_terrain
	rng.seed = p_seed + 4242

	_plan_villages()
	_clear_roads_of_houses()
	for h in houses:
		_build_house(h)
	_build_village_extras()
	_plan_towers()
	_plan_ruins()
	landmarks = Landmarks.new()
	landmarks.name = "Landmarks"
	add_child(landmarks)
	landmarks.build(terrain, self, p_seed)
	_commit_batches()
	_commit_colliders()
	print("[villages] %d villages, %d houses, %d towers, %d ruins, %d pieces, %d loot points, %d colliders" % [
		_stat.village_count, _stat.houses, _stat.towers, _stat.ruins, _stat.pieces, loot_points.size(), _colliders.size()
	])


func _plan_villages() -> void:
	# Settlements are placed per seed: street towns, villages and farmsteads
	# spread over flat-enough land, clear of the landmarks and the river.
	var specs: Array = ["city", "city"]
	for i in 5:
		specs.append("town")
	for i in 9:
		specs.append("village")
	for i in 14:
		specs.append("farm")
	var size := {"city": 96.0, "town": 58.0, "village": 32.0, "farm": 15.0}
	var spacing := {"city": 520.0, "town": 300.0, "village": 190.0, "farm": 110.0}
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = rng.seed + 11
	var forced: Array = []
	# Highfalls: a hamlet on the plateau top, by the lake.
	for off in [Vector2(-60, -55), Vector2(-75, 10), Vector2(10, -80), Vector2(-40, 70), Vector2(70, -40)]:
		var c: Vector2 = Terrain.PLATEAU_C + off
		if terrain.height_at(c.x, c.y) > Terrain.PLATEAU_H - 3.0 and c.distance_to(Terrain.LAKE_C) > Terrain.LAKE_R + 50.0 \
				and terrain.roughness(c.x, c.y, 22.0) < 6.0:
			forced.append(["village", c, "HIGHFALLS"])
			break
	# The east isle gets a village of its own.
	for i in 12:
		var a := TAU * float(i) / 12.0
		var c := Terrain.EAST_C + Vector2(cos(a), sin(a)) * 130.0
		if terrain.height_at(c.x, c.y) > 5.0 and not terrain.is_reserved(c, 40.0) and terrain.roughness(c.x, c.y, 22.0) < 9.0:
			forced.append(["village", c, "EASTMARCH"])
			break
	var name_i := 0
	for e in forced + specs:
		var type: String = e if e is String else e[0]
		var radius: float = size[type]
		var site := Vector2.INF
		var town_name := ""
		if e is Array:
			site = e[1]
			town_name = e[2]
		else:
			for attempt in 500:
				var c := terrain.random_land_point(rng2, 4.0, 0.3)
				if terrain.is_reserved(c, radius + 10.0):
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
		if type == "city" and town_name == "":
			town_name = ["KINGSHAVEN", "VALEMOOR"][_stat.get("cities", 0) % 2]
			_stat["cities"] = int(_stat.get("cities", 0)) + 1
		elif type != "farm" and town_name == "":
			town_name = TOWN_NAMES[name_i % TOWN_NAMES.size()]
			name_i += 1
		village_pads.append({"center": site, "pad": pad, "name": town_name, "radius": radius,
			"type": type, "spacing": spacing[type], "axis": axis})
		_stat.village_count += 1
		match type:
			"city":
				_plan_city(site, pad, radius, axis)
			"town":
				_plan_street(site, pad, radius, axis)
			"village":
				_plan_ring(site, pad, rng.randi_range(5, 8), 9.0, radius - 4.0)
			"farm":
				_plan_ring(site, pad, rng.randi_range(1, 2), 3.0, radius - 3.0)
	# The settlement on Kestrel Bay takes the bay's name.
	var best := -1
	var best_d := 420.0
	for i in village_pads.size():
		var d: float = village_pads[i].center.distance_to(Terrain.BAY_C)
		if village_pads[i].type != "farm" and d < best_d:
			best_d = d
			best = i
	if best >= 0:
		village_pads[best].name = "KESTREL BAY"
	_plan_roads()


## A grid city: an avenue and parallel streets crossed by side streets,
## lined with two-storey houses, around a market square.
func _plan_city(site: Vector2, pad: float, radius: float, axis: float) -> void:
	var dir := Vector2(cos(axis), sin(axis))
	var perp := Vector2(-dir.y, dir.x)
	var plaza := 16.0
	# The bell tower's plot on a corner of the square, kept clear of houses.
	var tower_c := site + dir * 15.0 + perp * 15.0
	_blockers.append([tower_c, 6.5])
	# Streets running along `dir` at three offsets, cross streets along `perp`.
	for off in [-34.0, 0.0, 34.0]:
		var half := sqrt(maxf(0.0, radius * radius - off * off)) - 6.0
		var c0: Vector2 = site + perp * float(off)
		roads.append({"a": c0 - dir * (half + 6.0), "b": c0 + dir * (half + 6.0), "w": 4.0 if off == 0.0 else 3.2})
		_street_houses(site, c0, dir, perp, half, pad, radius, -axis, plaza)
	for off in [-48.0, 0.0, 48.0]:
		var half := sqrt(maxf(0.0, radius * radius - off * off)) - 6.0
		var c1: Vector2 = site + dir * float(off)
		roads.append({"a": c1 - perp * (half + 6.0), "b": c1 + perp * (half + 6.0), "w": 3.4})
	city_squares.append({"center": site, "pad": pad, "axis": axis, "size": plaza, "tower": tower_c})


## Houses along one street, both sides, doors to the street.
func _street_houses(site: Vector2, line_c: Vector2, dir: Vector2, perp: Vector2, half: float, pad: float, radius: float, yaw: float, plaza: float) -> void:
	var k := -half + 6.0
	while k < half - 5.0:
		var at: Vector2 = line_c + dir * k
		if at.distance_to(site) < plaza + 6.0:
			k += 10.0
			continue
		for side in [-1.0, 1.0]:
			var lot: Vector2i = LOTS[rng.randi() % LOTS.size()]
			var w := float(lot.x)
			var d := float(lot.y)
			if w > 8.0:
				var tmp := w
				w = d
				d = tmp
			var c: Vector2 = at + perp * float(side) * (6.4 + d * 0.5)
			if c.distance_to(site) + maxf(w, d) * 0.5 > radius - 2.0:
				continue
			# Leave the cross streets (dir * -48, 0, 48; 3.4 m half-width) open.
			var on_cross := false
			for cross in [-48.0, 0.0, 48.0]:
				if absf((c - site).dot(dir) - float(cross)) < 3.4 + 1.0 + w * 0.5:
					on_cross = true
			if on_cross:
				continue
			_add_house(c, w, d, yaw, pad, at, 2 if rng.randf() < 0.8 else 1)
		k += 10.0 + rng.randf_range(0.0, 2.0)


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
			_add_house(c, w, d, -axis, pad, site + dir * along, 2 if rng.randf() < 0.6 else 1)
	# Cross street through the plaza, lined with houses in the bigger towns.
	roads.append({"a": site - perp * (radius * 0.75), "b": site + perp * (radius * 0.75), "w": 3.0})
	var m := int((radius * 0.75 - 8.0) / 12.0)
	for k in range(-m, m + 1):
		var along := float(k) * 12.0
		if absf(along) < 12.0:
			continue
		for side in [-1.0, 1.0]:
			if rng.randf() > 0.8:
				continue
			var lot: Vector2i = LOTS[rng.randi() % LOTS.size()]
			var w := float(mini(lot.x, lot.y))
			var d := float(maxi(lot.x, lot.y))
			var c: Vector2 = site + perp * along + dir * side * (6.0 + d * 0.5)
			if c.distance_to(site) + maxf(w, d) * 0.5 > radius - 1.0:
				continue
			_add_house(c, w, d, -axis + PI * 0.5, pad, site + perp * along, 2 if rng.randf() < 0.5 else 1)


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
		if _add_house(c, w, d, float(rng.randi_range(0, 3)) * PI * 0.5, pad, site, 2 if rng.randf() < 0.22 else 1):
			placed += 1


## Is this spot inside (or within `margin` of) any house footprint?
func _inside_house(p: Vector2, margin: float) -> bool:
	return blocks_house(p, margin)


## Drop houses that a road runs through (roads between settlements are laid
## after the houses, centre to centre).
func _clear_roads_of_houses() -> void:
	var keep: Array[Dictionary] = []
	var dropped := 0
	for h in houses:
		var hit := false
		for r in roads:
			if _segment_hits_rect(r.a, r.b, float(r.w) + 0.6, h.center, float(h.w), float(h.d), float(h.yaw)):
				hit = true
				break
		if hit:
			dropped += 1
		else:
			keep.append(h)
	houses = keep
	print("[villages] %d houses cleared off roads" % dropped)


func _segment_hits_rect(a: Vector2, b: Vector2, half_w: float, c: Vector2, w: float, d: float, yaw: float) -> bool:
	# Into the house's frame, then test the segment against the grown box.
	var la := (a - c).rotated(yaw)
	var lb := (b - c).rotated(yaw)
	var hx := w * 0.5 + half_w
	var hz := d * 0.5 + half_w
	var t0 := 0.0
	var t1 := 1.0
	var dv := lb - la
	for axis in 2:
		var p0 := la[axis]
		var dd := dv[axis]
		var lim := hx if axis == 0 else hz
		if absf(dd) < 1e-6:
			if absf(p0) > lim:
				return false
			continue
		var ta := (-lim - p0) / dd
		var tb := (lim - p0) / dd
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 > t1:
			return false
	return true


func _on_road(p: Vector2, margin: float) -> bool:
	for r in roads:
		var a: Vector2 = r.a
		var b: Vector2 = r.b
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		if p.distance_to(a + ab * t) < float(r.w) + margin:
			return true
	return false


## The house whose footprint (grown by `margin`) contains `p`, or {}.
## Uses a coarse grid so bots can ask every few frames.
var _house_grid: Dictionary = {}


func house_at(p: Vector2, margin := 0.0) -> Dictionary:
	if _house_grid.is_empty():
		for i in houses.size():
			var h: Dictionary = houses[i]
			var c: Vector2 = h.center
			var r := Vector2(float(h.w), float(h.d)).length() * 0.5 + 2.0
			for gx in range(int(floor((c.x - r) / 16.0)), int(floor((c.x + r) / 16.0)) + 1):
				for gz in range(int(floor((c.y - r) / 16.0)), int(floor((c.y + r) / 16.0)) + 1):
					var k := Vector2i(gx, gz)
					if not _house_grid.has(k):
						_house_grid[k] = []
					_house_grid[k].append(i)
		if _house_grid.is_empty():
			_house_grid[Vector2i(1 << 20, 0)] = []
	var cell: Array = _house_grid.get(Vector2i(int(floor(p.x / 16.0)), int(floor(p.y / 16.0))), [])
	for i in cell:
		var h: Dictionary = houses[int(i)]
		var local: Vector2 = (p - (h.center as Vector2)).rotated(float(h.yaw))
		if absf(local.x) < float(h.w) * 0.5 + margin and absf(local.y) < float(h.d) * 0.5 + margin:
			return h
	return {}


## World-space walking points for a house: "out" in front of the door, "in"
## just inside it, and for two-storey houses "up": stair side, stair foot,
## stair top and the landing beside it (the order you climb them).
func house_nav(h: Dictionary) -> Dictionary:
	if h.has("_nav"):
		return h["_nav"]
	var w := float(h.w)
	var d := float(h.d)
	var side := int(h.door_side)
	var b := Basis(Vector3.UP, float(h.yaw))
	var o := Vector3((h.center as Vector2).x, float(h.pad), (h.center as Vector2).y)
	var cells := int(w * 0.5) if side % 2 == 0 else int(d * 0.5)
	var along := -((cells - 1) * 0.5) * 2.0 + float(cells / 2) * 2.0
	var door: Vector3 = [Vector3(along, 0, d * 0.5), Vector3(w * 0.5, 0, along), Vector3(-along, 0, -d * 0.5), Vector3(-w * 0.5, 0, -along)][side]
	var nrm: Vector3 = [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0)][side]
	var nav := {"out": o + b * (door + nrm * 1.2), "in": o + b * (door - nrm * 1.3), "up": [], "floor_y": o.y + WALL_HEIGHT,
		"stair": [w * 0.5 - 1.1, stair_foot_z(d), stair_foot_z(d) - 4.58]}
	if int(h.get("built_levels", 1)) > 1:
		var foot := stair_foot_z(d)
		var sx := w * 0.5 - 1.1
		var top := foot - 4.58
		nav["up"] = [
			o + b * Vector3(sx - 1.0, 0, foot + 0.45),
			o + b * Vector3(sx, 0, foot + 0.45),
			o + b * Vector3(sx, WALL_HEIGHT - 0.3, top + 0.4),
			o + b * Vector3(sx - 1.6, WALL_HEIGHT, top + 0.3),
		]
	h["_nav"] = nav
	return nav


## True if something of radius `margin` at `p` would be in a house or in
## front of its door.
func blocks_house(p: Vector2, margin: float) -> bool:
	for h in houses:
		var local: Vector2 = (p - (h.center as Vector2)).rotated(float(h.yaw))
		if absf(local.x) < float(h.w) * 0.5 + margin and absf(local.y) < float(h.d) * 0.5 + margin:
			return true
		var ap: Array = h.apron
		var al: Vector2 = (p - (ap[0] as Vector2)).rotated(float(h.yaw))
		if absf(al.x) < float(ap[1]) * 0.5 + margin and absf(al.y) < float(ap[2]) * 0.5 + margin:
			return true
	return false


## Plots kept clear of houses: [Vector2 centre, radius].
var _blockers: Array = []


func _add_house(c: Vector2, w: float, d: float, yaw_house: float, pad: float, face_to: Vector2, levels := 1) -> bool:
	var radius := maxf(w, d) * 0.5
	var diag := Vector2(w, d).length() * 0.5
	for bl in _blockers:
		if c.distance_to(bl[0]) < diag + float(bl[1]):
			return false
	var door_side := _door_for(face_to - c, yaw_house)
	var apron := _door_apron(c, w, d, yaw_house, door_side)
	for h in houses:
		# Real footprints (rotated rectangles), with an alley wide enough to walk.
		if _rects_overlap(c, w, d, yaw_house, h.center, float(h.w), float(h.d), float(h.yaw), 1.8):
			return false
		# Nobody builds a wall right in front of somebody else's door.
		var ha: Array = h.apron
		if _rects_overlap(c, w, d, yaw_house, ha[0], ha[1], ha[2], float(h.yaw), 0.2):
			return false
		if _rects_overlap(apron[0], apron[1], apron[2], yaw_house, h.center, float(h.w), float(h.d), float(h.yaw), 0.2):
			return false
	houses.append({
		"center": c, "w": w, "d": d, "yaw": yaw_house, "pad": pad,
		"radius": radius, "door_side": door_side, "apron": apron,
		"style": "Plaster" if rng.randf() < 0.72 else "UnevenBrick",
		"levels": levels,
	})
	return true


## The patch of ground in front of a door: [world centre, size x, size z] in house axes.
func _door_apron(c: Vector2, w: float, d: float, yaw_house: float, side: int) -> Array:
	var cells := int(w * 0.5) if side % 2 == 0 else int(d * 0.5)
	var along := -((cells - 1) * 0.5) * 2.0 + float(cells / 2) * 2.0
	var depth := 3.4
	var local := Vector2.ZERO
	var size := Vector2(2.6, depth)
	match side:
		0:
			local = Vector2(along, d * 0.5 + depth * 0.5)
		1:
			local = Vector2(w * 0.5 + depth * 0.5, along)
			size = Vector2(depth, 2.6)
		2:
			local = Vector2(-along, -d * 0.5 - depth * 0.5)
		_:
			local = Vector2(-w * 0.5 - depth * 0.5, -along)
			size = Vector2(depth, 2.6)
	return [c + local.rotated(-yaw_house), size.x, size.y]


## Separating-axis test for two house footprints grown by `margin`.
func _rects_overlap(c1: Vector2, w1: float, d1: float, yaw1: float, c2: Vector2, w2: float, d2: float, yaw2: float, margin: float) -> bool:
	var axes := [Vector2(1, 0).rotated(-yaw1), Vector2(0, 1).rotated(-yaw1), Vector2(1, 0).rotated(-yaw2), Vector2(0, 1).rotated(-yaw2)]
	var delta := c2 - c1
	for n in axes:
		var e1 := w1 * 0.5 * absf((axes[0] as Vector2).dot(n)) + d1 * 0.5 * absf((axes[1] as Vector2).dot(n))
		var e2 := w2 * 0.5 * absf((axes[2] as Vector2).dot(n)) + d2 * 0.5 * absf((axes[3] as Vector2).dot(n))
		if absf(delta.dot(n)) >= e1 + e2 + margin:
			return false
	return true


## Dirt roads between neighbouring settlements (each links to its nearest
## two). Roads that would cross the river detour over a ford or Kingsbridge.
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
			if done.has(key) or float(e[0]) > 460.0:
				continue
			var b: Vector2 = village_pads[j].center
			if _island_of(a) != _island_of(b):
				continue
			done[key] = true
			_road_between(a, b)
	# Skyreach Bridge joins the islands.
	var ta := _nearest_pad(terrain.bridge_a, 0)
	var tb := _nearest_pad(terrain.bridge_b, 1)
	if ta != Vector2.INF:
		_road_between(ta, terrain.bridge_a)
	if tb != Vector2.INF:
		_road_between(terrain.bridge_b, tb)
	roads.append({"a": terrain.bridge_a, "b": terrain.bridge_b, "w": 3.0, "bridge": true})
	# A track up to the castle gate and to the trail heads of Highfalls.
	for target in [terrain.castle_c] + terrain.trails:
		var t := _nearest_pad(target, 0)
		if t != Vector2.INF and t.distance_to(target) < 520.0:
			_road_between(t, target)


func _island_of(p: Vector2) -> int:
	return 1 if p.distance_to(Terrain.EAST_C) < p.distance_to(Terrain.MAIN_C) and p.x > 560.0 else 0


func _road_anchor(c: Vector2, toward: Vector2) -> Vector2:
	for v in village_pads:
		if (v.center as Vector2).distance_to(c) > 0.5:
			continue
		var r := float(v.radius)
		var dir := Vector2(cos(float(v.axis)), sin(float(v.axis)))
		var perp := Vector2(-dir.y, dir.x)
		var ends: Array = []
		match String(v.type):
			"town":
				ends = [c + dir * (r + 6.0), c - dir * (r + 6.0)]
			"city":
				ends = [c + dir * r, c - dir * r, c + perp * r, c - perp * r]
			_:
				return c + (toward - c).normalized() * (r + 2.0)
		var best: Vector2 = ends[0]
		for e in ends:
			if (e as Vector2).distance_to(toward) < best.distance_to(toward):
				best = e
		return best
	return c


func _nearest_pad(p: Vector2, island: int) -> Vector2:
	var best := Vector2.INF
	var bd := 1e9
	for v in village_pads:
		var c: Vector2 = v.center
		if _island_of(c) != island:
			continue
		var d := c.distance_to(p)
		if d < bd and not _crosses_river(c, p):
			bd = d
			best = c
	return best


func _crosses_river(a: Vector2, b: Vector2) -> bool:
	var n := int(a.distance_to(b) / 8.0) + 1
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		var q := terrain.river_query(p)
		if q.x < terrain.river_profile(q.y).x + 1.0:
			return true
	return false


## A gently bent road, routed over a river crossing when it has to be.
func _road_between(a0: Vector2, b0: Vector2) -> void:
	# Join settlements at the end of their own streets, not through the houses.
	var a := _road_anchor(a0, b0)
	var b := _road_anchor(b0, a0)
	if not _crosses_river(a, b):
		_bent_road(a, b)
		return
	var best := []
	var best_len := 1e9
	var crossings: Array = []
	for f in terrain.fords:
		crossings.append([f, terrain.river_across(f), 22.0, false])
	var gq := terrain.river_query(terrain.gorge_bridge)
	var gp := terrain.river_profile(gq.y)
	crossings.append([terrain.gorge_bridge, terrain.gorge_bridge_dir, gp.x + gp.y + 8.0, true])
	for c in crossings:
		var p: Vector2 = c[0]
		var d: Vector2 = c[1]
		var r: float = c[2]
		var e0 := p - d * r
		var e1 := p + d * r
		if a.distance_to(e1) < a.distance_to(e0):
			var t := e0
			e0 = e1
			e1 = t
		var len := a.distance_to(e0) + e0.distance_to(e1) + e1.distance_to(b)
		if len < best_len:
			best_len = len
			best = [e0, e1, c[3]]
	if best.is_empty() or best_len > a.distance_to(b) * 1.9:
		return
	_bent_road(a, best[0])
	roads.append({"a": best[0], "b": best[1], "w": 2.6, "bridge": best[2]})
	_bent_road(best[1], b)


func _bent_road(a: Vector2, b: Vector2) -> void:
	# A gentle bend through a midpoint so roads do not look ruled.
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
	var local := to_center.rotated(yaw_house)
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

	# Two storeys where the footprint fits a stair along +x (not behind the door).
	var levels := int(h.get("levels", 1))
	if w < 6.0 or d < 6.0 or int(h.door_side) == 1:
		levels = 1
	var shutters := style == "Plaster" and rng.randf() < 0.6
	for level in levels:
		var y0 := WALL_HEIGHT * float(level)
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
						local = Vector3(along, y0, d * 0.5)
						wall_yaw = 0.0
					1:
						local = Vector3(w * 0.5, y0, along)
						wall_yaw = PI * 0.5
					2:
						local = Vector3(-along, y0, -d * 0.5)
						wall_yaw = PI
					3:
						local = Vector3(-w * 0.5, y0, -along)
						wall_yaw = -PI * 0.5
				var key := ""
				var is_door := level == 0 and side == int(h.door_side) and i == door_index
				var is_window := false
				# Upper floors get more windows: that is where you fight from.
				if is_door:
					key = "Wall_%s_Door_Flat" % style
				elif rng.randf() < (0.62 if level > 0 else 0.42):
					is_window = true
					if shutters:
						key = "Wall_Plaster_Window_Wide_Flat"
					else:
						key = "Wall_%s_Window_%s" % [style, "Wide_Round" if rng.randf() < 0.6 else "Thin_Round"]
				else:
					key = "Wall_%s_Straight" % style
				var world_pos: Vector3 = origin + house_basis * local
				_place(key, world_pos, yaw_house + wall_yaw)
				_add_wall_for(key, world_pos, yaw_house + wall_yaw)
				if is_window and shutters:
					_place("WindowShutters_Wide_Flat_Open", world_pos, yaw_house + wall_yaw, false, Vector3(0, 0, 0.11))
				if is_door:
					# The door itself, swung open into the room.
					var hinge: Vector3 = world_pos + Basis(Vector3.UP, yaw_house + wall_yaw) * Vector3(-0.56, 0.0, 0.0)
					_place("Door_1_Flat", hinge, yaw_house + wall_yaw + deg_to_rad(rng.randf_range(80.0, 110.0)), false, Vector3.ZERO)

	h["built_levels"] = levels
	if levels > 1:
		_upper_floor(origin, house_basis, w, d)

	# Roof matched to the footprint, eaves overlapping the wall head.
	# The kit's roofs run their ridge along z; a house that is wider than deep
	# gets the roof turned a quarter so the eaves still sit on the long walls.
	var roof_key := "Roof_RoundTiles_%dx%d" % [int(w), int(d)]
	var roof_yaw := yaw_house
	var span := w
	if not _has_model(roof_key):
		roof_key = "Roof_RoundTiles_%dx%d" % [int(d), int(w)]
		roof_yaw += PI * 0.5
		span = d
	var roof_base := pad + WALL_HEIGHT * float(levels) - 0.62
	var roof_pos := Vector3(center.x, roof_base, center.y)
	_place(roof_key, roof_pos, roof_yaw, false)
	_add_gables(Vector3(center.x, pad + WALL_HEIGHT * float(levels), center.y), roof_yaw, span, d if roof_yaw == yaw_house else w, style)
	# Chimney through the roof slope.
	if rng.randf() < 0.7:
		var cx := (w * 0.5 - 1.5) * (1.0 if rng.randf() < 0.5 else -1.0)
		var cz := (d * 0.5 - 1.2) * (1.0 if rng.randf() < 0.5 else -1.0)
		_place("Prop_Chimney" if rng.randf() < 0.5 else "Prop_Chimney2", origin + house_basis * Vector3(cx, roof_base - pad + 0.9, cz), yaw_house, false, Vector3.ZERO)
	if levels > 1:
		# The good stuff is upstairs.
		for i in rng.randi_range(2, 3):
			var lp := origin + house_basis * Vector3(rng.randf_range(-w * 0.5 + 1.2, w * 0.5 - 2.8), WALL_HEIGHT + 0.08, rng.randf_range(-d * 0.5 + 1.2, d * 0.5 - 1.2))
			loot_points.append({"pos": lp, "kind": "weapon" if i == 0 else "gear", "village": true, "tier": "hi" if rng.randf() < 0.25 else ""})

	# A chimney-ish crate stack + a couple of interior props.
	if rng.randf() < 0.75:
		# Crates sit in a corner: never in the doorway, the walkway or on the
		# stairs.
		var door_dir := [Vector2(0, 1), Vector2(1, 0), Vector2(0, -1), Vector2(-1, 0)][int(h.door_side)] as Vector2
		var best := Vector2.INF
		var best_d := -1.0
		for cx in [-1.0, 1.0]:
			for cz in [-1.0, 1.0]:
				if levels > 1 and cx > 0.0:
					continue
				var corner := Vector2(cx * (w * 0.5 - 0.85), cz * (d * 0.5 - 0.85))
				var dd := corner.distance_to(door_dir * Vector2(w * 0.5, d * 0.5))
				if dd > best_d:
					best_d = dd
					best = corner
		if best != Vector2.INF and minf(w, d) >= 4.0:
			var crate_local := Vector3(best.x, 0.0, best.y)
			var crate_pos: Vector3 = origin + house_basis * crate_local
			_place("Prop_Crate", crate_pos, yaw_house + rng.randf_range(-0.3, 0.3))
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


## Market square: fountain, stalls with awnings, and a bell tower.
func _build_square(sq: Dictionary) -> void:
	var c: Vector2 = sq.center
	var pad: float = sq.pad
	var axis: float = sq.axis
	var b := Basis(Vector3.UP, -axis)
	var o := Vector3(c.x, pad, c.y)
	# Fountain: a round stone basin, a pedestal and a raised bowl on top.
	_stone_ring(o, 3.0, 12, 0.7, 0.45, -axis)
	for k in 3:
		_proc_box(Transform3D(Basis(Vector3.UP, -axis + float(k) * PI / 6.0).scaled_local(Vector3(4.3, 0.1, 4.3)), o + Vector3(0, 0.5, 0)), "water")
	_proc_box(Transform3D(b.scaled_local(Vector3(0.9, 1.7, 0.9)), o + Vector3(0, 0.85, 0)), "stone")
	_stone_ring(o + Vector3(0, 1.55, 0), 0.95, 8, 0.35, 0.25, -axis)
	_proc_box(Transform3D(b.scaled_local(Vector3(1.5, 0.08, 1.5)), o + Vector3(0, 1.82, 0)), "water")
	_proc_box(Transform3D(b.scaled_local(Vector3(0.35, 0.7, 0.35)), o + Vector3(0, 2.1, 0)), "stone")
	for k in 2:
		_add_box_collider(o + Vector3(0, 0.35, 0), Vector3(6.1, 0.7, 6.1), -axis + float(k) * PI * 0.25)
	_add_box_collider(o + Vector3(0, 1.2, 0), Vector3(1.0, 2.4, 1.0), -axis)
	# Market stalls around the square.
	for i in 8:
		var a := TAU * float(i) / 8.0 + 0.2
		_build_stall(o + Vector3(cos(a) * 11.0, 0, sin(a) * 11.0), -a + PI * 0.5, i)
	# Bell tower on one corner of the square (a lookout with the best loot).
	var tc: Vector2 = sq.tower
	var t := {"center": tc, "pad": pad}
	towers.append(t)
	_build_tower(t)


const CLOTHS := ["cloth_red", "cloth_blue", "cloth_green", "cloth_yellow"]


## A market stall: counter, four posts and a sloped awning, loot on the counter.
func _build_stall(p: Vector3, yaw: float, i: int) -> void:
	var sb := Basis(Vector3.UP, yaw)
	_proc_box(Transform3D(sb.scaled_local(Vector3(2.6, 0.9, 1.2)), p + Vector3(0, 0.45, 0)), "wood")
	for px in [-1.2, 1.2]:
		for pz in [-0.55, 0.55]:
			_proc_box(Transform3D(sb.scaled_local(Vector3(0.1, 2.4, 0.1)), p + sb * Vector3(px, 1.2, pz)), "wood_dark")
	_proc_box(Transform3D((sb * Basis(Vector3.RIGHT, 0.25)).scaled_local(Vector3(2.9, 0.05, 1.7)), p + Vector3(0, 2.45, 0)), CLOTHS[i % CLOTHS.size()])
	_add_box_collider(p + Vector3(0, 0.45, 0), Vector3(2.6, 0.9, 1.2), yaw)
	loot_points.append({"pos": p + sb * Vector3(0, 0.95, 0), "kind": "gear" if i % 3 else "weapon", "village": true})


## A ring of stone blocks (basin kerbs, well heads), `n` segments around `r`.
func _stone_ring(c: Vector3, r: float, n: int, h: float, t: float, yaw: float) -> void:
	var seg := 2.0 * r * tan(PI / float(n)) + 0.08
	for i in n:
		var a := TAU * float(i) / float(n) + yaw
		var sb := Basis(Vector3.UP, -a + PI * 0.5)
		_proc_box(Transform3D(sb.scaled_local(Vector3(seg, h, t)), c + Vector3(cos(a) * r, h * 0.5, sin(a) * r)), "stone")


## A stone well: an octagonal kerb, two timber posts, a winch beam and a
## little tiled roof. Waist-high cover in the middle of a square.
func _build_well(p: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	for i in 8:
		var a := TAU * float(i) / 8.0
		# Each kerb stone runs along the ring (tangent), slightly overlapping.
		var sb := b * Basis(Vector3.UP, -a + PI * 0.5)
		_proc_box(Transform3D(sb.scaled_local(Vector3(0.78, 0.85, 0.3)), p + b * Vector3(cos(a) * 0.84, 0.425, sin(a) * 0.84)), "stone")
	_proc_box(Transform3D(b.scaled_local(Vector3(1.4, 0.06, 1.4)), p + Vector3(0, 0.55, 0)), "water")
	for sx in [-1.0, 1.0]:
		_proc_box(Transform3D(b.scaled_local(Vector3(0.14, 1.9, 0.14)), p + b * Vector3(float(sx) * 0.95, 1.4, 0)), "wood_dark")
	_proc_box(Transform3D(b.scaled_local(Vector3(2.1, 0.12, 0.12)), p + b * Vector3(0, 2.05, 0)), "wood_dark")
	_proc_box(Transform3D(b.scaled_local(Vector3(0.05, 0.6, 0.05)), p + b * Vector3(0, 1.72, 0)), "wood")
	for sz in [-1.0, 1.0]:
		var roof := b * Basis(Vector3.RIGHT, float(sz) * 0.6)
		_proc_box(Transform3D(roof.scaled_local(Vector3(2.4, 0.06, 1.1)), p + b * Vector3(0, 2.55, float(sz) * 0.42)), "cloth_red")
	_add_box_collider(p + Vector3(0, 0.42, 0), Vector3(2.0, 0.85, 2.0), yaw)


## Timber upper floor with a stairwell, the stair against the +x wall.
## The opening is cut exactly over the flight (plus head room), there is a
## solid landing beyond its top and a clear step-on space at its foot.
func _upper_floor(origin: Vector3, b: Basis, w: float, d: float) -> void:
	var y := WALL_HEIGHT
	var yaw := b.get_euler().y
	var stair_x := w * 0.5 - 1.1
	var run := 4.58
	var foot := stair_foot_z(d)
	var top := foot - run
	# Opening along z over the stair column: from just past the top of the
	# flight to where the treads are low enough for full head room.
	var hole0 := top - 0.05
	var hole1 := foot - 0.9
	var inner := d * 0.5 - 0.15
	var fx := -w * 0.5 + 1.0
	while fx < w * 0.5 - 0.1:
		var stair_col := absf(fx - stair_x) < 1.0
		var fz := -d * 0.5 + 1.0
		while fz < d * 0.5 - 0.1:
			var overlap := minf(fz + 1.0, hole1) - maxf(fz - 1.0, hole0)
			if not stair_col or overlap < 0.6:
				_place("Floor_WoodDark", origin + b * Vector3(fx, y + 0.012, fz), yaw)
			fz += 2.0
		if stair_col:
			if hole0 > -inner + 0.05:
				_add_box_collider(origin + b * Vector3(fx, y - 0.1, (-inner + hole0) * 0.5), Vector3(2.0, 0.2, hole0 + inner), yaw)
			if hole1 < inner - 0.05:
				_add_box_collider(origin + b * Vector3(fx, y - 0.1, (hole1 + inner) * 0.5), Vector3(2.0, 0.2, inner - hole1), yaw)
		else:
			_add_box_collider(origin + b * Vector3(fx, y - 0.1, 0.0), Vector3(2.0, 0.2, inner * 2.0), yaw)
		fx += 2.0
	_place("Stair_Interior_Simple", origin + b * Vector3(stair_x, 0.0, foot), yaw, false, Vector3.ZERO)
	var ang := atan2(WALL_HEIGHT, run)
	_colliders.append({
		"xform": Transform3D(b * Basis(Vector3.RIGHT, ang), origin + b * Vector3(stair_x, WALL_HEIGHT * 0.5 - 0.12, foot - run * 0.5)),
		"size": Vector3(1.6, 0.2, sqrt(run * run + WALL_HEIGHT * WALL_HEIGHT) + 0.2),
	})
	_stair_structure(origin, b, Vector3(stair_x, 0.0, foot), run, WALL_HEIGHT, 1.6)
	# A railing along the open side of the stairwell upstairs.
	var rail_z := (hole0 + hole1) * 0.5
	# (It stops short of the top step so you can walk off the stair there.)
	var gap := 1.35
	if hole1 - hole0 - gap > 0.3:
		_proc_box(Transform3D(b.scaled_local(Vector3(0.08, 0.9, hole1 - hole0 - gap)), origin + b * Vector3(stair_x - 0.95, y + 0.45, rail_z + gap * 0.5)), "wood_dark")
		_add_box_collider(origin + b * Vector3(stair_x - 0.95, y + 0.5, rail_z + gap * 0.5), Vector3(0.1, 1.0, hole1 - hole0 - gap), yaw)
	# Ceiling beams under the boards, stopping at the stairwell.
	var bz := -d * 0.5 + 2.0
	while bz < d * 0.5 - 0.5:
		var bw := w - 0.4
		var bx := 0.0
		if bz > hole0 - 0.2 and bz < hole1 + 0.2:
			bw -= 2.2
			bx = -1.1
		_proc_box(Transform3D(b.scaled_local(Vector3(bw, 0.2, 0.18)), origin + b * Vector3(bx, y - 0.15, bz)), "wood_dark")
		bz += 2.0


func _build_village_extras() -> void:
	for sq in city_squares:
		_build_square(sq)
	for v in village_pads:
		var site: Vector2 = v.center
		var pad: float = v.pad
		var vr: float = v.radius
		var is_farm: bool = v.type == "farm"

		# The village well and a couple of market stalls on the square.
		var taken: Array[Vector2] = []
		if not is_farm and v.type != "city":
			var axis := float(v.get("axis", 0.0))
			var sdir := Vector2(cos(axis), sin(axis))
			var sperp := Vector2(-sdir.y, sdir.x)
			# Towns have streets crossing in the middle: use the corners of the
			# crossing. Villages have an open green: the middle, or near it.
			var spots: Array[Vector2] = []
			if v.type == "town":
				for a in [1.0, -1.0]:
					for b in [1.0, -1.0]:
						spots.append(site + sdir * float(a) * 5.0 + sperp * float(b) * 6.2)
			else:
				spots.append(site)
				for k in 8:
					var ang := TAU * float(k) / 8.0 + axis
					spots.append(site + Vector2(cos(ang), sin(ang)) * 7.0)
			var placed := 0
			for sp in spots:
				var ok := not blocks_house(sp, 1.8) and not _on_road(sp, 1.6)
				for q in taken:
					if q.distance_to(sp) < 4.6:
						ok = false
				if not ok:
					continue
				var yaw := -atan2((sp - site).y, (sp - site).x) + PI * 0.5 if sp != site else -axis
				if placed == 0:
					_build_well(Vector3(sp.x, pad, sp.y), -axis)
				else:
					_build_stall(Vector3(sp.x, pad, sp.y), yaw, placed)
				taken.append(sp)
				placed += 1
				if placed >= 3:
					break

		# Plaza loot (open air crates) + cover.
		for i in (rng.randi_range(2, 3) if is_farm else rng.randi_range(3, 6)):
			var ang := rng.randf() * TAU
			var dist := rng.randf_range(4.0, maxf(6.0, vr * 0.3))
			var p := Vector3(site.x + cos(ang) * dist, pad, site.y + sin(ang) * dist)
			var crate := rng.randf() < 0.55
			if _inside_house(Vector2(p.x, p.z), 1.4 if crate else 2.4):
				continue
			# Streets stay drivable.
			if _on_road(Vector2(p.x, p.z), 1.2 if crate else 2.2):
				continue
			var clash := false
			for q in taken:
				if q.distance_to(Vector2(p.x, p.z)) < (2.6 if crate else 3.6):
					clash = true
			if clash:
				continue
			taken.append(Vector2(p.x, p.z))
			var py := rng.randf_range(0.0, TAU)
			var pb := Basis(Vector3.UP, py)
			if crate:
				_place("Prop_Crate", p, py)
				_add_box_collider(p + Vector3(0, 0.53, 0), Vector3(1.06, 1.06, 1.06), py)
				loot_points.append({"pos": p + pb * Vector3(0.0, 0.06, 0.9), "kind": "weapon", "village": true})
			else:
				_place("Prop_Wagon", p, py)
				_add_box_collider(p + Vector3(0, 0.7, 0), Vector3(1.7, 1.4, 3.4), py)
				loot_points.append({"pos": p + pb * Vector3(1.4, 0.06, 0.0), "kind": "gear", "village": true})

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
			if _inside_house(Vector2(p.x, p.z), 2.0):
				continue
			# A ruined corner of an old building: two walls meeting in an L,
			# the second one broken down to a low stub.
			_place("Wall_UnevenBrick_Straight", p, ang)
			_add_wall_collider(p, ang, false)
			var wb := Basis(Vector3.UP, ang)
			var p2 := p + wb * Vector3(1.0, 0, 1.0)
			if not _inside_house(Vector2(p2.x, p2.z), 1.2):
				var stub := Transform3D(Basis(Vector3.UP, ang + PI * 0.5).scaled_local(Vector3(2.0, 1.1, 0.4)), p2 + Vector3(0, 0.55, 0))
				_proc_box(stub, "stone")
				_add_box_collider(p2 + Vector3(0, 0.55, 0), Vector3(2.0, 1.1, 0.4), ang + PI * 0.5)
				for k in 3:
					_place("Prop_Brick%d" % rng.randi_range(1, 4), p2 + wb * Vector3(rng.randf_range(-0.6, 1.4), 0, rng.randf_range(-1.2, 0.8)), rng.randf() * TAU)


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
	var bkey := "%s|%d_%d" % [key, int(floor(bottom_center.x / BATCH_CELL)), int(floor(bottom_center.z / BATCH_CELL))]
	if not _batches.has(bkey):
		_batches[bkey] = []
	_batches[bkey].append(xform)
	_stat.pieces += 1


## Collision for a kit wall piece. Pieces with an opening (windows, doors,
## arches) collide with their own render mesh, so whatever you can see
## through you can shoot through, and nothing else.
func _add_wall_for(key: String, pos: Vector3, yaw: float) -> void:
	if key.contains("Window") or key.contains("Door") or key.contains("Arch"):
		_add_mesh_collider(key, pos, yaw)
	else:
		_add_wall_collider(pos, yaw, false)


var _mesh_shapes: Dictionary = {}
## Every wall piece with an opening that was placed: [key, model-to-world xform].
var opening_walls: Array = []


## A collider that is the model's own mesh, placed exactly like `_place` does.
func _add_mesh_collider(key: String, bottom_center: Vector3, yaw: float) -> void:
	var data := _model(key)
	if data.is_empty():
		_add_wall_collider(bottom_center, yaw, false)
		return
	if not _mesh_shapes.has(key):
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces((data.mesh as Mesh).get_faces())
		shape.backface_collision = true
		_mesh_shapes[key] = shape
	var aabb: AABB = data.aabb
	var basis := Basis(Vector3.UP, yaw)
	var offset := Vector3(-aabb.get_center().x, -aabb.position.y, -aabb.get_center().z)
	var xf := Transform3D(basis, bottom_center + basis * offset)
	_colliders.append({"xform": xf, "shape": _mesh_shapes[key]})
	opening_walls.append([key, xf])


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


## Where a staircase starts along z, leaving room at its foot to step on.
func stair_foot_z(d: float) -> float:
	# Leave about a metre to stand at the foot before stepping on.
	return d * 0.5 - 1.15


## Solid timber under a kit staircase: stringers both sides and a boarded
## underside, so the treads stop looking like they float.
func _stair_structure(origin: Vector3, b: Basis, foot: Vector3, run: float, rise: float, width: float) -> void:
	var ang := atan2(rise, run)
	var length := sqrt(run * run + rise * rise)
	var tilt := b * Basis(Vector3.RIGHT, ang)
	var mid := foot + Vector3(0, rise * 0.5, -run * 0.5)
	for side in [-1.0, 1.0]:
		var c: Vector3 = origin + b * (mid + Vector3(float(side) * (width * 0.5 + 0.02), -0.12, 0))
		_proc_box(Transform3D(tilt.scaled_local(Vector3(0.1, 0.36, length + 0.25)), c), "wood_dark")
	var under: Vector3 = origin + b * (mid + Vector3(0, -0.3, 0))
	_proc_box(Transform3D(tilt.scaled_local(Vector3(width + 0.1, 0.06, length)), under), "wood_dark")
	# A post holding up the top end.
	var post: Vector3 = origin + b * (foot + Vector3(width * 0.5 - 0.1, rise * 0.5 - 0.1, -run + 0.2))
	_proc_box(Transform3D(b.scaled_local(Vector3(0.16, rise - 0.2, 0.16)), post), "wood_dark")


var _proc: Dictionary = {}

## Gable infill under the kit roofs (which are open at the ends), per roof
## span: [height at the wall line, apex height], both above the wall head,
## kept just under the measured underside of the tiles.
const GABLE := {4: [0.07, 2.79], 6: [0.33, 4.2], 8: [0.36, 5.48]}
var _gables: Dictionary = {}


func _add_gables(top_center: Vector3, roof_yaw: float, span: float, length: float, style: String) -> void:
	var k := int(span)
	if not GABLE.has(k):
		return
	var rb := Basis(Vector3.UP, roof_yaw)
	var key := "%d|%s" % [k, style]
	if not _gables.has(key):
		_gables[key] = []
	for sz in [-1.0, 1.0]:
		_gables[key].append(Transform3D(rb, top_center + rb * Vector3(0, 0, float(sz) * length * 0.5)))


func _gable_mesh(span: int) -> ArrayMesh:
	var e: float = GABLE[span][0]
	var a: float = GABLE[span][1]
	var hw := float(span) * 0.5
	var t := 0.16
	var outline := [Vector2(-hw, -0.05), Vector2(hw, -0.05), Vector2(hw, e), Vector2(0, a), Vector2(-hw, e)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in [-1.0, 1.0]:
		var z := float(face) * t
		for tri in [[0, 1, 2], [0, 2, 4], [4, 2, 3]]:
			# Godot treats clockwise triangles as front faces.
			var idx: Array = tri if face < 0.0 else [tri[0], tri[2], tri[1]]
			for i in idx:
				var v: Vector2 = outline[int(i)]
				st.set_normal(Vector3(0, 0, float(face)))
				st.set_uv(Vector2(v.x, -v.y) * 0.5)
				st.add_vertex(Vector3(v.x, v.y, z))
	# Sides of the slab.
	for i in outline.size():
		var p0: Vector2 = outline[i]
		var p1: Vector2 = outline[(i + 1) % outline.size()]
		var n := Vector3(p1.y - p0.y, -(p1.x - p0.x), 0).normalized() * -1.0
		for v in [Vector3(p0.x, p0.y, -t), Vector3(p1.x, p1.y, -t), Vector3(p1.x, p1.y, t), Vector3(p0.x, p0.y, -t), Vector3(p1.x, p1.y, t), Vector3(p0.x, p0.y, t)]:
			st.set_normal(n)
			st.set_uv(Vector2((v as Vector3).z + (v as Vector3).x, -(v as Vector3).y) * 0.5)
			st.add_vertex(v)
	# The wall material is normal-mapped, which needs tangents.
	st.generate_tangents()
	return st.commit()


func _commit_gables() -> void:
	for key in _gables:
		var parts: PackedStringArray = (key as String).split("|")
		var list: Array = _gables[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _gable_mesh(int(parts[0]))
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "G_" + (key as String).replace("|", "_")
		mmi.multimesh = mm
		mmi.material_override = _proc_material("gable_" + parts[1])
		mmi.visibility_range_end = 1300.0
		add_child(mmi)


func _proc_box(xf: Transform3D, mat: String) -> void:
	if not _proc.has(mat):
		_proc[mat] = []
	_proc[mat].append(xf)


func _proc_material(key: String) -> Material:
	var m := StandardMaterial3D.new()
	if key.begins_with("cloth_"):
		var cols := {"cloth_red": Color(0.7, 0.16, 0.12), "cloth_blue": Color(0.18, 0.3, 0.62), "cloth_green": Color(0.2, 0.48, 0.24), "cloth_yellow": Color(0.86, 0.68, 0.22)}
		m.albedo_color = cols[key]
		m.roughness = 0.95
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		return m
	if key == "water":
		m.albedo_color = Color(0.22, 0.42, 0.5)
		m.roughness = 0.05
		m.metallic = 0.3
		return m
	if key.begins_with("gable_"):
		# Same surface as the kit's walls (copied from its material), mapped
		# in world space because the infill has no authored UVs.
		var wall := _model("Wall_%s_Straight" % key.substr(6))
		if not wall.is_empty():
			var wm: Mesh = wall.mesh
			for si in wm.get_surface_count():
				var km := wm.surface_get_material(si) as BaseMaterial3D
				if km != null and km.resource_name == ("MI_Plaster" if key == "gable_Plaster" else "MI_UnevenBrick"):
					var g := km.duplicate() as BaseMaterial3D
					g.uv1_triplanar = true
					g.uv1_world_triplanar = true
					g.uv1_scale = Vector3.ONE * 0.5
					g.cull_mode = BaseMaterial3D.CULL_DISABLED
					return g
		m.albedo_texture = load("res://assets/village/T_Plaster_BaseColor.png")
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		return m
	if key == "stone":
		m.albedo_texture = load("res://assets/village/T_UnevenBrick_BaseColor.png")
		m.normal_enabled = true
		m.normal_texture = load("res://assets/village/T_UnevenBrick_Normal.png")
		m.roughness = 0.9
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * 0.4
		return m
	m.albedo_texture = load("res://assets/village/T_WoodTrim_BaseColor.png")
	m.albedo_color = Color(0.62, 0.5, 0.42) if key == "wood_dark" else Color(1, 1, 1)
	m.normal_enabled = true
	m.normal_texture = load("res://assets/village/T_WoodTrim_Normal.png")
	m.roughness = 0.85
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.6
	return m


func _commit_proc() -> void:
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	for key in _proc:
		var list: Array = _proc[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = cube
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "P_" + key
		mmi.multimesh = mm
		mmi.material_override = _proc_material(key)
		add_child(mmi)


func _commit_batches() -> void:
	_commit_proc()
	_commit_gables()
	for bkey in _batches:
		var key: String = bkey.split("|")[0]
		var data := _model(key)
		if data.is_empty():
			continue
		var transforms: Array = _batches[bkey]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = data.mesh
		mm.instance_count = transforms.size()
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "V_" + bkey.replace("|", "_")
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# Range is measured to the batch centre, so it must cover the cell's
		# half-diagonal.
		mmi.visibility_range_end = 1300.0 + BATCH_CELL * 0.75
		add_child(mmi)


func _commit_colliders() -> void:
	var body := StaticBody3D.new()
	body.name = "VillageCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	for c in _colliders:
		var shape := CollisionShape3D.new()
		if c.has("shape"):
			shape.shape = c.shape
		else:
			var box := BoxShape3D.new()
			box.size = c.size
			shape.shape = box
		shape.transform = c.xform
		body.add_child(shape)
	add_child(body)


# ------------------------------------------------------------ lookout towers --
## Two-storey stone towers on high ground: interior stair, windows on every
## side of the upper floor, the best loot up top. Places worth fighting over.
func _plan_towers() -> void:
	# Bell towers in the cities were already built with their squares.
	var first_new := towers.size()
	var cands: Array = []
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = rng.seed + 31
	for i in 1500:
		var c := terrain.random_land_point(rng2, 8.0, 0.32)
		var h := terrain.height_at(c.x, c.y)
		if terrain.is_reserved(c, 12.0):
			continue
		if h < 8.0 or terrain.slope_at(c.x, c.y) > 0.32 or terrain.roughness(c.x, c.y, 5.0) > 3.5:
			continue
		cands.append([h + rng2.randf() * 4.0, c])
	cands.sort_custom(func(a, b): return a[0] > b[0])
	for e in cands:
		if towers.size() - first_new >= 12:
			break
		var c: Vector2 = e[1]
		if _too_close(c, 90.0, 220.0):
			continue
		var pad := terrain.flatten_circle(c.x, c.y, 5.5, 9.0)
		towers.append({"center": c, "pad": pad})
		poi_pads.append({"center": c, "radius": 9.0, "type": "tower"})
	for t in towers.slice(first_new):
		_build_tower(t)


func _too_close(c: Vector2, from_villages: float, from_pois: float) -> bool:
	for v in village_pads:
		# Big towns reach further out than the default clearance.
		if c.distance_to(v.center) < maxf(from_villages, float(v.radius) + 24.0):
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
				_add_wall_for(key, pos, yaw + wall_yaw)
	# Floors: brick downstairs, timber upstairs with a stairwell (same
	# layout as the two-storey houses).
	for fx in [-2.0, 0.0, 2.0]:
		for fz in [-2.0, 0.0, 2.0]:
			_place("Floor_Brick", origin + b * Vector3(fx, 0.012, fz), yaw)
	_upper_floor(origin, b, 6.0, 6.0)
	# Roof with eaves over the upper walls.
	_place("Roof_RoundTiles_6x6", origin + Vector3(0, WALL_HEIGHT * 2.0 - 0.62, 0), yaw)
	_add_gables(origin + Vector3(0, WALL_HEIGHT * 2.0, 0), yaw, 6.0, 6.0, "UnevenBrick")
	# Loot: the good stuff is upstairs.
	for i in 3:
		var lp := origin + b * Vector3(rng.randf_range(-2.2, 0.6), WALL_HEIGHT + 0.08, rng.randf_range(-2.2, 2.2))
		loot_points.append({"pos": lp, "kind": "weapon" if i == 0 else "gear", "village": true, "tier": "hi"})
	loot_points.append({"pos": origin + b * Vector3(-1.5, 0.08, rng.randf_range(-1.5, 1.5)), "kind": "gear", "village": true})
	_stat.towers += 1


# ------------------------------------------------------------------- ruins --
## Broken walls, arches and crates out in the open fields: cover between
## towns, with a little loot to make the detour worth it.
func _plan_ruins() -> void:
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = rng.seed + 57
	var placed := 0
	for i in 2000:
		if placed >= 30:
			break
		var c := terrain.random_land_point(rng2, 3.0, 0.22)
		if terrain.is_reserved(c, 14.0):
			continue
		if terrain.height_at(c.x, c.y) < 3.0 or terrain.slope_at(c.x, c.y) > 0.22:
			continue
		if terrain.roughness(c.x, c.y, 8.0) > 3.0:
			continue
		if _too_close(c, 70.0, 110.0):
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
				_add_wall_for("Wall_Arch", pos, yaw + wall_yaw)
			elif roll < 0.45:
				_place("Wall_UnevenBrick_Window_Wide_Round", pos, yaw + wall_yaw)
				_add_wall_for("Wall_UnevenBrick_Window_Wide_Round", pos, yaw + wall_yaw)
			else:
				_place("Wall_UnevenBrick_Straight", pos, yaw + wall_yaw)
				_add_wall_collider(pos, yaw + wall_yaw, false)
	# Rubble and crates for low cover.
	for i in rng.randi_range(2, 4):
		var p := origin + b * Vector3(rng.randf_range(-w, w), 0, rng.randf_range(-d - 3.0, d + 3.0))
		if rng.randf() < 0.6:
			var cy := rng.randf() * TAU
			_place("Prop_Crate", p, cy)
			_add_box_collider(p + Vector3(0, 0.53, 0), Vector3(1.06, 1.06, 1.06), cy)
		else:
			_place("Prop_Brick%d" % rng.randi_range(1, 4), p, rng.randf() * TAU)
	for i in rng.randi_range(2, 4):
		var lp := origin + b * Vector3(rng.randf_range(-w + 1.0, w - 1.0), 0.08, rng.randf_range(-d + 1.0, d - 1.0))
		loot_points.append({"pos": lp, "kind": "weapon" if i == 0 else "gear", "village": false})
	_stat.ruins += 1
