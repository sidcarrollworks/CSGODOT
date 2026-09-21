extends SceneTree

## One-off tool that writes the input map into project.godot.
##
## Run with:
##   godot --headless --path . --script scripts/setup_input_map.gd
##
## It exists because the serialised InputEvent format in project.godot is
## fiddly to hand-write and easy to get subtly wrong. Letting Godot serialise
## it is guaranteed correct. Re-run it after changing the bindings below.

const ACTIONS := {
	&"move_forward": [KEY_W],
	&"move_back": [KEY_S],
	&"move_left": [KEY_A],
	&"move_right": [KEY_D],
	&"jump": [KEY_SPACE],
	&"duck": [KEY_CTRL],
	&"walk": [KEY_SHIFT],
}

const MOUSE_ACTIONS := {
	&"attack": MOUSE_BUTTON_LEFT,
	&"attack2": MOUSE_BUTTON_RIGHT,
}


func _initialize() -> void:
	for action in ACTIONS:
		var setting := "input/%s" % action
		var events: Array[InputEvent] = []
		for key in ACTIONS[action]:
			var event := InputEventKey.new()
			# Physical keycodes so WASD stays WASD on a non-QWERTY layout.
			event.physical_keycode = key
			events.append(event)
		ProjectSettings.set_setting(setting, {"deadzone": 0.2, "events": events})

	for action in MOUSE_ACTIONS:
		var setting := "input/%s" % action
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_ACTIONS[action]
		ProjectSettings.set_setting(setting, {"deadzone": 0.2, "events": [event]})

	var error := ProjectSettings.save()
	if error != OK:
		printerr("Failed to save project settings: %d" % error)
		quit(1)
		return
	print("Input map written for %d actions." % (ACTIONS.size() + MOUSE_ACTIONS.size()))
	quit(0)
