extends "res://tests/check_suite.gd"

## Checks that dust2's match is the same match with the bots thinking on
## the worker threads as with them thinking in turn (GameWorld.commands_for):
## Competitive, five a side, nine of them bots with money to buy with, the
## same seed, played for fifty seconds of game each way. Every player is
## where it was, facing as it faced, has fired as often, is as hurt, as rich
## and holds the same gun, at every tick. tests/run_bot_think_checks.gd
## checks the same of a fight on made-up ground, without the map.
##
## Where they differ it plays the match in turn again, to say whether the
## match is the same twice at all: if it is not, something in it is no
## longer seeded, and the threads are not what differs.
##
##   godot --headless --path . --script tests/run_dust2_think_checks.gd
##
## Needs dust2, its nav mesh and the player models extracted, and the Box3D
## addon; it skips without them, as in CI.

const TICKS := 3200
const SEED := 20260926
const FREEZE_SECONDS := 6.0
const MONEY := 16000
## What everyone spawns with, which is not bought.
const SPAWNED_WITH: Array[String] = ["weapon_glock", "weapon_hkp2000", "weapon_usp_silencer", "weapon_knife"]


func _initialize() -> void:
	_run()


func _print_passes() -> bool:
	return true


func _run() -> void:
	if not Box3DDrops.available():
		_skip("dust2-think", "Box3D native addon is not installed; run scripts/install_box3d.ps1")
		return
	var paths := MapPaths.of("de_dust2")
	if not (FileAccess.file_exists(paths.nav_file) and DirAccess.dir_exists_absolute(paths.collision_dir)
			and ResourceLoader.exists(PlayerModel.AGENTS["T"]) and ResourceLoader.exists(PlayerModel.AGENTS["CT"])):
		_skip("dust2-think", "dust2, its nav mesh and the player models must be extracted for this check")
		return
	await process_frame
	var in_turn := await _play(false)
	var apart := await _play(true)
	_check(int(in_turn["shots"]) > 0 and int(in_turn["dead"]) > 0 and int(in_turn["bought"]) > 0,
		"in fifty seconds of dust2's match the bots buy, fight and die (%d guns bought, %d rounds fired, %d dead)" % [
			in_turn["bought"], in_turn["shots"], in_turn["dead"]])
	var differs := _first_difference(in_turn["ticks"], apart["ticks"])
	var why := ""
	if differs >= 0:
		var again := await _play(false)
		var twice := _first_difference(in_turn["ticks"], again["ticks"])
		why = " (tick %d; played in turn again it %s)" % [differs,
			"is the same, so it is the threads" if twice < 0 else "differs from tick %d too, so the match is not the same twice" % twice]
		_show(in_turn["ticks"], apart["ticks"], differs)
	_check(differs < 0 and (in_turn["ticks"] as PackedStringArray).size() == TICKS,
		"thinking on the threads or in turn, every player is where it was, as it was, at every tick%s" % why)
	_finish("dust2-think")


## The first tick two plays differ at, or -1.
static func _first_difference(one: PackedStringArray, other: PackedStringArray) -> int:
	for i in mini(one.size(), other.size()):
		if one[i] != other[i]:
			return i
	return -1 if one.size() == other.size() else mini(one.size(), other.size())


## Who differed at a tick, either way.
static func _show(one: PackedStringArray, other: PackedStringArray, at: int) -> void:
	if at >= one.size() or at >= other.size():
		return
	var left := one[at].split("; ")
	var right := other[at].split("; ")
	for i in mini(left.size(), right.size()):
		if left[i] != right[i]:
			print("  in turn        %s\n  on the threads %s" % [left[i], right[i]])


## The match, with the bots thinking on the worker threads or in turn: what
## every player was at every tick, the rounds fired, the dead, and the guns
## bought.
func _play(apart: bool) -> Dictionary:
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
	world.think_on_threads = apart
	# The ticks are run by hand, and the bodies posed after each.
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	await physics_frame
	await process_frame
	await physics_frame
	mode.match_state.rules.freeze_seconds = FREEZE_SECONDS
	mode.economy.rules.start_money = MONEY
	mode.match_state.end_warmup_on_next_tick()
	var ticks := PackedStringArray()
	for tick in TICKS:
		world.step()
		for player in world.players:
			if player.model != null and player.model.is_animating():
				player.model.step(SimClock.tick_seconds())
				if player.model.character_rig != null:
					player.model.character_rig.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
		var line := PackedStringArray()
		for player in world.players:
			line.append("%s %.3f %.3f %.3f %.2f %.2f %d %s %.0f %d %s" % [
				player.name, player.global_position.x, player.global_position.y, player.global_position.z,
				player.yaw_degrees, player.pitch_degrees, player.rounds_fired, player.alive,
				player.hit_target.health, int(world.game.query(&"money", [player.userid], 0)),
				player.weapon.data.item_class if player.weapon != null else "-"])
		ticks.append("; ".join(line))
	var shots := 0
	var dead := 0
	var bought := 0
	for player in world.players:
		shots += player.rounds_fired
		if not player.alive:
			dead += 1
		if player.weapon != null and player.weapon.data.item_class not in SPAWNED_WITH:
			bought += 1
	scene.queue_free()
	await process_frame
	await process_frame
	await physics_frame
	return {"ticks": ticks, "shots": shots, "dead": dead, "bought": bought}
