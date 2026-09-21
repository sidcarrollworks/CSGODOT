class_name MovementConfig
extends Resource

## Every tunable that decides how movement feels, in Source units.
##
## These are STARTING VALUES taken from published CS:GO/CS2 cvar defaults and
## from the Source movement code. They are the thing we tune against the real
## game, so nothing here is settled. When a value changes, record what was
## measured and how in reference/movement_constants.md.

# --- Acceleration model ---------------------------------------------------

## sv_accelerate. Ground acceleration rate. Sources disagree between 5.5 and
## 5.6; measure it.
@export var accelerate: float = 5.5

## sv_airaccelerate. Air acceleration rate. This is the number that decides how
## fast you can air strafe.
@export var air_accelerate: float = 12.0

## sv_friction. Ground friction.
@export var friction: float = 5.2

## sv_stopspeed. Below this speed, friction is applied as if you were moving at
## this speed, which is what makes you stop crisply instead of sliding.
@export var stop_speed: float = 80.0

## sv_air_max_wishspeed. The hard clamp on how much speed air acceleration can
## add toward the wish direction per tick. Air strafing exists because of this
## clamp: you gain speed by turning, not by holding forward.
@export var air_max_wishspeed: float = 30.0

# --- Speeds ---------------------------------------------------------------

## Base running speed with a knife out. Weapons scale this down (AK-47 215,
## M4A1-S 225) once weapons exist.
@export var max_speed: float = 250.0

## Shift-walk multiplier.
@export var walk_modifier: float = 0.52

## Ducked movement multiplier.
@export var duck_modifier: float = 0.34

# --- Gravity and jumping --------------------------------------------------

## sv_gravity.
@export var gravity: float = 800.0

## sv_jump_impulse. Upward velocity set on jump.
@export var jump_impulse: float = 301.993

## Source applies the jump impulse AFTER the leading half-step of gravity, so
## the first tick of a jump travels at the full impulse. That makes jump height
## depend on tick rate: about 58.2 units at 128 Hz and about 59.4 at 64 Hz,
## rather than the 57.0 the physics alone would give.
##
## Leave this false to match Source exactly. Set it true to take the half-step
## off the impulse, which makes jump height 57.0 at any tick rate.
##
## This matters more than it looks. We simulate at 128 Hz and CS2 moves at 64,
## so faithful-to-Source still means our jumps are about a unit shorter than
## CS2's. Measure a real CS2 jump before deciding which way this goes.
@export var tick_rate_independent_jump: bool = false

## sv_autobunnyhopping. CS2 default is off: you have to time the jump yourself.
@export var auto_bunnyhop: bool = false

## sv_enablebunnyhopping. CS2 default is off, which means landing speed is
## capped when you chain jumps. With this false, a jump taken while already
## above the cap is clamped to bunnyhop_speed_cap * max_speed.
@export var enable_bunnyhopping: bool = false

## The multiple of max_speed that a chained jump is clamped to when
## enable_bunnyhopping is false.
@export var bunnyhop_speed_cap: float = 1.1

# --- Player hull ----------------------------------------------------------

## Standing hull: 32 x 32 wide, 72 tall. Ducked height is 54.
@export var hull_width: float = 32.0
@export var stand_height: float = 72.0
@export var duck_height: float = 54.0
@export var stand_eye_height: float = 64.0
@export var duck_eye_height: float = 46.0

## How high a step the player walks up without jumping.
@export var step_height: float = 18.0

## A surface steeper than this angle (degrees from horizontal) is not ground,
## so you slide down it instead of walking on it. This is what makes surf ramps
## surfable. Source uses a 0.7 normal.y threshold, which is ~45.57 degrees.
@export var max_ground_angle_deg: float = 45.57

# --- CS2 quirks -----------------------------------------------------------

## CS2 drops surface friction to 0.25 while vertical velocity is between 0 and
## deadstrafe_max_vertical_speed, and air acceleration multiplies by that
## friction even though the player is airborne. The effect is that air strafing
## is roughly a third as effective for about the first quarter of a jump.
## GoldSrc keeps friction at 1.0 in the air and has no such dead zone.
##
## Leave this true to clone CS2. Set it false for the cleaner GoldSrc feel.
## Anyone who plays a lot of CS2 will notice the difference either way.
@export var cs2_deadstrafe: bool = true
@export var deadstrafe_friction: float = 0.25
@export var deadstrafe_max_vertical_speed: float = 140.0
