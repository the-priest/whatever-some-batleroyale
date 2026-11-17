class_name MeshMerge
extends RefCounted
## Folds many small procedural meshes into one, so a model built from
## dozens of boxes costs a draw call per material instead of one per box.


## Fold the parent's MeshInstance3D children (but not `keep`) into one mesh
## with a surface per material. Transparent and shader-driven parts stay as
## they are (they sort or animate on their own); the merged mesh takes its
## render layers and shadow setting from the parts.
static func merge(parent: Node3D, keep: Array) -> void:
	var by_mat := {}
	var order: Array[Material] = []
	var first: MeshInstance3D = null
	for c in parent.get_children():
		if not (c is MeshInstance3D) or keep.has(c):
			continue
		var mi := c as MeshInstance3D
		if mi.mesh == null:
			continue
		var mat := mi.material_override
		if mat == null:
			mat = mi.mesh.surface_get_material(0)
		if mat is ShaderMaterial or (mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED):
			continue
		if mi.mesh == null or mi.mesh.get_surface_count() != 1 or mi.get_surface_override_material_count() > 0 and mi.get_surface_override_material(0) != null:
			continue
		if first == null:
			first = mi
		elif mi.layers != first.layers or mi.cast_shadow != first.cast_shadow:
			continue
		if not by_mat.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			by_mat[mat] = st
			order.append(mat)
		(by_mat[mat] as SurfaceTool).append_from(mi.mesh, 0, mi.transform)
		if mi != first:
			parent.remove_child(mi)
			mi.queue_free()
	if order.is_empty():
		return
	var am := ArrayMesh.new()
	for mat in order:
		(by_mat[mat] as SurfaceTool).commit(am)
		am.surface_set_material(am.get_surface_count() - 1, mat)
	var out := MeshInstance3D.new()
	out.name = "Merged"
	out.mesh = am
	out.layers = first.layers
	out.cast_shadow = first.cast_shadow
	out.visibility_range_end = first.visibility_range_end
	parent.remove_child(first)
	first.queue_free()
	parent.add_child(out)
