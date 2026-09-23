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
## We simulate at 64 Hz, as CS2 moves, so faithful-to-Source gives CS2's 59.4
## if CS2 kept Source's order; at 128 Hz, as this did until 2026-09-23, jumps
## came out about a unit short. Measure a real CS2 jump to confirm it.
@export var tick_rate_independent_jump: bool = false

## Source's NON_JUMP_VELOCITY (gamemovement.cpp:3830). Rising faster than this
## means we definitively left the ground, so the ground trace is skipped for
## the tick. It is NOT half the jump impulse, which is what this used to use.
@export var non_jump_velocity: float = 140.0

## sv_maxvelocity (movevars_shared.cpp:93). Source clamps each velocity axis to
## this twice per tick. It only bites at surf and boost speeds, which is
## exactly where ramp exit angles are decided, so an unclamped axis there
## changes where you get launched.
@export var max_velocity: float = 3500.0

## Split the tick at the instant the jump key was pressed, rather than applying
## the impulse at the tick boundary. CS2 sends every button transition with a
## fractional timestamp (CSubtickMoveStep), and this is the local equivalent.
##
## It is the difference between a chained hop landing when you pressed it and
## landing up to a tick (15.6 ms) later, which is what makes bunny hopping feel
## reliable.
@export var subtick_jump: bool = true

## sv_autobunnyhopping. CS2 default is off: you have to time the jump yourself.
@export var auto_bunnyhop: bool = false

## sv_enablebunnyhopping. CS2 default is off, which means landing speed is
## capped when you chain jumps. With this false, a jump taken while already
## above the cap is clamped to bunnyhop_speed_cap * max_speed.
@export var enable_bunnyhopping: bool = false

## The multiple of max_speed that a chained jump is clamped to when
## enable_bunnyhopping is false.
@export var bunnyhop_speed_cap: float = 1.1

## Fly speed with noclip on. Not a gameplay value: noclip exists so you can
## find your way around a freshly imported map that has no spawn points yet.
@export var noclip_speed: float = 1200.0

# --- Player hull ----------------------------------------------------------

## Standing hull: 32 x 32 wide, 72 tall. Ducked height is 54.
@export var hull_width: float = 32.0
@export var stand_height: float = 72.0
@export var duck_height: float = 54.0
@export var stand_eye_height: float = 64.0
@export var duck_eye_height: float = 46.0

## How long a full duck takes on the ground. Ducking in the air is instant,
## which is what makes a crouch jump work: the hull shrinks upward, your feet
## come up with it, and you clear a ledge the standing jump could not.
@export var duck_time: float = 0.4

## How high a step the player walks up without jumping.
@export var step_height: float = 18.0

## A surface steeper than this angle (degrees from horizontal) is not ground,
## so you slide down it instead of walking on it. This is what makes surf ramps
## surfable. Source uses a 0.7 normal.y threshold, which is ~45.57 degrees.
@export var max_ground_angle_deg: float = 45.57

# --- Divergences from Source ----------------------------------------------

## Source's WalkMove flattens the move direction to the horizontal plane and
## never consults the ground normal (gamemovement.cpp:1893). Projecting the
## wish direction onto the slope instead stops a little speed bleeding into
## the ground plane when walking uphill, which is arguably better and is
## definitely not what CS2 does.
##
## False is faithful. True is the nicer-feeling divergence. It is a flag rather
## than a silent choice because it changes every slope on dust2.
@export var project_wish_dir_on_ground: bool = false

## Source glues the player to the ground for a full step height after every
## walk move (StayOnGround, gamemovement.cpp:1857). Without it, running down
## stairs or any shallow decline goes airborne for a few ticks at a time,
## which drops ground friction and ground acceleration and reads as floaty.
##
## True is faithful. False is here only so the difference can be measured.
@export var stay_on_ground: bool = true

## How far the body is pushed back out along a collision normal after each
## collide-and-slide iteration.
##
## Source does not do this at all: it relies on the trace stopping short by
## DIST_EPSILON and never adds position. s&box considered it and left the line
## commented out. With four bumps a tick (measured at 128 Hz), a non-zero
## value here injects outward drift while sliding along a surface, which
## bleeds speed off a surf ramp. Godot's own safe_margin already keeps us out of the geometry,
## so the default is zero.
##
## Kept as a tunable rather than deleted so the surf complaint can be falsified
## from both sides without editing code.
@export var trace_epsilon: float = 0.0

# --- Surface friction -----------------------------------------------------

## Surface friction drops to 0.25 while vertical velocity is between 0 and
## deadstrafe_max_vertical_speed, and air acceleration multiplies by that
## friction even though the player is airborne. The effect is that air strafing
## is roughly a third as effective for about the first quarter of a jump.
## GoldSrc keeps friction at 1.0 in the air and has no such dead zone.
##
## This is NOT a CS2 quirk, whatever it gets called in the community. It is
## Source 1 behaviour and it is in the public SDK: CategorizePosition resets
## m_surfaceFriction to 1.0, and assigns 0.25 when the ground trace finds
## nothing walkable while moving up (gamemovement.cpp:3871-3877). The upper
## bound is real too, because above NON_JUMP_VELOCITY (gamemovement.cpp:3830)
## Source skips the ground trace entirely, so the 0.25 never gets assigned.
##
## It was called cs2_deadstrafe, which invited someone to "fix" correct Source
## behaviour later. Leave it true unless you specifically want the GoldSrc
## feel; anyone who plays a lot of CS will notice either way.
@export var source_deadstrafe: bool = true
@export var deadstrafe_friction: float = 0.25
@export var deadstrafe_max_vertical_speed: float = 140.0
