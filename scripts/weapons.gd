class_name Weapons
extends RefCounted

# Weapon catalogue and model loading.
#
# Models are Quaternius' CC0 Ultimate Gun Pack (assets/guns/q). Each one is
# normalised at load time to a 1 m long, centred model with the muzzle at -Z,
# and its magazine is cut out of the mesh into a separate piece so reloads can
# drop the real magazine. Names are fictional.

const DEFS := {
	# ------------------------------------------------------------ rifles ----
	"rifle": {
		"name": "AR-74", "short": "AR-74", "cls": "ar", "cal": "7.62", "model": "res://assets/guns/q/ak74.glb",
		"damage": 47.0, "rpm": 600.0, "mag": 30, "reserve": 210, "auto": true, "pellets": 1,
		"spread": 1.4, "ads_spread": 0.24, "recoil": 1.25, "kick": 0.032, "pat": 1.0,
		"range": 160.0, "velocity": 600.0, "reload": 2.5, "head": 2.30, "zoom": 1.25,
		"ads_time": 0.22, "bloom": 0.22, "bloom_max": 1.4, "sound": "ak", "tier": 2, "len": 0.88,
	},
	"carbine": {
		"name": "CR-4 CARBINE", "short": "CR-4", "cls": "ar", "cal": "5.56", "model": "res://assets/guns/q/scarl.glb",
		"damage": 41.0, "rpm": 700.0, "mag": 30, "reserve": 210, "auto": true, "pellets": 1,
		"spread": 1.2, "ads_spread": 0.18, "recoil": 0.9, "kick": 0.026, "pat": -0.7,
		"range": 170.0, "velocity": 640.0, "reload": 2.2, "head": 2.30, "zoom": 1.25,
		"ads_time": 0.20, "bloom": 0.17, "bloom_max": 1.2, "sound": "rifle", "tier": 2, "len": 0.84,
	},
	"bullpup": {
		"name": "BX-9 BULLPUP", "short": "BX-9", "cls": "ar", "cal": "5.56", "model": "res://assets/guns/q/Bullpup_2.obj",
		"damage": 41.0, "rpm": 760.0, "mag": 30, "reserve": 210, "auto": true, "pellets": 1,
		"spread": 1.3, "ads_spread": 0.22, "recoil": 1.0, "kick": 0.028, "pat": 0.6,
		"range": 160.0, "velocity": 650.0, "reload": 2.6, "head": 2.30, "zoom": 1.3,
		"ads_time": 0.21, "bloom": 0.18, "bloom_max": 1.3, "sound": "rifle", "tier": 3, "len": 0.75, "mag_at": "rear",
	},
	# --------------------------------------------------------------- smgs ----
	"smg": {
		"name": "MK-5 SMG", "short": "MK-5", "cls": "smg", "cal": "9mm", "model": "res://assets/guns/q/mp5a5.glb",
		"damage": 33.0, "rpm": 850.0, "mag": 30, "reserve": 240, "auto": true, "pellets": 1,
		"spread": 1.6, "ads_spread": 0.5, "recoil": 0.6, "kick": 0.017, "pat": -1.0,
		"range": 90.0, "velocity": 400.0, "reload": 2.0, "head": 2.10, "zoom": 1.15,
		"ads_time": 0.15, "bloom": 0.13, "bloom_max": 1.0, "sound": "smg", "tier": 1, "len": 0.62,
	},
	"grease": {
		"name": "UMC GREASE GUN", "short": "UMC", "cls": "smg", "cal": "9mm", "model": "res://assets/guns/q/m3a1.glb",
		"damage": 38.0, "rpm": 600.0, "mag": 30, "reserve": 240, "auto": true, "pellets": 1,
		"spread": 1.5, "ads_spread": 0.45, "recoil": 0.55, "kick": 0.016, "pat": 0.5,
		"range": 80.0, "velocity": 330.0, "reload": 2.3, "head": 2.10, "zoom": 1.15,
		"ads_time": 0.16, "bloom": 0.12, "bloom_max": 0.9, "sound": "smg", "tier": 1, "len": 0.66,
	},
	# ------------------------------------------------------------ pistols ----
	"pistol": {
		"name": "P-26 SIDEARM", "short": "P-26", "cls": "pistol", "cal": "9mm", "model": "res://assets/guns/q/p226.glb",
		"damage": 35.0, "rpm": 380.0, "mag": 15, "reserve": 120, "auto": false, "pellets": 1,
		"spread": 1.4, "ads_spread": 0.4, "recoil": 0.85, "kick": 0.026, "pat": 1.0,
		"range": 70.0, "velocity": 350.0, "reload": 1.6, "head": 2.10, "zoom": 1.05,
		"ads_time": 0.13, "bloom": 0.30, "bloom_max": 1.2, "sound": "pistol", "tier": 1, "len": 0.21, "mag_at": "grip",
	},
	"m1911": {
		"name": "M-11 .45", "short": "M-11", "cls": "pistol", "cal": "9mm", "model": "res://assets/guns/q/m1911.glb",
		"damage": 41.0, "rpm": 300.0, "mag": 8, "reserve": 64, "auto": false, "pellets": 1,
		"spread": 1.3, "ads_spread": 0.38, "recoil": 1.15, "kick": 0.032, "pat": -1.0,
		"range": 70.0, "velocity": 300.0, "reload": 1.7, "head": 2.10, "zoom": 1.05,
		"ads_time": 0.13, "bloom": 0.36, "bloom_max": 1.2, "sound": "pistol", "tier": 1, "len": 0.22, "mag_at": "grip",
	},
	# ----------------------------------------------------------- shotguns ----
	"shotgun": {
		"name": "M-12 PUMP", "short": "M-12", "cls": "shotgun", "cal": "12ga", "model": "res://assets/guns/q/Shotgun_2.obj",
		"damage": 26.0, "rpm": 70.0, "mag": 5, "reserve": 40, "auto": false, "pellets": 9,
		"spread": 4.4, "ads_spread": 3.4, "recoil": 3.1, "kick": 0.075, "pat": 0.0,
		"range": 45.0, "velocity": 330.0, "reload": 3.2, "head": 1.50, "zoom": 1.1,
		"ads_time": 0.2, "bloom": 0.0, "bloom_max": 0.0, "sound": "shotgun", "tier": 2, "len": 1.0, "mag_at": "none", "pump": true,
	},
	"autoshotgun": {
		"name": "S-12 AUTO", "short": "S-12", "cls": "shotgun", "cal": "12ga", "model": "res://assets/guns/q/Shotgun_1.obj",
		"damage": 23.0, "rpm": 190.0, "mag": 5, "reserve": 40, "auto": false, "pellets": 9,
		"spread": 5.0, "ads_spread": 3.8, "recoil": 2.4, "kick": 0.06, "pat": 0.0,
		"range": 38.0, "velocity": 330.0, "reload": 3.0, "head": 1.50, "zoom": 1.1,
		"ads_time": 0.2, "bloom": 0.0, "bloom_max": 0.0, "sound": "shotgun", "tier": 3, "len": 0.98, "mag_at": "none",
	},
	# ----------------------------------------------------------- heavies ----
	"lmg": {
		"name": "HB-75 SUPPORT", "short": "HB-75", "cls": "lmg", "cal": "5.56", "model": "res://assets/guns/q/Bullpup_1.obj",
		"damage": 42.0, "rpm": 680.0, "mag": 75, "reserve": 300, "auto": true, "pellets": 1,
		"spread": 2.0, "ads_spread": 0.5, "recoil": 1.15, "kick": 0.028, "pat": 0.8,
		"range": 170.0, "velocity": 640.0, "reload": 4.6, "head": 2.30, "zoom": 1.2,
		"ads_time": 0.3, "bloom": 0.16, "bloom_max": 1.6, "sound": "lmg", "tier": 3, "len": 0.95, "mag_at": "rear",
	},
	"dmr": {
		"name": "VK MARKSMAN", "short": "VK", "cls": "dmr", "cal": "7.62", "model": "res://assets/guns/q/vss.glb",
		"damage": 55.0, "rpm": 280.0, "mag": 10, "reserve": 100, "auto": false, "pellets": 1,
		"spread": 0.9, "ads_spread": 0.1, "recoil": 1.8, "kick": 0.05, "pat": 1.0,
		"range": 260.0, "velocity": 700.0, "reload": 2.7, "head": 2.35, "zoom": 1.6, "scope": "4x",
		"ads_time": 0.26, "bloom": 0.45, "bloom_max": 1.2, "sound": "dmr", "tier": 3, "len": 1.0,
	},
	# ------------------------------------------------------------ snipers ----
	"m24": {
		"name": "M-24 HUNTER", "short": "M-24", "cls": "sniper", "cal": "7.62", "model": "res://assets/guns/q/m24.glb",
		"damage": 79.0, "rpm": 48.0, "mag": 5, "reserve": 40, "auto": false, "pellets": 1, "bolt": true,
		"spread": 0.35, "ads_spread": 0.0, "recoil": 3.8, "kick": 0.09, "pat": 0.0,
		"range": 450.0, "velocity": 760.0, "reload": 3.4, "head": 2.50, "zoom": 1.5, "scope": "4x",
		"ads_time": 0.3, "bloom": 0.0, "bloom_max": 0.0, "sound": "sniper", "tier": 3, "len": 1.12, "mag_at": "none",
	},
	"axmc": {
		"name": "AX-338", "short": "AX-338", "cls": "sniper", "cal": "7.62", "model": "res://assets/guns/q/axmc.glb",
		"damage": 98.0, "rpm": 45.0, "mag": 5, "reserve": 40, "auto": false, "pellets": 1, "bolt": true,
		"spread": 0.35, "ads_spread": 0.0, "recoil": 4.1, "kick": 0.1, "pat": 0.0,
		"range": 480.0, "velocity": 800.0, "reload": 3.5, "head": 2.50, "zoom": 1.5, "scope": "4x",
		"ads_time": 0.32, "bloom": 0.0, "bloom_max": 0.0, "sound": "sniper", "tier": 4, "len": 1.15, "mag_at": "none",
	},
	"sniper": {
		"name": "AWM LONGBOW", "short": "AWM", "cls": "sniper", "cal": "7.62", "model": "res://assets/guns/q/awm.glb",
		"damage": 120.0, "rpm": 42.0, "mag": 5, "reserve": 40, "auto": false, "pellets": 1, "bolt": true,
		"spread": 0.3, "ads_spread": 0.0, "recoil": 4.4, "kick": 0.1, "pat": 0.0,
		"range": 520.0, "velocity": 820.0, "reload": 3.6, "head": 2.50, "zoom": 1.5, "scope": "4x",
		"ads_time": 0.34, "bloom": 0.0, "bloom_max": 0.0, "sound": "sniper", "tier": 4, "len": 1.2, "mag_at": "none",
	},
}

const ORDER := ["pistol", "m1911", "smg", "grease", "shotgun", "autoshotgun", "rifle", "carbine", "bullpup", "lmg", "dmr", "m24", "axmc", "sniper"]
const TIER_COLORS := [
	Color(0.72, 0.76, 0.80), # 1 common
	Color(0.36, 0.72, 0.46), # 2 uncommon
	Color(0.34, 0.56, 0.96), # 3 rare
	Color(0.82, 0.52, 0.98), # 4 epic
]
const SCOPE_ZOOM := {"reddot": 1.3, "2x": 2.0, "4x": 4.0, "8x": 8.0}
const AMMO_CAP := {"9mm": 240, "5.56": 300, "7.62": 140, "12ga": 60}
const AMMO_BOX := {"9mm": 60, "5.56": 60, "7.62": 30, "12ga": 15}
const ZERO_MAX := {"sniper": 600, "dmr": 500, "ar": 400, "lmg": 300}

static var _flash_tex: Texture2D
static var _models: Dictionary = {}


static func def(id: String) -> Dictionary:
	return DEFS.get(id, DEFS["pistol"])


static func cls(id: String) -> String:
	return str(def(id).get("cls", "ar"))


static func caliber(id: String) -> String:
	return str(def(id).get("cal", "9mm"))


static func zero_max(id: String) -> int:
	return int(ZERO_MAX.get(cls(id), 100))


static func builtin_scope(id: String) -> String:
	return str(def(id).get("scope", ""))


static func tier_color(id: String) -> Color:
	return TIER_COLORS[clampi(int(def(id).get("tier", 1)) - 1, 0, 3)]


## A box of the gun's calibre comes with a fresh gun from a bot or a drop.
static func starting_reserve(id: String) -> int:
	return int(AMMO_BOX.get(caliber(id), 30))


static func scope_fits(gun: String, scope: String) -> bool:
	var c := cls(gun)
	match scope:
		"reddot":
			return c in ["ar", "smg", "lmg", "pistol", "shotgun"]
		"2x":
			return c in ["ar", "smg", "lmg", "dmr"]
		"4x":
			return c in ["ar", "lmg", "dmr"]
		"8x":
			return c in ["dmr", "sniper"]
	return false


static func attachment_fits(gun: String, kind: String) -> bool:
	var c := cls(gun)
	if kind == "extmag":
		return c in ["ar", "smg", "pistol", "dmr"]
	if kind == "comp":
		return c in ["ar", "smg", "lmg", "dmr", "pistol"]
	return false


## Learnable spray pattern: horizontal (degrees, signed) and a vertical
## multiplier for the n-th shot of a spray. Small jitter is added by the caller.
static func recoil_step(id: String, n: int) -> Vector2:
	var k := float(n)
	var side := float(def(id).get("pat", 1.0))
	match cls(id):
		"ar":
			# Straight up for five, then a lazy drift to one side and back.
			var h := 0.0 if n < 5 else (sin((k - 5.0) * 0.35) * 0.55 + 0.12) * side
			return Vector2(h, 1.0 + minf(k, 10.0) * 0.035)
		"smg":
			return Vector2((-0.10 + sin(k * 0.6) * 0.25) * side, 0.9 + minf(k, 14.0) * 0.015)
		"lmg":
			# Heavy start that settles once the belt is running.
			return Vector2(sin(k * 0.22) * 0.45 * side, 1.25 - minf(k, 12.0) * 0.035)
		"pistol":
			return Vector2(sin(k * 1.7) * 0.3 * side, 1.0)
		"dmr":
			return Vector2(0.25 * (1.0 if n % 2 == 0 else -1.0), 1.0)
	return Vector2(0.0, 1.0)


## Angle (radians) the bore is tilted up so a round crosses the sight line at
## `zero` metres.
static func zero_angle(id: String, zero: float) -> float:
	var v := float(def(id).get("velocity", 500.0))
	var t := zero / v
	return atan((0.5 * 9.8 * t * t) / maxf(1.0, zero))


## Viewmodel scale and hold positions derived from the gun's real length.
static func view_scale(id: String) -> float:
	return 0.12 + float(def(id).get("len", 0.8)) * 0.36


static func hip_pos(id: String) -> Vector3:
	var s := view_scale(id)
	if cls(id) == "pistol":
		return Vector3(0.13, -0.13, -0.30)
	# Stock at the shoulder (just behind the camera), gun low and to the right.
	return Vector3(0.11 + s * 0.12, -0.10 - s * 0.12, -s * 0.5 + 0.04)


## Aim position. With an optic, the optic's axis lands exactly on the screen
## centre; with iron sights, the tallest sight point (rear sight or front post)
## sits on it.
static func ads_pos(id: String, optic: String = "") -> Vector3:
	var s := view_scale(id)
	var m := model(id)
	var z := -0.27 if cls(id) == "pistol" else -s * 0.5 + 0.06
	if optic != "" and optic_kind(optic) != "":
		var oy := optic_center_y(id, optic)
		return Vector3(0.0, -oy, z - 0.02)
	var top: float = maxf(float(m.get("sight_y", 0.08)), float(m.get("front_y", 0.0)))
	return Vector3(0.0, -top * s - 0.003, z)


# --------------------------------------------------------------- optics ----
## Optic geometry is authored in metres. "kind" groups the shapes.
const OPTIC_SPECS := {
	"reddot": {"kind": "dot", "radius": 0.017, "length": 0.056},
	"2x": {"kind": "scope", "radius": 0.014, "length": 0.11, "bell": 0.019, "eye": 0.017},
	"4x": {"kind": "scope", "radius": 0.015, "length": 0.15, "bell": 0.024, "eye": 0.019},
	"8x": {"kind": "scope", "radius": 0.016, "length": 0.21, "bell": 0.03, "eye": 0.02},
}


static func optic_kind(optic: String) -> String:
	return str(OPTIC_SPECS.get(optic, {}).get("kind", ""))


## Height (metres, in viewmodel holder space) of the optic's axis above the
## gun's centre line.
static func optic_center_y(id: String, optic: String) -> float:
	var s := view_scale(id)
	var top := float(model(id).get("sight_y", 0.08)) * s
	var spec: Dictionary = OPTIC_SPECS.get(optic, {})
	var r := maxf(float(spec.get("radius", 0.016)), float(spec.get("bell", 0.0)))
	return top + r + 0.006


static var _optic_mats: Dictionary = {}


static func _omat(key: String) -> Material:
	if _optic_mats.has(key):
		return _optic_mats[key]
	var m := StandardMaterial3D.new()
	match key:
		"body":
			m.albedo_color = Color(0.075, 0.078, 0.085)
			m.roughness = 0.42
			m.metallic = 0.45
			m.rim_enabled = true
			m.rim = 0.3
			# Tubes are seen from the inside when aiming through them.
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"mount":
			m.albedo_color = Color(0.11, 0.115, 0.12)
			m.roughness = 0.5
			m.metallic = 0.5
		"knurl":
			m.albedo_color = Color(0.16, 0.16, 0.17)
			m.roughness = 0.75
		"glass":
			m.albedo_color = Color(0.45, 0.6, 0.7, 0.07)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.05
			m.metallic = 0.6
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"coat":
			# Anti-reflective coating sheen on the objective.
			m.albedo_color = Color(0.15, 0.32, 0.25, 0.10)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"dot":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_texture = _dot_texture()
			m.albedo_color = Color(1.0, 0.12, 0.08, 1.0)
			m.render_priority = 10
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.disable_fog = true
	_optic_mats[key] = m
	return m


static var _dot_tex: Texture2D


static func _dot_texture() -> Texture2D:
	if _dot_tex != null:
		return _dot_tex
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var r := Vector2(x - n * 0.5 + 0.5, y - n * 0.5 + 0.5).length() / (n * 0.5)
			# Hard bright core, soft bloom around it like a real LED reticle.
			var core := clampf(1.0 - r / 0.16, 0.0, 1.0)
			var glow := pow(clampf(1.0 - r, 0.0, 1.0), 3.0) * 0.55
			var a := clampf(core * 1.5 + glow, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 0.8 + core * 0.2, 0.75 + core * 0.25, a))
	_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex


static func _cyl_mesh(r_top: float, r_bot: float, h: float, seg := 20) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


static func _opart(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.layers = 2
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Builds an optic in metres. Its axis is local +Y=0 along -Z (forward); the
## base of the mount sits at y = -(axis height above rail).
static func build_optic(optic: String, axis_above_rail: float) -> Node3D:
	var spec: Dictionary = OPTIC_SPECS.get(optic, {})
	var root := Node3D.new()
	root.name = "Optic"
	var along := Vector3(PI * 0.5, 0, 0)  # cylinders point along Z
	if str(spec.get("kind", "")) == "dot":
		var r := float(spec["radius"])
		var l := float(spec["length"])
		# Tube housing: outer shell + a slightly larger front hood.
		_opart(root, _cyl_mesh(r, r, l, 24), _omat("body"), Vector3.ZERO, along)
		_opart(root, _cyl_mesh(r * 1.12, r * 1.06, 0.012, 24), _omat("body"), Vector3(0, 0, -l * 0.5 + 0.004), along)
		# The inside of the tube must read as hollow: dark inner sleeve.
		var inner := _opart(root, _cyl_mesh(r * 0.86, r * 0.86, l * 1.01, 24), _omat("body"), Vector3.ZERO, along)
		(inner.mesh as CylinderMesh).cap_top = false
		(inner.mesh as CylinderMesh).cap_bottom = false
		(root.get_child(0).mesh as CylinderMesh).cap_top = false
		(root.get_child(0).mesh as CylinderMesh).cap_bottom = false
		(root.get_child(1).mesh as CylinderMesh).cap_top = false
		(root.get_child(1).mesh as CylinderMesh).cap_bottom = false
		# Lenses.
		_opart(root, _cyl_mesh(r * 0.86, r * 0.86, 0.001, 24), _omat("glass"), Vector3(0, 0, -l * 0.5 + 0.006), along)
		_opart(root, _cyl_mesh(r * 0.86, r * 0.86, 0.001, 24), _omat("coat"), Vector3(0, 0, -l * 0.5 + 0.0065), along)
		# Brightness dial on the right, windage cap on top.
		_opart(root, _cyl_mesh(r * 0.55, r * 0.55, 0.008, 16), _omat("knurl"), Vector3(r + 0.003, 0.0, 0.006), Vector3(0, 0, PI * 0.5))
		_opart(root, _cyl_mesh(r * 0.38, r * 0.38, 0.006, 12), _omat("knurl"), Vector3(0, r + 0.002, 0.004))
		# Mount down to the rail.
		var mount_h := maxf(0.006, axis_above_rail - r + 0.002)
		var mb := BoxMesh.new()
		mb.size = Vector3(r * 1.3, mount_h, l * 0.7)
		_opart(root, mb, _omat("mount"), Vector3(0, -r - mount_h * 0.5 + 0.002, 0.004))
		var clamp_box := BoxMesh.new()
		clamp_box.size = Vector3(r * 2.4, 0.007, l * 0.5)
		_opart(root, clamp_box, _omat("mount"), Vector3(0, -axis_above_rail + 0.0035, 0.004))
		# The reticle: an LED dot projected on the front lens.
		var dot := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.006, 0.006)
		dot.mesh = q
		dot.material_override = _omat("dot")
		dot.position = Vector3(0, 0, -l * 0.5 + 0.0068)
		dot.rotation.y = PI
		dot.layers = 2
		dot.name = "Reticle"
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(dot)
	else:
		var r := float(spec.get("radius", 0.015))
		var l := float(spec.get("length", 0.15))
		var bell := float(spec.get("bell", 0.022))
		var eye := float(spec.get("eye", 0.018))
		# Main tube.
		_opart(root, _cyl_mesh(r, r, l * 0.62, 24), _omat("body"), Vector3(0, 0, 0.0), along)
		# Objective bell (front) with taper, eyepiece (rear) with taper.
		_opart(root, _cyl_mesh(r, bell, l * 0.16, 24), _omat("body"), Vector3(0, 0, -l * 0.39), along)
		_opart(root, _cyl_mesh(bell, bell, l * 0.1, 24), _omat("body"), Vector3(0, 0, -l * 0.52), along)
		_opart(root, _cyl_mesh(eye, r, l * 0.1, 24), _omat("body"), Vector3(0, 0, l * 0.36), along)
		_opart(root, _cyl_mesh(eye, eye, l * 0.08, 24), _omat("knurl"), Vector3(0, 0, l * 0.45), along)
		# Lenses.
		_opart(root, _cyl_mesh(bell * 0.9, bell * 0.9, 0.001, 24), _omat("coat"), Vector3(0, 0, -l * 0.57), along)
		_opart(root, _cyl_mesh(eye * 0.85, eye * 0.85, 0.001, 24), _omat("glass"), Vector3(0, 0, l * 0.49), along)
		# Turrets: elevation on top, windage on the right, both knurled.
		_opart(root, _cyl_mesh(r * 0.7, r * 0.7, 0.014, 16), _omat("knurl"), Vector3(0, r + 0.006, -0.004))
		_opart(root, _cyl_mesh(r * 0.7, r * 0.7, 0.014, 16), _omat("knurl"), Vector3(r + 0.006, 0, -0.004), Vector3(0, 0, PI * 0.5))
		_opart(root, _cyl_mesh(r * 1.05, r * 1.05, 0.014, 16), _omat("body"), Vector3(0, 0, -0.004), along)
		# Two scope rings down to the rail.
		for zr in [-l * 0.2, l * 0.2]:
			var ring := _opart(root, _cyl_mesh(r * 1.18, r * 1.18, 0.012, 20), _omat("mount"), Vector3(0, 0, zr), along)
			var ring_h := maxf(0.006, axis_above_rail - r)
			var leg := BoxMesh.new()
			leg.size = Vector3(r * 1.2, ring_h, 0.012)
			_opart(root, leg, _omat("mount"), Vector3(0, -r - ring_h * 0.5 + 0.002, zr))
			var base := BoxMesh.new()
			base.size = Vector3(r * 2.4, 0.006, 0.018)
			_opart(root, base, _omat("mount"), Vector3(0, -axis_above_rail + 0.003, zr))
	return root


# --------------------------------------------------------------- models ----
## Loads, normalises and splits a gun model. Cached per id:
##   body: ArrayMesh (normalised, muzzle at -Z, 1 m long)
##   mag: ArrayMesh or null, verts relative to mag_center
##   mag_center: Vector3, sight_y: float
static func model(id: String) -> Dictionary:
	if _models.has(id):
		return _models[id]
	var d := def(id)
	var res = load(str(d.get("model", "")))
	var parts: Array = []  # [Mesh, Transform3D]
	if res is PackedScene:
		var inst: Node = (res as PackedScene).instantiate()
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var m: MeshInstance3D = mi
			if m.mesh != null:
				parts.append([m.mesh, _rel_xf(m, inst), m])
		inst.free()
	elif res is Mesh:
		parts.append([res, Transform3D.IDENTITY, null])
	if parts.is_empty():
		_models[id] = {}
		return {}

	# Bounds in source space.
	var aabb := AABB()
	var first := true
	for p in parts:
		var a: AABB = (p[1] as Transform3D) * (p[0] as Mesh).get_aabb()
		aabb = a if first else aabb.merge(a)
		first = false
	var length := maxf(0.001, aabb.size.x)
	var center := aabb.get_center()
	# +X (muzzle) -> -Z, scaled to 1 m, centred.
	var nb := Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3.ONE / length)
	var norm := Transform3D(nb, -(nb * center))

	# Gather triangles in normalised space.
	var tris: Array = []  # per surface: {mat, verts: PackedVector3Array, norms: PackedVector3Array}
	var all_y_min := 1e9
	var all_y_max := -1e9
	for p in parts:
		var mesh: Mesh = p[0]
		var xf: Transform3D = norm * (p[1] as Transform3D)
		var nbasis := xf.basis.inverse().transposed()
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var n = arrays[Mesh.ARRAY_NORMAL]
			var idx = arrays[Mesh.ARRAY_INDEX]
			var mat: Material = null
			if p[2] != null:
				mat = (p[2] as MeshInstance3D).get_active_material(s)
			if mat == null:
				mat = mesh.surface_get_material(s)
			var tv := PackedVector3Array()
			var tn := PackedVector3Array()
			var count: int = idx.size() if idx != null and idx.size() > 0 else v.size()
			for i in count:
				var vi: int = idx[i] if idx != null and idx.size() > 0 else i
				var wv := xf * v[vi]
				tv.append(wv)
				var nn := Vector3.UP
				if n != null and n.size() > vi:
					nn = (nbasis * n[vi]).normalized()
				tn.append(nn)
				all_y_min = minf(all_y_min, wv.y)
				all_y_max = maxf(all_y_max, wv.y)
			tris.append({"mat": mat, "v": tv, "n": tn})

	# Find the magazine: the lowest-hanging cluster along the barrel axis,
	# front-most for rifles, rear-most for bullpups, the grip for pistols.
	var h := all_y_max - all_y_min
	var low_cut := all_y_min + h * 0.42
	var mag_mode := str(d.get("mag_at", "front"))
	var box := AABB()
	var has_mag := false
	if mag_mode != "none":
		var bins := {}
		for t in tris:
			for wv in (t["v"] as PackedVector3Array):
				if wv.y < low_cut:
					bins[int(floor(wv.z / 0.02))] = true
		var keys: Array = bins.keys()
		keys.sort()
		var groups: Array = []
		for k in keys:
			if groups.is_empty() or int(k) - int(groups[-1][-1]) > 2:
				groups.append([k])
			else:
				groups[-1].append(k)
		# Ignore slivers (sling swivels, triggers): need some length.
		groups = groups.filter(func(g): return g.size() >= 2)
		if not groups.is_empty():
			var g: Array = groups[0]
			if mag_mode == "rear":
				g = groups[-1]
			elif mag_mode == "grip":
				g = groups[-1]
			var z0 := float(g[0]) * 0.02 - 0.004
			var z1 := (float(g[-1]) + 1.0) * 0.02 + 0.004
			box = AABB(Vector3(-1, all_y_min - 0.01, z0), Vector3(2, low_cut - all_y_min + 0.01, z1 - z0))
			has_mag = true

	var body := ArrayMesh.new()
	var mag := ArrayMesh.new()
	var mag_center := box.get_center() if has_mag else Vector3.ZERO
	var sight_y := -1e9
	var front_y := -1e9
	for t in tris:
		var v: PackedVector3Array = t["v"]
		var n: PackedVector3Array = t["n"]
		var bv := PackedVector3Array()
		var bn := PackedVector3Array()
		var mv := PackedVector3Array()
		var mn := PackedVector3Array()
		for i in range(0, v.size() - 2, 3):
			var c := (v[i] + v[i + 1] + v[i + 2]) / 3.0
			if has_mag and box.has_point(c):
				for j in 3:
					mv.append(v[i + j] - mag_center)
					mn.append(n[i + j])
			else:
				for j in 3:
					bv.append(v[i + j])
					bn.append(n[i + j])
					# Sight line: highest point over the rear two thirds of the
					# gun, ignoring a tall scope at the very top (handled by
					# the scope overlay anyway).
					if v[i + j].z > -0.2:
						sight_y = maxf(sight_y, v[i + j].y)
					elif v[i + j].z < -0.3:
						front_y = maxf(front_y, v[i + j].y)
		_add_surface(body, bv, bn, t["mat"])
		_add_surface(mag, mv, mn, t["mat"])
	var hands := _hand_points(tris, low_cut, all_y_min, mag_mode, mag_center if has_mag else Vector3.INF)
	var out := {
		"grip": hands[0],
		"fore": hands[1],
		"body": body,
		"mag": mag if has_mag and mag.get_surface_count() > 0 else null,
		"mag_center": mag_center,
		"sight_y": sight_y if sight_y > -1e8 else all_y_max,
		"front_y": front_y if front_y > -1e8 else all_y_max,
	}
	_models[id] = out
	return out


## Where the hands go, in the normalised model (1 m long, muzzle at -Z):
## [pistol grip, underside of the handguard]. Found from what hangs below
## the receiver: the magazine, the grip, a pump.
static func _hand_points(tris: Array, low_cut: float, y_min: float, mag_mode: String, mag_c: Vector3) -> Array:
	var bins := {}
	for t in tris:
		for wv in (t["v"] as PackedVector3Array):
			if wv.y < low_cut:
				var k := int(floor(wv.z / 0.02))
				bins[k] = minf(float(bins.get(k, 1e9)), wv.y)
	var keys: Array = bins.keys()
	keys.sort()
	var groups: Array = []
	for k in keys:
		if groups.is_empty() or int(k) - int(groups[-1][-1]) > 2:
			groups.append([k])
		else:
			groups[-1].append(k)
	groups = groups.filter(func(g): return g.size() >= 2)
	var gz := func(g: Array) -> float: return (float(g[0]) + float(g[-1]) + 1.0) * 0.01
	var gl := func(g: Array) -> float:
		var lo := 1e9
		for k in g:
			lo = minf(lo, float(bins[k]))
		return lo
	var grip_g: Array = []
	match mag_mode:
		"grip":
			if not groups.is_empty():
				grip_g = groups[-1]
		"rear":
			# Bullpup: the grip is the drop in front of the magazine.
			for g in groups:
				if gz.call(g) < mag_c.z - 0.06:
					grip_g = g
		"front":
			for g in groups:
				if mag_c != Vector3.INF and gz.call(g) > mag_c.z + 0.05 and gz.call(g) < 0.4:
					grip_g = g
					break
		_:
			var best := 1e9
			for g in groups:
				var z: float = gz.call(g)
				if z > -0.08 and z < 0.4 and absf(z - 0.14) < best:
					best = absf(z - 0.14)
					grip_g = g
	var grip := Vector3(0, low_cut - 0.06, 0.15)
	if not grip_g.is_empty():
		var bottom: float = gl.call(grip_g)
		grip = Vector3(0, low_cut - (low_cut - bottom) * 0.42, gz.call(grip_g))
	# Support hand: under the handguard, a hand's width ahead of the
	# magazine (or of the grip), on its underside.
	var fz := grip.z - 0.32
	if mag_mode == "front" and mag_c != Vector3.INF:
		fz = mag_c.z - 0.17
	elif mag_mode == "none" and groups.size() > 1 and gz.call(groups[0]) < grip.z - 0.15:
		# A pump or a fore-end hanging under the barrel.
		fz = gz.call(groups[0])
	fz = clampf(fz, -0.42, grip.z - 0.14)
	var under := low_cut + 0.04
	for t in tris:
		for wv in (t["v"] as PackedVector3Array):
			if absf(wv.z - fz) < 0.03 and wv.y < under:
				under = minf(under, wv.y) if wv.y > low_cut - 0.08 else under
	return [grip, Vector3(0, under, fz)]


static func _add_surface(m: ArrayMesh, v: PackedVector3Array, n: PackedVector3Array, mat: Material) -> void:
	if v.size() < 3:
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.surface_set_material(m.get_surface_count() - 1, _gun_material(mat))


static var _mat_cache: Dictionary = {}


## Takes the pack's flat colours and makes them read as gun materials:
## dark parts become satin gunmetal, warm colours stay matte (wood, polymer).
## Finishes by part name in the gun kit: [colour, metallic, roughness].
const GUN_FINISH := {
	"wood": [Color(0.46, 0.25, 0.12), 0.0, 0.55],
	"darkwood": [Color(0.31, 0.16, 0.08), 0.0, 0.6],
	"black": [Color(0.075, 0.078, 0.085), 0.25, 0.55],
	"grey": [Color(0.13, 0.135, 0.14), 0.1, 0.62],
	"darkmetal": [Color(0.11, 0.115, 0.125), 0.7, 0.36],
	"metal": [Color(0.17, 0.175, 0.185), 0.8, 0.3],
	"lightmetal": [Color(0.3, 0.31, 0.32), 0.85, 0.26],
	"main": [Color(0.5, 0.42, 0.3), 0.05, 0.62],
	"mainlight": [Color(0.58, 0.5, 0.37), 0.05, 0.62],
	"maindark": [Color(0.085, 0.09, 0.095), 0.2, 0.55],
	"glass": [Color(0.04, 0.09, 0.16), 0.9, 0.05],
}


static func _gun_material(src: Material) -> Material:
	var key := src.get_instance_id() if src != null else 0
	if _mat_cache.has(key):
		return _mat_cache[key]
	var col := Color(0.2, 0.2, 0.22)
	var name := ""
	if src is BaseMaterial3D:
		col = (src as BaseMaterial3D).albedo_color
		name = src.resource_name.to_lower()
	var m := StandardMaterial3D.new()
	if GUN_FINISH.has(name):
		# A proper finish for each part: walnut, blued and parkerised steel,
		# polymer, a tan furniture set, glass.
		var f: Array = GUN_FINISH[name]
		m.albedo_color = f[0]
		m.metallic = f[1]
		m.roughness = f[2]
		m.metallic_specular = 0.6
	else:
		m.albedo_color = col
		var lum := col.r * 0.3 + col.g * 0.59 + col.b * 0.11
		var warm := col.r > col.b * 1.25
		if lum < 0.25 and not warm:
			m.albedo_color = col.lerp(Color(0.2, 0.205, 0.21), 0.45)
			m.metallic = 0.35
			m.roughness = 0.38
		elif warm:
			m.roughness = 0.75
		else:
			m.roughness = 0.55
			m.metallic = 0.15
	m.rim_enabled = true
	m.rim = 0.18
	m.rim_tint = 0.4
	# Keep the gun readable in deep shade (first person sits right in it).
	m.emission_enabled = true
	m.emission = m.albedo_color.lightened(0.25)
	m.emission_energy_multiplier = 0.05
	_mat_cache[key] = m
	return m


static func _rel_xf(n: Node, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c := n
	while c != null and c != root:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t


## First-person model: body plus a separate magazine node (the player keeps a
## reference to it to animate reloads). Returned node is 1 m long.
static func build_view_model(id: String) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Gun_" + id
	var m := model(id)
	if m.is_empty():
		return holder
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = m["body"]
	body.layers = 2
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(body)
	if m["mag"] != null:
		var mag := MeshInstance3D.new()
		mag.name = "Mag"
		mag.mesh = m["mag"]
		mag.position = m["mag_center"]
		mag.layers = 2
		mag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mag)
	return holder


## World model for floor loot and bots.
static func make_drop_node(id: String) -> Node3D:
	var root := Node3D.new()
	var m := model(id)
	if m.is_empty():
		return root
	var body := MeshInstance3D.new()
	body.mesh = m["body"]
	root.add_child(body)
	if m["mag"] != null:
		var mag := MeshInstance3D.new()
		mag.mesh = m["mag"]
		mag.position = m["mag_center"]
		root.add_child(mag)
	return root


## Soft star-shaped muzzle flash, generated once.
static func flash_texture() -> Texture2D:
	if _flash_tex != null:
		return _flash_tex
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var p := Vector2(x - n * 0.5 + 0.5, y - n * 0.5 + 0.5) / (n * 0.5)
			var r := p.length()
			var a := atan2(p.y, p.x)
			var star := pow(absf(cos(a * 3.0)), 6.0) * 0.55 + pow(absf(cos(a * 2.0 + 0.4)), 10.0) * 0.35
			var v := clampf(1.0 - r / (0.32 + star * 0.68), 0.0, 1.0)
			v = v * v
			var core := clampf(1.0 - r / 0.22, 0.0, 1.0)
			var c := Color(1.0, 0.72 + core * 0.28, 0.35 + core * 0.6, clampf(v + core, 0.0, 1.0))
			img.set_pixel(x, y, c)
	_flash_tex = ImageTexture.create_from_image(img)
	return _flash_tex
