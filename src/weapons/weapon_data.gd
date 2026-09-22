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

## The tick the punch spring is integrated at, and the one the solver below
## walks a spray with.
const SIMULATION_HZ := 128.0

var _solved_kick_up: float = -1.0

## A punch angle with its own velocity, damped, with a spring pulling it back
## to zero. Source's DecayPunchAngle.
##
## Two of these are in flight at once and they are deliberately different: the
## camera's settles over about two seconds so the crosshair climbs with a
## spray, the weapon model's over the few hundred milliseconds that were
## measured off CS2.
class Punch:
	var value := Vector2.ZERO
	var velocity := Vector2.ZERO

	## A round's kick, as a push on the VELOCITY rather than a jump in the
	## angle, which is what makes the punch rise into a kick over several
	## ticks instead of teleporting to it.
	func kick(impulse: Vector2) -> void:
		velocity += impulse

	## Runs the spring forward, substepped so the result does not depend on
	## the caller's frame length.
	##
	## Leapfrog: half a step of spring and damping, a whole step of movement
	## at that mid-step velocity, then the other half. Moving on the
	## end-of-step velocity instead biases the punch upward by half a tick of
	## it, which is small on a slow spring and not small on a fast one, so the
	## same weapon would throw further just for settling sooner.
	##
	## exp() rather than (1 - damping * step) for the same reason: the linear
	## form takes more out of the velocity than the damping it stands for
	## would, which cut the punch short of the time it is derived from.
	func advance(dt: float, damping: float, spring: float, max_step: float) -> void:
		if value.length_squared() < 1e-10 and velocity.length_squared() < 1e-10:
			value = Vector2.ZERO
			velocity = Vector2.ZERO
			return
		var remaining := dt
		while remaining > 0.0:
			var step := minf(remaining, max_step)
			var half := step * 0.5
			velocity *= exp(-damping * half)
			velocity -= value * spring * half
			value += velocity * step
			velocity -= value * spring * half
			velocity *= exp(-damping * half)
			remaining -= step


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

## Where the crosshair peaks during a held spray, as a fraction of how far
## the bullets climb over that same spray.
##
## This is the one knob for how hard the view kicks, and it is expressed as
## the thing you can actually see rather than as a per-round amount: the
## per-round kick is solved from it. Changing the spring, the fire rate or the
## pattern therefore moves the kick and leaves this alone.
##
## Sid read half the spray's height off CS2 on 2026-09-22 and that is what
## this is. It was tried once at half with the camera on the weapon model's
## own recovery time, which made it far too high in the hand: the crosshair
## got there in two rounds and a single tap threw the view five degrees. The
## reading was right; what was wrong was how quickly the view got there.
@export_range(0.0, 1.0) var view_kick_spray_peak: float = 0.5

## How far the view is kicked sideways each round, against how far up.
##
## Deliberately not read off the pattern's own sideways step, which reaches
## three degrees a round in the second half of an AK spray. The pattern
## decides the DIRECTION so the view leans the way the gun is going; this
## decides how far, so it stays small however far the pattern wanders.
@export_range(0.0, 1.0) var view_kick_side_ratio: float = 0.2

## How long the WEAPON MODEL's recoil takes to settle after a round, in
## seconds.
##
## MEASURED, from Sid's frame-by-frame capture of CS2: the weapon model is
## tracked away from its resting position and this is where that movement
## levels off. AK-47 644 +- 5 ms, M4A1-S 353 +- 5 ms. "Settled" means down to
## SETTLE_FRACTION of the kick's own peak.
##
## The camera is a separate system with a separate, much longer recovery: see
## view_punch_recovery_time. Driving both off this number was a mistake worth
## not repeating. It made the crosshair reach its full height within two or
## three rounds and sit there, when it should climb with the spray, and it
## forced the per-round kick so high that a single tap threw the view five
## degrees.
##
## Nor is it the time the weapon takes to become accurate again: see
## accuracy_reset_time.
@export var recoil_animation_time: float = 0.644

## How long the CAMERA's slow half takes to settle after a round, in seconds.
##
## Not measured, and much longer than the weapon model's. It has to be: the
## crosshair should climb with the spray over a magazine rather than reach its
## height in the first few rounds, and that only happens if a round's kick is
## still there when the next few land.
##
## Sid, 2026-09-22: "the crosshair still needs to move up about halfway as the
## shots go up. It maxes out about 3 shots up."
@export var view_punch_recovery_time: float = 1.9

## How long the CAMERA's fast half takes to settle after a round, in seconds.
##
## The camera's kick is two springs added together, and this is why. One
## spring cannot rise fast and fall slowly: a damped spring's rise and its
## decay are the same two constants read two ways, and making it rise in a
## few ticks makes it fall in a few ticks too. Slow enough to accumulate over
## a spray is therefore also smooth enough to have no per-round kick in it at
## all, which is what a single spring gave: a clean ramp with no shots in it.
##
## Sid, 2026-09-22: "the motion as it moves up is too smooth. we still want it
## to feel staccato, like each shot pushes it up."
##
## Short enough to land inside the gap between rounds at 600 RPM, so each
## round reads as its own shove.
@export var view_punch_snap_time: float = 0.18

## How much of a round's kick goes to the fast half.
##
## The rest goes to the slow one. This is the balance between "you can see
## each shot" and "the crosshair holds its height through the spray"; both
## halves are wanted and neither should have all of it.
@export_range(0.0, 1.0) var view_kick_snap_share: float = 0.4

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


## How high a punch peaks, against the velocity a shot gives it and the
## spring's frequency: peak = impulse / frequency * this. Depends only on the
## damping ratio.
func punch_peak_ratio() -> float:
	var z := _damping_ratio()
	var ringing := sqrt(1.0 - z * z)
	return exp(-z * atan(ringing / z) / ringing)


## A spring's undamped frequency, in radians per second, for a punch that
## should be down to SETTLE_FRACTION of its own peak after `recovery`.
##
## A damped spring's impulse response decays inside an exp(-zeta*w*t)
## envelope, so zeta*w is what the recovery time fixes; the peak term is there
## because the peak is reached some way into the response, well below where
## the envelope starts.
func punch_frequency_for(recovery: float) -> float:
	var z := _damping_ratio()
	var ringing := sqrt(1.0 - z * z)
	var peak := ringing * punch_peak_ratio()
	return -log(SETTLE_FRACTION * peak) / maxf(z * recovery, 0.0001)


func punch_damping_for(recovery: float) -> float:
	return 2.0 * _damping_ratio() * punch_frequency_for(recovery)


func punch_spring_for(recovery: float) -> float:
	var w := punch_frequency_for(recovery)
	return w * w


## What a round adds to a punch's VELOCITY, per degree of kick asked for.
##
## Normalised against the spring, so one round's punch peaks at exactly the
## kick it was given and changing a recovery time moves how long that punch
## lasts without moving how far it throws. Source's ViewPunch pushes the punch
## VELOCITY rather than the angle, which is what makes it rise into a kick
## instead of teleporting to it; this is that push.
func punch_impulse_scale_for(recovery: float) -> float:
	return punch_frequency_for(recovery) / punch_peak_ratio()


## The camera's slow half: what carries the crosshair up the spray.
func hold_punch_damping() -> float:
	return punch_damping_for(view_punch_recovery_time)


func hold_punch_spring() -> float:
	return punch_spring_for(view_punch_recovery_time)


func hold_punch_impulse_scale() -> float:
	return punch_impulse_scale_for(view_punch_recovery_time) * (
		1.0 - view_kick_snap_share
	)


## The camera's fast half: what makes each round its own shove.
func snap_punch_damping() -> float:
	return punch_damping_for(view_punch_snap_time)


func snap_punch_spring() -> float:
	return punch_spring_for(view_punch_snap_time)


func snap_punch_impulse_scale() -> float:
	return punch_impulse_scale_for(view_punch_snap_time) * view_kick_snap_share


## The weapon model's own spring, which settles far sooner than the camera's.
func model_punch_damping() -> float:
	return punch_damping_for(recoil_animation_time)


func model_punch_spring() -> float:
	return punch_spring_for(recoil_animation_time)


func model_punch_impulse_scale() -> float:
	return punch_impulse_scale_for(recoil_animation_time)


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


## Degrees the view is kicked UP by each round, solved so that holding the
## trigger for a magazine peaks the crosshair at view_kick_spray_peak of the
## spray's own climb.
##
## The same on every round. It used to be a fraction of the round's step
## through the pattern, and that was wrong: a pattern's vertical steps are
## front-loaded and its sideways steps are not, so the view punched hard for
## the first two rounds and then did nothing but sway. A gun does not stop
## recoiling halfway through a magazine.
func view_kick_up() -> float:
	if _solved_kick_up >= 0.0:
		return _solved_kick_up
	var climb := 0.0
	for i in recoil_pattern.size():
		climb = maxf(climb, recoil_offset(i).y)
	var unit_peak := spray_peak_per_degree()
	if climb <= 0.0 or unit_peak <= 0.0:
		_solved_kick_up = 0.0
	else:
		_solved_kick_up = view_kick_spray_peak * climb / unit_peak
	return _solved_kick_up


## Degrees sideways per round.
func view_kick_side() -> float:
	return view_kick_up() * view_kick_side_ratio


## How high the punch would peak over a magazine held down, per degree of
## per-round kick.
##
## The spring is linear, so one pass with a unit kick scales to any kick, and
## view_kick_up is one division rather than a search. There is a test that
## this agrees with what Weapon actually produces, since the two integrate the
## same spring in two places.
func spray_peak_per_degree() -> float:
	var tick := 1.0 / SIMULATION_HZ
	var snap := Punch.new()
	var hold := Punch.new()
	var snap_damping := snap_punch_damping()
	var snap_spring := snap_punch_spring()
	var snap_impulse := snap_punch_impulse_scale()
	var hold_damping := hold_punch_damping()
	var hold_spring := hold_punch_spring()
	var hold_impulse := hold_punch_impulse_scale()
	var peak := 0.0
	var until_shot := 0.0
	for tick_index in maxi(magazine_size, 1) * maxi(int(cycle_time * SIMULATION_HZ), 1):
		if until_shot <= 0.0:
			snap.kick(Vector2(0.0, snap_impulse))
			hold.kick(Vector2(0.0, hold_impulse))
			until_shot += cycle_time
		until_shot -= tick
		snap.advance(tick, snap_damping, snap_spring, tick)
		hold.advance(tick, hold_damping, hold_spring, tick)
		peak = maxf(peak, snap.value.y + hold.value.y)
	return peak


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
