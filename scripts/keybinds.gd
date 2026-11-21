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
	["dodge", "DODGE ROLL"], ["flask", "EMBER FLASK"], ["skill", "CLASS ABILITY"], ["ability", "USE GIFT (BLINK)"], ["inspect", "INSPECT WEAPON"], ["map", "MAP"], ["marker", "MARK ON MAP"], ["free_look", "FREE LOOK"],
]

static var _defaults: Dictionary = {}
## The gamepad layout (Xbox names; PlayStation and Switch pads map the same
## positions). Kept on every action alongside the keys, whatever is rebound.
const PAD_BUTTONS := {
	"jump": JOY_BUTTON_A, "dodge": JOY_BUTTON_B, "interact": JOY_BUTTON_X, "swap_weapon": JOY_BUTTON_Y,
	"skill": JOY_BUTTON_RIGHT_SHOULDER, "flask": JOY_BUTTON_LEFT_SHOULDER,
	"crouch": JOY_BUTTON_RIGHT_STICK, "sprint": JOY_BUTTON_LEFT_STICK,
	"reload": JOY_BUTTON_DPAD_RIGHT, "grenade": JOY_BUTTON_DPAD_UP, "heal": JOY_BUTTON_DPAD_DOWN,
	"slot_1": JOY_BUTTON_DPAD_LEFT, "map": JOY_BUTTON_BACK, "pause": JOY_BUTTON_START,
	"ui_accept": JOY_BUTTON_A, "ui_cancel": JOY_BUTTON_B,
	"ui_up": JOY_BUTTON_DPAD_UP, "ui_down": JOY_BUTTON_DPAD_DOWN, "ui_left": JOY_BUTTON_DPAD_LEFT, "ui_right": JOY_BUTTON_DPAD_RIGHT,
}
## Stick and trigger directions: [axis, sign].
const PAD_AXES := {
	"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
	"move_forward": [JOY_AXIS_LEFT_Y, -1.0], "move_back": [JOY_AXIS_LEFT_Y, 1.0],
	"fire": [JOY_AXIS_TRIGGER_RIGHT, 1.0], "aim": [JOY_AXIS_TRIGGER_LEFT, 1.0],
	"ui_up": [JOY_AXIS_LEFT_Y, -1.0], "ui_down": [JOY_AXIS_LEFT_Y, 1.0],
}
## The last thing touched was a gamepad: prompts show its buttons.
static var pad_mode := false


static func add_pad_bindings() -> void:
	for a in PAD_BUTTONS:
		if not InputMap.has_action(a):
			continue
		var have := false
		for e: InputEvent in InputMap.action_get_events(a):
			if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == PAD_BUTTONS[a]:
				have = true
		if not have:
			var ev := InputEventJoypadButton.new()
			ev.button_index = PAD_BUTTONS[a]
			ev.device = -1
			InputMap.action_add_event(a, ev)
	for a in PAD_AXES:
		if not InputMap.has_action(a):
			continue
		var spec: Array = PAD_AXES[a]
		var have2 := false
		for e: InputEvent in InputMap.action_get_events(a):
			if e is InputEventJoypadMotion and (e as InputEventJoypadMotion).axis == int(spec[0]) and signf((e as InputEventJoypadMotion).axis_value) == float(spec[1]):
				have2 = true
		if not have2:
			var mv := InputEventJoypadMotion.new()
			mv.axis = int(spec[0]) as JoyAxis
			mv.axis_value = float(spec[1])
			mv.device = -1
			InputMap.action_add_event(a, mv)


static func pad_text(ev: InputEvent) -> String:
	if ev is InputEventJoypadButton:
		match (ev as InputEventJoypadButton).button_index:
			JOY_BUTTON_A: return "(A)"
			JOY_BUTTON_B: return "(B)"
			JOY_BUTTON_X: return "(X)"
			JOY_BUTTON_Y: return "(Y)"
			JOY_BUTTON_LEFT_SHOULDER: return "LB"
			JOY_BUTTON_RIGHT_SHOULDER: return "RB"
			JOY_BUTTON_LEFT_STICK: return "L3"
			JOY_BUTTON_RIGHT_STICK: return "R3"
			JOY_BUTTON_DPAD_UP: return "D-PAD UP"
			JOY_BUTTON_DPAD_DOWN: return "D-PAD DOWN"
			JOY_BUTTON_DPAD_LEFT: return "D-PAD LEFT"
			JOY_BUTTON_DPAD_RIGHT: return "D-PAD RIGHT"
			JOY_BUTTON_BACK: return "VIEW"
			JOY_BUTTON_START: return "MENU"
		return "PAD %d" % int((ev as InputEventJoypadButton).button_index)
	if ev is InputEventJoypadMotion:
		var m := ev as InputEventJoypadMotion
		match m.axis:
			JOY_AXIS_TRIGGER_RIGHT: return "RT"
			JOY_AXIS_TRIGGER_LEFT: return "LT"
			JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y: return "LEFT STICK"
			JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y: return "RIGHT STICK"
	return ""


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
	add_pad_bindings()


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
	if pad_mode:
		for e in evs:
			var t := pad_text(e)
			if t != "":
				return t
	for e in evs:
		if e is InputEventKey or e is InputEventMouseButton:
			return event_text(e)
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
	add_pad_bindings()
