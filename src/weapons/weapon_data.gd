class_name WeaponData
extends Resource

## Everything that decides how a weapon behaves.
##
## IMPORTANT: none of these numbers have been measured against CS2. They come
## from published community figures, which are close but not authoritative, and
## the values that matter most for feel (recoil, inaccuracy) are not published
## at all in a form anyone can copy.
##
## The weapon tuning data in CS2 lives in scripts/weapons.vdata_c and no
## published artifact carries its values, so this cannot be extracted and has
## to be measured:
## https://github.com/CS2OpenDev/CS2OpenDev-SchemaTracker/issues/16
##
## reference/spray_patterns/README.md says how to do the measuring.

## What counts as settled, for both the view punch and the accuracy penalty:
## one percent of the peak. Both of Sid's measurements are of something
## visually reaching rest, and a decaying exponential never reaches zero, so
## the two need a shared threshold to be derived from. One place to change it.
const SETTLE_FRACTION := 0.01

@export var display_name: String = ""

## The weapon's model, as extracted by scripts/extract_assets.sh weapons, and
## the set of first-person clips under animation/anims/viewmodel/rifle that
## animate it. Both are Valve's and live in the gitignored assets/; with them
## missing there are no arms on screen, and nothing else changes.
@export var model_path: String = ""
@export var clip_set: String = ""

# --- Damage ---------------------------------------------------------------

## Damage to an unarmoured chest at point blank.
@export var base_damage: float = 36.0

## Fraction of damage that gets through armour.
@export_range(0.0, 1.0) var armor_penetration: float = 0.775

## Per-hitbox multipliers, applied to base_damage.
@export var head_multiplier: float = 4.0
@export var chest_multiplier: float = 1.0
@export var stomach_multiplier: float = 1.25
@export var leg_multiplier: float = 0.75

## Damage falls off by this factor every falloff_distance units.
@export var range_modifier: float = 0.98
@export var falloff_distance: float = 500.0

## Beyond this the bullet stops entirely.
@export var max_range: float = 8192.0

# --- Rate of fire ---------------------------------------------------------

## Seconds between shots. 600 RPM is 0.1.
@export var cycle_time: float = 0.1

@export var magazine_size: int = 30
@export var reserve_ammo: int = 90

## How long a reload takes.
@export var reload_time: float = 2.5

# --- Movement -------------------------------------------------------------

## Top running speed while holding this weapon, in units per second. The knife
## is 250; rifles are slower.
@export var max_player_speed: float = 215.0

# --- Recoil ---------------------------------------------------------------

## Per-shot aim offsets in degrees, indexed by shot number. This is the spray
## pattern, and it is the single most recognisable thing about a CS weapon.
##
## Loaded from reference/spray_patterns/<name>.csv, which is read off a CS2
## spray plot. The shape is measured; the overall size is an estimate, and
## recoil_scale below is the one knob for correcting it.
@export var recoil_pattern: PackedVector2Array = PackedVector2Array()

## Multiplies every entry in the pattern.
##
## The plots the patterns were read from carry no angular scale, so the size
## of the spray is the one part of it that was not measured. This exists so
## that correcting it is one number against a reference spray, rather than
## thirty rows edited by hand. See reference/spray_patterns/README.md.
@export var recoil_scale: float = 1.0


## How long the trigger has to be off before the spray starts from the top
## again, in seconds.
##
## This is deliberately a time and not a test on how far the view has
## recovered. The first entry of a pattern is (0, 0) by definition, so the
## accumulated punch after shot one is zero, and a recovery test would decide
## the spray had finished before it had started. That bug made every shot
## shot number one and flattened the pattern entirely.
@export var recoil_reset_time: float = 0.4

# --- View punch -----------------------------------------------------------
#
# The view kick and the bullet trajectory are two different things, and this
# is the single most misunderstood part of how CS shoots. The bullets follow
# the spray pattern exactly. The view is given a smaller, springy nudge that
# only suggests the pattern. You cannot read your own recoil off the screen;
# you learn the pattern and pull against it.
#
# Gluing the two together, which is what this used to do, produces a view
# that snaps to each bullet and sags between shots. That is not what CS looks
# like and it is not what CS plays like.

## Degrees the view is kicked UP by each round.
##
## The same for every round in the magazine, which is the whole point. This
## used to be a fraction of the round's own step through the spray pattern,
## and that was wrong: the AK's pattern climbs 2 degrees a shot for the first
## seven rounds and then goes almost flat and almost entirely sideways, so the
## view punched hard twice and then did nothing but sway. A gun does not stop
## recoiling halfway through a magazine.
@export var view_kick_up: float = 0.30

## Degrees the view is kicked SIDEWAYS by each round.
##
## Small, and deliberately not read off the pattern's own sideways step, which
## reaches three degrees a round in the second half of an AK spray. The
## pattern decides the DIRECTION so the view leans the way the gun is actually
## going; this decides how far, so it stays small however far the pattern
## wanders.
@export var view_kick_side: float = 0.06

## How long the visual recoil takes to settle after a shot, in seconds.
##
## MEASURED, from Sid's frame-by-frame capture of CS2: the weapon model is
## tracked away from its resting position and this is where that movement
## levels off. AK-47 644 +- 5 ms, M4A1-S 353 +- 5 ms.
##
## This is the only knob for how long the kick lasts. The spring and the
## damping below are derived from it, so changing it moves the whole
## animation rather than requiring two constants to be re-balanced by hand.
## "Settled" means down to SETTLE_FRACTION of the kick's own peak.
##
## Note what it is NOT: the time the weapon takes to become accurate again.
## Those are separate in CS2 and separate here. See accuracy_reset_time.
@export var recoil_animation_time: float = 0.644

## How the kick is shaped, against how long it lasts.
##
## Source's DecayPunchAngle is an angle with its own velocity, a viscous
## damping term and a torsional spring toward zero; this is that system's
## damping ratio. Under 1.0 it rises into the kick and settles back without a
## visible bounce, which is what CS looks like. Tuned by eye, not measured.
@export_range(0.05, 1.5) var punch_damping_ratio: float = 0.558

## How much the weapon model climbs on its own, on top of the camera.
##
## Small on purpose, and much smaller than it used to be. The model hangs off
## the camera, so it already carries the whole view kick; this is only the gun
## moving relative to the screen. Rotating it happens about the eye, so a
## degree here throws the gun a long way across the screen, and anything but a
## small number reads as the weapon teleporting from shot to shot.
##
## The view kick should be most of what moves. This is the bit on top.
@export_range(0.0, 2.0) var viewmodel_recoil: float = 0.35

## How much of that the model gets sideways, against how much it gets
## vertically. Side to side should be visible and clearly less than the climb,
## which is also how the patterns themselves are shaped.
@export_range(0.0, 1.0) var viewmodel_sway: float = 0.2

# --- Inaccuracy -----------------------------------------------------------

## Cone half-angle in degrees added to every shot, by player state. Standing
## still and not firing should be very close to zero for a rifle; everything
## else opens it up. These are the numbers that make spraying while running
## useless, so they matter as much as the pattern.
@export var inaccuracy_standing: float = 0.02
@export var inaccuracy_crouching: float = 0.015
@export var inaccuracy_moving: float = 0.9
@export var inaccuracy_jumping: float = 4.0

## Added per shot while firing, in degrees.
@export var inaccuracy_per_shot: float = 0.12

## How long a single standing shot takes to become fully accurate again, in
## seconds.
##
## MEASURED, from Sid's frame-by-frame capture of CS2: the accuracy box from
## weapon_debug_spread_show is tracked until it returns to its baseline size.
## AK-47 867 +- 0 ms, M4A1-S 542 +- 0 ms.
##
## This is deliberately a different number from recoil_animation_time, and for
## both weapons it is the LONGER of the two. The gun finishes moving before it
## finishes recovering, so the animation tells you the weapon is ready a couple
## of hundred milliseconds before it is. That desync is real CS2 behaviour and
## reproducing it is the point: a player who taps on the animation is early.
@export var accuracy_reset_time: float = 0.867

## Speed below which movement inaccuracy does not apply. CS lets you walk
## slowly without penalty, which is why counter-strafing matters.
@export var inaccuracy_speed_threshold: float = 55.0


## How high the punch peaks, against the velocity a shot gives it and the
## spring's frequency: peak = impulse / frequency * this. Depends only on the
## damping ratio.
func punch_peak_ratio() -> float:
	var z := _damping_ratio()
	var ringing := sqrt(1.0 - z * z)
	return exp(-z * atan(ringing / z) / ringing)


## The spring's undamped frequency, in radians per second.
##
## Derived so the punch is down to SETTLE_FRACTION of its own peak after
## exactly recoil_animation_time. A damped spring's impulse response decays
## inside an exp(-zeta*w*t) envelope, so zeta*w is what the measurement fixes;
## the peak term is there because the peak is reached some way into the
## response, well below where the envelope starts.
func punch_frequency() -> float:
	var z := _damping_ratio()
	var ringing := sqrt(1.0 - z * z)
	var peak := ringing * punch_peak_ratio()
	return -log(SETTLE_FRACTION * peak) / maxf(
		z * recoil_animation_time, 0.0001
	)


## Viscous damping on the punch velocity, per second.
func punch_damping() -> float:
	return 2.0 * _damping_ratio() * punch_frequency()


## Torsional spring pulling the view back to where the player is pointing.
func punch_spring() -> float:
	var w := punch_frequency()
	return w * w


## What a shot adds to the punch VELOCITY, per degree of view kick asked for.
##
## Normalised against the spring, so the punch peaks at exactly the kick it
## was given and re-measuring recoil_animation_time changes how long the view
## moves without changing how far. Source's ViewPunch pushes the punch
## VELOCITY rather than the angle, which is what makes the view rise into a
## kick instead of teleporting to it; this is that push.
func punch_impulse_scale() -> float:
	return punch_frequency() / punch_peak_ratio()


func _damping_ratio() -> float:
	return clampf(punch_damping_ratio, 0.05, 0.999)


## Time constant of the accuracy decay, in seconds.
##
## Exponential rather than linear, which is both what the measured curve looks
## like on a log scale and what CS:GO's accuracy penalty did. Derived so a
## single shot's penalty falls below the reset threshold in exactly
## accuracy_reset_time; a longer spray therefore takes proportionally longer,
## which is also what CS2 does.
func accuracy_time_constant() -> float:
	return maxf(accuracy_reset_time, 0.0001) / -log(SETTLE_FRACTION)


## Below this fraction of one shot's penalty the weapon counts as fully
## accurate again, matching the measurement's "back to baseline".
func accuracy_reset_threshold() -> float:
	return inaccuracy_per_shot * SETTLE_FRACTION


## The pattern offset for a shot, scaled, holding the last entry once the
## pattern runs out. CS patterns cover the magazine; anything past the end
## should not move.
func recoil_offset(shot_index: int) -> Vector2:
	return RecoilPattern.offset_for(recoil_pattern, shot_index) * recoil_scale


## Damage at a given distance, before armour.
func damage_at(distance: float) -> float:
	return base_damage * pow(range_modifier, distance / falloff_distance)


## Multiplier for a named hitbox.
func hitbox_multiplier(hitbox: StringName) -> float:
	match hitbox:
		&"head": return head_multiplier
		&"chest": return chest_multiplier
		&"stomach": return stomach_multiplier
		&"leg": return leg_multiplier
		_: return chest_multiplier
