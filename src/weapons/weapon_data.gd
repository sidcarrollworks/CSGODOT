class_name WeaponData
extends Resource

## Everything that decides how a weapon behaves.
##
## The damage, armour, falloff, fire rate, ammunition, speed, inaccuracy and
## recovery figures, and when a reload lets the gun fire again, come from
## CS2's own tuning, scripts/weapons.vdata_c, through WeaponVData; the CS2
## Weapon Spreadsheet (WeaponSheet) is read first and supplies only the
## landing and ladder figures (see WeaponLibrary and
## reference/weapon_stats.md). The spray patterns and recovery timings were
## measured in CS2 by hand:
## https://github.com/CS2OpenDev/CS2OpenDev-SchemaTracker/issues/16
##
## reference/spray_patterns/README.md says how to do the measuring.

## What counts as settled, for both the view punch and the accuracy penalty:
## one percent of the peak. Both of Sid's measurements are of something
## visually reaching rest, and a decaying exponential never reaches zero, so
## the two need a shared threshold to be derived from. One place to change it.
const SETTLE_FRACTION := 0.01

## The rate the punch spring is integrated at, and the one the solver below
## walks a spray with: finer than the game's 64 Hz tick, and what the
## punch's numbers were solved and measured at. It is the spring's own step,
## not the simulation's; Weapon steps it this finely whatever it is handed.
const PUNCH_HZ := 128.0


var _solved_kick_up: float = -1.0
var _solved_model_hold_time: float = -1.0

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
## CS2's class name for the gun (weapon_ak47): what its damage, its kills and
## its place in the item registry go by (ItemRegistry).
@export var item_class: String = ""

## The weapon's model, as extracted by scripts/extract_assets.sh weapons, and
## the set of first-person clips under animation/anims/viewmodel/rifle that
## animate it. Both are Valve's and live in the gitignored assets/; with them
## missing there are no arms on screen, and nothing else changes.
@export var model_path: String = ""
@export var clip_set: String = ""
## Its own third-person set, under animation/anims/world (rifle/rifle_ak):
## the hold, draw, reload and shot the body plays over its locomotion.
@export var world_clip_set: String = ""

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

## Rounds a trigger pull puts out: 1, or a shotgun's pellets
## (m_nNumBullets), each traced and damaged on its own (Weapon.Shot.pellet).
@export var pellets: int = 1

## How well a round carries through walls and props, as the game gives it
## (m_flPenetration: 2.0 for rifles, 1.0 for SMGs): how far through each
## surface it gets, and how little damage it loses (Penetration).
@export var penetration_power: float = 2.0

## How much of a victim's speed a hit takes away (0.6 for rifles): an AK-47
## round leaves its victim 40% of their speed (PlayerSim's tagging). It is
## CS2's m_flFlinchVelocityModifierLarge taken from one, read from the game
## through WeaponVData (the sheet's Tagging Power agrees). The game's
## m_flFlinchVelocityModifierSmall, in reference/weapons/vdata.csv for every
## gun, is not used until how CS2 applies it is measured (roadmap item 4a).
@export var tagging_power: float = 0.6

# --- Rate of fire ---------------------------------------------------------

## Seconds between shots. 600 RPM is 0.1.
@export var cycle_time: float = 0.1

## Whether holding the trigger keeps firing (the game's m_bIsFullAuto, the sheet's "hold to shoot").
## Both rifles are; most pistols are not.
@export var automatic: bool = true

@export var magazine_size: int = 30
@export var reserve_ammo: int = 90

## How long a reload takes.
@export var reload_time: float = 2.5

# --- Movement -------------------------------------------------------------

## Top running speed while holding this weapon, in units per second. The knife
## is 250; rifles are slower.
@export var max_player_speed: float = 215.0

# --- Scope ----------------------------------------------------------------

## The field of view at each zoom level, in CS2's degrees (horizontal at
## 4:3, where unzoomed is 90): the game's m_nZoomFOV1 and m_nZoomFOV2, as
## many as it has levels (m_nZoomLevels). Empty for a gun with no scope.
## The AWP's are 40 and 10; the AUG's and SG 553's one is 45.
@export var zoom_fovs: PackedFloat32Array = PackedFloat32Array()
## How long the view takes to reach each level, level 0 (unzoomed) first:
## the game's m_flZoomTime0 to 2. Read as the time to reach level N rather
## than into 1, into 2 and out, as reference/research/combat.md
## (correction 4) argues; either reading gives the AWP 0.05 s everywhere.
@export var zoom_times: PackedFloat32Array = PackedFloat32Array()
## The AWP and SSG 08 come out of the scope as they fire and go back in
## once the bolt is worked (m_bUnzoomsAfterShot, and CS2's
## cl_sniper_auto_rezoom, on by default).
@export var unzooms_after_shot: bool = false
## The snipers put the arms and gun away while scoped and draw the scope
## instead (m_bHideViewModelWhenZoomed); the AUG and SG 553 keep them.
@export var hides_view_model_when_zoomed: bool = false
## Whether the crosshair is drawn with it in hand (m_bShowCrosshair): not
## for the four snipers, whose only aim is the scope.
@export var shows_crosshair: bool = true
## The gun scoped: the game's second values for speed, inaccuracy and
## recovery (and the sheet's "(scoped)" row for landing and ladders). Null
## for a gun with no scope.
@export var scoped: WeaponData


## How many zoom levels the gun has: 0 for none.
func zoom_levels() -> int:
	return zoom_fovs.size()


## The field of view at a zoom level, in CS2's degrees: 90 at level 0.
func zoom_fov(level: int) -> float:
	if level <= 0 or level > zoom_fovs.size():
		return UNZOOMED_FOV
	return zoom_fovs[level - 1]


## How long the view takes to get to a zoom level, in seconds.
func zoom_time(level: int) -> float:
	if level < 0 or level >= zoom_times.size():
		return 0.0
	return zoom_times[level]


## CS2's fov with no scope.
const UNZOOMED_FOV := 90.0

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
## recovery_time_stand.
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

## How long the camera's slow half takes to settle once the trigger is OFF,
## in seconds.
##
## Shorter than view_punch_recovery_time, and separate from it because the two
## are wanted for opposite reasons. The long recovery exists so a round's kick
## is still there when the next few land, which is what carries the crosshair
## up a spray. Nothing is landing after the last round, so keeping it long
## there only leaves the view hanging.
##
## CS has the same split: its recoil index recovers between rounds, not while
## they are going out.
##
## Sid, 2026-09-22: "let's also make the decay when you stop shooting a little
## short. It feels a bit too floating at the moment."
@export var view_punch_release_time: float = 0.7

## How long after the last round the trigger counts as still down, in rounds.
##
## The camera cannot see the trigger, so it infers it from the gap since the
## last round. Anything above 1 keeps a spray from being mistaken for a release
## in the gap between two of its own rounds; everything above 1 is also dead
## time at the top of the spray, where the crosshair has stopped climbing and
## has not started coming down. At 2 that dead time was 200 ms on the AK and
## Sid felt exactly that: "it still feels like it hangs at the top for 200ms."
##
## A round is gated by the cycle time exactly, so the gap between two rounds of
## a spray never exceeds one cycle plus the tick the check runs on. 1.25 clears
## that with room and costs 125 ms rather than 200.
@export var trigger_release_cycles: float = 1.25

## How much of a round's kick goes to the fast half.
##
## The rest goes to the slow one. This is the balance between "you can see
## each shot" and "the crosshair holds its height through the spray"; both
## halves are wanted and neither should have all of it.
@export_range(0.0, 1.0) var view_kick_snap_share: float = 0.4

## How long the WEAPON MODEL's fast half takes to settle after a round, in
## seconds.
##
## The gun needs the same two-spring treatment the camera got, for the same
## reason and then one more. CS2 does not run a spring on the weapon model at
## all: it replays the firing clip from the start on every round, so the gun
## drops back towards rest between rounds however fast they come. A single
## spring long enough to last the measured animation reaches its own peak
## about 78 ms in, and the next round lands at 100 ms, so it never gets to
## fall: the gun climbed to a height and jittered there for the rest of the
## magazine.
##
## Sid, 2026-09-22: "the animation doesn't continually fall. It pushes up till
## you stop holding the mouse button. The animation needs to fall a little
## between shots."
##
## Short enough that a round's own shove is most of the way home before the
## next one lands.
@export var model_punch_snap_time: float = 0.1

## How much of a round's kick goes to the weapon model's fast half.
##
## Higher than the camera's share: the gun is meant to drop back between
## rounds, where the crosshair is meant to climb with the spray.
@export_range(0.0, 1.0) var model_kick_snap_share: float = 0.75

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

## Cone half-angle in degrees, by player state, each a TOTAL the way the
## weapon spreadsheet gives them: standing still, crouched, at full run, and
## at the top of a standing jump. Moving and jumping add up (see
## Weapon.current_inaccuracy). These are the numbers that make spraying while
## running useless, so they matter as much as the pattern. The defaults are
## the AK-47's; WeaponLibrary.cs_inaccuracy converts the sheet's units.
@export var inaccuracy_standing: float = 0.4016
@export var inaccuracy_crouching: float = 0.31
@export var inaccuracy_moving: float = 10.32
@export var inaccuracy_jumping: float = 8.41

## The gun's own spread (m_flSpread), in degrees: the part of each total
## above that is the gun rather than how it is held. A gun of one round
## fires into the whole total. A shotgun's pellets keep a fixed pattern
## this wide round the round's aim, and the rest of the total, what moving,
## jumping and firing add, throws that aim (Weapon.fire).
@export var spread: float = 0.0
## Seeds a shotgun's pellet pattern (m_nSpreadSeed; only the four shotguns
## have one), so a gun's pattern is the same every shot.
@export var spread_seed: int = 0

## Added per shot while firing, in degrees.
@export var inaccuracy_per_shot: float = 0.447

## Inaccuracy on a ladder, and the penalty landing from a jump puts on, both
## totals in degrees like the rest. Landing adds its excess over standing to
## the firing penalty, which then recovers the way a round's does.
@export var inaccuracy_ladder: float = 15.67
@export var inaccuracy_landing: float = 1.93

## How long the accuracy penalty takes to fall to a tenth, standing and
## crouched, in seconds: the game's recovery times (as the sheet has them), which are how CS
## defines them.
##
## This is deliberately separate from recoil_animation_time, and longer for
## both rifles once read to the same threshold: the gun finishes moving before
## it finishes recovering, so the animation tells you the weapon is ready
## before it is. A player who taps on the animation is early.
##
## Sid measured the AK back to baseline at 867 ms and the M4A1-S at 542 ms
## off weapon_debug_spread_show on 2026-09-22. Taken at a hundredth, the
## sheet gives 736 and 678.
@export var recovery_time_stand: float = 0.368
@export var recovery_time_crouch: float = 0.305257



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
func punch_frequency_for(recovery: float, ratio: float = -1.0) -> float:
	var z := _damping_ratio(ratio)
	var ringing := sqrt(1.0 - z * z)
	var peak := ringing * punch_peak_ratio()
	return -log(SETTLE_FRACTION * peak) / maxf(z * recovery, 0.0001)


func punch_damping_for(recovery: float, ratio: float = -1.0) -> float:
	return 2.0 * _damping_ratio(ratio) * punch_frequency_for(recovery, ratio)


func punch_spring_for(recovery: float, ratio: float = -1.0) -> float:
	var w := punch_frequency_for(recovery, ratio)
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


## The camera's slow half: what carries the crosshair up the spray while the
## trigger is down, and lets go of it once the trigger is up.
func hold_punch_damping(firing: bool = true) -> float:
	if firing:
		return punch_damping_for(view_punch_recovery_time)
	return 2.0 * release_frequency()


func hold_punch_spring(firing: bool = true) -> float:
	if firing:
		return punch_spring_for(view_punch_recovery_time)
	var w := release_frequency()
	return w * w


## The frequency the slow half returns on once the trigger is up, in radians
## per second.
##
## Critically damped, and Weapon gives it exactly minus this times its own
## height as a velocity at the moment the trigger goes up. That combination is
## not arbitrary: a critically damped spring released at height V with velocity
## -wV is exactly V*exp(-w*t), the only shape the second-order system can make
## that is a plain exponential decay.
##
## That is the shape Sid asked for. A spring let go from rest starts with no
## speed at all, builds up and then eases out: an S, which reads as the
## crosshair hanging at the top before it drops. An exponential is steepest at
## the instant it is released and flattens into the bottom. Sid, 2026-09-22:
## "if it were a curve it would be the bottom left quarter of a circle. A sharp
## drop and smooth at the bottom."
##
## An exponential is down to SETTLE_FRACTION of where it started after
## view_punch_release_time, which is what fixes the frequency. No peak term
## here, unlike punch_frequency_for: there is no rise to peak past.
func release_frequency() -> float:
	return -log(SETTLE_FRACTION) / maxf(view_punch_release_time, 0.0001)


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


## The weapon model's fast half: what drops the gun back between rounds.
func model_snap_punch_damping() -> float:
	return punch_damping_for(model_punch_snap_time)


func model_snap_punch_spring() -> float:
	return punch_spring_for(model_punch_snap_time)


func model_snap_punch_impulse_scale() -> float:
	return punch_impulse_scale_for(model_punch_snap_time) * model_kick_snap_share


## The weapon model's slow half: the tail that carries a single shot's
## animation out to the length Sid measured.
func model_hold_punch_damping() -> float:
	return punch_damping_for(model_hold_time())


func model_hold_punch_spring() -> float:
	return punch_spring_for(model_hold_time())


func model_hold_punch_impulse_scale() -> float:
	return punch_impulse_scale_for(model_hold_time()) * (
		1.0 - model_kick_snap_share
	)


## How long the weapon model's slow half takes to settle, SOLVED rather than
## picked, so that the two springs added together still settle after exactly
## recoil_animation_time.
##
## recoil_animation_time is the measurement and stays the specification: it is
## what a single shot's animation looks like on screen, and splitting the
## spring in two to get a fall between rounds must not quietly change it. The
## slow half on its own has to run somewhat longer than the measured number,
## because the fast half raises the peak the settle threshold is taken
## against. There is no closed form for where a sum of two springs crosses a
## fraction of its own peak, so this bisects for it once and remembers.
func model_hold_time() -> float:
	if _solved_model_hold_time >= 0.0:
		return _solved_model_hold_time
	var wanted := maxf(recoil_animation_time, 0.0001)
	var low := model_punch_snap_time
	var high := maxf(wanted * 4.0, low * 2.0)
	# A longer slow half can only settle later, so the answer is bracketed as
	# soon as the top of the range overshoots.
	for _widen in 8:
		if _model_settle_for(high) >= wanted:
			break
		high *= 2.0
	for _step in 40:
		var middle := (low + high) * 0.5
		if _model_settle_for(middle) < wanted:
			low = middle
		else:
			high = middle
	_solved_model_hold_time = (low + high) * 0.5
	return _solved_model_hold_time


## When one shot's weapon model punch is last above SETTLE_FRACTION of its own
## peak, with the slow half given the recovery time passed in.
func _model_settle_for(hold_time: float) -> float:
	var tick := 1.0 / PUNCH_HZ
	var snap := Punch.new()
	var hold := Punch.new()
	snap.kick(Vector2(0.0, punch_impulse_scale_for(model_punch_snap_time) * model_kick_snap_share))
	hold.kick(Vector2(0.0, punch_impulse_scale_for(hold_time) * (1.0 - model_kick_snap_share)))
	var snap_damping := punch_damping_for(model_punch_snap_time)
	var snap_spring := punch_spring_for(model_punch_snap_time)
	var hold_damping := punch_damping_for(hold_time)
	var hold_spring := punch_spring_for(hold_time)
	var peak := 0.0
	var samples := PackedFloat32Array()
	for _tick in int(PUNCH_HZ * 8.0):
		snap.advance(tick, snap_damping, snap_spring, tick)
		hold.advance(tick, hold_damping, hold_spring, tick)
		var size := absf(snap.value.y + hold.value.y)
		peak = maxf(peak, size)
		samples.append(size)
	for i in range(samples.size() - 1, -1, -1):
		if samples[i] >= peak * SETTLE_FRACTION:
			return float(i + 1) * tick
	return 0.0


func _damping_ratio(ratio: float = -1.0) -> float:
	return clampf(
		punch_damping_ratio if ratio < 0.0 else ratio, 0.05, 0.999
	)


## Time constant of the accuracy decay, in seconds, standing or crouched.
##
## Exponential rather than linear, which is both what the measured curve looks
## like on a log scale and what CS's accuracy penalty does: the recovery time
## is when it is down to a tenth. A longer spray therefore takes
## proportionally longer.
func accuracy_time_constant(ducked: bool = false) -> float:
	var recovery := recovery_time_crouch if ducked else recovery_time_stand
	return maxf(recovery, 0.0001) / log(10.0)


## How long one round's accuracy penalty takes to be gone, below the reset
## threshold, in seconds.
func accuracy_reset_time(ducked: bool = false) -> float:
	return accuracy_time_constant(ducked) * -log(SETTLE_FRACTION)


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
	var tick := 1.0 / PUNCH_HZ
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
	for tick_index in maxi(magazine_size, 1) * maxi(int(cycle_time * PUNCH_HZ), 1):
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
		# Arms take a chest's, as in CS.
		_: return chest_multiplier
