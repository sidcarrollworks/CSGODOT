extends "res://tests/check_suite.gd"

## Exercise the optional native backend through GameSystems, using the
## committed CS2 hulls. No extracted models are needed. Fresh clones without
## the addon skip; install it to run this suite before comparing physics.
##
## godot --headless --path . --script tests/run_box3d_drop_checks.gd

const METRES_PER_INCH := 0.0254
const SLOPE := 14.0
const GUNS := ["weapon_glock", "weapon_ak47", "weapon_awp"]
const THROWS := 4
const SETTLE_TICKS := 64 * 5
## Where the AWP's settling is tracked while its two checks are known open.
const AWP_SETTLING := "roadmap 12, Box3D: the AWP's settling, known open since 2026-09-28"


func _initialize() -> void:
	if not ClassDB.class_exists(&"Box3DWorld") or not ClassDB.class_exists(&"Box3DBody"):
		_skip("box3d-drops", "Box3D native addon is not installed; run scripts/install_box3d.ps1")
		return
	await physics_frame
	ItemPhysics.use_table(ItemPhysics.PATH)
	await _check_tick_and_units()
	_check_saved_flight()
	_check_restored_sleeping_pose()
	_check_landings(false)
	_check_landings(true)
	_check_cleanup()
	_finish("box3d-drops")


func _print_passes() -> bool:
	return true


func _check_tick_and_units() -> void:
	var test := _make_case()
	var velocity := Vector3(120.0, 250.0, -300.0)
	var spin := Vector3(2.0, 3.0, -4.0)
	var item := _drop(test, "weapon_ak47", Transform3D(Basis.IDENTITY, Vector3(0.0, 5000.0, 0.0)), velocity, spin)
	var native := test.adapter.body_for(item.id)
	_check(native != null, "spawning a dropped gun creates its native body immediately")
	if native == null:
		_close_case(test)
		return
	var from := item.position
	var before := native.global_transform
	var before_velocity: Vector3 = native.call(&"get_linear_velocity")
	for frame in 3:
		await physics_frame
		await process_frame
	_check(native.global_transform.is_equal_approx(before)
		and (native.call(&"get_linear_velocity") as Vector3).is_equal_approx(before_velocity)
		and test.adapter.steps == 0,
		"rendered and physics frames alone do not advance the native world")
	_check((before_velocity / METRES_PER_INCH).distance_to(velocity) < 0.001,
		"throw velocity crosses the inch/metre boundary once")
	for gun in GUNS:
		var mass_item := _drop(test, gun, Transform3D(Basis.IDENTITY, Vector3(1000.0, 5000.0, 1000.0)))
		var body := test.adapter.body_for(mass_item.id)
		var mass := float(body.call(&"get_mass")) if body != null else 0.0
		_check(absf(mass - mass_item.physics().mass) < 0.01,
			"%s keeps its extracted mass after hull scaling (%.4f kg)" % [gun, mass])
		mass_item.remove()
	var dt := SimClock.tick_seconds()
	for tick in 16:
		test.game.step(tick + 1, test.space())
	var time := 16.0 * dt
	var expected := from + velocity * time + Vector3.DOWN * 0.5 * 800.0 * time * time
	_check(test.adapter.steps == 16 and test.adapter.native_steps == 16 * Box3DDrops.COLLISION_STEPS,
		"sixteen game ticks each advance one interval with four native collision steps")
	_check(item.velocity.distance_to(velocity + Vector3.DOWN * 800.0 * time) < 0.02,
		"free flight applies 800 inches/s² of gravity at 64 Hz (velocity %s)" % item.velocity)
	_check(item.position.distance_to(expected) < 0.5,
		"the centre of mass follows the throw in Source inches (%.4f in from the parabola)" % item.position.distance_to(expected))
	_check(not item.basis.is_equal_approx(before.basis), "native angular velocity tumbles the gun during flight")
	_check((native.global_position / METRES_PER_INCH).distance_to(item.position) < 0.02,
		"the native pose and the simulation's drawn pose agree after each tick")
	_check_equal(item.queries, 0, "a native drop does not also run the legacy collision solver")
	_close_case(test)


func _check_saved_flight() -> void:
	var test := _make_case()
	var item := _drop(test, "weapon_ak47", Transform3D(Basis(Vector3.UP, 0.7), Vector3(30.0, 5000.0, 80.0)),
		Vector3(90.0, 110.0, -250.0), Vector3(1.0, 2.0, -3.0))
	item.entry.weapon.ammo = 7
	item.entry.weapon.reserve = 31
	for tick in 8:
		test.game.step(tick + 1, test.space())
	var copy := DroppedItem.new()
	copy.load_state(item.save_state())
	_check(copy.position == item.position and copy.basis == item.basis
		and copy.velocity == item.velocity and copy.angular_velocity == item.angular_velocity
		and copy.previous_position == item.previous_position and copy.previous_basis == item.previous_basis
		and copy.entry.weapon.ammo == 7 and copy.entry.weapon.reserve == 31,
		"saved state preserves the native drop's pose, velocities, interpolation history and ammunition")
	var restored := _make_case()
	restored.game.entities.spawn(copy)
	for tick in range(9, 25):
		test.game.step(tick, test.space())
		restored.game.step(tick, restored.space())
	_check(copy.position.distance_to(item.position) < 0.02
		and copy.velocity.distance_to(item.velocity) < 0.02
		and copy.basis.get_rotation_quaternion().angle_to(item.basis.get_rotation_quaternion()) < 0.002,
		"a restored moving drop continues from its saved pose and momentum")
	_close_case(test)
	_close_case(restored)


func _check_restored_sleeping_pose() -> void:
	var test := _make_case()
	var item := _drop(test, "weapon_glock", Transform3D(Basis.IDENTITY, Vector3(0.0, 30.0, 0.0)))
	for tick in 256:
		_step(test)
		if item.resting:
			break
	_check(item.resting, "the snapshot fixture reaches native sleep before restoring it")
	var view := DroppedItemView.new()
	test.host.add_child(view)
	view.set_process(false)
	view.watch(test.game)
	view._process(0.0)
	var model := view.model_of(item.id)
	_check(model != null, "a sleeping native gun has a drawn model, including without extracted assets")
	if model == null:
		_close_case(test)
		return
	var state := item.save_state()
	var destination := item.position + Vector3(200.0, 0.0, 0.0)
	state["position"] = destination
	state["previous_position"] = destination
	item.load_state(state)
	view._process(0.0)
	var drawn := DroppedItemView.drawn_frame(model, item.physics().bone)
	_check((drawn * item.physics().centre_of_mass).distance_to(destination) < 0.01,
		"restoring a sleeping gun at a new location refreshes its already-settled view")
	_step(test)
	var native := test.adapter.body_for(item.id)
	_check(item.resting and item.position.distance_to(destination) < 0.01
		and (native.global_position / METRES_PER_INCH).distance_to(destination) < 0.01,
		"restoring into an existing sleeping drop updates the native body as well as the entity")
	state = item.save_state()
	destination += Vector3.UP * 100.0
	var velocity := Vector3(-20.0, 100.0, 40.0)
	state["position"] = destination
	state["previous_position"] = destination
	state["velocity"] = velocity
	state["angular_velocity"] = Vector3(0.0, 2.0, 0.0)
	state["resting"] = false
	state["rested_usec"] = -1
	item.load_state(state)
	view._process(0.0)
	drawn = DroppedItemView.drawn_frame(model, item.physics().bone)
	_check((drawn * item.physics().centre_of_mass).distance_to(destination) < 0.01,
		"restoring an airborne snapshot restarts drawing a previously sleeping gun")
	_step(test)
	_check(not item.resting and item.position.distance_to(destination) > 0.1
		and item.velocity.distance_to(velocity + Vector3.DOWN * 800.0 * SimClock.tick_seconds()) < 0.02,
		"an existing native body resumes a loaded moving snapshot with its new momentum")
	_close_case(test)


## Check all corners throughout each fall, then a whole extra second after
## sleeping. A mere timeout flag must not hide a hovering or sinking gun.
func _check_landings(ramp: bool) -> void:
	var test := _make_case(ramp)
	var normal := Vector3(0.0, cos(deg_to_rad(SLOPE)), sin(deg_to_rad(SLOPE))) if ramp else Vector3.UP
	var label := "one-sided %d degree ramp" % SLOPE if ramp else "floor"
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for gun in GUNS:
		var worst_depth := INF
		var worst_gap := -INF
		var drift := 0.0
		var turn_drift := 0.0
		var rested := 0
		var slowest := 0.0
		for throw in THROWS:
			var turn := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.6, 0.3))
			var velocity := (turn * Vector3.BACK + Vector3.UP * ItemDrops.THROW_LIFT).normalized() * ItemDrops.THROW_SPEED
			var spin := turn.x * rng.randf_range(0.5, 1.0) * ItemDrops.THROW_TUMBLE + Vector3.UP * rng.randf_range(-1.0, 1.0) * ItemDrops.THROW_TWIST
			var item := _drop(test, gun, Transform3D(turn, Vector3(0.0, 60.0, 0.0)), velocity, spin)
			var first_tick := test.next_tick
			for tick in SETTLE_TICKS:
				_step(test)
				worst_depth = minf(worst_depth, _lowest(item, normal))
				if item.resting:
					rested += 1
					slowest = maxf(slowest, (test.next_tick - first_tick) * SimClock.tick_seconds())
					break
			worst_gap = maxf(worst_gap, _lowest(item, normal))
			var pose := Transform3D(item.basis, item.position)
			for tick in 64:
				_step(test)
				drift = maxf(drift, pose.origin.distance_to(item.position))
				turn_drift = maxf(turn_drift, pose.basis.get_rotation_quaternion().angle_to(item.basis.get_rotation_quaternion()))
			item.remove()
			_step(test)
		_check(worst_depth > -0.5, "%s hull stays above the %s within 0.5 inch contact tolerance (%.4f in)" % [gun, label, worst_depth])
		var settles := "%s settles onto the %s in every spin (%d/%d, slowest %.2f s, gap %.4f in)" % [gun, label, rested, THROWS, slowest, worst_gap]
		var still := "%s stays still for a second after settling on the %s (%.5f in, %.5f rad)" % [gun, label, drift, turn_drift]
		if gun == "weapon_awp":
			# Sid chose on 2026-09-28 to take Box3D with the AWP not yet
			# coming to rest (reference/box3d-trial.md); the thresholds stay.
			_check_known_open(rested == THROWS and worst_gap < 0.5, settles, AWP_SETTLING)
			_check_known_open(drift < 0.01 and turn_drift < 0.002, still, AWP_SETTLING)
		else:
			_check(rested == THROWS and worst_gap < 0.5, settles)
			_check(drift < 0.01 and turn_drift < 0.002, still)
	_close_case(test)


func _check_cleanup() -> void:
	var test := _make_case()
	var item := _drop(test, "weapon_glock", Transform3D(Basis.IDENTITY, Vector3(0.0, 30.0, 0.0)))
	for tick in 128:
		_step(test)
	var native := test.adapter.body_for(item.id)
	var player := _Player.new()
	test.host.add_child(player)
	player.position = Vector3(item.position.x, 0.0, item.position.z)
	var userid := test.game.add_player(player)
	item.next_pickup_check_usec = test.game.now_usec()
	_step(test)
	_check(test.game.inventory(userid).has("weapon_glock") and item.removed,
		"the ordinary pickup system takes a Box3D gun with its inventory entry")
	_step(test)
	_check(test.adapter.body_count() == 0 and not is_instance_valid(native),
		"pickup destroys the native body by the next tick")
	for gun in GUNS:
		_drop(test, gun, Transform3D(Basis.IDENTITY, Vector3(300.0, 60.0, 0.0)))
	_check_equal(test.adapter.body_count(), 3, "three dropped guns have three native bodies")
	test.game.events.send(&"round_prestart")
	test.game.events.flush()
	_step(test)
	_check(test.game.entities.size() == 0 and test.adapter.body_count() == 0,
		"round_prestart removes dropped entities and their native bodies")
	_drop(test, "weapon_ak47", Transform3D(Basis.IDENTITY, Vector3(300.0, 60.0, 0.0)))
	test.game.entities.clear()
	_check_equal(test.adapter.body_count(), 0, "clearing all entities also destroys native bodies immediately")
	_close_case(test)


func _make_case(ramp: bool = false) -> _Case:
	var test := _Case.new()
	test.host = Node3D.new()
	root.add_child(test.host)
	var geometry := Node3D.new()
	test.host.add_child(geometry)
	var body := StaticBody3D.new()
	body.collision_layer = Hitscan.WORLD_LAYER
	var collision := CollisionShape3D.new()
	collision.name = "concrete"
	if ramp:
		var rise := 2048.0 * tan(deg_to_rad(SLOPE))
		var a := Vector3(-2048.0, -rise, 2048.0)
		var b := Vector3(2048.0, -rise, 2048.0)
		var c := Vector3(2048.0, rise, -2048.0)
		var d := Vector3(-2048.0, rise, -2048.0)
		var triangles := ConcavePolygonShape3D.new()
		triangles.set_faces(PackedVector3Array([a, d, c, a, c, b]))
		collision.shape = triangles
	else:
		var box := BoxShape3D.new()
		box.size = Vector3(8192.0, 16.0, 8192.0)
		collision.shape = box
		collision.position.y = -8.0
	body.add_child(collision)
	geometry.add_child(body)
	test.game = GameSystems.new()
	test.game.last_tick = SimTick.new(test.game, 0)
	test.adapter = Box3DDrops.new()
	test.host.add_child(test.adapter)
	_check(test.adapter.initialize(test.game, geometry), "Box3D captures the test collision world")
	return test


func _drop(test: _Case, gun: String, from: Transform3D, velocity := Vector3.ZERO, spin := Vector3.ZERO) -> DroppedItem:
	var definition := ItemRegistry.item(gun)
	var entry := Inventory.Entry.new(definition, Weapon.new(ItemRegistry.weapon_data(gun)), 1)
	return DroppedItem.drop_from(test.game, 99, entry, from, velocity, spin)


func _step(test: _Case) -> void:
	test.game.step(test.next_tick, test.space())
	test.next_tick += 1


func _lowest(item: DroppedItem, normal: Vector3) -> float:
	var lowest := INF
	var model := item.model_transform()
	for point in item.physics().points:
		lowest = minf(lowest, (model * point).dot(normal))
	return lowest


func _close_case(test: _Case) -> void:
	test.game.entities.clear()
	test.host.free()


class _Case:
	extends RefCounted
	var host: Node3D
	var adapter: Box3DDrops
	var game: GameSystems
	var next_tick: int = 1

	func space() -> PhysicsDirectSpaceState3D:
		return host.get_world_3d().direct_space_state


class _Player:
	extends Node3D
	var team: String = "T"
	var alive: bool = true
