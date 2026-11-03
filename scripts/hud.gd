class_name HUD
extends CanvasLayer

signal play_pressed
signal resume_pressed
signal quit_pressed
signal settings_changed(sensitivity: float, volume: float)

# All HUD is constructed in code so the project stays scene-file free and the
# layout can respond to the viewport at runtime.

const ACCENT := Color(0.949, 0.639, 0.235)
const WHITE := Color(0.949, 0.957, 0.961)
const MUTED := Color(0.608, 0.639, 0.659)
const DIM := Color(0.42, 0.45, 0.47)
const DANGER := Color(0.886, 0.271, 0.235)
const ZONE_BLUE := Color(0.298, 0.553, 0.941)
const STORM := Color(0.62, 0.42, 1.0)
const PANEL := Color(0.043, 0.051, 0.059, 0.74)
const PANEL_SOLID := Color(0.043, 0.051, 0.059, 0.92)
const MAP_EXTENT := 450.0
const MINIMAP_VIEW := 140.0

var root: Control
var font_bold: Font
var font_body: Font
var font_mono: Font

var compass: Control
var crosshair: Control
var hitmarker: Control
var damage_ring: Control
var minimap: Control
var minimap_draw: Control
var vignette: Control
var progress: Control
var big_map: Control
var big_map_draw: Control
var scope: Control
var scoped := false

var lbl_alive: Label
var lbl_kills: Label
var lbl_zone_timer: Label
var lbl_zone_state: Label
var lbl_weapon: Label
var lbl_ammo: Label
var lbl_reserve: Label
var lbl_health: Label
var lbl_armor: Label
var health_fill: ColorRect
var armor_fill: ColorRect
var lbl_prompt: Label
var lbl_notice: Label
var lbl_spectate: Label
var lbl_big: Label
var killfeed_box: VBoxContainer
var slot_labels: Array[Label] = []
var lbl_meds: Label
var lbl_items: Label
var lbl_gear: Label
var boost_bg: ColorRect
var boost_fill: ColorRect
var menu: Control
var play_button: Button
var menu_seed: Label
var end_panel: Control
var end_title: Label
var end_sub: Label
var end_stats: Label
var end_hint: Label
var zone_panel: Control
var pause_panel: Control
var sens_slider: HSlider
var vol_slider: HSlider
var lbl_sens: Label
var lbl_vol: Label

var pause_allowed := false
var heading := 0.0
var damage_marks: Array = []
var spread := 10.0
var hit_t := 0.0
var hit_kill := false
var hit_head := false
var notice_t := 0.0
var big_t := 0.0
var minimap_tex: Texture2D
var pings: Array = []
var markers: Array = []
var zone_center := Vector2.ZERO
var zone_radius := 100.0
var next_center := Vector2.ZERO
var next_radius := 100.0
var player_pos := Vector3.ZERO
var plane_path: Array = []
var prompt_label := ""
var progress_text := ""
var progress_frac := -1.0
var low_hp := 0.0
var in_storm := false
var hurt_flash := 0.0
var _kills := 0


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	font_bold = load("res://assets/fonts/ui_bold.ttf")
	font_body = load("res://assets/fonts/ui.ttf")
	font_mono = load("res://assets/fonts/mono_bold.ttf")
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_vignette()
	_build_top()
	_build_crosshair()
	_build_bars()
	_build_weapon_panel()
	_build_minimap()
	_build_bottom_text()
	_build_big_map()
	_build_menu()
	_build_end()
	_build_pause()
	update_health(100, 0)
	update_weapon("", 0, 0)
	set_zone(0.0, 0.0, 0, false)
	set_alive(0, 0)
	set_gameplay_visible(false)


# ------------------------------------------------------------------ helpers --
func _lv(text: String, size: int, color: Color, bold := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_bold if bold else font_body)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _panel(alpha := 1.0) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var c := PANEL
	c.a *= alpha
	sb.bg_color = c
	sb.border_color = Color(1, 1, 1, 0.09)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 58 if primary else 46)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_font_override("font", font_bold)
	b.add_theme_font_size_override("font_size", 22 if primary else 16)
	var fg := Color(0.06, 0.06, 0.06) if primary else WHITE
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, fg)
	var sb := StyleBoxFlat.new()
	sb.bg_color = ACCENT if primary else Color(1, 1, 1, 0.08)
	sb.border_color = Color(1, 1, 1, 0.0 if primary else 0.16)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	b.add_theme_stylebox_override("normal", sb)
	var sbh := sb.duplicate()
	sbh.bg_color = ACCENT.lightened(0.16) if primary else Color(1, 1, 1, 0.16)
	b.add_theme_stylebox_override("hover", sbh)
	b.add_theme_stylebox_override("focus", sbh)
	var sbp := sb.duplicate()
	sbp.bg_color = ACCENT.darkened(0.18) if primary else Color(1, 1, 1, 0.22)
	b.add_theme_stylebox_override("pressed", sbp)
	return b


func _bar(height: float, color: Color) -> ColorRect:
	# A background strip with a fill child sized by anchors, so it is correct
	# before the first layout pass and when the window is resized.
	var bg := ColorRect.new()
	bg.color = Color(1, 1, 1, 0.08)
	bg.custom_minimum_size = Vector2(0, height)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := ColorRect.new()
	fill.color = color
	fill.anchor_left = 0.0
	fill.anchor_top = 0.0
	fill.anchor_bottom = 1.0
	fill.anchor_right = 1.0
	fill.offset_left = 0
	fill.offset_right = 0
	fill.offset_top = 0
	fill.offset_bottom = 0
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(fill)
	bg.set_meta("fill", fill)
	return bg


# ----------------------------------------------------------------- overlay --
var _hud_nodes: Array[Control] = []


func _build_vignette() -> void:
	vignette = Control.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.draw.connect(_draw_vignette)
	root.add_child(vignette)


func _build_top() -> void:
	compass = Control.new()
	compass.set_anchors_preset(Control.PRESET_TOP_WIDE)
	compass.offset_top = 8
	compass.offset_bottom = 46
	compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass.draw.connect(_draw_compass)
	root.add_child(compass)
	_hud_nodes.append(compass)

	zone_panel = _panel(0.85)
	zone_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	zone_panel.offset_left = -96
	zone_panel.offset_right = 96
	zone_panel.offset_top = 52
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_zone_state = _lv("ZONE HOLDING", 11, MUTED)
	lbl_zone_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_zone_timer = _lv("00:00", 26, WHITE)
	lbl_zone_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_zone_timer.add_theme_font_override("font", font_mono)
	vb.add_child(lbl_zone_state)
	vb.add_child(lbl_zone_timer)
	zone_panel.add_child(vb)
	root.add_child(zone_panel)
	_hud_nodes.append(zone_panel)

	lbl_kills = _lv("KILLS  0", 18, WHITE)
	lbl_kills.position = Vector2(28, 22)
	lbl_kills.size = Vector2(220, 24)
	root.add_child(lbl_kills)
	_hud_nodes.append(lbl_kills)

	lbl_alive = _lv("ALIVE  0", 22, WHITE)
	lbl_alive.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	lbl_alive.offset_left = -240
	lbl_alive.offset_right = -28
	lbl_alive.offset_top = 20
	lbl_alive.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(lbl_alive)
	_hud_nodes.append(lbl_alive)

	killfeed_box = VBoxContainer.new()
	killfeed_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	killfeed_box.offset_left = -440
	killfeed_box.offset_right = -28
	killfeed_box.offset_top = 56
	killfeed_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	killfeed_box.add_theme_constant_override("separation", 4)
	killfeed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(killfeed_box)


func _build_scope() -> void:
	scope = Control.new()
	scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scope.visible = false
	scope.draw.connect(_draw_scope)
	root.add_child(scope)


var scope_name := ""
var reddot := false


var scope_velocity := 700.0


func set_scope(v: bool, name: String = "", velocity: float = 700.0) -> void:
	if v == scoped and name == scope_name:
		return
	scoped = v
	scope_name = name
	scope_velocity = velocity
	scope.visible = v
	scope.queue_redraw()


func set_reddot(v: bool) -> void:
	if v == reddot:
		return
	reddot = v
	crosshair.queue_redraw()


func _draw_scope() -> void:
	var sz := scope.size
	var c := sz * 0.5
	var r := minf(sz.x, sz.y) * 0.46
	var black := Color(0, 0, 0, 1)
	# Mask everything outside the lens with a thick ring plus side bars.
	scope.draw_rect(Rect2(0, 0, c.x - r + 1, sz.y), black)
	scope.draw_rect(Rect2(c.x + r - 1, 0, sz.x - c.x - r + 1, sz.y), black)
	scope.draw_arc(c, r + 300.0, 0, TAU, 128, black, 602.0)
	scope.draw_arc(c, r, 0, TAU, 128, Color(0.05, 0.05, 0.05), 6.0)
	# Inner vignette.
	for i in 6:
		scope.draw_arc(c, r - 4.0 - i * 6.0, 0, TAU, 128, Color(0, 0, 0, 0.12 - i * 0.018), 6.0)
	# Reticle: thick posts, fine centre cross, a dot.
	var thin := Color(0.02, 0.02, 0.02, 0.95)
	scope.draw_line(Vector2(c.x - r, c.y), Vector2(c.x - r * 0.12, c.y), thin, 3.0)
	scope.draw_line(Vector2(c.x + r * 0.12, c.y), Vector2(c.x + r, c.y), thin, 3.0)
	scope.draw_line(Vector2(c.x, c.y + r * 0.12), Vector2(c.x, c.y + r), thin, 3.0)
	scope.draw_line(Vector2(c.x - r * 0.12, c.y), Vector2(c.x + r * 0.12, c.y), thin, 1.0)
	scope.draw_line(Vector2(c.x, c.y - r), Vector2(c.x, c.y + r * 0.12), thin, 1.0)
	scope.draw_circle(c, 1.6, Color(0.85, 0.12, 0.1))
	# Bullet-drop holdover marks: where the round lands at 100 m steps,
	# for this zoom and a typical rifle round.
	var zoom := float(Weapons.SCOPE_ZOOM.get(scope_name, 4.0))
	var fov := deg_to_rad(82.0 / zoom)
	var px_per_rad := (sz.y * 0.5) / tan(fov * 0.5)
	for i in range(1, 6):
		var dist := 100.0 * float(i)
		var tof := dist / scope_velocity
		var drop := 0.5 * Ballistics.GRAVITY * tof * tof
		var y := c.y + atan(drop / dist) * px_per_rad
		if y > c.y + r * 0.95:
			break
		var w := 10.0 if i % 2 == 0 else 6.0
		scope.draw_line(Vector2(c.x - w, y), Vector2(c.x + w, y), thin, 1.0)
		if i % 2 == 0 or zoom >= 6.0:
			scope.draw_string(font_mono, Vector2(c.x + w + 4, y + 4), "%d" % int(dist), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.05, 0.05, 0.05, 0.9))
	scope.draw_string(font_bold, Vector2(c.x - r * 0.62, c.y + r * 0.72), scope_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.05, 0.05, 0.05, 0.6))


func _build_crosshair() -> void:
	_build_scope()
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -60
	crosshair.offset_right = 60
	crosshair.offset_top = -60
	crosshair.offset_bottom = 60
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(_draw_crosshair)
	root.add_child(crosshair)
	_hud_nodes.append(crosshair)

	hitmarker = Control.new()
	hitmarker.set_anchors_preset(Control.PRESET_CENTER)
	hitmarker.offset_left = -40
	hitmarker.offset_right = 40
	hitmarker.offset_top = -40
	hitmarker.offset_bottom = 40
	hitmarker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hitmarker.draw.connect(_draw_hitmarker)
	root.add_child(hitmarker)

	damage_ring = Control.new()
	damage_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	damage_ring.draw.connect(_draw_damage)
	root.add_child(damage_ring)

	progress = Control.new()
	progress.set_anchors_preset(Control.PRESET_CENTER)
	progress.offset_left = -110
	progress.offset_right = 110
	progress.offset_top = 46
	progress.offset_bottom = 86
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress.draw.connect(_draw_progress)
	root.add_child(progress)


func _build_bars() -> void:
	var box := _panel()
	box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.offset_left = 28
	box.offset_top = -120
	box.offset_right = 348
	box.offset_bottom = -28
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var toprow := HBoxContainer.new()
	toprow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_health = _lv("100", 30, WHITE)
	lbl_health.add_theme_font_override("font", font_mono)
	var tag := _lv("  HP", 12, MUTED)
	lbl_armor = _lv("", 13, Color(0.55, 0.75, 0.95))
	lbl_armor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_armor.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	toprow.add_child(lbl_health)
	toprow.add_child(tag)
	toprow.add_child(lbl_armor)
	vb.add_child(toprow)

	var armor_bg := _bar(5, Color(0.42, 0.66, 0.95))
	armor_fill = armor_bg.get_meta("fill")
	vb.add_child(armor_bg)
	var hp_bg := _bar(9, Color(0.92, 0.93, 0.94))
	health_fill = hp_bg.get_meta("fill")
	vb.add_child(hp_bg)
	boost_bg = _bar(3, Color(0.45, 0.95, 0.55))
	boost_fill = boost_bg.get_meta("fill")
	boost_bg.visible = false
	vb.add_child(boost_bg)

	box.add_child(vb)
	root.add_child(box)
	_hud_nodes.append(box)

	lbl_gear = _lv("", 12, Color(0.55, 0.75, 0.95))
	lbl_gear.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	lbl_gear.offset_left = 30
	lbl_gear.offset_right = 600
	lbl_gear.offset_top = -144
	lbl_gear.offset_bottom = -126
	root.add_child(lbl_gear)
	_hud_nodes.append(lbl_gear)
	lbl_items = _lv("", 12, Color(0.92, 0.80, 0.70))
	lbl_items.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	lbl_items.offset_left = 30
	lbl_items.offset_right = 900
	lbl_items.offset_top = -164
	lbl_items.offset_bottom = -146
	root.add_child(lbl_items)
	_hud_nodes.append(lbl_items)


func _build_weapon_panel() -> void:
	var box := _panel()
	box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	box.offset_left = -330
	box.offset_right = -28
	box.offset_top = -132
	box.offset_bottom = -28
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var slots := HBoxContainer.new()
	slots.alignment = BoxContainer.ALIGNMENT_END
	slots.add_theme_constant_override("separation", 14)
	slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_meds = _lv("", 12, Color(0.95, 0.45, 0.45))
	slots.add_child(lbl_meds)
	for i in 2:
		var l := _lv("%d  —" % (i + 1), 12, DIM)
		slots.add_child(l)
		slot_labels.append(l)
	vb.add_child(slots)

	lbl_weapon = _lv("UNARMED", 13, ACCENT)
	lbl_weapon.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_ammo = _lv("0", 40, WHITE)
	lbl_ammo.add_theme_font_override("font", font_mono)
	lbl_reserve = _lv(" / 0", 16, MUTED)
	lbl_reserve.add_theme_font_override("font", font_mono)
	lbl_reserve.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(lbl_ammo)
	row.add_child(lbl_reserve)
	vb.add_child(lbl_weapon)
	vb.add_child(row)
	box.add_child(vb)
	root.add_child(box)
	_hud_nodes.append(box)


func _build_minimap() -> void:
	minimap = Control.new()
	minimap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	minimap.offset_left = -248
	minimap.offset_right = -28
	minimap.offset_top = -364
	minimap.offset_bottom = -144
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.clip_contents = true
	root.add_child(minimap)
	minimap_draw = Control.new()
	minimap_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	minimap_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_draw.draw.connect(_draw_minimap)
	minimap.add_child(minimap_draw)
	_hud_nodes.append(minimap)


func _build_bottom_text() -> void:
	lbl_prompt = _lv("", 16, WHITE)
	lbl_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	lbl_prompt.offset_left = -300
	lbl_prompt.offset_right = 300
	lbl_prompt.offset_top = -176
	lbl_prompt.offset_bottom = -150
	lbl_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(lbl_prompt)

	lbl_notice = _lv("", 15, ACCENT)
	lbl_notice.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	lbl_notice.offset_left = -400
	lbl_notice.offset_right = 400
	lbl_notice.offset_top = -214
	lbl_notice.offset_bottom = -188
	lbl_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(lbl_notice)

	lbl_big = _lv("", 30, WHITE)
	lbl_big.set_anchors_preset(Control.PRESET_CENTER)
	lbl_big.offset_left = -500
	lbl_big.offset_right = 500
	lbl_big.offset_top = -170
	lbl_big.offset_bottom = -126
	lbl_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(lbl_big)

	lbl_spectate = _lv("", 14, MUTED)
	lbl_spectate.set_anchors_preset(Control.PRESET_CENTER_TOP)
	lbl_spectate.offset_left = -400
	lbl_spectate.offset_right = 400
	lbl_spectate.offset_top = 118
	lbl_spectate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(lbl_spectate)


func _build_big_map() -> void:
	big_map = Control.new()
	big_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	big_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	big_map.visible = false
	root.add_child(big_map)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.01, 0.015, 0.02, 0.66)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	big_map.add_child(bg)
	big_map_draw = Control.new()
	big_map_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	big_map_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	big_map_draw.draw.connect(_draw_big_map)
	big_map.add_child(big_map_draw)


func _build_menu() -> void:
	menu = Control.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(menu)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.024, 0.028, 0.45)
	menu.add_child(bg)

	var side := ColorRect.new()
	side.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	side.offset_right = 760
	side.color = Color(0.02, 0.024, 0.028, 0.45)
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(side)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	col.offset_left = 96
	col.offset_right = 860
	col.offset_top = -250
	col.offset_bottom = 260
	col.add_theme_constant_override("separation", 10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	menu.add_child(col)

	var kicker := _lv("I S L A N D   D R O P   ·   2 0   P L A Y E R S", 12, ACCENT)
	col.add_child(kicker)

	var title := _lv("BLOCK ROYALE", 92, WHITE)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	col.add_child(title)

	var sub := _lv("JUMP  ·  LOOT  ·  SURVIVE", 18, MUTED, false)
	col.add_child(sub)
	col.add_child(_spacer(26))

	play_button = _button("P L A Y", true)
	play_button.pressed.connect(func(): play_pressed.emit())
	col.add_child(play_button)
	col.add_child(_spacer(18))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 4)
	for t in ["WASD  MOVE", "SHIFT  SPRINT", "C / CTRL  CROUCH", "LMB  FIRE", "RMB  AIM", "R  RELOAD",
			"E  PICK UP", "1 2 / Q  WEAPONS", "H  HEAL  (4 5 6)", "G  GRENADE", "M  MAP", "ESC  PAUSE"]:
		var l := _lv(t, 12, MUTED, false)
		grid.add_child(l)
	col.add_child(grid)

	menu_seed = _lv("", 11, DIM, false)
	col.add_child(menu_seed)

	var foot := _lv("SQUAD OF ONE  ·  NO FRIENDS  ·  NO MERCY", 11, DIM, false)
	foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot.offset_left = 96
	foot.offset_top = -52
	foot.offset_bottom = -28
	menu.add_child(foot)


func _build_end() -> void:
	end_panel = Control.new()
	end_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_panel.visible = false
	root.add_child(end_panel)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.01, 0.012, 0.014, 0.55)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_panel.add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.offset_left = -420
	col.offset_right = 420
	col.offset_top = -200
	col.offset_bottom = 220
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_panel.add_child(col)

	end_title = _lv("ELIMINATED", 64, DANGER)
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(end_title)
	end_sub = _lv("BY  UNKNOWN", 16, WHITE)
	end_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(end_sub)
	col.add_child(_spacer(18))
	end_stats = _lv("", 15, MUTED)
	end_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(end_stats)
	col.add_child(_spacer(24))
	end_hint = _lv("PRESS  SPACE  TO  REDEPLOY   ·   ESC  FOR  MENU", 13, ACCENT)
	end_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(end_hint)


func _build_pause() -> void:
	pause_panel = Control.new()
	pause_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_panel.visible = false
	root.add_child(pause_panel)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.01, 0.012, 0.014, 0.7)
	pause_panel.add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.offset_left = -170
	col.offset_right = 170
	col.offset_top = -200
	col.offset_bottom = 200
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	pause_panel.add_child(col)

	col.add_child(_lv("PAUSED", 44, WHITE))
	col.add_child(_spacer(8))

	lbl_sens = _lv("MOUSE SENSITIVITY", 12, MUTED)
	col.add_child(lbl_sens)
	sens_slider = HSlider.new()
	sens_slider.min_value = 0.2
	sens_slider.max_value = 3.0
	sens_slider.step = 0.05
	sens_slider.value = 1.0
	sens_slider.custom_minimum_size = Vector2(300, 22)
	sens_slider.value_changed.connect(func(_v): _settings_changed())
	col.add_child(sens_slider)

	lbl_vol = _lv("VOLUME", 12, MUTED)
	col.add_child(lbl_vol)
	vol_slider = HSlider.new()
	vol_slider.min_value = 0.0
	vol_slider.max_value = 1.0
	vol_slider.step = 0.05
	vol_slider.value = 0.8
	vol_slider.custom_minimum_size = Vector2(300, 22)
	vol_slider.value_changed.connect(func(_v): _settings_changed())
	col.add_child(vol_slider)
	col.add_child(_spacer(12))

	var resume := _button("RESUME", true)
	resume.pressed.connect(func(): resume_pressed.emit())
	col.add_child(resume)
	var quit := _button("LEAVE MATCH", false)
	quit.pressed.connect(func(): quit_pressed.emit())
	col.add_child(quit)
	var exit := _button("QUIT GAME", false)
	exit.pressed.connect(func(): get_tree().quit())
	col.add_child(exit)


func _settings_changed() -> void:
	lbl_sens.text = "MOUSE SENSITIVITY   %.2f" % sens_slider.value
	lbl_vol.text = "VOLUME   %d%%" % int(vol_slider.value * 100.0)
	settings_changed.emit(sens_slider.value, vol_slider.value)


func set_settings(sens: float, vol: float) -> void:
	sens_slider.set_value_no_signal(sens)
	vol_slider.set_value_no_signal(vol)
	lbl_sens.text = "MOUSE SENSITIVITY   %.2f" % sens
	lbl_vol.text = "VOLUME   %d%%" % int(vol * 100.0)


# --------------------------------------------------------------------- api --
func set_gameplay_visible(v: bool) -> void:
	for n in _hud_nodes:
		n.visible = v
	if not v:
		big_map.visible = false
		set_scope(false)
		lbl_prompt.text = ""
		lbl_big.text = ""
		progress_frac = -1.0


func set_crosshair_visible(v: bool) -> void:
	crosshair.visible = v or reddot


func show_pause(v: bool) -> void:
	pause_panel.visible = v
	if v:
		big_map.visible = false


func is_paused_open() -> bool:
	return pause_panel.visible


func toggle_map() -> void:
	big_map.visible = not big_map.visible


func update_health(hp: float, armor: float) -> void:
	if lbl_health == null:
		return
	lbl_health.text = "%d" % int(ceil(maxf(0.0, hp)))
	var low := hp <= 35.0
	lbl_health.add_theme_color_override("font_color", DANGER if low else WHITE)
	lbl_armor.text = ("ARMOR  %d" % int(ceil(armor))) if armor > 0.0 else ""
	health_fill.anchor_right = clampf(hp / 100.0, 0.0, 1.0)
	health_fill.color = DANGER if low else Color(0.92, 0.93, 0.94)
	armor_fill.anchor_right = clampf(armor / 100.0, 0.0, 1.0)
	armor_fill.visible = armor > 0.0
	low_hp = clampf((40.0 - hp) / 40.0, 0.0, 1.0)


func update_weapon(id: String, mag: int, reserve: int) -> void:
	if lbl_weapon == null:
		return
	if id == "" or not Weapons.DEFS.has(id):
		lbl_weapon.text = "UNARMED"
		lbl_weapon.add_theme_color_override("font_color", MUTED)
		lbl_ammo.text = "—"
		lbl_reserve.text = ""
		return
	var d: Dictionary = Weapons.def(id)
	lbl_weapon.text = str(d["name"])
	lbl_weapon.add_theme_color_override("font_color", Weapons.tier_color(id).lightened(0.15))
	lbl_ammo.text = "%d" % mag
	lbl_reserve.text = " / %d" % reserve
	lbl_ammo.add_theme_color_override("font_color", DANGER if mag <= int(d["mag"]) * 0.25 else WHITE)


func update_ammo(mag: int, reserve: int) -> void:
	if lbl_ammo != null:
		lbl_ammo.text = "%d" % mag
		lbl_reserve.text = " / %d" % reserve


func set_inventory(p: Player) -> void:
	for i in 2:
		var l := slot_labels[i]
		if i < p.loadout.size():
			var id: String = p.loadout[i]
			var att: Dictionary = p.attachments[i]
			var extras := ""
			if str(att.get("scope", "")) != "":
				extras += " " + str(att["scope"]).to_upper()
			if bool(att.get("extmag", false)):
				extras += " EXT"
			if bool(att.get("comp", false)):
				extras += " COMP"
			l.text = "%d  %s%s" % [i + 1, str(Weapons.def(id)["short"]), extras]
			var c := Weapons.tier_color(id)
			l.add_theme_color_override("font_color", c.lightened(0.2) if i == p.slot else Color(c.r, c.g, c.b, 0.5))
		else:
			l.text = "%d  —" % (i + 1)
			l.add_theme_color_override("font_color", DIM)
	lbl_meds.text = ""
	var parts: Array[String] = []
	if p.bandages > 0:
		parts.append("[4] BANDAGE ×%d" % p.bandages)
	if p.meds > 0:
		parts.append("[5] MEDKIT ×%d" % p.meds)
	if p.energy > 0:
		parts.append("[6] ENERGY ×%d" % p.energy)
	if p.grenades > 0:
		parts.append("[G] FRAG ×%d" % p.grenades)
	lbl_items.text = "     ".join(parts)
	var gear: Array[String] = []
	if p.helmet_level > 0:
		gear.append("HELMET LV%d" % p.helmet_level)
	if p.vest_level > 0:
		gear.append("VEST LV%d" % p.vest_level)
	lbl_gear.text = "   ·   ".join(gear)


func set_boost(v: float) -> void:
	boost_fill.anchor_right = clampf(v / 100.0, 0.0, 1.0)
	boost_bg.visible = v > 0.5


func set_progress(text: String, frac: float) -> void:
	if text == progress_text and absf(frac - progress_frac) < 0.002:
		return
	progress_text = text
	progress_frac = frac
	progress.queue_redraw()


func set_storm(v: bool) -> void:
	in_storm = v


func show_hitmarker(headshot: bool, killed: bool) -> void:
	hit_t = 0.24 if killed else 0.18
	hit_kill = killed
	hit_head = headshot
	hitmarker.queue_redraw()


func show_damage(dir: Vector3) -> void:
	var ang := atan2(dir.x, -dir.z)
	damage_marks.append({"a": ang, "t": 1.6})
	if damage_marks.size() > 6:
		damage_marks.pop_front()
	hurt_flash = 1.0


func set_zone(time_left: float, _radius: float, _phase: int, warning: bool, label := "") -> void:
	if lbl_zone_timer == null:
		return
	var t := maxf(0.0, time_left)
	var mins := int(t) / 60
	var secs := int(t) % 60
	lbl_zone_timer.text = "%02d:%02d" % [mins, secs]
	lbl_zone_timer.add_theme_color_override("font_color", DANGER if warning else WHITE)
	if label == "":
		label = "ZONE CLOSING" if warning else "ZONE HOLDING"
	lbl_zone_state.text = label
	lbl_zone_state.add_theme_color_override("font_color", DANGER if warning else MUTED)


func set_alive(count: int, _total: int) -> void:
	if lbl_alive != null:
		lbl_alive.text = "ALIVE  %d" % count
		lbl_kills.text = "KILLS  %d" % _kills


func set_kills(k: int) -> void:
	_kills = k
	if lbl_kills != null:
		lbl_kills.text = "KILLS  %d" % k


func killfeed(text: String, accent: Color) -> void:
	if killfeed_box == null:
		return
	var l := _lv(text, 13, accent)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	killfeed_box.add_child(l)
	while killfeed_box.get_child_count() > 6:
		var old := killfeed_box.get_child(0)
		killfeed_box.remove_child(old)
		old.queue_free()
	var tw := l.create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


func clear_killfeed() -> void:
	for c in killfeed_box.get_children():
		c.queue_free()


func show_notice(text: String, dur := 2.0) -> void:
	if lbl_notice == null:
		return
	lbl_notice.text = text
	lbl_notice.modulate.a = 1.0
	notice_t = dur


func show_big(text: String, color: Color, dur := 2.2) -> void:
	lbl_big.text = text
	lbl_big.add_theme_color_override("font_color", color)
	lbl_big.modulate.a = 1.0
	lbl_big.scale = Vector2.ONE
	lbl_big.pivot_offset = lbl_big.size * 0.5
	big_t = dur
	var tw := lbl_big.create_tween()
	lbl_big.scale = Vector2(1.25, 1.25)
	tw.tween_property(lbl_big, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func set_prompt(text: String) -> void:
	if text == prompt_label:
		return
	prompt_label = text
	if lbl_prompt != null:
		lbl_prompt.text = text


func set_spectate(text: String) -> void:
	lbl_spectate.text = text


func set_crosshair_spread(px: float) -> void:
	if absf(px - spread) < 0.05:
		return
	spread = px
	if crosshair != null:
		crosshair.queue_redraw()


func set_heading(deg: float) -> void:
	heading = deg
	if compass != null:
		compass.queue_redraw()


func set_minimap(tex: Texture2D) -> void:
	minimap_tex = tex


func set_plane_path(a: Vector3, b: Vector3) -> void:
	plane_path = [Vector2(a.x, a.z), Vector2(b.x, b.z)] if a != b else []


func update_minimap(p: Vector3, zc: Vector2, zr: float, nc: Vector2, nr: float, p_markers: Array) -> void:
	player_pos = p
	zone_center = zc
	zone_radius = zr
	next_center = nc
	next_radius = nr
	markers = p_markers


func add_ping(pos: Vector3) -> void:
	pings.append({"p": Vector2(pos.x, pos.z), "t": 2.2})
	if pings.size() > 24:
		pings.pop_front()


func show_menu(seed_text: String) -> void:
	menu.visible = true
	end_panel.visible = false
	pause_panel.visible = false
	set_gameplay_visible(false)
	lbl_spectate.text = ""
	if menu_seed != null:
		menu_seed.text = seed_text


func hide_menu() -> void:
	menu.visible = false


func show_death(killer: String, placement: int, stats: Dictionary) -> void:
	end_panel.visible = true
	set_gameplay_visible(false)
	end_title.text = "ELIMINATED"
	end_title.add_theme_color_override("font_color", DANGER)
	end_sub.text = "#%d   ·   KILLED BY  %s" % [placement, killer.to_upper()]
	end_stats.text = _stats_text(stats)
	end_hint.text = "SPACE  REDEPLOY      ·      ESC  MAIN MENU"
	end_hint.add_theme_color_override("font_color", ACCENT)


func show_victory(stats: Dictionary) -> void:
	end_panel.visible = true
	set_gameplay_visible(false)
	end_title.text = "WINNER WINNER"
	end_title.add_theme_color_override("font_color", ACCENT)
	end_sub.text = "#1   ·   LAST ONE STANDING"
	end_stats.text = _stats_text(stats)
	end_hint.text = "SPACE  PLAY AGAIN      ·      ESC  MAIN MENU"
	end_hint.add_theme_color_override("font_color", WHITE)


func _stats_text(s: Dictionary) -> String:
	var t := int(s.get("time", 0))
	return "KILLS  %d        DAMAGE  %d        ACCURACY  %d%%        SURVIVED  %d:%02d" % [
		int(s.get("kills", 0)), int(s.get("damage", 0)), int(s.get("accuracy", 0)), t / 60, t % 60]


func hide_end() -> void:
	end_panel.visible = false


# ------------------------------------------------------------------- input --
func _unhandled_input(event: InputEvent) -> void:
	if not pause_allowed:
		return
	if event.is_action_pressed("pause"):
		if pause_panel.visible:
			resume_pressed.emit()
		else:
			show_pause(true)
			get_tree().paused = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map") and not pause_panel.visible:
		toggle_map()
		get_viewport().set_input_as_handled()


# -------------------------------------------------------------------- draw --
func _process(delta: float) -> void:
	if hit_t > 0.0:
		hit_t = maxf(0.0, hit_t - delta)
		hitmarker.queue_redraw()
	if notice_t > 0.0:
		notice_t = maxf(0.0, notice_t - delta)
		lbl_notice.modulate.a = clampf(notice_t / 0.4, 0.0, 1.0)
	if big_t > 0.0:
		big_t = maxf(0.0, big_t - delta)
		lbl_big.modulate.a = clampf(big_t / 0.5, 0.0, 1.0)
	hurt_flash = maxf(0.0, hurt_flash - delta * 2.5)
	for m in damage_marks:
		m["t"] = float(m["t"]) - delta
	damage_marks = damage_marks.filter(func(m): return float(m["t"]) > 0.0)
	for p in pings:
		p["t"] = float(p["t"]) - delta
	pings = pings.filter(func(p): return float(p["t"]) > 0.0)
	damage_ring.queue_redraw()
	vignette.queue_redraw()
	if minimap.visible:
		minimap_draw.queue_redraw()
	if big_map.visible:
		big_map_draw.queue_redraw()


func _draw_vignette() -> void:
	var sz := vignette.size
	var storm_a := 0.0
	if in_storm:
		storm_a = 0.20 + sin(Time.get_ticks_msec() * 0.004) * 0.04
	if storm_a > 0.0:
		vignette.draw_rect(Rect2(Vector2.ZERO, sz), Color(STORM.r * 0.6, STORM.g * 0.4, STORM.b * 0.8, storm_a))
	var red := maxf(low_hp * (0.55 + sin(Time.get_ticks_msec() * 0.006) * 0.12), hurt_flash * 0.45)
	if red <= 0.01:
		return
	# Edge-only red: four gradient strips.
	var steps := 10
	var depth := minf(sz.x, sz.y) * 0.22
	for i in steps:
		var f := float(i) / float(steps)
		var a := red * (1.0 - f) * 0.16
		var c := Color(0.55, 0.0, 0.0, a)
		var d := depth * f
		var w := depth / float(steps) + 1.0
		vignette.draw_rect(Rect2(0, d, sz.x, w), c)
		vignette.draw_rect(Rect2(0, sz.y - d - w, sz.x, w), c)
		vignette.draw_rect(Rect2(d, 0, w, sz.y), c)
		vignette.draw_rect(Rect2(sz.x - d - w, 0, w, sz.y), c)


func _draw_compass() -> void:
	var w := compass.size.x
	var cx := w * 0.5
	var y := 14.0
	var half := 160.0
	compass.draw_rect(Rect2(cx - half, y + 16, half * 2.0, 1.0), Color(1, 1, 1, 0.10))
	var names := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}
	for d in range(0, 360, 15):
		var rel := wrapf(float(d) - heading, -180.0, 180.0)
		if absf(rel) > 62.0:
			continue
		var x := cx + rel / 62.0 * half
		var major := d % 45 == 0
		var h := 12.0 if major else 6.0
		compass.draw_line(Vector2(x, y + 16 - h), Vector2(x, y + 16), Color(1, 1, 1, 0.30 if not major else 0.55), 1.0)
		if names.has(d):
			var txt: String = names[d]
			compass.draw_string(font_bold, Vector2(x - 6, y - 2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, WHITE if txt == "N" else MUTED)
	# Marker toward the safe zone when outside it.
	var to_safe := next_center - Vector2(player_pos.x, player_pos.z)
	if to_safe.length() > next_radius and next_radius > 0.0:
		var bearing := rad_to_deg(atan2(to_safe.x, -to_safe.y))
		var rel := wrapf(bearing - heading, -180.0, 180.0)
		var x := cx + clampf(rel, -62.0, 62.0) / 62.0 * half
		compass.draw_colored_polygon(PackedVector2Array([Vector2(x, y + 19), Vector2(x - 5, y + 27), Vector2(x + 5, y + 27)]), STORM.lightened(0.3))
	compass.draw_string(font_mono, Vector2(cx + half + 14, y + 14), "%03d" % int(wrapf(heading, 0.0, 360.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.45))


func _draw_crosshair() -> void:
	var c := Vector2(60, 60)
	if reddot:
		crosshair.draw_circle(c, 2.6, Color(1.0, 0.12, 0.08, 0.95))
		crosshair.draw_arc(c, 3.2, 0, TAU, 16, Color(1.0, 0.3, 0.2, 0.35), 1.0)
		return
	var gap := 4.0 + spread
	var ln := 7.0
	var col := Color(0.95, 0.96, 0.97, 0.85)
	var sh := Color(0, 0, 0, 0.55)
	for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var a: Vector2 = c + d * gap
		var b: Vector2 = c + d * (gap + ln)
		crosshair.draw_line(a + Vector2(1, 1), b + Vector2(1, 1), sh, 2.0)
		crosshair.draw_line(a, b, col, 1.6)
	crosshair.draw_circle(c, 1.15, Color(0.95, 0.96, 0.97, 0.55))


func _draw_hitmarker() -> void:
	if hit_t <= 0.0:
		return
	var a := clampf(hit_t / 0.18, 0.0, 1.0)
	var col := DANGER if hit_kill else Color(1, 1, 1, 0.95)
	if hit_head and not hit_kill:
		col = Color(1.0, 0.85, 0.35)
	col.a = a
	var c := Vector2(40, 40)
	var s := 1.3 if hit_kill else 1.0
	for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		hitmarker.draw_line(c + d * 7.0 * s, c + d * 15.0 * s, col, 2.4 if hit_kill else 2.0)


func _draw_progress() -> void:
	if progress_frac < 0.0:
		return
	var w := progress.size.x
	progress.draw_string(font_bold, Vector2(0, 14), progress_text, HORIZONTAL_ALIGNMENT_CENTER, w, 12, WHITE)
	progress.draw_rect(Rect2(0, 22, w, 5), Color(1, 1, 1, 0.15))
	progress.draw_rect(Rect2(0, 22, w * progress_frac, 5), ACCENT)


func _draw_damage() -> void:
	if damage_marks.is_empty():
		return
	var vp := damage_ring.size
	var c := vp * 0.5
	var r := minf(vp.x, vp.y) * 0.34
	for m in damage_marks:
		var life: float = clampf(float(m["t"]) / 1.6, 0.0, 1.0)
		var ang: float = float(m["a"]) - deg_to_rad(heading)
		var base := Vector2(sin(ang), -cos(ang))
		var col := Color(DANGER.r, DANGER.g, DANGER.b, life * 0.85)
		for i in range(3):
			var rr := r + i * 9.0
			var a0 := ang - 0.14
			var a1 := ang + 0.14
			var p0 := c + Vector2(sin(a0), -cos(a0)) * rr
			var p1 := c + Vector2(sin(a1), -cos(a1)) * rr
			damage_ring.draw_line(p0, p1, col, 3.0 - i * 0.6)
		var tip := c + base * (r - 14.0)
		damage_ring.draw_line(tip, tip + base * 9.0, col, 2.0)


func _map_style(ctrl: Control, r: Rect2) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.045, 0.85)
	sb.border_color = Color(1, 1, 1, 0.14)
	sb.set_border_width_all(1)
	ctrl.draw_style_box(sb, r)


## Draws the island inside `inner`, showing world rect [origin, origin + span].
func _draw_world(ctrl: Control, inner: Rect2, origin: Vector2, span: float, big: bool) -> void:
	var to_map := func(p: Vector2) -> Vector2:
		return inner.position + (p - origin) / span * inner.size.x
	# Terrain texture: map the world rect onto the texture's pixel space.
	if minimap_tex != null:
		var ts := minimap_tex.get_size()
		var src := Rect2((origin + Vector2(MAP_EXTENT, MAP_EXTENT)) / (MAP_EXTENT * 2.0) * ts.x, Vector2.ONE * span / (MAP_EXTENT * 2.0) * ts.x)
		ctrl.draw_rect(inner, Color(0.07, 0.18, 0.28))
		ctrl.draw_texture_rect_region(minimap_tex, inner, src, Color(1, 1, 1, 0.95))
	var scale := inner.size.x / span

	# Plane route.
	if plane_path.size() == 2:
		var a: Vector2 = to_map.call(plane_path[0])
		var b: Vector2 = to_map.call(plane_path[1])
		ctrl.draw_dashed_line(a, b, Color(1, 1, 1, 0.55), 2.0, 10.0)

	# Storm: current circle (purple) and next safe zone (white).
	if zone_radius > 0.5:
		var zc: Vector2 = to_map.call(zone_center)
		ctrl.draw_arc(zc, zone_radius * scale, 0, TAU, 96, Color(STORM.r, STORM.g, STORM.b, 0.95), 2.0)
	if next_radius > 0.5 and absf(next_radius - zone_radius) > 0.5:
		var nc: Vector2 = to_map.call(next_center)
		ctrl.draw_arc(nc, next_radius * scale, 0, TAU, 96, Color(1, 1, 1, 0.9), 1.5)

	# Markers (supply drops).
	for m in markers:
		var mp: Vector2 = to_map.call(Vector2(m.x, m.z))
		ctrl.draw_rect(Rect2(mp - Vector2(4, 4), Vector2(8, 8)), Color(0.95, 0.25, 0.2))
		ctrl.draw_rect(Rect2(mp - Vector2(4, 4), Vector2(8, 8)), Color(1, 1, 1, 0.9), false, 1.0)

	# Gunfire pings.
	for p in pings:
		var pp: Vector2 = to_map.call(p["p"])
		var life: float = clampf(float(p["t"]) / 2.2, 0.0, 1.0)
		ctrl.draw_arc(pp, 3.0 + (1.0 - life) * 7.0, 0, TAU, 16, Color(1.0, 0.35, 0.25, life), 1.5)

	# Player arrow.
	var me: Vector2 = to_map.call(Vector2(player_pos.x, player_pos.z))
	var ang := deg_to_rad(heading)
	var fwd := Vector2(sin(ang), -cos(ang))
	var right := Vector2(cos(ang), sin(ang))
	var k := 1.6 if big else 1.0
	var p0 := me + fwd * 7.0 * k
	var p1 := me - fwd * 4.0 * k - right * 4.0 * k
	var p2 := me - fwd * 4.0 * k + right * 4.0 * k
	ctrl.draw_colored_polygon(PackedVector2Array([p0, p1, p2]), ACCENT)
	ctrl.draw_polyline(PackedVector2Array([p0, p1, p2, p0]), Color(0, 0, 0, 0.6), 1.0)

	# Line to safety.
	if big and next_radius > 0.5:
		var nc: Vector2 = to_map.call(next_center)
		if me.distance_to(nc) > next_radius * scale:
			var edge := nc + (me - nc).normalized() * next_radius * scale
			ctrl.draw_dashed_line(me, edge, Color(1, 1, 1, 0.6), 1.5, 6.0)


func _draw_minimap() -> void:
	var r := Rect2(Vector2.ZERO, minimap_draw.size)
	_map_style(minimap_draw, r)
	var inner := r.grow(-2.0)
	var span := MINIMAP_VIEW * 2.0
	var origin := Vector2(player_pos.x, player_pos.z) - Vector2(span, span) * 0.5
	_draw_world(minimap_draw, inner, origin, span, false)
	minimap_draw.draw_rect(inner, Color(1, 1, 1, 0.14), false, 1.0)


func _draw_big_map() -> void:
	var vp := big_map_draw.size
	var side := minf(vp.x, vp.y) - 120.0
	var inner := Rect2((vp - Vector2(side, side)) * 0.5, Vector2(side, side))
	_map_style(big_map_draw, inner.grow(3.0))
	_draw_world(big_map_draw, inner, Vector2(-MAP_EXTENT, -MAP_EXTENT), MAP_EXTENT * 2.0, true)
	# Grid labels like a real map.
	var cells := 8
	for i in cells + 1:
		var f := float(i) / float(cells)
		var x := inner.position.x + inner.size.x * f
		var y := inner.position.y + inner.size.y * f
		big_map_draw.draw_line(Vector2(x, inner.position.y), Vector2(x, inner.end.y), Color(1, 1, 1, 0.06), 1.0)
		big_map_draw.draw_line(Vector2(inner.position.x, y), Vector2(inner.end.x, y), Color(1, 1, 1, 0.06), 1.0)
		if i < cells:
			big_map_draw.draw_string(font_bold, Vector2(x + inner.size.x / cells * 0.5 - 4, inner.position.y - 10), "ABCDEFGH"[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)
			big_map_draw.draw_string(font_bold, Vector2(inner.position.x - 18, y + inner.size.y / cells * 0.5 + 4), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)
	big_map_draw.draw_string(font_bold, Vector2(inner.position.x, inner.end.y + 26), "M  CLOSE MAP      ·      WHITE CIRCLE = NEXT SAFE ZONE      ·      RED RINGS = GUNFIRE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)
