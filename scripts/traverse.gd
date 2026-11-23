class_name Traverse
extends Node3D
## Can you get everywhere on foot? The island is sampled on a grid; from each
## cell you can always drop to a lower one, and climb to a higher one only if
## the rise is a walkable slope or within one jump and the ledge-grab. Every
## patch of ground that cannot be reached from the heart of the isle (a
## plateau ringed by cliffs, a high shelf) gets ladders up its cliff, and the
## search runs again until nothing is cut off. The result is written to
## docs/TRAVERSAL.md by the --traverse check.

const CELL := 8.0
## Highest rise one jump and the ledge-grab can take you.
const CLIMB := 5.0
const MAX_SLOPE := 0.36
const MIN_REGION := 6

var game: Node
var n := 0
var walk := PackedByteArray()
var hgt := PackedFloat32Array()
var ladders: Array = []
## [cells, centre] of each region found cut off before ladders.
var cut_off: Array = []
var unreached_after := 0
var walkable_cells := 0
## Extra one-way links the ladders make: cell -> cell.
var _links: Dictionary = {}


func build(p_game: Node) -> void:
	game = p_game
	var tr: Terrain = game.terrain
	n = int(Terrain.HALF * 2.0 / CELL)
	walk.resize(n * n)
	hgt.resize(n * n)
	for j in n:
		for i in n:
			var x := -Terrain.HALF + (float(i) + 0.5) * CELL
			var z := -Terrain.HALF + (float(j) + 0.5) * CELL
			var h := tr.height_at(x, z)
			var w := tr.water_surface_at(x, z)
			var k := j * n + i
			hgt[k] = maxf(h, w)
			# In the water you swim: it is a way through, at the surface.
			if h < w - 0.5:
				walk[k] = 2
			elif tr.slope_at(x, z) <= MAX_SLOPE:
				walk[k] = 1
			else:
				walk[k] = 0
	walkable_cells = 0
	for k in walk.size():
		if walk[k] != 0:
			walkable_cells += 1
	var seed := _seed_cell()
	var first := true
	for round in 12:
		var reach := _reachable(seed)
		var blobs := _blobs(reach)
		if first:
			for b in blobs:
				cut_off.append([b.size(), _centre(b)])
			first = false
		if blobs.is_empty():
			break
		for b in blobs:
			_bridge(b, reach)
	_cliff_ladders()
	unreached_after = 0
	var final_reach := _reachable(seed)
	for k in walk.size():
		if walk[k] != 0 and not final_reach.has(k):
			unreached_after += 1


## The way up to a point, as the search found it (for the checks): the
## cells from the heart of the isle to it, with heights.
func path_to(target: Vector3) -> Array:
	var seed := _seed_cell()
	var tk := int((target.z + Terrain.HALF) / CELL) * n + int((target.x + Terrain.HALF) / CELL)
	var parent := {seed: -1}
	var q: Array[int] = [seed]
	var qi := 0
	while qi < q.size():
		var k: int = q[qi]
		qi += 1
		if k == tk:
			break
		var i := k % n
		var j := k / n
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var ni := i + d.x
			var nj := j + d.y
			if ni < 0 or nj < 0 or ni >= n or nj >= n:
				continue
			var nk := nj * n + ni
			if parent.has(nk) or walk[nk] == 0:
				continue
			if hgt[nk] <= hgt[k] or _up_ok(k, nk):
				parent[nk] = k
				q.append(nk)
		if _links.has(k):
			for lk: int in _links[k]:
				if not parent.has(lk):
					parent[lk] = k
					q.append(lk)
	var out: Array = []
	if not parent.has(tk):
		return out
	var c := tk
	while c != -1:
		out.push_front(_pos(c))
		c = parent[c]
	return out


func _seed_cell() -> int:
	# The heart of the isle: the walkable cell nearest the middle.
	var best := -1
	var bd := INF
	for j in n:
		for i in n:
			var k := j * n + i
			if walk[k] != 1:
				continue
			var d := Vector2(float(i) - n * 0.5, float(j) - n * 0.5).length()
			if d < bd:
				bd = d
				best = k
	return best


func _up_ok(a: int, b: int) -> bool:
	var dh := hgt[b] - hgt[a]
	return dh <= maxf(CLIMB, CELL * 0.7)


func _reachable(seed: int) -> Dictionary:
	var seen := {seed: true}
	var q: Array[int] = [seed]
	var qi := 0
	while qi < q.size():
		var k: int = q[qi]
		qi += 1
		var i := k % n
		var j := k / n
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var ni := i + d.x
			var nj := j + d.y
			if ni < 0 or nj < 0 or ni >= n or nj >= n:
				continue
			var nk := nj * n + ni
			if seen.has(nk) or walk[nk] == 0:
				continue
			if hgt[nk] <= hgt[k] or _up_ok(k, nk):
				seen[nk] = true
				q.append(nk)
		if _links.has(k):
			for lk: int in _links[k]:
				if not seen.has(lk):
					seen[lk] = true
					q.append(lk)
	return seen


## Groups of walkable cells not reached, big enough to matter.
func _blobs(reach: Dictionary) -> Array:
	var done := {}
	var out: Array = []
	for k in walk.size():
		if walk[k] != 1 or reach.has(k) or done.has(k):
			continue
		var blob: Array[int] = []
		var q: Array[int] = [k]
		done[k] = true
		while not q.is_empty():
			var c: int = q.pop_back()
			blob.append(c)
			var i := c % n
			var j := c / n
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var ni := i + d.x
				var nj := j + d.y
				if ni < 0 or nj < 0 or ni >= n or nj >= n:
					continue
				var nk := nj * n + ni
				if walk[nk] == 1 and not reach.has(nk) and not done.has(nk):
					done[nk] = true
					q.append(nk)
		if blob.size() >= MIN_REGION:
			out.append(blob)
	return out


func _centre(blob: Array) -> Vector3:
	var acc := Vector3.ZERO
	for k: int in blob:
		acc += _pos(k)
	return acc / float(maxi(1, blob.size()))


func _pos(k: int) -> Vector3:
	var i := k % n
	var j := k / n
	return Vector3(-Terrain.HALF + (float(i) + 0.5) * CELL, hgt[k], -Terrain.HALF + (float(j) + 0.5) * CELL)


## Ladders from reached ground up into a cut-off region: at the lowest rises
## round its edge, one for every stretch of cliff (big regions get several).
func _bridge(blob: Array, reach: Dictionary) -> void:
	var inside := {}
	for k: int in blob:
		inside[k] = true
	var cands: Array = []
	for k: int in blob:
		var i := k % n
		var j := k / n
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
			var ni := i + d.x
			var nj := j + d.y
			if ni < 0 or nj < 0 or ni >= n or nj >= n:
				continue
			var nk := nj * n + ni
			if reach.has(nk) and walk[nk] == 1 and not inside.has(nk):
				cands.append([hgt[k] - hgt[nk], nk, k])
	if cands.is_empty():
		return
	cands.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var want := 1 if blob.size() < 120 else (3 if blob.size() < 1500 else 5)
	var placed: Array[Vector3] = []
	for c in cands:
		if placed.size() >= want:
			break
		var top := _pos(int(c[2]))
		var clash := false
		for p in placed:
			if Vector2(p.x - top.x, p.z - top.z).length() < 140.0:
				clash = true
				break
		if clash:
			continue
		var bottom := _pos(int(c[1]))
		if _make_ladder(bottom, top):
			placed.append(top)
			var links: Array = _links.get(int(c[1]), [])
			links.append(int(c[2]))
			_links[int(c[1])] = links


## Every cliff too tall to jump gets a way up within a short walk, not just
## somewhere round the far side: a ladder every LADDER_SPACING metres along
## it, wherever flat ground lies at its top and at its foot.
const LADDER_SPACING := 150.0
const MAX_LADDERS := 90


func _cliff_ladders() -> void:
	# Bucketed by height (tallest first) instead of sorting thousands of
	# candidates; one candidate per cell is plenty.
	var buckets: Array = []
	buckets.resize(71)
	for bi in buckets.size():
		buckets[bi] = []
	for j in range(2, n - 2):
		for i in range(2, n - 2):
			var k := j * n + i
			if walk[k] != 1:
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var found := false
				for dist: int in [1, 2, 3]:
					var ci: int = i + d.x * dist
					var cj: int = j + d.y * dist
					var bk := cj * n + ci
					if walk[bk] != 1:
						continue
					var dh := hgt[k] - hgt[bk]
					if dh > CLIMB + 1.5 and dh < 70.0:
						(buckets[int(dh)] as Array).append(Vector2i(bk, k))
						found = true
					break
				if found:
					break
	var tops: Array[Vector3] = []
	for l in ladders:
		tops.append(l[2])
	for hb in range(70, -1, -1):
		for c: Vector2i in buckets[hb]:
			if ladders.size() >= MAX_LADDERS:
				return
			var top := _pos(c.y)
			var clash := false
			for p in tops:
				if absf(p.x - top.x) < LADDER_SPACING and absf(p.z - top.z) < LADDER_SPACING and Vector2(p.x - top.x, p.z - top.z).length() < LADDER_SPACING:
					clash = true
					break
			if clash:
				continue
			if not game.world.villages.house_at(Vector2(top.x, top.z), 20.0).is_empty():
				continue
			if _make_ladder(_pos(c.x), top):
				tops.append(top)
				var links: Array = _links.get(c.x, [])
				links.append(c.y)
				_links[c.x] = links


## A ladder up the cliff between two points: against the cliff face, from the
## foot of the climb to a little over the top.
func _make_ladder(bottom: Vector3, top: Vector3) -> bool:
	var tr: Terrain = game.terrain
	var flat := Vector2(top.x - bottom.x, top.z - bottom.z)
	if flat.length() < 0.5:
		return false
	var d := flat.normalized()
	var b2 := Vector2(bottom.x, bottom.z)
	var base_h := tr.height_at(b2.x, b2.y)
	var face := b2
	# Walk towards the top until the ground rears up: that is the cliff.
	for s in 60:
		var p := b2 + d * (float(s) * 0.5)
		if tr.height_at(p.x, p.y) > base_h + 1.2:
			face = p
			break
		face = p
	var foot := face - d * 0.7
	var y0 := tr.height_at(foot.x, foot.y)
	# The lip of the climb: the highest ground just past the face.
	var lip := face
	var y1 := y0
	for s in 40:
		var p := face + d * (float(s) * 0.5)
		var h := tr.height_at(p.x, p.y)
		if h > y1:
			y1 = h
			lip = p
		if h >= top.y - 0.5:
			lip = p
			y1 = h
			break
	if y1 - y0 < 1.5:
		return false
	# Nothing in the way at the foot or the top of the climb.
	game.world.remove_trees(Vector3(foot.x, y0, foot.y), 9.0)
	game.world.remove_trees(Vector3(lip.x, y1, lip.y), 3.0)
	var lad := Ladder.new()
	add_child(lad)
	lad.setup(Vector3(foot.x, y0, foot.y), y1 + 0.6, Vector3(d.x, 0, d.y), Vector3(lip.x, y1, lip.y))
	ladders.append([Vector3(foot.x, y0, foot.y), y1 - y0, Vector3(lip.x, y1, lip.y)])
	return true
