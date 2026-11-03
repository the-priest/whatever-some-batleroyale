class_name Weapons
extends RefCounted

# Weapon catalogue. Guns.json geometries are 1 m long on the Z axis with the
# muzzle at -Z; the thin axis (x) is widened at build time so they read as real
# 3D props instead of extruded silhouettes.

const DEFS := {
	"rifle": {
		"velocity": 540.0,
		"ads_time": 0.20, "bloom": 0.20, "bloom_max": 1.3,
		"name": "VK-47 RIFLE", "short": "RIFLE", "damage": 26.0, "rpm": 620.0,
		"mag": 30, "reserve": 210, "spread": 1.35, "ads_spread": 0.22,
		"recoil": 1.05, "range": 150.0, "auto": true, "reload": 2.45,
		"head": 2.1, "pellets": 1, "sound": "rifle", "tier": 2,
		"scale": 0.50, "hip": Vector3(0.185, -0.175, -0.42), "ads": Vector3(0.0, -0.092, -0.32),
		"kick": 0.030, "zoom": 1.25,
	},
	"smg": {
		"velocity": 360.0,
		"ads_time": 0.15, "bloom": 0.14, "bloom_max": 1.0,
		"name": "SP-9 SMG", "short": "SMG", "damage": 18.0, "rpm": 920.0,
		"mag": 35, "reserve": 280, "spread": 1.8, "ads_spread": 0.55,
		"recoil": 0.62, "range": 85.0, "auto": true, "reload": 1.95,
		"head": 1.9, "pellets": 1, "sound": "smg", "tier": 1,
		"scale": 0.42, "hip": Vector3(0.165, -0.150, -0.38), "ads": Vector3(0.0, -0.083, -0.30),
		"kick": 0.017, "zoom": 1.15,
	},
	"shotgun": {
		"velocity": 330.0,
		"ads_time": 0.20, "bloom": 0.0, "bloom_max": 0.0,
		"name": "M-12 BREACHER", "short": "SHOTGUN", "damage": 13.0, "rpm": 78.0,
		"mag": 6, "reserve": 48, "spread": 4.6, "ads_spread": 3.4,
		"recoil": 3.1, "range": 42.0, "auto": false, "reload": 3.05,
		"head": 1.7, "pellets": 8, "sound": "shotgun", "tier": 2,
		"scale": 0.50, "hip": Vector3(0.185, -0.170, -0.42), "ads": Vector3(0.0, -0.090, -0.33),
		"kick": 0.075, "zoom": 1.1,
	},
	"lmg": {
		"velocity": 560.0,
		"ads_time": 0.30, "bloom": 0.16, "bloom_max": 1.6,
		"name": "PK-74 BELT", "short": "LMG", "damage": 24.0, "rpm": 700.0,
		"mag": 100, "reserve": 300, "spread": 2.0, "ads_spread": 0.5,
		"recoil": 1.15, "range": 160.0, "auto": true, "reload": 4.7,
		"head": 2.0, "pellets": 1, "sound": "lmg", "tier": 3,
		"scale": 0.54, "hip": Vector3(0.205, -0.200, -0.45), "ads": Vector3(0.0, -0.100, -0.34),
		"kick": 0.028, "zoom": 1.2,
	},
	"dmr": {
		"velocity": 640.0,
		"ads_time": 0.24, "bloom": 0.45, "bloom_max": 1.2,
		"name": "SKS MARKSMAN", "short": "DMR", "damage": 46.0, "rpm": 300.0,
		"mag": 20, "reserve": 140, "spread": 0.9, "ads_spread": 0.10,
		"recoil": 1.9, "range": 220.0, "auto": false, "reload": 2.65,
		"head": 2.3, "pellets": 1, "sound": "dmr", "tier": 3,
		"scale": 0.52, "hip": Vector3(0.195, -0.180, -0.43), "ads": Vector3(0.0, -0.090, -0.34),
		"kick": 0.050, "zoom": 1.8,
	},
	"pistol": {
		"velocity": 310.0,
		"ads_time": 0.13, "bloom": 0.30, "bloom_max": 1.2,
		"name": "P-18 SIDEARM", "short": "PISTOL", "damage": 23.0, "rpm": 380.0,
		"mag": 15, "reserve": 120, "spread": 1.5, "ads_spread": 0.45,
		"recoil": 0.85, "range": 70.0, "auto": false, "reload": 1.75,
		"head": 2.0, "pellets": 1, "sound": "pistol", "tier": 1,
		"scale": 0.34, "hip": Vector3(0.145, -0.140, -0.34), "ads": Vector3(0.0, -0.082, -0.29),
		"kick": 0.026, "zoom": 1.05,
	},
	"sniper": {
		"velocity": 720.0,
		"ads_time": 0.32, "bloom": 0.0, "bloom_max": 0.0,
		"name": "AWM LONGBOW", "short": "SNIPER", "damage": 92.0, "rpm": 45.0,
		"mag": 5, "reserve": 40, "spread": 0.35, "ads_spread": 0.0,
		"recoil": 4.2, "range": 420.0, "auto": false, "reload": 3.55,
		"head": 2.5, "pellets": 1, "sound": "sniper", "tier": 4,
		"scale": 0.23, "hip": Vector3(0.195, -0.190, -0.46), "ads": Vector3(0.0, -0.098, -0.36),
		"kick": 0.10, "zoom": 4.2,
	},
}

const ORDER := ["rifle", "smg", "shotgun", "lmg", "dmr", "pistol", "sniper"]
const TIER_COLORS := [
	Color(0.72, 0.76, 0.80), # 1 common
	Color(0.36, 0.72, 0.46), # 2 uncommon
	Color(0.34, 0.56, 0.96), # 3 rare
	Color(0.82, 0.52, 0.98), # 4 epic
]

static var _geo: Dictionary = {}
static var _mats: Dictionary = {}
static var _view_mat: ShaderMaterial
static var _drop_mat: StandardMaterial3D


static func def(id: String) -> Dictionary:
	return DEFS.get(id, DEFS["pistol"])


const SCOPE_ZOOM := {"reddot": 1.3, "2x": 2.0, "4x": 4.0, "8x": 8.0}


static func scope_fits(gun: String, scope: String) -> bool:
	match scope:
		"reddot":
			return gun != "sniper"
		"2x", "4x":
			return gun in ["rifle", "smg", "lmg", "dmr", "sniper"]
		"8x":
			return gun in ["dmr", "sniper", "rifle"]
	return false


static func attachment_fits(gun: String, kind: String) -> bool:
	if kind == "extmag":
		return gun != "shotgun" and gun != "lmg"
	if kind == "comp":
		return gun != "shotgun"
	return false


## Reserve ammo that comes with a freshly looted gun: two magazines.
static func starting_reserve(id: String) -> int:
	var d := def(id)
	return mini(int(d["reserve"]), int(d["mag"]) * 2)


static func tier_color(id: String) -> Color:
	return TIER_COLORS[clampi(int(def(id).get("tier", 1)) - 1, 0, 3)]


# ---------------------------------------------------------------- geometry --
static func geo_arrays(id: String) -> Dictionary:
	if _geo.has(id):
		return _geo[id]
	var path := "res://assets/guns/guns.json"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("cannot open " + path)
		return {}
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	var raw: Dictionary = data.get(id, {})
	var verts: PackedVector3Array = PackedVector3Array()
	var norms: PackedVector3Array = PackedVector3Array()
	var pos: Array = raw.get("pos", [])
	var nrm: Array = raw.get("nrm", [])
	var thick := 2.9
	for i in range(0, int(raw.get("verts", 0))):
		var b := i * 3
		if b + 2 >= pos.size():
			break
		verts.append(Vector3(float(pos[b]) * thick, float(pos[b + 1]), float(pos[b + 2])))
		if b + 2 < nrm.size():
			norms.append(Vector3(float(nrm[b]), float(nrm[b + 1]), float(nrm[b + 2])).normalized())
		else:
			norms.append(Vector3.UP)
	var out := {"verts": verts, "norms": norms}
	_geo[id] = out
	return out


static func mesh(id: String) -> ArrayMesh:
	var cache_key := "mesh_" + id
	if _mats.has(cache_key):
		return _mats[cache_key]
	var arrays := geo_arrays(id)
	if arrays.is_empty():
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var verts: PackedVector3Array = arrays["verts"]
	var norms: PackedVector3Array = arrays["norms"]
	for i in range(verts.size()):
		st.set_normal(norms[i])
		st.add_vertex(verts[i])
	var m := st.commit()
	_mats[cache_key] = m
	return m


static func view_material(id: String) -> ShaderMaterial:
	if _view_mat == null:
		_view_mat = ShaderMaterial.new()
		_view_mat.shader = load("res://shaders/gun.gdshader")
	var mat: ShaderMaterial = _view_mat.duplicate()
	mat.set_shader_parameter("accent_amount", 0.55 if id == "sniper" or id == "dmr" else 0.22)
	mat.set_shader_parameter("accent", tier_color(id) * 0.8)
	return mat


static func drop_material(id: String) -> StandardMaterial3D:
	if _drop_mat == null:
		_drop_mat = StandardMaterial3D.new()
		_drop_mat.metallic = 0.72
		_drop_mat.roughness = 0.34
		_drop_mat.albedo_color = Color(0.26, 0.28, 0.31)
	var m: StandardMaterial3D = _drop_mat.duplicate()
	m.rim_enabled = true
	m.rim = 0.55
	m.rim_tint = 0.6
	m.emission_enabled = true
	m.emission = tier_color(id) * 0.55
	m.emission_energy_multiplier = 0.55
	return m


static func build_view_model(id: String) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Gun_" + id
	if id == "sniper":
		var ps: PackedScene = load("res://assets/guns/sniper.gltf")
		if ps != null:
			var inst: Node3D = ps.instantiate()
			# glTF sniper is 4.7 units long with the muzzle at +Z; normalise to 1 m
			# and rotate so the muzzle points down -Z like every other weapon.
			var norm := Node3D.new()
			norm.rotation.y = PI
			norm.scale = Vector3.ONE * 0.2125
			norm.add_child(inst)
			# Realign the model's bbox centre to the holder origin.
			norm.position = Vector3(0.0, -0.015, 0.0)
			holder.add_child(norm)
			_apply_gun_shading(inst)
			return holder
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(id)
	mi.material_override = view_material(id)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Keep the viewmodel out of the world's depth-test fight with its own hands.
	mi.layers = 2
	holder.add_child(mi)
	return holder


## Where each gun's magazine sits in its normalised 1 m model space:
## [centre, size]. Used for the drop-and-insert reload animation.
const MAGS := {
	"rifle": [Vector3(0.0, -0.080, 0.045), Vector3(0.046, 0.150, 0.066)],
	"smg": [Vector3(0.0, -0.100, 0.000), Vector3(0.040, 0.160, 0.050)],
	"lmg": [Vector3(0.0, -0.085, 0.020), Vector3(0.085, 0.120, 0.120)],
	"dmr": [Vector3(0.0, -0.070, 0.060), Vector3(0.040, 0.100, 0.060)],
	"pistol": [Vector3(0.0, -0.105, 0.235), Vector3(0.036, 0.120, 0.050)],
	"sniper": [Vector3(0.0, -0.060, 0.000), Vector3(0.040, 0.070, 0.080)],
}


static func build_magazine(id: String) -> MeshInstance3D:
	var spec: Array = MAGS.get(id, MAGS["rifle"])
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = spec[1]
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.07, 0.075, 0.085)
	m.metallic = 0.7
	m.roughness = 0.42
	mi.material_override = m
	mi.position = spec[0]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = 2
	return mi


static func _apply_gun_shading(n: Node) -> void:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = 2
		if mi.mesh != null:
			for s in range(mi.mesh.get_surface_count()):
				var m := mi.get_active_material(s)
				if m is BaseMaterial3D:
					m = (m as BaseMaterial3D).duplicate()
					(m as BaseMaterial3D).metallic = 0.75
					(m as BaseMaterial3D).roughness = 0.35
					mi.set_surface_override_material(s, m)
	for c in n.get_children():
		_apply_gun_shading(c)


static func make_drop_node(id: String) -> Node3D:
	var root := Node3D.new()
	if id == "sniper":
		var ps: PackedScene = load("res://assets/guns/sniper.gltf")
		if ps != null:
			var inst: Node3D = ps.instantiate()
			var norm := Node3D.new()
			norm.rotation.y = PI
			norm.scale = Vector3.ONE * 0.2125
			norm.add_child(inst)
			root.add_child(norm)
			_apply_gun_shading(inst)
			return root
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(id)
	mi.material_override = drop_material(id)
	root.add_child(mi)
	return root
