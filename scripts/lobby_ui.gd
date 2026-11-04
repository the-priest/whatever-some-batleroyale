extends Control
class_name LobbyUI

## LAN screens over the main menu: find or type a host to join, and the
## lobby where everyone waits for the host to start the drop.

signal host_pressed(name: String)
signal join_pressed(address: String, name: String)
signal start_pressed
signal leave_pressed
signal squad_toggled(on: bool)

var hud: Node
var net: Net

var _title: Label
var _sub: Label
var _status: Label
var _name_edit: LineEdit
var _join_box: VBoxContainer
var _games_box: VBoxContainer
var _ip_edit: LineEdit
var _lobby_box: VBoxContainer
var _players_box: VBoxContainer
var _mode_button: Button
var _start_button: Button
var _wait_label: Label
var _view := ""


func setup(p_hud: Node, p_net: Net) -> void:
	hud = p_hud
	net = p_net
	net.roster_changed.connect(_refresh_roster)
	net.status.connect(func(t): _status.text = t)
	net.games_found.connect(_show_games)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Same left-dark gradient as the main menu, over the island flyby.
	var bg := TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.024, 0.03, 0.95))
	g.set_color(1, Color(0.02, 0.024, 0.03, 0.3))
	g.add_point(0.5, Color(0.02, 0.024, 0.03, 0.82))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	bg.texture = gt
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	col.offset_left = 96
	col.offset_right = 900
	col.offset_top = -340
	col.offset_bottom = 340
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	add_child(col)

	_title = hud._lv("LAN GAME", 56, HUD.WHITE)
	col.add_child(_title)
	_sub = hud._lv("", 16, HUD.MUTED, false)
	col.add_child(_sub)
	col.add_child(hud._spacer(10))

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 12)
	name_row.add_child(hud._lv("YOUR NAME", 13, HUD.ACCENT))
	_name_edit = _edit(net.my_name if net != null else "PLAYER", 260)
	_name_edit.max_length = 14
	_name_edit.text_changed.connect(func(t): net.my_name = t.strip_edges().to_upper())
	name_row.add_child(_name_edit)
	col.add_child(name_row)
	col.add_child(hud._spacer(6))

	# Join view.
	_join_box = VBoxContainer.new()
	_join_box.add_theme_constant_override("separation", 8)
	col.add_child(_join_box)
	_join_box.add_child(hud._lv("GAMES ON YOUR NETWORK", 13, HUD.ACCENT))
	_games_box = VBoxContainer.new()
	_games_box.add_theme_constant_override("separation", 6)
	_join_box.add_child(_games_box)
	_show_games([])
	_join_box.add_child(hud._spacer(8))
	_join_box.add_child(hud._lv("OR TYPE THE HOST'S ADDRESS", 13, HUD.ACCENT))
	var ip_row := HBoxContainer.new()
	ip_row.add_theme_constant_override("separation", 10)
	_ip_edit = _edit("192.168.", 260)
	_ip_edit.text_submitted.connect(func(t): _do_join(t))
	ip_row.add_child(_ip_edit)
	var jb: Button = hud._button("JOIN", true)
	jb.custom_minimum_size = Vector2(160, 46)
	jb.pressed.connect(func(): _do_join(_ip_edit.text))
	ip_row.add_child(jb)
	_join_box.add_child(ip_row)

	# Lobby view.
	_lobby_box = VBoxContainer.new()
	_lobby_box.add_theme_constant_override("separation", 8)
	col.add_child(_lobby_box)
	_lobby_box.add_child(hud._lv("PLAYERS", 13, HUD.ACCENT))
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 4)
	_lobby_box.add_child(_players_box)
	_lobby_box.add_child(hud._spacer(8))
	_mode_button = hud._button("", false)
	_mode_button.custom_minimum_size = Vector2(420, 46)
	_mode_button.pressed.connect(_toggle_mode)
	_lobby_box.add_child(_mode_button)
	_start_button = hud._button("S T A R T   M A T C H", true)
	_start_button.custom_minimum_size = Vector2(420, 60)
	_start_button.pressed.connect(func(): hud.sfx_click(); start_pressed.emit())
	_lobby_box.add_child(_start_button)
	_wait_label = hud._lv("WAITING FOR THE HOST TO START  ...", 16, HUD.MUTED)
	_lobby_box.add_child(_wait_label)

	col.add_child(hud._spacer(10))
	_status = hud._lv("", 13, HUD.MUTED, false)
	col.add_child(_status)
	var back: Button = hud._button("BACK", false)
	back.custom_minimum_size = Vector2(200, 44)
	back.pressed.connect(func(): hud.sfx_click(); leave_pressed.emit())
	col.add_child(back)
	visible = false


func _edit(text: String, w: float) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.custom_minimum_size = Vector2(w, 42)
	e.add_theme_font_override("font", hud.font_bold)
	e.add_theme_font_size_override("font_size", 18)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.08)
	sb.border_color = Color(1, 1, 1, 0.2)
	sb.set_border_width_all(1)
	sb.content_margin_left = 10
	e.add_theme_stylebox_override("normal", sb)
	var sf := sb.duplicate()
	sf.border_color = HUD.ACCENT
	e.add_theme_stylebox_override("focus", sf)
	return e


func show_join() -> void:
	_view = "join"
	visible = true
	hud.menu.visible = false
	_title.text = "JOIN LAN GAME"
	_sub.text = "EVERYONE ON THE SAME WI-FI OR NETWORK  ·  THE HOST'S GAME SHOWS UP BELOW"
	_join_box.visible = true
	_lobby_box.visible = false
	_status.text = ""
	_name_edit.editable = true
	net.start_discovery()


func show_lobby() -> void:
	_view = "lobby"
	visible = true
	hud.menu.visible = false
	_join_box.visible = false
	_lobby_box.visible = true
	_name_edit.editable = false
	if net.hosting:
		_title.text = "HOSTING"
		_sub.text = "TELL YOUR FRIENDS TO PRESS  JOIN LAN  ·  ADDRESS  %s" % "  /  ".join(net.local_addresses())
	else:
		_title.text = "LOBBY"
		_sub.text = "CONNECTED  ·  THE HOST STARTS THE MATCH"
	_refresh_roster()


func close() -> void:
	if visible:
		hud.menu.visible = true
	visible = false
	net.stop_discovery()


func _do_join(address: String) -> void:
	if address.strip_edges() == "":
		return
	hud.sfx_click()
	net.my_name = _name_edit.text.strip_edges().to_upper()
	join_pressed.emit(address.strip_edges(), net.my_name)


func _show_games(list: Array) -> void:
	if _games_box == null:
		return
	for c in _games_box.get_children():
		c.queue_free()
	if list.is_empty():
		_games_box.add_child(hud._lv("SEARCHING  ...   (THE HOST MUST PRESS  HOST LAN  FIRST)", 13, HUD.DIM, false))
		return
	for g in list:
		var label := "%s'S GAME   ·   %d PLAYER%s   ·   %s%s" % [str(g.get("name", "?")), int(g.get("players", 1)),
			"" if int(g.get("players", 1)) == 1 else "S", str(g.get("ip", "")), "   ·   IN MATCH" if bool(g.get("running", false)) else ""]
		var b: Button = hud._button(label, false)
		b.custom_minimum_size = Vector2(640, 48)
		var ip := str(g.get("ip", ""))
		b.pressed.connect(func(): _do_join(ip))
		_games_box.add_child(b)


func _refresh_roster() -> void:
	if _players_box == null or _view != "lobby":
		return
	for c in _players_box.get_children():
		c.queue_free()
	var ids := net.roster.keys()
	ids.sort()
	for id in ids:
		var tag := "   (HOST)" if int(id) == 1 else ""
		var me := "   ·   YOU" if int(id) == net.my_id() else ""
		_players_box.add_child(hud._lv("●   %s%s%s" % [net.roster[id], tag, me], 20, HUD.WHITE if int(id) != net.my_id() else HUD.ACCENT))
	_mode_button.text = "MODE:  SQUAD  vs  BOTS" if net.squad else "MODE:  FREE-FOR-ALL"
	_mode_button.disabled = not net.hosting
	_start_button.visible = net.hosting
	_wait_label.visible = not net.hosting


func _toggle_mode() -> void:
	if not net.hosting:
		return
	hud.sfx_click()
	squad_toggled.emit(not net.squad)
