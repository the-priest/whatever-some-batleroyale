class_name Fauna
extends Node3D
## The animals of the isle: does, foxes, hares, squirrels and boars in the
## woods; cows, sheep, goats, pigs, chickens and horses round the villages;
## gulls and seals on the shore; whales offshore. They graze and wander, and
## bolt at gunfire or when you come too close. Only the ones near you think
## and animate; far ones stand still or are hidden.

const A := "res://assets/creatures/animals/"
## kind: [file, height (m), walk speed, wild]
const KINDS := {
	"doe": ["Doe.glb", 1.35, 1.6, true],
	"fox": ["Fox.glb", 0.55, 2.4, true],
	"hare": ["Hare.glb", 0.45, 2.8, true],
	"squirrel": ["Squirrel.glb", 0.3, 2.2, true],
	"boar": ["WildBoar.glb", 0.95, 1.8, true],
	"skulldeer": ["SkullDeer.glb", 1.6, 1.3, true],
	"cow": ["HolsteinCow.glb", 1.5, 0.9, false],
	"hcow": ["HighlandCow.glb", 1.4, 0.9, false],
	"sheep": ["Sheep.glb", 1.0, 1.0, false],
	"bsheep": ["BlackSheep.glb", 1.0, 1.0, false],
	"goat": ["Goat.glb", 1.0, 1.2, false],
	"pig": ["Pig.glb", 0.85, 1.0, false],
	"chicken": ["BrahmaChicken.glb", 0.5, 1.1, false],
	"horse": ["PalominoHorse.glb", 1.75, 1.3, false],
	"gull": ["Seagull.glb", 0.35, 1.2, true],
	"seal": ["Seal.glb", 0.7, 0.6, true],
	"whale": ["Whale.glb", 3.4, 2.5, true],
}
const WILD := ["doe", "doe", "fox", "hare", "hare", "squirrel", "boar", "doe", "fox", "boar"]
const FARM := ["cow", "sheep", "sheep", "goat", "pig", "chicken", "chicken", "hcow", "bsheep", "horse"]
const THINK_R := 150.0
const SHOW_R := 260.0

var game: Node
var animals: Array = []
var _rng := RandomNumberGenerator.new()
var _scenes: Dictionary = {}
var _tick := 0


func setup(p_game: Node, seed_value: int) -> void:
	game = p_game
	_rng.seed = seed_value + 909
	var terrain: Terrain = game.terrain
	# Farms: a few animals round each village.
	for v in game.world.villages.village_pads:
		var c: Vector2 = v.center
		var r := float(v.radius)
		var n := _rng.randi_range(3, 6)
		for i in n:
			for t in 8:
				var a := _rng.randf() * TAU
				var p := c + Vector2(cos(a), sin(a)) * _rng.randf_range(r * 0.7, r + 14.0)
				if not game.world.villages.house_at(p, 3.0).is_empty():
					continue
				if terrain.height_at(p.x, p.y) < terrain.water_surface_at(p.x, p.y) + 0.5:
					continue
				_spawn(FARM[_rng.randi() % FARM.size()], p, 10.0)
				break
	# The woods.
	var placed := 0
	var tries := 0
	while placed < 60 and tries < 3000:
		tries += 1
		var p2 := terrain.random_land_point(_rng, Terrain.WATER_LEVEL + 1.5, 0.35)
		if terrain.forest_density(p2.x, p2.y) < 0.25 and _rng.randf() < 0.7:
			continue
		if not game.world.villages.house_at(p2, 20.0).is_empty():
			continue
		var k: String = WILD[_rng.randi() % WILD.size()]
		if placed % 20 == 7:
			k = "skulldeer"
		_spawn(k, p2, 25.0)
		placed += 1
	# The shore: gulls and seals where the land meets the sea.
	var shore := 0
	tries = 0
	while shore < 20 and tries < 4000:
		tries += 1
		var q := Vector2(_rng.randf_range(-Terrain.HALF * 0.9, Terrain.HALF * 0.9), _rng.randf_range(-Terrain.HALF * 0.9, Terrain.HALF * 0.9))
		var h := terrain.height_at(q.x, q.y)
		var w := terrain.water_surface_at(q.x, q.y)
		if h < w + 0.3 or h > w + 1.6:
			continue
		_spawn("gull" if shore % 3 != 0 else "seal", q, 8.0)
		shore += 1
	# Whales, far out.
	for i in 3:
		var a2 := _rng.randf() * TAU
		var far := Terrain.HALF * 1.15
		var wp := Vector2(cos(a2), sin(a2)) * far
		_spawn("whale", wp, 60.0, true)


func _scene(file: String) -> PackedScene:
	if not _scenes.has(file):
		_scenes[file] = load(A + file)
	return _scenes[file]


func _spawn(kind: String, at: Vector2, wander: float, sea := false) -> void:
	var d: Array = KINDS[kind]
	var ps := _scene(str(d[0]))
	if ps == null:
		return
	var root := Node3D.new()
	add_child(root)
	var m := ps.instantiate() as Node3D
	root.add_child(m)
	var box := SoldierRig.skin_box(m)
	if box.size.y > 0.00001:
		var k := float(d[1]) / box.size.y
		m.scale = Vector3.ONE * k
		m.position.y = -box.position.y * k
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		g.visibility_range_end = SHOW_R
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if float(d[1]) > 0.8 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var aps := m.find_children("*", "AnimationPlayer", true, false)
	var ap: AnimationPlayer = aps[0] as AnimationPlayer if not aps.is_empty() else null
	if ap != null:
		for nm in ["idle", "walk"]:
			if ap.has_animation(nm):
				ap.get_animation(nm).loop_mode = Animation.LOOP_LINEAR
		ap.play("idle")
		ap.seek(_rng.randf() * 2.0, true)
	var y: float = game.terrain.height_at(at.x, at.y)
	if sea:
		y = game.terrain.water_surface_at(at.x, at.y) - 1.2
	root.global_position = Vector3(at.x, y, at.y)
	root.rotation.y = _rng.randf() * TAU
	animals.append({
		"node": root, "anim": ap, "kind": kind, "home": Vector2(at.x, at.y), "wander": wander,
		"speed": float(d[2]), "wild": bool(d[3]), "sea": sea, "state": "idle", "t": _rng.randf_range(1.0, 6.0),
		"to": Vector2(at.x, at.y), "flee": 0.0, "clip": "idle",
	})


## A shot nearby: the wild ones bolt (and the farm ones startle).
func gunshot(pos: Vector3) -> void:
	for a in animals:
		var n: Node3D = a.node
		if n.global_position.distance_to(pos) < 45.0:
			_scare(a, pos)


func _scare(a: Dictionary, from: Vector3) -> void:
	var n: Node3D = a.node
	var away := Vector2(n.global_position.x - from.x, n.global_position.z - from.z)
	if away.length() < 0.1:
		away = Vector2(1, 0)
	var dist := 18.0 if bool(a.wild) else 6.0
	a.to = Vector2(n.global_position.x, n.global_position.z) + away.normalized() * dist
	a.flee = 3.5 if bool(a.wild) else 1.5
	a.state = "walk"


func _play(a: Dictionary, clip: String, speed := 1.0) -> void:
	var ap: AnimationPlayer = a.anim
	if ap == null:
		return
	ap.speed_scale = speed
	if a.clip != clip and ap.has_animation(clip):
		a.clip = clip
		ap.play(clip, 0.25)


func _process(delta: float) -> void:
	if game == null or game.player == null or animals.is_empty():
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	var eye: Vector3 = cam.global_position if cam != null else game.player.global_position
	var pp: Vector3 = game.player.global_position
	_tick += 1
	for i in animals.size():
		var a: Dictionary = animals[i]
		var n: Node3D = a.node
		var d2 := n.global_position.distance_squared_to(eye)
		var ap: AnimationPlayer = a.anim
		if d2 > THINK_R * THINK_R:
			# Far away: frozen (and hidden past SHOW_R by the meshes themselves).
			if ap != null and ap.active:
				ap.active = false
			continue
		if ap != null and not ap.active:
			ap.active = true
		_think(a, delta, pp)


func _think(a: Dictionary, delta: float, pp: Vector3) -> void:
	var n: Node3D = a.node
	var here := Vector2(n.global_position.x, n.global_position.z)
	a.flee = maxf(0.0, float(a.flee) - delta)
	# Too close: the wild ones bolt.
	if bool(a.wild) and float(a.flee) <= 0.0 and not bool(a.sea) and here.distance_to(Vector2(pp.x, pp.z)) < 7.0:
		_scare(a, pp)
	match str(a.state):
		"idle":
			_play(a, "idle")
			a.t = float(a.t) - delta
			if float(a.t) <= 0.0:
				var ang := _rng.randf() * TAU
				a.to = (a.home as Vector2) + Vector2(cos(ang), sin(ang)) * _rng.randf_range(2.0, float(a.wander))
				a.state = "walk"
		"walk":
			var fleeing := float(a.flee) > 0.0
			var spd := float(a.speed) * (3.2 if fleeing else 1.0)
			var to: Vector2 = (a.to as Vector2) - here
			if to.length() < 0.6:
				a.state = "idle"
				a.t = _rng.randf_range(3.0, 9.0)
				return
			var step := to.normalized() * minf(spd * delta, to.length())
			var nx := here + step
			var ny: float
			if bool(a.sea):
				ny = game.terrain.water_surface_at(nx.x, nx.y) - 1.2 + sin(Time.get_ticks_msec() * 0.0005) * 0.6
			else:
				ny = game.terrain.height_at(nx.x, nx.y)
				# Never into the sea (or off a cliff into it).
				if ny < game.terrain.water_surface_at(nx.x, nx.y) + 0.2 and str(a.kind) not in ["seal", "gull"]:
					a.state = "idle"
					a.t = 1.0
					return
			n.global_position = Vector3(nx.x, ny, nx.y)
			var yaw := atan2(step.x, step.y)
			n.rotation.y = lerp_angle(n.rotation.y, yaw, clampf(delta * 6.0, 0.0, 1.0))
			_play(a, "walk", 2.2 if fleeing else 1.0)
