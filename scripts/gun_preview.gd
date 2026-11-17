class_name GunPreview
extends SubViewportContainer

## A slowly turning 3D gun in its own little world, for menus.

var viewport: SubViewport
var pivot: Node3D
var gun_id := ""
var spin_speed := 0.35
var _t := 0.0


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(viewport)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.70, 0.73, 0.78)
	e.ambient_light_energy = 1.25
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	viewport.add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -40, 0)
	key.light_energy = 2.4
	key.light_color = Color(1.0, 0.95, 0.88)
	viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, 150, 0)
	rim.light_energy = 1.6
	rim.light_color = Color(0.6, 0.75, 1.0)
	viewport.add_child(rim)

	var cam := Camera3D.new()
	cam.fov = 26.0
	cam.position = Vector3(0, 0.05, 1.45)
	viewport.add_child(cam)
	cam.look_at(Vector3(0, 0.0, 0), Vector3.UP)

	pivot = Node3D.new()
	viewport.add_child(pivot)
	if gun_id != "":
		show_gun(gun_id)


func show_gun(id: String, optic := "") -> void:
	gun_id = id
	if pivot == null:
		return
	for c in pivot.get_children():
		c.queue_free()
	var n := Weapons.make_drop_node(id)
	# Normalised models are 1 m long; short guns get a little bigger.
	var length := float(Weapons.def(id).get("len", 0.8))
	n.scale = Vector3.ONE * lerpf(0.75, 1.0, clampf(length, 0.2, 1.2) / 1.2)
	# The sight it will carry, sized and seated as on the gun in your hands.
	if optic != "" and Weapons.optic_kind(optic) != "" and Weapons.scope_fits(id, optic):
		var s := Weapons.view_scale(id)
		var oy := Weapons.optic_center_y(id, optic)
		var top := float(Weapons.model(id).get("sight_y", 0.08)) * s
		var o := Weapons.build_optic(optic, oy - top)
		o.position = Vector3(0.0, oy, -0.02 if Weapons.cls(id) != "pistol" else 0.01) / s
		o.scale = Vector3.ONE / s
		n.add_child(o)
	pivot.add_child(n)


func _process(delta: float) -> void:
	if pivot == null or not is_visible_in_tree():
		return
	_t += delta
	# Turn to show both sides, but favour the classic side profile.
	pivot.rotation.y = -PI * 0.5 + sin(_t * spin_speed) * 0.9
	pivot.rotation.x = sin(_t * 0.6) * 0.04
