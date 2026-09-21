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

## One button transition, with the moment it actually happened.
class ButtonEvent:
	var action: StringName
	var pressed: bool
	## Microseconds, from Time.get_ticks_usec().
	var timestamp_usec: int

	func _init(p_action: StringName, p_pressed: bool, p_timestamp_usec: int) -> void:
		action = p_action
		pressed = p_pressed
		timestamp_usec = p_timestamp_usec


var _pending: Array[ButtonEvent] = []

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

	for action in [&"jump", &"duck", &"walk", &"attack"]:
		if event.is_action_pressed(action, false):
			_pending.append(ButtonEvent.new(action, true, Time.get_ticks_usec()))
		elif event.is_action_released(action):
			_pending.append(ButtonEvent.new(action, false, Time.get_ticks_usec()))


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


## The movement direction the player is asking for, in world space, from the
## currently held keys and the current yaw.
func wish_direction() -> Vector3:
	var input := Vector2(
		Input.get_axis(&"move_left", &"move_right"),
		Input.get_axis(&"move_back", &"move_forward")
	)
	if input.length_squared() > 1.0:
		input = input.normalized()
	var yaw := deg_to_rad(yaw_degrees)
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var dir := right * input.x + forward * input.y
	if dir.length_squared() > 0.0:
		dir = dir.normalized()
	return dir
