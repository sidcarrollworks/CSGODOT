extends "res://tests/check_suite.gd"

## CS2's scoreboard on Tab: each player's numbers for the match as the
## server counts them (MatchStats), the rounds' history the timeline is
## drawn from (MatchState.history), and the board that shows them
## (Scoreboard, from GameHud).
##
##   godot --headless --path . --script tests/run_scoreboard_checks.gd
##
## Needs nothing extracted. How the board looks beside CS2's is Sid's check
## (the pull request says what to compare).

var _game: GameSystems
var _stats: MatchStats
var _state: MatchState
var _ids := {}


func _initialize() -> void:
	root.size = Vector2i(1920, 1080)
	await process_frame
	_set_up()
	_test_counting()
	_test_what_does_not_count()
	_test_rows()
	_test_history()
	_test_timeline()
	await _test_the_board()
	_test_the_key()
	_tear_down()
	await process_frame
	_finish("scoreboard")


func _set_up() -> void:
	_game = GameSystems.new()
	_stats = MatchStats.new()
	_game.add_system(_stats)
	_state = MatchState.new()
	_state.rules = MatchRules.new()
	root.add_child(_state)
	for who in ["you", "mate", "efe", "uri", "walt"]:
		var sim := PlayerSim.new()
		sim.name = who
		sim.team = "T" if who in ["you", "mate"] else "CT"
		root.add_child(sim)
		sim.userid = _game.add_player(sim)
		_state.add_player(sim)
		_ids[who] = sim.userid


func _tear_down() -> void:
	_state.free()
	for sim in root.get_children():
		if sim is PlayerSim:
			sim.free()


func _sim(who: String) -> PlayerSim:
	for sim in _state.players:
		if sim.userid == _ids[who]:
			return sim
	return null


func _hurt(attacker: String, victim: String, damage: int) -> void:
	_game.events.send(&"player_hurt", {"userid": _ids[victim], "attacker": _ids.get(attacker, GameEvents.NOBODY),
		"dmg_health": damage}, 0)


func _kill(attacker: String, victim: String, headshot: bool = false, assister: String = "") -> void:
	_game.events.send(&"player_death", {"userid": _ids[victim], "attacker": _ids.get(attacker, GameEvents.NOBODY),
		"headshot": headshot, "assister": _ids.get(assister, GameEvents.NOBODY), "weapon": "weapon_ak47"}, 0)


func _test_counting() -> void:
	_hurt("you", "uri", 100)
	_kill("you", "uri", true, "mate")
	_hurt("you", "efe", 27)
	_hurt("you", "walt", 100)
	_kill("you", "walt", false)
	_hurt("efe", "you", 100)
	_kill("efe", "you")
	_game.events.send(&"round_mvp", {"userid": _ids["efe"], "reason": 1}, 0)
	_game.events.flush()
	var you := _stats.of(_ids["you"])
	_check_equal([you["kills"], you["deaths"], you["assists"], you["headshots"], you["damage"]], [2, 1, 0, 1, 227],
		"you: two kills, one death, one headshot, 227 damage to enemies")
	_check_equal(MatchStats.headshot_percent(you), 50, "HS% is headshot kills over kills: 50")
	_check_equal(_stats.of(_ids["mate"])["assists"], 1, "the assister gets the assist")
	_check_equal(_stats.of(_ids["efe"])["mvps"], 1, "round_mvp counts an MVP")
	_check_equal(_stats.of(_ids["uri"])["deaths"], 1, "Uri died once")
	_check_equal(MatchStats.headshot_percent(MatchStats.ZERO), 0, "no kills: 0%, not a division by nothing")
	var copy := _stats.of(_ids["you"])
	copy["kills"] = 99
	_check_equal(_stats.of(_ids["you"])["kills"], 2, "of() hands out a copy")


func _test_what_does_not_count() -> void:
	_hurt("you", "mate", 50)
	_kill("you", "mate")
	_game.events.flush()
	var you := _stats.of(_ids["you"])
	_check_equal(you["damage"], 227, "damage to a teammate is not DMG")
	_check_equal(you["kills"], 1, "killing a teammate takes a kill away (CS:GO's rule)")
	_kill("walt", "walt")
	_kill("", "efe")
	_game.events.flush()
	_check_equal(_stats.of(_ids["walt"])["kills"], -1, "and so does killing yourself")
	_check_equal(_stats.of(_ids["walt"])["deaths"], 2, "a death all the same")
	_check_equal(_stats.of(_ids["efe"])["deaths"], 1, "the world's kill is a death and nobody's kill")


func _test_rows() -> void:
	var economy := Economy.new()
	_game.add_system(economy)
	economy.set_money(_ids["you"], 16000)
	economy.set_money(_ids["efe"], 2800)
	_sim("uri").alive = false
	var rows := Scoreboard.rows_for(_state, _stats, economy, _sim("you"), _ids["mate"])
	var names := func(side: String) -> Array:
		return rows[side].map(func(row: Scoreboard.Row) -> String: return row.name)
	_check_equal(names.call("T"), ["you", "mate"], "each side's rows: yours, the most damage first")
	var ct: Array = names.call("CT")
	_check_equal(ct[0], "efe", "Efe first of the counter-terrorists: 100 damage")
	_check_equal(ct.size(), 3, "every counter-terrorist has a row")
	var you: Scoreboard.Row = rows["T"][0]
	var mate: Scoreboard.Row = rows["T"][1]
	var efe: Scoreboard.Row = rows["CT"][0]
	_check(you.you and not mate.you, "your own row is marked")
	_check_equal(you.money, 16000, "your team's money is shown")
	_check_equal(efe.money, -1, "the other team's is not, as CS2's server sends -1")
	_check_equal(mate.status, "c4", "your team's carrier shows the C4")
	var uri: Scoreboard.Row
	for row: Scoreboard.Row in rows["CT"]:
		if row.name == "uri":
			uri = row
	_check(uri.status == "dead" and not uri.alive, "the dead show the skull")
	var rows_as_ct := Scoreboard.rows_for(_state, _stats, economy, _sim("efe"), _ids["mate"])
	_check_equal(rows_as_ct["T"][1].status, "", "the other side's carrier shows nothing")
	# Competitive's order past damage: kills, MVPs, assists, fewer deaths,
	# who joined first.
	var a := Scoreboard.Row.new()
	var b := Scoreboard.Row.new()
	a.damage = 100
	b.damage = 100
	a.kills = 1
	b.kills = 2
	_check(Scoreboard.before(b, a) and not Scoreboard.before(a, b), "equal damage: more kills first")
	b.kills = 1
	b.deaths = 3
	a.deaths = 1
	_check(Scoreboard.before(a, b), "then fewer deaths")
	b.deaths = 1
	a.joined = 2
	b.joined = 1
	_check(Scoreboard.before(b, a), "then who joined first")
	_sim("uri").alive = true


func _test_history() -> void:
	_state.phase = MatchState.Phase.LIVE
	_state.end_round("CT", MatchState.Reason.TIME_RAN_OUT, 0)
	_state.phase = MatchState.Phase.LIVE
	_state.end_round("T", MatchState.Reason.BOMB_EXPLODED, 0)
	_check_equal(_state.history.size(), 2, "each round played goes in the history")
	_check_equal(_state.history[0], {"team": "CT", "side": "CT", "reason": "TargetSaved"},
		"with the team that won (by the side it started on), the side it won on, and why")
	_check_equal(_state.history[1]["reason"], "TargetBombed", "the second: the bomb")


func _test_timeline() -> void:
	var period := Scoreboard.period_of(_state)
	_check_equal(period, Vector2i(0, 24), "the regulation's 24 rounds on the timeline")
	var columns := Scoreboard.timeline(_state, period)
	_check_equal(columns.size(), 24, "a column a round")
	_check(columns[0]["top"] and columns[0]["icon"] == "icons/ui/timer", "round 1: the counter-terrorists' clock, on top")
	_check(not columns[1]["top"] and columns[1]["icon"] == "icons/ui/bomb", "round 2: the terrorists' bomb, underneath")
	_check(columns[2].is_empty(), "round 3 still to come")
	var halves := Scoreboard.half_scores(_state, period)
	_check_equal(halves[0], [[1, "CT"], [1, "T"]], "the first half: 1 to 1, the top in the counter-terrorists' colour")
	_check_equal(halves[1], [[0, "T"], [0, "CT"]], "the second: nothing yet, the teams on the other sides")
	# 1-1 after two: either clinches with 12 more wins in a row, round 14.
	_check_equal(Scoreboard.clinch_rounds(_state, period), [[13, true], [13, false]],
		"the trophy on round 14 for both, where each would clinch it")
	# Seven played, the terrorists 5 to 2 (Sid's screenshot): they clinch on
	# round 15, the counter-terrorists no sooner than 18.
	var saved := _state.history.duplicate()
	for n in 5:
		_state.phase = MatchState.Phase.LIVE
		_state.end_round("T" if n < 4 else "CT", MatchState.Reason.CT_ELIMINATED if n < 4 else MatchState.Reason.T_ELIMINATED, 0)
	_check_equal(Scoreboard.clinch_rounds(_state, Scoreboard.period_of(_state)), [[14, false]],
		"5 to 2 after seven: the trophy on round 15, the terrorists' (as on Sid's screenshot)")
	_check_equal(Scoreboard.timeline(_state, period)[2]["icon"], "icons/ui/kill", "an elimination's skull")
	_state.history.assign(saved)


func _test_the_board() -> void:
	var board := Scoreboard.new()
	root.add_child(board)
	await process_frame
	board.show_match(_state, _stats, null, _sim("you"), 841 * 1_000_000)
	_check(not board.visible, "not shown until Tab is held")
	board.held = true
	board.show_match(_state, _stats, null, _sim("you"), 841 * 1_000_000)
	_check(board.visible, "shown while it is")
	_check_equal(board.clock, "14:01", "the time on the map, as CS2's 14:01")
	_check_equal(board.rows["T"].size() + board.rows["CT"].size(), 5, "a row for each of the five")
	_check_equal(board.size, Vector2(Scoreboard.WIDTH, Scoreboard.HEIGHT), "CS2's panel: 960 wide")
	_check(absf(board.get_global_rect().get_center().x - 960.0) < 0.5
		and absf(board.get_global_rect().get_center().y - 570.0) < 0.5, "in the middle, 30 px down")
	_check(not board.show_state(board._state), "an unchanged board does not redraw")
	board.held = false
	board.show_match(_state, _stats, null, _sim("you"), 0)
	_check(not board.visible, "gone as Tab is let go")
	board.free()


func _test_the_key() -> void:
	PlayerInput.ensure_actions()
	var keys: Array = InputMap.action_get_events(&"showscores").map(
		func(event: InputEvent) -> int: return (event as InputEventKey).physical_keycode if event is InputEventKey else 0)
	_check(keys.has(KEY_TAB), "Tab is +showscores, as in CS2")
	var board := Scoreboard.new()
	var press := InputEventAction.new()
	press.action = &"showscores"
	press.pressed = true
	board._input(press)
	_check(board.held, "Tab down holds it")
	var release := InputEventAction.new()
	release.action = &"showscores"
	release.pressed = false
	board._input(release)
	_check(not board.held, "Tab up lets go")
	board.free()
