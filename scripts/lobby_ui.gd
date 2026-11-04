extends Control
class_name LobbyUI

## LAN screens over the menu flyby: a server browser to find the host, and
## the lobby itself: player slots with ping and ready state, host settings,
## chat, map preview and the match countdown.

signal host_pressed(name: String)
signal join_pressed(address: String, name: String)
signal start_pressed
signal leave_pressed
signal squad_toggled(on: bool)

const W := Color(0.949, 0.957, 0.961)
const MUTED := Color(0.608, 0.639, 0.659)
const DIM := Color(0.42, 0.45, 0.47)
const ACCENT := Color(0.949, 0.639, 0.235)
const GOOD := Color(0.42, 0.90, 0.52)
const BAD := Color(0.94, 0.36, 0.32)
const CARD := Color(0.055, 0.065, 0.075, 0.88)
const CARD_HI := Color(0.10, 0.115, 0.13, 0.94)

var hud: Node
var net: Net
var game: Node

var _view := ""
var _browser: Control
var _lobby: Control
var _connecting: Control
var _countdown_layer: Control

# Shared top bar.
var _crumb: Label
var _pill: Label
var _ping_lbl: Label

# Browser.
var _name_edit: LineEdit
var _rows: VBoxContainer
var _scan_box: Control
var _ip_edit: LineEdit
var _browser_status: Label
var _conn_label: Label
var _conn_t := 0.0

# Lobby.
var _slots: Array = []
var _squad_count: Label
var _addr_label: Label
var _chat_log: RichTextLabel
var _chat_edit: LineEdit
var _map_tex: TextureRect
var _map_caption: Label
var _mode_squad: Button
var _mode_ffa: Button
var _bots_slider: HSlider
var _bots_value: Label
var _loadout_btn: Button
var _primary: Button
var _hint: Label
var _known_ids: Array = []
var _cd_number: Label
var _cd_title: Label
var _cd_left := -1.0
var _cd_shown := -1
var _syncing := false


func setup(p_hud: Node, p_net: Net, p_game: Node = null) -> void:
	hud = p_hud
	net = p_net
	game = p_game
	net.roster_changed.connect(_refresh_roster)
	net.pings_updated.connect(_refresh_pings)
	net.status.connect(_on_status)
	net.games_found.connect(_show_games)
	net.chat.connect(_on_chat)
	net.countdown.connect(_on_countdown)
	net.multiplayer.connected_to_server.connect(func(): _connecting.visible = false)


# ------------------------------------------------------------------ layout --

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := Gradient.new()
	g.set_color(0, Color(0.015, 0.018, 0.022, 0.96))
	g.set_color(1, Color(0.015, 0.018, 0.022, 0.55))
	g.add_point(0.62, Color(0.015, 0.018, 0.022, 0.86))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(1, 0)
	bg.texture = gt
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(bg)

	_build_top_bar()
	_build_browser()
	_build_lobby()
	_build_connecting()
	_build_countdown()
	visible = false


func _build_top_bar() -> void:
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.07)
	line.position = Vector2(80, 98)
	line.size = Vector2(1440, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)
	var logo := _lbl("BLOCK ROYALE", 24, W)
	logo.position = Vector2(80, 48)
	add_child(logo)
	var accent_bar := ColorRect.new()
	accent_bar.color = ACCENT
	accent_bar.position = Vector2(80, 40)
	accent_bar.size = Vector2(36, 3)
	add_child(accent_bar)
	_crumb = _lbl("/   LAN", 24, MUTED, false)
	_crumb.position = Vector2(290, 48)
	add_child(_crumb)
	_pill = _lbl("", 13, ACCENT)
	_pill.position = Vector2(1000, 54)
	_pill.size = Vector2(360, 20)
	_pill.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_pill)
	_ping_lbl = _lbl("", 13, MUTED)
	_ping_lbl.position = Vector2(1380, 54)
	_ping_lbl.size = Vector2(140, 20)
	_ping_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_ping_lbl)


func _build_browser() -> void:
	_browser = Control.new()
	_browser.set_anchors_preset(Control.PRESET_FULL_RECT)
	_browser.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_browser)

	var title := _lbl("FIND A GAME", 46, W)
	title.position = Vector2(80, 122)
	_browser.add_child(title)
	var sub := _lbl("GAMES HOSTED ON YOUR NETWORK SHOW UP HERE AUTOMATICALLY", 13, MUTED, false)
	sub.position = Vector2(82, 180)
	_browser.add_child(sub)

	# Player name, top right.
	var nl := _lbl("PLAYER NAME", 11, ACCENT)
	nl.position = Vector2(1200, 126)
	_browser.add_child(nl)
	_name_edit = _edit(net.my_name if net != null else "PLAYER")
	_name_edit.position = Vector2(1200, 146)
	_name_edit.size = Vector2(320, 44)
	_name_edit.max_length = 14
	_name_edit.text_changed.connect(func(t): net.my_name = t.strip_edges().to_upper())
	_browser.add_child(_name_edit)

	# Server table.
	var table := _card(Vector2(80, 220), Vector2(1080, 470))
	_browser.add_child(table)
	var heads := [["HOST", 24], ["MODE", 360], ["PLAYERS", 620], ["STATUS", 780]]
	for h in heads:
		var hl := _lbl(h[0], 11, DIM)
		hl.position = Vector2(h[1], 18)
		table.add_child(hl)
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.06)
	sep.position = Vector2(16, 44)
	sep.size = Vector2(1048, 1)
	table.add_child(sep)
	_rows = VBoxContainer.new()
	_rows.position = Vector2(12, 54)
	_rows.size = Vector2(1056, 400)
	_rows.add_theme_constant_override("separation", 6)
	table.add_child(_rows)
	_scan_box = Control.new()
	_scan_box.position = Vector2(0, 150)
	_scan_box.size = Vector2(1080, 200)
	_scan_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	table.add_child(_scan_box)
	var sp := Spinner.new()
	sp.position = Vector2(540 - 22, 0)
	sp.size = Vector2(44, 44)
	_scan_box.add_child(sp)
	var scan := _lbl("SCANNING YOUR NETWORK", 16, W)
	scan.position = Vector2(0, 62)
	scan.size = Vector2(1080, 24)
	scan.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scan_box.add_child(scan)
	var tip := _lbl("THE HOST PRESSES  HOST LAN  ·  EVERYONE ON THE SAME WI-FI OR ROUTER", 12, MUTED, false)
	tip.position = Vector2(0, 92)
	tip.size = Vector2(1080, 20)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scan_box.add_child(tip)

	# Direct connect card.
	var dc := _card(Vector2(1200, 220), Vector2(320, 250))
	_browser.add_child(dc)
	var dl := _lbl("DIRECT CONNECT", 13, ACCENT)
	dl.position = Vector2(22, 20)
	dc.add_child(dl)
	var dsub := _lbl("TYPE THE ADDRESS SHOWN IN\nTHE HOST'S LOBBY", 11, MUTED, false)
	dsub.position = Vector2(22, 46)
	dc.add_child(dsub)
	_ip_edit = _edit("192.168.")
	_ip_edit.position = Vector2(22, 100)
	_ip_edit.size = Vector2(276, 46)
	_ip_edit.text_submitted.connect(func(t): _do_join(t))
	dc.add_child(_ip_edit)
	var cb := _btn("CONNECT", true)
	cb.position = Vector2(22, 162)
	cb.size = Vector2(276, 52)
	cb.pressed.connect(func(): _do_join(_ip_edit.text))
	dc.add_child(cb)

	_browser_status = _lbl("", 12, BAD, false)
	_browser_status.position = Vector2(1200, 486)
	_browser_status.size = Vector2(320, 80)
	_browser_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_browser.add_child(_browser_status)

	var back := _btn("BACK", false)
	back.position = Vector2(80, 720)
	back.size = Vector2(200, 50)
	back.pressed.connect(func(): _click(); leave_pressed.emit())
	_browser.add_child(back)


func _build_lobby() -> void:
	_lobby = Control.new()
	_lobby.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lobby.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lobby)

	_addr_label = _lbl("", 13, MUTED, false)
	_addr_label.position = Vector2(82, 112)
	_lobby.add_child(_addr_label)
	var copy := _btn("COPY", false, 11)
	copy.position = Vector2(440, 107)
	copy.size = Vector2(70, 28)
	copy.pressed.connect(func():
		_click()
		DisplayServer.clipboard_set(net.local_addresses()[0])
		_on_chat(0, "", "ADDRESS COPIED TO CLIPBOARD", true))
	copy.name = "Copy"
	_lobby.add_child(copy)

	# Squad slots.
	_squad_count = _lbl("PLAYERS", 13, ACCENT)
	_squad_count.position = Vector2(80, 150)
	_lobby.add_child(_squad_count)
	for i in Net.MAX_PLAYERS:
		var slot := Slot.new()
		slot.lobby = self
		slot.position = Vector2(80, 178 + i * 58)
		slot.size = Vector2(560, 50)
		_lobby.add_child(slot)
		_slots.append(slot)

	# Chat.
	var cl := _lbl("CHAT", 13, ACCENT)
	cl.position = Vector2(680, 150)
	_lobby.add_child(cl)
	var chat := _card(Vector2(680, 178), Vector2(480, 456))
	_lobby.add_child(chat)
	_chat_log = RichTextLabel.new()
	_chat_log.bbcode_enabled = true
	_chat_log.scroll_following = true
	_chat_log.position = Vector2(16, 12)
	_chat_log.size = Vector2(448, 372)
	_chat_log.add_theme_font_override("normal_font", hud.font_body)
	_chat_log.add_theme_font_override("bold_font", hud.font_bold)
	_chat_log.add_theme_font_size_override("normal_font_size", 15)
	_chat_log.add_theme_font_size_override("bold_font_size", 15)
	_chat_log.add_theme_color_override("default_color", Color(0.86, 0.88, 0.9))
	_chat_log.mouse_filter = Control.MOUSE_FILTER_PASS
	chat.add_child(_chat_log)
	_chat_edit = _edit("")
	_chat_edit.placeholder_text = "Say something to the lobby…  (Enter)"
	_chat_edit.position = Vector2(12, 398)
	_chat_edit.size = Vector2(456, 44)
	_chat_edit.max_length = 140
	_chat_edit.add_theme_font_override("font", hud.font_body)
	_chat_edit.add_theme_font_size_override("font_size", 15)
	_chat_edit.text_submitted.connect(func(t):
		net.send_chat(t)
		_chat_edit.text = ""
		_chat_edit.grab_focus())
	chat.add_child(_chat_edit)

	# Match card: map preview and settings.
	var ml := _lbl("MATCH", 13, ACCENT)
	ml.position = Vector2(1200, 150)
	_lobby.add_child(ml)
	var mc := _card(Vector2(1200, 178), Vector2(320, 456))
	_lobby.add_child(mc)
	_map_tex = TextureRect.new()
	_map_tex.position = Vector2(12, 12)
	_map_tex.size = Vector2(296, 196)
	_map_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_map_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_child(_map_tex)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.position = Vector2(12, 172)
	shade.size = Vector2(296, 36)
	mc.add_child(shade)
	_map_caption = _lbl("HIGHFALLS ARCHIPELAGO", 13, W)
	_map_caption.position = Vector2(24, 180)
	mc.add_child(_map_caption)

	var mode_l := _lbl("MODE", 11, DIM)
	mode_l.position = Vector2(20, 226)
	mc.add_child(mode_l)
	_mode_squad = _btn("SQUAD vs BOTS", false, 12)
	_mode_squad.position = Vector2(20, 246)
	_mode_squad.size = Vector2(138, 40)
	_mode_squad.toggle_mode = true
	_mode_squad.pressed.connect(func(): _set_mode(true))
	mc.add_child(_mode_squad)
	_mode_ffa = _btn("FREE-FOR-ALL", false, 12)
	_mode_ffa.position = Vector2(162, 246)
	_mode_ffa.size = Vector2(138, 40)
	_mode_ffa.toggle_mode = true
	_mode_ffa.pressed.connect(func(): _set_mode(false))
	mc.add_child(_mode_ffa)

	var bots_l := _lbl("BOTS", 11, DIM)
	bots_l.position = Vector2(20, 304)
	mc.add_child(bots_l)
	_bots_value = _lbl("63", 13, W)
	_bots_value.position = Vector2(220, 300)
	_bots_value.size = Vector2(80, 20)
	_bots_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mc.add_child(_bots_value)
	_bots_slider = HSlider.new()
	_bots_slider.min_value = 0
	_bots_slider.max_value = 99
	_bots_slider.step = 1
	_bots_slider.position = Vector2(20, 324)
	_bots_slider.size = Vector2(280, 24)
	_bots_slider.value_changed.connect(func(v):
		_bots_value.text = str(int(v))
		if not _syncing:
			net.set_setting("bots", int(v)))
	mc.add_child(_bots_slider)

	var lo_l := _lbl("LOADOUT DROP", 11, DIM)
	lo_l.position = Vector2(20, 366)
	mc.add_child(lo_l)
	_loadout_btn = _btn("ON", false, 12)
	_loadout_btn.position = Vector2(20, 386)
	_loadout_btn.size = Vector2(280, 40)
	_loadout_btn.pressed.connect(func():
		_click()
		net.set_setting("loadout", not bool(net.settings.get("loadout", true))))
	mc.add_child(_loadout_btn)

	# Bottom bar.
	var leave := _btn("LEAVE LOBBY", false)
	leave.position = Vector2(80, 680)
	leave.size = Vector2(220, 58)
	leave.pressed.connect(func(): _click(); leave_pressed.emit())
	_lobby.add_child(leave)
	_hint = _lbl("", 14, MUTED)
	_hint.position = Vector2(320, 700)
	_hint.size = Vector2(760, 24)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_lobby.add_child(_hint)
	_primary = _btn("START MATCH", true, 22)
	_primary.position = Vector2(1100, 676)
	_primary.size = Vector2(420, 66)
	_primary.pressed.connect(_on_primary)
	_lobby.add_child(_primary)


func _build_connecting() -> void:
	_connecting = ColorRect.new()
	(_connecting as ColorRect).color = Color(0.01, 0.012, 0.015, 0.86)
	_connecting.set_anchors_preset(Control.PRESET_FULL_RECT)
	_connecting.mouse_filter = Control.MOUSE_FILTER_STOP
	_connecting.visible = false
	add_child(_connecting)
	var sp := Spinner.new()
	sp.position = Vector2(800 - 30, 360)
	sp.size = Vector2(60, 60)
	_connecting.add_child(sp)
	_conn_label = _lbl("CONNECTING", 20, W)
	_conn_label.position = Vector2(0, 446)
	_conn_label.size = Vector2(1600, 30)
	_conn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_connecting.add_child(_conn_label)
	var cancel := _btn("CANCEL", false)
	cancel.position = Vector2(700, 500)
	cancel.size = Vector2(200, 48)
	cancel.pressed.connect(func():
		_click()
		net.leave("")
		_connecting.visible = false
		net.start_discovery())
	_connecting.add_child(cancel)


func _build_countdown() -> void:
	_countdown_layer = ColorRect.new()
	(_countdown_layer as ColorRect).color = Color(0.0, 0.0, 0.0, 0.55)
	_countdown_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_countdown_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown_layer.visible = false
	add_child(_countdown_layer)
	_cd_title = _lbl("MATCH STARTING", 22, ACCENT)
	_cd_title.position = Vector2(0, 286)
	_cd_title.size = Vector2(1600, 30)
	_cd_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_layer.add_child(_cd_title)
	_cd_number = _lbl("5", 190, W)
	_cd_number.position = Vector2(0, 310)
	_cd_number.size = Vector2(1600, 240)
	_cd_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cd_number.pivot_offset = Vector2(800, 120)
	_cd_number.add_theme_font_override("font", hud.font_mono)
	_countdown_layer.add_child(_cd_number)
	var sub := _lbl("GET READY TO DROP", 14, MUTED)
	sub.position = Vector2(0, 560)
	sub.size = Vector2(1600, 20)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_layer.add_child(sub)


# ----------------------------------------------------------------- helpers --

func _lbl(text: String, size: int, color: Color, bold := true) -> Label:
	var l: Label = hud._lv(text, size, color, bold)
	return l


func _btn(text: String, primary: bool, font := 16) -> Button:
	var b: Button = hud._button(text, primary)
	b.add_theme_font_size_override("font_size", font)
	b.custom_minimum_size = Vector2.ZERO
	return b


func _card(pos: Vector2, size: Vector2) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD
	sb.border_color = Color(1, 1, 1, 0.07)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", sb)
	p.position = pos
	p.size = size
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	return p


func _edit(text: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.add_theme_font_override("font", hud.font_bold)
	e.add_theme_font_size_override("font_size", 18)
	e.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.3))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.06)
	sb.border_color = Color(1, 1, 1, 0.14)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	e.add_theme_stylebox_override("normal", sb)
	var sf := sb.duplicate()
	sf.border_color = ACCENT
	sf.bg_color = Color(1, 1, 1, 0.09)
	e.add_theme_stylebox_override("focus", sf)
	return e


func _click() -> void:
	hud.sfx_click()


func _play(name: String, db := -6.0) -> void:
	var g = hud.get_parent()
	if g != null and g.get("sfx") != null:
		g.sfx.play_ui(name, db)


# ------------------------------------------------------------------- views --

func show_join() -> void:
	_view = "join"
	visible = true
	hud.menu.visible = false
	_browser.visible = true
	_lobby.visible = false
	_connecting.visible = false
	_countdown_layer.visible = false
	_crumb.text = "/   FIND GAME"
	_pill.text = ""
	_ping_lbl.text = ""
	_browser_status.text = ""
	_name_edit.text = net.my_name
	net.start_discovery()
	_show_games([])


func show_lobby() -> void:
	_view = "lobby"
	visible = true
	hud.menu.visible = false
	_browser.visible = false
	_lobby.visible = true
	_connecting.visible = false
	_crumb.text = "/   LOBBY"
	_known_ids = []
	if net.hosting:
		_addr_label.text = "YOUR ADDRESS   %s     ·     FRIENDS PRESS  JOIN LAN" % "  /  ".join(net.local_addresses())
	else:
		_addr_label.text = "CONNECTED TO THE HOST     ·     PRESS  READY  WHEN YOU ARE SET"
	_lobby.get_node("Copy").visible = net.hosting
	if game != null and game.world != null:
		_map_tex.texture = game.world.minimap_texture
		_map_caption.text = "HIGHFALLS ARCHIPELAGO   ·   #%d" % int(game.seed_value)
	if _chat_log.get_parsed_text() == "":
		_on_chat(0, "", "WELCOME TO THE LOBBY  ·  PRESS ENTER TO CHAT", true)
	_refresh_roster()


func close() -> void:
	if visible:
		hud.menu.visible = true
	visible = false
	_countdown_layer.visible = false
	_cd_left = -1.0
	net.stop_discovery()


func refresh_map() -> void:
	if _view == "lobby" and game != null and game.world != null:
		_map_tex.texture = game.world.minimap_texture
		_map_caption.text = "HIGHFALLS ARCHIPELAGO   ·   #%d" % int(game.seed_value)


func _do_join(address: String) -> void:
	var a := address.strip_edges()
	if a == "" or a.ends_with("."):
		_browser_status.text = "ENTER THE FULL ADDRESS, FOR EXAMPLE 192.168.1.20"
		return
	_click()
	net.my_name = _name_edit.text.strip_edges().to_upper()
	if net.my_name == "":
		net.my_name = "PLAYER"
	_browser_status.text = ""
	_conn_label.text = "CONNECTING TO  %s" % a
	_connecting.visible = true
	_conn_t = 8.0
	join_pressed.emit(a, net.my_name)


func connection_failed(msg: String) -> void:
	_connecting.visible = false
	_browser_status.text = msg


func _on_status(t: String) -> void:
	if _view == "join" and t.begins_with("COULD NOT"):
		connection_failed(t)


func _process(delta: float) -> void:
	if not visible:
		return
	if _connecting.visible and _conn_t > 0.0:
		_conn_t -= delta
		if _conn_t <= 0.0:
			net.leave("")
			connection_failed("NO ANSWER FROM THAT ADDRESS  ·  CHECK IT, AND THAT YOU ARE ON THE SAME NETWORK AS THE HOST")
			net.start_discovery()
	if _cd_left > 0.0:
		_cd_left -= delta
		var n := int(ceil(_cd_left))
		if n != _cd_shown and n >= 0:
			_cd_shown = n
			_cd_number.text = str(maxi(n, 1)) if n > 0 else "GO"
			_cd_number.scale = Vector2.ONE * 1.35
			_cd_number.modulate.a = 0.0
			var tw := _cd_number.create_tween().set_parallel(true)
			tw.tween_property(_cd_number, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(_cd_number, "modulate:a", 1.0, 0.15)
			if n > 0:
				_play("countdown_tick", -4.0)
		if _cd_left <= 0.0:
			_cd_number.text = "GO"
			_cd_title.text = "DROPPING IN"
			_play("countdown_go", -2.0)
	if _view == "lobby":
		var me := net.my_id()
		var p := net.ping_of(me) if not net.hosting else 0
		_ping_lbl.text = ("PING  %d MS" % p) if not net.hosting else ""
		_ping_lbl.add_theme_color_override("font_color", _ping_color(p))


# ------------------------------------------------------------ server list --

func _show_games(list: Array) -> void:
	if _rows == null:
		return
	for c in _rows.get_children():
		c.queue_free()
	_scan_box.visible = list.is_empty()
	for g in list:
		_rows.add_child(_game_row(g))


func _game_row(g: Dictionary) -> Control:
	var row := Button.new()
	row.custom_minimum_size = Vector2(1056, 56)
	row.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.035)
	sb.set_corner_radius_all(3)
	row.add_theme_stylebox_override("normal", sb)
	var sh := sb.duplicate()
	sh.bg_color = Color(1, 1, 1, 0.09)
	sh.border_color = ACCENT
	sh.border_width_left = 3
	row.add_theme_stylebox_override("hover", sh)
	row.add_theme_stylebox_override("pressed", sh)
	row.mouse_entered.connect(hud._hover_sound)
	var running := bool(g.get("running", false))
	var players := int(g.get("players", 1))
	var cap := int(g.get("max", Net.MAX_PLAYERS))
	var full := players >= cap
	var name := _lbl("%s'S GAME" % str(g.get("name", "?")), 17, W)
	name.position = Vector2(14, 10)
	row.add_child(name)
	var addr := _lbl(str(g.get("ip", "")), 11, DIM, false)
	addr.position = Vector2(14, 33)
	row.add_child(addr)
	var mode := _lbl(("SQUAD vs BOTS" if bool(g.get("squad", true)) else "FREE-FOR-ALL") + "   ·   %d BOTS" % int(g.get("bots", 63)), 13, MUTED)
	mode.position = Vector2(348, 18)
	row.add_child(mode)
	var pl := _lbl("%d / %d" % [players, cap], 15, W)
	pl.position = Vector2(608, 17)
	row.add_child(pl)
	var st := _lbl("IN MATCH" if running else ("FULL" if full else "IN LOBBY"), 12, BAD if full else (ACCENT if running else GOOD))
	st.position = Vector2(768, 19)
	row.add_child(st)
	var jl := _lbl("JOIN  ›", 15, ACCENT)
	jl.position = Vector2(960, 17)
	row.add_child(jl)
	var ip := str(g.get("ip", ""))
	row.pressed.connect(func():
		if not full:
			_do_join(ip))
	return row


# ------------------------------------------------------------------ lobby --

func _refresh_roster() -> void:
	if _view != "lobby" or _slots.is_empty():
		return
	var ids := net.roster.keys()
	ids.sort()
	for i in _slots.size():
		var slot: Slot = _slots[i]
		if i < ids.size():
			var id := int(ids[i])
			var fresh := not (id in _known_ids)
			slot.fill(id, str(net.roster[id]), net.color_of(id), net.is_ready(id), net.ping_of(id), id == 1, id == net.my_id())
			if fresh:
				slot.pop_in(float(i) * 0.03)
		else:
			slot.clear()
	for id in ids:
		if not (id in _known_ids) and not _known_ids.is_empty():
			_play("lobby_join", -8.0)
			break
	if _known_ids.size() > ids.size():
		_play("lobby_leave", -8.0)
	_known_ids = ids.duplicate()
	_squad_count.text = "PLAYERS   %d / %d" % [ids.size(), Net.MAX_PLAYERS]
	_pill.text = ("HOSTING   ·   %d / %d" if net.hosting else "IN LOBBY   ·   %d / %d") % [ids.size(), Net.MAX_PLAYERS]

	# Settings.
	_syncing = true
	var squad := bool(net.settings.get("squad", true))
	_mode_squad.button_pressed = squad
	_mode_ffa.button_pressed = not squad
	_style_toggle(_mode_squad, squad)
	_style_toggle(_mode_ffa, not squad)
	_bots_slider.value = int(net.settings.get("bots", 63))
	_bots_value.text = str(int(net.settings.get("bots", 63)))
	var lo := bool(net.settings.get("loadout", true))
	_loadout_btn.text = "ON   ·   LAND WITH YOUR KIT" if lo else "OFF   ·   LOOT EVERYTHING"
	_style_toggle(_loadout_btn, lo)
	for c in [_mode_squad, _mode_ffa, _bots_slider, _loadout_btn]:
		(c as Control).mouse_filter = Control.MOUSE_FILTER_STOP if net.hosting else Control.MOUSE_FILTER_IGNORE
		(c as Control).modulate.a = 1.0 if net.hosting else 0.75
	_syncing = false

	# Primary button and hint.
	var ready_n := net.ready_count()
	var total := ids.size()
	if net.hosting:
		if net.counting_down():
			_primary.text = "CANCEL START"
			_hint.text = "STARTING  ..."
		elif net.all_ready():
			_primary.text = "START MATCH"
			_hint.text = "EVERYONE IS READY" if total > 1 else "PLAYING ALONE WITH BOTS  ·  WAIT FOR FRIENDS TO JOIN"
		else:
			_primary.text = "FORCE START"
			_hint.text = "%d / %d READY  ·  WAITING FOR PLAYERS TO READY UP" % [ready_n, total]
	else:
		var me_ready := net.is_ready(net.my_id())
		_primary.text = "NOT READY" if me_ready else "READY"
		_hint.text = ("%d / %d READY  ·  WAITING FOR THE HOST TO START" % [ready_n, total]) if me_ready else "PRESS  READY  WHEN YOU ARE SET"
	_style_primary(not net.hosting and net.is_ready(net.my_id()))


func _refresh_pings() -> void:
	if _view != "lobby":
		return
	var ids := net.roster.keys()
	ids.sort()
	for i in mini(ids.size(), _slots.size()):
		(_slots[i] as Slot).set_ping(net.ping_of(int(ids[i])), int(ids[i]) == 1)


func _style_toggle(b: Button, on: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.22) if on else Color(1, 1, 1, 0.05)
	sb.border_color = ACCENT if on else Color(1, 1, 1, 0.12)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	for k in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(k, sb)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, W if on else MUTED)


func _style_primary(is_ready_state: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = GOOD.darkened(0.25) if is_ready_state else ACCENT
	sb.set_corner_radius_all(3)
	_primary.add_theme_stylebox_override("normal", sb)
	var sh := sb.duplicate()
	sh.bg_color = sb.bg_color.lightened(0.14)
	_primary.add_theme_stylebox_override("hover", sh)
	_primary.add_theme_stylebox_override("focus", sh)


func _set_mode(squad: bool) -> void:
	if not net.hosting:
		return
	_click()
	squad_toggled.emit(squad)


func _on_primary() -> void:
	if net.hosting:
		_click()
		if net.counting_down():
			net.cancel_countdown()
		else:
			start_pressed.emit()
	else:
		var r := not net.is_ready(net.my_id())
		net.set_ready(r)
		_play("ready_on" if r else "ready_off", -6.0)
	_refresh_roster()


func _on_chat(from_id: int, name: String, text: String, system: bool) -> void:
	if _chat_log == null:
		return
	var safe := text.replace("[", "[lb]")
	var time := Time.get_time_string_from_system().substr(0, 5)
	if system:
		_chat_log.append_text("[color=#6b7378]%s[/color]  [color=#9aa3a8]•  %s[/color]\n" % [time, safe])
	else:
		var c: Color = net.color_of(from_id)
		_chat_log.append_text("[color=#6b7378]%s[/color]  [b][color=#%s]%s[/color][/b]  %s\n" % [time, c.to_html(false), name.replace("[", "[lb]"), safe])
		if from_id != net.my_id() and visible:
			_play("chat_msg", -8.0)


func _on_countdown(seconds: int) -> void:
	if seconds < 0:
		_cd_left = -1.0
		_countdown_layer.visible = false
		_on_chat(0, "", "START CANCELLED", true)
		_refresh_roster()
		return
	if not visible:
		return
	_cd_left = float(seconds)
	_cd_shown = -1
	_cd_title.text = "MATCH STARTING"
	_countdown_layer.visible = true
	_refresh_roster()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or _view != "lobby":
		return
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER):
		_chat_edit.grab_focus()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------ inner views --

## One player slot in the lobby.
class Slot extends Panel:
	var lobby: LobbyUI
	var _strip: ColorRect
	var _name: Label
	var _tags: Label
	var _state: Label
	var _state_bg: Panel
	var _ping: PingBars
	var _ping_txt: Label
	var _empty: Label
	var _sb: StyleBoxFlat

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sb = StyleBoxFlat.new()
		_sb.bg_color = LobbyUI.CARD
		_sb.set_corner_radius_all(3)
		_sb.border_color = Color(1, 1, 1, 0.06)
		_sb.set_border_width_all(1)
		add_theme_stylebox_override("panel", _sb)
		_strip = ColorRect.new()
		_strip.position = Vector2(0, 0)
		_strip.size = Vector2(5, 50)
		add_child(_strip)
		_name = lobby._lbl("", 19, LobbyUI.W)
		_name.position = Vector2(22, 7)
		add_child(_name)
		_tags = lobby._lbl("", 11, LobbyUI.ACCENT)
		_tags.position = Vector2(22, 30)
		add_child(_tags)
		_state_bg = Panel.new()
		_state_bg.position = Vector2(318, 12)
		_state_bg.size = Vector2(112, 26)
		_state_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_state_bg)
		_state = lobby._lbl("", 12, LobbyUI.W)
		_state.position = Vector2(318, 16)
		_state.size = Vector2(112, 20)
		_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(_state)
		_ping = PingBars.new()
		_ping.position = Vector2(452, 15)
		_ping.size = Vector2(26, 20)
		add_child(_ping)
		_ping_txt = lobby._lbl("", 13, LobbyUI.MUTED)
		_ping_txt.position = Vector2(482, 15)
		_ping_txt.size = Vector2(64, 20)
		_ping_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		add_child(_ping_txt)
		_empty = lobby._lbl("OPEN SLOT", 13, Color(1, 1, 1, 0.18))
		_empty.position = Vector2(22, 15)
		add_child(_empty)

	func fill(id: int, pname: String, col: Color, is_ready: bool, ping: int, host: bool, me: bool) -> void:
		modulate.a = 1.0
		_sb.bg_color = LobbyUI.CARD_HI if me else LobbyUI.CARD
		_sb.border_color = Color(col.r, col.g, col.b, 0.35) if me else Color(1, 1, 1, 0.06)
		_strip.visible = true
		_strip.color = col
		_name.text = pname
		_name.add_theme_color_override("font_color", LobbyUI.W)
		var tags: Array = []
		if host:
			tags.append("♛  HOST")
		if me:
			tags.append("YOU")
		_tags.text = "   ·   ".join(tags)
		_tags.add_theme_color_override("font_color", col)
		_name.position.y = 7 if not tags.is_empty() else 14
		_state_bg.visible = true
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(3)
		if host:
			sb.bg_color = Color(LobbyUI.ACCENT.r, LobbyUI.ACCENT.g, LobbyUI.ACCENT.b, 0.18)
			_state.text = "HOST"
			_state.add_theme_color_override("font_color", LobbyUI.ACCENT)
		elif is_ready:
			sb.bg_color = Color(LobbyUI.GOOD.r, LobbyUI.GOOD.g, LobbyUI.GOOD.b, 0.2)
			_state.text = "✓  READY"
			_state.add_theme_color_override("font_color", LobbyUI.GOOD)
		else:
			sb.bg_color = Color(1, 1, 1, 0.06)
			_state.text = "NOT READY"
			_state.add_theme_color_override("font_color", LobbyUI.MUTED)
		_state_bg.add_theme_stylebox_override("panel", sb)
		_state.visible = true
		_ping.visible = true
		_ping_txt.visible = true
		_empty.visible = false
		set_ping(ping, host)

	func set_ping(ping: int, host: bool) -> void:
		if host:
			_ping.level = 4
			_ping.col = LobbyUI.GOOD
			_ping_txt.text = "LOCAL"
		else:
			_ping.level = 4 if ping < 30 else (3 if ping < 70 else (2 if ping < 140 else 1))
			_ping.col = lobby._ping_color(ping)
			_ping_txt.text = "%d MS" % ping
		_ping_txt.add_theme_color_override("font_color", _ping.col)
		_ping.queue_redraw()

	func clear() -> void:
		_sb.bg_color = Color(1, 1, 1, 0.02)
		_sb.border_color = Color(1, 1, 1, 0.05)
		_strip.visible = false
		_name.text = ""
		_tags.text = ""
		_state.visible = false
		_state_bg.visible = false
		_ping.visible = false
		_ping_txt.visible = false
		_empty.visible = true

	func pop_in(delay: float) -> void:
		modulate.a = 0.0
		var x := position.x
		position.x = x - 24.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(self, "modulate:a", 1.0, 0.28).set_delay(delay)
		tw.tween_property(self, "position:x", x, 0.32).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _ping_color(ping: int) -> Color:
	if ping < 60:
		return GOOD
	if ping < 120:
		return Color(0.98, 0.82, 0.32)
	return BAD


## Four signal bars.
class PingBars extends Control:
	var level := 4
	var col := Color.WHITE

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for i in 4:
			var h := 5.0 + float(i) * 4.0
			var r := Rect2(Vector2(float(i) * 6.0, size.y - h), Vector2(4, h))
			draw_rect(r, col if i < level else Color(1, 1, 1, 0.12))


## Rotating arc for "working on it".
class Spinner extends Control:
	var _a := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			_a += delta * 5.0
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.42
		draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.08), 4.0, true)
		draw_arc(c, r, _a, _a + 1.7, 32, LobbyUI.ACCENT, 4.0, true)
