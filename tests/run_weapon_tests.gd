extends SceneTree

## Headless tests for shooting.
##
##   godot --headless --path . --script tests/run_weapon_tests.gd
##
## The firing model is a plain object, so most of this needs no scene at all.
## The last section builds a real target and traces real bullets at it, which
## is the part that would otherwise only be checked by squinting at a dummy.

const DT := 1.0 / 128.0
const SECOND := 1_000_000

var _failures: int = 0
var _checks: int = 0
var _frames: int = 0

var _target: HitTarget
var _wall: StaticBody3D
var _world: Node3D


func _process(_delta: float) -> bool:
	if _frames == 0:
		_test_fire_rate()
		_test_ammo_and_reload()
		_test_deterministic_spread()
		_test_recoil_follows_the_pattern()
		_test_recoil_recovers()
		_test_held_trigger_walks_the_whole_pattern()
		_test_tapping_recovers_gradually()
		_test_the_rate_of_fire_is_exact()
		_test_patterns_are_the_measured_ones()
		_test_recoil_scale()
		_test_bullets_ignore_the_view_kick()
		_test_view_kicks_less_than_the_spray()
		_test_every_round_kicks_the_view()
		_test_the_view_leans_without_swinging()
		_test_the_spray_peaks_where_it_was_asked_to()
		_test_each_round_shoves_the_crosshair()
		_test_the_weapon_model_falls_between_rounds()
		_test_the_solver_agrees_with_the_weapon()
		_test_view_rises_rather_than_teleporting()
		_test_viewmodel_follows_the_view()
		_test_the_camera_holds_while_firing_and_lets_go_after()
		_test_the_crosshair_drops_sharply_and_eases_out()
		_test_letting_go_beats_waiting_to_be_noticed()
		_test_the_model_moves_less_than_the_view()
		_test_a_single_tap_kicks_the_view()
		_test_animation_lasts_as_long_as_measured()
		_test_the_model_springs_add_up_to_the_measurement()
		_test_accuracy_resets_as_slowly_as_measured()
		_test_the_gun_looks_ready_before_it_is()
		_test_spray_peak_survives_a_faster_camera()
		_test_punch_is_the_same_at_any_frame_length()
		_test_inaccuracy_by_state()
		_test_damage_falloff()
		_test_hitbox_multipliers()
		_test_fatal_headshot_ranges()
		_test_landing_costs_accuracy()
		_test_every_value_comes_from_the_sheet()
		_build_world()
		_frames += 1
		return false

	# One physics frame so the hitbox areas are registered in the space.
	_frames += 1
	if _frames < 4:
		return false

	_test_headshot_registers()
	_test_wall_blocks_the_shot()
	_test_crosshair_is_centred()
	_report()
	return true


# --- Firing model ---------------------------------------------------------

func _standing() -> Weapon.ShooterState:
	return Weapon.ShooterState.new(0.0, true, false)


func _fire(weapon: Weapon, at_usec: int) -> Weapon.Shot:
	return weapon.fire(at_usec, 0.0, Vector3.ZERO, 0.0, 0.0, _standing())


func _test_fire_rate() -> void:
	var weapon := Weapon.new(WeaponLibrary.ak47())
	var cycle := int(weapon.data.cycle_time * SECOND)

	_check(_fire(weapon, 0) != null, "the first shot fires")
	_check(
		_fire(weapon, cycle / 2) == null,
		"a second shot inside the cycle time does not fire"
	)
	_check(
		_fire(weapon, cycle) != null,
		"a second shot after the cycle time fires"
	)


func _test_ammo_and_reload() -> void:
	var weapon := Weapon.new(WeaponLibrary.ak47())
	var cycle := int(weapon.data.cycle_time * SECOND)
	var magazine := weapon.data.magazine_size

	for shot in magazine:
		_fire(weapon, shot * cycle)
	_check_equal(weapon.ammo, 0, "a full magazine empties in %d shots" % magazine)
	_check(
		_fire(weapon, magazine * cycle) == null,
		"an empty weapon does not fire"
	)

	var now := magazine * cycle
	_check(weapon.start_reload(now), "reload starts")
	_check(
		not weapon.finish_reload_if_due(now),
		"reload does not finish instantly"
	)
	now += int(weapon.data.reload_time * SECOND)
	_check(weapon.finish_reload_if_due(now), "reload finishes after reload_time")
	_check_equal(weapon.ammo, magazine, "the magazine is full again")
	_check_equal(
		weapon.reserve, weapon.data.reserve_ammo - magazine,
		"the rounds came out of the reserve"
	)


## Same seed, same shot, same bullet. This is what makes the first shot
## trustworthy and the pattern worth learning, and later it is what lets a
## server and a client agree on where a bullet went without sending it.
func _test_deterministic_spread() -> void:
	var moving := Weapon.ShooterState.new(200.0, true, false)

	var first := Weapon.new(WeaponLibrary.ak47())
	first.spray_seed = 42
	var second := Weapon.new(WeaponLibrary.ak47())
	second.spray_seed = 42

	var a := first.fire(0, 0.0, Vector3.ZERO, 10.0, 5.0, moving)
	var b := second.fire(0, 0.0, Vector3.ZERO, 10.0, 5.0, moving)
	_check(a != null and b != null, "both weapons fired")
	if a == null or b == null:
		return
	_check(
		a.direction.distance_to(b.direction) < 0.000001,
		"the same seed and shot index give the same direction"
	)
	_check(
		a.inaccuracy > 0.5,
		"moving opens the cone (%.3f degrees)" % a.inaccuracy
	)

	var third := Weapon.new(WeaponLibrary.ak47())
	third.spray_seed = 43
	var c := third.fire(0, 0.0, Vector3.ZERO, 10.0, 5.0, moving)
	_check(
		a.direction.distance_to(c.direction) > 0.000001,
		"a different seed gives a different direction"
	)


## Shot N has to land at pattern entry N, otherwise the holes on the wall do
## not match the reference and the whole measuring loop is pointless.
func _test_recoil_follows_the_pattern() -> void:
	var data := WeaponLibrary.ak47()
	# Remove the cone so the test is about the pattern, not the spread.
	data.inaccuracy_standing = 0.0
	data.inaccuracy_per_shot = 0.0

	var weapon := Weapon.new(data)
	var cycle := int(data.cycle_time * SECOND)
	_check(data.recoil_pattern.size() > 10, "the AK has a pattern loaded")

	for shot in 8:
		var fired := weapon.fire(
			shot * cycle, 0.0, Vector3.ZERO, 0.0, 0.0, _standing()
		)
		if fired == null:
			_check(false, "shot %d fired" % shot)
			return
		var expected: Vector2 = data.recoil_pattern[shot]
		var angles := PlayerInput.angles_from_direction(fired.direction)
		# Punch x is degrees right, and yaw decreases rightward.
		_check(
			absf(-angles.x - expected.x) < 0.01
			and absf(angles.y - expected.y) < 0.01,
			"shot %d lands at pattern entry (%.2f, %.2f), got (%.2f, %.2f)" % [
				shot, expected.x, expected.y, -angles.x, angles.y
			]
		)


func _test_recoil_recovers() -> void:
	var weapon := Weapon.new(WeaponLibrary.ak47())
	var state := _standing()
	var now := 0

	# Six shots on a held trigger, ticking the spring as the game does.
	var fired := 0
	while fired < 6:
		now += int(DT * SECOND)
		weapon.update(DT, now)
		if weapon.fire(now, 1.0, Vector3.ZERO, 0.0, 0.0, state) != null:
			fired += 1
	# A few more ticks for the spring to carry the last kick.
	for tick in 12:
		now += int(DT * SECOND)
		weapon.update(DT, now)

	_check(
		weapon.aim_punch.length() > 1.0,
		"the view has kicked after six shots (%.2f degrees)"
			% weapon.aim_punch.length()
	)
	_check(weapon.shot_index() == 6, "six shots into the pattern")

	# Let go of the trigger and wait. The camera's spring settles over about
	# two seconds, so this is a little over three of them.
	for tick in 800:
		now += int(DT * SECOND)
		weapon.update(DT, now)

	_check(
		weapon.aim_punch == Vector2.ZERO
			and weapon.aim_punch_velocity == Vector2.ZERO,
		"the view returns exactly to where the player was pointing (%s)"
			% weapon.aim_punch
	)
	_check_equal(
		weapon.shot_index(), 0,
		"the pattern restarts once the trigger has been off long enough"
	)


## Drives update() and fire() together, the way PlayerController does.
##
## This is the shape the bug hid in: every earlier recoil test called fire()
## in a loop and never called update(), so nothing exercised the reset that
## runs between shots. In the game the spray never got past shot one and the
## gun had no pattern at all.
func _test_held_trigger_walks_the_whole_pattern() -> void:
	for data in [WeaponLibrary.ak47(), WeaponLibrary.m4a1s()]:
		var weapon := Weapon.new(data)
		var state := _standing()
		var now := 0
		var indices: Array[int] = []
		var climb: Array[float] = []

		# Two magazines' worth of ticks, trigger held the whole time.
		for tick in int(data.magazine_size * data.cycle_time * 2.0 / DT):
			now += int(DT * SECOND)
			weapon.update(DT, now)
			var shot := weapon.fire(now, 1.0, Vector3.ZERO, 0.0, 0.0, state)
			if shot != null:
				indices.append(shot.shot_index)
				climb.append(data.recoil_offset(shot.shot_index).y)

		_check_equal(
			indices.size(), data.magazine_size,
			"%s empties its magazine on a held trigger" % data.display_name
		)
		var walked := true
		for i in indices.size():
			if indices[i] != i:
				walked = false
				break
		_check(
			walked,
			"%s walks the pattern 0..%d rather than repeating a shot (%s)"
				% [data.display_name, data.magazine_size - 1, indices.slice(0, 6)]
		)
		if climb.size() > 8:
			_check(
				climb[7] > 3.0,
				"%s bullets have climbed by the eighth shot (%.2f degrees)"
					% [data.display_name, climb[7]]
			)


## Tapping is not spraying slowly. Off the trigger both the recoil and the
## recoil index recover, so a round after a pause lands short of where the
## spray would have got to, the more so the longer the pause, and steady taps
## settle low instead of walking the whole pattern. Sid, 2026-09-22: tapping
## "has the tendency to continue the spray pattern to the T instead of slowly
## being reset".
func _test_tapping_recovers_gradually() -> void:
	var data := WeaponLibrary.ak47()
	data.inaccuracy_standing = 0.0
	data.inaccuracy_per_shot = 0.0
	var cycle := int(data.cycle_time * SECOND)

	var first := Weapon.new(data).fire(0, 0.0, Vector3.ZERO, 0.0, 0.0, _standing())
	_check(first != null and first.shot_index == 0, "the first shot is shot zero")

	# Ten rounds held, a pause, then one more.
	var heights: Array[float] = []
	var indices: Array[int] = []
	for pause in [0.15, 0.3, 0.6, 1.5]:
		var weapon := Weapon.new(data)
		for shot in 10:
			weapon.fire(shot * cycle, 0.0, Vector3.ZERO, 0.0, 0.0, _standing())
		var at := 9 * cycle + int(pause * SECOND)
		var shot := weapon.fire(at, 0.0, Vector3.ZERO, 0.0, 0.0, _standing())
		heights.append(PlayerInput.angles_from_direction(shot.direction).y)
		indices.append(shot.shot_index)
	var held: float = data.recoil_offset(10).y
	_check(
		heights[0] < held and heights[0] > 0.5,
		"after 0.15 s off the trigger a round lands short of the spray's %.2f degrees, but not at the aim (%.2f)"
			% [held, heights[0]]
	)
	_check(
		heights[0] > heights[1] and heights[1] > heights[2] and heights[2] >= heights[3],
		"the longer the pause, the lower it lands (%s)" % [heights]
	)
	_check(absf(heights[3]) < 0.01, "after a second and a half the recoil is gone (%.3f)" % heights[3])
	_check(
		indices[0] > indices[1] and indices[1] > indices[2] and indices[3] == 0,
		"and the pattern falls back towards its top, not to it at once (%s)" % [indices]
	)
	# Ten rounds leave the index at 10; 0.6 s off, less the 0.11 s it waits,
	# takes it to a tenth to the power of 0.98.
	_check_equal(indices[2], 1, "0.6 s off the trigger, ten rounds in, the next is round 1")

	# Steady taps a quarter of a second apart stay near the aim; the same
	# eight rounds held climb most of the way up the pattern.
	var tapper := Weapon.new(data)
	var highest := 0.0
	for shot in 8:
		var tap := tapper.fire(shot * int(0.25 * SECOND), 0.0, Vector3.ZERO, 0.0, 0.0, _standing())
		highest = maxf(highest, PlayerInput.angles_from_direction(tap.direction).y)
	_check(
		highest < 1.0 and highest < data.recoil_offset(7).y * 0.2,
		"tapping every 0.25 s stays within a degree (%.2f), where holding climbs %.2f"
			% [highest, data.recoil_offset(7).y]
	)

	# And the view: the first round's kick is a push on the spring, so the
	# view has not moved yet the instant it goes.
	var viewer := Weapon.new(data)
	viewer.fire(0, 0.0, Vector3.ZERO, 0.0, 0.0, _standing())
	_check_near(viewer.aim_punch.length(), 0.0, "the first shot has not moved the view yet")


## A held trigger fires at the weapon's own rate however the ticks fall: the
## next round is due at the last one plus the cycle, not on the tick after.
func _test_the_rate_of_fire_is_exact() -> void:
	var data := WeaponLibrary.ak47()
	var weapon := Weapon.new(data)
	weapon.fire(0, 0.0, Vector3.ZERO, 0.0, 0.0, _standing())
	_check_equal(weapon.next_shot_usec(), int(data.cycle_time * SECOND), "the next round is due one cycle on")


## The patterns are the ones read off the CS2 spray plots, not placeholders.
func _test_patterns_are_the_measured_ones() -> void:
	var ak := WeaponLibrary.ak47()
	var m4 := WeaponLibrary.m4a1s()

	_check_equal(ak.recoil_pattern.size(), 30, "the AK pattern covers 30 rounds")
	_check_equal(m4.recoil_pattern.size(), 25, "the M4A1-S pattern covers 25 rounds")
	_check_equal(
		ak.magazine_size, ak.recoil_pattern.size(),
		"the AK magazine and its pattern are the same length"
	)
	_check_equal(m4.magazine_size, 20, "the M4A1-S magazine is the sheet's 20")
	_check(
		m4.recoil_pattern.size() >= m4.magazine_size,
		"the M4A1-S pattern covers its whole magazine"
	)

	for data in [ak, m4]:
		_check(
			data.recoil_pattern[0] == Vector2.ZERO,
			"%s puts its first bullet exactly on the crosshair" % data.display_name
		)

	# The opening of both patterns is a near-vertical climb, which is the part
	# a player learns first and the part most obviously wrong if the shot
	# order came out backwards.
	for data in [ak, m4]:
		var rising := true
		for i in range(1, 8):
			if data.recoil_pattern[i].y <= data.recoil_pattern[i - 1].y:
				rising = false
				break
		_check(
			rising,
			"%s climbs on every one of its first eight shots" % data.display_name
		)
		var drift: float = absf(data.recoil_pattern[4].x)
		_check(
			drift < absf(data.recoil_pattern[4].y),
			"%s climbs further than it drifts early on (%.2f across, %.2f up)"
				% [data.display_name, drift, data.recoil_pattern[4].y]
		)

	_check(
		ak.recoil_pattern[29].y > m4.recoil_pattern[24].y,
		"the AK ends up higher than the M4A1-S (%.1f vs %.1f degrees)"
			% [ak.recoil_pattern[29].y, m4.recoil_pattern[24].y]
	)


## The size of the spray is the one part of the pattern that was estimated
## rather than measured, so it has to be correctable without editing the rows.
func _test_recoil_scale() -> void:
	var data := WeaponLibrary.ak47()
	data.inaccuracy_standing = 0.0
	data.inaccuracy_per_shot = 0.0
	data.recoil_scale = 0.5

	var weapon := Weapon.new(data)
	var cycle := int(data.cycle_time * SECOND)
	var last: Weapon.Shot = null
	for shot in 5:
		last = weapon.fire(shot * cycle, 0.0, Vector3.ZERO, 0.0, 0.0, _standing())

	var angles := PlayerInput.angles_from_direction(last.direction)
	_check_near(
		angles.y, data.recoil_pattern[4].y * 0.5,
		"recoil_scale halves how far the bullets climb"
	)


## Fires the same spray with the view kick off and with it at full strength,
## and checks every bullet went to exactly the same place.
##
## This is the whole claim, as a test. The pattern is the truth; the view only
## suggests it. Anything that makes the view kick also move the bullets has
## broken the thing that makes a spray learnable.
func _test_bullets_ignore_the_view_kick() -> void:
	var runs: Array[Array] = []
	for size in [0.0, 0.5, 3.0]:
		var data := WeaponLibrary.ak47()
		data.view_kick_spray_peak = size
		var weapon := Weapon.new(data)
		var state := _standing()
		var now := 0
		var directions: Array[Vector3] = []
		while directions.size() < data.magazine_size:
			now += int(DT * SECOND)
			weapon.update(DT, now)
			var shot := weapon.fire(now, 1.0, Vector3.ZERO, 0.0, 0.0, state)
			if shot != null:
				directions.append(shot.direction)
		runs.append(directions)

	for run in range(1, runs.size()):
		var same := true
		var worst := 0.0
		for i in runs[0].size():
			var a: Vector3 = runs[0][i]
			var b: Vector3 = runs[run][i]
			worst = maxf(worst, (a - b).length())
			if not a.is_equal_approx(b):
				same = false
		_check(
			same,
			"every bullet lands identically whether the view kicks or not (worst difference %.8f)"
				% worst
		)


## The view kick is a suggestion, not a readout: it has to move noticeably
## less than the bullets, and letting go of the trigger has to put the view
## back exactly where the player was pointing.
func _test_view_kicks_less_than_the_spray() -> void:
	for data in [WeaponLibrary.ak47(), WeaponLibrary.m4a1s()]:
		var weapon := Weapon.new(data)
		var state := _standing()
		var now := 0
		var peak_view := 0.0
		var fired := 0

		while fired < data.magazine_size:
			now += int(DT * SECOND)
			weapon.update(DT, now)
			if weapon.fire(now, 1.0, Vector3.ZERO, 0.0, 0.0, state) != null:
				fired += 1
			peak_view = maxf(peak_view, weapon.aim_punch.y)

		var spray_climb := 0.0
		for entry in data.recoil_pattern:
			spray_climb = maxf(spray_climb, entry.y)

		# Then let go of the trigger and let the spring do its work.
		for tick in 256:
			now += int(DT * SECOND)
			weapon.update(DT, now)

		_check(
			peak_view > 0.5,
			"%s kicks the view at all (%.2f degrees)"
				% [data.display_name, peak_view]
		)
		_check(
			peak_view < spray_climb * 0.6,
			"%s kicks the view less than half as far as the spray climbs (%.2f against %.2f degrees)"
				% [data.display_name, peak_view, spray_climb]
		)
		_check(
			absf(weapon.aim_punch.y) < peak_view * 0.02,
			"%s view comes back to where the player is pointing once the trigger is off (%.3f degrees left)"
				% [data.display_name, weapon.aim_punch.y]
		)


## The view rises into a kick over several ticks rather than jumping to it.
##
## The reported bug was that each shot teleported the crosshair and it then
## drifted down, over and over. That happened because a shot set the punch
## ANGLE directly. A shot now pushes the punch VELOCITY, so no single tick can
## move the view anything like as far as one bullet does.
func _test_view_rises_rather_than_teleporting() -> void:
	var data := WeaponLibrary.ak47()
	var weapon := Weapon.new(data)
	var state := _standing()
	var now := 0
	var previous := Vector2.ZERO
	var biggest_step := 0.0
	var fired := 0

	while fired < data.magazine_size:
		now += int(DT * SECOND)
		weapon.update(DT, now)
		if weapon.fire(now, 1.0, Vector3.ZERO, 0.0, 0.0, state) != null:
			fired += 1
		biggest_step = maxf(biggest_step, (weapon.aim_punch - previous).length())
		previous = weapon.aim_punch

	# The steepest single step in the pattern is what a teleport would look
	# like, so the view has to move a lot less than that in any one tick.
	var steepest := 0.0
	for i in range(1, data.recoil_pattern.size()):
		steepest = maxf(
			steepest,
			(data.recoil_pattern[i] - data.recoil_pattern[i - 1]).length()
		)

	# A third of a bullet step, spread over the rise rather than applied at
	# once. Sid, watching CS2 back in slow motion, 2026-09-22: there is a
	# slight snap to the weapon's direction, "but very subtle". Not none.
	_check(
		biggest_step < steepest * 0.4,
		"no single tick moves the view near what one bullet moves (%.3f against %.3f degrees)"
			% [biggest_step, steepest]
	)


## The weapon model rides its own punch, scaled per axis, and changes nothing
## else.
func _test_viewmodel_follows_the_view() -> void:
	var data := WeaponLibrary.ak47()
	data.viewmodel_recoil = 2.0
	data.viewmodel_sway = 0.5
	var weapon := Weapon.new(data)
	var state := _standing()
	var now := 0

	for tick in 40:
		now += int(DT * SECOND)
		weapon.update(DT, now)
		weapon.fire(now, 1.0, Vector3.ZERO, 0.0, 0.0, state)

	_check(
		weapon.model_punch.length() > 0.1,
		"the model has kicked, so there is something to follow (%.2f degrees)"
			% weapon.model_punch.length()
	)
	_check(
		is_equal_approx(weapon.viewmodel_punch().y, weapon.model_punch.y * 2.0),
		"the weapon model climbs by viewmodel_recoil times its own punch"
	)
	_check(
		is_equal_approx(weapon.viewmodel_punch().x, weapon.model_punch.x * 1.0),
		"and sways by viewmodel_sway times that again"
	)

	data.viewmodel_recoil = 0.0
	_check(
		weapon.viewmodel_punch() == Vector2.ZERO,
		"and holds still when viewmodel_recoil is zero"
	)


## The camera and the weapon model are separate springs on purpose, and the
## camera's slow half is what lets the crosshair climb across a spray rather
## than max out in the first few rounds.
##
## That half also lets go faster once the trigger is up, because the reason it
## is slow is to still be there when the next round lands. Sid, 2026-09-22:
## "the decay when you stop shooting... feels a bit too floating."
func _test_the_camera_holds_while_firing_and_lets_go_after() -> void:
	for data in [WeaponLibrary.ak47(), WeaponLibrary.m4a1s()]:
		# The two springs are derived differently — the firing half from an
		# impulse response, the release from a plain exponential — so their
		# spring constants are not comparable. Their recovery times are.
		_check(
			data.view_punch_release_time < data.view_punch_recovery_time * 0.5,
			"%s comes home in %.0f ms off the trigger against %.0f ms on it"
				% [
					data.display_name,
					data.view_punch_release_time * 1000.0,
					data.view_punch_recovery_time * 1000.0
				]
		)

		# Empty a magazine, then let go and watch it come home.
		var weapon := Weapon.new(data)
		var state := _standing()
		var now := 0
		var fired := 0
		while fired < data.magazine_size:
			now += int(DT * SECOND)
			weapon.update(DT, now)
			if weapon.fire(now, 1.0, Vector3.ZERO, 0.0, 0.0, state) != null:
				fired += 1

		var left := weapon.aim_punch.y
		var halfway := -1.0
		var lowest := 0.0
		weapon.trigger_held = false
		for tick in 1024:
			now += int(DT * SECOND)
			weapon.update(DT, now)
			if halfway < 0.0 and weapon.aim_punch.y < left * 0.5:
				halfway = float(tick + 1) * DT
			lowest = minf(lowest, weapon.aim_punch.y)

		# An exponential is halfway down after ln(2)/ln(100) of the time it
		# takes to settle, so this tracks view_punch_release_time rather than
		# being a number of its own.
		_check(
			halfway > 0.0 and halfway < data.view_punch_release_time * 0.25,
			"%s crosshair is halfway home %.0f ms after the trigger comes up, against a %.0f ms return"
				% [
					data.display_name,
					halfway * 1000.0,
					data.view_punch_release_time * 1000.0
				]
		)
		# A return should not swing past the thing it is returning to. Under
		# damped, this passed most of a degree BELOW where the player was
		# pointing and came back up, which is most of what reads as floating.
		_check(
			lowest > -0.05,
			"%s comes home without dipping below where the player is pointing (%.2f degrees)"
				% [data.display_name, lowest]
		)


## The shape of the return, not just its length.
##
## A spring let go from rest starts with no speed at all, builds up and then
## eases out: an S, which reads as the crosshair hanging at the top of the
## spray before it drops. Sid, 2026-09-22: "it still feels like it hangs at
## the top for 200ms. It should move down very quickly. If it were a curve it
## would be the bottom left quarter of a circle. A sharp drop and smooth at
## the bottom."
##
## That curve is an exponential, which is what a critically damped spring makes
## when it is handed minus its own frequency times its height as a velocity.
## Its defining property is that it is steepest the instant it is released and
## never steeper again.
func _test_the_crosshair_drops_sharply_and_eases_out() -> void:
	for data in [WeaponLibrary.ak47(), WeaponLibrary.m4a1s()]:
		var weapon := Weapon.new(data)
		var state := _standing()
		var now := 0
		var fired := 0
		while fired < data.magazine_size:
			now += int(DT * SECOND)
			weapon.update(DT, now)
			if weapon.fire(now, 1.0, Vector3.ZERO, 0.0, 0.0, state) != null:
				fired += 1

		# Let go, and let the last round's own shove finish arriving: the fast
		# half is still a few milliseconds off its peak when the button comes
		# up, and that shove is the round's, not a hang. The curve Sid drew
		# starts at the top, so the windows below do too.
		weapon.trigger_held = false
		var left := weapon.aim_punch.y
		for tick in int(0.05 / DT):
			now += int(DT * SECOND)
			weapon.update(DT, now)
			if weapon.aim_punch.y < left:
				break
			left = weapon.aim_punch.y

		# How far it falls in each of eight windows, the eight together being
		# the whole return. Windows of the return's own length rather than a
		# fixed number of milliseconds, so the shape is what is measured and
		# not how long the return was set to take.
		var window := int(data.view_punch_release_time / 8.0 / DT)
		var falls: Array[float] = []
		var was := left
		for step in 8:
			for tick in window:
				now += int(DT * SECOND)
				weapon.update(DT, now)
			falls.append(was - weapon.aim_punch.y)
			was = weapon.aim_punch.y

		var steepest_first := true
		var easing := true
		for i in range(1, falls.size()):
			if falls[i] > falls[0]:
				steepest_first = false
			if falls[i] > falls[i - 1]:
				easing = false

		_check(
			steepest_first and easing,
			"%s crosshair falls hardest the moment the trigger comes up and eases out from there (%.2f, %.2f, %.2f, %.2f degrees over the first four eighths)"
				% [data.display_name, falls[0], falls[1], falls[2], falls[3]]
		)
		_check(
			falls[0] > left * 0.25,
			"%s crosshair gives up %.0f per cent of its height in the first eighth of its return rather than hanging there"
				% [data.display_name, 100.0 * falls[0] / maxf(left, 0.0001)]
		)


## The weapon is told about the trigger rather than left to infer it from the
## gap since the last round, which cost a round and a quarter of dead time at
## the top of the spray.
func _test_letting_go_beats_waiting_to_be_noticed() -> void:
	for data in [WeaponLibrary.ak47(), WeaponLibrary.m4a1s()]:
		var told := Weapon.new(data)
		var guessed := Weapon.new(data)
		var state := _standing()
		var now := 0
		var fired := 0
		while fired < data.magazine_size:
			now += int(DT * SECOND)
			told.update(DT, now)
			guessed.update(DT, now)
			told.fire(now, 1.0, Vector3.ZERO, 0.0, 0.0, state)
			if guessed.fire(now, 1.0, Vector3.ZERO, 0.0, 0.0, state) != null:
				fired += 1

		told.trigger_held = false
		for tick in int(0.06 / DT):
			now += int(DT * SECOND)
			told.update(DT, now)
			guessed.update(DT, now)

		_check(
			told.aim_punch.y < guessed.aim_punch.y * 0.75,
			"%s crosshair is %.2f degrees down sixty milliseconds after the button comes up, against %.2f if it had to be inferred from the gap"
				% [data.display_name, told.aim_punch.y, guessed.aim_punch.y]
		)


## Sid, 2026-09-22: the weapon model "looks like it's teleporting". It hangs
## off the camera, so it already carries the whole view kick, and the rotation
## on top of that happens about the eye: a degree of it throws the gun a long
## way across the screen. The view kick has to be most of what moves.
func _test_the_model_moves_less_than_the_view() -> void:
	for data in [WeaponLibrary.ak47(), WeaponLibrary.m4a1s()]:
		var weapon := Weapon.new(data)
		var state := _standing()
		var now := 0
		var worst_view := 0.0
		var worst_extra := Vector2.ZERO
		var fired := 0

		while fired < data.magazine_size:
			now += int(DT * SECOND)
			weapon.update(DT, now)
			if weapon.fire(now, 1.0, Vector3.ZERO, 0.0, 0.0, state) != null:
				fired += 1
			worst_view = maxf(worst_view, weapon.aim_punch.length())
			var extra := weapon.viewmodel_punch()
			worst_extra.x = maxf(worst_extra.x, absf(extra.x))
			worst_extra.y = maxf(worst_extra.y, absf(extra.y))

		_check(
			worst_extra.length() < worst_view * 0.5,
			"%s weapon model adds well under half of what the view kick moves (%.2f against %.2f degrees)"
				% [data.display_name, worst_extra.length(), worst_view]
		)
		_check(
			worst_extra.x > 0.0 and worst_extra.x < worst_extra.y,
			"%s sways sideways, visibly and less than it climbs (%.2f against %.2f degrees)"
				% [data.display_name, worst_extra.x, worst_extra.y]
		)


# --- Measured recovery timings --------------------------------------------
#
# Sid captured CS2 frame by frame on 2026-09-22: the weapon model tracked away
# from its resting position gives the recoil animation's length, and the
# accuracy box from weapon_debug_spread_show tracked back to its baseline size
# gives the accuracy reset. AK-47 644 and 867 ms, M4A1-S 353 and 542 ms.
#
# The two are different numbers and the accuracy one is longer, so the gun
# finishes moving before it finishes recovering. These tests exist so that
# stays true of this build, because it is the whole reason the animation
# cannot be trusted as a readout.


## How long after a single round the WEAPON MODEL's punch is still visibly
## moving, and how far it got, both in one pass. That is what Sid measured off
## CS2; the camera is a separate, much slower spring.
func _settle(data: WeaponData) -> Array:
	var weapon := Weapon.new(data)
	var now := int(SECOND)
	weapon.fire(now, 1.0, Vector3.ZERO, 0.0, 0.0, _standing())

	var peak := 0.0
	var samples: Array[float] = []
	for tick in 1024:
		now += int(DT * SECOND)
		weapon.update(DT, now)
		var size := weapon.model_punch.length()
		peak = maxf(peak, size)
		samples.append(size)

	# The last moment it was above a hundredth of its own peak, which is what
	# recoil_animation_time is defined against.
	var settled_at := 0.0
	for i in range(samples.size() - 1, -1, -1):
		if samples[i] >= peak * WeaponData.SETTLE_FRACTION:
			settled_at = float(i + 1) * DT
			break
	return [settled_at, peak]


## How long after a single standing shot the cone is back to its resting size.
func _accuracy_reset(data: WeaponData) -> float:
	var weapon := Weapon.new(data)
	var state := _standing()
	var now := int(SECOND)
	weapon.fire(now, 1.0, Vector3.ZERO, 0.0, 0.0, state)

	for tick in 1024:
		now += int(DT * SECOND)
		weapon.update(DT, now)
		if weapon.current_inaccuracy(state) <= data.inaccuracy_standing:
			return float(tick + 1) * DT
	return -1.0


## Every pattern's first entry is (0, 0), so reading a shot's recoil as the
## step INTO its entry left a single tap with no view kick whatsoever. A shot
## is what causes the climb to the next entry, not what results from the last.
func _test_a_single_tap_kicks_the_view() -> void:
	for data in [WeaponLibrary.ak47(), WeaponLibrary.m4a1s()]:
		var result := _settle(data)
		_check(
			(result[1] as float) > 0.1,
			"%s kicks the view on the very first round (%.2f degrees)"
				% [data.display_name, result[1]]
		)


func _test_animation_lasts_as_long_as_measured() -> void:
	for data in [WeaponLibrary.ak47(), WeaponLibrary.m4a1s()]:
		var settled: float = _settle(data)[0]
		_check(
			absf(settled - data.recoil_animation_time) < 0.02,
			"%s recoil animation lasts the measured %.0f ms (%.0f ms)"
				% [
					data.display_name,
					data.recoil_animation_time * 1000.0,
					settled * 1000.0
				]
		)


func _test_accuracy_resets_as_slowly_as_measured() -> void:
	for data in [WeaponLibrary.ak47(), WeaponLibrary.m4a1s()]:
		var reset := _accuracy_reset(data)
		_check(
			absf(reset - data.accuracy_reset_time()) < 0.02,
			"%s accuracy resets in %.0f ms (%.0f ms)"
				% [
					data.display_name,
					data.accuracy_reset_time() * 1000.0,
					reset * 1000.0
				]
		)
		# The sheet's recovery time is when a round's penalty is down to a tenth.
		var weapon := Weapon.new(data)
		var now := int(SECOND)
		weapon.fire(now, 1.0, Vector3.ZERO, 0.0, 0.0, _standing())
		var ticks := int(round(data.recovery_time_stand / DT))
		for tick in ticks:
			now += int(DT * SECOND)
			weapon.update(DT, now)
		var left: float = weapon.current_inaccuracy(_standing()) - data.inaccuracy_standing
		_check(
			absf(left / data.inaccuracy_per_shot - 0.1) < 0.01,
			"%s is down to a tenth of a round's penalty after the sheet's %.3f s (%.3f)"
				% [data.display_name, data.recovery_time_stand, left / data.inaccuracy_per_shot]
		)

		# Crouched it recovers on the sheet's crouched time, which is shorter.
		var crouched := Weapon.new(data)
		var ducked := Weapon.ShooterState.new(0.0, true, true)
		now = int(SECOND)
		crouched.fire(now, 1.0, Vector3.ZERO, 0.0, 0.0, ducked)
		for tick in int(round(data.recovery_time_crouch / DT)):
			now += int(DT * SECOND)
			crouched.update(DT, now, ducked)
		left = crouched.current_inaccuracy(ducked) - data.inaccuracy_crouching
		_check(
			absf(left / data.inaccuracy_per_shot - 0.1) < 0.01,
			"%s crouched is down to a tenth after the sheet's %.3f s (%.3f)"
				% [data.display_name, data.recovery_time_crouch, left / data.inaccuracy_per_shot]
		)


## Landing from a jump costs accuracy for a moment, as the sheet's "after
## landing" figure says, and it recovers the way a round's penalty does.
func _test_landing_costs_accuracy() -> void:
	var data := WeaponLibrary.ak47()
	var weapon := Weapon.new(data)
	var now := int(SECOND)
	weapon.update(DT, now, Weapon.ShooterState.new(0.0, false, false))
	now += int(DT * SECOND)
	weapon.update(DT, now, _standing())
	# The tick it lands on has already begun to recover it.
	var landed := weapon.current_inaccuracy(_standing())
	var expected := data.inaccuracy_standing + (data.inaccuracy_landing - data.inaccuracy_standing) * exp(
		-DT / data.accuracy_time_constant()
	)
	_check(
		absf(landed - expected) < 0.001,
		"just landed, the AK's cone is the sheet's 33.63, a tick recovered (%.3f against %.3f degrees)"
			% [landed, expected]
	)
	for tick in int(round(data.recovery_time_stand * 2.0 / DT)):
		now += int(DT * SECOND)
		weapon.update(DT, now, _standing())
	_check(
		weapon.current_inaccuracy(_standing()) < data.inaccuracy_standing * 1.1,
		"and it is back to standing accuracy shortly after"
	)


## The point of the two numbers being separate. A player who taps again the
## moment the gun stops moving is firing an inaccurate round.
func _test_the_gun_looks_ready_before_it_is() -> void:
	for data in [WeaponLibrary.ak47(), WeaponLibrary.m4a1s()]:
		var settled: float = _settle(data)[0]
		var reset := _accuracy_reset(data)
		_check(
			reset > settled + 0.1,
			"%s is still inaccurate %.0f ms after it has stopped moving"
				% [data.display_name, (reset - settled) * 1000.0]
		)


## Changing how long the crosshair takes to settle must not quietly change
## where it gets to over a spray, which is the thing that was observed.
##
## A faster spring stacks the rounds up less, so the solver raises the
## per-round kick to compensate. That is the point of solving it.
func _test_spray_peak_survives_a_faster_camera() -> void:
	var slow := WeaponLibrary.ak47()
	var fast := WeaponLibrary.ak47()
	fast.view_punch_recovery_time = slow.view_punch_recovery_time * 0.5

	var slow_peak: float = slow.spray_peak_per_degree() * slow.view_kick_up()
	var fast_peak: float = fast.spray_peak_per_degree() * fast.view_kick_up()
	_check(
		absf(fast_peak - slow_peak) < slow_peak * 0.02,
		"halving the camera's recovery leaves the spray's peak alone (%.3f against %.3f degrees)"
			% [fast_peak, slow_peak]
	)
	_check(
		fast.view_kick_up() > slow.view_kick_up(),
		"by kicking harder each round to make up for stacking less (%.2f against %.2f degrees)"
			% [fast.view_kick_up(), slow.view_kick_up()]
	)


## The spring is stiff on a fast weapon, so a long frame integrated in one go
## would ring instead of settling. update() substeps; this proves it.
func _test_punch_is_the_same_at_any_frame_length() -> void:
	var data := WeaponLibrary.m4a1s()
	var fine := Weapon.new(data)
	var coarse := Weapon.new(data)
	var now := int(SECOND)
	fine.fire(now, 1.0, Vector3.ZERO, 0.0, 0.0, _standing())
	coarse.fire(now, 1.0, Vector3.ZERO, 0.0, 0.0, _standing())

	# Inside the firing window: past it the two runs would cross the release
	# switch at different moments and diverge for a reason that is not the
	# integration.
	for tick in 16:
		now += int(DT * SECOND)
		fine.update(DT, now)
	coarse.update(16.0 * DT, now)

	_check(
		(fine.aim_punch - coarse.aim_punch).length() < 0.001,
		"an eighth-second frame lands where sixteen ticks do (%.4f against %.4f degrees)"
			% [fine.aim_punch.length(), coarse.aim_punch.length()]
	)


## Sid, 2026-09-22: "the aimpunch happens with 1 or 2 shots". It did. The kick
## was a fraction of each round's step through the pattern, and a pattern's
## vertical steps are front-loaded: the AK climbs about two degrees a round
## for seven rounds and then goes flat. So the view punched hard early and
## then only swayed. Every round kicks the same now.
func _test_every_round_kicks_the_view() -> void:
	for data in [WeaponLibrary.ak47(), WeaponLibrary.m4a1s()]:
		var weapon := Weapon.new(data)
		var state := _standing()
		var now := 0
		var kicks: Array[float] = []

		while kicks.size() < data.magazine_size:
			now += int(DT * SECOND)
			weapon.update(DT, now)
			var before := weapon.aim_punch_velocity.y
			if weapon.fire(now, 1.0, Vector3.ZERO, 0.0, 0.0, state) != null:
				kicks.append(weapon.aim_punch_velocity.y - before)

		var smallest: float = kicks[0]
		var largest: float = kicks[0]
		for kick in kicks:
			smallest = minf(smallest, kick)
			largest = maxf(largest, kick)

		_check(
			smallest > 0.0 and is_equal_approx(smallest, largest),
			"%s kicks the view upward by the same amount on all %d rounds"
				% [data.display_name, kicks.size()]
		)


## The sideways lean takes its direction from the pattern and its size from
## the weapon, so it stays small where the pattern does not: the AK's sideways
## steps reach three degrees a round in the second half of a spray.
func _test_the_view_leans_without_swinging() -> void:
	var data := WeaponLibrary.ak47()
	var weapon := Weapon.new(data)
	var state := _standing()
	var now := 0
	var leans: Array[float] = []

	while leans.size() < data.magazine_size:
		now += int(DT * SECOND)
		weapon.update(DT, now)
		var shot := weapon.fire(now, 1.0, Vector3.ZERO, 0.0, 0.0, state)
		if shot != null:
			leans.append(shot.view_punch.x)

	var went_left := false
	var went_right := false
	var biggest := 0.0
	for lean in leans:
		went_left = went_left or lean < 0.0
		went_right = went_right or lean > 0.0
		biggest = maxf(biggest, absf(lean))

	_check(
		went_left and went_right,
		"the view leans both ways through an AK spray"
	)
	_check(
		is_equal_approx(biggest, data.view_kick_side()),
		"and never further than view_kick_side, whatever the pattern does (%.3f degrees)"
			% biggest
	)
	_check(
		biggest < data.view_kick_up(),
		"which is less than it climbs (%.3f against %.3f degrees)"
			% [biggest, data.view_kick_up()]
	)


## Sid, 2026-09-22: "during spraying the crosshair should peak at around half
## of the height of the overall spray." The per-round kick is solved from
## that rather than picked, so this is the spec, not a regression guard.
func _test_the_spray_peaks_where_it_was_asked_to() -> void:
	for data in [WeaponLibrary.ak47(), WeaponLibrary.m4a1s()]:
		var weapon := Weapon.new(data)
		var state := _standing()
		var now := 0
		var peak := 0.0
		var fired := 0

		while fired < data.magazine_size:
			now += int(DT * SECOND)
			weapon.update(DT, now)
			if weapon.fire(now, 1.0, Vector3.ZERO, 0.0, 0.0, state) != null:
				fired += 1
			peak = maxf(peak, weapon.aim_punch.y)

		var climb := 0.0
		for i in data.recoil_pattern.size():
			climb = maxf(climb, data.recoil_offset(i).y)
		var wanted: float = climb * data.view_kick_spray_peak

		_check(
			absf(peak - wanted) < wanted * 0.05,
			"%s crosshair peaks at %.0f%% of the spray's climb (%.2f of %.2f degrees, asked for %.2f)"
				% [data.display_name, peak / climb * 100.0, peak, climb, wanted]
		)


## The solver walks the same spring twice over, in WeaponData rather than in
## Weapon, so the two have to be held together.
func _test_the_solver_agrees_with_the_weapon() -> void:
	for data in [WeaponLibrary.ak47(), WeaponLibrary.m4a1s()]:
		var weapon := Weapon.new(data)
		var state := _standing()
		var now := 0
		var peak := 0.0
		var fired := 0

		while fired < data.magazine_size:
			now += int(DT * SECOND)
			weapon.update(DT, now)
			if weapon.fire(now, 1.0, Vector3.ZERO, 0.0, 0.0, state) != null:
				fired += 1
			peak = maxf(peak, weapon.aim_punch.y)

		var predicted: float = data.spray_peak_per_degree() * data.view_kick_up()
		_check(
			absf(peak - predicted) < predicted * 0.05,
			"%s solver predicts the spray peak the weapon actually reaches (%.3f against %.3f degrees)"
				% [data.display_name, predicted, peak]
		)


## Sid, 2026-09-22: "the motion as it moves up is too smooth. we still want it
## to feel staccato, like each shot pushes it up."
##
## A single spring cannot give that. Its rise and its decay are the same two
## constants read two ways, so one slow enough to carry the crosshair up a
## whole spray is also smooth enough to have no rounds in it. The camera's
## kick is two springs added together for exactly this reason, and what this
## checks is that the fast one is actually visible: the crosshair has to shove
## up and fall back between rounds rather than ramp.
func _test_each_round_shoves_the_crosshair() -> void:
	for data in [WeaponLibrary.ak47(), WeaponLibrary.m4a1s()]:
		var weapon := Weapon.new(data)
		var state := _standing()
		var now := 0
		var fired := 0
		var peak := 0.0
		var low := 0.0
		var high := 0.0
		var rises: Array[float] = []
		var falls := 0

		while fired < data.magazine_size:
			now += int(DT * SECOND)
			weapon.update(DT, now)
			if weapon.fire(now, 1.0, Vector3.ZERO, 0.0, 0.0, state) != null:
				fired += 1
				# The first few rounds are still building, so the shove is
				# measured once the crosshair has something to fall back to.
				if fired > 3:
					rises.append(high - low)
					if high > low:
						falls += 1
				low = weapon.aim_punch.y
				high = weapon.aim_punch.y
			var y := weapon.aim_punch.y
			low = minf(low, y)
			high = maxf(high, y)
			peak = maxf(peak, y)

		var shove := 0.0
		for rise in rises:
			shove += rise
		shove /= maxf(float(rises.size()), 1.0)

		_check(
			shove > peak * 0.1,
			"%s shoves the crosshair %.2f degrees a round against a %.2f degree climb"
				% [data.display_name, shove, peak]
		)
		_check(
			falls == rises.size(),
			"%s falls back between every round rather than ramping (%d of %d)"
				% [data.display_name, falls, rises.size()]
		)


## The gun has to drop back towards rest between rounds, not climb to a height
## and jitter there for the rest of the magazine.
##
## CS2 does not run a spring on the weapon model: it replays the firing clip
## from its start on every round, so the gun falls back however fast the
## rounds come. A single spring long enough to last the measured animation
## reaches its own peak about 78 ms in and the next AK round lands at 100 ms,
## so it barely fell at all: 25 per cent of the height it was sitting at.
##
## Sid, 2026-09-22: "the animation doesn't continually fall. It pushes up till
## you stop holding the mouse button. The animation needs to fall a little
## between shots."
func _test_the_weapon_model_falls_between_rounds() -> void:
	for data in [WeaponLibrary.ak47(), WeaponLibrary.m4a1s()]:
		var weapon := Weapon.new(data)
		var state := _standing()
		var now := 0
		var fired := 0
		var peak := 0.0
		var low := 0.0
		var high := 0.0
		var rises: Array[float] = []
		var falls := 0

		while fired < data.magazine_size:
			now += int(DT * SECOND)
			weapon.update(DT, now)
			if weapon.fire(now, 1.0, Vector3.ZERO, 0.0, 0.0, state) != null:
				fired += 1
				# The first few rounds are still building, so the drop is
				# measured once the gun has something to fall back from.
				if fired > 3:
					rises.append(high - low)
					if high > low:
						falls += 1
				low = weapon.viewmodel_punch().y
				high = low
			var y := weapon.viewmodel_punch().y
			low = minf(low, y)
			high = maxf(high, y)
			peak = maxf(peak, y)

		var swing := 0.0
		for rise in rises:
			swing += rise
		swing /= maxf(float(rises.size()), 1.0)

		_check(
			swing > peak * 0.5,
			"%s weapon model swings %.2f degrees a round against a %.2f degree height, so most of each round's kick is gone before the next lands"
				% [data.display_name, swing, peak]
		)
		_check(
			falls == rises.size(),
			"%s weapon model falls back between every round (%d of %d)"
				% [data.display_name, falls, rises.size()]
		)


## Splitting the weapon model's spring in two must not move the measurement it
## was derived from, which is why the slow half's recovery time is solved
## rather than picked.
func _test_the_model_springs_add_up_to_the_measurement() -> void:
	for data in [WeaponLibrary.ak47(), WeaponLibrary.m4a1s()]:
		_check(
			data.model_hold_time() > data.recoil_animation_time,
			"%s slow half runs %.0f ms on its own, longer than the measured %.0f, because the fast half raises the peak the settle is taken against"
				% [
					data.display_name,
					data.model_hold_time() * 1000.0,
					data.recoil_animation_time * 1000.0
				]
		)
		_check(
			data.model_punch_snap_time < data.cycle_time * 2.0,
			"%s fast half settles in %.0f ms, inside two rounds at %.0f ms apart"
				% [
					data.display_name,
					data.model_punch_snap_time * 1000.0,
					data.cycle_time * 1000.0
				]
		)


func _test_inaccuracy_by_state() -> void:
	var weapon := Weapon.new(WeaponLibrary.ak47())

	var standing := weapon.current_inaccuracy(Weapon.ShooterState.new(0.0, true, false))
	var crouched := weapon.current_inaccuracy(Weapon.ShooterState.new(0.0, true, true))
	var walking := weapon.current_inaccuracy(Weapon.ShooterState.new(40.0, true, false))
	var running := weapon.current_inaccuracy(Weapon.ShooterState.new(215.0, true, false))
	var jumping := weapon.current_inaccuracy(Weapon.ShooterState.new(0.0, false, false))
	var running_jump := weapon.current_inaccuracy(Weapon.ShooterState.new(215.0, false, false))

	_check(crouched < standing, "crouching is more accurate than standing")
	_check(
		absf(walking - standing) < 0.0001,
		"a slow walk costs nothing, which is what makes counter-strafing work"
	)
	_check(running > standing * 10.0, "running is far less accurate")
	_check(jumping > standing * 10.0, "a standing jump is far less accurate")
	# The sheet has a standing jump's apex (147.77) under a full run (182.07):
	# it is the two together that are worst.
	_check(running_jump > running and running_jump > jumping, "jumping at a run is the worst of all")

	# The sheet's own figures, back out of the cone: its accurate range is
	# where the widest a standing round can land is 15.24 cm off.
	var ak := WeaponLibrary.ak47()
	_check_near(
		tan(deg_to_rad(ak.inaccuracy_standing)) * 21.74 / 0.0254, 6.0,
		"the AK standing still lands within 6 inches at the sheet's accurate range, 21.74 m"
	)
	_check_near(standing, WeaponLibrary.cs_inaccuracy(7.01), "the AK stands at the sheet's 7.01")
	_check_near(running, WeaponLibrary.cs_inaccuracy(182.07), "and runs at its 182.07")
	_check_near(jumping, WeaponLibrary.cs_inaccuracy(147.77), "and tops a standing jump at its 147.77")


func _test_damage_falloff() -> void:
	var data := WeaponLibrary.ak47()
	_check_near(data.damage_at(0.0), data.base_damage, "point blank is base damage")
	_check_near(
		data.damage_at(data.falloff_distance),
		data.base_damage * data.range_modifier,
		"damage drops by the range modifier every falloff distance"
	)
	_check(
		data.damage_at(2000.0) < data.damage_at(500.0),
		"damage keeps falling with distance"
	)


func _test_hitbox_multipliers() -> void:
	var data := WeaponLibrary.ak47()
	_check_near(
		data.base_damage * data.hitbox_multiplier(&"head"), 144.0,
		"an AK headshot is 144 unarmoured at point blank"
	)
	_check_near(
		data.base_damage * data.hitbox_multiplier(&"chest"), 36.0,
		"an AK chest shot is 36 unarmoured at point blank"
	)
	_check(
		data.hitbox_multiplier(&"leg") < data.hitbox_multiplier(&"chest"),
		"legs take less than the chest"
	)

	var m4 := WeaponLibrary.m4a1s()
	_check_near(m4.base_damage, 38.0, "an M4A1-S chest shot is 38 unarmoured at point blank")
	_check_near(
		m4.base_damage * m4.hitbox_multiplier(&"head"), 132.05,
		"an M4A1-S headshot is 132 unarmoured at point blank"
	)


## Everything the firing model reads is the sheet's, read through
## WeaponSheet rather than typed in, so a new weapon is one line.
func _test_every_value_comes_from_the_sheet() -> void:
	_check(WeaponSheet.rows().size() == 45, "the sheet has its 45 rows (%d)" % WeaponSheet.rows().size())
	var ak := WeaponLibrary.ak47()
	_check_near(ak.base_damage, 36.0, "AK damage 36")
	_check_near(ak.armor_penetration, 0.775, "AK armour penetration 77.5%")
	_check_near(ak.range_modifier, 0.98, "AK loses 2% every 500 units")
	_check_near(ak.cycle_time, 0.1, "AK at 600 RPM")
	_check_equal(ak.magazine_size, 30, "AK magazine 30")
	_check_equal(ak.reserve_ammo, 90, "AK reserve 90")
	_check_near(ak.max_player_speed, 215.0, "AK mobility 215")
	_check_near(ak.max_range, 8192.0, "AK range 8192")
	_check_near(ak.recovery_time_stand, 0.368, "AK recovers standing in 0.368 s")
	_check(ak.automatic, "the AK is automatic")
	var m4 := WeaponLibrary.m4a1s()
	_check_equal(m4.reserve_ammo, 60, "M4A1-S reserve 60")
	_check_near(m4.inaccuracy_per_shot, WeaponSheet.cone_degrees(7.0), "the M4A1-S reads its silencer row for firing inaccuracy")
	_check_near(m4.base_damage, 38.0, "and its main row where the silencer row says the same")
	# Units the sheet writes its own way.
	_check_near(WeaponSheet.parse_number("$2,700"), 2700.0, "prices lose their dollar and comma")
	_check_near(WeaponSheet.parse_number("77.50%"), 0.775, "percentages become fractions")
	_check_near(WeaponSheet.parse_number("3.475x"), 3.475, "multipliers lose their x")
	_check_near(WeaponSheet.parse_number("21.74m"), 21.74, "metres lose their m")
	_check(is_nan(WeaponSheet.parse_number("-")), "a dash is no number")
	_check(is_nan(WeaponSheet.parse_number("see note")), "nor is a note")
	# The sheet's accurate range is where its standing cone is six inches wide,
	# for every weapon that has both: the conversion to degrees holds for all.
	var worst := 0.0
	for weapon: String in WeaponSheet.rows():
		var metres := WeaponSheet.number(weapon, "Accurate Range Stand")
		var stand := WeaponSheet.number(weapon, "Standing Inaccuracy")
		if is_nan(metres) or is_nan(stand):
			continue
		var inches := tan(deg_to_rad(WeaponSheet.cone_degrees(stand))) * metres / 0.0254
		worst = maxf(worst, absf(inches - 6.0))
	_check(worst < 0.02, "every weapon's accurate range is its six-inch cone (worst off by %.3f in)" % worst)


## The sheet's fatal headshot ranges, which are the damage, the multiplier,
## the armour and the falloff all at once: a round to the head kills out to
## there and not past it. Taken through HitTarget, the path a real round takes.
func _test_fatal_headshot_ranges() -> void:
	var cases := [
		[WeaponLibrary.ak47(), false, 9024.61],
		[WeaponLibrary.ak47(), true, 2716.24],
		[WeaponLibrary.m4a1s(), false, 2246.53],
	]
	for case in cases:
		var data: WeaponData = case[0]
		var helmet: bool = case[1]
		var reach: float = case[2]
		var kills := func(distance: float) -> bool:
			var target := HitTarget.new()
			target.build_own_hitboxes = false
			target.wear(100.0 if helmet else 0.0, helmet)
			target.reset()
			target.apply_damage(
				data.damage_at(distance) * data.hitbox_multiplier(&"head"), &"head", data.armor_penetration
			)
			var dead := not target.alive
			target.free()
			return dead
		_check(
			kills.call(reach - 5.0) and not kills.call(reach + 5.0),
			"%s headshot %s kills out to the sheet's %.0f units and no further"
				% [data.display_name, "through a helmet" if helmet else "without a helmet", reach]
		)
	# And the sheet says none: the M4A1-S never one-shots through a helmet.
	var m4 := WeaponLibrary.m4a1s()
	var target := HitTarget.new()
	target.build_own_hitboxes = false
	target.wear(100.0, true)
	target.reset()
	target.apply_damage(m4.damage_at(0.0) * m4.hitbox_multiplier(&"head"), &"head", m4.armor_penetration)
	_check(target.alive, "an M4A1-S headshot through a helmet does not kill, even point blank")
	target.free()


# --- Hit registration -----------------------------------------------------

func _build_world() -> void:
	_world = Node3D.new()
	root.add_child(_world)

	_target = HitTarget.new()
	_target.position = Vector3(0.0, 0.0, -256.0)
	_world.add_child(_target)


## Aim at the head and hit the head. The basic promise of hit registration.
func _test_headshot_registers() -> void:
	var data := WeaponLibrary.ak47()
	data.inaccuracy_standing = 0.0
	data.inaccuracy_per_shot = 0.0
	var weapon := Weapon.new(data)

	var origin := Vector3(0.0, 64.0, 0.0)
	var head := _target.global_position + Vector3(
		0.0, HitTarget.ZONES[&"head"]["centre"], 0.0
	)
	var angles := PlayerInput.angles_from_direction(head - origin)

	var shot := weapon.fire(
		0, 0.0, origin, angles.x, angles.y, _standing()
	)
	_check(shot != null, "the shot fired")
	if shot == null:
		return

	var result := Hitscan.fire_at(
		_world.get_world_3d().direct_space_state, shot, data
	)
	_check(result.hit, "the bullet hit something")
	_check_equal(result.zone, &"head", "it hit the head")
	_check(
		result.hitbox != null and result.hitbox.target == _target,
		"the hit is attributed to the target"
	)

	# 36 base, x4 for the head, minus falloff over 256 units, then 77.5%
	# through armour.
	var expected := (
		data.damage_at(result.distance)
		* data.head_multiplier
		* data.armor_penetration
	)
	_check_near(
		result.damage, expected,
		"the damage matches base x head x falloff x armour"
	)
	_check(
		_target.health < _target.max_health,
		"the target actually lost health"
	)


## A wall in the way stops the bullet. A shot that clips a corner must not
## register on whoever is behind it, which is the kind of thing that reads as
## broken hit registration when it goes wrong.
func _test_wall_blocks_the_shot() -> void:
	_target.reset()

	_wall = StaticBody3D.new()
	_wall.position = Vector3(0.0, 64.0, -128.0)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(256.0, 256.0, 16.0)
	collision.shape = shape
	_wall.add_child(collision)
	_wall.collision_layer = Hitscan.WORLD_LAYER
	_world.add_child(_wall)

	# The wall only exists from the next physics step, so trace by hand
	# against a ray that would otherwise reach the head.
	var data := WeaponLibrary.ak47()
	data.inaccuracy_standing = 0.0
	var weapon := Weapon.new(data)
	var origin := Vector3(0.0, 64.0, 0.0)
	var head := _target.global_position + Vector3(
		0.0, HitTarget.ZONES[&"head"]["centre"], 0.0
	)
	var angles := PlayerInput.angles_from_direction(head - origin)
	var shot := weapon.fire(0, 0.0, origin, angles.x, angles.y, _standing())

	# Step physics so the wall is in the space.
	await physics_frame
	await physics_frame

	var result := Hitscan.fire_at(
		_world.get_world_3d().direct_space_state, shot, data
	)
	_check(result.hit, "the bullet hit the wall")
	_check(result.hitbox == null, "it did not register on the target behind it")
	_check_near(_target.health, _target.max_health, "the target took no damage")


# --- Harness --------------------------------------------------------------

## The crosshair has to sit exactly on the point a bullet with no spread
## passes through, because it is the only reference anyone has for judging
## whether aiming is right.
##
## The bug this guards: the crosshair was a Label anchored to the centre. A
## Control's anchors place its top-left corner, so the glyph was drawn down
## and right of centre by half its own box, and the first bullet looked like
## it landed up and to the left. The gun was fine; the crosshair was not.
func _test_crosshair_is_centred() -> void:
	var crosshair := Crosshair.new()
	root.add_child(crosshair)
	var viewport: Vector2 = root.get_visible_rect().size

	_check(
		crosshair.position.is_equal_approx(Vector2.ZERO),
		"the crosshair starts at the origin rather than at the centre (%s)"
			% crosshair.position
	)
	_check(
		crosshair.size.is_equal_approx(viewport),
		"the crosshair covers the whole viewport (%s of %s)"
			% [crosshair.size, viewport]
	)
	# Which is what makes its own centre the centre of the screen, and that
	# is the point it draws itself around.
	_check(
		(crosshair.position + crosshair.size * 0.5).is_equal_approx(viewport * 0.5),
		"so what it draws around is the centre of the screen"
	)
	crosshair.queue_free()


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	printerr("FAIL: %s" % description)


func _check_equal(actual: Variant, expected: Variant, description: String) -> void:
	_checks += 1
	if actual == expected:
		return
	_failures += 1
	printerr("FAIL: %s (expected %s, got %s)" % [description, expected, actual])


func _check_near(actual: float, expected: float, description: String) -> void:
	_checks += 1
	if absf(actual - expected) <= 0.01:
		return
	_failures += 1
	printerr("FAIL: %s (expected %.4f, got %.4f)" % [description, expected, actual])


func _report() -> void:
	if _world != null:
		_world.free()
	if _failures == 0:
		print("%d weapon checks passed." % _checks)
		quit(0)
	else:
		printerr("%d of %d weapon checks failed." % [_failures, _checks])
		quit(1)
