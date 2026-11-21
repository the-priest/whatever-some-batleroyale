class_name CharPreview
extends SubViewportContainer
## A character standing in its own little lit world: the class cards on the
## menu. It idles, turns slowly, and swings when you choose it.

var _vp: SubViewport
var _pivot: Node3D
var _model: Node3D
var _anim: AnimationPlayer
var _t := 0.0
var _swing := 0.0
var spin := true


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.5, 0.48)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 1.05, 4.4)
	cam.look_at_from_position(cam.position, Vector3(0, 0.92, 0))
	_vp.add_child(cam)
	# Warm key light from the front left, a cold rim from behind.
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.86, 0.7)
	key.light_energy = 1.5
	key.rotation = Vector3(deg_to_rad(-30), deg_to_rad(-35), 0)
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.55, 0.7, 1.0)
	rim.light_energy = 1.1
	rim.rotation = Vector3(deg_to_rad(-15), deg_to_rad(160), 0)
	_vp.add_child(rim)
	var ember := OmniLight3D.new()
	ember.light_color = Color(1.0, 0.45, 0.15)
	ember.light_energy = 1.2
	ember.omni_range = 3.0
	ember.position = Vector3(0, 0.1, 1.0)
	_vp.add_child(ember)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	# A disc of dark stone to stand on.
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.75
	cm.bottom_radius = 0.82
	cm.height = 0.08
	disc.mesh = cm
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.09, 0.085, 0.08)
	dm.roughness = 0.9
	disc.material_override = dm
	disc.position.y = -0.04
	_vp.add_child(disc)


func show_skin(path: String, height := 1.8) -> void:
	if _model != null:
		_model.queue_free()
		_model = null
		_anim = null
	var ps := load(path) as PackedScene
	if ps == null:
		return
	_model = ps.instantiate() as Node3D
	_pivot.add_child(_model)
	var box := SoldierRig.skin_box(_model)
	if box.size.y > 0.00001:
		var k := height / box.size.y
		_model.scale = Vector3.ONE * k
		_model.position.y = -box.position.y * k
	var aps := _model.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		_anim = aps[0] as AnimationPlayer
		if _anim.has_animation("Idle"):
			_anim.get_animation("Idle").loop_mode = Animation.LOOP_LINEAR
			_anim.play("Idle")


## Swing the weapon once (on being chosen).
func flourish() -> void:
	if _anim != null and _anim.has_animation("Attack"):
		_anim.play("Attack", 0.1)
		_swing = _anim.get_animation("Attack").length


static func _rel(n: Node, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c := n
	while c != null and c != root:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	if spin:
		_pivot.rotation.y = sin(_t * 0.45) * 0.55
	if _swing > 0.0:
		_swing -= delta
		if _swing <= 0.0 and _anim != null and _anim.has_animation("Idle"):
			_anim.play("Idle", 0.2)
