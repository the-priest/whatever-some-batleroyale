class_name Hollow
extends Node
## The Ashen Hollow: a cursed stretch of the island under a standing wall of
## ash. Inside, the ash drains the life out of you, slowly, except in the
## warmth of a lit brazier. Light all four (press F at each) and the ward on
## the Heart of the Hollow falls: whoever takes it gets a Gift, a sigil and a
## fortune in embers, and the Hollow is cleansed for everyone. Lighting the
## last brazier wakes its sentinels.
##
## Every machine builds the same Hollow (from the island's seed) and drains its
## own player; the host settles every brazier and the Heart.

const DRAIN := 3.0
const WARM_R := 11.0
const USE_R := 2.6
const HEART_R := 3.6
const SENTINELS := 2

var game: Node
var data: Dictionary = {}
var lit: Array[bool] = []
var cleansed := false
## The Hollow Warden (on every machine; it acts only on the host).
var warden: Node = null
## The Warden has fallen this match (from the host).
var warden_down := false
var _seen := false
var _drain_t := 0.0
var _k := 0.0
var _hint_t := 0.0
var _whisper_t := 8.0
## Screenshots: hold the ash at this depth (-1 = from the player).
var force_k := -1.0

var _flames: Array[Node3D] = []
var _lights: Array[OmniLight3D] = []
var _coals: Array[MeshInstance3D] = []
var _walls: Array[MeshInstance3D] = []
var _wall_mat: ShaderMaterial
var _ash: GPUParticles3D
var _ward: MeshInstance3D
var _crystal: MeshInstance3D
var _crystal_mat: StandardMaterial3D
var _heart_light: OmniLight3D
var _drone: AudioStreamPlayer


func setup(p_game: Node) -> void:
	game = p_game
	data = game.world.villages.hollow
	if data.is_empty():
		return
	for i in (data.braziers as Array).size():
		lit.append(false)
	_build()
	_show()


func active() -> bool:
	return not data.is_empty()


## A new match: the braziers cold, the ash standing again.
func reset() -> void:
	if not active():
		return
	for i in lit.size():
		lit[i] = false
	cleansed = false
	warden_down = false
	_seen = false
	_show()


func warden_awake() -> bool:
	return lit_count() == lit.size() and not warden_down and warden != null and is_instance_valid(warden)


## Whether the Warden still keeps the Heart.
func guarded() -> bool:
	return not warden_down and warden != null and is_instance_valid(warden) and (warden as Bot).alive


func lit_count() -> int:
	var n := 0
	for l in lit:
		if l:
			n += 1
	return n


## How far into the ash `p` is: 0 outside, 1 a good way in.
func depth(p: Vector3) -> float:
	if not active() or cleansed:
		return 0.0
	var c: Vector3 = data.c
	var d := Vector2(p.x - c.x, p.z - c.z).length()
	return clampf((float(data.r) - d) / 14.0, 0.0, 1.0)


func warm(p: Vector3) -> bool:
	for i in lit.size():
		if lit[i] and (data.braziers[i] as Vector3).distance_to(p) < WARM_R:
			return true
	return false


func _brazier_near(p: Vector3) -> int:
	if not active():
		return -1
	for i in lit.size():
		var b: Vector3 = data.braziers[i]
		if Vector2(p.x - b.x, p.z - b.z).length() < USE_R and absf(p.y - b.y) < 2.5:
			return i
	return -1


func _at_heart(p: Vector3) -> bool:
	if not active() or cleansed:
		return false
	var h: Vector3 = data.heart
	return Vector2(p.x - h.x, p.z - h.z).length() < HEART_R and absf(p.y - h.y) < 3.5


func prompt(p: Vector3) -> String:
	var i := _brazier_near(p)
	if i >= 0 and not lit[i] and not cleansed:
		return "[%s]  LIGHT THE BRAZIER   (%d / %d LIT)" % [Keybinds.key("interact"), lit_count(), lit.size()]
	if _at_heart(p):
		if lit_count() < lit.size():
			return "THE HEART IS WARDED  —  LIGHT THE BRAZIERS  (%d / %d)" % [lit_count(), lit.size()]
		if guarded():
			return "THE WARDEN KEEPS THE HEART  —  FELL IT FIRST"
		return "[%s]  TAKE THE HEART OF THE HOLLOW" % Keybinds.key("interact")
	return ""


func interact(p: Vector3) -> bool:
	if not active() or cleansed:
		return false
	var i := _brazier_near(p)
	if i >= 0 and not lit[i]:
		if game.net_is_client():
			game.net.send_hollow(i)
		else:
			light_on(0, i)
		return true
	if _at_heart(p) and lit_count() == lit.size() and not guarded():
		if game.net_is_client():
			game.net.send_hollow(-1)
		else:
			claim_on(0)
		return true
	return false


# ------------------------------------------------------------------ host --

func _owner_node(o: int) -> Node3D:
	if o == 0:
		return game.player
	var h = game.humans.get(o)
	return h if h != null and is_instance_valid(h) else null


func _owner_name(o: int) -> String:
	if o == 0:
		return str(game.net.my_name) if game.net_on() else "YOU"
	var h = game.humans.get(o)
	return str((h as Bot).bot_name) if h != null and is_instance_valid(h) else "SOMEONE"


func light_on(o: int, i: int) -> void:
	if not active() or cleansed or i < 0 or i >= lit.size() or lit[i]:
		return
	var who := _owner_node(o)
	if who == null or who.global_position.distance_to(data.braziers[i]) > USE_R + 2.5:
		return
	lit[i] = true
	game.writs.award(o, 150, "BRAZIER LIT")
	var last := lit_count() == lit.size()
	_broadcast("last" if last else "lit", o, i)
	if last:
		_wake_sentinels(who)
		if warden != null and is_instance_valid(warden) and warden.has_method("wake"):
			warden.wake()


## Host: the Warden fell; the Heart is free to take.
func on_warden_fell() -> void:
	warden_down = true
	_broadcast("warden", -1, -1)


func claim_on(o: int) -> void:
	if not active() or cleansed or lit_count() < lit.size() or guarded():
		return
	var who := _owner_node(o)
	if who == null or who.global_position.distance_to(data.heart) > HEART_R + 3.0:
		return
	cleansed = true
	game.writs.award(o, 1500, "HEART OF THE HOLLOW")
	game.writs.give_sigil(o, 1, "HEART OF THE HOLLOW")
	game.writs.give_gift(o)
	_broadcast("cleansed", o, -1)


func _broadcast(what: String, o: int, i: int) -> void:
	var e := {"ev": "hollow", "lit": lit.duplicate(), "cl": cleansed, "wd": warden_down, "what": what, "who": _owner_name(o) if o >= 0 else "", "i": i, "o": o}
	if game.net_on() and game.net.hosting:
		for pid in game.net.roster:
			if int(pid) != 1:
				var ee := e.duplicate()
				ee["mine"] = int(pid) == o
				game.net.send_writ_event(int(pid), ee)
	e["mine"] = o == 0
	apply_state(e)


## The Hollow's sentinels: a few soldiers from far off, armed and armoured,
## risen round the Heart and turned on whoever lit the last flame.
func _wake_sentinels(who: Node3D) -> void:
	var picks: Array = []
	for b in game.bots:
		if picks.size() >= SENTINELS:
			break
		if not is_instance_valid(b) or not b.alive or b.is_human or b.puppet or b is Revenant or b.state != Bot.State.GROUND:
			continue
		var near_player := false
		for t in _players():
			if (t as Node3D).global_position.distance_to(b.global_position) < 200.0:
				near_player = true
				break
		if not near_player:
			picks.append(b)
	var h: Vector3 = data.heart
	for k in picks.size():
		var b: Bot = picks[k]
		var a := TAU * float(k) / float(maxi(1, picks.size())) + 0.4
		var at: Vector3 = game.ground_at(h + Vector3(cos(a) * 9.0, 30.0, sin(a) * 9.0)) + Vector3.UP * 0.3
		game.spawn_smoke(at + Vector3.UP, 1.2)
		b.global_position = at
		b.velocity = Vector3.ZERO
		if not b.armed:
			b.arm_weapon("rifle")
		b.vest_level = maxi(b.vest_level, 2)
		b.armor = 100.0
		b.helmet_level = maxi(b.helmet_level, 2)
		b.roam_point = Vector2(who.global_position.x, who.global_position.z)
		b.heard_pos = who.global_position
		b.alert_timer = 20.0


func _players() -> Array:
	var out: Array = []
	if game.player != null and game.player.alive:
		out.append(game.player)
	for id in game.humans:
		var hh = game.humans[id]
		if hh != null and is_instance_valid(hh) and (hh as Bot).alive:
			out.append(hh)
	return out


## Everyone: the host says how the Hollow stands.
func apply_state(e: Dictionary) -> void:
	if not active():
		return
	var l: Array = e.get("lit", [])
	for i in mini(l.size(), lit.size()):
		lit[i] = bool(l[i])
	cleansed = bool(e.get("cl", cleansed))
	warden_down = bool(e.get("wd", warden_down))
	_show()
	var what := str(e.get("what", ""))
	var mine := bool(e.get("mine", false))
	var i := int(e.get("i", -1))
	if i >= 0 and i < lit.size():
		game.play_sfx_at("beacon_light", data.braziers[i], 4.0)
	match what:
		"lit":
			if mine:
				game.hud.show_notice("A BRAZIER BURNS  —  %d OF %d" % [lit_count(), lit.size()], 3.0)
		"last":
			game.sfx.play_ui("event_horn", -4.0)
			if mine or depth(game.player.global_position) > 0.0:
				game.hud.show_big("THE WARD FALLS", Color(1.0, 0.55, 0.25), 2.6)
				game.hud.show_notice("THE HOLLOW WARDEN RISES  —  FELL IT, THEN TAKE THE HEART", 4.0)
		"warden":
			if depth(game.player.global_position) > 0.0 or game.player.global_position.distance_to(data.heart) < 120.0:
				game.hud.show_notice("THE WARDEN IS ASH  —  THE HEART IS FREE TO TAKE", 4.0)
		"cleansed":
			game.sfx.play_ui("writ_done", -2.0)
			if mine:
				game.hud.show_big("HEART OF THE HOLLOW", Color(1.0, 0.86, 0.45), 3.0)
			else:
				game.hud.show_notice("%s TOOK THE HEART  —  THE ASHEN HOLLOW IS CLEANSED" % str(e.get("who", "SOMEONE")), 4.0)


# -------------------------------------------------------------- per frame --

func _process(delta: float) -> void:
	if not active() or game == null:
		return
	var t := Time.get_ticks_msec() * 0.001
	for i in _flames.size():
		if lit[i]:
			var f := _flames[i]
			var fl := 1.0 + sin(t * 11.0 + i) * 0.08 + sin(t * 23.0 + i * 2.0) * 0.05
			f.scale = Vector3(1.0 - (fl - 1.0) * 0.5, fl, 1.0 - (fl - 1.0) * 0.5)
			f.rotation.y = t * 0.7 + i
			_lights[i].light_energy = 4.0 * fl
	if _crystal != null and _crystal.visible:
		_crystal.rotation.y = t * 0.6
		_crystal.position.y = 3.0 + sin(t * 1.3) * 0.15
		var pulse := 3.0 + sin(t * 2.4) * 1.5
		_crystal_mat.emission_energy_multiplier = pulse
		_heart_light.light_energy = 1.2 + pulse * 0.3
	var p: Player = game.player
	var here: bool = p != null and p.alive and p.mode == Player.Mode.GROUND and game.phase == "playing"
	var dk := depth(p.global_position) if here else 0.0
	var is_warm: bool = here and warm(p.global_position)
	var want := dk * (0.4 if is_warm else 1.0)
	if force_k >= 0.0:
		want = force_k
		_k = force_k
	_k = move_toward(_k, want, delta * 0.8)
	game.world.set_hollow(_k)
	if _drone != null:
		_drone.volume_db = lerpf(-40.0, -14.0, _k)
		if _k > 0.01 and not _drone.playing and _drone.stream != null:
			_drone.play()
		elif _k <= 0.01 and _drone.playing:
			_drone.stop()
	if dk <= 0.0:
		return
	if not _seen:
		_seen = true
		game.hud.show_big("THE ASHEN HOLLOW", Color(0.72, 0.68, 0.64), 2.6)
		game.hud.show_notice("THE ASH DRAINS THE LIVING  —  STAY BY A LIT BRAZIER", 4.0)
	_whisper_t -= delta
	if _whisper_t <= 0.0:
		_whisper_t = randf_range(9.0, 18.0)
		var off := Vector3(randf_range(-12, 12), 1.5, randf_range(-12, 12))
		game.play_sfx_at("warden_whisper", p.global_position + off, -10.0)
	if is_warm:
		return
	_drain_t += delta
	if _drain_t >= 0.5:
		_drain_t -= 0.5
		if not p.downed:
			p.take_damage(DRAIN * 0.5 * dk, Vector3.ZERO, false, null)
		_hint_t -= 0.5
		if _hint_t <= 0.0:
			_hint_t = 2.0
			game.hud.show_notice("THE ASH DRAINS YOU  —  FIND A LIT BRAZIER  (%d / %d LIT)" % [lit_count(), lit.size()], 1.9)


# ---------------------------------------------------------------- looks --

func _show() -> void:
	if not active():
		return
	for i in _flames.size():
		_flames[i].visible = lit[i]
		_lights[i].visible = lit[i]
		(_coals[i].material_override as StandardMaterial3D).emission_energy_multiplier = 0.4 if lit[i] else 1.6
	var standing := not cleansed
	for w in _walls:
		w.visible = standing
	if _ash != null:
		_ash.emitting = standing
		_ash.visible = standing
	if _ward != null:
		_ward.visible = standing and lit_count() < lit.size()
	if _crystal != null:
		_crystal.visible = standing
		_heart_light.visible = standing
	var c0: Vector3 = data.c
	game.world.set_ash(Vector4(c0.x, c0.z, float(data.r), 1.0 if standing else 0.55))
	if game != null and game.hud != null:
		var bz: Array = []
		for i in lit.size():
			var b: Vector3 = data.braziers[i]
			bz.append([Vector2(b.x, b.z), lit[i]])
		var c: Vector3 = data.c
		game.hud.hollow_mark = {"c": Vector2(c.x, c.z), "r": float(data.r), "braz": bz, "cl": cleansed}


func _mat(c: Color, emit := 0.0, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m


func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _cyl(top: float, bottom: float, h: float, seg := 12) -> CylinderMesh:
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = h
	cm.radial_segments = seg
	cm.rings = 1
	return cm


const WALL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.36, 0.34, 0.33, 1.0);
uniform float base_y = 0.0;
uniform float phase = 0.0;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float ang = atan(wpos.z - MODEL_MATRIX[3].z, wpos.x - MODEL_MATRIX[3].x);
	float h = (wpos.y - base_y) / 58.0;
	float n = 0.7 + 0.3 * sin(ang * 31.0 + TIME * 0.35 + h * 6.0 + phase) * sin(ang * 9.0 - TIME * 0.22 + phase * 2.0);
	// Tall drifting plumes rather than a sheet.
	float plume = 0.6 + 0.4 * sin(ang * 57.0 + sin(h * 3.0 + TIME * 0.15 + phase) * 1.5);
	float fade = pow(1.0 - smoothstep(0.0, 1.0, h), 2.0);
	float cam = smoothstep(3.0, 30.0, length(wpos - CAMERA_POSITION_WORLD));
	// Thin where seen edge-on, so the rim has no hard silhouette.
	float facing = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.6);
	ALBEDO = tint.rgb * (0.85 + 0.3 * n);
	ALPHA = clamp(fade * n * plume * facing * 0.95 * cam, 0.0, 0.9);
}
"""


func _build() -> void:
	var root := Node3D.new()
	root.name = "AshenHollow"
	game.world.add_child(root)
	var c: Vector3 = data.c
	var r: float = data.r
	# The standing wall of ash, in two layers that drift against each other.
	var sh := Shader.new()
	sh.code = WALL_SHADER
	for k in 2:
		var cm := _cyl(r - k * 5.0, r - k * 5.0, 96.0, 72)
		cm.cap_top = false
		cm.cap_bottom = false
		var wm := ShaderMaterial.new()
		wm.shader = sh
		wm.set_shader_parameter("phase", float(k) * 2.3)
		wm.set_shader_parameter("base_y", c.y + 2.0)
		if k == 1:
			wm.set_shader_parameter("tint", Color(0.22, 0.21, 0.2))
		var w := _mesh(root, cm, Vector3(c.x, c.y - 4.0, c.z), wm, false)
		w.extra_cull_margin = 8.0
		_walls.append(w)
	# Ash falling, always.
	_ash = GPUParticles3D.new()
	_ash.amount = 700
	_ash.lifetime = 12.0
	_ash.preprocess = 12.0
	_ash.visibility_aabb = AABB(Vector3(-r, -40.0, -r), Vector3(r * 2.0, 60.0, r * 2.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(r * 0.9, 2.0, r * 0.9)
	pm.gravity = Vector3(0.3, -1.4, 0.15)
	pm.direction = Vector3(0, -1, 0)
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.8
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	_ash.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.07, 0.07)
	var am := StandardMaterial3D.new()
	am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	am.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	am.albedo_color = Color(0.55, 0.53, 0.5)
	qm.material = am
	_ash.draw_pass_1 = qm
	_ash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(_ash)
	_ash.global_position = c + Vector3.UP * 26.0
	_build_braziers(root)
	_build_heart(root)
	_drone = AudioStreamPlayer.new()
	var st = game.sfx.stream("warden_drone")
	if st is AudioStreamWAV:
		var wav := (st as AudioStreamWAV).duplicate() as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = int(wav.get_length() * float(wav.mix_rate))
		st = wav
	_drone.stream = st
	_drone.volume_db = -40.0
	_drone.bus = "Master"
	add_child(_drone)


func _build_braziers(root: Node3D) -> void:
	var stone := _mat(Color(0.3, 0.29, 0.28))
	var iron := _mat(Color(0.12, 0.11, 0.11), 0.0, 0.6)
	iron.metallic = 0.7
	var fire_o := StandardMaterial3D.new()
	fire_o.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire_o.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fire_o.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fire_o.albedo_color = Color(1.0, 0.42, 0.1, 0.5)
	var fire_y := fire_o.duplicate() as StandardMaterial3D
	fire_y.albedo_color = Color(1.0, 0.85, 0.45, 0.9)
	for i in (data.braziers as Array).size():
		var b: Vector3 = data.braziers[i]
		var body := StaticBody3D.new()
		root.add_child(body)
		body.global_position = b
		var lo := b.y
		for k in 6:
			var q := b + Vector3(cos(TAU * k / 6.0), 0, sin(TAU * k / 6.0)) * 0.8
			lo = minf(lo, game.terrain.height_at(q.x, q.z))
		var sink := b.y - lo
		_mesh(body, _cyl(0.85, 1.0, 0.4 + sink, 8), Vector3(0, 0.2 - sink * 0.5, 0), stone)
		_mesh(body, _cyl(0.32, 0.42, 0.9, 8), Vector3(0, 0.85, 0), stone)
		_mesh(body, _cyl(0.8, 0.42, 0.42, 12), Vector3(0, 1.5, 0), iron)
		var coal := _mesh(body, _cyl(0.68, 0.68, 0.06, 12), Vector3(0, 1.69, 0), _mat(Color(0.7, 0.16, 0.05), 1.6), false)
		_coals.append(coal)
		var flame := Node3D.new()
		flame.position = Vector3(0, 1.7, 0)
		body.add_child(flame)
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		sm.radial_segments = 10
		sm.rings = 5
		var o := _mesh(flame, sm, Vector3(0, 0.6, 0), fire_o, false)
		o.scale = Vector3(0.95, 2.0, 0.95)
		var o2 := _mesh(flame, sm, Vector3(0.12, 0.9, -0.05), fire_o, false)
		o2.scale = Vector3(0.45, 1.6, 0.45)
		var y := _mesh(flame, sm, Vector3(0, 0.35, 0), fire_y, false)
		y.scale = Vector3(0.6, 0.9, 0.6)
		_flames.append(flame)
		var lt := OmniLight3D.new()
		lt.light_color = Color(1.0, 0.6, 0.28)
		lt.light_energy = 4.0
		lt.omni_range = 16.0
		lt.position = Vector3(0, 2.4, 0)
		lt.shadow_enabled = false
		body.add_child(lt)
		_lights.append(lt)
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = 0.8
		cy.height = 1.75
		cs.shape = cy
		cs.position = Vector3(0, 0.88, 0)
		body.add_child(cs)


func _build_heart(root: Node3D) -> void:
	var h: Vector3 = data.heart
	var yaw: float = data.get("yaw", 0.0)
	var dais := StaticBody3D.new()
	root.add_child(dais)
	dais.global_transform = Transform3D(Basis(Vector3.UP, yaw), h)
	var stone := _mat(Color(0.27, 0.26, 0.25))
	var lo := h.y
	for k in 8:
		var q := h + Vector3(cos(TAU * k / 8.0), 0, sin(TAU * k / 8.0)) * 4.0
		lo = minf(lo, game.terrain.height_at(q.x, q.z))
	var sink := h.y - lo
	var steps := [[4.2, 0.35 + sink, 0.175 - sink * 0.5], [3.2, 0.35, 0.525], [2.2, 0.35, 0.875]]
	for st in steps:
		_mesh(dais, _cyl(float(st[0]), float(st[0]) + 0.1, float(st[1]), 16), Vector3(0, float(st[2]), 0), stone)
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = float(st[0])
		cy.height = float(st[1])
		cs.shape = cy
		cs.position = Vector3(0, float(st[2]), 0)
		dais.add_child(cs)
	# Four broken pillars round it, and chains of iron to the crystal.
	var iron := _mat(Color(0.14, 0.13, 0.13), 0.0, 0.5)
	iron.metallic = 0.7
	for k in 4:
		var a := TAU * float(k) / 4.0 + PI * 0.25
		var pp := Vector3(cos(a) * 3.6, 0.0, sin(a) * 3.6)
		var ph := 2.4 + float(k % 2) * 1.3
		var pm := BoxMesh.new()
		pm.size = Vector3(0.7, ph, 0.7)
		_mesh(dais, pm, pp + Vector3(0, ph * 0.5, 0), stone)
		var top := pp + Vector3(0, ph - 0.3, 0)
		var to := Vector3(0, 3.0, 0) - top
		var cm := BoxMesh.new()
		cm.size = Vector3(0.05, 0.05, to.length())
		var chain := _mesh(dais, cm, top + to * 0.5, iron, false)
		chain.look_at_from_position(top + to * 0.5, Vector3(0, 3.0, 0), Vector3.UP)
		var pc := CollisionShape3D.new()
		var pb := BoxShape3D.new()
		pb.size = pm.size
		pc.shape = pb
		pc.position = pp + Vector3(0, ph * 0.5, 0)
		dais.add_child(pc)
	# The Heart: a dark crystal that beats.
	var oc := SphereMesh.new()
	oc.radius = 0.6
	oc.height = 1.2
	oc.radial_segments = 4
	oc.rings = 2
	_crystal_mat = _mat(Color(0.75, 0.08, 0.06), 3.0, 0.2)
	_crystal_mat.metallic = 0.3
	_crystal = _mesh(dais, oc, Vector3(0, 3.0, 0), _crystal_mat, false)
	_crystal.scale = Vector3(0.8, 1.6, 0.8)
	_heart_light = OmniLight3D.new()
	_heart_light.light_color = Color(1.0, 0.2, 0.12)
	_heart_light.light_energy = 2.0
	_heart_light.omni_range = 12.0
	_heart_light.shadow_enabled = false
	_heart_light.position = Vector3(0, 3.0, 0)
	dais.add_child(_heart_light)
	var ws := SphereMesh.new()
	ws.radius = 1.6
	ws.height = 3.2
	ws.radial_segments = 20
	ws.rings = 10
	var wm := StandardMaterial3D.new()
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	wm.albedo_color = Color(0.5, 0.55, 0.7, 0.16)
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ward = _mesh(dais, ws, Vector3(0, 3.0, 0), wm, false)
