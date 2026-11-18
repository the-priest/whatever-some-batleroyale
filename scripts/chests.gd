class_name Chests
extends Node
## Treasure chests in the ruins and by the landmarks. Press F to open one:
## most hold a decent find. About one in three is a Mimic. It bites whoever
## opens it, wakes, and lashes out at anyone who comes within reach; shoot it
## apart from a distance and it gives up a hoard and a Gift.
##
## Every machine builds the same chests; the host decides which are Mimics
## (afresh each match) and settles every open and every hit.

const MIMIC_CHANCE := 0.34
const OPEN_RANGE := 2.2
const BITE := 55.0
const LASH := 32.0
const LASH_RANGE := 5.0
const LASH_EVERY := 1.4
const MIMIC_HP := 100.0
## A Mimic takes this share of what a bullet does (so it holds ~600).
const MIMIC_TAKEN := 0.17
const GOOD_GUNS := ["dmr", "m24", "carbine", "bullpup", "rifle", "lmg"]
const HOARD_GUNS := ["sniper", "axmc", "lmg", "m24"]

var game: Node
var spots: Array = []
## Per chest: "shut", "open", "awake", "dead".
var state: Array[String] = []
var _mimic: Array[bool] = []
var _hp: Array[float] = []
var _lash_t: Array[float] = []
var _nodes: Array[Node3D] = []
var _lids: Array[Node3D] = []
var _teeth: Array[Node3D] = []


func setup(p_game: Node) -> void:
	game = p_game
	spots = game.world.villages.chest_spots
	for i in spots.size():
		state.append("shut")
		_mimic.append(false)
		_hp.append(MIMIC_HP)
		_lash_t.append(0.0)
		_build(i)


## A new match: everything shut again; the host picks the Mimics.
func reset() -> void:
	for i in spots.size():
		state[i] = "shut"
		_hp[i] = MIMIC_HP
		_mimic[i] = false
		_show(i)
	if game == null or game.net_is_client():
		return
	for i in spots.size():
		_mimic[i] = randf() < MIMIC_CHANCE


func chest_near(p: Vector3) -> int:
	for i in spots.size():
		if state[i] != "shut":
			continue
		var sp: Vector3 = spots[i].pos
		if Vector2(p.x - sp.x, p.z - sp.z).length() < OPEN_RANGE and absf(p.y - sp.y) < 2.0:
			return i
	return -1


func prompt(p: Vector3) -> String:
	if chest_near(p) >= 0:
		return "[%s]  OPEN THE CHEST" % Keybinds.key("interact")
	return ""


func interact(p: Vector3) -> bool:
	var i := chest_near(p)
	if i < 0:
		return false
	if game.net_is_client():
		game.net.send_chest(i, "open", 0.0)
	else:
		open_on(0, i)
	return true


# ------------------------------------------------------------------ host --

func _owner_node(o: int) -> Node3D:
	if o == 0:
		return game.player
	var h = game.humans.get(o)
	return h if h != null and is_instance_valid(h) else null


func open_on(o: int, i: int) -> void:
	if i < 0 or i >= spots.size() or state[i] != "shut":
		return
	var who := _owner_node(o)
	if who == null or (who as Node3D).global_position.distance_to(spots[i].pos) > OPEN_RANGE + 2.0:
		return
	if _mimic[i]:
		_set_state(i, "awake")
		who.take_damage(BITE, (spots[i].pos as Vector3) + Vector3.UP * 0.6, false, null)
		_lash_t[i] = LASH_EVERY
		if o == 0:
			tell_mimic()
		elif game.net_on():
			game.net.send_writ_event(o, {"ev": "mimic"})
		return
	_set_state(i, "open")
	var base: Vector3 = spots[i].pos
	var gun: String = GOOD_GUNS[randi() % GOOD_GUNS.size()] if randf() < 0.35 else game._weighted_weapon()
	var extra: Array = [["med", ""], ["bandage", ""], ["energy", ""]][randi() % 3]
	var items: Array = [["weapon", gun], ["ammo", Weapons.caliber(gun)], extra]
	if randf() < 0.5:
		items.append(["armor", "2"])
	for k in items.size():
		var it: Array = items[k]
		var a := TAU * float(k) / float(items.size())
		var at: Vector3 = game.ground_at(base + Vector3(cos(a) * 1.1, 1.0, sin(a) * 1.1)) + Vector3.UP * 0.08
		game._spawn_loot(str(it[0]), str(it[1]), at)
	game.writs.award(o, 100, "CHEST")


## Host: a bullet (or a blast) hit Mimic `i`.
func hit_on(i: int, dmg: float, source: Node) -> void:
	if i < 0 or i >= spots.size() or state[i] != "awake":
		return
	_hp[i] -= dmg * MIMIC_TAKEN
	if _hp[i] > 0.0:
		return
	_set_state(i, "dead")
	var base: Vector3 = spots[i].pos
	game.spawn_explosion(base + Vector3.UP * 0.5)
	var gun: String = HOARD_GUNS[randi() % HOARD_GUNS.size()]
	var items: Array = [["weapon", gun], ["ammo", Weapons.caliber(gun)], ["armor", "3"], ["helmet", "3"], ["med", ""], ["med", ""]]
	for k in items.size():
		var a := TAU * float(k) / float(items.size())
		var at: Vector3 = game.ground_at(base + Vector3(cos(a) * 1.4, 1.0, sin(a) * 1.4)) + Vector3.UP * 0.08
		game._spawn_loot(items[k][0], items[k][1], at)
	var ko := -1
	if source == game.player:
		ko = 0
	elif source is Bot and is_instance_valid(source) and (source as Bot).is_human:
		ko = (source as Bot).peer_id
	if ko >= 0:
		game.writs.award(ko, 600, "MIMIC SLAIN")
		game.writs.give_gift(ko)


func _physics_process(delta: float) -> void:
	if game == null or game.net_is_client() or game.phase != "playing":
		return
	for i in spots.size():
		if state[i] != "awake":
			continue
		_lash_t[i] -= delta
		if _lash_t[i] > 0.0:
			continue
		_lash_t[i] = LASH_EVERY
		var base: Vector3 = spots[i].pos
		var targets: Array = []
		if game.player != null and game.player.alive:
			targets.append(game.player)
		for id in game.humans:
			var h = game.humans[id]
			if h != null and is_instance_valid(h) and (h as Bot).alive:
				targets.append(h)
		for b in game.bots:
			if is_instance_valid(b) and b.alive and b.state == Bot.State.GROUND and not (b is Revenant) and b.global_position.distance_to(base) < LASH_RANGE:
				targets.append(b)
		for t in targets:
			if (t as Node3D).global_position.distance_to(base) < LASH_RANGE:
				t.take_damage(LASH, base + Vector3.UP * 0.6, false, null)
				game.play_sfx_at("hit_flesh", base, 2.0)


func _set_state(i: int, st: String) -> void:
	state[i] = st
	_show(i)
	if game.net_on() and game.net.hosting:
		for pid in game.net.roster:
			if int(pid) != 1:
				game.net.send_writ_event(int(pid), {"ev": "chest", "i": i, "st": st})


## Everyone: a chest changed (from the host).
func apply_state(i: int, st: String) -> void:
	if i >= 0 and i < state.size():
		state[i] = st
		_show(i)


func tell_mimic() -> void:
	game.sfx.play_ui("writ_fail", -2.0)
	game.hud.show_big("A MIMIC!", HUD.DANGER, 2.2)
	game.hud.show_notice("IT BIT YOU  —  BACK OFF AND SHOOT IT APART FOR ITS HOARD", 3.0)
	game.shake(18.0)


# ---------------------------------------------------------------- looks --

func _mat(c: Color, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)


## A banded wooden chest; its lid on a hinge; teeth and a tongue hidden
## inside it, for the ones that are not chests.
func _build(i: int) -> void:
	var sp: Dictionary = spots[i]
	var root := ChestBody.new()
	root.chests = self
	root.index = i
	game.world.add_child(root)
	root.global_transform = Transform3D(Basis(Vector3.UP, float(sp.yaw)), sp.pos)
	var wood := _mat(Color(0.42, 0.27, 0.15))
	var iron := _mat(Color(0.2, 0.2, 0.21))
	iron.metallic = 0.6
	var gold := _mat(Color(0.85, 0.65, 0.25), 0.4)
	gold.metallic = 0.8
	var body := Node3D.new()
	root.add_child(body)
	_box(body, Vector3(1.1, 0.55, 0.7), Vector3(0, 0.3, 0), wood)
	for x: float in [-0.42, 0.42]:
		_box(body, Vector3(0.07, 0.58, 0.74), Vector3(x, 0.3, 0), iron)
	_box(body, Vector3(0.16, 0.16, 0.04), Vector3(0, 0.46, 0.37), gold)
	MeshMerge.merge(body, [])
	var hinge := Node3D.new()
	hinge.position = Vector3(0, 0.58, -0.35)
	root.add_child(hinge)
	_box(hinge, Vector3(1.1, 0.2, 0.7), Vector3(0, 0.1, 0.35), wood)
	for x: float in [-0.42, 0.42]:
		_box(hinge, Vector3(0.07, 0.22, 0.74), Vector3(x, 0.1, 0.35), iron)
	MeshMerge.merge(hinge, [])
	var teeth := Node3D.new()
	root.add_child(teeth)
	var tooth := _mat(Color(0.92, 0.9, 0.82))
	for k in 7:
		var x := -0.45 + 0.15 * float(k)
		_box(teeth, Vector3(0.06, 0.16, 0.04), Vector3(x, 0.62, 0.33), tooth, Vector3(0, 0, PI * 0.25))
		_box(teeth, Vector3(0.06, 0.14, 0.04), Vector3(x + 0.07, 0.62, -0.31), tooth, Vector3(0, 0, PI * 0.25))
	_box(teeth, Vector3(0.22, 0.05, 0.9), Vector3(0, 0.6, 0.55), _mat(Color(0.7, 0.1, 0.12)), Vector3(-0.5, 0, 0))
	_box(teeth, Vector3(0.12, 0.06, 0.04), Vector3(-0.2, 0.75, 0.3), _mat(Color(1.0, 0.2, 0.1), 4.0))
	_box(teeth, Vector3(0.12, 0.06, 0.04), Vector3(0.2, 0.75, 0.3), _mat(Color(1.0, 0.2, 0.1), 4.0))
	MeshMerge.merge(teeth, [])
	teeth.visible = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.1, 0.8, 0.75)
	cs.shape = bs
	cs.position = Vector3(0, 0.4, 0)
	root.add_child(cs)
	for c in root.find_children("*", "GeometryInstance3D", true, false):
		(c as GeometryInstance3D).visibility_range_end = 140.0
	_nodes.append(root)
	_lids.append(hinge)
	_teeth.append(teeth)


func _show(i: int) -> void:
	if i >= _nodes.size():
		return
	var st := state[i]
	var lid := _lids[i]
	match st:
		"shut":
			lid.rotation.x = 0.0
			_teeth[i].visible = false
			_nodes[i].visible = true
		"open":
			var tw := lid.create_tween()
			tw.tween_property(lid, "rotation:x", -1.9, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		"awake":
			_teeth[i].visible = true
			var tw := lid.create_tween()
			tw.tween_property(lid, "rotation:x", -1.1, 0.12)
			tw.tween_property(lid, "rotation:x", -0.6, 0.35).set_trans(Tween.TRANS_SINE)
			game.play_sfx_at("hit_flesh", spots[i].pos, 6.0)
		"dead":
			_teeth[i].visible = false
			lid.rotation.x = -2.3
