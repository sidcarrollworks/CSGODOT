extends "res://tests/check_suite.gd"

## Checks items on the ground as the bodies they are in CS2 (issue 2 of
## reference/playtest-2026-09-25.md): the table of their hulls
## (scripts/weapon_physics_table.gd, read from a fixture dump), ItemPhysics
## reading it, and DroppedItem simulating a hull whose centre of mass is
## well off the model's origin on a flat floor, a 14 degree ramp made the
## way dust2's hull is (one-sided triangles) and a curb step: never through
## any of them, lying along the ramp, spinning about its centre of mass,
## drawn where it is, picked up on the slope, saved and loaded, and what it
## costs a tick.
##
##   godot --headless --path . --script tests/run_item_physics_checks.gd
##
## Needs nothing extracted. Once reference/weapons/physics.csv is generated
## (scripts/extract_assets.sh weapon-physics, on a machine with CS2), it is
## checked too; with the models extracted, each hull is checked against its
## model.

const PhysicsTable := preload("res://scripts/weapon_physics_table.gd")
const FIXTURE_TABLE := "res://tests/fixtures/item_physics.csv"
const FIXTURE_DUMP := "res://tests/fixtures/phys_dump.txt"
## The fixture's gun: the class its row is under.
const GUN := "weapon_ak47"
const SLOPE_DEGREES := 14.0
const DT := 1.0 / 64.0

var _world: Node3D


func _initialize() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	await physics_frame
	_check_the_dump()
	_check_mass_properties()
	_check_rows()
	ItemPhysics.use_table(FIXTURE_TABLE)
	_check_the_fixture_table()
	await _check_flight()
	await _check_floor()
	await _check_ramp()
	await _check_curb()
	await _check_pickup_on_the_ramp()
	_check_the_view()
	ItemPhysics.use_table(ItemPhysics.PATH)
	await _check_the_real_table()
	_finish("item-physics")


func _check_the_dump() -> void:
	var dump := PhysicsTable.read_dump(FIXTURE_DUMP)
	_check_equal(dump.size(), 2, "the dump's two PHYS blocks are read, the cloth data after m_pFeModel skipped")
	var gun: Dictionary = dump.get("weapons/models/fixture/weapon_fixture.vmdl_c", {})
	_check(gun.get("bone") == "weapon_offset" and is_equal_approx(float(gun.get("mass", 0.0)), 4.5)
		and float(gun.get("angular_damping", -1.0)) == 0.0,
		"a gun's hull is bound to weapon_offset, with its mass and damping, read from its PHYS block and not the resource's details before it")
	var bind: Transform3D = gun.get("bind", Transform3D.IDENTITY)
	_check(bind.origin.is_equal_approx(Vector3(0.0, 2.0, 1.0)) and bind.basis.is_equal_approx(Basis.IDENTITY),
		"its bind pose comes from Source's axes (1, 0, 2) to the model's (x left, y up, z the muzzle): (0, 2, 1)")
	_check(int(gun.get("surface_hash", 0)) == 756963221 and SurfaceProperties.by_hash(756963221) == "weaponrifle",
		"its surface is named by hash: WeaponRifle")
	_check(is_equal_approx(float(gun.get("game_volume", 0.0)), 180.0)
		and (gun.get("game_centroid", Vector3.ZERO) as Vector3).is_equal_approx(Vector3(0.0, 2.0, 11.0)),
		"with the game's own volume and centroid, in the model's axes")
	var glock: Dictionary = dump.get("weapons/models/glock18/weapon_pist_glock18.vmdl_c", {})
	_check(is_equal_approx(float(glock.get("angular_damping", 0.0)), 10.0) and is_equal_approx(float(glock.get("mass", 0.0)), 3.0),
		"the next block after a cut-short one is read whole: the Glock's angular damping of 10")
	var turned := PhysicsTable.bind_from_source(PackedFloat64Array([0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0]))
	# Source's x (forward) turned onto y (left): the muzzle (+Z) onto the
	# gun's left (+X).
	_check((turned.basis * Vector3.BACK).is_equal_approx(Vector3.RIGHT),
		"a turn in the bind pose is carried into the model's axes")


func _check_mass_properties() -> void:
	var triangles := _box_triangles(Vector3(0.0, 4.0, 12.0), Vector3(1.5, 1.0, 15.0))
	var mass := PhysicsTable.mass_properties(triangles)
	var inertia: PackedFloat64Array = mass["inertia"]
	_check(is_equal_approx(float(mass["volume"]), 180.0) and (mass["centroid"] as Vector3).is_equal_approx(Vector3(0.0, 4.0, 12.0)),
		"a hull's volume and centre of mass, from its triangles (%s, %s)" % [mass["volume"], mass["centroid"]])
	_check(absf(inertia[0] - (4.0 + 900.0) / 12.0) < 1e-3 and absf(inertia[1] - (9.0 + 900.0) / 12.0) < 1e-3
		and absf(inertia[2] - (9.0 + 4.0) / 12.0) < 1e-3 and absf(inertia[3]) < 1e-6,
		"and its inertia for a mass of 1, about the centre of mass (%s)" % inertia)
	var reversed := PackedVector3Array()
	for i in range(0, triangles.size(), 3):
		reversed.append_array([triangles[i], triangles[i + 2], triangles[i + 1]])
	var again := PhysicsTable.mass_properties(reversed)
	_check(is_equal_approx(float(again["volume"]), 180.0) and (again["centroid"] as Vector3).is_equal_approx(Vector3(0.0, 4.0, 12.0)),
		"whichever way its triangles wind")


func _check_rows() -> void:
	var dump := PhysicsTable.read_dump(FIXTURE_DUMP)
	var phys: Dictionary = dump["weapons/models/fixture/weapon_fixture.vmdl_c"]
	# The hull exported about the bone: the bind pose puts it on the model.
	var about_bone := _box_triangles(Vector3(0.0, 2.0, 11.0), Vector3(1.5, 1.0, 15.0))
	var drawn := AABB(Vector3(-1.5, 3.0, -3.0), Vector3(3.0, 2.0, 30.0))
	var row := PhysicsTable.row(GUN, "fixture", phys, about_bone, drawn, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, -6.0)))
	_check(row.get("hull_frame") == "bone" and ItemPhysics.vector_of(row.get("centre_of_mass", "")).is_equal_approx(Vector3(0.0, 4.0, 12.0)),
		"a hull exported about its bone is placed by the bind pose, the one that puts its corners' average on the game's centroid (%s, %s)" % [row.get("hull_frame"), row.get("centre_of_mass")])
	# A model posed so its drawn box misleads (Sid's Nova): the centroid,
	# not the box, decides.
	var far_off := AABB(Vector3(-1.5, 30.0, -3.0), Vector3(3.0, 2.0, 30.0))
	var on_model_misled := PhysicsTable.row(GUN, "fixture", phys, _box_triangles(Vector3(0.0, 4.0, 12.0), Vector3(1.5, 1.0, 15.0)), far_off, Transform3D.IDENTITY)
	_check(on_model_misled.get("hull_frame") == "model",
		"a hull already on the model stays there however the drawn model's box lies (%s)" % on_model_misled.get("hull_frame"))
	var on_model := _box_triangles(Vector3(0.0, 4.0, 12.0), Vector3(1.5, 1.0, 15.0))
	row = PhysicsTable.row(GUN, "fixture", phys, on_model, drawn, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, -6.0)))
	_check(row.get("hull_frame") == "model" and ItemPhysics.vector_of(row.get("centre_of_mass", "")).is_equal_approx(Vector3(0.0, 4.0, 12.0)),
		"and one exported on the model is kept where it is")
	_check(row.get("surface") == "WeaponRifle" and String(row.get("mass")).to_float() == 4.5 and row.get("bone") == "weapon_offset"
		and ItemPhysics.vector_of(row.get("game_centre_of_mass", "")).is_equal_approx(Vector3(0.0, 4.0, 12.0)),
		"with the surface by its name, the mass, the bone, and the game's centroid through the bind pose")
	var path := "user://item_physics_round_trip.csv"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(PhysicsTable.csv([row]))
	file.close()
	ItemPhysics.use_table(path)
	var hull := ItemPhysics.of(GUN)
	_check(hull.from_table and hull.centre_of_mass.is_equal_approx(Vector3(0.0, 4.0, 12.0)) and hull.points.size() == 8
		and hull.held_bone.origin.is_equal_approx(Vector3(0.0, 1.0, -6.0)) and is_equal_approx(hull.inertia.x.x, 904.0 / 12.0),
		"a generated row reads back as the body ItemPhysics hands out")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check_the_fixture_table() -> void:
	var hull := ItemPhysics.of(GUN)
	_check(hull.from_table and hull.centre_of_mass.distance_to(Vector3.ZERO) > 10.0,
		"the fixture's hull has its centre of mass %.1f units off the model's origin" % hull.centre_of_mass.length())
	var shape_centre := Vector3.ZERO
	for point in hull.shape.points:
		shape_centre += point
	_check((shape_centre / hull.shape.points.size()).is_zero_approx(), "its query shape is about the centre of mass")
	var stand_in := ItemPhysics.of("weapon_glock")
	_check(not stand_in.from_table and stand_in.centre_of_mass == Vector3.ZERO and stand_in.points.size() == 8,
		"an item with no row is the stand-in box about its origin")
	var game := GameSystems.new()
	var held := Transform3D(Basis(Vector3.UP, 0.7), Vector3(10.0, 60.0, -4.0))
	var item := DroppedItem.drop_from(game, 1, _entry(GUN), held)
	_check(item.position.is_equal_approx(held * hull.held_bone.affine_inverse() * hull.centre_of_mass)
		and item.model_transform().is_equal_approx(held * hull.held_bone.affine_inverse()),
		"dropped from the hand, the body is at the centre of mass, the model where the hand held it by its root bone")


## In the air, the centre of mass follows the parabola whatever the spin.
func _check_flight() -> void:
	var space := _world.get_world_3d().direct_space_state
	var game := GameSystems.new()
	var start := Vector3(0.0, 5000.0, 0.0)
	var velocity := Vector3(120.0, 250.0, -300.0)
	var item := DroppedItem.drop_from(game, 1, _entry(GUN), Transform3D(Basis.IDENTITY, start), velocity, Vector3(9.0, 4.0, -12.0))
	var from := item.position
	var worst := 0.0
	var queries := 0
	for tick in 64:
		var before := item.queries
		item.tick(SimTick.new(game, tick + 1, space))
		queries = maxi(queries, item.queries - before)
		var t := (tick + 1) * DT
		var expected := from + velocity * t + Vector3.DOWN * 0.5 * DroppedItem.GRAVITY * t * t
		worst = maxf(worst, item.position.distance_to(expected))
	_check(worst < 1e-3, "in flight the centre of mass follows the parabola, spinning (%.5f off at worst)" % worst)
	_check(not item.basis.is_equal_approx(Basis.IDENTITY), "and it turns about it")
	_check_equal(queries, 2, "in flight it costs two queries a tick: what it touches, and the sweep")


func _check_floor() -> void:
	var floor_body := _static_box(Vector3(4096.0, 16.0, 4096.0), Vector3(0.0, -8.0, 0.0))
	await physics_frame
	var results := _throws(func(p: Vector3) -> float: return p.y, 4)
	_check(results["worst"] > -DroppedItem.SKIN - 0.01,
		"thrown onto a floor, no hull corner is ever more than a skin below it (%.3f at worst)" % results["worst"])
	_check(results["rested"] == 4, "and every throw comes to rest (%d of 4)" % results["rested"])
	_check(results["resting_queries"] == 0, "a gun at rest takes no queries")
	_check(results["most_queries"] <= 7, "and one moving at most %d a tick" % results["most_queries"])
	# How CS2's own guns bounce is checked on their hulls
	# (_check_real_bounces); this slab, thinner than any of them, rolls more.
	_check(results["highest_bounce"] < 16.0, "none bounces higher than 16 inches (%.1f)" % results["highest_bounce"])
	_check(results["slowest_rest"] < 3.0, "and lies still within 3 seconds, not the %d second cap (%.2f s)" % [DroppedItem.MOST_MOVING_USEC / 1_000_000, results["slowest_rest"]])
	floor_body.queue_free()
	await physics_frame


func _check_ramp() -> void:
	var slope := deg_to_rad(SLOPE_DEGREES)
	var ramp := _ramp(slope)
	await physics_frame
	var normal := Vector3(0.0, cos(slope), sin(slope))
	var results := _throws(func(p: Vector3) -> float: return p.dot(normal), 4, normal)
	_check(results["worst"] > -DroppedItem.SKIN - 0.01,
		"thrown onto a %d degree ramp of one-sided triangles, no hull corner goes more than a skin through it (%.3f)" % [SLOPE_DEGREES, results["worst"]])
	_check(results["rested"] == 4 and results["lowest_at_rest"] < DroppedItem.CONTACT_MARGIN,
		"at rest its lowest corner lies on the ramp (%.3f above it)" % results["lowest_at_rest"])
	_check(results["aligned"] > 0.99,
		"and it lies flat along the ramp, a face of it against it, not level (%.4f)" % results["aligned"])
	ramp.queue_free()
	await physics_frame


func _check_curb() -> void:
	var floor_body := _static_box(Vector3(4096.0, 16.0, 4096.0), Vector3(0.0, -8.0, 0.0))
	var curb := _static_box(Vector3(4096.0, 6.0, 400.0), Vector3(0.0, 3.0, 240.0))
	await physics_frame
	# How far a point is above the floor, or, inside the curb, how deep in
	# it (less than zero).
	var depth := func(p: Vector3) -> float:
		if p.z > 40.0 and p.z < 440.0 and p.y < 6.0:
			return -minf(6.0 - p.y, minf(p.z - 40.0, 440.0 - p.z))
		return p.y
	var results := _throws(depth, 4)
	_check(results["worst"] > -DroppedItem.SKIN - 0.05,
		"thrown at a curb step, no hull corner goes into the floor or the curb (%.3f)" % results["worst"])
	floor_body.queue_free()
	curb.queue_free()
	await physics_frame


func _check_pickup_on_the_ramp() -> void:
	var slope := deg_to_rad(SLOPE_DEGREES)
	var ramp := _ramp(slope)
	await physics_frame
	var space := _world.get_world_3d().direct_space_state
	var game := GameSystems.new()
	var node := _Player.new()
	_world.add_child(node)
	var userid := game.add_player(node)
	var item := DroppedItem.drop_from(game, 99, _entry(GUN), Transform3D(Basis(Vector3.UP, 1.0), Vector3(0.0, 40.0, 0.0)), Vector3.ZERO, Vector3(1.0, 0.0, 0.5))
	var tick := 1
	while not item.resting and tick < 64 * 10:
		game.step(tick, space)
		tick += 1
	# Standing uphill of it, as a box does on a slope: on its uphill edge,
	# its origin over the ground under its middle by 16 x tan(slope).
	var ground := func(x: float, z: float) -> float: return -z * tan(slope)
	var feet := Vector3(item.position.x, 0.0, item.position.z - 12.0)
	feet.y = ground.call(feet.x, feet.z) + 16.0 * tan(slope)
	node.global_position = feet
	var inventory := game.inventory(userid)
	for i in 64 * 2:
		game.step(tick, space)
		tick += 1
	_check(inventory.has(GUN) and game.entities.of_class(GUN).is_empty(),
		"a player on the ramp uphill of a gun, %.1f units above its centre of mass, picks it up" % (feet.y - item.position.y))
	node.queue_free()
	ramp.queue_free()
	await physics_frame


func _check_the_view() -> void:
	var game := GameSystems.new()
	var view := DroppedItemView.new()
	_world.add_child(view)
	view.watch(game)
	var held := Transform3D(Basis(Vector3.RIGHT, 0.4), Vector3(0.0, 50.0, 0.0))
	var item := DroppedItem.drop_from(game, 1, _entry(GUN), held, Vector3(0.0, 0.0, 100.0), Vector3(3.0, 0.0, 0.0))
	view._process(0.0)
	item.tick(SimTick.new(game, 1, null))
	view._process(0.0)
	var model := view.model_of(item.id)
	var hull := item.physics()
	# Measured off the skeleton, where the model has one: a gun's dropped
	# clip moves its root bone, which the view takes back out.
	var frame := DroppedItemView.drawn_frame(model, hull.bone) if model != null else Transform3D.IDENTITY
	_check(model != null and (frame * hull.centre_of_mass).is_equal_approx(item.position),
		"the drawn model's centre of mass is where the simulation's body is")
	var state := item.save_state()
	var copy := DroppedItem.new()
	copy.load_state(state)
	_check(copy.position == item.position and copy.basis == item.basis and copy.resting == item.resting
		and copy.slow_since_usec == item.slow_since_usec and copy.ground_normal == item.ground_normal
		and copy.model_transform().is_equal_approx(item.model_transform()),
		"a dropped item saves and loads its body")
	view.queue_free()


## The generated table, once there is one: a row for every item that can
## be dropped, each centre of mass inside its hull; and with the models,
## each hull on its model.
func _check_the_real_table() -> void:
	if not FileAccess.file_exists(ItemPhysics.PATH):
		print("  reference/weapons/physics.csv is not generated yet (scripts/extract_assets.sh weapon-physics); its checks wait for it")
		return
	var missing := PackedStringArray()
	for def in ItemRegistry.all():
		if def.droppable and def.type != "knife" and def.item_class != "weapon_c4" and not ItemPhysics.has(def.item_class):
			missing.append(def.item_class)
	_check(missing.is_empty(), "every item that can be dropped has a row in physics.csv (missing: %s)" % ", ".join(missing))
	var outside := PackedStringArray()
	var body := StaticBody3D.new()
	body.collision_layer = 1 << 9
	var shape_node := CollisionShape3D.new()
	body.add_child(shape_node)
	_world.add_child(body)
	for item_class in ItemPhysics.classes():
		shape_node.shape = ItemPhysics.of(item_class).shape
		await physics_frame
		var query := PhysicsPointQueryParameters3D.new()
		query.position = body.global_position
		query.collision_mask = 1 << 9
		if _world.get_world_3d().direct_space_state.intersect_point(query).is_empty():
			outside.append(item_class)
	_check(outside.is_empty(), "each centre of mass lies inside its hull (outside: %s)" % ", ".join(outside))
	body.queue_free()
	await _check_real_bounces()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/weapons")):
		print("  the models are not extracted; each hull's placement against the game's centroid waits for a table written with them")
		return
	# CS2's m_vCentroid is the average of the hull's corners: on a hull
	# placed right it is ours to a thousandth of an inch, so it checks the
	# axes and the frame (the drawn model's bounds do not: a convex hull
	# leaves out thin parts, and a posed model's parts lie apart). Only with
	# the models, as the table written on Sid's machine before this check
	# still has three hulls placed by their bounds.
	var off := PackedStringArray()
	var rows := ItemPhysics.read_table(ItemPhysics.PATH)
	for item_class in ItemPhysics.classes():
		var row: Dictionary = rows.get(item_class, {})
		var game := String(row.get("game_centre_of_mass", ""))
		if game.is_empty():
			continue
		var average := PhysicsTable.corner_average(ItemPhysics.of(item_class).points)
		if average.distance_to(ItemPhysics.vector_of(game)) > 0.01:
			off.append("%s (corners' average %s, game's %s)" % [item_class, average, game])
	_check(off.is_empty(), "each hull's corners average to the game's centroid: axes and placement are right (%s)" % "; ".join(off))


## CS2's own Glock, AK-47 and AWP thrown at CS2's drop speed onto concrete
## twelve ways each, from the committed table: what Sid saw in CS2
## (2026-09-26, DroppedItem.BOUNCE_SPEED) as far as it is checked. A Glock
## thrown right bounces a few inches (a landing answered on the one point
## the sweep met left it dead on the floor), none flies higher than 16
## inches, and each lies still within 3 seconds.
func _check_real_bounces() -> void:
	var floor_body := _static_box(Vector3(8192.0, 16.0, 8192.0), Vector3(0.0, -8.0, 0.0))
	(floor_body.get_child(0) as Node).name = "concrete"
	await physics_frame
	var space := _world.get_world_3d().direct_space_state
	var game := GameSystems.new()
	var worst := PackedStringArray()
	var glock_highest := 0.0
	for gun in ["weapon_glock", "weapon_ak47", "weapon_awp"]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var highest := 0.0
		var slowest := 0.0
		for throw in 12:
			var turn := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.6, 0.3))
			var velocity := (turn * Vector3.BACK + Vector3.UP * ItemDrops.THROW_LIFT).normalized() * ItemDrops.THROW_SPEED
			var spin := turn.x * rng.randf_range(0.5, 1.0) * ItemDrops.THROW_TUMBLE + Vector3.UP * rng.randf_range(-1.0, 1.0) * ItemDrops.THROW_TWIST
			var item := DroppedItem.drop_from(game, 1, _entry(gun), Transform3D(turn, Vector3(0.0, 60.0, 0.0)), velocity, spin)
			var touched := false
			for tick in DroppedItem.MOST_MOVING_USEC / SimClock.tick_usec() + 2:
				item.tick(SimTick.new(game, tick + 1, space))
				var lowest := INF
				for point in item.physics().points:
					lowest = minf(lowest, (item.model_transform() * point).y)
				touched = touched or lowest < DroppedItem.CONTACT_MARGIN
				if touched:
					highest = maxf(highest, lowest)
				if item.resting:
					slowest = maxf(slowest, (item.rested_usec - item.dropped_usec) / 1_000_000.0)
					break
		if gun == "weapon_glock":
			glock_highest = highest
		if highest > 16.0 or slowest > 3.0:
			worst.append("%s (%.1f in, %.2f s)" % [gun, highest, slowest])
	_check(glock_highest > 2.0, "CS2's Glock thrown onto concrete bounces a few inches, as Sid saw (%.1f in at most)" % glock_highest)
	_check(worst.is_empty(), "no gun bounces higher than 16 inches, and each lies still within 3 seconds (%s)" % "; ".join(worst))
	floor_body.queue_free()
	await physics_frame


## Throws the fixture gun count ways from above the origin and steps each
## until it rests: the least depth any hull corner reached (depth_of gives a
## corner's height above the surfaces, less than zero inside), how many
## came to rest, and at rest the lowest corner's height, how flat it lies
## against normal, the most queries a moving tick took and those a resting
## one takes; and once it first touches, how high it leaves the surface at
## most, and the longest a throw took to rest.
func _throws(depth_of: Callable, count: int, normal := Vector3.UP) -> Dictionary:
	var space := _world.get_world_3d().direct_space_state
	var game := GameSystems.new()
	var out := {"worst": INF, "rested": 0, "lowest_at_rest": -INF, "aligned": 1.0, "most_queries": 0, "resting_queries": 0,
		"highest_bounce": 0.0, "slowest_rest": 0.0}
	for throw in count:
		var yaw := throw * 1.7
		var turn := Basis(Vector3.UP, yaw)
		var item := DroppedItem.drop_from(game, 1, _entry(GUN), Transform3D(turn, Vector3(0.0, 50.0 + throw * 10.0, 0.0)),
			turn * Vector3(0.0, 75.0, 290.0), turn * Vector3(2.0 + throw, 0.5, 0.0))
		var touched := false
		for tick in DroppedItem.MOST_MOVING_USEC / SimClock.tick_usec() + 2:
			var before := item.queries
			item.tick(SimTick.new(game, tick + 1, space))
			out["most_queries"] = maxi(out["most_queries"], item.queries - before)
			var lowest := INF
			for point in item.physics().points:
				lowest = minf(lowest, depth_of.call(item.model_transform() * point))
			out["worst"] = minf(out["worst"], lowest)
			touched = touched or lowest < DroppedItem.CONTACT_MARGIN
			if touched:
				out["highest_bounce"] = maxf(out["highest_bounce"], lowest)
			if item.resting:
				out["slowest_rest"] = maxf(out["slowest_rest"], (item.rested_usec - item.dropped_usec) / 1_000_000.0)
				out["rested"] += 1
				out["lowest_at_rest"] = maxf(out["lowest_at_rest"], lowest)
				# The fixture is a box: lying flat, one of its axes is along
				# the surface's normal.
				var b := item.basis.orthonormalized()
				out["aligned"] = minf(out["aligned"], maxf(absf(b.x.dot(normal)), maxf(absf(b.y.dot(normal)), absf(b.z.dot(normal)))))
				var still := item.queries
				for i in 8:
					item.tick(SimTick.new(game, tick + 2 + i, space))
				out["resting_queries"] += item.queries - still
				break
	return out


func _entry(item_class: String) -> Inventory.Entry:
	var def := ItemRegistry.item(item_class)
	var weapon := Weapon.new(ItemRegistry.weapon_data(item_class)) if def.is_gun else null
	return Inventory.Entry.new(def, weapon, 1)


func _static_box(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Hitscan.WORLD_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	body.add_child(shape)
	_world.add_child(body)
	return body


## A ramp rising toward -Z at slope, through the origin, as dust2's hull
## is made: one-sided triangles, facing up.
func _ramp(slope: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Hitscan.WORLD_LAYER
	var shape := CollisionShape3D.new()
	var faces := ConcavePolygonShape3D.new()
	var rise := 1000.0 * tan(slope)
	var a := Vector3(-1000.0, -rise, 1000.0)
	var b := Vector3(1000.0, -rise, 1000.0)
	var c := Vector3(1000.0, rise, -1000.0)
	var d := Vector3(-1000.0, rise, -1000.0)
	faces.set_faces(PackedVector3Array([a, d, c, a, c, b]))
	shape.shape = faces
	body.add_child(shape)
	_world.add_child(body)
	return body


## A box's twelve triangles, wound outwards.
static func _box_triangles(centre: Vector3, half: Vector3) -> PackedVector3Array:
	var corner := func(x: int, y: int, z: int) -> Vector3:
		return centre + Vector3(half.x * x, half.y * y, half.z * z)
	var quads := [
		[[1, -1, -1], [1, 1, -1], [1, 1, 1], [1, -1, 1]],
		[[-1, -1, -1], [-1, -1, 1], [-1, 1, 1], [-1, 1, -1]],
		[[-1, 1, -1], [-1, 1, 1], [1, 1, 1], [1, 1, -1]],
		[[-1, -1, -1], [1, -1, -1], [1, -1, 1], [-1, -1, 1]],
		[[-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1]],
		[[-1, -1, -1], [-1, 1, -1], [1, 1, -1], [1, -1, -1]],
	]
	var out := PackedVector3Array()
	for quad in quads:
		var p: Array[Vector3] = []
		for c in quad:
			p.append(corner.call(c[0], c[1], c[2]))
		out.append_array([p[0], p[1], p[2], p[0], p[2], p[3]])
	return out


class _Player:
	extends Node3D
	var team: String = "T"
	var alive: bool = true
	var yaw_degrees: float = 0.0
	var velocity := Vector3.ZERO
