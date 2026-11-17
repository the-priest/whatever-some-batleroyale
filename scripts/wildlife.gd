class_name Wildlife
extends Node3D
## Birds: songbirds calling from the trees round you, gulls over the shore,
## and a few flocks wheeling high over the island. Gunfire hushes the woods
## for a while and sends the flocks up and away.

const FLOCKS := 4
const PER_FLOCK := 7
const CELL := 32.0

var game: Node = null
var _grid: Dictionary = {}
var _song_t := 3.0
var _gull_t := 6.0
var _hush := 0.0
var _t := 0.0
var _flocks: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
## Waves on the shore: a sound at the nearest open sea, louder the closer.
var _surf: AudioStreamPlayer3D = null
var _surf_t := 0.0
var _surf_at := Vector3.INF
## A quiet wind over the land: stronger up high and in the open, hushed in
## the woods and gone indoors.
var _wind: AudioStreamPlayer = null
## Pollen and dust drifting in the air round you on fair days.
var _motes: GPUParticles3D = null


func setup(p_game: Node) -> void:
	game = p_game
	_rng.randomize()
	_grid.clear()
	for rec in game.world.tree_records:
		var p: Vector3 = rec.pos
		var k := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
		if not _grid.has(k):
			_grid[k] = []
		_grid[k].append(p)
	for c in get_children():
		c.queue_free()
	_flocks.clear()
	var mesh := _bird_mesh()
	var mat := StandardMaterial3D.new()
	# Seen against the sky a bird is a dark shape, whatever the sun does.
	mat.albedo_color = Color(0.09, 0.09, 0.1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for f in FLOCKS:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = PER_FLOCK
		mm.mesh = mesh
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var birds: Array = []
		for i in PER_FLOCK:
			birds.append({"a": _rng.randf() * TAU, "r": _rng.randf_range(0.7, 1.3), "h": _rng.randf_range(-4, 4), "ph": _rng.randf() * TAU, "sp": _rng.randf_range(0.9, 1.1)})
		var fl := {"mm": mm, "birds": birds, "c": Vector3.ZERO, "rad": 30.0, "alt": 70.0, "speed": 0.25, "life": 0.0, "flee": 0.0, "dir": 1.0 if f % 2 == 0 else -1.0}
		_flocks.append(fl)
		_place_flock(fl, true)


## A bird seen from below: two swept wings and a small body, wings along X.
func _bird_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [
		# Left wing, right wing (root, tip, trailing edge), body.
		[Vector3(-0.05, 0, -0.08), Vector3(-0.55, 0.06, 0.12), Vector3(-0.05, 0, 0.12)],
		[Vector3(0.05, 0, -0.08), Vector3(0.05, 0, 0.12), Vector3(0.55, 0.06, 0.12)],
		[Vector3(0, 0, -0.26), Vector3(-0.06, 0, 0.1), Vector3(0.06, 0, 0.1)],
		[Vector3(-0.05, 0, 0.1), Vector3(0, 0, 0.3), Vector3(0.05, 0, 0.1)],
	]
	for tri in pts:
		for v in tri:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	return st.commit()


func _place_flock(fl: Dictionary, initial := false) -> void:
	var o := Vector3.ZERO
	if game.player != null:
		o = game.player.global_position
	var ang := _rng.randf() * TAU
	var dist := _rng.randf_range(30.0, 180.0) if not initial else _rng.randf_range(40.0, 300.0)
	var c := o + Vector3(cos(ang), 0, sin(ang)) * dist
	var ground: float = game.terrain.height_at(c.x, c.z)
	fl.c = Vector3(c.x, maxf(ground, Terrain.WATER_LEVEL), c.z)
	fl.rad = _rng.randf_range(18.0, 40.0)
	fl.alt = _rng.randf_range(28.0, 60.0)
	fl.speed = _rng.randf_range(0.18, 0.32)
	fl.life = _rng.randf_range(40.0, 90.0)
	fl.flee = 0.0


## Shots and blasts: the woods go quiet, nearby flocks take off.
func gunshot(pos: Vector3) -> void:
	if game == null or game.player == null:
		return
	if pos.distance_to(game.player.global_position) < 220.0:
		_hush = 25.0
	for fl in _flocks:
		if Vector2(pos.x - fl.c.x, pos.z - fl.c.z).length() < 200.0 and fl.flee <= 0.0:
			fl.flee = 0.01


func _process(delta: float) -> void:
	if game == null or game.player == null or game.terrain == null:
		return
	_t += delta
	_hush = maxf(0.0, _hush - delta)
	_update_flocks(delta)
	_update_surf(delta)
	_update_ground_wind(delta)
	_update_motes()
	var p: Player = game.player
	if not p.alive or p.mode != Player.Mode.GROUND or game.phase != "playing":
		return
	if p.swimming and p.global_position.y < game.terrain.water_surface_at(p.global_position.x, p.global_position.z) - 0.5:
		return
	var wet: bool = str(game.world.weather) == "rain"
	_song_t -= delta
	if _song_t <= 0.0:
		_song_t = _rng.randf_range(2.5, 7.0) * (3.0 if wet else 1.0)
		if _hush <= 0.0:
			_sing(p.global_position)
	_gull_t -= delta
	if _gull_t <= 0.0:
		_gull_t = _rng.randf_range(7.0, 16.0)
		if _hush <= 0.0 and not wet:
			_gull(p.global_position)


func _update_surf(delta: float) -> void:
	var p: Player = game.player
	if _surf == null:
		var st: AudioStream = game.sfx.stream("surf_loop")
		if st == null:
			return
		game._make_loop(st)
		_surf = AudioStreamPlayer3D.new()
		_surf.stream = st
		_surf.unit_size = 22.0
		_surf.max_distance = 140.0
		_surf.volume_db = -80.0
		_surf.attenuation_filter_cutoff_hz = 5000.0
		add_child(_surf)
	var listening: bool = p.alive and p.mode in [Player.Mode.GROUND, Player.Mode.VEHICLE] and game.phase in ["playing", "end"]
	_surf_t -= delta
	if _surf_t <= 0.0 and listening:
		_surf_t = 0.6
		# The nearest open sea in a ring of samples round you.
		var o := p.global_position
		var best := Vector3.INF
		var best_d := 1e9
		for r: float in [12.0, 30.0, 55.0, 90.0]:
			for k in 16:
				var a := TAU * float(k) / 16.0
				var q := o + Vector3(cos(a), 0, sin(a)) * r
				if game.terrain.height_at(q.x, q.z) < Terrain.WATER_LEVEL - 0.4:
					var d := r
					if d < best_d:
						best_d = d
						best = Vector3(q.x, Terrain.WATER_LEVEL + 0.5, q.z)
			if best != Vector3.INF:
				break
		_surf_at = best
	var want := -80.0
	if listening and _surf_at != Vector3.INF:
		want = -6.0
		_surf.global_position = _surf.global_position.lerp(_surf_at, clampf(delta * 2.0, 0.0, 1.0)) if _surf.playing else _surf_at
	if want > -70.0 and not _surf.playing:
		_surf.play(_rng.randf() * 20.0)
	_surf.volume_db = lerpf(_surf.volume_db, want, clampf(delta * 1.5, 0.0, 1.0))
	if want <= -70.0 and _surf.playing and _surf.volume_db < -60.0:
		_surf.stop()


func _update_ground_wind(delta: float) -> void:
	var p: Player = game.player
	if _wind == null:
		var st: AudioStream = game.sfx.stream("wind_loop")
		if st == null:
			return
		# Its own copy: the freefall rush sets the shared one's pitch.
		st = st.duplicate()
		game._make_loop(st)
		_wind = AudioStreamPlayer.new()
		_wind.stream = st
		_wind.volume_db = -80.0
		_wind.pitch_scale = 0.62
		add_child(_wind)
	var want := -80.0
	if p.alive and p.mode == Player.Mode.GROUND and game.phase in ["playing", "end"]:
		var env := str(game.get("_listener_env"))
		var h := clampf((p.global_position.y - 20.0) / 60.0, 0.0, 1.0)
		want = {"indoor": -80.0, "forest": -34.0, "town": -30.0}.get(env, -27.0) + h * 7.0
		if str(game.world.weather) == "rain":
			want += 3.0
	if want > -70.0 and not _wind.playing:
		_wind.play(_rng.randf() * 5.0)
	_wind.volume_db = lerpf(_wind.volume_db, want, clampf(delta * 1.2, 0.0, 1.0))
	if want <= -70.0 and _wind.playing and _wind.volume_db < -60.0:
		_wind.stop()


func _update_motes() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var p: Player = game.player
	if _motes == null:
		_motes = GPUParticles3D.new()
		_motes.amount = 70
		_motes.lifetime = 9.0
		_motes.preprocess = 9.0
		_motes.local_coords = false
		_motes.visibility_aabb = AABB(Vector3(-14, -6, -14), Vector3(28, 14, 28))
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(11, 4, 11)
		pm.direction = Vector3(1, 0.2, 0.3)
		pm.spread = 180.0
		pm.initial_velocity_min = 0.05
		pm.initial_velocity_max = 0.25
		pm.gravity = Vector3(0.08, 0.02, 0.04)
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 0.6
		pm.turbulence_noise_scale = 3.0
		pm.scale_min = 0.6
		pm.scale_max = 1.2
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 0.97, 0.85, 0.0))
		grad.add_point(0.2, Color(1, 0.97, 0.85, 0.75))
		grad.add_point(0.8, Color(1, 0.97, 0.85, 0.75))
		grad.set_color(grad.get_point_count() - 1, Color(1, 0.97, 0.85, 0.0))
		var gt := GradientTexture1D.new()
		gt.gradient = grad
		pm.color_ramp = gt
		_motes.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(0.05, 0.05)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		# A soft round speck.
		var dot := GradientTexture2D.new()
		dot.fill = GradientTexture2D.FILL_RADIAL
		dot.fill_from = Vector2(0.5, 0.5)
		dot.fill_to = Vector2(1.0, 0.5)
		dot.width = 32
		dot.height = 32
		var dg := Gradient.new()
		dg.set_color(0, Color(1, 1, 1, 1))
		dg.set_color(1, Color(1, 1, 1, 0))
		dot.gradient = dg
		m.albedo_texture = dot
		q.material = m
		_motes.draw_pass_1 = q
		_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_motes)
	var fair := str(game.world.weather) in ["clear", "golden", "misty"]
	var on := fair and p.alive and p.mode == Player.Mode.GROUND and str(game.get("_listener_env")) != "indoor"
	_motes.emitting = on
	if on:
		_motes.global_position = p.global_position + Vector3(0, 1.8, 0)


func _sing(o: Vector3) -> void:
	# A tree near you, not right overhead.
	var near: Array = []
	var c := Vector2i(floori(o.x / CELL), floori(o.z / CELL))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for tp: Vector3 in _grid.get(c + Vector2i(dx, dz), []):
				var d := Vector2(tp.x - o.x, tp.z - o.z).length()
				if d > 8.0 and d < 45.0:
					near.append(tp)
	if near.size() < 3:
		return
	var tp: Vector3 = near[_rng.randi() % near.size()]
	var at := tp + Vector3(_rng.randf_range(-1.5, 1.5), _rng.randf_range(6.0, 12.0), _rng.randf_range(-1.5, 1.5))
	game.sfx.play_at("bird_%d" % _rng.randi_range(1, 6), at, _rng.randf_range(-9.0, -3.0), 0.06)


func _gull(o: Vector3) -> void:
	# Out over the water, if there is water close by.
	for i in 6:
		var ang := _rng.randf() * TAU
		var d := _rng.randf_range(25.0, 70.0)
		var q := o + Vector3(cos(ang), 0, sin(ang)) * d
		if game.terrain.is_water(q.x, q.z) and game.terrain.height_at(q.x, q.z) < Terrain.WATER_LEVEL - 1.0:
			game.sfx.play_at("gull_%d" % _rng.randi_range(1, 3), Vector3(q.x, Terrain.WATER_LEVEL + _rng.randf_range(10.0, 25.0), q.z), _rng.randf_range(-6.0, -1.0), 0.08)
			return


func _update_flocks(delta: float) -> void:
	for fl in _flocks:
		fl.life -= delta
		if fl.flee > 0.0:
			fl.flee += delta
		var flee_k := clampf(fl.flee / 6.0, 0.0, 1.0)
		var far := false
		if game.player != null:
			var pp: Vector3 = game.player.global_position
			far = Vector2(pp.x - fl.c.x, pp.z - fl.c.z).length() > 600.0
		if fl.life <= 0.0 or fl.flee > 14.0 or far:
			_place_flock(fl)
		var mm: MultiMesh = fl.mm
		var birds: Array = fl.birds
		for i in birds.size():
			var b: Dictionary = birds[i]
			var spd: float = fl.speed * (1.0 + flee_k * 1.5) * float(b.sp)
			b.a = float(b.a) + spd * delta * float(fl.dir)
			var r: float = float(fl.rad) * float(b.r) * (1.0 + flee_k * 3.0)
			var a: float = b.a
			var pos: Vector3 = fl.c + Vector3(cos(a) * r, float(fl.alt) + float(b.h) + flee_k * 40.0 + sin(_t * 0.3 + a) * 3.0, sin(a) * r)
			# Facing along the circle, banked into the turn.
			var fwd := Vector3(-sin(a), 0, cos(a)) * float(fl.dir)
			var bas := Basis.looking_at(fwd, Vector3.UP).rotated(fwd.normalized(), -0.35 * float(fl.dir))
			# Wings beat in bursts, then glide.
			var beat := sin(_t * 9.0 * float(b.sp) + float(b.ph))
			var flapping := (sin(_t * 0.7 + float(b.ph)) > -0.2) or flee_k > 0.0
			var flap := beat * (0.9 if flapping else 0.1)
			var s := 1.5
			bas = bas * Basis.from_scale(Vector3(s, s * (1.0 + flap * 2.2), s))
			mm.set_instance_transform(i, Transform3D(bas, pos))
