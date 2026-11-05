class_name HUD
extends CanvasLayer

signal play_pressed
signal music_changed(menu_volume: float, match_volume: float)
signal music_skip
signal graphics_changed(quality: int)
signal chat_sent(text: String)
signal chat_closed
signal map_clicked(world: Vector2, button: int)
signal host_lan_pressed
signal join_lan_pressed
signal resume_pressed
signal quit_pressed
signal settings_changed(sensitivity: float, volume: float, fov: float, players: int)
signal loadout_changed(primary: String, secondary: String, optic: String, enabled: bool)

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
const MAP_EXTENT := Terrain.HALF
const MINIMAP_VIEW := 170.0

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
var kit_panel: PanelContainer
var lbl_cal: Label
var breath_val := 100.0
var breath_hold := false
var breath_show := false
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
var menu_card: VBoxContainer
var menu_kicker: Label
var menu_preview: GunPreview
var menu_loadout: Label
var menu_loadout_sub: Label
var loadout_screen: LoadoutScreen
var settings_from_menu := false
var _pause_resume: Button
var _pause_leave: Button
var _pause_title: Label
var _pause_bg: ColorRect
var fov_slider: HSlider
var lbl_fov: Label
var size_slider: HSlider
var lbl_size: Label
var sens_slider: HSlider
var music_menu_slider: HSlider
var lbl_gfx: Label
var gfx_button: Button
var gfx_quality := 2
var music_match_slider: HSlider
var lbl_music_menu: Label
var lbl_music_match: Label
var _now_playing: Label
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
var places: Array = []  # [name, Vector2, kind]
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
	_build_social()
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
	b.mouse_entered.connect(_hover_sound)
	return b


func _hover_sound() -> void:
	var g = get_parent()
	if g != null and g.get("sfx") != null:
		g.sfx.play_2d("ui_hover", -14.0, 0.05)


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


var ads_dot := false


func set_reddot(v: bool, iron: bool = false) -> void:
	if v == reddot and iron == ads_dot:
		return
	reddot = v
	ads_dot = iron
	crosshair.visible = crosshair.visible or v or iron
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
	var base_fov := 82.0
	var pf = get_parent().get("player")
	if pf != null:
		base_fov = float(pf.base_fov)
	var fov := deg_to_rad(base_fov / zoom)
	var px_per_rad := (sz.y * 0.5) / tan(fov * 0.5)
	var zero := 100.0
	var pl = get_parent().get("player")
	if pl != null:
		zero = float(pl.cur_zero())
	var zt := zero / scope_velocity
	var zero_ang := atan((0.5 * Ballistics.GRAVITY * zt * zt) / zero)
	# Breath meter under the lens.
	if breath_show:
		var bw := r * 0.5
		var by := c.y + r * 0.86
		scope.draw_rect(Rect2(c.x - bw * 0.5, by, bw, 3), Color(0, 0, 0, 0.35))
		scope.draw_rect(Rect2(c.x - bw * 0.5, by, bw * breath_val / 100.0, 3), Color(0.1, 0.1, 0.1, 0.85) if not breath_hold else Color(0.15, 0.4, 0.75, 0.9))
		scope.draw_string(font_bold, Vector2(c.x - 100, by - 6), "HOLD SHIFT  —  STEADY", HORIZONTAL_ALIGNMENT_CENTER, 200, 10, Color(0.05, 0.05, 0.05, 0.55))
	scope.draw_string(font_mono, Vector2(c.x + r * 0.45, c.y + r * 0.72), "ZERO %d" % int(zero), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.05, 0.05, 0.05, 0.6))
	var last_mark := c.y
	var last_label := c.y
	for i in range(1, 7):
		var dist := 100.0 * float(i)
		if dist <= zero:
			continue
		var tof := dist / scope_velocity
		var drop := 0.5 * Ballistics.GRAVITY * tof * tof
		var y := c.y + (atan(drop / dist) - zero_ang) * px_per_rad
		if y > c.y + r * 0.95:
			break
		var w := 10.0 if i % 2 == 0 else 6.0
		if y - last_mark < 3.0:
			continue
		scope.draw_line(Vector2(c.x - w, y), Vector2(c.x + w, y), thin, 1.0)
		if y - last_label > 11.0:
			scope.draw_string(font_mono, Vector2(c.x + w + 4, y + 4), "%d" % int(dist), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.05, 0.05, 0.05, 0.9))
			last_label = y
		last_mark = y
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

	# Kit strip above the health box: worn gear, then consumables and ammo.
	var kit := _panel(0.85)
	kit.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	kit.offset_left = 28
	kit.offset_top = -176
	kit.offset_bottom = -126
	kit.grow_horizontal = Control.GROW_DIRECTION_END
	kit.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var kv := VBoxContainer.new()
	kv.add_theme_constant_override("separation", 2)
	kv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kit.add_child(kv)
	lbl_gear = _lv("", 12, Color(0.55, 0.75, 0.95))
	kv.add_child(lbl_gear)
	lbl_items = _lv("", 12, Color(0.92, 0.80, 0.70))
	kv.add_child(lbl_items)
	root.add_child(kit)
	_hud_nodes.append(kit)
	kit_panel = kit


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
	lbl_cal = _lv("", 11, DIM)
	lbl_cal.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(lbl_cal)
	row.add_child(_spacer(0))
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

	lbl_spectate = _lv("", 18, Color(1, 1, 1, 0.85))
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

	# Darken toward the left so the text reads over the flyover.
	var grad := TextureRect.new()
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.024, 0.03, 0.92))
	g.set_color(1, Color(0.02, 0.024, 0.03, 0.15))
	g.add_point(0.45, Color(0.02, 0.024, 0.03, 0.7))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	grad.texture = gt
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	menu.add_child(grad)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	col.offset_left = 96
	col.offset_right = 760
	col.offset_top = -300
	col.offset_bottom = 300
	col.add_theme_constant_override("separation", 10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	menu.add_child(col)

	menu_kicker = _lv("", 12, ACCENT)
	col.add_child(menu_kicker)
	var title := _lv("BLOCK ROYALE", 96, WHITE)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	title.add_theme_constant_override("shadow_offset_y", 4)
	col.add_child(title)
	col.add_child(_lv("DROP  ·  LOOT  ·  OUTLAST", 18, MUTED, false))
	col.add_child(_spacer(30))

	play_button = _button("P L A Y   S O L O", true)
	play_button.custom_minimum_size = Vector2(340, 64)
	play_button.pressed.connect(func(): play_pressed.emit())
	col.add_child(play_button)
	var lan := HBoxContainer.new()
	lan.add_theme_constant_override("separation", 8)
	var hb := _button("HOST LAN", false)
	hb.custom_minimum_size = Vector2(166, 48)
	hb.pressed.connect(func(): sfx_click(); host_lan_pressed.emit())
	lan.add_child(hb)
	var jb := _button("JOIN LAN", false)
	jb.custom_minimum_size = Vector2(166, 48)
	jb.pressed.connect(func(): sfx_click(); join_lan_pressed.emit())
	lan.add_child(jb)
	col.add_child(lan)
	for item in [["LOADOUT", "_open_loadout"], ["SETTINGS", "_open_settings"], ["QUIT", "_quit"]]:
		var b := _button(item[0], false)
		b.custom_minimum_size = Vector2(340, 48)
		b.pressed.connect(Callable(self, item[1]))
		col.add_child(b)
	col.add_child(_spacer(20))
	menu_seed = _lv("", 11, DIM, false)
	col.add_child(menu_seed)

	# Loadout card on the right: the gun you will drop with.
	menu_card = VBoxContainer.new()
	menu_card.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	menu_card.offset_left = -720
	menu_card.offset_right = -70
	menu_card.offset_top = -230
	menu_card.offset_bottom = 230
	menu_card.add_theme_constant_override("separation", 6)
	menu_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(menu_card)
	menu_card.add_child(_lv("YOUR LOADOUT", 12, ACCENT))
	menu_preview = GunPreview.new()
	menu_preview.custom_minimum_size = Vector2(650, 300)
	menu_card.add_child(menu_preview)
	menu_loadout = _lv("", 22, WHITE)
	menu_card.add_child(menu_loadout)
	menu_loadout_sub = _lv("", 13, MUTED, false)
	menu_card.add_child(menu_loadout_sub)

	var foot := _lv("WASD MOVE · SHIFT SPRINT · C CROUCH · RMB AIM · R RELOAD · F PICK UP · Q/E LEAN · B FIRE MODE · G GRENADE · H HEAL · M MAP", 11, DIM, false)
	foot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	foot.offset_left = 96
	foot.offset_top = -48
	foot.offset_bottom = -26
	menu.add_child(foot)

	loadout_screen = LoadoutScreen.new()
	loadout_screen.setup(self)
	loadout_screen.visible = false
	loadout_screen.z_index = 20
	loadout_screen.changed.connect(func(p, s, o, e): loadout_changed.emit(p, s, o, e); _update_card(p, s, o, e))
	loadout_screen.closed.connect(func(): sfx_click(); loadout_screen.visible = false)
	root.add_child(loadout_screen)
	loadout_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func set_loadout(p: String, s: String, o: String, e: bool) -> void:
	loadout_screen.set_values(p, s, o, e)
	_update_card(p, s, o, e)


func _update_card(p: String, s: String, o: String, e: bool) -> void:
	menu_preview.show_gun(p)
	menu_loadout.text = "%s   +   %s" % [str(Weapons.def(p)["name"]), str(Weapons.def(s)["name"])]
	var optic := ("  ·  " + ("RED DOT" if o == "reddot" else o.to_upper())) if o != "" else ""
	menu_loadout_sub.text = ("DROPPING IN WITH THIS KIT" if e else "LOADOUT OFF  —  LOOT EVERYTHING") + optic


func _open_loadout() -> void:
	sfx_click()
	loadout_screen.visible = true


func _open_settings() -> void:
	sfx_click()
	settings_from_menu = true
	_pause_leave.visible = false
	_pause_resume.text = "BACK"
	show_pause(true)


func _quit() -> void:
	get_tree().quit()


func sfx_click() -> void:
	var g = get_parent()
	if g != null and g.get("sfx") != null:
		g.sfx.play_ui("ui_click", -8.0)


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
	end_stats = _lv("", 15, Color(1, 1, 1, 0.82))
	end_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(end_stats)
	col.add_child(_spacer(24))
	end_table = _lv("", 14, Color(1, 1, 1, 0.85))
	end_table.add_theme_font_override("font", font_mono)
	end_table.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(end_table)
	col.add_child(_spacer(14))
	end_hint = _lv("PRESS  SPACE  TO  REDEPLOY   ·   ESC  FOR  MENU", 13, ACCENT)
	end_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(end_hint)


func _build_pause() -> void:
	pause_panel = Control.new()
	pause_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_panel.visible = false
	pause_panel.z_index = 30
	root.add_child(pause_panel)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.01, 0.012, 0.014, 0.7)
	pause_panel.add_child(bg)
	_pause_bg = bg

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.offset_left = -170
	col.offset_right = 170
	col.offset_top = -300
	col.offset_bottom = 300
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 8)
	pause_panel.add_child(col)

	_pause_title = _lv("PAUSED", 44, WHITE)
	col.add_child(_pause_title)
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

	lbl_gfx = _lv("GRAPHICS", 12, MUTED)
	col.add_child(lbl_gfx)
	gfx_button = _button("HIGH", false)
	gfx_button.custom_minimum_size = Vector2(300, 36)
	gfx_button.add_theme_font_size_override("font_size", 14)
	gfx_button.pressed.connect(func():
		sfx_click()
		gfx_quality = (gfx_quality + 1) % 4
		_settings_labels()
		graphics_changed.emit(gfx_quality))
	col.add_child(gfx_button)

	lbl_music_menu = _lv("MENU MUSIC", 12, MUTED)
	col.add_child(lbl_music_menu)
	music_menu_slider = HSlider.new()
	music_menu_slider.min_value = 0.0
	music_menu_slider.max_value = 1.0
	music_menu_slider.step = 0.05
	music_menu_slider.value = 0.7
	music_menu_slider.custom_minimum_size = Vector2(300, 22)
	music_menu_slider.value_changed.connect(func(_v): _music_changed())
	col.add_child(music_menu_slider)
	lbl_music_match = _lv("MATCH MUSIC", 12, MUTED)
	col.add_child(lbl_music_match)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 8)
	music_match_slider = HSlider.new()
	music_match_slider.min_value = 0.0
	music_match_slider.max_value = 1.0
	music_match_slider.step = 0.05
	music_match_slider.value = 0.35
	music_match_slider.custom_minimum_size = Vector2(230, 22)
	music_match_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	music_match_slider.value_changed.connect(func(_v): _music_changed())
	mrow.add_child(music_match_slider)
	var skipb := _button("NEXT ▶", false)
	skipb.custom_minimum_size = Vector2(62, 30)
	skipb.add_theme_font_size_override("font_size", 11)
	skipb.pressed.connect(func(): sfx_click(); music_skip.emit())
	mrow.add_child(skipb)
	col.add_child(mrow)

	lbl_fov = _lv("FIELD OF VIEW", 12, MUTED)
	col.add_child(lbl_fov)
	fov_slider = HSlider.new()
	fov_slider.min_value = 70.0
	fov_slider.max_value = 100.0
	fov_slider.step = 1.0
	fov_slider.value = 82.0
	fov_slider.custom_minimum_size = Vector2(300, 22)
	fov_slider.value_changed.connect(func(_v): _settings_changed())
	col.add_child(fov_slider)

	lbl_size = _lv("MATCH SIZE", 12, MUTED)
	col.add_child(lbl_size)
	size_slider = HSlider.new()
	size_slider.min_value = 10
	size_slider.max_value = 100
	size_slider.step = 5
	size_slider.value = 50
	size_slider.custom_minimum_size = Vector2(300, 22)
	size_slider.value_changed.connect(func(_v): _settings_changed())
	col.add_child(size_slider)
	col.add_child(_spacer(12))

	var resume := _button("RESUME", true)
	resume.pressed.connect(_on_resume_button)
	col.add_child(resume)
	_pause_resume = resume
	var quit := _button("LEAVE MATCH", false)
	quit.pressed.connect(func(): quit_pressed.emit())
	col.add_child(quit)
	_pause_leave = quit
	var exit := _button("QUIT GAME", false)
	exit.pressed.connect(func(): get_tree().quit())
	col.add_child(exit)


func _on_resume_button() -> void:
	if settings_from_menu:
		sfx_click()
		settings_from_menu = false
		show_pause(false)
		_pause_leave.visible = true
		_pause_resume.text = "RESUME"
		return
	resume_pressed.emit()


func _settings_changed() -> void:
	_settings_labels()
	settings_changed.emit(sens_slider.value, vol_slider.value, fov_slider.value, int(size_slider.value))


func _music_changed() -> void:
	_settings_labels()
	music_changed.emit(music_menu_slider.value, music_match_slider.value)


func set_music(menu_v: float, match_v: float) -> void:
	music_menu_slider.set_value_no_signal(menu_v)
	music_match_slider.set_value_no_signal(match_v)
	_settings_labels()


## "Now playing" card that slides in for a few seconds.
func now_playing(title: String) -> void:
	if _now_playing == null:
		_now_playing = _lv("", 13, WHITE)
		_now_playing.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		_now_playing.offset_left = -520
		_now_playing.offset_right = -28
		_now_playing.offset_top = -30
		_now_playing.offset_bottom = -10
		_now_playing.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_now_playing.z_index = 40
		root.add_child(_now_playing)
	_now_playing.text = "♪   %s   ·   BLOCK ROYALE OST" % title
	_now_playing.modulate.a = 0.0
	var tw := _now_playing.create_tween()
	tw.tween_property(_now_playing, "modulate:a", 1.0, 0.6)
	tw.tween_interval(4.5)
	tw.tween_property(_now_playing, "modulate:a", 0.0, 1.2)


func set_graphics(q: int) -> void:
	gfx_quality = q
	_settings_labels()


func _settings_labels() -> void:
	if gfx_button != null:
		var hint: String = ["  ·  FAST", "  ·  BALANCED", "  ·  SSIL · REFLECTIONS · VOLUMETRICS", "  ·  SDFGI RAY-MARCHED GI · RTX 2060+"][gfx_quality]
		gfx_button.text = "◀   %s%s   ▶" % [Graphics.NAMES[gfx_quality], hint]
	if lbl_music_menu != null:
		lbl_music_menu.text = "MENU MUSIC   %s" % ("OFF" if music_menu_slider.value <= 0.001 else "%d%%" % int(music_menu_slider.value * 100.0))
		lbl_music_match.text = "MATCH MUSIC   %s" % ("OFF" if music_match_slider.value <= 0.001 else "%d%%" % int(music_match_slider.value * 100.0))
	lbl_sens.text = "MOUSE SENSITIVITY   %.2f" % sens_slider.value
	lbl_vol.text = "VOLUME   %d%%" % int(vol_slider.value * 100.0)
	lbl_fov.text = "FIELD OF VIEW   %d°" % int(fov_slider.value)
	lbl_size.text = "MATCH SIZE   %d PLAYERS  (NEXT MATCH)" % int(size_slider.value)


func set_settings(sens: float, vol: float, fov: float = 82.0, players: int = 50) -> void:
	sens_slider.set_value_no_signal(sens)
	vol_slider.set_value_no_signal(vol)
	fov_slider.set_value_no_signal(fov)
	size_slider.set_value_no_signal(players)
	_settings_labels()


# --------------------------------------------------------------------- api --
func set_gameplay_visible(v: bool) -> void:
	for n in _hud_nodes:
		n.visible = v
	if not v:
		big_map.visible = false
		set_scope(false)
		set_reddot(false, false)
		lbl_prompt.text = ""
		prompt_label = ""
		lbl_big.text = ""
		progress_frac = -1.0
		progress_text = ""
		progress.queue_redraw()
		low_hp = 0.0
		hurt_flash = 0.0
		in_storm = false
		damage_marks.clear()
		pings.clear()
		vignette.queue_redraw()


func set_crosshair_visible(v: bool) -> void:
	crosshair.visible = v or reddot or ads_dot


func show_pause(v: bool) -> void:
	pause_panel.visible = v
	if _pause_title != null:
		_pause_title.text = "SETTINGS" if settings_from_menu else "PAUSED"
		# Over the main menu the panel needs a solid backdrop; in a match the
		# world can show through.
		_pause_bg.color.a = 0.95 if settings_from_menu else 0.7
	if v:
		big_map.visible = false


func is_paused_open() -> bool:
	return pause_panel.visible


var map_zoom := 1.0


func toggle_map() -> void:
	set_map_open(not big_map.visible)


## The full map frees the mouse so you can point at a landing spot or a
## place to mark; closing it hands the mouse back to the camera.
func set_map_open(v: bool) -> void:
	big_map.visible = v
	var g = get_parent()
	var in_match: bool = g != null and str(g.get("phase")) in ["plane", "playing"]
	if v:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		# Start the cursor on yourself.
		await get_tree().process_frame
		if big_map.visible and _bm_inner.size.x > 0.0:
			var me := _bm_inner.position + (Vector2(player_pos.x, player_pos.z) - _bm_origin) / _bm_span * _bm_inner.size.x
			get_viewport().warp_mouse(me.clamp(_bm_inner.position, _bm_inner.end))
	elif in_match and not pause_panel.visible and not chat_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func map_open() -> bool:
	return big_map != null and big_map.visible


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
		lbl_cal.text = ""
		lbl_weapon.add_theme_color_override("font_color", MUTED)
		lbl_ammo.text = "—"
		lbl_reserve.text = ""
		return
	var d: Dictionary = Weapons.def(id)
	var p = get_parent().get("player")
	var tags := ""
	if p != null and p.has_gun() and p.current_id() == id:
		if bool(d.get("auto", false)) and Weapons.cls(id) != "lmg":
			tags += "   " + ("SINGLE" if not p.is_auto() else "AUTO")
		if Weapons.zero_max(id) > 100:
			tags += "   %dM" % p.cur_zero()
	lbl_weapon.text = str(d["name"]) + tags
	lbl_cal.text = Weapons.caliber(id).to_upper()
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
	var ammo_parts: Array[String] = []
	for cal in ["9mm", "5.56", "7.62", "12ga"]:
		if p.ammo_of(cal) > 0:
			ammo_parts.append("%s %d" % [cal.to_upper(), p.ammo_of(cal)])
	if not ammo_parts.is_empty():
		parts.append("AMMO  " + "  ".join(ammo_parts))
	lbl_items.text = "     ".join(parts)
	var gear: Array[String] = []
	if p.helmet_level > 0:
		gear.append("HELMET LV%d" % p.helmet_level)
	if p.vest_level > 0:
		gear.append("VEST LV%d" % p.vest_level)
	lbl_gear.text = "   ·   ".join(gear)
	lbl_gear.visible = lbl_gear.text != ""
	lbl_items.visible = lbl_items.text != ""
	kit_panel.modulate.a = 1.0 if (lbl_gear.visible or lbl_items.visible) else 0.0


func set_breath(v: float, holding: bool, show: bool) -> void:
	breath_val = v
	breath_hold = holding
	breath_show = show
	if scoped:
		scope.queue_redraw()


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


func set_places(p: Array) -> void:
	places = p


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


var mates: Array = []
## Map / compass / world markers: {pos: Vector3, color: Color, name: String}.
var waypoints: Array = []
var _bm_inner := Rect2()
var _bm_origin := Vector2.ZERO
var _bm_span := 1.0
## Overhead labels for team mates: {pos: Vector3, name: String, color: Color}.
var tags: Array = []
var camera_3d: Camera3D
var social_layer: Control
var scoreboard: Panel
var _sb_title: Label
var _sb_rows: VBoxContainer
var _sb_footer: Label
var squad_draw: Control
var squad_rows: Array = []
var chat_box: VBoxContainer
var chat_edit: LineEdit
var chat_open := false
var lbl_ping: Label
var end_table: Label


func set_mates(list: Array) -> void:
	mates = list


func set_match_size(n: int) -> void:
	if menu_kicker != null:
		var src := "ISLAND DROP  ·  %d PLAYERS  ·  SOLO" % n
		var spaced := ""
		for i in src.length():
			spaced += src[i] + (" " if i < src.length() - 1 else "")
		menu_kicker.text = spaced


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
	loadout_screen.visible = false
	settings_from_menu = false
	_pause_leave.visible = true
	_pause_resume.text = "RESUME"


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
	end_title.text = "VICTORY"
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
	# Esc backs out of the armory or menu settings.
	if event.is_action_pressed("pause"):
		if loadout_screen != null and loadout_screen.visible:
			sfx_click()
			loadout_screen.visible = false
			get_viewport().set_input_as_handled()
			return
		if settings_from_menu and pause_panel.visible:
			_on_resume_button()
			get_viewport().set_input_as_handled()
			return
	if not pause_allowed:
		return
	if event.is_action_pressed("pause"):
		if pause_panel.visible:
			resume_pressed.emit()
		else:
			show_pause(true)
			# A LAN match keeps running for everyone else.
			var g = get_parent()
			var online: bool = g != null and g.get("net") != null and g.net.active
			if not online:
				get_tree().paused = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map") and not pause_panel.visible:
		toggle_map()
		get_viewport().set_input_as_handled()
	elif big_map.visible and event is InputEventMouseButton and event.pressed:
		# Wheel zooms the map around you instead of swapping guns.
		var mb := event as InputEventMouseButton
		if (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT) and _bm_inner.has_point(mb.position):
			var w := _bm_origin + (mb.position - _bm_inner.position) / _bm_inner.size.x * _bm_span
			map_clicked.emit(w, mb.button_index)
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			map_zoom = minf(6.0, map_zoom * 1.5)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			map_zoom = maxf(1.0, map_zoom / 1.5)
			get_viewport().set_input_as_handled()


# -------------------------------------------------------------------- draw --
func _process(delta: float) -> void:
	if Prof.on:
		var t0 := Time.get_ticks_usec()
		_process_body(delta)
		Prof.add("hud", Time.get_ticks_usec() - t0)
	else:
		_process_body(delta)


func _process_body(delta: float) -> void:
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
	if _scare_layer != null and _scare_layer.visible:
		_scare_layer.queue_redraw()


# ----------------------------------------------------------- the warden --
## Anti-cheat dread: darkness closing in from the edges (0..1), and the
## jumpscare's red-to-black flash (0..1). Drawn above everything.
var _dread := 0.0
var _scare := 0.0
var _scare_layer: Control
var _dread_tex: GradientTexture2D


func set_dread(k: float) -> void:
	_dread = clampf(k, 0.0, 1.0)
	_ensure_scare_layer()


func set_scare(k: float) -> void:
	_scare = clampf(k, 0.0, 1.0)
	_ensure_scare_layer()


func _ensure_scare_layer() -> void:
	if _scare_layer != null:
		_scare_layer.visible = _dread > 0.0 or _scare > 0.0
		_scare_layer.queue_redraw()
		return
	_scare_layer = Control.new()
	_scare_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scare_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scare_layer.draw.connect(_draw_scare)
	add_child(_scare_layer)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 0.75, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0.0), Color(0.02, 0, 0, 0.25), Color(0.02, 0, 0, 0.8), Color(0, 0, 0, 0.98)])
	_dread_tex = GradientTexture2D.new()
	_dread_tex.gradient = g
	_dread_tex.fill = GradientTexture2D.FILL_RADIAL
	_dread_tex.fill_from = Vector2(0.5, 0.5)
	_dread_tex.fill_to = Vector2(1.0, 0.5)
	_dread_tex.width = 256
	_dread_tex.height = 256


func _draw_scare() -> void:
	var sz := _scare_layer.size
	var t := Time.get_ticks_msec() * 0.001
	if _dread > 0.0:
		# The edges of the world go black and pulse with the heartbeat.
		var pulse := 1.0 + sin(t * 7.0) * 0.04 * _dread
		var grow := lerpf(1.6, 0.95, _dread) * pulse
		var r := Rect2(sz * 0.5 - sz * grow * 0.5, sz * grow)
		_scare_layer.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.05, 0.0, 0.01, 0.18 * _dread))
		_scare_layer.draw_texture_rect(_dread_tex, r, false, Color(1, 1, 1, _dread))
		# Outside the gradient rect: solid black so nothing leaks at the corners.
		if r.position.x > 0.0:
			_scare_layer.draw_rect(Rect2(0, 0, r.position.x + 1, sz.y), Color(0, 0, 0, _dread * 0.98))
			_scare_layer.draw_rect(Rect2(r.end.x - 1, 0, sz.x - r.end.x + 1, sz.y), Color(0, 0, 0, _dread * 0.98))
		if r.position.y > 0.0:
			_scare_layer.draw_rect(Rect2(0, 0, sz.x, r.position.y + 1), Color(0, 0, 0, _dread * 0.98))
			_scare_layer.draw_rect(Rect2(0, r.end.y - 1, sz.x, sz.y - r.end.y + 1), Color(0, 0, 0, _dread * 0.98))
	if _scare > 0.0:
		# Blood-red flash, torn scanlines, then black.
		_scare_layer.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.55, 0.0, 0.0, minf(0.75, _scare * 1.6)))
		for i in 18:
			var y := fmod(randf() * sz.y + t * 900.0, sz.y)
			_scare_layer.draw_rect(Rect2(0, y, sz.x, randf_range(2.0, 14.0)), Color(0, 0, 0, 0.55 * _scare))
		if _scare > 0.7:
			_scare_layer.draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, (_scare - 0.7) / 0.3))


## Swimming: underwater tint and the air left in your lungs.
var underwater := false
var _uw_vig: GradientTexture2D = null
var air_val := 100.0
var air_show := false


func set_swim(under: bool, air: float, show_air: bool) -> void:
	if under != underwater or show_air != air_show or absf(air - air_val) > 0.5:
		underwater = under
		air_val = air
		air_show = show_air
		vignette.queue_redraw()


func _draw_vignette() -> void:
	var sz := vignette.size
	if underwater:
		# Murky blue-green with darker edges and slow light ripples.
		vignette.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.03, 0.2, 0.26, 0.36))
		if _uw_vig == null:
			var g := Gradient.new()
			g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
			g.colors = PackedColorArray([Color(0, 0.04, 0.06, 0.0), Color(0, 0.04, 0.06, 0.12), Color(0, 0.03, 0.05, 0.7)])
			_uw_vig = GradientTexture2D.new()
			_uw_vig.gradient = g
			_uw_vig.fill = GradientTexture2D.FILL_RADIAL
			_uw_vig.fill_from = Vector2(0.5, 0.5)
			_uw_vig.fill_to = Vector2(1.05, 0.5)
			_uw_vig.width = 256
			_uw_vig.height = 256
		vignette.draw_texture_rect(_uw_vig, Rect2(Vector2.ZERO, sz), false)
	if air_show:
		var bw := 220.0
		var bx := sz.x * 0.5 - bw * 0.5
		var by := sz.y * 0.7
		vignette.draw_rect(Rect2(bx - 2, by - 2, bw + 4, 10), Color(0, 0, 0, 0.55))
		var low := air_val < 30.0
		var col := Color(0.45, 0.85, 1.0, 0.95) if not low else Color(1.0, 0.35 + 0.25 * sin(Time.get_ticks_msec() * 0.012), 0.3, 0.95)
		vignette.draw_rect(Rect2(bx, by, bw * air_val / 100.0, 6), col)
		vignette.draw_string(ThemeDB.fallback_font, Vector2(bx, by - 6), "AIR", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.95, 1.0, 0.9))
	var storm_a := 0.0
	if in_storm:
		storm_a = 0.20 + sin(Time.get_ticks_msec() * 0.004) * 0.04
	if storm_a > 0.0:
		vignette.draw_rect(Rect2(Vector2.ZERO, sz), Color(STORM.r * 0.6, STORM.g * 0.4, STORM.b * 0.8, storm_a))
	var red := maxf(low_hp * (0.55 + sin(Time.get_ticks_msec() * 0.006) * 0.12), hurt_flash * 0.45)
	if red <= 0.01:
		return
	# Edge-only red: four gradient strips, strongest at the screen edge.
	var steps := 14
	var depth := minf(sz.x, sz.y) * 0.24
	for i in steps:
		var f := float(i) / float(steps)
		var a := red * pow(1.0 - f, 1.6) * 0.85
		var c := Color(0.62, 0.02, 0.02, a)
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
	for wp in waypoints:
		var to_w := Vector2(wp.pos.x, wp.pos.z) - Vector2(player_pos.x, player_pos.z)
		var bearing_w := rad_to_deg(atan2(to_w.x, -to_w.y))
		var rel_w := wrapf(bearing_w - heading, -180.0, 180.0)
		var xw := cx + clampf(rel_w, -62.0, 62.0) / 62.0 * half
		var col_w: Color = wp.color
		compass.draw_colored_polygon(PackedVector2Array([Vector2(xw, y + 6), Vector2(xw + 5, y + 11), Vector2(xw, y + 16), Vector2(xw - 5, y + 11)]), col_w)
	for m in mates:
		if m.size() > 3 and not bool(m[3]):
			continue
		var to_m: Vector2 = m[1] - Vector2(player_pos.x, player_pos.z)
		var rel_m := wrapf(rad_to_deg(atan2(to_m.x, -to_m.y)) - heading, -180.0, 180.0)
		if absf(rel_m) <= 62.0:
			var xm := cx + rel_m / 62.0 * half
			compass.draw_circle(Vector2(xm, y + 23), 3.0, m[2] if m.size() > 2 else Color(0.45, 0.95, 0.55))
	compass.draw_string(font_mono, Vector2(cx + half + 14, y + 14), "%03d" % int(wrapf(heading, 0.0, 360.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.45))


func _draw_crosshair() -> void:
	var c := Vector2(60, 60)
	if reddot:
		crosshair.draw_circle(c, 2.6, Color(1.0, 0.12, 0.08, 0.95))
		crosshair.draw_arc(c, 3.2, 0, TAU, 16, Color(1.0, 0.3, 0.2, 0.35), 1.0)
		return
	if ads_dot:
		crosshair.draw_circle(c, 2.2, Color(0, 0, 0, 0.6))
		crosshair.draw_circle(c, 1.4, Color(1, 1, 1, 0.95))
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
		var seg := _clip_segment(to_map.call(plane_path[0]), to_map.call(plane_path[1]), inner)
		if seg.size() == 2:
			ctrl.draw_dashed_line(seg[0], seg[1], Color(1, 1, 1, 0.55), 2.0, 10.0)

	# Storm: current circle (purple) and next safe zone (white).
	if zone_radius > 0.5:
		var zc: Vector2 = to_map.call(zone_center)
		ctrl.draw_arc(zc, zone_radius * scale, 0, TAU, 96, Color(STORM.r, STORM.g, STORM.b, 0.95), 2.0)
	if next_radius > 0.5 and absf(next_radius - zone_radius) > 0.5:
		var nc: Vector2 = to_map.call(next_center)
		ctrl.draw_arc(nc, next_radius * scale, 0, TAU, 96, Color(1, 1, 1, 0.9), 1.5)

	# Named places on the big map.
	if big:
		for pl in places:
			var mp: Vector2 = to_map.call(pl[1])
			var kind: String = pl[2]
			if kind == "town":
				ctrl.draw_string(font_bold, mp + Vector2(-60, -14), pl[0], HORIZONTAL_ALIGNMENT_CENTER, 120, 13, WHITE)
			elif kind == "tower":
				ctrl.draw_colored_polygon(PackedVector2Array([mp + Vector2(0, -7), mp + Vector2(-6, 5), mp + Vector2(6, 5)]), Color(0.95, 0.75, 0.35))
				ctrl.draw_string(font_bold, mp + Vector2(-50, 18), "LOOKOUT", HORIZONTAL_ALIGNMENT_CENTER, 100, 10, Color(0.95, 0.85, 0.6))
			elif kind == "landmark":
				ctrl.draw_circle(mp, 3.5, Color(1.0, 0.82, 0.42))
				ctrl.draw_string(font_bold, mp + Vector2(-80, -10), pl[0], HORIZONTAL_ALIGNMENT_CENTER, 160, 12, Color(1.0, 0.86, 0.55))
			elif kind == "ruin":
				ctrl.draw_rect(Rect2(mp - Vector2(3, 3), Vector2(6, 6)), Color(0.8, 0.78, 0.72), false, 1.5)
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

	# Squad mates.
	for m in mates:
		if m.size() > 3 and not bool(m[3]):
			continue
		var mp: Vector2 = to_map.call(m[1])
		if not inner.has_point(mp):
			continue
		var mc: Color = m[2] if m.size() > 2 else Color(0.45, 0.95, 0.55)
		ctrl.draw_circle(mp, 5.5 if big else 4.5, Color(0, 0, 0, 0.7))
		ctrl.draw_circle(mp, 4.2 if big else 3.4, mc)
		if big:
			ctrl.draw_string(font_bold, mp + Vector2(-60, -10), m[0], HORIZONTAL_ALIGNMENT_CENTER, 120, 11, mc)
	# Waypoints.
	for w in waypoints:
		var wp: Vector2 = to_map.call(Vector2(w.pos.x, w.pos.z))
		if not inner.has_point(wp):
			continue
		var wc: Color = w.color
		var k2 := 7.0 if big else 5.0
		ctrl.draw_colored_polygon(PackedVector2Array([wp + Vector2(0, -k2), wp + Vector2(k2, 0), wp + Vector2(0, k2), wp + Vector2(-k2, 0)]), Color(0, 0, 0, 0.6))
		ctrl.draw_colored_polygon(PackedVector2Array([wp + Vector2(0, -k2 + 1.5), wp + Vector2(k2 - 1.5, 0), wp + Vector2(0, k2 - 1.5), wp + Vector2(-k2 + 1.5, 0)]), wc)
	if big:
		_bm_inner = inner
		_bm_origin = origin
		_bm_span = span

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


## Liang-Barsky: the part of a-b inside r, or [] if none.
func _clip_segment(a: Vector2, b: Vector2, r: Rect2) -> Array:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	var p := [-d.x, d.x, -d.y, d.y]
	var q := [a.x - r.position.x, r.end.x - a.x, a.y - r.position.y, r.end.y - a.y]
	for i in 4:
		if absf(p[i]) < 1e-6:
			if q[i] < 0.0:
				return []
			continue
		var t: float = q[i] / p[i]
		if p[i] < 0.0:
			t0 = maxf(t0, t)
		else:
			t1 = minf(t1, t)
	if t0 > t1:
		return []
	return [a + d * t0, a + d * t1]


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
	var span := MAP_EXTENT * 2.0 / map_zoom
	var origin := Vector2(player_pos.x, player_pos.z) - Vector2(span, span) * 0.5
	origin = origin.clamp(Vector2(-MAP_EXTENT, -MAP_EXTENT), Vector2(MAP_EXTENT - span, MAP_EXTENT - span))
	if map_zoom <= 1.01:
		origin = Vector2(-MAP_EXTENT, -MAP_EXTENT)
	_draw_world(big_map_draw, inner, origin, span, true)
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
	big_map_draw.draw_string(font_bold, Vector2(inner.position.x, inner.end.y + 26), "M  CLOSE MAP      ·      LEFT CLICK  MARK      ·      RIGHT CLICK  REMOVE      ·      WHEEL  ZOOM      ·      WHITE CIRCLE = NEXT SAFE ZONE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)
	# Cursor readout: grid square and how far that is from you.
	var mp := big_map_draw.get_local_mouse_position()
	if inner.has_point(mp) and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		var w := origin + (mp - inner.position) / inner.size.x * span
		var d := Vector2(player_pos.x, player_pos.z).distance_to(w)
		var col := int(clampf((w.x + MAP_EXTENT) / (MAP_EXTENT * 2.0) * 8.0, 0.0, 7.0))
		var row := int(clampf((w.y + MAP_EXTENT) / (MAP_EXTENT * 2.0) * 8.0, 0.0, 7.0))
		var txt := "%s%d   ·   %s" % ["ABCDEFGH"[col], row + 1, ("%.1f KM" % (d / 1000.0)) if d >= 1000.0 else ("%d M" % int(d))]
		big_map_draw.draw_arc(mp, 9.0, 0.0, TAU, 24, Color(1, 1, 1, 0.85), 1.5, true)
		big_map_draw.draw_line(mp + Vector2(-15, 0), mp + Vector2(-5, 0), Color(1, 1, 1, 0.85), 1.5)
		big_map_draw.draw_line(mp + Vector2(5, 0), mp + Vector2(15, 0), Color(1, 1, 1, 0.85), 1.5)
		big_map_draw.draw_line(mp + Vector2(0, -15), mp + Vector2(0, -5), Color(1, 1, 1, 0.85), 1.5)
		big_map_draw.draw_line(mp + Vector2(0, 5), mp + Vector2(0, 15), Color(1, 1, 1, 0.85), 1.5)
		var tp := mp + Vector2(16, -14)
		big_map_draw.draw_rect(Rect2(tp + Vector2(-4, -14), Vector2(font_bold.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 8, 20)), Color(0, 0, 0, 0.6))
		big_map_draw.draw_string(font_bold, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, WHITE)



# ----------------------------------------------------------- multiplayer --
func _build_social() -> void:
	# Overhead tags and markers drawn over the 3D view.
	social_layer = Control.new()
	social_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	social_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	social_layer.draw.connect(_draw_social)
	root.add_child(social_layer)
	_hud_nodes.append(social_layer)

	lbl_ping = _lv("", 11, MUTED)
	lbl_ping.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	lbl_ping.offset_left = -240
	lbl_ping.offset_right = -28
	lbl_ping.offset_top = 46
	lbl_ping.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(lbl_ping)
	_hud_nodes.append(lbl_ping)

	# Squad health above the kit strip.
	squad_draw = Control.new()
	squad_draw.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	squad_draw.offset_left = 28
	squad_draw.offset_right = 348
	squad_draw.offset_top = -330
	squad_draw.offset_bottom = -186
	squad_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	squad_draw.draw.connect(_draw_squad)
	root.add_child(squad_draw)
	_hud_nodes.append(squad_draw)

	# Chat: recent lines fade out; Enter opens the input.
	chat_box = VBoxContainer.new()
	chat_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_box.offset_left = 28
	chat_box.offset_right = 560
	chat_box.offset_top = -560
	chat_box.offset_bottom = -390
	chat_box.alignment = BoxContainer.ALIGNMENT_END
	chat_box.add_theme_constant_override("separation", 2)
	chat_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(chat_box)
	chat_edit = LineEdit.new()
	chat_edit.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_edit.offset_left = 28
	chat_edit.offset_right = 560
	chat_edit.offset_top = -384
	chat_edit.offset_bottom = -348
	chat_edit.max_length = 140
	chat_edit.placeholder_text = "Say to everyone…   (Enter to send, Esc to close)"
	chat_edit.add_theme_font_override("font", font_body)
	chat_edit.add_theme_font_size_override("font_size", 15)
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(0.02, 0.025, 0.03, 0.85)
	csb.border_color = ACCENT
	csb.set_border_width_all(1)
	csb.content_margin_left = 10
	chat_edit.add_theme_stylebox_override("normal", csb)
	chat_edit.add_theme_stylebox_override("focus", csb)
	chat_edit.visible = false
	chat_edit.text_submitted.connect(func(t):
		if t.strip_edges() != "":
			chat_sent.emit(t)
		close_chat())
	chat_edit.gui_input.connect(func(e):
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			close_chat()
			chat_edit.accept_event())
	root.add_child(chat_edit)

	# Scoreboard (hold Tab).
	scoreboard = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.025, 0.03, 0.9)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	scoreboard.add_theme_stylebox_override("panel", sb)
	scoreboard.set_anchors_preset(Control.PRESET_CENTER)
	scoreboard.offset_left = -440
	scoreboard.offset_right = 440
	scoreboard.offset_top = -260
	scoreboard.offset_bottom = 260
	scoreboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scoreboard.visible = false
	root.add_child(scoreboard)
	var accent := ColorRect.new()
	accent.color = ACCENT
	accent.position = Vector2(0, 0)
	accent.size = Vector2(880, 3)
	scoreboard.add_child(accent)
	_sb_title = _lv("", 20, WHITE)
	_sb_title.position = Vector2(32, 22)
	scoreboard.add_child(_sb_title)
	var heads := [["PLAYER", 60], ["STATUS", 420], ["KILLS", 560], ["DAMAGE", 650], ["PING", 780]]
	for h in heads:
		var l := _lv(h[0], 11, DIM)
		l.position = Vector2(h[1], 72)
		scoreboard.add_child(l)
	_sb_rows = VBoxContainer.new()
	_sb_rows.position = Vector2(24, 96)
	_sb_rows.size = Vector2(832, 360)
	_sb_rows.add_theme_constant_override("separation", 4)
	scoreboard.add_child(_sb_rows)
	_sb_footer = _lv("", 13, MUTED)
	_sb_footer.position = Vector2(32, 474)
	_sb_footer.size = Vector2(816, 20)
	scoreboard.add_child(_sb_footer)


## unproject_position errors (every frame) for a point exactly on the
## camera plane; nudge such points just in front of it.
func _project(p: Vector3) -> Vector2:
	var fwd := -camera_3d.global_basis.z
	var rel := p - camera_3d.global_position
	var depth := rel.dot(fwd)
	if absf(depth) < 0.05:
		p += fwd * (0.05 - depth)
	return camera_3d.unproject_position(p)


func _draw_social() -> void:
	if camera_3d == null or not is_instance_valid(camera_3d) or not camera_3d.is_inside_tree():
		return
	var vp := social_layer.size
	var eye := camera_3d.global_position
	for t in tags:
		var p: Vector3 = t.pos
		if camera_3d.is_position_behind(p):
			continue
		var sp := _project(p)
		if sp.x < -50 or sp.y < -50 or sp.x > vp.x + 50 or sp.y > vp.y + 50:
			continue
		var d := eye.distance_to(p)
		var col: Color = t.color
		var a := clampf(1.2 - d / 900.0, 0.45, 1.0)
		social_layer.draw_colored_polygon(PackedVector2Array([sp + Vector2(-6, -4), sp + Vector2(6, -4), sp + Vector2(0, 4)]), Color(col.r, col.g, col.b, a))
		var label := "%s   %d m" % [t.name, int(d)] if d > 25.0 else str(t.name)
		var fs := 13
		var tw := font_bold.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		social_layer.draw_string(font_bold, sp + Vector2(-tw * 0.5 + 1, -9), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.7 * a))
		social_layer.draw_string(font_bold, sp + Vector2(-tw * 0.5, -10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.r, col.g, col.b, a))
	for w in waypoints:
		var p: Vector3 = w.pos + Vector3(0, 1.5, 0)
		var behind := camera_3d.is_position_behind(p)
		var sp := _project(p)
		if behind:
			sp = vp - sp
		# Pin to the screen edge when off-screen so you can always turn to it.
		var m := 40.0
		var clamped := Vector2(clampf(sp.x, m, vp.x - m), clampf(sp.y, m + 60.0, vp.y - m))
		if behind:
			clamped.y = vp.y - m
		var col: Color = w.color
		var k := 9.0
		social_layer.draw_colored_polygon(PackedVector2Array([clamped + Vector2(0, -k - 2), clamped + Vector2(k + 2, 0), clamped + Vector2(0, k + 2), clamped + Vector2(-k - 2, 0)]), Color(0, 0, 0, 0.55))
		social_layer.draw_colored_polygon(PackedVector2Array([clamped + Vector2(0, -k), clamped + Vector2(k, 0), clamped + Vector2(0, k), clamped + Vector2(-k, 0)]), col)
		var txt := "%d m" % int(eye.distance_to(w.pos))
		var tw2 := font_mono.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		social_layer.draw_string(font_mono, clamped + Vector2(-tw2 * 0.5 + 1, k + 17), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0, 0, 0, 0.7))
		social_layer.draw_string(font_mono, clamped + Vector2(-tw2 * 0.5, k + 16), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)


## Team mates: [name, Color, hp, alive, distance].
func set_squad_rows(rows: Array) -> void:
	squad_rows = rows
	squad_draw.visible = not rows.is_empty() and lbl_kills.visible
	squad_draw.queue_redraw()


func _draw_squad() -> void:
	var h := squad_draw.size.y
	var y := h
	for i in range(squad_rows.size() - 1, -1, -1):
		var r: Array = squad_rows[i]
		y -= 34.0
		var alive_r: bool = r[3]
		var col: Color = r[1]
		squad_draw.draw_rect(Rect2(0, y, 320, 30), Color(0.04, 0.05, 0.06, 0.72))
		squad_draw.draw_rect(Rect2(0, y, 4, 30), col if alive_r else Color(0.4, 0.4, 0.4))
		var nm: String = r[0]
		squad_draw.draw_string(font_bold, Vector2(14, y + 14), nm, HORIZONTAL_ALIGNMENT_LEFT, 170, 13, WHITE if alive_r else DIM)
		if alive_r:
			var hp := clampf(float(r[2]) / 100.0, 0.0, 1.0)
			squad_draw.draw_rect(Rect2(14, y + 20, 200, 4), Color(1, 1, 1, 0.12))
			var hc := Color(0.92, 0.93, 0.94) if hp > 0.5 else (Color(0.98, 0.78, 0.3) if hp > 0.25 else DANGER)
			squad_draw.draw_rect(Rect2(14, y + 20, 200 * hp, 4), hc)
			squad_draw.draw_string(font_mono, Vector2(230, y + 19), "%d m" % int(r[4]), HORIZONTAL_ALIGNMENT_RIGHT, 78, 11, MUTED)
		else:
			squad_draw.draw_string(font_bold, Vector2(230, y + 19), "OUT", HORIZONTAL_ALIGNMENT_RIGHT, 78, 11, DANGER)


func open_chat() -> void:
	chat_open = true
	chat_edit.visible = true
	chat_edit.text = ""
	chat_edit.grab_focus()
	for c in chat_box.get_children():
		c.modulate.a = 1.0


func close_chat() -> void:
	if not chat_open:
		return
	chat_open = false
	chat_edit.release_focus()
	chat_edit.visible = false
	chat_closed.emit()


func chat_add(name: String, col: Color, text: String, system := false) -> void:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.custom_minimum_size = Vector2(532, 0)
	l.add_theme_font_override("normal_font", font_body)
	l.add_theme_font_override("bold_font", font_bold)
	l.add_theme_font_size_override("normal_font_size", 15)
	l.add_theme_font_size_override("bold_font_size", 15)
	l.add_theme_color_override("default_color", Color(0.92, 0.93, 0.94))
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	var safe := text.replace("[", "[lb]")
	if system:
		l.text = "[color=#a8b0b5]%s[/color]" % safe
	else:
		l.text = "[b][color=#%s]%s[/color][/b]:  %s" % [col.to_html(false), name.replace("[", "[lb]"), safe]
	chat_box.add_child(l)
	while chat_box.get_child_count() > 7:
		var old := chat_box.get_child(0)
		chat_box.remove_child(old)
		old.queue_free()
	var tw := l.create_tween()
	tw.tween_interval(10.0)
	tw.tween_callback(func():
		if not chat_open:
			var t2 := l.create_tween()
			t2.tween_property(l, "modulate:a", 0.0, 1.0))


func clear_chat() -> void:
	for c in chat_box.get_children():
		c.queue_free()


## rows: {name, color, alive, kills, damage, ping, me}
func show_scoreboard(v: bool, title := "", rows: Array = [], footer := "") -> void:
	scoreboard.visible = v
	if not v:
		return
	_sb_title.text = title
	_sb_footer.text = footer
	for c in _sb_rows.get_children():
		c.queue_free()
	for r in rows:
		var row := Panel.new()
		row.custom_minimum_size = Vector2(832, 40)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.08) if bool(r.me) else Color(1, 1, 1, 0.03)
		sb.set_corner_radius_all(3)
		row.add_theme_stylebox_override("panel", sb)
		var strip := ColorRect.new()
		strip.color = r.color
		strip.size = Vector2(4, 40)
		row.add_child(strip)
		var alive_r: bool = r.alive
		var cols := [[str(r.name), 36, WHITE if alive_r else DIM, 16],
			["ALIVE" if alive_r else "ELIMINATED", 396, Color(0.45, 0.9, 0.5) if alive_r else DANGER, 12],
			[str(r.kills), 536, WHITE, 16], [str(int(r.damage)), 626, WHITE, 16],
			[("%d" % int(r.ping)) if int(r.ping) >= 0 else "—", 756, MUTED, 14]]
		for c in cols:
			var l := _lv(c[0], c[3], c[2])
			l.position = Vector2(c[1], 10 if c[3] >= 14 else 12)
			row.add_child(l)
		_sb_rows.add_child(row)


func set_ping_text(t: String, col: Color) -> void:
	lbl_ping.text = t
	lbl_ping.add_theme_color_override("font_color", col)



# ---------------------------------------------------------------- vehicle --
var _veh_panel: Control
var _veh_speed: Label
var _veh_unit: Label
var _veh_hp_fill: ColorRect
var _veh_hint: Label


func set_vehicle(v: bool, kmh := 0.0, hp_frac := 1.0, driver := true) -> void:
	if _veh_panel == null:
		if not v:
			return
		_veh_panel = Control.new()
		_veh_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_veh_panel.offset_left = -150
		_veh_panel.offset_right = 150
		_veh_panel.offset_top = -132
		_veh_panel.offset_bottom = -28
		_veh_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(_veh_panel)
		var bg := _panel(0.85)
		bg.position = Vector2(0, 0)
		bg.size = Vector2(300, 104)
		_veh_panel.add_child(bg)
		_veh_speed = _lv("0", 44, WHITE)
		_veh_speed.add_theme_font_override("font", font_mono)
		_veh_speed.position = Vector2(0, 4)
		_veh_speed.size = Vector2(210, 50)
		_veh_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_veh_panel.add_child(_veh_speed)
		_veh_unit = _lv("KM/H", 13, MUTED)
		_veh_unit.position = Vector2(218, 28)
		_veh_panel.add_child(_veh_unit)
		var bar := _bar(6, Color(0.95, 0.62, 0.22))
		bar.position = Vector2(20, 64)
		bar.size = Vector2(260, 6)
		_veh_hp_fill = bar.get_meta("fill")
		_veh_panel.add_child(bar)
		_veh_hint = _lv("", 11, MUTED)
		_veh_hint.position = Vector2(0, 78)
		_veh_hint.size = Vector2(300, 18)
		_veh_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_veh_panel.add_child(_veh_hint)
	_veh_panel.visible = v
	if not v:
		return
	_veh_speed.text = str(int(round(kmh)))
	_veh_hp_fill.anchor_right = clampf(hp_frac, 0.0, 1.0)
	_veh_hp_fill.color = Color(0.95, 0.62, 0.22) if hp_frac > 0.35 else DANGER
	_veh_hint.text = "SPACE  HANDBRAKE   ·   F  GET OUT" if driver else "PASSENGER   ·   F  GET OUT"
