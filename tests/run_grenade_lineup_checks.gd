extends "res://tests/check_suite.gd"

## Sid's Xbox screenshot and paired CS2 mid-door/B-doors console values.
## This is a local landing regression, not a recorded CS2 trajectory match.
## Loads collision only and uses the real movement, hand and flight paths.
## godot --headless --path . --script tests/run_grenade_lineup_checks.gd
const FEET := Vector3(-1163.7, 77.8, -299.7)
const YAW := 270.2
const PITCH := 11.8
## Paired CS2 getpos/getpos_exact reference. These are the pawn coordinates;
## local collision recovery/ground categorization may adjust them on settling.
const MID_DOOR_FEET := Vector3(-660.031250, 89.614380, -344.012573)
const MID_DOOR_YAW := 272.602875
const MID_DOOR_PITCH := 14.960024
const MID_DOOR_CAMERA_Y := 150.364380
const B_DOORS_FEET := Vector3(-256.021118, 128.077347, -1667.957031)
const B_DOORS_YAW := 262.148254
const B_DOORS_PITCH := 14.713711
const B_DOORS_CAMERA_Y := 192.014847
enum Lineup { XBOX, MID_DOOR, B_DOORS }
var _host: Node3D
var _world: GameWorld


class _Pawn extends PlayerSim:
	var jump_at := -1
	var release_at := 100000
	var fraction := 0.25
	var fresh_click := false
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
		cmd.buttons = UserCmd.ATTACK if tick < release_at and (not fresh_click or (jump_at >= 0 and tick >= jump_at)) else 0
		if fresh_click and tick == jump_at:
			cmd.steps.append(UserCmd.SubtickStep.new(UserCmd.ATTACK, true, fraction, aim_yaw, aim_pitch))
		if fresh_click and tick == release_at:
			var released := minf(fraction + 0.02, 1.0) if release_at == jump_at else 0.25
			cmd.steps.append(UserCmd.SubtickStep.new(UserCmd.ATTACK, false, released, aim_yaw, aim_pitch))
		if tick == jump_at:
			cmd.buttons |= UserCmd.JUMP
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
		# Fresh Space + click, including press/release inside one command
		# and a click held for roughly 125–191 ms before releasing.
		for fraction in [0.0, 0.25, 0.75]:
			for offset in [0, 8, 11, 12]:
				await _throw(fraction, offset, MID_DOOR_FEET, MID_DOOR_YAW, MID_DOOR_PITCH, Lineup.MID_DOOR, true)
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
				var landed := await _throw(fraction, offset, MID_DOOR_FEET, MID_DOOR_YAW, MID_DOOR_PITCH, Lineup.MID_DOOR)
				if reference.is_finite():
					_check(landed.distance_to(reference) < 0.1, "jump phases and eligible releases use the same mid-door trajectory")
				else:
					reference = landed
		# Sid confirmed a stationary left-click jump throw. The screenshot's
		# path bounces across the upper roof and wooden awning to above B doors.
		reference = Vector3.INF
		for fraction in [0.0, 0.25, 0.75]:
			for offset in [0, 2, 8]:
				var landed := await _throw(fraction, offset, B_DOORS_FEET, B_DOORS_YAW, B_DOORS_PITCH, Lineup.B_DOORS)
				if reference.is_finite():
					_check(landed.distance_to(reference) < 0.1, "jump phases and eligible releases use the same B-doors trajectory")
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


func _throw(fraction: float, release_offset: int, feet := FEET, yaw := YAW, pitch := PITCH, lineup := Lineup.XBOX, fresh_click := false) -> Vector3:
	var player := _Pawn.new()
	player.position = feet
	player.team = "T"
	player.fraction = fraction
	player.fresh_click = fresh_click
	player.aim_yaw = yaw
	player.aim_pitch = pitch
	_host.add_child(player)
	_world.add_player(player)
	player.inventory.add(GrenadeRules.SMOKE)
	await physics_frame
	for i in 80:
		_world.step()
	_check(player._pin_pulled != fresh_click and player.on_ground, "lineup fixture starts drawn on the floor with the requested pin state")
	if lineup != Lineup.XBOX:
		# Compare absolute camera height, not a hardcoded offset: Box3D's
		# resting hull clearance also changes the settled feet coordinate.
		var expected_y := MID_DOOR_CAMERA_Y if lineup == Lineup.MID_DOOR else B_DOORS_CAMERA_Y
		var camera_y := player.global_position.y + player.eye_height()
		_check(absf(camera_y - expected_y) < 0.08,
			"settled %s camera matches paired CS2 getpos within 0.08 units: %.6f vs %.6f" % [Lineup.keys()[lineup], camera_y, expected_y])
	player.jump_at = _world.tick + 1
	player.release_at = player.jump_at + release_offset
	var grenade: GrenadeEntity
	var top_contact := false
	var touched_sky := false
	var furthest_x := -INF
	var rest := Vector3.INF
	var contact_surfaces: Array[String] = []
	var target_surface := "physics_group_wood2" if lineup == Lineup.XBOX else "physics_group_wood_dense"
	if lineup == Lineup.B_DOORS:
		target_surface = "physics_group_concrete"
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
			contact_surfaces.append(touch.surface)
			touched_sky = touched_sky or touch.surface == "physics_sky"
			if touch.surface == target_surface and touch.normal.y > 0.9:
				top_contact = true
		if grenade.flight.at_rest:
			rest = grenade.position
			_check(not grenade.flight.blocked_start, "lineup flight settles through contacts without a blocked start")
			_check(not touched_sky, "sky brushes never bounce the lineup's smoke")
			if lineup == Lineup.XBOX:
				_check(top_contact, "jump smoke reaches the wooden box's upward-facing surface")
				_check(rest.x > 1400.0 and rest.x < 1480.0 and absf(rest.y + 27.0) < 2.0 and absf(rest.z + 309.0) < 10.0,
					"jump smoke rests on Xbox instead of the floor beside it: %s" % rest)
			elif lineup == Lineup.MID_DOOR:
				_check(furthest_x > 1304.0,
					"the second lineup travels beyond the sky plane instead of rebounding backward")
				_check(top_contact, "jump smoke reaches the mid door's upward-facing wooden surface")
				_check(rest.x > 1580.0 and rest.x < 1605.0 and absf(rest.y - 50.5) < 2.0 and absf(rest.z + 457.0) < 10.0,
					"jump smoke rests on the open mid door below the lintel: %s" % rest)
			else:
				_check(top_contact, "B-doors jump smoke reaches an upward-facing concrete roof")
				_check(rest.x > 2080.0 and rest.x < 2220.0 and absf(rest.y - 234.0) < 2.0 and rest.z > -1410.0 and rest.z < -1280.0,
					"jump smoke rests on the roof directly above B doors: %s" % rest)
				_check(contact_surfaces.size() >= 3 and contact_surfaces[0] == "physics_group_concrete"
					and contact_surfaces[1] == "physics_group_wood" and contact_surfaces[2] == "physics_group_concrete",
					"B-doors smoke bounces across the upper roof and wooden awning onto the gate roof")
			print("LINEUP ", JSON.stringify({"jump_fraction": fraction, "release_offset_ticks": release_offset,
				"fresh_click": fresh_click,
				"lineup": Lineup.keys()[lineup],
				"snapshot_velocity": str(player.grenade_throw.snapshot.get("velocity")),
				"rest": str(rest), "flight_seconds": grenade.age(_world.game.now_usec())}))
			var snapshot := player.grenade_throw.snapshot
			var snapshot_eye: Vector3 = snapshot["eye"]
			var snapshot_center: Vector3 = snapshot["center"]
			_check(absf(snapshot_eye.y - snapshot_center.y + player.config.stand_height * 0.5 - 64.0) < 0.001,
				"jump snapshot uses the shared airborne eye after the terrain offset clears")
			grenade.remove()
			break
	_check(rest.is_finite(), "lineup smoke spawns and settles within the bounded flight")
	if grenade != null and not rest.is_finite():
		grenade.remove()
	_world.remove_player(player)
	player.free()
	return rest
