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

	func command_for(tick: int, dt: float) -> UserCmd:
		var cmd := super.command_for(tick, dt)
		cmd.buttons = held
		return cmd


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_the_shotguns_have_cs2s_numbers()
	_test_a_pull_puts_out_every_pellet()
	_test_the_pattern_is_the_same_every_shot()
	_test_a_rifle_still_fires_one_round()
	_test_a_pellet_keeps_the_pulls_scope()

	_world = Node3D.new()
	root.add_child(_world)
	_build_floor()
	await physics_frame
	await physics_frame
	await _test_every_pellet_does_its_damage()
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
	player.queue_free()
	victim.queue_free()
	world.queue_free()
	await physics_frame


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
