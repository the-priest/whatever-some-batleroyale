class_name SoldierRig
extends Node3D

## Bot body: the mannequin dressed as a soldier (camo uniform, helmet or cap,
## plate carrier, backpack) with an upper/lower body animation blend so the
## arms can hold a weapon up while the legs walk, run or sprint.

const PALETTES := [
	[Color(0.33, 0.36, 0.24), Color(0.17, 0.18, 0.13)],  # olive
	[Color(0.55, 0.48, 0.35), Color(0.30, 0.26, 0.19)],  # desert tan
	[Color(0.42, 0.44, 0.46), Color(0.20, 0.21, 0.22)],  # urban grey
	[Color(0.27, 0.33, 0.22), Color(0.37, 0.30, 0.21)],  # woodland
	[Color(0.17, 0.19, 0.23), Color(0.08, 0.08, 0.09)],  # night
]
## Camouflage colours per palette: base, blotch A, blotch B, dark accent.
const CAMO := [
	[Color(0.33, 0.36, 0.24), Color(0.22, 0.26, 0.15), Color(0.40, 0.33, 0.22), Color(0.11, 0.12, 0.09)],
	[Color(0.62, 0.55, 0.40), Color(0.50, 0.42, 0.29), Color(0.70, 0.64, 0.50), Color(0.36, 0.28, 0.19)],
	[Color(0.46, 0.48, 0.50), Color(0.32, 0.34, 0.36), Color(0.60, 0.61, 0.62), Color(0.16, 0.17, 0.18)],
	[Color(0.27, 0.33, 0.22), Color(0.38, 0.30, 0.20), Color(0.17, 0.22, 0.14), Color(0.08, 0.08, 0.07)],
	[Color(0.17, 0.19, 0.24), Color(0.11, 0.12, 0.16), Color(0.24, 0.26, 0.31), Color(0.05, 0.05, 0.06)],
]
static var _camo: Shader


static func _camo_shader() -> Shader:
	if _camo == null:
		_camo = load("res://shaders/camo.gdshader")
	return _camo


const VEST_COLORS := [Color(0.55, 0.50, 0.38), Color(0.30, 0.34, 0.24), Color(0.10, 0.11, 0.12)]
const LEG_ANIMS := ["Idle", "Walk", "Jog_Fwd", "Sprint", "Jump", "Crouch_Idle", "Crouch_Fwd", "Swim_Fwd", "Swim_Idle"]
const ARM_ANIMS := ["Pistol_Idle", "Pistol_Aim_Neutral", "Pistol_Reload", "Idle_Talking", "Interact", "Idle_Torch", "Punch_Cross"]
## Upper-body clip per healing item: hands busy in front of the chest for a
## bandage, reaching for the kit, can held up (then lifted to the mouth by
## _drink_ik, as no clip has a hand-to-mouth pose).
const HEAL_ARMS := {"bandage": "Idle_Talking", "med": "Interact", "energy": "Idle_Torch"}
## The swim stroke clip lies the body flat at hip height; lift it to the
## surface (the soldier floats chest-deep, 1.38 m under the waterline).
const SWIM_LIFT := 1.12
const UPPER_BONES := ["spine_02", "spine_03", "neck_01", "Head", "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
	"clavicle_r", "upperarm_r", "lowerarm_r", "hand_r"]

var model: Node3D
var skeleton: Skeleton3D
var anim: AnimationPlayer
var tree: AnimationTree
var gun_holder: Node3D
var hand_r: BoneAttachment3D
var helmet: Node3D
var cap: Node3D
var vest: MeshInstance3D
var aim_dir := Vector3.FORWARD
var _legs := ""
var _arms := ""
var _armed := false
var _dead := false
var _gun_len := 0.8
var hand_l: BoneAttachment3D
var _props: Dictionary = {}
var _busy := false
var _swim_lift := 0.0


func _ready() -> void:
	var ps: PackedScene = load("res://assets/characters/mannequin.glb")
	model = ps.instantiate()
	add_child(model)
	model.rotation.y = PI
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	anim = model.find_children("*", "AnimationPlayer", true, false)[0]
	var pi := randi() % PALETTES.size()
	var pal: Array = PALETTES[pi]
	var camo := ShaderMaterial.new()
	camo.shader = _camo_shader()
	var cc: Array = CAMO[pi]
	camo.set_shader_parameter("c_base", cc[0])
	camo.set_shader_parameter("c_a", cc[1])
	camo.set_shader_parameter("c_b", cc[2])
	camo.set_shader_parameter("c_c", cc[3])
	camo.set_shader_parameter("seed", randf() * 10.0)
	camo.set_shader_parameter("scale", randf_range(7.0, 11.0))
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for si in m.mesh.get_surface_count():
			if si == 0:
				m.set_surface_override_material(si, camo)
				continue
			var mat := StandardMaterial3D.new()
			mat.albedo_color = pal[1].lerp(Color(randf(), randf(), randf()), 0.04)
			mat.roughness = 0.85
			m.set_surface_override_material(si, mat)
	_build_gear(pal)
	_build_tree()
	gun_holder = Node3D.new()
	add_child(gun_holder)


# ------------------------------------------------------------------- gear ----
func _attach(bone: String, desired_in_body: Transform3D) -> Node3D:
	# Attach to a bone so the piece follows every animation, with a correction
	# so it sits at `desired_in_body` (body space, +Z = front) in the rest pose.
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	skeleton.add_child(att)
	var bi := skeleton.find_bone(bone)
	var rest := skeleton.get_bone_global_rest(bi)
	var skel_in_body := _rel(skeleton, self)
	var holder := Node3D.new()
	holder.transform = rest.affine_inverse() * skel_in_body.affine_inverse() * desired_in_body
	att.add_child(holder)
	return holder


func _rel(n: Node, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c := n
	while c != null and c != root:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t


func _mesh(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rough := 0.8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _build_gear(pal: Array) -> void:
	# Head: helmet (hidden until one is worn) or a soft cap, plus goggles.
	var head := _attach("Head", Transform3D(Basis.IDENTITY, Vector3(0, 1.67, 0.0)))
	helmet = Node3D.new()
	head.add_child(helmet)
	var dome := SphereMesh.new()
	dome.radius = 0.15
	dome.height = 0.2
	dome.is_hemisphere = true
	_mesh(helmet, dome, pal[1].darkened(0.1), Vector3(0, 0.0, 0), 0.6)
	_mesh(helmet, _box(Vector3(0.2, 0.035, 0.05)), Color(0.05, 0.05, 0.06), Vector3(0, 0.0, -0.13), 0.3)
	helmet.visible = false
	cap = Node3D.new()
	head.add_child(cap)
	var brim := CylinderMesh.new()
	brim.top_radius = 0.13
	brim.bottom_radius = 0.16
	brim.height = 0.07
	_mesh(cap, brim, pal[0].darkened(0.15), Vector3(0, 0.03, 0))
	# Plate carrier on the chest, pouches on the front.
	var chest := _attach("spine_03", Transform3D(Basis.IDENTITY, Vector3(0, 1.30, 0.0)))
	vest = _mesh(chest, _box(Vector3(0.38, 0.36, 0.27)), VEST_COLORS[0], Vector3.ZERO, 0.9)
	for i in 3:
		_mesh(vest, _box(Vector3(0.09, 0.11, 0.05)), VEST_COLORS[0].darkened(0.2), Vector3(-0.11 + i * 0.11, -0.08, -0.15), 0.9)
	vest.visible = false
	# Backpack.
	var back := _attach("spine_02", Transform3D(Basis.IDENTITY, Vector3(0, 1.18, 0.0)))
	var pack := _mesh(back, _box(Vector3(0.30, 0.40, 0.15)), pal[1], Vector3(0, 0.02, 0.2), 0.9)
	_mesh(pack, _box(Vector3(0.26, 0.08, 0.06)), pal[1].darkened(0.25), Vector3(0, 0.18, 0.06))
	# Belt with pouches.
	var hips := _attach("pelvis", Transform3D(Basis.IDENTITY, Vector3(0, 0.98, 0.0)))
	_mesh(hips, _box(Vector3(0.36, 0.06, 0.25)), Color(0.12, 0.12, 0.11), Vector3.ZERO)
	_mesh(hips, _box(Vector3(0.08, 0.1, 0.06)), pal[1], Vector3(0.18, -0.03, -0.06))


func set_gear(vest_level: int, helmet_level: int) -> void:
	if vest == null:
		return
	vest.visible = vest_level > 0
	if vest_level > 0:
		(vest.material_override as StandardMaterial3D).albedo_color = VEST_COLORS[clampi(vest_level - 1, 0, 2)]
	helmet.visible = helmet_level > 0
	cap.visible = helmet_level <= 0


# --------------------------------------------------------------- animation ----
func _build_tree() -> void:
	anim.stop()
	var skel_path := String(anim.get_animation("Idle").track_get_path(0)).split(":")[0]
	tree = AnimationTree.new()
	model.add_child(tree)
	tree.anim_player = tree.get_path_to(anim)
	tree.root_node = tree.get_path_to(model)
	var bt := AnimationNodeBlendTree.new()
	var legs_tr := AnimationNodeTransition.new()
	legs_tr.xfade_time = 0.2
	for a in LEG_ANIMS:
		legs_tr.add_input(a)
		var an := AnimationNodeAnimation.new()
		an.animation = a
		bt.add_node("L_" + a, an)
	bt.add_node("legs", legs_tr)
	for j in LEG_ANIMS.size():
		bt.connect_node("legs", j, "L_" + LEG_ANIMS[j])
	var ts := AnimationNodeTimeScale.new()
	bt.add_node("speed", ts)
	bt.connect_node("speed", 0, "legs")
	var arms_tr := AnimationNodeTransition.new()
	arms_tr.xfade_time = 0.15
	for a in ARM_ANIMS:
		arms_tr.add_input(a)
		var an := AnimationNodeAnimation.new()
		an.animation = a
		bt.add_node("A_" + a, an)
	bt.add_node("arms", arms_tr)
	for j in ARM_ANIMS.size():
		bt.connect_node("arms", j, "A_" + ARM_ANIMS[j])
	var blend := AnimationNodeBlend2.new()
	blend.filter_enabled = true
	for b in UPPER_BONES:
		blend.set_filter_path(NodePath(skel_path + ":" + b), true)
	bt.add_node("blend", blend)
	bt.connect_node("blend", 0, "speed")
	bt.connect_node("blend", 1, "arms")
	bt.connect_node("output", 0, "blend")
	tree.tree_root = bt
	# We drive the tree ourselves so distant soldiers can update less often.
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	set_legs("Idle")
	set_arms("")


func set_legs(name: String, speed := 1.0) -> void:
	if _dead or tree == null:
		return
	if name != _legs and name in LEG_ANIMS:
		_legs = name
		tree.set("parameters/legs/transition_request", name)
	tree.set("parameters/speed/scale", speed)


## "" = arms follow the legs, "idle" = gun held low, "aim" = gun up,
## "reload", or a healing item ("bandage", "med", "energy"): the gun is put
## away and the item shows in the hands.
func set_arms(mode: String) -> void:
	if _dead or tree == null or mode == _arms or _throw_hold > 0.0:
		return
	_arms = mode
	var heal := str(mode) if HEAL_ARMS.has(mode) else ""
	_show_props(heal)
	_busy = heal != ""
	if mode == "":
		tree.set("parameters/blend/blend_amount", 0.0)
	else:
		var a := "Pistol_Idle"
		if mode == "aim":
			a = "Pistol_Aim_Neutral"
		elif mode == "reload":
			a = "Pistol_Reload"
		elif heal != "":
			a = HEAL_ARMS[heal]
		tree.set("parameters/arms/transition_request", a)
		tree.set("parameters/blend/blend_amount", 1.0)


## Overarm throw (a grenade left this soldier's hand): a short swing of the
## arms that the regular arm state cannot interrupt.
var _throw_hold := 0.0


func play_throw() -> void:
	if _dead or tree == null:
		return
	_show_props("")
	_busy = true
	_arms = "throw"
	_throw_hold = 0.55
	tree.set("parameters/arms/transition_request", "Punch_Cross")
	tree.set("parameters/blend/blend_amount", 1.0)


func is_swimming() -> bool:
	return _legs.begins_with("Swim")


# ------------------------------------------------------------ drinking ----
var _drink_k := 0.0
var _ik_bones: PackedInt32Array = PackedInt32Array()


## Two-bone IK on the left arm, applied over the animated pose: the hand (and
## the can in it) goes up to the mouth, dipping a little between sips.
func _drink_ik(k: float) -> void:
	if _ik_bones.is_empty():
		for b in ["upperarm_l", "lowerarm_l", "hand_l", "Head"]:
			_ik_bones.append(skeleton.find_bone(b))
		if _ik_bones.has(-1):
			return
	var ua := skeleton.get_bone_global_pose(_ik_bones[0])
	var la := skeleton.get_bone_global_pose(_ik_bones[1])
	var hd := skeleton.get_bone_global_pose(_ik_bones[2])
	var head := skeleton.get_bone_global_pose(_ik_bones[3])
	var sh := ua.origin
	var l1 := sh.distance_to(la.origin)
	var l2 := la.origin.distance_to(hd.origin)
	var sip := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.0035)
	# Mouth: in front of and below the head bone (+Z is the model's front).
	var mouth := head.origin + Vector3(0.05, -0.09 - sip * 0.04, 0.16 + sip * 0.03)
	var target := hd.origin.lerp(mouth, k)
	var to := target - sh
	var d := clampf(to.length(), absf(l1 - l2) + 0.01, l1 + l2 - 0.005)
	var n := to.normalized()
	var pole := Vector3(0.5, -1.0, -0.2)
	var bend := (pole - n * pole.dot(n)).normalized()
	var a := acos(clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0))
	var elbow := sh + n * cos(a) * l1 + bend * sin(a) * l1
	var wrist := sh + n * d
	var r1 := Quaternion(ua.basis.y.normalized(), (elbow - sh).normalized())
	skeleton.set_bone_global_pose(_ik_bones[0], Transform3D(Basis(r1) * ua.basis, sh))
	var r2 := Quaternion(la.basis.y.normalized(), (wrist - elbow).normalized())
	skeleton.set_bone_global_pose(_ik_bones[1], Transform3D(Basis(r2) * la.basis, elbow))
	# Tip the can back as it reaches the lips.
	var tip := Basis(Vector3(0, 0, 1), -0.5 * k)
	skeleton.set_bone_global_pose(_ik_bones[2], Transform3D(Basis(r2) * tip * hd.basis, wrist))


# ------------------------------------------------------------ hand props ----
func _bone_att(bone: String) -> BoneAttachment3D:
	var a := BoneAttachment3D.new()
	a.bone_name = bone
	skeleton.add_child(a)
	return a


func _prop_mat(c: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _prop(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _pcyl(r: float, h: float, caps := true) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 1
	c.cap_top = caps
	c.cap_bottom = caps
	return c


## Hand bones run along +Y to the fingertips with the thumb toward +Z; the
## palm faces -X on the right hand and +X on the left.
func _build_props(kind: String) -> Array:
	if hand_l == null:
		hand_l = _bone_att("hand_l")
	if hand_r == null:
		hand_r = _bone_att("hand_r")
	var out: Array = []
	var white := _prop_mat(Color(0.95, 0.93, 0.87), 0.95)
	match kind:
		"bandage":
			var r := Node3D.new()
			hand_r.add_child(r)
			_prop(r, _pcyl(0.035, 0.065), white, Vector3(-0.04, 0.085, 0.0), Vector3(PI * 0.5, 0, 0))
			out.append(r)
			var arm := _bone_att("lowerarm_l")
			_prop(arm, _pcyl(0.052, 0.12, false), white, Vector3(0, 0.17, 0))
			out.append(arm)
		"med":
			var k := Node3D.new()
			hand_l.add_child(k)
			var box := BoxMesh.new()
			box.size = Vector3(0.075, 0.22, 0.16)
			_prop(k, box, _prop_mat(Color(0.92, 0.91, 0.88), 0.45), Vector3(0.07, 0.1, 0.0))
			var red := _prop_mat(Color(0.86, 0.1, 0.1), 0.5)
			for sx in [-1.0, 1.0]:
				var bar := BoxMesh.new()
				bar.size = Vector3(0.004, 0.08, 0.026)
				_prop(k, bar, red, Vector3(0.07 + sx * 0.039, 0.1, 0.0))
				var bar2 := BoxMesh.new()
				bar2.size = Vector3(0.004, 0.026, 0.08)
				_prop(k, bar2, red, Vector3(0.07 + sx * 0.039, 0.1, 0.0))
			out.append(k)
			var sy := Node3D.new()
			hand_r.add_child(sy)
			_prop(sy, _pcyl(0.011, 0.11), _prop_mat(Color(0.75, 1.0, 0.6), 0.2), Vector3(-0.03, 0.08, 0.02), Vector3(PI * 0.5, 0, 0))
			_prop(sy, _pcyl(0.003, 0.05), _prop_mat(Color(0.85, 0.85, 0.88), 0.2, 1.0), Vector3(-0.03, 0.08, -0.06), Vector3(PI * 0.5, 0, 0))
			out.append(sy)
		"energy":
			var c := Node3D.new()
			hand_l.add_child(c)
			_prop(c, _pcyl(0.034, 0.12), _prop_mat(Color(0.07, 0.5, 0.27), 0.3, 0.5), Vector3(0.042, 0.08, 0.0), Vector3(PI * 0.5, 0, 0))
			_prop(c, _pcyl(0.0345, 0.03, false), _prop_mat(Color(1.0, 0.8, 0.1), 0.35, 0.3), Vector3(0.042, 0.08, 0.0), Vector3(PI * 0.5, 0, 0))
			out.append(c)
	return out


func _show_props(kind: String) -> void:
	if kind != "" and not _props.has(kind):
		_props[kind] = _build_props(kind)
	for k in _props:
		for n in _props[k]:
			for c in (n as Node3D).get_children():
				if c is MeshInstance3D:
					(c as MeshInstance3D).visible = k == kind


func die() -> void:
	_show_props("")
	_dead = true
	if tree != null:
		tree.active = false
	anim.play("Death01", 0.15)
	gun_holder.visible = false


## Brief jolt of the whole body away from the hit.
func flinch(strength := 1.0) -> void:
	if _dead or model == null:
		return
	var tw := model.create_tween()
	tw.tween_property(model, "rotation:x", -0.16 * strength, 0.06).set_ease(Tween.EASE_OUT)
	tw.tween_property(model, "rotation:x", 0.0, 0.22).set_trans(Tween.TRANS_SINE)


# --------------------------------------------------------------------- gun ----
func set_gun(id: String) -> void:
	for c in gun_holder.get_children():
		c.queue_free()
	if id == "":
		_armed = false
		return
	_armed = true
	_gun_len = float(Weapons.def(id).get("len", 0.8))
	var g := Weapons.make_drop_node(id)
	g.scale = Vector3.ONE * _gun_len
	gun_holder.add_child(g)
	if hand_r == null:
		hand_r = BoneAttachment3D.new()
		hand_r.bone_name = "hand_r"
		skeleton.add_child(hand_r)


func muzzle_position() -> Vector3:
	return gun_holder.global_position + gun_holder.global_basis * Vector3(0, 0.02, -0.5 * _gun_len)


var _lod_t := 0.0
var _anim_acc := 0.0
var _anim_frame := 0
var _anim_every := 1


func _process(delta: float) -> void:
	if Prof.on:
		var t0 := Time.get_ticks_usec()
		_process_body(delta)
		Prof.add("rigs", Time.get_ticks_usec() - t0)
	else:
		_process_body(delta)


func _process_body(delta: float) -> void:
	if tree != null and tree.active:
		_anim_acc += delta
		_anim_frame += 1
		if _anim_frame >= _anim_every:
			tree.advance(_anim_acc)
			_anim_acc = 0.0
			_anim_frame = 0
			_drink_k = move_toward(_drink_k, 1.0 if _arms == "energy" else 0.0, delta * float(_anim_every) * 2.5)
			if _drink_k > 0.0 and not _dead:
				_drink_ik(_drink_k)
	# Far away: stop animating and stop drawing. You could not make out a
	# soldier past ~260 m, and 50 animated rigs are not free.
	_lod_t -= delta
	if _lod_t <= 0.0 and not _dead:
		_lod_t = 0.4 + randf() * 0.2
		var cam := get_viewport().get_camera_3d()
		if cam != null and model != null:
			var dist := cam.global_position.distance_to(global_position)
			_anim_every = 1 if dist < 60.0 else (2 if dist < 120.0 else 3)
			var near := dist < 260.0
			if near != model.visible:
				model.visible = near
				gun_holder.visible = near
				if tree != null:
					tree.active = near
	if _throw_hold > 0.0:
		_throw_hold -= delta
		if _throw_hold <= 0.0:
			_busy = false
			_arms = "?"
	# Swim strokes lie the body flat: float it up to the waterline.
	var lift := SWIM_LIFT if _legs == "Swim_Fwd" else 0.0
	if absf(_swim_lift - lift) > 0.001:
		_swim_lift = move_toward(_swim_lift, lift, delta * 2.5)
		model.position.y = _swim_lift
	var hide_gun := _busy or is_swimming()
	if gun_holder.visible == hide_gun and model.visible:
		gun_holder.visible = not hide_gun
	if not _armed or hand_r == null or _dead or not model.visible or hide_gun:
		return
	# The gun follows the right hand and points where the soldier is aiming;
	# the grip (behind the centre of the model) sits in the hand.
	var dir := aim_dir.normalized()
	if dir.length() < 0.5:
		dir = -global_basis.z
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.FORWARD
	gun_holder.global_transform = Transform3D(Basis.looking_at(dir, up), hand_r.global_position + dir * _gun_len * 0.18 + Vector3(0, 0.03, 0))
