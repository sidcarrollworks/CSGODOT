class_name ViewModelMotion
extends RefCounted

## The movement of the arms and weapon on screen that is not animation: the
## bob of walking and running, the settling lower into the hands as you
## run, and the lag of the weapon behind a turn. Cosmetic in full; it
## changes nothing about aim or bullets.
##
## The bob is Source's in shape (CalcViewModelBob): a clock that runs at the
## speed you move, folded into a cycle that rises for cl_bobup of its
## length and falls for the rest, a vertical wave at that rate and a lateral
## one at half of it, both scaled by speed, and applied to the weapon as
## Source did: forward and up with the vertical, sideways with the lateral,
## a little roll, pitch and yaw with each. The amounts are set by eye
## against CS2, whose numbers are not published; the game's bob is slight.
## The sway is not Source's: CS2 lags the weapon behind a turn and springs
## it back, and this is a plain lag that does the same.

## Seconds per bob cycle at full speed, and the fraction of it spent rising.
const BOB_CYCLE := 0.98
const BOB_UP := 0.5
## The speed the bob is full at, in units per second; CS:GO clamps here.
const BOB_FULL_SPEED := 320.0
## Units of bob per unit of speed, before the amounts below.
const BOB_PER_SPEED := 0.005
const BOB_VERTICAL := 0.6
const BOB_LATERAL := 1.0
## How far the weapon settles back and down at full speed, in units.
const BOB_LOWER := 2.1

## Degrees of lag per degree per second of turning, its limit, and how
## quickly it follows (per second).
const SWAY_PER_RATE := 0.008
const SWAY_MAX := 3.5
const SWAY_RESPONSE := 10.0

## Left for the caller to read, in units and degrees.
var vertical_bob: float = 0.0
var lateral_bob: float = 0.0
var sway: Vector2 = Vector2.ZERO

var _bob_time: float = 0.0
var _previous_look: Vector2 = Vector2.ZERO
var _has_look := false


## Advances by delta seconds and returns the offset to apply to the view
## model in the camera's frame: origin in units (right, up, back), basis a
## rotation. velocity is the body's, in units per second; look is the yaw
## and pitch in degrees.
func update(delta: float, velocity: Vector3, on_ground: bool, look: Vector2) -> Transform3D:
	var speed := clampf(Vector2(velocity.x, velocity.z).length(), 0.0, BOB_FULL_SPEED) if on_ground else 0.0
	var fraction := speed / BOB_FULL_SPEED
	_bob_time += delta * fraction
	var bob := bob_at(_bob_time, speed)
	vertical_bob = bob.x
	lateral_bob = bob.y

	if _has_look and delta > 0.0:
		var rate := Vector2(
			angle_difference(deg_to_rad(_previous_look.x), deg_to_rad(look.x)),
			angle_difference(deg_to_rad(_previous_look.y), deg_to_rad(look.y))
		) * (1.0 / delta)
		var target := Vector2(
			clampf(-rad_to_deg(rate.x) * SWAY_PER_RATE, -SWAY_MAX, SWAY_MAX),
			clampf(-rad_to_deg(rate.y) * SWAY_PER_RATE, -SWAY_MAX, SWAY_MAX)
		)
		sway = sway.lerp(target, 1.0 - exp(-delta * SWAY_RESPONSE))
	_previous_look = look
	_has_look = true

	# Source moves the weapon forward and up with the vertical bob and
	# sideways with the lateral, noses it up and rolls it clockwise with the
	# vertical and turns it with the lateral; the lowering is a settle back
	# and down. Godot's frame: right, up, back; pitch up, yaw left, roll
	# anticlockwise.
	var origin := Vector3(
		lateral_bob * 0.8,
		vertical_bob * 0.1 - BOB_LOWER * fraction * 0.5,
		-vertical_bob * 0.4 + BOB_LOWER * fraction
	)
	var basis := Basis.from_euler(Vector3(
		deg_to_rad(vertical_bob * 0.4 + sway.y),
		deg_to_rad(-lateral_bob * 0.3 + sway.x),
		deg_to_rad(-vertical_bob * 0.5)
	))
	return Transform3D(basis, origin)


## The vertical and lateral bob, in units, for a bob clock and a speed.
static func bob_at(bob_time: float, speed: float) -> Vector2:
	var vertical := speed * BOB_PER_SPEED * BOB_VERTICAL
	vertical = vertical * 0.3 + vertical * 0.7 * sin(_cycle(bob_time, BOB_CYCLE))
	var lateral := speed * BOB_PER_SPEED * BOB_LATERAL
	lateral = lateral * 0.3 + lateral * 0.7 * sin(_cycle(bob_time, BOB_CYCLE * 2.0))
	return Vector2(vertical, lateral)


## Where in a cycle of this length the clock is, as an angle: rising over
## the first BOB_UP of it and falling over the rest.
static func _cycle(bob_time: float, length: float) -> float:
	var cycle := fmod(bob_time, length) / length
	if cycle < BOB_UP:
		return PI * cycle / BOB_UP
	return PI + PI * (cycle - BOB_UP) / (1.0 - BOB_UP)
