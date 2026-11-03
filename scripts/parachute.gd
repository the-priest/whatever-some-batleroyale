class_name Parachute
extends RefCounted

## Ram-air canopy: a curved row of cells in two colours, with suspension lines
## running down to the harness. The node's origin is at the harness.

const SCHEMES := [
	[Color(0.85, 0.36, 0.20), Color(0.95, 0.88, 0.72)],
	[Color(0.30, 0.36, 0.26), Color(0.62, 0.60, 0.48)],
	[Color(0.20, 0.32, 0.56), Color(0.88, 0.88, 0.90)],
	[Color(0.62, 0.18, 0.18), Color(0.20, 0.20, 0.22)],
]


static func build(scheme: int = -1, height := 3.8) -> Node3D:
	var root := Node3D.new()
	root.name = "Parachute"
	var cols: Array = SCHEMES[(randi() if scheme < 0 else scheme) % SCHEMES.size()]
	var mats: Array = []
	for c in cols:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.85
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mats.append(m)
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.85, 0.85, 0.82)
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var cells := 9
	var arc := deg_to_rad(110.0)
	var radius := 3.4
	var chord := 2.1
	for i in cells:
		var f := (float(i) + 0.5) / float(cells) - 0.5
		var a := f * arc
		var cell := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.0 * radius * sin(arc / float(cells) * 0.5) + 0.02, 0.32, chord)
		cell.mesh = bm
		cell.material_override = mats[i % 2]
		cell.position = Vector3(sin(a) * radius, height + cos(a) * radius - radius, 0)
		cell.rotation.z = -a
		root.add_child(cell)
		# Cell opening ribs give the leading edge some texture.
		var rib := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = Vector3(0.04, 0.34, chord * 0.98)
		rib.mesh = rb
		rib.material_override = mats[(i + 1) % 2]
		rib.position = cell.position + Vector3(cos(a), -sin(a), 0) * (bm.size.x * 0.5)
		rib.rotation.z = -a
		root.add_child(rib)
		# Two lines per cell to the harness.
		for z in [-chord * 0.35, chord * 0.35]:
			var top := cell.position + Vector3(0, -0.16, z)
			var bottom := Vector3(sign(top.x) * 0.15, 0.6, z * 0.15)
			var line := MeshInstance3D.new()
			var lm := BoxMesh.new()
			var len := top.distance_to(bottom)
			lm.size = Vector3(0.012, 0.012, len)
			line.mesh = lm
			line.material_override = line_mat
			line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var dir := (top - bottom).normalized()
			line.transform = Transform3D(Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT), (top + bottom) * 0.5)
			root.add_child(line)
	return root
