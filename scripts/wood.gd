class_name Wood
extends RefCounted

## Sawn timber for everything built in code: one shader (shaders/wood.gdshader)
## that lays the grain out board by board, and the helpers that tell it which
## way the boards of a piece run.

const SHADER := preload("res://shaders/wood.gdshader")
const BOARD_W := 0.26

static var _cache: Dictionary = {}


## Light or dark timber. `instanced` is for unit cubes in a MultiMesh, where
## the shader reads each board layout off the instance's size.
static func material(dark := false, instanced := false, tint := Color.WHITE) -> ShaderMaterial:
	var key := "%s|%s|%s" % [dark, instanced, tint]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("atlas", load("res://assets/village/T_WoodTrim_BaseColor.png"))
	m.set_shader_parameter("band_lo", 0.328 if dark else 0.014)
	m.set_shader_parameter("band_hi", 0.598 if dark else 0.292)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("board_w", BOARD_W)
	m.set_shader_parameter("instance_boxes", instanced)
	_cache[key] = m
	return m


## What a wood surface starts with: no layout given (the shader falls back to
## level planks). Every vertex needs the same attributes.
static func begin(st: SurfaceTool) -> void:
	st.set_color(Color(0.5, 0.5, 0.5, 0.0))
	st.set_uv(Vector2.ZERO)


## Grain runs along `dir` for what is added next: a round log (no seams) or
## boards with seams. Call begin() again afterwards.
static func grain(st: SurfaceTool, dir: Vector3, log := false) -> void:
	var d := dir.normalized() * 0.5 + Vector3(0.5, 0.5, 0.5)
	st.set_color(Color(d.x, d.y, d.z, 0.25 if log else 0.5))


## A box of boards: grain along its longest side, a whole number of boards
## across every face, sawn ends on the two short faces.
static func box(st: SurfaceTool, b: Basis, c: Vector3, size: Vector3) -> void:
	var ax: Array[Vector3] = [b.x.normalized(), b.y.normalized(), b.z.normalized()]
	var sz: Array[float] = [size.x, size.y, size.z]
	var l := 0
	if sz[1] > sz[l]:
		l = 1
	if sz[2] > sz[l]:
		l = 2
	var seed := fposmod(sin(c.dot(Vector3(12.9898, 78.233, 37.719))) * 43758.5453, 1.0)
	for k in 3:
		var end := k == l
		var ai := (k + 1) % 3 if end else l
		var bi := (k + 2) % 3 if end else 3 - k - l
		if end and maxf(sz[ai], sz[bi]) > 0.45:
			# Too big to be the sawn end of one timber (the side of a counter,
			# a crate): it is boarded like the other faces.
			end = false
			if sz[bi] > sz[ai]:
				var t := ai
				ai = bi
				bi = t
		var ha := ax[ai] * sz[ai] * 0.5
		var hb := ax[bi] * sz[bi] * 0.5
		var boards := maxf(1.0, round(sz[bi] / BOARD_W))
		var bw := sz[bi] / boards
		st.set_color(Color(1.0 if end else 0.0, seed, clampf(bw * 2.0, 0.0, 1.0), 1.0))
		for s: float in [-1.0, 1.0]:
			var n := ax[k] * s
			var fc := c + n * sz[k] * 0.5
			var ps: Array[Vector3] = []
			var uvs: Array[Vector2] = []
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				ps.append(fc + ha * corner.x + hb * corner.y)
				if end:
					uvs.append(Vector2(corner.x * sz[ai] * 0.5, corner.y * sz[bi] * 0.5))
				else:
					uvs.append(Vector2(corner.x * sz[ai] * 0.5, (corner.y * 0.5 + 0.5) * boards))
			st.set_normal(n)
			for tri: Array in [[0, 1, 2], [0, 2, 3]]:
				var i0: int = tri[0]
				var i1: int = tri[1]
				var i2: int = tri[2]
				# Godot's front faces wind clockwise.
				if (ps[i1] - ps[i0]).cross(ps[i2] - ps[i0]).dot(n) > 0.0:
					var t := i1
					i1 = i2
					i2 = t
				for i: int in [i0, i1, i2]:
					st.set_uv(uvs[i])
					st.add_vertex(ps[i])
	begin(st)
