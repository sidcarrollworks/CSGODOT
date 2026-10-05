extends "res://tests/check_suite.gd"

class MenuController:
	extends PlayerController
	var quits := 0
	func _ready() -> void:
		config = MovementConfig.new()
		preferences = ClientPreferences.new()
		preferences_file = "user://menu-test-preferences.cfg"
		PlayerInput.ensure_actions()
		_sync_menu_input()
	func quit_to_desktop() -> void:
		quits += 1

class MenuPawn:
	extends PlayerSim
	func _ready() -> void:
		config = MovementConfig.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_test_preferences()
	await _test_settings()
	await _test_controller()
	await _test_running_world_and_commands()
	_finish("game-menu")


func _test_preferences() -> void:
	var path := "user://menu-test-preferences.cfg"
	DirAccess.remove_absolute(path)
	var defaults := ClientPreferences.read_file(path)
	_check_equal(defaults.sensitivity, 2.0, "missing file preserves default CS2 sensitivity")
	_check_equal(defaults.audio.round_start, 0.0, "missing file preserves competitive music defaults")
	var draft := defaults.copy()
	draft.sensitivity = 3.25
	draft.audio.music_volume = 0.4
	draft.audio.round_end = 0.75
	_check_equal(defaults.audio.music_volume, 1.0, "editing draft cannot change active music resource")
	var audio := defaults.audio
	defaults.apply_from(draft)
	_check(defaults.audio == audio, "apply preserves live audio resource identity")
	_check_equal(audio.round_end, 0.75, "existing music presenter sees accepted values")
	_check_equal(defaults.save_file(path), OK, "accepted client settings save successfully")
	var loaded := ClientPreferences.read_file(path)
	_check_equal(loaded.sensitivity, 3.25, "sensitivity survives restart")
	_check_equal(loaded.audio.music_volume, 0.4, "master music survives restart")
	_check_equal(loaded.audio.round_end, 0.75, "cue music survives restart")
	var config := ConfigFile.new()
	config.set_value("input", "sensitivity", "bad")
	config.set_value("music", "round_end", -4.0)
	config.set_value("music", "mvp", 8.0)
	config.save(path)
	loaded = ClientPreferences.read_file(path)
	_check_equal(loaded.sensitivity, 2.0, "malformed sensitivity falls back safely")
	_check_equal(loaded.audio.round_end, 0.0, "negative saved music is clamped")
	_check_equal(loaded.audio.mvp, 1.0, "over-range saved music is clamped")
	draft.sensitivity = INF
	draft.audio.music_volume = NAN
	defaults.apply_from(draft)
	_check_equal(defaults.sensitivity, 2.0, "non-finite draft sensitivity cannot reach input")
	_check_equal(defaults.audio.music_volume, 1.0, "non-finite draft music cannot reach audio")
	DirAccess.remove_absolute(path)


func _test_settings() -> void:
	var preferences := ClientPreferences.new()
	var screen := ClientSettingsScreen.new()
	screen.preferences = preferences
	root.add_child(screen)
	await process_frame
	await process_frame
	var field := screen.find_child("Sensitivity", true, false) as SpinBox
	var music := screen.find_child("RoundEnd", true, false) as HSlider
	_check_equal(field.min_value, 0.1, "sensitivity UI uses shipped CS2 minimum")
	_check_equal(field.max_value, 8.0, "sensitivity UI uses shipped CS2 maximum")
	music.value = 73.0
	_check_equal(screen.draft.audio.round_end, 0.73, "native slider binds percent to cue volume")
	_check_equal(preferences.audio.round_end, 0.16, "slider leaves live settings unchanged before Apply")
	field.get_line_edit().grab_focus()
	await process_frame
	field.get_line_edit().text = "2.61"
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	root.push_input(enter, true)
	await process_frame
	_check(not screen._closing, "Enter in native field cannot apply the whole settings screen")
	_check_equal(screen.draft.sensitivity, 2.61, "Enter submits focused sensitivity field")
	field.get_line_edit().text = "3.27"
	var accepted: Array[ClientPreferences] = []
	screen.applied.connect(func(value: ClientPreferences) -> void: accepted.append(value))
	screen.apply()
	_check_equal(accepted.size(), 1, "Apply resolves once")
	_check_equal(accepted[0].sensitivity, 3.27, "Apply includes unsubmitted native text")
	_check_equal(accepted[0].audio.round_end, 0.73, "Apply includes slider draft")
	_check(not UiInputScope.blocks_gameplay(), "Apply releases its input ownership immediately")
	screen.apply()
	_check_equal(accepted.size(), 1, "double Apply cannot resolve twice")
	await process_frame
	screen = ClientSettingsScreen.new()
	screen.preferences = preferences
	root.add_child(screen)
	screen.draft.sensitivity = 7.0
	root.push_input(_escape(), true)
	_check_equal(preferences.sensitivity, 2.0, "Escape discards draft settings")
	_check(screen._closing, "Escape closes only settings screen")
	await process_frame


func _test_controller() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	var initial_mouse := Input.get_mouse_mode()
	var controller := MenuController.new()
	root.add_child(controller)
	root.push_input(_escape(), true)
	_check(is_instance_valid(controller.game_menu), "Escape opens real menu on player controller")
	_check(UiInputScope.blocks_gameplay(), "game menu blocks player command sampling")
	_check(not paused, "game menu leaves match simulation running")
	var menu := controller.game_menu
	controller._open_settings()
	var settings := menu.get_child(menu.get_child_count() - 1) as ClientSettingsScreen
	_check(settings != null and settings.input_scope.is_top(), "Settings opens above the menu")
	_check(not menu._view.visible, "settings hides the underlying pause surface before blurring the world")
	settings.draft.sensitivity = 2.75
	settings.draft.audio.mvp = 0.5
	settings.apply()
	_check_equal(controller.input.sensitivity, 2.75, "Apply changes active player sensitivity")
	_check_equal(controller.preferences.audio.mvp, 0.5, "Apply changes active music values")
	_check_equal(ClientPreferences.read_file(controller.preferences_file).sensitivity, 2.75, "host persists accepted settings")
	_check(menu.input_scope.is_top() and UiInputScope.blocks_gameplay(), "settings handoff keeps underlying menu blocking")
	await process_frame
	_check(menu._view.visible, "closing settings restores the pause navigation")
	controller._confirm_quit()
	var dialog := menu.get_child(menu.get_child_count() - 1) as UiDialog
	root.push_input(_escape(), true)
	_check_equal(controller.quits, 0, "Escape cancels Quit without ending game")
	_check(menu.input_scope.is_top(), "cancel returns focus ownership to menu")
	await process_frame
	controller._confirm_quit()
	dialog = menu.get_child(menu.get_child_count() - 1) as UiDialog
	dialog.resolve(true)
	_check_equal(controller.quits, 1, "explicit confirmation invokes host Quit once")
	await process_frame
	root.push_input(_escape(), true)
	_check(controller.game_menu == null, "Escape from home menu resumes gameplay")
	_check(not UiInputScope.blocks_gameplay(), "Resume releases command suppression")
	_check_equal(Input.get_mouse_mode(), initial_mouse, "Resume restores original cursor mode")
	await process_frame
	controller.open_game_menu()
	controller._open_settings()
	root.push_input(_escape(), true)
	_check(is_instance_valid(controller.game_menu), "Escape in settings keeps menu open")
	await process_frame
	controller.free()
	_check(not UiInputScope.blocks_gameplay(), "scene teardown releases nested gameplay blockers")
	_check_equal(Input.get_mouse_mode(), initial_mouse, "scene teardown restores cursor")
	DirAccess.remove_absolute("user://menu-test-preferences.cfg")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	await process_frame


func _test_running_world_and_commands() -> void:
	var world := GameWorld.new()
	world.initialize_drop_physics(null, "legacy")
	root.add_child(world)
	var bomb := BombSystem.new()
	world.game.add_system(bomb)
	bomb.bomb.state = C4.State.PLANTED
	bomb.bomb.planted_usec = SimClock.tick_end_usec(world.tick)
	bomb.bomb.explodes_usec = bomb.bomb.planted_usec + 40_000_000
	var controller := MenuController.new()
	root.add_child(controller)
	controller.open_game_menu()
	var hud := GameHud.new()
	root.add_child(hud)
	await process_frame
	_check(not hud.visible, "blocking menu hides HUD instead of drawing its timer through buttons")
	var before_tick := world.tick
	var before_remaining := bomb.bomb.seconds_left(SimClock.tick_end_usec(world.tick))
	for i in 4:
		await physics_frame
	_check(world.tick > before_tick, "real GameWorld physics advances with menu open")
	_check(bomb.bomb.seconds_left(SimClock.tick_end_usec(world.tick)) < before_remaining, "planted bomb countdown advances with menu open")
	world.set_physics_process(false)
	controller.game_menu.resume()
	await process_frame
	await process_frame
	_check(hud.visible, "Resume restores HUD presentation")
	var buy_scope := UiInputScope.acquire(controller)
	await process_frame
	_check(hud.visible, "cursor-only buy scope preserves HUD presentation")
	buy_scope.release()
	world.add_player(controller)
	var drops: Array[int] = []
	world.game.on_command(&"drop", func(userid: int, _args: PackedStringArray, _t: SimTick) -> bool:
		drops.append(userid)
		return true)
	controller.input.handle_event(_action(&"drop"))
	controller.input.handle_event(_action(&"attack"))
	controller.open_game_menu()
	var cmd := controller.command_for(world.tick + 1, SimClock.tick_seconds())
	world.game.step(world.tick + 1)
	_check(drops.is_empty(), "real controller discards queued Drop before command dispatch")
	_check_equal(cmd.buttons, 0, "real controller samples neutral menu command")
	_check(cmd.steps.is_empty(), "real controller discards queued attack subticks")
	controller.game_menu.resume()
	await process_frame
	controller.input.handle_event(_action(&"drop"))
	var scope := UiInputScope.acquire(controller, true)
	scope.release()
	controller.command_for(world.tick + 2, SimClock.tick_seconds())
	world.game.step(world.tick + 2)
	_check(drops.is_empty(), "menu opened and closed between samples cannot leak queued Drop")
	controller.input.handle_event(_action(&"drop"))
	controller.command_for(world.tick + 3, SimClock.tick_seconds())
	world.game.step(world.tick + 3)
	_check_equal(drops.size(), 1, "fresh gameplay Drop works after dismissal")
	var bot := MenuPawn.new()
	root.add_child(bot)
	world.add_player(bot)
	bot.controlled_by = controller
	controller.controlling = bot
	controller.open_game_menu()
	controller.input.handle_event(_action(&"attack"))
	var commands := world.commands_for([controller, bot], SimClock.tick_seconds())
	_check_equal(commands[1].buttons, 0, "taken bot receives neutral command while its controller's menu is open")
	_check(commands[1].steps.is_empty(), "taken bot receives no queued attack edges")
	controller.controlling = null
	bot.controlled_by = null
	controller.free()
	bot.free()
	hud.free()
	# Break this fixture's bound system callbacks and last-tick cycle.
	world.game.last_tick = null
	world.game._queries.clear()
	world.game._command_handlers.clear()
	world.game.events._listeners.clear()
	world.game.events.clear()
	world.game._systems.clear()
	world.free()
	DirAccess.remove_absolute("user://menu-test-preferences.cfg")
	await process_frame


func _action(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _escape() -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	return key
