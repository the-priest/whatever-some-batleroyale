extends Node3D
class_name Rain

## Rain weather: streaks falling around the camera that stop on roofs,
## terrain and trees (a height field follows the camera, so it never rains
## indoors), little splashes where they land, a rain bed that is muffled
## under a roof, and now and then lightning with thunder rolling in late.

var game: Node
var world: Node
var quality := 2
var _drops: GPUParticles3D
var _splash: GPUParticles3D
var _field: GPUParticlesCollisionHeightField3D
var _bed: AudioStreamPlayer
var _thunder_t := 12.0
var _flash_t := -1.0
var _flash_k := 0.0
var _sun_base := 0.0
var _amb_base := 0.0
var _sat_base := -1.0
var _no_collide := RenderingServer.get_current_rendering_method() == "gl_compatibility"


func _ready() -> void:
	var counts := [2000, 4200, 7000, 10000]
	var n: int = counts[clampi(quality, 0, 3)]
	_drops = GPUParticles3D.new()
	_drops.amount = n
	_drops.lifetime = 1.3
	_drops.preprocess = 1.3
	_drops.visibility_aabb = AABB(Vector3(-26, -40, -26), Vector3(52, 60, 52))
	_drops.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	# Thick close to you, where streaks read; the fog does the far rain.
	pm.emission_box_extents = Vector3(18, 0.5, 18)
	pm.direction = Vector3(0.12, -1.0, 0.06)
	pm.spread = 3.0
	pm.initial_velocity_min = 20.0
	pm.initial_velocity_max = 25.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.particle_flag_align_y = true
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	pm.collision_use_scale = false
	pm.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_AT_COLLISION
	pm.sub_emitter_amount_at_collision = 1
	_drops.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.022, 0.72)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.8, 0.84, 0.9, 0.3)
	# Soft ends: a streak is a blur of a falling drop, brightest mid-way.
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.set_color(1, Color(1, 1, 1, 0.0))
	g.add_point(0.62, Color(1, 1, 1, 1.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 4
	gt.height = 64
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	m.albedo_texture = gt
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	q.material = m
	_drops.draw_pass_1 = q
	_drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_drops)
	# Splashes where drops land.
	_splash = GPUParticles3D.new()
	_splash.amount = n / 3
	_splash.lifetime = 0.25
	_splash.local_coords = false
	_splash.visibility_aabb = _drops.visibility_aabb
	var sp := ParticleProcessMaterial.new()
	sp.direction = Vector3.UP
	sp.spread = 60.0
	sp.initial_velocity_min = 0.6
	sp.initial_velocity_max = 1.4
	sp.gravity = Vector3(0, -6.0, 0)
	sp.scale_min = 0.5
	sp.scale_max = 1.0
	_splash.process_material = sp
	var sq := QuadMesh.new()
	sq.size = Vector2(0.05, 0.05)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color = Color(0.85, 0.9, 0.95, 0.45)
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sq.material = smat
	_splash.draw_pass_1 = sq
	_splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_splash)
	_drops.sub_emitter = _drops.get_path_to(_splash)
	# Roofs, terrain and trees catch the rain.
	_field = GPUParticlesCollisionHeightField3D.new()
	_field.size = Vector3(64, 80, 64)
	_field.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_256
	_field.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	_field.follow_camera_enabled = true
	add_child(_field)
	# The rain bed.
	if game != null and game.get("sfx") != null:
		var st = game.sfx.stream("rain_loop")
		if st is AudioStreamWAV:
			var wav := (st as AudioStreamWAV).duplicate() as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_end = int(wav.get_length() * float(wav.mix_rate))
			_bed = AudioStreamPlayer.new()
			_bed.stream = wav
			_bed.volume_db = -12.0
			add_child(_bed)
			_bed.play()
	if world != null and world.get("sun") != null:
		_sun_base = world.sun.light_energy
		_amb_base = world.environment.ambient_light_energy
		# Wet, grey light: colours go flat under the cloud.
		_sat_base = world.environment.adjustment_saturation
		world.environment.adjustment_saturation = _sat_base * 0.84


func _exit_tree() -> void:
	# The weather can change between matches mid-flash: leave the light as found.
	if world != null and world.get("sun") != null and _sat_base > 0.0:
		world.sun.light_energy = _sun_base
		world.environment.ambient_light_energy = _amb_base
		world.environment.adjustment_saturation = _sat_base


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := cam.global_position
	# A little ahead of where you look, so you run into rain, not out of it.
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 0.01:
		fwd = fwd.normalized() * 5.0
	_drops.global_position = c + fwd + Vector3(-2.0, 16.0, -1.0)
	# Thick rain is for the ground: from the plane you fly above it.
	var high := false
	if game != null and game.get("terrain") != null:
		high = c.y - float(game.terrain.height_at(c.x, c.z)) > 120.0
	_drops.emitting = not high
	var indoor: bool = game != null and str(game.get("_listener_env")) == "indoor"
	# Without particle collision (Compatibility renderer) roofs cannot stop
	# the streaks, so under one they are simply not drawn.
	if _no_collide:
		_drops.visible = not indoor
		_splash.visible = not indoor
	if _bed != null:
		var want := -30.0 if high else (-19.0 if indoor else -9.0)
		_bed.volume_db = lerpf(_bed.volume_db, want, clampf(delta * 2.0, 0.0, 1.0))
	_lightning(delta)


func _lightning(delta: float) -> void:
	if world == null or world.get("sun") == null:
		return
	_thunder_t -= delta
	if _thunder_t <= 0.0:
		_thunder_t = randf_range(18.0, 45.0)
		_flash_t = 0.0
		var far := randf_range(0.8, 4.0)
		get_tree().create_timer(far, false).timeout.connect(func():
			if game != null and game.get("sfx") != null:
				game.sfx.play_2d("thunder", lerpf(-2.0, -12.0, far / 4.0), 0.1))
	if _flash_t >= 0.0:
		_flash_t += delta
		# Two quick flickers.
		var k := 0.0
		if _flash_t < 0.08:
			k = 1.0
		elif _flash_t > 0.16 and _flash_t < 0.22:
			k = 0.7
		_flash_k = lerpf(_flash_k, k, 0.7)
		if _flash_t > 0.4:
			_flash_t = -1.0
			_flash_k = 0.0
		world.sun.light_energy = _sun_base + _flash_k * 2.5
		world.environment.ambient_light_energy = _amb_base + _flash_k * 1.5
