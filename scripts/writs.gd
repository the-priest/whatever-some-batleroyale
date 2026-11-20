class_name Writs
extends Node
## Writs: jobs nailed to the boards in every town. Take one (F at a board),
## do it before its time runs out, and get paid in Embers and loot.
##
##   BLOOD WRIT   hunt a marked champion; their area shows as a circle that
##                follows them and shrinks, and close up you see them exactly
##   RELIC WRIT   three search circles, each smaller, then dig the relic up
##   BEACON WRIT  light a beacon on a hilltop and hold it while soldiers
##                come for you; a supply drop lands on it
##
## The host (or a solo game) owns every writ. A joined player asks the host
## to take one or to dig / light, and is told what to show. Owner 0 is the
## player on this machine; any other owner is a joined player's peer id.

const TITLE := {"blood": "BLOOD WRIT", "relic": "RELIC WRIT", "beacon": "BEACON WRIT"}
const BLURB := {"blood": "HUNT A MARKED CHAMPION", "relic": "DIG UP A BURIED RELIC", "beacon": "LIGHT AND HOLD A HILLTOP BEACON"}
const TINT := {"blood": Color(0.96, 0.30, 0.24), "relic": Color(1.0, 0.78, 0.32), "beacon": Color(0.42, 0.72, 1.0)}
const REWARD := {"blood": 650, "relic": 500, "beacon": 750}
const TIME := {"blood": 300.0, "relic": 360.0, "beacon": 300.0}
## A board gets new writs this long after one is taken from it.
const BOARD_REST := 75.0
const REACH := 2.8
const RELIC_RINGS := [95.0, 45.0, 15.0]
const DIG_TIME := 3.0
const LIGHT_TIME := 1.5
const HOLD_TIME := 45.0
const HOLD_RADIUS := 24.0
## Embers for a kill, and the extras.
## What a Wayshrine sells: [id, label, cost]. Laid out on its offering stone.
const WARES := [
	["med", "MEDKIT", 200],
	["ammo", "AMMUNITION  ·  TWO BOXES FOR THE GUN IN HAND", 150],
	["grenade", "FRAG GRENADES  ·  TWO", 220],
	["vest", "ARMOUR VEST  ·  LEVEL 2", 400],
	["helmet", "HELMET  ·  LEVEL 2", 300],
	["raven", "RAVEN'S EYE  ·  SEE EVERY SOLDIER WITHIN 250 M", 450],
	["vest3", "WARDEN'S PLATE  ·  LEVEL 3 VEST", 1100],
	["kindling", "KINDLING  ·  RISE AGAIN HERE WHEN YOU FALL", 1500],
	["sigil", "SIGIL  ·  OPENS ONE SEALED VAULT", 900],
]
const VAULT_EMBERS := 600
const VAULT_GUNS := ["sniper", "axmc", "lmg", "m24", "dmr"]
## Kindling stops working once the circle is this small: the fires go out.
const KINDLING_MIN_RADIUS := 160.0
const RISE_DELAY := 4.5
const RAVEN_RANGE := 250.0
const CHAMPION_GUNS := ["dmr", "m24", "carbine", "bullpup", "rifle", "lmg", "axmc"]
## Branded: this many kills inside BRAND_WINDOW seconds marks you for all.
const BRAND_KILLS := 5
const BRAND_WINDOW := 90.0
const BRAND_TIME := 90.0
const BRAND_REWARD := 1000
const KILL_EMBERS := 100
const HEADSHOT_EMBERS := 50
const LONG_SHOT_EMBERS := 50

var game: Node
## [{pos: Vector3, yaw, town, kind}] from the villages.
var boards: Array = []
var board_cool: Array[float] = []
## Host: owner -> the writ (with its target, site and timers).
var active: Dictionary = {}
## Host: owner -> Embers.
var purse: Dictionary = {}
## What this machine's player sees of their own writ ({} for none).
var view: Dictionary = {}
var my_embers := 0
var _tick := 0.0
var _hold := 0.0
var _hold_sent := false
## This machine's site props (the dig mound, the beacon) by kind.
var _site_nodes: Dictionary = {}
var _beacon_fire: Node3D = null
var _flicker := 0.0
## [{pos, yaw, name}] from the villages.
var shrines: Array = []
## The shrine whose wares are open on screen, or -1.
var shop := -1
## [{door, yaw, inside, name, door_w, door_h}] from the villages, and which are open.
var vaults: Array = []
var vault_open: Array[bool] = []
var _doors: Array[Node3D] = []
## Host: owner -> Sigils held. And this machine's own count.
var sigils: Dictionary = {}
var my_sigils := 0
## Blood Moon doubles what kills pay.
var ember_mult := 1
## Shrines of the Old Gods: [{pos, yaw, god, kind, eyes, eye_basis}] and which are spent.
var idols: Array = []
var idol_used: Array[bool] = []
var _idol_eyes: Array[Node3D] = []
## Lookout towers you have surveyed from this match (index -> true).
var _surveyed: Dictionary = {}
const SURVEY_RANGE := 300.0
## Host: owners blessed by the Ember King (kills pay half again).
var ember_blessed: Dictionary = {}
const KNEEL_TIME := 2.0
## Gifts: powers for the rest of the match, from fallen bosses.
const GIFTS := {
	"blink": ["BLINK", "PRESS V: STEP NINE METRES THROUGH THE AIR (5 S TO RECOVER)"],
	"second": ["SECOND WIND", "THE NEXT BLOW THAT WOULD FELL YOU LEAVES YOU STANDING"],
	"aegis": ["EMBER AEGIS", "A SHIELD OF 60 THAT REBUILDS WHEN YOU ARE NOT HIT"],
	"storm": ["STORMWALKER", "THE STORM CANNOT HURT YOU"],
	"hawk": ["HAWK'S EYE", "EVERY 20 SECONDS, THE SOLDIERS NEAR YOU SHOW ON YOUR MAP"],
	"blood": ["BLOODTHIRST", "A FIFTH OF THE DAMAGE YOU DEAL HEALS YOU"],
	"titan": ["TITAN", "+50 MAXIMUM HEALTH"],
}
## Host: owner -> gifts already given (so nobody gets the same twice).
var _gifted: Dictionary = {}
const BLESSINGS := {
	"swift": ["SWIFTNESS", "YOU MOVE A LITTLE FASTER"],
	"steady": ["STEADY AIM", "YOUR GUNS KICK A QUARTER LESS"],
	"quick": ["NIMBLE HANDS", "YOU RELOAD A QUARTER FASTER"],
	"vigour": ["VIGOUR", "+25 MAXIMUM HEALTH"],
	"warding": ["WARDING", "BULLETS AND BLASTS HURT YOU LESS"],
	"ember": ["EMBER-TOUCHED", "YOUR KILLS PAY HALF AGAIN IN EMBERS"],
}
## Kindling carried (one at most). Solo games only.
var kindling := 0
## Embers left where you fell: {pos, amount}, or {} for none.
var cinder: Dictionary = {}
var _cinder_node: Node3D = null
var rising := false
## Host: owner -> [kill times]; owner -> seconds of Branded left.
var _kill_times: Dictionary = {}
var branded: Dictionary = {}
var _brand_call := 0.0
## What this machine shows: seconds of Branded left (0 = not).
var my_brand := 0.0


func setup(p_game: Node) -> void:
	game = p_game
	boards = game.world.villages.writ_boards
	board_cool.resize(boards.size())
	board_cool.fill(0.0)
	var marks: Array = []
	for b in boards:
		marks.append([Vector2(b.pos.x, b.pos.z), b.kind, b.town])
	game.hud.writ_boards = marks
	shrines = game.world.villages.wayshrines
	var sm: Array = []
	for w in shrines:
		sm.append(Vector2(w.pos.x, w.pos.z))
	game.hud.shrine_marks = sm
	idols = game.world.villages.old_gods
	idol_used.resize(idols.size())
	idol_used.fill(false)
	for idol in idols:
		_idol_eyes.append(_make_eyes(idol))
	vaults = game.world.villages.vaults
	vault_open.resize(vaults.size())
	vault_open.fill(false)
	for v in vaults:
		_doors.append(_make_door(v))
	_vault_marks()


func reset() -> void:
	for o in active.keys():
		_end(int(o), false, "", false)
	active.clear()
	purse.clear()
	view = {}
	my_embers = 0
	board_cool.fill(0.0)
	_clear_sites()
	_hold = 0.0
	close_shop()
	kindling = 0
	rising = false
	_set_cinder({})
	_kill_times.clear()
	branded.clear()
	my_brand = 0.0
	sigils.clear()
	my_sigils = 0
	ember_mult = 1
	ember_blessed.clear()
	_surveyed.clear()
	_gifted.clear()
	for i in idol_used.size():
		idol_used[i] = false
		if i < _idol_eyes.size() and is_instance_valid(_idol_eyes[i]):
			_idol_eyes[i].visible = true
	if game != null and game.hud != null:
		game.hud.set_blessings([])
	for i in vault_open.size():
		if vault_open[i]:
			vault_open[i] = false
			if i < _doors.size() and is_instance_valid(_doors[i]):
				_doors[i].position.y = 0.0
				_doors[i].visible = true
				(_doors[i].get_meta("shape") as CollisionShape3D).disabled = false
	_vault_marks()
	if game != null and game.hud != null:
		game.hud.set_writ({})
		game.hud.set_embers(0, 0, "")


# ------------------------------------------------------------- the player --

## Board within reach of this spot (and in front of it), or -1.
func board_near(p: Vector3) -> int:
	var best := -1
	var best_d := REACH
	for i in boards.size():
		var bp: Vector3 = boards[i].pos
		var d := Vector2(p.x - bp.x, p.z - bp.z).length()
		if d < best_d and absf(p.y - bp.y) < 2.5:
			best_d = d
			best = i
	return best


## What the interact prompt should say here ("" for nothing writ-related).
func prompt(p: Vector3) -> String:
	var key := Keybinds.key("interact")
	var bi := board_near(p)
	if bi >= 0:
		var b: Dictionary = boards[bi]
		var kind: String = b.kind
		if not view.is_empty():
			return "WRIT BOARD  —  YOU ALREADY CARRY A WRIT"
		if board_cool[bi] > 0.0:
			return "WRIT BOARD  —  NEW WRITS IN %d:%02d" % [int(board_cool[bi]) / 60, int(board_cool[bi]) % 60]
		return "[%s]  TAKE THE %s  —  %s   (+%d EMBERS)" % [key, TITLE[kind], BLURB[kind], REWARD[kind]]
	var act := _act_here(p)
	if act != "":
		if act == "kneel":
			var idol: Dictionary = idols[idol_near(p)]
			return "HOLD [%s]  KNEEL BEFORE %s   (%s)" % [key, str(idol.god), str(BLESSINGS[str(idol.kind)][0])]
		return "HOLD [%s]  %s" % [key, "DIG UP THE RELIC" if act == "dig" else "LIGHT THE BEACON"]
	if shrine_near(p) >= 0:
		return "[%s]  WAYSHRINE  —  SPEND YOUR EMBERS   (◆ %d)" % [key, my_embers]
	var ti := tower_top(p)
	if ti >= 0 and not _surveyed.has(ti):
		return "[%s]  SURVEY THE LAND FROM THE TOWER" % key
	var vi := vault_near(p)
	if vi >= 0:
		if my_sigils > 0:
			return "[%s]  OPEN THE VAULT  —  USE A SIGIL   (%d HELD)" % [key, my_sigils]
		return "SEALED VAULT  —  A SIGIL OPENS IT. REVENANTS CARRY THEM; WAYSHRINES SELL THEM"
	return ""


## F pressed: take a writ from the board here. True if it was for us.
func interact(p: Vector3) -> bool:
	var bi := board_near(p)
	if bi < 0:
		var si := shrine_near(p)
		if si >= 0:
			open_shop(si)
			return true
		var ti := tower_top(p)
		if ti >= 0 and not _surveyed.has(ti):
			survey(ti)
			return true
		var vi := vault_near(p)
		if vi >= 0:
			if my_sigils <= 0:
				game.hud.show_notice("YOU HAVE NO SIGIL  —  FELL A REVENANT, OR BUY ONE AT A WAYSHRINE", 2.6)
				game.sfx.play_ui("empty_click", -6.0)
			elif game.net_is_client():
				game.net.send_vault_open(vi)
			else:
				open_vault(0, vi)
			return true
		return false
	if not view.is_empty() or board_cool[bi] > 0.0:
		return true
	if game.net_is_client():
		game.net.send_writ_take(bi)
	else:
		take(0, bi)
	return true


## The dig or light action available where you stand, or "".
func _act_here(p: Vector3) -> String:
	if idol_near(p) >= 0:
		return "kneel"
	if view.is_empty() or not view.has("act"):
		return ""
	var ap: Vector3 = view["act_pos"]
	if Vector2(p.x - ap.x, p.z - ap.z).length() < 2.6 and absf(p.y - ap.y) < 3.0:
		return str(view["act"])
	return ""


func _process(delta: float) -> void:
	if game == null or game.player == null:
		return
	var playing: bool = game.phase == "playing"
	if shop >= 0 and (not playing or not game.player.alive or shrine_near(game.player.global_position) != shop):
		close_shop()
	if not playing:
		return
	for i in board_cool.size():
		if board_cool[i] > 0.0:
			board_cool[i] = maxf(0.0, board_cool[i] - delta)
	# Holding F to dig or light.
	var pl: Player = game.player
	var act := _act_here(pl.global_position) if pl.alive and pl.mode == Player.Mode.GROUND else ""
	if act != "" and Input.is_action_pressed("interact") and not game.input_locked:
		var need := DIG_TIME if act == "dig" else (KNEEL_TIME if act == "kneel" else LIGHT_TIME)
		_hold += delta
		game.hud.set_progress({"dig": "DIGGING ...", "kneel": "KNEELING ..."}.get(act, "LIGHTING THE BEACON ..."), clampf(_hold / need, 0.0, 1.0))
		if _hold >= need and not _hold_sent:
			_hold_sent = true
			game.hud.set_progress("", 0.0)
			if game.net_is_client():
				game.net.send_writ_act(act)
			else:
				act_on(0, act)
	elif _hold > 0.0:
		_hold = 0.0
		_hold_sent = false
		game.hud.set_progress("", 0.0)
	# The clock on our own writ runs here too (the host corrects it).
	if not view.is_empty():
		view["t"] = maxf(0.0, float(view.get("t", 0.0)) - delta)
		game.hud.set_writ(view)
	_animate_sites(delta)
	_check_cinder()
	if my_brand > 0.0:
		my_brand = maxf(0.0, my_brand - delta)
		game.hud.branded_t = my_brand
	if game.net_is_client():
		return
	_tick -= delta
	if _tick <= 0.0:
		# Keep the remainder, so the writ clocks run at the real rate.
		_tick = maxf(_tick + 0.5, 0.0)
		for o in active.keys():
			_host_tick(int(o), 0.5)
		_brand_tick(0.5)


# -------------------------------------------------------------- shrines --

func shrine_near(p: Vector3) -> int:
	for i in shrines.size():
		var sp: Vector3 = shrines[i].pos
		if Vector2(p.x - sp.x, p.z - sp.z).length() < 2.6 and absf(p.y - sp.y) < 2.0:
			return i
	return -1


func open_shop(si: int) -> void:
	shop = si
	if game.player != null and game.player.refill_flask():
		game.hud.show_notice("THE SHRINE REKINDLES YOUR EMBER FLASK", 2.5)
	game.input_locked = true
	game.hud.show_shop(_priced_wares(), my_embers)
	game.sfx.play_ui("ui_click", -8.0)


func _priced_wares() -> Array:
	var out: Array = []
	for i in WARES.size():
		out.append([WARES[i][0], WARES[i][1], ware_cost(i)])
	return out


func close_shop() -> void:
	if shop < 0:
		return
	shop = -1
	if game != null:
		game.input_locked = false
		game.hud.hide_shop()


func _input(event: InputEvent) -> void:
	if shop < 0 or not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var k := event as InputEventKey
	var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
	if code >= KEY_1 and code <= KEY_9:
		var n := int(code - KEY_1)
		if n < WARES.size():
			_buy(n)
		get_viewport().set_input_as_handled()
	elif event.is_action("interact") or event.is_action("ui_cancel") or code == KEY_ESCAPE:
		close_shop()
		get_viewport().set_input_as_handled()


## What ware `n` costs owner `o` (the Oath of Embers doubles it).
func ware_cost(n: int, o: int = 0) -> int:
	return int(WARES[n][2]) * (2 if o == 0 and game.oath("embers") else 1)


func _buy(n: int) -> void:
	var cost := ware_cost(n)
	if my_embers < cost:
		game.hud.show_notice("NOT ENOUGH EMBERS  —  %d MORE" % (cost - my_embers), 1.8)
		game.sfx.play_ui("empty_click", -6.0)
		return
	if game.net_is_client():
		game.net.send_shrine_buy(shop, n)
	else:
		buy_on(0, shop, n)


## Host: owner `o` buys ware `n` at shrine `si`.
func buy_on(o: int, si: int, n: int) -> void:
	if si < 0 or si >= shrines.size() or n < 0 or n >= WARES.size() or not _owner_alive(o):
		return
	var sp: Vector3 = shrines[si].pos
	var at := _owner_pos(o)
	if at == Vector3.INF or Vector2(at.x - sp.x, at.z - sp.z).length() > 4.0:
		return
	var ware: Array = WARES[n]
	if str(ware[0]) == "kindling" and o == 0 and game.oath("ash"):
		_tell(o, "YOU SWORE THE OATH OF ASH  —  NO KINDLING FOR YOU")
		return
	if str(ware[0]) == "kindling":
		if game.net_on():
			_tell(o, "KINDLING ONLY BURNS IN A SOLO GAME")
			return
		if kindling > 0:
			_tell(o, "YOU ALREADY CARRY KINDLING")
			return
		if game.zone != null and game.zone.radius < KINDLING_MIN_RADIUS:
			_tell(o, "THE FIRES HAVE GONE OUT  —  TOO LATE FOR KINDLING")
			return
	if not spend(o, ware_cost(n, o)):
		return
	var yaw: float = shrines[si].yaw
	var side := Basis(Vector3.UP, yaw) * Vector3.RIGHT
	var spot: Vector3 = sp + side * randf_range(-0.35, 0.35) + Vector3.UP * 0.06
	match str(ware[0]):
		"med":
			game._spawn_loot("med", "", spot)
		"ammo":
			game._spawn_loot("ammo", "", spot - side * 0.2)
			game._spawn_loot("ammo", "", spot + side * 0.2)
		"grenade":
			game._spawn_loot("grenade", "", spot - side * 0.2)
			game._spawn_loot("grenade", "", spot + side * 0.2)
		"vest":
			game._spawn_loot("armor", "2", spot)
		"vest3":
			game._spawn_loot("armor", "3", spot)
		"helmet":
			game._spawn_loot("helmet", "2", spot)
		"kindling":
			kindling = 1
			game.hud.set_kindling(true)
		"sigil":
			give_sigil(o, 1, "")
		"raven":
			var pts: Array = []
			for b in game.bots:
				if not is_instance_valid(b) or not b.alive or b.state != Bot.State.GROUND:
					continue
				if b.is_human and (b.peer_id == o or b.friendly):
					continue
				if Vector2(b.global_position.x - at.x, b.global_position.z - at.z).length() < RAVEN_RANGE:
					pts.append(Vector2(b.global_position.x, b.global_position.z))
			if o != 0 and game.player != null and game.player.alive:
				var hp: Vector3 = game.player.global_position
				if Vector2(hp.x - at.x, hp.z - at.z).length() < RAVEN_RANGE and not game.net.squad:
					pts.append(Vector2(hp.x, hp.z))
			_send_event(o, {"ev": "reveal", "pts": pts})
	_send_event(o, {"ev": "bought", "what": str(ware[1]).split("  ·")[0]})


# ---------------------------------------------------- kindling, cinders --

## The player just fell (solo). With Kindling and the fires still burning,
## they rise again at the nearest Wayshrine instead. True if so.
func try_rise() -> bool:
	if game.net_on() or kindling <= 0 or rising or shrines.is_empty():
		return false
	if game.zone != null and game.zone.radius < KINDLING_MIN_RADIUS:
		return false
	kindling = 0
	rising = true
	game.hud.set_kindling(false)
	var pl: Player = game.player
	var here := pl.global_position
	# Your Embers stay where you fell. Die again before you get them back and
	# they are gone.
	if my_embers > 0:
		var amount := my_embers
		purse[0] = 0
		_embers_here(0, -amount, "")
		_set_cinder({"pos": game.ground_at(here + Vector3.UP * 0.5), "amount": amount})
	else:
		_set_cinder({})
	if not view.is_empty():
		_end(0, false, "YOU FELL  —  THE WRIT IS VOID")
	close_shop()
	game._drop_player_kit()
	game.hud.show_big("YOU FELL", HUD.DANGER, RISE_DELAY)
	game.hud.show_notice("THE KINDLING CATCHES  ...", RISE_DELAY)
	game.sfx.play_ui("defeat", -8.0)
	_rise_later(here)
	return true


func _rise_later(here: Vector3) -> void:
	await get_tree().create_timer(RISE_DELAY).timeout
	if game == null or game.phase != "playing" or not rising:
		rising = false
		return
	# The nearest Wayshrine inside the circle, else the nearest of all.
	var best := -1
	var best_s := INF
	for i in shrines.size():
		var sp: Vector3 = shrines[i].pos
		var s := sp.distance_to(here)
		if game.zone != null and game.zone.is_outside(sp):
			s += 100000.0
		if s < best_s:
			best_s = s
			best = i
	var sh: Dictionary = shrines[best]
	var pl: Player = game.player
	var keep_kills: int = pl.kills
	pl.reset_for_match()
	pl.kills = keep_kills
	pl.mode = Player.Mode.GROUND
	pl.landed = true
	pl.global_position = game.ground_at(sh.pos + Basis(Vector3.UP, float(sh.yaw)) * Vector3(0, 1.0, 1.6)) + Vector3.UP * 0.1
	pl.velocity = Vector3.ZERO
	pl.yaw = float(sh.yaw) + PI
	pl.give_weapon("pistol")
	pl.add_ammo_cal("9mm", 30)
	pl.bandages = 2
	pl.spawn_protect = 3.0
	game.anticheat.grace(3.0)
	pl._emit_health()
	pl._emit_weapon()
	pl.inventory_changed.emit()
	rising = false
	game.hud.show_big("YOU RISE AGAIN", Color(1.0, 0.72, 0.36), 2.6)
	game.hud.show_notice("YOUR EMBERS WAIT WHERE YOU FELL" if not cinder.is_empty() else "THE WAYSHRINE'S FIRE BROUGHT YOU BACK", 3.5)
	game.sfx.play_ui("beacon_light", -6.0)


func _set_cinder(c: Dictionary) -> void:
	cinder = c
	if _cinder_node != null and is_instance_valid(_cinder_node):
		_cinder_node.queue_free()
	_cinder_node = null
	if game != null and game.hud != null:
		game.hud.cinder = c.duplicate()
	if c.is_empty() or game == null:
		return
	var root := Node3D.new()
	game.add_child(root)
	root.global_position = c.pos
	var glow := _mat(Color(1.0, 0.55, 0.2), 4.0)
	var ash := _mat(Color(0.12, 0.11, 0.1))
	for i in 9:
		var a := randf() * TAU
		var r := randf() * 0.45
		_box(root, Vector3(0.14, 0.06, 0.1), Vector3(cos(a) * r, 0.04, sin(a) * r), glow if i % 3 != 0 else ash, Vector3(0, randf() * PI, 0))
	MeshMerge.merge(root, [])
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.25)
	light.light_energy = 1.6
	light.omni_range = 4.0
	light.position.y = 0.4
	root.add_child(light)
	_cinder_node = root


## Walking over your Cinder gives the Embers back.
func _check_cinder() -> void:
	if cinder.is_empty() or game.player == null or not game.player.alive:
		return
	var cp: Vector3 = cinder.pos
	if game.player.global_position.distance_to(cp) < 2.2:
		var amount := int(cinder.amount)
		_set_cinder({})
		purse[0] = int(purse.get(0, 0)) + amount
		_embers_here(int(purse[0]), amount, "RECOVERED")
		game.hud.show_big("EMBERS RECOVERED", Color(1.0, 0.72, 0.36), 2.2)


# ---------------------------------------------------------- the old gods --

func idol_near(p: Vector3) -> int:
	for i in idols.size():
		if idol_used[i]:
			continue
		var ip: Vector3 = idols[i].pos
		if Vector2(p.x - ip.x, p.z - ip.z).length() < 2.2 and absf(p.y - ip.y) < 2.0:
			return i
	return -1


## The idol's eyes: two embers in the stone that go out once it has blessed
## someone. Built on every machine.
func _make_eyes(idol: Dictionary) -> Node3D:
	var root := Node3D.new()
	game.world.add_child(root)
	root.global_transform = Transform3D(idol.eye_basis, idol.eyes)
	var em := _mat(Color(0.55, 1.0, 0.75), 5.0)
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for sx: float in [-0.11, 0.11]:
		_box(root, Vector3(0.09, 0.04, 0.03), Vector3(sx, 0, 0), em)
	MeshMerge.merge(root, [])
	var l := OmniLight3D.new()
	l.light_color = Color(0.55, 1.0, 0.75)
	l.light_energy = 0.8
	l.omni_range = 4.0
	l.position = Vector3(0, 0, 0.4)
	l.distance_fade_enabled = true
	l.distance_fade_begin = 80.0
	l.distance_fade_length = 30.0
	root.add_child(l)
	return root


## Host: owner `o` knelt long enough at an idol.
func _kneel(o: int) -> void:
	var at := _owner_pos(o)
	if at == Vector3.INF or not _owner_alive(o):
		return
	var ii := idol_near(at + Vector3.UP * 0.0)
	if ii < 0:
		return
	idol_used[ii] = true
	var kind := str(idols[ii].kind)
	if kind == "ember":
		ember_blessed[o] = true
	if game.net_on():
		for pid in game.net.roster:
			if int(pid) != 1:
				game.net.send_writ_event(int(pid), {"ev": "idol_used", "i": ii})
	apply_event({"ev": "idol_used", "i": ii})
	_send_event(o, {"ev": "blessing", "kind": kind, "god": str(idols[ii].god)})


# --------------------------------------------------------- lookout towers --

## A lookout tower whose upper floor you are standing on, or -1.
func tower_top(p: Vector3) -> int:
	var towers: Array = game.world.villages.towers
	for i in towers.size():
		var c: Vector2 = towers[i].center
		if Vector2(p.x, p.z).distance_to(c) < 4.3 and p.y - float(towers[i].pad) > 2.6:
			return i
	return -1


## From the top of a tower: every soldier within range shows on your map.
func survey(ti: int) -> void:
	_surveyed[ti] = true
	var at: Vector3 = game.player.global_position
	var pts: Array = []
	for b in game.bots:
		if not is_instance_valid(b) or not b.alive or b.state != Bot.State.GROUND or b.friendly:
			continue
		if Vector2(b.global_position.x - at.x, b.global_position.z - at.z).length() < SURVEY_RANGE:
			pts.append(Vector2(b.global_position.x, b.global_position.z))
	for id in game.humans:
		var h = game.humans[id]
		if h != null and is_instance_valid(h) and (h as Bot).alive and not (h as Bot).friendly and (h as Bot).state == Bot.State.GROUND:
			if Vector2((h as Node3D).global_position.x - at.x, (h as Node3D).global_position.z - at.z).length() < SURVEY_RANGE:
				pts.append(Vector2((h as Node3D).global_position.x, (h as Node3D).global_position.z))
	game.hud.reveal(pts, 12.0)
	game.sfx.play_ui("writ_ping", -4.0)
	game.hud.show_big("THE LAND LIES BELOW YOU", Color(0.75, 0.85, 1.0), 2.2)
	game.hud.show_notice("%d SOLDIER%s WITHIN %d M  —  ON YOUR MAP" % [pts.size(), "" if pts.size() == 1 else "S", int(SURVEY_RANGE)], 3.5)


# --------------------------------------------------------------- vaults --

func vault_near(p: Vector3) -> int:
	for i in vaults.size():
		if vault_open[i]:
			continue
		var v: Dictionary = vaults[i]
		var front: Vector3 = v.door + Basis(Vector3.UP, float(v.yaw)) * Vector3(0, 0, 1.0)
		if Vector2(p.x - front.x, p.z - front.z).length() < 1.9 and absf(p.y - front.y) < 2.2:
			return i
	return -1


## An iron door with a gold sigil set in it, in the doorway; it sinks into
## the floor when opened. Built on every machine (the island is the same).
func _make_door(v: Dictionary) -> Node3D:
	var root := StaticBody3D.new()
	game.world.add_child(root)
	var holder := Node3D.new()
	game.world.add_child(holder)
	holder.global_transform = Transform3D(Basis(Vector3.UP, float(v.yaw)), v.door)
	root.reparent(holder, false)
	var dw := float(v.door_w)
	var dh := float(v.door_h)
	var iron := _mat(Color(0.13, 0.12, 0.12), 0.0, 0.45)
	iron.metallic = 0.7
	var gold := _mat(Color(0.95, 0.7, 0.25), 2.2, 0.3)
	gold.metallic = 0.8
	_box(root, Vector3(dw, dh, 0.16), Vector3(0, dh * 0.5, 0), iron)
	for k in 4:
		_box(root, Vector3(dw + 0.04, 0.07, 0.2), Vector3(0, 0.3 + float(k) * (dh - 0.6) / 3.0, 0), iron)
	_box(root, Vector3(0.36, 0.36, 0.05), Vector3(0, dh * 0.58, 0.1), gold, Vector3(0, 0, PI * 0.25))
	_box(root, Vector3(0.14, 0.14, 0.06), Vector3(0, dh * 0.58, 0.12), _mat(Color(0.08, 0.06, 0.05)), Vector3(0, 0, PI * 0.25))
	MeshMerge.merge(root, [])
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(dw, dh, 0.3)
	cs.shape = sh
	cs.position = Vector3(0, dh * 0.5, 0)
	root.add_child(cs)
	root.set_meta("shape", cs)
	holder.set_meta("shape", cs)
	holder.set_meta("door", root)
	return holder


func give_sigil(o: int, n: int, why: String) -> void:
	sigils[o] = int(sigils.get(o, 0)) + n
	_send_event(o, {"ev": "sigil", "n": int(sigils[o]), "why": why})


## Host: owner `o` breaks the seal on vault `vi`.
func open_vault(o: int, vi: int) -> void:
	if vi < 0 or vi >= vaults.size() or vault_open[vi] or int(sigils.get(o, 0)) <= 0 or not _owner_alive(o):
		return
	var v: Dictionary = vaults[vi]
	var at := _owner_pos(o)
	var front: Vector3 = v.door + Basis(Vector3.UP, float(v.yaw)) * Vector3(0, 0, 1.0)
	if at == Vector3.INF or Vector2(at.x - front.x, at.z - front.z).length() > 3.5:
		return
	sigils[o] = int(sigils[o]) - 1
	_send_event(o, {"ev": "sigil", "n": int(sigils[o]), "why": ""})
	if game.net_on():
		game.net.send_vault_open(vi)
	apply_vault_open(vi)
	# The hoard, laid out on the coffers and the floor.
	var b := Basis(Vector3.UP, float(v.yaw))
	var inside: Vector3 = v.inside
	var gun: String = VAULT_GUNS[randi() % VAULT_GUNS.size()]
	var items: Array = [["weapon", gun, Vector3(0, 0.75, -2.0)], ["ammo", Weapons.caliber(gun), Vector3(0.5, 0.05, -1.2)],
		["ammo", Weapons.caliber(gun), Vector3(-0.5, 0.05, -1.2)], ["armor", "3", Vector3(-1.5, 0.75, -0.2)],
		["helmet", "3", Vector3(1.5, 0.75, -0.2)], ["scope", "8x", Vector3(0.0, 0.05, 0.2)], ["med", "", Vector3(-0.6, 0.05, 0.8)],
		["med", "", Vector3(0.6, 0.05, 0.8)], ["grenade", "", Vector3(0.0, 0.05, 1.2)]]
	for it: Array in items:
		var p: Vector3 = inside + b * (it[2] as Vector3) + Vector3.UP * 0.1
		game._spawn_loot(it[0], it[1], game.ground_at(p + Vector3.UP * 0.4) + Vector3.UP * 0.08)
	award(o, VAULT_EMBERS, "VAULT OPENED")


## Everyone: the vault's door grinds down into the floor.
func apply_vault_open(vi: int) -> void:
	if vi < 0 or vi >= vaults.size() or vault_open[vi]:
		return
	vault_open[vi] = true
	_vault_marks()
	var door := _doors[vi]
	(door.get_meta("shape") as CollisionShape3D).disabled = true
	var root := door.get_meta("door") as Node3D
	var tw := root.create_tween()
	tw.tween_property(root, "position:y", -float(vaults[vi].door_h) - 0.1, 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func(): door.visible = false)
	game.sfx.play_at("vault_open", door.global_position + Vector3.UP * 1.2, 4.0)
	if game.player != null and game.player.global_position.distance_to(door.global_position) < 60.0:
		game.hud.show_big("THE VAULT OPENS", Color(1.0, 0.82, 0.38), 2.4)


func _vault_marks() -> void:
	var vm: Array = []
	for i in vaults.size():
		vm.append([Vector2(vaults[i].door.x, vaults[i].door.z), vault_open[i] if i < vault_open.size() else false])
	if game != null and game.hud != null:
		game.hud.vault_marks = vm


# ------------------------------------------------------------------ host --

func _owner_pos(o: int) -> Vector3:
	if o == 0:
		return game.player.global_position if game.player != null else Vector3.INF
	return game.net_peer_position(o)


func _owner_alive(o: int) -> bool:
	if o == 0:
		return game.player != null and game.player.alive
	var h = game.humans.get(o)
	return h != null and is_instance_valid(h) and (h as Bot).alive


func take(o: int, bi: int) -> void:
	if bi < 0 or bi >= boards.size() or active.has(o) or board_cool[bi] > 0.0 or not _owner_alive(o):
		return
	var b: Dictionary = boards[bi]
	var at := _owner_pos(o)
	if at == Vector3.INF or Vector2(at.x - b.pos.x, at.z - b.pos.z).length() > REACH + 2.0:
		return
	var kind: String = b.kind
	var w := {"kind": kind, "t": TIME[kind], "stage": 0, "board": bi}
	match kind:
		"blood":
			var target := _pick_mark(at)
			if target == null:
				_tell(o, "NO CHAMPION TO MARK RIGHT NOW  —  TRY AGAIN SOON")
				return
			_crown(target, o)
			w["target"] = target
			w["name"] = target.bot_name
			w["r"] = 110.0
			w["c"] = _ring_centre(target.global_position, 110.0)
			w["move"] = 20.0
		"relic":
			var site := _pick_site(at, 250.0, 650.0, false)
			if site == Vector3.INF:
				_tell(o, "THE BOARD'S RELIC MAPS ARE ALL TAKEN")
				return
			w["site"] = site
			w["c"] = _ring_centre(site, RELIC_RINGS[0])
		"beacon":
			var site2 := _pick_site(at, 220.0, 600.0, true)
			if site2 == Vector3.INF:
				_tell(o, "NO HILL FOR A BEACON NEARBY")
				return
			w["site"] = site2
			w["hold"] = HOLD_TIME
			w["call"] = 0.0
	active[o] = w
	board_cool[bi] = BOARD_REST
	if game.net_on():
		game.net.send_writ_board(bi, BOARD_REST)
	_refresh(o, w)
	_send_event(o, {"ev": "take", "kind": kind, "town": str(b.town)})


## A soldier for a Blood Writ: on the ground, not too near, not too far.
func _pick_mark(at: Vector3) -> Bot:
	var best: Bot = null
	var best_s := INF
	for b in game.bots:
		if not is_instance_valid(b) or not b.alive or b.is_human or b.puppet or b.state != Bot.State.GROUND or b.has_meta("writ_mark"):
			continue
		var d := Vector2(b.global_position.x - at.x, b.global_position.z - at.z).length()
		if d < 140.0 or d > 750.0:
			continue
		var s := absf(d - 380.0) + randf() * 60.0
		if s < best_s:
			best_s = s
			best = b
	return best


## The mark becomes a champion: armoured, well armed, sharper.
func _crown(b: Bot, o: int) -> void:
	b.set_meta("writ_mark", o)
	b.vest_level = maxi(b.vest_level, 3)
	b.armor = 100.0
	b.helmet_level = maxi(b.helmet_level, 2)
	b.hp = maxf(b.hp, 100.0)
	b.shoot_skill = maxf(b.shoot_skill, 0.72)
	b.reaction = minf(b.reaction, 0.28)
	b.aggression = maxf(b.aggression, 0.7)
	if not b.armed or not (b.weapon_id in CHAMPION_GUNS):
		b.arm_weapon(CHAMPION_GUNS[randi() % CHAMPION_GUNS.size()])
	b.meds = maxi(b.meds, 2)


## Open, dry ground at a distance; a hilltop for a beacon. Inside the next
## safe circle when possible.
func _pick_site(at: Vector3, lo: float, hi: float, hill: bool) -> Vector3:
	var terrain: Terrain = game.terrain
	var best := Vector3.INF
	var best_s := -INF
	var zc: Vector2 = game.zone.next_center() if game.zone != null else Vector2(at.x, at.z)
	var zr: float = game.zone.next_radius() if game.zone != null else 99999.0
	for i in 70:
		var a := randf() * TAU
		var d := randf_range(lo, hi)
		var q := Vector2(at.x, at.z) + Vector2(cos(a), sin(a)) * d
		if absf(q.x) > Terrain.HALF - 60.0 or absf(q.y) > Terrain.HALF - 60.0:
			continue
		var h := terrain.height_at(q.x, q.y)
		if h < terrain.water_surface_at(q.x, q.y) + 1.0 or terrain.slope_at(q.x, q.y) > (0.45 if hill else 0.35):
			continue
		if game._on_building(q.x, q.y) or game.world.villages.blocks_house(q, 4.0):
			continue
		var s := h * 0.08 if hill else randf()
		if q.distance_to(zc) < zr * 0.85:
			s += 30.0
		if s > best_s:
			best_s = s
			best = Vector3(q.x, h, q.y)
	if best != Vector3.INF:
		best = game.ground_at(best + Vector3.UP * 30.0)
	return best


func _ring_centre(site: Vector3, r: float) -> Vector2:
	var a := randf() * TAU
	return Vector2(site.x, site.z) + Vector2(cos(a), sin(a)) * r * randf_range(0.2, 0.62)


func _host_tick(o: int, dt: float) -> void:
	var w: Dictionary = active[o]
	if not _owner_alive(o):
		_end(o, false, "YOU FELL  —  THE WRIT IS VOID")
		return
	w["t"] = float(w["t"]) - dt
	if float(w["t"]) <= 0.0:
		_end(o, false, "OUT OF TIME  —  THE WRIT IS VOID")
		return
	var at := _owner_pos(o)
	var here := Vector2(at.x, at.z)
	var changed := false
	match str(w.kind):
		"blood":
			var b = w.get("target")
			if b == null or not is_instance_valid(b) or not (b as Bot).alive:
				_end(o, false, "YOUR MARK IS GONE")
				return
			var tp: Vector3 = (b as Bot).global_position
			var close := here.distance_to(Vector2(tp.x, tp.z)) < 70.0
			w["move"] = float(w["move"]) - dt
			if close != bool(w.get("close", false)):
				w["close"] = close
				changed = true
				if close:
					_send_event(o, {"ev": "close"})
			if float(w["move"]) <= 0.0 or not w.has("c"):
				w["move"] = 20.0
				var frac := 1.0 - float(w["t"]) / TIME["blood"]
				w["r"] = lerpf(110.0, 40.0, clampf(frac, 0.0, 1.0))
				w["c"] = _ring_centre(tp, float(w["r"]))
				changed = true
				_send_event(o, {"ev": "ping"})
			if close:
				w["pt"] = tp + Vector3.UP * 2.0
				changed = true
		"relic":
			var st := int(w["stage"])
			var c: Vector2 = w["c"]
			if st < RELIC_RINGS.size() - 1 and here.distance_to(c) < float(RELIC_RINGS[st]) * 0.8:
				w["stage"] = st + 1
				w["c"] = _ring_centre(w.site, RELIC_RINGS[st + 1])
				changed = true
				_send_event(o, {"ev": "ping"})
		"beacon":
			var site: Vector3 = w.site
			if int(w["stage"]) == 1:
				var inside := here.distance_to(Vector2(site.x, site.z)) < HOLD_RADIUS
				if inside:
					w["hold"] = float(w["hold"]) - dt
				if inside != bool(w.get("inside", true)):
					w["inside"] = inside
				w["call"] = float(w["call"]) - dt
				if float(w["call"]) <= 0.0:
					w["call"] = 15.0
					_call_soldiers(site, 6)
				changed = true
				if float(w["hold"]) <= 0.0:
					game.spawn_airdrop_at(Vector2(site.x + 7.0, site.z + 3.0))
					_end(o, true, "THE BEACON BURNS  —  A SUPPLY DROP IS ON ITS WAY")
					return
	# The timer itself is kept in step every few seconds.
	if changed or int(float(w["t"]) * 2.0) % 10 == 0:
		_refresh(o, w)


## Armed soldiers near the beacon come to see who lit it.
func _call_soldiers(site: Vector3, n: int) -> void:
	var near: Array = []
	for b in game.bots:
		if is_instance_valid(b) and b.alive and b.armed and not b.is_human and not b.puppet and b.state == Bot.State.GROUND:
			var d := Vector2(b.global_position.x - site.x, b.global_position.z - site.z).length()
			if d < 450.0:
				near.append([d, b])
	near.sort_custom(func(a, c): return a[0] < c[0])
	for i in mini(n, near.size()):
		var b: Bot = near[i][1]
		b.roam_point = Vector2(site.x, site.z) + Vector2(randf_range(-8, 8), randf_range(-8, 8))
		b.heard_pos = site
		b.alert_timer = 12.0


## A player finished holding F at the dig spot or the beacon.
func act_on(o: int, act: String) -> void:
	if act == "kneel":
		_kneel(o)
		return
	if not active.has(o):
		return
	var w: Dictionary = active[o]
	if not w.has("site"):
		return
	var site: Vector3 = w.site
	var at := _owner_pos(o)
	if at == Vector3.INF or Vector2(at.x - site.x, at.z - site.z).length() > 3.6:
		return
	if act == "dig" and str(w.kind) == "relic" and int(w["stage"]) == RELIC_RINGS.size() - 1:
		_relic_cache(site)
		_end(o, true, "RELIC RECOVERED")
	elif act == "light" and str(w.kind) == "beacon" and int(w["stage"]) == 0:
		w["stage"] = 1
		w["inside"] = true
		_call_soldiers(site, 6)
		w["call"] = 15.0
		_send_event(o, {"ev": "lit"})
		_refresh(o, w)


func _relic_cache(site: Vector3) -> void:
	var gun: String = CHAMPION_GUNS[randi() % CHAMPION_GUNS.size()]
	var items: Array = [["weapon", gun], ["ammo", Weapons.caliber(gun)], ["ammo", Weapons.caliber(gun)],
		["armor", "3" if randf() < 0.4 else "2"], ["helmet", "2"], ["med", ""], ["scope", "4x"]]
	for i in items.size():
		var a := TAU * float(i) / float(items.size())
		var p: Vector3 = game.ground_at(site + Vector3(cos(a), 1.0, sin(a)) * 1.6) + Vector3(0, 0.08, 0)
		game._spawn_loot(items[i][0], items[i][1], p)


## A soldier died (host). Pays for the kill, and settles a Blood Writ.
func on_bot_eliminated(victim: Bot) -> void:
	if game.net_is_client():
		return
	var src = victim.last_killer_node
	var killer_o := -1
	if src == game.player:
		killer_o = 0
	elif src is Bot and is_instance_valid(src) and (src as Bot).is_human:
		killer_o = (src as Bot).peer_id
	if killer_o >= 0:
		var n := KILL_EMBERS
		var why := "KILL"
		if victim.last_headshot:
			n += HEADSHOT_EMBERS
			why = "HEADSHOT"
		if src is Node3D and (src as Node3D).global_position.distance_to(victim.global_position) > 150.0:
			n += LONG_SHOT_EMBERS
			why = "LONG SHOT" if why == "KILL" else why + " · LONG SHOT"
		n *= ember_mult
		if ember_blessed.has(killer_o):
			n = int(float(n) * 1.5)
		if victim is Revenant:
			n += 2500 if victim is Colossus else (1600 if victim is HollowWarden or victim is Bellkeeper or victim is Wyrm or victim is Carrion or victim is LanternWitch or victim is VeilSister or victim is IronSentinel else 1200)
			why = "COLOSSUS FELLED" if victim is Colossus else ("WARDEN FELLED" if victim is HollowWarden else ("BELLKEEPER FELLED" if victim is Bellkeeper else ("WYRM SLAIN" if victim is Wyrm else ("CARRION QUEEN SLAIN" if victim is Carrion else ("LANTERN WITCH SLAIN" if victim is LanternWitch else ("SISTER OF THE VEIL SLAIN" if victim is VeilSister else ("SENTINEL STILLED" if victim is IronSentinel else "REVENANT FELLED")))))))
			if game.ordeal == null:
				give_sigil(killer_o, 1, "THE %s'S SIGIL IS YOURS  —  IT OPENS A SEALED VAULT" % ("COLOSSUS" if victim is Colossus else "REVENANT"))
		award(killer_o, n, why)
		_count_kill(killer_o)
	if victim.is_human and branded.has(victim.peer_id):
		_unbrand(victim.peer_id, false)
		if killer_o >= 0:
			award(killer_o, BRAND_REWARD / 2, "BRANDED SLAIN")
	if game.events != null:
		game.events.on_bot_eliminated(victim)
	# A fallen boss gives Gifts: a Revenant to whoever felled it, a Colossus
	# to everyone who stood against it. (In the Ordeal the altars give them.)
	if victim is Revenant and game.ordeal == null:
		var takers: Array = []
		if killer_o >= 0:
			takers.append(killer_o)
		if victim is Colossus:
			if game.player != null and game.player.alive and game.player.global_position.distance_to(victim.global_position) < 90.0 and not takers.has(0):
				takers.append(0)
			for id in game.humans:
				var h = game.humans[id]
				if h != null and is_instance_valid(h) and (h as Bot).alive and (h as Node3D).global_position.distance_to(victim.global_position) < 90.0 and not takers.has(int(id)):
					takers.append(int(id))
		for o2 in takers:
			give_gift(int(o2))
			if victim is Colossus and int(o2) == killer_o:
				give_gift(int(o2))
	if victim.has_meta("writ_mark"):
		var o := int(victim.get_meta("writ_mark"))
		victim.remove_meta("writ_mark")
		if active.has(o) and active[o].get("target") == victim:
			if killer_o == o:
				# The champion's kit is worth having.
				var base: Vector3 = game.ground_at(victim.global_position)
				game._spawn_loot("armor", "3", base + Vector3(0.9, 0.08, 0.3))
				game._spawn_loot("med", "", base + Vector3(-0.7, 0.08, 0.5))
				_end(o, true, "MARK SLAIN")
			else:
				var by := "THE STORM"
				if src != null and is_instance_valid(src) and src.has_method("display_name"):
					by = str(src.call("display_name"))
				_end(o, false, "YOUR MARK FELL TO %s" % by)


# -------------------------------------------------------------- branded --

func _count_kill(o: int) -> void:
	var now: float = game.match_time
	var times: Array = _kill_times.get(o, [])
	times.append(now)
	times = times.filter(func(t): return now - float(t) <= BRAND_WINDOW)
	_kill_times[o] = times
	if times.size() >= BRAND_KILLS and not branded.has(o):
		_kill_times[o] = []
		brand(o)


## Mark owner `o` as Branded (too many kills, or the Oath of the Hunted).
func brand(o: int) -> void:
	if branded.has(o):
		return
	if true:
		branded[o] = BRAND_TIME
		_brand_call = 0.0
		_send_event(o, {"ev": "branded", "t": BRAND_TIME})
		# Everyone else hears of it.
		var who := ""
		if game.net_on():
			who = str(game.net.my_name) if o == 0 else str(game.net.roster.get(o, "A PLAYER"))
		if game.net_on():
			for pid in game.net.roster:
				if int(pid) != o and int(pid) != 1:
					game.net.send_writ_event(int(pid), {"ev": "brand_other", "who": who})
			if o != 0:
				apply_event({"ev": "brand_other", "who": who})


func _brand_tick(dt: float) -> void:
	if branded.is_empty():
		return
	_brand_call -= dt
	var call := _brand_call <= 0.0
	if call:
		_brand_call = 15.0
	for o in branded.keys():
		var oi := int(o)
		if not _owner_alive(oi):
			_unbrand(oi, false)
			continue
		branded[o] = float(branded[o]) - dt
		var at := _owner_pos(oi)
		if call and at != Vector3.INF:
			# They know where you are: soldiers within 500 m come hunting, and
			# the other players see you on their maps.
			var n := 0
			for b in game.bots:
				if n >= 10:
					break
				if is_instance_valid(b) and b.alive and b.armed and not b.is_human and not b.puppet and b.state == Bot.State.GROUND \
						and b.global_position.distance_to(at) < 500.0:
					b.roam_point = Vector2(at.x, at.z) + Vector2(randf_range(-15, 15), randf_range(-15, 15))
					b.heard_pos = at
					b.alert_timer = 10.0
					n += 1
			var pts := [Vector2(at.x, at.z)]
			if game.net_on():
				for pid in game.net.roster:
					if int(pid) != oi and int(pid) != 1:
						game.net.send_writ_event(int(pid), {"ev": "reveal_brand", "pts": pts})
				if oi != 0:
					apply_event({"ev": "reveal_brand", "pts": pts})
		if float(branded[o]) <= 0.0:
			_unbrand(oi, true)


func _unbrand(o: int, survived: bool) -> void:
	if not branded.has(o):
		return
	branded.erase(o)
	if survived:
		award(o, BRAND_REWARD, "SURVIVED BRANDED")
	_send_event(o, {"ev": "unbranded", "won": survived})


## Host: a power for the rest of the match, one they do not have yet.
func give_gift(o: int) -> void:
	var have: Array = _gifted.get(o, [])
	var pool: Array = GIFTS.keys().filter(func(k): return not have.has(k))
	if pool.is_empty():
		return
	var k: String = pool[randi() % pool.size()]
	have.append(k)
	_gifted[o] = have
	_send_event(o, {"ev": "gift", "kind": k})


## A chosen Gift (the Ordeal's altars).
func give_gift_kind(o: int, k: String) -> void:
	if not GIFTS.has(k):
		return
	var have: Array = _gifted.get(o, [])
	if not have.has(k):
		have.append(k)
	_gifted[o] = have
	_send_event(o, {"ev": "gift", "kind": k})


func award(o: int, n: int, why: String) -> void:
	purse[o] = int(purse.get(o, 0)) + n
	if o == 0:
		_embers_here(int(purse[o]), n, why)
	elif game.net_on():
		game.net.send_embers(o, int(purse[o]), n, why)


## Spend Embers (Wayshrines). False if there are not enough.
func spend(o: int, n: int) -> bool:
	if int(purse.get(o, 0)) < n:
		return false
	purse[o] = int(purse[o]) - n
	if o == 0:
		_embers_here(int(purse[o]), -n, "")
	elif game.net_on():
		game.net.send_embers(o, int(purse[o]), -n, "")
	return true


func _end(o: int, won: bool, why: String, tell := true) -> void:
	var w: Dictionary = active.get(o, {})
	if w.is_empty():
		return
	active.erase(o)
	var b = w.get("target")
	if b != null and is_instance_valid(b) and (b as Bot).has_meta("writ_mark"):
		(b as Bot).remove_meta("writ_mark")
	if not tell:
		return
	var kind := str(w.kind)
	if won:
		award(o, REWARD[kind], TITLE[kind])
	_send_view(o, {})
	_send_event(o, {"ev": "done" if won else "fail", "kind": kind, "why": why, "reward": REWARD[kind] if won else 0})


## Turn the host's writ into what its owner's HUD shows.
func _refresh(o: int, w: Dictionary) -> void:
	var kind := str(w.kind)
	var v := {"kind": kind, "title": TITLE[kind], "t": float(w["t"])}
	match kind:
		"blood":
			v["line"] = "HUNT %s" % str(w.get("name", "THE MARK"))
			if w.has("c"):
				v["c"] = w["c"]
				v["r"] = w["r"]
			if bool(w.get("close", false)) and w.has("pt"):
				v["pt"] = w["pt"]
				v["line"] = "%s IS CLOSE" % str(w.get("name", "THE MARK"))
		"relic":
			var st := int(w["stage"])
			v["c"] = w["c"]
			v["r"] = RELIC_RINGS[st]
			if st == RELIC_RINGS.size() - 1:
				v["line"] = "DIG WHERE THE GROUND GLOWS"
				v["act"] = "dig"
				v["act_pos"] = w.site
				v["mound"] = w.site
			else:
				v["line"] = "SEARCH THE CIRCLE  (%d / %d)" % [st + 1, RELIC_RINGS.size()]
		"beacon":
			var site: Vector3 = w.site
			v["pt"] = site + Vector3.UP * 3.0
			v["beacon"] = site
			if int(w["stage"]) == 0:
				v["line"] = "CLIMB TO THE BEACON AND LIGHT IT"
				v["act"] = "light"
				v["act_pos"] = site
			else:
				v["lit"] = true
				v["hold"] = float(w["hold"])
				v["line"] = ("HOLD THE BEACON  %d s" % int(ceil(float(w["hold"])))) if bool(w.get("inside", true)) else "GET BACK TO THE BEACON!"
				v["c"] = Vector2(site.x, site.z)
				v["r"] = HOLD_RADIUS
	_send_view(o, v)


func _send_view(o: int, v: Dictionary) -> void:
	if o == 0:
		apply_view(v)
	elif game.net_on():
		game.net.send_writ_view(o, v)


func _send_event(o: int, e: Dictionary) -> void:
	if o == 0:
		apply_event(e)
	elif game.net_on():
		game.net.send_writ_event(o, e)


func _tell(o: int, text: String) -> void:
	_send_event(o, {"ev": "say", "why": text})


# ------------------------------------------------------- this machine ----

func apply_view(v: Dictionary) -> void:
	view = v
	game.hud.set_writ(v)
	_sync_sites()


func apply_event(e: Dictionary) -> void:
	var hud: HUD = game.hud
	match str(e.get("ev", "")):
		"take":
			game.sfx.play_ui("writ_take", -3.0)
			var kind := str(e.kind)
			hud.show_big(TITLE[kind], TINT[kind], 2.4)
			hud.show_notice("%s  —  TAKEN AT %s" % [BLURB[kind], str(e.get("town", ""))], 3.0)
		"ping":
			game.sfx.play_ui("writ_ping", -10.0)
		"close":
			game.sfx.play_ui("writ_ping", -6.0)
			hud.show_notice("YOUR MARK IS CLOSE  —  MARKED ON YOUR SCREEN", 2.6)
		"lit":
			hud.show_big("THE BEACON IS LIT", TINT["beacon"], 2.2)
			hud.show_notice("HOLD IT FOR %d SECONDS  —  THEY HAVE SEEN THE FIRE" % int(HOLD_TIME), 3.0)
		"done":
			game.match_tally["writs"] = int(game.match_tally.get("writs", 0)) + 1
			game.sfx.play_ui("writ_done", -2.0)
			hud.show_big("WRIT FULFILLED", Color(1.0, 0.82, 0.38), 3.2)
			hud.show_notice("%s   ·   +%d EMBERS" % [str(e.get("why", "")), int(e.get("reward", 0))], 3.5)
			hud.killfeed("%s FULFILLED  +%d" % [TITLE.get(str(e.get("kind", "")), "WRIT"), int(e.get("reward", 0))], Color(1.0, 0.82, 0.38))
		"fail":
			game.sfx.play_ui("writ_fail", -3.0)
			hud.show_big("WRIT FAILED", HUD.DANGER, 2.6)
			hud.show_notice(str(e.get("why", "")), 3.0)
		"say":
			hud.show_notice(str(e.get("why", "")), 2.6)
		"branded":
			my_brand = float(e.get("t", BRAND_TIME))
			hud.branded_t = my_brand
			game.sfx.play_ui("writ_fail", -2.0)
			hud.show_big("BRANDED", HUD.DANGER, 3.0)
			hud.show_notice("TOO MANY KILLS TOO FAST  —  EVERYONE KNOWS WHERE YOU ARE. SURVIVE %d SECONDS" % int(BRAND_TIME), 4.0)
		"unbranded":
			my_brand = 0.0
			hud.branded_t = 0.0
			if bool(e.get("won", false)):
				game.sfx.play_ui("writ_done", -4.0)
				hud.show_big("THE BRAND FADES", Color(1.0, 0.82, 0.38), 2.6)
				hud.show_notice("YOU SURVIVED BRANDED   ·   +%d EMBERS" % BRAND_REWARD, 3.0)
		"brand_other":
			hud.killfeed("%s %s BRANDED  —  HUNT THEM FOR EMBERS" % [str(e.get("who", "")), "IS"], HUD.DANGER)
		"reveal_brand":
			hud.reveal(e.get("pts", []), 6.0)
		"sigil":
			my_sigils = int(e.get("n", 0))
			hud.set_sigils(my_sigils)
			if str(e.get("why", "")) != "":
				hud.show_notice(str(e.get("why", "")), 3.5)
		"gift":
			var gk := str(e.get("kind", ""))
			if GIFTS.has(gk) and game.player != null:
				game.player.gifts[gk] = true
				if gk == "aegis":
					game.player.aegis = game.player.AEGIS_MAX
				if gk == "titan":
					game.player.hp = minf(game.player.max_hp(), game.player.hp + 50.0)
					game.player._emit_health()
				game.sfx.play_ui("vault_open", -6.0)
				hud.show_big("GIFT:  %s" % str(GIFTS[gk][0]), Color(1.0, 0.86, 0.45), 3.4)
				hud.show_notice("%s  —  FOR THE REST OF THE MATCH" % str(GIFTS[gk][1]), 5.0)
		"chest":
			if game.chests != null:
				game.chests.apply_state(int(e.get("i", -1)), str(e.get("st", "")))
		"mimic":
			if game.chests != null:
				game.chests.tell_mimic()
		"hollow":
			if game.hollow != null:
				game.hollow.apply_state(e)
		"boss_fx":
			Colossus.show_fx(game, e.get("fx", {}))
		"idol_used":
			var ii := int(e.get("i", -1))
			if ii >= 0 and ii < idol_used.size():
				idol_used[ii] = true
				if ii < _idol_eyes.size() and is_instance_valid(_idol_eyes[ii]):
					_idol_eyes[ii].visible = false
		"blessing":
			var bk := str(e.get("kind", ""))
			if BLESSINGS.has(bk) and game.player != null:
				game.player.blessings[bk] = true
				game.match_tally["blessings"] = int(game.match_tally.get("blessings", 0)) + 1
				if bk == "vigour":
					game.player.hp = minf(game.player.max_hp(), game.player.hp + 25.0)
					game.player._emit_health()
				game.sfx.play_ui("writ_done", -6.0)
				hud.show_big("BLESSED: %s" % str(BLESSINGS[bk][0]), Color(0.6, 1.0, 0.78), 3.0)
				hud.show_notice("%s  —  %s, FOR THE REST OF THE MATCH" % [str(e.get("god", "")), str(BLESSINGS[bk][1])], 4.0)
				var names: Array = []
				for k in game.player.blessings:
					names.append(str(BLESSINGS.get(k, [k])[0]))
				hud.set_blessings(names)
		"island":
			if game.events != null:
				game.events.apply(str(e.get("kind", "")), e.get("data", {}))
		"bought":
			game.sfx.play_ui("shrine_buy", -4.0)
			hud.show_notice("%s  —  LAID ON THE OFFERING STONE" % str(e.get("what", "")), 2.4)
		"reveal":
			var pts: Array = e.get("pts", [])
			hud.reveal(pts, 10.0)
			hud.show_big("RAVEN'S EYE", Color(0.75, 0.6, 1.0), 2.0)
			hud.show_notice("%d SOLDIER%s WITHIN %d M  —  ON YOUR MAP" % [pts.size(), "" if pts.size() == 1 else "S", int(RAVEN_RANGE)], 3.0)


func _embers_here(total: int, gain: int, why: String) -> void:
	my_embers = total
	if why == "REVENANT FELLED" or why.begins_with("REVENANT"):
		game.match_tally["revenants"] = int(game.match_tally.get("revenants", 0)) + 1
	elif why == "VAULT OPENED":
		game.match_tally["vaults"] = int(game.match_tally.get("vaults", 0)) + 1
	game.hud.set_embers(total, gain, why)
	if shop >= 0:
		game.hud.show_shop(_priced_wares(), my_embers)
	if gain > 0:
		game.sfx.play_ui("ember", -12.0 if gain < 300 else -6.0)


# ---------------------------------------------------- site props (local) --

func _clear_sites() -> void:
	for k in _site_nodes:
		var n = _site_nodes[k]
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
	_site_nodes.clear()
	_beacon_fire = null


## Build or remove the dig mound and the beacon to match our writ.
func _sync_sites() -> void:
	var want_mound: bool = view.has("mound")
	var want_beacon: bool = view.has("beacon")
	if not want_mound and _site_nodes.has("mound"):
		(_site_nodes["mound"] as Node).queue_free()
		_site_nodes.erase("mound")
	if want_mound and not _site_nodes.has("mound"):
		_site_nodes["mound"] = _make_mound(view["mound"])
	if not want_beacon and _site_nodes.has("beacon"):
		(_site_nodes["beacon"] as Node).queue_free()
		_site_nodes.erase("beacon")
		_beacon_fire = null
	if want_beacon and not _site_nodes.has("beacon"):
		_site_nodes["beacon"] = _make_beacon(view["beacon"])
	if _beacon_fire != null and bool(view.get("lit", false)) and not _beacon_fire.visible:
		_beacon_fire.visible = true
		game.sfx.play_at("beacon_light", (_site_nodes["beacon"] as Node3D).global_position + Vector3.UP * 2.0, 2.0)


func _mat(c: Color, emit := 0.0, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
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


## Freshly turned earth with a faint golden glow seeping out of it.
func _make_mound(at: Vector3) -> Node3D:
	var root := Node3D.new()
	game.add_child(root)
	root.global_position = at
	var soil := _mat(Color(0.24, 0.17, 0.11), 0.0, 0.95)
	for i in 7:
		var a := TAU * float(i) / 7.0
		_box(root, Vector3(0.7, 0.22, 0.55), Vector3(cos(a) * 0.55, 0.06, sin(a) * 0.55), soil, Vector3(0.0, a, 0.15))
	_box(root, Vector3(1.0, 0.3, 1.0), Vector3(0, 0.1, 0), soil)
	var glow := _mat(Color(1.0, 0.75, 0.3), 3.5)
	for i in 3:
		_box(root, Vector3(0.06, 0.04, 0.4), Vector3(randf_range(-0.3, 0.3), 0.26, randf_range(-0.3, 0.3)), glow, Vector3(0, randf() * PI, 0))
	MeshMerge.merge(root, [])
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.35)
	light.light_energy = 1.4
	light.omni_range = 5.0
	light.position = Vector3(0, 0.6, 0)
	light.shadow_enabled = false
	root.add_child(light)
	root.set_meta("light", light)
	# A shovel left stuck in the earth.
	var shovel := Node3D.new()
	shovel.position = Vector3(0.7, 0.0, -0.3)
	shovel.rotation = Vector3(0.25, 0.6, 0.1)
	root.add_child(shovel)
	_box(shovel, Vector3(0.04, 1.1, 0.04), Vector3(0, 0.7, 0), _mat(Color(0.42, 0.28, 0.16)))
	_box(shovel, Vector3(0.24, 0.3, 0.02), Vector3(0, 0.1, 0), _mat(Color(0.3, 0.3, 0.32), 0.0, 0.4))
	MeshMerge.merge(shovel, [])
	return root


## A hilltop beacon: a stone plinth, an iron fire basket full of pitch-soaked
## wood. When lit: flames, a big warm light and a column of smoke.
func _make_beacon(at: Vector3) -> Node3D:
	var root := Node3D.new()
	game.add_child(root)
	root.global_position = at
	var stone := _mat(Color(0.46, 0.45, 0.43), 0.0, 0.95)
	var iron := _mat(Color(0.12, 0.12, 0.13), 0.0, 0.5)
	iron.metallic = 0.6
	var wood := _mat(Color(0.3, 0.2, 0.12))
	_box(root, Vector3(2.2, 0.5, 2.2), Vector3(0, 0.1, 0), stone)
	_box(root, Vector3(1.6, 0.9, 1.6), Vector3(0, 0.75, 0), stone)
	_box(root, Vector3(0.5, 1.2, 0.5), Vector3(0, 1.75, 0), stone)
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		_box(root, Vector3(0.06, 0.9, 0.06), Vector3(cos(a) * 0.55, 2.7, sin(a) * 0.55), iron, Vector3(-sin(a) * 0.3, 0, cos(a) * 0.3))
	_box(root, Vector3(0.9, 0.06, 0.9), Vector3(0, 2.35, 0), iron)
	for k in 2:
		_box(root, Vector3(1.4, 0.05, 1.4), Vector3(0, 2.55 + float(k) * 0.55, 0), iron, Vector3(0, PI * 0.25 * float(k), 0))
	for i in 6:
		_box(root, Vector3(0.12, 0.9, 0.12), Vector3(randf_range(-0.25, 0.25), 2.75, randf_range(-0.25, 0.25)), wood, Vector3(randf_range(-0.5, 0.5), randf() * PI, randf_range(-0.5, 0.5)))
	MeshMerge.merge(root, [])
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.6, 1.4, 1.6)
	cs.shape = sh
	cs.position = Vector3(0, 0.6, 0)
	body.add_child(cs)
	root.add_child(body)
	# The fire, hidden until it is lit.
	var fire := Node3D.new()
	fire.position = Vector3(0, 3.0, 0)
	fire.visible = false
	root.add_child(fire)
	var flame := _mat(Color(1.0, 0.55, 0.18), 6.0)
	flame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 3:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1.1, 1.8)
		q.mesh = qm
		q.material_override = flame
		q.rotation.y = PI / 3.0 * float(i)
		q.position.y = 0.6
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fire.add_child(q)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.62, 0.3)
	light.light_energy = 4.0
	light.omni_range = 26.0
	light.position.y = 1.2
	fire.add_child(light)
	_beacon_fire = fire
	return root


func _animate_sites(delta: float) -> void:
	_flicker += delta
	if _site_nodes.has("mound"):
		var m := _site_nodes["mound"] as Node3D
		var l := m.get_meta("light") as OmniLight3D
		l.light_energy = 1.2 + sin(_flicker * 3.1) * 0.35
	if _beacon_fire != null and is_instance_valid(_beacon_fire) and _beacon_fire.visible:
		var f := 1.0 + sin(_flicker * 13.0) * 0.08 + sin(_flicker * 7.3) * 0.06
		_beacon_fire.scale = Vector3(1.0, f, 1.0)
		var light := _beacon_fire.get_child(_beacon_fire.get_child_count() - 1) as OmniLight3D
		light.light_energy = 3.6 + sin(_flicker * 11.0) * 0.6
		if fmod(_flicker, 0.9) < delta:
			game.spawn_smoke(_beacon_fire.global_position + Vector3.UP * 1.5, 0.8)
