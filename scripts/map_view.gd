class_name MapView
extends Control

## The island drawn as a map. The terrain and the storm are shaders, so they
## stay sharp at any zoom; roads and buildings are drawn on top as vectors.
## The HUD minimap, the full map and the lobby preview are each one of these.
## Whoever owns it draws its own markers over it using to_map().

const SHADER_BASE := preload("res://shaders/map_base.gdshader")
const SHADER_STORM := preload("res://shaders/map_storm.gdshader")

const ROAD := Color(0.950, 0.885, 0.700)
const ROAD_EDGE := Color(0.330, 0.250, 0.140, 0.62)
const BRIDGE := Color(0.900, 0.870, 0.810)
const BRIDGE_EDGE := Color(0.180, 0.160, 0.150, 0.85)
const ROOF_LIT := Color(0.870, 0.455, 0.310)
const ROOF_SHADE := Color(0.660, 0.310, 0.225)
const SLATE_LIT := Color(0.610, 0.650, 0.730)
const SLATE_SHADE := Color(0.420, 0.460, 0.550)
const OUTLINE := Color(0.160, 0.110, 0.090, 0.92)
const STONE := Color(0.760, 0.740, 0.700)
const STONE_DARK := Color(0.520, 0.500, 0.470)
## Direction the sun comes from on the map (north-west).
const SUN := Vector2(-0.7071, -0.7071)
const CELL := 240.0

## World x/z at the top-left corner, and how many metres the width covers.
var origin := Vector2(-Terrain.HALF, -Terrain.HALF)
var span := Terrain.SIZE

var _base: ColorRect
var _vec: Control
var _storm: ColorRect
var _base_mat: ShaderMaterial
var _storm_mat: ShaderMaterial
## [a, b, width, is_bridge]
var _roads: Array = []
## [corners (4, world), ridge a, ridge b, slate roof, the lit half comes first]
var _houses: Array = []
## Other footprints: [kind, centre, half size or radius, yaw]
var _blocks: Array = []
## Spatial index so the minimap only walks what is near the player.
var _cells: Dictionary = {}
var _has_world := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_base = ColorRect.new()
	_base.set_anchors_preset(Control.PRESET_FULL_RECT)
	_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_base.color = Color(0.09, 0.275, 0.42)
	_base_mat = ShaderMaterial.new()
	_base_mat.shader = SHADER_BASE
	add_child(_base)
	_vec = Control.new()
	_vec.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vec.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vec.draw.connect(_draw_vectors)
	add_child(_vec)
	_storm = ColorRect.new()
	_storm.set_anchors_preset(Control.PRESET_FULL_RECT)
	_storm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_storm_mat = ShaderMaterial.new()
	_storm_mat.shader = SHADER_STORM
	_storm.material = _storm_mat
	_storm.visible = false
	add_child(_storm)
	resized.connect(_push_view)


## Hands over the baked map data and the vector features of a built world.
func set_world(world: WorldBuilder) -> void:
	if world == null or world.map_data_texture == null:
		return
	_has_world = true
	_base.material = _base_mat
	_base_mat.set_shader_parameter("data_tex", world.map_data_texture)
	_base_mat.set_shader_parameter("canopy_tex", world.map_canopy_texture)
	_base_mat.set_shader_parameter("half_size", Terrain.HALF)
	_base_mat.set_shader_parameter("cell", Terrain.STEP)
	_base_mat.set_shader_parameter("data_res", float(Terrain.RES))
	_roads.clear()
	_houses.clear()
	_blocks.clear()
	_cells.clear()
	var v := world.villages
	for r in v.roads:
		var a: Vector2 = r.a
		var b: Vector2 = r.b
		_roads.append([a, b, float(r.w), bool(r.get("bridge", false))])
		_index(a.min(b), a.max(b), 0, _roads.size() - 1)
	for h in v.houses:
		var c: Vector2 = h.center
		var w := float(h.w)
		var d := float(h.d)
		var yaw := float(h.yaw)
		var ax := Vector2(1, 0).rotated(-yaw)
		var az := Vector2(0, 1).rotated(-yaw)
		var along := ax if w >= d else az
		var across := az if w >= d else ax
		var hl := maxf(w, d) * 0.5
		var hw := minf(w, d) * 0.5
		# Lit half first: the side of the roof that faces the sun.
		if across.dot(SUN) < 0.0:
			across = -across
		var corners := PackedVector2Array([
			c - along * hl + across * hw, c + along * hl + across * hw,
			c + along * hl - across * hw, c - along * hl - across * hw])
		_houses.append([corners, c - along * hl, c + along * hl, str(h.style) != "Plaster"])
		var lo := corners[0]
		var hi := corners[0]
		for p in corners:
			lo = lo.min(p)
			hi = hi.max(p)
		_index(lo, hi, 1, _houses.size() - 1)
	for t in v.towers:
		_add_block("tower", t.center, Vector2(3.6, 3.6), float(t.get("yaw", 0.0)))
	for p in v.poi_pads:
		if str(p.type) == "ruin":
			_add_block("ruin", p.center, Vector2(5.0, 4.0), 0.0)
	var t3 := world.terrain
	_add_block("castle", t3.castle_c, Vector2(24.0, 24.0), 0.0)
	_add_block("temple", t3.temple_c, Vector2(15.0, 15.0), 0.0)
	_add_block("light", t3.lighthouse_c, Vector2(5.0, 5.0), 0.0)
	_add_block("henge", t3.henge_c, Vector2(11.0, 11.0), 0.0)
	_push_view()


func _add_block(kind: String, c: Vector2, half: Vector2, yaw: float) -> void:
	_blocks.append([kind, c, half, yaw])
	var r := half.length()
	_index(c - Vector2(r, r), c + Vector2(r, r), 2, _blocks.size() - 1)


func _index(lo: Vector2, hi: Vector2, list: int, id: int) -> void:
	for cz in range(int(floor(lo.y / CELL)), int(floor(hi.y / CELL)) + 1):
		for cx in range(int(floor(lo.x / CELL)), int(floor(hi.x / CELL)) + 1):
			var key := Vector2i(cx, cz)
			if not _cells.has(key):
				_cells[key] = [[], [], []]
			(_cells[key][list] as Array).append(id)


## Shows world rect [o, o + s] (s metres across the width).
func set_view(o: Vector2, s: float) -> void:
	if o.is_equal_approx(origin) and is_equal_approx(s, span):
		return
	origin = o
	span = maxf(s, 1.0)
	_push_view()


## Frames a world rect so all of it fits, whatever the control's shape.
func fit(rect: Rect2, margin := 0.06) -> void:
	var sz := size
	if sz.x < 1.0 or sz.y < 1.0:
		return
	var r := rect.grow(maxf(rect.size.x, rect.size.y) * margin)
	var s := maxf(r.size.x, r.size.y * sz.x / sz.y)
	var h := s * sz.y / sz.x
	set_view(r.get_center() - Vector2(s, h) * 0.5, s)


func set_zone(c: Vector2, r: float, nc: Vector2, nr: float) -> void:
	var show_zone := r > 0.5
	var show_next := nr > 0.5 and (absf(nr - r) > 0.5 or nc.distance_to(c) > 0.5)
	_storm.visible = show_zone or show_next
	_storm_mat.set_shader_parameter("zone_c", c)
	_storm_mat.set_shader_parameter("zone_r", r)
	_storm_mat.set_shader_parameter("next_c", nc)
	_storm_mat.set_shader_parameter("next_r", nr)
	_storm_mat.set_shader_parameter("show_zone", 1.0 if show_zone else 0.0)
	_storm_mat.set_shader_parameter("show_next", 1.0 if show_next else 0.0)


func hide_zone() -> void:
	_storm.visible = false


func set_grid(alpha: float) -> void:
	_base_mat.set_shader_parameter("grid_alpha", alpha)


func scale_px() -> float:
	return size.x / span


func to_map(p: Vector2) -> Vector2:
	return (p - origin) * (size.x / span)


func to_world(p: Vector2) -> Vector2:
	return origin + p * (span / maxf(size.x, 1.0))


func _push_view() -> void:
	var sz := size
	if sz.x < 1.0 or sz.y < 1.0:
		return
	var sp := Vector2(span, span * sz.y / sz.x)
	var ppm := sz.x / span
	for m: ShaderMaterial in [_base_mat, _storm_mat]:
		m.set_shader_parameter("view_origin", origin)
		m.set_shader_parameter("view_span", sp)
		m.set_shader_parameter("px_per_m", ppm)
	_vec.queue_redraw()


# -------------------------------------------------------------- vectors --
func _draw_vectors() -> void:
	if not _has_world:
		return
	var k := size.x / span
	var view := Rect2(origin, Vector2(span, span * size.y / maxf(size.x, 1.0)))
	var roads: PackedInt32Array
	var houses: PackedInt32Array
	var blocks: PackedInt32Array
	# Walk only the cells in view, unless that is most of the map anyway.
	var c0 := Vector2i(int(floor(view.position.x / CELL)), int(floor(view.position.y / CELL)))
	var c1 := Vector2i(int(floor(view.end.x / CELL)), int(floor(view.end.y / CELL)))
	if (c1.x - c0.x + 1) * (c1.y - c0.y + 1) > 30:
		roads = PackedInt32Array(range(_roads.size()))
		houses = PackedInt32Array(range(_houses.size()))
		blocks = PackedInt32Array(range(_blocks.size()))
	else:
		var seen := [{}, {}, {}]
		for cz in range(c0.y, c1.y + 1):
			for cx in range(c0.x, c1.x + 1):
				var cell: Variant = _cells.get(Vector2i(cx, cz))
				if cell == null:
					continue
				for list in 3:
					for id: int in (cell[list] as Array):
						seen[list][id] = true
		roads = PackedInt32Array(seen[0].keys())
		houses = PackedInt32Array(seen[1].keys())
		blocks = PackedInt32Array(seen[2].keys())

	# Roads: every casing first, then every surface, so junctions join up.
	var pad := view.grow(12.0)
	for pass_i in 2:
		for id in roads:
			var r: Array = _roads[id]
			var a: Vector2 = r[0]
			var b: Vector2 = r[1]
			if not pad.intersects(Rect2(a.min(b), (a - b).abs())):
				continue
			var bridge: bool = r[3]
			var w := maxf(float(r[2]) * 1.5 * k, 1.25)
			var pa := (a - origin) * k
			var pb := (b - origin) * k
			if pass_i == 0:
				var edge := BRIDGE_EDGE if bridge else ROAD_EDGE
				var we := w + (2.6 if bridge else 1.8)
				_vec.draw_line(pa, pb, edge, we, true)
				if we > 3.0:
					_vec.draw_circle(pa, we * 0.5, edge)
					_vec.draw_circle(pb, we * 0.5, edge)
			else:
				var col := BRIDGE if bridge else ROAD
				_vec.draw_line(pa, pb, col, w, true)
				if w > 2.2:
					_vec.draw_circle(pa, w * 0.5, col)
					_vec.draw_circle(pb, w * 0.5, col)

	# Houses: a two-tone gabled roof with a dark outline.
	for id in houses:
		var h: Array = _houses[id]
		var cw: PackedVector2Array = h[0]
		var p := PackedVector2Array([(cw[0] - origin) * k, (cw[1] - origin) * k, (cw[2] - origin) * k, (cw[3] - origin) * k])
		var slate: bool = h[3]
		var size_px := p[0].distance_to(p[2])
		if size_px < 5.0:
			_vec.draw_colored_polygon(p, SLATE_SHADE if slate else ROOF_SHADE)
			continue
		var ra := ((h[1] as Vector2) - origin) * k
		var rb := ((h[2] as Vector2) - origin) * k
		_vec.draw_colored_polygon(PackedVector2Array([p[0], p[1], rb, ra]), SLATE_LIT if slate else ROOF_LIT)
		_vec.draw_colored_polygon(PackedVector2Array([ra, rb, p[2], p[3]]), SLATE_SHADE if slate else ROOF_SHADE)
		var lw := clampf(size_px * 0.07, 1.0, 1.8)
		_vec.draw_polyline(PackedVector2Array([p[0], p[1], p[2], p[3], p[0]]), OUTLINE, lw, true)
		if size_px > 14.0:
			_vec.draw_line(ra, rb, OUTLINE, 1.0, true)

	# Towers, ruins and the big landmarks.
	for id in blocks:
		var bl: Array = _blocks[id]
		var c := ((bl[1] as Vector2) - origin) * k
		var half: Vector2 = (bl[2] as Vector2) * k
		match str(bl[0]):
			"tower":
				var r := maxf(half.x, 2.0)
				_vec.draw_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), STONE_DARK)
				_vec.draw_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), OUTLINE, false, 1.0)
			"ruin":
				if half.x > 2.5:
					_vec.draw_rect(Rect2(c - half, half * 2.0), Color(STONE.r, STONE.g, STONE.b, 0.55))
					_vec.draw_rect(Rect2(c - half, half * 2.0), STONE_DARK, false, maxf(1.0, half.x * 0.22))
			"castle":
				var wall := maxf(1.5, half.x * 0.20)
				_vec.draw_rect(Rect2(c - half, half * 2.0), Color(0.60, 0.56, 0.50))
				_vec.draw_rect(Rect2(c - half, half * 2.0), STONE, false, wall)
				_vec.draw_rect(Rect2(c - half - Vector2.ONE * wall * 0.5, half * 2.0 + Vector2.ONE * wall), OUTLINE, false, 1.0)
				for sx in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						var tc := c + Vector2(half.x * sx, half.y * sz)
						_vec.draw_circle(tc, wall * 1.25, STONE)
						_vec.draw_arc(tc, wall * 1.25, 0.0, TAU, 16, OUTLINE, 1.0, true)
				var keep := half * 0.42
				_vec.draw_rect(Rect2(c - keep, keep * 2.0), STONE_DARK)
				_vec.draw_rect(Rect2(c - keep, keep * 2.0), OUTLINE, false, 1.0)
			"temple":
				_vec.draw_rect(Rect2(c - half, half * 2.0), STONE)
				_vec.draw_rect(Rect2(c - half, half * 2.0), OUTLINE, false, 1.0)
				_vec.draw_rect(Rect2(c - half * 0.62, half * 1.24), Color(0.92, 0.84, 0.56))
				_vec.draw_rect(Rect2(c - half * 0.62, half * 1.24), OUTLINE, false, 1.0)
			"light":
				var r2 := maxf(half.x, 2.5)
				_vec.draw_circle(c, r2, Color(0.96, 0.95, 0.92))
				_vec.draw_arc(c, r2, 0.0, TAU, 20, OUTLINE, 1.0, true)
				_vec.draw_circle(c, r2 * 0.45, Color(0.86, 0.27, 0.22))
			"henge":
				var rr := maxf(half.x, 3.0)
				var dot := clampf(rr * 0.2, 1.0, 3.0)
				for i in 10:
					var ang := TAU * float(i) / 10.0
					_vec.draw_circle(c + Vector2(cos(ang), sin(ang)) * rr, dot, STONE_DARK)
