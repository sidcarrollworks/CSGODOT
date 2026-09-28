extends "res://tests/check_suite.gd"

## Real extracted Dust2, Competitive 5v5, through the shared native world.
## Asset-free CI skips this; synthetic native suites cover that environment.
## The timed window reports costs without imposing a machine-specific limit.
## godot --headless --path . --script tests/run_box3d_match_checks.gd

const TICKS := 768
var scene: PlayScene
var world: GameWorld
var mode: Competitive
var tick_costs := PackedFloat64Array()
var max_traces := 0
var total_traces := 0


func _initialize() -> void:
	if not Box3DDrops.available():
		_skip("box3d-match", "Box3D native addon is not installed; run scripts/install_box3d.ps1")
		return
	if not _assets_available():
		_skip("box3d-match", "Dust2, its nav mesh and player models must be extracted for this integration check")
		return
	await process_frame
	await _load_match("box3d")
	_check(world.players.size() == 10 and mode.bots.size() == 9,
		"the real Dust2 Competitive scene contains both five-player teams")
	var adapter := world.game.drop_physics
	_check(adapter != null and adapter.full_world and adapter.queries.native_world == adapter.native_world,
		"map collision and all gameplay queries share the match's native world")
	var local := mode.player as PlayerSim
	var starts := {}
	for player in world.players:
		starts[player.userid] = player.position
	var events: Array[StringName] = []
	world.game.events.listen_all(func(event: GameEvent) -> void: events.append(event.name))
	var native_before := PhysicsQueries.native_queries
	var legacy_before := PhysicsQueries.legacy_queries
	var finite := true
	var above_floor := true
	var floor_samples := 0
	var map_bounds: AABB = scene.map.importer.stats["bounds"]
	var worst_floor_gap := INF
	var physical_floor_ok := true
	var drop: DroppedItem
	var grenade: GrenadeEntity
	var ragdoll: Ragdoll
	var victim := mode.bots.back() as PlayerSim
	for tick in TICKS:
		if tick == TICKS - 128:
			_stage_engagement()
		if tick == 32:
			local.equip(WeaponLibrary.ak47())
			world.game.command(local.userid, "drop")
		if tick == 33:
			var dropped := world.game.entities.of_class("weapon_ak47")
			if not dropped.is_empty():
				drop = dropped[0] as DroppedItem
			local.equip(WeaponLibrary.ak47())
		if tick == 64:
			local.inventory.add(GrenadeRules.HE)
			world.game.command(local.userid, "throw %s 1" % GrenadeRules.HE)
		if tick == 65:
			var thrown := world.game.entities.of_class("hegrenade_projectile")
			if not thrown.is_empty():
				grenade = thrown[0] as GrenadeEntity
		if tick == 320:
			victim.hit_target.immortal = false
			var damage := DamageInfo.new()
			damage.attacker = local.userid
			damage.weapon = "weapon_ak47"
			damage.inflictor = damage.weapon
			damage.damage = 1000.0
			damage.direction = Vector3.FORWARD
			damage.origin = victim.global_position + Vector3.BACK * 100.0
			damage.position = victim.global_position + Vector3.UP * 48.0
			DamageInfo.deal(victim.hit_target, damage, world.game.events)
			ragdoll = victim.ragdoll
		_tick()
		for player in world.players:
			finite = finite and player.position.is_finite() and player.velocity.is_finite()
			if not player.alive:
				continue
			# A map-wide lower bound also catches falling through a surface
			# far enough that a short ground ray could no longer find it.
			above_floor = above_floor and player.position.y > map_bounds.position.y - 64.0
			if tick % 16 == 0 and player.on_ground:
				# Nav polygons bridge small stairs and lips, so their height is
				# not a collision-floor measurement. Sample the real surface.
				# A centre ray can miss while a hull corner supports an edge;
				# the many successful samples establish the floor comparison.
				var ray := PhysicsRayQueryParameters3D.create(player.position + Vector3.UP * 2.0,
					player.position + Vector3.DOWN * 4.0, Hitscan.WORLD_LAYER | MapImporter.PLAYER_CLIP_LAYER)
				var floor_hit := PhysicsQueries.intersect_ray(player.get_world_3d().direct_space_state, ray)
				if not floor_hit.is_empty():
					floor_samples += 1
					var gap := player.position.y - (floor_hit["position"] as Vector3).y
					worst_floor_gap = minf(worst_floor_gap, gap)
					physical_floor_ok = physical_floor_ok and gap >= -0.5
		for entity in world.game.entities.all():
			finite = finite and entity.position.is_finite()
		if ragdoll != null:
			for part: Ragdoll.Part in ragdoll.bodies.values():
				finite = finite and part.global_position.is_finite() and part.linear_velocity.is_finite()
	_check(finite, "players, drops, grenades and ragdoll retain finite poses and velocities")
	_check(above_floor and physical_floor_ok and floor_samples > 100,
		"grounded players stay above Dust2's physical floor (%d samples; smallest clearance %.3f inches)" % [floor_samples, worst_floor_gap])
	var moved := 0
	var shots := 0
	for bot in mode.bots:
		if bot.position.distance_to(starts[bot.userid]) > 100.0:
			moved += 1
		shots += bot.rounds_fired
	_check(moved >= 7 and shots > 0, "bots travel their real map routes and fire through gameplay (%d moved, %d shots)" % [moved, shots])
	_check(PhysicsQueries.native_queries > native_before and PhysicsQueries.legacy_queries == legacy_before,
		"the entire gameplay window routes physics queries to Box3D (%d native, %d legacy)" % [PhysicsQueries.native_queries - native_before, PhysicsQueries.legacy_queries - legacy_before])
	_check(drop != null and drop.position.is_finite() and adapter.body_for(drop.id) != null
		and adapter.body_for(drop.id).get_parent() == adapter.native_world,
		"the commanded gun drop lives in the same native world as the map")
	_check(grenade != null and events.has(&"grenade_thrown") and events.has(&"hegrenade_detonate"),
		"the inventory throw creates an HE that completes its flight and detonates on Dust2")
	var shared_ragdoll := ragdoll != null and not ragdoll.bodies.is_empty()
	if shared_ragdoll:
		for part: Ragdoll.Part in ragdoll.bodies.values():
			shared_ragdoll = shared_ragdoll and part.native.get_parent() == adapter.native_world
	_check(not victim.alive and shared_ragdoll, "an actual player death creates a ragdoll in the match's shared native world")
	var detached := true
	for source in scene.find_children("*", "PhysicsBody3D", true, false):
		detached = detached and not PhysicsServer3D.body_get_space((source as PhysicsBody3D).get_rid()).is_valid()
	for source in scene.find_children("*", "Area3D", true, false):
		detached = detached and not PhysicsServer3D.area_get_space((source as Area3D).get_rid()).is_valid()
	await physics_frame
	_check(detached and PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_ACTIVE_OBJECTS) == 0,
		"Godot's server has no active bodies or attached map/player collision objects")
	_report_costs("box3d-match")
	scene.free()
	await process_frame
	_finish("box3d-match")


static func _assets_available() -> bool:
	var paths := MapPaths.of("de_dust2")
	return (FileAccess.file_exists(paths.nav_file) and DirAccess.dir_exists_absolute(paths.collision_dir)
		and ResourceLoader.exists(PlayerModel.AGENTS["T"]) and ResourceLoader.exists(PlayerModel.AGENTS["CT"]))


func _load_match(backend: String) -> void:
	seed(20260926)
	scene = (load("res://maps/de_dust2/de_dust2.tscn") as PackedScene).instantiate() as PlayScene
	scene.game_mode = "Competitive"
	scene.team_size = 5
	scene.warmup_seconds = 120.0
	root.add_child(scene)
	world = scene.world
	mode = scene.mode
	world.set_physics_process(false)
	# Disabling frame callbacks must not disable authoring collision in the
	# explicit legacy comparison. Set this before native ownership detaches it.
	for source in scene.find_children("*", "CollisionObject3D", true, false):
		(source as CollisionObject3D).disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	world.initialize_drop_physics(scene, backend)
	# Manual world ticks with animation poses advanced separately. This
	# reports simulation cost, not rendering, audio or UI frame cost.
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	await physics_frame
	await process_frame
	await physics_frame
	mode.match_state.rules.freeze_seconds = 0.0
	mode.match_state.end_warmup_on_next_tick()
	world.step()
	for player in world.players:
		player.equip(WeaponLibrary.ak47())
		# Preserve the ten-player workload until the explicit death case.
		player.hit_target.immortal = true
	for tick in 96:
		world.step()
		_pose_players()


func _tick() -> void:
	var before := 0
	for player in world.players:
		before += player.traces
	var start := Time.get_ticks_usec()
	world.step()
	tick_costs.append(float(Time.get_ticks_usec() - start))
	var after := 0
	for player in world.players:
		after += player.traces
	total_traces += after - before
	max_traces = maxi(max_traces, after - before)
	_pose_players()


## Ensure the short route window includes actual bot decisions and shots:
## two opponents meet on the map's open T spawn, face each other, and keep
## their normal sight/reaction/weapon code. Their held weapons stay real.
func _stage_engagement() -> void:
	var first: Bot
	var second: Bot
	for bot in mode.bots:
		if not bot.alive:
			continue
		if bot.team == "T" and first == null:
			first = bot
		elif bot.team == "CT" and second == null:
			second = bot
	if first == null or second == null:
		return
	var spawns: Array = mode.map.spawns["T"]
	var start: Vector3 = spawns[0]["position"]
	var finish := start
	for spawn: Dictionary in spawns:
		var at: Vector3 = spawn["position"]
		if start.distance_squared_to(at) > start.distance_squared_to(finish):
			finish = at
	var look := PlayerInput.angles_from_direction(finish - start)
	first.place(start, look.x)
	second.place(finish, look.x + 180.0)
	first.route = PackedVector3Array()
	second.route = PackedVector3Array()
	first.velocity = Vector3.ZERO
	second.velocity = Vector3.ZERO
	first.holds_fire = false
	second.holds_fire = false


func _pose_players() -> void:
	for player in world.players:
		if player.model != null and player.model.is_animating():
			player.model.step(SimClock.tick_seconds())
			if player.model.character_rig != null:
				player.model.character_rig.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)


func _report_costs(label: String) -> void:
	var sorted := tick_costs.duplicate()
	sorted.sort()
	var total := 0.0
	for cost in sorted:
		total += cost
	var p95 := sorted[mini(sorted.size() - 1, int(ceil(sorted.size() * 0.95)) - 1)]
	print("PROFILE %s ticks=%d mean_ms=%.3f p95_ms=%.3f max_ms=%.3f mean_traces=%.2f max_traces=%d" % [
		label, sorted.size(), total / sorted.size() / 1000.0, p95 / 1000.0, sorted[-1] / 1000.0,
		float(total_traces) / sorted.size(), max_traces])


func _print_passes() -> bool:
	return true
