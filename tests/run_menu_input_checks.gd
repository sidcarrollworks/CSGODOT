extends "res://tests/check_suite.gd"

## Client menu ownership changes command sampling, never server-side state.
## No map, extracted models or captured cursor is needed for these checks.
class Boundary:
	extends RefCounted
	var input := PlayerInput.new()
	var generation := UiInputScope.gameplay_generation

	func reconcile() -> void:
		var next_generation := UiInputScope.gameplay_generation
		input.set_gameplay_blocked(UiInputScope.blocks_gameplay(), next_generation != generation)
		generation = next_generation

	func event(action: StringName, pressed: bool) -> void:
		reconcile()
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		input.handle_event(event)

	func command(tick: int, now_usec: int) -> UserCmd:
		reconcile()
		return input.build_command(tick, now_usec)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	PlayerInput.ensure_actions()
	_clear_held()
	_test_scope_policy()
	_test_queued_requests()
	_test_between_samples()
	_test_held_keys()
	_test_resume_click()
	_test_fresh_forwarded_press()
	_test_sampling_window()
	_test_buy_movement()
	_test_screen_lifetime()
	_clear_held()
	_finish("menu-input")


func _owner() -> Node:
	var owner := Node.new()
	root.add_child(owner)
	return owner


func _clear_held() -> void:
	for action: StringName in PlayerInput.BUTTONS:
		Input.action_release(action)


func _test_scope_policy() -> void:
	_check(not UiInputScope.blocks_gameplay(), "normal gameplay has no blocking scope")
	var generation := UiInputScope.gameplay_generation
	var buying := _owner()
	var buy_scope := UiInputScope.acquire(buying)
	_check(not UiInputScope.blocks_gameplay(), "cursor-only scope preserves gameplay sampling")
	_check_equal(UiInputScope.gameplay_generation, generation, "buy scope does not invalidate gameplay input")
	var menu := _owner()
	var menu_scope := UiInputScope.acquire(menu, true)
	_check(UiInputScope.blocks_gameplay(), "a blocking screen blocks gameplay")
	_check_equal(UiInputScope.gameplay_generation, generation + 1, "blocking acquisition advances the generation")
	_check_equal(UiInputScope.acquire(menu, true), menu_scope, "duplicate acquisition returns the same scope")
	_check_equal(UiInputScope.gameplay_generation, generation + 1, "duplicate acquisition does not invalidate twice")
	var above := _owner()
	var above_scope := UiInputScope.acquire(above)
	_check(above_scope.is_top() and UiInputScope.blocks_gameplay(), "nonblocking top owner cannot override a blocking screen below it")
	var popup := _owner()
	var popup_scope := UiInputScope.acquire(popup, true)
	menu_scope.release()
	menu_scope.release()
	_check(UiInputScope.blocks_gameplay(), "out-of-order and duplicate release leave the popup blocking")
	popup_scope.release()
	_check(not UiInputScope.blocks_gameplay(), "releasing the last blocker restores gameplay despite cursor owners")
	above_scope.release()
	buy_scope.release()
	menu.free()
	popup.free()
	above.free()
	buying.free()
	var stale := _owner()
	var stale_scope := UiInputScope.acquire(stale, true)
	stale.free()
	_check(not UiInputScope.blocks_gameplay(), "invalid blocking owner is pruned from the count")
	stale_scope.release()
	_check(not UiInputScope.blocks_gameplay(), "a pruned scope can release again without corrupting the count")


func _queue_requests(input: PlayerInput) -> void:
	for action: StringName in [&"attack", &"attack2", &"jump", &"use", &"reload", &"slot3", &"invnext", &"drop", &"noclip"]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = true
		input.handle_event(event)


func _neutral(cmd: UserCmd, tick: int, description: String) -> void:
	_check_equal(cmd.tick, tick, description + ": current tick")
	_check_equal(cmd.buttons, 0, description + ": no held buttons")
	_check_equal(cmd.move, Vector2.ZERO, description + ": no movement")
	_check(cmd.steps.is_empty(), description + ": no subtick transitions")
	_check(cmd.weapon_select == UserCmd.SELECT_NONE and cmd.weapon_cycle == 0 and not cmd.toggle_noclip,
		description + ": no inventory or noclip requests")


func _test_queued_requests() -> void:
	var boundary := Boundary.new()
	boundary.input.yaw_degrees = 123.0
	boundary.input.pitch_degrees = -14.0
	_queue_requests(boundary.input)
	_check(not boundary.input._pending.is_empty() and not boundary.input._commands.is_empty(), "fixture has unsampled button and console requests")
	var owner := _owner()
	var scope := UiInputScope.acquire(owner, true)
	boundary.reconcile()
	_check(boundary.input.take_commands().is_empty(), "reconcile discards queued drop before console dispatch")
	var cmd := boundary.command(9, 5_000_000)
	_neutral(cmd, 9, "open menu")
	_check(cmd.yaw_degrees == 123.0 and cmd.pitch_degrees == -14.0, "neutral command preserves aim")
	var motion := InputEventMouseMotion.new()
	motion.screen_relative = Vector2(80.0, 40.0)
	boundary.input.handle_event(motion)
	_queue_requests(boundary.input)
	_check(boundary.input._pending.is_empty() and boundary.input.take_commands().is_empty(), "blocked sampler rejects subsequently forwarded events")
	_check(boundary.input.yaw_degrees == 123.0 and boundary.input.pitch_degrees == -14.0, "blocked mouse motion cannot change aim")
	scope.release()
	owner.free()


func _test_between_samples() -> void:
	var boundary := Boundary.new()
	_queue_requests(boundary.input)
	var owner := _owner()
	var scope := UiInputScope.acquire(owner, true)
	scope.release()
	owner.free()
	_check(not UiInputScope.blocks_gameplay(), "fixture opens and closes before a command")
	boundary.reconcile()
	_check(boundary.input.take_commands().is_empty(), "generation discards queued console requests after an immediate close")
	_neutral(boundary.command(11, 6_000_000), 11, "menu between samples")


func _test_held_keys() -> void:
	var input := PlayerInput.new()
	for action: StringName in PlayerInput.BUTTONS:
		Input.action_press(action)
	input.set_gameplay_blocked(true)
	_neutral(input.build_command(12, 7_000_000), 12, "held controls in menu")
	input.set_gameplay_blocked(false)
	_neutral(input.build_command(13, 7_000_000 + SimClock.tick_usec()), 13, "held controls after menu")
	_clear_held()
	# GUI consumes release events. Global polling must still forget them.
	input.build_command(14, 7_000_000 + 2 * SimClock.tick_usec())
	_check(input._ignored_actions.is_empty(), "GUI-consumed releases clear suppression through command sampling")
	Input.action_press(&"move_forward")
	var cmd := input.build_command(15, 7_000_000 + 3 * SimClock.tick_usec())
	_check(cmd.held(UserCmd.FORWARD) and cmd.move.y == 1.0, "fresh held movement works after a release without an event callback")
	_clear_held()


func _test_resume_click() -> void:
	var input := PlayerInput.new()
	input.set_gameplay_blocked(true)
	# Clicking Resume updates global state before the menu closes.
	Input.action_press(&"attack")
	input.set_gameplay_blocked(false)
	var cmd := input.build_command(20, 8_000_000)
	_check(not cmd.held(UserCmd.ATTACK) and cmd.first_press(UserCmd.ATTACK) == null, "held Resume click does not become an attack")
	Input.action_release(&"attack")
	var event := InputEventAction.new()
	event.action = &"attack"
	event.pressed = false
	input.handle_event(event)
	cmd = input.build_command(21, 8_000_000 + SimClock.tick_usec())
	_check(cmd.steps.is_empty(), "releasing an ignored menu click cannot synthesize a subtick hold")
	Input.action_press(&"attack")
	event.pressed = true
	input.handle_event(event)
	cmd = input.build_command(22, 8_000_000 + 2 * SimClock.tick_usec())
	_check(cmd.first_press(UserCmd.ATTACK) != null, "a fresh gameplay click works after Resume releases")
	_clear_held()


func _test_fresh_forwarded_press() -> void:
	var boundary := Boundary.new()
	var owner := _owner()
	var scope := UiInputScope.acquire(owner, true)
	scope.release()
	owner.free()
	# First reconciliation sees this press already held, because Godot
	# updates global state before forwarding the input event.
	Input.action_press(&"move_forward")
	boundary.event(&"move_forward", true)
	var cmd := boundary.command(23, 9_000_000)
	_check(cmd.held(UserCmd.FORWARD) and cmd.move.y == 1.0 and cmd.first_press(UserCmd.FORWARD) != null,
		"first forwarded fresh press survives a newly observed menu generation")
	_clear_held()


func _test_sampling_window() -> void:
	var input := PlayerInput.new()
	var tick := SimClock.tick_usec()
	input.set_gameplay_blocked(true)
	input.build_command(30, 10_000_000)
	input.build_command(31, 10_000_000 + tick)
	_check_equal(input._last_sample_usec, 10_000_000 + tick, "blocked ticks keep the wall-clock sampling window current")
	input.set_gameplay_blocked(false)
	input._pending.append(PlayerInput.ButtonEvent.new(&"attack", true, 10_000_000 + tick + tick / 2, 5.0, 6.0))
	var cmd := input.build_command(32, 10_000_000 + 2 * tick)
	_check(cmd.first_press(UserCmd.ATTACK) != null and is_equal_approx(cmd.first_press(UserCmd.ATTACK).when, 0.5),
		"fresh resumed input retains its correct subtick fraction")


func _test_buy_movement() -> void:
	var boundary := Boundary.new()
	var owner := _owner()
	var scope := UiInputScope.acquire(owner)
	Input.action_press(&"move_forward")
	Input.action_press(&"duck")
	Input.action_press(&"attack")
	var cmd := boundary.command(40, 11_000_000)
	_check(cmd.move.y == 1.0 and cmd.held(UserCmd.DUCK), "nonblocking buy ownership keeps polled movement and crouching")
	_check(not cmd.held(UserCmd.ATTACK), "buy ownership still exposes the cursor instead of firing")
	scope.release()
	owner.free()
	_clear_held()


func _test_screen_lifetime() -> void:
	var lower := UiScreen.new()
	root.add_child(lower)
	var upper := UiScreen.new()
	root.add_child(upper)
	_check(UiInputScope.blocks_gameplay(), "UiScreen blocks gameplay by default")
	lower.free()
	_check(UiInputScope.blocks_gameplay(), "freeing an underlying screen leaves the successor blocking")
	upper.close_screen()
	_check(not UiInputScope.blocks_gameplay(), "closing the successor releases input before its deferred deletion")
	upper.free()
	var cursor_only := UiScreen.new()
	cursor_only.block_gameplay = false
	root.add_child(cursor_only)
	_check(not UiInputScope.blocks_gameplay(), "a cursor-only screen can explicitly preserve gameplay")
	cursor_only.free()
	_check(not UiInputScope.blocks_gameplay(), "screen teardown balances every blocker")
