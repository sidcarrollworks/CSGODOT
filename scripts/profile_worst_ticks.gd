extends SceneTree

## What the worst ticks of dust2's match are made of, which the mean of a
## tick does not say: the seeded Competitive match of
## tests/run_dust2_think_checks.gd (nine bots with money to buy with, fifty
## seconds of game), the tick run by its parts and each timed.
##
## It plays the match three times. The first warms what a first play reads.
## The second is the one measured: how many ticks took more than 6 ms, and
## the worst of them, each with its split (the tick's beginning, everyone's
## command, everyone's run, its end), whose run was the longest, and the
## events the tick sent. The third asks a ray that can meet a hitbox after
## every tick, and the same ray again, and one that meets the world alone:
## what a round's trace pays before it has met anything.
##
##   godot --headless --path . --script scripts/profile_worst_ticks.gd
##   godot --headless --path . --script scripts/profile_worst_ticks.gd -- --think main
##
## Needs dust2, its nav mesh and the player models extracted, and the Box3D
## addon. First run 2026-09-28
## (reference/research/box3d-walking-hitch-2026-09-28.md).

const TICKS := 3200
const FREEZE_SECONDS := 6.0
const MONEY := 16000
const SEED := 20260926
const SHOWN := 12
## The target a tick is held to (Sid, 2026-09-28).
const TARGET_USEC := 6000
## From when the rays are asked: the round under way.
const RAYS_FROM_TICK := 500

enum { WARM, PARTS, RAYS }


func _initialize() -> void:
	_run()


func _run() -> void:
	if not Box3DDrops.available():
		print("PROFILE skipped: install the native addon with scripts/install_box3d.ps1")
		quit()
		return
	var paths := MapPaths.of("de_dust2")
	if not (FileAccess.file_exists(paths.nav_file) and DirAccess.dir_exists_absolute(paths.collision_dir)
			and ResourceLoader.exists(PlayerModel.AGENTS["T"]) and ResourceLoader.exists(PlayerModel.AGENTS["CT"])):
		print("PROFILE skipped: extracted Dust2 and player assets are required")
		quit()
		return
	await process_frame
	for what: int in [WARM, PARTS, RAYS]:
		await _play(what)
	quit()


func _play(what: int) -> void:
	seed(SEED)
	var scene := (load("res://maps/de_dust2/de_dust2.tscn") as PackedScene).instantiate() as PlayScene
	scene.game_mode = "Competitive"
	scene.team_size = 5
	scene.warmup_seconds = 120.0
	root.add_child(scene)
	var world := scene.world
	var mode := scene.mode as Competitive
	world.set_physics_process(false)
	world.initialize_drop_physics(scene, "box3d")
	# The ticks are run by hand, and the bodies posed after each.
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	await physics_frame
	await process_frame
	await physics_frame
	mode.match_state.rules.freeze_seconds = FREEZE_SECONDS
	mode.economy.rules.start_money = MONEY
	mode.match_state.end_warmup_on_next_tick()
	var events := PackedStringArray()
	world.game.events.listen_all(func(event: GameEvent) -> void: events.append(String(event.name)))
	var space := scene.get_world_3d().direct_space_state
	var rows: Array[Dictionary] = []
	var first := PackedFloat64Array()
	var again := PackedFloat64Array()
	var world_only := PackedFloat64Array()
	for tick in TICKS:
		events.clear()
		var t0 := Time.get_ticks_usec()
		world.begin_tick()
		var dt := SimClock.tick_seconds()
		var running := world.playing()
		var t1 := Time.get_ticks_usec()
		var commands := world.commands_for(running, dt)
		var t2 := Time.get_ticks_usec()
		var longest := 0
		var who := ""
		for i in running.size():
			if running[i].is_inside_tree():
				var before := Time.get_ticks_usec()
				var traces := running[i].traces
				running[i].run_command(commands[i], dt)
				var took := Time.get_ticks_usec() - before
				if took > longest:
					longest = took
					who = "%s (%d traces)" % [running[i].name, running[i].traces - traces]
		var t3 := Time.get_ticks_usec()
		world.end_tick()
		var t4 := Time.get_ticks_usec()
		rows.append({
			"tick": tick, "total": t4 - t0, "begin": t1 - t0, "commands": t2 - t1, "runs": t3 - t2, "end": t4 - t3,
			"longest": longest, "who": who, "events": ", ".join(events),
		})
		for player in world.players:
			if player.model != null and player.model.is_animating():
				player.model.step(SimClock.tick_seconds())
				if player.model.character_rig != null:
					player.model.character_rig.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
		if what == RAYS and tick >= RAYS_FROM_TICK:
			var asker := world.players[0]
			var from := asker.global_position + Vector3.UP * 64.0
			var to := from + Vector3(4000.0, 0.0, 0.0)
			var query := PhysicsRayQueryParameters3D.create(from, to, Hitscan.WORLD_LAYER | Hitbox.LAYER, [asker.get_rid()])
			query.collide_with_areas = true
			var plain := PhysicsRayQueryParameters3D.create(from, to, Hitscan.WORLD_LAYER, [asker.get_rid()])
			var r0 := Time.get_ticks_usec()
			PhysicsQueries.intersect_ray(space, query)
			var r1 := Time.get_ticks_usec()
			PhysicsQueries.intersect_ray(space, query)
			var r2 := Time.get_ticks_usec()
			PhysicsQueries.intersect_ray(space, plain)
			var r3 := Time.get_ticks_usec()
			first.append(float(r1 - r0))
			again.append(float(r2 - r1))
			world_only.append(float(r3 - r2))
	if what == PARTS:
		_show(rows, world)
	elif what == RAYS:
		var boxes := 0
		for player in world.players:
			boxes += player.hit_target.hitboxes().size()
		print("RAYS over %d ticks, %d players, %d hitboxes: the first ray that can meet a hitbox %.0f us (95th %.0f, worst %.0f); the same again, nothing having moved, %.0f us (95th %.0f); one that meets the world alone %.0f us" % [
			first.size(), world.players.size(), boxes, _mean(first), _at(first, 0.95), _at(first, 1.0),
			_mean(again), _at(again, 0.95), _mean(world_only)])
	scene.queue_free()
	await process_frame
	await process_frame
	await physics_frame


func _show(rows: Array[Dictionary], world: GameWorld) -> void:
	var totals := PackedFloat64Array()
	var over := 0
	for row in rows:
		totals.append(float(row["total"]))
		if int(row["total"]) > TARGET_USEC:
			over += 1
	print("WORST dust2's match, %d players, the bots thinking %s: %d ticks, mean %.2f ms, 95th %.2f, 99th %.2f; %d took more than %d ms" % [
		world.players.size(), "on worker threads" if world.think_on_threads else "in turn", rows.size(),
		_mean(totals) / 1000.0, _at(totals, 0.95) / 1000.0, _at(totals, 0.99) / 1000.0, over, TARGET_USEC / 1000])
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["total"]) > int(b["total"]))
	for i in mini(SHOWN, rows.size()):
		var row := rows[i]
		print("WORST tick %d: %.2f ms (begin %.2f, commands %.2f, the runs %.2f, end %.2f); the longest run %.2f ms, %s; events: %s" % [
			row["tick"], int(row["total"]) / 1000.0, int(row["begin"]) / 1000.0, int(row["commands"]) / 1000.0,
			int(row["runs"]) / 1000.0, int(row["end"]) / 1000.0, int(row["longest"]) / 1000.0, row["who"],
			row["events"] if row["events"] != "" else "none"])


static func _mean(values: PackedFloat64Array) -> float:
	var sum := 0.0
	for value in values:
		sum += value
	return sum / maxf(values.size(), 1.0)


static func _at(values: PackedFloat64Array, share: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(int(ceil(share * sorted.size())) - 1, 0, sorted.size() - 1)]
