class_name LootPickup
extends Node3D

# A floor pickup: rotating weapon or a supply stack, with a tier-coloured
# beacon so it is visible from a distance through trees.

var kind := "weapon"
var item_id := "pistol"
var amount := 1
var base_y := 0.0
var taken := false
var bob_phase := 0.0
var label: Label3D
var beacon: MeshInstance3D
var ring: MeshInstance3D
var spin: Node3D
var tier := 1
var radius := 2.2
var spawn_time := 0.0


func setup(p_kind: String, p_id: String, p_amount: int = 1) -> void:
	kind = p_kind
	item_id = p_id
	amount = p_amount
	bob_phase = randf() * TAU
	if kind == "weapon":
		tier = int(Weapons.def(item_id).get("tier", 1))
	else:
		tier = 2 if kind == "armor" else 1


func _ready() -> void:
	var accent := Weapons.tier_color(item_id) if kind == "weapon" else Color(0.55, 0.78, 0.95)
	if kind == "med":
		accent = Color(0.95, 0.35, 0.35)
	if kind == "ammo":
		accent = Color(0.95, 0.78, 0.35)
	spin = Node3D.new()
	spin.position.y = 0.55
	add_child(spin)

	if kind == "weapon":
		var gun := Weapons.make_drop_node(item_id)
		gun.scale = Vector3.ONE * 0.62
		gun.rotation.y = PI * 0.5
		gun.rotation.z = 0.25
		spin.add_child(gun)
	else:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.55, 0.38, 0.42) if kind != "med" else Vector3(0.46, 0.30, 0.32)
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.18, 0.20, 0.21)
		m.metallic = 0.5
		m.roughness = 0.4
		m.emission_enabled = true
		m.emission = accent * 0.35
		mi.material_override = m
		mi.position.y = 0.55
		spin.add_child(mi)
		var band := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(0.57, 0.08, 0.44)
		band.mesh = bb
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = accent
		bmat.emission_enabled = true
		bmat.emission = accent
		bmat.emission_energy_multiplier = 1.6
		band.material_override = bmat
		band.position.y = 0.62
		mi.add_child(band)

	# Glow ring on the ground.
	ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.52
	torus.outer_radius = 0.62
	torus.rings = 20
	torus.ring_segments = 6
	ring.mesh = torus
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = accent
	rm.emission_enabled = true
	rm.emission = accent
	rm.emission_energy_multiplier = 2.2
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color.a = 0.85
	ring.material_override = rm
	ring.position.y = 0.03
	ring.scale = Vector3.ONE * 0.9
	add_child(ring)

	# Thin vertical light shaft.
	beacon = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.035
	cyl.bottom_radius = 0.14
	cyl.height = 5.0
	cyl.radial_segments = 6
	cyl.rings = 1
	beacon.mesh = cyl
	var bmm := StandardMaterial3D.new()
	bmm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmm.albedo_color = Color(accent.r, accent.g, accent.b, 0.30)
	bmm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bmm.cull_mode = BaseMaterial3D.CULL_DISABLED
	beacon.material_override = bmm
	beacon.position.y = 2.5
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beacon)

	label = Label3D.new()
	label.text = display_name()
	label.font = load("res://assets/fonts/ui_bold.ttf")
	label.font_size = 64
	label.pixel_size = 0.0042
	label.modulate = accent
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.outline_size = 12
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.position.y = 1.55
	label.visible = false
	add_child(label)


func display_name() -> String:
	match kind:
		"weapon":
			return str(Weapons.def(item_id).get("name", item_id.to_upper()))
		"ammo":
			return "AMMO"
		"armor":
			return "ARMOR  +50"
		"med":
			return "MEDKIT"
		"gear":
			return "SUPPLY"
	return "LOOT"


func prompt_text() -> String:
	match kind:
		"weapon":
			return "[E]  PICK UP  " + display_name()
		"ammo":
			return "[E]  TAKE  %d ROUNDS" % (amount * 30)
		"armor":
			return "[E]  EQUIP ARMOR"
		"med":
			return "[E]  USE MEDKIT"
	return "[E]  TAKE"


func can_pickup(player: Player) -> bool:
	if taken:
		return false
	if kind == "weapon":
		return true
	if kind == "ammo":
		return player.has_gun()
	return true


func pickup(player: Player) -> bool:
	if taken:
		return false
	match kind:
		"weapon":
			player.give_weapon(item_id)
		"ammo":
			player.add_ammo(player.current_id(), amount * 30)
		"armor":
			player.add_armor(50.0)
		"med":
			player.heal(50.0)
		"gear":
			player.add_armor(25.0)
			player.heal(25.0)
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


func _process(delta: float) -> void:
	if taken:
		return
	spawn_time += delta
	var bob := sin(Time.get_ticks_msec() * 0.0022 + bob_phase) * 0.07
	spin.position.y = 0.55 + bob + 0.12
	if kind == "weapon":
		spin.rotation.y += delta * 1.05
	else:
		spin.rotation.y += delta * 0.5
	ring.scale = Vector3.ONE * (0.9 + sin(Time.get_ticks_msec() * 0.003 + bob_phase) * 0.10)
	beacon.rotation.y += delta * 0.6
