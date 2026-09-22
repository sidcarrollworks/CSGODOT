class_name UserCmd
extends RefCounted

## One tick of one player's input: everything the simulation needs from the
## player to run that player forward one tick, and nothing it does not.
##
## This is the shape of CS2's user command (CBaseUserCmdPB in
## usercmd.proto, published by SteamDatabase's GameTracking-CS2): the tick it
## is for, the buttons held, the move keys, where the player was looking at
## the end of the tick, and every button that went down or up during the
## tick with the fraction of the tick at which it happened
## (CSubtickMoveStep's `when`) and the look angles at that instant.
##
## Everything that plays the game is driven by these: the local player's
## keys become one per tick (PlayerInput.build_command), a bot's brain writes
## one per tick, and later a client sends them to a server. The simulation
## never reads Godot's Input, the wall clock or anything on screen, so the
## same commands run on the same state give the same game.

## Buttons, as bits of `buttons` (held at the end of the tick) and as the
## button of a SubtickStep.
const ATTACK := 1
const JUMP := 2
const DUCK := 4
const WALK := 8
const RELOAD := 16

## Weapon slots a command can ask to switch to (`weapon_select`), until
## there is an inventory; 0 asks for nothing.
const SELECT_NONE := 0


## One button going down or up inside the tick.
class SubtickStep:
	var button: int
	var pressed: bool
	## How far through the tick it happened, 0 at its start and 1 at its end.
	var when: float
	## Where the player was looking at that instant.
	var yaw_degrees: float
	var pitch_degrees: float

	func _init(
		p_button: int, p_pressed: bool, p_when: float, p_yaw: float, p_pitch: float
	) -> void:
		button = p_button
		pressed = p_pressed
		when = p_when
		yaw_degrees = p_yaw
		pitch_degrees = p_pitch


## The simulation tick this command runs (Engine.get_physics_frames()).
var tick: int = 0
## Buttons held at the end of the tick.
var buttons: int = 0
## The move keys: x right (+1) or left (-1), y forward (+1) or back (-1).
var move: Vector2 = Vector2.ZERO
## Where the player was looking at the end of the tick, in degrees.
var yaw_degrees: float = 0.0
var pitch_degrees: float = 0.0
## Transitions during the tick, in the order they happened.
var steps: Array[SubtickStep] = []
## A weapon to switch to (WeaponLibrary's slot numbers), or SELECT_NONE.
var weapon_select: int = SELECT_NONE
## Noclip on or off this tick. A developer's key; CS has it as a command.
var toggle_noclip: bool = false


func held(button: int) -> bool:
	return buttons & button != 0


## Whether the button went down at any point in the tick, held at its end or
## not: a tap shorter than a tick still counts.
func pressed_during(button: int) -> bool:
	for step in steps:
		if step.button == button and step.pressed:
			return true
	return false


## The first press of the button in the tick, or null.
func first_press(button: int) -> SubtickStep:
	for step in steps:
		if step.button == button and step.pressed:
			return step
	return null


## Every press of the button in the tick, in order.
func presses(button: int) -> Array[SubtickStep]:
	var found: Array[SubtickStep] = []
	for step in steps:
		if step.button == button and step.pressed:
			found.append(step)
	return found


## The flat direction the move keys ask for, in world space, from the yaw at
## the end of the tick; zero when no key is down.
func wish_direction() -> Vector3:
	var keys := move
	if keys.length_squared() > 1.0:
		keys = keys.normalized()
	var yaw := deg_to_rad(yaw_degrees)
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var dir := right * keys.x + forward * keys.y
	if dir.length_squared() > 0.0:
		dir = dir.normalized()
	return dir


## The move keys that ask for a world direction, facing a yaw: the inverse of
## wish_direction, for a bot that knows where it wants to go.
static func move_toward(direction: Vector3, yaw: float) -> Vector2:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() == 0.0:
		return Vector2.ZERO
	flat = flat.normalized()
	var radians := deg_to_rad(yaw)
	var forward := Vector3(-sin(radians), 0.0, -cos(radians))
	var right := Vector3(cos(radians), 0.0, -sin(radians))
	return Vector2(flat.dot(right), flat.dot(forward))
