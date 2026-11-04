extends Node

## Registers input actions in code so the project file stays readable.

func _enter_tree() -> void:
	_key("move_forward", [KEY_W])
	_key("move_back", [KEY_S])
	_key("move_left", [KEY_A])
	_key("move_right", [KEY_D])
	_key("sprint", [KEY_SHIFT])
	_key("jump", [KEY_SPACE])
	_key("crouch", [KEY_CTRL, KEY_C])
	_key("interact", [KEY_F])
	_key("lean_left", [KEY_Q])
	_key("lean_right", [KEY_E])
	_key("fire_mode", [KEY_B])
	_key("zero_up", [KEY_PAGEUP])
	_key("zero_down", [KEY_PAGEDOWN])
	_key("reload", [KEY_R])
	_key("heal", [KEY_H])
	_key("use_bandage", [KEY_4])
	_key("use_med", [KEY_5])
	_key("use_energy", [KEY_6])
	_key("grenade", [KEY_G])
	_key("slot_1", [KEY_1])
	_key("slot_2", [KEY_2])
	_key("swap_weapon", [KEY_X])
	_wheel("swap_weapon", MOUSE_BUTTON_WHEEL_DOWN)
	_wheel("swap_weapon", MOUSE_BUTTON_WHEEL_UP)
	_key("map", [KEY_M])
	_key("pause", [KEY_ESCAPE])
	_key("free_look", [KEY_ALT])
	_key("scoreboard", [KEY_TAB])
	_key("chat", [KEY_ENTER, KEY_KP_ENTER])
	_mouse("marker", MOUSE_BUTTON_MIDDLE)
	_mouse("fire", MOUSE_BUTTON_LEFT)
	_mouse("aim", MOUSE_BUTTON_RIGHT)


func _key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _wheel(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
