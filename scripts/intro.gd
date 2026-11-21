class_name Intro
extends CanvasLayer
## The opening of Souls Mode: a short film over the real isle. Letterboxed
## shots of the island, its keepers, the fire going out, the shore you wash
## up on, each with a line of the tale, then the title. Hold SPACE (or ESC,
## or a pad's A/B) to skip.

const LINES := [
	"Before the towns, before the storms, a fire burned at the heart of the isle, and the isle was warm.",
	"The Ember King kept it. Thirteen keepers kept the roads to it: knights and giants, a witch, a warden, a queen of crows.",
	"Then the fire began to go out.",
	"The keepers would not let it die. They took its last embers into themselves, and the embers ate them hollow.",
	"They still keep the old roads, though there is nothing left at the end of them to keep.",
	"Those who came after, for the gold in the ruins, are hollow too now. They wander the towns.",
	"You wash ashore with your weapon, and a flask with a little fire in it.",
	"Rest at the Wayshrines. Their fire will bring you back each time you fall.",
]
const TITLE := "THE ISLE OF EMBERS"
const SUBTITLE := "Slay the keepers. Free the isle. Or join them."

var game: Node
var done: Callable
var shots: Array = []
var shot := -1
var t := 0.0
var running := false
var _actors: Array = []
var _skip := 0.0
var _weather := ""

var _top: ColorRect
var _bottom: ColorRect
var _fade: ColorRect
var _vignette: TextureRect
var _line: Label
var _title: Label
var _sub: Label
var _skip_label: Label
var _skip_bar: ColorRect


func _init() -> void:
	layer = 90


func setup(p_game: Node) -> void:
	game = p_game
	_build_overlay()
	visible = false


func _build_overlay() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	_vignette = TextureRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.add_point(0.62, Color(0, 0, 0, 0.12))
	g.set_color(g.get_point_count() - 1, Color(0, 0, 0, 0.75))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.05, 1.05)
	gt.width = 256
	gt.height = 256
	_vignette.texture = gt
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	root.add_child(_vignette)
	# A warm grade over everything.
	var grade := ColorRect.new()
	grade.set_anchors_preset(Control.PRESET_FULL_RECT)
	grade.color = Color(1.0, 0.55, 0.25, 0.06)
	grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(grade)
	_top = ColorRect.new()
	_top.color = Color.BLACK
	_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_top)
	_bottom = ColorRect.new()
	_bottom.color = Color.BLACK
	_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_bottom)
	var serif := SystemFont.new()
	serif.font_names = PackedStringArray(["Georgia", "Palatino Linotype", "Book Antiqua", "Times New Roman", "DejaVu Serif", "Liberation Serif", "serif"])
	serif.font_weight = 400
	var serif_b := SystemFont.new()
	serif_b.font_names = serif.font_names
	serif_b.font_weight = 700
	_line = Label.new()
	_line.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_line.offset_left = -560
	_line.offset_right = 560
	_line.offset_top = -210
	_line.offset_bottom = -120
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.add_theme_font_override("font", serif)
	_line.add_theme_font_size_override("font_size", 27)
	_line.add_theme_color_override("font_color", Color(0.97, 0.93, 0.86))
	_line.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_line.add_theme_constant_override("shadow_offset_y", 2)
	_line.add_theme_constant_override("shadow_outline_size", 6)
	_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_line)
	_title = Label.new()
	_title.set_anchors_preset(Control.PRESET_CENTER)
	_title.offset_left = -800
	_title.offset_right = 800
	_title.offset_top = -90
	_title.offset_bottom = 10
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_override("font", serif_b)
	_title.add_theme_font_size_override("font_size", 74)
	_title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.5))
	_title.add_theme_color_override("font_shadow_color", Color(0.3, 0.08, 0.0, 0.9))
	_title.add_theme_constant_override("shadow_outline_size", 16)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_title)
	_sub = Label.new()
	_sub.set_anchors_preset(Control.PRESET_CENTER)
	_sub.offset_left = -600
	_sub.offset_right = 600
	_sub.offset_top = 22
	_sub.offset_bottom = 70
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.add_theme_font_override("font", serif)
	_sub.add_theme_font_size_override("font_size", 24)
	_sub.add_theme_color_override("font_color", Color(0.92, 0.88, 0.8))
	_sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_sub.add_theme_constant_override("shadow_outline_size", 6)
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_sub)
	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)
	_skip_label = Label.new()
	_skip_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip_label.offset_left = -320
	_skip_label.offset_right = -40
	_skip_label.offset_top = -62
	_skip_label.offset_bottom = -40
	_skip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skip_label.add_theme_font_size_override("font_size", 13)
	_skip_label.add_theme_color_override("font_color", Color(0.75, 0.72, 0.68, 0.8))
	_skip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_skip_label)
	_skip_bar = ColorRect.new()
	_skip_bar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip_bar.offset_left = -200
	_skip_bar.offset_right = -200
	_skip_bar.offset_top = -36
	_skip_bar.offset_bottom = -33
	_skip_bar.color = Color(1.0, 0.7, 0.35)
	_skip_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_skip_bar)


# ----------------------------------------------------------------- shots --
## Each shot: [camera from, camera to, look from, look to, seconds, line,
## weather]. Built from the real isle when the film starts.
func _plan() -> void:
	shots.clear()
	var tr: Terrain = game.terrain
	var mid := Vector3(0, 30, 0)
	# 1. The isle from high above, in the last of the gold.
	shots.append([Vector3(-520, 330, 620), Vector3(-260, 250, 330), mid, mid + Vector3(60, 0, -40), 9.0, 0, "golden"])
	# 2. The keepers, standing in the ring of stones.
	var ring := _open_spot(tr.castle_c + Vector2(140, 60))
	var keepers_at := ring
	_stage_keepers(keepers_at)
	var kc := _clear_cam(keepers_at + Vector3(0, 2.0, -1), Vector3(-6, 1.7, 11), Vector3(5, 2.1, 10))
	shots.append([kc[0], kc[1], keepers_at + Vector3(-1, 2.0, -1), keepers_at + Vector3(1, 2.2, -1), 9.5, 1, "golden"])
	# 3. The fire going out: the castle in mist.
	var cp: Array = game._landmark_pose("castle")
	shots.append([cp[0] + Vector3(40, 30, 40), cp[0], cp[1], cp[1], 6.5, 2, "misty"])
	# 4. The Warden, kneeling, close.
	var w_at := _open_spot(tr.castle_c + Vector2(-120, 140))
	_stage_one("warden", w_at, PI)
	var wc := _clear_cam(w_at + Vector3(0, 1.4, 0), Vector3(1.2, 1.5, 8.5), Vector3(0.5, 1.8, 5.2))
	shots.append([wc[0], wc[1], w_at + Vector3(0, 1.3, 0), w_at + Vector3(0, 1.6, 0), 9.0, 3, "misty"])
	# 5. The old roads: the long bridge.
	var bp: Array = game._landmark_pose("bridge")
	shots.append([bp[0], bp[0] + Vector3(-50, 12, 30), bp[1], bp[1], 7.5, 4, "overcast"])
	# 6. A town, and the hollow walking its street.
	var town := _town_spot()
	_stage_hollows(town)
	var tc := _clear_cam(town + Vector3(0, 1.1, 0), Vector3(7, 1.7, 9), Vector3(-3, 1.6, 8))
	shots.append([tc[0], tc[1], town + Vector3(0, 1.1, 0), town + Vector3(-1, 1.2, 0), 8.0, 5, "overcast"])
	# 7. The shore, from the water.
	var shore := _shore_spot()
	var out := Vector3(shore.x, 0, shore.z).normalized()
	# You, on the sand, looking up at the isle.
	_stage_hero(shore, out)
	var side := out.cross(Vector3.UP)
	shots.append([shore + out * 9.0 + side * 3.0 + Vector3(0, 2.4, 0), shore + out * 4.5 + side * 1.6 + Vector3(0, 1.9, 0), shore + Vector3(0, 1.3, 0) - out * 2.0, shore + Vector3(0, 2.2, 0) - out * 25.0, 8.5, 6, "golden"])
	# 8. A Wayshrine and its fire.
	var sh := _shrine_spot()
	_stage_fire(sh)
	var scam := _clear_cam(sh + Vector3(0, 1.0, 0), Vector3(6, 2.2, 7), Vector3(3.2, 1.5, 4.0))
	shots.append([scam[0], scam[1], sh + Vector3(0, 1.0, 0), sh + Vector3(0, 1.1, 0), 8.0, 7, "golden"])
	# 9. The title, the isle at dusk.
	shots.append([Vector3(380, 220, -520), Vector3(260, 200, -360), mid, mid, 8.5, -1, "golden"])


## Flat, open ground near a point: out of the woods, level for a few metres
## all round, so the camera sees the figures and not a hillside.
func _open_spot(near: Vector2) -> Vector3:
	var tr: Terrain = game.terrain
	for k in 120:
		var a := float(k) * 2.4
		var p := near + Vector2(cos(a), sin(a)) * float(k) * 5.0
		var h := tr.height_at(p.x, p.y)
		if h < tr.water_surface_at(p.x, p.y) + 1.5 or tr.slope_at(p.x, p.y) > 0.1 or tr.forest_density(p.x, p.y) > 0.15:
			continue
		if not game.world.villages.house_at(p, 12.0).is_empty():
			continue
		var flat := true
		for j in 8:
			var q := p + Vector2(cos(j * 0.785), sin(j * 0.785)) * 14.0
			if absf(tr.height_at(q.x, q.y) - h) > 1.2:
				flat = false
				break
		if not flat:
			continue
		return game.ground_at(Vector3(p.x, 400.0, p.y))
	return game.ground_at(Vector3(near.x, 400.0, near.y))


func _town_spot() -> Vector3:
	var pads: Array = game.world.villages.village_pads
	if pads.is_empty():
		return _open_spot(Vector2(200, 200))
	var c: Vector2 = pads[0].center
	return _open_spot(c)


## A real sea beach: walking out from the middle of the isle until the land
## meets the open sea, on a gentle slope with no trees on the sand.
func _shore_spot() -> Vector3:
	var tr: Terrain = game.terrain
	for k in 32:
		var a := float(k) / 32.0 * TAU + 0.3
		var dir := Vector2(cos(a), sin(a))
		var last := Vector2.INF
		var r := Terrain.HALF * 0.35
		while r < Terrain.HALF * 1.1:
			var q := dir * r
			var h := tr.height_at(q.x, q.y)
			if h < Terrain.WATER_LEVEL + 0.2:
				break
			last = q
			r += 6.0
		if last == Vector2.INF or r >= Terrain.HALF * 1.1:
			continue
		var p := last - dir * 8.0
		if tr.slope_at(p.x, p.y) > 0.15 or tr.forest_density(p.x, p.y) > 0.1:
			continue
		if tr.water_surface_at(p.x + dir.x * 30.0, p.y + dir.y * 30.0) > Terrain.WATER_LEVEL + 0.5:
			continue
		return game.ground_at(Vector3(p.x, 400.0, p.y))
	return _open_spot(Vector2(600, 0))


## A camera path for a subject with nothing in the way: turned round the
## subject until the subject can be seen from both ends of the move, and kept
## above the ground.
func _clear_cam(subject: Vector3, a: Vector3, b: Vector3) -> Array:
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	for step in 12:
		# 0, +30, -30, +60, -60 ... degrees round the subject.
		var ang := deg_to_rad(30.0 * float((step + 1) / 2)) * (1.0 if step % 2 == 1 else -1.0)
		var ra := Basis(Vector3.UP, ang) * a
		var rb := Basis(Vector3.UP, ang) * b
		var pa := _above_ground(_flat(subject) + ra, ra.y)
		var pb := _above_ground(_flat(subject) + rb, rb.y)
		var clear := true
		for p: Vector3 in [pa, pb, pa.lerp(pb, 0.5)]:
			var q := PhysicsRayQueryParameters3D.create(p, subject, 1)
			var hit := space.intersect_ray(q)
			if not hit.is_empty() and (hit.position as Vector3).distance_to(subject) > 1.2:
				clear = false
				break
		if clear:
			return [pa, pb]
	return [_above_ground(_flat(subject) + a, a.y), _above_ground(_flat(subject) + b, b.y)]


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, game.ground_at(Vector3(v.x, 400.0, v.z)).y, v.z)


## A point the given height over the ground beneath it.
func _above_ground(p: Vector3, h: float) -> Vector3:
	var g: Vector3 = game.ground_at(Vector3(p.x, 400.0, p.z))
	return Vector3(p.x, maxf(p.y, g.y + h), p.z)


func _shrine_spot() -> Vector3:
	# The Wayshrine most in the open (not lost in a dark wood).
	if game.writs != null and not game.writs.shrines.is_empty():
		var best: Vector3 = game.writs.shrines[0].pos
		var bd := INF
		for s in game.writs.shrines:
			var p: Vector3 = s.pos
			var d: float = game.terrain.forest_density(p.x, p.z)
			if d < bd:
				bd = d
				best = p
		return best
	return _open_spot(Vector2(0, 0))


## Keepers for the camera to see (still, playing their idle).
func _stage_one(kind: String, at: Vector3, yaw: float) -> Node3D:
	var b: Revenant = null
	match kind:
		"warden":
			var w := HollowWarden.new()
			w.setup_warden(at, game)
			b = w
		"colossus":
			var c := Colossus.new()
			c.setup_colossus("VARGHUL", "THE ASHEN COLOSSUS", at, game)
			b = c
		"witch":
			var lw := LanternWitch.new()
			lw.setup_witch(at, game)
			b = lw
		"bell":
			var bk := Bellkeeper.new()
			bk.setup_bell(at, game)
			b = bk
		_:
			var rv := Revenant.new()
			rv.setup_revenant("MAELIS", "THE ASH WARDEN", at, game)
			b = rv
	game.add_child(b)
	b.set_physics_process(false)
	b.global_position = at
	b.rotation.y = yaw
	b.set_meta("intro", true)
	_actors.append(b)
	_fill_light(b)
	return b


## A warm light from the camera's side, so a dark figure reads on film.
func _fill_light(n: Node3D) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.6)
	l.light_energy = 2.2
	l.omni_range = 9.0
	l.shadow_enabled = false
	l.position = Vector3(1.5, 2.8, -3.5)
	n.add_child(l)


## Your own class's character, standing on the beach facing inland.
func _stage_hero(at: Vector3, out: Vector3) -> void:
	var h := Bot.new()
	h.setup("YOU", Vector2(at.x, at.z), game, 999)
	h.skin = str(Classes.SKINS.get(Classes.chosen, Classes.SKINS["knight"]))
	game.add_child(h)
	h.set_physics_process(false)
	h.visible = true
	h.state = Bot.State.GROUND
	h.global_position = at
	h.rotation.y = atan2(out.x, out.z)
	_actors.append(h)


## A Wayshrine's fire for the camera: a brazier, flames and a warm light.
func _stage_fire(at: Vector3) -> void:
	var root := Node3D.new()
	game.add_child(root)
	root.global_position = game.ground_at(at + Vector3(0, 20, 0))
	var bowl := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.5
	bm.bottom_radius = 0.3
	bm.height = 0.5
	bowl.mesh = bm
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.18, 0.16, 0.14)
	iron.metallic = 0.6
	bowl.material_override = iron
	bowl.position.y = 0.25
	root.add_child(bowl)
	var fl := GPUParticles3D.new()
	fl.amount = 60
	fl.lifetime = 0.9
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0, 1.5, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.45, 1.0))
	ramp.add_point(0.5, Color(1.0, 0.4, 0.1, 0.8))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.3, 0.08, 0.02, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	fl.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.vertex_color_use_as_albedo = true
	qm.albedo_texture = Revenant._mote_tex()
	q.material = qm
	fl.draw_pass_1 = q
	fl.position.y = 0.55
	fl.preprocess = 1.0
	root.add_child(fl)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.25)
	l.light_energy = 3.5
	l.omni_range = 11.0
	l.position.y = 1.3
	root.add_child(l)
	_actors.append(root)


func _stage_keepers(at: Vector3) -> void:
	# Facing the camera (a body looks down its -Z; PI turns it to +Z).
	_stage_one("colossus", at + Vector3(0, 0, -2.5), PI)
	_stage_one("revenant", at + Vector3(-4.0, 0, 0.5), PI - 0.3)
	_stage_one("witch", at + Vector3(4.0, 0, 0.5), PI + 0.3)
	_stage_one("bell", at + Vector3(-7.5, 0, -1.0), PI - 0.5)
	for b in _actors:
		var n := b as Node3D
		n.global_position = game.ground_at(n.global_position + Vector3.UP * 30.0)


func _stage_hollows(at: Vector3) -> void:
	var skins := ["undead/SheetGhost.glb", "undead/StitchedBrute.glb", "undead/TombMummy.glb"]
	for i in 3:
		var h := Bot.new()
		h.setup("HOLLOW", Vector2(at.x, at.z), game, 900 + i)
		h.skin = Revenant.G + skins[i]
		game.add_child(h)
		h.set_physics_process(false)
		h.visible = true
		h.state = Bot.State.GROUND
		h.global_position = game.ground_at(at + Vector3(-2.5 + 2.5 * float(i), 30, -1.0 + float(i % 2)))
		h.rotation.y = PI + 0.3 * float(i - 1)
		if h.body != null:
			h.body.set_legs("Walk" if i != 1 else "Idle")
		_actors.append(h)


func _clear_actors() -> void:
	for a in _actors:
		if is_instance_valid(a):
			(a as Node).queue_free()
	_actors.clear()


# ------------------------------------------------------------------ play --
func play(p_done: Callable) -> void:
	done = p_done
	_weather = str(game.world.weather)
	_plan()
	visible = true
	running = true
	_skip = 0.0
	shot = -1
	_next()


func _next() -> void:
	shot += 1
	t = 0.0
	if shot >= shots.size():
		finish()
		return
	var s: Array = shots[shot]
	game.world.set_weather(str(s[6]))
	var li: int = s[5]
	_line.text = LINES[li] if li >= 0 else ""
	_title.text = TITLE if li < 0 else ""
	_sub.text = SUBTITLE if li < 0 else ""


## Poses everything for shot n at fraction k of it (also used for stills).
func pose(n: int, k: float) -> void:
	var s: Array = shots[n]
	var e := k * k * (3.0 - 2.0 * k)
	var cam: Camera3D = game.menu_cam
	cam.make_current()
	cam.global_position = (s[0] as Vector3).lerp(s[1], e)
	cam.look_at((s[2] as Vector3).lerp(s[3], e), Vector3.UP)
	cam.fov = 50.0
	var vh := get_viewport().get_visible_rect().size.y
	var bar := vh * 0.115
	_top.offset_bottom = bar
	_bottom.offset_top = -bar
	var dur: float = s[4]
	var tt := k * dur
	# Fade from black at the start of each shot, to black at its end.
	var a := 0.0
	if tt < 0.9:
		a = 1.0 - tt / 0.9
	elif tt > dur - 0.8:
		a = (tt - (dur - 0.8)) / 0.8
	_fade.color.a = clampf(a, 0.0, 1.0)
	# The words come a little after the picture and leave a little before.
	var ta := clampf((tt - 1.0) / 1.0, 0.0, 1.0) * clampf((dur - 0.9 - tt) / 0.8, 0.0, 1.0)
	_line.modulate.a = ta
	_title.modulate.a = ta
	_sub.modulate.a = clampf((tt - 2.0) / 1.0, 0.0, 1.0) * clampf((dur - 0.9 - tt) / 0.8, 0.0, 1.0)
	_title.scale = Vector2.ONE * (1.0 + e * 0.04)


func _process(delta: float) -> void:
	if not running:
		return
	var holding := Input.is_action_pressed("jump") or Input.is_action_pressed("pause") or Input.is_action_pressed("ui_cancel") or Input.is_action_pressed("ui_accept") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_skip = clampf(_skip + (delta if holding else -delta * 2.0), 0.0, 0.9)
	_skip_label.text = "HOLD %s TO SKIP" % Keybinds.key("jump")
	_skip_bar.offset_right = -200.0 + 160.0 * (_skip / 0.9)
	if _skip >= 0.9:
		finish()
		return
	t += delta
	var s: Array = shots[shot]
	var dur: float = s[4]
	if t >= dur:
		_next()
		if not running:
			return
		s = shots[shot]
		dur = s[4]
	pose(shot, clampf(t / dur, 0.0, 1.0))


func finish() -> void:
	if not running:
		return
	running = false
	visible = false
	_clear_actors()
	if _weather != "":
		game.world.set_weather(_weather)
	if done.is_valid():
		done.call()
