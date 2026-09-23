extends SceneTree

## Checks the match: warmup, freeze time, a round won on eliminations or on
## time, nobody coming back mid-round, survivors keeping their armour, the
## score staying with the team when the sides swap at half time, the clinch
## at 13, overtime at 12-12 and the draw at 15-15, friendly fire at CS2's
## third, teammates being solid, and watching a teammate once dead.
##
##   godot --headless --path . --script tests/run_match_checks.gd
##
## Needs nothing extracted: players without their model wear the standard
## boxes. The match is moved on by hand (MatchState.tick) with simulation
## times the checks choose, so two minutes of warmup take no time at all.

const DT := 1.0 / 128.0
const SECOND := 1_000_000

const MATCH_FILES := [
	"res://src/match/match_state.gd",
	"res://src/match/match_rules.gd",
]

const T_SPAWNS := [
	{"position": Vector3(0.0, 0.0, 0.0), "yaw": 0.0, "priority": 0},
	{"position": Vector3(128.0, 0.0, 0.0), "yaw": 0.0, "priority": 0},
	{"position": Vector3(256.0, 0.0, 0.0), "yaw": 0.0, "priority": 1},
]
const CT_SPAWNS := [
	{"position": Vector3(0.0, 0.0, -2000.0), "yaw": 180.0, "priority": 0},
	{"position": Vector3(128.0, 0.0, -2000.0), "yaw": 180.0, "priority": 0},
	{"position": Vector3(256.0, 0.0, -2000.0), "yaw": 180.0, "priority": 1},
]

var _failures: int = 0
var _checks: int = 0
var _world: Node3D
var _tick: int = 100_000


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_the_match_reads_only_the_simulation()
	_test_the_rules_are_cs2s()
	_test_the_hud_lines()

	_world = Node3D.new()
	root.add_child(_world)
	_build_floor()
	await physics_frame
	await physics_frame

	await _test_a_round_from_warmup_to_its_end()
	await _test_the_score_stays_with_the_team()
	await _test_overtime()
	await _test_friendly_fire()
	await _test_teammates_are_solid()
	await _test_watching_a_teammate()
	await _test_a_bot_spawns_where_it_is_put()
	_report()


# --- What the match may read -----------------------------------------------

func _test_the_match_reads_only_the_simulation() -> void:
	var keys := RegEx.create_from_string("(?<![A-Za-z_])Input\\.")
	var clock := RegEx.create_from_string("Time\\.get_ticks|Time\\.get_unix")
	for path: String in MATCH_FILES:
		var code := ""
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if not line.strip_edges().begins_with("#"):
				code += line + "\n"
		_check(not code.is_empty(), "%s is there to read" % path.get_file())
		_check(keys.search(code) == null, "%s never reads the keys" % path.get_file())
		_check(clock.search(code) == null, "%s never reads the wall clock" % path.get_file())


func _test_the_rules_are_cs2s() -> void:
	var rules := MatchRules.new()
	_check(
		rules.warmup_seconds == 120.0 and rules.freeze_seconds == 15.0 and rules.round_seconds == 115.0
			and rules.round_restart_seconds == 7.0 and rules.halftime_seconds == 15.0,
		"CS2's times: 120 s warmup, 15 s freeze, 1:55 rounds, 7 s between them, 15 s at half time"
	)
	_check(
		rules.max_rounds == 24 and rules.can_clinch and rules.overtime and rules.overtime_rounds == 6
			and rules.overtime_limit == 1,
		"MR12 with the clinch, one MR3 overtime"
	)
	_check(is_equal_approx(rules.friendly_fire_bullets, 0.33), "a teammate's round does a third of its damage")


func _test_the_hud_lines() -> void:
	_check(
		GameHud.clock_text(115.0) == "1:55" and GameHud.clock_text(0.2) == "0:01" and GameHud.clock_text(0.0) == "0:00",
		"the clock reads 1:55, 0:01 with a fifth of a second left, and 0:00 only when time is out"
	)


# --- A round ----------------------------------------------------------------

## Warmup: everyone at a spawn, coming back when they die, nothing counting.
## Then round 1: fresh, held still in freeze time, able to look round but not
## to move or fire. Then played: the clock runs out and the CTs have it.
## Round 2: a T dies and stays dead, even past the respawn time, and their
## side, all dead, loses it. Round 3: they are back, whole, at a T spawn; the
## CT who lived keeps the armour they had left and is healed.
func _test_a_round_from_warmup_to_its_end() -> void:
	var t := _new_player(Vector3(0.0, 0.0, 600.0), "T")
	var ct := _new_player(Vector3(0.0, 0.0, -2600.0), "CT")
	var game := _new_match([t, ct], MatchRules.new())
	var now := 10 * SECOND
	game.start(now)

	_check(game.phase == MatchState.Phase.WARMUP, "the match opens in warmup")
	_check(
		_at_a_spawn(t, T_SPAWNS) and _at_a_spawn(ct, CT_SPAWNS),
		"with each player at one of their side's spawn points (%s, %s)" % [t.global_position, ct.global_position]
	)
	_check(t.respawns and not t.frozen, "free to move, and coming back after a death")
	_kill(t)
	game.tick(now + SECOND)
	_check(game.phase == MatchState.Phase.WARMUP and game.rounds_played == 0, "a death in warmup ends nothing")

	now += 120 * SECOND
	game.tick(now)
	_check(
		game.phase == MatchState.Phase.FREEZE and game.round_number == 1 and game.score("T") == 0 and game.score("CT") == 0,
		"after 120 s round 1 starts in freeze time, 0 to 0"
	)
	_check(t.alive and t.hit_target.health == 100.0 and _at_a_spawn(t, T_SPAWNS), "everyone starts it alive at a spawn")
	_check(t.frozen and ct.frozen and not t.respawns, "held still, and nobody comes back from a death now")
	_check(
		t.weapon != null and t.weapon.data.display_name == "AK-47" and ct.weapon != null and ct.weapon.data.display_name == "M4A1-S",
		"the Ts with the AK-47 and the CTs with the M4A1-S, until they can buy"
	)

	var from := t.global_position
	var fired := t.rounds_fired
	for i in 64:
		var cmd := _command(Vector2(0.0, 1.0), UserCmd.ATTACK | UserCmd.JUMP)
		cmd.yaw_degrees = 30.0
		cmd.steps.append(UserCmd.SubtickStep.new(UserCmd.ATTACK, true, 0.5, 30.0, 0.0))
		cmd.steps.append(UserCmd.SubtickStep.new(UserCmd.JUMP, true, 0.5, 30.0, 0.0))
		t.run_command(cmd, DT)
	_check(
		Vector2(t.global_position.x - from.x, t.global_position.z - from.z).length() < 0.01
			and t.global_position.y - from.y < 0.5,
		"freeze time: running and jumping go nowhere (moved %.2f across)" % Vector2(t.global_position.x - from.x, t.global_position.z - from.z).length()
	)
	_check(t.rounds_fired == fired, "and the trigger fires nothing")
	_check(is_equal_approx(t.yaw_degrees, 30.0), "but the player looks where the mouse goes")

	now += 15 * SECOND
	game.tick(now)
	_check(game.phase == MatchState.Phase.LIVE and not t.frozen, "15 s later the round is live")
	_run_forward(t, 32)
	_check(t.global_position.distance_to(from) > 20.0, "and the player can move")
	game.tick(now + 114 * SECOND)
	_check(game.phase == MatchState.Phase.LIVE, "at 1:54 in it is still being played")
	now += 115 * SECOND
	game.tick(now)
	_check(
		game.phase == MatchState.Phase.ROUND_END and game.last_winner == "CT"
			and game.last_reason == MatchState.Reason.TIME_RAN_OUT and game.score("CT") == 1,
		"at 1:55 time runs out, and with no bomb the CTs win it"
	)
	game.tick(now + 6 * SECOND)
	_check(game.phase == MatchState.Phase.ROUND_END, "the next round waits 7 s")
	now += 7 * SECOND
	game.tick(now)
	_check(game.phase == MatchState.Phase.FREEZE and game.round_number == 2, "then round 2 begins")

	now += 15 * SECOND
	game.tick(now)
	ct.hit_target.apply_damage(40.0, &"chest", 0.5)
	var ct_armor := ct.hit_target.armor
	_kill(t)
	for i in 3 * 128 + 64:
		t.run_command(_command(), DT)
	_check(not t.alive, "a player killed in a round stays dead past the respawn time")
	game.tick(now + SECOND)
	_check(
		game.phase == MatchState.Phase.ROUND_END and game.last_winner == "CT"
			and game.last_reason == MatchState.Reason.T_ELIMINATED and game.score("CT") == 2,
		"every T dead: the CTs win the round"
	)
	now += 8 * SECOND
	game.tick(now)
	_check(t.alive and t.hit_target.health == 100.0 and _at_a_spawn(t, T_SPAWNS), "the next round they are back, whole, at a T spawn")
	_check(
		ct.hit_target.health == 100.0 and is_equal_approx(ct.hit_target.armor, ct_armor) and ct_armor < 100.0,
		"and the CT who lived is healed and keeps the armour they had left (%.0f)" % ct.hit_target.armor
	)
	_check(t.hit_target.armor == 100.0, "the one who died has their armour back as it was")
	await _clear([t, ct, game])


# --- The score --------------------------------------------------------------

## The Ts win 8 of the first 12. The pause after the 12th is half time, 15 s,
## and then everyone has swapped sides: the team that started T is on CT with
## its 8. It wins 5 more and the match is over at 13, the players still.
func _test_the_score_stays_with_the_team() -> void:
	var a := _new_player(Vector3(0.0, 0.0, 600.0), "T")
	var b := _new_player(Vector3(0.0, 0.0, -2600.0), "CT")
	var rules := MatchRules.new()
	rules.warmup_seconds = 0.0
	var game := _new_match([a, b], rules)
	var now := 10 * SECOND
	game.start(now)
	_check(game.phase == MatchState.Phase.FREEZE and game.round_number == 1, "without warmup the match starts at round 1")

	var halftime_pause := 0
	for i in 12:
		now = _play_round(game, now, "T" if i < 8 else "CT")
		if i == 11:
			halftime_pause = game.phase_ends_usec - now
			_check(game.swapping_next(), "after round 12 the sides swap")
		now = _next_round(game, now)
	_check(halftime_pause == 15 * SECOND, "and the pause before round 13 is half time's 15 s (%.1f)" % (halftime_pause / float(SECOND)))
	_check(a.team == "CT" and b.team == "T", "everyone is on the other side")
	_check(a.hit_target.team == "CT", "and their hitboxes say so")
	_check(game.score("CT") == 8 and game.score("T") == 4, "the 8 went with the team to CT: 8 to 4")
	await physics_frame
	_check(
		a.hit_target.hitboxes().size() == 4 and a.hit_target.get_child_count() == 4
			and a.hit_target.hitboxes().all(func(box: Hitbox) -> bool: return box.collision_layer == Hitbox.LAYER),
		"the old side's hitboxes are gone and the new side's are on, one set (%d)" % a.hit_target.get_child_count()
	)
	_check(a.weapon.data.display_name == "M4A1-S", "and the team now on CT has the M4A1-S")

	for i in 4:
		now = _play_round(game, now, "CT")
		now = _next_round(game, now)
	_check(game.phase != MatchState.Phase.OVER and game.score("CT") == 12, "at 12 the match goes on")
	now = _play_round(game, now, "CT")
	_check(
		game.phase == MatchState.Phase.OVER and game.winner == "CT" and game.score("CT") == 13,
		"at 13 it is over: the team that started T wins, 13 to %d" % game.score("T")
	)
	_check(a.frozen and b.frozen, "and everyone stands still")
	game.tick(now + 60 * SECOND)
	_check(game.phase == MatchState.Phase.OVER and game.round_number == 17, "no round follows it")
	await _clear([a, b, game])


## 12-12 goes to overtime without a swap; its first half is three rounds and
## the sides swap after it; 3-3 in it, with one overtime allowed, is a draw at
## 15-15. With them unlimited, the next begins with the sides swapped again,
## and 4 of its rounds wins it. Rounds here are given to a team (the player
## on it), whichever side it is on.
func _test_overtime() -> void:
	var a := _new_player(Vector3(0.0, 0.0, 600.0), "T")
	var b := _new_player(Vector3(0.0, 0.0, -2600.0), "CT")
	var rules := MatchRules.new()
	rules.warmup_seconds = 0.0
	var game := _new_match([a, b], rules)
	var now := 10 * SECOND
	game.start(now)
	for i in 24:
		now = _play_round(game, now, a if i % 2 == 0 else b)
		if i < 23:
			now = _next_round(game, now)
	_check(game.phase == MatchState.Phase.ROUND_END and game.score("T") == 12, "12 to 12 after 24 rounds, and the match goes on")
	_check(not game.swapping_next(), "into overtime on the sides the second half ended on")
	now = _next_round(game, now)
	_check(game.in_overtime() and a.team == "CT", "round 25 is overtime")
	for i in 3:
		now = _play_round(game, now, a if i % 2 == 0 else b)
		if i == 2:
			_check(game.swapping_next(), "the sides swap after overtime's third round")
		now = _next_round(game, now)
	_check(a.team == "T", "and are swapped for its second half")
	for i in 3:
		now = _play_round(game, now, b if i % 2 == 0 else a)
		if i < 2:
			now = _next_round(game, now)
	_check(
		game.phase == MatchState.Phase.OVER and game.winner == "" and game.score("T") == 15 and game.score("CT") == 15,
		"15 to 15 at the end of the one overtime is a draw"
	)
	await _clear([game])

	rules = MatchRules.new()
	rules.warmup_seconds = 0.0
	rules.overtime_limit = 0
	a.change_team("T")
	b.change_team("CT")
	game = _new_match([a, b], rules)
	game.start(now)
	for i in 30:
		now = _play_round(game, now, a if i % 2 == 0 else b)
		if i == 29:
			_check(game.swapping_next(), "unlimited, 15 to 15 swaps the sides for a second overtime")
		now = _next_round(game, now)
	for i in 4:
		now = _play_round(game, now, a)
		if i < 3:
			now = _next_round(game, now)
	_check(
		game.phase == MatchState.Phase.OVER and game.winner == a.team and game.score(a.team) == 19
			and game.score(b.team) == 15,
		"and 4 of its 6 wins it, 19 to %d, across the swap in its middle" % game.score(b.team)
	)
	await _clear([a, b, game])


# --- Between players --------------------------------------------------------

## A round from your own side does a third of what it would do to the other
## side, before armour.
func _test_friendly_fire() -> void:
	var victim := _new_player(Vector3(3000.0, 0.0, 0.0), "T")
	victim.hit_target.wear(0.0, false)
	victim.hit_target.reset()
	await physics_frame
	await physics_frame
	var ak := WeaponLibrary.ak47()
	var shot := Weapon.Shot.new()
	shot.origin = victim.global_position + Vector3(300.0, 50.0, 0.0)
	shot.direction = Vector3.LEFT
	var space := victim.get_world_3d().direct_space_state
	var enemy_round := Hitscan.fire_at(space, shot, ak, [], "CT", 0.33)
	victim.hit_target.reset()
	var team_round := Hitscan.fire_at(space, shot, ak, [], "T", 0.33)
	_check(
		enemy_round.damage > 20.0 and absf(team_round.damage - enemy_round.damage * 0.33) < 0.01,
		"a teammate's round does a third: %.1f of %.1f" % [team_round.damage, enemy_round.damage]
	)
	await _clear([victim])


## Running into a teammate stops you at their hull; once they are dead, you
## walk on through where they fell.
func _test_teammates_are_solid() -> void:
	var runner := _new_player(Vector3(5000.0, 0.0, 0.0), "T")
	var mate := _new_player(Vector3(5000.0, 0.0, -100.0), "T")
	await physics_frame
	await physics_frame
	_run_forward(runner, 128)
	_check(
		runner.global_position.z > mate.global_position.z + 31.0,
		"running into a teammate stops at their hull (%.1f units apart)" % (runner.global_position.z - mate.global_position.z)
	)
	_kill(mate)
	await physics_frame
	_run_forward(runner, 128)
	_check(runner.global_position.z < mate.global_position.z - 100.0, "a dead teammate is no longer in the way")
	await _clear([runner, mate])


## Dead with no respawn: two seconds on your own body, then a living
## teammate's eyes, never the other side's. Fire moves on to the next one,
## jump takes the camera behind them, and when the one watched dies the next
## one living is watched.
func _test_watching_a_teammate() -> void:
	var dead := _new_player(Vector3(-3000.0, 0.0, 0.0), "T")
	var first := _new_player(Vector3(-3000.0, 0.0, 300.0), "T")
	var second := _new_player(Vector3(-3000.0, 0.0, 600.0), "T")
	var enemy := _new_player(Vector3(-3000.0, 0.0, -600.0), "CT")
	dead.respawns = false
	_kill(dead)
	var died := SimClock.current_tick()
	var cmd := UserCmd.new()
	cmd.tick = died + 128
	dead.run_command(cmd, DT)
	_check(dead.observing == null, "one second on, the camera is still on your own body")
	cmd = UserCmd.new()
	cmd.tick = died + 2 * 128 + 8
	dead.run_command(cmd, DT)
	var watched := dead.observing
	_check(watched == first or watched == second, "two seconds on, a living teammate is watched")
	cmd = UserCmd.new()
	cmd.tick = died + 2 * 128 + 9
	cmd.steps.append(UserCmd.SubtickStep.new(UserCmd.ATTACK, true, 0.2, 0.0, 0.0))
	dead.run_command(cmd, DT)
	_check(dead.observing != watched and dead.observing != enemy and dead.observing.team == "T", "fire moves on to the other teammate")
	cmd = UserCmd.new()
	cmd.tick = died + 2 * 128 + 10
	cmd.steps.append(UserCmd.SubtickStep.new(UserCmd.ATTACK, true, 0.2, 0.0, 0.0))
	dead.run_command(cmd, DT)
	_check(dead.observing == watched, "and round again, never to the other side")
	cmd = UserCmd.new()
	cmd.tick = died + 2 * 128 + 11
	cmd.steps.append(UserCmd.SubtickStep.new(UserCmd.JUMP, true, 0.2, 0.0, 0.0))
	dead.run_command(cmd, DT)
	_check(dead.observing_chase and dead.observing == watched, "jump takes the camera behind them")
	_kill(watched)
	cmd = UserCmd.new()
	cmd.tick = died + 2 * 128 + 12
	dead.run_command(cmd, DT)
	_check(dead.observing != null and dead.observing != watched and dead.observing.alive, "the one watched dies: the next one living is watched")
	dead.spawn_at(Vector3(-3000.0, 0.0, 0.0), 0.0)
	_check(dead.alive and dead.observing == null, "spawned for the next round, nobody is watched")
	await _clear([dead, first, second, enemy])


## A bot the match spawns on its route sets off for the point after it, and
## a dead one comes back at the spawn it was given, not its route's start.
func _test_a_bot_spawns_where_it_is_put() -> void:
	var bot := (load("res://src/bots/bot.tscn") as PackedScene).instantiate() as Bot
	bot.team = "CT"
	bot.route = PackedVector3Array([Vector3(-5000, 0, 0), Vector3(-5000, 0, 400), Vector3(-5000, 0, 800)])
	bot.position = Vector3(-5000.0, 0.0, 0.0)
	_world.add_child(bot)
	bot.spawn_at(Vector3(-5000.0, 0.0, 400.0), 90.0)
	_check(bot._next == 2 and is_equal_approx(bot.yaw_degrees, 90.0), "spawned on its route's second point, it heads for the third")
	_kill(bot)
	bot.spawn_at(Vector3(-5000.0, 0.0, 800.0), 0.0)
	_check(
		bot.alive and bot.global_position.is_equal_approx(Vector3(-5000.0, 0.0, 800.0)) and bot._next == 0,
		"dead, it comes back at the spawn it is given (%s)" % bot.global_position
	)
	await _clear([bot])


# --- Helpers ----------------------------------------------------------------

func _new_match(players: Array, rules: MatchRules) -> MatchState:
	var game := MatchState.new()
	game.rules = rules
	game.spawns = {"T": T_SPAWNS.duplicate(), "CT": CT_SPAWNS.duplicate()}
	_world.add_child(game)
	# Moved on by hand, with the times the checks choose.
	game.set_physics_process(false)
	for player: PlayerSim in players:
		game.add_player(player)
	return game


## Plays a round to its end, won by this side, or by the team this player
## is on; returns the time it ended.
func _play_round(game: MatchState, now: int, winner: Variant) -> int:
	var side: String = winner.team if winner is PlayerSim else winner
	if game.phase == MatchState.Phase.FREEZE:
		now = game.phase_ends_usec
		game.tick(now)
	now += SECOND
	game.end_round(side, MatchState.Reason.T_ELIMINATED if side == "CT" else MatchState.Reason.CT_ELIMINATED, now)
	return now


## From a round's end to the next one's start.
func _next_round(game: MatchState, now: int) -> int:
	if game.phase != MatchState.Phase.ROUND_END:
		return now
	now = game.phase_ends_usec
	game.tick(now)
	return now


func _at_a_spawn(player: PlayerSim, spawns: Array) -> bool:
	for spawn: Dictionary in spawns:
		if player.global_position.is_equal_approx(spawn["position"]):
			return true
	return false


func _kill(player: PlayerSim) -> void:
	player.hit_target.apply_damage(1000.0, &"chest", 1.0)


func _command(move: Vector2 = Vector2.ZERO, buttons: int = 0) -> UserCmd:
	var cmd := UserCmd.new()
	_tick += 1
	cmd.tick = _tick
	cmd.move = move
	cmd.buttons = buttons
	return cmd


func _run_forward(player: PlayerSim, ticks: int) -> void:
	for i in ticks:
		player.run_command(_command(Vector2(0.0, 1.0)), DT)


func _clear(nodes: Array) -> void:
	for node: Node in nodes:
		if is_instance_valid(node):
			node.queue_free()
	await physics_frame


func _build_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(16384.0, 32.0, 16384.0)
	shape.shape = box
	shape.position = Vector3(0.0, -16.0, 0.0)
	floor_body.add_child(shape)
	_world.add_child(floor_body)


## A player in the simulation with nothing drawing it, standing on the floor.
func _new_player(at: Vector3, team: String) -> PlayerSim:
	var player := PlayerSim.new()
	player.team = team
	player.collision_layer = PlayerSim.PLAYER_LAYER
	var hull := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(32.0, 72.0, 32.0)
	hull.shape = box
	hull.position = Vector3(0.0, 36.0, 0.0)
	player.add_child(hull)
	player.position = at
	_world.add_child(player)
	player.place(at, 0.0)
	for i in 4:
		player.run_command(_command(), DT)
	return player


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("  ok   %s" % description)
	else:
		_failures += 1
		print("  FAIL %s" % description)


func _report() -> void:
	if _failures == 0:
		print("%d match checks passed." % _checks)
		quit(0)
	else:
		print("%d of %d match checks failed." % [_failures, _checks])
		quit(1)
