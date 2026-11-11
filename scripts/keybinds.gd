class_name Keybinds
extends RefCounted
## Rebindable controls: which actions the KEYS tab offers, what each is bound
## to now, saving and loading them, and the defaults to go back to.

const BINDABLE := [
	["move_forward", "MOVE FORWARD"], ["move_back", "MOVE BACK"],
	["move_left", "MOVE LEFT"], ["move_right", "MOVE RIGHT"],
	["sprint", "SPRINT"], ["jump", "JUMP"], ["crouch", "CROUCH"],
	["lean_left", "LEAN LEFT"], ["lean_right", "LEAN RIGHT"],
	["fire", "FIRE"], ["aim", "AIM"], ["reload", "RELOAD"],
	["interact", "USE / PICK UP"], ["grenade", "GRENADE"], ["heal", "HEAL"],
	["use_bandage", "BANDAGE"], ["use_med", "MEDKIT"], ["use_energy", "ENERGY DRINK"],
	["swap_weapon", "SWAP WEAPON"], ["fire_mode", "FIRE MODE"],
	["map", "MAP"], ["marker", "MARK ON MAP"], ["free_look", "FREE LOOK"],
]

static var _defaults: Dictionary = {}


## The bindings as the game set them up, before any player changes.
static func snapshot_defaults() -> void:
	if not _defaults.is_empty():
		return
	for b in BINDABLE:
		_defaults[b[0]] = InputMap.action_get_events(b[0]).duplicate()


static func reset_all() -> void:
	for a in _defaults:
		InputMap.action_erase_events(a)
		for e: InputEvent in _defaults[a]:
			InputMap.action_add_event(a, e)


## Bind an action to this one key or button, taking it off any other action
## that had it (so one key never does two things).
static func rebind(action: String, ev: InputEvent) -> void:
	var code := encode(ev)
	if code == "":
		return
	for b in BINDABLE:
		var other: String = b[0]
		if other == action:
			continue
		for e: InputEvent in InputMap.action_get_events(other):
			if encode(e) == code:
				InputMap.action_erase_event(other, e)
	# The mouse wheel stays on whatever it was on (weapon swap) unless the
	# new binding is the wheel itself.
	var keep: Array[InputEvent] = []
	if not code.begins_with("m:4") and not code.begins_with("m:5"):
		for e: InputEvent in InputMap.action_get_events(action):
			if e is InputEventMouseButton and (e as InputEventMouseButton).button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				keep.append(e)
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, decode(code))
	for e in keep:
		InputMap.action_add_event(action, e)


## "k:<physical keycode>" or "m:<mouse button>"; "" for anything else.
static func encode(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		return "k:%d" % int(code)
	if ev is InputEventMouseButton:
		return "m:%d" % int((ev as InputEventMouseButton).button_index)
	return ""


static func decode(code: String) -> InputEvent:
	var n := int(code.substr(2))
	if code.begins_with("k:"):
		var k := InputEventKey.new()
		k.physical_keycode = n as Key
		return k
	var m := InputEventMouseButton.new()
	m.button_index = n as MouseButton
	return m


## How the key reads on screen: "F", "SPACE", "LEFT CLICK".
static func key(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	var evs := InputMap.action_get_events(action)
	if evs.is_empty():
		return "—"
	return event_text(evs[0])


static func event_text(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		# On the player's own layout (AZERTY's A is where QWERTY's Q is).
		var shown := code
		if k.physical_keycode != KEY_NONE and DisplayServer.get_name() != "headless":
			shown = DisplayServer.keyboard_get_label_from_physical(code)
		var s := OS.get_keycode_string(shown if shown != KEY_NONE else code)
		return s.to_upper().replace("KP ", "NUM ")
	if ev is InputEventMouseButton:
		match (ev as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				return "LEFT CLICK"
			MOUSE_BUTTON_RIGHT:
				return "RIGHT CLICK"
			MOUSE_BUTTON_MIDDLE:
				return "MIDDLE CLICK"
			MOUSE_BUTTON_WHEEL_UP:
				return "WHEEL UP"
			MOUSE_BUTTON_WHEEL_DOWN:
				return "WHEEL DOWN"
			MOUSE_BUTTON_XBUTTON1:
				return "MOUSE 4"
			MOUSE_BUTTON_XBUTTON2:
				return "MOUSE 5"
		return "MOUSE %d" % int((ev as InputEventMouseButton).button_index)
	return "?"


static func save(cfg: ConfigFile) -> void:
	for b in BINDABLE:
		var codes: Array[String] = []
		for e: InputEvent in InputMap.action_get_events(b[0]):
			var c := encode(e)
			if c != "":
				codes.append(c)
		cfg.set_value("keys", b[0], ",".join(codes))


static func load_from(cfg: ConfigFile) -> void:
	snapshot_defaults()
	for b in BINDABLE:
		if not cfg.has_section_key("keys", b[0]):
			continue
		var s := str(cfg.get_value("keys", b[0]))
		if s == "":
			continue
		InputMap.action_erase_events(b[0])
		for c in s.split(","):
			if c.begins_with("k:") or c.begins_with("m:"):
				InputMap.action_add_event(b[0], decode(c))
