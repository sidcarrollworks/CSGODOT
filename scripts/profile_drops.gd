extends SceneTree

## Repeatable drop comparison, using the same CS2 hulls and seeded throws.
## godot --headless --path . --script scripts/profile_drops.gd -- --drop-physics box3d --slope 14
## Repeat with --drop-physics legacy. Optional --count 36 --ticks 640.
## --map de_dust2 drops at the extracted map's T spawns instead of a test floor.
## Times cover GameSystems.step (including pickup checks), without rendering.
## This measures drops on a controlled surface, not whole-match performance.

const GUNS := ["weapon_glock", "weapon_ak47", "weapon_awp"]
const DT := 1.0 / 64.0
var _stage: Node3D


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var backend := _arg(args, "--drop-physics", "box3d")
	var count := clampi(int(_arg(args, "--count", "36")), 1, 1000)
	var ticks := clampi(int(_arg(args, "--ticks", "640")), 128, 6400)
	var slope := clampf(float(_arg(args, "--slope", "0")), 0.0, 30.0)
	var map_name := _arg(args, "--map", "")
	if backend not in ["box3d", "legacy"]:
		printerr("Use --drop-physics box3d or legacy.")
		quit(1)
		return
	_stage = Node3D.new()
	root.add_child(_stage)
	var turn := Basis(Vector3.RIGHT, deg_to_rad(slope))
	var normal := turn * Vector3.UP
	var map_spawns: Array = []
	var map_start := Time.get_ticks_usec()
	if not map_name.is_empty():
		var map := MapLoader.new()
		map.map_name = map_name
		_stage.add_child(map)
		map_spawns = map.contents.spawns["T"]
		if map.importer == null or map_spawns.is_empty():
			printerr("Map geometry and T spawns must be extracted to profile " + map_name)
			_stage.free()
			quit(1)
			return
	else:
		var floor_body := StaticBody3D.new()
		floor_body.collision_layer = 1
		floor_body.collision_mask = 0
		floor_body.basis = turn
		var shape := CollisionShape3D.new()
		shape.name = "concrete"
		var box := BoxShape3D.new()
		box.size = Vector3(16384.0, 16.0, 16384.0)
		shape.shape = box
		shape.position.y = -8.0
		floor_body.add_child(shape)
		_stage.add_child(floor_body)
	var map_load_usec := Time.get_ticks_usec() - map_start
	await physics_frame
	var game := GameSystems.new()
	game.last_tick = SimTick.new(game, 0)
	var adapter: Box3DDrops
	var setup_start := Time.get_ticks_usec()
	if backend == "box3d":
		adapter = Box3DDrops.new()
		_stage.add_child(adapter)
		if not adapter.initialize(game, _stage):
			printerr("Box3D initialization failed; run scripts/install_box3d.ps1.")
			_stage.free()
			quit(1)
			return
	var setup_usec := Time.get_ticks_usec() - setup_start
	var items: Array[DroppedItem] = []
	var random := RandomNumberGenerator.new()
	random.seed = 924043
	var columns := ceili(sqrt(float(count)))
	var spawn_start := Time.get_ticks_usec()
	for i in count:
		var gun: String = GUNS[i % GUNS.size()]
		var carried := Inventory.new()
		carried.add(gun)
		var x := (float(i % columns) - float(columns) / 2.0) * 256.0
		var z := (floorf(float(i) / columns) - float(columns) / 2.0) * 256.0
		var pose := Transform3D(Basis.from_euler(Vector3(random.randf_range(-1.0, 1.0), random.randf_range(-PI, PI), random.randf_range(-1.0, 1.0))), turn * Vector3(x, 72.0, z))
		if not map_spawns.is_empty():
			pose.origin = (map_spawns[i % map_spawns.size()]["position"] as Vector3) + Vector3.UP * 72.0
		var item := DroppedItem.drop_from(game, -1, carried.remove(gun), pose,
			turn * Vector3(120.0, 80.0, 0.0), Vector3(random.randf_range(-3.0, 3.0), 1.0, 2.5))
		items.append(item)
	var spawn_usec := Time.get_ticks_usec() - spawn_start
	var samples: Array[int] = []
	var first_two_seconds_usec := 0
	var worst_penetration := 0.0
	var late_translation := 0.0
	var late_rotation := 0.0
	var all_rest_tick := -1
	var space := _stage.get_world_3d().direct_space_state
	for tick in ticks:
		var before := Time.get_ticks_usec()
		game.step(tick + 1, space)
		var duration := Time.get_ticks_usec() - before
		samples.append(duration)
		if tick < 128:
			first_two_seconds_usec += duration
		var sleeping := 0
		for item in items:
			if item.resting:
				sleeping += 1
			if map_name.is_empty():
				for point in item.physics().shape.points:
					worst_penetration = minf(worst_penetration, (item.position + item.basis * point).dot(normal))
			if tick >= ticks - 64:
				late_translation = maxf(late_translation, item.position.distance_to(item.previous_position))
				if item.basis != item.previous_basis:
					late_rotation = maxf(late_rotation, item.basis.get_rotation_quaternion().angle_to(item.previous_basis.get_rotation_quaternion()))
		if sleeping == count and all_rest_tick < 0:
			all_rest_tick = tick + 1
	var slept := 0
	var queries := 0
	for item in items:
		slept += int(item.resting)
		queries += item.queries
	var total := 0
	for sample in samples:
		total += sample
	samples.sort()
	print(JSON.stringify({
		"backend": backend, "guns": count, "slope_degrees": slope, "ticks": ticks,
		"map": map_name, "map_load_ms": map_load_usec / 1000.0,
		"collision_setup_ms": setup_usec / 1000.0, "gun_spawn_ms": spawn_usec / 1000.0,
		"step_mean_us": float(total) / ticks,
		"step_p95_us": samples[mini(samples.size() - 1, floori(samples.size() * 0.95))],
		"first_two_seconds_mean_us": first_two_seconds_usec / 128.0,
		"resting": slept, "all_rest_seconds": all_rest_tick * DT if all_rest_tick >= 0 else -1.0,
		"deepest_corner_inches": worst_penetration if map_name.is_empty() else null,
		"last_second_max_tick_translation_inches": late_translation,
		"last_second_max_tick_rotation_degrees": rad_to_deg(late_rotation),
		"legacy_queries": queries,
		"native_steps": adapter.native_steps if adapter != null else 0,
		"native_static_shapes": adapter.captured_shapes if adapter != null else 0,
		"native_static_triangles": adapter.captured_triangles if adapter != null else 0,
	}, "\t"))
	game.entities.clear()
	_stage.free()
	quit(0)


func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	for i in args.size():
		if args[i] == key and i + 1 < args.size():
			return args[i + 1]
		if args[i].begins_with(key + "="):
			return args[i].trim_prefix(key + "=")
	return fallback
