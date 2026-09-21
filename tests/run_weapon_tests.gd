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
