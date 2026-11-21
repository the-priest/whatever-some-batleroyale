class_name Guide
extends Node3D
## Souls Mode's guidance: an ember wisp that flies ahead to the next goal and
## waits for you, and the objective tracker that always says what to do next.
## The first steps teach the game one thing at a time; after that it leads to
## the nearest keeper you have not felled.
##
## Settings → Gameplay: GUIDANCE turns the wisp off, TUTORIAL HINTS the key
## hints. The tracker always stays: it is only information.

const STEPS := [
	["THE SHORE", "Follow the ember wisp inland.", "move"],
	["ROLL", "Roll forward through the brambles.", "dodge"],
	["A HOLLOW STIRS", "Strike it down with your weapon.", "fire"],
	["THE WAYSHRINE", "Rest at the Wayshrine: you heal, your flask refills, and you will rise here if you fall.", "interact"],
	["THE FIRST KEEPER", "Follow the wisp to the keeper and fell it.", "skill"],
	["THE KEEPERS", "Fell the keepers of the isle.", ""],
]

var game: Node
var step := -1
var target := Vector3.INF
var shrine: Dictionary = {}
var hollow: Bot = null
var done := false
var _wisp: Node3D
var _wisp_light: OmniLight3D
var _wisp_mat: StandardMaterial3D
var _wisp_pos := Vector3.ZERO
var _step_t := 0.0
var _t := 0.0
var _rolled := false
var _rested := false


func setup(p_game: Node) -> void:
	game = p_game
	_build_wisp()


func _build_wisp() -> void:
	_wisp = Node3D.new()
	add_child(_wisp)
	_wisp.top_level = true
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.13
	sm.height = 0.26
	sm.radial_segments = 12
	sm.rings = 6
	core.mesh = sm
	_wisp_mat = StandardMaterial3D.new()
	_wisp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wisp_mat.albedo_color = Color(1.0, 0.85, 0.55)
	_wisp_mat.emission_enabled = true
	_wisp_mat.emission = Color(1.0, 0.62, 0.25)
	_wisp_mat.emission_energy_multiplier = 7.0
	core.material_override = _wisp_mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wisp.add_child(core)
	var halo := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.32
	hm.height = 0.64
	halo.mesh = hm
	var h2 := StandardMaterial3D.new()
	h2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	h2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	h2.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	h2.albedo_color = Color(1.0, 0.5, 0.15, 0.28)
	halo.material_override = h2
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wisp.add_child(halo)
	# A trail of sparks behind it.
	var trail := GPUParticles3D.new()
	trail.amount = 48
	trail.lifetime = 1.1
	trail.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3(0, 0.4, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.8, 0.45, 1.0))
	ramp.set_color(1, Color(1.0, 0.35, 0.1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	trail.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.vertex_color_use_as_albedo = true
	qm.albedo_texture = Revenant._mote_tex()
	q.material = qm
	trail.draw_pass_1 = q
	_wisp.add_child(trail)
	_wisp_light = OmniLight3D.new()
	_wisp_light.light_color = Color(1.0, 0.65, 0.3)
	_wisp_light.light_energy = 1.4
	_wisp_light.omni_range = 6.0
	_wisp.add_child(_wisp_light)
	_wisp.visible = false


func guidance_on() -> bool:
	return game.hud.opt("guidance") == 0


func hints_on() -> bool:
	return game.hud.opt("hints") == 0


## Souls Mode begins: ashore at `start`, the first Wayshrine inland.
func begin(start: Vector3, p_shrine: Dictionary) -> void:
	shrine = p_shrine
	done = false
	_rolled = false
	_rested = false
	_wisp_pos = start + Vector3.UP * 2.0
	_go(0)


func stop() -> void:
	step = -1
	done = true
	_wisp.visible = false
	if hollow != null and is_instance_valid(hollow) and hollow.alive:
		hollow.queue_free()
	hollow = null
	if game != null and game.hud != null:
		game.hud.set_objective("", "", "", "")


func on_rest() -> void:
	_rested = true


func _go(i: int) -> void:
	step = i
	_step_t = 0.0
	var p: Player = game.player
	var shrine_at: Vector3 = shrine.get("pos", p.global_position) as Vector3
	match i:
		0:
			# Some way inland, towards the Wayshrine.
			var to := shrine_at - p.global_position
			to.y = 0.0
			var d := minf(to.length() * 0.35, 22.0)
			target = game.ground_at(p.global_position + to.normalized() * d + Vector3.UP * 30.0)
		1:
			var to2 := shrine_at - p.global_position
			to2.y = 0.0
			target = game.ground_at(p.global_position + to2.normalized() * 6.0 + Vector3.UP * 30.0)
		2:
			_spawn_hollow()
		3:
			target = shrine_at
		4:
			target = _first_keeper()
		5:
			target = Vector3.INF
	if i > 0:
		game.sfx.play_ui("writ_done", -10.0)


## A lone, weak hollow on the path, to try your weapon on.
func _spawn_hollow() -> void:
	var p: Player = game.player
	var shrine_at: Vector3 = shrine.get("pos", p.global_position) as Vector3
	var to := shrine_at - p.global_position
	to.y = 0.0
	var at: Vector3 = game.ground_at(p.global_position + to.normalized() * 9.0 + Vector3.UP * 30.0)
	var b := Bot.new()
	b.setup("A HOLLOW", Vector2(at.x, at.z), game, 77)
	b.skin = Revenant.G + "minions/minion-a01.glb"
	game.add_child(b)
	b.global_position = at + Vector3.UP * 0.3
	b.state = Bot.State.GROUND
	b.landed = true
	b.visible = true
	b.arm_weapon("pistol")
	b.hp = 30.0
	b.vest_level = 0
	b.helmet_level = 0
	b.shoot_skill = 0.15
	b.aggression = 0.2
	b.set_meta("tutorial", true)
	b.eliminated.connect(game._on_bot_eliminated)
	game.bots.append(b)
	hollow = b
	target = at


## The keeper to face first: the Bellkeeper if it stands, else the nearest.
func _first_keeper() -> Vector3:
	var best := Vector3.INF
	var bd := INF
	for b in game.bots:
		if is_instance_valid(b) and b is Revenant and (b as Bot).alive and not b.has_meta("echo"):
			var r := b as Revenant
			var d: float = r.arena.distance_to(game.player.global_position) * (0.3 if r is Bellkeeper and not (r is Unkindled) else 1.0)
			if d < bd:
				bd = d
				best = r.arena
	return best


func tick(delta: float) -> void:
	if step < 0 or game == null or game.player == null:
		return
	_t += delta
	_step_t += delta
	var p: Player = game.player
	if p.dodge_t > 0.0:
		_rolled = true
	var pp := p.global_position
	match step:
		0:
			if Vector2(pp.x - target.x, pp.z - target.z).length() < 4.5 or _step_t > 40.0:
				_go(1)
		1:
			if _rolled or _step_t > 25.0:
				_go(2)
		2:
			if hollow == null or not is_instance_valid(hollow) or not hollow.alive or _step_t > 60.0:
				_go(3)
			elif is_instance_valid(hollow):
				target = hollow.global_position
		3:
			if _rested:
				_go(4)
		4:
			if game.souls_slain > 0:
				_go(5)
			elif int(_step_t * 2.0) % 4 == 0:
				target = _first_keeper()
		5:
			var k: Vector3 = (game.hud.quest.get("pos", Vector3.INF) as Vector3) if not game.hud.quest.is_empty() else Vector3.INF
			target = k
	_update_tracker()
	_update_wisp(delta)


func _update_tracker() -> void:
	var s: Array = STEPS[step]
	var title := str(s[0])
	var text := str(s[1])
	if step == 4:
		var nm := ""
		for b in game.bots:
			if is_instance_valid(b) and b is Revenant and (b as Revenant).arena.distance_to(target) < 1.0:
				nm = (b as Revenant).display_name()
		if nm != "":
			text = "Follow the wisp to %s, and fell it." % nm
	elif step == 5:
		title = "THE KEEPERS   %d / %d" % [game.souls_slain, game.souls_total]
		text = "Fell the next keeper: %s." % str(game.hud.quest.get("name", "")) if not game.hud.quest.is_empty() else "Every keeper has fallen."
	var dist := ""
	if target != Vector3.INF:
		dist = game.hud._dist_text(Vector2(target.x - game.player.global_position.x, target.z - game.player.global_position.z).length())
	var hint := ""
	if hints_on():
		match str(s[2]):
			"move":
				hint = "%s %s %s %s  MOVE   ·   %s  SPRINT   ·   MOUSE  LOOK" % [Keybinds.key("move_forward"), Keybinds.key("move_left"), Keybinds.key("move_back"), Keybinds.key("move_right"), Keybinds.key("sprint")]
			"dodge":
				hint = "%s  DODGE ROLL   (you cannot be hurt mid-roll)" % Keybinds.key("dodge")
			"fire":
				hint = "%s  ATTACK   ·   %s  %s" % [Keybinds.key("fire"), Keybinds.key("aim"), "GUARD" if game.player.pclass == "knight" else ("FOCUS" if game.player.pclass == "hunter" else ("FLAME" if game.player.pclass == "pyro" else "AIM"))]
			"interact":
				hint = "%s  REST AT THE WAYSHRINE   ·   %s  EMBER FLASK" % [Keybinds.key("interact"), Keybinds.key("flask")]
			"skill":
				hint = "%s  CLASS ABILITY   ·   %s  ROLL THROUGH ITS BLOWS" % [Keybinds.key("skill"), Keybinds.key("dodge")]
	game.hud.set_objective(title, text, dist, hint)


func _update_wisp(delta: float) -> void:
	var show := guidance_on() and target != Vector3.INF
	_wisp.visible = show
	if not show:
		return
	var pp: Vector3 = game.player.global_position
	var to := target - pp
	to.y = 0.0
	var dist := to.length()
	var want: Vector3
	if dist < 9.0:
		# Close: it circles over the goal.
		want = target + Vector3(cos(_t * 1.6) * 1.2, 2.4 + sin(_t * 2.3) * 0.25, sin(_t * 1.6) * 1.2)
	else:
		# Ahead of you, on the way, waiting if you stop.
		var ahead := pp + to.normalized() * minf(7.5, dist - 2.0)
		want = game.ground_at(ahead + Vector3.UP * 40.0) + Vector3.UP * (1.9 + sin(_t * 2.2) * 0.22)
		want.y = maxf(want.y, pp.y + 1.2)
	_wisp_pos = _wisp_pos.lerp(want, clampf(delta * 2.2, 0.0, 1.0))
	_wisp.global_position = _wisp_pos
	_wisp_mat.emission_energy_multiplier = 6.0 + sin(_t * 5.0) * 1.5
	_wisp_light.light_energy = 1.2 + sin(_t * 5.0) * 0.3
