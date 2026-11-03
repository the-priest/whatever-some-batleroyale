class_name LootPickup
extends Node3D

# A floor pickup: a rotating weapon or item with a tier-coloured ground ring
# and light shaft, so loot reads from a distance.
#
# kinds: weapon (item_id = gun), ammo, armor (vest, tier 1-3), helmet (tier
# 1-3), bandage, med, energy, scope (item_id = reddot|2x|4x|8x), extmag, comp,
# grenade.

const ITEM_NAMES := {
	"ammo": "AMMO BOX", "bandage": "BANDAGES", "med": "MEDKIT", "energy": "ENERGY DRINK",
	"extmag": "EXTENDED MAG", "comp": "COMPENSATOR", "grenade": "FRAG GRENADE",
}
const SCOPE_NAMES := {"reddot": "RED DOT SIGHT", "2x": "2X SCOPE", "4x": "4X SCOPE", "8x": "8X SCOPE"}
const SCOPE_TIER := {"reddot": 1, "2x": 2, "4x": 3, "8x": 4}

var kind := "weapon"
var item_id := "pistol"
var amount := 1
var taken := false
var bob_phase := 0.0
var label: Label3D
var beacon: MeshInstance3D
var ring: MeshInstance3D
var spin: Node3D
var tier := 1
var mag_override := -1
var reserve_override := -1
var dropped := false


func setup(p_kind: String, p_id: String, p_amount: int = 1) -> void:
	kind = p_kind
	item_id = p_id
	amount = p_amount
	bob_phase = randf() * TAU
	match kind:
		"weapon":
			tier = int(Weapons.def(item_id).get("tier", 1))
		"armor", "helmet":
			tier = clampi(int(item_id) if item_id != "" else 1, 1, 3) + 1
			if item_id == "":
				item_id = "1"
		"scope":
			tier = int(SCOPE_TIER.get(item_id, 1))
		"extmag", "comp":
			tier = 3
		"med", "energy":
			tier = 2
		_:
			tier = 1
	if kind == "bandage" and amount <= 1:
		amount = 5


func accent_color() -> Color:
	match kind:
		"weapon":
			return Weapons.tier_color(item_id)
		"med", "bandage":
			return Color(0.95, 0.38, 0.38)
		"energy":
			return Color(0.45, 0.95, 0.55)
		"ammo":
			return Color(0.95, 0.78, 0.35)
		"grenade":
			return Color(0.62, 0.78, 0.36)
	return Weapons.TIER_COLORS[clampi(tier - 1, 0, 3)]


func _ready() -> void:
	var accent := accent_color()
	# Loot rests on the ground like a real object: no floating, no spinning.
	spin = Node3D.new()
	spin.rotation.y = randf() * TAU
	add_child(spin)

	if kind == "weapon":
		var gun := Weapons.make_drop_node(item_id)
		var length := float(Weapons.def(item_id).get("len", 0.8))
		gun.scale = Vector3.ONE * length
		# Lying on its side.
		gun.rotation.z = PI * 0.5
		gun.position.y = 0.035
		spin.add_child(gun)
	else:
		_build_item_model(accent)
		_settle_item()

	# Glow ring on the ground.
	ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.52
	torus.outer_radius = 0.60
	torus.rings = 20
	torus.ring_segments = 6
	ring.mesh = torus
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(accent.r, accent.g, accent.b, 0.85)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = rm
	ring.position.y = 0.02
	ring.scale = Vector3(1.0, 0.25, 1.0) * (0.9 if kind == "weapon" else 0.6)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A faint ground marker only shows when you are close (see game.gd).
	rm.albedo_color.a = 0.35
	ring.visible = false
	add_child(ring)

	# Light shaft: taller for better loot.
	beacon = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.12
	cyl.height = 2.5 + tier * 1.2
	cyl.radial_segments = 6
	cyl.rings = 1
	beacon.mesh = cyl
	beacon.visible = false
	var bmm := StandardMaterial3D.new()
	bmm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmm.albedo_color = Color(accent.r, accent.g, accent.b, 0.22 + tier * 0.03)
	bmm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bmm.cull_mode = BaseMaterial3D.CULL_DISABLED
	beacon.material_override = bmm
	beacon.position.y = cyl.height * 0.5
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beacon)

	label = Label3D.new()
	label.text = display_name()
	label.font = load("res://assets/fonts/ui_bold.ttf")
	label.font_size = 40
	# Constant size on screen, so it is readable from 10 m and not a wall of
	# text when you stand right over the item.
	label.fixed_size = true
	label.pixel_size = 0.0009
	label.modulate = accent.lightened(0.2)
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.outline_size = 10
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 0.55
	label.visible = false
	add_child(label)


func _mat(c: Color, metal := 0.3, rough := 0.5, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m


func _part(mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	spin.add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 1
	return c


func _build_item_model(accent: Color) -> void:
	var dark := _mat(Color(0.16, 0.17, 0.18), 0.5, 0.45)
	var glow := _mat(accent, 0.1, 0.4, 1.4)
	match kind:
		"armor":
			# Plate carrier: torso slab with shoulder straps.
			var vest := _mat(Color(0.20, 0.24, 0.20).lerp(accent * 0.6, 0.25), 0.1, 0.8)
			_part(_box(Vector3(0.48, 0.52, 0.16)), vest)
			_part(_box(Vector3(0.10, 0.12, 0.17)), vest, Vector3(-0.15, 0.31, 0))
			_part(_box(Vector3(0.10, 0.12, 0.17)), vest, Vector3(0.15, 0.31, 0))
			_part(_box(Vector3(0.36, 0.05, 0.17)), glow, Vector3(0, -0.06, 0.005))
		"helmet":
			var hm := SphereMesh.new()
			hm.radius = 0.2
			hm.height = 0.26
			hm.is_hemisphere = true
			_part(hm, _mat(Color(0.22, 0.26, 0.22).lerp(accent * 0.6, 0.25), 0.2, 0.7), Vector3(0, -0.05, 0))
			_part(_cyl(0.205, 0.035), glow, Vector3(0, -0.04, 0))
		"bandage":
			_part(_cyl(0.11, 0.16), _mat(Color(0.92, 0.9, 0.86), 0.0, 0.9), Vector3.ZERO, Vector3(0, 0, PI * 0.5))
			_part(_cyl(0.112, 0.04), glow, Vector3.ZERO, Vector3(0, 0, PI * 0.5))
		"med":
			_part(_box(Vector3(0.46, 0.30, 0.30)), _mat(Color(0.88, 0.88, 0.86), 0.0, 0.6))
			_part(_box(Vector3(0.20, 0.06, 0.31)), glow)
			_part(_box(Vector3(0.06, 0.20, 0.31)), glow)
		"energy":
			_part(_cyl(0.07, 0.24), _mat(Color(0.15, 0.55, 0.30), 0.7, 0.3))
			_part(_cyl(0.072, 0.06), glow, Vector3(0, 0.04, 0))
		"ammo":
			_part(_box(Vector3(0.52, 0.30, 0.30)), _mat(Color(0.28, 0.32, 0.22), 0.4, 0.6))
			_part(_box(Vector3(0.53, 0.06, 0.31)), glow, Vector3(0, 0.05, 0))
		"scope":
			var length := 0.18 + tier * 0.06
			var r := 0.035 + tier * 0.006
			_part(_cyl(r, length), dark, Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
			_part(_cyl(r * 1.35, 0.05), dark, Vector3(0, 0, -length * 0.5), Vector3(PI * 0.5, 0, 0))
			_part(_cyl(r * 1.15, 0.03), glow, Vector3(0, 0, length * 0.5), Vector3(PI * 0.5, 0, 0))
		"extmag":
			_part(_box(Vector3(0.07, 0.34, 0.10)), dark, Vector3.ZERO, Vector3(0.25, 0, 0))
			_part(_box(Vector3(0.075, 0.05, 0.105)), glow, Vector3(0, -0.15, 0.04), Vector3(0.25, 0, 0))
		"comp":
			_part(_cyl(0.045, 0.2), dark, Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
			_part(_cyl(0.05, 0.04), glow, Vector3(0, 0, 0.08), Vector3(PI * 0.5, 0, 0))
		"grenade":
			var sm := SphereMesh.new()
			sm.radius = 0.09
			sm.height = 0.2
			_part(sm, _mat(Color(0.28, 0.34, 0.20), 0.3, 0.6))
			_part(_box(Vector3(0.03, 0.08, 0.06)), dark, Vector3(0.0, 0.11, 0.0))
			_part(_cyl(0.025, 0.03), glow, Vector3(0, 0.1, 0))
		_:
			_part(_box(Vector3(0.4, 0.3, 0.3)), _mat(Color(0.18, 0.20, 0.21), 0.5, 0.4))


func display_name() -> String:
	match kind:
		"weapon":
			return str(Weapons.def(item_id).get("name", item_id.to_upper()))
		"armor":
			return "VEST  LV%d" % int(item_id)
		"helmet":
			return "HELMET  LV%d" % int(item_id)
		"scope":
			return str(SCOPE_NAMES.get(item_id, "SCOPE"))
		"bandage":
			return "BANDAGES ×%d" % amount
		"ammo":
			if item_id != "":
				return "%s  ×%d" % [item_id.to_upper(), int(Weapons.AMMO_BOX.get(item_id, 30))]
	return str(ITEM_NAMES.get(kind, "LOOT"))


func prompt_text() -> String:
	var verb := "PICK UP" if kind == "weapon" else ("EQUIP" if kind in ["armor", "helmet", "scope", "extmag", "comp"] else "TAKE")
	return "[F]  %s  %s" % [verb, display_name()]


## Empty string when the player can take this, otherwise the reason they cannot.
func block_reason(player: Player) -> String:
	if taken:
		return "GONE"
	return player.loot_block_reason(self)


func can_pickup(player: Player) -> bool:
	return block_reason(player) == ""


func pickup(player: Player) -> bool:
	if taken:
		return false
	if not player.take_loot(self):
		return false
	taken = true
	_pop()
	return true


func consume() -> void:
	taken = true
	var parent := get_parent()
	if parent != null:
		var pool = parent.get("loot_pool")
		if pool is Array:
			(pool as Array).erase(self)
	_pop()


func _pop() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(spin, "scale", Vector3.ONE * 0.01, 0.14).set_ease(Tween.EASE_IN)
	tw.tween_property(beacon, "scale", Vector3(1.0, 0.05, 1.0), 0.14)
	tw.tween_property(ring, "scale", Vector3.ONE * 2.4, 0.16)
	tw.tween_property(ring, "transparency", 1.0, 0.16)
	tw.chain().tween_callback(queue_free)


func _settle_item() -> void:
	# Items are modelled centred on the origin; drop them so they sit on the floor.
	var lowest := 0.0
	for c in spin.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var a: AABB = (c as MeshInstance3D).transform * (c as MeshInstance3D).mesh.get_aabb()
			lowest = minf(lowest, a.position.y)
	spin.position.y = -lowest + 0.005
