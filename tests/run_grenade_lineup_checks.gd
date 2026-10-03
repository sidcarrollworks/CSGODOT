extends "res://tests/check_suite.gd"

## Sid's T-spawn Xbox screenshot and October 3 CS2 mid-door console values.
## This is a local landing regression, not a recorded CS2 trajectory match.
## Loads collision only and uses the real movement, hand and flight paths.
## godot --headless --path . --script tests/run_grenade_lineup_checks.gd
const FEET := Vector3(-1163.7, 77.8, -299.7)
const YAW := 270.2
const PITCH := 11.8
## CS2 getpos supplied horizontal position and aim; use the known local
## grounded height until getpos_exact supplies the pawn origin.
const MID_DOOR_FEET := Vector3(-660.031250, 89.8, -344.002014)
const MID_DOOR_YAW := 272.595718
const MID_DOOR_PITCH := 15.030418
var _host: Node3D
var _world: GameWorld


class _Pawn extends PlayerSim:
	var jump_at := -1
	var release_at := 100000
	var fraction := 0.25
	var aim_yaw := YAW
	var aim_pitch := PITCH
	func _init() -> void:
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		add_child(shape)
	func wear_body(_weapon_model: String, _drawn: bool) -> void:
		pass
	func command_for(tick: int, _dt: float) -> UserCmd:
		var cmd := UserCmd.new()
		cmd.tick = tick
		cmd.yaw_degrees = aim_yaw
		cmd.pitch_degrees = aim_pitch
		cmd.weapon_select = 4
		cmd.buttons = UserCmd.ATTACK if tick < release_at else 0
		if tick == jump_at:
			cmd.steps.append(UserCmd.SubtickStep.new(UserCmd.JUMP, true, fraction, aim_yaw, aim_pitch))
		return cmd


func _initialize() -> void:
	_run()


func _run() -> void:
	var paths := MapPaths.of("de_dust2")
	var file := MapImporter.find_collision_file(paths.collision_dir)
	if file.is_empty() or not Box3DDrops.available():
		_skip("grenade-lineup", "Requires extracted Dust2 collision and the patched Box3D addon")
		return
	await process_frame
	_host = Node3D.new()
	root.add_child(_host)
	var importer := MapImporter.new()
	_host.add_child(importer)
	var hull := importer._load_scene(file)
	importer.add_child(hull)
	hull.scale = Vector3.ONE * MapImporter.SOURCE2_VIEWER_SCALE
	var meshes: Array[MeshInstance3D] = []
	importer._collect_meshes(hull, meshes)
	var targets: Array[MeshInstance3D] = []
	for mesh in meshes:
		mesh.visible = false
		if not importer._matches_any(PackedStringArray([mesh.name]), importer.hull_skip_hints):
			targets.append(mesh)
	importer._build_collision(targets)
	_world = GameWorld.new()
	_host.add_child(_world)
	_world.set_physics_process(false)
	_world.set_process(false)
	_world.game.add_system(GrenadeSystem.new())
	await physics_frame
	if _world.initialize_drop_physics(_host, "box3d"):
		_check_clip_queries()
		var reference := Vector3.INF
		for fraction in [0.0, 0.25, 0.75]:
			for offset in [0, 2, 8]:
				var landed := await _throw(fraction, offset)
				if fraction == 0.25:
					if reference.is_finite():
						_check(landed.distance_to(reference) < 0.1, "eligible release times use the same Xbox jump trajectory")
					else:
						reference = landed
		# The CS2 inset puts this smoke on the open door leaf below the lintel.
		# Use the supplied CS2 aim rather than the earlier Godot HUD aim.
		# Surface and rest-region checks remain strict.
		reference = Vector3.INF
		for fraction in [0.0, 0.25, 0.75]:
			for offset in [0, 2, 8]:
				var landed := await _throw(fraction, offset, MID_DOOR_FEET, MID_DOOR_YAW, MID_DOOR_PITCH, false)
				if reference.is_finite():
					_check(landed.distance_to(reference) < 0.1, "jump phases and eligible releases use the same mid-door trajectory")
				else:
					reference = landed
	else:
		_check(false, "patched Box3D initializes on extracted Dust2 collision")
	_world.game.entities.clear()
	_world.game.last_tick = null
	for system in _world.game.systems():
		if system is ItemDrops or system is KillCredit or system is GrenadeSystem:
			system.game = null
	_host.free()
	_host = null
	_world = null
	_finish.call_deferred("grenade-lineup")


func _check_clip_queries() -> void:
	var space := _host.get_world_3d().direct_space_state
	var from := Vector3(1160.0, 390.0, -427.2)
	var to := from + Vector3.RIGHT * 32.0
	var sky := PhysicsRayQueryParameters3D.create(from, to, MapImporter.SKY_LAYER)
	_check(not PhysicsQueries.intersect_ray(space, sky).is_empty(),
		"the extracted sky plane above mid is retained for explicit sky queries")
	var flight := GrenadeFlight._sweep(space, from, to - from, [])
	_check(float(flight["safe"]) == 1.0 and not flight["blocked_start"],
		"live grenade sweeps pass through Dust2's sky plane above mid")
	var clip := GrenadeFlight._sweep(space, Vector3(-1040.0, 485.0, -2272.0), Vector3(0.0, 0.0, 32.0), [])
	_check(clip.get("surface", "") == "physics_csgo_grenadeclip",
		"live grenade sweeps still hit Dust2's extracted grenade-only clipping")


func _throw(fraction: float, release_offset: int, feet := FEET, yaw := YAW, pitch := PITCH, xbox := true) -> Vector3:
	var player := _Pawn.new()
	player.position = feet
	player.team = "T"
	player.fraction = fraction
	player.aim_yaw = yaw
	player.aim_pitch = pitch
	_host.add_child(player)
	_world.add_player(player)
	player.inventory.add(GrenadeRules.SMOKE)
	await physics_frame
	for i in 80:
		_world.step()
	_check(player._pin_pulled and player.on_ground, "lineup fixture starts with a held smoke on the T-spawn floor")
	player.jump_at = _world.tick + 1
	player.release_at = player.jump_at + release_offset
	var grenade: GrenadeEntity
	var top_contact := false
	var touched_sky := false
	var furthest_x := -INF
	var rest := Vector3.INF
	var target_surface := "physics_group_wood2" if xbox else "physics_group_wood_dense"
	for i in 500:
		_world.step()
		if grenade == null:
			var entities := _world.game.entities.of_class("smokegrenade_projectile")
			if not entities.is_empty():
				grenade = entities[0]
		if grenade == null:
			continue
		furthest_x = maxf(furthest_x, grenade.position.x)
		for touch in grenade.flight.touches:
			touched_sky = touched_sky or touch.surface == "physics_sky"
			if touch.surface == target_surface and touch.normal.y > 0.9:
				top_contact = true
		if grenade.flight.at_rest:
			rest = grenade.position
			_check(not grenade.flight.blocked_start, "lineup flight settles through contacts without a blocked start")
			_check(not touched_sky, "sky brushes never bounce the lineup's smoke")
			if xbox:
				_check(top_contact, "jump smoke reaches the wooden box's upward-facing surface")
				_check(rest.x > 1400.0 and rest.x < 1480.0 and absf(rest.y + 27.0) < 2.0 and absf(rest.z + 309.0) < 10.0,
					"jump smoke rests on Xbox instead of the floor beside it: %s" % rest)
			else:
				_check(furthest_x > 1304.0,
					"the second lineup travels beyond the sky plane instead of rebounding backward")
				_check(top_contact, "jump smoke reaches the mid door's upward-facing wooden surface")
				_check(rest.x > 1580.0 and rest.x < 1605.0 and absf(rest.y - 50.5) < 2.0 and absf(rest.z + 457.0) < 10.0,
					"jump smoke rests on the open mid door below the lintel: %s" % rest)
			print("LINEUP ", JSON.stringify({"jump_fraction": fraction, "release_offset_ticks": release_offset,
				"snapshot_velocity": str(player.grenade_throw.snapshot.get("velocity")),
				"rest": str(rest), "flight_seconds": grenade.age(_world.game.now_usec())}))
			grenade.remove()
			break
	_check(rest.is_finite(), "lineup smoke spawns and settles within the bounded flight")
	if grenade != null and not rest.is_finite():
		grenade.remove()
	_world.remove_player(player)
	player.free()
	return rest
