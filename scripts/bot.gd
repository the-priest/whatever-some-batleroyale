class_name Bot
extends CharacterBody3D

signal eliminated(victim: Bot, killer_name: String)

enum State { PLANE, FALL, CHUTE, GROUND, DEAD }

const WALK := 4.2
const RUN := 7.0
const GRAVITY := 24.0

var bot_name := "BOT"
var game: Node = null
var state: int = State.PLANE
var hp := 100.0
var armor := 0.0
var alive := true

var rig: Node3D
var anim: AnimationPlayer
var weapon_id := ""
var mag := 0
var armed := false
var kills := 0

var drop_target := Vector2.ZERO
var loot_target: LootPickup = null
var enemy: Node3D = null
var fire_timer := 0.0
var think_timer := 0.0
var shoot_skill := 0.55
var reaction := 0.35
var sight := 130.0
var fall_speed := -12.0
var landed := false
var roam_point := Vector2.ZERO
var chute_node: Node3D
var body: SoldierRig
var speed_anim := "Idle"
var hit_flash := 0.0
var dead_timer := 0.0
## A body lies where it fell this long (by its dropped kit), then sinks away.
const BODY_STAYS := 45.0
var head_offset := 1.50

var _loot_scan := 0.0
var _skip_loot: Array[int] = []
var _last_loot_d := 9999.0
var _loot_stuck := 0.0
var _blocked := 0.0
var _muzzle_flash: MeshInstance3D
var _flash := 0.0

# Awareness.
var alert_timer := 0.0
var heard_pos := Vector3.ZERO
var aggression := 0.5
var meds := 0
var vest_level := 0
var helmet_level := 0
var heal_timer := 0.0
var _roam_wait := 0.0
var _progress_t := 0.0
var _progress_pos := Vector3.ZERO
var _step := 0.0
var _burst := 0
var _see_cache := {}
var _shot_seq := 0
var _col: CollisionShape3D
var _cap: CapsuleShape3D
var crouched := false
var calm_t := 0.0
var fight_moving := false
var _probe_t := 0
var _probe_blocked := false
## Which way the probe last went round an obstacle (+1 left, -1 right): kept,
## so a bot follows a wall out of a corner instead of flip-flopping in it.
var _avoid_side := 1.0
var _avoid_dir := Vector3.ZERO
## Backing out of a corner the slide could not get us out of.
var _escape_t := 0.0
var _escape_dir := Vector3.ZERO
var _stuck_n := 0
var _dead_floor := INF
var _dead_vy := 0.0
## Way round cliffs to the roam point, from the terrain's walking grid.
var _tpath := PackedVector2Array()
var _tp_i := 0
var _tp_goal := Vector2.INF
var _fight_t := 0.0
var _fight_dir := Vector3.FORWARD
var _posture_t := 0.0
var _reload_t := 0.0

var last_killer_node: Node = null
## Whether the killing blow was a headshot (for the kill feed).
var last_headshot := false

# --- Network puppets: bots mirrored from the host, and other humans.
## Driven by snapshots instead of AI.
var puppet := false
## A remote human player (not a bot).
var is_human := false
var peer_id := 0
## Index in the host's bot list (bots only).
var net_index := -1
## Squad mate: our bullets pass harmlessly.
var friendly := false
var net_pitch := 0.0
var net_kills := 0
## A remote human riding in a jeep: drawn in the seat, not at the snapshot.
var seated_in: Vehicle = null
var seated_slot := -1
var net_damage := 0.0
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_flags := 0
var _net_seen := false
var _tag: Label3D
## Walking route through doors and up/down stairs: [[Vector3 point, bool indoor], ...].
var _route: Array = []
var _route_goal := Vector3.INF
var _route_replan := 0.0
var _route_stuck := 0.0
var _route_fast := false
## Tests set this so the zone and gunfire do not pick the roam point.
var test_hold_roam := false
## Holding an upstairs window: time left, where, which way to look.
var _camp_t := 0.0
var _camp_cool := 4.0
var _camp_pos := Vector3.ZERO
var _camp_yaw := 0.0

const NF_ALIVE := 1
const NF_CROUCH := 2
const NF_AIM := 4
const NF_RELOAD := 8
const NF_ARMED := 16
const NF_HEAL_BANDAGE := 32
const NF_HEAL_MED := 64
const NF_HEAL_DRINK := 128
const NF_SWIM := 256
const HEAL_FLAGS := {"bandage": NF_HEAL_BANDAGE, "med": NF_HEAL_MED, "energy": NF_HEAL_DRINK}
const HEAL_START_SFX := {"bandage": "bandage_tear", "med": "kit_zip_open", "energy": "can_open"}


static func heal_kind_of(flags: int) -> String:
	if flags & NF_HEAL_BANDAGE:
		return "bandage"
	if flags & NF_HEAL_MED:
		return "med"
	if flags & NF_HEAL_DRINK:
		return "energy"
	return ""

const FOV_COS := 0.42      # ~130 degree cone
const CLOSE_SENSE := 13.0  # always noticed this close


func setup(p_name: String, p_target: Vector2, p_game: Node, seed_n: int) -> void:
	bot_name = p_name
	drop_target = p_target
	game = p_game
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_n
	shoot_skill = rng.randf_range(0.30, 0.82)
	reaction = rng.randf_range(0.35, 0.85)
	sight = rng.randf_range(85.0, 150.0)
	aggression = rng.randf_range(0.2, 0.95)


func _ready() -> void:
	add_to_group("humans" if is_human else "bots")
	add_to_group("damageable")
	# Passengers are inside the hold: nobody should see them through the hull.
	visible = state != State.PLANE
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	floor_max_angle = deg_to_rad(55.0)

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = 1.78
	col.shape = cap
	col.position.y = 0.89
	add_child(col)
	_col = col
	_cap = cap

	body = SoldierRig.new()
	add_child(body)
	# The body you see glides between the 60 Hz physics steps (see _process),
	# so soldiers move smoothly on fast screens.
	body.top_level = true
	body.global_transform = global_transform
	rig = body
	anim = body.anim

	_muzzle_flash = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	_muzzle_flash.mesh = q
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.albedo_color = Color(1.0, 0.85, 0.55, 1.0)
	fm.albedo_texture = Weapons.flash_texture()
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.no_depth_test = true
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_muzzle_flash.material_override = fm
	_muzzle_flash.visible = false
	_muzzle_flash.position = Vector3(0.30, 1.32, -0.95)
	add_child(_muzzle_flash)

	chute_node = Parachute.build()
	chute_node.position = Vector3(0, 0.6, 0)
	chute_node.visible = false
	add_child(chute_node)

	if false:
		# Squad mates get a name tag (now drawn by the HUD).
		_tag = Label3D.new()
		_tag.text = bot_name
		_tag.position = Vector3(0, 2.25, 0)
		_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_tag.no_depth_test = true
		_tag.fixed_size = true
		_tag.pixel_size = 0.0011
		_tag.font_size = 28
		_tag.outline_size = 8
		_tag.modulate = Color(0.45, 0.95, 0.55)
		_tag.font = load("res://assets/fonts/ui_bold.ttf")
		add_child(_tag)


func head_y() -> float:
	return global_position.y + (1.0 if crouched else head_offset)


func _set_crouch(v: bool) -> void:
	if v == crouched:
		return
	crouched = v
	# Shrink the hitbox with the pose so bullets miss the empty space above.
	_cap.height = 1.2 if v else 1.78
	_col.position.y = _cap.height * 0.5


func display_name() -> String:
	return bot_name


# ------------------------------------------------------------------ states --
func jump_from_plane() -> void:
	if state != State.PLANE:
		return
	state = State.FALL
	fall_speed = -10.0
	velocity = Vector3(randf_range(-2, 2), -10.0, randf_range(-2, 2))
	if game != null and game.plane != null:
		velocity += game.plane.jump_velocity()
	visible = true
	_play("Jump_Start")


var _lod_skip := 0.0
var _lod_mult := 1.0
var _lod_odd := false


## Bodies moved with a bigger step when ticking at half rate far away.
func _move() -> void:
	if _lod_mult > 1.0:
		velocity *= _lod_mult
		move_and_slide()
		velocity /= _lod_mult
	else:
		move_and_slide()


func _physics_process(delta: float) -> void:
	if Prof.on:
		var t0 := Time.get_ticks_usec()
		_physics_process_body(delta)
		Prof.add("bots", Time.get_ticks_usec() - t0)
	else:
		_physics_process_body(delta)
	_xf_prev = _xf_cur if _xf_set else global_transform
	_xf_cur = global_transform
	_xf_set = true
	if _xf_prev.origin.distance_to(_xf_cur.origin) > 6.0:
		_xf_prev = _xf_cur


var _xf_prev := Transform3D.IDENTITY
var _xf_cur := Transform3D.IDENTITY
var _xf_set := false


func _process(_delta: float) -> void:
	if body == null:
		return
	if not _xf_set or not is_physics_processing():
		body.global_transform = global_transform
		return
	var xf := _xf_prev.interpolate_with(_xf_cur, clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0))
	# Moved outside the physics step (a teleport, a seat): follow at once.
	if xf.origin.distance_to(global_position) > 6.0:
		xf = global_transform
		_xf_prev = xf
		_xf_cur = xf
	body.global_transform = xf


func _physics_process_body(delta: float) -> void:
	if puppet:
		_puppet_tick(delta)
		return
	# Far from the player (and out of sight range) bots think and move every
	# other tick with a double step: same behaviour, half the cost.
	_lod_mult = 1.0
	if state == State.GROUND or state == State.DEAD:
		var far: bool = game != null and game.player != null and game.player.global_position.distance_squared_to(global_position) > 180.0 * 180.0
		# Doors and stairs need every tick to stay on the line.
		if far and not (not _route.is_empty() and bool(_route[0][1])):
			_lod_odd = not _lod_odd
			if _lod_odd:
				_lod_skip = delta
				return
			delta += _lod_skip
			_lod_mult = 2.0
	_lod_skip = 0.0
	if state == State.DEAD:
		dead_timer += delta
		velocity.x = move_toward(velocity.x, 0.0, 6.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 6.0 * delta)
		if dead_timer <= 7.0:
			# A body falls like anything else: shot mid-jump, off a ledge or
			# thrown by a jeep, it comes down instead of drifting on up.
			if is_on_floor():
				velocity.y = minf(velocity.y, 0.0)
			velocity.y = maxf(velocity.y - GRAVITY * delta, -50.0)
			_move()
		elif dead_timer > BODY_STAYS:
			# Settle into the ground rather than vanish.
			position.y -= delta * 0.6
		if dead_timer > BODY_STAYS + 3.0:
			queue_free()
		return

	fire_timer = maxf(0.0, fire_timer - delta)
	think_timer -= delta
	_flash = maxf(0.0, _flash - delta)
	_muzzle_flash.visible = _flash > 0.0
	if hit_flash > 0.0:
		hit_flash = maxf(0.0, hit_flash - delta)

	match state:
		State.PLANE:
			_follow_plane(delta)
		State.FALL:
			_fall(delta, false)
		State.CHUTE:
			_fall(delta, true)
		State.GROUND:
			_ground(delta)


func _follow_plane(delta: float) -> void:
	velocity = Vector3.ZERO
	if game != null and game.plane != null:
		var p: DropPlane = game.plane
		var seat := p.seat_position() + p.global_basis * Vector3(randf_range(-0.9, 0.9), -0.1, randf_range(-1.2, 0.4))
		global_position = global_position.lerp(seat, clampf(delta * 6.0, 0.0, 1.0))
		rotation.y = lerp_angle(rotation.y, p.rotation.y, delta * 3.0)


func _fall(delta: float, chute: bool) -> void:
	var to := Vector2(drop_target.x - global_position.x, drop_target.y - global_position.z)
	var dist := to.length()
	var move := to.normalized() * minf(dist, 13.0 if chute else 34.0)
	velocity.x = move_toward(velocity.x, move.x, 16.0 * delta)
	velocity.z = move_toward(velocity.z, move.y, 16.0 * delta)
	if chute:
		velocity.y = move_toward(velocity.y, -7.5, 30.0 * delta)
	else:
		fall_speed = move_toward(fall_speed, -52.0, 80.0 * delta)
		velocity.y = fall_speed
		# Pull early when the target is still far: the canopy glides further
		# than freefall does.
		var agl := global_position.y - game_ground_y()
		if agl < 110.0 or dist > (agl - 110.0) * 0.65 + 180.0:
			state = State.CHUTE
			chute_node.visible = true
			_play("Jump_Start")
	move_and_slide()
	if chute:
		chute_node.rotation.y = sin(Time.get_ticks_msec() * 0.0009 + randf()) * 0.08
	rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.y), delta * 2.0)
	_play("Jump" if not chute else "Idle")
	if is_on_floor() or global_position.y <= game_ground_y() + 0.6:
		_land()


func game_ground_y() -> float:
	if game != null and game.terrain != null:
		return float(game.terrain.height_at(global_position.x, global_position.z))
	return 0.0


func _land() -> void:
	if state == State.GROUND:
		return
	state = State.GROUND
	landed = true
	chute_node.visible = false
	velocity = Vector3.ZERO
	global_position.y = game_ground_y() + 1.4
	_play("Jump_Land")
	roam_point = drop_target
	# Fresh off the plane, people loot first and only fight what is in their face.
	calm_t = randf_range(60.0, 150.0)
	if game != null and game.has_method("on_bot_landed"):
		game.on_bot_landed(self)


func _ground(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	alert_timer = maxf(0.0, alert_timer - delta)
	calm_t = maxf(0.0, calm_t - delta)
	_shoot_logic(delta)
	if heal_timer > 0.0:
		heal_timer -= delta
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
		if heal_timer < 1.4 and heal_timer + delta >= 1.4:
			_heal_sound("syringe_inject", -6.0)
		if heal_timer <= 0.0 and meds > 0:
			meds -= 1
			hp = minf(100.0, hp + 50.0)
			_heal_sound("kit_zip_close", -8.0)
		_move()
		_ground_safety()
		_animate_ground()
		# Standing still on purpose: not stuck.
		_progress_t = 0.0
		_progress_pos = global_position
		return
	var safe := enemy == null or not is_instance_valid(enemy) or (_tactic == "hide" and _hidden_t > 0.6 and _hurt_t > 2.0)
	if armed and meds > 0 and hp < (62.0 if _tactic == "hide" else 55.0) and safe and not in_deep_water():
		heal_timer = 3.0
		_heal_sound("kit_zip_open", -6.0)
		return

	var target_pos := global_position
	var want_sprint := false
	var stop_dist := 0.0

	_hurt_t += delta
	_hit_them_t += delta
	var sees := armed and enemy != null and is_instance_valid(enemy) and enemy_visible()
	# A fight does not end the moment they duck out of sight: the bot keeps
	# working the last place it saw them for a while.
	var memory := 26.0 if _tactic in ["push", "flank"] else 14.0
	var fighting := sees or (armed and enemy != null and is_instance_valid(enemy) and bool(enemy.get("alive")) and _last_seen_t < memory)
	if not fighting:
		if loot_target == null or not is_instance_valid(loot_target) or loot_target.taken:
			loot_target = null
			_loot_scan -= delta
			if _loot_scan <= 0.0:
				_loot_scan = 0.8 if not armed else 1.6
				loot_target = _find_loot()
	if not armed or (not fighting and loot_target != null):
		if loot_target != null:
			target_pos = loot_target.global_position
			stop_dist = 1.8
			want_sprint = true
		else:
			if Vector2(global_position.x, global_position.z).distance_to(roam_point) < 3.5:
				_pick_roam_point()
			var leg := _terrain_leg(roam_point)
			target_pos = Vector3(leg.x, global_position.y, leg.y)
			stop_dist = 3.0 if leg == roam_point else 0.0
	else:
		if _camp_t > 0.0 and _camp_pos.distance_to(global_position) < 1.5 and sees:
			# Holding a window: no dashing about the room. Pop up and shoot,
			# then duck below the sill, then up again.
			_fight_t -= delta
			fight_moving = false
			if _fight_t <= 0.0:
				var ducking := not crouched and randf() < 0.45
				_set_crouch(ducking)
				_fight_t = randf_range(0.8, 1.6) if ducking else randf_range(1.6, 3.2)
			_fight_t = minf(_fight_t, 3.2)
			target_pos = global_position
			stop_dist = 1.0
		elif fighting:
			var plan := _combat(delta, sees)
			target_pos = plan[0]
			stop_dist = float(plan[1])
			want_sprint = bool(plan[2])
		elif _camp_t > 0.0 and crouched and _fight_t > 0.0 and enemy != null and is_instance_valid(enemy):
			# Ducked below a window sill: stay down until it is time to pop up.
			_fight_t -= delta
			target_pos = global_position
			stop_dist = 1.0
		else:
			enemy = null
			_set_crouch(false)
			fight_moving = false
			var here := Vector2(global_position.x, global_position.z)
			var must_move := false
			if game != null and game.zone != null and not test_hold_roam:
				var zc: Vector2 = game.zone.center
				var r: float = game.zone.radius
				# Head for safety early, not when the storm is already on top of us.
				var nr: float = game.zone.next_radius()
				var nc: Vector2 = game.zone.next_center()
				# Rotate when the storm is coming or we are well outside the
				# next circle; otherwise keep to our own area.
				must_move = here.distance_to(zc) > r * 0.8 or (game.zone.warning and here.distance_to(nc) > nr * 0.9)
				if must_move and roam_point.distance_to(nc) > nr * 0.85:
					roam_point = nc + (here - nc).normalized() * (nr * randf_range(0.45, 0.8))
					roam_point += Vector2(randf_range(-10, 10), randf_range(-10, 10))
			if alert_timer > 0.0 and aggression > 0.6 and heard_pos.distance_to(global_position) > 10.0 and not test_hold_roam:
				# Go and see who is shooting.
				roam_point = Vector2(heard_pos.x, heard_pos.z)
			_camp_cool -= delta
			if _camp_t > 0.0 and (must_move or (alert_timer > 0.0 and aggression > 0.75)):
				_camp_t = 0.0
			if _camp_t <= 0.0 and armed and _camp_cool <= 0.0 and not must_move and not test_hold_roam:
				_camp_cool = 8.0
				_try_camp()
			if _camp_t > 0.0:
				# Holding a window upstairs: stand at it and watch the street.
				_camp_t -= delta
				target_pos = _camp_pos
				stop_dist = 0.35
				want_sprint = false
			else:
				if here.distance_to(roam_point) < 3.0:
					_roam_wait -= delta
					if _roam_wait <= 0.0:
						_roam_wait = randf_range(1.0, 5.0)
						_pick_roam_point()
				var leg := _terrain_leg(roam_point)
				target_pos = Vector3(leg.x, global_position.y, leg.y)
				stop_dist = 2.5 if leg == roam_point else 0.0
				want_sprint = alert_timer <= 0.0

	var routing := false
	if not fighting:
		var goal_up := (loot_target != null and target_pos.is_equal_approx(loot_target.global_position)) or (_camp_t > 0.0 and target_pos.is_equal_approx(_camp_pos))
		var wp := _routed(target_pos, goal_up, delta)
		if not wp.is_equal_approx(target_pos):
			target_pos = wp
			stop_dist = 0.0
			routing = true
			# Indoors and on stairs: walk, do not sprint into the door frame.
			# Treetop Town's stair is wide and open: run it.
			if bool(_route[0][1]) and not _route_fast:
				want_sprint = false
	else:
		_route.clear()
		_route_goal = Vector3.INF

	var flat := Vector3(target_pos.x - global_position.x, 0, target_pos.z - global_position.z)
	var dist := flat.length()
	var speed := RUN if want_sprint else WALK
	if crouched:
		speed = 1.8
	if loot_target != null and target_pos.is_equal_approx(loot_target.global_position):
		if dist < _last_loot_d - 0.5:
			_last_loot_d = dist
			_loot_stuck = 0.0
		else:
			_loot_stuck += delta
		if _loot_stuck > 3.5:
			_skip_loot.append(loot_target.get_instance_id())
			loot_target = null
			_loot_stuck = 0.0
			_last_loot_d = 9999.0
			dist = 9999.0
	if dist <= stop_dist:
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
		if _camp_t > 0.0 and not fighting and not routing:
			rotation.y = lerp_angle(rotation.y, _camp_yaw, clampf(delta * 4.0, 0.0, 1.0))
		if loot_target != null and is_instance_valid(loot_target) and not loot_target.taken:
			if loot_target.global_position.distance_to(global_position) < 2.8:
				_take_loot(loot_target)
	else:
		var dir := flat.normalized()
		# Obstacle probe, refreshed every few ticks: walls do not move.
		var space := get_world_3d().direct_space_state
		_probe_t -= 1
		if _probe_t <= 0:
			_probe_t = 4
			_probe_blocked = _ray_blocked(space, dir, 1.6)
			_avoid_dir = Vector3.ZERO
			if _probe_blocked:
				# Go round on whichever side is open, keeping the side we
				# went last time; with both shut, back off.
				for deg in [55.0, -55.0, 100.0, -100.0]:
					var d2 := dir.rotated(Vector3.UP, deg_to_rad(deg * _avoid_side))
					if not _ray_blocked(space, d2, 1.6):
						_avoid_dir = d2
						_avoid_side *= signf(deg)
						break
				if _avoid_dir == Vector3.ZERO:
					_avoid_dir = -dir
		# Inside a house the route is exact: the probe would only see the
		# stair treads ahead and steer off them.
		if _probe_blocked and not (routing and bool(_route[0][1])):
			dir = _avoid_dir if _avoid_dir != Vector3.ZERO else dir.rotated(Vector3.UP, deg_to_rad(70.0))
		if _escape_t > 0.0:
			_escape_t -= delta
			dir = _escape_dir
		if game != null and game.terrain != null and bool(game.terrain.is_water(global_position.x, global_position.z)):
			speed *= 0.5
		velocity.x = move_toward(velocity.x, dir.x * speed, 26.0 * delta)
		velocity.z = move_toward(velocity.z, dir.z * speed, 26.0 * delta)
		if not fighting or fight_moving:
			rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), clampf(delta * 10.0, 0.0, 1.0))
		_blocked -= delta
		if _blocked <= 0.0 and _probe_t == 4 and is_on_floor() and dist > 3.0 and not routing:
			var q2 := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.4, global_position + Vector3.UP * 0.4 + dir * 0.9, 1)
			q2.exclude = [get_rid()]
			if not space.intersect_ray(q2).is_empty():
				velocity.y = 5.2
				_blocked = 1.2

	var wish := Vector3(velocity.x, 0.0, velocity.z)
	var grounded_before := is_on_floor()
	_move()
	_step_up(wish, grounded_before)
	_ground_safety()
	_animate_ground()
	# Stuck detection: if we have barely moved in a while, try somewhere else.
	_progress_t += delta
	if _progress_t > 3.0:
		if global_position.distance_to(_progress_pos) < 1.2 and dist > stop_dist + 1.0:
			_unstick()
			_pick_roam_point()
			_route.clear()
			_route_goal = Vector3.INF
			if loot_target != null:
				_skip_loot.append(loot_target.get_instance_id())
				loot_target = null
			if is_on_floor():
				velocity.y = 5.2
		elif global_position.distance_to(_progress_pos) > 3.0:
			_stuck_n = maxi(0, _stuck_n - 1)
		_progress_pos = global_position
		_progress_t = 0.0


## Next point on the way to a roam goal: the goal itself, or the next turn of
## a path round the cliffs between us.
func _terrain_leg(goal: Vector2) -> Vector2:
	if game == null or game.terrain == null:
		return goal
	var here := Vector2(global_position.x, global_position.z)
	if goal.distance_to(_tp_goal) > 6.0:
		var res: Dictionary = game.terrain.walk_path(here, goal)
		if not bool(res.ok):
			return goal  # Out of searches this frame: ask again next frame.
		_tp_goal = goal
		_tpath = res.path
		_tp_i = 0
	while _tp_i < _tpath.size() and here.distance_to(_tpath[_tp_i]) < 4.0:
		_tp_i += 1
	if _tp_i >= _tpath.size():
		return goal
	return _tpath[_tp_i]


# ------------------------------------------------------------------ combat --
## Fighting like a person: get behind something solid (a trunk, a rock, a
## wall, the brow of a hill), lean out to shoot in bursts and duck back in to
## reload or patch up; push an enemy who is hurt or hiding, flank one who
## holds an angle, flush them out with a grenade. Out in the open with
## nothing to hide behind: shoot from a crouch and dash between bursts.
var _tactic := ""
var _tactic_t := 0.0
var _cover := Vector3.INF
var _peek := Vector3.INF
var _cover_eval := 0.0
var _last_seen := Vector3.INF
var _last_seen_t := 99.0
var _engage_t := 0.0
var _hidden_t := 0.0
var _hurt_t := 99.0
var _hit_them_t := 99.0
var _flank := Vector3.INF
var _foe_id := 0
var _push_side := 0.0
var grenades := 0
var _nade_cd := 4.0


func _hold_range() -> float:
	match Weapons.cls(weapon_id):
		"smg", "pistol":
			return 16.0
		"shotgun":
			return 8.0
		"dmr", "sniper":
			return 90.0
		"lmg":
			return 55.0
	return 45.0


## One of our rounds hit someone (from the ballistics).
func on_bullet_hit(_shot_id: int, _pos: Vector3, _dmg: float, _headshot: bool, _killed: bool) -> void:
	_hit_them_t = 0.0


## Forget the current fight (cover, tactic, where the enemy was).
func reset_combat() -> void:
	enemy = null
	_foe_id = 0
	_cover = Vector3.INF
	_peek = Vector3.INF
	_flank = Vector3.INF
	_last_seen = Vector3.INF
	_last_seen_t = 99.0
	_hidden_t = 0.0
	_engage_t = 0.0
	_set_tactic("", 0.0)


func _set_tactic(t: String, dur: float) -> void:
	if t == "push" and _tactic != "push":
		_push_side = 0.0
	_tactic = t
	_tactic_t = dur


## [target, stop distance, sprint] for this tick of a fight.
func _combat(delta: float, sees: bool) -> Array:
	var e := enemy as Node3D
	if e.get_instance_id() != _foe_id:
		_foe_id = e.get_instance_id()
		_engage_t = 0.0
		_cover = Vector3.INF
		_peek = Vector3.INF
		_cover_eval = 0.0
		_set_tactic("", 0.0)
	_engage_t += delta
	_tactic_t -= delta
	_cover_eval -= delta
	_nade_cd -= delta
	if sees:
		_last_seen = e.global_position
		_last_seen_t = 0.0
		_hidden_t = 0.0
	else:
		_last_seen_t += delta
		_hidden_t += delta
	var here := global_position
	var ep := _last_seen if _last_seen != Vector3.INF else e.global_position
	var to_e := Vector3(ep.x - here.x, 0, ep.z - here.z)
	var d := to_e.length()
	to_e = to_e / maxf(d, 0.01)
	var hold := _hold_range()
	# Cover we have ended up far from is no use to us now.
	if _cover != Vector3.INF and _flat_d(here, _cover) > 20.0:
		_cover = Vector3.INF
		_peek = Vector3.INF
		if _tactic in ["dash", "hide", "peek"]:
			_set_tactic("", 0.0)
	# The enemy moved round our cover: it is not cover any more.
	if _cover != Vector3.INF and _cover_eval <= 0.0:
		_cover_eval = 1.2
		if not _hidden_from(_cover, ep):
			_cover = Vector3.INF
			_peek = Vector3.INF
			if _tactic in ["hide", "peek"]:
				_set_tactic("", 0.0)
	# Look for cover when the fight starts, when hit out in the open, or
	# every few seconds while exposed.
	if _cover == Vector3.INF and _cover_eval <= 0.0 and _tactic not in ["push", "flank"]:
		var found := _find_cover(ep, hold)
		_cover_eval = 1.0 if not found.is_empty() else (1.2 if _hurt_t < 1.0 else 3.0)
		if not found.is_empty():
			_cover = found[0]
			_peek = found[1]
			_set_tactic("dash", 6.0)
	# Pre-aim where they were: when we lean out the gun is already there.
	if not fight_moving or _tactic in ["hide", "peek"]:
		rotation.y = lerp_angle(rotation.y, atan2(-to_e.x, -to_e.z), clampf(delta * 8.0, 0.0, 1.0))
	match _tactic:
		"dash":
			fight_moving = true
			_set_crouch(false)
			if _cover == Vector3.INF or _tactic_t <= 0.0:
				_set_tactic("", 0.0)
			elif _flat_d(here, _cover) < 0.8:
				_set_tactic("hide", randf_range(0.6, 1.4))
			else:
				return [_cover, 0.0, true]
		"hide":
			fight_moving = false
			_set_crouch(true)
			if _cover == Vector3.INF:
				_set_tactic("", 0.0)
			else:
				# Reload out of sight rather than in the middle of a burst.
				if mag < int(Weapons.def(weapon_id)["mag"]) / 2 and _reload_t <= 0.0:
					_start_reload()
				if _wants_grenade(d, sees):
					_throw_nade(ep)
				if _tactic_t <= 0.0 and heal_timer <= 0.0 and _reload_t <= 0.0:
					if _hidden_t > 7.0 and _last_seen_t > 7.0:
						_set_tactic("push" if (aggression > 0.55 or _hit_them_t < 8.0) else "flank", 0.0)
					elif _engage_t > 20.0 and _hurt_t > 9.0 and _hit_them_t > 9.0 and hp > 45.0:
						# Trading peeks and nobody is getting hurt: stop waiting
						# for them to make a mistake and go round.
						_engage_t = 6.0
						_set_tactic("flank" if aggression < 0.6 else "push", 0.0)
					else:
						_set_tactic("peek", randf_range(1.2, 2.6))
						fire_timer = maxf(fire_timer, reaction * 0.5)
				return [_cover, 0.0, false]
		"peek":
			if _peek == Vector3.INF or _cover == Vector3.INF:
				_set_tactic("", 0.0)
			else:
				var at_peek := _flat_d(here, _peek) < 0.6
				fight_moving = not at_peek
				_set_crouch(false)
				# Hit while leaning out, or the burst is done: back in.
				if _hurt_t < 0.25 or _tactic_t <= 0.0:
					_set_tactic("hide", randf_range(0.7, 1.8))
				elif at_peek and not sees and _tactic_t < 0.8:
					# Nobody there any more: they moved. Try again from cover.
					_cover_eval = 0.0
					_set_tactic("hide", 0.4)
				return [_peek, 0.0, false]
		"push":
			fight_moving = not sees or d > hold + 10.0
			_set_crouch(false)
			# Soften them up before going in.
			if _wants_grenade(d, sees):
				_throw_nade(ep)
			if sees and d < hold + 10.0:
				# Caught them: fight it out from here.
				_set_tactic("", 0.0)
				_cover_eval = 0.0
			elif _flat_d(here, ep) < 3.0 and not sees:
				# They are not where we left them: give it up.
				enemy = null
				_last_seen = Vector3.INF
				_last_seen_t = 99.0
				_set_tactic("", 0.0)
			else:
				# Not at the spot itself (they are behind something there):
				# round it on one side, closing in as we go.
				if _push_side == 0.0:
					_push_side = 1.0 if randf() < 0.5 else -1.0
				var side := Vector3(-to_e.z, 0, to_e.x) * _push_side
				var aim := ep + side * clampf(d * 0.3, 0.0, 7.0)
				if d < 15.0:
					# Close and still nothing: work round them at a few
					# metres until we can see past whatever they are behind.
					aim = ep + (-to_e).rotated(Vector3.UP, _push_side * deg_to_rad(70.0)) * 7.0
				var leg := _terrain_leg(Vector2(aim.x, aim.z))
				return [Vector3(leg.x, here.y, leg.y), 0.0, d > 18.0]
		"flank":
			if _flank == Vector3.INF:
				# Round them by a right angle at about the same range.
				var side := 1.0 if randf() < 0.5 else -1.0
				var rel := (here - ep)
				rel.y = 0.0
				var r := clampf(rel.length(), hold * 0.6, hold * 1.2)
				var dir := rel.normalized().rotated(Vector3.UP, side * deg_to_rad(80.0))
				_flank = ep + dir * r
				_flank.y = here.y
				_tactic_t = 14.0
			fight_moving = true
			_set_crouch(false)
			if sees or _tactic_t <= 0.0 or _flat_d(here, _flank) < 3.0:
				_flank = Vector3.INF
				_cover = Vector3.INF
				_cover_eval = 0.0
				_set_tactic("", 0.0)
			else:
				var leg2 := _terrain_leg(Vector2(_flank.x, _flank.z))
				return [Vector3(leg2.x, here.y, leg2.y), 0.0, true]
	# No cover to use: fight in the open. Hold still (crouched at range) and
	# shoot, then dash sideways to a new spot, closing or opening the range.
	if not sees:
		# Lost them and nothing to hide behind: go and look.
		if _last_seen_t > 2.5:
			_set_tactic("push", 0.0)
		fight_moving = false
		return [here, 1.0, false]
	_fight_t -= delta
	if _fight_t <= 0.0:
		fight_moving = not fight_moving
		if fight_moving:
			_set_crouch(false)
			_fight_t = randf_range(0.6, 1.3) * (1.6 if d > hold + 10.0 else 1.0)
			var side := Vector3(-to_e.z, 0, to_e.x) * (1.0 if randf() < 0.5 else -1.0)
			var push := 0.0
			if d > hold + 6.0:
				push = 1.0
			elif d < hold - 8.0:
				push = -0.8
			_fight_dir = (side * (1.0 - absf(push) * 0.6) + to_e * push).normalized()
			# Never dash off a ledge, down a stairwell or out of a window.
			if not _floor_ahead(_fight_dir):
				var alt := (-side * (1.0 - absf(push) * 0.6) + to_e * push).normalized()
				if _floor_ahead(alt):
					_fight_dir = alt
				else:
					fight_moving = false
					_fight_t = randf_range(1.4, 3.0)
		else:
			_fight_t = randf_range(1.2, 3.0)
			_set_crouch(d > 25.0 and randf() < 0.45 + shoot_skill * 0.35)
	if fight_moving:
		return [here + _fight_dir * 6.0, 0.0, true]
	return [here, 1.0, false]


func _flat_d(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Is a body at `p` (crouched) out of sight of someone standing at `ep`?
func _hidden_from(p: Vector3, ep: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(ep + Vector3.UP * 1.5, p + Vector3.UP * 1.0, 1)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## The nearest spot out of the enemy's sight that has somewhere to lean out
## from and shoot (step to the side, or stand up over low cover):
## [cover, peek], or [] when there is none within reach.
func _find_cover(ep: Vector3, hold: float) -> Array:
	if game == null:
		return []
	var space := get_world_3d().direct_space_state
	var here := global_position
	var eye := ep + Vector3.UP * 1.5
	var best: Array = []
	var best_score := INF
	var a0 := randf() * TAU
	for r in [2.5, 5.0, 8.5, 12.5]:
		for k in 8:
			var a := a0 + TAU * float(k) / 8.0
			var c: Vector3 = game.ground_at(here + Vector3(cos(a), 0.0, sin(a)) * float(r) + Vector3.UP * 1.0)
			if absf(c.y - here.y) > 1.8:
				continue
			if game.terrain != null and bool(game.terrain.is_water(c.x, c.z)):
				continue
			# Out of sight at crouch height.
			var hid := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, c + Vector3.UP * 1.0, 1))
			if hid.is_empty():
				continue
			# Straight run to it.
			if not space.intersect_ray(PhysicsRayQueryParameters3D.create(here + Vector3.UP * 0.9, c + Vector3.UP * 0.9, 1)).is_empty():
				continue
			# Somewhere to shoot from: stand up over it, or lean out a step.
			var peek := Vector3.INF
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(c + Vector3.UP * 1.65, eye, 1)).is_empty():
				peek = c
			else:
				var fe := Vector3(ep.x - c.x, 0, ep.z - c.z).normalized()
				var side := Vector3(-fe.z, 0, fe.x)
				for sd in [1.0, -1.0]:
					var pp: Vector3 = c + side * float(sd) * 1.3
					if not space.intersect_ray(PhysicsRayQueryParameters3D.create(c + Vector3.UP * 0.9, pp + Vector3.UP * 0.9, 1)).is_empty():
						continue
					if space.intersect_ray(PhysicsRayQueryParameters3D.create(pp + Vector3.UP * 1.35, eye, 1)).is_empty():
						peek = pp
						break
			if peek == Vector3.INF:
				continue
			# Close cover with the blocker right beside it, at a range the gun
			# likes, not closer to the enemy than we already are.
			var blocker_d: float = (hid["position"] as Vector3).distance_to(c)
			var de := _flat_d(c, ep)
			var score: float = float(r) + blocker_d * 0.6 + absf(de - hold) * 0.04 + maxf(0.0, _flat_d(here, ep) - de - 4.0) * 0.5
			if score < best_score:
				best_score = score
				best = [c + Vector3.UP * 0.05, peek + Vector3.UP * 0.05]
		if not best.is_empty():
			return best
	return best


func _start_reload() -> void:
	var d: Dictionary = Weapons.def(weapon_id)
	mag = int(d["mag"])
	fire_timer = float(d["reload"])
	_reload_t = float(d["reload"])
	if game != null and game.player != null and game.player.global_position.distance_to(global_position) < 30.0:
		# Enemies are heard reloading: a cue to push.
		var c := Weapons.cls(weapon_id)
		if c == "shotgun":
			for k in 3:
				game._delayed_sfx("rl_shotgun_shell", global_position, -5.0, 0.4 + k * 0.5, 0.05)
		else:
			if c not in ["ar", "smg", "pistol", "lmg", "dmr", "sniper"]:
				c = "ar"
			game.play_sfx_at("rl_%s_out" % c, global_position, -4.0)
			game._delayed_sfx("rl_%s_in" % c, global_position, -3.0, _reload_t * 0.55, 0.05)
			game._delayed_sfx("rl_%s_rack" % c, global_position, -4.0, _reload_t * 0.75, 0.05)


## Someone is dug in out of sight at grenade range: flush them out.
func _wants_grenade(d: float, sees: bool) -> bool:
	return grenades > 0 and _nade_cd <= 0.0 and not sees and _hidden_t > 1.5 and _last_seen_t < 10.0 and d > 9.0 and d < 34.0


func _throw_nade(at: Vector3) -> void:
	var from := global_position + Vector3.UP * 1.6 - global_basis.z * 0.4
	var flat := Vector3(at.x - from.x, 0.0, at.z - from.z)
	var dist := flat.length()
	var h := at.y + 0.3 - from.y
	var th := deg_to_rad(40.0)
	var denom := 2.0 * cos(th) * cos(th) * (dist * tan(th) - h)
	if denom <= 0.1:
		return
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var v := minf(sqrt(g * dist * dist / denom) * 1.04, 24.0)
	var vel := flat.normalized() * v * cos(th) + Vector3.UP * v * sin(th)
	# Make sure the arc is not blocked right in front of us (a wall, a trunk).
	var q := PhysicsRayQueryParameters3D.create(from, from + vel.normalized() * 3.0, 1)
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		_nade_cd = 2.0
		return
	grenades -= 1
	_nade_cd = randf_range(7.0, 12.0)
	var gr := Grenade.new()
	gr.game = game
	gr.thrower = self
	game.add_child(gr)
	gr.global_position = from
	gr.linear_velocity = vel
	gr.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	if body != null:
		body.play_throw()
	if game.has_method("net_bot_grenade"):
		game.net_bot_grenade(self, from, vel)


func _ray_blocked(space: PhysicsDirectSpaceState3D, dir: Vector3, length: float) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.0, global_position + Vector3.UP * 1.0 + dir * length, 1)
	q.exclude = [get_rid()]
	return not space.intersect_ray(q).is_empty()


## No headway for a few seconds: back away from whatever we are pressed
## against (the walls' own normals say which way is out), and if that keeps
## failing, step to the nearest free bit of ground.
func _unstick() -> void:
	_stuck_n += 1
	_tp_goal = Vector2.INF
	var away := Vector3.ZERO
	for ci in get_slide_collision_count():
		var nrm := get_slide_collision(ci).get_normal()
		if absf(nrm.y) < 0.7:
			away += Vector3(nrm.x, 0.0, nrm.z)
	if away.length() < 0.1:
		away = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	_escape_dir = away.normalized().rotated(Vector3.UP, randf_range(-0.6, 0.6))
	_escape_t = 0.8 + 0.4 * float(mini(_stuck_n, 4))
	if enemy != null:
		# Mid-fight a short step back is enough; a long run hands them the
		# initiative.
		_escape_t = minf(_escape_t, 0.6)
	_avoid_side = -_avoid_side
	if _stuck_n >= 4:
		_nudge_free()


func _nudge_free() -> void:
	if game == null:
		return
	var space := get_world_3d().direct_space_state
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = _cap
	sq.collision_mask = 1
	sq.exclude = [get_rid()]
	var a0 := randf() * TAU
	for r in [1.6, 2.6, 4.0, 6.0]:
		for k in 12:
			var a := a0 + float(k) * TAU / 12.0
			var p: Vector3 = global_position + Vector3(cos(a), 0.0, sin(a)) * r
			var g: Vector3 = game.ground_at(p + Vector3.UP * 1.0)
			# Ground at about our level or a short drop below: not a roof or a
			# ledge above us.
			if g.y - global_position.y > 1.6 or global_position.y - g.y > 8.0:
				continue
			sq.transform = Transform3D(Basis.IDENTITY, g + Vector3.UP * 1.0)
			if not space.intersect_shape(sq, 1).is_empty():
				continue
			global_position = g + Vector3.UP * 0.05
			velocity = Vector3.ZERO
			_stuck_n = 0
			return


## Is there floor at about our height a dash-length ahead?
func _floor_ahead(dir: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	for dist in [1.0, 2.2]:
		var p := global_position + dir * float(dist) + Vector3.UP * 1.0
		var q := PhysicsRayQueryParameters3D.create(p, p - Vector3.UP * 2.2, 1)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			# Open terrain has no collider under some LOD tiles: trust the heightmap.
			if game != null and game.terrain != null and global_position.y - game_ground_y() < 0.6:
				var gy: float = game.terrain.height_at(p.x, p.z)
				if absf(gy - global_position.y) < 1.2:
					continue
			return false
	return true


## Upstairs in a house with a gun and in no hurry? Cautious bots sometimes
## take a window and hold it for a while, PUBG style.
func _try_camp() -> void:
	if game == null or game.world == null or game.world.villages == null:
		return
	if global_position.y - game_ground_y() < 2.2 or randf() > (1.0 - aggression) * 0.9:
		return
	var vil: Villages = game.world.villages
	var h := vil.house_at(Vector2(global_position.x, global_position.z), 0.0)
	if h.is_empty() or int(h.get("built_levels", 1)) < 2:
		return
	var nav := vil.house_nav(h)
	if global_position.y < float(nav.floor_y) - 1.0:
		return
	var w := float(h.w)
	var d := float(h.d)
	var b := Basis(Vector3.UP, float(h.yaw))
	var o := Vector3((h.center as Vector2).x, float(nav.floor_y), (h.center as Vector2).y)
	var space := get_world_3d().direct_space_state
	for attempt in 6:
		# Any wall but the stair wall (+x); keep clear of the stairwell.
		# Watch the street first: the door side, unless the stair is on it.
		var door := int(h.door_side)
		var side: int = door if attempt < 3 and door != 1 else [0, 2, 3][randi() % 3]
		var local := Vector3.ZERO
		var out_dir := Vector3.ZERO
		match side:
			0:
				local = Vector3(randf_range(-w * 0.5 + 1.0, w * 0.5 - 2.4), 0, d * 0.5 - 0.75)
				out_dir = Vector3(0, 0, 1)
			2:
				local = Vector3(randf_range(-w * 0.5 + 1.0, w * 0.5 - 2.4), 0, -d * 0.5 + 0.75)
				out_dir = Vector3(0, 0, -1)
			_:
				local = Vector3(-w * 0.5 + 0.75, 0, randf_range(-d * 0.5 + 1.0, d * 0.5 - 1.0))
				out_dir = Vector3(-1, 0, 0)
		var p := o + b * local
		var od := b * out_dir
		# Only a spot with an actual window in front of it.
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.5, p + Vector3.UP * 1.5 + od * 2.0, 1)
		if not space.intersect_ray(q).is_empty():
			continue
		_camp_pos = p + Vector3.UP * 0.05
		_camp_yaw = atan2(-od.x, -od.z)
		_camp_t = randf_range(20.0, 55.0)
		return


## Next point to walk to on the way to `goal`: through the door of a house
## and up or down its stairs when the goal (or the bot) is inside one.
func _routed(goal: Vector3, goal_up: bool, delta: float) -> Vector3:
	if game == null or game.world == null or game.world.villages == null:
		return goal
	var vil: Villages = game.world.villages
	_route_replan -= delta
	# Compare goals on the ground plane: roam goals ride along at our own
	# height, which changes on every stair.
	var moved := Vector2(goal.x - _route_goal.x, goal.z - _route_goal.z).length() > 2.0 if _route_goal != Vector3.INF else true
	if moved or (_route.is_empty() and _route_replan <= 0.0):
		_route_replan = 0.6
		_route_goal = goal
		_route = _plan_route(vil, goal, goal_up)
		_route_stuck = 0.0
	while not _route.is_empty():
		var p: Vector3 = _route[0][0]
		var flat := Vector2(p.x - global_position.x, p.z - global_position.z).length()
		# Points on the stair also need the height, so a bot standing under
		# the stair top does not count as having climbed it.
		if flat < 0.55 and absf(p.y - global_position.y) < (0.7 if _route_fast else 1.2):
			_route.pop_front()
			_route_stuck = 0.0
			continue
		break
	if _route.is_empty():
		return goal
	_route_stuck += delta
	if _route_stuck > 6.0:
		# Something is in the way: drop the route and let the stuck logic
		# pick something else. Up the giant tree, plan again from here.
		_route.clear()
		_route_replan = 0.2 if _route_fast else 3.0
		return goal
	return _route[0][0]


func _plan_route(vil: Villages, goal: Vector3, goal_up: bool) -> Array:
	var tree_route := _tree_town_route(vil, goal, goal_up)
	_route_fast = not tree_route.is_empty()
	if not tree_route.is_empty() or _on_tree_town(vil, global_position):
		return tree_route
	var me := Vector2(global_position.x, global_position.z)
	var hb := vil.house_at(me, 0.1)
	var ht := vil.house_at(Vector2(goal.x, goal.z), -0.2)
	var out: Array = []
	if not hb.is_empty():
		var nav := vil.house_nav(hb)
		var pad := float(nav.floor_y) - Villages.WALL_HEIGHT
		var up: Array = nav.up
		# Standing on the flight itself?
		var st: Array = nav.stair
		var local := (me - (hb.center as Vector2)).rotated(float(hb.yaw))
		var on_stair := up.size() == 4 and absf(local.x - float(st[0])) < 0.95 and local.y < float(st[1]) + 0.2 \
				and local.y > float(st[2]) - 0.2 and global_position.y > pad + 0.25
		var me_up := global_position.y > pad + (1.6 if on_stair else 2.1)
		var same := not ht.is_empty() and ht == hb
		var tgt_up := same and goal_up and goal.y > pad + 2.1
		if same and me_up == tgt_up and not on_stair:
			return []
		if up.size() == 4 and (me_up or on_stair) and not (same and tgt_up):
			# Down: landing, stair top, stair foot, beside the foot (from the
			# stair itself, straight to its foot).
			for i in ([1, 0] if on_stair else [3, 2, 1, 0]):
				out.append([up[i], true])
		if same:
			if tgt_up and up.size() == 4:
				for q in (up.slice(2) if on_stair or me_up else up):
					out.append([q, true])
			return out
		out.append([nav["in"], true])
		out.append([nav.out, true])
	if not ht.is_empty() and ht != hb:
		var nav2 := vil.house_nav(ht)
		out.append([nav2.out, false])
		out.append([nav2["in"], true])
		if goal_up and goal.y > float(nav2.floor_y) - 1.0:
			for q in nav2.up:
				out.append([q, true])
	return out


func _tree_town(vil: Villages) -> TreeTown:
	if vil.landmarks == null or vil.landmarks.fantasy == null:
		return null
	return vil.landmarks.fantasy.tree_town


## Up on Treetop Town (a deck, the stair, a lookout)?
func _on_tree_town(vil: Villages, p: Vector3) -> bool:
	var tt := _tree_town(vil)
	if tt == null:
		return false
	return Vector2(p.x - tt.o.x, p.z - tt.o.z).length() < TreeTown.LOOKOUT_R + 6.0 and p.y > tt.o.y + 3.0


## Treetop Town by its spiral stair: up to the goal's deck and round the
## walkway to it, round and down again, or deck to deck by the stair.
func _tree_town_route(vil: Villages, goal: Vector3, goal_is_spot: bool) -> Array:
	var tt := _tree_town(vil)
	if tt == null or tt.helix.is_empty():
		return []
	var me := global_position
	var me_up := _on_tree_town(vil, me)
	# Only loot and lookout spots carry a real height; a roam point is given
	# our own height and is somewhere on the ground.
	var goal_up := goal_is_spot and _on_tree_town(vil, goal)
	if not me_up and not goal_up:
		return []
	var my_lv := tt.level_of(me) if me_up else -1.0
	var goal_lv := tt.level_of(goal) if goal_up else -1.0
	# In or out of a hut by its door (it faces the trunk).
	var my_hut := tt.hut_at(me) if me_up else {}
	var goal_hut := tt.hut_at(goal) if goal_up else {}
	var head: Array = []
	var tail: Array = []
	var me_a := tt.angle_of(me)
	var goal_a := tt.angle_of(goal)
	if not my_hut.is_empty():
		head = tt.hut_door(my_hut)
		me_a = float(my_hut.a)
	if not goal_hut.is_empty():
		var door := tt.hut_door(goal_hut)
		tail = [door[1], door[0]]
		goal_a = float(goal_hut.a)
	if me_up and goal_up and my_lv >= 0.0 and my_lv == goal_lv:
		if not my_hut.is_empty() and my_hut == goal_hut:
			return []
		# Same deck: round the walkway.
		var same: Array = head.duplicate()
		same.append_array(tt.ring_points(my_lv, me_a, goal_a))
		same.append_array(tail)
		return _wrap_route(same)
	var pts: Array = head.duplicate()
	# Along the stair to the goal's level (or the ground).
	var i1 := tt.helix_index(goal_lv) if goal_up and goal_lv >= 0.0 else (tt.helix.size() - 1 if goal_up else 0)
	var goal_h := (tt.helix[i1] as Vector3).y
	# From where we are to the stair: off a deck by its walkway to where the
	# stair arrives, or on the stair itself from the next point along it in
	# the direction we are going (picked by height: the nearest point can be
	# the one up at the deck while we are still below it).
	var i0 := 0
	if me_up and my_lv >= 0.0:
		# Round the walkway to where the stair arrives, then straight in.
		var off_a := tt.stair_angle(my_lv) + 0.08
		pts.append_array(tt.ring_points(my_lv, me_a, off_a))
		i0 = tt.helix_index(my_lv)
	elif me_up:
		var up := goal_h > me.y
		i0 = 0 if up else tt.helix.size() - 1
		for i in tt.helix.size():
			var hy := (tt.helix[i] as Vector3).y
			if up and hy >= me.y - 0.2:
				i0 = i
				break
			if not up and hy <= me.y + 0.2:
				i0 = i
	var step := 1 if i1 >= i0 else -1
	var i := i0
	while true:
		pts.append(tt.helix[i])
		if i == i1:
			break
		i += step
	# Step straight out onto the deck where the stair arrives (behind that
	# point the stair is still below the deck), then round its walkway.
	if goal_up and goal_lv >= 0.0:
		var on_a := tt.stair_angle(goal_lv) + 0.08
		var wr := tt.walk_r(goal_lv)
		pts.append(tt.o + Vector3(cos(on_a) * wr, goal_lv + 0.1, sin(on_a) * wr))
		pts.append_array(tt.ring_points(goal_lv, on_a, goal_a))
		pts.append_array(tail)
	return _wrap_route(pts)


func _wrap_route(pts: Array) -> Array:
	var out: Array = []
	for q in pts:
		out.append([q, true])
	return out


## Walk up small ledges (stair edges, floor lips, kerbs) like the player does.
## A footstep you can hear, and see: dust off a dirt road at a run, a splash
## in the shallows.
func _step_fx(planar: float) -> void:
	var surf: String = game.surface_at(global_position)
	game.play_sfx_at("step_%s_%d" % [surf, randi() % 4 + 1], global_position, 1.0 if planar > 5.5 else -3.0)
	if (surf == "dirt" and planar > 5.5) or surf == "water":
		game.step_puff(global_position, surf == "water")


func _step_up(wish: Vector3, grounded: bool) -> void:
	if not grounded or wish.length() < 0.5:
		return
	var got := Vector2(velocity.x, velocity.z).length()
	if got > wish.length() * 0.6 and not is_on_wall():
		return
	var dir := wish.normalized()
	if not test_move(global_transform, dir * 0.25):
		return
	for h in [0.16, 0.3, 0.45]:
		var up := Vector3.UP * float(h)
		if test_move(global_transform, up):
			return
		var raised := global_transform.translated(up)
		if test_move(raised, dir * 0.48):
			continue
		var land := global_position + up + dir * 0.48
		var q := PhysicsRayQueryParameters3D.create(land + Vector3.UP * 0.05, land - Vector3.UP * (float(h) + 0.1), 1)
		q.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			continue
		global_position = Vector3(land.x, float(hit["position"].y) + 0.02, land.z)
		velocity.y = 0.0
		return


func _ground_safety() -> void:
	# Safety net: bilinear height and the collision mesh differ on steep slopes, so a
	# body that ends up buried gets lifted back out instead of falling forever.
	var gy := game_ground_y()
	if game != null and game.terrain != null and bool(game.terrain.is_water(global_position.x, global_position.z)):
		# Deep water: float chest-deep like a swimmer (sea, river or lake).
		var ws: float = game.terrain.water_surface_at(global_position.x, global_position.z)
		var swim_y: float = ws - 1.38
		if ws - gy > 1.43 and global_position.y < swim_y:
			global_position.y = move_toward(global_position.y, swim_y, 0.08)
			velocity.y = maxf(velocity.y, 0.0)
	elif global_position.y < gy - 0.4:
		global_position.y = gy + 1.4
		velocity.y = 0.0
	if global_position.y < -20.0:
		global_position = Vector3(roam_point.x, game_ground_y() + 2.0, roam_point.y)


var _deep_frame := -1
var _deep := false


## Floating in water too deep to stand in (cached for the physics frame).
func in_deep_water() -> bool:
	var f := Engine.get_physics_frames()
	if f == _deep_frame:
		return _deep
	_deep_frame = f
	_deep = false
	if game != null and game.terrain != null and bool(game.terrain.is_water(global_position.x, global_position.z)):
		var ws: float = game.terrain.water_surface_at(global_position.x, global_position.z)
		_deep = ws - game_ground_y() > 1.43 and global_position.y < ws - 1.0
	return _deep


func _heal_sound(name: String, db: float) -> void:
	if game != null and game.player != null and game.player.global_position.distance_to(global_position) < 40.0:
		game.play_sfx_at(name, global_position + Vector3(0, 1.2, 0), db)


var _swim_stroke := 0.0


## Swim clips for a body in deep water; true when it handled the frame.
func _animate_swim(planar: float, delta: float) -> bool:
	if body == null:
		return true
	_play("Swim_Fwd" if planar > 0.6 else "Swim_Idle", clampf(planar / 2.4, 0.7, 1.3) if planar > 0.6 else 1.0)
	body.set_arms("")
	if planar > 0.6:
		_swim_stroke += delta * planar
		if _swim_stroke > 2.2:
			_swim_stroke = 0.0
			_heal_sound("swim_stroke_%d" % (randi() % 3 + 1), -4.0)
	return true


func _animate_ground() -> void:
	var planar := Vector2(velocity.x, velocity.z).length()
	if in_deep_water():
		_animate_swim(planar, get_physics_process_delta_time())
		return
	if is_on_floor() and planar > 1.0:
		_step += planar * get_physics_process_delta_time()
		if _step > 2.9:
			_step = 0.0
			if game != null and game.player != null and game.player.global_position.distance_to(global_position) < 42.0:
				_step_fx(planar)
	if is_on_floor() and planar > 0.4:
		var want := "Sprint" if planar > 5.6 else ("Jog_Fwd" if planar > 2.6 else "Walk")
		if crouched:
			want = "Crouch_Fwd"
		speed_anim = want
		var ref := 6.2 if want == "Sprint" else (4.0 if want == "Jog_Fwd" else 1.6)
		_play(want, clampf(planar / ref, 0.7, 1.4))
	elif state == State.GROUND:
		speed_anim = "Crouch_Idle" if crouched else "Idle"
		_play(speed_anim)
	# Arms: gun up while fighting, held low otherwise.
	if body != null:
		if armed:
			var fighting_now := enemy != null and is_instance_valid(enemy) and enemy_visible() and not fight_moving
			_reload_t = maxf(0.0, _reload_t - get_physics_process_delta_time())
			body.set_arms("med" if heal_timer > 0.0 else ("reload" if _reload_t > 0.0 else ("aim" if fighting_now else "idle")))
			var aim_to: Vector3 = (enemy.global_position + Vector3(0, 1.2, 0) - _shot_origin()) if fighting_now else -global_basis.z
			body.aim_dir = aim_to
		else:
			body.set_arms("")
		body.set_gear(vest_level, helmet_level)


func _pick_roam_point() -> void:
	# Wander your own patch of the safe area rather than its centre, so the
	# lobby does not funnel into one spot.
	var here := Vector2(global_position.x, global_position.z)
	var nc := here
	var nr := 1e9
	if game != null and game.zone != null:
		nc = game.zone.next_center()
		nr = maxf(8.0, game.zone.next_radius())
	for i in 10:
		var a := randf() * TAU
		var p := here + Vector2(cos(a), sin(a)) * randf_range(15.0, 70.0)
		if p.distance_to(nc) > nr * 0.85:
			# Outside the next circle: aim for its near edge instead.
			p = nc + (p - nc).normalized() * nr * randf_range(0.45, 0.8)
		if game == null or game.terrain == null or not bool(game.terrain.is_water(p.x, p.y)):
			roam_point = p
			return
	roam_point = nc


## Someone fired a gun nearby.
func hear_shot(pos: Vector3, shooter: Node) -> void:
	if state != State.GROUND or not alive or shooter == self:
		return
	if enemy != null and is_instance_valid(enemy) and enemy_visible():
		return
	alert_timer = 5.0
	heard_pos = pos
	var to := pos - global_position
	rotation.y = atan2(-to.x, -to.z)
	think_timer = minf(think_timer, reaction)


# ------------------------------------------------------------- net puppet --
## Latest state from the network.
func apply_net(pos: Vector3, yaw: float, st: int, flags: int, weapon: String, vest: int, helmet: int, pitch := 0.0) -> void:
	if not alive:
		return
	_net_pos = pos
	_net_yaw = yaw
	net_pitch = pitch
	var heal := heal_kind_of(flags)
	if heal != "" and heal != heal_kind_of(_net_flags) and alive:
		_heal_sound(HEAL_START_SFX[heal], -5.0)
	_net_flags = flags
	if not _net_seen or st != state and (st == State.GROUND or state == State.PLANE):
		global_position = pos
		rotation.y = yaw
	_net_seen = true
	if st != state:
		if st == State.FALL:
			_play("Jump_Start")
		elif st == State.GROUND and state == State.CHUTE:
			_play("Jump_Land")
		state = st
	vest_level = vest
	helmet_level = helmet
	var want_armed := (flags & NF_ARMED) != 0 and weapon != ""
	if want_armed and weapon != weapon_id:
		arm_weapon(weapon)
	elif not want_armed and armed:
		armed = false
		weapon_id = ""
		if body != null:
			body.set_gun("")


func _puppet_tick(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	_muzzle_flash.visible = _flash > 0.0
	if hit_flash > 0.0:
		hit_flash = maxf(0.0, hit_flash - delta)
	if state == State.DEAD or not alive:
		dead_timer += delta
		# The last update may have caught them mid-air (a jump, a ledge, the
		# parachute): the body comes down to the ground under it.
		if _dead_floor == INF and game != null:
			_dead_floor = float(game.ground_at(global_position).y)
		if dead_timer <= 7.0 and global_position.y > _dead_floor + 0.01:
			_dead_vy = minf(_dead_vy + GRAVITY * delta, 50.0)
			global_position.y = maxf(_dead_floor, global_position.y - _dead_vy * delta)
		if dead_timer > BODY_STAYS and not is_human:
			position.y -= delta * 0.6
		if dead_timer > BODY_STAYS + 3.0 and not is_human:
			queue_free()
		return
	if not _net_seen:
		return
	if seated_in != null and is_instance_valid(seated_in) and not seated_in.wrecked:
		var xf := seated_in.seat_transform(seated_slot)
		global_position = xf.origin - xf.basis.y * 0.55
		rotation.y = xf.basis.get_euler().y
		velocity = seated_in.linear_velocity
		visible = true
		chute_node.visible = false
		_play("Crouch_Idle")
		if body != null:
			body.set_arms("")
		return
	var prev := global_position
	var k := clampf(delta * 14.0, 0.0, 1.0)
	if global_position.distance_to(_net_pos) > 25.0:
		global_position = _net_pos
	else:
		global_position = global_position.lerp(_net_pos, k)
	rotation.y = lerp_angle(rotation.y, _net_yaw, k)
	velocity = (global_position - prev) / maxf(delta, 0.0001)
	visible = state != State.PLANE
	chute_node.visible = state == State.CHUTE
	_set_crouch((_net_flags & NF_CROUCH) != 0)
	match state:
		State.FALL:
			_play("Jump")
		State.CHUTE:
			_play("Idle")
			chute_node.rotation.y = sin(Time.get_ticks_msec() * 0.0009) * 0.08
		State.GROUND:
			var planar := Vector2(velocity.x, velocity.z).length()
			if (_net_flags & NF_SWIM) != 0:
				_animate_swim(planar, delta)
				if body != null:
					body.set_gear(vest_level, helmet_level)
				return
			if planar > 0.5:
				var want := "Sprint" if planar > 5.6 else ("Jog_Fwd" if planar > 2.6 else "Walk")
				if crouched:
					want = "Crouch_Fwd"
				var ref := 6.2 if want == "Sprint" else (4.0 if want == "Jog_Fwd" else 1.6)
				_play(want, clampf(planar / ref, 0.7, 1.4))
				_step += planar * delta
				if _step > 2.9:
					_step = 0.0
					if game != null and game.player != null and game.player.global_position.distance_to(global_position) < 42.0:
						_step_fx(planar)
			else:
				_play("Crouch_Idle" if crouched else "Idle")
	if body != null:
		var heal_kind := heal_kind_of(_net_flags)
		if heal_kind != "":
			body.set_arms(heal_kind)
		elif armed:
			var aiming := (_net_flags & NF_AIM) != 0
			body.set_arms("reload" if (_net_flags & NF_RELOAD) != 0 else ("aim" if aiming else "idle"))
			body.aim_dir = (-global_basis.z).rotated(global_basis.x, net_pitch)
		else:
			body.set_arms("")
		body.set_gear(vest_level, helmet_level)


## Pack this bot's state for a snapshot (host side).
func net_pack(out: PackedFloat32Array) -> void:
	var flags := 0
	if alive:
		flags |= NF_ALIVE
	if crouched:
		flags |= NF_CROUCH
	if armed:
		flags |= NF_ARMED
	if enemy != null and is_instance_valid(enemy) and not fight_moving and state == State.GROUND:
		flags |= NF_AIM
	if _reload_t > 0.0:
		flags |= NF_RELOAD
	if heal_timer > 0.0:
		flags |= NF_HEAL_MED
	if state == State.GROUND and in_deep_water():
		flags |= NF_SWIM
	var p := global_position
	out.append_array(PackedFloat32Array([p.x, p.y, p.z, rotation.y, float(state), float(flags),
		float(Weapons.ORDER.find(weapon_id) if armed else -1), float(vest_level * 10 + helmet_level)]))


## Show a death that happened on the host.
func puppet_die() -> void:
	if not alive:
		return
	alive = false
	state = State.DEAD
	dead_timer = 0.0
	_dead_floor = INF
	_dead_vy = 0.0
	collision_layer = 0
	chute_node.visible = false
	if _tag != null:
		_tag.visible = false
	if body != null:
		body.die()


func muzzle_flash() -> void:
	_flash = 0.06


func _play(name: String, speed := 1.0) -> void:
	if body == null:
		return
	var legs := name
	match name:
		"Jump_Start", "Jump_Land":
			legs = "Jump" if name == "Jump_Start" else "Idle"
	body.set_legs(legs, speed)


# ------------------------------------------------------------------- loot ---
func _find_loot() -> LootPickup:
	if game == null or game.loot_pool == null:
		return null
	var best: LootPickup = null
	var best_d := 130.0 if not armed else 28.0
	var my_tier := int(Weapons.def(weapon_id).get("tier", 0)) if armed else 0
	# Nearby cells only, distance first (cheap), then the wish list.
	for l in game.loot_near(global_position, best_d):
		var d: float = l.global_position.distance_to(global_position)
		if d >= best_d:
			continue
		if not _wants(l, my_tier):
			continue
		if _skip_loot.has(l.get_instance_id()):
			continue
		if d < best_d:
			best_d = d
			best = l
	return best


func _wants(l: LootPickup, my_tier: int) -> bool:
	match l.kind:
		"weapon":
			return not armed or int(Weapons.def(l.item_id).get("tier", 1)) > my_tier
		"armor":
			return armed and int(l.item_id) > vest_level
		"helmet":
			return armed and int(l.item_id) > helmet_level
		"med", "bandage":
			return armed and meds < 2
		"grenade":
			return armed and grenades < 2
	return false


func _take_loot(l: LootPickup) -> void:
	if l == null or l.taken:
		return
	if l.kind == "weapon":
		if armed and game != null and game.has_method("drop_weapon"):
			game.drop_weapon(weapon_id, -1, -1, global_position + Vector3(0.6, 0, 0.6))
		arm_weapon(l.item_id)
	elif l.kind == "armor":
		vest_level = int(l.item_id)
		armor = 100.0
	elif l.kind == "helmet":
		helmet_level = int(l.item_id)
	elif l.kind == "med" or l.kind == "bandage":
		meds += 1
	elif l.kind == "grenade":
		grenades += 1
	l.consume()
	if game != null and game.has_method("play_sfx_at"):
		game.play_sfx_at("pickup", global_position, 0.7)
	loot_target = null


func arm_weapon(id: String) -> void:
	weapon_id = id
	armed = true
	var d: Dictionary = Weapons.def(id)
	mag = int(d["mag"])
	if body != null:
		body.set_gun(id)
	speed_anim = ""
	_play("Idle")


# ------------------------------------------------------------------ combat --
func _shoot_logic(delta: float) -> void:
	if not armed or weapon_id == "":
		return
	if in_deep_water():
		# Both hands are swimming, same as for the player.
		_reload_t = maxf(0.0, _reload_t - delta)
		return
	if think_timer <= 0.0:
		think_timer = randf_range(0.22, 0.45)
		var prev := enemy
		var found := _find_enemy()
		if found != null:
			enemy = found
			if found != prev:
				# Reaction time before the first shot on a new target.
				fire_timer = maxf(fire_timer, reaction * randf_range(0.8, 1.4))
				_burst = 0
		elif enemy != null and (not is_instance_valid(enemy) or not (enemy.get("alive") == true)):
			enemy = null
	if enemy == null or not is_instance_valid(enemy) or not (enemy.get("alive") == true):
		enemy = null
		return
	if not enemy_visible():
		return
	var d: Dictionary = Weapons.def(weapon_id)
	var dist := global_position.distance_to(enemy.global_position)
	var max_range: float = minf(float(d["range"]), sight)
	if dist > max_range:
		return
	var aim_h := aim_height(enemy)
	if randf() < shoot_skill * 0.18:
		aim_h = aim_height(enemy, true)
	var aim := (enemy.global_position + Vector3(0, aim_h, 0)) - _shot_origin()
	if fight_moving:
		# Running between positions: no shooting, and the next stop needs a
		# moment to bring the gun back on target.
		fire_timer = maxf(fire_timer, 0.25)
		return
	rotation.y = lerp_angle(rotation.y, atan2(-aim.x, -aim.z), clampf(delta * 9.0, 0.0, 1.0))
	if fire_timer > 0.0:
		return
	if mag <= 0:
		_start_reload()
		return
	fire_timer = 60.0 / float(d["rpm"]) * (1.15 if dist < 45.0 else 1.6)
	# Fire in bursts with short pauses, like a person re-acquiring the target.
	if bool(d["auto"]) and _burst > 0 and _burst % randi_range(4, 7) == 0:
		fire_timer += randf_range(0.35, 0.8)
	mag -= 1
	_flash = 0.05
	_muzzle_flash.visible = true
	_muzzle_flash.rotation.z = randf() * TAU
	if body != null:
		_muzzle_flash.global_position = body.muzzle_position()
		if game != null and game.player != null and game.player.global_position.distance_to(global_position) < 60.0:
			game.spawn_smoke(_muzzle_flash.global_position, 0.6)
	var from := _shot_origin()
	# Aim error: skill, range, target movement and the first shots of a burst.
	var tvel := Vector3.ZERO
	if enemy is CharacterBody3D:
		tvel = (enemy as CharacterBody3D).velocity
	# A trained shooter: an average bot puts about one round in five on
	# someone standing still at 55 m; worse on the move, further out and for
	# the first rounds before the gun settles.
	var spread_deg := 0.35 + (1.0 - shoot_skill) * 1.3
	spread_deg += dist * 0.005
	spread_deg += Vector2(tvel.x, tvel.z).length() * 0.12
	spread_deg += maxf(0.0, 3.0 - float(_burst)) * 0.35
	spread_deg *= float(d["spread"]) / 1.35 * 0.5 + 0.5
	_burst += 1
	var spread := deg_to_rad(spread_deg)
	# Lead the target and hold over for drop, as well as this bot is able to.
	var speed := float(d.get("velocity", 500.0))
	var tof := dist / speed
	var comp := clampf(shoot_skill * 1.15, 0.0, 1.0)
	var aim_pt := enemy.global_position + Vector3(0, aim_h, 0) + tvel * tof * comp
	aim_pt.y += 0.5 * Ballistics.GRAVITY * tof * tof * comp
	var base_dir := (aim_pt - from).normalized()
	var mult := 0.62 if (enemy is Player or (enemy is Bot and (enemy as Bot).is_human)) else 0.2
	var pellets := int(d["pellets"])
	_shot_seq += 1
	for i in pellets:
		var s := spread if pellets == 1 else deg_to_rad(float(d["spread"])) * randf_range(0.4, 1.5)
		var dir := (base_dir + Vector3(randf_range(-s, s), randf_range(-s, s), randf_range(-s, s))).normalized()
		if game != null and game.ballistics != null:
			game.ballistics.fire(self, from, dir, weapon_id, _muzzle_flash.global_position, _shot_seq, mult)
	if game != null and game.has_method("play_sfx_at"):
		game.play_sfx_at("shot_" + str(d["sound"]), from, 0.85)
	if game != null and game.has_method("on_gunshot"):
		game.on_gunshot(from, self)


func _shot_origin() -> Vector3:
	return global_position + Vector3(0, 0.95 if crouched else 1.30, 0) + -global_basis.z * 0.55


func _find_enemy() -> Node3D:
	if game == null:
		return null
	var candidates: Array = []
	var p = game.player
	if p != null and p.alive and (p.mode == Player.Mode.GROUND or p.mode == Player.Mode.CHUTE or p.mode == Player.Mode.VEHICLE):
		candidates.append(p)
	for g in ["bots", "humans"]:
		for b in get_tree().get_nodes_in_group(g):
			if b != self and is_instance_valid(b) and (b as Bot).alive and ((b as Bot).state == State.GROUND or (b as Bot).state == State.CHUTE):
				candidates.append(b)
	var fwd := -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var scored: Array = []
	for c in candidates:
		var to: Vector3 = (c as Node3D).global_position - global_position
		var d := to.length()
		# Bots pick fights with each other at shorter range than with you, and
		# barely at all while still looting after the drop.
		var human: bool = c is Player or (c is Bot and (c as Bot).is_human)
		var reach := sight if human else sight * 0.5
		if calm_t > 0.0 and c != enemy:
			# Only the aggressive ones start a fight while still looting.
			reach = 18.0 if aggression > 0.72 else 0.0
		if d > reach:
			continue
		var flat := Vector3(to.x, 0, to.z).normalized()
		var in_view: bool = d < CLOSE_SENSE or alert_timer > 0.0 or fwd.dot(flat) > FOV_COS or c == enemy
		if not in_view:
			continue
		# Crouching targets in the distance are harder to spot.
		if c is Player and Input.is_action_pressed("crouch") and d > 55.0:
			continue
		if c is Bot and (c as Bot).is_human and (c as Bot).crouched and d > 55.0:
			continue
		scored.append([d, c])
	scored.sort_custom(func(a, b): return a[0] < b[0])
	var checks := 0
	for e in scored:
		if checks >= 4:
			break
		checks += 1
		if _can_see(e[1]):
			return e[1]
	return null


## Height above the feet to look and aim at: chest, or head; lower when the
## target is crouched (their body is shorter then).
static func aim_height(target: Node3D, head := false) -> float:
	var low := false
	if target is Player:
		low = (target as Player).crouching()
	elif target is Bot:
		low = (target as Bot).crouched
	if head:
		return 1.0 if low else 1.55
	return 0.78 if low else 1.15


func _can_see(target: Node3D) -> bool:
	var from := _shot_origin()
	var to := target.global_position + Vector3(0, aim_height(target), 0)
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | 4)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return false
	return hit["collider"] == target


func enemy_visible() -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	var key := enemy.get_instance_id()
	var now := Engine.get_physics_frames()
	if _see_cache.get("id", -1) == key and now - int(_see_cache.get("f", -99)) < 6:
		return bool(_see_cache.get("v", false))
	var from := _shot_origin()
	var to := (enemy as Node3D).global_position + Vector3(0, aim_height(enemy as Node3D), 0)
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | 4)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var vis := false
	if not hit.is_empty():
		var col: Object = hit["collider"]
		vis = col == enemy or (col is Node and (col as Node).is_ancestor_of(enemy))
	_see_cache = {"id": key, "f": now, "v": vis}
	return vis


# ------------------------------------------------------------------ damage --
func take_damage(amount: float, _pos: Vector3 = Vector3.ZERO, headshot: bool = false, source: Node = null) -> bool:
	if not alive:
		return false
	if puppet:
		# The real body lives on another machine: show the hit, send it on.
		if source == null:
			return false
		# Squad mates cannot hurt each other (grenades included); bots can.
		if friendly and (source is Player or (source is Bot and (source as Bot).is_human)):
			return false
		hit_flash = 0.25
		if body != null:
			body.flinch(1.4 if headshot else 1.0)
		if game != null:
			game.net_route_hit(self, amount, _pos, headshot, source)
		return false
	var dmg := amount
	if source != null:
		if headshot and helmet_level > 0:
			dmg *= 1.0 - Player.ABSORB[helmet_level]
		elif not headshot and vest_level > 0 and armor > 0.0:
			dmg *= 1.0 - Player.ABSORB[vest_level]
			armor -= amount * 0.45
			if armor <= 0.0:
				vest_level = 0
	hp -= dmg
	hit_flash = 0.25
	if body != null:
		body.flinch(1.4 if headshot else 1.0)
	heal_timer = 0.0
	_hurt_t = 0.0
	# Being shot at makes bots fight back.
	if source != null and is_instance_valid(source) and source != self:
		alert_timer = 6.0
		heard_pos = (source as Node3D).global_position
		if enemy == null or not is_instance_valid(enemy) or not enemy_visible():
			enemy = source as Node3D
			var to: Vector3 = heard_pos - global_position
			rotation.y = atan2(-to.x, -to.z)
			think_timer = reaction
	if hp <= 0.0:
		last_headshot = headshot
		_die(source)
		return true
	return false


func _die(source: Node) -> void:
	if not alive:
		return
	alive = false
	state = State.DEAD
	dead_timer = 0.0
	collision_layer = 0
	collision_mask = 1
	chute_node.visible = false
	if body != null:
		body.die()
	last_killer_node = source if source != null and is_instance_valid(source) else null
	var killer := ""
	if source != null and source.has_method("display_name"):
		killer = str(source.call("display_name"))
	eliminated.emit(self, killer)

