extends "res://tests/check_suite.gd"

## Checks CS2's grenades: the game's numbers read the way its file gives
## them, the throw at each strength, the flight (an arc, bounces, lying
## still, the same every time), the smoke's cloud (filling round walls and
## through doors, blocking sight, holes that fill back in), the fire's
## spread, the flash's blinding and the decoy's bursts, each on a
## grey-box floor and walls built here.
##
##   godot --headless --path . --script tests/run_grenade_checks.gd

var _world: Node3D
var _space: PhysicsDirectSpaceState3D
var _walls: Array[Node] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_the_numbers()
	_test_the_throw()

	_world = Node3D.new()
	root.add_child(_world)
	_box(Vector3(4096.0, 32.0, 4096.0), Vector3(0.0, -16.0, 0.0))
	await _settle()
	_space = _world.get_world_3d().direct_space_state

	_test_flight()
	await _test_a_wall()
	_test_the_smoke()
	await _test_smoke_and_walls()
	_test_the_fire()
	await _test_fire_and_walls()
	await _test_the_flash()
	_test_the_decoy()
	_world.queue_free()
	await _settle()
	await _test_the_range()
	_finish("grenade")


# --- The numbers ----------------------------------------------------------

func _test_the_numbers() -> void:
	_check_equal(GrenadeRules.ALL.size(), 6, "six grenades")
	for weapon_class in GrenadeRules.ALL:
		_check(WeaponVData.has(weapon_class), "the game's file has %s" % weapon_class)
		_check_near(GrenadeRules.throw_speed(weapon_class), 750.0, "%s is thrown at the game's 750" % weapon_class)
	_check_near(GrenadeRules.damage(GrenadeRules.HE), 99.0, "an HE does the game's 99 at the centre")
	_check_near(GrenadeRules.reach(GrenadeRules.HE), 350.0, "out to the game's 350")
	_check_near(GrenadeRules.he_damage_at(0.0), 99.0, "99 at the centre")
	var sigma := 350.0 / 3.0
	_check_near(GrenadeRules.he_damage_at(100.0), 99.0 * exp(-10000.0 / (2.0 * sigma * sigma)), "about 69 at 100 units")
	_check(GrenadeRules.he_damage_at(200.0) < GrenadeRules.he_damage_at(100.0), "less further out")
	_check_near(GrenadeRules.he_damage_at(350.0), 0.0, "nothing at the edge")
	var he := GrenadeRules.weapon_data(GrenadeRules.HE)
	_check_near(he.armor_penetration, 0.6, "armour lets 60% of an HE through (the game's ratio 1.2, halved)")
	_check_near(GrenadeRules.weapon_data(GrenadeRules.MOLOTOV).tagging_power, 0.0, "fire does not tag")
	_check_near(GrenadeRules.strength_for(true, false), 1.0, "left click throws hardest")
	_check_near(GrenadeRules.strength_for(false, true), 0.0, "right click lobs")
	_check_near(GrenadeRules.strength_for(true, true), 0.5, "both between")


func _test_the_throw() -> void:
	_check_near(GrenadeFlight.throw_speed(GrenadeRules.HE, 1.0), 675.0, "a left-click throw leaves the hand at 675 u/s")
	_check_near(GrenadeFlight.throw_speed(GrenadeRules.HE, 0.5), 438.75, "both buttons at 439")
	_check_near(GrenadeFlight.throw_speed(GrenadeRules.HE, 0.0), 202.5, "a lob at 203")


# --- Flight ---------------------------------------------------------------

func _throw(weapon_class: String, eye: Vector3, yaw: float, pitch: float, velocity := Vector3.ZERO, strength := 1.0) -> GrenadeFlight:
	return GrenadeFlight.throw_from(_space, weapon_class, eye, yaw, pitch, velocity, strength)


## Flies a grenade until it lies still or seconds run out; returns the
## ticks it took, or -1.
func _fly(flight: GrenadeFlight, seconds: float) -> int:
	var dt := SimClock.tick_seconds()
	for tick in SimClock.ticks_in(seconds):
		flight.step(_space, dt)
		if flight.at_rest:
			return tick + 1
	return -1


func _test_flight() -> void:
	var eye := Vector3(0.0, 64.0, 0.0)
	var level := _throw(GrenadeRules.HE, eye, 0.0, 0.0)
	var direction := level.velocity.normalized()
	_check_near(rad_to_deg(asin(direction.y)), 10.0, "a throw at the horizon goes ten degrees up")
	_check(level.position.z < -20.0 and level.position.y < 64.0 + GrenadeRules.RELEASE_AHEAD * sin(deg_to_rad(10.0)) + 0.01,
		"it leaves the hand ahead of the eyes (%s)" % level.position)
	var lob := _throw(GrenadeRules.HE, eye, 0.0, 0.0, Vector3.ZERO, 0.0)
	_check_near(lob.position.y, 52.0 + sin(deg_to_rad(10.0)) * GrenadeRules.RELEASE_AHEAD, "a lob leaves 12 units lower")
	var running := _throw(GrenadeRules.HE, eye, 0.0, 0.0, Vector3(0.0, 0.0, -250.0))
	_check_near(running.velocity.z - level.velocity.z, -312.5, "running adds 1.25 times your speed")
	var up := _throw(GrenadeRules.HE, eye, 0.0, 89.0)
	_check(rad_to_deg(asin(up.velocity.normalized().y)) > 88.9, "straight up is not lifted past it")

	var ticks := _fly(level, 20.0)
	_check(ticks > 0, "thrown flat, it comes to rest (%d ticks)" % ticks)
	_check_near(level.position.y, GrenadeRules.RADIUS, "on the floor")
	_check(level.bounces >= 2, "after bouncing (%d)" % level.bounces)
	_check(level.position.z < -600.0, "a long way off (%.0f units)" % -level.position.z)
	var again := _throw(GrenadeRules.HE, eye, 0.0, 0.0)
	_fly(again, 20.0)
	_check(again.position.is_equal_approx(level.position), "the same throw lands in the same place")

	# The first bounce: CS:GO's arc at 40% gravity. With no drag, it meets
	# the floor where the arc says it should.
	var arc := _throw(GrenadeRules.HE, eye, 0.0, -30.0)
	var start := arc.position
	var v := arc.velocity
	var g := GrenadeRules.SV_GRAVITY * GrenadeRules.GRAVITY_SCALE
	var height := start.y - GrenadeRules.RADIUS
	var t := (v.y + sqrt(v.y * v.y + 2.0 * g * height)) / g
	var expected_z := start.z + v.z * t
	var dt := SimClock.tick_seconds()
	while arc.bounces == 0:
		arc.step(_space, dt)
	_check(absf(arc.touches[0]["position"].z - expected_z) < 1.0, "it meets the floor where the arc says (%.1f, expected %.1f)" % [arc.touches[0]["position"].z, expected_z])
	var after: Vector3 = arc.velocity
	_check(after.y > 0.0, "and bounces up off it")
	var before_y := v.y - g * t
	_check(absf(after.y + before_y * GrenadeRules.ELASTICITY) < 12.0, "keeping 45%% of its speed into it (%.1f from %.1f)" % [after.y, before_y])


func _test_a_wall() -> void:
	var wall := _box(Vector3(512.0, 256.0, 16.0), Vector3(0.0, 128.0, -200.0))
	await _settle()
	var eye := Vector3(0.0, 64.0, 0.0)
	var flight := _throw(GrenadeRules.HE, eye, 0.0, 0.0)
	var dt := SimClock.tick_seconds()
	var touched_wall := false
	for tick in 64:
		flight.step(_space, dt)
		for touch in flight.touches:
			if (touch["normal"] as Vector3).z > 0.9:
				touched_wall = true
		if touched_wall:
			break
	_check(touched_wall, "thrown at a wall, it hits it")
	_check(flight.velocity.z > 0.0 and flight.velocity.z < 675.0 * 0.45 + 1.0, "and comes back off it slower (%.0f u/s)" % flight.velocity.z)
	_fly(flight, 20.0)
	_check(flight.at_rest and flight.position.z > -200.0, "on its own side of the wall (%.0f)" % flight.position.z)
	_remove(wall)
	await _settle()


# --- Smoke ----------------------------------------------------------------

func _fill(cloud: SmokeVoxels) -> int:
	var ticks := 0
	while not cloud.full() and ticks < 1000:
		cloud.grow(_space, SmokeVoxels.per_tick())
		ticks += 1
	return ticks


func _test_the_smoke() -> void:
	var rest := Vector3(0.0, GrenadeRules.RADIUS, 0.0)
	var cloud := SmokeVoxels.new(rest, 7)
	var ticks := _fill(cloud)
	_check_equal(cloud.filled.size(), GrenadeRules.SMOKE_VOXELS, "in the open, it fills its %d cubes" % GrenadeRules.SMOKE_VOXELS)
	_check(ticks <= SimClock.ticks_in(GrenadeRules.SMOKE_BLOOM_SECONDS) + 1, "over the bloom (%d ticks)" % ticks)
	print("  the fill made %d traces, %.0f a tick while it blooms" % [cloud.traces, float(cloud.traces) / ticks])
	_check(float(cloud.traces) / ticks < 300.0, "at under 300 traces a tick while it blooms")
	_check(cloud.bounds.position.y >= -0.01, "none of it under the floor")
	var size := cloud.bounds.size
	_check(size.x > size.y and size.z > size.y, "wider than it is tall, a dome (%s)" % size)
	print("  the cloud: %.0f across, %.0f tall" % [size.x, size.y])
	_check(size.x > 240.0 and size.x < 360.0, "about 300 units across (%.0f)" % size.x)
	var same := SmokeVoxels.new(rest, 7)
	_fill(same)
	_check(same.filled.keys() == cloud.filled.keys(), "the same seed fills the same cloud")
	var other := SmokeVoxels.new(rest, 8)
	_fill(other)
	_check(other.filled.keys() != cloud.filled.keys(), "another seed a slightly different one")

	var through := cloud.length_through(Vector3(-400.0, 40.0, 0.0), Vector3(400.0, 40.0, 0.0), 0)
	_check(through > GrenadeRules.BOT_MAX_VISIBLE_SMOKE_LENGTH, "a line through the middle is in smoke for %.0f units, more than a bot sees through" % through)
	_check_near(cloud.length_through(Vector3(-400.0, 400.0, 0.0), Vector3(400.0, 400.0, 0.0), 0), 0.0, "a line over it is clear")
	_check(cloud.contains(Vector3(0.0, 40.0, 0.0), 0), "the middle is smoke")

	var usec := 1_000_000
	var hole := cloud.clear_sphere(Vector3(0.0, 40.0, 0.0), GrenadeRules.HE_SMOKE_CLEAR_RADIUS, usec + 3_000_000)
	_check(hole > 100 and not cloud.contains(Vector3(0.0, 40.0, 0.0), usec), "an HE clears a hole in it (%d cubes)" % hole)
	_check(cloud.length_through(Vector3(-400.0, 40.0, 0.0), Vector3(400.0, 40.0, 0.0), usec) < through, "thinner to see through")
	_check(cloud.contains(Vector3(0.0, 40.0, 0.0), usec + 3_000_000), "that fills back in")
	var later := usec + 4_000_000
	var tunnel := cloud.clear_line(Vector3(-400.0, 40.0, 0.0), Vector3(400.0, 40.0, 0.0), later + 250_000)
	_check(tunnel > 10 and not cloud.contains(Vector3(0.0, 40.0, 0.0), later), "a round cuts a tunnel (%d cubes)" % tunnel)
	_check(cloud.contains(Vector3(0.0, 40.0, 0.0), later + 250_000), "that closes a quarter of a second later")


func _test_smoke_and_walls() -> void:
	# A wall across, with a door in it 64 wide: the smoke lands on one side.
	var left := _box(Vector3(1000.0, 256.0, 16.0), Vector3(-532.0, 128.0, -64.0))
	var right := _box(Vector3(1000.0, 256.0, 16.0), Vector3(532.0, 128.0, -64.0))
	await _settle()
	var cloud := SmokeVoxels.new(Vector3(100.0, GrenadeRules.RADIUS, 0.0), 3)
	_fill(cloud)
	var beyond_door := 0
	var beyond_wall := 0
	for key: Vector3i in cloud.filled:
		var centre := cloud.centre_of(key)
		if centre.z < -72.0:
			if absf(centre.x) < 128.0:
				beyond_door += 1
			elif centre.x > 160.0:
				beyond_wall += 1
	_check(beyond_door > 0, "it flows through the door (%d cubes past it)" % beyond_door)
	_check(beyond_wall == 0 or beyond_wall < beyond_door, "not through the wall (%d straight behind it)" % beyond_wall)
	var sealed := _box(Vector3(64.0, 256.0, 16.0), Vector3(0.0, 128.0, -64.0))
	await _settle()
	var shut := SmokeVoxels.new(Vector3(100.0, GrenadeRules.RADIUS, 0.0), 3)
	_fill(shut)
	var past := 0
	for key: Vector3i in shut.filled:
		if shut.centre_of(key).z < -72.0:
			past += 1
	_check_equal(past, 0, "with the door shut none of it gets past")
	_remove(left)
	_remove(right)
	_remove(sealed)
	await _settle()


# --- Fire -----------------------------------------------------------------

func _burn(fire: FireSpread, seconds: float, might := Callable()) -> void:
	var dt_usec := SimClock.tick_usec()
	var now := fire.started_usec
	for tick in SimClock.ticks_in(seconds):
		now += dt_usec
		fire.spread(_space, now, might)


func _test_the_fire() -> void:
	var molotov := FireSpread.new(GrenadeRules.MOLOTOV, Vector3.ZERO, 0, 11)
	_burn(molotov, 5.0)
	_check_equal(molotov.flames.size(), GrenadeRules.FIRE_MOST_FLAMES, "a molotov spreads to 16 flames")
	var furthest := 0.0
	var closest := INF
	for flame in molotov.flames:
		furthest = maxf(furthest, Vector2(flame.x, flame.z).length())
		for other in molotov.flames:
			if other != flame:
				closest = minf(closest, flame.distance_to(other))
	_check(furthest <= 150.0, "no further than 150 units (%.0f)" % furthest)
	_check(closest >= GrenadeRules.FIRE_SPACING * 0.75, "the flames spaced out (%.0f apart at the closest)" % closest)
	_check(molotov.burns(Vector3(0.0, 0.0, 0.0)) and not molotov.burns(Vector3(400.0, 0.0, 0.0)), "it burns where it is and not away from it")
	_check(not molotov.burns(Vector3(0.0, 200.0, 0.0)), "nor high over it")
	_check(not molotov.out(6_900_000) and molotov.out(7_000_000), "and goes out after 7 s")

	var incendiary := FireSpread.new(GrenadeRules.INCENDIARY, Vector3.ZERO, 0, 11)
	_burn(incendiary, 0.5)
	var slow := FireSpread.new(GrenadeRules.MOLOTOV, Vector3.ZERO, 0, 11)
	_burn(slow, 0.5)
	_check(incendiary.flames.size() > slow.flames.size(), "an incendiary spreads faster (%d flames to %d in half a second)" % [incendiary.flames.size(), slow.flames.size()])
	_burn(incendiary, 5.0)
	var widest := 0.0
	for flame in incendiary.flames:
		widest = maxf(widest, Vector2(flame.x, flame.z).length())
	_check(widest <= 110.0, "and no further than 110 units (%.0f)" % widest)
	_check(incendiary.out(5_500_000) and not incendiary.out(5_400_000), "and is out after 5.5 s")

	var smoked := FireSpread.new(GrenadeRules.MOLOTOV, Vector3.ZERO, 0, 11)
	_burn(smoked, 5.0, func(point: Vector3) -> bool: return point.x < 0.0)
	var into_smoke := 0
	for flame in smoked.flames:
		if flame.x > 0.01:
			into_smoke += 1
	_check_equal(into_smoke, 0, "it does not spread into smoke")
	var gone := molotov.put_out(func(point: Vector3) -> bool: return point.x > 0.0)
	_check(gone > 0 and not molotov.extinguished, "smoke puts out the flames it covers (%d)" % gone)
	molotov.put_out(func(_point: Vector3) -> bool: return true)
	_check(molotov.extinguished and molotov.out(0), "and the fire, when it covers all of them")


func _test_fire_and_walls() -> void:
	var wall := _box(Vector3(512.0, 128.0, 16.0), Vector3(0.0, 64.0, -40.0))
	await _settle()
	var fire := FireSpread.new(GrenadeRules.MOLOTOV, Vector3.ZERO, 0, 5)
	_burn(fire, 5.0)
	var behind := 0
	for flame in fire.flames:
		if flame.z < -40.0:
			behind += 1
	_check_equal(behind, 0, "fire does not spread through a wall")
	_check(fire.flames.size() > 4, "but does along it (%d flames)" % fire.flames.size())
	_remove(wall)
	await _settle()


# --- The flash ------------------------------------------------------------

func _test_the_flash() -> void:
	var eyes := Vector3(0.0, 64.0, 0.0)
	var ahead := Vector3(0.0, 64.0, -200.0)
	var facing := FlashBlind.from(_space, ahead, eyes, Vector3.FORWARD, 0)
	_check(facing != null and is_equal_approx(facing.duration, GrenadeRules.FLASH_MAX_SECONDS) and facing.peak == 1.0,
		"a flash close in front blinds for the longest, all white")
	_check_near(facing.amount(1_000_000), 1.0, "held white")
	_check(facing.amount(4_000_000) < 0.5 and facing.amount(4_000_000) > 0.0, "fading at the end")
	_check_near(facing.amount(5_000_000), 0.0, "and gone after")
	var behind := FlashBlind.from(_space, ahead, eyes, Vector3.BACK, 0)
	_check(behind != null and behind.duration < facing.duration * 0.3 and behind.peak < 1.0,
		"with your back to it, a short grey (%.2f s)" % (behind.duration if behind != null else 0.0))
	var side := FlashBlind.from(_space, ahead, eyes, Vector3.RIGHT, 0)
	_check(side.duration > behind.duration and side.duration < facing.duration, "side-on between (%.2f s)" % side.duration)
	var far := FlashBlind.from(_space, Vector3(0.0, 64.0, -1500.0), eyes, Vector3.FORWARD, 0)
	_check(far.duration < facing.duration * 0.5, "far off, less (%.2f s)" % far.duration)
	_check(FlashBlind.from(_space, Vector3(0.0, 64.0, -2100.0), eyes, Vector3.FORWARD, 0) == null, "too far, nothing")
	var wall := _box(Vector3(512.0, 256.0, 16.0), Vector3(0.0, 128.0, -100.0))
	await _settle()
	_check(FlashBlind.from(_space, ahead, eyes, Vector3.FORWARD, 0) == null, "not through a wall")
	_remove(wall)
	await _settle()
	_check(not facing.outlasts(facing) and facing.outlasts(behind), "a longer blind wins over a shorter")


# --- The decoy ------------------------------------------------------------

func _test_the_decoy() -> void:
	var decoy := DecoyBursts.new(0, 21, 0.1)
	var rounds := PackedInt64Array()
	var now := 0
	for tick in SimClock.ticks_in(20.0):
		now += SimClock.tick_usec()
		rounds.append_array(decoy.due(now))
	_check(rounds.size() > 10, "a decoy fires in bursts (%d rounds)" % rounds.size())
	_check(rounds[rounds.size() - 1] < 15_000_000, "for 15 s")
	var burst := 1
	var longest := 1
	for i in range(1, rounds.size()):
		if rounds[i] - rounds[i - 1] == 100_000:
			burst += 1
			longest = maxi(longest, burst)
		else:
			_check(rounds[i] - rounds[i - 1] >= 500_000, "a pause of at least half a second between bursts")
			burst = 1
	_check(longest >= 2 and longest <= GrenadeRules.DECOY_BURST_MOST, "bursts of up to five at the gun's rate (%d at most)" % longest)
	var again := DecoyBursts.new(0, 21, 0.1)
	_check(again.due(15_000_000) == rounds, "the same seed, the same bursts")


# --- On the range, through the shared contracts ---------------------------

const RANGE_SCENE := "res://maps/test_range/test_range.tscn"

var _range: Node3D
var _lane: GrenadeLane
var _events: Array[GameEvent] = []


func _test_the_range() -> void:
	_range = (load(RANGE_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_range)
	for i in 8:
		await physics_frame
	_lane = _range.grenades
	_check(_lane != null and _lane.system != null, "the range has its grenades")
	var game := _lane.game
	game.events.listen_all(func(event: GameEvent) -> void: _events.append(event))
	var you: int = game.roster.userid_of(_range.player)
	var dummy: int = game.roster.userid_of(_range.dummy)
	_check(you != GameEvents.NOBODY and dummy != GameEvents.NOBODY, "you and the dummy are in its roster")

	_check_equal(_lane.kind(), GrenadeRules.HE, "an HE in hand to begin with")
	_lane.next_kind()
	_check_equal(_lane.kind(), GrenadeRules.FLASHBANG, "4 takes the flash next")
	_lane.kind_index = 0

	# A throw: on the next tick, from your eyes.
	_lane.ask_throw(1.0)
	await physics_frame
	await physics_frame
	var thrown := _named(&"grenade_thrown")
	_check(thrown.size() == 1 and int(thrown[0].fields["userid"]) == you and thrown[0].fields["weapon"] == GrenadeRules.HE,
		"Q throws an HE, as you")
	var grenades := game.entities.of_class("hegrenade_projectile")
	_check_equal(grenades.size(), 1, "and it is in the world")
	for i in SimClock.ticks_in(1.6):
		await physics_frame
	_check_equal(_named(&"hegrenade_detonate").size(), 1, "it goes off 1.5 s later")
	_check(game.entities.of_class("hegrenade_projectile").is_empty(), "and is gone")
	_lane.clear()
	_events.clear()
	game.command(you, "throw weapon_ak47")
	await physics_frame
	await physics_frame
	_check(_named(&"grenade_thrown").is_empty(), "the throw command takes only a grenade")

	# An HE at the dummy's feet: it is hurt, by you, through its armour.
	var target := _range.dummy.hit_target as HitTarget
	target.reset()
	var feet: Vector3 = _range.dummy.global_position
	await _set_off(GrenadeRules.HE, feet + Vector3(0.0, GrenadeRules.RADIUS, 40.0))
	var hurt := _hurt_of(dummy)
	_check(hurt.size() == 1 and int(hurt[0].fields["attacker"]) == you and hurt[0].fields["weapon"] == GrenadeRules.HE,
		"an HE beside the dummy hurts it, credited to you")
	if hurt.size() == 1:
		var dealt := int(hurt[0].fields["dmg_health"])
		_check(dealt > 30 and dealt <= roundi(GrenadeRules.damage(GrenadeRules.HE) * 0.6) and int(hurt[0].fields["dmg_armor"]) > 0,
			"through its kevlar: %d to health, %d to armour" % [dealt, int(hurt[0].fields["dmg_armor"])])
		_check_equal(int(hurt[0].fields["hitgroup"]), DamageInfo.HITGROUP_GENERIC, "hit group generic, as a blast is")
	_lane.clear()
	_events.clear()

	# Behind the range's wall it is safe.
	target.reset()
	var dummy_before := target.health
	var wall_z: float = -512.0
	await _set_off(GrenadeRules.HE, Vector3(0.0, GrenadeRules.RADIUS, wall_z - 40.0))
	_check(_hurt_of(you).is_empty(), "an HE behind the wall does not reach you")
	_check_near(target.health, dummy_before, "nor the dummy, too far off")
	_lane.clear()
	_events.clear()

	# A flash in your face whites you out; the one who threw it is you.
	var eyes: Vector3 = _range.player.global_position + Vector3.UP * _range.player.eye_height()
	var forward := PlayerInput.aim_direction(_range.player.yaw_degrees, _range.player.pitch_degrees)
	await _set_off(GrenadeRules.FLASHBANG, eyes + forward * 150.0)
	var blinded := _named(&"player_blind")
	var yours: Array[GameEvent] = []
	for event in blinded:
		if int(event.fields["userid"]) == you:
			yours.append(event)
	_check(yours.size() == 1 and float(yours[0].fields["blind_duration"]) > 4.0, "a flash in your face blinds you for the longest")
	_check(float(game.query(&"blind_share", [you], 0.0)) > 0.99, "all white (the blind_share query)")
	_check(not (game.query(&"blindness", [you], {}) as Dictionary).is_empty(), "the blindness query says for how long")
	_lane.clear()
	_check_near(float(game.query(&"blind_share", [you], 0.0)), 0.0, "O clears it")
	_events.clear()

	# A smoke between you and the dummy hides it.
	var dummy_eyes: Vector3 = _range.dummy.global_position + Vector3.UP * 64.0
	var from_spot := Vector3(_range.dummy.global_position.x, 64.0, 0.0)
	var halfway := from_spot.lerp(dummy_eyes, 0.5)
	await _set_off(GrenadeRules.SMOKE, Vector3(halfway.x, GrenadeRules.RADIUS, halfway.z))
	_check_equal(_named(&"smokegrenade_detonate").size(), 1, "a smoke pops once it is still")
	for i in SimClock.ticks_in(GrenadeRules.SMOKE_BLOOM_SECONDS) + 2:
		await physics_frame
	var through := float(game.query(&"smoke_length_between", [from_spot, dummy_eyes], 0.0))
	_check(through > GrenadeRules.BOT_MAX_VISIBLE_SMOKE_LENGTH, "and hides the dummy from its firing spot (%.0f units of smoke)" % through)

	# A molotov into it fizzles.
	await _set_off(GrenadeRules.MOLOTOV, Vector3(halfway.x, GrenadeRules.RADIUS, halfway.z))
	_check_equal(_named(&"molotov_detonate").size(), 1, "a molotov into the smoke breaks")
	_check(game.entities.of_class(InfernoEntity.ENTITY_CLASS).is_empty(), "and no fire starts")
	_lane.clear()
	_events.clear()

	# A molotov under the dummy burns it, credited to you, armour or not.
	target.reset()
	await _set_off(GrenadeRules.MOLOTOV, feet + Vector3(0.0, GrenadeRules.RADIUS, 0.0))
	_check_equal(_named(&"inferno_startburn").size(), 1, "a molotov at the dummy's feet catches")
	for i in SimClock.ticks_in(1.5):
		await physics_frame
	var burns := _hurt_of(dummy)
	var total := 0
	for event in burns:
		total += int(event.fields["dmg_health"])
	_check(burns.size() >= 5 and int(burns[0].fields["attacker"]) == you and burns[0].fields["weapon"] == GrenadeRules.MOLOTOV,
		"and burns it in steps, credited to you (%d steps)" % burns.size())
	_check(bool(game.query(&"burning_at", [feet + Vector3.UP], false)), "the burning_at query says the dummy stands in fire")
	_check(not bool(game.query(&"burning_at", [feet + Vector3(0.0, 1.0, 600.0)], false)), "and nowhere near it does not")
	_check(total > 30 and total < 60, "about 40 a second, ramping up (%d in 1.5 s)" % total)
	_check(burns.size() > 0 and int(burns[0].fields["dmg_armor"]) == 0, "armour takes none of it")
	# A smoke on it puts it out.
	await _set_off(GrenadeRules.SMOKE, feet + Vector3(20.0, GrenadeRules.RADIUS, 0.0))
	for i in 3:
		await physics_frame
	_check_equal(_named(&"inferno_extinguish").size(), 1, "a smoke on it puts it out")
	_check(game.entities.of_class(InfernoEntity.ENTITY_CLASS).is_empty(), "and the fire is gone")
	_lane.clear()
	_events.clear()

	# A decoy fires in bursts.
	await _set_off(GrenadeRules.DECOY, Vector3(-200.0, GrenadeRules.RADIUS, -100.0))
	for i in SimClock.ticks_in(3.0):
		await physics_frame
	_check_equal(_named(&"decoy_started").size(), 1, "a decoy starts once it is still")
	_check(_named(&"decoy_firing").size() >= 2, "and fires (%d rounds in 3 s)" % _named(&"decoy_firing").size())
	_lane.clear()
	await physics_frame
	_check(game.entities.all().is_empty(), "O clears every grenade")
	_range.queue_free()
	await _settle()


## Puts a grenade of a kind, yours, lying still at a point, due to go off,
## and runs a tick or two for it to.
func _set_off(weapon_class: String, at: Vector3) -> void:
	var game := _lane.game
	var you: int = game.roster.userid_of(_range.player)
	var space := _range.get_world_3d().direct_space_state
	var grenade := _lane.system.throw_from(you, weapon_class, at, 0.0, -89.0, Vector3.ZERO, 0.0, space)
	grenade.flight.position = at
	grenade.flight.velocity = Vector3.ZERO
	grenade.flight.at_rest = weapon_class in [GrenadeRules.SMOKE, GrenadeRules.DECOY]
	if GrenadeRules.is_fire(weapon_class):
		grenade.flight.at_rest = false
		grenade.flight.velocity = Vector3.DOWN * 200.0
	grenade.position = at
	# Two seconds out of the hand, all but a tick: past the fuse, and a
	# still smoke's or decoy's check falls on the next tick.
	grenade.thrown_usec = SimClock.now_usec() - 2_000_000 + SimClock.tick_usec()
	for i in 4:
		await physics_frame


func _named(name: StringName) -> Array[GameEvent]:
	var out: Array[GameEvent] = []
	for event in _events:
		if event.name == name:
			out.append(event)
	return out


func _hurt_of(userid: int) -> Array[GameEvent]:
	var out: Array[GameEvent] = []
	for event in _named(&"player_hurt"):
		if int(event.fields["userid"]) == userid:
			out.append(event)
	return out


# --- Building the stand-ins -----------------------------------------------

func _box(size: Vector3, centre: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = centre
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_world.add_child(body)
	_walls.append(body)
	return body


func _remove(node: Node) -> void:
	_walls.erase(node)
	node.queue_free()


func _settle() -> void:
	for i in 3:
		await physics_frame
