class_name Revenant
extends Bot
## A Revenant: a named champion who never left the island's old places. It
## holds an arena at a landmark and will not be drawn far from it.
##
##   - takes a fifth of the damage a soldier would, behind level 3 plate
##   - telegraphs its grenade volleys: red rings on the ground where they
##     will land, a moment before they come
##   - at half health it rages: faster to react, deadlier aim, and every armed
##     soldier nearby answers its call
##   - leashed: lure it too far and it turns back home, healing as it goes
##   - its fall tolls a bell across the island; it drops a fortune
##
## Revenants are not players: they do not count toward who is left alive.

const NAMES := [
	["MAELIS", "THE ASH WARDEN"], ["ORVEN", "THE HOLLOW KNIGHT"], ["SERA VANE", "THE GRAVE-SINGER"],
	["THRAIN", "THE IRON OATH"], ["KESSA", "THE PALE HUNTRESS"], ["DORIAN", "THE LAST CAPTAIN"],
	["VELKA", "WHO WALKS IN SMOKE"], ["ABBOT GREL", "THE UNBURIED"],
]
## Who each of them is, to look at (assets/characters/gobkit).
const G := "res://assets/characters/gobkit/"
const SKINS := {
	"MAELIS": G + "bloodiron/BloodironKnight.glb",
	"ORVEN": G + "medieval/HeavyWarrior.glb",
	"SERA VANE": G + "orcs/OrcWarShaman.glb",
	"THRAIN": G + "bloodiron/BloodironHalberdier.glb",
	"KESSA": G + "orcs/OrcLegionArcher.glb",
	"DORIAN": G + "orcs/OrcLegionCommander.glb",
	"VELKA": G + "bloodiron/OrcPyromancer.glb",
	"ABBOT GREL": G + "undead/TombMummy.glb",
	"MOURNE": G + "undead/CleaverButcher.glb",
	"ISOLDE": G + "undead/NightWitch.glb",
	"ELLAN": G + "undead/VampireCountess.glb",
	"MOIRA": G + "undead/VampireCountess.glb",
	"THE IRON SENTINEL": G + "orcs/OrcIronGuard.glb",
	"THE HOLLOW WARDEN": G + "bloodiron/BloodironShieldwall.glb",
	"THE UNKINDLED": G + "medieval/King.glb",
}
const DAMAGE_TAKEN := 0.2
const LEASH := 55.0
const REGEN := 6.0
const VOLLEY_EVERY := 13.0
const VOLLEY_WINDUP := 1.4

var title := ""
var arena := Vector3.ZERO
## Tuning a bigger boss can change.
var damage_taken := DAMAGE_TAKEN
var leash := LEASH
var volleys := true
var regen_rate := REGEN
var _away_t := 0.0
var glow_base := 0.9
var calm_before_regen := 5.0
var raged := false
## The motes that drift up round it (embers, ash, spores, feathers...).
var aura_color := Color(1.0, 0.32, 0.14)
var aura_size := 1.0
## Its silhouette: a ragged cloak (clear: none), and what crowns its head
## ("horns", "spikes", "great_horns" or "").
var cloak_color := Color(0.32, 0.04, 0.04)
var cloak_long := 1.0
var crown := "horns"
## Cracks of fire across the body and a burning heart (the giants).
var embers := false
var _volley_t := 6.0
var _calm := 0.0
var _rings: Array[Node3D] = []
var _glow: OmniLight3D


func setup_revenant(p_name: String, p_title: String, p_arena: Vector3, p_game: Node) -> void:
	setup(p_name, Vector2(p_arena.x, p_arena.z), p_game, randi())
	title = p_title
	arena = p_arena
	shoot_skill = 0.78
	reaction = 0.3
	sight = 140.0
	aggression = 0.85
	vest_level = 3
	armor = 100.0
	helmet_level = 3
	meds = 2
	grenades = 99
	state = State.GROUND
	landed = true
	set_meta("revenant", title)
	skin = SKINS.get(p_name, "")
	skin_height = 1.8


func display_name() -> String:
	return "%s, %s" % [bot_name, title]


func _ready() -> void:
	super._ready()
	visible = true
	roam_point = Vector2(arena.x, arena.z)
	calm_t = 0.0
	# Black and crimson, a little taller than a soldier, with a dull red glow.
	if body != null and body.model != null:
		body.model.scale = Vector3.ONE * 1.12
		if body.skin == null:
			for mi in body.model.find_children("*", "MeshInstance3D", true, false):
				var m := mi as MeshInstance3D
				var sm := m.get_surface_override_material(0)
				if sm is ShaderMaterial:
					var camo := (sm as ShaderMaterial).duplicate() as ShaderMaterial
					camo.set_shader_parameter("c_base", Color(0.12, 0.11, 0.11))
					camo.set_shader_parameter("c_a", Color(0.27, 0.035, 0.03))
					camo.set_shader_parameter("c_b", Color(0.19, 0.17, 0.16))
					camo.set_shader_parameter("c_c", Color(0.07, 0.065, 0.065))
					m.set_surface_override_material(0, camo)
			# Eyes that burn in the dark of the helmet.
			var k := 1.12
			var eyes := body._attach("Head", Transform3D(Basis.IDENTITY, Vector3(0, 1.62 * k, -0.11 * k)))
			var em := StandardMaterial3D.new()
			em.albedo_color = Color(1.0, 0.3, 0.12)
			em.emission_enabled = true
			em.emission = Color(1.0, 0.25, 0.08)
			em.emission_energy_multiplier = 9.0
			em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			for sx: float in [-0.04, 0.04]:
				var e := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.045, 0.018, 0.012)
				e.mesh = bm
				e.material_override = em
				e.position = Vector3(sx, 0, 0)
				e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				eyes.add_child(e)
			body.helmet.visible = true
			_add_menace(k)
	head_offset = 1.66
	if _cap != null:
		_cap.radius = 0.4
		_cap.height = 1.98
		_col.position.y = 0.99
	_add_aura()
	if body != null and body.skin_path != "":
		fit_hitbox.call_deferred()
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.25, 0.15)
	_glow.light_energy = 0.9
	_glow.omni_range = 3.5
	_glow.position = Vector3(0, 1.4, 0)
	_glow.shadow_enabled = false
	add_child(_glow)


## What makes it a boss at a glance: a ragged cloak streaming from its
## shoulders, horns or a crown of iron spikes.
func _add_menace(k: float) -> void:
	# No soldier's backpack on a boss.
	if not body._extra_kit.is_empty():
		var pack: Node3D = body._extra_kit[0]
		body._extra_kit.erase(pack)
		pack.queue_free()
	if cloak_color.a > 0.01:
		# (A body looks down its -Z: the cloak hangs at +Z, behind.)
		var back := body._attach("spine_03", Transform3D(Basis.IDENTITY, Vector3(0, 1.42 * k, 0.17 * k)))
		var cm := StandardMaterial3D.new()
		cm.albedo_color = cloak_color
		cm.roughness = 1.0
		cm.cull_mode = BaseMaterial3D.CULL_DISABLED
		var mi := MeshInstance3D.new()
		mi.mesh = _cloak_mesh(0.46 * k, 0.95 * k, 1.25 * k * cloak_long)
		mi.material_override = cm
		mi.rotation.x = -0.12
		back.add_child(mi)
	if embers:
		_add_embers(k)
	if crown == "hood":
		_add_hood(k)
		return
	if crown == "":
		return
	# Spiked pauldrons of black iron on both shoulders.
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.11, 0.1, 0.1)
	iron.metallic = 0.75
	iron.roughness = 0.38
	var spike_m := StandardMaterial3D.new()
	spike_m.albedo_color = Color(0.2, 0.18, 0.17)
	spike_m.metallic = 0.6
	spike_m.roughness = 0.45
	for side: float in [-1.0, 1.0]:
		var sh := body._attach("upperarm_l" if side < 0.0 else "upperarm_r", Transform3D(Basis.IDENTITY, Vector3(side * 0.19 * k, 1.47 * k, 0.0)))
		var pm := SphereMesh.new()
		pm.radius = 0.13 * k
		pm.height = 0.18 * k
		pm.is_hemisphere = true
		pm.radial_segments = 10
		pm.rings = 4
		var pd := MeshInstance3D.new()
		pd.mesh = pm
		pd.material_override = iron
		pd.scale = Vector3(1.15, 1.0, 1.25)
		pd.rotation.z = -side * 0.35
		sh.add_child(pd)
		for j in 3:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0
			cm.bottom_radius = 0.022 * k
			cm.height = (0.2 - 0.04 * absf(float(j) - 1.0)) * k
			cm.radial_segments = 5
			cm.rings = 1
			var sp := MeshInstance3D.new()
			sp.mesh = cm
			sp.material_override = spike_m
			sp.position = Vector3(side * 0.04 * k, 0.1 * k, (float(j) - 1.0) * 0.07 * k)
			sp.rotation = Vector3(0.0, 0.0, -side * 0.55)
			sh.add_child(sp)
	var head := body._attach("Head", Transform3D(Basis.IDENTITY, Vector3(0, 1.72 * k, -0.02 * k)))
	var bone := StandardMaterial3D.new()
	bone.albedo_color = Color(0.82, 0.78, 0.68) if crown != "spikes" else Color(0.14, 0.13, 0.13)
	bone.roughness = 0.6
	bone.metallic = 0.0 if crown != "spikes" else 0.7
	if crown == "spikes":
		# A ring of iron spikes all round the head, tallest at the brow.
		for i in 9:
			var a := TAU * float(i) / 9.0
			var sp := CylinderMesh.new()
			sp.top_radius = 0.0
			sp.bottom_radius = 0.025
			sp.height = 0.17 + 0.12 * (0.5 + 0.5 * cos(a))
			sp.radial_segments = 5
			var m := MeshInstance3D.new()
			m.mesh = sp
			m.material_override = bone
			m.position = Vector3(sin(a) * 0.13, 0.08, -cos(a) * 0.13 - 0.02)
			m.rotation = Vector3(-cos(a) * 0.35, 0.0, -sin(a) * 0.35)
			head.add_child(m)
		return
	var big := crown == "great_horns"
	for side: float in [-1.0, 1.0]:
		# Three segments that sweep out, up and forward: a horn.
		var root := Node3D.new()
		root.position = Vector3(side * 0.11, 0.06, 0.0)
		root.rotation = Vector3(-0.25, 0.0, side * -0.9)
		head.add_child(root)
		var seg_len := 0.15 * (1.6 if big else 1.0)
		var r := 0.05 * (1.5 if big else 1.0)
		var at := root
		for j in 3:
			var cy := CylinderMesh.new()
			cy.top_radius = r * (0.65 - 0.2 * float(j)) if j < 2 else 0.0
			cy.bottom_radius = r * (1.0 - 0.3 * float(j))
			cy.height = seg_len
			cy.radial_segments = 6
			var m := MeshInstance3D.new()
			m.mesh = cy
			m.material_override = bone
			m.position = Vector3(0, seg_len * 0.5, 0)
			at.add_child(m)
			var nxt := Node3D.new()
			nxt.position = Vector3(0, seg_len, 0)
			nxt.rotation = Vector3(-0.35, 0.0, side * 0.55)
			at.add_child(nxt)
			at = nxt


## A deep cowl over the head; nothing inside but two eyes.
func _add_hood(k: float) -> void:
	if body.helmet != null:
		body.helmet.visible = false
	var head := body._attach("Head", Transform3D(Basis.IDENTITY, Vector3(0, 1.66 * k, 0.03 * k)))
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = cloak_color.darkened(0.15)
	cloth.roughness = 1.0
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	var hm := CylinderMesh.new()
	hm.top_radius = 0.02
	hm.bottom_radius = 0.2 * k
	hm.height = 0.5 * k
	hm.radial_segments = 12
	hm.cap_top = false
	hm.cap_bottom = false
	var hood := MeshInstance3D.new()
	hood.mesh = hm
	hood.material_override = cloth
	hood.rotation.x = 0.22
	hood.position = Vector3(0, 0.02 * k, 0.02 * k)
	head.add_child(hood)
	# The dark inside the cowl, where a face should be.
	var void_m := StandardMaterial3D.new()
	void_m.albedo_color = Color(0.0, 0.0, 0.0)
	void_m.roughness = 1.0
	var vm := SphereMesh.new()
	vm.radius = 0.13 * k
	vm.height = 0.24 * k
	var vd := MeshInstance3D.new()
	vd.mesh = vm
	vd.material_override = void_m
	vd.position = Vector3(0, -0.04 * k, -0.06 * k)
	head.add_child(vd)
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.albedo_color = aura_color.lightened(0.2)
	em.emission_enabled = true
	em.emission = aura_color
	em.emission_energy_multiplier = 9.0
	for sx: float in [-0.045, 0.045]:
		var e := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.022 * k
		sm.height = 0.03 * k
		e.mesh = sm
		e.material_override = em
		e.position = Vector3(sx * k, -0.02 * k, -0.18 * k)
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		head.add_child(e)


## Cracks of fire across chest, arms and legs, and a heart that burns.
func _add_embers(k: float) -> void:
	var fire := StandardMaterial3D.new()
	fire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire.albedo_color = Color(1.0, 0.38, 0.08)
	fire.emission_enabled = true
	fire.emission = Color(1.0, 0.3, 0.05)
	fire.emission_energy_multiplier = 4.0
	var spots := [
		["spine_03", Vector3(0, 1.36, -0.15), 0.0, 0.16],
		["spine_03", Vector3(0.08, 1.28, -0.14), 0.7, 0.12],
		["spine_02", Vector3(-0.07, 1.15, -0.13), -0.6, 0.13],
		["spine_01", Vector3(0.05, 1.04, -0.12), 0.3, 0.1],
		["spine_03", Vector3(0.0, 1.32, 0.15), 0.2, 0.18],
		["upperarm_l", Vector3(-0.27, 1.38, -0.04), 1.2, 0.12],
		["upperarm_r", Vector3(0.27, 1.38, -0.04), -1.2, 0.12],
		["lowerarm_l", Vector3(-0.42, 1.2, -0.03), 1.0, 0.1],
		["lowerarm_r", Vector3(0.42, 1.2, -0.03), -1.0, 0.1],
		["thigh_l", Vector3(-0.11, 0.7, -0.09), 0.4, 0.14],
		["thigh_r", Vector3(0.11, 0.62, -0.09), -0.5, 0.14],
		["calf_l", Vector3(-0.11, 0.3, -0.07), 0.2, 0.11],
		["calf_r", Vector3(0.11, 0.35, -0.07), -0.3, 0.11],
	]
	for sp in spots:
		var at: Vector3 = sp[1]
		var holder := body._attach(str(sp[0]), Transform3D(Basis.IDENTITY, at * k))
		var bm := BoxMesh.new()
		bm.size = Vector3(0.018, float(sp[3]), 0.01) * k
		var c := MeshInstance3D.new()
		c.mesh = bm
		c.material_override = fire
		c.rotation.z = float(sp[2])
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(c)
		# A branch off each crack.
		var b2 := MeshInstance3D.new()
		var bm2 := BoxMesh.new()
		bm2.size = Vector3(0.014, float(sp[3]) * 0.55, 0.01) * k
		b2.mesh = bm2
		b2.material_override = fire
		b2.position = Vector3(0.02, float(sp[3]) * 0.2, 0.0) * k
		b2.rotation.z = float(sp[2]) - 0.8
		b2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(b2)
	# The heart: a coal showing through a split in its chest.
	var heart := body._attach("spine_03", Transform3D(Basis.IDENTITY, Vector3(0, 1.3, -0.13) * k))
	var hm := SphereMesh.new()
	hm.radius = 0.06 * k
	hm.height = 0.1 * k
	var h := MeshInstance3D.new()
	h.mesh = hm
	h.material_override = fire
	h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	heart.add_child(h)


## The hitbox fitted to the character as it stands: the posed model sliced
## into bands (legs, hips, chest and arms, shoulders and head), a box round
## each, so wherever you can see the body a hit lands, weapons included.
var _fit_shapes: Array[CollisionShape3D] = []
var _hurtbox: Hurtbox = null
const FIT_BANDS := [0.0, 0.28, 0.5, 0.72, 0.86, 1.0]


func fit_hitbox() -> void:
	# Let the clips put it in its idle pose first.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree() or body == null or body.skin == null:
		return
	for c in _fit_shapes:
		if is_instance_valid(c):
			c.queue_free()
	_fit_shapes.clear()
	if _hurtbox == null:
		_hurtbox = Hurtbox.new()
		_hurtbox.name = "Hurtbox"
		_hurtbox.owner_bot = self
		add_child(_hurtbox)
	var inv := global_transform.affine_inverse()
	var pts := PackedVector3Array()
	for n in body.skin.find_children("*", "MeshInstance3D", true, false):
		var faces := SoldierRig.posed_faces(n as MeshInstance3D)
		for i in range(0, faces.size(), 3):
			pts.append(inv * faces[i])
	if pts.size() < 12:
		return
	var lo := INF
	var hi := -INF
	for p in pts:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	var h := hi - lo
	if h < 0.3:
		return
	for bi in FIT_BANDS.size() - 1:
		var y0 := lo + h * float(FIT_BANDS[bi])
		var y1 := lo + h * float(FIT_BANDS[bi + 1])
		var mn := Vector3(INF, y0, INF)
		var mx := Vector3(-INF, y1, -INF)
		var any := false
		for p in pts:
			if p.y >= y0 and p.y <= y1:
				mn.x = minf(mn.x, p.x)
				mn.z = minf(mn.z, p.z)
				mx.x = maxf(mx.x, p.x)
				mx.z = maxf(mx.z, p.z)
				any = true
		if not any:
			continue
		var bx := BoxShape3D.new()
		# A little room for the clips moving the limbs about.
		bx.size = Vector3((mx.x - mn.x) * 1.08 + 0.06, y1 - y0, (mx.z - mn.z) * 1.08 + 0.06)
		var cs := CollisionShape3D.new()
		cs.shape = bx
		cs.position = Vector3((mn.x + mx.x) * 0.5, (y0 + y1) * 0.5, (mn.z + mx.z) * 0.5)
		_hurtbox.add_child(cs)
		_fit_shapes.append(cs)
	# The head is the top band of the body as it is built, not a soldier's.
	head_offset = lo + h * 0.8


## A cloak: wide at the hem, ragged along it.
static func _cloak_mesh(top_w: float, hem_w: float, length: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 10
	var top: Array[Vector3] = []
	var hem: Array[Vector3] = []
	for i in n + 1:
		var u := float(i) / float(n)
		# Curved round the shoulders, its edges wrapping forward at the sides.
		var wrap := (u * 2.0 - 1.0) * (u * 2.0 - 1.0)
		top.append(Vector3(lerpf(-top_w, top_w, u) * 0.5, 0.0, -wrap * 0.16))
		var rag := (0.18 if i % 2 == 0 else 0.0) * length + sin(u * 17.0) * 0.04 * length
		hem.append(Vector3(lerpf(-hem_w, hem_w, u) * 0.5, -length + rag, 0.12 * length - wrap * 0.22))
	for i in n:
		st.add_vertex(top[i])
		st.add_vertex(hem[i])
		st.add_vertex(top[i + 1])
		st.add_vertex(top[i + 1])
		st.add_vertex(hem[i])
		st.add_vertex(hem[i + 1])
	st.generate_normals()
	return st.commit()


static var _mote: Texture2D = null


## A soft round dot, shared by every aura.
static func _mote_tex() -> Texture2D:
	if _mote == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(0.5, 0.0)
		gt.width = 32
		gt.height = 32
		_mote = gt
	return _mote


## More of its body that bullets can find (wings, an arched neck, a bell):
## a shape on the same body, so a hit anywhere on it counts.
func add_hit_shape(shape: Shape3D, at: Vector3, rot := Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = at
	cs.rotation = rot
	add_child(cs)
	return cs


## Motes drifting up round a boss, always: you know one from a distance.
func _add_aura() -> void:
	var em := GPUParticles3D.new()
	em.name = "Aura"
	em.amount = 40
	em.lifetime = 2.4
	em.preprocess = 2.4
	em.visibility_aabb = AABB(Vector3(-4, -1, -4) * aura_size, Vector3(8, 9, 8) * aura_size)
	em.visibility_range_end = 140.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.8 * aura_size
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0, 0.35, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.0))
	grad.add_point(0.2, Color(1, 1, 1, 0.95))
	grad.set_color(1, Color(0.5, 0.5, 0.5, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	em.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.05, 0.05)
	# Round glowing motes in its own colour (not squares, not white).
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = aura_color
	mat.albedo_texture = _mote_tex()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.material = mat
	em.draw_pass_1 = qm
	em.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	em.position = Vector3(0, 1.0 * aura_size, 0)
	add_child(em)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not alive or puppet:
		return
	var here := Vector2(global_position.x, global_position.z)
	var home := Vector2(arena.x, arena.z)
	var storm: bool = game != null and game.zone != null and game.zone.is_outside(arena)
	# Leashed to its arena (unless the storm has taken it).
	if not storm and here.distance_to(home) > leash:
		enemy = null
		loot_target = null
		roam_point = home
		alert_timer = 0.0
		# Stranded (in the sea, down a cliff): it returns to its ground and
		# the fight starts over, as a boss does.
		_away_t += delta
		if _away_t > 12.0:
			_away_t = 0.0
			global_position = arena + Vector3.UP * 0.5
			velocity = Vector3.ZERO
			hp = 100.0
			if game != null and game.has_method("spawn_smoke"):
				game.spawn_smoke(arena + Vector3.UP, 1.5)
	else:
		_away_t = 0.0
	var fighting := enemy != null and is_instance_valid(enemy) and bool(enemy.get("alive"))
	_calm = 0.0 if fighting else _calm + delta
	if _calm > calm_before_regen and hp < 100.0 and not raged:
		hp = minf(100.0, hp + regen_rate * delta)
	# Lobs its volley where it saw you last, over walls if need be.
	if volleys and fighting and (enemy_visible() or _last_seen_t < 5.0):
		_volley_t -= delta
		if _volley_t <= 0.0:
			_volley_t = VOLLEY_EVERY * (0.7 if raged else 1.0)
			_volley((enemy as Node3D).global_position)
	_glow.light_energy = glow_base + (0.5 * glow_base if raged else 0.0) + sin(Time.get_ticks_msec() * 0.004) * 0.2 * glow_base


func _pick_roam_point() -> void:
	# Pace the arena.
	var a := randf() * TAU
	roam_point = Vector2(arena.x, arena.z) + Vector2(cos(a), sin(a)) * randf_range(4.0, 18.0)


func _find_loot() -> LootPickup:
	return null


func take_damage(amount: float, pos: Vector3 = Vector3.ZERO, headshot: bool = false, source: Node = null) -> bool:
	if puppet:
		return super.take_damage(amount, pos, headshot, source)
	# The storm burns it like anyone; bullets and blasts barely scratch it.
	var scaled := amount * (damage_taken if source != null else 1.0)
	if game != null and (source is Player or (source is Bot and (source as Bot).is_human)):
		scaled *= game.diff_boss()
	var killed := super.take_damage(scaled, pos, headshot, source)
	if alive and not raged and hp <= 50.0:
		_rage()
	return killed


func _rage() -> void:
	raged = true
	shoot_skill = 0.9
	reaction = 0.18
	aggression = 1.0
	_volley_t = 2.0
	# The pack answers.
	if game != null:
		var n := 0
		for b in game.bots:
			if n >= 5:
				break
			if is_instance_valid(b) and b != self and b.alive and b.armed and not b.is_human and not b.puppet \
					and b.state == State.GROUND and not (b is Revenant) and b.global_position.distance_to(global_position) < 300.0:
				b.roam_point = Vector2(global_position.x, global_position.z) + Vector2(randf_range(-12, 12), randf_range(-12, 12))
				b.heard_pos = global_position
				b.alert_timer = 15.0
				n += 1


## Three grenades at and around the target, with the landing spots marked
## on the ground first, so you can see it coming and move.
func _volley(at: Vector3) -> void:
	var spots: Array[Vector3] = []
	for i in 3:
		var off := Vector3.ZERO if i == 0 else Vector3(randf_range(-4.0, 4.0), 0, randf_range(-4.0, 4.0))
		var p: Vector3 = game.ground_at(at + off + Vector3.UP * 2.0)
		spots.append(p)
		_mark_ring(p)
	if game.has_method("play_sfx_at"):
		game.play_sfx_at("writ_fail", global_position, 1.0)
	await get_tree().create_timer(VOLLEY_WINDUP).timeout
	if not alive or not is_inside_tree():
		_clear_rings()
		return
	for p in spots:
		_throw_nade(p)
		_nade_cd = 0.0
		await get_tree().create_timer(0.18).timeout
		if not alive or not is_inside_tree():
			break
	await get_tree().create_timer(2.2).timeout
	_clear_rings()


func _mark_ring(p: Vector3) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.6
	tm.outer_radius = 3.0
	tm.rings = 24
	tm.ring_segments = 6
	ring.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.18, 0.1, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = false
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(1, 0.1, 1)
	game.add_child(ring)
	ring.global_position = p + Vector3.UP * 0.08
	_rings.append(ring)


func _clear_rings() -> void:
	for r in _rings:
		if is_instance_valid(r):
			r.queue_free()
	_rings.clear()


func _die(source: Node) -> void:
	_clear_rings()
	super._die(source)
