extends "res://tests/run_box3d_match_checks.gd"

## Paired Dust2 Competitive 5v5 simulation timings, using extracted assets.
## Run each backend in its own otherwise idle headless process:
## godot --headless --path . --script scripts/profile_box3d_match.gd -- --physics box3d
## godot --headless --path . --script scripts/profile_box3d_match.gd -- --physics legacy
##
## Both use seed 20260926, 96 warmup ticks and the same 768-tick schedule:
## an AK drop, an HE throw, map routes and a staged bot engagement. Players
## remain immortal: the legacy comparison cannot create native ragdolls.
## Poses/velocities stay in Source inches; the native bridge handles metres.
## Only GameWorld.step() is timed, including commands, movement, gameplay
## and native stepping. Animation poses are refreshed outside the interval;
## rendering, audio/UI callbacks and Godot's automatic server step are excluded.
##
## The checks it is built on compare as they go, every step of the movement
## run by the script and by the native code and every hitbox set looked
## over: a profile turns both off, and times the game's own tick.
## `--movement script` has the script run the movement's step.


func _init() -> void:
	super()
	Box3DQueries.check_sets = false
	PlayerBody.check_steps = false


func _initialize() -> void:
	if not _assets_available():
		print("PROFILE skipped: extracted Dust2 and player assets are required")
		quit(1)
		return
	var backend := GameWorld.configured_drop_physics()
	if backend == "box3d" and not Box3DDrops.available():
		print("PROFILE skipped: install the native addon with scripts/install_box3d.ps1")
		quit(1)
		return
	await process_frame
	await _load_match(backend)
	var local := mode.player as PlayerSim
	var native_before := PhysicsQueries.native_queries
	var legacy_before := PhysicsQueries.legacy_queries
	for tick in TICKS:
		if tick == TICKS - 128:
			_stage_engagement()
		if tick == 32:
			local.equip(WeaponLibrary.ak47())
			world.game.command(local.userid, "drop")
		if tick == 33:
			local.equip(WeaponLibrary.ak47())
		if tick == 64:
			local.inventory.add(GrenadeRules.HE)
			world.game.command(local.userid, "throw %s 1" % GrenadeRules.HE)
		_tick()
	_report_costs("dust2-5v5-" + backend)
	print("PROFILE movement=%s" % _movement())
	var shots := 0
	for bot in mode.bots:
		shots += bot.rounds_fired
	print("PROFILE workload seed=20260926 shots=%d native_queries=%d legacy_queries=%d alive=%d" % [
		shots, PhysicsQueries.native_queries - native_before, PhysicsQueries.legacy_queries - legacy_before,
		mode.match_state.alive_on("T") + mode.match_state.alive_on("CT")])
	scene.free()
	await process_frame
	quit(0)


## What ran the movement's step in this run.
func _movement() -> String:
	if not PlayerBody.native_steps:
		return "script"
	if not PlayerBody.native_built():
		return "script (the native code: %s)" % PlayerBody.native_missing
	for player in world.players:
		if player.get("_mover") != null:
			return "native"
	return "script (nobody's step could be run by the native code)"
