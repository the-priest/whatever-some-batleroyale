class_name Reaches
extends Node3D
## The sky ledges: basalt columns standing alone in the wilds, each with an
## ember cache burning on top. One jump (and the ledge-grab) does not reach
## them; a second jump in the air does. In Souls Mode that is Ember Wings,
## from a keeper; each cache there holds an Ember Shard (one more swallow in
## the flask). In Battle Royale everyone can double jump, and the caches
## hold Embers and a rare gun.
##
## Every column is measured against the real movement: the highest ground a
## player could stand on beside it, the single jump with the ledge-grab (and
## the feather talisman), the double jump. A column one jump can reach, or a
## double jump cannot, fails the audit (see audit()).

const COUNT := 14
## Top of the column above the highest ground beside it.
const RISE := 3.45
const RADIUS := 1.25
const MANTLE_REACH := 2.05

var game: Node
var shelves: Array = []
var _rng := RandomNumberGenerator.new()


static func apex(v: float) -> float:
	return v * v / (2.0 * Player.GRAVITY)


## Highest a top surface can be above where you stand and still be reached.
static func single_reach(feather := true) -> float:
	var v := Player.JUMP * (1.16 if feather else 1.0)
	return apex(v) + MANTLE_REACH


static func double_reach(feather := false) -> float:
	var v := Player.JUMP * (1.16 if feather else 1.0)
	return apex(v) * 2.0 + MANTLE_REACH


func build(p_game: Node, seed_value: int) -> void:
	game = p_game
	_rng.seed = seed_value + 4242
	var terrain: Terrain = game.terrain
	var tries := 0
	while shelves.size() < COUNT and tries < 2000:
		tries += 1
		var p := terrain.random_land_point(_rng, Terrain.WATER_LEVEL + 3.0, 0.22)
		if game.world.villages.house_at(p, 30.0).size() > 0:
			continue
		var near_town := false
		for v in game.world.villages.village_pads:
			if (v.center as Vector2).distance_to(p) < float(v.radius) + 30.0:
				near_town = true
				break
		if near_town:
			continue
		var clash := false
		for s in shelves:
			if Vector2((s.pos as Vector3).x, (s.pos as Vector3).z).distance_to(p) < 260.0:
				clash = true
				break
		if clash:
			continue
		var base := Vector3(p.x, terrain.height_at(p.x, p.y), p.y)
		var stand := _highest_beside(base, base.y + 12.0, null)
		if stand > base.y + 1.5:
			continue
		_place(base, stand)


## The highest surface a player could stand on within a few metres of the
## column (ground, rocks, roofs; not the column itself).
func _highest_beside(c: Vector3, from_y: float, exclude: CollisionObject3D) -> float:
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	var hi := -INF
	for ring: float in [RADIUS + 0.35, RADIUS + 1.2, RADIUS + 2.2, RADIUS + 3.2]:
		for k in 16:
			var a := TAU * float(k) / 16.0
			var o := c + Vector3(cos(a) * ring, 0.0, sin(a) * ring)
			var q := PhysicsRayQueryParameters3D.create(Vector3(o.x, from_y, o.z), Vector3(o.x, c.y - 20.0, o.z), 1)
			if exclude != null:
				q.exclude = [exclude.get_rid()]
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				hi = maxf(hi, (hit.position as Vector3).y)
	return hi


func _place(base: Vector3, stand: float) -> void:
	var top := stand + RISE
	var h := top - (base.y - 0.6)
	var body := StaticBody3D.new()
	body.name = "SkyLedge"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	body.global_position = Vector3(base.x, base.y - 0.6, base.z)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = RADIUS
	cyl.height = h
	cs.shape = cyl
	cs.position.y = h * 0.5
	body.add_child(cs)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.13, 0.12, 0.12)
	stone.roughness = 0.85
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = RADIUS
	cm.bottom_radius = RADIUS * 1.15
	cm.height = h
	cm.radial_segments = 7
	cm.rings = 2
	mi.mesh = cm
	mi.material_override = stone
	mi.position.y = h * 0.5
	body.add_child(mi)
	# Glowing veins up the column, so it is seen from afar.
	var vein := StandardMaterial3D.new()
	vein.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	vein.albedo_color = Color(1.0, 0.55, 0.2)
	vein.emission_enabled = true
	vein.emission = Color(1.0, 0.45, 0.12)
	vein.emission_energy_multiplier = 3.0
	for k in 3:
		var a := TAU * float(k) / 3.0 + 0.4
		var v := MeshInstance3D.new()
		var vb := BoxMesh.new()
		vb.size = Vector3(0.06, h * 0.75, 0.04)
		v.mesh = vb
		v.material_override = vein
		v.position = Vector3(cos(a) * RADIUS * 1.04, h * 0.45, sin(a) * RADIUS * 1.04)
		v.rotation.y = -a
		v.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(v)
	# The cache on top: a brazier of embers.
	var cache := Node3D.new()
	body.add_child(cache)
	cache.position.y = h
	var bowl := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.35
	bm.bottom_radius = 0.2
	bm.height = 0.3
	bowl.mesh = bm
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.2, 0.18, 0.16)
	iron.metallic = 0.6
	bowl.material_override = iron
	bowl.position.y = 0.15
	cache.add_child(bowl)
	var coal := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.26
	sm.height = 0.3
	coal.mesh = sm
	coal.material_override = vein
	coal.position.y = 0.32
	cache.add_child(coal)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.25)
	light.light_energy = 2.2
	light.omni_range = 7.0
	light.position.y = 0.8
	light.distance_fade_enabled = true
	light.distance_fade_begin = 120.0
	cache.add_child(light)
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	var ash := SphereShape3D.new()
	ash.radius = 1.4
	var acs := CollisionShape3D.new()
	acs.shape = ash
	area.add_child(acs)
	area.position.y = 0.9
	cache.add_child(area)
	var idx := shelves.size()
	area.body_entered.connect(func(b: Node3D): _take(idx, b))
	shelves.append({"pos": Vector3(base.x, top, base.z), "stand": stand, "top": top, "body": body, "cache": cache, "taken": false})


func _take(i: int, who: Node3D) -> void:
	if i >= shelves.size() or who != game.player:
		return
	var s: Dictionary = shelves[i]
	if bool(s.taken):
		return
	s.taken = true
	(s.cache as Node3D).visible = false
	if game.souls_mode:
		game.player.flask_max = mini(game.player.flask_max + 1, 6)
		game.player.flask = game.player.flask_max
		game.player.inventory_changed.emit()
		game.hud.show_big("EMBER SHARD", Color(1.0, 0.78, 0.4), 2.6)
		game.hud.show_notice("THE FLASK HOLDS ONE MORE SWALLOW  (%d)" % game.player.flask_max, 4.0)
	else:
		if game.writs != null:
			game.writs.award(0, 250, "SKY LEDGE")
		game.drop_weapon(["axmc", "lmg", "m24", "autoshotgun"][i % 4], -1, 30, (s.pos as Vector3) + Vector3.UP * 0.5)
		game.hud.show_notice("THE EMBER CACHE  —  250 EMBERS AND A RARE GUN", 3.0)
	game.sfx.play_ui("writ_done", -2.0)


## Near a ledge you cannot reach yet: say what it needs.
func hint_for(p: Vector3, has_double: bool) -> String:
	if has_double:
		return ""
	for s in shelves:
		if bool(s.taken):
			continue
		var c: Vector3 = s.pos
		if Vector2(c.x - p.x, c.z - p.z).length() < 6.0:
			return "A LEDGE TOO HIGH TO REACH  —  YOU NEED A SECOND JUMP (EMBER WINGS, FROM THE BELLKEEPER)"
	return ""


## Measures every ledge against the real movement. Returns
## [[position, need, single, double, ok], ...].
func audit() -> Array:
	var out: Array = []
	var s1 := single_reach(true)
	var s2 := double_reach(false)
	for s in shelves:
		var c: Vector3 = s.pos
		var stand := _highest_beside(Vector3(c.x, c.y - RISE, c.z), (s.top as float) + 6.0, s.body as CollisionObject3D)
		var need := (s.top as float) - stand
		var ok := need > s1 + 0.08 and need < s2 - 0.05
		out.append([c, need, s1, s2, ok])
	return out
