class_name PlayerInput
extends RefCounted

## Input sampling with timestamps.
##
## Why this exists before there is anything to shoot: CS2's sub-tick model
## evaluates a shot at the instant the button went down, not at the next
## simulation tick. At 128 Hz a tick is 7.8 ms, so snapping shots to tick
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
## up to 7.8 ms ago. Recording both is what makes a sub-tick shot actually
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
	&"jump": UserCmd.JUMP,
	&"duck": UserCmd.DUCK,
	&"walk": UserCmd.WALK,
	&"reload": UserCmd.RELOAD,
}

var _pending: Array[ButtonEvent] = []
var _weapon_select: int = UserCmd.SELECT_NONE
var _toggle_noclip: bool = false
## When the last command was sampled, on the wall clock: the start of the
## stretch the next one covers.
var _last_sample_usec: int = -1

## Look angles accumulate at render rate, not tick rate. Mouse movement must
## never be quantised to the simulation tick or aiming feels heavy.
var yaw_degrees: float = 0.0
var pitch_degrees: float = 0.0

## CS2 semantics: the game turns m_yaw (0.022 degrees) per mouse count per
## point of sensitivity, so this is the same number you would type in CS2.
var sensitivity: float = 2.0
const CS_YAW_PER_COUNT := 0.022

const PITCH_LIMIT := 89.0


func handle_event(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		yaw_degrees -= motion.relative.x * sensitivity * CS_YAW_PER_COUNT
		pitch_degrees -= motion.relative.y * sensitivity * CS_YAW_PER_COUNT
		pitch_degrees = clampf(pitch_degrees, -PITCH_LIMIT, PITCH_LIMIT)
		return

	for action: StringName in BUTTONS:
		if event.is_action_pressed(action, false):
			_pending.append(_event(action, true))
		elif event.is_action_released(action):
			_pending.append(_event(action, false))

	if event.is_action_pressed(&"slot1"):
		_weapon_select = 1
	elif event.is_action_pressed(&"slot2"):
		_weapon_select = 2
	elif event.is_action_pressed(&"noclip"):
		_toggle_noclip = not _toggle_noclip


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
	for action: StringName in BUTTONS:
		if Input.is_action_pressed(action):
			cmd.buttons |= BUTTONS[action]
	cmd.move = Vector2(
		Input.get_axis(&"move_left", &"move_right"),
		Input.get_axis(&"move_back", &"move_forward")
	)
	cmd.yaw_degrees = yaw_degrees
	cmd.pitch_degrees = pitch_degrees
	for event in take_events():
		cmd.steps.append(UserCmd.SubtickStep.new(
			BUTTONS[event.action], event.pressed,
			tick_fraction(event.timestamp_usec, _last_sample_usec, window),
			event.yaw_degrees, event.pitch_degrees
		))
	cmd.weapon_select = _weapon_select
	cmd.toggle_noclip = _toggle_noclip
	_weapon_select = UserCmd.SELECT_NONE
	_toggle_noclip = false
	_last_sample_usec = now_usec
	return cmd
