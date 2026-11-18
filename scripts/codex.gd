class_name Codex
extends Node
## The Codex: twenty-four torn pages of the island's story, hidden in its
## ruins, by its landmarks and idols, in its vaults and up its towers. Read
## one (F) and it is yours for good: the pages you have found are kept in
## your profile and read again from the main menu (CODEX). A new page pays
## Renown.
##
## Pages are placed the same way on every machine (from the island's seed),
## and each player finds their own.

const RENOWN_PER_PAGE := 30
const READ_RANGE := 1.9
const PAGES := [
	["THE FIRST FIRE", "Before the storm there was a fire on this island that never went out. The fisher-folk fed it driftwood and their dead, and in return it kept the dark off the water. They called its light the Embers, and carried them home in clay pots."],
	["OF THE STORM", "The storm is not weather. It came the year the fire was stolen, a wall of violet cloud that walks inward a little more each day. Whatever it touches it unmakes. The old women say it is the fire's grief, looking for what was taken."],
	["WAYSHRINES", "When the great fire was lost, the keepers broke what was left into nine coals and hid them in stone shrines along the old roads. Trade at one and you feed it; feed it and it remembers you. That is all Kindling is: a shrine that remembers you."],
	["ON EMBERS", "Every death on this island gives back a little of the fire that made us. You will see it rise from the fallen like sparks from a log. Gather it, and spend it at the shrines. Hoard it, and lose it where you fall."],
	["THE WRIT-KEEPERS", "In every town there is a board where the living post their grievances: a debt, a murder, a lost heirloom. Sealed in red, gold or blue. Whoever settles a writ is paid in embers by the town, and nobody asks how it was settled."],
	["MAELIS", "Maelis kept the ash at Kingsbridge, sweeping the great fire's leavings into the river so it would not choke the town. When the fire was stolen she would not stop sweeping. She is still sweeping. She does not like to be interrupted."],
	["ORVEN", "Sir Orven held the bridge for nine days against the raiders who took the fire. On the tenth he held it against the storm. His armour is empty now, but it has not noticed. Do not cross it on the bridge."],
	["SERA VANE", "Sera sang the dead into their graves at Shimmerdeep. When the storm came there were too many dead and not enough songs, so she kept singing. If you hear a hymn among the crystals, you are already too close."],
	["THE IRON OATH", "Thrain swore on his forge that no stranger would take what was his. The forge went cold a hundred years ago. The oath did not. Revenants are only promises that would not end."],
	["THE PALE HUNTRESS", "Kessa hunted the hills above the falls with a bow her grandmother made. When her village burned she hunted the men who burned it. When they were gone she kept hunting. Anyone will do now."],
	["THE LAST CAPTAIN", "Dorian's ship brought the raiders and took the fire away. It sank in sight of Gull Point, and the sea gave him back alone. He has been trying to return the fire ever since. He does not remember that it went down with the ship."],
	["WHO WALKS IN SMOKE", "Velka was the fire's last keeper. She let it be stolen, and she has never stopped looking for it. When the moon turns red she leaves her hill and walks the island, smelling every soul for smoke."],
	["ABBOT GREL", "The abbot buried the drowned of the great storm in unconsecrated ground to save the labour. He was the first to rise. He has been digging ever since, trying to put them right."],
	["SIGILS", "Every Revenant carries a seal from the vault it swore to guard: a gold sigil warm as a coal. The vaults hold what the old town-lords hid from the raiders. Fell the guardian, take the seal, open the door. The dead will not need it."],
	["VARRA OF THE SWIFT WIND", "Varra was the wind that carried the fishing boats home. Kneel and she will lend you a little of it, as she lent it to them. She asks nothing back. The sea already took her people."],
	["OSK THE UNSHAKEN", "Osk was a mountain before he was a god, and a god before he was a stone. Pray to him and your hands will be still as rock. He was carved by men who needed steady hands for the harpoon."],
	["THE GREEN MOTHER", "Moss on the stone, moss on the dead, moss on the hearth. The Green Mother keeps what grows. She is older than the fire and will outlast the storm. Her blessing makes the blood slow to leave you."],
	["THE EMBER KING", "Some say the Ember King was the man who stole the fire, and that his idol was carved by those he paid. Kneel to him and death will pay you better. The fisher-folk spat when they passed his stone."],
	["BLOOD MOON", "Once in a long while the storm's light turns the moon red, and the soldiers of the island forget that they are men. They hunt in packs then, and the shrines pay double for what is spilled. Lock your doors. You have no doors."],
	["THE RELIQUARY", "The old town-lords sealed their gold in caskets and sent them up on the wind in balloons, meaning to fetch them back after the raiders left. The balloons still come down, now and then, gilded and heavy. Everyone sees them fall."],
	["THE LIGHTHOUSE", "Gull Point's lamp was lit from the great fire, and it still burns, though nobody has climbed the tower in a hundred years. The keepers say it will go out the day the fire is found. It has not gone out."],
	["THE GIANT TREE", "The great tree in the west was a sapling when the first fire was lit. A whole village lives in its branches now, and it is the only place on the island the storm has never reached. Not yet."],
	["THE SOLDIERS", "Nobody knows who the soldiers are. They come in the plane, as you did, sixty and more at a time, and they fight for the last patch of ground the storm leaves. Some say they are what is left of everyone who ever tried to take the fire."],
	["THE LAST PAGE", "The fire was never stolen. It was given away, a coal to each of us, and every one who falls on this island gives a little of it back. When the last of us stands alone in the eye of the storm, the fire is whole again. That is why you came. That is why we all came."],
]

static var found: Dictionary = {}
static var _loaded := false

var game: Node
## [{pos, page}] where each page lies on this island.
var spots: Array = []
var _nodes: Array[Node3D] = []
var reading := -1
var _panel: Control = null


static func load_found() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(Renown.PATH) != OK:
		return
	for i in PAGES.size():
		if bool(cfg.get_value("codex", str(i), false)):
			found[i] = true


static func save_found() -> void:
	var cfg := ConfigFile.new()
	cfg.load(Renown.PATH)
	for i in PAGES.size():
		cfg.set_value("codex", str(i), found.has(i))
	cfg.save(Renown.PATH)


func setup(p_game: Node) -> void:
	game = p_game
	load_found()
	spots = game.world.villages.codex_spots
	for sp in spots:
		_nodes.append(_make_page(sp.pos, float(sp.yaw)))
	refresh()


## Show only the pages this player has not read yet.
func refresh() -> void:
	for i in spots.size():
		if i < _nodes.size() and is_instance_valid(_nodes[i]):
			_nodes[i].visible = not found.has(int(spots[i].page))


func page_near(p: Vector3) -> int:
	for i in spots.size():
		if found.has(int(spots[i].page)):
			continue
		var sp: Vector3 = spots[i].pos
		if p.distance_to(sp) < READ_RANGE + 0.6 and Vector2(p.x - sp.x, p.z - sp.z).length() < READ_RANGE:
			return i
	return -1


func prompt(p: Vector3) -> String:
	if page_near(p) >= 0:
		return "[%s]  READ THE TORN PAGE" % Keybinds.key("interact")
	return ""


func interact(p: Vector3) -> bool:
	var si := page_near(p)
	if si < 0:
		return false
	var pg := int(spots[si].page)
	var fresh := not found.has(pg)
	found[pg] = true
	save_found()
	refresh()
	open_page(pg, fresh)
	if fresh:
		Renown.total += RENOWN_PER_PAGE
		Renown.save_profile()
	return true


func open_page(pg: int, fresh: bool) -> void:
	reading = pg
	game.input_locked = true
	game.sfx.play_ui("writ_take", -8.0)
	game.hud.show_codex_page(pg, PAGES[pg][0], PAGES[pg][1], found.size(), PAGES.size(), RENOWN_PER_PAGE if fresh else 0)


func close_page() -> void:
	if reading < 0:
		return
	reading = -1
	game.input_locked = false
	game.hud.hide_codex_page()


func _input(event: InputEvent) -> void:
	if reading < 0 or not (event is InputEventKey or event is InputEventMouseButton) or not event.is_pressed():
		return
	if event is InputEventKey and (event as InputEventKey).is_echo():
		return
	close_page()
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if reading >= 0 and (game.phase != "playing" or not game.player.alive):
		close_page()


## A torn page weighted down by a stone, glowing faintly gold.
func _make_page(at: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	game.world.add_child(root)
	root.global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.93, 0.86, 0.68)
	paper.emission_enabled = true
	paper.emission = Color(1.0, 0.8, 0.45)
	paper.emission_energy_multiplier = 0.6
	paper.roughness = 0.9
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.4, 0.39, 0.37)
	var ink := StandardMaterial3D.new()
	ink.albedo_color = Color(0.2, 0.14, 0.1)
	for part in [[Vector3(0.32, 0.01, 0.42), Vector3(0, 0.02, 0), paper, 0.12], [Vector3(0.22, 0.012, 0.03), Vector3(0.0, 0.03, -0.1), ink, 0.12],
			[Vector3(0.18, 0.012, 0.03), Vector3(0.0, 0.03, 0.0), ink, 0.12], [Vector3(0.2, 0.012, 0.03), Vector3(0.0, 0.03, 0.1), ink, 0.12],
			[Vector3(0.12, 0.08, 0.1), Vector3(0.1, 0.06, 0.16), stone, 0.4]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = part[0]
		mi.mesh = bm
		mi.material_override = part[2]
		mi.position = part[1]
		mi.rotation.y = float(part[3])
		root.add_child(mi)
	MeshMerge.merge(root, [])
	for c in root.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).visibility_range_end = 70.0
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.45)
	l.light_energy = 0.6
	l.omni_range = 1.8
	l.position.y = 0.35
	l.distance_fade_enabled = true
	l.distance_fade_begin = 35.0
	l.distance_fade_length = 15.0
	root.add_child(l)
	return root
