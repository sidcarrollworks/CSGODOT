extends "res://tests/check_suite.gd"

## Shotguns (weapons TODO R5): every pellet of a trigger pull traced and
## damaged on its own, with CS2's numbers for the Nova, XM1014, Sawed-Off
## and MAG-7 (reference/weapons/vdata.csv, reference/research/combat.md),
## and the pellets in a fixed pattern the gun's spread wide.

var DT := SimClock.tick_seconds()

## CS2's figures for each shotgun: pellets, damage a pellet, range, range
## modifier, spread (the game's tangent) and spread seed.
const SHOTGUNS := {
	"weapon_nova": [9, 26.0, 3000.0, 0.70, 0.04, 17514],
	"weapon_xm1014": [6, 20.0, 3000.0, 0.70, 0.038, 817955],
	"weapon_sawedoff": [8, 32.0, 1400.0, 0.45, 0.062, 9571223],
	"weapon_mag7": [8, 30.0, 1400.0, 0.45, 0.04, 19899236],
}

var _world: Node3D


class Commanded extends PlayerSim:
	var held := 0
	## A button pressed on the next tick only, part way through it.
	var tap := 0

	func command_for(tick: int, dt: float) -> UserCmd:
		var cmd := super.command_for(tick, dt)
		cmd.buttons = held
		if tap != 0:
			cmd.steps.append(UserCmd.SubtickStep.new(tap, true, 0.5, cmd.yaw_degrees, cmd.pitch_degrees))
			tap = 0
		return cmd


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_the_shotguns_have_cs2s_numbers()
	_test_a_pull_puts_out_every_pellet()
	_test_the_pattern_is_the_same_every_shot()
	_test_a_rifle_still_fires_one_round()
	_test_a_pellet_keeps_the_pulls_scope()
	_test_three_load_a_shell_at_a_time()
	_test_a_reload_puts_in_one_shell_a_loop()
	_test_a_shot_stops_the_reload()
	_test_the_clip_goes_round_its_loop_for_every_shell()

	_world = Node3D.new()
	root.add_child(_world)
	_build_floor()
	await physics_frame
	await physics_frame
	await _test_every_pellet_does_its_damage()
	await _test_a_player_s_shot_stops_the_reload()
	_finish("shotgun")


func _test_the_shotguns_have_cs2s_numbers() -> void:
	for weapon_class: String in SHOTGUNS:
		var want: Array = SHOTGUNS[weapon_class]
		var data := WeaponLibrary.build(weapon_class)
		_check(data != null, "%s is a gun" % weapon_class)
		if data == null:
			continue
		_check_equal(data.pellets, want[0], "%s fires %d pellets" % [weapon_class, want[0]])
		_check_near(data.base_damage, want[1], "%s does %d a pellet" % [weapon_class, want[1]])
		_check_near(data.max_range, want[2], "%s reaches %d units" % [weapon_class, want[2]])
		_check_near(data.range_modifier, want[3], "%s keeps %.2f of its damage every 500 units" % [weapon_class, want[3]])
		_check_near(data.spread, WeaponSheet.cone_degrees(float(want[4]) * 1000.0),
			"%s spreads its pellets %.2f degrees" % [weapon_class, data.spread])
		_check_equal(data.spread_seed, want[5], "%s's pattern comes from its spread seed" % weapon_class)
		_check(data.inaccuracy_standing >= data.spread and data.inaccuracy_crouching >= data.spread,
			"%s's standing and crouching cones take in the spread" % weapon_class)
	var ak := WeaponLibrary.build("weapon_ak47")
	_check(ak.pellets == 1 and ak.spread_seed == 0, "the AK-47 fires one round and has no pellet pattern")


func _test_a_pull_puts_out_every_pellet() -> void:
	for weapon_class: String in SHOTGUNS:
		var data := WeaponLibrary.build(weapon_class)
		var weapon := _loaded(data)
		var aim := PlayerInput.aim_direction(0.0, 0.0)
		var shot := weapon.fire(0, 0.0, Vector3.ZERO, 0.0, 0.0, Weapon.ShooterState.new())
		_check(shot != null, "%s fires" % weapon_class)
		if shot == null:
			continue
		_check_equal(shot.pellets(), data.pellets, "%s's pull puts out %d pellets" % [weapon_class, data.pellets])
		_check_equal(weapon.ammo, data.magazine_size - 1, "%s's pull takes one shell" % weapon_class)
		var widest := 0.0
		var apart := 0.0
		for i in shot.pellets():
			var pellet := shot.pellet_shot(i)
			_check(pellet.pellet == i and pellet.timestamp_usec == shot.timestamp_usec and pellet.origin == shot.origin,
				"%s's pellet %d is the same pull's" % [weapon_class, i])
			widest = maxf(widest, rad_to_deg(aim.angle_to(pellet.direction)))
			if i > 0:
				apart = maxf(apart, rad_to_deg(shot.direction.angle_to(pellet.direction)))
		_check(widest <= data.inaccuracy_standing + 0.001,
			"%s's pellets all land inside its %.2f degree standing cone (widest %.2f)" % [weapon_class, data.inaccuracy_standing, widest])
		_check(apart > data.spread * 0.2,
			"%s's pellets spread out rather than go one way (%.2f degrees apart at most)" % [weapon_class, apart])
		_check(shot.pellet_shot(0) == shot, "%s's first pellet is the shot itself" % weapon_class)


## A pellet is the pull's in everything but where it goes, the scope too
## (the scopes, weapons TODO R4): each pellet's hurt and death carry the
## zoom level and noscope of the pull that fired it.
func _test_a_pellet_keeps_the_pulls_scope() -> void:
	var shot := Weapon.Shot.new()
	shot.direction = Vector3.FORWARD
	shot.pellet_directions = PackedVector3Array([Vector3.FORWARD, Vector3(0.1, 0.0, -1.0).normalized()])
	shot.zoom_level = 1
	var pellet := shot.pellet_shot(1)
	_check(pellet.zoom_level == 1 and not pellet.noscope, "a pellet of a scoped pull is scoped")
	shot.zoom_level = 0
	shot.noscope = true
	pellet = shot.pellet_shot(1)
	_check(pellet.zoom_level == 0 and pellet.noscope, "and a pellet of a noscope pull is a noscope")


## Held still with nothing but the spread in the cone, every shot lands the
## same pattern; the rest of the cone throws the pattern whole, so the
## pellets keep their places towards each other.
func _test_the_pattern_is_the_same_every_shot() -> void:
	var data := WeaponLibrary.build("weapon_nova")
	data.inaccuracy_standing = data.spread
	data.inaccuracy_per_shot = 0.0
	var weapon := _loaded(data)
	var still := Weapon.ShooterState.new()
	var first := weapon.fire(0, 0.0, Vector3.ZERO, 0.0, 0.0, still)
	var later := int(data.cycle_time * 3.0 * 1_000_000.0)
	weapon.update(data.cycle_time * 3.0, later, still)
	weapon.press_trigger()
	var second := weapon.fire(later, 0.0, Vector3.ZERO, 0.0, 0.0, still)
	var same := first != null and second != null
	if same:
		for i in first.pellets():
			same = same and first.pellet_directions[i].is_equal_approx(second.pellet_directions[i])
	_check(same, "with no inaccuracy past the spread, the Nova lands the same pattern every shot")

	# Running, the cone past the spread moves the pattern, and only moves it.
	var nova := WeaponLibrary.build("weapon_nova")
	var running := Weapon.ShooterState.new(nova.max_player_speed)
	var a := _loaded(nova).fire(0, 0.0, Vector3.ZERO, 0.0, 0.0, running)
	var b := _loaded(nova).fire(123_457, 0.0, Vector3.ZERO, 0.0, 0.0, running)
	_check(not a.direction.is_equal_approx(b.direction), "running, two Nova shots go different ways")
	var kept := true
	for i in range(1, a.pellets()):
		var there := rad_to_deg(a.direction.angle_to(a.pellet_directions[i]))
		var here := rad_to_deg(b.direction.angle_to(b.pellet_directions[i]))
		kept = kept and absf(there - here) < 0.01
	_check(kept, "and each pellet keeps its place in the pattern")


func _test_a_rifle_still_fires_one_round() -> void:
	var weapon := _loaded(WeaponLibrary.ak47())
	var shot := weapon.fire(0, 0.0, Vector3.ZERO, 0.0, 0.0, Weapon.ShooterState.new())
	_check(shot.pellets() == 1 and shot.pellet_shot(0) == shot and shot.pellet == 0,
		"the AK-47's pull is one round, the shot itself")
	var by_hand := Weapon.Shot.new()
	_check_equal(by_hand.pellets(), 1, "a shot built by hand is one round")


## A Nova fired from 100 units into another player's chest: one pull, one
## weapon_fire and so one report heard, and a trace, a bullet_impact and a hurt for every pellet
## that lands, the lot killing where one pellet's 26 would not. The player
## here is what a bot is too: both fire through PlayerSim._try_shoot.
func _test_every_pellet_does_its_damage() -> void:
	var player := Commanded.new()
	player.starting_gun = WeaponLibrary.build("weapon_nova")
	_new_player(Vector3(2048.0, 0.0, 2048.0), "T", player)
	player.respawn()
	var world := GameWorld.new()
	_world.add_child(world)
	world.set_physics_process(false)
	var events: Array[GameEvent] = []
	world.game.events.listen_all(func(event: GameEvent) -> void: events.append(event))
	world.add_player(player)
	var victim := _new_player(Vector3(2048.0, 0.0, 1948.0), "CT")
	world.add_player(victim)
	await physics_frame
	await physics_frame
	_check(player.weapon != null and player.weapon.data.item_class == "weapon_nova", "the player has the Nova in hand")

	var traced: Array[Weapon.Shot] = []
	player.shot_traced.connect(func(shot: Weapon.Shot, _result: Hitscan.Result) -> void: traced.append(shot))
	# What the shooter hears, from the pull's weapon_fire (WeaponSounds.watch).
	var sounds := WeaponSounds.new()
	player.add_child(sounds)
	sounds.set_process(false)
	sounds.watch(player)
	# At the chest: down from the eye to about the victim's middle.
	player.pitch_degrees = -rad_to_deg(atan2(player.eye_height() - 40.0, 100.0))
	var ready := int(roundf(ItemRegistry.item("weapon_nova").deploy_seconds * 1_000_000.0))
	player.held = UserCmd.ATTACK
	for i in SimClock.ticks_in(float(ready) / 1_000_000.0 + 0.1):
		world.step()
	player.held = 0
	world.step()

	_check_equal(traced.size(), 9, "one pull of the Nova traces nine pellets")
	_check(traced.all(func(shot: Weapon.Shot) -> bool: return shot.timestamp_usec == traced[0].timestamp_usec),
		"all nine at the one instant")
	_check_equal(_named(events, &"weapon_fire").size(), 1, "and sends one weapon_fire")
	_check(sounds.pending_shots() == PackedStringArray(["weapon_nova"]), "so the shooter hears one report, the Nova's (%s)" % [sounds.pending_shots()])
	var hurts := _named(events, &"player_hurt")
	var dealt := 0
	for event in hurts:
		dealt += int(event.fields.get("dmg_health", 0))
	_check(hurts.size() > 1, "more than one pellet hurts the victim (%d)" % hurts.size())
	# The victim wears kevlar, which takes half of each of the Nova's
	# pellets (armour ratio 1.0): 12 a pellet at this range, one pull
	# killing all the same.
	_check(not victim.alive and dealt >= 99,
		"point blank to the chest, the Nova's pellets together kill through kevlar (%d dealt in %d hits)" % [dealt, hurts.size()])
	_check(_named(events, &"bullet_impact").size() >= hurts.size(), "every pellet that lands is a bullet_impact")
	# Each pellet is a round of its own to whoever draws it: its fire_bullets,
	# numbered, then its own impacts, so each has its tracer (ShotEffects).
	var rounds := PackedInt32Array()
	var impacts_in_order := true
	for event in events:
		if event.name == &"fire_bullets":
			rounds.append(int(event.fields["pellet"]))
		elif event.name == &"bullet_impact" and rounds.is_empty():
			impacts_in_order = false
	var bullets := _named(events, &"fire_bullets")
	var ways := {}
	for event in bullets:
		ways["%.3f %.3f" % [event.fields["yaw"], event.fields["pitch"]]] = true
	_check(
		rounds == PackedInt32Array([0, 1, 2, 3, 4, 5, 6, 7, 8]) and impacts_in_order and ways.size() == 9,
		"and a fire_bullets for each pellet, numbered 0 to 8, each its own way and before its impacts (%s)" % [rounds]
	)
	player.queue_free()
	victim.queue_free()
	world.queue_free()
	await physics_frame


## CS2's m_bReloadsSingleShells, and each one's reload clip in its parts
## (reference/weapons/timings.csv): intro, a shell's loop, where in it the
## shell goes in, outro. The MAG-7 has a magazine.
const SHELL_BY_SHELL := {
	"weapon_nova": [0.3667, 0.4333, 0.3, 0.8333],
	"weapon_xm1014": [0.7, 0.6, 0.3333, 0.4333],
	"weapon_sawedoff": [0.4, 0.5333, 0.2667, 0.8],
}


func _test_three_load_a_shell_at_a_time() -> void:
	for weapon_class: String in SHOTGUNS:
		var data := WeaponLibrary.build(weapon_class)
		var shells := SHELL_BY_SHELL.has(weapon_class)
		_check(data.reloads_single_shells == shells,
			"%s %s" % [weapon_class, "loads a shell at a time" if shells else "has a magazine"])
		if not shells:
			continue
		var want: Array = SHELL_BY_SHELL[weapon_class]
		var got := [data.shell_intro, data.shell_loop, data.shell_in, data.shell_outro]
		var close := true
		for i in 4:
			close = close and absf(got[i] - want[i]) < 0.001
		_check(close, "%s's reload clip is %s: intro, loop, shell in, outro (got %s)" % [weapon_class, want, got])
		_check(is_equal_approx(data.shell_reload_seconds(1), want[0] + want[1] + want[3]),
			"%s's clip is the intro, one loop and the outro long" % weapon_class)
	_check(not WeaponLibrary.build("weapon_ak47").reloads_single_shells, "the AK-47 has a magazine")


## The Nova, three in the tube and the reserve full: five shells, the first
## 0.67 s in, then one every 0.43 s, and ready once the outro is over.
func _test_a_reload_puts_in_one_shell_a_loop() -> void:
	var data := WeaponLibrary.build("weapon_nova")
	var nova := Weapon.new(data)
	nova.ammo = 3
	var reserve := nova.reserve
	var t0 := 10 * 1_000_000
	_check(nova.start_reload(t0) and nova.shells_planned() == 5, "a reload of the Nova with three in sets out to load five")
	var first := t0 + _usec(data.shell_in_seconds(0))
	nova.finish_reload_if_due(first - 1)
	_check_equal(nova.ammo, 3, "no shell is in before the first loop's ADD_AMMO")
	nova.finish_reload_if_due(first)
	_check(nova.ammo == 4 and nova.reserve == reserve - 1, "the first shell goes in at %.2f s, out of the reserve" % data.shell_in_seconds(0))
	nova.finish_reload_if_due(t0 + _usec(data.shell_in_seconds(1)) - 1)
	_check_equal(nova.ammo, 4, "the second waits a loop")
	nova.finish_reload_if_due(t0 + _usec(data.shell_in_seconds(2)))
	_check_equal(nova.ammo, 6, "and a shell goes in every loop after (%.2f s)" % data.shell_loop)
	var done := t0 + _usec(data.shell_reload_seconds(5))
	nova.finish_reload_if_due(done - 1)
	_check(nova.ammo == 8 and nova.is_reloading(done - 1), "all five in, it is still reloading through the outro")
	_check(nova.finish_reload_if_due(done) and not nova.is_reloading(done), "and ready %.2f s after it started" % data.shell_reload_seconds(5))
	_check(nova.ammo == 8 and nova.reserve == reserve - 5, "eight in the tube, five out of the reserve")

	# Two left in the reserve: two shells, and done two loops in.
	var short := Weapon.new(data)
	short.ammo = 0
	short.reserve = 2
	short.start_reload(t0)
	_check_equal(short.shells_planned(), 2, "with two in reserve it loads two")
	var two := t0 + _usec(data.shell_reload_seconds(2))
	short.finish_reload_if_due(two)
	_check(short.ammo == 2 and short.reserve == 0 and not short.is_reloading(two), "and is ready after two loops")

	# Put away part way, it keeps the shells that went in.
	var away := Weapon.new(data)
	away.ammo = 0
	away.start_reload(t0)
	away.finish_reload_if_due(t0 + _usec(data.shell_in_seconds(1)))
	away.holster()
	_check(away.ammo == 2 and not away.is_reloading(t0 + _usec(data.shell_in_seconds(1))), "put away after two shells, it keeps the two")


## With a shell in, the trigger fires once the reload has run its
## m_flDisallowAttackAfterReloadStartDuration, and the shot stops it: the
## Nova's and Sawed-Off's 0.47 s, the XM1014's 0.6. An empty one waits for
## its first shell.
func _test_a_shot_stops_the_reload() -> void:
	var data := WeaponLibrary.build("weapon_nova")
	var t0 := 10 * 1_000_000
	var nova := Weapon.new(data)
	nova.ammo = 3
	nova.start_reload(t0)
	_check(not nova.can_fire(t0 + _usec(data.reload_time) - 1), "the Nova cannot fire in the first %.2f s of a reload" % data.reload_time)
	_check(nova.can_fire(t0 + _usec(data.reload_time)), "and can after, a shell in the tube")
	var at := t0 + _usec(data.shell_in_seconds(1)) + 1000
	_check(_fire(nova, at) != null, "a shot after two shells fires")
	_check(nova.ammo == 3 + 2 - 1 and not nova.is_reloading(at), "and stops the reload with the two in (%d in the tube)" % nova.ammo)
	nova.finish_reload_if_due(at + 10 * 1_000_000)
	_check_equal(nova.ammo, 4, "no more go in after it")

	var empty := Weapon.new(data)
	empty.ammo = 0
	empty.start_reload(t0)
	_check(not empty.can_fire(t0 + _usec(data.shell_in_seconds(0)) - 1000), "empty, it cannot fire before the first shell")
	var first := t0 + _usec(data.shell_in_seconds(0))
	_check(_fire(empty, first) != null and empty.ammo == 0 and not empty.is_reloading(first),
		"and fires the first the instant it is in, however the ticks fell, stopping the reload")

	var xm := Weapon.new(WeaponLibrary.build("weapon_xm1014"))
	xm.ammo = 5
	xm.start_reload(t0)
	_check(not xm.can_fire(t0 + 590_000) and xm.can_fire(t0 + 600_000), "the XM1014 holds off for its own 0.6 s")

	var mag7 := Weapon.new(WeaponLibrary.build("weapon_mag7"))
	mag7.ammo = 2
	mag7.start_reload(t0)
	_check(not mag7.can_fire(t0 + _usec(mag7.data.reload_time) - 1000), "the MAG-7 cannot fire through its magazine reload")


## The arms go round the reload clip's loop once for every shell, then
## through the outro; the loop's sounds are heard once a shell.
func _test_the_clip_goes_round_its_loop_for_every_shell() -> void:
	var data := WeaponLibrary.build("weapon_nova")
	var intro := data.shell_intro
	var loop := data.shell_loop
	_check_near(data.shell_clip_seconds(0.2, 3), 0.2, "in the intro the clip runs as it is")
	_check_near(data.shell_clip_seconds(intro + loop * 2.0 + 0.1, 3), intro + 0.1, "in the third shell's loop it is back at the loop's start")
	_check_near(data.shell_clip_seconds(intro + loop * 3.0 + 0.2, 3), intro + loop + 0.2, "after the last it runs into the outro")
	_check_near(data.shell_clip_seconds(99.0, 3), data.shell_reload_seconds(1), "and holds at the clip's end")

	var parts := [[0.0, PackedStringArray(["move"])], [intro + 0.01, PackedStringArray(["insert"])],
		[intro + 0.3, PackedStringArray(["add"])], [intro + loop + 0.3, PackedStringArray(["pump"])]]
	var heard := WeaponSounds.shell_parts(parts, 3, intro, loop)
	var names := PackedStringArray()
	var times := PackedFloat32Array()
	for part: Array in heard:
		names.append((part[1] as PackedStringArray)[0])
		times.append(part[0])
	_check(names == PackedStringArray(["move", "insert", "add", "insert", "add", "insert", "add", "pump"]),
		"three shells: the intro's sound once, the loop's three times, the outro's once (%s)" % [names])
	_check(absf(times[5] - (intro + 0.01 + loop * 2.0)) < 0.001 and absf(times[7] - (intro + loop * 3.0 + 0.3)) < 0.001,
		"each loop's a loop after the last, the outro's after the third (%s)" % [times])


## The same through PlayerSim: R, then the trigger part way through, heard
## and seen as the reload stopping.
func _test_a_player_s_shot_stops_the_reload() -> void:
	var player := Commanded.new()
	player.starting_gun = WeaponLibrary.build("weapon_nova")
	_new_player(Vector3(2048.0, 0.0, 2048.0), "T", player)
	player.respawn()
	var world := GameWorld.new()
	_world.add_child(world)
	world.set_physics_process(false)
	world.add_player(player)
	await physics_frame
	var nova := player.weapon
	var steps := func(seconds: float) -> void:
		for i in SimClock.ticks_in(seconds):
			world.step()
	steps.call(ItemRegistry.item("weapon_nova").deploy_seconds + 0.1)
	nova.ammo = 2
	var started := [0]
	var stopped := [0]
	player.reload_started.connect(func() -> void: started[0] += 1)
	player.reload_stopped.connect(func() -> void: stopped[0] += 1)
	player.tap = UserCmd.RELOAD
	world.step()
	steps.call(nova.data.shell_in_seconds(2) + 0.05)
	_check(started[0] == 1 and nova.ammo == 5 and nova.is_reloading(SimClock.now_usec()),
		"R starts the reload, and three loops in, three shells are in (%d)" % nova.ammo)
	player.tap = UserCmd.ATTACK
	world.step()
	world.step()
	_check(stopped[0] == 1 and nova.ammo == 4 and not nova.is_reloading(SimClock.now_usec()),
		"the trigger fires and stops the reload (%d in the tube)" % nova.ammo)
	steps.call(2.0)
	_check_equal(nova.ammo, 4, "and no more shells go in")
	player.queue_free()
	world.queue_free()
	await physics_frame


static func _usec(seconds: float) -> int:
	return int(seconds * 1_000_000.0)


func _fire(weapon: Weapon, at_usec: int) -> Weapon.Shot:
	return weapon.fire(at_usec, 0.0, Vector3.ZERO, 0.0, 0.0, Weapon.ShooterState.new())


func _loaded(data: WeaponData) -> Weapon:
	var weapon := Weapon.new(data)
	weapon.ammo = data.magazine_size
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


static func _named(events: Array[GameEvent], event_name: StringName) -> Array[GameEvent]:
	var out: Array[GameEvent] = []
	for event in events:
		if event.name == event_name:
			out.append(event)
	return out


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
