class_name MainMenu
extends Control
## The main menu: sections down the left, the chosen section in the glass
## panel, and a line at the bottom that says what whatever you point at does.
## Every button explains itself.

var hud: HUD
var _nav: VBoxContainer
var _pages: Dictionary = {}
var _nav_buttons: Dictionary = {}
var _page_title: Label
var _page_sub: Label
var _desc_title: Label
var _desc_text: Label
var _current := ""
var _class_cards: Dictionary = {}
var _class_previews: Dictionary = {}
var _howto_text: RichTextLabel
var _howto_buttons: Dictionary = {}
var _records_text: Label
var kicker: Label
var rank_label: Label
var seed_label: Label
var ordeal_rec: Label

const SECTIONS := [
	["play", "PLAY", "Start a game: Battle Royale, Souls Mode, the Ordeal, the Hall of Echoes, or play with friends over LAN."],
	["character", "CHARACTER", "Choose who you are: the Knight, the Hunter, the Pyromancer or the Gunslinger. Your class is used in every mode."],
	["armoury", "ARMOURY", "Your Battle Royale loadout, the talismans you wear, and the oaths you swear for extra renown."],
	["codex", "CODEX", "The lore pages you have found, and every boss of the isle with how to beat it."],
	["records", "RECORDS", "Your rank and renown, and your best runs in the Ordeal and the Hall of Echoes."],
	["howto", "HOW TO PLAY", "Every mode, every control and every system, explained in short pages."],
	["settings", "SETTINGS", "Video, audio, controls, key bindings and gameplay options (including guidance)."],
	["quit", "QUIT", "Close the game."],
]

const HOWTO := [
	["MODES", "[b]BATTLE ROYALE[/b]\nDrop from the plane onto the Isle of Embers with 75 others. Loot, fight, and stay inside the storm circle. The last one standing wins. Every boss of the isle is on the map from the start, and they drop powerful Gifts.\n\n[b]SOULS MODE[/b]\nNo plane, no storm, no rivals: you, the isle, and its thirteen keepers. Explore, rest at Wayshrines, and fell every keeper. Die and you rise again at the last Wayshrine you rested at.\n\n[b]THE ORDEAL[/b]\nA boss rush in a ring of standing stones: bout after bout, harder each time. Swear Bindings to make it harder for more renown.\n\n[b]HALL OF ECHOES[/b]\nFight again any boss you have slain with your own hand, alone, against the clock."],
	["CONTROLS", "[b]Move[/b] W A S D   ·   [b]Look[/b] mouse   ·   [b]Jump[/b] Space\n[b]Sprint[/b] Shift   ·   [b]Crouch[/b] Ctrl / C   ·   [b]Dodge roll[/b] Z\n[b]Attack / fire[/b] left mouse   ·   [b]Guard / focus / aim[/b] right mouse\n[b]Class ability[/b] V   ·   [b]Class weapon[/b] 1   ·   [b]Guns[/b] 2, mouse wheel\n[b]Reload[/b] R   ·   [b]Interact / pick up[/b] F   ·   [b]Ember Flask[/b] T\n[b]Heal[/b] H   ·   [b]Grenade[/b] G (hold to aim)   ·   [b]Map[/b] M   ·   [b]Lean[/b] Q / E\n\nEvery key can be changed in SETTINGS → KEYS."],
	["CLASSES", "Each class has [b]one attack[/b], [b]one alternate[/b], [b]one ability[/b] (V) and [b]one passive[/b].\n\n[b]THE KNIGHT[/b]: greatsword combos up close. Hold right mouse to GUARD; raise it just as a blow lands to PARRY, and the attacker reels.\n[b]THE HUNTER[/b]: longbow. Hold to draw, release to loose. Full draw flies flat and hits hard. Arrows drop with distance: aim a little high.\n[b]THE PYROMANCER[/b]: fireballs that burst and burn the ground; hold right mouse for a cone of flame. Both cost Ember, which comes back on its own.\n[b]THE GUNSLINGER[/b]: the guns. Quickdraw reloads at once and quickens your next shots.\n\nEveryone can carry guns too: press 2 to swap to them, 1 to go back to your class weapon."],
	["COMBAT", "[b]Dodge roll (Z)[/b]: for a moment you are untouchable; blows and bullets pass through you. Read the boss and roll through the blow, not away from it.\n\n[b]Ember Flask (T)[/b]: a few swallows that heal 50. Refilled when you rest at a Wayshrine.\n\n[b]Parry[/b] (Knight): guard at the last instant. Bosses reel only briefly; soldiers drop their guard for a long moment.\n\n[b]Headshots[/b]: bullets and arrows above the shoulders count double or more. A boss's weak point is shown in its description in the Codex."],
	["SOULS MODE", "You wash ashore at the edge of the isle. Follow the [b]ember wisp[/b]: it leads you to your next goal and waits for you.\n\nThe [b]objective tracker[/b] (top left) always says what to do next and how far it is.\n\n[b]Wayshrines[/b]: press F to rest. You heal, your flask refills, and you will rise here if you die. You can also buy things with Embers.\n\n[b]Keepers[/b]: thirteen bosses. Each one gives up a [b]talisman[/b] (yours for good) and some give new moves that open the sealed parts of the isle."],
	["BATTLE ROYALE", "Jump from the plane (Space), open your chute, land and loot. The [b]storm[/b] closes in: stay inside the white circle. Bosses guard the landmarks; felling one gives you a [b]Gift[/b] for the rest of the match.\n\n[b]Writs[/b]: bounties posted at the notice boards. Complete them for Embers, spend Embers at Wayshrines.\n\nPlay with friends: PLAY → HOST GAME or JOIN GAME (same network)."],
	["GIFTS & TALISMANS", "[b]Gifts[/b] are for one match: a boss's power (Blink, Titan, Second Wind and more).\n\n[b]Talismans[/b] are for good: one from every kind of boss you slay with your own hand. Wear up to five (ARMOURY → TALISMANS); each changes one thing (faster rolls, more health, a quicker flask...).\n\n[b]Oaths[/b] make Battle Royale harder for extra renown; [b]Bindings[/b] do the same for the Ordeal."],
]

const BOSSES := [
	["THE REVENANTS", "Black knights at the landmarks. They fire volleys; roll through and close in."],
	["THE COLOSSUS", "A giant juggernaut. It slams the ground: get out of the red ring, then punish."],
	["THE HOLLOW WARDEN", "Kneels in the Ashen Hollow until you light its braziers. Patient and deadly."],
	["MOURNE, THE BELLKEEPER", "Strike the bell above its head. Jump over its toll rings."],
	["SKARN, THE WYRM BENEATH", "Swims through the earth. Leave the cracked ring, hit its head while it is up."],
	["VESPERA, THE CARRION QUEEN", "Dives along a red line. Step off it, then strike while she perches."],
	["ISOLDE, THE LANTERN WITCH", "Sweeping beams: jump the low ones, crouch the high ones."],
	["THE VEIL SISTERS", "Crossfire from two sides. Kill one and the other grieves: faster, deadlier."],
	["THE IRON SENTINEL", "Near-immune in its plate. Strike when the vents on its back glow."],
	["THE UNKINDLED", "The last fire of the isle. Waits at the end of the Ordeal and of Souls Mode."],
]


func setup(p_hud: HUD) -> void:
	hud = p_hud
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _build() -> void:
	# Left rail: title, rank and the sections.
	var rail := VBoxContainer.new()
	rail.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	rail.offset_left = 64
	rail.offset_right = 420
	rail.offset_top = 64
	rail.offset_bottom = -40
	rail.add_theme_constant_override("separation", 4)
	add_child(rail)
	kicker = hud._lv("THE ISLE OF EMBERS", 11, HUD.ACCENT)
	rail.add_child(kicker)
	var title := hud._lv("BLOCK ROYALE", 46, HUD.WHITE)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_y", 4)
	rail.add_child(title)
	rail.add_child(hud._lv("BATTLE ROYALE  ·  SOULS  ·  BOSS RUSH", 14, HUD.MUTED, false))
	rank_label = hud._lv("", 13, Color(1.0, 0.76, 0.42))
	rail.add_child(rank_label)
	rail.add_child(hud._spacer(22))
	_nav = VBoxContainer.new()
	_nav.add_theme_constant_override("separation", 3)
	rail.add_child(_nav)
	for s in SECTIONS:
		var b := _nav_button(str(s[1]))
		var key := str(s[0])
		b.pressed.connect(func(): _select(key))
		_explain(b, str(s[1]), str(s[2]))
		_nav.add_child(b)
		_nav_buttons[key] = b
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail.add_child(filler)
	seed_label = hud._lv("", 10, HUD.DIM, false)
	rail.add_child(seed_label)

	# The glass panel for the chosen section.
	var glass := PanelContainer.new()
	glass.set_anchors_preset(Control.PRESET_FULL_RECT)
	glass.offset_left = 460
	glass.offset_right = -56
	glass.offset_top = 64
	glass.offset_bottom = -150
	var gs := StyleBoxFlat.new()
	gs.bg_color = Color(0.03, 0.035, 0.045, 0.78)
	gs.border_color = Color(1.0, 0.65, 0.3, 0.22)
	gs.set_border_width_all(1)
	gs.border_width_top = 3
	gs.set_corner_radius_all(4)
	gs.content_margin_left = 28
	gs.content_margin_right = 28
	gs.content_margin_top = 18
	gs.content_margin_bottom = 18
	gs.shadow_color = Color(0, 0, 0, 0.45)
	gs.shadow_size = 18
	glass.add_theme_stylebox_override("panel", gs)
	add_child(glass)
	var gv := VBoxContainer.new()
	gv.add_theme_constant_override("separation", 10)
	glass.add_child(gv)
	_page_title = hud._lv("", 30, HUD.WHITE)
	gv.add_child(_page_title)
	_page_sub = hud._lv("", 13, HUD.MUTED, false)
	_page_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gv.add_child(_page_sub)
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.08)
	line.custom_minimum_size = Vector2(0, 1)
	gv.add_child(line)
	var holder := Control.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gv.add_child(holder)
	for s in SECTIONS:
		var page := Control.new()
		page.set_anchors_preset(Control.PRESET_FULL_RECT)
		page.visible = false
		holder.add_child(page)
		_pages[str(s[0])] = page
	_build_play(_pages["play"])
	_build_character(_pages["character"])
	_build_armoury(_pages["armoury"])
	_build_codex(_pages["codex"])
	_build_records(_pages["records"])
	_build_howto(_pages["howto"])
	_build_settings(_pages["settings"])
	_build_quit(_pages["quit"])

	# What you are pointing at, in plain words.
	var desc := PanelContainer.new()
	desc.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	desc.offset_left = 460
	desc.offset_right = -56
	desc.offset_top = -134
	desc.offset_bottom = -40
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(0.02, 0.022, 0.03, 0.85)
	ds.border_color = Color(1, 1, 1, 0.07)
	ds.set_border_width_all(1)
	ds.border_width_left = 4
	ds.border_color = HUD.ACCENT
	ds.set_corner_radius_all(3)
	ds.content_margin_left = 22
	ds.content_margin_right = 22
	ds.content_margin_top = 12
	ds.content_margin_bottom = 12
	desc.add_theme_stylebox_override("panel", ds)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(desc)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 4)
	desc.add_child(dv)
	_desc_title = hud._lv("", 15, HUD.ACCENT)
	dv.add_child(_desc_title)
	_desc_text = hud._lv("", 14, HUD.WHITE, false)
	_desc_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dv.add_child(_desc_text)
	_select("play")


func _nav_button(text: String) -> Button:
	var b := Button.new()
	b.text = "   " + text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(320, 44)
	b.add_theme_font_override("font", hud.font_bold)
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", HUD.MUTED)
	b.add_theme_color_override("font_hover_color", HUD.WHITE)
	b.add_theme_color_override("font_focus_color", HUD.WHITE)
	b.add_theme_color_override("font_pressed_color", HUD.WHITE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.0)
	sb.border_width_left = 3
	sb.border_color = Color(1, 1, 1, 0.0)
	b.add_theme_stylebox_override("normal", sb)
	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(1, 1, 1, 0.06)
	sh.border_width_left = 3
	sh.border_color = Color(1.0, 0.65, 0.3, 0.6)
	b.add_theme_stylebox_override("hover", sh)
	b.add_theme_stylebox_override("focus", sh)
	b.add_theme_stylebox_override("pressed", sh)
	b.mouse_entered.connect(hud._hover_sound)
	return b


## For a gamepad: focus on the current section in the left rail.
func focus_first() -> void:
	var key := _current if _current != "" else "play"
	if _nav_buttons.has(key):
		(_nav_buttons[key] as Button).grab_focus()


func _mark_nav(key: String) -> void:
	for k in _nav_buttons:
		var b: Button = _nav_buttons[k]
		var on: bool = k == key
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1.0, 0.62, 0.25, 0.14) if on else Color(1, 1, 1, 0.0)
		sb.border_width_left = 3
		sb.border_color = HUD.ACCENT if on else Color(1, 1, 1, 0.0)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_color_override("font_color", HUD.WHITE if on else HUD.MUTED)


## Every control says what it does when the mouse is over it or it has focus.
func _explain(c: Control, title: String, text: String) -> void:
	c.mouse_entered.connect(func(): _describe(title, text))
	c.focus_entered.connect(func(): _describe(title, text))


func _describe(title: String, text: String) -> void:
	if _desc_title != null:
		_desc_title.text = title
		_desc_text.text = text


func _select(key: String) -> void:
	if key == "quit" and _current == "quit":
		hud._quit()
		return
	hud.sfx_click()
	_current = key
	for k in _pages:
		(_pages[k] as Control).visible = k == key
	for s in SECTIONS:
		if str(s[0]) == key:
			_page_title.text = str(s[1])
			_page_sub.text = str(s[2])
			_describe(str(s[1]), str(s[2]))
	_mark_nav(key)
	if key == "records":
		refresh_records()
	if key == "character":
		_mark_class()


# ------------------------------------------------------------------ cards --
## A big button with a title, a line or two under it, and a coloured edge.
func _card(title: String, sub: String, col: Color, size: Vector2, desc: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_ALL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r * 0.18, col.g * 0.18, col.b * 0.18, 0.75)
	sb.border_color = Color(col.r, col.g, col.b, 0.35)
	sb.set_border_width_all(1)
	sb.border_width_left = 5
	sb.border_color = col
	sb.set_corner_radius_all(4)
	b.add_theme_stylebox_override("normal", sb)
	var sh := sb.duplicate() as StyleBoxFlat
	sh.bg_color = Color(col.r * 0.32, col.g * 0.32, col.b * 0.32, 0.9)
	sh.shadow_color = Color(col.r, col.g, col.b, 0.25)
	sh.shadow_size = 10
	b.add_theme_stylebox_override("hover", sh)
	b.add_theme_stylebox_override("focus", sh)
	b.add_theme_stylebox_override("pressed", sh)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 22
	v.offset_top = 14
	v.offset_right = -16
	v.offset_bottom = -12
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var t := hud._lv(title, 22, HUD.WHITE)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	var s := hud._lv(sub, 13, Color(0.85, 0.85, 0.85), false)
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(s)
	b.mouse_entered.connect(hud._hover_sound)
	_explain(b, title, desc)
	return b


func _small(text: String, desc_title: String, desc: String, w := 230.0) -> Button:
	var b := hud._button(text, false)
	b.custom_minimum_size = Vector2(w, 44)
	b.add_theme_font_size_override("font_size", 15)
	_explain(b, desc_title, desc)
	return b


func _build_play(page: Control) -> void:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 14)
	page.add_child(v)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	v.add_child(grid)
	var w := 470.0
	var br := _card("BATTLE ROYALE", "Drop onto the isle with 75 others. Loot, fight, outlast the storm. Bosses roam the landmarks.", HUD.ACCENT, Vector2(w, 128),
		"Start a Battle Royale match: jump from the plane, loot, fight, and stay inside the storm. Last one standing wins. Your class comes with you.")
	br.pressed.connect(func(): hud.sfx_click(); hud.play_pressed.emit())
	grid.add_child(br)
	var so := _card("SOULS MODE", "No storm, no rivals. Explore the isle, rest at Wayshrines, fell its thirteen keepers. Hard.", Color(0.85, 0.25, 0.15), Vector2(w, 128),
		"Start Souls Mode: an exploration and boss adventure. A wisp guides you; die and you rise at the last Wayshrine. Fell every keeper to win.")
	so.pressed.connect(func(): hud.sfx_click(); hud.souls_pressed.emit())
	grid.add_child(so)
	var od := _card("THE ORDEAL", "A boss rush in a ring of stones. Bout after bout, each harder than the last.", Color(1.0, 0.72, 0.42), Vector2(w, 116),
		"Start the Ordeal: fight bosses one bout after another in an arena. Your best bout and time are kept. Swear Bindings (in the Ordeal) for more renown.")
	od.pressed.connect(func(): hud.sfx_click(); hud.ordeal_pressed.emit())
	grid.add_child(od)
	var ec := _card("HALL OF ECHOES", "Fight again any boss you have slain, alone, against the clock.", Color(0.6, 0.75, 1.0), Vector2(w, 116),
		"Open the Hall of Echoes: pick a boss you have already slain and fight it again for a best time.")
	ec.pressed.connect(Callable(hud, "_open_echoes"))
	grid.add_child(ec)
	ordeal_rec = hud._lv("", 11, Color(0.85, 0.62, 0.42), false)
	v.add_child(ordeal_rec)
	v.add_child(hud._lv("PLAY WITH FRIENDS (SAME NETWORK)", 12, HUD.MUTED))
	var lan := HBoxContainer.new()
	lan.add_theme_constant_override("separation", 10)
	v.add_child(lan)
	var hb := _small("HOST GAME", "HOST GAME", "Open a game on this computer for friends on the same network to join. You start it when everyone is in.")
	hb.pressed.connect(func(): hud.sfx_click(); hud.host_lan_pressed.emit())
	lan.add_child(hb)
	var jb := _small("JOIN GAME", "JOIN GAME", "Join a friend's game: it finds games on your network, or type their address.")
	jb.pressed.connect(func(): hud.sfx_click(); hud.join_lan_pressed.emit())
	lan.add_child(jb)
	var qb := _small("QUICK LAN", "QUICK LAN", "Joins a game on your network if there is one; if not, hosts one for others to join.", 300.0)
	qb.pressed.connect(func(): hud.sfx_click(); hud.quick_lan_pressed.emit())
	lan.add_child(qb)


func _build_character(page: Control) -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 12)
	page.add_child(row)
	for c in Classes.ORDER:
		var d := Classes.def(c)
		var col: Color = d.color
		var card := Button.new()
		card.custom_minimum_size = Vector2(232, 0)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.focus_mode = Control.FOCUS_ALL
		row.add_child(card)
		var v := VBoxContainer.new()
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 12
		v.offset_right = -12
		v.offset_top = 8
		v.offset_bottom = -10
		v.add_theme_constant_override("separation", 3)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(v)
		var pv := CharPreview.new()
		pv.custom_minimum_size = Vector2(200, 210)
		v.add_child(pv)
		pv.show_skin(str(Classes.SKINS[c]))
		_class_previews[c] = pv
		var nm := hud._lv(str(d.name), 19, col)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(nm)
		var tag := hud._lv("%s    %s" % [str(d.tag), "●".repeat(int(d.difficulty)) + "○".repeat(3 - int(d.difficulty))], 11, HUD.MUTED)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(tag)
		for part in [["ATTACK", d.attack], ["ALT", d.alt], ["ABILITY  (%s)" % Keybinds.key("skill"), d.ability], ["PASSIVE", d.passive]]:
			var hl := hud._lv(str(part[0]), 10, col.lightened(0.2))
			hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(hl)
			var tl := hud._lv(str(part[1]), 11, Color(0.86, 0.86, 0.86), false)
			tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(tl)
		var key := str(c)
		card.pressed.connect(func(): _choose_class(key))
		card.mouse_entered.connect(hud._hover_sound)
		_explain(card, "%s  —  %s" % [str(d.name), str(d.style)], "Click to play as %s in every mode. %s" % [str(d.name), str(d.passive)])
		_class_cards[c] = card
	_mark_class()


func _choose_class(c: String) -> void:
	Classes.choose(c)
	hud.sfx_click()
	if _class_previews.has(c):
		(_class_previews[c] as CharPreview).flourish()
	_mark_class()
	hud.show_notice("YOU ARE  %s" % str(Classes.def(c).name), 2.0)


func _mark_class() -> void:
	Classes.load_choice()
	for c in _class_cards:
		var d := Classes.def(c)
		var col: Color = d.color
		var on: bool = c == Classes.chosen
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(col.r * 0.2, col.g * 0.2, col.b * 0.2, 0.85) if on else Color(0.06, 0.065, 0.075, 0.75)
		sb.border_color = col if on else Color(1, 1, 1, 0.08)
		sb.set_border_width_all(2 if on else 1)
		sb.border_width_top = 5 if on else 1
		sb.set_corner_radius_all(4)
		if on:
			sb.shadow_color = Color(col.r, col.g, col.b, 0.3)
			sb.shadow_size = 14
		var card: Button = _class_cards[c]
		card.add_theme_stylebox_override("normal", sb)
		var sh := sb.duplicate() as StyleBoxFlat
		sh.bg_color = sb.bg_color.lightened(0.08)
		card.add_theme_stylebox_override("hover", sh)
		card.add_theme_stylebox_override("focus", sh)
		card.add_theme_stylebox_override("pressed", sh)


func _build_armoury(page: Control) -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 24)
	page.add_child(row)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	row.add_child(left)
	left.add_child(hud._lv("BATTLE ROYALE LOADOUT", 12, HUD.ACCENT))
	hud.menu_preview = GunPreview.new()
	hud.menu_preview.custom_minimum_size = Vector2(520, 230)
	left.add_child(hud.menu_preview)
	hud.menu_loadout = hud._lv("", 20, HUD.WHITE)
	left.add_child(hud.menu_loadout)
	hud.menu_loadout_sub = hud._lv("", 12, HUD.MUTED, false)
	left.add_child(hud.menu_loadout_sub)
	var lb := _small("EDIT LOADOUT", "EDIT LOADOUT", "Choose the two guns and the optic you drop into Battle Royale with, or turn the loadout off to loot everything.", 260.0)
	lb.pressed.connect(Callable(hud, "_open_loadout"))
	left.add_child(lb)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	row.add_child(right)
	var tb := _card("TALISMANS", "Wear up to five. One from every kind of boss you slay yourself.", Color(1.0, 0.8, 0.4), Vector2(360, 110),
		"Choose the talismans you wear. Each changes one thing: faster rolls, more health, a quicker flask, and more. You earn them by slaying bosses.")
	tb.pressed.connect(Callable(hud, "_open_talismans"))
	right.add_child(tb)
	var ob := _card("OATHS", "Swear to make Battle Royale harder, for more renown.", Color(0.9, 0.45, 0.4), Vector2(360, 110),
		"Swear oaths (no minimap, glass bones, iron soldiers...) for the next Battle Royale match. Each one multiplies the renown you earn.")
	ob.pressed.connect(Callable(hud, "_open_oaths"))
	right.add_child(ob)


func _build_codex(page: Control) -> void:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 10)
	page.add_child(v)
	var cb := _small("OPEN THE LORE PAGES", "LORE PAGES", "Read the codex pages you have found on the isle. Each new page also pays renown.", 300.0)
	cb.pressed.connect(Callable(hud, "_open_codex"))
	v.add_child(cb)
	v.add_child(hud._lv("THE KEEPERS OF THE ISLE  —  AND HOW TO BEAT THEM", 12, HUD.ACCENT))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	for b in BOSSES:
		var box := VBoxContainer.new()
		box.custom_minimum_size = Vector2(450, 0)
		box.add_theme_constant_override("separation", 1)
		box.add_child(hud._lv(str(b[0]), 13, HUD.WHITE))
		var t := hud._lv(str(b[1]), 12, HUD.MUTED, false)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(t)
		grid.add_child(box)


func _build_records(page: Control) -> void:
	_records_text = hud._lv("", 15, HUD.WHITE, false)
	_records_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_records_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_child(_records_text)


func refresh_records() -> void:
	if _records_text == null:
		return
	Renown.load_profile()
	Ordeal.load_record()
	var pr: Array = Renown.progress()
	var lines: Array = []
	lines.append("RANK   %s" % Renown.rank_name())
	lines.append("RENOWN   %d%s" % [Renown.total, "" if int(pr[1]) == 0 else "    (%d / %d to the next rank)" % [int(pr[0]), int(pr[1])]])
	lines.append("")
	lines.append("THE ORDEAL   %s" % Ordeal.record_line())
	lines.append("")
	lines.append("BOSSES SLAIN WITH YOUR OWN HAND")
	var any := false
	for k in Ordeal.slain:
		lines.append("   %s" % str(k).to_upper())
		any = true
	if not any:
		lines.append("   none yet")
	_records_text.text = "\n".join(PackedStringArray(lines))


func _build_howto(page: Control) -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 20)
	page.add_child(row)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	row.add_child(list)
	for h in HOWTO:
		var key := str(h[0])
		var b := _small(key, key, "Read about %s." % key.to_lower(), 220.0)
		b.pressed.connect(func(): _show_howto(key))
		list.add_child(b)
		_howto_buttons[key] = b
	_howto_text = RichTextLabel.new()
	_howto_text.bbcode_enabled = true
	_howto_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_howto_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_howto_text.add_theme_font_override("normal_font", hud.font_body)
	_howto_text.add_theme_font_override("bold_font", hud.font_bold)
	_howto_text.add_theme_font_size_override("normal_font_size", 15)
	_howto_text.add_theme_font_size_override("bold_font_size", 15)
	_howto_text.add_theme_color_override("default_color", Color(0.9, 0.9, 0.9))
	row.add_child(_howto_text)
	_show_howto("MODES")


func _show_howto(key: String) -> void:
	for h in HOWTO:
		if str(h[0]) == key:
			_howto_text.text = str(h[1])
	for k in _howto_buttons:
		(_howto_buttons[k] as Button).add_theme_color_override("font_color", HUD.ACCENT if k == key else HUD.WHITE)


func _build_settings(page: Control) -> void:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 12)
	page.add_child(v)
	var groups := [
		["GRAPHICS & VIDEO", "Quality presets, shadows, lighting, draw distance, resolution scale, fullscreen, V-sync and the frame rate limit."],
		["AUDIO", "Master volume, music volume in the menu and in matches, and skipping the current song."],
		["CONTROLS & KEYS", "Mouse sensitivity, aim sensitivity, invert Y, hold or toggle for aim, crouch and sprint, and every key binding."],
		["GAMEPLAY", "Guidance (the ember wisp and hints) on or off, crosshair style and colour, hit markers, damage numbers, head bob and camera shake."],
	]
	for g in groups:
		var b := _card(str(g[0]), str(g[1]), Color(0.6, 0.65, 0.7), Vector2(620, 84), str(g[1]) + " Click to open the settings.")
		b.pressed.connect(Callable(hud, "_open_settings"))
		v.add_child(b)


func _build_quit(page: Control) -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	page.add_child(v)
	v.add_child(hud._lv("Leave the Isle of Embers?", 18, HUD.WHITE, false))
	var qb := _small("QUIT TO DESKTOP", "QUIT", "Close the game now. Your class, records, talismans and settings are saved.", 280.0)
	qb.pressed.connect(Callable(hud, "_quit"))
	v.add_child(qb)
