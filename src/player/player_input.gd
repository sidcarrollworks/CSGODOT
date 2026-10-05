class_name PlayerInput
extends RefCounted

## Input sampling with timestamps.
##
## Why this exists before there is anything to shoot: CS2's sub-tick model
## evaluates a shot at the instant the button went down, not at the next
## simulation tick. At 64 Hz a tick is 15.6 ms, so snapping shots to tick
## boundaries adds up to that much error to every single bullet, which is
## exactly the "felt like I hit that" complaint.
##
## Timestamping costs nothing now. Retrofitting it later means touching
## movement, animation and netcode at once, so it goes in from the start even
## though single-player bots will not notice.

## One button transition, with the moment it actually happened and where the
## player was looking at that moment.
##
## The look angles matter as much as the timestamp. Knowing a shot happened
## 3 ms into the tick is no use if the only aim direction on hand is the one
## from the tick boundary: you would be firing where the player was pointing
## up to a tick (15.6 ms) ago. Recording both is what makes a sub-tick shot actually
## sub-tick.
class ButtonEvent:
	var action: StringName
	var pressed: bool
	## Microseconds, from Time.get_ticks_usec().
	var timestamp_usec: int
	var yaw_degrees: float
	var pitch_degrees: float

	func _init(
		p_action: StringName,
		p_pressed: bool,
		p_timestamp_usec: int,
		p_yaw: float,
		p_pitch: float
	) -> void:
		action = p_action
		pressed = p_pressed
		timestamp_usec = p_timestamp_usec
		yaw_degrees = p_yaw
		pitch_degrees = p_pitch


## The actions that are buttons in a command, and their bits.
const BUTTONS := {
	&"attack": UserCmd.ATTACK,
	&"attack2": UserCmd.ATTACK2,
	&"use": UserCmd.USE,
	&"jump": UserCmd.JUMP,
	&"duck": UserCmd.DUCK,
	&"walk": UserCmd.WALK,
	&"reload": UserCmd.RELOAD,
	&"move_forward": UserCmd.FORWARD,
	&"move_back": UserCmd.BACK,
	&"move_left": UserCmd.LEFT,
	&"move_right": UserCmd.RIGHT,
}
## The mouse's buttons, which count only while the game has the mouse.
const MOUSE_BUTTONS: Array[StringName] = [&"attack", &"attack2"]

## The number keys, CS2's slots: the primary, the pistol, the knife and the
## Zeus, the grenades, the bomb.
const SLOT_ACTIONS: Array[StringName] = [&"slot1", &"slot2", &"slot3", &"slot4", &"slot5"]

## The keys the game reads that project.godot has not always had, with
## CS2's own bindings: added at start wherever the input map lacks them (a
## project.godot an open editor wrote back over), so the keys still work.
const GAME_KEYS := {
	&"slot3": KEY_3, &"slot4": KEY_4, &"slot5": KEY_5,
	&"lastinv": KEY_Q, &"drop": KEY_G, &"use": KEY_E,
	# The client's own: CS2's TAB +showscores, the scoreboard while held.
	&"showscores": KEY_TAB,
}
## The same for the mouse's buttons: CS2's MWHEELDOWN invnext
## (user_keys_default.vcfg). The wheel going up stays Sid's jump.
const GAME_MOUSE := {
	&"invnext": MOUSE_BUTTON_WHEEL_DOWN,
}
## Test keys moved off a key CS2 uses, as [from, to], put right in such a
## map too: the range's never-die was on G, which is drop
## (reference/binds.md).
const MOVED_KEYS := {
	&"dummy_immortal": [KEY_G, KEY_BRACKETLEFT],
}

var _pending: Array[ButtonEvent] = []
var _weapon_select: int = UserCmd.SELECT_NONE
## Notches of the wheel since the last command (UserCmd.weapon_cycle).
var _weapon_cycle: int = 0
var _toggle_noclip: bool = false
## Console commands the keys have asked for since the last command ("drop"),
## for whatever runs the player to send to the game.
var _commands := PackedStringArray()
## When the last command was sampled, on the wall clock: the start of the
## stretch the next one covers.
var _last_sample_usec: int = -1
## Set by the controller at the command/event boundary, never by the
## simulation. The local menu does not pause the world or change a pawn.
var gameplay_blocked: bool = false
## Keys held in a menu must come up before polling can drive gameplay.
## A genuine newly forwarded press can also clear its own suppression.
var _ignored_actions: Dictionary = {}

## Look angles accumulate at render rate, not tick rate. Mouse movement must
## never be quantised to the simulation tick or aiming feels heavy.
var yaw_degrees: float = 0.0
var pitch_degrees: float = 0.0

## CS2 semantics: the game turns m_yaw (0.022 degrees) per mouse count per
## point of sensitivity, so this is the same number you would type in CS2.
var sensitivity: float = 2.0
## What a scope makes of it: the zoomed field of view over the unzoomed one,
## set by the view each frame (PlayerView._follow_scope); 1 unscoped.
var zoom_sensitivity: float = 1.0
const CS_YAW_PER_COUNT := 0.022

const PITCH_LIMIT := 89.0


## Adds every action in GAME_KEYS and GAME_MOUSE the input map does not
## have, and moves each in MOVED_KEYS still on its old key.
static func ensure_actions() -> void:
	for action: StringName in GAME_KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.2)
		var event := InputEventKey.new()
		event.physical_keycode = GAME_KEYS[action]
		InputMap.action_add_event(action, event)
	for action: StringName in GAME_MOUSE:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.2)
		var button := InputEventMouseButton.new()
		button.button_index = GAME_MOUSE[action]
		InputMap.action_add_event(action, button)
	for action: StringName in MOVED_KEYS:
		if not InputMap.has_action(action):
			continue
		var keys: Array = MOVED_KEYS[action]
		for event in InputMap.action_get_events(action):
			var old_key := event as InputEventKey
			if old_key == null or old_key.physical_keycode != keys[0]:
				continue
			InputMap.action_erase_event(action, event)
			var moved := InputEventKey.new()
			moved.physical_keycode = keys[1]
			InputMap.action_add_event(action, moved)


func handle_event(event: InputEvent) -> void:
	if gameplay_blocked:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		# The mouse's own movement on the screen: relative is scaled with the
		# 2D (the canvas_items stretch halves it in a 3840x2160 window), which
		# would turn the view half as far as CS2 at the same sensitivity.
		yaw_degrees -= motion.screen_relative.x * sensitivity * zoom_sensitivity * CS_YAW_PER_COUNT
		pitch_degrees -= motion.screen_relative.y * sensitivity * zoom_sensitivity * CS_YAW_PER_COUNT
		pitch_degrees = clampf(pitch_degrees, -PITCH_LIMIT, PITCH_LIMIT)
		return

	for action: StringName in BUTTONS:
		if event.is_action_pressed(action, false):
			# Godot updates held state before callbacks. If this callback first
			# notices a menu generation, its fresh gameplay press still counts.
			_ignored_actions.erase(action)
			_pending.append(_event(action, true))
		elif event.is_action_released(action):
			if _ignored_actions.erase(action):
				# No accepted press preceded this release. Replaying it would
				# reconstruct a held button before the release inside the tick.
				continue
			_pending.append(_event(action, false))

	for i in SLOT_ACTIONS.size():
		if event.is_action_pressed(SLOT_ACTIONS[i]):
			_weapon_select = i + 1
	# The wheel sends a press and a release for each notch; the press
	# counts (reference/godot/input.md).
	if event.is_action_pressed(&"invnext"):
		_weapon_cycle += 1
	if event.is_action_pressed(&"lastinv"):
		_weapon_select = UserCmd.SELECT_LAST
	elif event.is_action_pressed(&"drop"):
		_commands.append("drop")
	elif event.is_action_pressed(&"noclip"):
		_toggle_noclip = not _toggle_noclip


## discard_pending also covers a screen that opened and closed between
## samples: the controller compares UiInputScope.gameplay_generation first.
func set_gameplay_blocked(blocked: bool, discard_pending: bool = false) -> void:
	if gameplay_blocked == blocked and not discard_pending:
		return
	gameplay_blocked = blocked
	_discard_pending()
	_remember_held_actions()


func _discard_pending() -> void:
	_pending.clear()
	_commands = PackedStringArray()
	_weapon_select = UserCmd.SELECT_NONE
	_weapon_cycle = 0
	_toggle_noclip = false


func _remember_held_actions() -> void:
	for action: StringName in BUTTONS:
		if Input.is_action_pressed(action):
			_ignored_actions[action] = true
		else:
			_ignored_actions.erase(action)


func _forget_released_actions() -> void:
	for action: StringName in _ignored_actions.keys():
		if not Input.is_action_pressed(action):
			_ignored_actions.erase(action)


func _axis(negative: StringName, positive: StringName) -> float:
	if _ignored_actions.is_empty():
		return Input.get_axis(negative, positive)
	var left := 0.0 if _ignored_actions.has(negative) else Input.get_action_strength(negative)
	var right := 0.0 if _ignored_actions.has(positive) else Input.get_action_strength(positive)
	return right - left


## The console commands asked for since the last call, in order.
func take_commands() -> PackedStringArray:
	var commands := _commands
	_commands = PackedStringArray()
	return commands


func _event(action: StringName, pressed: bool) -> ButtonEvent:
	return ButtonEvent.new(
		action, pressed, Time.get_ticks_usec(), yaw_degrees, pitch_degrees
	)


## Drains the events that happened since the last tick. The caller gets them in
## order with their real timestamps, so a shot can be placed at its exact
## fraction through the tick rather than at the boundary.
func take_events() -> Array[ButtonEvent]:
	var events := _pending
	_pending = []
	return events


## Where in the current tick a timestamp falls, as 0..1. This is the number a
## sub-tick shot is sampled at.
static func tick_fraction(
	timestamp_usec: int, tick_start_usec: int, tick_length_usec: int
) -> float:
	if tick_length_usec <= 0:
		return 0.0
	var offset := timestamp_usec - tick_start_usec
	return clampf(float(offset) / float(tick_length_usec), 0.0, 1.0)


## The direction the player was aiming at a given moment, as a unit vector.
static func aim_direction(yaw_deg: float, pitch_deg: float) -> Vector3:
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(pitch_deg)
	return Vector3(
		-sin(yaw) * cos(pitch),
		sin(pitch),
		-cos(yaw) * cos(pitch)
	)


## The inverse of aim_direction: the yaw and pitch, in degrees, that would
## produce this direction. Used to turn a bullet hole back into the angular
## offset that put it there.
static func angles_from_direction(direction: Vector3) -> Vector2:
	var normalized := direction.normalized()
	return Vector2(
		rad_to_deg(atan2(-normalized.x, -normalized.z)),
		rad_to_deg(asin(clampf(normalized.y, -1.0, 1.0)))
	)


## The command for one tick, from everything that happened since the last
## one was sampled.
##
## The key and mouse events arrive between ticks, while frames are drawn, and
## the tick that runs them comes after. So a command covers the wall-clock
## stretch from the last sample to this one, and each press is placed at its
## fraction of that stretch: the same share of the tick the simulation runs
## it at. Measuring it from when the tick itself began, as this code once
## did, put every press before the start and so at fraction 0, and the
## sub-tick timing never reached the game.
func build_command(tick: int, now_usec: int = -1) -> UserCmd:
	if now_usec < 0:
		now_usec = Time.get_ticks_usec()
	var tick_length := SimClock.tick_usec()
	if _last_sample_usec < 0 or now_usec - _last_sample_usec > 4 * tick_length:
		# The first command, or after a stall: a tick's worth, not a second's.
		_last_sample_usec = now_usec - tick_length
	var window := maxi(now_usec - _last_sample_usec, 1)

	var cmd := UserCmd.new()
	cmd.tick = tick
	cmd.yaw_degrees = yaw_degrees
	cmd.pitch_degrees = pitch_degrees
	if gameplay_blocked:
		_discard_pending()
		_remember_held_actions()
		_last_sample_usec = now_usec
		return cmd
	if not _ignored_actions.is_empty():
		_forget_released_actions()
	# The mouse's buttons count only while the game has the mouse, as the
	# look does: a click in a menu (the buy menu, Escape's free cursor) is
	# not a shot.
	var has_mouse := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	for action: StringName in BUTTONS:
		if Input.is_action_pressed(action) and not _ignored_actions.has(action) \
				and (has_mouse or action not in MOUSE_BUTTONS):
			cmd.buttons |= BUTTONS[action]
	cmd.move = Vector2(
		_axis(&"move_left", &"move_right"),
		_axis(&"move_back", &"move_forward")
	)
	for event in take_events():
		cmd.steps.append(UserCmd.SubtickStep.new(
			BUTTONS[event.action], event.pressed,
			UserCmd.movement_phase(tick_fraction(event.timestamp_usec, _last_sample_usec, window)),
			event.yaw_degrees, event.pitch_degrees
		))
	cmd.weapon_select = _weapon_select
	cmd.weapon_cycle = _weapon_cycle
	cmd.toggle_noclip = _toggle_noclip
	_weapon_select = UserCmd.SELECT_NONE
	_weapon_cycle = 0
	_toggle_noclip = false
	_last_sample_usec = now_usec
	return cmd
