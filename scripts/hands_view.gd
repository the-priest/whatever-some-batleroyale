extends Node3D
class_name HandsView

## First-person hands: two gloved hands and whatever they hold, animated in
## camera space. The player passes the action and its normalised progress
## every frame; sounds are timed to the motion and fire once per use.
##
##   bandage  tear a strip, wrap three turns round the forearm, press it flat
##   med      unzip the kit, take the syringe, cap off, inject into the thigh,
##            toss it, zip the kit shut
##   energy   crack the tab, tip it back in three gulps, crush the can
##   grenade  pull the pin, wind up, throw (the spoon flies off)
##   swim     breaststroke; t is the stroke phase and loops
##   vault    both palms planted on the ledge, pushing up and over

signal sound(name: String, db: float)
signal jolt(amount: float)

const SKIN := Color(0.87, 0.66, 0.52)
const GLOVE := Color(0.21, 0.15, 0.11)
const SLEEVE := Color(0.30, 0.35, 0.24)
const GAUZE := Color(0.96, 0.94, 0.88)
const KIT_W := 0.20
const KIT_D := 0.13
const KIT_HB := 0.05
const KIT_HL := 0.028
const WRAP_RINGS := 8
const WRAP_Z0 := 0.035
const WRAP_Z1 := 0.165

var cam_pitch := 0.0
var item := ""
var _t := 0.0
var _show := 0.0
var _fired: Dictionary = {}
var _mats: Dictionary = {}

var arm_l: Node3D
var arm_r: Node3D
var fore_l: Node3D
var fore_r: Node3D
var _fingers: Dictionary = {}
var _thumbs: Dictionary = {}

var roll: Node3D
var roll_mesh: Node3D
var wraps: Array[MeshInstance3D] = []
var strip: MeshInstance3D
var strip_mesh: ImmediateMesh

var kit: Node3D
var kit_lid: Node3D
var syringe: Node3D
var plunger: Node3D
var fluid: MeshInstance3D
var syr_cap: Node3D

var can: Node3D
var can_tab: Node3D
var can_body: Node3D
var can_hole: MeshInstance3D

var grenade: Node3D
var g_ring: Node3D
var g_spoon: Node3D

var _drops: Array[MeshInstance3D] = []
## Holding a gun (when no item is in use): {xf, grip, fore, scale, hand, pistol}.
var _gun: Dictionary = {}
## Reload in progress (see player._hand_reload), {} when not reloading.
var reload: Dictionary = {}
var _debris: Dictionary = {}


func _ready() -> void:
	arm_l = _arm(true)
	arm_r = _arm(false)
	_build_bandage()
	_build_kit()
	_build_syringe()
	_build_can()
	_build_grenade()
	for i in 8:
		var d := _mi(self, _sphere(0.004), _mat("drop", Color(0.75, 1.0, 0.5, 0.7), 0.1, 0.0, 0.6))
		d.visible = false
		_drops.append(d)
	visible = false


# ----------------------------------------------------------------- building --
func _mat(key: String, c: Color, rough := 0.8, metal := 0.0, glow := 0.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = Color(c.r, c.g, c.b)
		m.emission_energy_multiplier = glow
	_mats[key] = m
	return m


func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation = rot
	m.layers = 2
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m


func _node(parent: Node3D, pos := Vector3.ZERO, rot := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation = rot
	parent.add_child(n)
	return n


static func _cyl(r0: float, r1: float, h: float, seg := 16, caps := true) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r0
	c.bottom_radius = r1
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	c.cap_top = caps
	c.cap_bottom = caps
	return c


static func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(h, r * 2.0)
	c.radial_segments = 10
	c.rings = 2
	return c


## A wrist frame: fingers point down -Z, the back of the hand faces +Y, the
## forearm hangs off a separate pivot so the wrist can bend toward the elbow.
## The thumb sits on +X for the left hand and -X for the right.
func _arm(left: bool) -> Node3D:
	var root := _node(self)
	var glove := _mat("glove", GLOVE, 0.55)
	var skin := _mat("skin", SKIN, 0.62)
	var sleeve := _mat("sleeve", SLEEVE, 0.95)
	var cuff_m := _mat("cuff", GLOVE.darkened(0.25), 0.6)
	var fore := _node(root)
	# Bare forearm with the sleeve rolled up past the middle.
	var bare := _mi(fore, _cyl(0.041, 0.034, 0.2, 16), skin, Vector3(0, 0, 0.1), Vector3(PI * 0.5, 0, 0))
	root.set_meta("bare", bare)
	var roll_up := TorusMesh.new()
	roll_up.inner_radius = 0.036
	roll_up.outer_radius = 0.056
	roll_up.rings = 16
	roll_up.ring_segments = 8
	_mi(fore, roll_up, _mat("sleeve_roll", SLEEVE.darkened(0.12), 0.95), Vector3(0, 0, 0.205), Vector3(PI * 0.5, 0, 0))
	_mi(fore, _cyl(0.054, 0.046, 0.26, 16), sleeve, Vector3(0, 0, 0.34), Vector3(PI * 0.5, 0, 0))
	# Glove cuff and palm.
	_mi(root, _cyl(0.04, 0.043, 0.04, 16), cuff_m, Vector3(0, -0.002, 0.008), Vector3(PI * 0.5, 0, 0))
	var palm := _mi(root, _sphere(0.046), glove, Vector3(0, -0.004, -0.044))
	palm.scale = Vector3(0.94, 0.44, 1.02)
	var s := 1.0 if left else -1.0
	var fingers: Array = []
	var lens := [0.033, 0.036, 0.033, 0.026]
	var zs := [-0.082, -0.086, -0.083, -0.074]
	for i in 4:
		var x := s * (0.026 - 0.0175 * float(i))
		var l: float = lens[i]
		var k1 := _node(root, Vector3(x, -0.002, zs[i]))
		_mi(k1, _capsule(0.0105, l + 0.02), glove, Vector3(0, 0, -l * 0.5), Vector3(-PI * 0.5, 0, 0))
		var k2 := _node(k1, Vector3(0, 0, -l))
		_mi(k2, _capsule(0.0098, l * 0.8 + 0.018), glove, Vector3(0, 0, -l * 0.4), Vector3(-PI * 0.5, 0, 0))
		fingers.append([k1, k2])
	var t1 := _node(root, Vector3(s * 0.03, -0.012, -0.026))
	_mi(t1, _capsule(0.012, 0.05), glove, Vector3(0, 0, -0.016), Vector3(-PI * 0.5, 0, 0))
	var t2 := _node(t1, Vector3(0, 0, -0.032))
	_mi(t2, _capsule(0.0105, 0.04), glove, Vector3(0, 0, -0.012), Vector3(-PI * 0.5, 0, 0))
	_fingers[root] = fingers
	_thumbs[root] = [t1, t2, s]
	root.set_meta("fore", fore)
	if left:
		fore_l = fore
	else:
		fore_r = fore
	_curl(root, 0.35)
	return root


## 0 = flat open hand, 1 = closed round a can, 1.6 = tight fist.
func _curl(arm: Node3D, amount: float, thumb_in := -1.0) -> void:
	var f: Array = _fingers[arm]
	for i in f.size():
		var spread := (float(i) - 1.5) * 0.05 * (1.0 - clampf(amount, 0.0, 1.0))
		var seg: Array = f[i]
		(seg[0] as Node3D).rotation = Vector3(-0.12 - amount * 0.85 - float(i) * 0.04 * amount, spread, 0)
		(seg[1] as Node3D).rotation = Vector3(-0.1 - amount * 0.95, 0, 0)
	var th: Array = _thumbs[arm]
	var s: float = th[2]
	var ti := amount if thumb_in < 0.0 else thumb_in
	(th[0] as Node3D).rotation = Vector3(-0.35 - ti * 0.35, -s * (0.85 - ti * 0.5), s * 0.5)
	(th[1] as Node3D).rotation = Vector3(-0.15 - ti * 0.55, 0, 0)


func _build_bandage() -> void:
	var gauze := _mat("gauze", GAUZE, 0.95)
	roll = _node(self)
	roll_mesh = _node(roll)
	_mi(roll_mesh, _cyl(0.03, 0.03, 0.062, 18), gauze)
	_mi(roll_mesh, _cyl(0.0095, 0.0095, 0.0625, 10), _mat("core", Color(0.62, 0.52, 0.38), 0.9))
	# Turns already on the arm: tubes revealed one by one as the wrap passes.
	for i in WRAP_RINGS:
		var z := lerpf(WRAP_Z0, WRAP_Z1, (float(i) + 0.5) / float(WRAP_RINGS))
		var r := _fore_radius(z) + 0.004 + float(i % 2) * 0.001
		var w := _mi(fore_l, _cyl(r, r - 0.0015, 0.021, 18, false), gauze, Vector3(0, 0, z), Vector3(PI * 0.5 + (0.16 if i % 2 == 0 else -0.1), 0.0, 0.0))
		w.visible = false
		wraps.append(w)
	strip_mesh = ImmediateMesh.new()
	var sm := gauze.duplicate() as StandardMaterial3D
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	strip = _mi(self, strip_mesh, sm)
	strip.visible = false


static func _fore_radius(z: float) -> float:
	return lerpf(0.034, 0.041, clampf(z / 0.2, 0.0, 1.0))


func _build_kit() -> void:
	var shell := _mat("kit_shell", Color(0.93, 0.92, 0.89), 0.42)
	var red := _mat("kit_red", Color(0.86, 0.1, 0.1), 0.5, 0.0, 0.25)
	var lining := _mat("kit_lining", Color(0.5, 0.07, 0.07), 0.9)
	var zip := _mat("kit_zip", Color(0.13, 0.13, 0.14), 0.5, 0.4)
	kit = _node(self)
	# Open-topped base: floor and four walls, lined in red.
	var t := 0.008
	_mi(kit, _box(Vector3(KIT_W, t, KIT_D)), shell, Vector3(0, t * 0.5, 0))
	_mi(kit, _box(Vector3(KIT_W - t * 2.0, 0.002, KIT_D - t * 2.0)), lining, Vector3(0, t + 0.001, 0))
	for sgn in [-1.0, 1.0]:
		_mi(kit, _box(Vector3(KIT_W, KIT_HB, t)), shell, Vector3(0, KIT_HB * 0.5, sgn * (KIT_D - t) * 0.5))
		_mi(kit, _box(Vector3(t, KIT_HB, KIT_D)), shell, Vector3(sgn * (KIT_W - t) * 0.5, KIT_HB * 0.5, 0))
		_mi(kit, _box(Vector3(KIT_W - t * 2.2, KIT_HB - t, 0.002)), lining, Vector3(0, KIT_HB * 0.5 + t * 0.5, sgn * (KIT_D * 0.5 - t - 0.001)))
	# Zip track round the rim and a carry strap on the front.
	for sgn in [-1.0, 1.0]:
		_mi(kit, _box(Vector3(KIT_W + 0.004, 0.006, 0.006)), zip, Vector3(0, KIT_HB - 0.003, sgn * (KIT_D * 0.5 - 0.001)))
		_mi(kit, _box(Vector3(0.006, 0.006, KIT_D + 0.004)), zip, Vector3(sgn * (KIT_W * 0.5 - 0.001), KIT_HB - 0.003, 0))
	_mi(kit, _box(Vector3(0.07, 0.012, 0.01)), zip, Vector3(-0.05, KIT_HB * 0.45, KIT_D * 0.5 + 0.004))
	# Contents along the back: gauze pads, a vial and a tape roll. The syringe
	# lies in front of them.
	_mi(kit, _box(Vector3(0.05, 0.016, 0.045)), _mat("gauze", GAUZE, 0.95), Vector3(-0.058, t + 0.009, -0.03))
	_mi(kit, _box(Vector3(0.05, 0.012, 0.045)), _mat("gauze", GAUZE, 0.95), Vector3(-0.056, t + 0.022, -0.028), Vector3(0, 0.3, 0))
	_mi(kit, _cyl(0.011, 0.011, 0.04, 10), _mat("vial", Color(0.75, 0.42, 0.12, 0.85), 0.15), Vector3(0.008, t + 0.0115, -0.034), Vector3(0, 0, PI * 0.5))
	_mi(kit, _cyl(0.019, 0.019, 0.016, 14), _mat("tape", Color(0.85, 0.82, 0.74), 0.8), Vector3(0.062, t + 0.009, -0.032))
	# Lid hinged on the far edge, red cross on top.
	kit_lid = _node(kit, Vector3(0, KIT_HB, -KIT_D * 0.5))
	_mi(kit_lid, _box(Vector3(KIT_W, KIT_HL, KIT_D)), shell, Vector3(0, KIT_HL * 0.5, KIT_D * 0.5))
	_mi(kit_lid, _box(Vector3(KIT_W - 0.016, 0.002, KIT_D - 0.016)), lining, Vector3(0, -0.0005, KIT_D * 0.5))
	_mi(kit_lid, _box(Vector3(0.075, 0.004, 0.024)), red, Vector3(0, KIT_HL + 0.001, KIT_D * 0.5))
	_mi(kit_lid, _box(Vector3(0.024, 0.004, 0.075)), red, Vector3(0, KIT_HL + 0.001, KIT_D * 0.5))
	# Zip pull on the front-right.
	_mi(kit_lid, _box(Vector3(0.012, 0.004, 0.022)), zip, Vector3(0.06, 0.004, KIT_D + 0.008))


## Syringe along its local Y: needle down at -Y, plunger up at +Y.
func _build_syringe() -> void:
	syringe = _node(self)
	var glass := _mat("syr_glass", Color(0.85, 0.95, 1.0, 0.32), 0.08)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var white := _mat("syr_white", Color(0.95, 0.95, 0.95), 0.4)
	var steel := _mat("steel", Color(0.82, 0.83, 0.86), 0.18, 1.0)
	fluid = _mi(syringe, _cyl(0.0098, 0.0098, 0.08, 12), _mat("syr_fluid", Color(0.35, 1.0, 0.5), 0.2, 0.0, 1.4), Vector3(0, -0.002, 0))
	_mi(syringe, _cyl(0.0115, 0.0115, 0.088, 14), glass)
	# Graduation ring, finger flange, hub and needle.
	_mi(syringe, _cyl(0.0118, 0.0118, 0.004, 14), white, Vector3(0, 0.02, 0))
	_mi(syringe, _box(Vector3(0.044, 0.004, 0.016)), white, Vector3(0, 0.045, 0))
	_mi(syringe, _cyl(0.0115, 0.004, 0.012, 12), white, Vector3(0, -0.05, 0))
	_mi(syringe, _cyl(0.0012, 0.0012, 0.032, 6), steel, Vector3(0, -0.071, 0))
	syr_cap = _node(syringe, Vector3(0, -0.07, 0))
	_mi(syr_cap, _cyl(0.0055, 0.0045, 0.04, 10), _mat("syr_cap", Color(1.0, 0.45, 0.1), 0.5))
	plunger = _node(syringe, Vector3(0, 0.0, 0))
	_mi(plunger, _cyl(0.004, 0.004, 0.066, 8), white, Vector3(0, 0.063, 0))
	_mi(plunger, _cyl(0.013, 0.013, 0.004, 14), white, Vector3(0, 0.096, 0))
	_mi(plunger, _cyl(0.0105, 0.0105, 0.006, 12), _mat("syr_rubber", Color(0.12, 0.12, 0.13), 0.7), Vector3(0, 0.032, 0))


## Can along its local Y, top up.
func _build_can() -> void:
	can = _node(self)
	can_body = _node(can)
	var green := _mat("can_green", Color(0.07, 0.5, 0.27), 0.3, 0.55)
	var band := _mat("can_band", Color(1.0, 0.8, 0.1), 0.35, 0.4, 0.15)
	var alu := _mat("alu", Color(0.8, 0.81, 0.83), 0.25, 0.9)
	_mi(can_body, _cyl(0.033, 0.033, 0.108, 20), green)
	_mi(can_body, _cyl(0.0335, 0.0335, 0.03, 20, false), band, Vector3(0, 0.005, 0))
	# Lightning-bolt flash on the band (two skewed slabs).
	_mi(can_body, _box(Vector3(0.006, 0.026, 0.004)), _mat("can_bolt", Color(0.95, 0.2, 0.1), 0.4), Vector3(0.0, 0.006, 0.0335), Vector3(0, 0, 0.45))
	_mi(can_body, _cyl(0.029, 0.033, 0.008, 20), alu, Vector3(0, 0.058, 0))
	_mi(can_body, _cyl(0.033, 0.028, 0.008, 20), alu, Vector3(0, -0.058, 0))
	_mi(can_body, _cyl(0.031, 0.031, 0.002, 20), alu, Vector3(0, 0.0625, 0))
	can_tab = _node(can_body, Vector3(0, 0.064, 0.004))
	_mi(can_tab, _box(Vector3(0.012, 0.0015, 0.022)), alu, Vector3(0, 0, 0.008))
	# Drinking hole, shown once the tab is pulled.
	can_hole = _mi(can_body, _box(Vector3(0.013, 0.0012, 0.016)), _mat("can_hole", Color(0.04, 0.05, 0.04), 0.6), Vector3(0, 0.0632, -0.01))


## Frag along its local Y, fuse up; ring and spoon on the sides.
func _build_grenade() -> void:
	grenade = _node(self)
	var olive := _mat("gren_body", Color(0.27, 0.32, 0.2), 0.55, 0.15)
	var steel := _mat("steel", Color(0.82, 0.83, 0.86), 0.18, 1.0)
	var dark := _mat("gren_fuse", Color(0.2, 0.21, 0.2), 0.4, 0.7)
	var body := _mi(grenade, _sphere(0.03), olive)
	body.scale = Vector3(1.0, 1.2, 1.0)
	# Cast segment grooves.
	for i in 3:
		var ring := TorusMesh.new()
		ring.inner_radius = 0.026 - absf(float(i) - 1.0) * 0.006
		ring.outer_radius = ring.inner_radius + 0.006
		ring.rings = 16
		ring.ring_segments = 6
		_mi(grenade, ring, _mat("gren_groove", Color(0.2, 0.24, 0.15), 0.6), Vector3(0, (float(i) - 1.0) * 0.016, 0))
	_mi(grenade, _cyl(0.011, 0.013, 0.02, 12), dark, Vector3(0, 0.041, 0))
	g_spoon = _node(grenade, Vector3(0.014, 0.046, 0))
	_mi(g_spoon, _box(Vector3(0.006, 0.055, 0.013)), dark, Vector3(0.012, -0.022, 0), Vector3(0, 0, -0.32))
	g_ring = _node(grenade, Vector3(-0.016, 0.044, 0))
	var tr := TorusMesh.new()
	tr.inner_radius = 0.008
	tr.outer_radius = 0.0115
	tr.rings = 14
	tr.ring_segments = 6
	_mi(g_ring, tr, steel, Vector3(-0.012, 0, 0), Vector3(0, 0, PI * 0.5))
	_mi(g_ring, _cyl(0.0015, 0.0015, 0.03, 6), steel, Vector3(0.006, 0, 0), Vector3(0, 0, PI * 0.5))


# -------------------------------------------------------------------- frame --
func reset() -> void:
	_fired.clear()
	_debris.clear()
	for w in wraps:
		w.visible = false
	for d in _drops:
		d.visible = false
	syringe.scale = Vector3.ONE
	if syr_cap.get_parent() != syringe:
		syr_cap.get_parent().remove_child(syr_cap)
		syringe.add_child(syr_cap)
	syr_cap.visible = true
	syr_cap.position = Vector3(0, -0.07, 0)
	syr_cap.rotation = Vector3.ZERO
	syringe.visible = true
	can_body.scale = Vector3.ONE
	can_body.rotation = Vector3.ZERO
	can.visible = true
	can_tab.rotation = Vector3.ZERO
	roll.visible = true
	for n in [g_ring, g_spoon]:
		var nd := n as Node3D
		if nd.get_parent() != grenade:
			nd.get_parent().remove_child(nd)
			grenade.add_child(nd)
		nd.visible = true
	g_ring.transform = Transform3D(Basis.IDENTITY, Vector3(-0.016, 0.044, 0))
	g_spoon.transform = Transform3D(Basis.IDENTITY, Vector3(0.014, 0.046, 0))
	grenade.visible = true


## active: an item is in use right now; t: its progress 0..1.
func update(active: bool, p_item: String, t: float, delta: float) -> void:
	if active and (p_item != item or (t < _t - 0.2) or _show <= 0.0):
		item = p_item
		reset()
	if active:
		_t = t
	var t_in: float = {"vault": 0.06, "grenade": 0.12, "swim": 0.3}.get(item, 0.2)
	_show = move_toward(_show, 1.0 if active else 0.0, delta / (t_in if active else 0.17))
	if _show <= 0.0:
		cam_pitch = lerpf(cam_pitch, 0.0, clampf(delta * 10.0, 0.0, 1.0))
		item = ""
		if not _gun.is_empty():
			visible = true
			_pose_gun()
			return
		visible = false
		return
	visible = true
	arm_l.visible = true
	arm_r.visible = true
	_sleeves(false)
	var e := _show * _show * (3.0 - 2.0 * _show)
	position = Vector3(0.0, -(1.0 - e) * 0.32, (1.0 - e) * 0.06)
	rotation = Vector3(-(1.0 - e) * 0.55, 0.0, 0.0)
	roll.visible = item == "bandage"
	strip.visible = false
	kit.visible = item == "med"
	syringe.visible = item == "med" and not _debris.has("syr_gone")
	can.visible = item == "energy" and not _debris.has("can_gone")
	grenade.visible = item == "grenade" and _t < 0.6
	for w in wraps:
		w.visible = w.visible and item == "bandage"
	var pitch := 0.0
	match item:
		"bandage":
			pitch = _bandage(_t)
		"med":
			pitch = _med(_t)
		"energy":
			pitch = _energy(_t)
		"grenade":
			pitch = _grenade(_t)
		"swim":
			pitch = _swim(_t)
		"vault":
			pitch = _vault(_t)
	cam_pitch = lerpf(cam_pitch, pitch * e, clampf(delta * 9.0, 0.0, 1.0))
	_tick_debris(delta)


func _event(key: String, when: bool, snd: String, db := 0.0) -> bool:
	if when and not _fired.has(key):
		_fired[key] = true
		if snd != "":
			sound.emit(snd, db)
		return true
	return false


static func _xf(pos: Vector3, rot: Vector3) -> Transform3D:
	return Transform3D(Basis.from_euler(rot), pos)


static func _s(t: float, a: float, b: float) -> float:
	return smoothstep(a, b, t)


static func _bump(t: float, a: float, b: float) -> float:
	return sin(clampf((t - a) / (b - a), 0.0, 1.0) * PI)


## Wrist transform (in the prop's space) that closes this hand round a
## cylinder of radius r lying along the prop's Y axis: back of the hand on
## the +X side (-X for the left hand), fingers wrapping round the far side.
static func _grip_cyl(r: float, left: bool) -> Transform3D:
	if left:
		# Mirror: thumb toward +Y, back of the hand toward -X.
		return Transform3D(Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1)), Vector3(-(r + 0.024), -0.004, 0.044))
	return Transform3D(Basis(Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)), Vector3(r + 0.024, -0.004, 0.044))


## Point the forearm from the wrist toward an elbow position (view space).
func _aim_fore(arm: Node3D, elbow: Vector3) -> void:
	var fore: Node3D = arm.get_meta("fore")
	var wrist := arm.transform.origin
	var dir := (wrist - elbow).normalized()
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.FORWARD
	var g := Basis.looking_at(dir, up)
	fore.basis = arm.basis.orthonormalized().inverse() * g


## The gun in hand (view space transform of the gun, its hand points in the
## normalised model, the gun's view scale, the hands' scale). {} = no gun.
func set_gun(d: Dictionary) -> void:
	_gun = d


## The gun moved this frame (recoil, bolt, sway): keep the hands on it.
func refresh_gun(xf: Transform3D) -> void:
	if _gun.is_empty() or item != "" or not visible:
		return
	_gun["xf"] = xf
	_pose_gun()


## Sleeves down (holding a gun) or rolled up (healing, swimming).
func _sleeves(down: bool) -> void:
	var m: Material = _mat("sleeve", SLEEVE, 0.95) if down else null
	for a: Node3D in [arm_l, arm_r]:
		var bare: MeshInstance3D = a.get_meta("bare")
		bare.material_override = m
		bare.scale = Vector3(1.08, 1.0, 1.08) if down else Vector3.ONE


func _pose_gun() -> void:
	_sleeves(true)
	position = Vector3.ZERO
	rotation = Vector3.ZERO
	arm_l.visible = true
	arm_r.visible = true
	for n: Node3D in [roll, kit, syringe, can, grenade]:
		n.visible = false
	strip.visible = false
	var gx: Transform3D = _gun.xf
	var s: float = _gun.scale
	var hs: float = _gun.hand
	var sc := func(t: Transform3D) -> Transform3D:
		return Transform3D(t.basis, t.origin * hs)
	# Right hand round the pistol grip, which leans back at the bottom.
	var grip_b := Basis(Vector3.RIGHT, -0.3)
	var pr := gx * Transform3D(grip_b, (_gun.grip as Vector3) * s)
	var wr: Transform3D = pr * sc.call(_grip_cyl(0.019, false))
	arm_r.transform = Transform3D(wr.basis.scaled(Vector3.ONE * hs), wr.origin)
	_aim_fore(arm_r, ELBOW_R)
	_curl(arm_r, 1.12, 0.85)
	if bool(_gun.pistol):
		# Support hand wrapped round the shooting hand, a little lower.
		var pl := gx * Transform3D(grip_b, (_gun.grip as Vector3) * s + Vector3(-0.004, -0.016, 0.006))
		var wl: Transform3D = pl * sc.call(_grip_cyl(0.026, true))
		_place_left(Transform3D(wl.basis.scaled(Vector3.ONE * hs), wl.origin), Vector3(-0.16, -0.6, -0.12), 1.05, 0.6)
		return
	if bool(_gun.get("fore_vertical", false)):
		# Left hand round the vertical foregrip, leaning a little forward.
		var pv := gx * Transform3D(Basis(Vector3.RIGHT, 0.12), (_gun.fore as Vector3) * s)
		var wv: Transform3D = pv * sc.call(_grip_cyl(0.019, true))
		_place_left(Transform3D(wv.basis.scaled(Vector3.ONE * hs), wv.origin), ELBOW_L, 1.15, 0.85)
		return
	# Left hand under the handguard, the barrel along its palm.
	var fb := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
	var pf := gx * Transform3D(fb, (_gun.fore as Vector3) * s + Vector3(0, -0.006, 0))
	var wf: Transform3D = pf * sc.call(_grip_cyl(0.024, true))
	_place_left(Transform3D(wf.basis.scaled(Vector3.ONE * hs), wf.origin), ELBOW_L, 1.25, 0.7)


## The support hand: on the gun, or (reloading) off it to swap the magazine,
## feed shells or work the charging handle.
func _place_left(home: Transform3D, elbow: Vector3, curl: float, thumb: float) -> void:
	var xf := home
	var c := curl
	if not reload.is_empty():
		var t: float = reload.t
		var hs: float = _gun.hand
		var s: float = _gun.scale
		var gx: Transform3D = _gun.xf
		var sc := func(g: Transform3D) -> Transform3D:
			var w := Transform3D(g.basis, g.origin * hs)
			return Transform3D(w.basis.scaled(Vector3.ONE * hs), w.origin)
		if str(reload.kind) == "mag":
			# Hand round the bottom of the magazine (it follows it out of
			# sight and back in with the new one), then home or onto the
			# charging handle when the gun ran dry.
			var mx: Transform3D = reload.mag
			var mp: Vector3 = mx * (reload.mag_low as Vector3)
			var on_mag: Transform3D = Transform3D(mx.basis.orthonormalized() * Basis(Vector3.RIGHT, 0.1), mp) * sc.call(_grip_cyl(0.021, true))
			var on := _s(t, 0.08, 0.17)
			var off := _s(t, 0.62, 0.70)
			xf = home.interpolate_with(on_mag, on)
			c = lerpf(curl, 1.1, on)
			if bool(reload.empty) and not bool(_gun.pistol):
				var pull := _bump(t, 0.70, 0.82)
				var rp: Vector3 = (reload.rack as Vector3) * s + Vector3(0, 0, pull * 0.065)
				var rk: Transform3D = gx * Transform3D(Basis(Vector3.RIGHT, -0.25), rp) * sc.call(_grip_cyl(0.008, true))
				xf = xf.interpolate_with(rk, off)
				var back := _s(t, 0.84, 0.93)
				xf = xf.interpolate_with(home, back)
				c = lerpf(lerpf(c, 1.35, off), curl, back)
			else:
				xf = xf.interpolate_with(home, off)
				c = lerpf(c, curl, off)
			# A little lift in between, not a straight slide.
			xf.origin.y += 0.03 * (_bump(t, 0.08, 0.17) + _bump(t, 0.62, 0.70))
		elif str(reload.kind) == "shell":
			# Shell by shell: down to the belt, up to the loading port.
			var fb := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
			var port: Transform3D = gx * Transform3D(fb, (reload.port as Vector3) * s) * sc.call(_grip_cyl(0.02, true))
			var n := maxi(1, int(reload.shells))
			var span := 0.62 / float(n)
			var on := _s(t, 0.06, 0.14) * (1.0 - _s(t, 0.76, 0.86))
			var dip := 0.0
			if t > 0.14 and t < 0.76:
				var ph := fmod((t - 0.14) / span, 1.0)
				dip = _bump(ph, 0.0, 0.5)
			var at_port := port
			at_port.origin += Vector3(-0.05, -0.2, 0.08) * dip
			xf = home.interpolate_with(at_port, on)
			c = lerpf(curl, lerpf(0.9, 0.5, dip), on)
	arm_l.transform = xf
	_aim_fore(arm_l, elbow)
	_curl(arm_l, c, thumb)


func _place(arm: Node3D, xf: Transform3D, elbow: Vector3) -> void:
	arm.transform = xf
	_aim_fore(arm, elbow)


const ELBOW_L := Vector3(-0.3, -0.62, -0.2)
const ELBOW_R := Vector3(0.3, -0.62, -0.18)
const OFF_L := Vector3(-0.22, -0.42, -0.2)
const OFF_R := Vector3(0.22, -0.42, -0.2)


# ------------------------------------------------------------------ bandage --
func _bandage(t: float) -> float:
	# Left forearm held across the view, inside of the wrist turned up.
	var lp := Vector3(0.11, -0.115, -0.45)
	var dir_f := Vector3(0.85, 0.28, -0.45).normalized()
	var lb := Basis.looking_at(dir_f, Vector3.UP) * Basis(Vector3(0, 0, 1), 0.65)
	var in_k := _s(t, 0.0, 0.1)
	var lift := Vector3(0, -0.04, 0.02) * (1.0 - in_k)
	var settle := _bump(t, 0.86, 1.0)
	var lx := Transform3D(lb * Basis(Vector3(0, 0, 1), -settle * 0.45), lp + lift + Vector3(0, settle * 0.015, 0))
	_place(arm_l, lx, Vector3(-0.34, -0.3, -0.3))
	_curl(arm_l, 0.45)
	var fore_x := lx * fore_l.transform

	var w := clampf((t - 0.14) / 0.68, 0.0, 1.0)
	var zw := lerpf(WRAP_Z0, WRAP_Z1, w)
	var passes := 3.0
	var theta := PI * 0.5 + w * passes * TAU
	for i in WRAP_RINGS:
		if w > (float(i) + 0.35) / float(WRAP_RINGS) and t >= 0.14:
			wraps[i].visible = true
	_event("tear", t >= 0.05, "bandage_tear", -6.0)
	for p in 3:
		_event("wrap%d" % p, t >= 0.14 + 0.68 * float(p) / passes, "bandage_wrap", -5.0)

	# The roll circles the forearm, held out radially by the right hand.
	var rr := lerpf(1.0, 0.55, w)
	roll_mesh.scale = Vector3(rr, 1.0, rr)
	var radius := 0.08
	var rx: Transform3D
	if t < 0.14:
		# Strip torn and pinned under the left thumb, roll pulled away.
		var pull := _bump(t, 0.03, 0.14)
		var c := Vector3(radius + pull * 0.05, 0.02, WRAP_Z0)
		var x_dir := c.normalized()
		var b := Basis(Vector3(x_dir.x, x_dir.y, 0).normalized(), Vector3(0, 0, 1), Vector3(x_dir.y, -x_dir.x, 0).normalized())
		rx = fore_x * Transform3D(b.orthonormalized(), c)
	elif t < 0.84:
		var radial := Vector3(cos(theta), sin(theta), 0)
		var c := radial * radius + Vector3(0, 0, zw)
		# Keep the knuckles mostly upright: only half the circle shows in the wrist.
		var out := radial.lerp(Vector3(0.6, 0.8, 0).normalized(), 0.45).normalized()
		var tang := Vector3(0, 0, 1).cross(out).normalized()
		rx = fore_x * Transform3D(Basis(out, Vector3(0, 0, 1), -tang).orthonormalized(), c)
	else:
		# Roll used up: tuck the end and press the wrap flat.
		var press := _bump(t, 0.84, 0.91) + _bump(t, 0.91, 0.98) * 0.7
		var c := Vector3(0.03, 0.05 + 0.025 * (1.0 - press), lerpf(WRAP_Z0, WRAP_Z1, 0.55))
		rx = fore_x * Transform3D(Basis(Vector3(0.5, 0.86, 0).normalized(), Vector3(0, 0, 1), Vector3(0.86, -0.5, 0).normalized()).orthonormalized(), c)
	roll_mesh.rotation = Vector3(0, -theta * 1.6, 0)
	roll.transform = rx
	roll.visible = t < 0.84
	# Pinched at one end so the roll itself stays in view.
	var rhand := rx * Transform3D(Basis.IDENTITY, Vector3(0, 0.045, 0)) * _grip_cyl(0.03 * rr, false)
	if t < 0.06:
		rhand = rhand.interpolate_with(Transform3D(Basis.from_euler(Vector3(-0.6, 0.4, 0.3)), OFF_R), 1.0 - _s(t, 0.0, 0.06))
	_place(arm_r, rhand, Vector3(0.4, -0.44, -0.22))
	_curl(arm_r, 0.4 if t >= 0.84 else 0.95)

	# Loose strip from the roll to the last turn on the arm.
	if t >= 0.02 and t < 0.84:
		var a := (rx * Vector3(-0.03 * rr, -0.01, 0))
		var back := theta - 1.1
		var bz := maxf(WRAP_Z0, zw - 0.006)
		var b := fore_x * (Vector3(cos(back), sin(back), 0) * (_fore_radius(bz) + 0.004) + Vector3(0, 0, bz))
		if t < 0.14:
			b = fore_x * Vector3(0.0, _fore_radius(WRAP_Z0) + 0.004, WRAP_Z0)
		var axis := (fore_x.basis * Vector3(0, 0, 1)).normalized() * 0.0095
		_strip(a, b, axis)
	return -0.07 * _s(t, 0.1, 0.25) * (1.0 - _s(t, 0.85, 1.0))


func _strip(a: Vector3, b: Vector3, half: Vector3) -> void:
	strip_mesh.clear_surfaces()
	strip_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := (b - a).cross(half).normalized()
	for v in [a - half, a + half, b + half, a - half, b + half, b - half]:
		strip_mesh.surface_set_normal(n)
		strip_mesh.surface_add_vertex(v)
	strip_mesh.surface_end()
	strip.visible = true


# ------------------------------------------------------------------ medkit --
func _med(t: float) -> float:
	# Kit held flat on the left palm, tipped toward the eye.
	var k0 := _xf(Vector3(-0.035, -0.175, -0.36), Vector3(0.5, 0.22, 0.04))
	var k1 := _xf(Vector3(-0.2, -0.205, -0.3), Vector3(0.55, 0.7, 0.32))
	var aside := _s(t, 0.42, 0.52) * (1.0 - _s(t, 0.72, 0.82))
	var kx := k0.interpolate_with(k1, aside)
	kit.transform = kx
	var lid_open := _s(t, 0.1, 0.24) * (1.0 - _s(t, 0.84, 0.94))
	kit_lid.rotation = Vector3(-1.95 * lid_open, 0, 0)
	_event("zip_open", t >= 0.08, "kit_zip_open", -3.0)
	_event("zip_close", t >= 0.84, "kit_zip_close", -3.0)

	# Left hand flat under the kit, fingers to the right.
	var under := Transform3D(Basis(Vector3(0, 0, -1), Vector3(0, -1, 0), Vector3(-1, 0, 0)), Vector3(-0.098, -0.027, 0.0))
	_place(arm_l, kx * under, Vector3(-0.36, -0.42, -0.22))
	_curl(arm_l, 0.12, 0.3)

	# Right hand: pull tab, then the syringe, then the lid again.
	var lid_x := kx * kit_lid.transform
	var on_tab := lid_x * Transform3D(Basis.from_euler(Vector3(-0.55, 0.15, 0.0)), Vector3(0.075, 0.07, KIT_D + 0.088))
	var syr_in := kx * _xf(Vector3(-0.004, 0.021, 0.034), Vector3(0, 0.1, PI * 0.5))
	var s_up := _xf(Vector3(0.07, -0.07, -0.3), Vector3(0.12, -0.1, 0.22))
	var s_aim := _xf(Vector3(0.03, -0.17, -0.27), Vector3(-0.45, 0.0, 0.16))
	var stab := _s(t, 0.5, 0.53) * (1.0 - _s(t, 0.72, 0.78))
	var s_in := _xf(Vector3(0.03, -0.215, -0.29), Vector3(-0.45, 0.0, 0.16))
	var sx := syr_in
	if t >= 0.34:
		sx = syr_in.interpolate_with(s_up, _s(t, 0.34, 0.44))
		if t >= 0.44:
			sx = s_up.interpolate_with(s_aim, _s(t, 0.44, 0.5)).interpolate_with(s_in, stab)
		if t >= 0.72:
			sx = sx.interpolate_with(s_up, _s(t, 0.72, 0.78))
	var flinch := _bump(t, 0.52, 0.6)
	sx.origin += Vector3(0.004, 0.0, 0.0) * sin(t * 180.0) * flinch
	if not _debris.has("syr"):
		syringe.transform = sx
	# Cap off with a flick of the thumb.
	if _event("cap", t >= 0.43, "syringe_click", -4.0):
		_throw("cap", syr_cap, sx.basis * Vector3(0.35, -0.2, 0.1), Vector3(14, 3, 9))
	if _event("stab", t >= 0.52, "syringe_inject", -2.0):
		jolt.emit(0.16)
	var push := _s(t, 0.54, 0.7)
	plunger.position = Vector3(0, -0.032 * push, 0)
	fluid.scale = Vector3(1, maxf(0.04, 1.0 - push), 1)
	fluid.position = Vector3(0, -0.002 - 0.04 * push, 0)
	if _event("toss", t >= 0.78, ""):
		_throw("syr", syringe, Vector3(0.5, 0.35, 0.15), Vector3(2, 12, 5))

	var grip := _grip_cyl(0.0115, false)
	var rx: Transform3D
	var rcurl := 1.0
	if t < 0.24:
		var come := _s(t, 0.0, 0.09)
		rx = Transform3D(Basis.from_euler(Vector3(-0.7, 0.5, 0.2)), OFF_R).interpolate_with(on_tab, come)
		rcurl = 0.7
	elif t < 0.34:
		var reach := _s(t, 0.24, 0.31)
		var hover := syr_in * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)) * grip
		rx = on_tab.interpolate_with(hover, reach)
		rcurl = lerpf(0.7, 0.2, _bump(t, 0.24, 0.3)) if t < 0.3 else lerpf(0.2, 1.05, _s(t, 0.3, 0.34))
	elif t < 0.78:
		rx = sx * grip
		rcurl = 1.05
	else:
		var after := _s(t, 0.78, 0.86)
		rx = (s_up * grip).interpolate_with(on_tab, after)
		rcurl = lerpf(0.3, 0.7, after)
	_place(arm_r, rx, Vector3(0.34, -0.48, -0.16))
	_curl(arm_r, rcurl, 1.3 if (t >= 0.5 and t < 0.74) else -1.0)
	return -0.36 * _s(t, 0.42, 0.52) * (1.0 - _s(t, 0.72, 0.84))


# ------------------------------------------------------------- energy drink --
func _energy(t: float) -> float:
	var c0 := _xf(Vector3(0.1, -0.15, -0.34), Vector3(0.12, 0.3, -0.1))
	var tilt := 2.1 + _s(t, 0.4, 0.75) * 0.3
	var c1 := _xf(Vector3(0.01, -0.07, -0.15), Vector3(tilt, 0.12, 0.04))
	var c2 := _xf(Vector3(0.095, -0.14, -0.33), Vector3(0.25, 0.35, -0.18))
	var cx := c0
	if t >= 0.3:
		cx = c0.interpolate_with(c1, _s(t, 0.3, 0.42))
	if t >= 0.78:
		cx = c1.interpolate_with(c2, _s(t, 0.78, 0.88))
	# A swallow every few tips: the can bobs toward the mouth.
	for g in 3:
		var gt := 0.44 + 0.12 * float(g)
		cx.origin += Vector3(0, 0.006, 0.01) * _bump(t, gt - 0.03, gt + 0.05)
		_event("gulp%d" % g, t >= gt, "gulp", -4.0)
	_event("open", t >= 0.165, "can_open", -3.0)
	_event("ahh", t >= 0.82, "drink_ahh", -6.0)
	can_tab.rotation = Vector3(-0.7 * _s(t, 0.15, 0.18), 0, 0)
	can_hole.visible = t >= 0.16
	if _event("spray", t >= 0.165, ""):
		for d in _drops:
			_throw("drop%d" % _drops.find(d), d, cx.basis * Vector3(randf_range(-0.25, 0.25), randf_range(0.5, 0.9), randf_range(-0.25, 0.25)), Vector3.ZERO, cx * Vector3(0, 0.066, 0.01))
	# Crush, then let it drop.
	var crush := _s(t, 0.88, 0.94)
	can_body.scale = Vector3(1.0 + crush * 0.12, 1.0 - crush * 0.42, 1.0 + crush * 0.06)
	can_body.rotation = Vector3(crush * 0.12, crush * 0.6, crush * 0.08)
	_event("crush", t >= 0.88, "can_crush", -4.0)
	if _event("drop", t >= 0.965, ""):
		_throw("can", can, Vector3(0.12, 0.25, 0.1), Vector3(4, 2, 6))
	if not _debris.has("can"):
		can.transform = cx

	var rx := cx * _grip_cyl(0.033 * (1.0 + crush * 0.1), false)
	if t < 0.08:
		rx = Transform3D(Basis.from_euler(Vector3(-0.6, 0.4, 0.3)), OFF_R).interpolate_with(rx, _s(t, 0.0, 0.08))
	if t >= 0.965:
		rx = rx.interpolate_with(Transform3D(rx.basis, rx.origin + Vector3(0.03, -0.06, 0.02)), _s(t, 0.965, 1.0))
	var lift := _s(t, 0.3, 0.42) * (1.0 - _s(t, 0.78, 0.88))
	_place(arm_r, rx, Vector3(0.32, -0.48, -0.16).lerp(Vector3(0.26, -0.36, -0.02), lift))
	_curl(arm_r, 1.0 + crush * 0.5 if t < 0.965 else lerpf(1.5, 0.4, _s(t, 0.965, 1.0)))

	# Left index finger pops the tab, then the hand drops away.
	var on_top := cx * Transform3D(Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)), Vector3(-0.108, 0.082, -0.005))
	var off_l := Transform3D(Basis.from_euler(Vector3(-0.6, -0.5, -0.3)), OFF_L)
	var lk := _s(t, 0.04, 0.13) * (1.0 - _s(t, 0.2, 0.3))
	_place(arm_l, off_l.interpolate_with(on_top, lk), ELBOW_L)
	_curl(arm_l, lerpf(0.35, 0.95, _s(t, 0.13, 0.17)), 0.2)
	arm_l.visible = lk > 0.01
	return 0.17 * _s(t, 0.32, 0.44) * (1.0 - _s(t, 0.76, 0.86)) + 0.015 * (_bump(t, 0.41, 0.49) + _bump(t, 0.53, 0.61) + _bump(t, 0.65, 0.73))


# ------------------------------------------------------------------ grenade --
func _grenade(t: float) -> float:
	var g0 := _xf(Vector3(0.12, -0.14, -0.34), Vector3(0.12, 0.35, -0.08))
	var g1 := _xf(Vector3(0.2, -0.04, -0.19), Vector3(-0.55, 0.5, -0.35))
	var g2 := _xf(Vector3(0.03, 0.02, -0.6), Vector3(0.7, 0.1, 0.1))
	var gx := g0
	if t >= 0.32:
		gx = g0.interpolate_with(g1, _s(t, 0.32, 0.5))
	if t >= 0.52:
		gx = g1.interpolate_with(g2, _s(t, 0.52, 0.6))
	grenade.transform = gx
	_event("pin", t >= 0.19, "grenade_pin", -3.0)
	_event("whoosh", t >= 0.5, "throw_whoosh", -5.0)
	if _event("spoon", t >= 0.6, "casing_2", -12.0):
		_throw("spoon", g_spoon, gx.basis * Vector3(0.7, 0.9, 0.3), Vector3(25, 6, 12))
	# Left hand: index through the ring, pull it out sideways, drop away.
	var on_pin := gx * Transform3D(Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)), Vector3(-0.15, 0.06, -0.01))
	var off_l := Transform3D(Basis.from_euler(Vector3(-0.6, -0.5, -0.3)), OFF_L)
	var come := _s(t, 0.04, 0.15)
	var lx := off_l.interpolate_with(on_pin, come)
	var pull := _s(t, 0.18, 0.3)
	lx.origin += Vector3(-0.09, -0.02, 0.03) * pull
	lx = lx.interpolate_with(off_l, _s(t, 0.34, 0.5))
	_place(arm_l, lx, Vector3(-0.34, -0.42, -0.2))
	_curl(arm_l, lerpf(0.4, 1.1, _s(t, 0.14, 0.19)), 0.2)
	arm_l.visible = t < 0.5
	if t >= 0.19 and g_ring.get_parent() == grenade:
		grenade.remove_child(g_ring)
		add_child(g_ring)
	if g_ring.get_parent() == self:
		g_ring.transform = lx * Transform3D(Basis.IDENTITY, Vector3(0.012, -0.03, -0.125))
		g_ring.visible = t < 0.48
	# Right hand round the body, then the follow-through after release.
	var rx := gx * _grip_cyl(0.03, false)
	var follow := _xf(Vector3(-0.04, -0.3, -0.42), Vector3(0.9, -0.3, 0.5))
	if t >= 0.6:
		rx = (g2 * _grip_cyl(0.03, false)).interpolate_with(follow, _s(t, 0.6, 0.9))
	var elbow := Vector3(0.32, -0.46, -0.16).lerp(Vector3(0.34, -0.2, 0.08), _s(t, 0.32, 0.5) * (1.0 - _s(t, 0.52, 0.62)))
	_place(arm_r, rx, elbow)
	_curl(arm_r, 1.0 if t < 0.6 else lerpf(0.5, 0.25, _s(t, 0.6, 0.8)))
	return 0.03 * _s(t, 0.32, 0.5) * (1.0 - _s(t, 0.52, 0.62)) - 0.025 * _bump(t, 0.56, 0.85)


# --------------------------------------------------------------------- swim --
## Breaststroke key poses for the right hand (the left mirrors it):
## together at the chest, reach forward, sweep out, pull back in.
const STROKE := [
	[Vector3(0.07, -0.2, -0.28), Vector3(0.0, 0.0, -1.0), 0.35],
	[Vector3(0.06, -0.13, -0.56), Vector3(0.05, 0.05, -1.0), 0.0],
	[Vector3(0.33, -0.16, -0.42), Vector3(0.65, 0.0, -0.75), -0.95],
	[Vector3(0.17, -0.27, -0.26), Vector3(-0.45, 0.1, -0.85), -0.45],
]


func _swim(t: float) -> float:
	var n := STROKE.size()
	# Catmull-Rom round the loop so the stroke never snaps.
	var f := t * float(n)
	var i: int = int(floorf(f)) % n
	var u: float = f - floorf(f)
	for side in [-1.0, 1.0]:
		var arm := arm_l if side < 0.0 else arm_r
		var pts: Array = []
		var dirs: Array = []
		var rolls: Array = []
		for k in [-1, 0, 1, 2]:
			var kf: Array = STROKE[(i + k + n) % n]
			var p: Vector3 = kf[0]
			var d: Vector3 = kf[1]
			pts.append(Vector3(p.x * side, p.y, p.z))
			dirs.append(Vector3(d.x * side, d.y, d.z))
			rolls.append(float(kf[2]) * side)
		var pos := _catmull(pts[0], pts[1], pts[2], pts[3], u)
		var dir := (dirs[1] as Vector3).lerp(dirs[2], smoothstep(0.0, 1.0, u)).normalized()
		var roll := lerpf(float(rolls[1]), float(rolls[2]), smoothstep(0.0, 1.0, u))
		var b := Basis.looking_at(dir, Vector3.UP) * Basis(Vector3(0, 0, 1), -roll)
		_place(arm, Transform3D(b, pos), Vector3(side * 0.3, -0.52, -0.08))
		_curl(arm, 0.18, 0.15)
	return sin(t * TAU) * 0.012


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: float) -> Vector3:
	var u2 := u * u
	var u3 := u2 * u
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3)


# -------------------------------------------------------------------- vault --
func _vault(t: float) -> float:
	var push := _s(t, 0.0, 0.7)
	var away := _s(t, 0.7, 1.0)
	for side in [-1.0, 1.0]:
		var arm := arm_l if side < 0.0 else arm_r
		var pos := Vector3(side * 0.17, lerpf(-0.17, -0.36, push) - away * 0.2, -0.42 + push * 0.08 + away * 0.1)
		var b := Basis.looking_at(Vector3(-side * 0.25, -0.35, -1.0).normalized(), Vector3.UP) * Basis(Vector3(0, 0, 1), side * 0.15)
		_place(arm, Transform3D(b, pos), Vector3(side * 0.32, -0.5, -0.12))
		_curl(arm, 0.08, 0.4)
	return -0.05 * _bump(t, 0.0, 0.8)


# ------------------------------------------------------------------- debris --
## Let a prop go: it flies off in view space under gravity.
func _throw(key: String, node: Node3D, vel: Vector3, spin: Vector3, from := Vector3.INF) -> void:
	var xf := node.transform if node.get_parent() == self else (node.get_parent() as Node3D).transform * node.transform
	if node.get_parent() != self:
		node.get_parent().remove_child(node)
		add_child(node)
	if from != Vector3.INF:
		xf.origin = from
	node.transform = xf
	node.visible = true
	_debris[key] = {"node": node, "vel": vel, "spin": spin, "life": 0.9}


func _tick_debris(delta: float) -> void:
	for key in _debris.keys():
		var d: Dictionary = _debris[key]
		if not d.has("node"):
			continue
		var n: Node3D = d["node"]
		d["life"] = float(d["life"]) - delta
		d["vel"] = Vector3(d["vel"]) + Vector3(0, -3.2, 0) * delta
		n.position += Vector3(d["vel"]) * delta
		var sp: Vector3 = d["spin"]
		if sp != Vector3.ZERO:
			n.rotate_object_local(sp.normalized(), sp.length() * delta)
		if float(d["life"]) <= 0.0 or n.position.y < -0.6:
			n.visible = false
			_debris.erase(key)
			if key == "syr":
				_debris["syr_gone"] = {}
			elif key == "can":
				_debris["can_gone"] = {}
			elif key == "cap":
				_restore_cap()


func _restore_cap() -> void:
	if syr_cap.get_parent() != syringe:
		syr_cap.get_parent().remove_child(syr_cap)
		syringe.add_child(syr_cap)
	syr_cap.visible = false
