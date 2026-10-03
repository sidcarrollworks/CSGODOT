extends SceneTree

## Repeatable flight-only workload on Dust2's extracted collision hull.
## Ten sustained projectiles and ten stationary player hulls. No drawing,
## smoke/fire/effects, bot thinking or rigid-body stepping. Resets are outside
## timing; the measured loop includes per-projectile body checks and sweeps.
## Copy the identical script into an old checkout for a paired comparison:
## godot --headless --path . --script scripts/profile_grenades.gd
const COUNT := 10
const WARMUP := 128
const TICKS := 4096
const DT := 1.0 / 64.0
var _host: Node3D
var _game: GameSystems
var _system: GrenadeSystem
var _spawns: Array[Dictionary] = []
var _players: Array[PlayerSim] = []
var _grenades: Array[GrenadeEntity] = []
var _serial := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var paths := MapPaths.of("de_dust2")
	var hull_file := MapImporter.find_collision_file(paths.collision_dir)
	var map_file := MapImporter.find_map_file(paths.map_dir)
	var spawns := SourceEntities.player_spawns(SourceEntities.parse(map_file.get_base_dir().path_join(MapPaths.ENTITIES_FILE)))
	if hull_file.is_empty() or spawns.T.is_empty() or spawns.CT.is_empty() or not Box3DDrops.available():
		printerr("Requires extracted Dust2 hull/entities and installed Box3D")
		quit(2)
		return
	_host = Node3D.new()
	root.add_child(_host)
	var importer := MapImporter.new()
	_host.add_child(importer)
	var hull := importer._load_scene(hull_file)
	importer.add_child(hull)
	hull.scale = Vector3.ONE * MapImporter.SOURCE2_VIEWER_SCALE
	var meshes: Array[MeshInstance3D] = []
	importer._collect_meshes(hull, meshes)
	var targets: Array[MeshInstance3D] = []
	for mesh in meshes:
		mesh.visible = false
		if not importer._matches_any(PackedStringArray([mesh.name]), importer.hull_skip_hints):
			targets.append(mesh)
	var triangles := importer._build_collision(targets)
	_game = GameSystems.new()
	_system = GrenadeSystem.new()
	_game.add_system(_system)
	for side in ["T", "CT"]:
		for index in 5:
			var spawn: Dictionary = spawns[side][index % spawns[side].size()]
			_spawns.append(spawn)
			var player := _HullPlayer.new()
			player.position = spawn.position
			player.team = side
			player.collision_layer = PlayerSim.PLAYER_LAYER
			_host.add_child(player)
			player.userid = _game.add_player(player, player.hit_target, player.inventory)
			_players.append(player)
			_grenades.append(null)
	for frame in 3:
		await physics_frame
	var adapter := Box3DDrops.new()
	_host.add_child(adapter)
	if not adapter.initialize(_game, _host, true):
		quit(2)
		return
	var samples: Array[float] = []
	var contacts := 0
	var blocked := 0
	var peak_contacts := 0
	var query_start := 0
	var legacy_start := 0
	var space := _host.get_world_3d().direct_space_state
	for tick in TICKS + WARMUP:
		var t := SimTick.new(_game, tick + 1, space)
		for index in COUNT:
			var grenade := _grenades[index]
			if grenade == null or grenade.flight.at_rest or t.now_usec - grenade.thrown_usec > 1_200_000:
				_grenades[index] = _new_flight(index, t.now_usec)
		if tick == WARMUP:
			query_start = PhysicsQueries.native_queries
			legacy_start = PhysicsQueries.legacy_queries
		var started := Time.get_ticks_usec()
		for grenade in _grenades:
			grenade._fly(t)
		var elapsed := Time.get_ticks_usec() - started
		if tick >= WARMUP:
			samples.append(float(elapsed))
			var in_tick := 0
			for grenade in _grenades:
				in_tick += grenade.flight.touches.size()
				if not grenade.flight.position.is_finite() or not grenade.flight.velocity.is_finite():
					printerr("Non-finite trajectory at tick ", tick)
					quit(1)
					return
			contacts += in_tick
			peak_contacts = maxi(peak_contacts, in_tick)
			for grenade in _grenades:
				blocked += int(grenade.flight.get("blocked_start") == true)
		if tick % 256 == 0:
			await process_frame
	samples.sort()
	var sum := 0.0
	for sample in samples:
		sum += sample
	print("GRENADE_PROFILE ", JSON.stringify({"projectiles": COUNT, "ticks": TICKS,
		"triangles": triangles, "native_queries": PhysicsQueries.native_queries - query_start,
		"legacy_queries": PhysicsQueries.legacy_queries - legacy_start,
		"mean_ms": sum / TICKS / 1000.0, "p95_ms": samples[int(TICKS * 0.95)] / 1000.0,
		"max_ms": samples[-1] / 1000.0, "contacts": contacts, "peak_contacts": peak_contacts,
		"blocked_updates": blocked, "finite": true}))
	_host.free()
	for system in _game.systems():
		if system is ItemDrops or system is GrenadeSystem:
			system.game = null
	quit(0)


func _new_flight(index: int, at_usec: int) -> GrenadeEntity:
	_serial += 1
	var grenade := GrenadeEntity.new()
	grenade.system = _system
	grenade.weapon_class = GrenadeRules.HE
	grenade.owner_id = _players[index].userid
	grenade.team = _players[index].team
	grenade.thrown_usec = at_usec
	grenade.flight = GrenadeFlight.new()
	grenade.flight.position = _spawns[index].position + Vector3.UP * 64.0
	var yaw := float(_spawns[index].yaw) + float((_serial % 5) * 10 - 20)
	grenade.flight.velocity = PlayerInput.aim_direction(yaw, 5.0 + float(_serial % 3) * 15.0) * 675.0
	grenade.position = grenade.flight.position
	return grenade


class _HullPlayer extends PlayerSim:
	func _init() -> void:
		var collision := CollisionShape3D.new()
		collision.shape = BoxShape3D.new()
		add_child(collision)

	func wear_body(_weapon_model: String, _drawn: bool) -> void:
		pass
