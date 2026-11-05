class_name Ballistics
extends Node3D

## Every bullet in the match is a real projectile: it has a muzzle velocity,
## drops under gravity, takes time to arrive and draws a glowing tracer, so
## long shots need lead and holdover. Hits are resolved with a ray per bullet
## per physics tick from its previous to its new position.

const GRAVITY := 9.8
const MAX_BULLETS := 260
const MASK := 1 | 2 | 4

var game: Node = null
var bullets: Array = []
var _pool: Array[MeshInstance3D] = []
var _mesh: BoxMesh
var _mat_mine: StandardMaterial3D
var _mat_enemy: StandardMaterial3D
var _mat_sniper: StandardMaterial3D


func _ready() -> void:
	_mesh = BoxMesh.new()
	_mesh.size = Vector3(1.0, 1.0, 1.0)
	_mat_mine = _tracer_mat(Color(1.0, 0.78, 0.25))
	_mat_enemy = _tracer_mat(Color(1.0, 0.32, 0.16))
	_mat_sniper = _tracer_mat(Color(1.0, 0.92, 0.55))


func _tracer_mat(c: Color) -> StandardMaterial3D:
	# Solid core with a soft halo as a second pass: reads against both sky and
	# grass, where a pale additive line all but vanished.
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = c
	m.disable_receive_shadows = true
	m.disable_fog = true
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow.albedo_color = Color(c.r, c.g * 0.7, c.b * 0.4, 0.45)
	glow.disable_fog = true
	glow.grow = true
	glow.grow_amount = 0.6
	m.next_pass = glow
	return m


func _take_mesh() -> MeshInstance3D:
	var mi: MeshInstance3D
	if _pool.is_empty():
		mi = MeshInstance3D.new()
		mi.mesh = _mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	else:
		mi = _pool.pop_back()
	mi.visible = true
	return mi


func _release(b: Dictionary) -> void:
	var mi: MeshInstance3D = b["mesh"]
	if mi != null and is_instance_valid(mi):
		mi.visible = false
		_pool.append(mi)


## Launch one bullet. `visual_from` is where the tracer appears to start (the
## muzzle) while the true path starts at `from` (the eye), so what you aim at is
## what you hit; the tracer converges onto the real path within a few metres.
func fire(shooter: Node, from: Vector3, dir: Vector3, weapon_id: String, visual_from: Vector3, shot_id: int, dmg_mult := 1.0, visual := false) -> void:
	var d: Dictionary = Weapons.def(weapon_id)
	# In a LAN game, real shots are mirrored to everyone else as visual ones.
	if not visual and game != null and game.has_method("net_shot_fired"):
		game.net_shot_fired(shooter, from, dir, weapon_id, visual_from, shot_id)
	if bullets.size() >= MAX_BULLETS:
		_release(bullets.pop_front())
	var speed := float(d.get("velocity", 500.0))
	var mi := _take_mesh()
	var mine: bool = shooter != null and shooter is Player
	mi.material_override = _mat_sniper if Weapons.cls(weapon_id) in ["sniper", "dmr"] else (_mat_mine if mine else _mat_enemy)
	var b := {
		"pos": from,
		"vel": dir.normalized() * speed,
		"speed": speed,
		"shooter": shooter,
		"rid": (shooter as CollisionObject3D).get_rid() if shooter is CollisionObject3D else RID(),
		"id": weapon_id,
		"dist": 0.0,
		"max": float(d["range"]) * 1.7,
		"range": float(d["range"]),
		"shot": shot_id,
		"off": visual_from - from,
		"mesh": mi,
		"mine": mine,
		"mult": dmg_mult,
		"cracked": false,
		"trail": 0.0,
		"visual": visual,
	}
	bullets.append(b)
	_place_tracer(b)


func clear() -> void:
	for b in bullets:
		_release(b)
	bullets.clear()


func _physics_process(delta: float) -> void:
	if Prof.on:
		var t0 := Time.get_ticks_usec()
		_physics_process_body(delta)
		Prof.add("bullets", Time.get_ticks_usec() - t0)
	else:
		_physics_process_body(delta)


func _physics_process_body(delta: float) -> void:
	if bullets.is_empty():
		return
	var space := get_world_3d().direct_space_state
	var cam := get_viewport().get_camera_3d()
	var player: Node3D = game.player if game != null else null
	var dead: Array = []
	for b in bullets:
		var pos: Vector3 = b["pos"]
		var vel: Vector3 = b["vel"]
		vel.y -= GRAVITY * delta
		var step := vel * delta
		var to := pos + step
		var q := PhysicsRayQueryParameters3D.create(pos, to, MASK)
		var rid: RID = b["rid"]
		if rid.is_valid():
			q.exclude = [rid]
		var hit := space.intersect_ray(q)
		if not b["mine"] and player != null and not b["cracked"]:
			_near_miss(b, pos, to, player)
		if not hit.is_empty():
			b["dist"] = float(b["dist"]) + pos.distance_to(hit["position"])
			_resolve_hit(b, hit)
			dead.append(b)
			continue
		b["pos"] = to
		b["vel"] = vel
		b["dist"] = float(b["dist"]) + step.length()
		b["trail"] = minf(float(b["trail"]) + step.length(), 9999.0)
		if float(b["dist"]) > float(b["max"]) or to.y < -30.0:
			dead.append(b)
			continue
		_place_tracer(b, cam)
	for b in dead:
		_release(b)
		bullets.erase(b)


func _place_tracer(b: Dictionary, cam: Camera3D = null) -> void:
	var mi: MeshInstance3D = b["mesh"]
	var vel: Vector3 = b["vel"]
	var dir := vel.normalized()
	# Muzzle offset fades out over the first ~18 m of flight.
	var k := clampf(1.0 - float(b["dist"]) / 18.0, 0.0, 1.0)
	var head: Vector3 = b["pos"] + Vector3(b["off"]) * k
	var length := minf(float(b["speed"]) * 0.028, maxf(0.4, float(b["trail"])))
	var width := 0.022
	if cam != null:
		# Keep a few pixels wide however far away it is.
		width = maxf(width, head.distance_to(cam.global_position) * 0.0032)
	if Weapons.cls(b["id"]) == "sniper":
		width *= 1.5
	var center := head - dir * length * 0.5
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
	var basis := Basis.looking_at(dir, up)
	mi.global_transform = Transform3D(Basis(basis.x * width, basis.y * width, basis.z * length), center)


func _near_miss(b: Dictionary, a: Vector3, c: Vector3, player: Node3D) -> void:
	if not (player.get("alive") == true):
		return
	var ear := player.global_position + Vector3(0, 1.5, 0)
	var seg := c - a
	var t := clampf((ear - a).dot(seg) / maxf(0.0001, seg.length_squared()), 0.0, 1.0)
	var p := a + seg * t
	var d := p.distance_to(ear)
	if d < 3.0 and t > 0.0 and t < 1.0:
		b["cracked"] = true
		if game != null:
			game.play_sfx_at("bullet_crack" if float(b["speed"]) > 450.0 else "bullet_whiz", p, -2.0 if d < 1.5 else -7.0)
			if d < 1.2 and player.has_method("add_trauma"):
				player.add_trauma(0.12)


func _resolve_hit(b: Dictionary, hit: Dictionary) -> void:
	var col: Object = hit["collider"]
	var pos: Vector3 = hit["position"]
	var d: Dictionary = Weapons.def(b["id"])
	var shooter: Node = b["shooter"]
	var damageable: bool = col != null and col.has_method("take_damage") and (col.get("alive") == true) and col != shooter
	# Squad mates: friendly fire is off, the round just stops.
	if damageable and col.get("friendly") == true and shooter is Player:
		damageable = false
	if col is Vehicle:
		# Jeeps ring and spark; no hitmarker for shooting metal.
		if not bool(b.get("visual", false)):
			var vd := float(d["damage"]) * float(b["mult"])
			(col as Vehicle).take_damage(vd, pos, false, shooter if is_instance_valid(shooter) else null)
		elif game != null:
			game.spawn_impact(pos, hit.get("normal", Vector3.UP), col, false)
		return
	if damageable and bool(b.get("visual", false)):
		# Someone else's bullet: their machine works out the damage.
		if game != null:
			game.spawn_blood(pos)
		return
	if damageable:
		var headshot := false
		if col.has_method("head_y"):
			headshot = pos.y >= float(col.call("head_y"))
		# Rifle rounds keep most of their punch; buckshot falls off hard.
		var shot_cls := Weapons.cls(b["id"])
		var slope := 0.55 if shot_cls == "shotgun" else 0.25
		var floor_k := 0.3 if shot_cls == "shotgun" else 0.75
		var falloff := clampf(1.0 - (float(b["dist"]) / maxf(1.0, float(b["range"]))) * slope, floor_k, 1.0)
		var dmg := float(d["damage"]) * falloff * float(b["mult"])
		if headshot:
			dmg *= float(d["head"])
		elif col is Node3D and pos.y - (col as Node3D).global_position.y < 0.8:
			dmg *= 0.8  # legs
		# What the round hit decides the sound: helmet ping, plate, or flesh.
		var snd := "hit_body"
		if headshot and int(col.get("helmet_level")) > 0:
			snd = "hit_helmet"
		elif not headshot and int(col.get("vest_level")) > 0:
			snd = "hit_armor"
		var killed = col.call("take_damage", dmg, pos, headshot, shooter if is_instance_valid(shooter) else null)
		if game != null:
			game.spawn_blood(pos)
			game.play_sfx_at(snd, pos, 2.0 if snd != "hit_body" else 0.0)
		if shooter != null and is_instance_valid(shooter) and shooter.has_method("on_bullet_hit"):
			shooter.on_bullet_hit(int(b["shot"]), pos, dmg, headshot, killed is bool and killed)
	else:
		if game != null:
			game.spawn_impact(pos, hit.get("normal", Vector3.UP), col, Weapons.cls(b["id"]) == "sniper")
			var surf := "bullet_impact"
			if col is Node:
				var nm := String((col as Node).name)
				if nm.begins_with("Village") or nm.begins_with("Tree"):
					surf = "impact_wood"
				elif nm.begins_with("Rock"):
					surf = "impact_stone"
			if game.player != null and pos.distance_to(game.player.global_position) < 60.0:
				game.play_sfx_at(surf, pos, -4.0)
				if surf == "impact_stone" and randf() < 0.35:
					game.play_sfx_at("ricochet", pos, -6.0)
