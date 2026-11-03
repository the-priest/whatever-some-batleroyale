extends SceneTree
func _init():
	var root3d := Node3D.new()
	root.add_child(root3d)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.6, 0.65)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.85)
	e.ambient_light_energy = 0.6
	env.environment = e
	root3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	root3d.add_child(sun)
	var files: Array = []
	for f in DirAccess.open("res://assets/guns/q").get_files():
		if f.ends_with(".glb") or f.ends_with(".obj"):
			files.append(f)
	files.sort()
	var cols := 4
	for i in files.size():
		var f: String = files[i]
		var r = load("res://assets/guns/q/" + f)
		var n: Node3D
		if r is PackedScene:
			n = r.instantiate()
		else:
			var mi := MeshInstance3D.new()
			mi.mesh = r
			n = mi
		var holder := Node3D.new()
		holder.add_child(n)
		root3d.add_child(holder)
		holder.position = Vector3((i % cols) * 8.5 - 12.5, -(i / cols) * 2.6 + 7.0, 0)
		var l := Label3D.new()
		l.text = f + "  (+X →)"
		l.pixel_size = 0.01
		l.font_size = 48
		l.modulate = Color.BLACK
		l.position = holder.position + Vector3(0, -1.0, 0.5)
		root3d.add_child(l)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 19.0
	cam.position = Vector3(0, 0, 30)
	root3d.add_child(cam)
	cam.make_current()
	for k in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/shots/sheet.png")
	quit()
