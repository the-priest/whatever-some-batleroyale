extends Node3D

# BLOCK ROYALE — match orchestrator.
# menu -> plane -> freefall -> ground -> win / eliminated

const BOT_NAMES := [
	"RAVEN", "GHOST", "BOLT", "VEX", "SABLE", "NOMAD", "CINDER", "HALO",
	"TALON", "DRIFT", "ECHO", "FLINT", "ONYX", "PIKE", "RUNE", "SLATE",
	"THORN", "VOID", "WREN", "ZERO", "ASH", "BRICK", "COBRA", "DUSK",
	"ANVIL", "BADGER", "CROW", "DAGGER", "EMBER", "FALCON", "GRIT", "HAWK",
	"IRON", "JACKAL", "KNOX", "LYNX", "MAMBA", "NOVA", "ORCA", "PROWLER",
	"QUILL", "REAPER", "STEEL", "TUNDRA", "UMBRA", "VIPER", "WOLF", "XENON",
	"YARROW", "ZULU", "BISHOP", "DOZER", "FROST", "GUNNER", "HUNTER", "KILO",
	"MAVERICK", "ROOK", "SHADE", "TANGO",
]
const WEAPON_DROP_WEIGHTS := {
	"pistol": 12, "m1911": 9, "smg": 14, "grease": 10, "shotgun": 11, "autoshotgun": 4,
	"rifle": 13, "carbine": 12, "bullpup": 6, "lmg": 3, "dmr": 5, "m24": 4, "axmc": 1,
}
const AIRDROP_WEAPONS := ["sniper", "sniper", "axmc", "lmg"]
const HI_WEAPONS := ["dmr", "m24", "carbine", "bullpup", "rifle", "lmg", "axmc"]
const HI_GEAR := [["scope", "4x"], ["scope", "8x"], ["armor", "2"], ["helmet", "2"], ["armor", "3"], ["med", ""], ["scope", "2x"], ["ammo", "7.62"], ["ammo", "5.56"]]
## Floor loot table for non-weapon spots: [kind, id, weight].
const GEAR_TABLE := [
	["ammo", "", 16.0], ["bandage", "", 15.0], ["med", "", 7.0], ["energy", "", 7.0],
	["armor", "1", 8.0], ["armor", "2", 4.0], ["armor", "3", 1.2],
	["helmet", "1", 8.0], ["helmet", "2", 4.0], ["helmet", "3", 1.2],
	["scope", "reddot", 6.0], ["scope", "2x", 5.0], ["scope", "4x", 3.0], ["scope", "8x", 1.2],
	["extmag", "", 4.5], ["comp", "", 4.5], ["grenade", "", 7.0],
]
const SETTINGS_PATH := "user://settings.cfg"
## Start in fullscreen (F11 / Alt + Enter or Settings switch it).
var fullscreen := true
## Upscaling: 0 native, 1 FSR quality, 2 FSR balanced, 3 FSR performance.
var upscaling := 0
var vsync := true
var show_fps := true
## Choice settings (HUD.OPTS): key -> index.
var options: Dictionary = {}
const HEAR_RANGE := 70.0
const PING_RANGE := 160.0

var world: WorldBuilder
var wildlife: Wildlife = null
var terrain: Terrain
var player: Player
var plane: DropPlane
var zone: Zone
var hud: HUD
var sfx: Sfx
var ballistics: Ballistics
var menu_cam: Camera3D

var phase := "boot"      # boot | menu | plane | playing | end
var match_size := 64
const PLANE_ALT := 520.0
var MAX_BOTS := 49
var lobby_ready := false
var seed_value := 20261101
var loot_pool: Array = []
## Loot bucketed by 24 m cells so "what is near me" never scans the island.
var loot_grid: Dictionary = {}
const LOOT_CELL := 24.0


func _loot_cell(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / LOOT_CELL)), int(floor(p.z / LOOT_CELL)))


## Live (valid, not taken) loot within roughly `r` of `pos` (cell accuracy:
## callers still check exact distance).
func loot_near(pos: Vector3, r: float) -> Array:
	var out: Array = []
	var a := _loot_cell(pos - Vector3(r, 0, r))
	var b := _loot_cell(pos + Vector3(r, 0, r))
	for cz in range(a.y, b.y + 1):
		for cx in range(a.x, b.x + 1):
			var cell = loot_grid.get(Vector2i(cx, cz))
			if cell == null:
				continue
			for l in cell:
				if is_instance_valid(l) and not l.taken:
					out.append(l)
	return out
var bots: Array = []
var airdrops: Array = []
var alive := 1
var total_players := 1
var player_kills := 0
var damage_dealt := 0.0
var match_time := 0.0
var survive_time := 0.0
var zone_acc := 0.0
var zone_was_warning := false
var winner := false
var plane_start := Vector3.ZERO
var plane_end := Vector3.ZERO
var menu_angle := 0.0
var tracers: Array = []
var impacts: Array = []
var cam_shake := 0.0
var menu_t := 0.0
var last_hud_alive := -1
var end_cam_target: Node3D = null
var end_cam_spot := Vector3.ZERO
var end_cam_angle := 0.0
var mouse_sens := 1.0
var scope_sens := 1.0
var volume := 0.8
var fov := 82.0
var loadout_primary := "carbine"
var loadout_secondary := "pistol"
var loadout_optic := "reddot"
var loadout_enabled := true
var _loot_label_t := 0.0
var _last_best: LootPickup = null
var _lit_loot: Array = []
var _wind: AudioStreamPlayer3D = null
var net: Net
var anticheat: AntiCheat
var wardens: Array = []
var _dark_saved: Array = []
## Host: names of players caught cheating this session (they stay hunted).
var condemned_names: Dictionary = {}
var music: Music
var music_menu := 0.7
var music_match := 0.35
var graphics_quality := 2
var lobby: LobbyUI
## Remote humans in the current LAN match: peer id -> puppet.
var humans: Dictionary = {}
var loot_by_id: Dictionary = {}
var _next_loot_id := 1
var _net_dummy: Node
var _net_setup_ok := false
## True while a text box (chat) owns the keyboard.
var input_locked := false
var vehicles: Array = []
var _match_vehicles: Array = []
var _match_weather := "clear"
var _veh_cam_yaw := 0.0
var _veh_last_yaw := 0.0
var _veh_idle_t := 0.0
## Tests drive the jeep themselves.
var _drive_scripted := false
## Map / world markers per player id: {pos, t}.
var waypoints: Dictionary = {}
var _social_t := 0.0
var _shot_tab: bool = OS.get_cmdline_user_args().has("--tab")


func _ready() -> void:
	randomize()
	seed_value = 100000 + int(Time.get_unix_time_from_system()) % 899999
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_value = int(a.substr(7))
	sfx = Sfx.new()
	sfx.name = "Sfx"
	sfx.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(sfx)
	ballistics = Ballistics.new()
	ballistics.name = "Ballistics"
	ballistics.game = self
	add_child(ballistics)
	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.play_pressed.connect(_start_match_ui)
	hud.resume_pressed.connect(_resume)
	hud.quit_pressed.connect(_quit_to_menu)
	hud.settings_changed.connect(_on_settings_changed)
	hud.loadout_changed.connect(_on_loadout_changed)
	hud.keys_changed.connect(func():
		_save_settings())
	hud.scope_sens_changed.connect(func(v: float):
		scope_sens = v
		_apply_settings()
		_save_settings())
	hud.show_menu("GENERATING ISLAND ...")
	music = Music.new()
	music.name = "Music"
	add_child(music)
	music.track_started.connect(func(t): hud.now_playing(t))
	hud.music_changed.connect(func(a, b):
		music_menu = a
		music_match = b
		music.set_volumes(a, b)
		_save_settings())
	hud.music_skip.connect(func(): music.skip())
	hud.option_changed.connect(func(key, value):
		options[key] = value
		_apply_options()
		if key in ["shadows", "lighting", "reflections", "ao", "fog", "bloom", "aa", "draw", "grass", "brightness"]:
			_apply_graphics()
		_save_settings())
	hud.video_changed.connect(func(up, vs, fps):
		upscaling = up
		vsync = vs
		show_fps = fps
		_apply_vsync()
		_apply_graphics()
		_save_settings())
	hud.fullscreen_changed.connect(func(on):
		fullscreen = on
		_save_settings())
	hud.graphics_changed.connect(func(q):
		graphics_quality = q
		_apply_graphics()
		_save_settings())
	_load_settings()
	net = Net.new()
	net.name = "Net"
	net.game = self
	add_child(net)
	anticheat = AntiCheat.new()
	anticheat.name = "AntiCheat"
	add_child(anticheat)
	anticheat.setup(self)
	lobby = LobbyUI.new()
	lobby.setup(hud, net, self)
	hud.root.add_child(lobby)
	lobby.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lobby.z_index = 30
	lobby.host_pressed.connect(func(_n): _net_host())
	lobby.join_pressed.connect(func(a, _n): net.join(a))
	lobby.start_pressed.connect(func(): net.start_countdown(5))
	lobby.leave_pressed.connect(_net_leave)
	lobby.squad_toggled.connect(func(v): net.set_setting("squad", v))
	net.chat.connect(_on_net_chat)
	net.marker.connect(_on_net_marker)
	hud.chat_sent.connect(func(t): net.send_chat(t))
	hud.chat_closed.connect(func(): input_locked = false)
	hud.map_clicked.connect(_on_map_clicked)
	hud.host_lan_pressed.connect(_net_host)
	hud.join_lan_pressed.connect(func(): lobby.show_join())
	net.multiplayer.connected_to_server.connect(func(): lobby.show_lobby())
	net.left_session.connect(_on_left_session)
	net.reconnect_state.connect(_on_reconnect_state)
	_net_dummy = Node.new()
	_net_dummy.set_script(load("res://scripts/net_name.gd"))
	add_child(_net_dummy)

	menu_cam = Camera3D.new()
	menu_cam.fov = 68.0
	menu_cam.near = 0.1
	menu_cam.far = 6000.0
	add_child(menu_cam)
	menu_cam.make_current()

	await get_tree().process_frame
	await _build_world()
	_create_player()
	lobby_ready = true
	phase = "menu"
	_show_menu()
	_refresh_places()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if OS.get_cmdline_user_args().has("--smoke"):
		_run_smoke()
	elif OS.get_cmdline_user_args().has("--sim"):
		_run_sim()
	elif OS.get_cmdline_user_args().has("--cycle"):
		_run_cycle()
	elif OS.get_cmdline_user_args().has("--perf"):
		_run_perf()
	elif OS.get_cmdline_user_args().has("--shot"):
		_run_shot()
	elif OS.get_cmdline_user_args().has("--houses"):
		_run_house_walk_test()
	elif OS.get_cmdline_user_args().has("--swim"):
		_run_swim_test()
	elif OS.get_cmdline_user_args().has("--fantasy"):
		_run_fantasy_test()
	elif OS.get_cmdline_user_args().has("--raybench"):
		await get_tree().physics_frame
		await get_tree().physics_frame
		var sp := get_world_3d().direct_space_state
		var rr := RandomNumberGenerator.new()
		rr.seed = 7
		var hits := 0
		var t0 := Time.get_ticks_usec()
		for i in 40000:
			var x := rr.randf_range(-900.0, 900.0)
			var z := rr.randf_range(-900.0, 900.0)
			var y: float = terrain.height_at(x, z) + 1.5
			var a := Vector3(x, y, z)
			var d := Vector3(rr.randf_range(-1, 1), rr.randf_range(-0.05, 0.05), rr.randf_range(-1, 1)).normalized()
			if not sp.intersect_ray(PhysicsRayQueryParameters3D.create(a, a + d * 60.0, 1)).is_empty():
				hits += 1
		print("[raybench] 40000 rays in %.1f ms, %d hits" % [(Time.get_ticks_usec() - t0) / 1000.0, hits])
		get_tree().quit()
	elif OS.get_cmdline_user_args().has("--shootthru"):
		_run_shoot_through_test()
	elif OS.get_cmdline_user_args().has("--camp"):
		_run_camp_test()
	elif OS.get_cmdline_user_args().has("--gunaudio"):
		_run_gun_audio_test()
	elif OS.get_cmdline_user_args().has("--bottree"):
		_run_bot_tree_test()
	elif OS.get_cmdline_user_args().has("--treeshoot"):
		_run_tree_shoot_test()
	elif OS.get_cmdline_user_args().has("--botvsyou"):
		_run_bot_vs_player_test()
	elif OS.get_cmdline_user_args().has("--botfight"):
		_run_botfight_test()
	elif OS.get_cmdline_user_args().has("--corpse"):
		_run_corpse_test()
	elif OS.get_cmdline_user_args().has("--botstairs"):
		_run_bot_stairs_test()
	elif OS.get_cmdline_user_args().has("--stairs"):
		_run_stairs_test()
	elif OS.get_cmdline_user_args().has("--mantle"):
		_run_mantle_test()
	elif OS.get_cmdline_user_args().has("--drive"):
		_run_drive_test()
	elif OS.get_cmdline_user_args().has("--carexit"):
		_run_carexit_test()
	elif OS.get_cmdline_user_args().has("--cheattest"):
		_run_cheat_test()
	elif OS.get_cmdline_user_args().has("--windows"):
		_run_window_test()
	elif OS.get_cmdline_user_args().has("--gpubench"):
		_run_gpu_bench()
	elif OS.get_cmdline_user_args().has("--lootaudit"):
		_run_loot_audit()
	elif OS.get_cmdline_user_args().has("--loose"):
		_run_loose_audit()
	elif OS.get_cmdline_user_args().has("--netstress"):
		_run_net_stress(OS.get_environment("NET_ROLE") == "host")
	elif OS.get_cmdline_user_args().has("--netattack"):
		_run_net_attack(OS.get_environment("NET_ROLE") == "host")
	elif OS.get_cmdline_user_args().has("--nethost"):
		_run_net_test(true)
	elif OS.get_cmdline_user_args().has("--netjoin"):
		_run_net_test(false)


func _refresh_places() -> void:
	hud.set_world_map(world)
	var places: Array = []
	for v in world.villages.village_pads:
		if str(v.name) != "":
			places.append([v.name, v.center, "town"])
	for t in world.villages.towers:
		places.append(["LOOKOUT", t.center, "tower"])
	for p in world.villages.poi_pads:
		if p.type == "ruin":
			places.append(["RUINS", p.center, "ruin"])
	for l in world.villages.landmarks.labels:
		places.append([l[0], l[1], "landmark"])
	hud.set_places(places)


func _show_menu() -> void:
	hud.set_match_size(MAX_BOTS + 1)
	hud.show_menu("SEED  %d   ·   %d LOOT SPOTS   ·   %d PLAYERS" % [seed_value, world.loot_points.size(), MAX_BOTS + 1])


func _build_world() -> void:
	var t0 := Time.get_ticks_msec()
	world = WorldBuilder.new()
	world.name = "World"
	add_child(world)
	world.progress.connect(hud.show_loading)
	await world.build(seed_value)
	terrain = world.terrain
	if wildlife == null:
		wildlife = Wildlife.new()
		wildlife.name = "Wildlife"
		add_child(wildlife)
	wildlife.setup(self)
	_apply_graphics()
	print("[game] world seed %d built in %d ms, loot=%d" % [seed_value, Time.get_ticks_msec() - t0, world.loot_points.size()])
	# The bots' walking grid, while the loading screen is still up.
	var tn := Time.get_ticks_msec()
	hud.show_loading("MAPPING THE PATHS", 0.96)
	await get_tree().process_frame
	terrain.build_nav()
	print("[game] bot walking grid in %d ms, %d of %d cells too steep" % [Time.get_ticks_msec() - tn, terrain.nav_blocked, Terrain.RES * Terrain.RES])
	hud.hide_loading()


func _create_player() -> void:
	player = Player.new()
	player.name = "Player"
	player.game = self
	add_child(player)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.health_changed.connect(_on_health_changed)
	player.weapon_changed.connect(_on_weapon_changed)
	player.ammo_changed.connect(_on_ammo_changed)
	player.hitmarker.connect(_on_hitmarker)
	player.damaged.connect(_on_player_damaged)
	player.died.connect(_on_player_died)
	player.notice.connect(_on_notice)
	player.inventory_changed.connect(_on_inventory_changed)
	player.mouse_sens = 0.0022 * mouse_sens
	_apply_options()
	menu_cam.make_current()


# ----------------------------------------------------------------- settings --
func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		mouse_sens = float(cfg.get_value("input", "sensitivity", 1.0))
		scope_sens = clampf(float(cfg.get_value("input", "scoped", 1.0)), 0.3, 2.0)
		match_size = int(cfg.get_value("match", "players", 64))
		volume = float(cfg.get_value("audio", "volume", 0.8))
		fov = float(cfg.get_value("video", "fov", 82.0))
		loadout_primary = str(cfg.get_value("loadout", "primary", loadout_primary))
		loadout_secondary = str(cfg.get_value("loadout", "secondary", loadout_secondary))
		loadout_optic = str(cfg.get_value("loadout", "optic", loadout_optic))
		loadout_enabled = bool(cfg.get_value("loadout", "enabled", loadout_enabled))
		music_menu = float(cfg.get_value("audio", "music_menu", music_menu))
		music_match = float(cfg.get_value("audio", "music_match", music_match))
		graphics_quality = clampi(int(cfg.get_value("video", "quality", graphics_quality)), 0, 3)
		fullscreen = bool(cfg.get_value("video", "fullscreen", true))
		upscaling = clampi(int(cfg.get_value("video", "upscaling", 0)), 0, 3)
		vsync = bool(cfg.get_value("video", "vsync", true))
		show_fps = bool(cfg.get_value("video", "show_fps", true))
		for k in HUD.OPTS:
			if cfg.has_section_key("options", k):
				options[k] = int(cfg.get_value("options", k))
		Keybinds.load_from(cfg)
		hud._key_labels()
	if not Weapons.DEFS.has(loadout_primary):
		loadout_primary = "carbine"
	if not Weapons.DEFS.has(loadout_secondary):
		loadout_secondary = "pistol"
	match_size = clampi(match_size, 10, 100)
	MAX_BOTS = match_size - 1
	hud.set_settings(mouse_sens, volume, fov, match_size)
	hud.scope_sens_slider.set_value_no_signal(scope_sens)
	hud.set_music(music_menu, music_match)
	hud.set_graphics(graphics_quality)
	hud.set_video(upscaling, vsync, show_fps)
	hud.set_options(options)
	options = hud.opts.duplicate()
	_apply_vsync()
	_apply_options()
	# Screenshots and tests keep the window they were given.
	var scripted := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			scripted = true
	if scripted:
		hud.fullscreen = fullscreen
	else:
		hud.set_fullscreen(fullscreen)
	if music != null:
		music.set_volumes(music_menu, music_match)
	hud.set_loadout(loadout_primary, loadout_secondary, loadout_optic, loadout_enabled)
	_apply_settings()


func _apply_settings() -> void:
	if player != null:
		player.mouse_sens = 0.0022 * mouse_sens
		player.scope_sens = scope_sens
		player.base_fov = fov
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, volume)))


func _on_settings_changed(sens: float, vol: float, p_fov: float, players: int) -> void:
	mouse_sens = sens
	volume = vol
	fov = p_fov
	match_size = players
	MAX_BOTS = players - 1
	if phase == "menu" and world != null:
		_show_menu()
	_apply_settings()
	_save_settings()


func _on_loadout_changed(p: String, s: String, o: String, e: bool) -> void:
	loadout_primary = p
	loadout_secondary = s
	loadout_optic = o
	loadout_enabled = e
	_save_settings()


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "sensitivity", mouse_sens)
	cfg.set_value("input", "scoped", scope_sens)
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("audio", "music_menu", music_menu)
	cfg.set_value("audio", "music_match", music_match)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("video", "quality", graphics_quality)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "upscaling", upscaling)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "show_fps", show_fps)
	for k in options:
		cfg.set_value("options", k, options[k])
	cfg.set_value("match", "players", match_size)
	cfg.set_value("loadout", "primary", loadout_primary)
	cfg.set_value("loadout", "secondary", loadout_secondary)
	cfg.set_value("loadout", "optic", loadout_optic)
	cfg.set_value("loadout", "enabled", loadout_enabled)
	Keybinds.save(cfg)
	cfg.save(SETTINGS_PATH)


## Drop-in kit: your chosen guns, a few boxes of their ammo, the optic.
func _give_loadout() -> void:
	if not loadout_enabled or player == null:
		return
	player.give_weapon(loadout_primary)
	player.give_weapon(loadout_secondary)
	var prim_slot := player.loadout.find(loadout_primary)
	for i in 3:
		player.add_ammo_cal(Weapons.caliber(loadout_primary), int(Weapons.AMMO_BOX.get(Weapons.caliber(loadout_primary), 30)))
	for i in 2:
		player.add_ammo_cal(Weapons.caliber(loadout_secondary), int(Weapons.AMMO_BOX.get(Weapons.caliber(loadout_secondary), 30)))
	if loadout_optic != "" and prim_slot >= 0 and Weapons.scope_fits(loadout_primary, loadout_optic):
		player.attachments[prim_slot]["scope"] = loadout_optic
	if prim_slot >= 0:
		player.select_slot(prim_slot)
	player.refresh_viewmodel()
	player.inventory_changed.emit()


func _resume() -> void:
	hud.show_pause(false)
	get_tree().paused = false
	if phase == "playing" or phase == "plane":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _quit_to_menu() -> void:
	if hud != null and hud.map_open():
		hud.set_map_open(false)
	hud.show_pause(false)
	get_tree().paused = false
	if net != null and net.active and net.hosting and net.match_running:
		net.match_running = false
		net._abort.rpc()
	if net != null and net.active and net.hosting:
		net.call_deferred("_send_roster")
	_cleanup_match()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.alive = false
	hud.pause_allowed = false
	hud.set_plane_path(Vector3.ZERO, Vector3.ZERO)
	phase = "menu"
	menu_cam.make_current()
	_show_menu()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if net != null and net.active:
		lobby.show_lobby()


# -------------------------------------------------------------------- match --
var _starting := false


## Starting a match takes a moment (loot, 60-odd soldiers): show it rather
## than freeze on the menu.
func _start_match_ui() -> void:
	if _starting:
		return
	_starting = true
	hud.show_loading("PREPARING THE DROP", 0.5)
	await get_tree().process_frame
	await get_tree().process_frame
	_start_match()
	hud.hide_loading()
	_starting = false


func _start_match() -> void:
	if not lobby_ready:
		return
	# In a LAN game only the host starts matches; clients follow its setup.
	if net != null and net.active and not net.hosting:
		return
	if net != null and net.active:
		lobby.close()
		humans.clear()
	sfx.play_ui("ui_click", -6.0)
	hud.hide_menu()
	hud.hide_end()
	hud.clear_killfeed()
	hud.set_spectate("")
	_cleanup_match()
	player.reset_for_match()
	anticheat.reset_match()
	player.global_position = Vector3(0, 120, 0)

	# Flight path across the island, offset so it does not always cross centre.
	var ang := randf() * TAU
	var dir := Vector3(cos(ang), 0.0, sin(ang))
	var side := Vector3(-dir.z, 0.0, dir.x) * randf_range(-320.0, 320.0)
	var mid := Vector3(Zone.MAP_MID.x, 0.0, Zone.MAP_MID.y)
	plane_start = mid - dir * 1450.0 + side + Vector3(0, PLANE_ALT + 8.0, 0)
	plane_end = mid + dir * 1450.0 + side + Vector3(0, PLANE_ALT, 0)
	plane = DropPlane.new()
	plane.name = "Plane"
	add_child(plane)
	plane.setup(plane_start, plane_end)
	hud.set_plane_path(plane_start, plane_end)

	menu_cam.make_current()
	phase = "plane"
	player.global_position = plane.seat_position()

	# Loot: every item settles on a real floor, clear of walls and props, and
	# keeps its distance from the others (no piles).
	loot_pool.clear()
	loot_grid.clear()
	_spot_hash.clear()
	var points := world.loot_points.duplicate()
	points.shuffle()
	var t_loot := Time.get_ticks_msec()
	var skipped := 0
	for p in points:
		var kind := str(p.get("kind", "weapon"))
		var hi := str(p.get("tier", "")) == "hi"
		var base := _loot_spot(Vector3(p["pos"]), 0.0, 1.3)
		if base == Vector3.INF:
			skipped += 1
			continue
		if kind == "weapon":
			_spawn_loot("weapon", HI_WEAPONS[randi() % HI_WEAPONS.size()] if hi else _weighted_weapon(), base)
			# Guns come with something nearby: usually ammo.
			var gun_id: String = loot_pool[loot_pool.size() - 1].item_id
			if randf() < 0.85:
				var sp := _loot_spot(base, 1.0, 2.4)
				if sp != Vector3.INF:
					_spawn_loot("ammo", Weapons.caliber(gun_id), sp)
			if randf() < 0.35:
				var extra := _roll_gear()
				var sp2 := _loot_spot(base, 1.2, 2.6)
				if sp2 != Vector3.INF:
					_spawn_loot(extra[0], extra[1], sp2)
		else:
			var g: Array = HI_GEAR[randi() % HI_GEAR.size()] if hi else _roll_gear()
			_spawn_loot(g[0], g[1], base)
			if bool(p.get("village", false)) and randf() < 0.5:
				var g2 := _roll_gear()
				var sp3 := _loot_spot(base, 1.2, 2.6)
				if sp3 != Vector3.INF:
					_spawn_loot(g2[0], g2[1], sp3)

	print("[game] loot: %d items from %d spots (%d spots had no room) in %d ms (finding spots %d ms)  rejects=%s" % [loot_pool.size(), points.size(), skipped, Time.get_ticks_msec() - t_loot, _spot_us / 1000, str(spot_why)])
	_spot_us = 0
	# Bots: most drop near a weapon so the first minute has real fights.
	var weapon_spots: Array = []
	for l in loot_pool:
		if is_instance_valid(l) and l.kind == "weapon" and l.global_position.y > 0.0:
			weapon_spots.append(l.global_position)
	bots.clear()
	var drop_targets: Array = []
	var route := plane_end - plane_start
	var route_len2 := maxf(1.0, route.x * route.x + route.z * route.z)
	for i in range(MAX_BOTS):
		var b := Bot.new()
		var target := _bot_drop_point()
		# Spread the lobby out: no two landing spots within 45 m.
		for tries in 12:
			var clash := false
			for other in drop_targets:
				if Vector2(target.x, target.z).distance_to(other) < 45.0:
					clash = true
					break
			if not clash:
				break
			target = _bot_drop_point()
		var jump_t := _route_fraction(target)
		if weapon_spots.size() > 0 and randf() < 0.3:
			var best_spot: Vector3
			var best_cost := 1.0e9
			for attempt in 10:
				var cand: Vector3 = weapon_spots[randi() % weapon_spots.size()]
				var tt := clampf(((cand.x - plane_start.x) * route.x + (cand.z - plane_start.z) * route.z) / route_len2, 0.05, 0.90)
				var rp := plane_start + route * tt
				var d_route := Vector2(cand.x - rp.x, cand.z - rp.z).length()
				if d_route < best_cost:
					best_cost = d_route
					best_spot = cand
					jump_t = tt
				if d_route < 55.0:
					break
			if best_cost <= 150.0:
				var a := randf() * TAU
				var r := randf_range(10.0, 45.0)
				target = Vector3(best_spot.x + cos(a) * r, best_spot.y, best_spot.z + sin(a) * r)
		drop_targets.append(Vector2(target.x, target.z))
		b.setup(BOT_NAMES[(i + seed_value) % BOT_NAMES.size()] + ("" if i < BOT_NAMES.size() else str(i)), Vector2(target.x, target.z), self, seed_value + i * 977 + randi() % 1000)
		add_child(b)
		b.global_position = plane.seat_position() + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
		b.set_meta("jump_at", clampf(jump_t + randf_range(-0.02, 0.02), 0.03, 0.93))
		b.eliminated.connect(_on_bot_eliminated)
		bots.append(b)

	# Zone.
	zone = Zone.new()
	zone.name = "Zone"
	zone.terrain = terrain
	add_child(zone)
	zone.start(1250.0)
	zone.set_process(false)
	zone.phase_changed.connect(_on_zone_phase)
	zone_was_warning = false

	alive = MAX_BOTS + 1
	if net != null and net.active:
		alive += net.roster.size() - 1
	total_players = alive
	player_kills = 0
	damage_dealt = 0.0
	match_time = 0.0
	survive_time = 0.0
	zone_acc = 0.0
	winner = false
	_match_weather = WorldBuilder.WEATHERS[randi() % WorldBuilder.WEATHERS.size()]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--weather="):
			_match_weather = a.substr(10)
	world.set_weather(_match_weather)
	_match_vehicles = _choose_vehicles()
	_spawn_vehicles(_match_vehicles)
	if net != null and net.active:
		_net_setup_ok = true
		_net_send_setup()
	_after_match_setup()


func _after_match_setup() -> void:
	last_hud_alive = -1
	end_cam_target = null
	hud.set_gameplay_visible(true)
	hud.set_crosshair_visible(false)
	hud.pause_allowed = true
	hud.set_kills(0)
	hud.set_alive(alive, total_players)
	hud.set_prompt("")
	hud.set_storm(false)
	_hud_zone()
	_on_inventory_changed()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_attach_plane_audio()


## Taken loot spots this match, 2 m cells -> positions.
var _spot_hash: Dictionary = {}
const LOOT_GAP := 1.4


## A good place for one item near `from`: distance rmin..rmax away (0 = try
## the spot itself first), resting on the floor right below, not inside a
## wall or prop, nothing solid between it and `from`, and LOOT_GAP clear of
## other items on the same floor. Vector3.INF when there is none.
var _spot_us := 0


func _loot_spot(from: Vector3, rmin: float, rmax: float) -> Vector3:
	var t0 := Time.get_ticks_usec()
	var r := _loot_spot_body(from, rmin, rmax)
	_spot_us += Time.get_ticks_usec() - t0
	return r


func _loot_spot_body(from: Vector3, rmin: float, rmax: float) -> Vector3:
	var space := get_world_3d().direct_space_state
	var tries: Array = []
	if rmin <= 0.0:
		tries.append(Vector3.ZERO)
	var a0 := randf() * TAU
	for ring in 3:
		var r := lerpf(maxf(rmin, 0.5), rmax, float(ring) / 2.0)
		for k in 7:
			var a := a0 + TAU * float(k) / 7.0 + float(ring) * 0.45
			tries.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
	var ball := SphereShape3D.new()
	ball.radius = 0.16
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = ball
	sq.collision_mask = 1
	for off in tries:
		var c: Vector3 = from + off
		# Cheapest test first: most candidates are simply too close to loot
		# already placed, and need no physics queries at all.
		if _spot_taken(c):
			_why("taken")
			continue
		if off != Vector3.ZERO:
			# Same room: nothing between the two at knee height.
			var los := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.35, c + Vector3.UP * 0.35, 1)
			if not space.intersect_ray(los).is_empty():
				_why("wall")
				continue
		var down := PhysicsRayQueryParameters3D.create(c + Vector3.UP * 0.7, c + Vector3.DOWN * 1.2, 1)
		var hit := space.intersect_ray(down)
		if hit.is_empty() or Vector3(hit["normal"]).y < 0.75:
			_why("nofloor" if hit.is_empty() else "slope")
			continue
		var g := Vector3(c.x, float(hit["position"].y) + 0.08, c.z)
		if terrain.is_water(g.x, g.z) and g.y < terrain.water_surface_at(g.x, g.z) + 0.05:
			_why("water")
			continue
		sq.transform = Transform3D(Basis.IDENTITY, g + Vector3.UP * 0.24)
		if not space.intersect_shape(sq, 1).is_empty():
			_why("inside")
			continue
		if _spot_taken(g):
			_why("taken")
			continue
		_take_spot(g)
		return g
	return Vector3.INF


var spot_why: Dictionary = {}


func _why(k: String) -> void:
	spot_why[k] = int(spot_why.get(k, 0)) + 1


func _spot_taken(g: Vector3) -> bool:
	var k := Vector2i(int(floor(g.x / 2.0)), int(floor(g.z / 2.0)))
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			for q in _spot_hash.get(Vector2i(k.x + dx, k.y + dz), []):
				var o: Vector3 = q
				if absf(o.y - g.y) < 1.2 and Vector2(o.x, o.z).distance_to(Vector2(g.x, g.z)) < LOOT_GAP:
					return true
	return false


func _take_spot(g: Vector3) -> void:
	var k := Vector2i(int(floor(g.x / 2.0)), int(floor(g.z / 2.0)))
	if not _spot_hash.has(k):
		_spot_hash[k] = []
	_spot_hash[k].append(g)


func _spawn_loot(kind: String, id: String, pos: Vector3, mag := -1, reserve := -1, net_id := 0, announce := true) -> LootPickup:
	var l := LootPickup.new()
	l.setup(kind, id, 1)
	l.mag_override = mag
	l.reserve_override = reserve
	l.position = pos
	if net_id == 0:
		if net != null and net.active and _net_setup_ok:
			net_id = net.new_loot_id()
		else:
			net_id = _next_loot_id
			_next_loot_id += 1
	l.net_id = net_id
	add_child(l)
	loot_pool.append(l)
	var lc := _loot_cell(pos)
	if not loot_grid.has(lc):
		loot_grid[lc] = []
	loot_grid[lc].append(l)
	loot_by_id[net_id] = l
	# Loot that appears mid-match (drops, crates, airdrops) is announced.
	if announce and net_on():
		net.queue_loot([net_id, kind, id, pos, mag, reserve, false])
	return l


func _cleanup_match() -> void:
	_net_setup_ok = false
	_clear_wardens()
	if player != null and player.mode == Player.Mode.VEHICLE:
		player.vehicle = null
		player.mode = Player.Mode.PLANE
	for v in vehicles:
		if is_instance_valid(v):
			v.queue_free()
	vehicles.clear()
	hud.set_vehicle(false)
	waypoints.clear()
	hud.waypoints = []
	hud.tags = []
	hud.set_squad_rows([])
	hud.show_scoreboard(false)
	hud.close_chat()
	input_locked = false
	for l in loot_pool:
		if is_instance_valid(l):
			l.queue_free()
	loot_pool.clear()
	loot_grid.clear()
	loot_by_id.clear()
	_next_loot_id = 1
	for id in humans:
		if is_instance_valid(humans[id]):
			humans[id].queue_free()
	humans.clear()
	for b in bots:
		if is_instance_valid(b):
			b.queue_free()
	bots.clear()
	for a in airdrops:
		if is_instance_valid(a):
			a.queue_free()
	airdrops.clear()
	if plane != null and is_instance_valid(plane):
		plane.queue_free()
	plane = null
	if zone != null and is_instance_valid(zone):
		zone.queue_free()
	zone = null
	if _wind != null and is_instance_valid(_wind):
		_wind.queue_free()
	_wind = null
	for n in [_cabin, _wind2d, _storm]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_cabin = null
	_wind2d = null
	_storm = null
	for t in tracers:
		if is_instance_valid(t):
			t.queue_free()
	tracers.clear()
	ballistics.clear()
	for i in impacts:
		if is_instance_valid(i):
			i.queue_free()
	impacts.clear()
	for h in _holes:
		if is_instance_valid(h):
			h.queue_free()
	_holes.clear()
	for b in _brass:
		if is_instance_valid(b):
			b.queue_free()
	_brass.clear()
	_hole_i = 0
	for g in get_tree().get_nodes_in_group("grenades"):
		g.queue_free()
	if player != null:
		player.mode = Player.Mode.PLANE
	hud.set_storm(false)


func _roll_gear() -> Array:
	var total := 0.0
	for e in GEAR_TABLE:
		total += float(e[2])
	var roll := randf() * total
	for e in GEAR_TABLE:
		roll -= float(e[2])
		if roll <= 0.0:
			if e[0] == "ammo":
				return ["ammo", _random_caliber()]
			return [e[0], e[1]]
	return ["ammo", _random_caliber()]


func _random_caliber() -> String:
	var r := randf()
	return "5.56" if r < 0.34 else ("9mm" if r < 0.62 else ("7.62" if r < 0.84 else "12ga"))


func _weighted_weapon() -> String:
	var total := 0
	for k in WEAPON_DROP_WEIGHTS:
		total += int(WEAPON_DROP_WEIGHTS[k])
	var roll := randi_range(1, total)
	for k in WEAPON_DROP_WEIGHTS:
		roll -= int(WEAPON_DROP_WEIGHTS[k])
		if roll <= 0:
			return str(k)
	return "pistol"


## A walkable dry spot within `max_r` of `center` (the whole map when the
## radius is large).
func _random_ground_point(max_r: float, center := Zone.MAP_MID) -> Vector3:
	for i in range(80):
		var a := randf() * TAU
		var r := sqrt(randf()) * max_r
		var x := center.x + cos(a) * r
		var z := center.y + sin(a) * r
		if terrain == null:
			return Vector3(x, 40, z)
		var h := terrain.height_at(x, z)
		if h > terrain.water_surface_at(x, z) + 0.5 and terrain.slope_at(x, z) < 0.45 and not _on_building(x, z):
			return Vector3(x, h, z)
	var c := Vector2(terrain.castle_c) if terrain != null else Vector2.ZERO
	return Vector3(c.x, (terrain.castle_h if terrain != null else 60.0), c.y)


## Inside or on top of a house, tower or anything else solid standing on
## the ground here (so nobody is dropped onto a roof or into a wall).
func _on_building(x: float, z: float) -> bool:
	if world == null or world.villages == null:
		return false
	if not world.villages.house_at(Vector2(x, z), 1.2).is_empty():
		return true
	for t in world.villages.towers:
		if (t.center as Vector2).distance_to(Vector2(x, z)) < 6.0:
			return true
	var h := terrain.height_at(x, z)
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, h + 60.0, z), Vector3(x, h - 1.0, z), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and float(hit["position"].y) > h + 0.6


## Where a bot wants to land: mostly within glide range of the flight path,
## like players who jump when the plane passes somewhere they like.
func _bot_drop_point() -> Vector3:
	var route := plane_end - plane_start
	for i in 30:
		var p := _random_ground_point(1250.0)
		var t := _route_fraction(p)
		var rp := plane_start + route * t
		var off := Vector2(p.x - rp.x, p.z - rp.z).length()
		if off < 650.0 or randf() < 0.08:
			return p
	return _random_ground_point(1250.0)


## Fraction along the flight path closest to a point, kept off the very ends.
func _route_fraction(p: Vector3) -> float:
	var route := plane_end - plane_start
	var len2 := maxf(1.0, route.x * route.x + route.z * route.z)
	var t := ((p.x - plane_start.x) * route.x + (p.z - plane_start.z) * route.z) / len2
	return clampf(t + randf_range(-0.03, 0.03), 0.04, 0.94)


## What the ground under a point is made of, for footsteps.
func surface_at(pos: Vector3) -> String:
	if terrain == null:
		return "grass"
	if terrain.is_water(pos.x, pos.z) and pos.y < terrain.water_surface_at(pos.x, pos.z) + 0.3:
		return "water"
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.4, pos + Vector3.DOWN * 1.2, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var col: Object = hit["collider"]
		if col is Node:
			var n := (col as Node).name
			if n.begins_with("Village"):
				return "wood"
			if n.begins_with("Rock"):
				return "stone"
	var h := terrain.height_at(pos.x, pos.z)
	if h < 3.6 or terrain.slope_at(pos.x, pos.z) > 0.35:
		return "stone"
	if world != null:
		# Dirt roads crunch; paved squares and courtyards click.
		if world._road_distance(pos.x, pos.z) < 2.2:
			return "dirt"
		if world.grass_blocked(pos.x, pos.z):
			return "stone"
	return "grass"


## Ground height under a point, including houses and props.
func ground_at(pos: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 1.5, pos + Vector3.DOWN * 30.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return Vector3(pos.x, terrain.height_at(pos.x, pos.z), pos.z)
	return hit["position"]


# ------------------------------------------------------------------- update --
func _process(delta: float) -> void:
	if Prof.on:
		var t0 := Time.get_ticks_usec()
		_process_body(delta)
		Prof.add("game", Time.get_ticks_usec() - t0)
	else:
		_process_body(delta)


func _process_body(delta: float) -> void:
	match phase:
		"menu":
			menu_t += delta
			_menu_flyby(delta)
		"plane":
			_follow_plane_cam(delta)
			_update_airborne_bots()
			_update_prompt()
			_update_minimap()
			if plane != null and plane.active and plane.progress() >= 0.985 and player.mode == Player.Mode.PLANE:
				_player_jump(true)
			if plane != null and not plane.active and player.mode == Player.Mode.PLANE:
				_player_jump(true)
		"playing":
			_update_play(delta)
		"end":
			_update_end_cam(delta)
			_update_world_sim(delta)
	if phase in ["plane", "playing", "end"]:
		_pt = Time.get_ticks_usec()
		_update_social(delta)
		Prof.add("g_social", Time.get_ticks_usec() - _pt)
	var want_match: bool = phase in ["plane", "playing"]
	if music != null and music.in_match != want_match:
		music.set_in_match(want_match)
	_update_mouse_capture()


var _plane_bump_t := 3.0
var _plane_bump := 0.0
var _auto_t := 0.0
var _beat_t := 0.0
var _storm: AudioStreamPlayer = null


## Walking over ammo for a gun you carry, or an attachment for an empty slot,
## picks it up without pressing anything.
func _auto_pickup(delta: float) -> void:
	_auto_t -= delta
	if _auto_t > 0.0 or player == null or not player.alive or player.mode != Player.Mode.GROUND:
		return
	_auto_t = 0.15
	var pp := player.global_position
	var cals := {}
	for id in player.loadout:
		cals[Weapons.caliber(id)] = true
	for l in loot_near(pp, 2.0):
		if not is_instance_valid(l) or l.taken:
			continue
		var d: Vector3 = l.position - pp
		if d.x * d.x + d.z * d.z > 4.0:
			continue
		if Vector2(d.x, d.z).length() > 1.8 or absf(d.y) > 1.6:
			continue
		var want := false
		match l.kind:
			"ammo":
				var cal: String = l.item_id if l.item_id != "" else (Weapons.caliber(player.current_id()) if player.has_gun() else "")
				want = cals.has(cal)
			"extmag", "comp":
				want = player.loadout.size() > 0
			"scope":
				for s in player.loadout.size():
					if str(player.attachments[s].get("scope", "")) == "" and Weapons.builtin_scope(player.loadout[s]) == "" and Weapons.scope_fits(player.loadout[s], l.item_id):
						want = true
		if not want or l.block_reason(player) != "":
			continue
		var kind: String = l.kind
		if l.pickup(player):
			sfx.play_at("ammo_pickup" if kind == "ammo" else "pickup", l.global_position, -6.0)
			loot_pool.erase(l)


# ------------------------------------------------------------------ water --

var _ripple_mat: StandardMaterial3D = null


## A splash where someone hits the water: sound, spray and a ring.
func water_splash(pos: Vector3, big: bool) -> void:
	if sfx != null:
		sfx.play_at("splash_big" if big else "splash_small", pos, 2.0 if big else -4.0)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 46 if big else 18
	p.lifetime = 1.0 if big else 0.7
	p.explosiveness = 0.92
	p.direction = Vector3.UP
	p.spread = 32.0
	p.initial_velocity_min = 2.5 if big else 1.4
	p.initial_velocity_max = 6.0 if big else 3.0
	p.gravity = Vector3(0, -12.0, 0)
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.16
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.86, 0.94, 1.0, 0.7)
	m.albedo_texture = _droplet_tex()
	# Spray right at your face fades out instead of whiting out the screen.
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 0.6
	m.distance_fade_max_distance = 2.2
	qm.material = m
	p.mesh = qm
	p.position = pos + Vector3(0, 0.05, 0)
	add_child(p)
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)
	water_ripple(pos + Vector3(0, 0.02, 0), 1.8 if big else 1.1)


var _drop_tex: Texture2D = null


## Soft round droplet sprite (white, faded edge; no glow).
func _droplet_tex() -> Texture2D:
	if _drop_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 32
		gt.height = 32
		_drop_tex = gt
	return _drop_tex


## An expanding ring on the surface (swim strokes, wading, splashes).
func water_ripple(pos: Vector3, size: float) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.95
	tm.outer_radius = 1.0
	tm.rings = 24
	tm.ring_segments = 4
	mi.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.85, 0.95, 1.0, 0.22)
	# Rings right around your own head fade out instead of slicing the view.
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 1.0
	m.distance_fade_max_distance = 4.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.scale = Vector3(0.3, 0.02, 0.3) * size
	add_child(mi)
	var tw := mi.create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mi, "scale", Vector3(2.2, 0.02, 2.2) * size, 1.6)
	tw.tween_property(m, "albedo_color:a", 0.0, 1.6)
	tw.chain().tween_callback(mi.queue_free)


var _underwater := false
var _uw_saved: Array = []
var _uw_loop: AudioStreamPlayer = null


## Under the surface: thick blue-green fog, muffled sound, bubbling rumble.
func set_underwater(on: bool) -> void:
	if on == _underwater or world == null or world.environment == null:
		return
	_underwater = on
	var env: Environment = world.environment
	if on:
		_uw_saved = [env.fog_enabled, env.fog_density, env.fog_light_color, env.fog_sky_affect]
		env.fog_enabled = true
		env.fog_density = 0.06
		env.fog_light_color = Color(0.06, 0.3, 0.36)
		env.fog_sky_affect = 1.0
	elif not _uw_saved.is_empty():
		env.fog_enabled = _uw_saved[0]
		env.fog_density = _uw_saved[1]
		env.fog_light_color = _uw_saved[2]
		env.fog_sky_affect = _uw_saved[3]
	var bus := AudioServer.get_bus_index("Master")
	var fx := -1
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectLowPassFilter:
			fx = i
	if fx < 0 and on:
		var lpf := AudioEffectLowPassFilter.new()
		lpf.cutoff_hz = 650.0
		AudioServer.add_bus_effect(bus, lpf)
		fx = AudioServer.get_bus_effect_count(bus) - 1
	if fx >= 0:
		AudioServer.set_bus_effect_enabled(bus, fx, on)
	if _uw_loop == null and sfx != null:
		_uw_loop = AudioStreamPlayer.new()
		var st = sfx.stream("underwater_loop")
		if st is AudioStreamWAV:
			(st as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
			(st as AudioStreamWAV).loop_end = (st as AudioStreamWAV).data.size() / 2
		_uw_loop.stream = st
		_uw_loop.volume_db = -6.0
		add_child(_uw_loop)
	if _uw_loop != null:
		if on:
			_uw_loop.play()
		else:
			_uw_loop.stop()


## Heartbeat when hurt, storm rumble when outside the zone.
var _drift_t := 0.0


func _update_ambience(delta: float) -> void:
	# Clouds creep across the sky: a step every few seconds is enough.
	_drift_t -= delta
	if _drift_t <= 0.0 and world != null and world.sky_material != null:
		_drift_t = 3.0
		world.sky_material.set_shader_parameter("drift", float(Time.get_ticks_msec()) / 1000.0)
	if player == null:
		return
	if player.alive and player.hp < 30.0 and player.mode == Player.Mode.GROUND:
		_beat_t -= delta
		if _beat_t <= 0.0:
			var k := clampf(player.hp / 30.0, 0.0, 1.0)
			_beat_t = lerpf(0.5, 0.85, k)
			sfx.play_2d("heartbeat", lerpf(-2.0, -10.0, k), 0.0)
	var outside := zone != null and player.alive and zone.is_outside(player.global_position) and player.mode == Player.Mode.GROUND
	if outside and _storm == null:
		var s := sfx.stream("storm_loop")
		if s != null:
			_make_loop(s)
			_storm = AudioStreamPlayer.new()
			_storm.stream = s
			_storm.volume_db = -40.0
			add_child(_storm)
			_storm.play()
	if _storm != null:
		_storm.volume_db = lerpf(_storm.volume_db, -8.0 if outside else -60.0, clampf(delta * 2.0, 0.0, 1.0))
		if not outside and _storm.volume_db < -55.0:
			_storm.queue_free()
			_storm = null


## Storm rumble and wind belong to being alive in the match; fade them out
## for the end screen.
func _stop_ambience() -> void:
	for n in [_storm, _wind2d]:
		if n != null and is_instance_valid(n):
			var tw := (n as Node).create_tween()
			tw.tween_property(n, "volume_db", -60.0, 1.0)
			tw.tween_callback((n as Node).queue_free)
	_storm = null
	_wind2d = null


func _follow_plane_cam(delta: float) -> void:
	if plane == null:
		return
	# Orbit the plane with the mouse (the player's look angles drive it).
	var orbit := Basis(Vector3.UP, player.yaw) * Basis(Vector3.RIGHT, clampf(player.pitch, deg_to_rad(-60.0), deg_to_rad(25.0)) - 0.18)
	var focus := plane.global_position + Vector3(0, 1.5, 0)
	var want := focus + orbit * Vector3(0, 0, 34.0)
	menu_cam.global_position = menu_cam.global_position.lerp(want, clampf(delta * 6.0, 0.0, 1.0))
	menu_cam.look_at(focus, Vector3.UP)
	# Riding along: engine vibration, slow turbulence, and the odd jolt.
	_plane_bump_t -= delta
	if _plane_bump_t <= 0.0:
		_plane_bump_t = randf_range(3.5, 8.0)
		_plane_bump = randf_range(0.6, 1.0)
		sfx.play_2d("plane_bump", -8.0, 0.15)
	_plane_bump = maxf(0.0, _plane_bump - delta * 1.8)
	var t := Time.get_ticks_msec() * 0.001
	var vib := 0.0025 + _plane_bump * _plane_bump * 0.03
	menu_cam.rotate_object_local(Vector3.RIGHT, (sin(t * 47.0) + sin(t * 31.0 + 1.1)) * vib + sin(t * 0.6) * 0.006 + _plane_bump * sin(t * 18.0) * 0.02)
	menu_cam.rotate_object_local(Vector3.UP, (sin(t * 39.0 + 2.0) + sin(t * 23.0)) * vib * 0.8)
	menu_cam.rotate_object_local(Vector3.FORWARD, sin(t * 0.45) * 0.02 + _plane_bump * sin(t * 13.0) * 0.03)
	menu_cam.fov = lerpf(menu_cam.fov, 62.0, delta * 2.0)


func _update_airborne_bots() -> void:
	if plane == null:
		return
	var prog := plane.progress()
	for b in bots:
		if not is_instance_valid(b):
			continue
		if b.state == Bot.State.PLANE and not b.puppet and prog >= float(b.get_meta("jump_at", 0.5)):
			b.jump_from_plane()


var _pt := 0


func _update_play(delta: float) -> void:
	match_time += delta
	survive_time += delta
	_pt = Time.get_ticks_usec()
	_update_wind(delta)
	Prof.add("g_update_wind", Time.get_ticks_usec() - _pt)
	_pt = Time.get_ticks_usec()
	_update_ambience(delta)
	Prof.add("g_update_ambience", Time.get_ticks_usec() - _pt)
	_pt = Time.get_ticks_usec()
	_auto_pickup(delta)
	Prof.add("g_auto_pickup", Time.get_ticks_usec() - _pt)
	if player == null or not is_instance_valid(player):
		return
	_pt = Time.get_ticks_usec()
	_update_airborne_bots()
	Prof.add("g_update_airborne_bots", Time.get_ticks_usec() - _pt)
	_pt = Time.get_ticks_usec()
	_update_driving(delta)
	Prof.add("g_update_driving", Time.get_ticks_usec() - _pt)
	if zone != null and not zone.is_processing() and (player.landed or match_time > 50.0) and not net_is_client():
		zone.set_process(true)
	hud.set_crosshair_visible(player.mode == Player.Mode.GROUND and player.has_gun() and player.aim_blend < 0.6)
	_update_world_sim(delta)
	if zone != null and (zone.is_processing() or net_is_client()):
		if zone.warning and not zone_was_warning:
			zone_was_warning = true
			sfx.play_ui("zone_warn", -8.0)
		elif not zone.warning:
			zone_was_warning = false
		_pt = Time.get_ticks_usec()
	_hud_zone()
	Prof.add("g_hud_zone", Time.get_ticks_usec() - _pt)
	hud.set_storm(zone != null and player.alive and zone.is_outside(player.global_position) and (player.mode == Player.Mode.GROUND or player.mode == Player.Mode.VEHICLE))

	_pt = Time.get_ticks_usec()
	_hud_player()
	Prof.add("g_hud_player", Time.get_ticks_usec() - _pt)
	_pt = Time.get_ticks_usec()
	_update_prompt()
	Prof.add("g_update_prompt", Time.get_ticks_usec() - _pt)
	_pt = Time.get_ticks_usec()
	_update_minimap()
	Prof.add("g_update_minimap", Time.get_ticks_usec() - _pt)
	_pt = Time.get_ticks_usec()
	_update_progress()
	Prof.add("g_update_progress", Time.get_ticks_usec() - _pt)
	_pt = Time.get_ticks_usec()
	hud.set_crosshair_spread(_crosshair_spread())
	Prof.add("g_xhair", Time.get_ticks_usec() - _pt)

	if alive <= 1 and player.alive and phase == "playing" and not net_on():
		_win()


## Zone damage for everyone; keeps running behind the end screen so the
## spectated fight still plays out.
func _update_world_sim(delta: float) -> void:
	if zone == null or (not zone.is_processing() and not net_is_client()):
		return
	zone_acc += delta
	if zone_acc < 1.0:
		return
	zone_acc -= 1.0
	var dps := zone.damage_per_second()
	if phase == "playing" and player.alive and zone.is_outside(player.global_position) and (player.mode == Player.Mode.GROUND or player.mode == Player.Mode.VEHICLE):
		player.take_damage(dps, Vector3.ZERO, false, null)
		hud.show_notice("YOU ARE IN THE STORM  —  FOLLOW THE ARROW ON THE COMPASS", 1.4)
	if net_is_client():
		return
	for b in bots:
		if is_instance_valid(b) and b.alive and b.state == Bot.State.GROUND and zone.is_outside(b.global_position):
			b.take_damage(dps, b.global_position, false, null)


func _on_zone_phase(p: int, warning: bool) -> void:
	if phase != "playing":
		return
	if warning:
		hud.show_big("THE STORM IS CLOSING", _storm_color(), 2.4)
		sfx.play_ui("zone_warn", -6.0)
	elif not zone.finished:
		hud.show_notice("NEXT SAFE ZONE MARKED  —  PRESS %s FOR THE MAP" % Keybinds.key("map"), 3.0)
		if p in [1, 2, 4, 5] and not net_is_client():
			_spawn_airdrop()


func _storm_color() -> Color:
	return HUD.STORM.lightened(0.25)


func _hud_zone() -> void:
	if zone == null:
		return
	hud.set_zone(zone.time_left(), zone.radius, zone.phase, zone.warning, zone.label())


func _hud_player() -> void:
	if player == null:
		return
	var deg := wrapf(-rad_to_deg(player.yaw), 0.0, 360.0)
	hud.set_heading(deg)
	if last_hud_alive != alive:
		last_hud_alive = alive
		hud.set_alive(alive, total_players)


func _crosshair_spread() -> float:
	if player == null or not player.has_gun():
		return 14.0
	return player.current_spread_px()


func _update_progress() -> void:
	hud.set_boost(player.boost)
	hud.set_breath(player.breath, player.holding_breath, player.aiming and player.cur_zoom() >= 1.9)
	var hp := player.heal_progress()
	if hp >= 0.0:
		hud.set_progress(player.heal_label(), hp)
		return
	var rp := player.reload_progress()
	if rp >= 0.0:
		hud.set_progress("RELOADING", rp)
		return
	hud.set_progress("", -1.0)


func _nearest_loot(pos: Vector3, max_d: float) -> LootPickup:
	# Prefer what the player is looking at, then what is closest.
	var best: LootPickup = null
	var best_score := 1e9
	var fwd := -player.camera.global_basis.z
	var max_d2 := max_d * max_d
	for l in loot_near(pos, max_d):
		var to: Vector3 = l.position - pos
		if to.x * to.x + to.z * to.z > max_d2:
			continue
		var d := to.length()
		if d > max_d:
			continue
		var facing := fwd.dot(to.normalized()) if d > 0.01 else 1.0
		var score := d - facing * 1.2
		if score < best_score:
			best_score = score
			best = l
	return best


func _update_prompt() -> void:
	if player == null:
		hud.set_prompt("")
		return
	if player.mode == Player.Mode.PLANE:
		hud.set_prompt("%s  —  JUMP FROM THE PLANE" % Keybinds.key("jump"))
		return
	if player.mode == Player.Mode.FREEFALL:
		hud.set_prompt("%s  DIVE  ·  %s  DEPLOY PARACHUTE" % [Keybinds.key("move_forward"), Keybinds.key("jump")])
		return
	if player.mode == Player.Mode.CHUTE:
		hud.set_prompt("STEER WITH WASD  —  PICK YOUR LANDING SPOT")
		return
	if player.mode == Player.Mode.VEHICLE:
		hud.set_prompt("[%s]  GET OUT" % Keybinds.key("interact"))
		return
	if player.mode != Player.Mode.GROUND:
		hud.set_prompt("")
		return
	var best := _nearest_loot(player.global_position, 3.0)
	var car := _nearest_vehicle(player.global_position, 1.7)
	if _interact_wants_car(player, best, car):
		var seat := car.free_seat()
		hud.set_prompt("JEEP IS FULL" if seat < 0 else (("[%s]  DRIVE THE JEEP" if seat == 0 else "[%s]  RIDE AS PASSENGER") % Keybinds.key("interact")))
	elif best != null:
		var why := best.block_reason(player)
		hud.set_prompt(best.prompt_text() if why == "" else why)
	else:
		hud.set_prompt("")
	_loot_label_t -= get_process_delta_time()
	if _loot_label_t <= 0.0 or best != _last_best:
		_loot_label_t = 0.2
		_last_best = best
		var pp := player.global_position
		# Only touch items near you: name tag on the one you are about to take,
		# a faint ground ring on the rest within reach.
		var near_now: Array = []
		for l in loot_near(pp, 14.0):
			var dx: float = l.position.x - pp.x
			var dz: float = l.position.z - pp.z
			if dx * dx + dz * dz < 196.0:
				near_now.append(l)
		for l in _lit_loot:
			if is_instance_valid(l) and not near_now.has(l):
				l.ring.visible = false
				l.label.visible = false
		for l in near_now:
			l.ring.visible = true
			l.label.visible = l == best
		_lit_loot = near_now


func _update_minimap() -> void:
	var marks: Array = []
	for a in airdrops:
		if is_instance_valid(a):
			marks.append(a.global_position)
	var zc := zone.center if zone != null else Vector2.ZERO
	var zr := zone.radius if zone != null else 1250.0
	var nc := zone.next_center() if zone != null else zc
	var nr := zone.next_radius() if zone != null else zr
	hud.update_minimap(player.global_position, zc, zr, nc, nr, marks)
	if not humans.is_empty() and net != null and net.squad:
		var m: Array = []
		for id in humans:
			var h = humans[id]
			if h != null and is_instance_valid(h) and (h as Bot).alive:
				m.append([(h as Bot).bot_name, Vector2(h.global_position.x, h.global_position.z)])
		hud.set_mates(m)
	else:
		hud.set_mates([])


func _update_mouse_capture() -> void:
	if get_tree().paused:
		return
	if phase == "playing" or phase == "plane":
		# The open map keeps the cursor (clicks there mark the map).
		if hud.map_open():
			if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and Input.is_action_just_pressed("fire") and not hud.chat_open:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif phase == "menu" or phase == "end":
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Menu backdrop: slow drifting shots of the island's landmarks.
const MENU_SHOTS := ["castle", "falls", "bridge", "lighthouse", "temple", "plateau", "gorge", "henge"]
var _menu_shot := -1
var _menu_shot_t := 0.0
var _menu_pose: Array = []


func _menu_flyby(delta: float) -> void:
	if terrain == null:
		return
	_menu_shot_t -= delta
	if _menu_shot < 0 or _menu_shot_t <= 0.0:
		_menu_shot = (_menu_shot + 1) % MENU_SHOTS.size()
		_menu_shot_t = 13.0
		_menu_pose = _landmark_pose(MENU_SHOTS[_menu_shot])
	var pos: Vector3 = _menu_pose[0]
	var look: Vector3 = _menu_pose[1]
	# Orbit slowly around the subject and rise a little.
	var k := 13.0 - _menu_shot_t
	var off := pos - look
	off = off.rotated(Vector3.UP, k * 0.018)
	menu_cam.global_position = look + off + Vector3(0, k * 0.35, 0)
	menu_cam.look_at(look, Vector3.UP)
	menu_cam.fov = 58.0


func _update_end_cam(delta: float) -> void:
	var focus := end_cam_spot
	if end_cam_target != null and is_instance_valid(end_cam_target) and (end_cam_target.get("alive") == true):
		focus = end_cam_target.global_position
		end_cam_spot = focus
		if end_cam_target is Bot and (end_cam_target as Bot).is_human:
			# Team mate: ride over their shoulder, looking where they look.
			var b := end_cam_target as Bot
			var fwd := (-b.global_basis.z).rotated(b.global_basis.x, b.net_pitch * 0.8)
			var side := b.global_basis.x
			var want_s := focus + Vector3(0, 2.1, 0) - Vector3(fwd.x, 0, fwd.z).normalized() * 3.6 + side * 0.7
			menu_cam.global_position = menu_cam.global_position.lerp(want_s, clampf(delta * 8.0, 0.0, 1.0))
			menu_cam.look_at(focus + Vector3(0, 1.6, 0) + fwd * 30.0, Vector3.UP)
			menu_cam.fov = lerpf(menu_cam.fov, 74.0, delta * 3.0)
			return
	end_cam_angle += delta * 0.25
	var want := focus + Vector3(cos(end_cam_angle) * 9.0, 4.5, sin(end_cam_angle) * 9.0)
	menu_cam.global_position = menu_cam.global_position.lerp(want, clampf(delta * 2.5, 0.0, 1.0))
	menu_cam.look_at(focus + Vector3(0, 1.2, 0), Vector3.UP)


func _begin_end_cam(target: Node3D, spot: Vector3) -> void:
	if net_on() and net.squad and phase == "end" and not winner:
		var mate := _next_mate(null)
		if mate != null:
			target = mate
	end_cam_target = target
	end_cam_spot = spot
	end_cam_angle = player.yaw + PI * 0.5
	menu_cam.global_position = player.camera.global_position
	menu_cam.fov = 70.0
	menu_cam.make_current()
	_spectate_label()


# -------------------------------------------------------------------- input --
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("chat") and net.active and phase in ["plane", "playing", "end"] and not hud.chat_open:
		input_locked = true
		hud.open_chat()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact") and phase == "playing" and player != null and player.mode == Player.Mode.VEHICLE \
			and Engine.get_physics_frames() - _veh_enter_frame > 12:
		_exit_vehicle()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("marker") and phase == "playing" and player != null and player.alive:
		_place_marker_from_view()
		return
	if phase == "end" and event.is_action_pressed("fire") and net_on() and net.squad:
		_spectate_next()
		return
	if event.is_action_pressed("jump"):
		if phase == "menu":
			# Not while the armory, settings or a LAN screen are open.
			if not hud.loadout_screen.visible and not hud.pause_panel.visible and not lobby.visible:
				_start_match_ui()
			return
		if phase == "plane" and player != null and player.mode == Player.Mode.PLANE:
			_player_jump(false)
		elif phase == "end":
			if net != null and net.active:
				# Back to the lobby to ready up for the next one.
				_quit_to_menu()
			else:
				_start_match_ui()
		return
	if phase == "end" and event.is_action_pressed("pause"):
		_quit_to_menu()


func _player_jump(auto: bool) -> void:
	if player == null or player.mode != Player.Mode.PLANE:
		return
	player.jump_from_plane()
	player.velocity += plane.jump_velocity() if plane != null else Vector3.ZERO
	player.camera.make_current()
	phase = "playing"
	if not auto:
		sfx.play_ui("jump_whoosh", -6.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_fade_cabin()
	_attach_wind_audio()


# ------------------------------------------------------------------ signals --
func _on_health_changed(hp: float, armor: float) -> void:
	hud.update_health(hp, armor)


func _on_weapon_changed(id: String, mag: int, reserve: int) -> void:
	hud.update_weapon(id, mag, reserve)


func _on_ammo_changed(mag: int, reserve: int) -> void:
	hud.update_ammo(mag, reserve)


func _on_inventory_changed() -> void:
	if player != null:
		hud.set_inventory(player)
		if player.has_gun():
			hud.update_weapon(player.current_id(), player.current_mag(), player.current_reserve())


func _on_hitmarker(headshot: bool, killed: bool) -> void:
	hud.show_hitmarker(headshot, killed)
	sfx.play_ui("headshot" if headshot else "hitmarker", -9.0 if headshot else -11.0)


func _on_player_damaged(amount: float, from_dir: Vector3) -> void:
	hud.show_damage(from_dir)
	sfx.play_ui("hit_flesh", -8.0)
	cam_shake = minf(1.4, cam_shake + amount * 0.02)
	player.add_trauma(clampf(amount * 0.015, 0.05, 0.5))


func _on_player_died(killer: String) -> void:
	if phase == "end":
		return
	if player.mode == Player.Mode.VEHICLE:
		_leave_seat()
	# Hosting: your own kit falls where you did, for the others to take.
	# (Everyone else's death is a Bot on this machine: _drop_bot_kit.)
	if net_on() and net.hosting and player.mode == Player.Mode.GROUND:
		var base := ground_at(player.global_position + Vector3.UP * 0.5) + Vector3(0, 0.3, 0)
		var items: Array = []
		for gid: String in player.loadout:
			if gid != "":
				items.append(["weapon", gid, int(player.mags.get(gid, 0))])
		for cal in player.ammo:
			if int(player.ammo[cal]) > 0:
				items.append(["ammo", str(cal), -1])
		if player.vest_level > 0:
			items.append(["armor", str(player.vest_level), -1])
		if player.helmet_level > 0:
			items.append(["helmet", str(player.helmet_level), -1])
		if player.meds > 0:
			items.append(["med", "", -1])
		if player.bandages > 0:
			items.append(["bandage", "", -1])
		for it: Array in items:
			var at := _loot_spot(base, 0.6, 1.8)
			if at == Vector3.INF:
				continue
			if it[0] == "weapon":
				_spawn_loot("weapon", it[1], at, int(it[2]), -1).dropped = true
			else:
				_spawn_loot(it[0], it[1], at).dropped = true
	if net_on():
		var k = player.last_killer
		var kk := node_key(k)
		var wpn := ""
		if k is Bot and is_instance_valid(k) and (k as Bot).weapon_id != "":
			wpn = str(Weapons.def((k as Bot).weapon_id)["short"])
		net.report_death(kk, _name_for_key(kk) if kk != "" else ("THE STORM" if killer == "THE STORM" else killer), wpn)
	phase = "end"
	if hud.map_open():
		hud.set_map_open(false)
	player.alive = false
	hud.pause_allowed = false
	hud.set_storm(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var placement := maxi(1, alive)
	if not net_on():
		alive = maxi(0, alive - 1)
	_stop_ambience()
	hud.killfeed("%s   >   YOU" % killer, HUD.DANGER)
	hud.show_death(killer, placement, _stats())
	_net_end_hint()
	sfx.play_ui("defeat", -4.0)
	hud.set_prompt("")
	var k = player.last_killer
	_begin_end_cam(k as Node3D if k != null and is_instance_valid(k) and k is Node3D else null, player.global_position)


func _stats() -> Dictionary:
	var acc := 0
	if player.shots_fired > 0:
		acc = int(round(100.0 * float(player.shots_hit) / float(player.shots_fired)))
	return {"kills": player_kills, "damage": damage_dealt, "accuracy": acc, "time": survive_time}


func _on_notice(text: String) -> void:
	hud.show_notice(text, 2.0)


func _on_bot_eliminated(victim: Bot, killer: String) -> void:
	alive = maxi(0, alive - 1)
	_drop_bot_kit(victim)
	if net_on() and net.hosting and victim.last_killer_node is Bot and is_instance_valid(victim.last_killer_node) and (victim.last_killer_node as Bot).is_human:
		anticheat.host_peer_kill((victim.last_killer_node as Bot).peer_id)
	if net_on() and net.hosting:
		var src0 = victim.last_killer_node
		var kkey := node_key(src0)
		var wpn := ""
		if src0 is Bot and is_instance_valid(src0) and (src0 as Bot).weapon_id != "":
			wpn = str(Weapons.def((src0 as Bot).weapon_id)["short"])
		elif src0 == player and player.has_gun():
			wpn = str(Weapons.def(player.current_id())["short"])
		net.send_elim({"victim": "b%d" % bots.find(victim), "victim_name": victim.bot_name, "killer": kkey,
			"killer_name": net.my_name if src0 == player else killer, "weapon": wpn, "alive": alive})
	if OS.get_cmdline_user_args().has("--sim"):
		var src = victim.last_killer_node
		var dist := -1.0
		var info := ""
		if src is Node3D and is_instance_valid(src):
			dist = (src as Node3D).global_position.distance_to(victim.global_position)
			if src is Bot:
				info = "calm=%.0f wpn=%s" % [(src as Bot).calm_t, (src as Bot).weapon_id]
		print("[kill] t=%d %s -> %s dist=%.0f victim_calm=%.0f victim_state=%d %s" % [int(match_time), killer, victim.bot_name, dist, victim.calm_t, victim.state, info])
	var k := killer if killer != "" else "THE STORM"
	var weapon := ""
	var src = victim.last_killer_node
	if src is Bot and is_instance_valid(src):
		weapon = str(Weapons.def((src as Bot).weapon_id)["short"]) if (src as Bot).weapon_id != "" else ""
	elif src is Player and player.has_gun():
		weapon = str(Weapons.def(player.current_id())["short"])
	if killer == "YOU":
		player_kills += 1
		hud.set_kills(player_kills)
		sfx.play_ui("elim", -4.0)
		hud.show_big("ELIMINATED  %s" % victim.bot_name, HUD.WHITE, 2.0)
		hud.show_notice("%d KILL%s" % [player_kills, "" if player_kills == 1 else "S"], 1.6)
	var col := HUD.ACCENT if killer == "YOU" else HUD.MUTED
	var mid := ("  [%s]  " % weapon) if weapon != "" else "   >   "
	# Headshot mark and the range, like a scoreboard would show them.
	var tail := ""
	if src is Node3D and is_instance_valid(src) and weapon != "":
		var kd := (src as Node3D).global_position.distance_to(victim.global_position)
		tail = "   %dM" % int(round(kd))
	if victim.last_headshot and weapon != "":
		mid = mid.replace("]", " ◎]")
	hud.killfeed("%s%s%s%s" % [k, mid, victim.bot_name, tail], col)
	hud.set_alive(alive, total_players)
	last_hud_alive = alive
	_drop_bot_loot(victim)
	if phase == "end" and end_cam_target == victim:
		# Follow whoever got them, so the spectate cam keeps showing the fight.
		if src is Bot and is_instance_valid(src) and (src as Bot).alive:
			end_cam_target = src
			hud.set_spectate("SPECTATING  %s" % (src as Bot).bot_name)
		else:
			hud.set_spectate("")
	if net_on():
		_net_check_win()
	elif alive <= 1 and player != null and player.alive and phase == "playing":
		_win()


func _drop_bot_loot(b: Bot) -> void:
	var base := ground_at(b.global_position)
	if b.armed and b.weapon_id != "":
		_spawn_loot("weapon", b.weapon_id, base + Vector3(0.0, 0.08, 0.0), int(Weapons.def(b.weapon_id)["mag"]))
	var extras: Array = [["ammo", Weapons.caliber(b.weapon_id) if b.armed else _random_caliber()]]
	if b.meds > 0:
		extras.append(["med", ""])
	if randf() < 0.6:
		extras.append(["bandage", ""])
	if b.vest_level > 0:
		extras.append(["armor", str(b.vest_level)])
	if b.helmet_level > 0:
		extras.append(["helmet", str(b.helmet_level)])
	if randf() < 0.35:
		extras.append(_roll_gear())
	for i in extras.size():
		var a := TAU * float(i) / float(extras.size()) + randf() * 0.5
		var p := ground_at(b.global_position + Vector3(cos(a), 0.0, sin(a)) * 1.2)
		_spawn_loot(extras[i][0], extras[i][1], p + Vector3(0, 0.08, 0))


func _win() -> void:
	if phase == "end":
		return
	phase = "end"
	if hud.map_open():
		hud.set_map_open(false)
	winner = true
	_stop_ambience()
	hud.pause_allowed = false
	hud.set_storm(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_victory(_stats())
	_net_end_hint()
	sfx.play_ui("victory", -3.0)
	hud.set_prompt("")
	_begin_end_cam(player, player.global_position)


func on_player_landed() -> void:
	sfx.play_ui("land_thud", -6.0)
	hud.set_plane_path(Vector3.ZERO, Vector3.ZERO)
	if loadout_enabled:
		_give_loadout()
		hud.show_notice("LOADOUT READY  —  FIND ARMOR AND MEDS", 3.0)
	else:
		hud.show_notice("FIND A WEAPON  —  CHECK THE HOUSES", 3.0)
	player.add_trauma(0.35)


func on_bot_landed(bot: Bot) -> void:
	# With loadouts on, bots get a kit too so nobody lands defenceless.
	if loadout_enabled and not bot.armed:
		bot.arm_weapon(_weighted_weapon())


func on_player_damaged(_amount: float, _from: Vector3) -> void:
	pass


func on_player_hit(_pos: Vector3, dmg: float, _headshot: bool) -> void:
	# The hitmarker and sound are the feedback; floating numbers only for
	# those who switch them on (Settings, GAME).
	damage_dealt += dmg
	if int(options.get("damage_numbers", 0)) == 1:
		spawn_damage_number(_pos, dmg, _headshot)
	if player != null:
		anticheat.on_local_hit(player.global_position.distance_to(_pos), _headshot)


## Every gunshot: nearby bots hear it, distant ones show on the map.
func on_gunshot(pos: Vector3, shooter: Node) -> void:
	if wildlife != null:
		wildlife.gunshot(pos)
	for b in bots:
		if is_instance_valid(b) and b != shooter and b.alive and b.global_position.distance_to(pos) < HEAR_RANGE:
			b.hear_shot(pos, shooter)
	if shooter != player and player != null:
		var d := pos.distance_to(player.global_position)
		if d < PING_RANGE and d > 8.0 and randf() < 0.35:
			hud.add_ping(pos)


# --------------------------------------------------------------------- loot --
func try_pickup(p: Player) -> void:
	if p == null or p.mode != Player.Mode.GROUND:
		return
	var best := _nearest_loot(p.global_position, 3.2)
	var car := _nearest_vehicle(p.global_position, 1.7)
	# The F that just got you out is still "just pressed" for the player's own
	# tick this frame: without this you were put straight back in.
	if Engine.get_physics_frames() - _veh_exit_frame < 20:
		car = null
	if _interact_wants_car(p, best, car):
		_enter_vehicle(car)
		return
	if best == null:
		return
	var why := best.block_reason(p)
	if why != "":
		p.notice.emit(why)
		return
	var kind := best.kind
	if best.pickup(p):
		var snd := "pickup"
		if kind == "ammo":
			snd = "ammo_pickup"
		elif kind == "armor":
			snd = "armor_pickup"
		sfx.play_at(snd, best.global_position, -4.0)
		loot_pool.erase(best)
		hud.set_prompt("")
		if p.hands != null:
			p.hands.grab()


## What a fallen fighter had on them is left where they fell: the gun with
## what was in it, ammo for it, armour, helmet, meds and grenades, spread
## round the body so each can be picked up. The host (or a solo game) drops
## it; clients get it like any other loot.
func _drop_bot_kit(b: Bot) -> void:
	if b == null or not is_instance_valid(b) or phase != "playing":
		return
	if net_on() and not net.hosting:
		return
	var c := b.global_position
	var items: Array = []
	if b.armed and b.weapon_id != "":
		items.append(["weapon", b.weapon_id, b.mag])
		items.append(["ammo", Weapons.caliber(b.weapon_id), -1])
	if b.vest_level > 0:
		items.append(["armor", str(b.vest_level), -1])
	if b.helmet_level > 0:
		items.append(["helmet", str(b.helmet_level), -1])
	for i in mini(b.meds, 2):
		items.append(["med" if i == 0 else "bandage", "", -1])
	if b.grenades > 0:
		items.append(["grenade", "", -1])
	# Where the body lies, then free floor round it in the same room.
	var base := ground_at(c + Vector3.UP * 0.5) + Vector3(0, 0.3, 0)
	for it: Array in items:
		var at := _loot_spot(base, 0.6, 1.6)
		if at == Vector3.INF:
			at = _loot_spot(base, 0.0, 2.4)
		if at == Vector3.INF:
			continue
		if it[0] == "weapon":
			_spawn_loot("weapon", it[1], at, int(it[2]), -1).dropped = true
		else:
			_spawn_loot(it[0], it[1], at).dropped = true


func drop_item(kind: String, id: String, pos: Vector3) -> void:
	_spawn_loot(kind, id, ground_at(pos) + Vector3(0, 0.08, 0)).dropped = true


func drop_weapon(id: String, mag: int, reserve: int, pos: Vector3) -> void:
	if id == "":
		return
	var g := ground_at(pos)
	_spawn_loot("weapon", id, g + Vector3(0, 0.08, 0), mag, reserve).dropped = true


func _spawn_airdrop() -> void:
	if zone == null:
		return
	var c := zone.next_center()
	var r := zone.next_radius() * 0.7
	for i in 40:
		var a := randf() * TAU
		var p := c + Vector2(cos(a), sin(a)) * sqrt(randf()) * r
		var h := terrain.height_at(p.x, p.y)
		# Open ground only: not on a roof, a tree or a rock.
		if h > terrain.water_surface_at(p.x, p.y) + 1.0 and terrain.slope_at(p.x, p.y) < 0.4 and not _on_building(p.x, p.y) \
				and terrain.forest_density(p.x, p.y) < 0.45:
			var drop := Airdrop.new()
			var gy := ground_at(Vector3(p.x, h + 20.0, p.y)).y
			drop.setup(self, p, gy)
			add_child(drop)
			airdrops.append(drop)
			if net_on():
				net.send_airdrop(p, gy)
			hud.show_big("SUPPLY DROP INCOMING", Color(1.0, 0.45, 0.3), 2.6)
			hud.show_notice("HIGH-TIER LOOT  —  MARKED ON THE MAP", 3.0)
			sfx.play_ui("zone_warn", -10.0)
			return


func on_airdrop_landed(drop: Airdrop) -> void:
	if net_is_client():
		return
	var base := drop.global_position
	var gun: String = AIRDROP_WEAPONS[randi() % AIRDROP_WEAPONS.size()]
	var items: Array = [["weapon", gun], ["armor", "3"], ["helmet", "3"], ["med", ""], ["scope", "8x" if Weapons.cls(gun) in ["sniper", "dmr"] else "4x"], ["ammo", Weapons.caliber(gun)], ["ammo", Weapons.caliber(gun)]]
	for i in items.size():
		var a := TAU * float(i) / float(items.size())
		var p := ground_at(base + Vector3(cos(a), 0.0, sin(a)) * 1.9) + Vector3(0, 0.08, 0)
		if items[i][0] == "weapon":
			_spawn_loot("weapon", gun, p)
		else:
			_spawn_loot(items[i][0], items[i][1], p)
	# Armed bots nearby want it too.
	for b in bots:
		if is_instance_valid(b) and b.alive and b.armed and b.global_position.distance_to(base) < 140.0 and randf() < 0.6:
			b.roam_point = Vector2(base.x, base.z)


# ------------------------------------------------------------------- effects --
## What a round hit, from the body it struck: "dirt", "wood", "stone",
## "plaster" or "metal". Sets the dust colour, the chips and the hole.
static func impact_surface(col: Object) -> String:
	if col is Vehicle:
		return "metal"
	if not (col is Node):
		return "stone"
	var nm := String((col as Node).name)
	if nm.begins_with("Terrain"):
		return "dirt"
	if nm.begins_with("Tree"):
		return "wood"
	if nm.begins_with("Rock"):
		return "stone"
	if nm.begins_with("Village"):
		return "plaster"
	return "stone"


const IMPACT_DUST := {
	"dirt": Color(0.42, 0.34, 0.24, 0.85), "wood": Color(0.66, 0.52, 0.36, 0.8),
	"stone": Color(0.62, 0.61, 0.58, 0.8), "plaster": Color(0.82, 0.79, 0.72, 0.8),
	"metal": Color(0.55, 0.55, 0.55, 0.5),
}
const IMPACT_CHIP := {
	"wood": Color(0.72, 0.56, 0.36), "stone": Color(0.5, 0.49, 0.47),
	"plaster": Color(0.88, 0.85, 0.78), "dirt": Color(0.3, 0.24, 0.17),
}
const MAX_HOLES := 96
var _holes: Array[Decal] = []
var _hole_i := 0
var _hole_tex: Texture2D = null
var _chip_mesh: BoxMesh = null
var _chip_mats: Dictionary = {}


func spawn_impact(pos: Vector3, normal: Vector3, col: Object, big := false) -> void:
	var surf := impact_surface(col)
	var n := normal.normalized() if normal.length() > 0.01 else Vector3.UP
	_puff(pos + n * 0.04, IMPACT_DUST[surf], 0.9 if big else 0.6, 4.0 if big else 2.2)
	if player == null or pos.distance_to(player.global_position) > 70.0:
		return
	_bullet_hole(pos, n, surf, big)
	if IMPACT_CHIP.has(surf):
		_chips(pos + n * 0.02, n, IMPACT_CHIP[surf], 5 if big else 3)
	elif surf == "metal":
		_sparks(pos + n * 0.02, n)


## A hole left in whatever was hit: a pooled decal, so the oldest of the
## last few dozen give way to new ones.
func _bullet_hole(pos: Vector3, n: Vector3, surf: String, big: bool) -> void:
	if _hole_tex == null:
		_hole_tex = _make_hole_texture()
	var d: Decal
	if _holes.size() < MAX_HOLES:
		d = Decal.new()
		d.texture_albedo = _hole_tex
		d.cull_mask = 1
		d.distance_fade_enabled = true
		d.distance_fade_begin = 35.0
		d.distance_fade_length = 15.0
		d.upper_fade = 0.2
		d.lower_fade = 0.2
		d.normal_fade = 0.3
		add_child(d)
		_holes.append(d)
	else:
		d = _holes[_hole_i % MAX_HOLES]
		_hole_i += 1
		if not is_instance_valid(d):
			return
	var r := (0.12 if surf != "dirt" else 0.16) * (1.4 if big else 1.0)
	d.size = Vector3(r, 0.4, r)
	d.modulate = {"wood": Color(0.55, 0.42, 0.3), "dirt": Color(0.45, 0.38, 0.3), "plaster": Color(0.85, 0.82, 0.78)}.get(surf, Color(0.8, 0.8, 0.8))
	var side := n.cross(Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT).normalized()
	side = side.rotated(n, randf() * TAU)
	d.global_transform = Transform3D(Basis(side, n, side.cross(n)), pos)
	d.visible = true


## A small soft-edged hole: black core, a dark scorched rim, chipped edge.
func _make_hole_texture() -> Texture2D:
	var sz := 64
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var jag: Array[float] = []
	for i in 24:
		jag.append(rng.randf_range(0.85, 1.15))
	for y in sz:
		for x in sz:
			var dx := (x + 0.5) / sz * 2.0 - 1.0
			var dy := (y + 0.5) / sz * 2.0 - 1.0
			var r := sqrt(dx * dx + dy * dy)
			var a := fposmod(atan2(dy, dx) / TAU, 1.0) * 24.0
			var j := lerpf(jag[int(a) % 24], jag[(int(a) + 1) % 24], a - floor(a))
			var rr := r / j
			var core := 1.0 - smoothstep(0.24, 0.32, rr)
			var rim := 1.0 - smoothstep(0.3, 0.7, rr)
			var chip := (1.0 - smoothstep(0.6, 0.98, rr)) * 0.3
			var alpha := clampf(core + rim * 0.85 + chip, 0.0, 1.0)
			var v := lerpf(lerpf(0.55, 0.22, rim), 0.02, core)
			img.set_pixel(x, y, Color(v, v * 0.97, v * 0.94, alpha))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Chips of wood, stone or plaster knocked off the surface.
func _chips(pos: Vector3, n: Vector3, col: Color, count: int) -> void:
	if _chip_mesh == null:
		_chip_mesh = BoxMesh.new()
		_chip_mesh.size = Vector3(0.018, 0.01, 0.024)
	var key := col.to_html()
	if not _chip_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.9
		_chip_mats[key] = m
	for i in count:
		var c := MeshInstance3D.new()
		c.mesh = _chip_mesh
		c.material_override = _chip_mats[key]
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(c)
		c.global_position = pos
		var v := (n * randf_range(1.6, 3.2) + Vector3(randf_range(-1, 1), randf_range(0.2, 1.4), randf_range(-1, 1)) * 1.3)
		var spin := Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))
		var life := randf_range(0.45, 0.7)
		var tw := c.create_tween()
		tw.tween_method(func(t: float) -> void:
			if is_instance_valid(c):
				c.global_position = pos + v * t + Vector3.DOWN * 4.9 * t * t
				c.rotation = spin * t
				c.scale = Vector3.ONE * (1.0 - smoothstep(0.7, 1.0, t / life))
		, 0.0, life, life)
		tw.tween_callback(c.queue_free)
		impacts.append(c)
	while impacts.size() > 60:
		var o: Variant = impacts.pop_front()
		if is_instance_valid(o) and o is Node and not (o as Node).is_queued_for_deletion():
			(o as Node).queue_free()


## Hot sparks off metal.
func _sparks(pos: Vector3, n: Vector3) -> void:
	var col := Color(1.0, 0.75, 0.35)
	var key := "spark"
	if not _chip_mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = col
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 4.0
		_chip_mats[key] = m
	if _chip_mesh == null:
		_chip_mesh = BoxMesh.new()
		_chip_mesh.size = Vector3(0.018, 0.01, 0.024)
	for i in 5:
		var c := MeshInstance3D.new()
		c.mesh = _chip_mesh
		c.material_override = _chip_mats[key]
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(c)
		c.global_position = pos
		c.scale = Vector3(0.4, 0.4, 1.4)
		var v := (n * randf_range(2.0, 4.0) + Vector3(randf_range(-1, 1), randf_range(0, 1), randf_range(-1, 1)) * 2.0)
		var tw := c.create_tween()
		tw.tween_method(func(t: float) -> void:
			if is_instance_valid(c):
				c.global_position = pos + v * t + Vector3.DOWN * 4.9 * t * t
		, 0.0, 0.25, 0.25)
		tw.tween_callback(c.queue_free)


## Spent brass on the ground: up to 60 lie around, the oldest picked up first.
var _brass: Array[MeshInstance3D] = []


func drop_casing(at: Vector3, mesh: Mesh, mat: Material, vel: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at
	# The viewmodel's brass is drawn at its scale; in the world, real size.
	mi.scale = Vector3.ONE * 1.9
	_brass.append(mi)
	while _brass.size() > 60:
		var o: MeshInstance3D = _brass.pop_front()
		if is_instance_valid(o):
			o.queue_free()
	# Where it comes down: a ray straight below, then it lies on its side.
	var q := PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 4.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var ground := at + Vector3.DOWN * 1.6
	if not hit.is_empty():
		ground = hit.position
	var flat := Vector3(vel.x, 0.0, vel.z) * 0.18
	var land := ground + flat + Vector3(0, 0.004, 0)
	var t := sqrt(maxf(0.02, 2.0 * (at.y - ground.y) / 9.8))
	var lie := Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.FORWARD, PI * 0.5)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "global_position", land, t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(mi, "rotation", lie.get_euler() + Vector3(0, TAU * 2.0, 0), t)
	tw.chain().tween_property(mi, "global_position", land + flat * 0.3, 0.15)


## A bullet going into the water: a white spout and a ring.
func spawn_splash(at: Vector3) -> void:
	if player == null or at.distance_to(player.global_position) > 160.0:
		return
	_puff(at + Vector3(0, 0.15, 0), Color(0.92, 0.96, 1.0, 0.75), 0.8, 3.2)
	var spout := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.02
	cm.bottom_radius = 0.09
	cm.height = 1.0
	cm.radial_segments = 6
	spout.mesh = cm
	if _splash_mat == null:
		_splash_mat = StandardMaterial3D.new()
		_splash_mat.albedo_color = Color(0.92, 0.96, 1.0, 0.8)
		_splash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_splash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spout.material_override = _splash_mat
	spout.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(spout)
	spout.global_position = at
	spout.scale = Vector3(1, 0.05, 1)
	var tw := spout.create_tween()
	tw.tween_property(spout, "scale", Vector3(1.2, 0.9, 1.2), 0.12).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(spout, "position:y", at.y + 0.45, 0.12)
	tw.tween_property(spout, "scale", Vector3(1.5, 0.02, 1.5), 0.3).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(spout, "position:y", at.y, 0.3)
	tw.tween_callback(spout.queue_free)
	if at.distance_to(player.global_position) < 50.0:
		play_sfx_at("splash_small", at, -10.0)


var _splash_mat: StandardMaterial3D = null


var _bb_mesh: Array = []
var _bb_mat: Array = []


## Someone else's spent case or hull, flung out and left on the ground.
func bot_casing(at: Vector3, vel: Vector3, shell: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _bb_mesh.is_empty():
		for sh: bool in [false, true]:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0065 if sh else 0.0034
			cm.bottom_radius = cm.top_radius
			cm.height = 0.055 if sh else 0.03
			cm.radial_segments = 6
			cm.rings = 1
			_bb_mesh.append(cm)
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.7, 0.12, 0.1) if sh else Color(0.86, 0.66, 0.28)
			m.metallic = 0.0 if sh else 0.7
			m.roughness = 0.5 if sh else 0.3
			_bb_mat.append(m)
	var k := 1 if shell else 0
	drop_casing(at, _bb_mesh[k], _bb_mat[k], vel)


## A footstep's puff of dust, or a splash in the shallows.
func step_puff(pos: Vector3, wet: bool) -> void:
	if player == null or pos.distance_to(player.global_position) > 60.0:
		return
	var at := pos + Vector3(randf_range(-0.15, 0.15), 0.08, randf_range(-0.15, 0.15))
	if wet:
		at.y = terrain.water_surface_at(pos.x, pos.z) + 0.04
		_puff(at, Color(0.85, 0.92, 0.95, 0.55), 1.2, 5.0)
	else:
		_puff(at, Color(0.55, 0.47, 0.36, 0.32), 1.6, 6.5)


var _blast_mats: Dictionary = {}


func _blast_mat(key: String) -> StandardMaterial3D:
	if _blast_mats.has(key):
		return _blast_mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = world._cloud_texture() if world != null else null
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.disable_receive_shadows = true
	if key == "fire":
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	else:
		m.roughness = 1.0
	_blast_mats[key] = m
	return m


## A grenade going off: a white-hot flash, a rolling fireball, dirt and stones
## flung out, a column of dark smoke drifting up for a few seconds and a
## scorch left on the ground.
func _blast_visuals(pos: Vector3) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var up := Vector3.UP
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	# Fireball: puffs bursting out and fading from white through orange.
	for i in 14:
		var mi := MeshInstance3D.new()
		mi.mesh = q
		var fm := _blast_mat("fire").duplicate() as StandardMaterial3D
		mi.material_override = fm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var dir := Vector3(randf_range(-1, 1), randf_range(0.2, 1.0), randf_range(-1, 1)).normalized()
		mi.global_position = pos + up * 0.6 + dir * 0.3
		mi.scale = Vector3.ONE * 1.8
		var end := pos + up * 1.0 + dir * randf_range(0.8, 1.8)
		var life := randf_range(0.35, 0.55)
		var tw := mi.create_tween().set_parallel(true)
		tw.tween_property(mi, "global_position", end, life).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(mi, "scale", Vector3.ONE * randf_range(3.8, 5.2), life).set_ease(Tween.EASE_OUT)
		tw.tween_method(func(t: float) -> void:
			var c := Color(1.0, 0.95, 0.8).lerp(Color(1.0, 0.42, 0.1), clampf(t * 1.6, 0.0, 1.0))
			c.a = (1.0 - t) * 0.95
			fm.albedo_color = c
		, 0.0, 1.0, life)
		tw.chain().tween_callback(mi.queue_free)
	# Smoke: dark puffs that rise, spread and thin out over a few seconds.
	for i in 12:
		var mi := MeshInstance3D.new()
		mi.mesh = q
		var sm2 := _blast_mat("smoke")
		sm2.albedo_color = Color(0.2, 0.19, 0.18, 0.85)
		mi.material_override = sm2
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var off := Vector3(randf_range(-1.2, 1.2), randf_range(0.3, 1.4), randf_range(-1.2, 1.2))
		mi.global_position = pos + off
		mi.scale = Vector3.ONE * 1.2
		var life := randf_range(2.5, 4.0)
		var end := pos + off * 1.6 + up * randf_range(3.0, 5.5) + Vector3(0.8, 0, 0.4)
		var tw := mi.create_tween().set_parallel(true)
		tw.tween_property(mi, "global_position", end, life).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3.ONE * randf_range(5.0, 8.0), life).set_ease(Tween.EASE_OUT)
		mi.transparency = 0.15
		tw.tween_property(mi, "transparency", 1.0, life).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(mi.queue_free)
	# Dirt and stones.
	var n := up
	_chips(pos + up * 0.2, n, Color(0.3, 0.24, 0.17), 10)
	_chips(pos + up * 0.2, n, Color(0.45, 0.43, 0.4), 5)
	# A scorch on the ground (a big burnt hole decal).
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(pos + up * 1.0, pos + Vector3.DOWN * 2.0, 1))
	if not hit.is_empty():
		if _hole_tex == null:
			_hole_tex = _make_hole_texture()
		var d := Decal.new()
		d.texture_albedo = _hole_tex
		d.modulate = Color(0.25, 0.22, 0.2)
		d.size = Vector3(3.4, 1.2, 3.4)
		d.cull_mask = 1
		d.distance_fade_enabled = true
		d.distance_fade_begin = 60.0
		d.distance_fade_length = 20.0
		add_child(d)
		var nn: Vector3 = (hit.normal as Vector3).normalized()
		var sd := nn.cross(Vector3.RIGHT if absf(nn.x) < 0.9 else Vector3.FORWARD).normalized()
		d.global_transform = Transform3D(Basis(sd, nn, sd.cross(nn)), hit.position)
		_holes.append(d)


func spawn_explosion(pos: Vector3) -> void:
	sfx.play_at("explosion", pos, 4.0, 0.1)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.65, 0.3)
	light.light_energy = 8.0
	light.omni_range = 14.0
	add_child(light)
	light.global_position = pos + Vector3.UP * 0.6
	var tl := light.create_tween()
	tl.tween_property(light, "light_energy", 0.0, 0.35)
	tl.tween_callback(light.queue_free)
	_blast_visuals(pos)
	if player != null and player.alive:
		var d := pos.distance_to(player.global_position)
		if d < 30.0:
			player.add_trauma(clampf(1.0 - d / 30.0, 0.0, 1.0) * 0.9)
	# Bots nearby flinch toward the blast.
	on_gunshot(pos, null)


var _smoke_tex: Texture2D
var _smokes := 0


## Wisp of gun smoke from your muzzle. It must never hide what you are
## shooting at: none while aiming down sights, faint, quick, drifting up and
## off to the side, and invisible close to the camera.
var _smoke_mat: StandardMaterial3D = null
var _smoke_mesh: QuadMesh = null


func spawn_smoke(pos: Vector3, amount := 1.0) -> void:
	if player != null and (player.aiming or player.aim_blend > 0.2):
		return
	if _smokes >= 6:
		return
	if _smoke_mat == null:
		_smoke_tex = world._cloud_texture()
		_smoke_mat = StandardMaterial3D.new()
		_smoke_mat.albedo_texture = _smoke_tex
		_smoke_mat.albedo_color = Color(0.8, 0.8, 0.78, 0.16)
		_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_smoke_mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
		_smoke_mat.distance_fade_min_distance = 0.45
		_smoke_mat.distance_fade_max_distance = 1.6
		_smoke_mesh = QuadMesh.new()
		_smoke_mesh.size = Vector2(0.35, 0.35)
	var s := MeshInstance3D.new()
	s.mesh = _smoke_mesh
	s.material_override = _smoke_mat
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.transparency = 1.0 - clampf(amount, 0.3, 1.0) * 0.9
	add_child(s)
	s.global_position = pos
	_smokes += 1
	# Up and away to the right of the sight line.
	var side := Vector3.RIGHT
	if player != null and player.camera != null:
		side = player.camera.global_basis.x
	var tw := s.create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "global_position", pos + side * randf_range(0.25, 0.45) + Vector3(0, randf_range(0.35, 0.55), 0), 0.8)
	tw.tween_property(s, "scale", Vector3.ONE * 2.2, 0.8)
	tw.tween_property(s, "transparency", 1.0, 0.8)
	tw.chain().tween_callback(func(): _smokes -= 1; s.queue_free())


func spawn_blood(pos: Vector3) -> void:
	_puff(pos, Color(0.75, 0.08, 0.06, 0.9), 0.9, 2.6)


func _puff(pos: Vector3, col: Color, s0: float, s1: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	sm.radial_segments = 6
	sm.rings = 3
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * s0
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * s1, 0.22)
	tw.tween_property(mi, "transparency", 1.0, 0.22)
	tw.chain().tween_callback(mi.queue_free)
	impacts.append(mi)
	if impacts.size() > 40:
		impacts.pop_front()


func spawn_damage_number(pos: Vector3, dmg: float, headshot: bool) -> void:
	var l := Label3D.new()
	l.text = "%d" % int(round(dmg))
	l.font = load("res://assets/fonts/ui_bold.ttf")
	l.font_size = 48
	l.outline_size = 10
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.modulate = Color(1.0, 0.82, 0.3) if headshot else Color(1, 1, 1)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0009
	add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.3, 0.3), 0.4, randf_range(-0.3, 0.3))
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position", l.global_position + Vector3(0, 0.9, 0), 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tw.chain().tween_callback(l.queue_free)


func spawn_tracer(from: Vector3, to: Vector3, mine := false) -> void:
	var dist := from.distance_to(to)
	if dist < 1.0:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var w := 0.022 if mine else 0.03
	bm.size = Vector3(w, w, dist)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, 0.86, 0.52, 0.65) if mine else Color(1.0, 0.55, 0.35, 0.8)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = (from + to) * 0.5
	mi.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	var tw := mi.create_tween()
	tw.tween_property(mi, "transparency", 1.0, 0.08)
	tw.tween_callback(mi.queue_free)
	tracers.append(mi)
	if tracers.size() > 60:
		var old = tracers.pop_front()
		if is_instance_valid(old):
			old.queue_free()


func shake(amt: float) -> void:
	cam_shake = minf(1.6, cam_shake + amt * 0.03)


func plane_seat_position() -> Vector3:
	if plane != null:
		return plane.seat_position()
	return Vector3.ZERO


func play_sfx_at(name: String, pos: Vector3, vol := 0.0) -> void:
	if name.begins_with("shot_"):
		_play_gunshot(name.substr(5), pos, vol)
		return
	sfx.play_at(name, pos, vol, 0.07)


const SOUND_SPEED := 343.0
var _listener_env := "field"
var _listener_env_t := 0.0


## Where the listener is decides how gunfire echoes: open field (long
## rolling tail), forest (diffuse), town (tight slap-back) or indoors
## (short, loud, boomy).
func _update_listener_env() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or terrain == null:
		return
	var p := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(p, p + Vector3.UP * 12.0, 1)
	if player != null:
		q.exclude = [player.get_rid()]
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		_listener_env = "indoor"
	elif world != null and world._near_village(p.x, p.z, 40.0):
		_listener_env = "town"
	elif terrain.forest_density(p.x, p.z) > 0.6:
		_listener_env = "forest"
	else:
		_listener_env = "field"


## A shot as heard from here. Close up it is the full shot; past ~40 m it
## crossfades into the far recording (the air has eaten the crack, the
## valley rolls it back), past ~450 m into the very far thump. It arrives
## late (sound travels 343 m/s), and it fades with distance more gently than
## the inverse-square law so a fight across the valley stays audible.
## Shots near you also wake the surroundings' own echo, all around you.
const SHOT_REF_D := 10.0


func _play_gunshot(cls: String, pos: Vector3, vol: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var ear := cam.global_position if cam != null else pos
	var d := ear.distance_to(pos)
	if d > 1500.0:
		return
	_refresh_listener_env()
	var delay := d / SOUND_SPEED
	var att := -20.0 * log(maxf(d, SHOT_REF_D) / SHOT_REF_D) / log(10.0) * 0.78
	var w_close := clampf(1.0 - (d - 40.0) / 140.0, 0.0, 1.0)
	var w_far := clampf((d - 40.0) / 140.0, 0.0, 1.0) * clampf(1.0 - (d - 450.0) / 350.0, 0.0, 1.0)
	var w_vfar := clampf((d - 450.0) / 350.0, 0.0, 1.0)
	if w_close > 0.0:
		var variant := "shot_%s_%d" % [cls, randi() % 4 + 1]
		if sfx.stream(variant) == null:
			variant = "shot_" + cls
		_delayed_sfx(variant, pos, vol + att + linear_to_db(w_close), delay, 0.04)
		_delayed_tail(vol + att + _tail_db() + linear_to_db(w_close), delay + 0.02)
	if w_far > 0.0:
		# The far recordings spread their energy over a soft front and a long
		# echo: lift them so a fight across the valley is clearly heard.
		_delayed_sfx("shot_%s_far" % cls, pos, vol + att + 7.0 + linear_to_db(w_far), delay, 0.06)
	if w_vfar > 0.0:
		_delayed_sfx("shot_%s_vfar" % cls, pos, vol + att + 9.0 + linear_to_db(w_vfar), delay, 0.06)


## Your own gun: the stereo first-person shot right in your hands, and the
## surroundings answering.
func play_own_gunshot(cls: String, vol := 0.0) -> void:
	_refresh_listener_env()
	var v := "shot_%s_fp_%d" % [cls, randi() % 3 + 1]
	if sfx.stream(v) == null:
		v = "shot_%s_1" % cls
	sfx.play_own(v, vol)
	_delayed_tail(vol + _tail_db(), 0.02)


func _refresh_listener_env() -> void:
	if Time.get_ticks_msec() - int(_listener_env_t) > 500:
		_listener_env_t = Time.get_ticks_msec()
		_update_listener_env()


func _tail_db() -> float:
	return float({"indoor": -1.0, "town": -5.0, "forest": -7.0, "field": -6.0}.get(_listener_env, -6.0))


func _delayed_tail(db: float, delay: float) -> void:
	var nm := "tail_" + _listener_env
	if delay < 0.03:
		sfx.play_tail(nm, db)
		return
	get_tree().create_timer(delay, false).timeout.connect(func(): sfx.play_tail(nm, db))


func _delayed_sfx(name: String, pos: Vector3, db: float, delay: float, jitter: float) -> void:
	if delay < 0.03:
		sfx.play_at(name, pos, db, jitter)
		return
	get_tree().create_timer(delay, false).timeout.connect(func(): sfx.play_at(name, pos, db, jitter))


func clamp_airborne(pos: Vector3, vel: Vector3, delta: float) -> Vector3:
	var flat := Vector2(pos.x, pos.z) - Zone.MAP_MID
	var d := flat.length()
	if d > 1350.0:
		var inward := -flat / d
		vel.x += inward.x * 30.0 * delta
		vel.z += inward.y * 30.0 * delta
	return vel


func respawn_player() -> void:
	if player == null:
		return
	anticheat.grace(3.0)
	var p := _random_ground_point(900.0)
	player.global_position = p + Vector3(0, 3, 0)
	player.velocity = Vector3.ZERO


# -------------------------------------------------------------------- audio --
func _attach_plane_audio() -> void:
	if plane == null:
		return
	var p := _loop_player("plane_loop", -2.0)
	if p != null:
		p.unit_size = 60.0
		p.max_distance = 1500.0
		plane.add_child(p)
		p.position = Vector3.ZERO
		p.play()
	_attach_cabin_audio()


var _cabin: AudioStreamPlayer = null
var _wind2d: AudioStreamPlayer = null


## Inside the hold: the engines through the hull, as a flat (non-positional) loop.
func _attach_cabin_audio() -> void:
	var s := sfx.stream("plane_interior")
	if s == null:
		return
	_make_loop(s)
	_cabin = AudioStreamPlayer.new()
	_cabin.stream = s
	_cabin.volume_db = -7.0
	add_child(_cabin)
	_cabin.play()


func _fade_cabin() -> void:
	if _cabin == null or not is_instance_valid(_cabin):
		return
	var c := _cabin
	_cabin = null
	var tw := c.create_tween()
	tw.tween_property(c, "volume_db", -50.0, 1.2)
	tw.tween_callback(c.queue_free)


## Freefall rush that follows your speed, softens under the canopy and stops
## on landing.
func _attach_wind_audio() -> void:
	var s := sfx.stream("wind_loop")
	if s == null:
		return
	_make_loop(s)
	_wind2d = AudioStreamPlayer.new()
	_wind2d.stream = s
	_wind2d.volume_db = -30.0
	add_child(_wind2d)
	_wind2d.play()


func _update_wind(delta: float) -> void:
	if _wind2d == null or not is_instance_valid(_wind2d) or player == null:
		return
	var want := -60.0
	if player.mode == Player.Mode.FREEFALL:
		want = lerpf(-16.0, -4.0, clampf(-player.velocity.y / 70.0, 0.0, 1.0))
	elif player.mode == Player.Mode.CHUTE:
		want = -20.0
	_wind2d.volume_db = lerpf(_wind2d.volume_db, want, clampf(delta * 3.0, 0.0, 1.0))
	_wind2d.pitch_scale = lerpf(_wind2d.pitch_scale, 1.15 if player.mode == Player.Mode.FREEFALL else 0.85, clampf(delta * 2.0, 0.0, 1.0))
	if player.mode == Player.Mode.GROUND and _wind2d.volume_db < -45.0:
		_wind2d.queue_free()
		_wind2d = null


func _make_loop(s: AudioStream) -> void:
	if s is AudioStreamWAV:
		var wav: AudioStreamWAV = s
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)


func _loop_player(name: String, db: float) -> AudioStreamPlayer3D:
	var s := sfx.stream(name)
	if s == null:
		return null
	if s is AudioStreamWAV:
		var wav: AudioStreamWAV = s
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = db
	p.unit_size = 18.0
	p.max_distance = 400.0
	return p


# ------------------------------------------------------------------- shots --
## Camera pose [position, look-at] that frames a landmark nicely.
## Screenshot tour of the island for polish review: random ground spots,
## every settlement and every set piece. --sweep=<dir>[,start,count]
func _sweep(spec: String) -> void:
	var parts := spec.split(",")
	var dir := parts[0]
	DirAccess.make_dir_recursive_absolute(dir)
	var shots: Array = []
	var rr := RandomNumberGenerator.new()
	rr.seed = 4242
	for i in 24:
		var c := terrain.random_land_point(rr, 1.0, 0.6)
		if c == Vector2.INF:
			continue
		var a := rr.randf() * TAU
		var gy: float = maxf(terrain.height_at(c.x, c.y), Terrain.WATER_LEVEL)
		var p := Vector3(c.x, gy + 1.8, c.y)
		shots.append(["ground_%02d" % i, p, p + Vector3(cos(a), -0.08, sin(a)) * 10.0])
	for v in world.villages.village_pads:
		var c: Vector2 = v.center
		var r := float(v.radius)
		var off := Vector2(r * 0.55, r * 0.35)
		var gy: float = terrain.height_at(c.x + off.x, c.y + off.y)
		shots.append(["%s_%s" % [v.type, String(v.name).replace(" ", "_").replace("'", "")], Vector3(c.x + off.x, gy + 2.0, c.y + off.y), Vector3(c.x, float(v.pad) + 2.0, c.y)])
	var ri := 0
	for pp in world.villages.poi_pads:
		if String(pp.type) != "ruin" and String(pp.type) != "tower":
			continue
		ri += 1
		if ri % 3 != 0:
			continue
		var pc: Vector2 = pp.center
		var off2 := Vector2(14.0, 9.0)
		var gy2: float = terrain.height_at(pc.x + off2.x, pc.y + off2.y)
		shots.append(["%s_%d" % [pp.type, ri], Vector3(pc.x + off2.x, gy2 + 2.2, pc.y + off2.y), Vector3(pc.x, terrain.height_at(pc.x, pc.y) + 2.0, pc.y)])
	for k in 6:
		# Along the shore, looking along the beach.
		var a := TAU * float(k) / 6.0 + 0.3
		var p := Vector2(cos(a), sin(a)) * 900.0
		for step in 60:
			if terrain.height_at(p.x, p.y) > Terrain.WATER_LEVEL + 1.0:
				break
			p *= 0.985
		var gy3: float = terrain.height_at(p.x, p.y)
		var tang := Vector2(-sin(a), cos(a))
		shots.append(["coast_%d" % k, Vector3(p.x, gy3 + 2.0, p.y), Vector3(p.x + tang.x * 20.0, gy3, p.y + tang.y * 20.0)])
	for nm in ["castle", "castlein", "field", "henge", "lighthouse", "temple", "oak", "bridge", "falls", "spire", "crystals", "crystals2", "dragon", "grove", "treetown", "treetown2"]:
		var pose := _landmark_pose(nm)
		shots.append(["lm_" + nm, pose[0], pose[1]])
	var start := int(parts[1]) if parts.size() > 1 else 0
	var count := int(parts[2]) if parts.size() > 2 else shots.size()
	phase = "shot"
	hud.hide_menu()
	hud.visible = false
	menu_cam.make_current()
	for k in range(start, mini(shots.size(), start + count)):
		var e: Array = shots[k]
		menu_cam.global_position = e[1]
		menu_cam.look_at(e[2])
		for i in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if OS.get_environment("SWEEP_NOPNG") == "":
			get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [dir, k, e[0]])
		print("[sweep] %02d %s at %s  objects=%d draws=%d prims=%dk" % [k, e[0], str((e[1] as Vector3).round()),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)) / 1000])


## Ground-level centre of a named place: a fantasy site, a landmark or a town.
## DBG_PICK="x,y;x,y": what is under those pixels (of a 1280x720 shot).
func _dbg_pick() -> void:
	if OS.get_environment("DBG_PICK") == "":
		return
	var cam3 := get_viewport().get_camera_3d()
	for pp in OS.get_environment("DBG_PICK").split(";"):
		var xy := pp.split_floats(",")
		var px := Vector2(xy[0], xy[1]) * Vector2(get_viewport().get_visible_rect().size) / Vector2(1280, 720)
		var o3 := cam3.project_ray_origin(px)
		var d3 := cam3.project_ray_normal(px)
		var hit3 := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(o3, o3 + d3 * 300.0))
		if not hit3.is_empty():
			print("[pick] ", pp, " -> ", hit3.collider.name if hit3.collider is Node else hit3.collider, " at ", hit3.position, " place ", _place_name(hit3.position))


func _poi_centre(nm: String) -> Vector3:
	var t := terrain
	var key := nm.to_lower()
	var fz: Fantasy = world.villages.landmarks.fantasy
	if fz != null and fz.poi.has(key):
		var e: Array = fz.poi[key]
		return Vector3((e[0] as Vector2).x, float(e[1]), (e[0] as Vector2).y)
	var marks := {"castle": [t.castle_c, t.castle_h], "henge": [t.henge_c, t.henge_h], "lighthouse": [t.lighthouse_c, t.lighthouse_h], "temple": [t.temple_c, t.temple_h], "oak": [t.oak_c, t.oak_h]}
	if marks.has(key):
		var m: Array = marks[key]
		return Vector3((m[0] as Vector2).x, float(m[1]), (m[0] as Vector2).y)
	for v in world.villages.village_pads:
		if str(v.name).to_lower().replace(" ", "") == key:
			return Vector3(v.center.x, t.height_at(v.center.x, v.center.y), v.center.y)
	for l in world.villages.landmarks.labels:
		if str(l[0]).to_lower().replace(" ", "").replace("'", "") == key:
			var lc: Vector2 = l[1]
			return Vector3(lc.x, t.height_at(lc.x, lc.y), lc.y)
	return Vector3.INF


func _landmark_pose(name: String) -> Array:
	var t := terrain
	var at := func(c: Vector2, h: float, back: Vector2, dist: float, up: float) -> Array:
		var p := c + back.normalized() * dist
		var gy := maxf(t.height_at(p.x, p.y), Terrain.WATER_LEVEL)
		return [Vector3(p.x, gy + up, p.y), Vector3(c.x, h, c.y)]
	match name:
		"bridge":
			var mid := (t.bridge_a + t.bridge_b) * 0.5
			var perp := (t.bridge_b - t.bridge_a).orthogonal().normalized()
			return [Vector3(mid.x + perp.x * 190.0, 30.0, mid.y + perp.y * 190.0), Vector3(mid.x, 24.0, mid.y)]
		"deck":
			var d := (t.bridge_b - t.bridge_a).normalized()
			var p := t.bridge_a - d * 6.0
			return [Vector3(p.x, t.bridge_h + 1.7, p.y), Vector3(t.bridge_b.x, t.bridge_h + 4.0, t.bridge_b.y)]
		"castle":
			return at.call(t.castle_c, t.castle_h + 4.0, Vector2(0.6, 1.0), 85.0, 28.0)
		"castlein":
			var cc := t.castle_c + Vector2(14.0, 9.0)
			return [Vector3(cc.x, t.castle_h + 2.0, cc.y), Vector3(t.castle_c.x, t.castle_h + 5.0, t.castle_c.y)]
		"falls":
			var b := Vector2(t.falls_bottom.x, t.falls_bottom.z)
			return [Vector3(b.x + t.falls_dir.x * 110.0 + 30.0, 22.0, b.y + t.falls_dir.y * 110.0), Vector3(b.x, 40.0, b.y)]
		"lighthouse":
			return at.call(t.lighthouse_c, t.lighthouse_h + 12.0, Vector2(-1.0, -0.4), 60.0, 10.0)
		"henge":
			return at.call(t.henge_c, t.henge_h + 2.0, Vector2(1.0, 0.5), 38.0, 9.0)
		"temple":
			return at.call(t.temple_c, t.temple_h + 8.0, Vector2(-1.0, 0.3), 70.0, 16.0)
		"oak":
			return at.call(t.oak_c, t.oak_h + 12.0, Vector2(1.0, 0.6), 60.0, 22.0)
		"oakfoot":
			var os: Array = world.villages.landmarks.oak_stair
			if not os.is_empty():
				var oo: Vector3 = os[0]
				var sa: float = os[2]
				var foot := oo + Vector3(cos(sa), 0, sin(sa)) * float(os[1])
				var cam := oo + Vector3(cos(sa - 0.7), 0, sin(sa - 0.7)) * (float(os[1]) + 6.0)
				cam.y = t.height_at(cam.x, cam.z) + 2.2
				return [cam, foot + Vector3.UP * 0.6]
		"gorge":
			var g := t.gorge_bridge
			var fl := t.gorge_bridge_dir.orthogonal()
			return [Vector3(g.x + fl.x * 70.0, 12.0, g.y + fl.y * 70.0), Vector3(g.x, 8.0, g.y)]
		"plateau":
			return [Vector3(Terrain.PLATEAU_C.x + 260.0, 140.0, Terrain.PLATEAU_C.y + 330.0), Vector3(Terrain.PLATEAU_C.x, 60.0, Terrain.PLATEAU_C.y)]
		"overview":
			return [Vector3(200.0, 900.0, 1300.0), Vector3(60.0, 0.0, -50.0)]
	var fz: Fantasy = world.villages.landmarks.fantasy
	var pkey := "spire" if name == "spiretop" else ("treetown" if name.begins_with("treetown") else name)
	if fz != null and fz.poi.has(pkey):
		var e: Array = fz.poi[pkey]
		var fc: Vector2 = e[0]
		var fh: float = e[1]
		var spec: Array = {"spire": [16.0, Vector2(1.0, 0.5), 70.0, 30.0], "spiretop": [27.0, Vector2(0.4, 1.0), 13.0, 30.0], "crystals": [3.0, Vector2(1.0, 0.4), 32.0, 6.0], "crystals2": [3.0, Vector2(-0.6, 1.0), 32.0, 6.0],
			"dragon": [3.0, Vector2(0.7, 1.0), 40.0, 9.0], "field": [1.0, Vector2(1.0, 0.7), 16.0, 3.5], "grove": [5.0, Vector2(1.0, 0.3), 28.0, 4.0],
			"treetown": [45.0, Vector2(1.0, 0.35), 165.0, 20.0], "treetown2": [20.0, Vector2(-0.4, 1.0), 42.0, 22.0], "treetown3": [60.0, Vector2(0.8, -0.6), 30.0, 62.0],
			"treetown4": [19.9, Vector2(0.3, 1.0), 20.0, 18.6], "treetown5": [76.0, Vector2(1.0, 0.2), 14.5, 74.6], "treetown6": [39.8, Vector2(-1.0, 0.25), 18.0, 38.4]}.get(name, [4.0, Vector2(1, 0), 40.0, 8.0])
		return at.call(fc, fh + float(spec[0]), spec[1], float(spec[2]), float(spec[3]))
	return [Vector3(0, 300, 600), Vector3.ZERO]


# Offscreen capture: renders the real scene through the real renderer with no
# window (headless display driver + vulkan) and writes a PNG. Used to actually
# look at the game instead of guessing.
func _run_shot() -> void:
	print("[shot] begin")
	var out := "/tmp/opencode/shot.png"
	var spot := Vector3(0, 0, 0)
	var ang := 0.6
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--at="):
			var parts := a.substr(5).split(",")
			if parts.size() == 2:
				spot = Vector3(float(parts[0]), 0.0, float(parts[1]))
		elif a.begins_with("--yaw="):
			ang = float(a.substr(6))
	# Free camera: --lm=<landmark> or --cam=x,y,z --look=x,y,z.
	var cam_pos := Vector3.INF
	var cam_look := Vector3.ZERO
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cam="):
			# --cam=x,y,z[,lx,ly,lz]: explicit camera (and look-at point).
			var c := a.substr(6).split(",")
			cam_pos = Vector3(float(c[0]), float(c[1]), float(c[2]))
			if c.size() >= 6:
				cam_look = Vector3(float(c[3]), float(c[4]), float(c[5]))
		elif a.begins_with("--poi="):
			# --poi=name,r,angle,h,look_r,look_angle,look_h: camera on a circle
			# round a named place (town, landmark or fantasy site), heights
			# above its ground; angles in degrees.
			var f := a.substr(6).split(",")
			var pc := _poi_centre(f[0])
			if pc != Vector3.INF:
				var a0 := deg_to_rad(float(f[2]))
				var a1 := deg_to_rad(float(f[5]))
				cam_pos = pc + Vector3(cos(a0) * float(f[1]), float(f[3]), sin(a0) * float(f[1]))
				cam_look = pc + Vector3(cos(a1) * float(f[4]), float(f[6]), sin(a1) * float(f[4]))
				print("[shot] poi %s at %s" % [f[0], pc])
		elif a.begins_with("--look="):
			var c := a.substr(7).split(",")
			cam_look = Vector3(float(c[0]), float(c[1]), float(c[2]))
		elif a.begins_with("--cam="):
			# --cam=x,y,z,lx,ly,lz : explicit camera and look-at point.
			var f := a.substr(6).split(",")
			cam_pos = Vector3(float(f[0]), float(f[1]), float(f[2]))
			cam_look = Vector3(float(f[3]), float(f[4]), float(f[5]))
		elif a.begins_with("--lm="):
			var pose := _landmark_pose(a.substr(5))
			cam_pos = pose[0]
			cam_look = pose[1]
		elif a.begins_with("--vil="):
			# --vil=<n>[,h]: the n-th ring village from above.
			var fa2 := a.substr(6).split(",")
			var k2 := 0
			for v in world.villages.village_pads:
				if str(v.type) != "village":
					continue
				if k2 < int(fa2[0]):
					k2 += 1
					continue
				var c2: Vector2 = v.center
				var hy2 := terrain.height_at(c2.x, c2.y)
				var hh2 := float(fa2[1]) if fa2.size() > 1 else 14.0
				cam_pos = Vector3(c2.x - hh2 * 1.4, hy2 + hh2, c2.y - hh2 * 1.4)
				cam_look = Vector3(c2.x, hy2, c2.y)
				print("[shot] village ", v.name, " at ", c2)
				break
		elif a.begins_with("--farm="):
			# --farm=<n>[,air]: from inside the n-th farm's paddock, or above it.
			var fa := a.substr(7).split(",")
			var k := 0
			for v in world.villages.village_pads:
				if str(v.type) != "farm":
					continue
				if k < int(fa[0]):
					k += 1
					continue
				var c: Vector2 = v.center
				var r: float = v.radius
				var hy := terrain.height_at(c.x, c.y)
				if fa.size() > 1:
					cam_pos = Vector3(c.x - r * 0.9, hy + r * 1.3, c.y - r * 0.9)
					cam_look = Vector3(c.x, hy, c.y)
				else:
					cam_pos = Vector3(c.x - r * 0.35, hy + 1.8, c.y)
					cam_look = Vector3(c.x + r, hy + 0.6, c.y + r * 0.25)
				print("[shot] farm at ", c, " r=", r)
				break
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sweep="):
			await _sweep(a.substr(8))
			get_tree().quit()
			return
	if cam_pos != Vector3.INF:
		for a2 in OS.get_cmdline_user_args():
			if a2.begins_with("--weather="):
				world.set_weather(a2.substr(10))
		phase = "shot"
		hud.hide_menu()
		hud.visible = false
		menu_cam.global_position = cam_pos
		menu_cam.look_at(cam_look)
		menu_cam.make_current()
		for i in 6:
			var tf := Time.get_ticks_msec()
			await get_tree().process_frame
			print("[shot] frame ", i, " ", Time.get_ticks_msec() - tf, " ms")
		_dbg_pick()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out)
		print("[shot] saved ", out, " objects=%d draws=%d prims=%dk" % [int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)) / 1000])
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--menu"):
		if OS.get_cmdline_user_args().has("--loadout"):
			hud._open_loadout()
		if OS.get_cmdline_user_args().has("--lobby"):
			_net_host()
			if OS.get_cmdline_user_args().has("--fake"):
				# Stand-in players so the lobby can be judged full.
				var fake := [[2, "LUKA", true, 1, 4], [3, "MARKO", false, 2, 9], [4, "IVAN", true, 3, 23]]
				for f in fake:
					net.roster[f[0]] = f[1]
					net.info[f[0]] = {"ready": f[2], "color": f[3], "ping": f[4]}
				net.roster_changed.emit()
				net.chat.emit(0, "", "LUKA JOINED THE LOBBY", true)
				net.chat.emit(2, "LUKA", "ajmo ajmo, castle drop?", false)
				net.chat.emit(3, "MARKO", "give me a sec, setting my loadout", false)
				net.chat.emit(4, "IVAN", "bridge is better, sniper on the gate", false)
				net.chat.emit(1, net.my_name, "castle first then bridge", false)
				if OS.get_cmdline_user_args().has("--countdown"):
					lobby._on_countdown(3)
		if OS.get_cmdline_user_args().has("--join"):
			lobby.show_join()
			if OS.get_cmdline_user_args().has("--fake"):
				lobby._show_games([
					{"name": "LUKA", "ip": "192.168.1.23", "players": 3, "max": 8, "running": false, "squad": true, "bots": 63},
					{"name": "MARKO", "ip": "192.168.1.40", "players": 2, "max": 8, "running": true, "squad": false, "bots": 40},
				])
		for i in 30:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out)
		print("[shot] saved ", out, " objects=%d draws=%d prims=%dk" % [int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)) / 1000])
		get_tree().quit()
		return
	print("[shot] starting match")
	if OS.get_cmdline_user_args().has("--no3d"):
		# HUD and map pictures: skip the 3D world so they render in seconds.
		get_viewport().disable_3d = true
	_start_match()
	if OS.get_cmdline_user_args().has("--plane"):
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--yaw="):
				player.yaw = float(a.substr(6))
		player.pitch = -0.15
		plane.t = 0.3
		for i in 60:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out)
		print("[shot] saved ", out, " objects=%d draws=%d prims=%dk" % [int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)) / 1000])
		get_tree().quit()
		return
	await get_tree().process_frame
	print("[shot] match up, player=", player)
	var p := player
	if OS.get_cmdline_user_args().has("--town"):
		for v in world.villages.village_pads:
			if v.type == "town":
				var dir := Vector2(cos(float(v.axis)), sin(float(v.axis)))
				var c: Vector2 = v.center - dir * (float(v.radius) - 6.0)
				spot = Vector3(c.x, 0.0, c.y)
				# Look down the main street.
				ang = atan2(-dir.x, -dir.y)
				break
	for a in OS.get_cmdline_user_args():
		# --pad=village / farm / city: stand at the edge of the first one, facing in.
		if a.begins_with("--pad="):
			for v in world.villages.village_pads:
				if String(v.type) == a.substr(6):
					var pr := 0.6
					for a2 in OS.get_cmdline_user_args():
						if a2.begins_with("--padr="):
							pr = float(a2.substr(7))
					var c: Vector2 = v.center + Vector2(1, 0.4).normalized() * (float(v.radius) * pr)
					spot = Vector3(c.x, 0.0, c.y)
					var to: Vector2 = (v.center as Vector2) - c
					ang = atan2(-to.x, -to.y)
					break
	if OS.get_cmdline_user_args().has("--tower") and world.villages.towers.size() > 0:
		var tc: Vector2 = world.villages.towers[0].center
		spot = Vector3(tc.x + 14.0, 0.0, tc.y + 10.0)
		ang = atan2(14.0, 10.0)
	for a in OS.get_cmdline_user_args():
		# --ruin=N: the Nth ruin, from a few metres out.
		if a.begins_with("--ruin="):
			var k := 0
			for pp in world.villages.poi_pads:
				if str(pp.type) != "ruin":
					continue
				if k < int(a.substr(7)):
					k += 1
					continue
				var rc: Vector2 = pp.center
				spot = Vector3(rc.x + 6.0, 0.0, rc.y + 4.0)
				ang = atan2(6.0, 4.0)
				break
	if OS.get_cmdline_user_args().has("--inside") and world.villages.towers.size() > 0:
		var tw: Dictionary = world.villages.towers[0]
		var tb := Basis(Vector3.UP, float(tw.yaw))
		var local := tb * Vector3(-1.6, 0, 2.0)
		spot = Vector3(tw.center.x + local.x, 0.0, tw.center.y + local.z)
		# Look toward the stair (+x side, climbing to -z).
		var look := tb * Vector3(1.0, 0, -0.35)
		ang = atan2(-look.x, -look.z)
	# --house=N / --housein=N / --houseup=N: the Nth two-storey house, from
	# the street, from just inside the door, or from its upper floor.
	var spot_y := INF
	for a in OS.get_cmdline_user_args():
		for key in ["--house=", "--housein=", "--houseup="]:
			if not a.begins_with(key):
				continue
			var want := int(a.substr(key.length()))
			var k := 0
			for hh in world.villages.houses:
				if int(hh.get("built_levels", 1)) < 2 and want >= 0:
					continue
				# Negative index: the first house that is wider than deep.
				if want < 0 and float(hh.w) <= float(hh.d):
					continue
				if k < want:
					k += 1
					continue
				var hb := Basis(Vector3.UP, float(hh.yaw))
				var hw := float(hh.w)
				var hd := float(hh.d)
				var ho := Vector3(hh.center.x, float(hh.pad), hh.center.y)
				var dn: Vector3 = [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0)][int(hh.door_side)]
				var dp := Vector3(dn.x * hw * 0.5, 0, dn.z * hd * 0.5)
				var at := Vector3.ZERO
				var look := Vector3.ZERO
				if key == "--house=":
					at = dp + dn * 9.0
					look = -dn
				elif key == "--housein=":
					at = dp - dn * 1.0
					look = Vector3(hw * 0.5 - 1.1, 0, Villages.WALL_HEIGHT) - at
				else:
					at = Vector3(-hw * 0.5 + 1.0, Villages.WALL_HEIGHT, hd * 0.5 - 1.0)
					look = Vector3(hw * 0.5 - 1.0, 0, -hd * 0.5 + 1.0) - at
					spot_y = ho.y + Villages.WALL_HEIGHT + 0.1
				var wp := ho + hb * at
				var wl := hb * look
				spot = Vector3(wp.x, 0.0, wp.z)
				ang = atan2(-wl.x, -wl.z)
				if key == "--housein=":
					spot_y = ho.y + 0.1
				print("[shot] house ", ho, " ", hw, "x", hd, " door ", hh.door_side)
				break
	if p == null:
		print("[shot] no player")
		get_tree().quit()
		return
	p.mode = Player.Mode.GROUND
	p.alive = true
	var h: float = float(terrain.height_at(spot.x, spot.z))
	if spot_y != INF:
		h = spot_y - 2.4
	if h < Terrain.WATER_LEVEL + 0.5 and not OS.get_cmdline_user_args().has("--water"):
		spot = _random_ground_point(200.0)
		h = spot.y
	elif OS.get_cmdline_user_args().has("--water"):
		h = maxf(h, Terrain.WATER_LEVEL)
	p.global_position = Vector3(spot.x, h + 2.4, spot.z)
	p.velocity = Vector3.ZERO
	p.yaw = ang
	p.pitch = -0.16
	# --step=M: walk M metres the way you are facing (up to a wall, say).
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--step="):
			p.global_position += Basis(Vector3.UP, ang) * Vector3(0, 0, -float(a.substr(7)))
		elif a.begins_with("--turn="):
			p.yaw = ang + float(a.substr(7))
		elif a.begins_with("--strafe="):
			p.global_position += Basis(Vector3.UP, ang) * Vector3(float(a.substr(9)), 0, 0)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pitch="):
			p.pitch = float(a.substr(8))
	p.camera.make_current()
	phase = "playing"
	if OS.get_cmdline_user_args().has("--fakesquad"):
		net.set_process(false)
		net.active = true
		net.match_running = true
		net.squad = true
		net.roster = {1: "PLAYER", 2: "LUKA", 3: "MARKO", 4: "IVAN"}
		net.info = {1: {"ready": true, "color": 0, "ping": 0}, 2: {"ready": true, "color": 1, "ping": 4}, 3: {"ready": true, "color": 2, "ping": 9}, 4: {"ready": true, "color": 3, "ping": 23}}
		var fwd := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
		var right := Vector3(cos(p.yaw), 0, -sin(p.yaw))
		var offs := [fwd * 14.0 + right * 4.0, fwd * 40.0 - right * 12.0, fwd * 120.0 + right * 30.0]
		for i in 3:
			var mate := _make_human(i + 2, ["LUKA", "MARKO", "IVAN"][i])
			var mp: Vector3 = p.global_position + offs[i]
			mp.y = terrain.height_at(mp.x, mp.z)
			mate.apply_net(mp, p.yaw + 0.4, Bot.State.GROUND, Bot.NF_ALIVE | Bot.NF_ARMED, "rifle", 2, 1)
			mate.hp = [100.0, 46.0, 18.0][i]
			mate.net_kills = [3, 1, 5][i]
			mate.net_damage = [412.0, 160.0, 655.0][i]
		player_kills = 2
		damage_dealt = 288.0
		waypoints[2] = {"pos": p.global_position + fwd * 260.0 + right * 60.0, "t": 60.0}
		waypoints[1] = {"pos": p.global_position + fwd * 90.0 - right * 80.0, "t": 60.0}
		hud.chat_add("LUKA", net.color_of(2), "enemy behind the red house", false)
		hud.chat_add("IVAN", net.color_of(4), "i have a 4x if anyone needs it", false)
		hud.chat_add("", Color.WHITE, "MARKO PLACED A MARKER", true)
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--gun="):
			p.give_weapon(a.substr(6))
	for a in args:
		if a.begins_with("--optic="):
			p.attachments[p.slot]["scope"] = a.substr(8)
			p.refresh_viewmodel()
	if args.has("--hud"):
		p.landed = true
		hud.set_crosshair_visible(true)
	else:
		hud.root.visible = false
	for a in args:
		# --zone=cx,cz,r,ncx,ncz,nr[,phase]: put the storm somewhere for a picture.
		if a.begins_with("--zone="):
			var zv := a.substr(7).split_floats(",")
			if zv.size() >= 6:
				zone.set_process(false)
				zone.center = Vector2(zv[0], zv[1])
				zone.radius = zv[2]
				zone.target_center = Vector2(zv[3], zv[4])
				zone.target_radius = zv[5]
				zone.phase = int(zv[6]) if zv.size() > 6 else 2
				zone.state = "shrink"
				zone._apply_wall()
	if args.has("--map"):
		hud.toggle_map()
	for a in args:
		# --mapzoom=N: the full map zoomed in on the player.
		if a.begins_with("--mapzoom="):
			hud.map_zoom = float(a.substr(10))
			hud._bm_focus = Vector2(p.global_position.x, p.global_position.z)
	if args.has("--garc"):
		p.grenades = 3
		Input.action_press("grenade")
	if args.has("--aim"):
		p.aim_blend = 1.0
		p.land_dip = 0.0
		Input.action_press("aim")
	hud.set_prompt("")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var wait := 10
	for a in args:
		if a.begins_with("--wait="):
			wait = int(a.substr(7))
	if args.has("--loot"):
		var kinds := [["armor", "3"], ["helmet", "2"], ["scope", "4x"], ["med", ""], ["weapon", "sniper"], ["energy", ""], ["grenade", ""], ["ammo", ""]]
		var fwd := Basis(Vector3.UP, p.yaw) * Vector3(0, 0, -1)
		var right := Basis(Vector3.UP, p.yaw) * Vector3(1, 0, 0)
		for i in kinds.size():
			var lp := p.global_position + fwd * (4.0 + float(i / 4) * 2.2) + right * (float(i % 4) - 1.5) * 1.6
			_spawn_loot(kinds[i][0], kinds[i][1], ground_at(lp) + Vector3(0, 0.08, 0)).label.visible = true
	for a in args:
		# --boom=F: a grenade going off 8 m ahead, caught F seconds in.
		if a.begins_with("--boom="):
			var bp := ground_at(p.global_position + Basis(Vector3.UP, p.yaw) * Vector3(0, 0, -8.0))
			spawn_explosion(bp)
			var t_end := Time.get_ticks_msec() + int(float(a.substr(7)) * 1000.0)
			while Time.get_ticks_msec() < t_end:
				await get_tree().process_frame
	if args.has("--feed"):
		hud.killfeed("YOU  [AR-74 ◎]  RAVEN   48M", HUD.ACCENT)
		hud.killfeed("FALCON  [M-24]  ONYX   212M", HUD.MUTED)
		hud.killfeed("THE STORM   >   BADGER", HUD.MUTED)
	# --opt=key:value: a settings choice, as if picked in the menu.
	for a in args:
		if a.begins_with("--opt="):
			var kv := a.substr(6).split(":")
			options[kv[0]] = int(kv[1])
			_apply_options()
	# --splash: rounds into the water in front of the camera.
	if args.has("--splash"):
		var fwd2 := Basis(Vector3.UP, p.yaw) * Vector3(0, 0, -1)
		for i in 5:
			var wp := p.global_position + fwd2 * (6.0 + i * 2.0) + Basis(Vector3.UP, p.yaw) * Vector3(randf_range(-2, 2), 0, 0)
			spawn_splash(Vector3(wp.x, maxf(terrain.water_surface_at(wp.x, wp.z), terrain.height_at(wp.x, wp.z)) + 0.02, wp.z))
	# --holes=N: N rounds into whatever is in front of the camera.
	for a in args:
		if a.begins_with("--holes="):
			await get_tree().physics_frame
			var cam := p.camera
			var space := p.get_world_3d().direct_space_state
			for i in int(a.substr(8)):
				var dir := -cam.global_basis.z + cam.global_basis.x * randf_range(-0.3, 0.3) + cam.global_basis.y * randf_range(-0.15, 0.25)
				var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + dir.normalized() * 80.0)
				q.exclude = [p.get_rid()]
				var hit := space.intersect_ray(q)
				if not hit.is_empty():
					spawn_impact(hit.position, hit.normal, hit.collider, i % 5 == 0)
	# --reload=F: hold a reload at that point (0..1) for the picture.
	var rl_at := -1.0
	for a in args:
		if a.begins_with("--reload="):
			rl_at = float(a.substr(9))
			p.mags[p.current_id()] = 0
			p.ammo[Weapons.caliber(p.current_id())] = 90
			p.start_reload()
	var grab_at := -1.0
	for a in args:
		if a.begins_with("--grab="):
			grab_at = float(a.substr(7))
	for i in wait:
		if grab_at >= 0.0:
			p.hands._grab = grab_at
		for a in args:
			if a.begins_with("--inspect="):
				p._inspect = float(a.substr(10))
		if rl_at >= 0.0 and p.reloading:
			p.reload_timer = p._reload_dur * (1.0 - rl_at)
			p._reload_events.clear()
		await get_tree().process_frame
		if args.has("--fire") and i % 6 == 0 and i > 20:
			p.fire_timer = 0.0
			p._try_fire()
			# Some enemy fire crossing the view as well.
			var side := Basis(Vector3.UP, p.yaw) * Vector3(-30, 1.5, -60)
			ballistics.fire(null, p.global_position + side, (p.global_position + Basis(Vector3.UP, p.yaw) * Vector3(25, 1, -50) - (p.global_position + side)).normalized(), "rifle", p.global_position + side, 1)
	if args.has("--jeep") or args.has("--drivecam"):
		# Park a jeep in front of the camera (or put us at the wheel).
		var jeep: Vehicle = vehicles[0]
		var fwd := Basis(Vector3.UP, p.yaw) * Vector3(0, 0, -1)
		var right := Basis(Vector3.UP, p.yaw) * Vector3(1, 0, 0)
		var jp := ground_at(p.global_position + fwd * 7.0 + right * 1.5)
		jeep.global_position = jp + Vector3(0, 0.35, 0)
		jeep.rotation = Vector3(0, p.yaw + 2.2, 0)
		jeep.linear_velocity = Vector3.ZERO
		for i in 40:
			await get_tree().physics_frame
		if args.has("--drivecam"):
			p.global_position = jeep.global_position + jeep.global_basis.x * 2.4
			_enter_vehicle(jeep)
			_drive_scripted = true
			p.yaw = jeep.global_basis.get_euler().y
			_veh_last_yaw = p.yaw
			for i in 90:
				jeep.throttle = 1.0
				jeep.steer_in = 0.25
				await get_tree().physics_frame
			_update_driving(0.5)
	if args.has("--dive"):
		p.test_hold["crouch"] = true
		for i in 150:
			await get_tree().physics_frame
	if args.has("--camper"):
		# A cautious bot on the upper floor of the framed house takes a window.
		var hh: Dictionary = world.villages.house_at(Vector2(p.global_position.x, p.global_position.z) + Vector2(-sin(p.yaw), -cos(p.yaw)) * 9.0, 1.0)
		if not hh.is_empty() and int(hh.get("built_levels", 1)) > 1:
			var nav := world.villages.house_nav(hh)
			var cb: Bot = bots[0]
			p.spawn_protect = 9999.0
			cb.state = Bot.State.GROUND
			cb.visible = true
			cb.global_position = (nav.up[3] as Vector3) + Vector3(0, 0.2, 0)
			cb.arm_weapon("rifle")
			cb.aggression = 0.0
			cb.shoot_skill = 0.0
			cb._camp_cool = 0.0
			var sight0 := cb.sight
			cb.sight = 0.0
			cb.set_physics_process(true)
			zone.center = Vector2(cb.global_position.x, cb.global_position.z)
			for i in 300:
				cb.enemy = null
				cb.loot_target = null
				cb._loot_scan = 99.0
				await get_tree().physics_frame
			cb.set_physics_process(false)
			cb.sight = sight0
			var to: Vector3 = cb.global_position + Vector3(0, 1.4, 0) - p.camera.global_position
			p.yaw = atan2(-to.x, -to.z)
			p.pitch = atan2(to.y, Vector2(to.x, to.z).length())
			print("[shot] camper camp_t=%.1f at %s" % [cb._camp_t, str(cb.global_position.round())])
			for i in 10:
				await get_tree().process_frame
	if args.has("--bot") or args.has("--botheal"):
		var poses := [["aim", "Idle", Vector3(-1.4, 0, -5.5), 2, 2], ["idle", "Jog_Fwd", Vector3(1.6, 0, -7.0), 1, 0], ["idle", "Sprint", Vector3(4.2, 0, -9.0), 3, 3]]
		if args.has("--botheal"):
			poses = [["bandage", "Idle", Vector3(-1.5, 0, -4.2), 2, 2], ["med", "Walk", Vector3(0.6, 0, -4.6), 1, 0], ["energy", "Idle", Vector3(2.4, 0, -4.4), 3, 3]]
		var k := 0
		for b in bots:
			if not is_instance_valid(b) or k >= poses.size():
				continue
			var pose: Array = poses[k]
			k += 1
			var fwd: Vector3 = Basis(Vector3.UP, p.yaw) * pose[2]
			b.state = Bot.State.GROUND
			b.visible = true
			b.global_position = ground_at(p.global_position + fwd) + Vector3(0, 0.05, 0)
			b.arm_weapon(["rifle", "carbine", "smg"][k - 1])
			b.set_physics_process(false)
			var to: Vector3 = p.global_position - b.global_position
			b.rotation.y = atan2(-to.x, -to.z) + (0.0 if pose[0] == "aim" else (0.45 if Bot.HEAL_FLAGS.has(pose[0]) else 1.2))
			b.body.set_gear(pose[3], pose[4])
			b.body.set_arms(pose[0])
			b.body.set_legs(pose[1])
			b.body.aim_dir = (p.global_position + Vector3(0, 1.5, 0)) - (b.global_position + Vector3(0, 1.4, 0)) if pose[0] == "aim" else -b.global_basis.z
		for i in 20:
			await get_tree().process_frame
	if args.has("--reload"):
		p.mags[p.current_id()] = 0
		p.ammo[Weapons.caliber(p.current_id())] = 60
		p.start_reload()
		# Freeze the pose at the moment the magazine is out.
		var at := 0.38
		for a in args:
			if a.begins_with("--at_t="):
				at = float(a.substr(7))
		p.reload_timer = p._reload_dur * (1.0 - at)
		p._update_weapon(0.0)
		p.set_physics_process(false)
	for a in args:
		if a.begins_with("--heal="):
			# Freeze a healing animation part-way through.
			var it := a.substr(7)
			p.bandages = 5
			p.meds = 2
			p.energy = 2
			p.hp = 40.0
			p.boost = 0.0
			p.grenades = 2
			var at := 0.5
			for b in args:
				if b.begins_with("--at_t="):
					at = float(b.substr(7))
			# Hand actions other than healing are frozen by setting their clocks.
			var set_t := func(x: float) -> void:
				match it:
					"grenade":
						p._throw_t = x
						p._thrown = x >= Player.THROW_RELEASE
					"vault":
						p._mantle = [p.global_position, p.global_position, x, 99.0]
					"swim":
						p._swim_phase = x
						p.swimming = true
						p.equip_t = 0.0
					_:
						p.heal_timer = p.heal_dur * (1.0 - x)
			if it == "grenade":
				p.throw_grenade()
			elif it != "vault" and it != "swim":
				p.use_item(it)
			var steps := 6
			for i in steps + 1:
				set_t.call(at * float(i) / float(steps))
				await get_tree().process_frame
			p.set_physics_process(false)
			p.hands._show = 1.0
			for i in 4:
				set_t.call(at)
				p._update_weapon(1.0 / 60.0)
				p._update_camera(1.0 / 60.0)
				await get_tree().process_frame
	if args.has("--warden"):
		# The Warden, posed in front of the camera; --scare=k freezes the jumpscare.
		var w := Warden.new()
		w.game = self
		w.target = p
		w.local_victim = false
		add_child(w)
		var fwd := Basis(Vector3.UP, p.yaw) * Vector3(0, 0, -1)
		var wp := p.global_position + fwd * 13.0
		wp.y = terrain.height_at(wp.x, wp.z)
		w.global_position = wp
		w.look_at(Vector3(p.global_position.x, wp.y, p.global_position.z), Vector3.UP)
		for i in 3:
			await get_tree().process_frame
		w.set_process(false)
		for a in args:
			if a.begins_with("--scare="):
				w._scare_t = float(a.substr(8))
				w._jumpscare(0.0)
				hud.set_scare(clampf((w._scare_t - 0.25) / 0.5, 0.0, 1.0))
		if args.has("--dread"):
			hud.set_dread(0.7)
		for i in 3:
			await get_tree().process_frame
	if args.has("--fire"):
		# One volley right before capture so tracers are in flight in the frame.
		get_tree().paused = false
		for k in 4:
			p.fire_timer = 0.0
			p._try_fire()
			for f in 3:
				await get_tree().process_frame
		for k in 4:
			var side := Basis(Vector3.UP, p.yaw) * Vector3(-40.0 + k * 3.0, 2.0 + k, -90.0)
			var tgt := Basis(Vector3.UP, p.yaw) * Vector3(30.0, 1.0 + k * 0.5, -40.0)
			ballistics.fire(null, p.global_position + side, (tgt - side).normalized(), "rifle", p.global_position + side, 1)
		# Advance the bullets a few metres without letting them leave the frame.
		for b in ballistics.bullets:
			b["pos"] = b["pos"] + Vector3(b["vel"]) * 0.035
			b["dist"] = float(b["dist"]) + float(b["speed"]) * 0.035
			b["trail"] = float(b["speed"]) * 0.035
			ballistics._place_tracer(b, p.camera)
		ballistics.set_physics_process(false)
		for b in ballistics.bullets:
			var mi: MeshInstance3D = b["mesh"]
			print("[shot] bullet pos=", b["pos"], " mesh vis=", mi.visible, " in_tree=", mi.is_inside_tree(), " xf=", mi.global_transform.origin, " scale=", mi.global_transform.basis.get_scale(), " cam=", p.camera.global_position)
	for a2 in args:
		if a2.begins_with("--state="):
			await _shot_state(a2.substr(8))
	print("[shot] frames waited")
	_dbg_pick()
	if args.has("--lookback"):
		p.yaw -= 2.05
		p.pitch = -0.95
		for i in 6:
			await get_tree().process_frame
	if OS.get_environment("DBG_ADS") != "" and player != null:
		print("[dbgads] grab_t=", player.hands._grab_t(), " vis=", player.hands.visible, " arm_l=", player.hands.arm_l.position, " gun=", not player.hands._gun.is_empty())
		print("[dbgads] holder=", player.gun_holder.position, " rot=", player.gun_holder.rotation, " view=", player.view.position, " ads=", Weapons.ads_pos(player.current_id(), player._optic_id), " blend=", player.aim_blend, " equip=", player.equip_t)
		if player._mag_node != null:
			print("[dbgads] magview=", player.view.global_transform.affine_inverse() * player._mag_node.global_position, " reload=", player.hands.reload, " arm_l=", player.hands.arm_l.position, " hands=", player.hands.transform)
	if OS.get_environment("DBG_SHADOW") != "" and player != null:
		var cp := player.camera.global_position
		for n in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
			var gi := n as GeometryInstance3D
			if gi.is_visible_in_tree() and gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and gi.global_position.distance_to(cp) < 3.0:
				print("[dbgshadow] ", gi.get_path(), " at ", (gi.global_position - cp).snapped(Vector3.ONE * 0.01))
	await RenderingServer.frame_post_draw
	print("[shot] post draw")
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("[shot] no image")
	else:
		img.save_png(out)
		print("[shot] saved ", out, " size=", img.get_size(), " objects=%d draws=%d prims=%dk" % [int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)) / 1000])
		# Report what the frame actually contains so a blind run is still useful.
		var dark := 0
		var bright := 0
		for y in range(0, img.get_height(), 7):
			for x in range(0, img.get_width(), 7):
				var c := img.get_pixel(x, y)
				var l := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
				if l < 0.02:
					dark += 1
				elif l > 0.5:
					bright += 1
		print("[shot] samples dark=", dark, " bright=", bright)
	get_tree().quit()


## The shape node a physics hit landed on (null for tree trunks: their
## shapes live on the physics server alone).
func _shape_node(body: CollisionObject3D, shape_idx: int) -> Node:
	if body == null or str(body.name) == "TreeCollision" or shape_idx < 0:
		return null
	return body.shape_owner_get_owner(body.shape_find_owner(shape_idx))


# --------------------------------------------------------------- smoke test --
func _run_smoke() -> void:
	print("[smoke] lobby ready, world loot=", world.loot_points.size())
	# Tree trunks must stop bullets and bodies.
	var tcol := world.get_node_or_null("TreeCollision")
	if tcol != null:
		await get_tree().physics_frame
		var tsp := get_world_3d().direct_space_state
		var th := 0
		var tn := 0
		for rec in world.tree_records:
			if tn >= 200:
				break
			tn += 1
			var tp: Vector3 = Vector3(rec.pos) + Vector3.UP * 1.45
			var tq := PhysicsRayQueryParameters3D.create(tp + Vector3(3, 0, 0), tp - Vector3(3, 0, 0), 1)
			var thit := tsp.intersect_ray(tq)
			if not thit.is_empty() and str((thit["collider"] as Node).name) == "TreeCollision":
				th += 1
		print("[smoke] tree trunks hit by rays: %d / %d" % [th, tn])
	await get_tree().process_frame
	var tb := world.get_node_or_null("TerrainCollision")
	print("[smoke] terrain node=", tb != null, " shapes=", (tb.get_child_count() if tb != null else -1), " layer=", (tb.collision_layer if tb != null else -1))
	var ray_hits := 0
	var ray_miss := 0
	for gi in range(-4, 4):
		for gj in range(-4, 4):
			var px := float(gi) * 100.0 + 37.0
			var pz := float(gj) * 100.0 + 53.0
			var q := PhysicsRayQueryParameters3D.create(Vector3(px, 300, pz), Vector3(px, -40, pz), 1)
			var hit := get_world_3d().direct_space_state.intersect_ray(q)
			if hit.is_empty():
				ray_miss += 1
			else:
				ray_hits += 1
	print("[smoke] terrain rays hit=", ray_hits, " miss=", ray_miss)
	# Collision must match the rendered ground: compare ray hits to the mesh.
	var worst := 0.0
	var sum := 0.0
	var cnt := 0
	for i in 400:
		var px := randf_range(-440.0, 440.0)
		var pz := randf_range(-440.0, 440.0)
		var q := PhysicsRayQueryParameters3D.create(Vector3(px, 300, pz), Vector3(px, -40, pz), 1)
		q.collide_with_bodies = true
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty() or not (hit["collider"] as Node).name.begins_with("Terrain"):
			continue
		var err := absf(float(hit["position"].y) - terrain.mesh_height_at(px, pz))
		worst = maxf(worst, err)
		sum += err
		cnt += 1
	print("[smoke] ground collision vs mesh: n=%d avg err=%.3f m worst=%.3f m" % [cnt, sum / maxf(1, cnt), worst])
	_start_match()
	print("[smoke] match started plane=", plane != null, " bots=", bots.size(), " loot=", loot_pool.size())
	await get_tree().physics_frame
	await get_tree().physics_frame
	_player_jump(true)
	print("[smoke] jumped, player y=", player.global_position.y, " mode=", player.mode)
	# Fast-forward the drop: teleport to a landing spot and land.
	var drop := _random_ground_point(300.0)
	player.global_position = drop + Vector3(0, 2.0, 0)
	player.open_chute()
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.mode = Player.Mode.GROUND
	player.landed = true
	player.global_position = drop + Vector3(0, 0.4, 0)
	player.velocity = Vector3.ZERO
	player.give_weapon("rifle")
	player.add_armor(50.0)
	print("[smoke] armed=", player.current_id(), " mag=", player.current_mag(), " hp=", player.hp, " armor=", player.armor)
	await get_tree().create_timer(1.0).timeout
	print("[smoke] player after 1s mode=", player.mode, " y=", player.global_position.y, " floor=", player.is_on_floor() if player.has_method("is_on_floor") else "n/a", " vel=", player.velocity)
	var picked := 0
	for l in loot_pool:
		if is_instance_valid(l) and not l.taken and l.global_position.distance_to(player.global_position) < 3.0:
			player.global_position = l.global_position + Vector3(0, 0.3, 0)
			try_pickup(player)
			picked += 1
	print("[smoke] proximity pickups tested=", picked)
	print("[smoke] audio rifle=", sfx.stream("shot_rifle") != null, " ui=", sfx.stream("zone_warn") != null, " loop=", sfx.stream("plane_loop") != null)
	# Every gun needs all its distances and its own first-person shot.
	var missing_gun := []
	for wid in Weapons.DEFS:
		var snd := str(Weapons.def(wid)["sound"])
		for suf in ["_1", "_4", "_fp_1", "_fp_3", "_far", "_vfar"]:
			if sfx.stream("shot_" + snd + suf) == null:
				missing_gun.append("shot_" + snd + suf)
	for env in ["field", "forest", "town", "indoor"]:
		if sfx.stream("tail_" + env) == null:
			missing_gun.append("tail_" + env)
	print("[smoke] gun sounds missing: ", missing_gun if not missing_gun.is_empty() else "none")
	if not missing_gun.is_empty():
		push_error("gun sounds missing: " + str(missing_gun))
	# Fast-forward the plane so every bot jumps, then let them descend.
	if plane != null:
		plane.t = 0.97
	# The plane runs 46 s end to end; for the smoke, drop each bot over its own target.
	for b in bots:
		if is_instance_valid(b) and b.state == Bot.State.PLANE:
			b.jump_from_plane()
			var gy: float = terrain.height_at(b.drop_target.x, b.drop_target.y)
			b.global_position = Vector3(b.drop_target.x, gy + 55.0, b.drop_target.y)
			b.velocity = Vector3.ZERO
	await get_tree().create_timer(0.4).timeout
	print("[smoke] bots jumping: plane=", _count_state(Bot.State.PLANE), " falling=", _count_state(Bot.State.FALL) + _count_state(Bot.State.CHUTE))
	# Force a bot to fight and die so the kill path is exercised.
	var victim: Bot = null
	for b in bots:
		if is_instance_valid(b):
			victim = b
			break
	if victim != null:
		victim.state = Bot.State.GROUND
		victim.global_position = player.global_position + Vector3(4, 1, 0)
		var before := alive
		victim.take_damage(500.0, victim.global_position, true, player)
		print("[smoke] bot killed alive ", before, " -> ", alive)
	if zone != null:
		zone.set_process(true)
		zone.timer = 1.0
		print("[smoke] zone phase=", zone.phase, " radius=", zone.radius, " dps=", zone.damage_per_second())
	await get_tree().create_timer(12.0).timeout
	print("[smoke] after 12s zone phase=", zone.phase if zone else -1, " radius=", zone.radius if zone else -1, " alive=", alive)
	print("[smoke] bots landed=", _count_landed_bots(), " player_kills=", player_kills, " armed_bots=", _count_armed_bots())
	var with_target := 0
	var moving := 0
	var grounded := 0
	var avg_nearest := 0.0
	var n_dbg := 0
	var sample: Bot = null
	for b in bots:
		if not is_instance_valid(b):
			continue
		if sample == null:
			sample = b
		n_dbg += 1
		if b.loot_target != null:
			with_target += 1
		if Vector2(b.velocity.x, b.velocity.z).length() > 0.5:
			moving += 1
		if b.is_on_floor():
			grounded += 1
		avg_nearest += _nearest_weapon(b)
	if n_dbg > 0:
		avg_nearest /= float(n_dbg)
	print("[smoke] bots n=", n_dbg, " with_target=", with_target, " moving=", moving, " on_floor=", grounded, " avg_nearest=", snappedf(avg_nearest, 0.1))
	if sample != null:
		print("[smoke] sample state=", sample.state, " pos=", sample.global_position, " armed=", sample.armed, " loot_scan=", sample._loot_scan, " vel=", sample.velocity, " nearest=", _nearest_weapon(sample))
	await get_tree().create_timer(12.0).timeout
	print("[smoke] after 24s alive=", alive, " armed_bots=", _count_armed_bots(), " kills=", player_kills, " bot_fights_ok=", alive < 19)
	print("[smoke] map data=", world.map_data_texture, " canopy=", world.map_canopy_texture)
	print("[smoke] OK")
	get_tree().quit()


func _nearest_weapon(b: Bot) -> float:
	var best := 9999.0
	for l in loot_pool:
		if is_instance_valid(l) and not l.taken and l.kind == "weapon":
			best = minf(best, l.global_position.distance_to(b.global_position))
	return best


func _count_state(st: int) -> int:
	var n := 0
	for b in bots:
		if is_instance_valid(b) and b.state == st:
			n += 1
	return n


func _count_armed_bots() -> int:
	var n := 0
	for b in bots:
		if is_instance_valid(b) and b.armed:
			n += 1
	return n


func _count_landed_bots() -> int:
	var n := 0
	for b in bots:
		if is_instance_valid(b) and b.state == Bot.State.GROUND:
			n += 1
	return n


# ----------------------------------------------------------------- sim test --
# Headless gameplay test: exercises loot, items, ballistics, then fast-forwards
# a whole match with an invulnerable observer. Run with --fixed-fps 60.
func _check(name: String, ok: bool) -> void:
	print("[sim] %s %s" % ["PASS" if ok else "FAIL", name])


func _run_sim() -> void:
	_start_match()
	await get_tree().physics_frame
	_player_jump(true)
	var spot := _random_ground_point(200.0)
	player.global_position = spot + Vector3(0, 1.0, 0)
	player.mode = Player.Mode.GROUND
	player.landed = true
	player.velocity = Vector3.ZERO
	for i in 5:
		await get_tree().physics_frame
	# Loot of every kind.
	var kinds := [["weapon", "rifle"], ["ammo", "5.56"], ["armor", "2"], ["helmet", "1"], ["bandage", ""], ["med", ""],
		["energy", ""], ["scope", "4x"], ["extmag", ""], ["comp", ""], ["grenade", ""], ["weapon", "sniper"], ["armor", "3"], ["ammo", "7.62"], ["ammo", "7.62"], ["ammo", "7.62"]]
	for k in kinds:
		var l := _spawn_loot(k[0], k[1], player.global_position)
		await get_tree().process_frame
		var why := l.block_reason(player)
		var ok := why == "" and l.pickup(player)
		_check("pickup %s %s %s" % [k[0], k[1], why], ok)
		loot_pool.erase(l)
	_check("loadout rifle+sniper", player.loadout.size() == 2 and player.loadout.has("sniper"))
	_check("vest lv3", player.vest_level == 3)
	_check("extmag mag size", player.mag_size("rifle") == 45)
	var att0: Dictionary = player.attachments[player.loadout.find("rifle")]
	_check("rifle has 4x", str(att0.get("scope", "")) == "4x")
	# Healing.
	player.hp = 40.0
	player.use_item("bandage")
	for i in 150:
		await get_tree().physics_frame
	_check("bandage heals 40->55 (%d)" % int(player.hp), absf(player.hp - 55.0) < 1.5)
	player.use_item("med")
	for i in 250:
		await get_tree().physics_frame
	_check("medkit heals (%d)" % int(player.hp), player.hp > 99.0)
	# Reload: empty the mag then reload.
	player.select_slot(player.loadout.find("rifle"))
	for i in 30:
		await get_tree().physics_frame
	player.mags["rifle"] = 0
	player.start_reload()
	for i in 200:
		await get_tree().physics_frame
	_check("reload fills ext mag (%d)" % player.current_mag(), player.current_mag() == 45)
	# Ballistics: a bot 250 m away, aim with holdover, check a hit lands.
	player.select_slot(player.loadout.find("sniper"))
	for i in 40:
		await get_tree().physics_frame
	var target: Bot = null
	for b in bots:
		if is_instance_valid(b):
			target = b
			break
	var dir2 := Vector2(1, 0)
	var tgt_pos := Vector3.ZERO
	for attempt in 30:
		var a := randf() * TAU
		dir2 = Vector2(cos(a), sin(a))
		var p2 := Vector2(player.global_position.x, player.global_position.z) + dir2 * 250.0
		var h := terrain.height_at(p2.x, p2.y)
		if h > 2.0:
			tgt_pos = Vector3(p2.x, h, p2.y)
			break
	target.state = Bot.State.GROUND
	target.set_physics_process(false)
	# Both up in clear air so nothing but the bullet's own drop matters.
	var sky := maxf(player.global_position.y, tgt_pos.y) + 70.0
	target.global_position = Vector3(tgt_pos.x, sky, tgt_pos.z)
	player.global_position = Vector3(player.global_position.x, sky, player.global_position.z)
	player.set_physics_process(false)
	var eye := player.global_position + Vector3(0, Player.EYE, 0)
	var aim := target.global_position + Vector3(0, 1.0, 0)
	var dist := eye.distance_to(aim)
	var tof := dist / float(Weapons.def("sniper")["velocity"])
	var hold := aim + Vector3(0, 0.5 * Ballistics.GRAVITY * tof * tof, 0)
	var hp_before := target.hp
	# Drop check: a level shot into open sky, sampled after ~0.35 s of flight.
	ballistics.fire(player, eye + Vector3(0, 60, 0), Vector3(dir2.x, 0, dir2.y), "sniper", eye, 999001)
	for i in 21:
		await get_tree().physics_frame
	if ballistics.bullets.size() > 0:
		var bp: Vector3 = ballistics.bullets[0]["pos"]
		var fell := eye.y + 60.0 - bp.y
		var flown := Vector2(bp.x - eye.x, bp.z - eye.z).length()
		_check("bullet drop %.2f m after %.0f m (expect ~0.58)" % [fell, flown], fell > 0.45 and fell < 0.75 and flown > 230.0)
	ballistics.clear()
	ballistics.fire(player, eye, (hold - eye).normalized(), "sniper", eye, 999002)
	for i in 40:
		await get_tree().physics_frame
	_check("250m shot with holdover hits (hp %d)" % int(target.hp), target.hp < hp_before)
	player.set_physics_process(true)
	target.set_physics_process(true)
	# Gun handling: recoil pattern is repeatable, fire mode, zeroing.
	player.select_slot(player.loadout.find("rifle"))
	for i in 30:
		await get_tree().physics_frame
	var seq_a: Array = []
	var seq_b: Array = []
	for i in 8:
		seq_a.append(Weapons.recoil_step("rifle", i))
		seq_b.append(Weapons.recoil_step("rifle", i))
	_check("recoil pattern deterministic", seq_a == seq_b and absf(seq_a[0].x) < 0.01 and seq_a[7].x != 0.0)
	_check("rifle starts auto", player.is_auto())
	player.toggle_fire_mode()
	_check("fire mode toggles to single", not player.is_auto())
	player.toggle_fire_mode()
	player.adjust_zero(100)
	player.adjust_zero(100)
	_check("rifle zero 300 (%d)" % player.cur_zero(), player.cur_zero() == 300)
	_check("zero angle sane", Weapons.zero_angle("rifle", 300.0) > 0.0005 and Weapons.zero_angle("rifle", 300.0) < 0.02)
	_check("ammo pools: 5.56=%d 7.62=%d" % [player.ammo_of("5.56"), player.ammo_of("7.62")], player.ammo_of("5.56") > 0 and player.ammo_of("7.62") > 0)
	# Firing feel: brass ejects and the muzzle smokes.
	player.select_slot(player.loadout.find("rifle"))
	for i in 30:
		await get_tree().physics_frame
	player.mags["rifle"] = 10
	player.fire_timer = 0.0
	player._try_fire()
	await get_tree().physics_frame
	_check("casing ejected (%d) and smoke (%d)" % [player._casings.size(), _smokes], player._casings.size() > 0 and _smokes > 0)
	# Auto pickup: ammo for a carried gun is taken just by walking over it.
	player.global_position = spot + Vector3(0, 1.0, 0)
	player.ammo["7.62"] = 0
	var box := _spawn_loot("ammo", "7.62", ground_at(player.global_position) + Vector3(0, 0.08, 0))
	var stray := _spawn_loot("ammo", "12ga", ground_at(player.global_position) + Vector3(0.4, 0.08, 0))
	for i in 30:
		await get_tree().physics_frame
	_check("auto pickup 7.62 (%d)" % player.ammo_of("7.62"), player.ammo_of("7.62") > 0 and (not is_instance_valid(box) or box.taken))
	_check("no auto pickup for 12ga (no shotgun)", is_instance_valid(stray) and not stray.taken)
	# Grenade.
	player.global_position = spot + Vector3(0, 1.0, 0)
	var g_before := player.grenades
	player.throw_grenade()
	_check("grenade still in hand at the start of the throw", player.grenades == g_before and player.is_throwing())
	for i in 60:
		await get_tree().physics_frame
	_check("grenade thrown", player.grenades == g_before - 1 and not player.is_throwing())
	for i in 240:
		await get_tree().physics_frame
	# Full match fast-forward.
	player.spawn_protect = 1.0e9
	var t0 := match_time
	var last_print := 0.0
	while alive > 1 and match_time - t0 < 3300.0:
		await get_tree().physics_frame
		if match_time - last_print > 60.0:
			last_print = match_time
			print("[sim] t=%d alive=%d zone phase=%d r=%d armed=%d" % [int(match_time), alive, zone.phase, int(zone.radius), _count_armed_bots()])
	print("[sim] match over t=%d alive=%d bullets_live=%d" % [int(match_time), alive, ballistics.bullets.size()])
	_check("match finishes", alive <= 1)
	get_tree().quit()


# -------------------------------------------------------------- cycle test --
# Several matches back to back, ending each a different way, checking that
# nothing leaks or sticks between them.
func _census() -> String:
	var counts := {}
	for c in get_children():
		var k := c.get_class()
		if c.get_script() != null and (c.get_script() as Script).get_global_name() != "":
			k = (c.get_script() as Script).get_global_name()
		counts[k] = int(counts.get(k, 0)) + 1
	var keys := counts.keys()
	keys.sort()
	var parts: Array[String] = []
	for k in keys:
		parts.append("%s=%d" % [k, counts[k]])
	return ", ".join(parts)


func _land_player_now() -> void:
	anticheat.grace(2.0)
	_player_jump(true)
	var drop := _random_ground_point(250.0)
	player.global_position = drop + Vector3(0, 0.5, 0)
	player.mode = Player.Mode.GROUND
	player.landed = true
	player.velocity = Vector3.ZERO
	on_player_landed()


func _run_cycle() -> void:
	for i in 10:
		await get_tree().process_frame
	var base := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	print("[cycle] baseline nodes=%d  %s" % [base, _census()])
	var endings := ["death", "win", "quit", "death"]
	for r in endings.size():
		_start_match()
		for i in 30:
			await get_tree().physics_frame
		_land_player_now()
		for i in 90:
			await get_tree().physics_frame
		player.start_reload()
		match endings[r]:
			"death":
				var killer: Node = bots[0] if bots.size() > 0 else null
				player.spawn_protect = 0.0
				player.take_damage(9999.0, player.global_position + Vector3(5, 0, 0), false, killer)
			"win":
				for b in bots:
					if is_instance_valid(b) and b.alive:
						b.take_damage(9999.0, b.global_position, false, player)
			"quit":
				_quit_to_menu()
		for i in 120:
			await get_tree().physics_frame
		print("[cycle] round %d (%s): phase=%s alive=%d winner=%s nodes=%d paused=%s" % [r, endings[r], phase, alive, winner, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), get_tree().paused])
		print("[cycle]   hud: progress=%.2f scope=%s low_hp=%.2f storm=%s end_visible=%s menu=%s prompt='%s'" % [hud.progress_frac, hud.scoped, hud.low_hp, hud.in_storm, hud.end_panel.visible, hud.menu.visible, hud.prompt_label])
		print("[cycle]   audio: cabin=%s wind=%s storm=%s  children: %s" % [_cabin != null, _wind2d != null, _storm != null, _census()])
	_quit_to_menu()
	for i in 120:
		await get_tree().physics_frame
	var end_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	print("[cycle] final nodes=%d (baseline %d, diff %d)  %s" % [end_nodes, base, end_nodes - base, _census()])
	get_tree().quit()


# --------------------------------------------------------------- perf test --
func _run_perf() -> void:
	for i in 10:
		await get_tree().process_frame
	_start_match()
	for i in 30:
		await get_tree().physics_frame
	_land_player_now()
	player.spawn_protect = 1.0e9
	# Let the bots land and spread out, then measure a minute of play.
	for i in 60 * 45:
		await get_tree().physics_frame
	if OS.get_cmdline_user_args().has("--nobots"):
		for b in bots:
			if is_instance_valid(b):
				b.set_physics_process(false)
	if OS.get_environment("PERF_GRASS") != "" and world.grass != null:
		world.grass.set_radius(38.0)
	var exp_mode := OS.get_environment("PERF_EXP")
	if exp_mode == "noanim":
		for n in find_children("*", "AnimationMixer", true, false):
			(n as AnimationMixer).active = false
	elif exp_mode == "noaudio":
		for n in find_children("*", "AudioStreamPlayer3D", true, false):
			(n as AudioStreamPlayer3D).stop()
			(n as AudioStreamPlayer3D).process_mode = Node.PROCESS_MODE_DISABLED
	print("[perf] exp=", exp_mode, " anim mixers=", find_children("*", "AnimationMixer", true, false).size(), " audio3d=", find_children("*", "AudioStreamPlayer3D", true, false).size(), " lights=", find_children("*", "Light3D", true, false).size())
	for window in 3:
		Prof.reset()
		Prof.on = true
		var phys := 0.0
		var proc := 0.0
		var n := 0
		var worst := 0.0
		var last_us := Time.get_ticks_usec()
		var snap: Dictionary = {}
		var spikes := 0
		var wall_sum := 0.0
		var wall_max := 0.0
		for i in 60 * 15:
			await get_tree().physics_frame
			var now_us := Time.get_ticks_usec()
			var wall := float(now_us - last_us) / 1000.0
			last_us = now_us
			wall_sum += wall
			wall_max = maxf(wall_max, wall)
			if wall > 33.0:
				spikes += 1
				var diff: Array = []
				for k in Prof.acc:
					var dv2 := float(int(Prof.acc[k]) - int(snap.get(k, 0))) / 1000.0
					if dv2 > 1.0:
						diff.append("%s %.1f" % [k, dv2])
				if spikes <= 6:
					print("[perf]   SPIKE frame %d: %.1f ms wall | %s" % [i, wall, ", ".join(diff)])
			snap = Prof.acc.duplicate()
			if OS.get_environment("PERF_SEC") != "" and i % 60 == 59:
				var parts2: Array = []
				for k in Prof.acc:
					if float(Prof.acc[k]) > 2000.0:
						parts2.append("%s %.1f" % [k, float(Prof.acc[k]) / 1000.0])
				print("[perf]     sec %d phys %.1f ms | %s" % [i / 60, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, ", ".join(parts2)])
			var p := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			if OS.get_environment("PERF_SEC") != "" and i % 30 == 0:
				var awake := 0
				for v in vehicles:
					if is_instance_valid(v) and not v.freeze:
						awake += 1
				print("[perf]       f%d phys %.1f active=%d pairs=%d islands=%d awake_jeeps=%d" % [i, p, PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_ACTIVE_OBJECTS), PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_COLLISION_PAIRS), PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_ISLAND_COUNT), awake])
			phys += p
			proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			worst = maxf(worst, p)
			n += 1
		print("[perf] window %d: physics avg %.2f ms (worst %.2f)  process avg %.2f ms  alive=%d bullets=%d nodes=%d" % [
			window, phys / n, worst, proc / n, alive, ballistics.bullets.size(), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
		print("[perf]   wall frame avg %.2f ms, max %.1f ms, frames over 33 ms: %d" % [wall_sum / float(n), wall_max, spikes])
		var parts: Array = []
		for k in Prof.acc:
			parts.append("%s %.2f" % [k, float(Prof.acc[k]) / 1000.0 / float(n)])
		print("[perf]   per frame ms: ", ", ".join(parts))
		Prof.on = false
	get_tree().quit()


## Puts the match into a particular state for a screenshot.
func _shot_state(st: String) -> void:
	var p := player
	match st:
		"menu":
			hud.root.visible = true
			hud.show_menu("SEED %d" % seed_value)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			for i in 10:
				await get_tree().process_frame
		"freefall":
			hud.root.visible = true
			p.mode = Player.Mode.FREEFALL
			p.global_position += Vector3(0, 140, 0)
			p.velocity = Vector3(0, -55, 0)
			p.pitch = -0.7
		"chute":
			hud.root.visible = true
			p.mode = Player.Mode.FREEFALL
			p.global_position += Vector3(0, 60, 0)
			p.open_chute()
			p.pitch = 0.9
		"storm":
			zone.radius = 20.0
			zone.center = Vector2(p.global_position.x + 120.0, p.global_position.z)
			zone.set_process(false)
			zone._apply_wall()
			hud.set_storm(true)
		"lowhp":
			p.spawn_protect = 0.0
			p.take_damage(80.0, p.global_position + Vector3(4, 0, -6), false, bots[0])
		"inventory":
			for k in [["armor", "2"], ["helmet", "3"], ["bandage", ""], ["med", ""], ["energy", ""], ["grenade", ""], ["ammo", "5.56"], ["scope", "2x"]]:
				var l := _spawn_loot(k[0], k[1], p.global_position)
				l.pickup(p)
			p.give_weapon("dmr")
			p.boost = 60.0
		"death":
			p.spawn_protect = 0.0
			player_kills = 3
			damage_dealt = 412.0
			p.take_damage(999.0, p.global_position + Vector3(5, 0, 0), true, bots[0])
		"win":
			player_kills = 7
			damage_dealt = 960.0
			for b in bots:
				if is_instance_valid(b) and b.alive:
					b.take_damage(9999.0, b.global_position, false, p)
		"loading":
			hud.show_loading("GROWING THE FORESTS", 0.6)
		"pause":
			hud.show_pause(true)
			for a3 in OS.get_cmdline_user_args():
				if a3.begins_with("--tab="):
					hud._show_tab(int(a3.substr(6)))
		"settings":
			_quit_to_menu()
			hud._open_settings()
		"firefight":
			# Bursts crossing the view at 40, 120 and 300 m, caught mid-flight.
			var ffwd := Basis(Vector3.UP, p.yaw) * Vector3(0, 0, -1)
			var fright := ffwd.cross(Vector3.UP)
			var shooter: Node = bots[0] if not bots.is_empty() else p
			var seq := 9000
			for i in 8:
				for d in [15.0, 40.0, 120.0, 300.0]:
					var from: Vector3 = p.global_position + ffwd * float(d) - fright * 45.0 + Vector3.UP * (1.6 + 0.04 * i)
					from.y = maxf(from.y, terrain.height_at(from.x, from.z) + 1.6) + (0.0 if d < 20.0 else 4.0 + float(d) * 0.04)
					seq += 1
					ballistics.fire(shooter, from, (fright + ffwd * randf_range(-0.01, 0.01)).normalized(), "rifle", from, seq, 0.2)
				await get_tree().physics_frame
			await get_tree().physics_frame
			await get_tree().physics_frame
			return
		"airdrop":
			var c := Vector2(p.global_position.x, p.global_position.z) + Vector2(cos(p.yaw + PI * 0.5), -sin(p.yaw + PI * 0.5)) * 0.0
			var fwd := Basis(Vector3.UP, p.yaw) * Vector3(0, 0, -14)
			var drop := Airdrop.new()
			drop.setup(self, Vector2(p.global_position.x + fwd.x, p.global_position.z + fwd.z), ground_at(p.global_position + fwd).y)
			add_child(drop)
			airdrops.append(drop)
			drop.position.y = ground_at(p.global_position + fwd).y + 0.05
			for i in 5:
				await get_tree().process_frame
	for i in 25:
		await get_tree().process_frame


# ================================================================ LAN play ==

func _net_host() -> void:
	if not lobby_ready:
		return
	sfx.play_ui("ui_click", -6.0)
	if net.host():
		lobby.show_lobby()


func _net_leave() -> void:
	net.leave("")
	lobby.close()
	if phase != "menu":
		_quit_to_menu()


var _reco_shown := ""


func _on_reconnect_state(text: String) -> void:
	if text == _reco_shown:
		return
	_reco_shown = text
	if text != "":
		hud.show_notice(text, 1.3)


func _on_left_session(reason: String) -> void:
	if phase != "menu":
		_quit_to_menu()
	if reason == "CONNECTION FAILED":
		# Stay on the join screen so another address can be tried.
		lobby.show_join()
		lobby.connection_failed("COULD NOT REACH THAT HOST  ·  CHECK THE ADDRESS AND THAT YOU ARE ON THE SAME NETWORK")
		return
	lobby.close()
	hud.show_menu(reason)


## Host started a match from the lobby.
func _net_host_start() -> void:
	if not net.hosting or not lobby_ready:
		return
	lobby.close()
	_start_match()


## Client: the host's roster arrived. Make sure we have the host's island.
func net_lobby_update(seed_v: int, size: int) -> void:
	match_size = size
	MAX_BOTS = size - 1
	if seed_v != seed_value and seed_v != 0:
		_rebuild_world(seed_v)


func _rebuild_world(seed_v: int) -> void:
	lobby_ready = false
	seed_value = seed_v
	hud.show_menu("LOADING THE HOST'S ISLAND ...")
	if world != null and is_instance_valid(world):
		world.queue_free()
	world = null
	await get_tree().process_frame
	await get_tree().process_frame
	await _build_world()
	_refresh_places()
	lobby_ready = true
	_show_menu()


func net_on() -> bool:
	# Still a networked match while a dropped client dials back in.
	return net != null and ((net.active and net.match_running) or net.reconnecting)


func net_is_client() -> bool:
	return net != null and net.active and not net.hosting


## Stable network name for anything that can shoot or be shot.
## Where a remote player is (host side), or INF if unknown.
func net_peer_position(pid: int) -> Vector3:
	var h = humans.get(pid)
	if h != null and is_instance_valid(h):
		return (h as Node3D).global_position
	return Vector3.INF


func node_key(n: Object) -> String:
	if n == null or not is_instance_valid(n):
		return ""
	if n == player:
		return net.my_key()
	if n is Bot:
		var b := n as Bot
		if b.is_human:
			return "p%d" % b.peer_id
		if b.puppet:
			return "b%d" % b.net_index
		return "b%d" % bots.find(b)
	return ""


func node_for_key(key: String) -> Node:
	if key == "":
		return null
	if key == net.my_key():
		return player
	if key.begins_with("p"):
		return humans.get(int(key.substr(1)))
	if key.begins_with("b"):
		var i := int(key.substr(1))
		if i >= 0 and i < bots.size() and is_instance_valid(bots[i]):
			return bots[i]
	return null


func _name_for_key(key: String) -> String:
	if key == net.my_key():
		return "YOU"
	var n := node_for_key(key)
	if n != null and n.has_method("display_name"):
		return str(n.call("display_name"))
	if key.begins_with("p"):
		return str(net.roster.get(int(key.substr(1)), "PLAYER"))
	return "THE STORM" if key == "" else "SOMEONE"


func _make_human(peer_id: int, pname: String) -> Bot:
	var h := Bot.new()
	h.puppet = true
	h.is_human = true
	h.peer_id = peer_id
	h.friendly = net.squad
	h.setup(pname, Vector2.ZERO, self, peer_id)
	add_child(h)
	h.global_position = plane.seat_position() if plane != null else Vector3(0, 300, 0)
	humans[peer_id] = h
	return h


## Host: package the match that _start_match just set up.
func _net_send_setup() -> void:
	# Loot packed tight: a table of kind/item names and 7 floats per item,
	# zstd-compressed (a few dozen KB instead of a quarter megabyte).
	var names_t: Array = []
	var name_i: Dictionary = {}
	var fl := PackedFloat32Array()
	for l in loot_pool:
		if not is_instance_valid(l):
			continue
		var nk := "%s|%s" % [l.kind, l.item_id]
		if not name_i.has(nk):
			name_i[nk] = names_t.size()
			names_t.append(nk)
		fl.append_array([float(l.net_id), float(name_i[nk]), l.position.x, l.position.y, l.position.z, float(l.mag_override), float(l.reserve_override)])
	var raw := fl.to_byte_array()
	var loot := [names_t, raw.size(), raw.compress(FileAccess.COMPRESSION_ZSTD)]
	var bot_names: Array = []
	for b in bots:
		bot_names.append(b.bot_name)
	var list: Array = []
	for id in net.roster:
		list.append([id, net.roster[id]])
	for id in net.roster:
		if int(id) != 1:
			_make_human(int(id), str(net.roster[id]))
	var setup := {
		"seed": seed_value, "squad": net.squad, "plane": [plane_start, plane_end],
		"loot": loot, "bots": bot_names, "humans": list, "total": total_players,
		"loadout": loadout_enabled, "vehicles": _match_vehicles, "weather": _match_weather,
		"match_id": randi() % 1000000000 + 1,
	}
	_last_setup = setup
	human_inv.clear()
	net.send_setup(setup)


## Client: build the host's match locally.
func net_start_match(setup: Dictionary) -> void:
	if int(setup.get("seed", seed_value)) != seed_value:
		# Should not happen (the roster carries the seed), but never desync.
		await _rebuild_world(int(setup["seed"]))
	# The island for the host's seed may still be building (a rejoin right
	# after launching the game): wait for it rather than build it twice.
	var waited := 0.0
	while not lobby_ready and waited < 60.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	lobby.close()
	sfx.play_ui("ui_click", -6.0)
	hud.hide_menu()
	hud.hide_end()
	hud.clear_killfeed()
	hud.set_spectate("")
	_cleanup_match()
	player.reset_for_match()
	anticheat.reset_match()
	net.squad = bool(setup.get("squad", true))
	var path: Array = setup["plane"]
	plane_start = path[0]
	plane_end = path[1]
	plane = DropPlane.new()
	plane.name = "Plane"
	add_child(plane)
	plane.setup(plane_start, plane_end)
	hud.set_plane_path(plane_start, plane_end)
	menu_cam.make_current()
	phase = "plane"
	player.global_position = plane.seat_position()
	loot_pool.clear()
	loot_grid.clear()
	loot_by_id.clear()
	if setup.get("loot2") != null:
		for e in _unpack_loot_v2(setup["loot2"]):
			var l2 := _spawn_loot(str(e[1]), str(e[2]), e[3], int(e[4]), int(e[5]), int(e[0]), false)
			l2.dropped = bool(e[6])
	else:
		var lp: Array = setup["loot"]
		var names_t: Array = lp[0]
		var fl: PackedFloat32Array = (lp[2] as PackedByteArray).decompress(int(lp[1]), FileAccess.COMPRESSION_ZSTD).to_float32_array()
		for o in range(0, fl.size() - 6, 7):
			var nk: String = names_t[int(fl[o + 1])]
			var pos := Vector3(fl[o + 2], fl[o + 3], fl[o + 4])
			var l := _spawn_loot(nk.get_slice("|", 0), nk.get_slice("|", 1), pos, int(fl[o + 5]), int(fl[o + 6]), int(fl[o]), false)
			l.position = pos
	bots.clear()
	var names: Array = setup["bots"]
	for i in names.size():
		var b := Bot.new()
		b.puppet = true
		b.net_index = i
		b.setup(str(names[i]), Vector2.ZERO, self, i)
		add_child(b)
		b.global_position = plane.seat_position()
		bots.append(b)
	for e in setup["humans"]:
		var id := int(e[0])
		if id != net.my_id():
			_make_human(id, str(e[1]))
	zone = Zone.new()
	zone.name = "Zone"
	zone.terrain = terrain
	add_child(zone)
	zone.start(1250.0)
	zone.set_process(false)
	zone.phase_changed.connect(_on_zone_phase)
	zone_was_warning = false
	_spawn_vehicles(setup.get("vehicles", []))
	world.set_weather(str(setup.get("weather", "clear")))
	total_players = int(setup.get("total", names.size() + 1))
	alive = total_players
	loadout_enabled = bool(setup.get("loadout", loadout_enabled))
	player_kills = 0
	damage_dealt = 0.0
	match_time = 0.0
	survive_time = 0.0
	zone_acc = 0.0
	winner = false
	_net_setup_ok = true
	_after_match_setup()
	if setup.has("resume"):
		_apply_resume(setup["resume"])


func net_abort() -> void:
	if phase != "menu":
		_quit_to_menu()
	hud.show_menu("THE HOST ENDED THE MATCH")
	lobby.show_lobby()


## Host -> clients, ~12 times a second.
func net_snapshot() -> Array:
	var bp := PackedFloat32Array()
	for b in bots:
		if is_instance_valid(b):
			(b as Bot).net_pack(bp)
		else:
			bp.append_array(PackedFloat32Array([0, -500, 0, 0, float(Bot.State.DEAD), 0, -1, 0]))
	var zp := zone.net_pack() if zone != null else PackedFloat32Array()
	var misc := PackedFloat32Array([plane.t if plane != null and is_instance_valid(plane) else 1.0, float(alive), float(total_players), match_time])
	return [bp, zp, misc]


func net_apply_snapshot(bp: PackedFloat32Array, zp: PackedFloat32Array, misc: PackedFloat32Array, first := 0) -> void:
	if not _net_setup_ok:
		return
	var n := mini(bots.size() - first, bp.size() / 8)
	for j in n:
		var i := first + j
		var b = bots[i]
		if b == null or not is_instance_valid(b):
			continue
		var o := j * 8
		var flags := int(bp[o + 5])
		if (flags & Bot.NF_ALIVE) == 0:
			continue
		var wi := int(bp[o + 6])
		var gear := int(bp[o + 7])
		(b as Bot).apply_net(Vector3(bp[o], bp[o + 1], bp[o + 2]), bp[o + 3], int(bp[o + 4]), flags,
			Weapons.ORDER[wi] if wi >= 0 and wi < Weapons.ORDER.size() else "", gear / 10, gear % 10)
	if zone != null and zp.size() > 0:
		zone.net_apply(zp)
	if misc.size() >= 4:
		if plane != null and is_instance_valid(plane):
			plane.t = maxf(plane.t, misc[0])
		alive = int(misc[1])
		total_players = int(misc[2])
		if last_hud_alive != alive:
			last_hud_alive = alive
			hud.set_alive(alive, total_players)


func net_player_state() -> Variant:
	if player == null or phase == "menu":
		return null
	var st := Bot.State.PLANE
	match player.mode:
		Player.Mode.FREEFALL:
			st = Bot.State.FALL
		Player.Mode.CHUTE:
			st = Bot.State.CHUTE
		Player.Mode.GROUND, Player.Mode.VEHICLE:
			st = Bot.State.GROUND
	if not player.alive:
		st = Bot.State.DEAD
	var flags := 0
	if player.alive:
		flags |= Bot.NF_ALIVE
	if player.crouching():
		flags |= Bot.NF_CROUCH
	if player.aiming:
		flags |= Bot.NF_AIM
	if player.reloading:
		flags |= Bot.NF_RELOAD
	if player.has_gun():
		flags |= Bot.NF_ARMED
	if player.healing:
		flags |= int(Bot.HEAL_FLAGS.get(player.heal_item, 0))
	if player.swimming:
		flags |= Bot.NF_SWIM
	return [player.global_position, player.yaw, player.pitch, st, flags, player.current_id() if player.has_gun() else "", player.vest_level, player.helmet_level,
		player.hp, player_kills, damage_dealt,
		player.vehicle.net_id if player.mode == Player.Mode.VEHICLE and player.vehicle != null else -1, player.seat]


func net_apply_player_state(sender: int, st: Array) -> void:
	var h = humans.get(sender)
	if h == null or not is_instance_valid(h) or st.size() < 8:
		return
	var yaw: float = st[1]
	# The player's yaw faces down -Z of its basis like a bot's.
	(h as Bot).apply_net(st[0], yaw, int(st[3]), int(st[4]), str(st[5]), int(st[6]), int(st[7]), float(st[2]))
	if net.hosting:
		anticheat.host_peer_state(sender, st[0], int(st[3]) == Bot.State.GROUND, st.size() >= 13 and int(st[11]) >= 0)
	if st.size() >= 13:
		_seat_remote(h as Bot, int(st[11]), int(st[12]))
	if st.size() >= 11:
		(h as Bot).hp = float(st[8])
		(h as Bot).net_kills = int(st[9])
		(h as Bot).net_damage = float(st[10])


## Ballistics: a real shot went off here. Mirror it to everyone else.
func net_shot_fired(shooter: Node, from: Vector3, dir: Vector3, weapon: String, vis: Vector3, shot_id: int) -> void:
	if not net_on():
		return
	if shooter is Bot and (shooter as Bot).puppet:
		return
	var key := node_key(shooter)
	if key == "":
		return
	net.queue_shot(key, from, dir, weapon, vis, shot_id)


var _last_remote_shot := ""


func net_remote_shots(list: Array) -> void:
	if not _net_setup_ok:
		return
	for e in list:
		var key: String = e[0]
		var src := node_for_key(key)
		var from: Vector3 = e[1]
		var weapon: String = e[3]
		ballistics.fire(src, from, e[2], weapon, e[4], 0, 1.0, true)
		var tag := "%s:%d" % [key, int(e[5])]
		if tag != _last_remote_shot:
			_last_remote_shot = tag
			play_sfx_at("shot_" + str(Weapons.def(weapon)["sound"]), from, 0.9)
			if src is Bot:
				(src as Bot).muzzle_flash()
			if net.hosting or src == null:
				on_gunshot(from, src)
			elif player != null:
				var d := from.distance_to(player.global_position)
				if d < PING_RANGE and d > 8.0 and randf() < 0.35:
					hud.add_ping(from)


func net_grenade_thrown(from: Vector3, vel: Vector3) -> void:
	if net_on():
		net.send_grenade(net.my_key(), from, vel)


## A bot (simulated here, on the host) threw one: show it everywhere else.
func net_bot_grenade(b: Bot, from: Vector3, vel: Vector3) -> void:
	if net_on() and net.hosting:
		var i := bots.find(b)
		if i >= 0:
			net.send_grenade("b%d" % i, from, vel)


func net_remote_grenade(key: String, from: Vector3, vel: Vector3) -> void:
	var g := Grenade.new()
	g.game = self
	g.thrower = node_for_key(key)
	var who = g.thrower
	if who is Bot and is_instance_valid(who) and (who as Bot).body != null:
		(who as Bot).body.play_throw()
		if player != null and player.global_position.distance_to(from) < 30.0:
			play_sfx_at("throw_whoosh", from, -4.0)
	g.visual = true
	add_child(g)
	g.global_position = from
	g.linear_velocity = vel


## A puppet took a hit here: forward it to the machine that owns the body.
func net_route_hit(target: Bot, amount: float, pos: Vector3, headshot: bool, source: Node) -> void:
	if not net_on():
		return
	if target.is_human and target.has_meta("ghost"):
		# Their machine is offline: nobody can apply the hit.
		return
	if target.is_human:
		net.send_player_hit(target.peer_id, amount, pos, headshot, node_key(source))
	elif net_is_client() and source == player:
		net.send_bot_hit(target.net_index, amount, pos, headshot)


## Host: a client shot one of our bots.
func net_bot_hit(sender: int, idx: int, dmg: float, pos: Vector3, headshot: bool) -> void:
	if idx < 0 or idx >= bots.size() or not is_instance_valid(bots[idx]):
		return
	var shooter = humans.get(sender)
	if anticheat.is_condemned(sender):
		return
	if shooter == null or not is_instance_valid(shooter) or not (shooter as Bot).alive:
		return
	anticheat.host_peer_hit(sender, (shooter as Node3D).global_position if shooter != null and is_instance_valid(shooter) else Vector3.INF, (bots[idx] as Node3D).global_position, dmg, get_world_3d())
	if anticheat.is_condemned(sender):
		return
	dmg = minf(dmg, AntiCheat._max_hit())
	(bots[idx] as Bot).take_damage(dmg, pos, headshot, shooter if shooter != null and is_instance_valid(shooter) else _net_dummy)


## Host: a client says it hit another human. Returns how much of that
## stands (0 = none of it): the shooter has to be alive and in the match, the
## victim alive, the damage what a gun can do, the range and the line of fire
## possible.
func net_check_hit(sender: int, victim: int, dmg: float, pos: Vector3) -> float:
	var shooter = humans.get(sender)
	if shooter == null or not is_instance_valid(shooter) or not (shooter as Bot).alive or anticheat.is_condemned(sender):
		return 0.0
	var target: Node3D = player if victim == 1 else humans.get(victim)
	if target == null or not is_instance_valid(target) or sender == victim:
		return 0.0
	if target.get("alive") != true:
		return 0.0
	var tp := target.global_position
	# The hit has to be on the victim, give or take lag and a moving target.
	if pos.distance_to(tp + Vector3.UP * 0.9) > 9.0:
		return 0.0
	var sp := (shooter as Node3D).global_position
	if sp.distance_to(tp) > 1750.0:
		anticheat.strike(sender, 3, "hit from %.0f m away" % sp.distance_to(tp))
		return 0.0
	anticheat.host_peer_hit(sender, sp, tp, dmg, get_world_3d())
	if anticheat.is_condemned(sender):
		return 0.0
	return minf(dmg, AntiCheat._max_hit())


## Host: may this client pick that loot up? It has to exist and be in reach.
func net_loot_reachable(sender: int, id: int) -> bool:
	var l = loot_by_id.get(id)
	if l == null or not is_instance_valid(l):
		return false
	var where := net_peer_position(sender)
	if where == Vector3.INF:
		return true
	# Reach, plus how far a sprinting player or a jeep gets between updates.
	if where.distance_to((l as Node3D).global_position) > 14.0:
		anticheat.strike(sender, 1, "looting from %.0f m away" % where.distance_to((l as Node3D).global_position))
		return false
	return true


## Host: of the jeep states a client sent, those of jeeps it is in charge of.
func net_own_vehicle_states(sender: int, list: Array) -> Array:
	var out: Array = []
	for st in list:
		if not (st is Array) or (st as Array).is_empty() or typeof(st[0]) != TYPE_INT:
			continue
		var v := _vehicle(int(st[0]))
		if v != null and v.owner_peer == sender:
			out.append(st)
	return out


func net_vehicle_owned_by(sender: int, id: int) -> bool:
	var v := _vehicle(id)
	return v != null and v.owner_peer == sender


## Host: a client can only take charge of a jeep it is standing at.
func net_vehicle_reachable(sender: int, id: int) -> bool:
	var v := _vehicle(id)
	if v == null:
		return false
	var where := net_peer_position(sender)
	return where == Vector3.INF or where.distance_to(v.global_position) < 16.0


## Our own player was hit on someone else's machine.
func net_player_hit(dmg: float, pos: Vector3, headshot: bool, source_key: String) -> void:
	if player == null or not player.alive:
		return
	var src := node_for_key(source_key)
	if src == null:
		_net_dummy.shown_name = _name_for_key(source_key)
		src = _net_dummy
	player.take_damage(dmg, pos, headshot, src)


## Host: a human is out (ours or a client's).
func net_human_died(peer_id: int, killer_key: String, killer_name: String, weapon: String) -> void:
	if peer_id != 1:
		var h = humans.get(peer_id)
		# You only die once: a second report must not cost the match a player.
		if h == null or not is_instance_valid(h) or not (h as Bot).alive:
			return
		(h as Bot).puppet_die()
	alive = maxi(0, alive - 1)
	var victim_name: String = net.roster.get(peer_id, "PLAYER")
	var e := {"victim": "p%d" % peer_id, "victim_name": victim_name, "killer": killer_key,
		"killer_name": killer_name, "weapon": weapon, "alive": alive}
	net.send_elim(e)
	if peer_id != 1:
		_show_elim(e)
	# A human killer gets the credit on their machine via the elim message.
	_net_check_win()


## Everyone: an elimination happened on the host.
func net_elim(e: Dictionary) -> void:
	_show_elim(e)
	var victim: String = e["victim"]
	var v := node_for_key(victim)
	if v is Bot and v != player:
		(v as Bot).puppet_die()
	alive = int(e.get("alive", alive))
	hud.set_alive(alive, total_players)
	last_hud_alive = alive


func _show_elim(e: Dictionary) -> void:
	var victim: String = e["victim"]
	if victim == net.my_key():
		return
	var killer: String = e.get("killer", "")
	var kname := "YOU" if killer == net.my_key() else str(e.get("killer_name", ""))
	if kname == "":
		kname = "THE STORM"
	var vname: String = e.get("victim_name", "?")
	var weapon: String = e.get("weapon", "")
	if killer == net.my_key() and net_is_client():
		player_kills += 1
		hud.set_kills(player_kills)
		sfx.play_ui("elim", -4.0)
		hud.show_big("ELIMINATED  %s" % vname, HUD.WHITE, 2.0)
		hud.show_hitmarker(false, true)
	var col := HUD.ACCENT if killer == net.my_key() else (Color(0.45, 0.95, 0.55) if victim.begins_with("p") else HUD.MUTED)
	var mid := ("  [%s]  " % weapon) if weapon != "" else "   >   "
	hud.killfeed("%s%s%s" % [kname, mid, vname], col)
	if victim.begins_with("p") and net.squad:
		hud.show_notice("%s WAS ELIMINATED%s" % [vname, ("  BY  " + kname) if kname != "" else ""], 3.0)
	if phase == "end" and end_cam_target != null and node_key(end_cam_target) == victim:
		var mate := _next_mate(end_cam_target) if net.squad else null
		if mate != null and mate != end_cam_target:
			end_cam_target = mate
		else:
			var k := node_for_key(killer)
			if k is Node3D and (k.get("alive") == true):
				end_cam_target = k
		_spectate_label()


func net_loot_removed(l: LootPickup) -> void:
	loot_pool.erase(l)
	if l.net_id != 0:
		loot_by_id.erase(l.net_id)
	if net_on() and l.net_id != 0:
		net.send_loot_taken(l.net_id)


func net_loot_spawned(list: Array) -> void:
	if not _net_setup_ok:
		return
	for e in list:
		if loot_by_id.has(int(e[0])):
			continue
		var l := _spawn_loot(str(e[1]), str(e[2]), e[3], int(e[4]), int(e[5]), int(e[0]), false)
		l.dropped = bool(e[6]) if e.size() > 6 else false


func net_loot_taken(id: int) -> void:
	var l = loot_by_id.get(id)
	loot_by_id.erase(id)
	if l != null and is_instance_valid(l) and not l.taken:
		(l as LootPickup).consume(false)
		if l == _last_best:
			_last_best = null
			hud.set_prompt("")


func net_airdrop(p: Vector2, ground: float) -> void:
	var drop := Airdrop.new()
	drop.setup(self, p, ground)
	add_child(drop)
	airdrops.append(drop)
	hud.show_big("SUPPLY DROP INCOMING", Color(1.0, 0.45, 0.3), 2.6)
	hud.show_notice("HIGH-TIER LOOT  —  MARKED ON THE MAP", 3.0)
	sfx.play_ui("zone_warn", -10.0)


## Host: is the match decided?
func _net_check_win() -> void:
	if not net.hosting or not net.match_running:
		return
	var humans_alive: Array = []
	if player != null and player.alive:
		humans_alive.append(net.my_key())
	for id in humans:
		var h = humans[id]
		if h != null and is_instance_valid(h) and (h as Bot).alive:
			humans_alive.append("p%d" % id)
	var bots_alive: Array = []
	for i in bots.size():
		if is_instance_valid(bots[i]) and (bots[i] as Bot).alive:
			bots_alive.append("b%d" % i)
	if net.squad:
		if bots_alive.is_empty() and not humans_alive.is_empty():
			_net_finish("squad", "YOUR SQUAD", true)
	elif humans_alive.size() + bots_alive.size() <= 1:
		var w: String = (humans_alive + bots_alive)[0] if humans_alive.size() + bots_alive.size() == 1 else ""
		_net_finish(w, _name_for_key(w) if w != "" else "NOBODY", false)


func _net_finish(key: String, wname: String, squad_win: bool) -> void:
	net.send_match_over(key, wname if key != net.my_key() else net.my_name, squad_win)
	net_match_over(key, wname, squad_win)


func net_match_over(winner_key: String, winner_name: String, squad_win: bool) -> void:
	var i_won := (squad_win and player != null and player.alive) or winner_key == net.my_key()
	if i_won and phase != "end":
		_win()
	elif phase == "end" and not winner:
		hud.show_notice(("YOUR SQUAD WON THE MATCH" if squad_win else "%s WON THE MATCH" % winner_name), 6.0)
	elif not i_won:
		hud.show_big(("YOUR SQUAD WON" if squad_win else "%s WINS" % winner_name), HUD.ACCENT, 4.0)


## Host: a client dropped out mid-match.
# ------------------------------------------------------------ the warden --
## The anti-cheat condemned someone. who = 0 is us; otherwise a peer id
## (the host caught a client, or the network told us about one).
func on_cheater_condemned(who: int, reason: String) -> void:
	if who == 0 or (net.active and who == net.my_id()):
		_hunt_me(reason)
		if net_on():
			net.send_self_condemned(reason)
		return
	if net_on() and net.hosting:
		condemned_names[str(net.roster.get(who, ""))] = reason
		net.send_hunt(who, reason)
	_hunt_other(who, reason)


## Someone else is hunted: everyone watches the Warden stalk them.
func _hunt_other(who: int, reason: String) -> void:
	var h = humans.get(who)
	var nm := str(net.roster.get(who, "A PLAYER"))
	hud.chat_add("", Color(1.0, 0.25, 0.2), "%s WAS CAUGHT CHEATING (%s). THE WARDEN IS COMING FOR THEM." % [nm, reason.to_upper()], true)
	print("[anticheat] %s CAUGHT CHEATING: %s" % [nm, reason])
	if h == null or not is_instance_valid(h) or not (h as Bot).alive:
		return
	var w := Warden.new()
	w.game = self
	w.target = h
	w.local_victim = false
	add_child(w)
	w.global_position = (h as Node3D).global_position - (h as Node3D).global_basis.z * -30.0
	wardens.append(w)


## We are the cheater: the light goes, and something comes.
func _hunt_me(reason: String) -> void:
	anticheat.mark_condemned(0, reason)
	if player == null or not player.alive or phase != "playing":
		return
	for w in wardens:
		if is_instance_valid(w) and (w as Warden).local_victim:
			return
	var w := Warden.new()
	w.game = self
	w.target = player
	w.local_victim = true
	w.reason = reason
	add_child(w)
	w.global_position = w._behind(player, 38.0)
	wardens.append(w)
	w.caught.connect(func(): hud.show_big("CHEATING DETECTED  ·  %s" % reason.to_upper(), Color(1.0, 0.15, 0.1), 6.0))
	hud.show_big("SOMETHING HAS NOTICED YOU", Color(0.85, 0.08, 0.05), 3.5)
	sfx.play_2d("warden_whisper", 0.0, 0.0)
	_darken_world(true)


## The world drains of colour and light while the Warden hunts you.
func _darken_world(on: bool) -> void:
	if world == null or world.environment == null:
		return
	var env: Environment = world.environment
	if on and _dark_saved.is_empty():
		_dark_saved = [env.adjustment_brightness, env.adjustment_saturation, env.fog_density, env.fog_light_color]
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(env, "adjustment_brightness", 0.55, 4.0)
		tw.tween_property(env, "adjustment_saturation", 0.25, 4.0)
		tw.tween_property(env, "fog_density", 0.006, 4.0)
		tw.tween_property(env, "fog_light_color", Color(0.12, 0.05, 0.06), 4.0)
	elif not on and not _dark_saved.is_empty():
		env.adjustment_brightness = _dark_saved[0]
		env.adjustment_saturation = _dark_saved[1]
		env.fog_density = _dark_saved[2]
		env.fog_light_color = _dark_saved[3]
		_dark_saved = []


func _clear_wardens() -> void:
	for w in wardens:
		if is_instance_valid(w):
			w.queue_free()
	wardens.clear()
	_darken_world(false)
	if hud != null:
		hud.set_dread(0.0)
		hud.set_scare(0.0)


# ------------------------------------------------------- reconnecting ----
var _last_setup: Dictionary = {}
## Host: what each client last said it carries (for a rejoin after a crash).
var human_inv: Dictionary = {}


## Client: worth trying to get back in (alive and in the match).
func net_can_reconnect() -> bool:
	return phase in ["plane", "playing"] and player != null and player.alive


## Host: a client dropped mid-match. Keep their soldier standing where it was
## (untouchable, out of any jeep) so they can come back to it.
func net_ghost_human(id: int) -> bool:
	var h = humans.get(id)
	if h == null or not is_instance_valid(h) or not (h as Bot).alive:
		return false
	var b := h as Bot
	b.set_meta("ghost", true)
	if b.seated_in != null:
		_seat_remote(b, -1, -1)
	for v in vehicles:
		if is_instance_valid(v) and (v as Vehicle).owner_peer == id:
			(v as Vehicle).owner_peer = 1
			(v as Vehicle).set_puppet(false)
			net.send_vehicle_owner((v as Vehicle).net_id)
	return true


## Host: the ghost's player is back on a new peer id.
func net_resume_human(old: int, new: int) -> void:
	net_remap_human(old, new)
	var h = humans.get(new)
	if h != null and is_instance_valid(h):
		(h as Bot).remove_meta("ghost")
	if human_inv.has(old):
		human_inv[new] = human_inv[old]
		human_inv.erase(old)


## Everyone: a player came back with a new peer id.
func net_remap_human(old: int, new: int) -> void:
	if old == new:
		return
	var h = humans.get(old)
	if h == null or not is_instance_valid(h):
		return
	humans.erase(old)
	if new == net.my_id():
		# That is us: our own soldier is the local player, not a puppet.
		h.queue_free()
		return
	humans[new] = h
	(h as Bot).peer_id = new
	for v in vehicles:
		if is_instance_valid(v) and (v as Vehicle).owner_peer == old:
			(v as Vehicle).owner_peer = new


## Client -> host every few seconds: the kit on our back.
func net_inventory() -> Dictionary:
	if player == null or not player.alive or phase != "playing":
		return {}
	return player.net_inventory()


func net_store_inventory(id: int, d: Dictionary) -> void:
	human_inv[id] = d


## Current loot with full-size ids (drops from clients carry big ids that a
## float would round).
func _pack_loot_v2() -> Array:
	var names_t: Array = []
	var name_i: Dictionary = {}
	var fl := PackedFloat32Array()
	var ids := PackedInt64Array()
	for l in loot_pool:
		if not is_instance_valid(l) or l.taken:
			continue
		var nk := "%s|%s" % [l.kind, l.item_id]
		if not name_i.has(nk):
			name_i[nk] = names_t.size()
			names_t.append(nk)
		ids.append(int(l.net_id))
		fl.append_array([float(name_i[nk]), l.position.x, l.position.y, l.position.z, float(l.mag_override), float(l.reserve_override), 1.0 if l.dropped else 0.0])
	var raw := fl.to_byte_array()
	return [names_t, raw.size(), raw.compress(FileAccess.COMPRESSION_ZSTD), ids]


func _unpack_loot_v2(lp: Array) -> Array:
	var names_t: Array = lp[0]
	var fl: PackedFloat32Array = (lp[2] as PackedByteArray).decompress(int(lp[1]), FileAccess.COMPRESSION_ZSTD).to_float32_array()
	var ids: PackedInt64Array = lp[3]
	var out: Array = []
	for i in ids.size():
		var o := i * 7
		var nk: String = names_t[int(fl[o])]
		out.append([ids[i], nk.get_slice("|", 0), nk.get_slice("|", 1), Vector3(fl[o + 1], fl[o + 2], fl[o + 3]), int(fl[o + 4]), int(fl[o + 5]), fl[o + 6] > 0.5])
	return out


## Host: everything a reconnecting client may have missed.
func net_resync_data() -> Dictionary:
	var wrecked: Array = []
	for v in vehicles:
		if is_instance_valid(v) and (v as Vehicle).wrecked:
			wrecked.append((v as Vehicle).net_id)
	var hs: Array = [[1, net.my_name, player.alive if player != null else false]]
	for id in humans:
		var h = humans[id]
		if is_instance_valid(h):
			hs.append([int(id), (h as Bot).bot_name, (h as Bot).alive])
	return {"loot": _pack_loot_v2(), "wrecked": wrecked, "humans": hs, "alive": alive,
		"total": total_players, "match_time": match_time}


## Client: catch up after a reconnect.
func net_apply_resync(d: Dictionary) -> void:
	var have: Dictionary = {}
	for e in _unpack_loot_v2(d["loot"]):
		have[int(e[0])] = true
		if not loot_by_id.has(int(e[0])):
			var l := _spawn_loot(str(e[1]), str(e[2]), e[3], int(e[4]), int(e[5]), int(e[0]), false)
			l.dropped = bool(e[6])
	for id in loot_by_id.keys():
		if not have.has(int(id)):
			net_loot_taken(int(id))
	for v in vehicles:
		if is_instance_valid(v) and int((v as Vehicle).net_id) in d.get("wrecked", []):
			(v as Vehicle).wreck_quiet()
	var seen: Dictionary = {}
	for e in d.get("humans", []):
		var id := int(e[0])
		if id == net.my_id():
			continue
		seen[id] = true
		var h = humans.get(id)
		if h == null or not is_instance_valid(h):
			h = _make_human(id, str(e[1]))
		if not bool(e[2]) and (h as Bot).alive:
			(h as Bot).puppet_die()
	for id in humans.keys():
		if not seen.has(int(id)):
			var h = humans[id]
			if is_instance_valid(h):
				h.queue_free()
			humans.erase(id)
	alive = int(d.get("alive", alive))
	total_players = int(d.get("total", total_players))
	match_time = float(d.get("match_time", match_time))
	hud.set_alive(alive, total_players)
	last_hud_alive = alive
	hud.show_notice("RECONNECTED", 2.0)
	net.flush_pending()


## Host: rebuild the match for a player whose game restarted, with their
## soldier where it stood and the kit it carried.
func net_resume_setup(id: int) -> Dictionary:
	var setup := _last_setup.duplicate()
	setup["loot"] = null
	setup["loot2"] = _pack_loot_v2()
	var list: Array = [[1, net.my_name]]
	for hid in humans:
		list.append([int(hid), (humans[hid] as Bot).bot_name])
	setup["humans"] = list
	var h = humans.get(id)
	var r := net_resync_data()
	if h != null and is_instance_valid(h):
		var b := h as Bot
		r["pos"] = b.global_position
		r["yaw"] = b.rotation.y
		r["hp"] = b.hp
		r["kills"] = b.net_kills
		r["damage"] = b.net_damage
	r["inv"] = human_inv.get(id, {})
	setup["resume"] = r
	return setup


## Client: we rejoined a running match after restarting the game.
func _apply_resume(r: Dictionary) -> void:
	anticheat.grace(5.0)
	_player_jump(true)
	if plane != null and is_instance_valid(plane):
		plane.queue_free()
		plane = null
	player.global_position = Vector3(r.get("pos", player.global_position)) + Vector3(0, 0.3, 0)
	player.yaw = float(r.get("yaw", 0.0)) + PI
	player.mode = Player.Mode.GROUND
	player.landed = true
	player.velocity = Vector3.ZERO
	var inv: Dictionary = r.get("inv", {})
	if not inv.is_empty():
		player.apply_net_inventory(inv)
	player.hp = clampf(float(r.get("hp", player.hp)), 1.0, 100.0)
	player._emit_health()
	player_kills = int(r.get("kills", 0))
	damage_dealt = float(r.get("damage", 0.0))
	hud.set_kills(player_kills)
	phase = "playing"
	on_player_landed()
	net_apply_resync(r)
	hud.show_big("BACK IN THE MATCH", HUD.WHITE, 2.4)


func net_player_left(id: int) -> void:
	var h = humans.get(id)
	if h != null and is_instance_valid(h) and (h as Bot).alive:
		net_human_died(id, "", "", "")
	if h != null and is_instance_valid(h):
		h.queue_free()
	humans.erase(id)


## Spawn a match's loot and check every item: resting on a floor (not
## floating, not sunk), not inside a wall or prop, and not piled up with
## others. Prints totals and the worst offenders.
## Loose pieces: every solid part of every building and landmark has to be
## joined, directly or through other parts, to something that stands on the
## ground. Reports whatever hangs in the air on its own, and lone bits.
func _run_loose_audit() -> void:
	for i in 3:
		await get_tree().physics_frame
	var boxes: Array[AABB] = []
	var owners: Array[String] = []
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is CollisionShape3D):
			continue
		var cs := n as CollisionShape3D
		var body := cs.get_parent()
		if not (body is StaticBody3D) or cs.shape == null:
			continue
		if str(body.name) in ["TerrainCollision", "TreeCollision"] or cs.shape is HeightMapShape3D:
			continue
		var xf := cs.global_transform
		var pts := PackedVector3Array()
		if cs.shape is BoxShape3D:
			var h := (cs.shape as BoxShape3D).size * 0.5
			for sx: float in [-1.0, 1.0]:
				for sy: float in [-1.0, 1.0]:
					for sz: float in [-1.0, 1.0]:
						pts.append(xf * Vector3(h.x * sx, h.y * sy, h.z * sz))
		elif cs.shape is ConvexPolygonShape3D:
			for p in (cs.shape as ConvexPolygonShape3D).points:
				pts.append(xf * p)
		elif cs.shape is ConcavePolygonShape3D:
			for p in (cs.shape as ConcavePolygonShape3D).get_faces():
				pts.append(xf * p)
		elif cs.shape is CylinderShape3D:
			var cyl := cs.shape as CylinderShape3D
			for sx: float in [-1.0, 1.0]:
				for sy: float in [-1.0, 1.0]:
					for sz: float in [-1.0, 1.0]:
						pts.append(xf * Vector3(cyl.radius * sx, cyl.height * 0.5 * sy, cyl.radius * sz))
		elif cs.shape is SphereShape3D:
			var r := (cs.shape as SphereShape3D).radius
			pts.append(xf.origin - Vector3.ONE * r)
			pts.append(xf.origin + Vector3.ONE * r)
		if pts.is_empty():
			continue
		var bb := AABB(pts[0], Vector3.ZERO)
		for p in pts:
			bb = bb.expand(p)
		boxes.append(bb)
		owners.append("%s/%s" % [body.get_parent().name if body.get_parent() != null else "?", body.name])
	print("[loose] %d solid parts" % boxes.size())
	# Join parts that touch.
	var parent := PackedInt32Array()
	parent.resize(boxes.size())
	for i in boxes.size():
		parent[i] = i
	var find := func(i: int) -> int:
		while parent[i] != i:
			parent[i] = parent[parent[i]]
			i = parent[i]
		return i
	const CELL := 6.0
	var grid: Dictionary = {}
	for i in boxes.size():
		var g := boxes[i].grow(0.15)
		for cx in range(int(floor(g.position.x / CELL)), int(floor(g.end.x / CELL)) + 1):
			for cz in range(int(floor(g.position.z / CELL)), int(floor(g.end.z / CELL)) + 1):
				var key := Vector2i(cx, cz)
				if not grid.has(key):
					grid[key] = []
				for j: int in grid[key]:
					if g.intersects(boxes[j]):
						var a: int = find.call(i)
						var b: int = find.call(j)
						if a != b:
							parent[a] = b
				(grid[key] as Array).append(i)
	# Which groups reach the ground?
	var groups: Dictionary = {}
	for i in boxes.size():
		var root: int = find.call(i)
		if not groups.has(root):
			groups[root] = {"n": 0, "bb": boxes[i], "gap": INF, "owner": owners[i]}
		var gdata: Dictionary = groups[root]
		gdata.n += 1
		gdata.bb = (gdata.bb as AABB).merge(boxes[i])
		var bb := boxes[i]
		var ground := -INF
		for fx: float in [0.0, 0.5, 1.0]:
			for fz: float in [0.0, 0.5, 1.0]:
				var gx := bb.position.x + bb.size.x * fx
				var gz := bb.position.z + bb.size.z * fz
				ground = maxf(ground, maxf(terrain.height_at(gx, gz), terrain.water_surface_at(gx, gz) - 3.0))
		gdata.gap = minf(float(gdata.gap), bb.position.y - ground)
	var floating: Array = []
	var lone := 0
	for root in groups:
		var gdata: Dictionary = groups[root]
		if float(gdata.gap) > 0.45:
			floating.append(gdata)
		elif int(gdata.n) == 1:
			lone += 1
			# A slab standing by itself: a wall nobody built a house round?
			var lb: AABB = gdata.bb
			if lb.size.y > 2.0 and maxf(lb.size.x, lb.size.z) > 1.6 and (OS.get_cmdline_user_args().has("--verbose-loose")):
				var lc := lb.get_center()
				print("[loose] lone slab of %s at (%.0f, %.1f, %.0f) size (%.1f, %.1f, %.1f) near %s" % [gdata.owner, lc.x, lc.y, lc.z, lb.size.x, lb.size.y, lb.size.z, _place_name(lc)])
	floating.sort_custom(func(a, b): return float(a.gap) > float(b.gap))
	print("[loose] %d groups, %d of them a single part on the ground, %d hang in the air" % [groups.size(), lone, floating.size()])
	for gdata in floating:
		var bb: AABB = gdata.bb
		var c := bb.get_center()
		print("[loose] FLOATING %.1f m up: %d part(s) of %s at (%.0f, %.1f, %.0f) size (%.1f, %.1f, %.1f) near %s" % [gdata.gap, gdata.n, gdata.owner, c.x, c.y, c.z, bb.size.x, bb.size.y, bb.size.z, _place_name(c)])
	# Houses whose corners hang over a slope (daylight under the wall), or
	# that are sunk into the ground.
	var hanging := 0
	for h in world.villages.houses:
		var hc: Vector2 = h.center
		var worst := 0.0
		var deepest := 0.0
		for sx: float in [-0.5, 0.0, 0.5]:
			for sz: float in [-0.5, 0.0, 0.5]:
				var q := hc + Vector2(float(h.w) * sx, float(h.d) * sz).rotated(-float(h.yaw))
				var gap := float(h.pad) - terrain.height_at(q.x, q.y)
				worst = maxf(worst, gap)
				deepest = minf(deepest, gap)
		# (A stone footing goes 2.6 m down: only a deeper drop shows daylight.)
		if worst > 2.5 or deepest < -0.3:
			hanging += 1
			print("[loose] HOUSE at (%.0f, %.0f) near %s: floor %.2f m above the ground at one corner, %.2f m below it at another" % [hc.x, hc.y, _place_name(Vector3(hc.x, 0, hc.y)), worst, -deepest])
	print("[loose] %d of %d houses do not sit on their ground" % [hanging, world.villages.houses.size()])
	print("[loose] %s" % ("ALL GOOD" if floating.is_empty() and hanging == 0 else "%d FLOATING, %d HOUSES OFF THE GROUND" % [floating.size(), hanging]))
	get_tree().quit()


## The named town or landmark nearest to a spot (for test reports).
func _place_name(p: Vector3) -> String:
	var best := "?"
	var best_d := INF
	var here := Vector2(p.x, p.z)
	for v in world.villages.village_pads:
		var d := here.distance_to(v.center)
		if str(v.name) != "" and d < best_d:
			best_d = d
			best = str(v.name)
	for l in world.villages.landmarks.labels:
		var d := here.distance_to(l[1])
		if d < best_d:
			best_d = d
			best = str(l[0])
	return "%s (%d m)" % [best, int(best_d)]


## Rendered frame times in a busy spot (a town street, then a forest), at
## the quality given with --quality=N. Run with a real renderer.
func _run_gpu_bench() -> void:
	_start_match()
	_player_jump(true)
	var spots: Array = []
	for v in world.villages.village_pads:
		if v.type == "city":
			spots.append(Vector3(v.center.x, 0, v.center.y))
			break
	spots.append(_random_ground_point(150.0))
	for sp: Vector3 in spots:
		player.global_position = ground_at(Vector3(sp.x, terrain.height_at(sp.x, sp.z) + 2.0, sp.z)) + Vector3.UP * 0.2
		player.velocity = Vector3.ZERO
		player.mode = Player.Mode.GROUND
		player.spawn_protect = 9999.0
		var warm := int(OS.get_environment("GB_WARM")) if OS.get_environment("GB_WARM") != "" else 40
		var count := int(OS.get_environment("GB_FRAMES")) if OS.get_environment("GB_FRAMES") != "" else 120
		for i in warm:
			await get_tree().process_frame
		var times: Array[float] = []
		var last := Time.get_ticks_usec()
		for i in count:
			player.yaw += 0.02
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			times.append(float(now - last) / 1000.0)
			last = now
		times.sort()
		var sum := 0.0
		for t in times:
			sum += t
		print("[gpubench] quality %s at %s: avg %.1f ms, median %.1f ms, 95%% %.1f ms, worst %.1f ms, draws=%d prims=%dk" % [Graphics.NAMES[graphics_quality], str(sp.round()), sum / times.size(), times[times.size() / 2], times[int(times.size() * 0.95)], times[times.size() - 1], int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)) / 1000])
	get_tree().quit()


func _run_loot_audit() -> void:
	_start_match()
	for i in 3:
		await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var ball := SphereShape3D.new()
	ball.radius = 0.12
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = ball
	sq.collision_mask = 1
	var floating := 0
	var sunk := 0
	var inside := 0
	var piles := 0
	var bad: Array = []
	var pts: Array = []
	for l in loot_pool:
		if is_instance_valid(l):
			pts.append(l.global_position)
	var grid: Dictionary = {}
	for i in pts.size():
		var p: Vector3 = pts[i]
		var k := Vector2i(int(floor(p.x / 2.0)), int(floor(p.z / 2.0)))
		if not grid.has(k):
			grid[k] = []
		grid[k].append(i)
	var nn_hist := [0, 0, 0, 0]
	var st_shown: Dictionary = {}
	for i in pts.size():
		var p: Vector3 = pts[i]
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.4, p + Vector3.DOWN * 1.5, 1)
		var hit := space.intersect_ray(q)
		var why := ""
		if hit.is_empty():
			floating += 1
			why = "no floor"
		else:
			var gap: float = p.y - float(hit["position"].y)
			if gap > 0.25:
				floating += 1
				why = "floating %.2f" % gap
			elif gap < -0.2:
				sunk += 1
				why = "sunk %.2f" % gap
		sq.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.22)
		if why == "" and not space.intersect_shape(sq, 1).is_empty():
			inside += 1
			why = "inside geometry"
		var near := 0
		var k := Vector2i(int(floor(p.x / 2.0)), int(floor(p.z / 2.0)))
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				for j in grid.get(Vector2i(k.x + dx, k.y + dz), []):
					if j != i and absf((pts[j] as Vector3).y - p.y) < 1.0 and Vector2(p.x, p.z).distance_to(Vector2((pts[j] as Vector3).x, (pts[j] as Vector3).z)) < 1.5:
						near += 1
		nn_hist[mini(near, 3)] += 1
		if near >= 3:
			piles += 1
			if why == "":
				why = "pile of %d" % (near + 1)
		if why != "" and not why.begins_with("pile"):
			var cat := why.get_slice(" ", 0)
			var shown: int = int(st_shown.get(cat, 0))
			if shown < 8:
				st_shown[cat] = shown + 1
				var what := ""
				if not hit.is_empty() and hit.get("collider") is Node:
					what = str((hit["collider"] as Node).name)
				bad.append("%s at %s (%s) floor=%s" % [why, str(p.snapped(Vector3.ONE * 0.1)), (loot_pool[i] as LootPickup).kind if i < loot_pool.size() else "?", what])
	print("[loot] items=%d points=%d floating=%d sunk=%d inside=%d piles(>=4 within 1.5m)=%d  neighbours<1.5m: 0=%d 1=%d 2=%d 3+=%d" % [pts.size(), world.loot_points.size(), floating, sunk, inside, piles, nn_hist[0], nn_hist[1], nn_hist[2], nn_hist[3]])
	for b in bad:
		print("[loot]   ", b)
	get_tree().quit()


## Multi-process soak test: one host and several clients (each behind its
## own network emulator) play a scripted match: walking, shooting at bots and
## each other, healing, grenades, driving, looting, chat and markers. Every
## process logs one line a second (wall clock stamped) so a script can check
## that everyone agrees on the match. Env: NET_ROLE host|client, NET_JOIN,
## NET_CLIENTS (host waits for this many), NET_SECS, NET_NAME, NET_DRIVE,
## NET_DROP_AT + NET_DROP_MODE quit|crash (a client vanishes mid-match).
func _env_f(k: String, d: float) -> float:
	var v := OS.get_environment(k)
	return float(v) if v != "" else d


func _run_net_stress(as_host: bool) -> void:
	var tag := OS.get_environment("NET_NAME") if OS.get_environment("NET_NAME") != "" else ("HOST" if as_host else "CLIENT")
	net.my_name = tag
	var secs := _env_f("NET_SECS", 180.0)
	var drop_at := _env_f("NET_DROP_AT", -1.0)
	var st := {"left": "", "errors": 0}
	net.left_session.connect(func(t): st["left"] = t; print("[stress] %s left session: %s" % [tag, t]))
	net.status.connect(func(t): print("[stress] %s status: %s" % [tag, t]))
	net.reconnect_state.connect(func(t): if t == "" or t.ends_with("RECONNECTING"): print("[stress] %s reconnect: '%s' active=%s" % [tag, t, net.active]))
	seed(hash(tag))
	if as_host:
		_net_host()
		var want := int(_env_f("NET_CLIENTS", 1.0))
		var w := 0.0
		while net.roster.size() < want + 1 and w < 120.0:
			await get_tree().create_timer(0.5).timeout
			w += 0.5
		w = 0.0
		while not net.all_ready() and w < 120.0:
			await get_tree().create_timer(0.5).timeout
			w += 0.5
		print("[stress] HOST roster=%s ready=%s after %.0fs" % [str(net.roster.values()), net.all_ready(), w])
		net.start_countdown(3)
	else:
		net.join(OS.get_environment("NET_JOIN"))
		var r := 0.0
		while net.roster.size() < 2 and r < 60.0:
			await get_tree().create_timer(0.5).timeout
			r += 0.5
		# The host's island may still be building here.
		while not lobby_ready and r < 120.0:
			await get_tree().create_timer(0.5).timeout
			r += 0.5
		await get_tree().create_timer(1.0).timeout
		net.set_ready(true)
		print("[stress] %s joined roster=%s after %.0fs" % [tag, str(net.roster.values()), r])
	var t0 := 0.0
	while phase == "menu" and t0 < 150.0:
		await get_tree().create_timer(0.25).timeout
		t0 += 0.25
	print("[stress] %s match phase=%s setup_ok=%s bots=%d humans=%d" % [tag, phase, _net_setup_ok or as_host, bots.size(), humans.size()])
	await get_tree().create_timer(2.0 + randf() * 3.0).timeout
	var rejoined := player.mode == Player.Mode.GROUND and phase == "playing"
	if rejoined:
		print("[stress] %s REJOINED pos=%s hp=%d loadout=%s mags=%s meds=%d bandages=%d grenades=%d vest=%d kills=%d alive=%d humans=%d loot=%d" % [tag, str(player.global_position.round()), int(player.hp), str(player.loadout), str(player.mags), player.meds, player.bandages, player.grenades, player.vest_level, player_kills, alive, humans.size(), loot_pool.size()])
	_player_jump(true)
	# Everyone meets in the same town so they see and shoot each other.
	var meet := Vector2.ZERO
	for pad in world.villages.village_pads:
		if pad.type == "town":
			meet = pad.center
			break
	anticheat.grace(4.0)
	var idle := OS.get_environment("NET_IDLE") == "1"
	var cheat_at := _env_f("NET_CHEAT_AT", -1.0)
	var cheat_st := {"caught": "", "died": ""}
	anticheat.condemned.connect(func(w, r): cheat_st["caught"] = r; print("[stress] %s anticheat condemned %d: %s" % [tag, w, r]))
	player.died.connect(func(k): cheat_st["died"] = k; print("[stress] %s died, killer=%s" % [tag, k]))
	if not rejoined:
		var spot := ground_at(Vector3(meet.x + randf_range(-40, 40), 200.0, meet.y + randf_range(-40, 40)))
		player.global_position = spot + Vector3(0, 1.0, 0)
		player.mode = Player.Mode.GROUND
		player.landed = true
		player.velocity = Vector3.ZERO
		player.give_weapon("rifle")
		# Some kit to carry over a rejoin.
		player.meds = 2
		player.bandages = 4
		player.vest_level = 2
	player.spawn_protect = 1.0e9
	var t := 0.0
	var next_log := 0.0
	var dir_t := 0.0
	var drove := false
	var drive_until := -1.0
	var tick := 0.25
	while t < secs:
		await get_tree().create_timer(tick).timeout
		t += tick
		if st["left"] != "" and not as_host:
			print("[stress] %s disconnected at t=%.0f: %s" % [tag, t, st["left"]])
			break
		if drop_at > 0.0 and t >= drop_at:
			print("[stress] %s dropping out (%s) at t=%.0f" % [tag, OS.get_environment("NET_DROP_MODE"), t])
			if OS.get_environment("NET_DROP_MODE") == "crash":
				OS.kill(OS.get_process_id())
			net.leave("")
			get_tree().quit()
			return
		var p := player
		if cheat_at > 0.0 and t >= cheat_at and p.alive:
			# Speed hack: shove the body along far faster than legs can.
			p.global_position += (Basis(Vector3.UP, p.yaw) * Vector3(0, 0, -1)) * 6.0
		if idle:
			if p.alive and p.mode == Player.Mode.GROUND:
				p.test_input = Vector2(0, -0.6)
				if int(t / tick) % 16 == 0:
					p.yaw += 0.6
		elif p.alive and p.mode == Player.Mode.GROUND:
			dir_t -= tick
			if dir_t <= 0.0:
				dir_t = randf_range(1.5, 4.0)
				p.test_input = Vector2(randf_range(-1, 1), randf_range(-1, 0.4)).limit_length(1.0)
				p.yaw = randf() * TAU
			# Keep near the meeting point.
			if Vector2(p.global_position.x, p.global_position.z).distance_to(meet) > 90.0:
				var to := Vector3(meet.x, 0, meet.y) - p.global_position
				p.yaw = atan2(-to.x, -to.z)
				p.test_input = Vector2(0, -1)
			var k := int(t / tick)
			if k % 24 == 5:
				# Burst at the nearest soldier in sight.
				var tgt: Node3D = null
				var bd := 150.0
				for b in bots + humans.values():
					if is_instance_valid(b) and b.alive and (b as Bot).state == Bot.State.GROUND:
						var d: float = (b as Node3D).global_position.distance_to(p.global_position)
						if d < bd:
							bd = d
							tgt = b
				if tgt != null:
					var to := tgt.global_position + Vector3(0, 1.3, 0) - p.camera.global_position
					p.yaw = atan2(-to.x, -to.z)
					p.pitch = atan2(to.y, Vector2(to.x, to.z).length())
					p.mags[p.current_id()] = 30
					for n in 3:
						p.fire_timer = 0.0
						p._try_fire()
						await get_tree().physics_frame
						await get_tree().physics_frame
			if k % 80 == 17:
				p.hp = minf(p.hp, 55.0)
				p.bandages += 1
				p.use_item("bandage")
			if k % 108 == 41:
				p.grenades = 1
				p.throw_grenade()
			if k % 60 == 30:
				net.send_chat("%s says hi at %d" % [tag, int(t)])
			if k % 132 == 66:
				net.send_marker(p.global_position + Vector3(randf_range(-60, 60), 0, randf_range(-60, 60)))
			if k % 40 == 20:
				var l := _nearest_loot(p.global_position, 60.0)
				if l != null and not l.taken:
					p.global_position = l.global_position + Vector3(0.6, 0.6, 0)
					await get_tree().physics_frame
					try_pickup(p)
		if OS.get_environment("NET_DRIVE") == "1" and not drove and t > 40.0 and p.alive and p.mode == Player.Mode.GROUND:
			var car := _nearest_vehicle_any(p.global_position)
			if car != null:
				p.global_position = car.global_position + car.global_basis.x * 2.4 + Vector3(0, 0.5, 0)
				p.yaw = atan2(car.global_basis.x.x, car.global_basis.x.z)
				p.pitch = -0.15
				await get_tree().physics_frame
				await get_tree().physics_frame
				try_pickup(p)
				if p.mode == Player.Mode.VEHICLE:
					drove = true
					_drive_scripted = true
					drive_until = t + 12.0
					print("[stress] %s in jeep %d seat=%d" % [tag, car.net_id, p.seat])
		if p.mode == Player.Mode.VEHICLE and p.vehicle != null:
			if p.seat == 0:
				p.vehicle.throttle = 0.8
				p.vehicle.steer_in = sin(t) * 0.4
			if t > drive_until:
				p.vehicle.throttle = 0.0
				_exit_vehicle()
				_drive_scripted = false
				print("[stress] %s left jeep mode=%d" % [tag, p.mode])
		if t >= next_log:
			next_log += 1.0
			var hs := []
			for id in humans:
				var h = humans[id]
				if is_instance_valid(h):
					hs.append("%d:%.1f,%.1f,%.1f:%d" % [int(id), h.global_position.x, h.global_position.y, h.global_position.z, int(h.alive)])
			var bots_alive := 0
			for b in bots:
				if is_instance_valid(b) and b.alive:
					bots_alive += 1
			print("[stress] %s wall=%.2f t=%.0f phase=%s alive=%d bots=%d zone=%.1f ping=%d fps=%d id=%d pos=%.1f,%.1f,%.1f mode=%d hp=%d loot=%d humans=%s" % [tag, Time.get_unix_time_from_system(), t, phase, alive, bots_alive, zone.radius if zone != null else -1.0, net.ping_of(net.my_id()), Engine.get_frames_per_second(), net.my_id(), p.global_position.x, p.global_position.y, p.global_position.z, p.mode, int(p.hp), loot_pool.size(), " ".join(hs)])
	var wn := 0
	for w in wardens:
		if is_instance_valid(w):
			wn += 1
	print("[stress] %s END t=%.0f phase=%s left=%s caught=%s died=%s wardens=%d chat_hunts=%s" % [tag, t, phase, st["left"], cheat_st["caught"], cheat_st["died"], wn, str(anticheat._condemned)])
	if as_host:
		await get_tree().create_timer(2.0).timeout
	net.leave("")
	get_tree().quit()


func _nearest_vehicle_any(pos: Vector3) -> Vehicle:
	var best: Vehicle = null
	var bd := 1e9
	for v in vehicles:
		if is_instance_valid(v) and not (v as Vehicle).wrecked and (v as Vehicle).free_seat() >= 0:
			var d: float = pos.distance_to((v as Vehicle).global_position)
			if d < bd:
				bd = d
				best = v
	return best


## Two-instance smoke test on this machine: --nethost / --netjoin.
## A hostile client against a password-protected host (run both, real time):
## wrong password, speaking as the host, impossible damage, dying three times,
## flooding. The host reports what got through.
func _run_net_attack(as_host: bool) -> void:
	var wait_for := func(cond: Callable, secs: float) -> bool:
		var t0 := Time.get_ticks_msec()
		while not cond.call() and Time.get_ticks_msec() - t0 < int(secs * 1000.0):
			await get_tree().create_timer(0.1).timeout
		return cond.call()
	var verdict := func(ok: bool, what: String) -> void:
		print("[attack] %s %s" % ["PASS" if ok else "FAIL", what])
	if as_host:
		var seen := {"chats": [], "condemned": ""}
		net.password = "sesame"
		_net_host()
		net.chat.connect(func(id, n, t, sys): if not sys: (seen["chats"] as Array).append([id, n, t]))
		anticheat.condemned.connect(func(w, r): seen["condemned"] = r)
		await wait_for.call(func(): return net.roster.size() >= 2, 90.0)
		var foe := 0
		for id in net.roster:
			if int(id) != 1:
				foe = int(id)
		print("[attack] host: attacker is ", foe, " roster ", net.roster)
		await wait_for.call(func(): return net.all_ready(), 30.0)
		var spoof: Array = seen["chats"].duplicate()
		verdict.call(spoof.size() == 1 and int(spoof[0][0]) == foe and str(spoof[0][1]) == str(net.roster.get(foe, "")) and not str(spoof[0][2]).contains("["), "chat is stamped with the real sender and stripped of markup: %s" % str(spoof))
		net.start_countdown(1)
		await wait_for.call(func(): return phase != "menu", 30.0)
		await wait_for.call(func(): return humans.has(foe), 30.0)
		var hp0 := player.hp
		var alive0 := alive
		# The attack takes about ten seconds.
		await get_tree().create_timer(16.0).timeout
		verdict.call(is_equal_approx(player.hp, hp0), "a 99999 damage hit did nothing (hp %.0f -> %.0f)" % [hp0, player.hp])
		verdict.call(str(seen["condemned"]) != "", "the anti-cheat caught it: %s" % str(seen["condemned"]))
		verdict.call(alive0 - alive == 1, "dying three times cost one player, not three (%d -> %d)" % [alive0, alive])
		await wait_for.call(func(): return not net.roster.has(foe), 20.0)
		verdict.call(not net.roster.has(foe), "the flooder was kicked")
		verdict.call((seen["chats"] as Array).size() < 40, "the flood was cut off (%d of 3000 lines got through)" % (seen["chats"] as Array).size())
	else:
		var st := {"left": ""}
		net.left_session.connect(func(t): st["left"] = t)
		net.my_name = "MALLORY"
		net.join_password = "open sesame?"
		await get_tree().create_timer(6.0).timeout
		net.join("127.0.0.1")
		await wait_for.call(func(): return str(st["left"]) != "", 20.0)
		verdict.call(str(st["left"]) == "WRONG PASSWORD", "wrong password refused: '%s'" % str(st["left"]))
		st["left"] = ""
		net.join_password = "sesame"
		net.join("127.0.0.1")
		await wait_for.call(func(): return net.roster.size() >= 2, 20.0)
		verdict.call(net.roster.size() >= 2, "right password let in: %s" % str(net.roster))
		# Speak as the host, as the system, with markup.
		net._chat.rpc_id(1, 1, "HOST", "[b]SERVER:[/b] everyone send me your loot", true)
		await get_tree().create_timer(1.0).timeout
		net.set_ready(true)
		await wait_for.call(func(): return _net_setup_ok, 120.0)
		await get_tree().create_timer(4.0).timeout
		var host_body = humans.get(1)
		var at: Vector3 = (host_body as Node3D).global_position if host_body != null else Vector3.ZERO
		net._player_hit.rpc_id(1, 1, 99999.0, at + Vector3.UP, true, "p1")
		await get_tree().create_timer(2.0).timeout
		for i in 3:
			net._died.rpc_id(1, "p1", "HOST", "rifle")
		await get_tree().create_timer(2.0).timeout
		for i in 3000:
			net._chat.rpc_id(1, 0, "", "spam %d" % i, false)
		await wait_for.call(func(): return str(st["left"]) != "", 20.0)
		verdict.call(str(st["left"]).contains("FLOODING"), "kicked for flooding: '%s'" % str(st["left"]))
	await get_tree().create_timer(1.0).timeout
	print("[attack] done")
	get_tree().quit()


func _run_net_test(as_host: bool) -> void:
	net.status.connect(func(t): print("[net] status: ", t))
	net.left_session.connect(func(t): print("[net] left: ", t))
	net.multiplayer.peer_connected.connect(func(id): print("[net] peer connected ", id))
	if as_host:
		_net_host()
		print("[net] hosting, waiting for a client")
		# Real seconds: under --fixed-fps the game clock runs far ahead of the
		# wall clock, and connecting takes wall-clock time.
		var t0 := Time.get_ticks_msec()
		while net.roster.size() < 2 and Time.get_ticks_msec() - t0 < 60000:
			await get_tree().create_timer(0.5).timeout
		print("[net] roster ", net.roster)
		net.chat.connect(func(id, n, t, sys): print("[net] host chat <%s> %s sys=%s" % [n, t, sys]))
		var w0 := Time.get_ticks_msec()
		while not net.all_ready() and Time.get_ticks_msec() - w0 < 20000:
			await get_tree().create_timer(0.5).timeout
		print("[net] all ready=", net.all_ready(), " info=", net.info)
		net.start_countdown(3)
		var c := 0.0
		while phase == "menu" and c < 10.0:
			await get_tree().create_timer(0.25).timeout
			c += 0.25
		print("[net] countdown started the match after %.1fs phase=%s" % [c, phase])
	else:
		net.join(OS.get_environment("NET_JOIN") if OS.get_environment("NET_JOIN") != "" else "127.0.0.1")
		net.chat.connect(func(id, n, t2, sys): print("[net] client chat <%s> %s sys=%s" % [n, t2, sys]))
		net.countdown.connect(func(sec): print("[net] client countdown ", sec))
		net.marker.connect(func(id, pos): print("[net] client marker from ", id, " at ", pos.round()))
		var r0 := Time.get_ticks_msec()
		while net.roster.size() < 2 and Time.get_ticks_msec() - r0 < 30000:
			await get_tree().create_timer(0.5).timeout
		await get_tree().create_timer(1.0).timeout
		net.send_chat("hello from the client")
		net.set_ready(true)
		print("[net] client ready, my ping ", net.ping_of(net.my_id()))
		var t := 0.0
		while not _net_setup_ok and t < 90.0:
			await get_tree().create_timer(0.5).timeout
			t += 0.5
		print("[net] client got setup=", _net_setup_ok, " bots=", bots.size(), " loot=", loot_pool.size(), " humans=", humans.size())
	await get_tree().create_timer(4.0).timeout
	_player_jump(true)
	var spot := _random_ground_point(150.0)
	player.global_position = spot + Vector3(0, 1.0, 0)
	player.mode = Player.Mode.GROUND
	player.landed = true
	player.velocity = Vector3.ZERO
	player.give_weapon("rifle")
	for i in 75:
		await get_tree().create_timer(1.0).timeout
		var moving := 0
		var landed := 0
		for b in bots:
			if is_instance_valid(b) and b.velocity.length() > 0.5:
				moving += 1
			if is_instance_valid(b) and b.state == Bot.State.GROUND:
				landed += 1
		var hs := []
		for id in humans:
			var h = humans[id]
			if is_instance_valid(h):
				hs.append("%s@%s st=%d" % [h.bot_name, str(h.global_position.round()), h.state])
		if i % 5 == 0:
			print("[net] %s t=%d alive=%d landed=%d moving=%d loot=%d zone=%.0f hp=%.0f kills=%d ping=%d fps=%d humans=%s" % ["host" if as_host else "client", i, alive, landed, moving, loot_pool.size(), zone.radius if zone != null else -1.0, player.hp, player_kills, net.ping_of(net.my_id()) if not as_host else 0, Engine.get_frames_per_second(), str(hs)])
		var near: Bot = null
		var bd := 1e9
		for b in bots:
			if is_instance_valid(b) and b.alive and b.state == Bot.State.GROUND:
				var d: float = b.global_position.distance_to(player.global_position)
				if d < bd:
					bd = d
					near = b
		if i == 14 and not as_host and not vehicles.is_empty():
			var jeep: Vehicle = vehicles[0]
			player.global_position = jeep.global_position + jeep.global_basis.x * 2.4 + Vector3(0, 0.5, 0)
			await get_tree().physics_frame
			try_pickup(player)
			_drive_scripted = true
			print("[net] client in jeep mode=", player.mode, " owner=", jeep.owner_peer)
		if i >= 14 and i < 24 and not as_host and player.mode == Player.Mode.VEHICLE:
			player.vehicle.throttle = 1.0
			player.vehicle.steer_in = 0.3
		if i == 24 and not as_host and player.mode == Player.Mode.VEHICLE:
			player.vehicle.throttle = 0.0
			print("[net] client jeep at ", player.vehicle.global_position.round(), " speed ", int(player.vehicle.speed * 3.6))
			_exit_vehicle()
		if as_host and i in [10, 16, 22, 26] and not vehicles.is_empty():
			var hj: Vehicle = vehicles[0]
			var seated := ""
			for id in humans:
				if humans[id].seated_in != null:
					seated = "seat %d" % humans[id].seated_slot
			print("[net] host sees jeep0 at ", hj.global_position.round(), " owner=", hj.owner_peer, " frozen=", hj.freeze, " client ", seated)
		if i == 50 and not as_host and near != null:
			print("[net] client shooting ", near.bot_name, " at ", int(bd), " m")
			net_route_hit(near, 500.0, near.global_position + Vector3(0, 1.6, 0), true, player)
		if i == 55 and as_host and near != null:
			print("[net] host kills ", near.bot_name)
			near.take_damage(500.0, near.global_position, true, player)
		if i == 58 and as_host:
			net.send_marker(player.global_position + Vector3(50, 0, 0))
		if i == 60 and as_host:
			for id in humans:
				print("[net] host hits human ", id)
				net_route_hit(humans[id], 30.0, humans[id].global_position + Vector3(0, 1, 0), false, near if near != null else player)
		if i == 62 and not as_host:
			# Take some loot and drop a gun: both must show on the host.
			var l := _nearest_loot(player.global_position, 4000.0)
			if l != null:
				print("[net] client takes loot ", l.net_id, " ", l.item_id)
				l.consume()
			drop_weapon("smg", 10, 30, player.global_position)
	print("[net] done")
	get_tree().quit()


# ====================================================== social / squad UI ==

## Host settings arrived (or changed locally on the host).
func net_apply_settings(st: Dictionary) -> void:
	MAX_BOTS = clampi(int(st.get("bots", MAX_BOTS)), 0, 99)
	match_size = MAX_BOTS + 1
	loadout_enabled = bool(st.get("loadout", loadout_enabled))
	net.squad = bool(st.get("squad", net.squad))


func _on_net_chat(from_id: int, pname: String, text: String, system: bool) -> void:
	if phase in ["plane", "playing", "end"]:
		hud.chat_add(pname, net.color_of(from_id), text, system)
		if not system and from_id != net.my_id():
			sfx.play_ui("chat_msg", -10.0)


func _marker_color(id: int) -> Color:
	return net.color_of(id) if net.active else HUD.ACCENT


func _on_net_marker(from_id: int, pos: Vector3) -> void:
	if phase == "menu":
		return
	# Same spot again removes it, like toggling a map pin.
	if waypoints.has(from_id) and Vector2(pos.x, pos.z).distance_to(Vector2(waypoints[from_id].pos.x, waypoints[from_id].pos.z)) < 6.0:
		waypoints.erase(from_id)
		return
	waypoints[from_id] = {"pos": pos, "t": 120.0}
	# In free-for-all only your own marker shows.
	if from_id == net.my_id() or not net.active or net.squad:
		sfx.play_ui("marker_ping", -8.0)
		if from_id != net.my_id() and net.active:
			hud.show_notice("%s PLACED A MARKER" % str(net.roster.get(from_id, "MATE")), 1.6)


func _place_marker_from_view() -> void:
	var cam := player.camera
	var from := cam.global_position
	var to := from - cam.global_basis.z * 1500.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var pos: Vector3 = hit["position"] if not hit.is_empty() else to
	if hit.is_empty():
		pos.y = terrain.height_at(pos.x, pos.z)
	_send_marker(pos)


func _on_map_clicked(w: Vector2, button: int) -> void:
	if phase == "menu":
		return
	var me := net.my_id()
	if button == MOUSE_BUTTON_RIGHT:
		if waypoints.has(me):
			_send_marker(waypoints[me].pos)
		return
	_send_marker(Vector3(w.x, terrain.height_at(w.x, w.y), w.y))


func _send_marker(pos: Vector3) -> void:
	if net.active and net_on():
		net.send_marker(pos)
	else:
		_on_net_marker(net.my_id(), pos)


## Squad panel, overhead tags, markers, scoreboard and ping, every frame.
func _update_social(delta: float) -> void:
	hud.camera_3d = get_viewport().get_camera_3d()
	# Markers expire.
	var wl: Array = []
	for id in waypoints.keys():
		waypoints[id].t -= delta
		if waypoints[id].t <= 0.0:
			waypoints.erase(id)
			continue
		if id == net.my_id() or not net.active or net.squad:
			wl.append({"pos": waypoints[id].pos, "color": _marker_color(id), "name": ""})
	hud.waypoints = wl
	var tags: Array = []
	var rows: Array = []
	var mates: Array = []
	if net_on() and net.squad:
		var eye := player.global_position
		var ids := humans.keys()
		ids.sort()
		for id in ids:
			var h = humans[id]
			if h == null or not is_instance_valid(h):
				continue
			var b := h as Bot
			var col := net.color_of(id)
			rows.append([b.bot_name, col, b.hp, b.alive, eye.distance_to(b.global_position)])
			mates.append([b.bot_name, Vector2(b.global_position.x, b.global_position.z), col, b.alive])
			if b.alive and b.state != Bot.State.PLANE:
				tags.append({"pos": b.global_position + Vector3(0, 2.15, 0), "name": b.bot_name, "color": col})
	hud.tags = tags
	hud.set_squad_rows(rows)
	hud.set_mates(mates)
	hud.social_layer.queue_redraw()
	if net.active:
		var p := net.ping_of(net.my_id())
		hud.set_ping_text("HOST" if net.hosting else "PING  %d MS" % p, LobbyUI.GOOD if p < 60 else (Color(0.98, 0.82, 0.32) if p < 120 else LobbyUI.BAD))
	else:
		hud.set_ping_text("", Color.WHITE)
	# Scoreboard while Tab is held (and refreshed a few times a second).
	var want_sb: bool = (Input.is_action_pressed("scoreboard") or _shot_tab) and not hud.chat_open
	_social_t -= delta
	if want_sb and (_social_t <= 0.0 or not hud.scoreboard.visible):
		_social_t = 0.25
		_show_scoreboard()
	elif not want_sb and hud.scoreboard.visible:
		hud.show_scoreboard(false)
	if phase == "end" and net_on():
		_social_t -= 0.0
		_refresh_end_table()


func _human_rows() -> Array:
	var rows: Array = []
	var my_col := net.color_of(net.my_id()) if net.active else HUD.ACCENT
	rows.append({"name": (net.my_name if net.active else "YOU"), "color": my_col, "alive": player.alive,
		"kills": player_kills, "damage": damage_dealt, "ping": net.ping_of(net.my_id()) if net.active and not net.hosting else -1, "me": true})
	for id in humans:
		var h = humans[id]
		if h == null or not is_instance_valid(h):
			continue
		var b := h as Bot
		rows.append({"name": b.bot_name, "color": net.color_of(id), "alive": b.alive, "kills": b.net_kills,
			"damage": b.net_damage, "ping": -1 if id == 1 else net.ping_of(id), "me": false})
	rows.sort_custom(func(a, b): return int(a.kills) > int(b.kills) or (int(a.kills) == int(b.kills) and float(a.damage) > float(b.damage)))
	return rows


func _show_scoreboard() -> void:
	var bots_alive := 0
	for b in bots:
		if is_instance_valid(b) and (b as Bot).alive:
			bots_alive += 1
	var mode := ("SQUAD vs BOTS" if net.squad else "FREE-FOR-ALL") if net.active else "SOLO"
	var t := int(match_time)
	var title := "%s   ·   %d ALIVE   ·   %d:%02d" % [mode, alive, t / 60, t % 60]
	var zone_txt := ""
	if zone != null:
		zone_txt = "   ·   STORM PHASE %d" % (zone.phase + 1)
	hud.show_scoreboard(true, title, _human_rows(), "BOTS REMAINING   %d%s" % [bots_alive, zone_txt])


func _refresh_end_table() -> void:
	if not net_on():
		hud.end_table.text = ""
		return
	var lines: Array = ["%-16s %8s %8s   %s" % ["PLAYER", "KILLS", "DAMAGE", "STATUS"]]
	for r in _human_rows():
		lines.append("%-16s %8d %8d   %s" % [str(r.name).substr(0, 16), int(r.kills), int(r.damage), "ALIVE" if r.alive else "OUT"])
	hud.end_table.text = "\n".join(lines)


func _next_mate(after: Node) -> Bot:
	var ids := humans.keys()
	ids.sort()
	var list: Array = []
	for id in ids:
		var h = humans[id]
		if h != null and is_instance_valid(h) and (h as Bot).alive:
			list.append(h)
	if list.is_empty():
		return null
	var i := list.find(after)
	return list[(i + 1) % list.size()]


func _spectate_next() -> void:
	var m := _next_mate(end_cam_target)
	if m != null and m != end_cam_target:
		end_cam_target = m
		sfx.play_ui("ui_click", -10.0)
		_spectate_label()


func _net_end_hint() -> void:
	if net.active:
		hud.end_hint.text = "SPACE / ESC   BACK TO LOBBY      ·      ENTER   CHAT      ·      TAB   SCOREBOARD"
		if net.squad and winner:
			hud.end_sub.text = "#1   ·   YOUR SQUAD WINS"
	_refresh_end_table()


func _spectate_label() -> void:
	var t := end_cam_target
	if t != null and is_instance_valid(t) and t is Bot and (t as Bot).alive:
		var b := t as Bot
		var extra := "      ·      LMB  NEXT TEAMMATE" if b.is_human and humans.size() > 1 else ""
		hud.set_spectate("SPECTATING  %s%s" % [b.bot_name, extra])
	else:
		hud.set_spectate("")



# ================================================================ vehicles ==

## Pick parking spots for this match and park jeeps on them.
func _choose_vehicles() -> Array:
	var spots: Array = world.vehicle_spawns.duplicate()
	spots.shuffle()
	var out: Array = []
	for e in spots.slice(0, mini(34, spots.size())):
		out.append([e[0], e[1], randi() % Vehicle.PALETTE.size()])
	return out


func _spawn_vehicles(list: Array) -> void:
	for i in list.size():
		var e: Array = list[i]
		var v := Vehicle.new()
		v.setup(self, i, int(e[2]))
		v.position = Vector3(e[0]) + Vector3(0, 0.35, 0)
		v.rotation.y = float(e[1])
		add_child(v)
		v.owner_peer = 1
		v.set_puppet(net_is_client())
		vehicles.append(v)


## Nearest drivable jeep whose body (not its centre) is within max_d: you
## can get in from a door, the bonnet or the tailgate alike.
func _nearest_vehicle(pos: Vector3, max_d: float) -> Vehicle:
	var best: Vehicle = null
	var bd := max_d
	for v in vehicles:
		if not is_instance_valid(v) or (v as Vehicle).wrecked:
			continue
		var d := _vehicle_gap(pos + Vector3.UP * 0.9, v as Vehicle)
		if d < bd:
			bd = d
			best = v
	return best


## With a jeep and an item both in reach, F does what you look at: the jeep
## when the crosshair is on its body, else whichever sits nearer the
## crosshair.
func _interact_wants_car(p: Player, best: Node3D, car: Vehicle) -> bool:
	if car == null:
		return false
	if best == null:
		return true
	var eye := p.global_position + Vector3.UP * 1.55
	var fwd := -p.global_basis.z
	if p.camera != null:
		eye = p.camera.global_position
		fwd = -p.camera.global_basis.z
	# Crosshair ray against the body box, in the jeep's own space.
	var inv := car.global_transform.affine_inverse()
	var o := inv * eye
	var d := inv.basis * fwd
	var lo := Vector3(-1.05, 0.3, -2.2)
	var hi := Vector3(1.05, 1.95, 2.2)
	var t0 := 0.0
	var t1 := 4.5
	var hit := true
	for a in 3:
		if absf(d[a]) < 0.00001:
			if o[a] < lo[a] or o[a] > hi[a]:
				hit = false
				break
			continue
		var ta := (lo[a] - o[a]) / d[a]
		var tb := (hi[a] - o[a]) / d[a]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 > t1:
			hit = false
			break
	if hit:
		return true
	var to_car := (car.global_position + car.global_basis.y * 1.0 - eye).normalized()
	var to_loot := (best.global_position - eye).normalized()
	return fwd.dot(to_car) > fwd.dot(to_loot)


## Distance from a point to the jeep's body box.
static func _vehicle_gap(p: Vector3, v: Vehicle) -> float:
	var l := v.global_transform.affine_inverse() * p
	var c := Vector3(clampf(l.x, -0.95, 0.95), clampf(l.y, 0.6, 1.75), clampf(l.z, -2.05, 2.05))
	return l.distance_to(c)


func _enter_vehicle(v: Vehicle) -> void:
	var seat := v.free_seat()
	if seat < 0:
		hud.show_notice("JEEP IS FULL", 1.4)
		return
	v.seats[seat] = player
	_veh_enter_frame = Engine.get_physics_frames()
	player.vehicle = v
	player.seat = seat
	player.mode = Player.Mode.VEHICLE
	player.cancel_heal()
	player.reloading = false
	player.add_collision_exception_with(v)
	v.add_collision_exception_with(player)
	_veh_cam_yaw = 0.0
	_veh_last_yaw = player.yaw
	_veh_idle_t = 0.0
	menu_cam.global_position = player.camera.global_position
	menu_cam.fov = 72.0
	menu_cam.make_current()
	sfx.play_at("car_door", v.global_position, -2.0)
	hud.set_prompt("")
	if seat == 0:
		v.handbrake = false
		_claim_vehicle(v)
		hud.show_notice("%s / %s  DRIVE   ·   %s / %s  STEER   ·   %s  HANDBRAKE   ·   %s  GET OUT" % [Keybinds.key("move_forward"), Keybinds.key("move_back"), Keybinds.key("move_left"), Keybinds.key("move_right"), Keybinds.key("jump"), Keybinds.key("interact")], 3.0)
	else:
		hud.show_notice("PASSENGER   ·   %s  GET OUT" % Keybinds.key("interact"), 2.0)


func _claim_vehicle(v: Vehicle) -> void:
	if not net_on() or v.owner_peer == net.my_id():
		v.set_puppet(false)
		return
	var vel := v._net_vel
	v.owner_peer = net.my_id()
	v.set_puppet(false)
	v.linear_velocity = vel
	net.send_vehicle_owner(v.net_id)


## Out of the seat without placing the body (death, explosion).
func _leave_seat() -> void:
	var v: Vehicle = player.vehicle
	if v != null and is_instance_valid(v):
		if player.seat >= 0 and v.seats[player.seat] == player:
			v.seats[player.seat] = null
		v.release_rider(player)
		if player.seat == 0:
			v.throttle = 0.0
			v.steer_in = 0.0
	player.vehicle = null
	player.seat = -1
	player.mode = Player.Mode.GROUND
	hud.set_vehicle(false)


var _veh_exit_frame := -100000
var _veh_enter_frame := -100000


func _exit_vehicle() -> void:
	anticheat.grace(1.5)
	var v: Vehicle = player.vehicle
	if v == null or not is_instance_valid(v):
		_leave_seat()
		return
	var spot := _exit_spot(v, player.seat)
	var vel := v.linear_velocity
	var car_yaw := v.global_basis.get_euler().y
	_leave_seat()
	_veh_exit_frame = Engine.get_physics_frames()
	player.global_position = spot
	player.velocity = vel * 0.6
	player.yaw = car_yaw + _veh_cam_yaw
	player.camera.make_current()
	sfx.play_at("car_door", v.global_position, -2.0)
	# Bailing out at speed hurts.
	if vel.length() > 14.0:
		player.take_damage((vel.length() - 14.0) * 4.0, player.global_position, false, null)


## Where to stand after getting out: beside your own door if there is room
## (no wall between the seat and the spot, nothing in the way of your body),
## else the other door, behind, in front, and the roof as a last resort.
func _exit_spot(v: Vehicle, seat: int) -> Vector3:
	var s := maxi(seat, 0)
	var side := -1.0 if s % 2 == 0 else 1.0
	var sz: float = (Vehicle.SEATS[s] as Vector3).z
	# Yaw only, so a car on its side still lets you out onto the ground.
	var flat := Transform3D(Basis(Vector3.UP, v.global_basis.get_euler().y), v.global_position)
	var seat_pos := v.global_transform * (Vehicle.SEATS[s] as Vector3)
	var tries := [Vector3(side * 1.85, 0, sz), Vector3(side * 1.85, 0, sz + 1.1), Vector3(side * 1.85, 0, sz - 1.2),
		Vector3(-side * 1.85, 0, sz), Vector3(-side * 1.85, 0, sz + 1.1), Vector3(0, 0, 3.3), Vector3(0, 0, -3.5),
		Vector3(side * 2.6, 0, sz), Vector3(-side * 2.6, 0, sz)]
	var space := get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = 1.72
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = cap
	sq.collision_mask = 1 | 4
	# The jeep's own body counts: on its side it reaches out over the spots
	# beside the doors.
	sq.exclude = [player.get_rid()]
	for o in tries:
		var p: Vector3 = flat * (o as Vector3)
		var down := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 6.0, 1)
		down.exclude = [v.get_rid()]
		var hit := space.intersect_ray(down)
		var g: Vector3 = Vector3(hit["position"]) if not hit.is_empty() else Vector3(p.x, terrain.height_at(p.x, p.z), p.z)
		if absf(g.y - v.global_position.y) > 2.2:
			continue
		# Deep water is fine: come up swimming at the surface.
		if terrain.is_water(g.x, g.z):
			var ws: float = terrain.water_surface_at(g.x, g.z)
			if ws - g.y > Player.FLOAT_DEPTH:
				g.y = ws - Player.FLOAT_DEPTH
		sq.transform = Transform3D(Basis.IDENTITY, g + Vector3.UP * 0.94)
		if not space.intersect_shape(sq, 1).is_empty():
			continue
		var los := PhysicsRayQueryParameters3D.create(seat_pos + Vector3.UP * 0.3, g + Vector3.UP * 1.2, 1)
		los.exclude = [v.get_rid()]
		if not space.intersect_ray(los).is_empty():
			continue
		return g + Vector3.UP * 0.06
	return v.global_position + Vector3.UP * 2.3


## Driver input, the chase camera and the speedometer.
func _update_driving(delta: float) -> void:
	if player.mode != Player.Mode.VEHICLE:
		return
	var v: Vehicle = player.vehicle
	if v == null or not is_instance_valid(v):
		_leave_seat()
		player.camera.make_current()
		return
	# Backup for F when a focused menu control swallowed the key event.
	if Input.is_action_just_pressed("interact") and not input_locked and phase == "playing" \
			and Engine.get_physics_frames() - _veh_enter_frame > 12:
		_exit_vehicle()
		return
	if player.seat == 0 and not input_locked and not _drive_scripted:
		var fwd := (1.0 if Input.is_action_pressed("move_forward") else 0.0) - (1.0 if Input.is_action_pressed("move_back") else 0.0)
		v.throttle = fwd
		v.steer_in = (1.0 if Input.is_action_pressed("move_right") else 0.0) - (1.0 if Input.is_action_pressed("move_left") else 0.0)
		v.handbrake = Input.is_action_pressed("jump")
	elif player.seat == 0 and not _drive_scripted:
		v.throttle = 0.0
		v.steer_in = 0.0
	# Camera: mouse orbits, then eases back behind the jeep.
	var dy := wrapf(player.yaw - _veh_last_yaw, -PI, PI)
	_veh_last_yaw = player.yaw
	_veh_cam_yaw = wrapf(_veh_cam_yaw + dy, -PI, PI)
	_veh_idle_t = 0.0 if absf(dy) > 0.0005 else _veh_idle_t + delta
	if _veh_idle_t > 1.4 and absf(v.speed) > 3.0:
		_veh_cam_yaw = lerp_angle(_veh_cam_yaw, 0.0, clampf(delta * 1.6, 0.0, 1.0))
	var car_yaw := v.global_basis.get_euler().y
	var pitch := clampf(player.pitch, -0.75, 0.4)
	var b := Basis(Vector3.UP, car_yaw + _veh_cam_yaw) * Basis(Vector3.RIGHT, pitch - 0.1)
	var focus := v.global_position + Vector3(0, 1.8, 0)
	var dist := 7.4 + clampf(absf(v.speed) / 30.0, 0.0, 1.0) * 1.6
	var want := focus + b * Vector3(0, 0.4, dist)
	var q := PhysicsRayQueryParameters3D.create(focus, want, 1)
	q.exclude = [v.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		want = Vector3(hit["position"]) + (focus - Vector3(hit["position"])).normalized() * 0.5
	menu_cam.global_position = menu_cam.global_position.lerp(want, clampf(delta * 12.0, 0.0, 1.0))
	menu_cam.look_at(focus + b * Vector3(0, 0, -6.0) * 0.0 + Vector3(0, 0.2, 0), Vector3.UP)
	menu_cam.fov = lerpf(menu_cam.fov, fov - 6.0 + clampf(absf(v.speed) / 30.0, 0.0, 1.0) * 12.0, clampf(delta * 3.0, 0.0, 1.0))
	hud.set_vehicle(true, absf(v.speed) * 3.6, v.hp / Vehicle.MAX_HP, player.seat == 0)
	hud.set_crosshair_visible(false)


## Something blew up a jeep: hurt whoever was in or near it.
func vehicle_exploded(v: Vehicle, source: Node) -> void:
	var pos := v.global_position
	if player != null and player.alive:
		if player.vehicle == v:
			_leave_seat()
			player.camera.make_current()
			player.global_position = ground_at(pos + Vector3(2.0, 2.0, 0)) + Vector3(0, 0.2, 0)
			player.take_damage(240.0, pos, false, source if source != null and is_instance_valid(source) else null)
		else:
			var d := player.global_position.distance_to(pos)
			if d < 8.0:
				player.take_damage((1.0 - d / 8.0) * 110.0, pos, false, source if source != null and is_instance_valid(source) else null)
	if net_is_client():
		return
	for b in bots:
		if is_instance_valid(b) and (b as Bot).alive:
			var d2: float = (b as Bot).global_position.distance_to(pos)
			if d2 < 8.0:
				(b as Bot).take_damage((1.0 - d2 / 8.0) * 120.0, pos, false, source if source != null and is_instance_valid(source) else null)


func net_vehicle_hit(v: Vehicle, amount: float) -> void:
	if net_on():
		net.send_vehicle_hit(v.net_id, amount)


func net_vehicle_destroyed(v: Vehicle) -> void:
	if net_on():
		net.send_vehicle_destroyed(v.net_id)


func _vehicle(id: int) -> Vehicle:
	if id >= 0 and id < vehicles.size() and is_instance_valid(vehicles[id]):
		return vehicles[id]
	return null


## Snapshots of the jeeps this machine simulates.
func net_vehicle_states(full: bool) -> Array:
	var out: Array = []
	for v in vehicles:
		if not is_instance_valid(v) or not (v as Vehicle).is_local() or (v as Vehicle).wrecked:
			continue
		var vv := v as Vehicle
		if full or vv.seats[0] != null or vv.linear_velocity.length() > 0.2:
			out.append(vv.net_state())
	return out


func net_apply_vehicle_states(list: Array) -> void:
	if not _net_setup_ok:
		return
	for st in list:
		var v := _vehicle(int(st[0]))
		if v != null and not v.is_local():
			v.apply_net_state(st)


func net_vehicle_owner(id: int, peer_id: int) -> void:
	var v := _vehicle(id)
	if v == null:
		return
	v.owner_peer = peer_id
	v.set_puppet(peer_id != net.my_id())
	# If we were driving it, someone took the wheel: hop to another seat.
	if peer_id != net.my_id() and player.vehicle == v and player.seat == 0:
		_exit_vehicle()


func net_vehicle_hit_received(id: int, amount: float) -> void:
	var v := _vehicle(id)
	if v != null and v.is_local():
		v.apply_damage(amount, null)


func net_vehicle_destroyed_received(id: int) -> void:
	var v := _vehicle(id)
	if v != null:
		v.explode(null)


## Remote humans riding in jeeps (from their state packets).
func _seat_remote(h: Bot, vid: int, slot: int) -> void:
	var v := _vehicle(vid) if vid >= 0 else null
	if h.seated_in != null and is_instance_valid(h.seated_in) and (h.seated_in != v or h.seated_slot != slot):
		if h.seated_slot >= 0 and h.seated_in.seats[h.seated_slot] == h:
			h.seated_in.seats[h.seated_slot] = null
		h.seated_in.release_rider(h)
		h.seated_in = null
		h.seated_slot = -1
	if v != null and slot >= 0 and h.seated_in == null:
		h.seated_in = v
		h.seated_slot = slot
		v.seats[slot] = h
		h.add_collision_exception_with(v)
		v.add_collision_exception_with(h)



## Headless jeep test: settle, accelerate, steer, roadkill, explode.
## Press F through the real input path: get in, get out, stay out. From every
## seat, parked against a house wall, and with the jeep on its side.
func _press(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().physics_frame
	await get_tree().process_frame
	var r := InputEventAction.new()
	r.action = action
	r.pressed = false
	Input.parse_input_event(r)
	await get_tree().physics_frame


func _run_carexit_test() -> void:
	_start_match()
	await get_tree().physics_frame
	_land_player_now()
	var v: Vehicle = vehicles[0]
	var fails := 0
	var space := get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.6
	var places: Array = []
	for pad in world.villages.village_pads:
		if pad.type == "town":
			places.append(["plaza", Vector3((pad.center as Vector2).x, float(pad.pad) + 0.5, (pad.center as Vector2).y), 0.0, false])
			break
	# Against a house: door side pressed to the wall.
	var h: Dictionary = world.villages.houses[3]
	var hc2: Vector2 = h["center"]
	var hy: float = float(h.get("yaw", 0.0))
	var hx := Basis(Vector3.UP, hy) * Vector3(1, 0, 0)
	var half_w: float = float(h.get("w", 8.0)) * 0.5
	var hc := Vector3(hc2.x, float(h.get("pad", 0.0)), hc2.y)
	places.append(["wall", Vector3(0, 0.5, 0) + Vector3(hc.x, 0, hc.z) + hx * (half_w + 1.75), hy, false])
	var dummy := Node3D.new()
	places.append(["tipped", places[0][1] + Vector3(6, 0.4, 0), 0.0, true])
	for pl in places:
		for seat in 4:
			v.global_transform = Transform3D(Basis(Vector3.UP, float(pl[2])) * (Basis(Vector3.FORWARD, PI * 0.5) if bool(pl[3]) else Basis.IDENTITY), pl[1])
			if pl[0] == "wall":
				var gw := terrain.height_at(v.global_position.x, v.global_position.z)
				v.global_position.y = gw + 0.6
			v.linear_velocity = Vector3.ZERO
			v.angular_velocity = Vector3.ZERO
			v._last_vel = Vector3.ZERO
			v._crash_cd = 2.0
			# A tipped jeep rights itself after a few seconds: let it settle.
			for i in (420 if bool(pl[3]) else 50):
				await get_tree().physics_frame
				if bool(pl[3]) and i % 30 == 0:
					print("[carexit]   settle %d up=%.2f hp=%.0f vel=%.1f grounded=%d flip_t=%.1f asleep=%s frozen=%s driver=%s" % [i, v.global_basis.y.y, v.hp, v.linear_velocity.length(), v._grounded, v._flip_t, v._asleep, v.freeze, v.seats[0] != null])
			while v.linear_velocity.length() > 0.3:
				await get_tree().physics_frame
			v.hp = Vehicle.MAX_HP
			for k in 4:
				v.seats[k] = dummy if k < seat else null
			var flat_x := Basis(Vector3.UP, v.global_basis.get_euler().y) * Vector3(1, 0, 0)
			player.global_position = ground_at(v.global_position + flat_x * 2.6) + Vector3.UP * 0.1
			player.velocity = Vector3.ZERO
			player.yaw = atan2(flat_x.x, flat_x.z)
			player.pitch = -0.15
			for i in 3:
				await get_tree().physics_frame
			var nl := _nearest_loot(player.global_position, 3.2)
			var pre := "mode=%d d=%.1f car=%s up=%.2f near_car=%s free=%d loot=%s locked=%s cd=%d hp=%d wrecked=%s" % [player.mode, player.global_position.distance_to(v.global_position + Vector3(0, 0.8, 0)), str(v.global_position.round()), v.global_basis.y.y, _nearest_vehicle(player.global_position, 1.7) == v, v.free_seat(), str(nl.global_position.distance_to(player.global_position)) if nl != null else "-", player._locked(), Engine.get_physics_frames() - _veh_exit_frame, int(v.hp), v.wrecked]
			await _press("interact")
			for i in 6:
				await get_tree().physics_frame
			var entered := player.mode == Player.Mode.VEHICLE
			var got_seat := player.seat
			for i in 20:
				await get_tree().physics_frame
			await _press("interact")
			var exit_d := player.global_position.distance_to(v.global_position)
			var car0 := v.global_position
			var stayed_out := true
			for i in 40:
				await get_tree().physics_frame
				if player.mode != Player.Mode.GROUND:
					stayed_out = false
			var sq := PhysicsShapeQueryParameters3D.new()
			sq.shape = cap
			sq.collision_mask = 1
			sq.exclude = [player.get_rid()]
			sq.transform = Transform3D(Basis.IDENTITY, player.global_position + Vector3.UP * 0.95)
			var stuck := not space.intersect_shape(sq, 1).is_empty()
			var ok := entered and stayed_out and not stuck and exit_d < 4.0
			if not ok:
				fails += 1
			print("[carexit] %s seat=%d entered=%s got_seat=%d stayed_out=%s stuck=%s exit_d=%.1f later_d=%.1f car_moved=%.1f %s  (%s)" % [pl[0], seat, entered, got_seat, stayed_out, stuck, exit_d, player.global_position.distance_to(v.global_position), car0.distance_to(v.global_position), "ok" if ok else "FAIL", pre])
			for k in 4:
				v.seats[k] = null
	dummy.free()
	print("[carexit] ", "ALL GOOD" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()


func _run_drive_test() -> void:
	_start_match()
	await get_tree().physics_frame
	_land_player_now()
	print("[drive] spawns=", world.vehicle_spawns.size(), " jeeps=", vehicles.size())
	var v: Vehicle = vehicles[0]
	# Test on the flattened plaza of a town, pointed down its main street.
	for pad in world.villages.village_pads:
		if pad.type == "town":
			var c: Vector2 = pad.center
			var d := Vector2(cos(float(pad.axis)), sin(float(pad.axis)))
			var start2 := c - d * (float(pad.radius) - 4.0)
			v.global_position = Vector3(start2.x, float(pad.pad) + 0.4, start2.y)
			v.rotation = Vector3(0, atan2(-d.x, -d.y), 0)
			v.linear_velocity = Vector3.ZERO
			v.angular_velocity = Vector3.ZERO
			break
	player.global_position = v.global_position + v.global_basis.x * 2.5 + Vector3(0, 1, 0)
	for i in 120:
		await get_tree().physics_frame
	var up := v.global_basis.y.y
	var gy: float = terrain.height_at(v.global_position.x, v.global_position.z)
	print("[drive] settled: up=%.2f height_above_ground=%.2f grounded=%d speed=%.2f" % [up, v.global_position.y - gy, v._grounded, v.speed])
	try_pickup(player)
	_drive_scripted = true
	print("[drive] entered mode=", player.mode, " seat=", player.seat)
	var start := v.global_position
	var t := 0.0
	var top := 0.0
	var nxt := 0.0
	while t < 6.0:
		v.throttle = 1.0
		v.steer_in = 0.0
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		top = maxf(top, v.speed)
		if t >= nxt:
			nxt += 1.0
			print("[drive]   t=%.0f speed=%.1f m/s grounded=%d comp=%s slip=%.2f up=%.2f vel=%s" % [t, v.speed, v._grounded, str(v._compress), v._slip, v.global_basis.y.y, str(v.linear_velocity.round())])
	print("[drive] after 6s full throttle: speed=%.1f km/h top=%.1f km/h moved=%.0f m up=%.2f hp=%.0f" % [v.speed * 3.6, top * 3.6, start.distance_to(v.global_position), v.global_basis.y.y, v.hp])
	if v.speed < 3.0:
		# Report what stopped it.
		var qs := PhysicsShapeQueryParameters3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(2.6, 1.6, 5.4)
		qs.shape = bx
		qs.transform = Transform3D(v.global_basis, v.global_position + Vector3(0, 1.0, 0))
		qs.exclude = [v.get_rid()]
		for r in get_world_3d().direct_space_state.intersect_shape(qs, 8):
			var body := r["collider"] as CollisionObject3D
			var sn: Node = _shape_node(body, int(r["shape"]))
			print("[drive]   blocked by ", body.name if body else "?", " ", (sn as Node3D).global_position if sn is Node3D else "", " ", ((sn as CollisionShape3D).shape as BoxShape3D).size if sn is CollisionShape3D and (sn as CollisionShape3D).shape is BoxShape3D else "")
	var yaw0 := v.global_basis.get_euler().y
	t = 0.0
	while t < 2.0:
		v.throttle = 0.6
		v.steer_in = 1.0
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	print("[drive] turn right 2s: yaw change=%.0f deg up=%.2f slip=%.2f" % [rad_to_deg(wrapf(v.global_basis.get_euler().y - yaw0, -PI, PI)), v.global_basis.y.y, v._slip])
	t = 0.0
	while t < 1.5:
		v.throttle = 0.0
		v.steer_in = -1.0
		v.handbrake = true
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	v.handbrake = false
	print("[drive] handbrake: speed=%.1f km/h slip=%.2f up=%.2f" % [v.speed * 3.6, v._slip, v.global_basis.y.y])
	# Roadkill: put a bot in the path and floor it.
	var victim: Bot = null
	for b in bots:
		if is_instance_valid(b) and b.alive:
			victim = b
			break
	if victim != null:
		for pad in world.villages.village_pads:
			if pad.type == "town":
				var c: Vector2 = pad.center
				var d := Vector2(cos(float(pad.axis)), sin(float(pad.axis)))
				var start2 := c - d * (float(pad.radius) - 4.0)
				v.global_position = Vector3(start2.x, float(pad.pad) + 0.4, start2.y)
				v.rotation = Vector3(0, atan2(-d.x, -d.y), 0)
				v.linear_velocity = Vector3.ZERO
				v.angular_velocity = Vector3.ZERO
				break
		for i in 30:
			await get_tree().physics_frame
		victim.state = Bot.State.GROUND
		victim.global_position = v.global_position - v.global_basis.z * 22.0 + Vector3(0, 0.5, 0)
		victim.set_physics_process(false)
		victim.velocity = Vector3.ZERO
		t = 0.0
		while t < 3.0 and victim.alive:
			v.throttle = 1.0
			v.steer_in = 0.0
			var to := victim.global_position - v.global_position
			v.steer_in = clampf(to.normalized().dot(v.global_basis.x) * 3.0, -1.0, 1.0)
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		print("[drive] roadkill: victim alive=", victim.alive, " hp=", int(victim.hp), " dist=", int(victim.global_position.distance_to(v.global_position)), " speed=", int(v.speed * 3.6), " victim_layer=", victim.collision_layer, " contacts=", v.get_contact_count())
	_exit_vehicle()
	print("[drive] exited mode=", player.mode, " cam_is_player=", player.camera.current)
	v.apply_damage(5000.0, null)
	await get_tree().physics_frame
	print("[drive] destroyed wrecked=", v.wrecked, " player_hp=", int(player.hp))
	print("[drive] done")
	get_tree().quit()



## Apply the graphics preset to the world's lights, environment and foliage.
## Adaptive vsync: no tearing at full rate, no stutter below it (plain vsync
## halves the frame rate in steps whenever a frame runs a little late).
## Player, frame-rate and interface options from Settings.
func _apply_options() -> void:
	var o := func(k: String) -> int: return int(options.get(k, HUD.OPTS[k][2]))
	Engine.max_fps = [0, 30, 60, 90, 120, 144, 165, 240][clampi(o.call("fps_cap"), 0, 7)]
	if DisplayServer.get_name() != "headless":
		get_tree().root.content_scale_factor = [0.85, 1.0, 1.15, 1.3][clampi(o.call("ui_scale"), 0, 3)]
		hud.set_colorblind(o.call("colorblind"))
	if player != null:
		player.invert_y = o.call("invert_y") == 1
		player.aim_toggle = o.call("aim_mode") == 1
		player.crouch_toggle = o.call("crouch_mode") == 1
		player.sprint_toggle = o.call("sprint_mode") == 1
		player.bob_scale = [1.0, 0.4, 0.0][clampi(o.call("head_bob"), 0, 2)]
		player.shake_scale = [1.0, 0.45, 0.0][clampi(o.call("shake"), 0, 2)]
		player.vm_offset = [Vector3.ZERO, Vector3(-0.085, 0.02, 0.0), Vector3(0.0, -0.045, 0.03)][clampi(o.call("viewmodel"), 0, 2)]


func _apply_vsync() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ADAPTIVE if vsync else DisplayServer.VSYNC_DISABLED)


func _apply_graphics() -> void:
	if world == null:
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--quality="):
			graphics_quality = clampi(int(arg.substr(10)), 0, 3)
	Graphics.apply(graphics_quality, world.environment, world.sun, world.fill_light, get_viewport(), world.world_env, upscaling, options)
	var k := Graphics.draw_scale(graphics_quality, options)
	for n in world.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := n as MultiMeshInstance3D
		if not mmi.has_meta("vr"):
			mmi.set_meta("vr", mmi.visibility_range_end)
		var base: float = mmi.get_meta("vr")
		if base > 0.0:
			mmi.visibility_range_end = base * k
	if world.grass != null and DisplayServer.get_name() != "headless":
		var gr := int(options.get("grass", 0))
		world.grass.set_radius([0.0, 26.0, 36.0, 46.0][graphics_quality] if gr == 0 else [0.0, 0.0, 22.0, 36.0, 52.0][gr])
	print("[gfx] renderer=%s quality=%s" % [RenderingServer.get_current_rendering_method(), Graphics.NAMES[graphics_quality]])



## Cheat in one way (CHEAT=speed|rapid|ammo|hp|time|fly|legit) and check the
## anti-cheat catches it and the Warden finishes the job. "legit" plays
## normally (running, jumping, shooting, vaulting) and must not be caught.
func _run_cheat_test() -> void:
	var kind := OS.get_environment("CHEAT") if OS.get_environment("CHEAT") != "" else "speed"
	_start_match()
	await get_tree().physics_frame
	_land_player_now()
	for bt in bots:
		if is_instance_valid(bt):
			bt.set_physics_process(false)
	if zone != null:
		zone.set_process(false)
	var p := player
	p.give_weapon("rifle")
	for i in 240:
		await get_tree().physics_frame
	var t0 := Time.get_ticks_msec()
	var st := {"caught": -1.0, "died": false, "killer": ""}
	anticheat.condemned.connect(func(_w, r): st["caught"] = (Time.get_ticks_msec() - t0) / 1000.0; print("[cheat] CONDEMNED after %.1fs: %s" % [st["caught"], r]))
	print("[cheat] cheating: ", kind)
	# Run the way with the most open ground, not into the nearest wall.
	var fwd := Basis(Vector3.UP, p.yaw) * Vector3(0, 0, -1)
	var best := -1.0
	var space := p.get_world_3d().direct_space_state
	for k in 16:
		var dir := Vector3(sin(k * TAU / 16.0), 0.0, cos(k * TAU / 16.0))
		var from := p.global_position + Vector3(0, 1.0, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 120.0)
		q.exclude = [p.get_rid()]
		var hit := space.intersect_ray(q)
		var free := 120.0 if hit.is_empty() else from.distance_to(hit.position)
		if free > best:
			best = free
			fwd = dir
	p.yaw = atan2(-fwd.x, -fwd.z)
	for i in 600:
		match kind:
			"speed":
				# Moved along the ground, so no fence or crate on the way
				# can wedge the test body and hide the hack.
				p.test_input = Vector2(0, -1)
				var np := p.global_position + fwd * 0.42
				np.y = maxf(np.y, terrain.height_at(np.x, np.z) + 0.05)
				p.global_position = np
			"rapid":
				p.fire_timer = 0.0
				p.reloading = false
				p.mags[p.current_id()] = 30
				p._try_fire()
			"ammo":
				if i % 5 == 0:
					p.fire_timer = 0.0
					p._try_fire()
					p.mags[p.current_id()] = 30
			"hp":
				p.hp = 250.0
			"time":
				Engine.time_scale = 1.6
			"fly":
				p.global_position.y += 0.0 if i > 30 else 0.4
				p.velocity = Vector3.ZERO
			"legit":
				p.test_input = Vector2(sin(i * 0.02), -1)
				p.sprinting = true
				if i % 90 == 0:
					p.test_jump = true
				if i % 7 == 0 and p.current_mag() > 0:
					p.fire_timer = 0.0
					p._try_fire()
				if p.current_mag() <= 0 and not p.reloading:
					p.ammo[Weapons.caliber(p.current_id())] = 90
					p.start_reload()
				p.yaw += 0.01
		await get_tree().physics_frame
		if i % 120 == 0:
			print("[cheat]   t=%d enabled=%s phase=%s mode=%d grace=%.1f mode_t=%.1f hist=%d pos=%s" % [i, anticheat.enabled, phase, p.mode, anticheat._grace, anticheat._mode_t, anticheat._hist.size(), str(p.global_position.round())])
		if float(st["caught"]) >= 0.0:
			break
	Engine.time_scale = 1.0
	p.test_input = Vector2.ZERO
	var w_seen := false
	p.died.connect(func(k): st["died"] = true; st["killer"] = k)
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 40000 and not bool(st["died"]) and float(st["caught"]) >= 0.0:
		await get_tree().process_frame
		for w in wardens:
			if is_instance_valid(w):
				if not w_seen:
					print("[cheat] warden spawned %.0f m away" % (w as Node3D).global_position.distance_to(p.global_position))
				w_seen = true
	var caught := float(st["caught"]) >= 0.0
	var ok := (caught and w_seen and bool(st["died"]) and str(st["killer"]) == "THE WARDEN") if kind != "legit" else not caught
	print("[cheat] %s: caught=%s warden=%s died=%s killer=%s -> %s" % [kind, caught, w_seen, st["died"], st["killer"], "PASS" if ok else "FAIL"])
	for l in anticheat.report():
		print("[cheat]   ", l)
	get_tree().quit()


## Jump through every ground-floor window: in from outside, out from inside.
func _run_window_test() -> void:
	_start_match()
	await get_tree().physics_frame
	_land_player_now()
	for bt in bots:
		if is_instance_valid(bt):
			bt.set_physics_process(false)
	if zone != null:
		zone.set_process(false)
	player.spawn_protect = 1.0e9
	var space := get_world_3d().direct_space_state
	var tried := 0
	var ok_in := 0
	var ok_out := 0
	var why: Dictionary = {}
	var limit := int(_env_f("WIN_LIMIT", 60.0))
	for h in world.villages.houses:
		if tried >= limit:
			break
		var hb := Basis(Vector3.UP, float(h.yaw))
		var c2: Vector2 = h.center
		var o := Vector3(c2.x, float(h.pad), c2.y)
		var seen: Dictionary = {}
		for op in h.get("openings", []):
			var l: Vector2 = op
			var key := "%d,%d" % [int(l.x * 10), int(l.y * 10)]
			if seen.has(key):
				continue
			seen[key] = true
			var nl := Vector3(0, 0, signf(l.y)) if absf(absf(l.y) - float(h.d) * 0.5) < 0.3 else Vector3(signf(l.x), 0, 0)
			var n := hb * nl
			var wc := o + hb * Vector3(l.x, 0.0, l.y)
			# Doors reach the floor: skip them. So are upper-floor windows
			# over a solid ground-floor wall.
			var dq := PhysicsRayQueryParameters3D.create(wc + n * 0.8 + Vector3.UP * 0.5, wc - n * 0.8 + Vector3.UP * 0.5, 1)
			if space.intersect_ray(dq).is_empty():
				continue
			var wq := PhysicsRayQueryParameters3D.create(wc + n * 0.8 + Vector3.UP * 1.3, wc - n * 0.8 + Vector3.UP * 1.3, 1)
			if not space.intersect_ray(wq).is_empty():
				continue
			tried += 1
			for dir in [1.0, -1.0]:
				var start: Vector3 = wc + n * 0.75 * float(dir)
				var g := ground_at(start + Vector3.UP * 1.2) if dir > 0.0 else Vector3(start.x, float(h.pad) + 0.05, start.z)
				player.mode = Player.Mode.GROUND
				player.velocity = Vector3.ZERO
				player.global_position = g + Vector3.UP * 0.05
				var face: Vector3 = -n * float(dir)
				player.yaw = atan2(-face.x, -face.z)
				for i in 3:
					await get_tree().physics_frame
				var pre_pos := player.global_position
				if Vector2(pre_pos.x - g.x, pre_pos.z - g.z).length() > 0.25:
					# Furniture or stairs in front of this window: nobody can stand there.
					why["spot blocked"] = int(why.get("spot blocked", 0)) + 1
					continue
				var did := player._try_window_vault()
				for i in 50:
					await get_tree().physics_frame
				var through: bool = (player.global_position - wc).dot(n) * float(dir) < -0.25
				if did and through:
					if dir > 0.0:
						ok_in += 1
					else:
						ok_out += 1
				else:
					var r := player.vault_fail if not did else "stuck"
					var k2 := ("in " if dir > 0.0 else "out ") + r
					why[k2] = int(why.get(k2, 0)) + 1
					if int(why[k2]) <= 3:
						# What the rays see at each height in front of us.
						var f2 := -n * float(dir)
						var feet2 := g + Vector3.UP * 0.05
						var hits := []
						for hh in [0.3, 0.55, 0.8, 1.0, 1.2, 1.4, 1.6, 1.8, 2.0]:
							var q2 := PhysicsRayQueryParameters3D.create(feet2 + Vector3.UP * hh, feet2 + Vector3.UP * hh + f2 * 2.0, 1 | 4)
							q2.exclude = [player.get_rid()]
							var hr := space.intersect_ray(q2)
							hits.append("%.1f:%s" % [hh, ("%.2f %s" % [(Vector3(hr["position"]) - feet2).dot(f2), str((hr["collider"] as Node).name).substr(0, 10)]) if not hr.is_empty() else "-"])
						print("[windows]   %s at %s house %s g=%s player=%s  %s" % [k2, str(wc.snapped(Vector3.ONE * 0.01)), str(h.get("style", "")), str(g.snapped(Vector3.ONE * 0.01)), str(player.global_position.snapped(Vector3.ONE * 0.01)), " ".join(hits)])
	var blocked := int(why.get("spot blocked", 0))
	print("[windows] tried %d windows: in %d/%d  out %d/%d  (attempts from a blocked spot: %d)  fails=%s" % [tried, ok_in, tried, ok_out, tried, blocked, str(why)])
	get_tree().quit()


func _run_mantle_test() -> void:
	_start_match()
	await get_tree().physics_frame
	_land_player_now()
	for i in 30:
		await get_tree().physics_frame
	for h in [0.6, 1.1, 1.6, 2.6]:
		var fwd := Basis(Vector3.UP, player.yaw) * Vector3(0, 0, -1)
		var feet := player.global_position
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(2.0, h, 1.2)
		cs.shape = bs
		body.add_child(cs)
		add_child(body)
		body.global_position = feet + fwd * 1.2 + Vector3.UP * (h * 0.5)
		body.rotation.y = player.yaw
		await get_tree().physics_frame
		var ok := player._try_mantle()
		for i in 60:
			await get_tree().physics_frame
		print("[mantle] obstacle %.1f m: vaulted=%s  height gained=%.2f  forward=%.2f" % [h, ok, player.global_position.y - feet.y, (player.global_position - feet).dot(fwd)])
		body.queue_free()
		player.global_position = feet
		player.velocity = Vector3.ZERO
		for i in 20:
			await get_tree().physics_frame
	get_tree().quit()



## Walk up the stairs of every two-storey house and every tower.
func _run_stairs_test() -> void:
	_start_match()
	await get_tree().physics_frame
	_land_player_now()
	for i in 20:
		await get_tree().physics_frame
	# Nobody shoots the tester.
	for bt in bots:
		if is_instance_valid(bt):
			bt.set_physics_process(false)
	if zone != null:
		zone.set_process(false)
	var vil := world.villages
	var jobs: Array = []
	for h in vil.houses:
		if int(h.get("built_levels", 1)) > 1:
			jobs.append(["house", Vector3(h.center.x, h.pad, h.center.y), float(h.yaw), float(h.w) * 0.5 - 1.1, float(h.w), float(h.d)])
	for t in vil.towers:
		jobs.append(["tower", Vector3(t.center.x, t.pad, t.center.y), float(t.get("yaw", 0.0)), 1.9, 6.0, 6.0])
	var ok := 0
	var fails: Array = []
	for j in jobs:
		var o: Vector3 = j[1]
		var b := Basis(Vector3.UP, float(j[2]))
		var foot := float(j[3])
		player.alive = true
		player.hp = 100.0
		player.spawn_protect = 999.0
		player.mode = Player.Mode.GROUND
		player.velocity = Vector3.ZERO
		player.global_position = o + b * Vector3(foot, 0.1, vil.stair_foot_z(float(j[5])) + 0.45)
		player.yaw = float(j[2])
		player.test_input = Vector2.ZERO
		for i in 6:
			await get_tree().physics_frame
		player.test_input = Vector2(0, -1)
		var best := -10.0
		var dbg := false
		var last_hits: Array = []
		for i in 240:
			await get_tree().physics_frame
			best = maxf(best, player.global_position.y - o.y)
			if i == 200:
				last_hits.clear()
				for k in player.get_slide_collision_count():
					var c2 := player.get_slide_collision(k)
					var shp2 = c2.get_collider_shape()
					var nm := str((c2.get_collider() as Node).name) if c2.get_collider() is Node else "?"
					if shp2 is CollisionShape3D:
						var cs4 := shp2 as CollisionShape3D
						last_hits.append("%s shape_local=%s size=%s" % [nm, str((b.inverse() * (cs4.global_position - o)).snapped(Vector3.ONE * 0.01)), str((cs4.shape as BoxShape3D).size if cs4.shape is BoxShape3D else cs4.shape.get_class())])
					else:
						last_hits.append(nm)
			if dbg and i % 40 == 0:
				var hits := []
				for k in player.get_slide_collision_count():
					var c := player.get_slide_collision(k)
					var shp = c.get_collider_shape()
					var info := ""
					if shp is CollisionShape3D:
						var cs3 := shp as CollisionShape3D
						info = " shape_local=%s size=%s" % [str((b.inverse() * (cs3.global_position - o)).snapped(Vector3.ONE * 0.01)), str((cs3.shape as BoxShape3D).size if cs3.shape is BoxShape3D else "?")]
					hits.append("%s n=%s%s" % [str((c.get_collider() as Node).name) if c.get_collider() is Node else "?", str(c.get_normal().round()), info])
				print("[stairs] dbg local=", (b.inverse() * (player.global_position - o)).snapped(Vector3.ONE * 0.01), " hits=", hits)
		player.test_input = Vector2.INF
		if best > Villages.WALL_HEIGHT - 0.35:
			ok += 1
		else:
			fails.append("%s %dx%d at %s reached %.2f m  player_local=%s  hits=%s" % [j[0], int(j[4]), int(j[5]), str(o.round()), best, str((b.inverse() * (player.global_position - o)).snapped(Vector3.ONE * 0.01)), str(last_hits)])
	print("[stairs] %d / %d buildings: upstairs reached" % [ok, jobs.size()])
	for f in fails.slice(0, 20):
		print("[stairs] FAIL ", f)
	get_tree().quit()



## Walk into every house through its door (and upstairs if it has one),
## steering through waypoints like a player would.
## Swimming: float at the right depth, dive and come up, run out of air,
## swim to the beach and walk out; the plateau lake floats you too.
func _run_swim_test() -> void:
	_start_match()
	await get_tree().physics_frame
	_land_player_now()
	for bt in bots:
		if is_instance_valid(bt):
			bt.set_physics_process(false)
	if zone != null:
		zone.set_process(false)
	player.spawn_protect = 9999.0
	var ok := true
	# Find deep sea a little way off a beach: walk out from the centre.
	var spot := Vector3.INF
	var shore := Vector3.INF
	for k in 24:
		var a := TAU * float(k) / 24.0
		var d := 300.0
		while d < 1200.0:
			var x := cos(a) * d
			var z := sin(a) * d
			if terrain.height_at(x, z) < Terrain.WATER_LEVEL - 3.0:
				spot = Vector3(x, Terrain.WATER_LEVEL + 2.0, z)
				shore = Vector3(cos(a) * (d - 40.0), 0, sin(a) * (d - 40.0))
				break
			d += 4.0
		if spot != Vector3.INF and terrain.slope_at(shore.x, shore.z) < 0.25:
			break
	player.global_position = spot
	player.velocity = Vector3(0, -8.0, 0)
	player.mode = Player.Mode.GROUND
	for i in 120:
		await get_tree().physics_frame
	var surf := Terrain.WATER_LEVEL
	var depth_ok := absf(player.global_position.y - (surf - Player.FLOAT_DEPTH)) < 0.25
	print("[swim] sea: swimming=%s y=%.2f (want %.2f) cam above water=%s" % [player.swimming, player.global_position.y, surf - Player.FLOAT_DEPTH, player.camera.global_position.y > surf])
	ok = ok and player.swimming and depth_ok
	# Dive.
	player.test_hold["crouch"] = true
	for i in 240:
		await get_tree().physics_frame
	var dived := player.global_position.y < surf - 3.0
	var air_used := player.air < 90.0
	print("[swim] dive: y=%.2f air=%.0f underwater fx=%s" % [player.global_position.y, player.air, _underwater])
	player.test_hold.clear()
	for i in 240:
		await get_tree().physics_frame
	var back_up := absf(player.global_position.y - (surf - Player.FLOAT_DEPTH)) < 0.3
	print("[swim] surfaced=%s air=%.0f underwater fx=%s" % [back_up, player.air, _underwater])
	ok = ok and dived and air_used and back_up and not _underwater
	# Swim to the beach and walk out.
	var t := 0.0
	var out := false
	while t < 40.0:
		var to := shore - player.global_position
		to.y = 0.0
		player.yaw = atan2(-to.x, -to.z)
		player.test_input = Vector2(0, -1)
		if player.swimming and player.is_on_wall():
			player.test_jump = true
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if not player.swimming and not player.in_water and player.global_position.y > surf + 0.3:
			out = true
			break
	player.test_input = Vector2.INF
	print("[swim] walked out onto the beach=%s after %.0fs at %s" % [out, t, str(player.global_position.round())])
	ok = ok and out
	# Plateau lake.
	var lc := Terrain.LAKE_C
	player.global_position = Vector3(lc.x, terrain.lake_level + 3.0, lc.y)
	player.velocity = Vector3.ZERO
	for i in 150:
		await get_tree().physics_frame
	var lake_ok: bool = player.swimming and absf(player.global_position.y - (terrain.lake_level - Player.FLOAT_DEPTH)) < 0.3
	print("[swim] lake: swimming=%s y=%.2f lake level %.2f (deep %.1f)" % [player.swimming, player.global_position.y, terrain.lake_level, terrain.lake_level - terrain.height_at(lc.x, lc.y)])
	ok = ok and lake_ok
	print("[swim] %s" % ("ALL GOOD" if ok else "FAIL"))
	get_tree().quit()


## Climb the new set pieces: the Arcane Spire's outside stair to the top
## deck, and the Faerie Grove's mushroom caps (vaulting cap to cap).
func _run_fantasy_test() -> void:
	_start_match()
	await get_tree().physics_frame
	_land_player_now()
	for bt in bots:
		if is_instance_valid(bt):
			bt.set_physics_process(false)
	if zone != null:
		zone.set_process(false)
	player.spawn_protect = 9999.0
	var fz: Fantasy = world.villages.landmarks.fantasy
	var all_ok := true
	# Spire and Elder Oak: follow each helix up.
	var helixes: Array = []
	if fz.poi.has("spire_stair"):
		helixes.append(["spire", fz.poi["spire_stair"], 2.5, 4.3])
	var oak: Array = world.villages.landmarks.oak_stair
	if not oak.is_empty():
		helixes.append(["oak", oak, 1.15, 5.0])
	for hx in helixes:
		var sp: Array = hx[1]
		var o: Vector3 = sp[0]
		var hr: float = sp[1]
		var a0: float = sp[2]
		var deck: float = sp[4]
		player.global_position = o + Vector3(cos(a0 - 0.25) * hr, 1.2, sin(a0 - 0.25) * hr)
		player.velocity = Vector3.ZERO
		player.mode = Player.Mode.GROUND
		var t := 0.0
		var top := false
		while t < 90.0:
			var rel := player.global_position - o
			var ang := atan2(rel.z, rel.x)
			# Unwrap to the stair's own turn count using height.
			var y0: float = float(sp[5]) if sp.size() > 5 else 0.0
			var frac := clampf((player.global_position.y - o.y - y0) / (deck - y0), 0.0, 1.0)
			var target_a := a0 + (TAU * float(hx[2])) * frac + 0.22
			var tgt := o + Vector3(cos(target_a) * hr, 0, sin(target_a) * hr)
			if player.global_position.y > o.y + deck - 0.3:
				tgt = o + Vector3(cos(target_a) * (float(hx[3]) - 1.0), 0, sin(target_a) * (float(hx[3]) - 1.0))
			var to := tgt - player.global_position
			player.yaw = atan2(-to.x, -to.z)
			player.test_input = Vector2(0, -1)
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			if OS.has_environment("DBG_SPIRE") and int(t * 60.0) % 120 == 0:
				var hs: Array = []
				for k in player.get_slide_collision_count():
					var col := player.get_slide_collision(k)
					var cob := col.get_collider() as CollisionObject3D
					var sn2 = _shape_node(cob, col.get_collider_shape_index())
					hs.append("%s %s n=%s" % [cob.name if cob else "?", (sn2 as Node3D).global_position.round() - o.round() if sn2 is Node3D else "", col.get_normal().snapped(Vector3.ONE * 0.1)])
				print("[dbg] t=%.0f rel=%s ang=%.2f tgt_a=%.2f hits=%s" % [t, (player.global_position - o).snapped(Vector3.ONE * 0.1), ang, target_a, str(hs)])
			if player.global_position.y > o.y + deck - 0.2 and Vector2(rel.x, rel.z).length() < float(hx[3]):
				top = true
				break
		player.test_input = Vector2.INF
		print("[fantasy] %s stair: reached top deck=%s in %.0fs (y %.1f / deck %.1f)" % [hx[0], top, t, player.global_position.y - o.y, deck])
		all_ok = all_ok and top
	# Treetop Town: up the spiral stair from the roots to the crow's nest,
	# then across a rope bridge to a branch lookout.
	var tt: TreeTown = fz.tree_town
	if tt != null and not tt.helix.is_empty():
		var pts: Array = tt.helix
		player.global_position = (pts[0] as Vector3) + Vector3.UP * 0.6
		player.velocity = Vector3.ZERO
		player.mode = Player.Mode.GROUND
		var t := 0.0
		var idx := 0
		var decks_seen := 0
		var nest := false
		var top_y := tt.o.y + TreeTown.NEST_Y
		while t < 120.0:
			var pp := player.global_position
			while idx < pts.size() - 1 and pp.distance_to(pts[idx]) > pp.distance_to(pts[idx + 1]):
				idx += 1
			var tgt: Vector3 = pts[mini(idx + 2, pts.size() - 1)]
			var to := tgt - pp
			player.yaw = atan2(-to.x, -to.z)
			player.test_input = Vector2(0, -1)
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			for d in TreeTown.DECKS:
				if decks_seen < TreeTown.DECKS.size() and absf(pp.y - (tt.o.y + float(d[0]))) < 0.4 and TreeTown.DECKS.find(d) == decks_seen:
					decks_seen += 1
			if pp.y > top_y - 0.4:
				nest = true
				break
		print("[fantasy] treetown stair: reached crow's nest=%s in %.0fs (y %.1f / %.1f), passed %d decks" % [nest, t, player.global_position.y - tt.o.y, TreeTown.NEST_Y, decks_seen])
		all_ok = all_ok and nest
		if nest:
			var ba: float = float(tt.bridge_angles()[0])
			var dir := Vector3(cos(ba), 0, sin(ba))
			var outer := TreeTown.trunk_r(TreeTown.NEST_Y) + float(TreeTown.DECKS[TreeTown.DECKS.size() - 1][1])
			var way := [tt.o + dir * (outer - 1.5) + Vector3.UP * TreeTown.NEST_Y, tt.o + dir * TreeTown.LOOKOUT_R + Vector3.UP * TreeTown.NEST_Y]
			var wi := 0
			var t2 := 0.0
			var made := false
			while t2 < 40.0:
				var pp := player.global_position
				var tgt: Vector3 = way[wi]
				var to := tgt - pp
				to.y = 0.0
				if to.length() < 1.2:
					if wi == way.size() - 1:
						made = pp.y > top_y - 1.0
						break
					wi += 1
					continue
				player.yaw = atan2(-to.x, -to.z)
				player.test_input = Vector2(0, -1)
				await get_tree().physics_frame
				t2 += get_physics_process_delta_time()
				if OS.has_environment("DBG_SPIRE") and int(t2 * 60.0) % 180 == 0:
					var hs2: Array = []
					for k in player.get_slide_collision_count():
						var col2 := player.get_slide_collision(k)
						hs2.append("n=%s at %s" % [col2.get_normal().snapped(Vector3.ONE * 0.1), (col2.get_position() - tt.o).snapped(Vector3.ONE * 0.1)])
					var rp := pp - tt.o
					print("[dbg] bridge t=%.0f wi=%d r=%.1f ang=%.2f (ba %.2f) y=%.1f hits=%s" % [t2, wi, Vector2(rp.x, rp.z).length(), atan2(rp.z, rp.x), wrapf(ba, -PI, PI), rp.y, str(hs2)])
			print("[fantasy] treetown bridge: reached lookout=%s in %.0fs (y %.1f)" % [made, t2, player.global_position.y - tt.o.y])
			all_ok = all_ok and made
		player.test_input = Vector2.INF
	# Grove: vault cap to cap.
	if fz.poi.has("grove_climb"):
		var climb: Array = fz.poi["grove_climb"]
		var first: Vector3 = climb[0][0]
		var fr: float = climb[0][1]
		var gyv: float = terrain.height_at(first.x, first.z)
		var outward := Vector3(first.x, 0, first.z) - Vector3(climb[climb.size() - 1][0].x, 0, climb[climb.size() - 1][0].z)
		player.global_position = Vector3(first.x, gyv + 0.3, first.z) + outward.normalized() * (fr + 1.6)
		player.velocity = Vector3.ZERO
		var reached := 0
		for k in climb.size():
			var c: Vector3 = climb[k][0]
			var t2 := 0.0
			var got := false
			while t2 < 12.0:
				var to := c - player.global_position
				to.y = 0.0
				player.yaw = atan2(-to.x, -to.z)
				player.test_input = Vector2(0, -1) if to.length() > 0.6 else Vector2.ZERO
				if player.is_on_floor() and to.length() < float(climb[k][1]) + 1.3 and player.global_position.y < c.y - 0.6:
					player.test_jump = true
				await get_tree().physics_frame
				t2 += get_physics_process_delta_time()
				if player.global_position.y > c.y - 0.45 and to.length() < float(climb[k][1]) and player.is_on_floor():
					got = true
					break
			if not got:
				print("[fantasy] grove: stuck before cap %d (top %.1f), player y %.1f" % [k, c.y - gyv, player.global_position.y - gyv])
				break
			reached += 1
		player.test_input = Vector2.INF
		print("[fantasy] grove: climbed %d / %d caps" % [reached, climb.size()])
		all_ok = all_ok and reached == climb.size()
	print("[fantasy] %s" % ("ALL CLIMBABLE" if all_ok else "FAIL"))
	get_tree().quit()


## Every window, door and arch on the map: wherever the wall is visibly
## open, a bullet must pass straight through (both ways), and wherever it
## is visibly solid, a bullet must stop.
func _run_shoot_through_test() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var vil := world.villages
	var space := get_world_3d().direct_space_state
	var raster := {}
	var walls := 0
	var cells_open := 0
	var cells_solid := 0
	var blocked_open := 0
	var leaking_solid := 0
	var reports: Array = []
	var leak_reports: Array = []
	var blockers := {}
	for e in vil.opening_walls:
		var key: String = e[0]
		var xf: Transform3D = e[1]
		var data: Dictionary = vil._model(key)
		var aabb: AABB = data.aabb
		var offset := Vector3(-aabb.get_center().x, -aabb.position.y, -aabb.get_center().z)
		if not raster.has(key):
			var faces: PackedVector3Array = (data.mesh as Mesh).get_faces()
			var grid := {}
			var v := 0.05
			while v < 3.1:
				var u := -0.95
				while u < 0.96:
					var hit := false
					for i in range(0, faces.size(), 3):
						if Geometry3D.segment_intersects_triangle(Vector3(u, v, -1.0) - offset, Vector3(u, v, 1.0) - offset, faces[i], faces[i + 1], faces[i + 2]) != null:
							hit = true
							break
					# Only judge cells well inside open or solid areas (not on an edge).
					grid[Vector2(u, v)] = hit
					u += 0.1
				v += 0.1
			raster[key] = grid
		walls += 1
		var g: Dictionary = raster[key]
		for cell in g:
			var c: Vector2 = cell
			var solid: bool = g[cell]
			# Skip cells within 6 cm of an edge between open and solid.
			var edge := false
			for dd in [Vector2(0.1, 0), Vector2(-0.1, 0), Vector2(0, 0.1), Vector2(0, -0.1)]:
				var nb: Vector2 = (c + dd).snapped(Vector2(0.05, 0.05))
				for k2 in g:
					if (k2 as Vector2).distance_to(c + dd) < 0.01 and bool(g[k2]) != solid:
						edge = true
			if edge:
				continue
			var a := xf * (Vector3(c.x, c.y, -1.6) - offset)
			var b := xf * (Vector3(c.x, c.y, 1.6) - offset)
			var hits_both := 0
			for dir in 2:
				var q := PhysicsRayQueryParameters3D.create(a if dir == 0 else b, b if dir == 0 else a, 1)
				var r := space.intersect_ray(q)
				if not r.is_empty():
					hits_both += 1
					if not solid:
						var body := r["collider"] as CollisionObject3D
						var sn: Node = _shape_node(body, int(r["shape"]))
						var desc := "%s %s" % [body.name if body else "?", str(((sn as CollisionShape3D).shape as BoxShape3D).size.snapped(Vector3.ONE * 0.01)) if sn is CollisionShape3D and (sn as CollisionShape3D).shape is BoxShape3D else (sn as CollisionShape3D).shape.get_class() if sn is CollisionShape3D else ""]
						blockers[desc] = int(blockers.get(desc, 0)) + 1
						if reports.size() < 25:
							reports.append("%s at %s cell (%.2f, %.2f) dir %d blocked by %s at %s" % [key, str(xf.origin.round()), c.x, c.y, dir, desc, str((r["position"] as Vector3).snapped(Vector3.ONE * 0.01))])
			if solid:
				cells_solid += 1
				if hits_both < 2:
					leaking_solid += 1
					if leak_reports.size() < 20:
						leak_reports.append("%s at %s cell (%.2f, %.2f) hits %d" % [key, str(xf.origin.round()), c.x, c.y, hits_both])
			else:
				cells_open += 1
				if hits_both > 0:
					blocked_open += 1
	print("[shootthru] %d opening walls, %d open cells, %d solid cells" % [walls, cells_open, cells_solid])
	print("[shootthru] visibly open but blocked: %d   visibly solid but shot passes: %d" % [blocked_open, leaking_solid])
	for lr in leak_reports:
		print("[shootthru] LEAK ", lr)
	for k in blockers:
		print("[shootthru] blocker ", k, " x", blockers[k])
	for r2 in reports:
		print("[shootthru] ", r2)
	get_tree().quit()


## Cautious armed bots upstairs take a window and watch the street.
func _run_camp_test() -> void:
	_start_match()
	await get_tree().physics_frame
	_land_player_now()
	player.spawn_protect = 9999.0
	for bt in bots:
		if is_instance_valid(bt):
			bt.set_physics_process(false)
	var vil := world.villages
	var bot: Bot = bots[0]
	bot.set_physics_process(true)
	var n := 0
	var camped := 0
	var at_window := 0
	for h in vil.houses:
		if int(h.get("built_levels", 1)) < 2 or n >= 20:
			continue
		n += 1
		var nav := vil.house_nav(h)
		var landing: Vector3 = nav.up[3]
		bot.global_position = landing + Vector3(0, 0.2, 0)
		bot.velocity = Vector3.ZERO
		bot.state = Bot.State.GROUND
		bot.alive = true
		bot.armed = true
		bot.weapon_id = "rifle"
		bot.aggression = 0.0
		bot.enemy = null
		bot.loot_target = null
		bot._loot_scan = 99.0
		bot._camp_t = 0.0
		bot._camp_cool = 0.0
		bot._route.clear()
		bot._route_goal = Vector3.INF
		# Keep it in the zone so it has no reason to leave.
		zone.center = Vector2(landing.x, landing.z)
		var t := 0.0
		var ok_camp := false
		while t < 8.0:
			bot._loot_scan = 99.0
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			if bot._camp_t > 0.0:
				ok_camp = true
		if ok_camp:
			camped += 1
			var fwd := -bot.global_basis.z
			var p0 := bot.global_position + Vector3.UP * 1.5
			var q := PhysicsRayQueryParameters3D.create(p0, p0 + fwd * 2.5, 1)
			var clear := get_world_3d().direct_space_state.intersect_ray(q).is_empty()
			var close := Vector2(bot.global_position.x - bot._camp_pos.x, bot.global_position.z - bot._camp_pos.z).length() < 0.6
			if clear and close and bot.global_position.y > float(nav.floor_y) - 0.4:
				at_window += 1
			else:
				print("[camp] miss house %s: close=%s clear=%s y=%.1f floor=%.1f" % [str(h.center.round()), close, clear, bot.global_position.y, float(nav.floor_y)])
	print("[camp] %d houses: %d took a window, %d standing at it looking out" % [n, camped, at_window])
	get_tree().quit()


## A bot walks in through the door, up the stairs to loot on the upper
## floor, picks it up, then walks back down and out to the street.
## Gunfire as heard in the game, for the record (run with --write-movie):
## your own gun, then the same gun at growing distances, one every 5 s.
func _run_gun_audio_test() -> void:
	var cls := "ak"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--gun="):
			cls = a.substr(6)
	music.set_volumes(0.0, 0.0)
	await get_tree().create_timer(1.0).timeout
	var cam := get_viewport().get_camera_3d()
	var ear := cam.global_position if cam != null else Vector3.ZERO
	var fwd := -cam.global_basis.z if cam != null else Vector3.FORWARD
	fwd.y = 0.0
	fwd = fwd.normalized()
	print("[gunaudio] t=%.1f own" % (Time.get_ticks_msec() / 1000.0))
	for k in 3:
		play_own_gunshot(cls)
		await get_tree().create_timer(0.11).timeout
	await get_tree().create_timer(4.0).timeout
	for d in [5.0, 30.0, 80.0, 200.0, 400.0, 800.0, 1200.0]:
		print("[gunaudio] t=%.1f d=%d" % [Time.get_ticks_msec() / 1000.0, int(d)])
		_play_gunshot(cls, ear + fwd * d, 0.85)
		await get_tree().create_timer(5.0 + d / SOUND_SPEED).timeout
	get_tree().quit()


## A bot climbs Treetop Town for loot on each deck, then comes back down.
func _run_bot_tree_test() -> void:
	_start_match()
	await get_tree().physics_frame
	_land_player_now()
	player.spawn_protect = 9999.0
	player.global_position = Vector3(0, terrain.height_at(0, 0) + 300.0, 0)
	for bt in bots:
		if is_instance_valid(bt):
			bt.set_physics_process(false)
	if zone != null:
		zone.set_process(false)
	var tt: TreeTown = world.villages.landmarks.fantasy.tree_town
	if tt == null:
		print("[bottree] no tree town on this island")
		get_tree().quit()
		return
	var b: Bot = bots[0]
	b.state = Bot.State.GROUND
	b.arm_weapon("rifle")
	b.calm_t = 99.0
	b.test_hold_roam = true
	b.set_physics_process(true)
	var ok := 0
	for di in 3:
		var dy: float = float(TreeTown.DECKS[di][0])
		# Loot inside a hut on that deck, like the town's own.
		var lp := Vector3.ZERO
		for h in tt.huts:
			if absf(float(h.level) - dy) < 0.5:
				lp = tt.o + Vector3(cos(float(h.a)) * float(h.r), dy + 0.1, sin(float(h.a)) * float(h.r))
				break
		var l := _spawn_loot("med", "", lp)
		b.global_position = ground_at((tt.helix[0] as Vector3) + Vector3(3.0, 2.0, 0.0)) + Vector3.UP * 0.1
		b.velocity = Vector3.ZERO
		b.meds = 0
		b.loot_target = l
		b._last_loot_d = 9999.0
		b._skip_loot.clear()
		var t := 0.0
		var top := -INF
		while t < 180.0 and not l.taken:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			top = maxf(top, b.global_position.y - tt.o.y)
			if b.loot_target != l and not l.taken:
				b.loot_target = l
		print("[bottree] deck %d (%.0f m): took loot=%s in %.0fs (highest %.1f m)" % [di + 1, dy, l.taken, t, top])
		if l.taken:
			ok += 1
	# Back down to the ground.
	var gp := tt.o + Vector3(TreeTown.LOOKOUT_R + 20.0, 0, 0)
	b.roam_point = Vector2(gp.x, gp.z)
	b.loot_target = null
	var t2 := 0.0
	while t2 < 180.0 and b.global_position.y > tt.o.y + 2.0:
		await get_tree().physics_frame
		t2 += get_physics_process_delta_time()
	var down := b.global_position.y < tt.o.y + 2.0
	var bp := b.global_position
	print("[bottree] came back down=%s in %.0fs (ended y %.1f a %.2f r %.1f route %d tactic '%s' enemy %s)" % [down, t2, bp.y - tt.o.y, tt.angle_of(bp), Vector2(bp.x - tt.o.x, bp.z - tt.o.z).length(), b._route.size(), b._tactic, b.enemy != null])
	print("[bottree] ", "ALL GOOD" if ok == 3 and down else "FAILED")
	get_tree().quit()


## Do trees stop exactly the bullets their wood would? Each sampled tree gets
## its real bark as a reference shape, and its trunk alone as another (on
## layers nothing else uses); rays across the trunk at heights up to 10 m
## compare what they hit: the tree collider with no wood there is an invisible
## wall, a trunk with no collider lets shots through (limbs are allowed to).
func _run_tree_shoot_test() -> void:
	await get_tree().physics_frame
	var ref := StaticBody3D.new()
	ref.collision_layer = 1 << 9
	ref.collision_mask = 0
	add_child(ref)
	var ref_trunk := StaticBody3D.new()
	ref_trunk.collision_layer = 1 << 10
	ref_trunk.collision_mask = 0
	add_child(ref_trunk)
	var per_species := {}
	var trees: Array = []
	var trunk_shapes := {}
	# Neighbours get reference wood too: their trunks can stand on a ray.
	var cells := {}
	for i in world.tree_records.size():
		var rp: Vector3 = world.tree_records[i].pos
		var ck := Vector2i(floori(rp.x / 10.0), floori(rp.z / 10.0))
		if not cells.has(ck):
			cells[ck] = []
		(cells[ck] as Array).append(i)
	var added := {}
	var closest := INF
	for i in world.tree_records.size():
		var rec: Dictionary = world.tree_records[i]
		var species := str(rec.name)
		var n := int(per_species.get(species, 0))
		if n >= 40 or randf() > 0.08:
			continue
		var others: Array = []
		trees.append([species, Transform3D(Basis(Vector3.UP, float(rec.rot)).scaled(Vector3.ONE * float(rec.scale)), rec.pos), others])
		per_species[species] = n + 1
		var ck := Vector2i(floori(rec.pos.x / 10.0), floori(rec.pos.z / 10.0))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for j: int in cells.get(ck + Vector2i(dx, dz), []):
					var other: Dictionary = world.tree_records[j]
					var dist := Vector2(other.pos.x - rec.pos.x, other.pos.z - rec.pos.z).length()
					if j != i:
						var ofoot := float(world.TRUNK_FOOT[str(other.name)]) * float(other.scale)
						closest = minf(closest, dist - (ofoot + float(world.TRUNK_FOOT[species]) * float(rec.scale)))
						others.append(Vector3(other.pos.x, ofoot + 0.3, other.pos.z))
					if added.has(j) or dist > 9.5:
						continue
					added[j] = true
					var osp := str(other.name)
					var xf := Transform3D(Basis(Vector3.UP, float(other.rot)).scaled(Vector3.ONE * float(other.scale)), other.pos)
					var cs := CollisionShape3D.new()
					var refshape := world._mesh_shape(osp, "Bark").duplicate() as ConcavePolygonShape3D
					# Either side of a face counts: the kit's bark is not wound
					# consistently, and a miss on a back face is not a gap in the wood.
					refshape.backface_collision = true
					cs.shape = refshape
					cs.transform = xf
					ref.add_child(cs)
					if not trunk_shapes.has(osp):
						trunk_shapes[osp] = world._trunk_shape(osp)
					var ts := CollisionShape3D.new()
					ts.shape = trunk_shapes[osp]
					ts.transform = xf
					ref_trunk.add_child(ts)
	print("[treeshoot] %d trees sampled; the tightest gap between roots near them is %.2f m" % [trees.size(), closest])
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var heights := [0.5, 1.2, 2.0, 3.0, 4.5, 6.0, 8.0, 10.0]
	var stats := {}
	var bad := 0
	for tr in trees:
		var species: String = tr[0]
		var xf: Transform3D = tr[1]
		var sc := xf.basis.get_scale().x
		var st: Dictionary = stats.get(species, {"rays": 0, "wall": 0, "through": 0, "limb": 0, "wall_h": {}, "through_h": {}, "all_h": {}, "ok": 0})
		for h in heights:
			for di in 6:
				var a := TAU * float(di) / 6.0
				var d := Vector3(cos(a), 0, sin(a))
				var side := Vector3(-d.z, 0, d.x)
				for off in [-0.6, -0.3, 0.0, 0.3, 0.6]:
					var c: Vector3 = xf.origin + Vector3.UP * (float(h) + 0.25) + side * float(off) * sc * 0.5
					# Short enough that a neighbouring tree (7.6 m or more away)
					# is never on the ray: only this tree's wood and collider.
					var from: Vector3 = c - d * 3.0
					var to: Vector3 = c + d * 3.0
					# Not from inside a neighbour's trunk: a solid has no inside
					# face to hit, the bark reference does.
					var inside := false
					for o: Vector3 in tr[2]:
						if Vector2(from.x - o.x, from.z - o.z).length() < o.y or Vector2(to.x - o.x, to.z - o.z).length() < o.y:
							inside = true
							break
					if inside:
						continue
					var vis := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1 << 9))
					var trk := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1 << 10))
					var phy := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
					var phy_tree: bool = not phy.is_empty() and str((phy["collider"] as Node).name) == "TreeCollision"
					if phy.is_empty() and vis.is_empty():
						continue
					st["rays"] = int(st["rays"]) + 1
					var dv: float = from.distance_to(vis["position"]) if not vis.is_empty() else INF
					var dt: float = from.distance_to(trk["position"]) if not trk.is_empty() else INF
					var dp: float = from.distance_to(phy["position"]) if not phy.is_empty() else INF
					if phy_tree and dp + 0.25 < dv:
						st["wall"] = int(st["wall"]) + 1
						var gap := dv - dp
						var gk := "<0.5m" if gap < 0.5 else ("0.5-1m" if gap < 1.0 else ("1-3m" if gap < 3.0 else "no wood on the ray"))
						st[gk] = int(st.get(gk, 0)) + 1
						var wh: Dictionary = st["wall_h"]
						wh[h] = int(wh.get(h, 0)) + 1
						# How far outside the wood did it stop the shot? Slide
						# the ray sideways until bark is where the collider was.
						var pp: Vector3 = phy["position"]
						var lat := 99.0
						for k in range(1, 26):
							for sg in [-1.0, 1.0]:
								var sh: Vector3 = side * float(sg) * 0.02 * float(k)
								var v2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(from + sh, to + sh, 1 << 9))
								if not v2.is_empty() and (v2["position"] as Vector3).distance_to(pp + sh) < 0.3:
									lat = minf(lat, 0.02 * float(k))
							if lat < 99.0:
								break
						var lk := "lat<=4cm" if lat <= 0.041 else ("lat<=8cm" if lat <= 0.081 else ("lat<=14cm" if lat <= 0.141 else ("lat<=30cm" if lat <= 0.301 else "lat>30cm")))
						st[lk] = int(st.get(lk, 0)) + 1
						if lat > 0.141 and OS.get_cmdline_user_args().has("--verbose-walls") and int(st.get("lat>30cm", 0)) <= 6:
							var lp: Vector3 = xf.affine_inverse() * pp
							var near := INF
							for rec2 in world.tree_records:
								var d2 := Vector2(rec2.pos.x - pp.x, rec2.pos.z - pp.z).length()
								if d2 > 0.01 and (Vector3(rec2.pos) - xf.origin).length() > 0.05:
									near = minf(near, d2)
							print("[treeshoot]   wall %s sc %.2f h %.1f off %.1f dir %d: hit local %s r %.2f shape %d, nearest other tree %.2f m from the hit" % [species, sc, float(h), float(off), di, str(lp.snapped(Vector3.ONE * 0.01)), Vector2(lp.x, lp.z).length(), int(phy["shape"]), near])
						if lat > 0.081:
							var bh: Dictionary = st.get("big_h", {})
							bh[h] = int(bh.get(h, 0)) + 1
							st["big_h"] = bh
					elif dt < INF and dp > dt + 0.25:
						st["through"] = int(st["through"]) + 1
						var th: Dictionary = st["through_h"]
						th[h] = int(th.get(h, 0)) + 1
					elif dv < INF and dp > dv + 0.25:
						st["limb"] = int(st["limb"]) + 1
					else:
						st["ok"] = int(st["ok"]) + 1
					var ah: Dictionary = st["all_h"]
					ah[h] = int(ah.get(h, 0)) + 1
		stats[species] = st
	for sp in stats:
		var st: Dictionary = stats[sp]
		print("[treeshoot] %s: trunk in %d slabs" % [sp, (world._hull_cache.get(sp, []) as Array).size()])
		print("[treeshoot] %s: %d rays near wood, invisible wall %d (%.1f%%), shot through the trunk %d (%.1f%%), through a limb %d  wall gaps: <0.5m %d, 0.5-1m %d, 1-3m %d, nothing there %d" % [sp, st.rays, st.wall, 100.0 * st.wall / maxf(1, st.rays), st.through, 100.0 * st.through / maxf(1, st.rays), st.limb, int(st.get("<0.5m", 0)), int(st.get("0.5-1m", 0)), int(st.get("1-3m", 0)), int(st.get("no wood on the ray", 0))])
		# By height: a trunk that lets shots through at head height is no cover.
		var line := ""
		for h in heights:
			var n_all := int((st["all_h"] as Dictionary).get(h, 0))
			var w := int((st["wall_h"] as Dictionary).get(h, 0))
			var t := int((st["through_h"] as Dictionary).get(h, 0))
			line += "  %.1fm %d/%d/%d" % [h, w, t, n_all]
			# Up to head height the trunk has to be the cover it looks like.
			# (A collider within 8 cm of the bark is the bark, to the eye.)
			var big := int((st.get("big_h", {}) as Dictionary).get(h, 0))
			if float(h) <= 3.0 and n_all > 0 and (float(t) > 0.01 * n_all or float(big) > 0.01 * n_all):
				bad += 1
		print("[treeshoot]    height wall/through/rays:", line)
		print("[treeshoot]    walls stand off the wood by: <=4cm %d, <=8cm %d, <=14cm %d, <=30cm %d, more %d   (over 8 cm by height: %s)" % [int(st.get("lat<=4cm", 0)), int(st.get("lat<=8cm", 0)), int(st.get("lat<=14cm", 0)), int(st.get("lat<=30cm", 0)), int(st.get("lat>30cm", 0)), str(st.get("big_h", {}))])
	if closest < 1.0:
		bad += 1
	print("[treeshoot] ", "ALL GOOD" if bad == 0 and not stats.is_empty() else "FAILED: %d species-heights leak or wall (or trees crowd)" % bad)
	get_tree().quit()


## A bot against you (standing still, kept alive): how soon and how hard it
## hits you in the open, and what it does when you hide behind a trunk.
func _run_bot_vs_player_test() -> void:
	_start_match()
	await get_tree().physics_frame
	_land_player_now()
	for bt in bots:
		if is_instance_valid(bt):
			bt.set_physics_process(false)
	if zone != null:
		zone.set_process(false)
	var tcol := world.get_node_or_null("TreeCollision")
	var rr := RandomNumberGenerator.new()
	rr.seed = 5
	for scen in ["open", "open", "behind tree", "behind tree"]:
		# Somewhere grassy; for cover, right behind a trunk. The bot goes 45 m
		# away where it can see you (in the tree case: see you beside the
		# trunk, with the same low ray it aims along, but not once you step
		# behind it).
		var space := get_world_3d().direct_space_state
		var pp := Vector3.ZERO
		var side_pos := Vector3.ZERO
		var bdir := Vector3.ZERO
		for attempt in 60:
			var c := Vector3.ZERO
			var hide_dir := Vector3.ZERO
			for tries in 2000:
				var x := rr.randf_range(-900.0, 900.0)
				var z := rr.randf_range(-900.0, 900.0)
				if terrain.height_at(x, z) < Terrain.WATER_LEVEL + 2.0 or terrain.slope_at(x, z) > 0.2:
					continue
				if scen == "open":
					if terrain.forest_density(x, z) < 0.35:
						c = Vector3(x, 0, z)
						break
				elif tcol != null:
					var rec: Dictionary = world.tree_records[rr.randi() % world.tree_records.size()]
					var tp: Vector3 = rec.pos
					if terrain.slope_at(tp.x, tp.z) < 0.2 and terrain.height_at(tp.x, tp.z) > Terrain.WATER_LEVEL + 2.0:
						var rad := 0.42 * float(rec.scale)
						var ha := rr.randf() * TAU
						hide_dir = Vector3(cos(ha), 0, sin(ha))
						c = Vector3(tp.x, 0, tp.z) + hide_dir * (rad + 0.5)
						break
			pp = ground_at(Vector3(c.x, terrain.height_at(c.x, c.z) + 2.0, c.z))
			side_pos = pp
			if scen != "open":
				var sp := pp + Vector3(-hide_dir.z, 0, hide_dir.x) * 2.2
				side_pos = ground_at(Vector3(sp.x, terrain.height_at(sp.x, sp.z) + 2.0, sp.z))
			bdir = Vector3.ZERO
			for k in 36:
				var a := rr.randf() * TAU
				var dtry := Vector3(cos(a), 0, sin(a))
				if scen != "open":
					dtry = (-hide_dir).rotated(Vector3.UP, rr.randf_range(-0.35, 0.35))
				var bq := pp + dtry * 45.0
				var btry := ground_at(Vector3(bq.x, terrain.height_at(bq.x, bq.z) + 3.0, bq.z))
				if btry.y < Terrain.WATER_LEVEL + 1.0:
					continue
				var eye := btry + Vector3.UP * 1.3
				var see_side := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, side_pos + Vector3.UP * 1.2, 1)).is_empty() \
					and space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, side_pos + Vector3.UP * 0.7, 1)).is_empty()
				var see_hide := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, pp + Vector3.UP * 0.9, 1)).is_empty()
				if see_side and (scen == "open" or not see_hide):
					bdir = dtry
					break
			if bdir != Vector3.ZERO:
				break
		if bdir == Vector3.ZERO:
			print("[botvsyou] %s: no spot with a clear view, skipped" % scen)
			continue
		player.global_position = pp + Vector3.UP * 0.1
		player.velocity = Vector3.ZERO
		player.spawn_protect = 0.0
		player.alive = true
		player.hp = 100.0
		player.vest_level = 0
		player.helmet_level = 0
		player.test_input = Vector2.ZERO
		player.test_hold = {"crouch": true} if scen != "open" else {}
		if scen != "open":
			player.global_position = side_pos + Vector3.UP * 0.1
		var b: Bot = bots[0]
		var bq2 := pp + bdir * 45.0
		var bp := ground_at(Vector3(bq2.x, terrain.height_at(bq2.x, bq2.z) + 3.0, bq2.z))
		b.global_position = bp + Vector3.UP * 0.1
		b.state = Bot.State.GROUND
		b.velocity = Vector3.ZERO
		b.arm_weapon("rifle")
		b.mag = 30
		b.grenades = 2
		b.hp = 100.0
		b.alive = true
		b.calm_t = 0.0
		b.aggression = 0.6
		b.shoot_skill = 0.5
		b.reset_combat()
		b._loot_scan = 1.0e9
		b.loot_target = null
		b.test_hold_roam = true
		b.roam_point = Vector2(bp.x, bp.z)
		var to := pp - bp
		b.rotation.y = atan2(-to.x, -to.z)
		b.set_physics_process(true)
		var t := 0.0
		var dmg := 0.0
		var hits := 0
		var first := -1.0
		var seen := {}
		var nades0 := b.grenades
		var shots := 0
		var last_mag := b.mag
		var vis_n := 0
		var n := 0
		while t < 45.0:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			if scen != "open" and t > 2.0 and t - get_physics_process_delta_time() <= 2.0:
				# Seen: now duck behind the trunk.
				player.global_position = pp + Vector3.UP * 0.1
			if b.mag < last_mag:
				shots += last_mag - b.mag
			last_mag = b.mag
			if OS.has_environment("DBG_BVY") and int(t * 60.0) % 180 == 0:
				print("[bvydbg] %s t=%.0f bot->you %.1f m  tactic=%s last_seen=%s (%.1f m from you) hidden_t=%.1f route=%d stuck=%d" % [scen, t, b.global_position.distance_to(player.global_position), b._tactic, str(b._last_seen.round()) if b._last_seen != Vector3.INF else "-", b._last_seen.distance_to(player.global_position) if b._last_seen != Vector3.INF else -1.0, b._hidden_t, b._route.size(), b._stuck_n])
			n += 1
			if b.enemy == player and b.enemy_visible():
				vis_n += 1
			if player.hp < 100.0:
				dmg += 100.0 - player.hp
				hits += 1
				if first < 0.0:
					first = t
				player.hp = 100.0
			if not player.alive:
				player.alive = true
				player.hp = 100.0
			if int(t * 60.0) % 15 == 0:
				var tac: String = b._tactic if b._tactic != "" else ("open" if b.enemy != null else "idle")
				seen[tac] = int(seen.get(tac, 0)) + 1
		print("[botvsyou] %s: first hit after %s, %d hits / %d shots, %.0f damage/min, sees you %d%% of the time, range %.0f m, grenades thrown %d, tactics %s" % [scen, ("%.1fs" % first) if first >= 0.0 else "never", hits, shots, dmg / t * 60.0, int(100.0 * vis_n / maxf(1.0, n)), b.global_position.distance_to(player.global_position), nades0 - b.grenades, str(seen)])
		b.set_physics_process(false)
		b.global_position = Vector3(0, -500, 0)
	player.test_hold = {}
	get_tree().quit()


## Bot against bot in the woods: do they take cover, lean out to shoot,
## duck back to reload, push, flank and use grenades? Five duels.
func _run_botfight_test() -> void:
	_start_match()
	await get_tree().physics_frame
	_land_player_now()
	player.spawn_protect = 9999.0
	player.global_position = Vector3(0, terrain.height_at(0, 0) + 300.0, 0)
	for bt in bots:
		if is_instance_valid(bt):
			bt.set_physics_process(false)
	if zone != null:
		zone.set_process(false)
	var rr := RandomNumberGenerator.new()
	rr.seed = 99
	var totals := {}
	var wins := 0
	var nades := 0
	for duel in 5:
		# A spot in the woods with room for a firefight.
		var c := Vector3.ZERO
		for tries in 400:
			var x := rr.randf_range(-900.0, 900.0)
			var z := rr.randf_range(-900.0, 900.0)
			if terrain.forest_density(x, z) > 0.62 and terrain.height_at(x, z) > Terrain.WATER_LEVEL + 2.0 and terrain.slope_at(x, z) < 0.25:
				c = Vector3(x, 0, z)
				break
		var ang := rr.randf() * TAU
		var dir := Vector3(cos(ang), 0, sin(ang))
		var pair: Array = []
		for k in 2:
			var b: Bot = bots[duel * 2 + k]
			var p := ground_at(c + dir * (18.0 if k == 0 else -18.0) + Vector3.UP * 2.0)
			b.global_position = p + Vector3.UP * 0.1
			b.state = Bot.State.GROUND
			b.velocity = Vector3.ZERO
			b.arm_weapon("rifle")
			b.mag = 30
			b.meds = 2
			b.grenades = 2
			b.hp = 100.0
			b.calm_t = 0.0
			b.aggression = 0.6
			b.test_hold_roam = true
			b.roam_point = Vector2(p.x, p.z)
			var to := (c - p)
			b.rotation.y = atan2(-to.x, -to.z)
			b.set_physics_process(true)
			pair.append(b)
		var t := 0.0
		var seen := {}
		var nade0: int = int(pair[0].grenades) + int(pair[1].grenades)
		while t < 90.0 and pair[0].alive and pair[1].alive:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			if int(t * 60.0) % 15 == 0:
				for b in pair:
					var tac: String = b._tactic if b._tactic != "" else ("open" if b.enemy != null else "idle")
					seen[tac] = int(seen.get(tac, 0)) + 1
		var used: int = nade0 - int(pair[0].grenades) - int(pair[1].grenades)
		nades += used
		var won: bool = pair[0].alive != pair[1].alive
		if won:
			wins += 1
		print("[botfight] duel %d: %s after %.0fs  hp %d / %d  grenades thrown %d  tactics %s" % [duel, "decided" if won else "no winner", t, int(pair[0].hp), int(pair[1].hp), used, str(seen)])
		for k in seen:
			totals[k] = int(totals.get(k, 0)) + int(seen[k])
		for b in pair:
			b.set_physics_process(false)
			b.global_position = Vector3(0, -500, 0)
	var all := 0
	for k in totals:
		all += int(totals[k])
	var share := {}
	for k in totals:
		share[k] = "%d%%" % int(100.0 * float(totals[k]) / maxf(1.0, float(all)))
	print("[botfight] %d / 5 duels decided, %d grenades, time share %s" % [wins, nades, str(share)])
	get_tree().quit()


## Bodies come down: killed mid-jump, high up or as a LAN puppet whose last
## update left it in the air, every body ends on the ground.
func _run_corpse_test() -> void:
	_start_match()
	await get_tree().physics_frame
	_land_player_now()
	player.spawn_protect = 9999.0
	for bt in bots:
		if is_instance_valid(bt):
			bt.set_physics_process(false)
	if zone != null:
		zone.set_process(false)
	var fails := 0
	var cases := [["mid-jump", 6.0, 0.4], ["thrown", 9.0, 3.0], ["ledge", 0.0, 7.0], ["puppet", 0.0, 6.0]]
	for i in cases.size():
		var c: Array = cases[i]
		var b: Bot = bots[i]
		var spot := _random_ground_point(300.0)
		b.state = Bot.State.GROUND
		b.global_position = spot + Vector3.UP * float(c[2])
		b.velocity = Vector3(0.0, float(c[1]), 0.0)
		b.set_physics_process(true)
		await get_tree().physics_frame
		if c[0] == "puppet":
			b.puppet = true
			b.puppet_die()
		else:
			b.take_damage(9999.0, b.global_position, false, null)
		var top := b.global_position.y
		for k in 300:
			await get_tree().physics_frame
			top = maxf(top, b.global_position.y)
		var g := ground_at(Vector3(b.global_position.x, spot.y + 2.0, b.global_position.z)).y
		var dy := b.global_position.y - g
		var ok := absf(dy) < 0.6 and not b.alive
		if not ok:
			fails += 1
		print("[corpse] %s: above ground %.2f m after 5 s (highest %.1f m over the ground) %s" % [c[0], dy, top - g, "ok" if ok else "FAIL"])
		if not ok:
			# What is the body lying on?
			var sp := get_world_3d().direct_space_state
			var bq := PhysicsShapeQueryParameters3D.new()
			var ball := SphereShape3D.new()
			ball.radius = 0.6
			bq.shape = ball
			bq.transform = Transform3D(Basis.IDENTITY, b.global_position)
			bq.collision_mask = 1 | 4
			bq.exclude = [b.get_rid()]
			for hit in sp.intersect_shape(bq, 8):
				var co: Object = hit["collider"]
				var sn = _shape_node(co as CollisionObject3D, int(hit["shape"])) if co is CollisionObject3D else null
				print("[corpse]   touching %s %s near %s" % [co.name if co is Node else str(co), str((sn as CollisionShape3D).shape) if sn is CollisionShape3D else "", _place_name(b.global_position)])
			print("[corpse]   at %s" % str(b.global_position.snapped(Vector3.ONE * 0.01)))
	print("[corpse] ", "ALL GOOD" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()


func _run_bot_stairs_test() -> void:
	_start_match()
	await get_tree().physics_frame
	_land_player_now()
	player.spawn_protect = 9999.0
	player.global_position = Vector3(0, terrain.height_at(0, 0) + 1.0, 0)
	for bt in bots:
		if is_instance_valid(bt):
			bt.set_physics_process(false)
	if zone != null:
		zone.set_process(false)
	var vil := world.villages
	var bot: Bot = bots[0]
	bot.set_physics_process(true)
	bot.test_hold_roam = true
	var up_ok := 0
	var down_ok := 0
	var n := 0
	var fails: Array = []
	var limit := 40
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--limit="):
			limit = int(a.substr(8))
	for h in vil.houses:
		if int(h.get("built_levels", 1)) < 2 or n >= limit:
			continue
		var nav := vil.house_nav(h)
		var hc: Vector2 = h.center
		var lp: LootPickup = null
		for l in loot_pool:
			var lo := l as LootPickup
			if lo == null or lo.taken or not is_instance_valid(lo):
				continue
			if lo.global_position.y > float(nav.floor_y) - 0.5 and vil.house_at(Vector2(lo.global_position.x, lo.global_position.z), -0.3) == h:
				lp = lo
				break
		if lp == null:
			continue
		n += 1
		var o: Vector3 = nav.out
		var nrm := (o - (nav["in"] as Vector3))
		nrm.y = 0.0
		nrm = nrm.normalized()
		bot.global_position = o + nrm * 3.0 + Vector3(0, 0.3, 0)
		bot.velocity = Vector3.ZERO
		bot.state = Bot.State.GROUND
		bot.alive = true
		bot.hp = 100.0
		bot.armed = false
		bot.enemy = null
		bot.loot_target = lp
		bot._skip_loot.clear()
		bot._route.clear()
		bot._route_goal = Vector3.INF
		var t := 0.0
		while t < 35.0 and not lp.taken:
			bot.loot_target = lp if not lp.taken else null
			bot._loot_scan = 99.0
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		var got := lp.taken
		if got:
			up_ok += 1
		# Now send it back out to the street.
		var street: Vector3 = o + nrm * 6.0
		bot.loot_target = null
		bot.armed = true
		bot.enemy = null
		bot.roam_point = Vector2(street.x, street.z)
		var t2 := 0.0
		var out_ok := false
		while t2 < 35.0:
			bot.roam_point = Vector2(street.x, street.z)
			bot._roam_wait = 99.0
			bot.enemy = null
			await get_tree().physics_frame
			t2 += get_physics_process_delta_time()
			if vil.house_at(Vector2(bot.global_position.x, bot.global_position.z), 0.3) != h and bot.global_position.distance_to(street) < 4.0:
				out_ok = true
				break
		if out_ok:
			down_ok += 1
		if not got or not out_ok:
			var local := Basis(Vector3.UP, float(h.yaw)).inverse() * (bot.global_position - Vector3(hc.x, float(h.pad), hc.y))
			var hits: Array = []
			for k in bot.get_slide_collision_count():
				var c := bot.get_slide_collision(k)
				var cob := c.get_collider() as CollisionObject3D
				if cob == null:
					continue
				var sn = _shape_node(cob, c.get_collider_shape_index())
				var hb := Basis(Vector3.UP, float(h.yaw)).inverse()
				hits.append("%s@%s" % [cob.name, str((hb * ((sn as Node3D).global_position - Vector3(hc.x, float(h.pad), hc.y))).snapped(Vector3.ONE * 0.01)) if sn is Node3D else "?"])
			fails.append("%dx%d door %d at %s: up=%s (%.0fs) out=%s, bot local %s vel %s route=%d hits %s" % [int(h.w), int(h.d), int(h.door_side), str(Vector3(hc.x, float(h.pad), hc.y).round()), got, t, out_ok, str(local.snapped(Vector3.ONE * 0.1)), str(bot.velocity.snapped(Vector3.ONE * 0.1)), bot._route.size(), str(hits)])
	print("[botstairs] %d houses: %d looted upstairs, %d walked back out" % [n, up_ok, down_ok])
	for f in fails.slice(0, 20):
		print("[botstairs] FAIL ", f)
	get_tree().quit()


func _run_house_walk_test() -> void:
	_start_match()
	await get_tree().physics_frame
	_land_player_now()
	for bt in bots:
		if is_instance_valid(bt):
			bt.set_physics_process(false)
	if zone != null:
		zone.set_process(false)
	var vil := world.villages
	var ok := 0
	var fails: Array = []
	var n := 0
	for h in vil.houses:
		var w := float(h.w)
		var d := float(h.d)
		var o := Vector3(h.center.x, h.pad, h.center.y)
		var b := Basis(Vector3.UP, float(h.yaw))
		var side := int(h.door_side)
		var cells := int(w * 0.5) if side % 2 == 0 else int(d * 0.5)
		var along := -((cells - 1) * 0.5) * 2.0 + float(cells / 2) * 2.0
		var door := Vector3.ZERO
		var nrm := Vector3.ZERO
		match side:
			0:
				door = Vector3(along, 0, d * 0.5)
				nrm = Vector3(0, 0, 1)
			1:
				door = Vector3(w * 0.5, 0, along)
				nrm = Vector3(1, 0, 0)
			2:
				door = Vector3(-along, 0, -d * 0.5)
				nrm = Vector3(0, 0, -1)
			3:
				door = Vector3(-w * 0.5, 0, -along)
				nrm = Vector3(-1, 0, 0)
		var two := int(h.get("built_levels", 1)) > 1
		var pts: Array = [door + nrm * 1.2, door - nrm * 1.3]
		if two:
			var foot := vil.stair_foot_z(d)
			var sx := w * 0.5 - 1.1
			pts.append(Vector3(sx - 1.0, 0, foot + 0.45))
			pts.append(Vector3(sx, 0, foot + 0.45))
			pts.append(Vector3(sx, 0, foot - 4.58 + 0.4))
			# Step off the top of the flight onto the upstairs floor.
			pts.append(Vector3(sx - 1.6, 0, foot - 4.58 + 0.3))
		else:
			pts.append(Vector3(0, 0, 0))
		player.alive = true
		player.hp = 100.0
		player.spawn_protect = 999.0
		player.mode = Player.Mode.GROUND
		player.velocity = Vector3.ZERO
		player.global_position = o + b * (door + nrm * 2.4) + Vector3(0, 0.3, 0)
		for i in 5:
			await get_tree().physics_frame
		var wi := 0
		var frames := 0
		while wi < pts.size() and frames < 900:
			var target: Vector3 = o + b * pts[wi]
			var to := target - player.global_position
			to.y = 0.0
			if to.length() < 0.35:
				wi += 1
				continue
			player.yaw = atan2(-to.x, -to.z)
			player.test_input = Vector2(0, -1)
			await get_tree().physics_frame
			frames += 1
		var hits_h: Array = []
		for k in player.get_slide_collision_count():
			var c2 := player.get_slide_collision(k)
			var shp2 = c2.get_collider_shape()
			if shp2 is CollisionShape3D:
				var cs4 := shp2 as CollisionShape3D
				hits_h.append("%s@%s %s" % [str((c2.get_collider() as Node).name), str((b.inverse() * (cs4.global_position - o)).snapped(Vector3.ONE * 0.01)), str((cs4.shape as BoxShape3D).size.snapped(Vector3.ONE * 0.01) if cs4.shape is BoxShape3D else "")])
		player.test_input = Vector2.INF
		# What is actually touching the capsule (slide shape ids can mislead).
		var qs := PhysicsShapeQueryParameters3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.42
		cap.height = 1.9
		qs.shape = cap
		qs.transform = Transform3D(Basis(), player.global_position + Vector3(0, 0.95, 0))
		qs.exclude = [player.get_rid()]
		for r in player.get_world_3d().direct_space_state.intersect_shape(qs, 8):
			var body := r["collider"] as CollisionObject3D
			if body == null:
				continue
			var sn := _shape_node(body, int(r["shape"])) as CollisionShape3D
			if sn != null:
				hits_h.append("Q:%s@%s %s" % [str(body.name), str((b.inverse() * (sn.global_position - o)).snapped(Vector3.ONE * 0.01)), str((sn.shape as BoxShape3D).size.snapped(Vector3.ONE * 0.01) if sn.shape is BoxShape3D else "")])
		var inside := (b.inverse() * (player.global_position - o))
		var good := wi >= pts.size() and absf(inside.x) < w * 0.5 and absf(inside.z) < d * 0.5
		if two:
			good = good and player.global_position.y - o.y > Villages.WALL_HEIGHT - 0.35
		n += 1
		if good:
			ok += 1
		else:
			fails.append("%s%dx%d door side %d at %s: waypoint %d/%d, local %s hits %s" % ["2F " if two else "", int(w), int(d), side, str(o.round()), wi, pts.size(), str(inside.snapped(Vector3.ONE * 0.1)), str(hits_h)])
	print("[houses] %d / %d houses entered through the door%s" % [ok, n, " (and climbed)" if true else ""])
	for f in fails.slice(0, 25):
		print("[houses] FAIL ", f)
	get_tree().quit()
