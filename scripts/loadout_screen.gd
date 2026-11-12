class_name LoadoutScreen
extends Control

## Armory: pick a primary, a secondary and an optic, see the gun and its stats.

signal changed(primary: String, secondary: String, optic: String, enabled: bool)
signal closed

const PRIMARY_CLASSES := [["ASSAULT RIFLES", "ar"], ["SUBMACHINE GUNS", "smg"], ["SHOTGUNS", "shotgun"],
	["LIGHT MACHINE GUN", "lmg"], ["MARKSMAN", "dmr"], ["SNIPER RIFLES", "sniper"]]
const SECONDARY_CLASSES := [["PISTOLS", "pistol"], ["SUBMACHINE GUNS", "smg"], ["SHOTGUNS", "shotgun"]]
const OPTICS := [["IRON SIGHTS", ""], ["RED DOT", "reddot"], ["2X", "2x"], ["4X", "4x"], ["8X", "8x"]]

var hud: HUD
var primary := "carbine"
var secondary := "pistol"
var optic := ""
var enabled := true
var editing := "primary"

var preview: GunPreview
var list_box: VBoxContainer
var lbl_name: Label
var lbl_info: Label
var stat_bars: Dictionary = {}
var tab_primary: Button
var tab_secondary: Button
var optic_row: HBoxContainer
var toggle: CheckButton
var slot_primary: Label
var slot_secondary: Label


func setup(p_hud: HUD) -> void:
	hud = p_hud


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.035, 0.04, 1.0)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 56)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 18)
	margin.add_child(outer)

	# Header.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	outer.add_child(head)
	var title := hud._lv("ARMORY", 40, HUD.WHITE)
	head.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	toggle = CheckButton.new()
	toggle.text = "DROP IN WITH THIS LOADOUT"
	toggle.add_theme_font_override("font", hud.font_bold)
	toggle.add_theme_font_size_override("font_size", 14)
	toggle.button_pressed = enabled
	toggle.toggled.connect(func(v): enabled = v; _emit())
	head.add_child(toggle)
	var done := hud._button("DONE", true)
	done.custom_minimum_size = Vector2(160, 46)
	done.pressed.connect(func(): closed.emit())
	head.add_child(done)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 36)
	outer.add_child(body)

	# Left: slots + weapon list.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(380, 0)
	left.add_theme_constant_override("separation", 10)
	body.add_child(left)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	left.add_child(tabs)
	tab_primary = _tab("PRIMARY")
	tab_primary.pressed.connect(func(): editing = "primary"; _refresh())
	tabs.add_child(tab_primary)
	tab_secondary = _tab("SECONDARY")
	tab_secondary.pressed.connect(func(): editing = "secondary"; _refresh())
	tabs.add_child(tab_secondary)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 4)
	scroll.add_child(list_box)

	# Right: preview, name, stats, optic.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	body.add_child(right)
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 30)
	right.add_child(slots)
	slot_primary = hud._lv("", 13, HUD.MUTED)
	slots.add_child(slot_primary)
	slot_secondary = hud._lv("", 13, HUD.MUTED)
	slots.add_child(slot_secondary)

	preview = GunPreview.new()
	preview.custom_minimum_size = Vector2(0, 330)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(preview)

	lbl_name = hud._lv("", 34, HUD.WHITE)
	right.add_child(lbl_name)
	lbl_info = hud._lv("", 13, HUD.MUTED, false)
	right.add_child(lbl_info)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	right.add_child(grid)
	for stat in ["DAMAGE", "FIRE RATE", "RANGE", "STABILITY", "HANDLING"]:
		var l := hud._lv(stat, 12, HUD.MUTED)
		l.custom_minimum_size = Vector2(120, 0)
		grid.add_child(l)
		var bar := hud._bar(8, HUD.ACCENT)
		bar.custom_minimum_size = Vector2(420, 8)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(bar)
		stat_bars[stat] = bar.get_meta("fill")

	right.add_child(hud._spacer(6))
	right.add_child(hud._lv("OPTIC  (PRIMARY)", 12, HUD.MUTED))
	optic_row = HBoxContainer.new()
	optic_row.add_theme_constant_override("separation", 8)
	right.add_child(optic_row)
	_refresh()


func set_values(p: String, s: String, o: String, e: bool) -> void:
	primary = p if Weapons.DEFS.has(p) else "carbine"
	secondary = s if Weapons.DEFS.has(s) else "pistol"
	optic = o
	enabled = e
	if toggle != null:
		toggle.set_pressed_no_signal(e)
		_refresh()


func _tab(text: String) -> Button:
	var b := hud._button(text, false)
	b.custom_minimum_size = Vector2(150, 40)
	b.toggle_mode = true
	return b


func _refresh() -> void:
	if list_box == null:
		return
	tab_primary.set_pressed_no_signal(editing == "primary")
	tab_secondary.set_pressed_no_signal(editing == "secondary")
	for c in list_box.get_children():
		c.queue_free()
	var groups: Array = PRIMARY_CLASSES if editing == "primary" else SECONDARY_CLASSES
	var current := primary if editing == "primary" else secondary
	for g in groups:
		var header := hud._lv(g[0], 11, HUD.DIM)
		list_box.add_child(hud._spacer(4))
		list_box.add_child(header)
		for id in Weapons.ORDER:
			if Weapons.cls(id) != g[1]:
				continue
			var d := Weapons.def(id)
			var b := Button.new()
			b.text = "  %s" % str(d["name"])
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size = Vector2(360, 36)
			b.add_theme_font_override("font", hud.font_bold)
			b.add_theme_font_size_override("font_size", 15)
			var sb := StyleBoxFlat.new()
			var sel: bool = id == current
			sb.bg_color = Color(1, 1, 1, 0.12) if sel else Color(1, 1, 1, 0.03)
			sb.border_color = Weapons.tier_color(id) if sel else Color(1, 1, 1, 0.0)
			sb.border_width_left = 4
			b.add_theme_stylebox_override("normal", sb)
			var sbh := sb.duplicate()
			sbh.bg_color = Color(1, 1, 1, 0.16)
			b.add_theme_stylebox_override("hover", sbh)
			b.add_theme_stylebox_override("pressed", sbh)
			b.add_theme_stylebox_override("focus", sb)
			b.add_theme_color_override("font_color", HUD.WHITE if sel else HUD.MUTED)
			b.add_theme_color_override("font_hover_color", HUD.WHITE)
			b.pressed.connect(_pick.bind(id))
			list_box.add_child(b)
	_show(current)
	slot_primary.text = "PRIMARY   %s%s" % [str(Weapons.def(primary)["name"]), ("  +  " + ("RED DOT" if optic == "reddot" else optic.to_upper())) if optic != "" else ""]
	slot_secondary.text = "SECONDARY   %s" % str(Weapons.def(secondary)["name"])
	slot_primary.add_theme_color_override("font_color", HUD.WHITE if editing == "primary" else HUD.MUTED)
	slot_secondary.add_theme_color_override("font_color", HUD.WHITE if editing == "secondary" else HUD.MUTED)
	_build_optics()


func _pick(id: String) -> void:
	if editing == "primary":
		primary = id
		if optic != "" and not Weapons.scope_fits(id, optic):
			optic = ""
	else:
		secondary = id
	hud.sfx_click()
	_refresh()
	_emit()


func _show(id: String) -> void:
	var d := Weapons.def(id)
	# The primary carries the chosen sight in the preview as well.
	preview.show_gun(id, optic if id == primary else "")
	lbl_name.text = str(d["name"])
	lbl_name.add_theme_color_override("font_color", Weapons.tier_color(id).lightened(0.25))
	var mode := "AUTO" if bool(d["auto"]) else ("BOLT" if bool(d.get("bolt", false)) else "SEMI")
	var dmg := "%d" % int(d["damage"])
	if int(d["pellets"]) > 1:
		dmg = "%d × %d" % [int(d["damage"]), int(d["pellets"])]
	lbl_info.text = "%s   ·   %s   ·   %d ROUNDS   ·   %d RPM   ·   %s DAMAGE   ·   %d M/S" % [
		Weapons.caliber(id).to_upper(), mode, int(d["mag"]), int(d["rpm"]), dmg, int(d["velocity"])]
	var per_shot := float(d["damage"]) * float(d["pellets"])
	_set_bar("DAMAGE", per_shot / 130.0)
	_set_bar("FIRE RATE", float(d["rpm"]) / 900.0)
	_set_bar("RANGE", float(d["range"]) / 520.0)
	_set_bar("STABILITY", 1.0 - clampf(float(d["recoil"]) / 4.5, 0.0, 0.95))
	_set_bar("HANDLING", 1.0 - clampf((float(d["ads_time"]) - 0.12) / 0.25, 0.0, 0.95))


func _set_bar(stat: String, v: float) -> void:
	var fill: ColorRect = stat_bars[stat]
	var tw := fill.create_tween()
	tw.tween_property(fill, "anchor_right", clampf(v, 0.03, 1.0), 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _build_optics() -> void:
	for c in optic_row.get_children():
		c.queue_free()
	for o in OPTICS:
		var id: String = o[1]
		if id != "" and not Weapons.scope_fits(primary, id):
			continue
		var b := hud._button(o[0], false)
		b.custom_minimum_size = Vector2(110, 38)
		b.add_theme_font_size_override("font_size", 13)
		if id == optic or (id == "" and optic == "" and Weapons.builtin_scope(primary) == ""):
			var sb := StyleBoxFlat.new()
			sb.bg_color = HUD.ACCENT
			sb.set_corner_radius_all(2)
			b.add_theme_stylebox_override("normal", sb)
			b.add_theme_color_override("font_color", Color(0.06, 0.06, 0.06))
		b.pressed.connect(func(): optic = id; hud.sfx_click(); _refresh(); _emit())
		optic_row.add_child(b)
	if Weapons.builtin_scope(primary) != "" and optic == "":
		var l := hud._lv("   BUILT-IN %s SCOPE" % Weapons.builtin_scope(primary).to_upper(), 12, HUD.MUTED)
		optic_row.add_child(l)


func _emit() -> void:
	changed.emit(primary, secondary, optic, enabled)
