extends "res://tests/check_suite.gd"

const CARD := preload("res://src/ui/components/choice_card.tscn")
var _activated := 0

class GameplayProbe:
	extends Node
	var keys := 0
	var clicks := 0
	var shortcuts := 0
	func _shortcut_input(_event: InputEvent) -> void:
		shortcuts += 1
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey:
			keys += 1
		if event is InputEventMouseButton:
			clicks += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await _test_scope()
	await _test_components()
	await _test_input()
	_finish("ui-foundation")


func _test_scope() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Headless DisplayServer cannot capture a cursor; compare the actual mode.
	var initial_mouse := Input.get_mouse_mode()
	var lower := UiScreen.new()
	root.add_child(lower)
	var upper := UiDialog.new()
	root.add_child(upper)
	_check_equal(Input.get_mouse_mode(), Input.MOUSE_MODE_VISIBLE, "nested screens release the cursor")
	_check(upper.input_scope.is_top() and not lower.input_scope.is_top(), "only topmost screen owns input")
	_check(upper.layer > lower.layer, "nested popup has a distinct higher canvas layer")
	lower.free()
	_check_equal(Input.get_mouse_mode(), Input.MOUSE_MODE_VISIBLE, "freeing underlying screen cannot recapture popup cursor")
	upper.free()
	_check_equal(Input.get_mouse_mode(), initial_mouse, "unexpected tree exit restores initial cursor")
	var focus := Button.new()
	root.add_child(focus)
	focus.grab_focus()
	var owner := UiScreen.new()
	root.add_child(owner)
	_check_equal(root.gui_get_focus_owner(), null, "opening modal removes underlying widget focus")
	root.gui_release_focus()
	owner.free()
	_check_equal(root.gui_get_focus_owner(), focus, "closing a screen restores surviving focus")
	focus.free()
	var first := UiScreen.new()
	root.add_child(first)
	var next := UiScreen.new()
	first.close_screen()
	root.add_child(next)
	first.free()
	_check(next.input_scope.is_top(), "handoff survives deferred removal of previous screen")
	_check_equal(Input.get_mouse_mode(), Input.MOUSE_MODE_VISIBLE, "old screen cannot restore cursor over its successor")
	next.free()
	_check_equal(Input.get_mouse_mode(), initial_mouse, "handoff ultimately restores cursor")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _test_components() -> void:
	_check(UiStyle.menu() == UiStyle.menu(), "menu theme is cached")
	_check(UiStyle.menu().get_font(&"font", &"UiHeading") == HudStyle.face(&"bold_tf"), "menu and HUD share font assets")
	var holder := VBoxContainer.new()
	holder.theme = UiStyle.menu()
	holder.size = Vector2(450, 700)
	root.add_child(holder)
	var first := CARD.instantiate() as UiChoiceCard
	var second := CARD.instantiate() as UiChoiceCard
	holder.add_child(first)
	holder.add_child(second)
	first.bind("A choice", "Long translated text with enough words to wrap naturally. ".repeat(5), true)
	second.bind("Unavailable", "A disabled action", false, false)
	await process_frame
	await process_frame
	_check(first.size.y > 120.0, "wrapped description expands card instead of clipping text")
	var description := first.get_node("%Description") as Label
	_check(first.get_global_rect().encloses(description.get_global_rect()), "expanded card contains its description")
	_check(second.position.y >= first.position.y + first.size.y + UiStyle.GAP, "flow layout preserves gap after growing card")
	_check_equal(first.get_node("%Action").focus_mode, Control.FOCUS_NONE, "choice never inherits default Space activation")
	_check(second.get_node("%Action").disabled, "disabled data disables native action")
	_check_equal(description.mouse_filter, Control.MOUSE_FILTER_IGNORE, "text does not steal pointer events")
	_check_equal(second.get_node("%Heading").get_theme_color(&"font_color"), UiStyle.DISABLED, "disabled label uses shared token")
	var activations: Array[int] = [0]
	first.activated.connect(func() -> void: activations[0] += 1)
	second.activated.connect(func() -> void: activations[0] += 1)
	_click(first.get_global_rect().get_center())
	_check_equal(activations[0], 1, "pointer reaches native action through decorative children")
	_click(second.get_global_rect().get_center())
	_check_equal(activations[0], 1, "pointer cannot activate disabled card")
	_check_equal(UiStyle.menu().get_stylebox(&"normal", &"UiButton").border_color, Color(1, 1, 1, 0.25), "selected card never mutates shared style")
	var selected_style: StyleBox = first.get_node("%Action").get_theme_stylebox(&"normal")
	first.bind(first.heading, first.description, true)
	_check(first.get_node("%Action").get_theme_stylebox(&"normal") == selected_style, "unchanged state reuses selected style")
	first.bind(first.heading, first.description, false)
	_check(not first.get_node("%Action").has_theme_stylebox_override(&"normal"), "deselection restores shared style")
	holder.free()
	var configured := CARD.instantiate() as UiChoiceCard
	configured.bind("Configured before mounting", "Remains unavailable", false, false)
	root.add_child(configured)
	_check(configured.get_node("%Action").disabled, "configuration before mounting preserves disabled state")
	configured.free()
	await process_frame
	var picker := ModePicker.new()
	picker.settings_file = "user://ui-foundation-mode.cfg"
	root.add_child(picker)
	await process_frame
	await process_frame
	_check_equal(picker._cards.size(), 2, "production mode picker uses shared choice scenes")
	_check(picker._screen.get_global_rect().encloses(picker._cards[1].get_global_rect()), "production choices fit logical viewport")
	_check(picker._cards[picker.highlighted].selected, "remembered highlight binds selected state")
	var picked: Array[String] = []
	picker.chosen.connect(func(value: String) -> void: picked.append(value))
	_click(picker._cards[1].get_global_rect().get_center())
	_check_equal(picked, ["Practice"] as Array[String], "clicking production card chooses correct mode")
	_check(picker._closing, "clicked selection immediately releases input")
	picker.free()
	var dialog := UiDialog.new()
	dialog.message = "<b>Plain player text</b> [color=red] remains plain"
	root.add_child(dialog)
	_check_equal(dialog.find_child("Message", true, false).text, dialog.message, "popup does not interpret player text as markup")
	dialog.free()


func _test_input() -> void:
	var probe := GameplayProbe.new()
	root.add_child(probe)
	PlayerInput.ensure_actions()
	var board := Scoreboard.new()
	root.add_child(board)
	var scores := InputEventAction.new()
	scores.action = &"showscores"
	scores.pressed = true
	root.push_input(scores, true)
	_check(board.held, "scoreboard opens normally without a modal owner")
	var picker := ModePicker.new()
	picker.settings_file = "user://ui-foundation-mode.cfg"
	root.add_child(picker)
	await process_frame
	await process_frame
	root.push_input(_key(KEY_F5), true)
	_check_equal(probe.keys, 0, "unbound modal key cannot start gameplay")
	_check_equal(probe.shortcuts, 0, "modal also blocks underlying shortcut handlers after GUI")
	scores.pressed = false
	root.push_input(scores, true)
	_check(not board.held, "scoreboard release under a modal cannot leave it latched")
	scores.pressed = true
	root.push_input(scores, true)
	_check(not board.held, "modal ownership blocks legacy scoreboard input phase")
	var dialog := UiDialog.new()
	root.add_child(dialog)
	dialog.confirmed.connect(func() -> void: _activated += 1)
	var before := picker.highlighted
	root.push_input(_key(KEY_DOWN), true)
	_check_equal(picker.highlighted, before, "popup blocks underlying navigation")
	root.push_input(_key(KEY_SPACE), true)
	_check_equal(_activated, 0, "Space does not accidentally confirm popup")
	root.push_input(_key(KEY_ENTER), true)
	_check_equal(_activated, 1, "Enter confirms exactly once")
	root.push_input(_key(KEY_ENTER), true)
	_check_equal(_activated, 1, "resolved popup cannot confirm twice")
	await process_frame
	# The second Enter also legitimately closes the underlying mode picker.
	if is_instance_valid(picker):
		picker.free()
	var screen := UiScreen.new()
	root.add_child(screen)
	screen.mount(UiDialog.VIEW)
	await process_frame
	var field := LineEdit.new()
	screen.get_child(0).add_child(field)
	field.grab_focus()
	var letter := _key(KEY_A)
	letter.unicode = 97
	root.push_input(letter, true)
	_check_equal(field.text, "a", "modal permits native text entry inside its own tree")
	_check_equal(probe.keys, 0, "native text entry does not reach gameplay")
	field.release_focus()
	root.push_input(_key(KEY_F5), true)
	_check_equal(probe.keys, 0, "unused keys remain blocked after native GUI phase")
	var wheel := InputEventMouseButton.new()
	wheel.position = Vector2(20, 20)
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	root.push_input(wheel, true)
	_check_equal(probe.clicks, 0, "scroll cannot leak from modal into jump/weapon selection")
	screen.free()
	board.free()
	probe.free()
	DirAccess.remove_absolute("user://ui-foundation-mode.cfg")
	await process_frame


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event


func _click(point: Vector2) -> void:
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = point
		click.pressed = pressed
		root.push_input(click, true)
