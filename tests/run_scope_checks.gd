extends "res://tests/check_suite.gd"

## Checks the scopes (weapons TODO R4): the six guns CS2 scopes, each with
## the game's own levels, fields of view, zoom times and scoped numbers;
## right click stepping through the levels and back out; the view easing
## to each level over its zoom time and the scoped accuracy coming in with
## it; the scoped speed; the AWP and SSG 08 coming out of the scope for
## their shot and going back in once the bolt is worked; a reload or a
## switch taking the scope down; noscope kills; and, through commands on a
## world's ticks, a player scoping with right click (weapon_zoom) and
## running no faster than the scoped speed, and a bot with an AWP firing
## only through its scope.
##
##   godot --headless --path . --script tests/run_scope_checks.gd
##
## Needs nothing extracted: bots without their model wear the standard boxes.

var DT := SimClock.tick_seconds()
const SECOND := 1_000_000
## Well after anything a weapon starts with, so a draw or a last shot at
## time zero is long over.
const T0 := 100 * SECOND

var _world: Node3D


## A player that runs what the check asks of it: a tap of a button, walking
## forward.
class Commanded extends PlayerSim:
	var tap := 0
	var walks := false
	## Presses for the next command, in order, each [button, fraction].
	var taps: Array = []

	func command_for(tick: int, dt: float) -> UserCmd:
		var cmd := super.command_for(tick, dt)
		if tap != 0:
			cmd.steps.append(UserCmd.SubtickStep.new(tap, true, 0.5, yaw_degrees, pitch_degrees))
			tap = 0
		for press: Array in taps:
			cmd.steps.append(UserCmd.SubtickStep.new(press[0], true, press[1], yaw_degrees, pitch_degrees))
		taps = []
		if walks:
			cmd.move = Vector2(0.0, 1.0)
		return cmd


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_the_games_numbers()
	_test_right_click_steps_through_the_levels()
	_test_the_view_eases_in()
	_test_scoped_accuracy_comes_in_with_the_view()
	_test_the_scoped_speed()
	_test_a_sniper_comes_out_for_its_shot()
	_test_a_reload_or_a_switch_takes_the_scope_down()
	_test_noscope()

	_world = Node3D.new()
	root.add_child(_world)
	_build_floor()
	await physics_frame
	await physics_frame
	await _test_a_player_scopes_with_right_click()
	await _test_a_click_and_a_round_in_one_tick()
	await _test_a_bot_fires_through_its_scope()
	_finish("scope")


# --- The game's numbers ----------------------------------------------------------

func _test_the_games_numbers() -> void:
	var scoping := PackedStringArray()
	for data in WeaponLibrary.all():
		if data.zoom_levels() > 0:
			scoping.append(data.item_class)
		_check(
			(data.scoped != null) == (data.zoom_levels() > 0),
			"%s has scoped numbers exactly when it has a scope" % data.item_class
		)
	scoping.sort()
	_check_equal(
		scoping,
		PackedStringArray(["weapon_aug", "weapon_awp", "weapon_g3sg1", "weapon_scar20", "weapon_sg556", "weapon_ssg08"]),
		"six guns scope, as m_nZoomLevels says"
	)

	var awp := WeaponLibrary.build("weapon_awp")
	_check_equal(awp.zoom_fovs, PackedFloat32Array([40.0, 10.0]), "the AWP zooms to fov 40, then 10")
	_check_near(awp.zoom_time(1), 0.05, "and takes 0.05 s to each level")
	_check(awp.unzooms_after_shot and awp.hides_view_model_when_zoomed and not awp.shows_crosshair,
		"the AWP comes out of the scope to fire, puts the arms away scoped, and has no crosshair")
	_check_near(awp.max_player_speed, 200.0, "the AWP runs at 200")
	_check_near(awp.scoped.max_player_speed, 100.0, "and at 100 scoped")
	_check_near(awp.scoped.inaccuracy_standing, WeaponSheet.cone_degrees((0.002 + 0.0002) * 1000.0),
		"scoped, it stands at the game's second inaccuracy (0.002 and the spread)")
	_check(awp.scoped.inaccuracy_standing < awp.inaccuracy_standing / 20.0,
		"a small fraction of its unscoped cone (%.3f against %.3f degrees)" % [awp.scoped.inaccuracy_standing, awp.inaccuracy_standing])
	_check_near(awp.scoped.base_damage, awp.base_damage, "and does the same damage")

	var ssg := WeaponLibrary.build("weapon_ssg08")
	_check_equal(ssg.zoom_fovs, PackedFloat32Array([40.0, 15.0]), "the SSG 08 zooms to 40, then 15")
	_check_near(ssg.scoped.max_player_speed, 230.0, "and runs at 230 scoped or not")
	var scar := WeaponLibrary.build("weapon_scar20")
	_check(not scar.unzooms_after_shot and scar.hides_view_model_when_zoomed, "the SCAR-20 stays scoped as it fires")

	var aug := WeaponLibrary.build("weapon_aug")
	_check_equal(aug.zoom_fovs, PackedFloat32Array([45.0]), "the AUG has one level, fov 45")
	_check_near(aug.zoom_time(1), 0.1, "0.1 s in")
	_check_near(aug.zoom_time(0), 0.06, "0.06 s out")
	_check(not aug.hides_view_model_when_zoomed and aug.shows_crosshair and not aug.unzooms_after_shot,
		"the AUG keeps its arms and crosshair and stays scoped as it fires")
	_check_near(aug.scoped.max_player_speed, 150.0, "and runs at 150 scoped")

	var ak := WeaponLibrary.ak47()
	_check(ak.zoom_levels() == 0 and ak.scoped == null and ak.shows_crosshair, "the AK-47 has no scope")
	var m4 := WeaponLibrary.m4a1s()
	_check(m4.zoom_levels() == 0, "nor the M4A1-S, whose right click is its silencer")


# --- The weapon ------------------------------------------------------------------

func _test_right_click_steps_through_the_levels() -> void:
	var awp := _ready_weapon("weapon_awp")
	var levels: Array[int] = []
	for i in 3:
		_check(awp.press_zoom(T0 + i * SECOND), "the AWP scopes on right click")
		levels.append(awp.zoom_level)
	_check_equal(levels, [1, 2, 0] as Array[int], "each press the next level, and from the last back out")

	var aug := _ready_weapon("weapon_aug")
	aug.press_zoom(T0)
	var first := aug.zoom_level
	aug.press_zoom(T0 + SECOND)
	_check(first == 1 and aug.zoom_level == 0, "the AUG's one level, in and out")

	var ak := _ready_weapon("weapon_ak47")
	_check(not ak.press_zoom(T0) and ak.zoom_level == 0, "right click does nothing to the AK-47's aim")

	var drawing := Weapon.new(WeaponLibrary.build("weapon_awp"))
	drawing.draw(T0, 1.0)
	_check(not drawing.press_zoom(T0 + 500_000) and drawing.zoom_level == 0, "no scoping while it is being drawn")
	_check(drawing.press_zoom(T0 + SECOND), "and once it is drawn, yes")

	var reloading := _ready_weapon("weapon_awp")
	reloading.ammo = 1
	reloading.start_reload(T0)
	_check(not reloading.press_zoom(T0 + 100_000) and reloading.zoom_level == 0, "nor while it is reloading")


func _test_the_view_eases_in() -> void:
	var awp := _ready_weapon("weapon_awp")
	_check_near(awp.zoom_fov_at(T0), 90.0, "unscoped, the view is fov 90")
	awp.press_zoom(T0)
	_check_near(awp.zoom_fov_at(T0), 90.0, "scoping, it starts from 90")
	_check_near(awp.zoom_fov_at(T0 + 25_000), 65.0, "is half way to 40 in half the zoom time")
	_check_near(awp.zoom_fov_at(T0 + 50_000), 40.0, "and at 40 when the zoom time is up")
	awp.press_zoom(T0 + SECOND)
	_check_near(awp.zoom_fov_at(T0 + SECOND + 25_000), 25.0, "the second level eases from 40 to 10")
	awp.press_zoom(T0 + 2 * SECOND)
	_check_near(awp.zoom_fov_at(T0 + 2 * SECOND + 50_000), 90.0, "and out, back to 90")


func _test_scoped_accuracy_comes_in_with_the_view() -> void:
	var awp := _ready_weapon("weapon_awp")
	var standing := Weapon.ShooterState.new()
	var unscoped := awp.current_inaccuracy(standing, T0)
	_check_near(unscoped, awp.data.inaccuracy_standing, "unscoped, the AWP's standing cone is the unscoped one")
	awp.press_zoom(T0)
	_check_near(awp.current_inaccuracy(standing, T0), unscoped, "scoping in, none of the scoped accuracy yet: a quickscope misses")
	_check_near(
		awp.current_inaccuracy(standing, T0 + 25_000),
		lerpf(awp.data.inaccuracy_standing, awp.data.scoped.inaccuracy_standing, 0.5),
		"half of it half way through the zoom time"
	)
	_check_near(awp.current_inaccuracy(standing, T0 + 50_000), awp.data.scoped.inaccuracy_standing, "and all of it once scoped in")
	awp.press_zoom(T0 + SECOND)
	_check_near(awp.current_inaccuracy(standing, T0 + SECOND), awp.data.scoped.inaccuracy_standing,
		"the second level keeps it: the gun is scoped either way")
	awp.press_zoom(T0 + 2 * SECOND)
	_check_near(awp.current_inaccuracy(standing, T0 + 2 * SECOND), unscoped, "and out of the scope it is gone at once")

	# Moving scoped counts against the scoped speed: 100 is a full run.
	var scoped := _ready_weapon("weapon_awp")
	scoped.press_zoom(T0)
	var running := Weapon.ShooterState.new(100.0)
	_check_near(scoped.current_inaccuracy(running, T0 + SECOND), scoped.data.scoped.inaccuracy_moving,
		"scoped at 100 units a second, the AWP has its whole scoped running cone")


func _test_the_scoped_speed() -> void:
	var awp := _ready_weapon("weapon_awp")
	_check_near(awp.max_speed(), 200.0, "the AWP unscoped lets you run at 200")
	awp.press_zoom(T0)
	_check_near(awp.max_speed(), 100.0, "scoped, at 100 from the press")


func _test_a_sniper_comes_out_for_its_shot() -> void:
	var awp := _ready_weapon("weapon_awp")
	var state := Weapon.ShooterState.new()
	awp.press_zoom(T0)
	awp.update(DT, T0 + SECOND, state)
	var shot := awp.fire(T0 + SECOND, 0.0, Vector3.ZERO, 0.0, 0.0, state)
	_check(shot != null and shot.zoom_level == 1 and not shot.noscope, "a scoped AWP round goes out scoped")
	_check(awp.zoom_level == 0 and awp.rezoom_pending(), "and the AWP comes out of the scope with it")
	var cycle := int(round(awp.data.cycle_time * SECOND))
	awp.update(DT, T0 + SECOND + cycle - 10_000, state)
	_check_equal(awp.zoom_level, 0, "out while the bolt is worked")
	awp.update(DT, T0 + SECOND + cycle + 10_000, state)
	_check_equal(awp.zoom_level, 1, "and back to the level it was at once it may fire again (cl_sniper_auto_rezoom)")
	_check_near(awp.zoom_fov_at(T0 + SECOND + cycle), 90.0, "easing in again from 90")

	var twice := _ready_weapon("weapon_awp")
	twice.press_zoom(T0)
	twice.press_zoom(T0 + 1)
	twice.update(DT, T0 + SECOND, state)
	twice.fire(T0 + SECOND, 0.0, Vector3.ZERO, 0.0, 0.0, state)
	twice.update(DT, T0 + 3 * SECOND, state)
	_check_equal(twice.zoom_level, 2, "from the second level, back to the second")

	var pressed := _ready_weapon("weapon_awp")
	pressed.press_zoom(T0)
	pressed.update(DT, T0 + SECOND, state)
	pressed.fire(T0 + SECOND, 0.0, Vector3.ZERO, 0.0, 0.0, state)
	pressed.press_zoom(T0 + SECOND + 100_000)
	pressed.update(DT, T0 + 3 * SECOND, state)
	_check_equal(pressed.zoom_level, 1, "a right click while the bolt is worked takes over from the rezoom")

	var last := _ready_weapon("weapon_awp")
	last.ammo = 1
	last.press_zoom(T0)
	last.update(DT, T0 + SECOND, state)
	last.fire(T0 + SECOND, 0.0, Vector3.ZERO, 0.0, 0.0, state)
	last.update(DT, T0 + 3 * SECOND, state)
	_check_equal(last.zoom_level, 0, "with the magazine empty it stays out")

	var scar := _ready_weapon("weapon_scar20")
	scar.press_zoom(T0)
	scar.update(DT, T0 + SECOND, state)
	scar.fire(T0 + SECOND, 0.0, Vector3.ZERO, 0.0, 0.0, state)
	_check_equal(scar.zoom_level, 1, "the SCAR-20 stays scoped as it fires")


func _test_a_reload_or_a_switch_takes_the_scope_down() -> void:
	var awp := _ready_weapon("weapon_awp")
	awp.ammo = 2
	awp.press_zoom(T0)
	_check(awp.start_reload(T0 + SECOND) and awp.zoom_level == 0, "a reload takes the scope down")
	awp.finish_reload_if_due(T0 + 10 * SECOND)
	awp.update(DT, T0 + 10 * SECOND, Weapon.ShooterState.new())
	_check_equal(awp.zoom_level, 0, "and it stays down")

	var put_away := _ready_weapon("weapon_awp")
	put_away.press_zoom(T0)
	put_away.holster()
	_check(put_away.zoom_level == 0 and is_equal_approx(put_away.zoom_fov_at(T0 + 1), 90.0), "put away, it is out of the scope at once")
	put_away.press_zoom(T0 + SECOND)
	put_away.draw(T0 + 2 * SECOND, 1.0)
	_check_equal(put_away.zoom_level, 0, "and drawn, it comes out unscoped")


func _test_noscope() -> void:
	var state := Weapon.ShooterState.new()
	var awp := _ready_weapon("weapon_awp")
	var shot := awp.fire(T0, 0.0, Vector3.ZERO, 0.0, 0.0, state)
	_check(shot.noscope and shot.zoom_level == 0, "an AWP round fired unscoped is a noscope")
	var ak := _ready_weapon("weapon_ak47")
	_check(not ak.fire(T0, 0.0, Vector3.ZERO, 0.0, 0.0, state).noscope, "an AK-47 round never is")


# --- Through commands --------------------------------------------------------------

## Right click through a command on the world's tick: the scope up, a
## weapon_zoom event, and running forward no faster than the scoped 100;
## then out, and back to 200.
func _test_a_player_scopes_with_right_click() -> void:
	var world := GameWorld.new()
	_world.add_child(world)
	world.set_physics_process(false)
	var player := Commanded.new()
	_new_player(Vector3(0.0, 0.0, 0.0), "CT", player)
	world.add_player(player)
	player.equip(WeaponLibrary.build("weapon_awp"))
	var zooms: Array[GameEvent] = []
	world.game.events.listen(&"weapon_zoom", func(event: GameEvent) -> void: zooms.append(event))
	# Through the draw.
	for i in SimClock.ticks_in(2.0):
		world.step()
	_check(player.weapon != null and player.weapon.data.item_class == "weapon_awp", "the player has the AWP in hand")

	player.tap = UserCmd.ATTACK2
	world.step()
	world.step()
	_check_equal(player.weapon.zoom_level, 1, "right click scopes it")
	_check(zooms.size() == 1 and zooms[0].fields["userid"] == player.userid, "and says so: weapon_zoom, with who")

	player.walks = true
	var fastest := 0.0
	for i in SimClock.ticks_in(1.5):
		world.step()
		fastest = maxf(fastest, Vector2(player.velocity.x, player.velocity.z).length())
	_check(fastest > 95.0 and fastest <= 100.5, "scoped, running forward tops out at the scoped 100 (%.1f)" % fastest)

	player.tap = UserCmd.ATTACK2
	world.step()
	player.tap = UserCmd.ATTACK2
	world.step()
	_check_equal(player.weapon.zoom_level, 0, "two more clicks, through the second level and out")
	fastest = 0.0
	for i in SimClock.ticks_in(1.5):
		world.step()
		fastest = maxf(fastest, Vector2(player.velocity.x, player.velocity.z).length())
	_check(fastest > 195.0 and fastest <= 200.5, "and it runs at 200 again (%.1f)" % fastest)
	player.queue_free()
	world.queue_free()
	await physics_frame


## A right click and a round in the one tick go in the order they came: a
## round fired before the click that takes the scope down went out through
## it, and one fired before the click that puts it up went out without.
func _test_a_click_and_a_round_in_one_tick() -> void:
	var world := GameWorld.new()
	_world.add_child(world)
	world.set_physics_process(false)
	var player := Commanded.new()
	_new_player(Vector3(0.0, 0.0, 0.0), "CT", player)
	world.add_player(player)
	player.equip(WeaponLibrary.build("weapon_awp"))
	var shots: Array[Weapon.Shot] = []
	player.shot_traced.connect(func(shot: Weapon.Shot, _result: Hitscan.Result) -> void: shots.append(shot))
	for i in SimClock.ticks_in(2.0):
		world.step()
	# Up to the second level, and settled in it.
	for i in 2:
		player.tap = UserCmd.ATTACK2
		world.step()
	for i in SimClock.ticks_in(0.5):
		world.step()
	player.taps = [[UserCmd.ATTACK, 0.2], [UserCmd.ATTACK2, 0.7]]
	world.step()
	var scoped := shots.size() == 1 and shots[0].zoom_level == 2 and not shots[0].noscope
	# Out of the scope, and the bolt worked.
	for i in 3:
		if player.weapon.zoom_level != 0:
			player.tap = UserCmd.ATTACK2
			world.step()
	for i in SimClock.ticks_in(2.0):
		world.step()
	var level_before := player.weapon.zoom_level
	player.taps = [[UserCmd.ATTACK, 0.2], [UserCmd.ATTACK2, 0.7]]
	world.step()
	var unscoped := level_before == 0 and shots.size() == 2 and shots[1].zoom_level == 0 and shots[1].noscope
	_check(
		scoped and unscoped,
		"a round fired a moment before the click that takes the scope down goes out scoped, one before the click that puts it up a noscope (%s)"
			% [shots.map(func(shot: Weapon.Shot) -> String: return "level %d%s" % [shot.zoom_level, ", noscope" if shot.noscope else ""])]
	)
	player.queue_free()
	world.queue_free()
	await physics_frame


## A bot with an AWP facing an enemy: it scopes before it fires, and every
## round it fires goes through the scope.
func _test_a_bot_fires_through_its_scope() -> void:
	var enemy := _new_player(Vector3(0.0, 0.0, -800.0), "T")
	var bot := (load("res://src/bots/bot.tscn") as PackedScene).instantiate() as Bot
	bot.team = "CT"
	bot.weapon_data = WeaponLibrary.build("weapon_awp")
	bot.position = Vector3(0.0, 0.0, -1600.0)
	bot.yaw_degrees = 180.0
	_world.add_child(bot)
	var world := GameWorld.new()
	_world.add_child(world)
	for player: PlayerSim in [enemy, bot]:
		world.add_player(player)
	var zooms: Array[GameEvent] = []
	world.game.events.listen(&"weapon_zoom", func(event: GameEvent) -> void: zooms.append(event))
	var shots: Array[Weapon.Shot] = []
	bot.shot_traced.connect(func(shot: Weapon.Shot, _result: Hitscan.Result) -> void: shots.append(shot))
	for i in SimClock.ticks_in(5.0):
		await physics_frame
		if not enemy.alive:
			break
	var scoped := not shots.is_empty()
	for shot in shots:
		scoped = scoped and shot.zoom_level == 1 and not shot.noscope
	_check(scoped, "a bot with an AWP fires, and every round through the scope (%d rounds)" % shots.size())
	_check(not zooms.is_empty() and zooms[0].fields["userid"] == bot.userid, "it scopes with right click, as you do (weapon_zoom)")
	_check(enemy.hit_target.health < 100.0 or not enemy.alive, "and its rounds land (health %.0f)" % enemy.hit_target.health)
	bot.queue_free()
	enemy.queue_free()
	world.queue_free()
	await physics_frame


# --- Helpers -----------------------------------------------------------------------

## A gun of the class, drawn long ago and ready to fire.
func _ready_weapon(weapon_class: String) -> Weapon:
	var weapon := Weapon.new(WeaponLibrary.build(weapon_class))
	weapon.trigger_held = false
	return weapon


func _build_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8192.0, 32.0, 8192.0)
	shape.shape = box
	shape.position = Vector3(0.0, -16.0, 0.0)
	floor_body.add_child(shape)
	_world.add_child(floor_body)


## A player in the simulation with nothing drawing it, standing on the floor.
func _new_player(at: Vector3, team: String, player: PlayerSim = null) -> PlayerSim:
	if player == null:
		player = PlayerSim.new()
	player.team = team
	player.collision_layer = 2
	var hull := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(32.0, 72.0, 32.0)
	hull.shape = box
	hull.position = Vector3(0.0, 36.0, 0.0)
	player.add_child(hull)
	player.position = at
	_world.add_child(player)
	player.place(at, 0.0)
	for i in 4:
		var settle := UserCmd.new()
		settle.tick = 1 + i
		player.run_command(settle, DT)
	return player
