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
const VEST_COLORS := [Color(0.55, 0.50, 0.38), Color(0.30, 0.34, 0.24), Color(0.10, 0.11, 0.12)]
const LEG_ANIMS := ["Idle", "Walk", "Jog_Fwd", "Sprint", "Jump", "Crouch_Idle", "Crouch_Fwd"]
const ARM_ANIMS := ["Pistol_Idle", "Pistol_Aim_Neutral", "Pistol_Reload"]
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


func _ready() -> void:
	var ps: PackedScene = load("res://assets/characters/mannequin.glb")
	model = ps.instantiate()
	add_child(model)
	model.rotation.y = PI
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	anim = model.find_children("*", "AnimationPlayer", true, false)[0]
	var pal: Array = PALETTES[randi() % PALETTES.size()]
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for si in m.mesh.get_surface_count():
			var mat := StandardMaterial3D.new()
			mat.albedo_color = (pal[0] if si == 0 else pal[1]).lerp(Color(randf(), randf(), randf()), 0.04)
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


## "" = arms follow the legs, "idle" = gun held low, "aim" = gun up.
func set_arms(mode: String) -> void:
	if _dead or tree == null or mode == _arms:
		return
	_arms = mode
	if mode == "":
		tree.set("parameters/blend/blend_amount", 0.0)
	else:
		var a := "Pistol_Idle"
		if mode == "aim":
			a = "Pistol_Aim_Neutral"
		elif mode == "reload":
			a = "Pistol_Reload"
		tree.set("parameters/arms/transition_request", a)
		tree.set("parameters/blend/blend_amount", 1.0)


func die() -> void:
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
	if tree != null and tree.active:
		_anim_acc += delta
		_anim_frame += 1
		if _anim_frame >= _anim_every:
			tree.advance(_anim_acc)
			_anim_acc = 0.0
			_anim_frame = 0
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
	if not _armed or hand_r == null or _dead or not model.visible:
		return
	# The gun follows the right hand and points where the soldier is aiming;
	# the grip (behind the centre of the model) sits in the hand.
	var dir := aim_dir.normalized()
	if dir.length() < 0.5:
		dir = -global_basis.z
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.FORWARD
	gun_holder.global_transform = Transform3D(Basis.looking_at(dir, up), hand_r.global_position + dir * _gun_len * 0.18 + Vector3(0, 0.03, 0))
