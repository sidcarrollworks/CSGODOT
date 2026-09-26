extends "res://tests/check_suite.gd"

## The round's end: what the server says of a round once it is over
## (RoundReport: the MVP it sends as round_mvp and the fun fact it sends as
## cs_win_panel_round) and CS2's win panel that shows it (WinPanel, from
## GameHud).
##
##   godot --headless --path . --script tests/run_win_panel_checks.gd
##
## Needs nothing extracted. How the panel looks beside CS2's is Sid's check
## (the pull request says what to compare).

const SECOND := 1_000_000

## A player as the roster needs one: a node with a side.
class Someone extends Node3D:
	var team: String = "T"


var _game: GameSystems
var _report: RoundReport
var _ids := {}
var _sent: Array[GameEvent] = []


func _initialize() -> void:
	root.size = Vector2i(1920, 1080)
	await process_frame
	_test_most_kills_is_mvp()
	_test_bomb_mvps()
	_test_no_mvp_without_kills()
	_test_fun_facts()
	_test_what_does_not_count()
	_test_panel_text()
	await _test_the_panel()
	await _test_the_hud_shows_it()
	_finish("win-panel")


## Five a side: T1 to T5 and C1 to C5, joined in that order.
func _new_game() -> void:
	for node in _ids.keys():
		(node as Node).free()
	_ids.clear()
	_sent.clear()
	_game = GameSystems.new()
	_report = RoundReport.new()
	_game.add_system(_report)
	_game.events.listen_all(func(e: GameEvent) -> void: _sent.append(e))
	for side in ["T", "CT"]:
		for i in 5:
			var who := Someone.new()
			who.name = ("T%d" if side == "T" else "C%d") % (i + 1)
			who.team = side
			root.add_child(who)
			_ids[who] = _game.add_player(who)


func _id(player_name: String) -> int:
	for node: Node in _ids:
		if str(node.name) == player_name:
			return _ids[node]
	return GameEvents.NOBODY


func _start(at: int = 0) -> void:
	_game.events.send(&"round_start", {}, at)
	_game.events.send(&"round_freeze_end", {}, at + 15 * SECOND)
	_game.events.flush()


func _kill(attacker: String, victim: String, at: int, headshot: bool = false, damage: int = 100) -> void:
	_game.events.send(&"player_hurt", {"userid": _id(victim), "attacker": _id(attacker), "dmg_health": damage}, at)
	_game.events.send(&"player_death", {"userid": _id(victim), "attacker": _id(attacker), "headshot": headshot}, at)
	_game.events.flush()


func _end(winner: String, reason: String, at: int) -> void:
	_game.events.send(&"round_end", {"winner": winner, "reason": reason}, at)
	_game.events.flush()


func _sent_named(event_name: StringName) -> GameEvent:
	for e in _sent:
		if e.name == event_name:
			return e
	return null


func _test_most_kills_is_mvp() -> void:
	_new_game()
	_start()
	var t := 20 * SECOND
	_kill("T1", "C1", t, true)
	_kill("C2", "T2", t + SECOND)
	for victim in ["C2", "C3", "C4"]:
		t += 3 * SECOND
		_kill("T1", victim, t, true)
	_kill("T3", "C5", t + SECOND)
	_end("T", "TerroristsWin", t + 2 * SECOND)
	var mvp := _sent_named(&"round_mvp")
	_check(mvp != null and mvp.fields["userid"] == _id("T1"), "the winner with the most kills is the MVP")
	_check(mvp != null and mvp.fields["reason"] == RoundReport.MVP_KILLS_FOUR and mvp.fields["value"] == 4,
		"four kills is CS2's reason 16, most kills (4k), worth 4")
	_check_equal(_report.last.get("mvp"), _id("T1"), "and the report keeps it for the win panel")
	var panel := _sent_named(&"cs_win_panel_round")
	_check(panel != null and panel.fields["funfact_token"] == "#funfact_kills_headshots"
		and panel.fields["funfact_player"] == _id("T1") and panel.fields["funfact_data1"] == 4,
		"the fun fact is CS2's: T1 killed 4 enemies with headshots that round")
	var index_end := _sent.find(_sent.filter(func(e: GameEvent) -> bool: return e.name == &"round_end")[0])
	_check(_sent.find(mvp) > index_end, "round_mvp follows round_end in the same hand-out, as CS2 sends it")
	_check_equal(_report.damage_between(_id("T1"), _id("C1")),
		{"given": 100, "hits": 1, "taken": 0, "taken_hits": 0}, "the damage each gave the other is kept")

	# Tie: the first to join takes it; five of five is an ace.
	_new_game()
	_start()
	_kill("C2", "T1", 20 * SECOND)
	_kill("C1", "T2", 21 * SECOND)
	_end("CT", "CTsWin", 30 * SECOND)
	_check_equal(_report.last.get("mvp"), _id("C1"), "a tie goes to whoever joined first")
	_check_equal(_report.last.get("mvp_reason"), RoundReport.MVP_KILLS, "one kill is reason 1, plain MVP")
	_new_game()
	_start()
	for i in 5:
		_kill("C3", "T%d" % (i + 1), (20 + i) * SECOND)
	_end("CT", "CTsWin", 30 * SECOND)
	_check_equal(_report.last.get("mvp_reason"), RoundReport.MVP_ACE, "every one of five killed is an ace (9)")


func _test_bomb_mvps() -> void:
	_new_game()
	_start()
	_game.events.send(&"bomb_planted", {"userid": _id("T4"), "site": "A"}, 40 * SECOND)
	_game.events.flush()
	_kill("T1", "C1", 45 * SECOND)
	_kill("C2", "T2", 50 * SECOND)
	_end("T", "TargetBombed", 80 * SECOND)
	_check_equal(_report.last.get("mvp"), _id("T4"), "the bomb going off makes its planter MVP")
	_check_equal(_report.last.get("mvp_reason"), RoundReport.MVP_BOMB_PLANT, "for planting the bomb (2)")
	_check_equal(_report.last.get("funfact_token"), "funfact_bomb_planted_before_kill",
		"no one died before the plant: CS2's fun fact for it")

	_new_game()
	_start()
	_kill("C2", "T1", 30 * SECOND)
	_game.events.send(&"bomb_defused", {"userid": _id("C2"), "site": "B"}, 60 * SECOND)
	_game.events.flush()
	_end("CT", "BombDefused", 60 * SECOND)
	_check(_report.last.get("mvp") == _id("C2") and _report.last.get("mvp_reason") == RoundReport.MVP_BOMB_DEFUSE,
		"a defuser with a kill is MVP for defusing the bomb (3)")

	_new_game()
	_start()
	_kill("C1", "T1", 30 * SECOND)
	_game.events.send(&"bomb_defused", {"userid": _id("C2"), "site": "B"}, 60 * SECOND)
	_game.events.flush()
	_end("CT", "BombDefused", 60 * SECOND)
	_check_equal(_report.last.get("mvp"), _id("C1"), "a defuser without a kill is not; the most kills is")


func _test_no_mvp_without_kills() -> void:
	_new_game()
	_start()
	_end("CT", "TargetSaved", 130 * SECOND)
	_check(_sent_named(&"round_mvp") == null and _report.last.get("mvp") == GameEvents.NOBODY,
		"a round won on time with no kills has no MVP, and no round_mvp is sent")
	_check(_sent_named(&"cs_win_panel_round") != null, "the win panel's event still goes out")
	_check_equal(_report.last.get("funfact_token"), "", "and with nothing to tell, no fun fact")


func _test_fun_facts() -> void:
	_new_game()
	_start()
	_kill("T1", "C1", 20 * SECOND)
	_kill("T2", "C2", 21 * SECOND)
	_end("T", "TerroristsWin", 22 * SECOND)
	_check_equal(_report.last.get("funfact_token"), "funfact_t_win_no_casualties",
		"the winners lost no one: Terrorists won without taking any casualties")

	_new_game()
	_start()
	_game.events.send(&"player_hurt", {"userid": _id("C1"), "attacker": _id("T5"), "dmg_health": 140}, 20 * SECOND)
	_game.events.flush()
	_kill("C1", "T1", 25 * SECOND, false, 100)
	_kill("T3", "C2", 26 * SECOND)
	_end("CT", "CTsWin", 90 * SECOND)
	var fact := [_report.last.get("funfact_token"), _report.last.get("funfact_player"), _report.last.get("funfact_data1")]
	_check_equal(fact, ["funfact_damage_no_kills", _id("T5"), 140], "no kills but 140 damage is told")

	_new_game()
	_start()
	_kill("C1", "T1", 25 * SECOND)
	_kill("T2", "C1", 26 * SECOND)
	_end("CT", "TargetSaved", 130 * SECOND)
	fact = [_report.last.get("funfact_token"), _report.last.get("funfact_player"), _report.last.get("funfact_data1")]
	_check_equal(fact, ["funfact_first_blood", _id("C1"), 10], "first blood, counted from the end of freeze time")


func _test_what_does_not_count() -> void:
	_new_game()
	_start()
	_kill("T1", "T2", 20 * SECOND)
	_kill("C1", "C1", 21 * SECOND)
	_end("CT", "TargetSaved", 130 * SECOND)
	_check_equal(_report.kills_of(_id("T1")), 0, "a teammate killed is no kill")
	_check_equal(_report.last.get("mvp"), GameEvents.NOBODY, "nor is a suicide")
	var before := _sent.size()
	_kill("T3", "C2", 131 * SECOND)
	_end("T", "TerroristsWin", 132 * SECOND)
	_check(_sent.slice(before).filter(func(e: GameEvent) -> bool: return e.name == &"round_mvp").is_empty(),
		"after a round's end nothing counts, and only one round_end is reported")
	_game.events.send(&"round_start", {}, 140 * SECOND)
	_game.events.flush()
	_check(_report.last.is_empty(), "the next round starts with no report")


func _test_panel_text() -> void:
	_check_equal(WinPanel.title_for("T", "T"), "ROUND WON", "your side won: ROUND WON")
	_check_equal(WinPanel.title_for("T", "CT"), "ROUND LOST", "your side lost: ROUND LOST")
	_check_equal(WinPanel.title_for("CT", ""), "Counter-Terrorists Win", "on neither side: who won, as CS2 says it")
	_check_equal(WinPanel.mvp_reason_text(16), "MVP for most kills (4k)", "reason 16 reads as CS2's does")
	_check_equal(WinPanel.mvp_reason_text(1), "MVP", "reason 1 is just MVP")
	_check_equal(WinPanel.fun_fact_text("#funfact_kills_headshots", "THICCBOI", 4),
		"THICCBOI killed 4 enemies with headshots that round.", "the screenshot's fun fact, word for word")
	_check_equal(WinPanel.fun_fact_text("#funfact_kills_headshots", "A", 1),
		"A killed 1 enemy with headshots that round.", "one takes CS2's singular")
	_check_equal(WinPanel.reason_text("TargetSaved"), "Bombing failed", "without a fun fact, why it ended")
	for token in RoundReport.FUN_FACTS:
		_check(not WinPanel.fun_fact_text(token, "A", 2).is_empty(), "the panel can say %s" % token)
	var long_name := WinPanel.fit_name("A really very extremely long player name here")
	_check(long_name.ends_with("…"), "a name too long for its box is cut short")


func _test_the_panel() -> void:
	var panel := WinPanel.new()
	root.add_child(panel)
	await process_frame
	_check_near(panel.get_global_rect().position.y, WinPanel.TOP, "the panel starts 190 px down (winPanelPosY)")
	_check_near(panel.get_global_rect().get_center().x, 960.0, "in the middle")
	_check(not panel.is_showing() and not panel.is_animating(), "hidden and idle until a round ends")
	panel.show_round("ROUND WON", "T", false, "fact", "T1", "MVP", "T", true)
	_check(panel.is_animating(), "it opens as the round ends")
	_check_near(panel.title_scale(), WinPanel.TITLE_START_SCALE, "the title starts half as large again")
	_check(panel.accent() == HudStyle.T_COLOUR, "a terrorist win is in t-color")
	for i in 20:
		panel._process(0.3)
	_check(not panel.is_animating(), "and stops redrawing once open")
	_check_near(panel.title_scale(), 1.0, "with the title at its size")
	_check_near(panel.openness(), 1.0, "and the bar open")
	panel.show_round("ROUND LOST", "T", true)
	_check(panel.accent() == WinPanel.NEGATIVE, "a round lost is in CS2's negativeColor")
	panel.show_round("")
	_check(not panel.is_showing(), "and it goes as the next round starts")
	panel.free()


func _test_the_hud_shows_it() -> void:
	_new_game()
	var state := MatchState.new()
	root.add_child(state)
	state.phase = MatchState.Phase.ROUND_END
	state.last_winner = "T"
	state.last_reason = MatchState.Reason.CT_ELIMINATED
	var hud := GameHud.new()
	hud.match_state = state
	hud.round_report = _report
	root.add_child(hud)
	_start()
	_kill("T1", "C1", 20 * SECOND, true)
	_kill("T1", "C2", 21 * SECOND, true)
	_kill("C3", "T2", 22 * SECOND)
	_end("T", "TerroristsWin", 25 * SECOND)
	hud._show_win_panel("T")
	var panel := hud.win_panel
	_check_equal(panel.title, "ROUND WON", "the HUD's panel says ROUND WON to the winners")
	_check_equal(panel.fact, "T1 killed 2 enemies with headshots that round.", "with the round's fun fact")
	_check(panel.mvp_name == "T1" and panel.mvp_reason == "MVP", "and its MVP")
	hud._show_win_panel("CT")
	_check_equal(panel.title, "ROUND LOST", "and ROUND LOST to the losers")
	state.phase = MatchState.Phase.FREEZE
	hud._show_win_panel("T")
	_check(not panel.is_showing(), "gone once the next round is on")
	hud.free()
	state.free()
	await process_frame
