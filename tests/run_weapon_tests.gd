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
		_test_spray_resets_on_time()
		_test_patterns_are_the_measured_ones()
		_test_recoil_scale()
		_test_inaccuracy_by_state()
		_test_damage_falloff()
		_test_hitbox_multipliers()
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
	var cycle := int(weapon.data.cycle_time * SECOND)

	for shot in 6:
		weapon.fire(shot * cycle, 0.0, Vector3.ZERO, 0.0, 0.0, _standing())
	_check(
		weapon.accumulated_punch.length() > 1.0,
		"the view has climbed after six shots (%.2f degrees)"
			% weapon.accumulated_punch.length()
	)
	_check(weapon.shot_index() == 6, "six shots into the pattern")

	# Let go of the trigger and wait.
	var now := 6 * cycle
	for tick in 512:
		now += int(DT * SECOND)
		weapon.update(DT, now)

	_check(
		weapon.accumulated_punch == Vector2.ZERO,
		"the view returns exactly to where the player was pointing"
	)
	_check_equal(
		weapon.shot_index(), 0,
		"the pattern restarts once the view has settled"
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
				climb.append(weapon.accumulated_punch.y)

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
				"%s view has climbed by the eighth shot (%.2f degrees)"
					% [data.display_name, climb[7]]
			)


## The spray restarts on time off the trigger, not on how far the view has
## recovered. A pattern's first entry is (0, 0), so punch after shot one is
## zero and a recovery test resets a spray that has not started.
func _test_spray_resets_on_time() -> void:
	var data := WeaponLibrary.ak47()
	var weapon := Weapon.new(data)
	var state := _standing()
	var now := 0

	# One shot, then wait less than the reset time.
	now += int(DT * SECOND)
	weapon.update(DT, now)
	var first := weapon.fire(now, 1.0, Vector3.ZERO, 0.0, 0.0, state)
	_check(first != null and first.shot_index == 0, "the first shot is shot zero")
	_check_near(
		weapon.accumulated_punch.length(), 0.0,
		"the first shot applies no punch, because the pattern starts at zero"
	)

	var short_wait := int(data.recoil_reset_time * 0.5 * SECOND)
	var target := now + short_wait
	while now < target:
		now += int(DT * SECOND)
		weapon.update(DT, now)
	_check_equal(
		weapon.shot_index(), 1,
		"a pause shorter than the reset time keeps the place in the pattern"
	)

	var long_wait := int(data.recoil_reset_time * 1.5 * SECOND)
	target = now + long_wait
	while now < target:
		now += int(DT * SECOND)
		weapon.update(DT, now)
	_check_equal(
		weapon.shot_index(), 0,
		"a pause longer than the reset time starts the pattern again"
	)


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
	_check_equal(
		m4.magazine_size, m4.recoil_pattern.size(),
		"the M4A1-S magazine and its pattern are the same length"
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
	for shot in 5:
		weapon.fire(shot * cycle, 0.0, Vector3.ZERO, 0.0, 0.0, _standing())

	_check_near(
		weapon.accumulated_punch.y, data.recoil_pattern[4].y * 0.5,
		"recoil_scale halves how far the view climbs"
	)


func _test_inaccuracy_by_state() -> void:
	var weapon := Weapon.new(WeaponLibrary.ak47())

	var standing := weapon.current_inaccuracy(Weapon.ShooterState.new(0.0, true, false))
	var crouched := weapon.current_inaccuracy(Weapon.ShooterState.new(0.0, true, true))
	var walking := weapon.current_inaccuracy(Weapon.ShooterState.new(40.0, true, false))
	var running := weapon.current_inaccuracy(Weapon.ShooterState.new(215.0, true, false))
	var jumping := weapon.current_inaccuracy(Weapon.ShooterState.new(0.0, false, false))

	_check(crouched < standing, "crouching is more accurate than standing")
	_check(
		absf(walking - standing) < 0.0001,
		"a slow walk costs nothing, which is what makes counter-strafing work"
	)
	_check(running > standing * 10.0, "running is far less accurate")
	_check(jumping > running, "jumping is the worst of all")


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
