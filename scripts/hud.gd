class_name HUD
extends CanvasLayer

signal play_pressed

# All HUD is constructed in code so the project stays scene-file free and the
# layout can respond to the viewport at runtime.

const ACCENT := Color(0.949, 0.639, 0.235)
const WHITE := Color(0.949, 0.957, 0.961)
const MUTED := Color(0.608, 0.639, 0.659)
const DANGER := Color(0.886, 0.271, 0.235)
const ZONE_BLUE := Color(0.298, 0.553, 0.941)
const PANEL := Color(0.043, 0.051, 0.059, 0.74)
const PANEL_SOLID := Color(0.043, 0.051, 0.059, 0.92)

var root: Control
var font_bold: Font
var font_body: Font
var font_mono: Font

var compass: Control
var crosshair: Control
var hitmarker: Control
var damage_ring: Control
var minimap: Control

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
var killfeed_box: VBoxContainer
var menu: Control
var play_button: Button
var menu_seed: Label
var end_panel: Control
var end_title: Label
var end_sub: Label
var end_stats: Label
var end_hint: Label
var zone_panel: Control

var heading := 0.0
var damage_marks: Array = []
var spread := 10.0
var hit_t := 0.0
var hit_kill := false
var hit_head := false
var notice_t := 0.0
var shake := 0.0
var minimap_tex: Texture2D
var enemies_cache: Array = []
var zone_center := Vector2.ZERO
var zone_radius := 100.0
var player_pos := Vector3.ZERO
var prompt_label := ""


func _ready() -> void:
	layer = 10
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
	_build_menu()
	_build_end()
	_update_health(100, 0)
	update_weapon("", 0, 0)
	set_zone(0.0, 0.0, 0, false)
	set_alive(0, 0)


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
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
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


# ----------------------------------------------------------------- overlay --
func _build_vignette() -> void:
	var v := ColorRect.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.color = Color(0, 0, 0, 0.0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(v)


func _build_top() -> void:
	# Compass.
	compass = Control.new()
	compass.set_anchors_preset(Control.PRESET_TOP_WIDE)
	compass.offset_top = 8
	compass.offset_bottom = 46
	compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass.draw.connect(_draw_compass)
	root.add_child(compass)

	# Zone timer, top centre.
	zone_panel = _panel(0.85)
	zone_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	zone_panel.offset_left = -92
	zone_panel.offset_right = 92
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

	# Kills, top-left.
	lbl_kills = _lv("KILLS  0", 16, WHITE)
	lbl_kills.position = Vector2(28, 22)
	lbl_kills.size = Vector2(220, 24)
	root.add_child(lbl_kills)

	# Alive, top-right.
	lbl_alive = _lv("ALIVE  0", 22, WHITE)
	lbl_alive.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	lbl_alive.offset_left = -240
	lbl_alive.offset_right = -28
	lbl_alive.offset_top = 20
	lbl_alive.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(lbl_alive)

	# Killfeed under alive.
	killfeed_box = VBoxContainer.new()
	killfeed_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	killfeed_box.offset_left = -420
	killfeed_box.offset_right = -28
	killfeed_box.offset_top = 56
	killfeed_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	killfeed_box.add_theme_constant_override("separation", 4)
	killfeed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(killfeed_box)


func _build_crosshair() -> void:
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -60
	crosshair.offset_right = 60
	crosshair.offset_top = -60
	crosshair.offset_bottom = 60
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(_draw_crosshair)
	root.add_child(crosshair)

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


func _build_bars() -> void:
	var box := _panel()
	box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.offset_left = 28
	box.offset_top = -118
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

	var armor_bg := ColorRect.new()
	armor_bg.color = Color(1, 1, 1, 0.08)
	armor_bg.custom_minimum_size = Vector2(0, 5)
	armor_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(armor_bg)
	armor_fill = ColorRect.new()
	armor_fill.color = Color(0.42, 0.66, 0.95)
	armor_fill.set_anchors_preset(Control.PRESET_TOP_LEFT)
	armor_fill.size = Vector2(0, 5)
	armor_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	armor_bg.add_child(armor_fill)

	var hp_bg := ColorRect.new()
	hp_bg.color = Color(1, 1, 1, 0.08)
	hp_bg.custom_minimum_size = Vector2(0, 9)
	hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(hp_bg)
	health_fill = ColorRect.new()
	health_fill.color = Color(0.92, 0.93, 0.94)
	health_fill.set_anchors_preset(Control.PRESET_TOP_LEFT)
	health_fill.size = Vector2(0, 9)
	health_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bg.add_child(health_fill)

	box.add_child(vb)
	root.add_child(box)
	health_fill.set_meta("bg", hp_bg)
	armor_fill.set_meta("bg", armor_bg)


func _build_weapon_panel() -> void:
	var box := _panel()
	box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	box.offset_left = -330
	box.offset_right = -28
	box.offset_top = -118
	box.offset_bottom = -28
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_weapon = _lv("UNARMED", 12, ACCENT)
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


func _build_minimap() -> void:
	minimap = Control.new()
	minimap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	minimap.offset_left = -256
	minimap.offset_right = -28
	minimap.offset_top = -336
	minimap.offset_bottom = -132
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.draw.connect(_draw_minimap)
	root.add_child(minimap)


func _build_bottom_text() -> void:
	lbl_prompt = _lv("", 15, WHITE)
	lbl_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	lbl_prompt.offset_left = -300
	lbl_prompt.offset_right = 300
	lbl_prompt.offset_top = -168
	lbl_prompt.offset_bottom = -144
	lbl_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(lbl_prompt)

	lbl_notice = _lv("", 14, ACCENT)
	lbl_notice.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	lbl_notice.offset_left = -400
	lbl_notice.offset_right = 400
	lbl_notice.offset_top = -210
	lbl_notice.offset_bottom = -186
	lbl_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(lbl_notice)

	lbl_spectate = _lv("", 13, MUTED)
	lbl_spectate.set_anchors_preset(Control.PRESET_CENTER_TOP)
	lbl_spectate.offset_left = -400
	lbl_spectate.offset_right = 400
	lbl_spectate.offset_top = 108
	lbl_spectate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(lbl_spectate)


func _build_menu() -> void:
	menu = Control.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(menu)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.024, 0.028, 0.55)
	menu.add_child(bg)

	var grad := TextureRect.new()
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(grad)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	col.offset_left = 96
	col.offset_right = 860
	col.offset_top = -230
	col.offset_bottom = 250
	col.add_theme_constant_override("separation", 10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	menu.add_child(col)

	var kicker := _lv("V O X E L   I S L A N D   ·   1 0 0   D R O P", 12, ACCENT)
	kicker.add_theme_constant_override("outline_size", 0)
	col.add_child(kicker)

	var title := _lv("BLOCK ROYALE", 92, WHITE)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	col.add_child(title)

	var sub := _lv("JUMP  ·  LOOT  ·  SURVIVE", 18, MUTED, false)
	col.add_child(sub)
	col.add_child(_spacer(26))

	play_button = Button.new()
	play_button.text = "        P L A Y        "
	play_button.custom_minimum_size = Vector2(300, 66)
	play_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	play_button.add_theme_font_override("font", font_bold)
	play_button.add_theme_font_size_override("font_size", 24)
	play_button.add_theme_color_override("font_color", Color(0.06, 0.06, 0.06))
	play_button.add_theme_color_override("font_hover_color", Color(0.06, 0.06, 0.06))
	play_button.add_theme_color_override("font_pressed_color", Color(0.06, 0.06, 0.06))
	var sb := StyleBoxFlat.new()
	sb.bg_color = ACCENT
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	play_button.add_theme_stylebox_override("normal", sb)
	var sbh := sb.duplicate()
	sbh.bg_color = ACCENT.lightened(0.16)
	play_button.add_theme_stylebox_override("hover", sbh)
	var sbp := sb.duplicate()
	sbp.bg_color = ACCENT.darkened(0.18)
	play_button.add_theme_stylebox_override("pressed", sbp)
	play_button.pressed.connect(func(): play_pressed.emit())
	col.add_child(play_button)
	col.add_child(_spacer(18))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 4)
	for t in ["WASD  MOVE", "SHIFT  SPRINT", "C  CROUCH", "LMB  FIRE", "RMB  AIM", "R  RELOAD",
			"E  PICK UP", "Q  SWAP", "SPACE  JUMP / CHUTE"]:
		var l := _lv(t, 12, MUTED, false)
		grid.add_child(l)
	col.add_child(grid)

	menu_seed = _lv("", 11, Color(0.42, 0.45, 0.47), false)
	col.add_child(menu_seed)

	var foot := _lv("SQUAD OF ONE  ·  NO FRIENDS  ·  NO MERCY", 11, Color(0.42, 0.45, 0.47), false)
	foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot.offset_left = 96
	foot.offset_top = -52
	foot.offset_bottom = -28
	menu.add_child(foot)


func _build_end() -> void:
	end_panel = Control.new()
	end_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	end_panel.visible = false
	root.add_child(end_panel)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.01, 0.012, 0.014, 0.72)
	end_panel.add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.offset_left = -420
	col.offset_right = 420
	col.offset_top = -180
	col.offset_bottom = 180
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	end_panel.add_child(col)

	end_title = _lv("ELIMINATED", 64, DANGER)
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(end_title)
	end_sub = _lv("BY  UNKNOWN", 16, WHITE)
	end_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(end_sub)
	col.add_child(_spacer(18))
	end_stats = _lv("", 14, MUTED)
	end_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(end_stats)
	col.add_child(_spacer(24))
	end_hint = _lv("PRESS  SPACE  TO  REDEPLOY", 13, ACCENT)
	end_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(end_hint)


# --------------------------------------------------------------------- api --
func update_health(hp: float, armor: float) -> void:
	_update_health(hp, armor)


func _update_health(hp: float, armor: float) -> void:
	if lbl_health == null:
		return
	lbl_health.text = "%d" % int(ceil(maxf(0.0, hp)))
	var low := hp <= 35.0
	lbl_health.add_theme_color_override("font_color", DANGER if low else WHITE)
	lbl_armor.text = ("ARMOR  %d" % int(armor)) if armor > 0.0 else ""
	var bg: Control = health_fill.get_meta("bg")
	health_fill.size = Vector2(bg.size.x * clampf(hp / 100.0, 0.0, 1.0), 9)
	health_fill.color = DANGER if low else Color(0.92, 0.93, 0.94)
	var abg: Control = armor_fill.get_meta("bg")
	armor_fill.size = Vector2(abg.size.x * clampf(armor / 100.0, 0.0, 1.0), 5)
	armor_fill.visible = armor > 0.0


func update_weapon(id: String, mag: int, reserve: int) -> void:
	if lbl_weapon == null:
		return
	if id == "" or not Weapons.DEFS.has(id):
		lbl_weapon.text = "UNARMED"
		lbl_ammo.text = "—"
		lbl_reserve.text = ""
		return
	var d: Dictionary = Weapons.def(id)
	lbl_weapon.text = str(d["name"])
	lbl_ammo.text = "%d" % mag
	lbl_reserve.text = " / %d" % reserve
	lbl_ammo.add_theme_color_override("font_color", DANGER if mag <= int(d["mag"]) * 0.25 else WHITE)


func update_ammo(mag: int, reserve: int) -> void:
	if lbl_ammo != null:
		lbl_ammo.text = "%d" % mag
		lbl_reserve.text = " / %d" % reserve


func show_hitmarker(headshot: bool, killed: bool) -> void:
	hit_t = 0.20
	hit_kill = killed
	hit_head = headshot
	hitmarker.queue_redraw()


func show_damage(dir: Vector3) -> void:
	var ang := atan2(dir.x, -dir.z)
	damage_marks.append({"a": ang, "t": 1.6})
	if damage_marks.size() > 6:
		damage_marks.pop_front()


func set_zone(time_left: float, _radius: float, _phase: int, warning: bool) -> void:
	if lbl_zone_timer == null:
		return
	var t := maxf(0.0, time_left)
	var mins := int(t) / 60
	var secs := int(t) % 60
	lbl_zone_timer.text = "%02d:%02d" % [mins, secs]
	lbl_zone_timer.add_theme_color_override("font_color", DANGER if warning else WHITE)
	lbl_zone_state.text = "ZONE CLOSING" if warning else "ZONE HOLDING"
	lbl_zone_state.add_theme_color_override("font_color", DANGER if warning else MUTED)


func set_alive(count: int, total: int) -> void:
	if lbl_alive != null:
		lbl_alive.text = "ALIVE  %d" % count
		lbl_kills.text = "KILLS  %d" % _kills


var _kills := 0


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
	while killfeed_box.get_child_count() > 5:
		killfeed_box.get_child(0).queue_free()
	var tw := create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


func show_notice(text: String, dur := 2.0) -> void:
	if lbl_notice == null:
		return
	lbl_notice.text = text
	lbl_notice.modulate.a = 1.0
	notice_t = dur


func set_prompt(text: String) -> void:
	prompt_label = text
	if lbl_prompt != null:
		lbl_prompt.text = text


func set_crosshair_spread(px: float) -> void:
	spread = px
	if crosshair != null:
		crosshair.queue_redraw()


func set_heading(deg: float) -> void:
	heading = deg
	if compass != null:
		compass.queue_redraw()


func set_minimap(tex: Texture2D) -> void:
	minimap_tex = tex
	if minimap != null:
		minimap.queue_redraw()


func update_minimap(p: Vector3, zc: Vector2, zr: float, enemies: Array) -> void:
	player_pos = p
	zone_center = zc
	zone_radius = zr
	enemies_cache = enemies
	if minimap != null:
		minimap.queue_redraw()


func show_menu(seed_text: String) -> void:
	menu.visible = true
	end_panel.visible = false
	if menu_seed != null:
		menu_seed.text = seed_text


func hide_menu() -> void:
	menu.visible = false


func show_death(killer: String, kills: int, placement: int) -> void:
	end_panel.visible = true
	end_title.text = "ELIMINATED"
	end_title.add_theme_color_override("font_color", DANGER)
	end_sub.text = "BY  " + killer.to_upper()
	end_stats.text = "PLACEMENT  #%d        KILLS  %d" % [placement, kills]
	end_hint.text = "PRESS  SPACE  TO  REDEPLOY"
	end_hint.add_theme_color_override("font_color", ACCENT)


func show_victory(kills: int, damage: int = 0) -> void:
	end_panel.visible = true
	end_title.text = "WINNER"
	end_title.add_theme_color_override("font_color", ACCENT)
	end_sub.text = "LAST ONE STANDING"
	end_stats.text = "KILLS  %d        DAMAGE  %d" % [kills, damage]
	end_hint.text = "PRESS  SPACE  TO  PLAY  AGAIN"
	end_hint.add_theme_color_override("font_color", WHITE)


func hide_end() -> void:
	end_panel.visible = false


# -------------------------------------------------------------------- draw --
func _process(delta: float) -> void:
	if hit_t > 0.0:
		hit_t = maxf(0.0, hit_t - delta)
		hitmarker.queue_redraw()
	if notice_t > 0.0:
		notice_t = maxf(0.0, notice_t - delta)
		if lbl_notice != null:
			lbl_notice.modulate.a = clampf(notice_t / 0.4, 0.0, 1.0)
	for m in damage_marks:
		m["t"] = float(m["t"]) - delta
	damage_marks = damage_marks.filter(func(m): return float(m["t"]) > 0.0)
	damage_ring.queue_redraw()
	if minimap != null:
		minimap.queue_redraw()
	# Health bar widths follow their parent size when the window resizes.
	if health_fill != null and hp_cache >= 0.0:
		pass


var hp_cache := -1.0


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
	# Heading readout.
	compass.draw_string(font_mono, Vector2(cx + half + 14, y + 14), "%03d" % int(wrapf(heading, 0.0, 360.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.45))


func _draw_crosshair() -> void:
	var c := Vector2(60, 60)
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
	var a := clampf(hit_t / 0.20, 0.0, 1.0)
	var col := DANGER if hit_kill else Color(1, 1, 1, 0.95)
	if hit_head and not hit_kill:
		col = Color(1.0, 0.85, 0.35)
	col.a = a
	var c := Vector2(40, 40)
	for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		hitmarker.draw_line(c + d * 7.0, c + d * 15.0, col, 2.2)


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
		# Small arrow pointing inward.
		var tip := c + base * (r - 14.0)
		damage_ring.draw_line(tip, tip + base * 9.0, col, 2.0)


func _draw_minimap() -> void:
	var r := Rect2(Vector2.ZERO, minimap.size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.045, 0.82)
	sb.border_color = Color(1, 1, 1, 0.10)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	minimap.draw_style_box(sb, r)
	var inner := r.grow(-1.5)
	if minimap_tex != null:
		minimap.draw_texture_rect(minimap_tex, inner, false, Color(1, 1, 1, 0.92))
	else:
		minimap.draw_rect(inner, Color(0.10, 0.13, 0.12, 0.9))

	var extent := 450.0
	var to_map := func(p: Vector2) -> Vector2:
		return Vector2(inner.position.x + (p.x + extent) / (extent * 2.0) * inner.size.x,
				inner.position.y + (p.y + extent) / (extent * 2.0) * inner.size.y)

	var zc: Vector2 = to_map.call(zone_center)
	var zr: float = zone_radius / (extent * 2.0) * inner.size.x
	minimap.draw_arc(zc, maxf(1.0, zr), 0, TAU, 64, Color(0.35, 0.6, 1.0, 0.9), 1.5)
	minimap.draw_arc(zc, maxf(1.0, zr), 0, TAU, 64, Color(0.35, 0.6, 1.0, 0.18), 4.0)

	for e in enemies_cache:
		var ep: Vector3 = e
		var mp: Vector2 = to_map.call(Vector2(ep.x, ep.z))
		if inner.has_point(mp):
			minimap.draw_circle(mp, 2.2, Color(0.95, 0.45, 0.25, 0.95))

	var pp: Vector2 = to_map.call(Vector2(player_pos.x, player_pos.z))
	var ang := deg_to_rad(heading)
	var fwd := Vector2(sin(ang), -cos(ang))
	var right := Vector2(cos(ang), sin(ang))
	var p0 := pp + fwd * 6.0
	var p1 := pp - fwd * 3.5 - right * 3.2
	var p2 := pp - fwd * 3.5 + right * 3.2
	minimap.draw_colored_polygon(PackedVector2Array([p0, p1, p2]), Color(1, 1, 1, 0.98))
