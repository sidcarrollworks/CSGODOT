extends "res://tests/check_suite.gd"

## The player owns one current shooter state. Every weapon update must see
## this command's movement, including landing and changing crouch recovery.
## No scene or extracted assets are needed.


func _near_tolerance() -> float:
	return 0.00001


func _initialize() -> void:
	var dt := SimClock.tick_seconds()
	var data := WeaponData.new()
	data.max_player_speed = 100.0
	data.inaccuracy_standing = 1.0
	data.inaccuracy_crouching = 0.25
	data.inaccuracy_jumping = 5.0
	data.inaccuracy_moving = 9.0
	data.inaccuracy_landing = 11.0
	# A crouched tick recovers to a tenth; standing takes two ticks.
	data.recovery_time_crouch = dt
	data.recovery_time_stand = 2.0 * dt
	var player := PlayerSim.new()
	player.weapon = Weapon.new(data)
	var state := player.shooter_state
	var other := PlayerSim.new()
	_check(state != other.shooter_state, "players own separate shooter states")

	_step(player, 0, Vector3(3.0, 900.0, 4.0), true, false, false)
	_check_state(player, state, 5.0, true, false, false, "grounded")
	_check_near(player.weapon.current_inaccuracy(state), 1.0,
		"vertical velocity does not add movement inaccuracy")

	# 64.5 is halfway between the movement cone's 34% and 95% thresholds.
	_step(player, 1, Vector3(64.5, -300.0, 0.0), false, false, false)
	_check_state(player, state, 64.5, false, false, false, "airborne running")
	_check_near(player.weapon.current_inaccuracy(state), 5.0 + 8.0 * pow(0.5, 0.25),
		"airborne running uses the new speed and ground state")

	_step(player, 2, Vector3(0.0, -300.0, -64.5), false, true, true)
	_check_state(player, state, 64.5, false, true, true, "airborne crouch walking")
	_check_near(player.weapon.current_inaccuracy(state), 8.25,
		"crouch and walk changes immediately affect the cone")

	_step(player, 3, Vector3.ZERO, true, true, true)
	_check_state(player, state, 0.0, true, true, true, "crouched landing")
	_check_near(player.weapon.current_inaccuracy(state), 1.25,
		"Weapon.update sees landing and uses crouched recovery in the same tick")

	_step(player, 4, Vector3.ZERO, true, false, false)
	_check_state(player, state, 0.0, true, false, false, "standing still")
	_check_near(player.weapon.current_inaccuracy(state), 1.0 + sqrt(0.1),
		"Weapon.update switches to standing recovery without repeating landing")
	_check(other.shooter_state.speed == 0.0 and other.shooter_state.on_ground
		and not other.shooter_state.ducked and not other.shooter_state.walking,
		"updating one player leaves another player's state untouched")
	player.free()
	other.free()
	_finish("shooter-state")


func _step(
	player: PlayerSim, tick: int, velocity: Vector3, grounded: bool, ducked: bool, walking: bool
) -> void:
	player.velocity = velocity
	player.on_ground = grounded
	player.is_ducked = ducked
	var cmd := UserCmd.new()
	cmd.tick = tick
	cmd.buttons = UserCmd.WALK if walking else 0
	player._update_weapon(cmd, SimClock.tick_seconds(), false)


func _check_state(
	player: PlayerSim, retained: Weapon.ShooterState, speed: float, grounded: bool,
	ducked: bool, walking: bool, label: String
) -> void:
	_check(player.shooter_state == retained, "%s reuses the player's state" % label)
	_check_near(retained.speed, speed, "%s refreshes horizontal speed" % label)
	_check_equal(retained.on_ground, grounded, "%s refreshes ground state" % label)
	_check_equal(retained.ducked, ducked, "%s refreshes crouch state" % label)
	_check_equal(retained.walking, walking, "%s refreshes walk state" % label)
