class_name Ordeal
extends Node
## THE ORDEAL: the island's bosses, one bout after another, in a ring of
## standing stones. No soldiers, no storm, no loot from the fallen. Health
## carries from bout to bout (a little comes back after each); after every
## bout three altars rise and you take one Gift of the three for the rest of
## the Ordeal. Fall and it is over. Solo only.
##
## The best bout reached and the fastest full Ordeal are kept in the profile.

const R := 34.0
const REST := 5.0
const BREATH := 30.0
const PATH := "user://profile.cfg"
## Each bout: a name, and the foes in it.
const BOUTS := [
	["THE FIRST BOUT", ["revenant"]],
	["THE KEEPER", ["warden"]],
	["THE GIANT", ["colossus"]],
	["THE TOLLING", ["bell"]],
	["THE WYRM BENEATH", ["wyrm"]],
	["THE CARRION QUEEN", ["carrion"]],
	["THE LANTERN WITCH", ["witch"]],
	["THE TWIN OATHS", ["revenant", "revenant"]],
	["THE SECOND GIANT", ["colossus"]],
	["THE ASHEN CHOIR", ["warden", "colossus"]],
]
## Bindings: handicaps sworn before an Ordeal. [id, name, what it does]
const BINDINGS := [
	["flesh", "BINDING OF FLESH", "No armour, no helmet"],
	["breath", "BINDING OF BREATH", "No health back between bouts"],
	["want", "BINDING OF WANT", "No Gifts from the altars"],
	["arms", "BINDING OF ARMS", "A sidearm and nothing more"],
]
## The Hall of Echoes: every kind of boss, to be fought again alone once
## slain. [kind, name]
const ECHOES := [
	["revenant", "A REVENANT"], ["warden", "THE HOLLOW WARDEN"], ["colossus", "A COLOSSUS"],
	["bell", "MOURNE, THE BELLKEEPER"], ["wyrm", "SKARN, THE WYRM BENEATH"],
	["carrion", "VESPERA, THE CARRION QUEEN"], ["witch", "ISOLDE, THE LANTERN WITCH"],
	["unkindled", "THE UNKINDLED"],
]
## The hidden bout, for those who have endured the Ordeal before.
const SECRET := ["THE UNKINDLED", ["unkindled"]]
## Gifts no use in the ring.
const NO_GIFTS := ["storm", "hawk"]

var game: Node
var centre := Vector3.ZERO
var bout := -1
## "rest", "fight", "choose", "done", "fallen"
var state := "rest"
var foes: Array = []
var time := 0.0
var _rest_t := 0.0
var _hold_t := 0.0
var _altars: Array = []
var _root: Node3D
var _used_rev: Array = []
var _used_giant: Array = []
var _floor_lo := 0.0
var secret_open := false
## The Hall of Echoes: one boss of this kind, alone ("" = the Ordeal).
var echo := ""
## Seven endured this run (the hidden bout may follow).
var endured_run := false
var _hud_t := 0.0

static var best_bout := 0
static var best_time := 0.0
## The most bindings an Ordeal has been endured under.
static var best_bound := 0
## The Unkindled has been slain (ever).
static var unkindled_slain := false
## Kinds of boss slain by your hand (ever) -> best echo time (0: none yet).
static var slain: Dictionary = {}
static var bound: Dictionary = {}
static var _loaded := false
## Headless checks run the Ordeal without touching the player's records.
static var no_save := false


static func load_record() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	best_bout = int(cfg.get_value("ordeal", "best_bout", 0))
	best_time = float(cfg.get_value("ordeal", "best_time", 0.0))
	best_bound = int(cfg.get_value("ordeal", "best_bound", 0))
	unkindled_slain = bool(cfg.get_value("ordeal", "unkindled", false))
	for e in ECHOES:
		if cfg.has_section_key("echoes", e[0]):
			slain[e[0]] = float(cfg.get_value("echoes", e[0], 0.0))
	for b in BINDINGS:
		if bool(cfg.get_value("ordeal_bind", b[0], false)):
			bound[b[0]] = true


static func save_record() -> void:
	if no_save:
		return
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("ordeal", "best_bout", best_bout)
	cfg.set_value("ordeal", "best_time", best_time)
	cfg.set_value("ordeal", "best_bound", best_bound)
	cfg.set_value("ordeal", "unkindled", unkindled_slain)
	for k in slain:
		cfg.set_value("echoes", k, float(slain[k]))
	cfg.save(PATH)


## The bindings are kept whatever the tests do (they are the player's choice).
static func save_bindings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	for b in BINDINGS:
		cfg.set_value("ordeal_bind", b[0], bound.has(b[0]))
	cfg.save(PATH)


## What kind of boss `b` is (for the Hall of Echoes).
static func kind_of(b: Node) -> String:
	if b is Unkindled:
		return "unkindled"
	if b is Colossus:
		return "colossus"
	if b is HollowWarden:
		return "warden"
	if b is Bellkeeper:
		return "bell"
	if b is Wyrm:
		return "wyrm"
	if b is Carrion:
		return "carrion"
	if b is LanternWitch:
		return "witch"
	return "revenant"


## A boss of this kind fell to your hand: its echo waits in the Hall.
static func mark_slain(kind: String) -> void:
	load_record()
	if slain.has(kind):
		return
	slain[kind] = 0.0
	save_record()


static func echo_name(kind: String) -> String:
	for e in ECHOES:
		if e[0] == kind:
			return str(e[1])
	return kind.to_upper()


static func is_bound(id: String) -> bool:
	return bound.has(id)


static func record_line() -> String:
	load_record()
	var tail := ""
	if bound.size() > 0:
		tail = "   ·   %d BINDING%s SWORN" % [bound.size(), "" if bound.size() == 1 else "S"]
	return _record_head() + tail


static func _record_head() -> String:
	if best_bout <= 0:
		return "%d BOUTS  ·  NO REST  ·  ONE GIFT AFTER EACH" % BOUTS.size()
	if unkindled_slain:
		return "THE UNKINDLED SLAIN  ·  BEST TIME %s%s" % [_clock(best_time), ("  ·  MOST BOUND %d" % best_bound) if best_bound > 0 else ""]
	if best_bout >= BOUTS.size() and best_time > 0.0:
		return "ENDURED  ·  BEST TIME %s%s" % [_clock(best_time), ("  ·  MOST BOUND %d" % best_bound) if best_bound > 0 else ""]
	return "BEST: BOUT %d OF %d" % [best_bout, BOUTS.size()]


static func _clock(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


func setup(p_game: Node) -> void:
	game = p_game
	# After the foes each frame, so what it tells them sticks.
	process_physics_priority = 100
	load_record()
	centre = _find_ground()
	_build()


## Open, level ground away from the towns, the Hollow and the water, with as
## few trees as can be found.
func _find_ground() -> Vector3:
	var terrain: Terrain = game.terrain
	var best := Vector3.INF
	var best_score := INF
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	for k in 400:
		var q := Vector2(randf_range(-Terrain.HALF * 0.7, Terrain.HALF * 0.7), randf_range(-Terrain.HALF * 0.7, Terrain.HALF * 0.7))
		var h := terrain.height_at(q.x, q.y)
		if h < terrain.water_surface_at(q.x, q.y) + 3.0 or terrain.slope_at(q.x, q.y) > 0.2:
			continue
		var near_town := false
		for v in game.world.villages.village_pads:
			if (v.center as Vector2).distance_to(q) < float(v.radius) + R + 50.0:
				near_town = true
				break
		for pp in game.world.villages.poi_pads:
			if (pp.center as Vector2).distance_to(q) < R + 25.0:
				near_town = true
				break
		if near_town or not game.world.villages.house_at(q, R + 10.0).is_empty():
			continue
		if game.hollow != null and game.hollow.active() and Vector2(game.hollow.data.c.x, game.hollow.data.c.z).distance_to(q) < 160.0:
			continue
		var lo := h
		var hi := h
		var wet := false
		for j in 12:
			var a := TAU * float(j) / 12.0
			var e := q + Vector2(cos(a), sin(a)) * R
			var eh := terrain.height_at(e.x, e.y)
			lo = minf(lo, eh)
			hi = maxf(hi, eh)
			if eh < terrain.water_surface_at(e.x, e.y) + 0.5:
				wet = true
		if wet or hi - lo > 7.0:
			continue
		var wood := 0.0
		for j in 9:
			var a2 := TAU * float(j) / 9.0
			var e2 := q + Vector2(cos(a2), sin(a2)) * R * 0.6 * float(j % 3) * 0.5
			wood += terrain.forest_density(e2.x, e2.y)
		wood /= 9.0
		var g := Vector3(q.x, h, q.y)
		var blocked := 0
		for j in 16:
			var a := TAU * float(j) / 16.0
			var o := g + Vector3.UP * 1.6
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(o, o + Vector3(cos(a), 0.0, sin(a)) * (R - 2.0), 1))
			if not hit.is_empty():
				blocked += 1
		var score := float(blocked) * 3.0 + (hi - lo) + wood * 30.0
		if score < best_score:
			best_score = score
			best = g
	if best == Vector3.INF:
		best = game.ground_at(Vector3(0, 300, 0))
	# The floor of the ring: level, a hand above the highest ground in it.
	var top := best.y
	_floor_lo = best.y
	for j in 24:
		for rr: float in [0.35, 0.7, 1.0]:
			var a := TAU * float(j) / 24.0
			var e := Vector2(best.x, best.z) + Vector2(cos(a), sin(a)) * (R + 2.0) * rr
			var eh := terrain.height_at(e.x, e.y)
			top = maxf(top, eh)
			_floor_lo = minf(_floor_lo, eh)
	return Vector3(best.x, top + 0.6, best.z)


func _build() -> void:
	# The ring is cleared of trees for as long as the Ordeal lasts.
	var cut: int = game.world.hide_trees(centre, R + 4.0)
	print("[ordeal] ring at %s, %d trees cleared" % [str(centre.round()), cut])
	_root = Node3D.new()
	_root.name = "OrdealRing"
	game.world.add_child(_root)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.32, 0.3, 0.29)
	stone.roughness = 0.9
	var fire := StandardMaterial3D.new()
	fire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire.albedo_color = Color(1.0, 0.55, 0.2)
	fire.emission_enabled = true
	fire.emission = Color(1.0, 0.45, 0.15)
	fire.emission_energy_multiplier = 4.0
	# The floor: a great round of fitted stone, level, with a ring inlaid.
	var tex = load("res://assets/textures/tex_rock.png")
	var floor_m := StandardMaterial3D.new()
	floor_m.albedo_color = Color(0.62, 0.6, 0.58)
	if tex != null:
		floor_m.albedo_texture = tex
		floor_m.uv1_triplanar = true
		floor_m.uv1_world_triplanar = true
		floor_m.uv1_scale = Vector3(0.12, 0.12, 0.12)
	floor_m.roughness = 0.95
	var depth := centre.y - _floor_lo + 1.5
	var fl := StaticBody3D.new()
	_root.add_child(fl)
	fl.global_position = centre - Vector3(0, depth * 0.5, 0)
	var fmi := MeshInstance3D.new()
	var fcm := CylinderMesh.new()
	fcm.top_radius = R + 2.5
	fcm.bottom_radius = R + 3.2
	fcm.height = depth
	fcm.radial_segments = 64
	fcm.rings = 1
	fmi.mesh = fcm
	fmi.material_override = floor_m
	fl.add_child(fmi)
	var fcs := CollisionShape3D.new()
	var fcy := CylinderShape3D.new()
	fcy.radius = R + 2.5
	fcy.height = depth
	fcs.shape = fcy
	fl.add_child(fcs)
	var inlay := StandardMaterial3D.new()
	inlay.albedo_color = Color(0.2, 0.18, 0.17)
	inlay.roughness = 0.8
	for rr: float in [R * 0.32, R * 0.7]:
		var im := MeshInstance3D.new()
		var it := TorusMesh.new()
		it.inner_radius = rr - 0.3
		it.outer_radius = rr + 0.3
		it.rings = 64
		it.ring_segments = 4
		im.mesh = it
		im.material_override = inlay
		im.scale = Vector3(1, 0.06, 1)
		im.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(im)
		im.global_position = centre + Vector3.UP * 0.01
	var n := 20
	for k in n:
		var a := TAU * float(k) / float(n)
		var p := centre + Vector3(cos(a), 0.0, sin(a)) * (R + 1.5)
		var g := p
		var ph := 6.0 + float(k % 3) * 1.4
		var body := StaticBody3D.new()
		_root.add_child(body)
		body.global_position = g
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.7, ph + 2.0, 1.7)
		mi.mesh = bm
		mi.material_override = stone
		mi.position = Vector3(0, ph * 0.5 - 1.0, 0)
		mi.rotation.y = -a
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = bm.size
		cs.shape = bs
		cs.position = mi.position
		cs.rotation = mi.rotation
		body.add_child(cs)
		if true:
			var f := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.35
			sm.height = 0.9
			sm.radial_segments = 8
			sm.rings = 4
			f.mesh = sm
			f.material_override = fire
			f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			f.position = Vector3(0, ph + 1.4, 0)
			body.add_child(f)
		if k % 5 == 0:
			var lt := OmniLight3D.new()
			lt.light_color = Color(1.0, 0.6, 0.3)
			lt.light_energy = 2.5
			lt.omni_range = 18.0
			lt.shadow_enabled = false
			lt.position = Vector3(0, ph + 1.6, 0)
			body.add_child(lt)
	# A line of embers on the ground: the edge of the ring.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = R - 0.25
	tm.outer_radius = R + 0.25
	tm.rings = 96
	tm.ring_segments = 4
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(1.0, 0.45, 0.15, 0.85)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(1, 0.3, 1)
	_root.add_child(ring)
	ring.global_position = centre + Vector3.UP * 0.05


func cleanup() -> void:
	_clear_altars()
	if game != null and game.world != null and in_secret():
		_set_dark(-1.0)
	if game != null and game.world != null:
		game.world.restore_trees()
	if _root != null and is_instance_valid(_root):
		_root.queue_free()


## The player stands in the ring: the first bout after a short breath.
func begin() -> void:
	bout = -1
	time = 0.0
	# Those who have endured it once find something more waiting at its end.
	secret_open = best_time > 0.0 and echo == ""
	_next_bout()


func n_bouts() -> int:
	return 1 if echo != "" else BOUTS.size()


## The bout `i`: one of the seven, or the hidden one after them.
func bout_def(i: int) -> Array:
	if echo != "":
		return [echo_name(echo), [echo]]
	return BOUTS[i] if i < BOUTS.size() else SECRET


func in_secret() -> bool:
	return echo == "" and bout >= BOUTS.size()


func _next_bout() -> void:
	bout += 1
	if bout > n_bouts() or (bout == n_bouts() and not secret_open):
		_endured()
		return
	state = "rest"
	_rest_t = REST
	var b: Array = bout_def(bout)
	if in_secret():
		_rest_t = REST + 2.0
		game.hud.show_big("THE STONES DO NOT OPEN", Color(0.7, 0.8, 1.0), 3.0)
		game.hud.show_notice("SOMETHING KNELT HERE BEFORE THE ORDEAL BEGAN  —  %s" % str(b[0]), 4.5)
		_set_dark(0.55)
	else:
		game.hud.show_big("BOUT %d  ·  %s" % [bout + 1, str(b[0])], Color(1.0, 0.7, 0.4), 3.0)
	game.sfx.play_ui("event_horn", -4.0)


func _spawn_bout() -> void:
	state = "fight"
	foes.clear()
	var kinds: Array = bout_def(bout)[1]
	for i in kinds.size():
		var a := TAU * float(i) / float(kinds.size()) + randf() * TAU
		var at: Vector3 = game.ground_at(centre + Vector3(cos(a), 0.0, sin(a)) * (R * 0.55) + Vector3.UP * 30.0)
		var f := _spawn(str(kinds[i]), at)
		if f != null:
			foes.append(f)
			game.spawn_smoke(at + Vector3.UP, 2.0)
	var names: Array = foes.map(func(f): return str(f.bot_name))
	game.hud.show_notice("  ·  ".join(names), 3.0)


func _spawn(kind: String, at: Vector3) -> Revenant:
	var f: Revenant = null
	match kind:
		"revenant":
			var pool: Array = Revenant.NAMES.filter(func(n): return not _used_rev.has(n[0]))
			if pool.is_empty():
				pool = Revenant.NAMES.duplicate()
			var nm: Array = pool[randi() % pool.size()]
			_used_rev.append(nm[0])
			var rv := Revenant.new()
			rv.setup_revenant(str(nm[0]), str(nm[1]), centre, game)
			f = rv
		"colossus":
			var gpool: Array = Colossus.GIANT_NAMES.filter(func(n): return not _used_giant.has(n[0]))
			if gpool.is_empty():
				gpool = Colossus.GIANT_NAMES.duplicate()
			var gn: Array = gpool[randi() % gpool.size()]
			_used_giant.append(gn[0])
			var cg := Colossus.new()
			cg.setup_colossus(str(gn[0]), str(gn[1]), centre, game)
			f = cg
		"bell":
			var bk := Bellkeeper.new()
			bk.setup_bell(centre, game)
			f = bk
		"witch":
			var lw := LanternWitch.new()
			lw.setup_witch(centre, game)
			f = lw
		"carrion":
			var cr := Carrion.new()
			cr.setup_carrion(centre, game)
			f = cr
		"wyrm":
			var wy := Wyrm.new()
			wy.setup_wyrm(centre, game)
			f = wy
		"unkindled":
			var uk := Unkindled.new()
			uk.setup_unkindled(centre, game)
			f = uk
		"warden":
			var wd := HollowWarden.new()
			wd.setup_warden(centre, game)
			f = wd
	if f == null:
		return null
	f.leash = R + 10.0
	game.add_child(f)
	f.global_position = at + Vector3.UP * 0.4
	if f is Colossus:
		f.arm_weapon("lmg")
	elif f is Unkindled:
		f.arm_weapon("axmc")
	elif f is Bellkeeper or f is LanternWitch:
		f.arm_weapon("dmr")
	elif f is HollowWarden:
		f.arm_weapon("dmr")
		(f as HollowWarden).wake()
	else:
		f.arm_weapon(game.REVENANT_GUNS[randi() % game.REVENANT_GUNS.size()])
	f.enemy = game.player
	f.eliminated.connect(game._on_bot_eliminated)
	game.bots.append(f)
	return f


func _physics_process(delta: float) -> void:
	if game == null or game.phase != "playing" or state == "done" or state == "fallen":
		return
	var p: Player = game.player
	if p == null or not p.alive:
		return
	if state != "rest" or bout > 0:
		time += delta
	# Where you stand, in place of the count of the living.
	_hud_t -= delta
	if _hud_t <= 0.0 and game.hud.lbl_alive != null:
		_hud_t = 0.25
		if in_secret():
			game.hud.lbl_alive.text = "THE LAST BOUT   ·   %s" % _clock(time)
		else:
			if echo != "":
				game.hud.lbl_alive.text = "ECHO   ·   %s" % _clock(time)
			else:
				game.hud.lbl_alive.text = "BOUT %d / %d   ·   %s" % [clampi(bout + 1, 1, BOUTS.size()), BOUTS.size(), _clock(time)]
	# The ring holds you.
	var off := p.global_position - centre
	off.y = 0.0
	if off.length() > R + 0.5:
		p.velocity -= off.normalized() * 14.0 * delta * 10.0
		_hold_t -= delta
		if _hold_t <= 0.0:
			_hold_t = 0.5
			p.take_damage(4.0, Vector3.ZERO, false, null)
			game.hud.show_notice("THE RING HOLDS YOU  —  THERE IS NO WAY OUT BUT THROUGH", 1.0)
	match state:
		"rest":
			_rest_t -= delta
			if _rest_t <= 0.0:
				_spawn_bout()
		"fight":
			# They always know where you are: there is nowhere in the ring to hide.
			var any := false
			for f in foes:
				if is_instance_valid(f) and f.alive:
					f.enemy = p
					f.heard_pos = p.global_position
					f.alert_timer = maxf(f.alert_timer, 3.0)
					any = true
			if not any:
				_bout_won()


func _bout_won() -> void:
	var p: Player = game.player
	if not is_bound("breath"):
		p.hp = minf(p.max_hp(), p.hp + BREATH)
		p._emit_health()
		# A swallow of fire back in the flask.
		p.flask = mini(p.flask_max, p.flask + 1)
	for i in p.loadout.size():
		var w: String = str(p.loadout[i])
		if w != "":
			p.add_ammo_cal(Weapons.caliber(w), int(Weapons.AMMO_BOX.get(Weapons.caliber(w), 30)) * 2)
	p.inventory_changed.emit()
	if echo != "":
		var prev := float(slain.get(echo, 0.0))
		if prev <= 0.0 or time < prev:
			slain[echo] = time
		save_record()
		state = "done"
		game.ordeal_endured()
		return
	if bout + 1 > best_bout and not in_secret():
		best_bout = bout + 1
		save_record()
	if in_secret():
		unkindled_slain = true
		_endured()
		return
	if bout + 1 >= BOUTS.size():
		_record_endured()
		if not secret_open:
			_endured()
			return
		# The seven are endured; the record is kept. Then the ring darkens.
		game.sfx.play_ui("writ_done", -3.0)
		game.hud.show_big("ALL %d BOUTS ENDURED" % BOUTS.size(), Color(1.0, 0.86, 0.45), 2.4)
		_next_bout()
		return
	game.sfx.play_ui("writ_done", -3.0)
	game.hud.show_big("BOUT %d WON" % (bout + 1), Color(1.0, 0.86, 0.45), 2.4)
	var offer := _offer()
	if offer.is_empty():
		_next_bout()
		return
	state = "choose"
	game.hud.show_notice("THREE ALTARS RISE  —  TAKE ONE GIFT  (%s, AMMO REFILLED)" % ("BOUND: NO BREATH" if is_bound("breath") else "+%d HEALTH" % int(BREATH)), 4.0)
	_raise_altars(offer)


func _offer() -> Array:
	if is_bound("want") or echo != "":
		return []
	var have: Dictionary = game.player.gifts
	var pool: Array = Writs.GIFTS.keys().filter(func(k): return not have.has(k) and not NO_GIFTS.has(k))
	pool.shuffle()
	return pool.slice(0, 3)


func _raise_altars(offer: Array) -> void:
	_clear_altars()
	var orb_m := StandardMaterial3D.new()
	orb_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	orb_m.albedo_color = Color(1.0, 0.85, 0.45)
	orb_m.emission_enabled = true
	orb_m.emission = Color(1.0, 0.75, 0.35)
	orb_m.emission_energy_multiplier = 3.0
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.36, 0.34, 0.32)
	var p: Vector3 = game.player.global_position
	var facing := centre - p
	facing.y = 0.0
	if facing.length() < 1.0:
		facing = Vector3.FORWARD
	var fw := facing.normalized()
	var side := Vector3(-fw.z, 0.0, fw.x)
	for i in offer.size():
		var at: Vector3 = game.ground_at(p + fw * 5.0 + side * (float(i) - float(offer.size() - 1) * 0.5) * 3.2 + Vector3.UP * 20.0)
		var node := Node3D.new()
		_root.add_child(node)
		node.global_position = at
		var plinth := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.45
		cm.bottom_radius = 0.6
		cm.height = 1.1
		cm.radial_segments = 8
		plinth.mesh = cm
		plinth.material_override = stone
		plinth.position = Vector3(0, 0.55, 0)
		node.add_child(plinth)
		var orb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.22
		sm.height = 0.44
		orb.mesh = sm
		orb.material_override = orb_m
		orb.position = Vector3(0, 1.45, 0)
		orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(orb)
		var lb := Label3D.new()
		lb.text = str(Writs.GIFTS[offer[i]][0])
		lb.font_size = 48
		lb.pixel_size = 0.006
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.modulate = Color(1.0, 0.88, 0.6)
		lb.outline_size = 10
		lb.position = Vector3(0, 2.0, 0)
		lb.no_depth_test = true
		node.add_child(lb)
		game.spawn_smoke(at + Vector3.UP * 0.5, 0.8)
		_altars.append({"node": node, "gift": offer[i], "pos": at})


func _clear_altars() -> void:
	for a in _altars:
		if is_instance_valid(a.node):
			(a.node as Node).queue_free()
	_altars.clear()


func _altar_near(pos: Vector3) -> int:
	for i in _altars.size():
		var ap: Vector3 = _altars[i].pos
		if Vector2(pos.x - ap.x, pos.z - ap.z).length() < 1.6:
			return i
	return -1


func prompt(pos: Vector3) -> String:
	if state != "choose":
		return ""
	var i := _altar_near(pos)
	if i < 0:
		return ""
	var g: Array = Writs.GIFTS[_altars[i].gift]
	return "[%s]  TAKE %s  —  %s" % [Keybinds.key("interact"), str(g[0]), str(g[1])]


func interact(pos: Vector3) -> bool:
	if state != "choose":
		return false
	var i := _altar_near(pos)
	if i < 0:
		return false
	var k: String = _altars[i].gift
	game.writs.give_gift_kind(0, k)
	_clear_altars()
	_next_bout()
	return true


func on_player_fell() -> void:
	if state == "done" or state == "fallen":
		return
	state = "fallen"
	_clear_altars()
	_set_dark(-1.0)
	if echo != "":
		return
	if bout > best_bout:
		best_bout = bout
		save_record()


## Text for the end screen.
func end_line() -> String:
	var bt := ("   ·   %d BOUND" % bound.size()) if bound.size() > 0 else ""
	if echo != "":
		var best := float(slain.get(echo, 0.0))
		if state == "done":
			return "%s  ·  %s   ·   BEST %s" % [echo_name(echo), _clock(time), _clock(best)]
		return "%s PREVAILS  ·  %s%s" % [echo_name(echo), _clock(time), ("   ·   BEST %s" % _clock(best)) if best > 0.0 else ""]
	if state == "done" and in_secret():
		return "THE UNKINDLED IS SLAIN  ·  %s%s" % [_clock(time), bt]
	if in_secret():
		return "ALL %d BOUTS ENDURED  ·  FELL TO THE UNKINDLED%s" % [BOUTS.size(), bt]
	if state == "done":
		return "ALL %d BOUTS  ·  %s   ·   BEST %s%s" % [BOUTS.size(), _clock(time), _clock(best_time), bt]
	return "FELL IN BOUT %d OF %d  ·  %s   ·   BEST: BOUT %d%s" % [bout + 1, BOUTS.size(), str(BOUTS[clampi(bout, 0, BOUTS.size() - 1)][0]), best_bout, bt]


## The seven are behind you: the time and the bindings are recorded.
func _record_endured() -> void:
	if endured_run:
		return
	endured_run = true
	best_bout = BOUTS.size()
	if best_time <= 0.0 or time < best_time:
		best_time = time
	best_bound = maxi(best_bound, bound.size())
	save_record()


func _endured() -> void:
	state = "done"
	_record_endured()
	save_record()
	_set_dark(-1.0)
	game.ordeal_endured()


## The ring darkens for the hidden bout (-1: as it was).
func _set_dark(k: float) -> void:
	if game.hollow != null:
		game.hollow.force_k = k
		if k < 0.0:
			game.hollow._k = 0.0
	game.world.set_hollow(maxf(k, 0.0))


## The Unkindled calls echoes of the Revenants into the ring.
func call_echoes(n: int) -> void:
	for i in n:
		var a := randf() * TAU
		var at: Vector3 = game.ground_at(centre + Vector3(cos(a), 0.0, sin(a)) * (R * 0.7) + Vector3.UP * 30.0)
		var f := _spawn("revenant", at)
		if f != null:
			f.set_meta("echo", true)
			foes.append(f)
			game.spawn_smoke(at + Vector3.UP, 2.0)
