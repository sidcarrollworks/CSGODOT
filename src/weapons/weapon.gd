class_name Weapon
extends RefCounted

## Firing state for one weapon: rate of fire, recoil, inaccuracy and ammo.
##
## Deliberately a plain object rather than a node, so the whole firing model
## can be driven and asserted on headless without a scene. The view model and
## effects are a separate concern and hang off the controller.
##
## Two things here are load-bearing for how CS feels:
##
## The view kick and the bullet trajectory are SEPARATE. Bullets walk the
## spray pattern exactly on a held trigger (RecoilState). The view gets a
## smaller, spring-damped nudge that
## only suggests the pattern, so you cannot read your own recoil off the
## screen: you learn the pattern and pull against it. Gluing the two together
## gives a view that snaps to each bullet and sags between them, which is
## neither what CS looks like nor how it plays.
##
## Spread is deterministic, seeded per round from the instant it was fired
## (simulation time, which the server and a client agree on), the way CS2
## seeds it from the command that fired it. That lets a server and a client
## agree on where a bullet went without sending the bullet. It is NOT seeded
## by the round's place in the pattern: every first round would then land on
## the same spot in the cone, a tenth of the way out, and a running first
## shot would never miss. The first round is reliable because the standing
## cone is small, not because it always goes to the same place.

## The state of whoever is firing, which decides inaccuracy.
class ShooterState:
	var speed: float = 0.0
	var on_ground: bool = true
	var ducked: bool = false
	## Holding the walk key, which makes moving cost accuracy in proportion
	## to speed rather than steeply, as CS does.
	var walking: bool = false

	func _init(
		p_speed: float = 0.0, p_on_ground: bool = true, p_ducked: bool = false, p_walking: bool = false
	) -> void:
		speed = p_speed
		on_ground = p_on_ground
		ducked = p_ducked
		walking = p_walking


## One bullet, with everything needed to trace it and to explain it later.
class Shot:
	var origin: Vector3
	var direction: Vector3
	var shot_index: int
	var timestamp_usec: int
	## Where in the simulation tick the trigger was actually pulled, 0 to 1.
	var tick_fraction: float
	## Degrees of cone this shot was fired into, for debugging a miss.
	var inaccuracy: float
	## The player's own aim when the trigger was pulled, before recoil. The
	## reference a recorded spray is measured against.
	var base_yaw: float
	var base_pitch: float
	## The view kick this shot applied, in degrees. Recorded for debugging;
	## it has no bearing on where this bullet went.
	var view_punch: Vector2
	## The zoom level it was fired at (0 unscoped), and whether it went out
	## of a gun that has a scope without it: CS2's noscope.
	var zoom_level: int
	var noscope: bool
	## Which of the trigger pull's rounds this is: 0, or a shotgun's pellet.
	## Everything else is the trigger pull's and the same for every pellet.
	var pellet: int = 0
	## Where every one of the pull's rounds goes, the first being direction.
	## Filled by Weapon.fire; empty on a shot built by hand, which is one
	## round.
	var pellet_directions := PackedVector3Array()

	## How many rounds the trigger pull put out.
	func pellets() -> int:
		return maxi(pellet_directions.size(), 1)

	## The pull's round `index` as a shot of its own, to trace: this one,
	## pointed where that pellet goes.
	func pellet_shot(index: int) -> Shot:
		if index == pellet:
			return self
		var copy := Shot.new()
		copy.origin = origin
		copy.direction = pellet_directions[index]
		copy.shot_index = shot_index
		copy.timestamp_usec = timestamp_usec
		copy.tick_fraction = tick_fraction
		copy.inaccuracy = inaccuracy
		copy.base_yaw = base_yaw
		copy.base_pitch = base_pitch
		copy.view_punch = view_punch
		copy.zoom_level = zoom_level
		copy.noscope = noscope
		copy.pellet = index
		copy.pellet_directions = pellet_directions
		return copy


## The punch spring is integrated at no coarser than this, whatever the
## caller's tick or frame: WeaponData.PUNCH_HZ, the step its constants suit.
const PUNCH_MAX_STEP := 1.0 / WeaponData.PUNCH_HZ

## The recoil index starts to decay once the trigger has been off this many
## cycles, so it never does during a spray, and then falls to a tenth every
## 1 / RECOIL_INDEX_DECAY seconds. CS:GO's weapon_recoil_decay_coefficient,
## which replaced a flat 0.55 s reset (weapon_recoil_cooldown); CS2's own
## value is not published.
const RECOIL_INDEX_DELAY_CYCLES := 1.1
const RECOIL_INDEX_DECAY := 2.0

## Movement inaccuracy starts at this share of the weapon's top speed and is
## all there at the second (CS:GO's 0.34 and 0.95).
const MOVING_FROM := 0.34
const MOVING_FULL := 0.95

var data: WeaponData

var ammo: int = 0
var reserve: int = 0

## Seeds the per-round spread. Same seed and firing time give the same offset.
var spray_seed: int = 1

var _snap := WeaponData.Punch.new()
var _hold := WeaponData.Punch.new()
var _model_snap := WeaponData.Punch.new()
var _was_firing: bool = true

## Whether the player is holding the trigger down right now.
##
## Set by whoever drives the weapon, once a tick, before update(). The camera's
## slow half stops carrying the crosshair up and starts bringing it home the
## moment this goes false, which is the only way the drop can begin on the
## frame the button comes up.
##
## Inferring it from the gap since the last round instead, as this used to,
## costs a round and a quarter of dead time at the top of the spray: 125 ms on
## the AK where the crosshair has stopped climbing and has not started falling.
## Sid felt the 200 ms version of it. Left true by default so a caller that
## never sets it still behaves, falling back on the gap alone.
##
## Letting go is also what lets a semi-automatic weapon fire again: see
## press_trigger().
var trigger_held: bool = true:
	set(value):
		trigger_held = value
		if not value:
			_trigger_reset = true
## Whether the trigger has come up, or gone down afresh, since the last
## round. A semi-automatic weapon ("Hold to Shoot: No", the game's
## m_bIsFullAuto false) fires only when it has: one round a click, however
## long the button is held. An automatic one ignores it.
var _trigger_reset: bool = true
var _model_hold := WeaponData.Punch.new()

## Where the recoil has pushed the VIEW, in degrees, as (right, up).
##
## The player's own look angles are never touched by recoil. The camera adds
## this on top, which is what lets letting go of the trigger return the view
## to exactly where the player was pointing rather than somewhere near it.
##
## This does NOT decide where bullets go. See fire().
var aim_punch: Vector2:
	get: return _snap.value + _hold.value

## The punch angle's own velocity, both halves together. A round pushes this
## rather than pushing the angle, so the view rises into a kick over a few
## ticks instead of teleporting to it, and the springs bring it back.
var aim_punch_velocity: Vector2:
	get: return _snap.velocity + _hold.velocity

var _last_shot_usec: int = -1_000_000_000
## CS's recoil index, as it stood just after the last round: which round of
## the pattern the next one is. A round adds one; off the trigger it decays,
## to a tenth every half second (recoil_index_at), so a tap after a short
## pause carries on from part-way down the pattern rather than from where the
## spray left off or from the top.
var _recoil_index: float = 0.0
## The latest time the weapon has been told about, for shot_index().
var _clock_usec: int = 0
## Where the recoil has carried the bullets, and the pushes the rounds give it.
var _recoil := RecoilState.new()
var _impulses := PackedVector2Array()
var _inaccuracy: float = 0.0
var _was_on_ground: bool = true
var _reloading_until_usec: int = -1
## Until when it is being drawn, in simulation time: it fires from then on
## (draw()).
var _drawn_usec: int = 0

## The scope, for a gun that has one (WeaponData.zoom_fovs): the level it is
## at, 0 unscoped. Right click steps it up and round (press_zoom). Speed
## follows the level at once; the view and the scoped accuracy take the
## level's zoom time to get there (zoom_progress).
var zoom_level: int = 0
## The level it was at before the last change, and when the change was.
var _zoom_from: int = 0
var _zoomed_usec: int = -1_000_000_000
## A sniper that came out of the scope to fire goes back in to this level
## once it may fire again (WeaponData.unzooms_after_shot); 0 for none.
var _rezoom_level: int = 0


func _init(p_data: WeaponData) -> void:
	data = p_data
	ammo = data.magazine_size
	reserve = data.reserve_ammo
	var pattern := PackedVector2Array()
	for i in data.recoil_pattern.size():
		pattern.append(data.recoil_offset(i))
	_impulses = RecoilState.solve_impulses(pattern, data.cycle_time)


## Which round of the pattern the next one is, now. Falls back towards zero
## off the trigger.
func shot_index() -> int:
	return floori(recoil_index_at(_clock_usec))


## The recoil index at a moment: as the last round left it, decayed for as
## long as the trigger has been off past RECOIL_INDEX_DELAY_CYCLES. Worked
## out from the time rather than stepped, so it is the same however the ticks
## fell.
func recoil_index_at(now_usec: int) -> float:
	var gap := float(now_usec - _last_shot_usec) / 1_000_000.0
	var off_trigger := gap - data.cycle_time * RECOIL_INDEX_DELAY_CYCLES
	if off_trigger <= 0.0:
		return _recoil_index
	return _recoil_index * exp(-off_trigger * log(10.0) * RECOIL_INDEX_DECAY)


## When a held trigger fires next: the last round plus the cycle time,
## exactly. Firing on the tick instead rounds every gap up to a whole tick,
## which is 549 rounds a minute at 64 Hz rather than 600.
func next_shot_usec() -> int:
	return maxi(_last_shot_usec + int(round(data.cycle_time * 1_000_000.0)), _drawn_usec)


func is_reloading(now_usec: int) -> bool:
	return now_usec < _reloading_until_usec


## Taken in hand at now_usec: it fires once the draw is over, seconds later
## (CS2's deploy time, the item's m_flDeployDuration).
func draw(now_usec: int, seconds: float) -> void:
	_drawn_usec = now_usec + int(roundf(seconds * 1_000_000.0))
	_unscope()


## Put away: a reload under way stops, without its rounds, as a switch
## stops one in CS2, and the scope comes down.
func holster() -> void:
	_reloading_until_usec = -1
	_unscope()


## Right click on a gun with a scope: the next zoom level, and from the last
## back out, one level a press (CS2's cl_debounce_zoom: holding does not
## cycle). Not while it is being drawn or reloaded. Whether it zoomed:
## false for a gun with no scope, where right click is something else's.
func press_zoom(now_usec: int) -> bool:
	if data.zoom_levels() == 0 or is_drawing(now_usec) or is_reloading(now_usec):
		return false
	_rezoom_level = 0
	_zoom_to((zoom_level + 1) % (data.zoom_levels() + 1), now_usec)
	return true


func _zoom_to(level: int, now_usec: int) -> void:
	if level == zoom_level:
		return
	_zoom_from = zoom_level
	zoom_level = level
	_zoomed_usec = now_usec


## Straight out of the scope, with no time to get there: put away, drawn.
func _unscope() -> void:
	zoom_level = 0
	_zoom_from = 0
	_zoomed_usec = -1_000_000_000
	_rezoom_level = 0


## Whether it is out of the scope for a shot and going back in
## (WeaponData.unzooms_after_shot).
func rezoom_pending() -> bool:
	return _rezoom_level > 0


## How far the last zoom change has got, 0 to 1, over its level's zoom
## time.
func zoom_progress(now_usec: int) -> float:
	var seconds := data.zoom_time(zoom_level)
	if seconds <= 0.0:
		return 1.0
	return clampf(float(now_usec - _zoomed_usec) / (seconds * 1_000_000.0), 0.0, 1.0)


## The field of view the scope gives at a moment, in CS2's degrees (90
## unscoped), eased from the last level's to this one's over the zoom time.
## What the view is drawn with; nothing in the game reads it.
func zoom_fov_at(now_usec: int) -> float:
	return lerpf(data.zoom_fov(_zoom_from), data.zoom_fov(zoom_level), zoom_progress(now_usec))


## How much of the scoped accuracy it has: none unscoped, and scoping in, it
## comes in over the zoom time, as the view narrows; coming out, it is gone
## at once. CS2 keeps m_fAccuracySmoothedForZoom for this and publishes no
## rate, so easing over the zoom time is a guess until it is measured
## (reference/research/combat.md, R4).
func scoped_share(now_usec: int) -> float:
	if zoom_level == 0 or data.scoped == null:
		return 0.0
	if _zoom_from > 0:
		return 1.0
	return zoom_progress(now_usec)


## Whether the view is through the scope now: a sniper's, which puts the
## arms away and draws the scope over the screen, where the AUG's and SG
## 553's keep both (WeaponData.hides_view_model_when_zoomed).
func through_scope() -> bool:
	return zoom_level > 0 and data.hides_view_model_when_zoomed


## How fast the player may run with it: the scoped speed as soon as the
## scope is up (the AWP's 100 against 200).
func max_speed() -> float:
	if zoom_level > 0 and data.scoped != null:
		return data.scoped.max_player_speed
	return data.max_player_speed


func is_drawing(now_usec: int) -> bool:
	return now_usec < _drawn_usec


## When the draw is over, in the simulation's microseconds.
func drawn_usec() -> int:
	return _drawn_usec


## The trigger went down afresh. Call it for every press, before firing the
## round it asks for.
##
## Letting go (trigger_held going false) already re-arms a semi-automatic
## weapon, and on its own that serves every click with a whole tick of the
## button up between it and the one before. This covers the rest: a click
## that comes up and goes down again inside one tick, or a release and a
## press in two ticks in a row, where the trigger never reads false.
##
## A click is not saved up. Pressed before the weapon is ready and held, it
## fires the moment the weapon is; let go before then, it fires nothing
## (PlayerSim fires only while the trigger is down), and the next click
## starts again.
func press_trigger() -> void:
	_trigger_reset = true


func can_fire(now_usec: int) -> bool:
	if ammo <= 0 or is_reloading(now_usec) or is_drawing(now_usec):
		return false
	if not data.automatic and not _trigger_reset:
		return false
	var elapsed := float(now_usec - _last_shot_usec) / 1_000_000.0
	return elapsed >= data.cycle_time


## Advances recoil recovery and inaccuracy decay. Call once per simulation
## tick, whether or not anything was fired.
##
## state is what the shooter is doing this tick, where the caller knows it:
## crouched, the penalty recovers on the crouched time, and landing from a
## jump puts the landing penalty on. Without it the shooter counts as
## standing on the ground.
func update(dt: float, now_usec: int, state: ShooterState = null) -> void:
	_clock_usec = maxi(_clock_usec, now_usec)
	# Back into the scope once the bolt is worked, unless it is reloading or
	# empty (a reload takes it out anyway).
	if _rezoom_level > 0 and now_usec >= next_shot_usec():
		if ammo > 0 and not is_reloading(now_usec):
			_zoom_to(_rezoom_level, next_shot_usec())
		_rezoom_level = 0
	var since_shot := float(now_usec - _last_shot_usec) / 1_000_000.0

	# Held, and still shooting. The gap matters as well as the button, because
	# an empty magazine stops the rounds with the trigger still down.
	var firing := (
		trigger_held
		and since_shot <= data.cycle_time * data.trigger_release_cycles
	)
	if _was_firing and not firing:
		_let_go_of_the_trigger()
	_was_firing = firing

	_decay_punch(dt, firing)

	var ducked := state != null and state.ducked
	if state != null:
		if state.on_ground and not _was_on_ground:
			# As scoped as the cone is (scoped_share).
			var share := scoped_share(now_usec)
			var excess := data.inaccuracy_landing - data.inaccuracy_standing
			if share > 0.0:
				excess = lerpf(excess, data.scoped.inaccuracy_landing - data.scoped.inaccuracy_standing, share)
			_inaccuracy = maxf(_inaccuracy, excess)
		_was_on_ground = state.on_ground
	_decay_inaccuracy(dt, ducked)


## Runs the three punch springs forward.
##
## The camera's kick is two of them added together: a fast half so each round
## reads as its own shove, and a slow half that carries the crosshair up the
## spray and holds it there. One spring cannot do both, because a damped
## spring's rise and its decay are the same two constants read two ways.
##
## The third is the weapon model's, on the few hundred milliseconds measured
## off CS2.
##
## The slow half lets go faster once the trigger is up, because the reason it
## is slow is to still be there when the next round lands, and after the last
## round nothing is landing. CS splits these the same way: its recoil index
## recovers between rounds rather than while they are going out.
##
## Running them every tick, including while firing, is deliberate. The old
## code only decayed between rounds, which is what made the view snap up to
## each bullet and then sag.
func _decay_punch(dt: float, firing: bool) -> void:
	_snap.advance(
		dt, data.snap_punch_damping(), data.snap_punch_spring(), PUNCH_MAX_STEP
	)
	_hold.advance(
		dt,
		data.hold_punch_damping(firing),
		data.hold_punch_spring(firing),
		PUNCH_MAX_STEP
	)
	_model_snap.advance(
		dt,
		data.model_snap_punch_damping(),
		data.model_snap_punch_spring(),
		PUNCH_MAX_STEP
	)
	_model_hold.advance(
		dt,
		data.model_hold_punch_damping(),
		data.model_hold_punch_spring(),
		PUNCH_MAX_STEP
	)


## Hands the slow half the velocity that turns its return into a plain
## exponential decay, at the instant the trigger goes up.
##
## A critically damped spring let go at height V with velocity -wV is exactly
## V*exp(-w*t). Let go from rest instead and it starts with no speed at all,
## builds up and eases out, which is the crosshair hanging at the top of the
## spray for a moment before it drops. Sid, 2026-09-22: "it still feels like it
## hangs at the top for 200ms. It should move down very quickly... a sharp drop
## and smooth at the bottom."
##
## Only the velocity is touched, so there is no jump: the crosshair is exactly
## where it was, it has simply stopped climbing and started falling.
func _let_go_of_the_trigger() -> void:
	_hold.velocity = -_hold.value * data.release_frequency()


## The accuracy penalty decays exponentially toward zero and snaps to it once
## it is below what the game could show you.
##
## Exponential, not linear, for two reasons: it is what the measured accuracy
## box does (the steps shrink as it recovers, which is a straight line only on
## a log scale), and it is what CS's accuracy penalty does. The time constant
## comes from the weapon sheet's recovery time, standing or crouched: the
## penalty is down to a tenth after it.
func _decay_inaccuracy(dt: float, ducked: bool = false) -> void:
	if _inaccuracy <= 0.0:
		return
	_inaccuracy *= exp(-dt / data.accuracy_time_constant(ducked))
	if _inaccuracy < data.accuracy_reset_threshold():
		_inaccuracy = 0.0


## Whether the weapon has finished recovering its accuracy.
##
## Worth reading next to how far the view has settled, because the two do not
## agree: on both of these weapons the gun stops moving a couple of hundred
## milliseconds before this turns true.
func is_accuracy_reset() -> bool:
	return _inaccuracy <= 0.0


## Where the recoil has pushed the WEAPON MODEL, in degrees, before
## viewmodel_recoil scales it. Two springs of its own, settling together in
## the few hundred milliseconds measured off CS2 rather than the camera's
## couple of seconds, and falling back towards rest between rounds the way
## CS2's firing clip does by being replayed from the start.
var model_punch: Vector2:
	get: return _model_snap.value + _model_hold.value


## Where the weapon model should be pushed to, in degrees, over and above the
## camera it already hangs from. Cosmetic only: it moves the gun in the
## player's hands and changes nothing about aim or bullets.
##
## Sideways is scaled down against the climb, so the gun sways without
## wandering off the middle of the screen.
func viewmodel_punch() -> Vector2:
	var model := model_punch
	return Vector2(
		model.x * data.viewmodel_recoil * data.viewmodel_sway,
		model.y * data.viewmodel_recoil
	)


## The current cone half-angle in degrees, given what the shooter is doing.
##
## This is the part that makes counter-strafing matter: stopping drops you
## below the speed threshold, and the cone collapses.
##
## Moving and jumping add up, as in CS: the moving and jumping figures are
## totals over standing still, so what each adds is its excess over that.
## A jump taken at a run is therefore worse than either, while a standing
## jump is not as bad as a full run.
##
## Scoped, the gun's scoped numbers, as far as they have come in at now_usec
## (scoped_share; the latest time the weapon was told of, left out).
func current_inaccuracy(state: ShooterState, now_usec: int = -1) -> float:
	var share := scoped_share(now_usec if now_usec >= 0 else _clock_usec)
	var base := _cone_for(data, state)
	if share > 0.0:
		base = lerpf(base, _cone_for(data.scoped, state), share)
	return base + _inaccuracy


## The cone for how the shooter stands and moves, with one set of the gun's
## numbers (unscoped or scoped), before the firing penalty.
static func _cone_for(numbers: WeaponData, state: ShooterState) -> float:
	var base := numbers.inaccuracy_standing
	if state.ducked:
		base = numbers.inaccuracy_crouching
	if not state.on_ground:
		base += maxf(numbers.inaccuracy_jumping - numbers.inaccuracy_standing, 0.0)
	# Nothing under a third of the weapon's top speed, all of it from 95% up,
	# as CS does. Between, it rises steeply (the fourth root) unless the walk
	# key is down, when it is in proportion: a little speed costs a lot
	# unless you are walking, which is what makes counter-strafing matter.
	var over := inverse_lerp(
		numbers.max_player_speed * MOVING_FROM, numbers.max_player_speed * MOVING_FULL, state.speed
	)
	if over > 0.0:
		over = minf(over, 1.0)
		if not state.walking:
			over = pow(over, 0.25)
		base += maxf(numbers.inaccuracy_moving - numbers.inaccuracy_standing, 0.0) * over
	return base


## The view kick of one round, in degrees.
##
## The same climb every round, with a small sideways lean whose DIRECTION
## comes from the pattern and whose size does not.
##
## Reading the size off the pattern too is the obvious thing to do and it is
## wrong. A pattern's vertical steps are front-loaded and its sideways steps
## are not: the AK climbs about two degrees a round for seven rounds and then
## goes flat, while its sideways steps grow to three degrees. Scale the kick
## by those and the view punches twice and then only sways, which is not what
## a gun does and is not what CS2 does either.
func _view_kick_for(round_index: int) -> Vector2:
	var here := data.recoil_offset(round_index)
	var sideways := data.recoil_offset(round_index + 1).x - here.x
	if is_zero_approx(sideways) and round_index > 0:
		# Past the end of the pattern, lean the way the last round did.
		sideways = here.x - data.recoil_offset(round_index - 1).x
	return Vector2(signf(sideways) * data.view_kick_side(), data.view_kick_up())


## Fires one round. Returns null if the weapon could not fire.
##
## yaw and pitch are the angles at the instant the trigger was pulled, which
## for a player come off the timestamped input event rather than from the tick
## boundary. That is the whole point of sub-tick shooting.
func fire(
	now_usec: int,
	tick_fraction: float,
	origin: Vector3,
	yaw_degrees: float,
	pitch_degrees: float,
	state: ShooterState
) -> Shot:
	if not can_fire(now_usec):
		return null

	# The recoil since the last round: the punch decays, and once the trigger
	# has been off for a little over a cycle, so does the index. Both run on
	# the time between rounds, so where a round goes does not depend on how
	# the ticks fell.
	_recoil.advance(float(now_usec - _last_shot_usec) / 1_000_000.0)
	var index := recoil_index_at(now_usec)
	var round_index := floori(index)
	var current := _recoil.value

	# The bullet goes where the recoil has carried it, measured from where the
	# player is actually pointing. Held down, that is exactly this round's
	# entry in the pattern. Nothing about the view is involved: not the punch
	# that has built up, not how much of it has sprung back, not how large the
	# view kick is configured to be. Turning the view kick off entirely would
	# leave every bullet hole where it is.
	#
	# This is the whole point. The pattern is the truth and it is the same
	# every spray, which is what makes it learnable. The view only suggests it.
	#
	# A shotgun's pellets keep a fixed pattern, the gun's spread wide, round
	# an aim that the rest of the cone throws (pellet_directions).
	var spread := current_inaccuracy(state, now_usec)
	var many := data.pellets > 1
	var direction := _spread_direction(
		# Pattern x is degrees to the RIGHT, and yaw decreases rightward.
		yaw_degrees - current.x,
		pitch_degrees + current.y,
		maxf(spread - data.spread, 0.0) if many else spread,
		now_usec
	)
	var rounds := pellet_directions(direction) if many else PackedVector3Array([direction])
	direction = rounds[0]

	# The view gets kicked by this shot's own recoil, scaled down, and as a
	# push on the punch velocity rather than a jump in the angle, so it rises
	# into the kick over the next few ticks.
	var punch := _view_kick_for(round_index)

	var shot := Shot.new()
	shot.origin = origin
	shot.direction = direction
	shot.shot_index = round_index
	shot.timestamp_usec = now_usec
	shot.tick_fraction = tick_fraction
	shot.inaccuracy = spread
	shot.view_punch = punch
	shot.base_yaw = yaw_degrees
	shot.base_pitch = pitch_degrees
	shot.pellet_directions = rounds
	shot.zoom_level = zoom_level
	shot.noscope = data.zoom_levels() > 0 and zoom_level == 0

	_snap.kick(punch * data.snap_punch_impulse_scale())
	_hold.kick(punch * data.hold_punch_impulse_scale())
	_model_snap.kick(punch * data.model_snap_punch_impulse_scale())
	_model_hold.kick(punch * data.model_hold_punch_impulse_scale())
	var per_shot := data.inaccuracy_per_shot
	var share := scoped_share(now_usec)
	if share > 0.0:
		per_shot = lerpf(per_shot, data.scoped.inaccuracy_per_shot, share)
	_inaccuracy += per_shot
	if not _impulses.is_empty():
		_recoil.velocity += _impulses[mini(round_index, _impulses.size() - 1)]
	_recoil_index = index + 1.0
	_last_shot_usec = now_usec
	_clock_usec = maxi(_clock_usec, now_usec)
	_trigger_reset = false
	ammo -= 1
	# The AWP and SSG 08 come out of the scope with the shot, and go back in
	# once the bolt is worked (update).
	if data.unzooms_after_shot and zoom_level > 0:
		_rezoom_level = zoom_level
		_zoom_to(0, now_usec)

	return shot


## Starts a reload at now_usec. Not during the draw: in CS2 the pull-out
## finishes before a reload starts (Sid, 2026-09-26; PlayerSim keeps a press
## made during it for when it ends).
func start_reload(now_usec: int) -> bool:
	if reserve <= 0 or ammo >= data.magazine_size or is_reloading(now_usec) or is_drawing(now_usec):
		return false
	_reloading_until_usec = now_usec + int(data.reload_time * 1_000_000.0)
	# Reloading takes the scope down, and it stays down.
	_rezoom_level = 0
	_zoom_to(0, now_usec)
	return true


## Completes a reload whose time has elapsed. Returns true if it did anything.
func finish_reload_if_due(now_usec: int) -> bool:
	if _reloading_until_usec < 0 or now_usec < _reloading_until_usec:
		return false
	var wanted: int = data.magazine_size - ammo
	var taken: int = mini(wanted, reserve)
	ammo += taken
	reserve -= taken
	_reloading_until_usec = -1
	# CS starts the pattern again on a fresh magazine.
	_recoil_index = 0.0
	return true


## Applies the spread cone to an aim direction. The radius is a uniform
## random share of the cone, as CS draws it, which bunches rounds towards the
## centre: half of them land within half the cone, where spreading them evenly
## over the disc would put only a quarter there.
func _spread_direction(
	yaw_degrees: float, pitch_degrees: float, spread_degrees: float, fired_usec: int
) -> Vector3:
	var direction := PlayerInput.aim_direction(yaw_degrees, pitch_degrees)
	if spread_degrees <= 0.0:
		return direction

	var rng := RandomNumberGenerator.new()
	rng.seed = _shot_seed(fired_usec)

	var angle := rng.randf() * TAU
	var radius := rng.randf() * spread_degrees
	return _tilted(direction, angle, radius)


## Where each of a shotgun's pellets goes from an aim: the gun's pattern
## laid round it, the same every shot. The pattern is drawn the way a
## round's place in the cone is, a direction and a uniform share of the
## gun's spread, from the gun's spread seed and the pellet's number rather
## than from when it was fired.
##
## CS2 fixed each shotgun's pattern in place of random pellets (Valve's
## "Holiday Spread", December 2017; weapon_accuracy_shotgun_spread_patterns
## is on), and only the shotguns have a spread seed. That the pattern comes
## from the seed and that the spread sets its size is inferred; its real
## shape is still to be read off CS2 (reference/research/combat.md, R5).
func pellet_directions(aim: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var rng := RandomNumberGenerator.new()
	for i in maxi(data.pellets, 1):
		rng.seed = hash([data.spread_seed, i])
		var angle := rng.randf() * TAU
		var radius := rng.randf() * data.spread
		out.append(_tilted(aim, angle, radius))
	return out


## direction turned `degrees` away from itself, towards `angle` round it
## (0 to the right, a quarter turn up).
static func _tilted(direction: Vector3, angle: float, degrees: float) -> Vector3:
	if degrees <= 0.0:
		return direction
	var right := direction.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		# Looking straight up or down; any perpendicular will do.
		right = direction.cross(Vector3.RIGHT)
	right = right.normalized()
	var up := right.cross(direction).normalized()

	var offset := (right * cos(angle) + up * sin(angle)) * tan(deg_to_rad(degrees))
	return (direction + offset).normalized()


## A weapon never fires twice in the same microsecond, so no two of its
## rounds share a seed.
func _shot_seed(fired_usec: int) -> int:
	# Hashed rather than used as is so rounds fired close together do not
	# produce visibly related offsets.
	return hash([spray_seed, fired_usec])
