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


## Two report frames drawn through the production helper. Their pixels
## must mirror within the same boxes, including with the extracted SVG.
class ReportFrames extends Control:
	var counter: TeamCounter

	func _draw() -> void:
		draw_rect(Rect2(0, 0, 64, 88), Color.BLACK)
		counter._draw_report_frame(self, Rect2(8, 8, 48, 32), false, Color.WHITE)
		counter._draw_report_frame(self, Rect2(8, 48, 48, 32), true, Color.WHITE)


## Flat black/white fields measure the share of the world visible through
## the banner; fine stripes then distinguish its blur from plain tinting.
class BannerBackdrop extends Control:
	var kind := 0

	func _draw() -> void:
		draw_rect(Rect2(0, 0, 900, 160), Color.BLACK if kind == 0 else Color.WHITE)
		if kind == 2:
			for x in range(0, 900, 4):
				draw_rect(Rect2(x, 0, 2, 160), Color.BLACK)


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
	await _test_the_damage_report()
	if DisplayServer.get_name() != "headless":
		await _test_the_report_frames_render_in_place()
		await _test_the_title_layers_render_in_place()
		await _test_the_banner_blurs_the_world()
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


## Whether a fun fact holds for the round just ended.
func _holds(winner: String, reason: String, end_usec: int, fact: Array) -> bool:
	return _report.fun_facts_holding(winner, reason, end_usec).has(fact)


func _name_of(userid: int) -> String:
	for node: Node in _ids:
		if _ids[node] == userid:
			return str(node.name)
	return ""


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
	_check(_holds("T", "TerroristsWin", t + 2 * SECOND, ["funfact_kills_headshots", _id("T1"), 4]),
		"a fun fact that holds is CS2's: T1 killed 4 enemies with headshots that round")
	_check(panel != null and _holds("T", "TerroristsWin", t + 2 * SECOND,
		[String(panel.fields["funfact_token"]).trim_prefix("#"), panel.fields["funfact_player"], panel.fields["funfact_data1"]]),
		"and the one told (%s) is one that holds" % (panel.fields["funfact_token"] if panel != null else "none"))
	var index_end := _sent.find(_sent.filter(func(e: GameEvent) -> bool: return e.name == &"round_end")[0])
	_check(_sent.find(mvp) > index_end, "round_mvp follows round_end in the same hand-out, as CS2 sends it")
	_check_equal(_report.damage_between(_id("T1"), _id("C1")),
		{"given": 100, "hits": 1, "taken": 0, "taken_hits": 0, "kill": "headshot", "taken_kill": ""},
		"the damage each gave the other is kept, and how T1 killed C1")
	_check_equal(_report.damage_between(_id("C2"), _id("T2"))["kill"], "default", "a body shot's kill is the default one")
	_check_equal(_report.damage_between(_id("T2"), _id("C2"))["taken_kill"], "default", "and T2 sees it as what killed them")

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
	_check(_holds("T", "TargetBombed", 80 * SECOND, ["funfact_bomb_planted_before_kill", GameEvents.NOBODY, 0]),
		"no one died before the plant: CS2's fun fact for it holds")

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
	_check(_holds("T", "TerroristsWin", 22 * SECOND, ["funfact_t_win_no_casualties", GameEvents.NOBODY, 0]),
		"the winners lost no one: Terrorists won without taking any casualties")

	_new_game()
	_start()
	_game.events.send(&"player_hurt", {"userid": _id("C1"), "attacker": _id("T5"), "dmg_health": 140}, 20 * SECOND)
	_game.events.flush()
	_kill("C1", "T1", 25 * SECOND, false, 100)
	_kill("T3", "C2", 26 * SECOND)
	_end("CT", "CTsWin", 90 * SECOND)
	_check(_holds("CT", "CTsWin", 90 * SECOND, ["funfact_damage_no_kills", _id("T5"), 140]),
		"no kills but 140 damage is one to tell")

	_new_game()
	_start()
	_kill("C1", "T1", 25 * SECOND)
	_kill("T2", "C1", 26 * SECOND)
	_end("CT", "TargetSaved", 130 * SECOND)
	_check(_holds("CT", "TargetSaved", 130 * SECOND, ["funfact_first_blood", _id("C1"), 10]),
		"first blood, counted from the end of freeze time")

	# Sid's 2026-09-30 screenshot: 138 shots were fired that round.
	_new_game()
	_start()
	for i in 138:
		_game.events.send(&"weapon_fire", {"userid": _id("T%d" % (i % 5 + 1)), "weapon": "weapon_glock"}, 20 * SECOND)
	_game.events.flush()
	_kill("C1", "T1", 30 * SECOND)
	_end("CT", "TargetSaved", 130 * SECOND)
	_check(_holds("CT", "TargetSaved", 130 * SECOND, ["funfact_shots_fired", GameEvents.NOBODY, 138]),
		"every shot of the round is counted, both sides'")
	_check_equal(WinPanel.fun_fact_text("#funfact_shots_fired", "", 138), "138 shots were fired that round.",
		"and told as CS2 tells it")
	var holding := _report.fun_facts_holding("CT", "TargetSaved", 130 * SECOND)
	var picks := {}
	for n in 40:
		var at := (130 + n) * SECOND
		picks[_report.pick_fun_fact("CT", "TargetSaved", at)[0]] = true
	_check(picks.size() > 1, "which fact is told is drawn among those that hold, not always the first")
	_check_equal(_report.pick_fun_fact("CT", "TargetSaved", 130 * SECOND),
		_report.pick_fun_fact("CT", "TargetSaved", 130 * SECOND), "the same round always draws the same")
	_check(holding.size() >= 2, "(this round has %d to draw from)" % holding.size())
	_check_equal(RoundReport.kill_type("weapon_hegrenade", false), "blast", "an HE's kill is a blast")
	_check_equal(RoundReport.kill_type("inferno", false), "burn", "fire's is a burn")
	_check_equal(RoundReport.kill_type("weapon_knife_t", true), "slash", "a knife's a slash, headshot or not")
	_check_equal(RoundReport.kill_type("weapon_taser", false), "shock", "the Zeus's a shock")


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
	_check_near(panel.echo_scale(), 1.0, "the background title starts at the foreground's size")
	panel._process(0.1)
	_check(panel._result_clip.clip_contents and panel._result_clip.size.x < WinPanel.WIDTH,
		"the opening strip clips the growing copy and reveals the centre of the title")
	_check(panel._result_contents.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"the title's canvas leaves clicks to the game")
	_check(panel.accent() == HudStyle.T_COLOUR, "a terrorist win is in t-color")
	for i in 17:
		panel._process(0.3)
	_check(panel.is_animating() and panel.echo_scale() < WinPanel.ECHO_END_SCALE,
		"five seconds after opening, the slower background is still growing")
	for i in 20:
		panel._process(0.3)
	_check(not panel.is_animating(), "and stops redrawing once open")
	_check_near(panel.echo_scale(), WinPanel.ECHO_END_SCALE, "with only the background copy grown to its final size")
	_check_near(panel.openness(), 1.0, "and the bar open")
	_check_near(panel._bar().size.x, 640.0, "the full-screen reference's result strip spans 640 base pixels")
	panel.show_round("ROUND LOST", "T", true)
	_check(panel.accent() == WinPanel.NEGATIVE, "a round lost is in CS2's negativeColor")
	panel.show_round("")
	_check(not panel.is_showing() and not panel._result_clip.visible, "and both layers go as the next round starts")
	panel.show_round("ROUND WON", "CT")
	_check_near(panel.echo_scale(), 1.0, "a new round's title restarts the background growth")
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
	_check_equal(panel.fact, WinPanel.fun_fact_text(_report.last["funfact_token"], _name_of(_report.last["funfact_player"]),
		_report.last["funfact_data1"]), "with the round's fun fact")
	_check(panel.mvp_name == "T1" and panel.mvp_reason == "MVP", "and its MVP")
	hud._show_win_panel("CT")
	_check_equal(panel.title, "ROUND LOST", "and ROUND LOST to the losers")
	state.phase = MatchState.Phase.FREEZE
	hud._show_win_panel("T")
	_check(not panel.is_showing(), "gone once the next round is on")
	hud.free()
	state.free()
	await process_frame


## CS2's post-round damage report under the enemies' cards (Sid's CS2
## screenshot of 2026-09-30: "100 in 3" in green, "27 in 1" in red).
func _test_the_damage_report() -> void:
	var game := GameSystems.new()
	var report := RoundReport.new()
	game.add_system(report)
	var state := MatchState.new()
	root.add_child(state)
	var sims := {}
	for who in ["you", "mate", "efe", "uri", "walt"]:
		var sim := PlayerSim.new()
		sim.name = who
		sim.team = "T" if who in ["you", "mate"] else "CT"
		root.add_child(sim)
		sim.userid = game.add_player(sim)
		state.add_player(sim)
		sims[who] = sim.userid
	var hit := func(attacker: String, victim: String, damage: int, at: int) -> void:
		game.events.send(&"player_hurt", {"userid": sims[victim], "attacker": sims[attacker], "dmg_health": damage}, at)
	game.events.send(&"round_start", {}, 0)
	for n in 3:
		hit.call("you", "uri", 40, (20 + n) * SECOND)
	game.events.send(&"player_death", {"userid": sims["uri"], "attacker": sims["you"], "weapon": "weapon_glock"}, 22 * SECOND)
	hit.call("uri", "you", 27, 21 * SECOND)
	hit.call("efe", "you", 17, 30 * SECOND)
	hit.call("mate", "you", 10, 31 * SECOND)
	game.events.send(&"round_end", {"winner": "CT", "reason": "TargetSaved"}, 130 * SECOND)
	game.events.flush()
	var you: PlayerSim = null
	for sim in state.players:
		if sim.userid == sims["you"]:
			you = sim
	var counter := TeamCounter.new()
	root.add_child(counter)
	await process_frame
	var reported := func() -> Dictionary:
		var out := {}
		for side: String in MatchState.SIDES:
			for card: TeamCounter.Card in counter.cards[side]:
				if not card.report.is_empty():
					out[card.name] = card.report
		return out
	state.phase = MatchState.Phase.LIVE
	counter.show_match(state, you, null, 0, null, report)
	_check(reported.call().is_empty(), "no report while the round is played")
	state.phase = MatchState.Phase.ROUND_END
	counter.show_match(state, you, null, 0, null, report)
	var shown: Dictionary = reported.call()
	_check_equal(shown.keys().size(), 2, "at the round's end, a report under each enemy you traded damage with")
	_check(shown.has("uri") and shown["uri"]["given"] == 100 and shown["uri"]["hits"] == 3
		and shown["uri"]["taken"] == 27 and shown["uri"]["taken_hits"] == 1 and shown["uri"]["kill"] == "default",
		"Uri: 100 in 3 given (capped at 100, as CS2 shows it) with the kill, 27 in 1 taken")
	_check(shown.has("efe") and shown["efe"]["given"] == 0 and shown["efe"]["taken"] == 17,
		"Efe, still alive: only 17 in 1 taken")
	_check(not shown.has("mate") and not shown.has("walt"), "none for a teammate, nor an enemy you never traded with")
	_check(counter.is_animating() and counter.report_shown(0) < 1.0, "the reports slide in")
	for n in 20:
		counter._process(0.1)
	_check(not counter.is_animating() and counter.report_shown(1) == 1.0, "one after another, then stop redrawing")
	state.phase = MatchState.Phase.FREEZE
	counter.show_match(state, you, null, 0, null, report)
	_check(reported.call().is_empty(), "and go as the next round starts")
	_check_equal(TeamCounter.PRDR_GIVEN, Color8(9, 255, 0), "given in CS2's green")
	_check_equal(TeamCounter.PRDR_TAKEN, Color8(255, 84, 84), "taken in its red")
	counter.free()
	state.free()
	for sim in root.get_children():
		if sim is PlayerSim:
			sim.free()
	await process_frame


func _test_the_report_frames_render_in_place() -> void:
	HudStyle.read_ahead(["hud/teamcounter/damage-report-frame"])
	# An unscaled offscreen canvas, independent of the desktop's resolution.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64, 88)
	viewport.disable_3d = true
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var frames := ReportFrames.new()
	frames.counter = TeamCounter.new()
	frames.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(frames)
	await process_frame
	await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	var largest_error := 0.0
	var total_error := 0.0
	var filled := 0
	for y in 32:
		for x in 48:
			var given := pixels.get_pixel(8 + x, 8 + y)
			var taken := pixels.get_pixel(8 + x, 48 + 31 - y)
			var error := maxf(absf(given.r - taken.r), maxf(absf(given.g - taken.g), absf(given.b - taken.b)))
			largest_error = maxf(largest_error, error)
			total_error += error
			if given.r > 0.01:
				filled += 1
	_check(filled > 100, "the renderer draws a visible damage-report frame")
	# Filtered SVG edges can round differently with reversed UVs. Compare
	# the whole shape while allowing that small edge sampling difference.
	var mean_error := total_error / (48 * 32)
	_check(mean_error <= 0.002 and largest_error <= 0.02,
		"the taken frame mirrors the given one inside its row (mean %.6f, max %.6f)" % [mean_error, largest_error])
	pixels.save_png("user://win_panel_frame_check.png")
	frames.counter.free()
	viewport.free()


## Render the production panel at the start/end of the growth, then turn
## off only its clip to prove that the larger text really reaches beyond
## the border. The bright foreground's bounds must remain unchanged.
func _test_the_title_layers_render_in_place() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(900, 160)
	viewport.disable_3d = true
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var panel := WinPanel.new()
	viewport.add_child(panel)
	panel.position = Vector2(50, 30)
	panel.size = Vector2(WinPanel.WIDTH, WinPanel.BAR_HEIGHT)
	panel.show_round("ROUND LOST", "T", true)
	panel.set_process(false)
	panel._t = WinPanel.OPEN_SECONDS
	panel.redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var early := viewport.get_texture().get_image()
	panel._t = WinPanel.ECHO_SECONDS
	panel.redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var late := viewport.get_texture().get_image()
	panel._result_clip.clip_contents = false
	await process_frame
	await RenderingServer.frame_post_draw
	var unclipped := viewport.get_texture().get_image()
	var early_bounds := _bright_title_bounds(early)
	var late_bounds := _bright_title_bounds(late)
	_check(early_bounds.has_area() and early_bounds == late_bounds,
		"the foreground's size and position stay fixed while the background grows (%s / %s)" % [early_bounds, late_bounds])
	var bar := Rect2i(50, 30, int(WinPanel.WIDTH), int(WinPanel.BAR_HEIGHT))
	var growth := 0
	var clipped := 0
	var leaks := 0
	for y in late.get_height():
		for x in late.get_width():
			var at := Vector2i(x, y)
			var colour := late.get_pixelv(at)
			if bar.has_point(at):
				if absf(colour.r - early.get_pixelv(at).r) > 0.04:
					growth += 1
			else:
				if unclipped.get_pixelv(at).r - colour.r > 0.04:
					clipped += 1
				if absf(colour.r - early.get_pixelv(at).r) > 0.04:
					leaks += 1
	_check(growth > 100 and clipped > 100 and leaks == 0,
		"the faint copy expands behind the title and is cropped at the bar's borders (%d changed, %d clipped, %d leaked)" % [growth, clipped, leaks])
	early.save_png("user://win_panel_layers_early.png")
	late.save_png("user://win_panel_layers_late.png")
	viewport.free()


func _bright_title_bounds(pixels: Image) -> Rect2i:
	var bounds := Rect2i()
	for y in pixels.get_height():
		for x in pixels.get_width():
			if pixels.get_pixel(x, y).r > 0.7:
				if not bounds.has_area():
					bounds = Rect2i(x, y, 1, 1)
				else:
					bounds = bounds.merge(Rect2i(x, y, 1, 1))
	return bounds


func _test_the_banner_blurs_the_world() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(900, 160)
	viewport.disable_3d = true
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var backdrop := BannerBackdrop.new()
	viewport.add_child(backdrop)
	var panel := WinPanel.new()
	viewport.add_child(panel)
	panel.position = Vector2(50, 30)
	panel.size = Vector2(WinPanel.WIDTH, WinPanel.BAR_HEIGHT)
	panel.show_round("ROUND LOST", "T", true)
	panel.set_process(false)
	panel._t = WinPanel.OPEN_SECONDS
	panel.redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var dark := viewport.get_texture().get_image()
	backdrop.kind = 1
	backdrop.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var light := viewport.get_texture().get_image()
	var centre_x := int(50 + WinPanel.WIDTH * 0.5)
	var world_share := light.get_pixel(centre_x, 95).r - dark.get_pixel(centre_x, 95).r
	_check(world_share > 0.3 and world_share < 0.5,
		"the tinted banner keeps a visible share of the world behind it (%.3f)" % world_share)
	var sides_fade := true
	for side in [-1, 1]:
		var outer_x := centre_x + int(side * WinPanel.WIDTH * 0.49)
		var inner_x := centre_x + int(side * WinPanel.WIDTH * 0.38)
		var outer_share := light.get_pixel(outer_x, 95).r - dark.get_pixel(outer_x, 95).r
		var inner_share := light.get_pixel(inner_x, 95).r - dark.get_pixel(inner_x, 95).r
		sides_fade = sides_fade and outer_share > 0.9 and inner_share > 0.65 and inner_share < 0.85
	_check(sides_fade, "both ends reveal almost all the world and fade gradually across a broad area")
	backdrop.kind = 2
	backdrop.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var blurred := viewport.get_texture().get_image()
	panel._blur.visible = false
	await process_frame
	await RenderingServer.frame_post_draw
	var sharp := viewport.get_texture().get_image()
	var blurred_contrast := 0.0
	var sharp_contrast := 0.0
	for x in range(centre_x - 20, centre_x + 20):
		blurred_contrast += absf(blurred.get_pixel(x, 85).r - blurred.get_pixel(x + 1, 85).r)
		sharp_contrast += absf(sharp.get_pixel(x, 85).r - sharp.get_pixel(x + 1, 85).r)
	_check(sharp_contrast > 1.0 and blurred_contrast < sharp_contrast * 0.2,
		"the shared HUD blur softens the world beneath the banner (%.3f blurred / %.3f sharp)" % [blurred_contrast, sharp_contrast])
	var edges_fade := true
	for edge_x in [52, int(50 + WinPanel.WIDTH) - 6]:
		var blurred_edge := 0.0
		var sharp_edge := 0.0
		for x in range(edge_x, edge_x + 4):
			blurred_edge += absf(blurred.get_pixel(x, 85).r - blurred.get_pixel(x + 1, 85).r)
			sharp_edge += absf(sharp.get_pixel(x, 85).r - sharp.get_pixel(x + 1, 85).r)
		edges_fade = edges_fade and sharp_edge > 1.0 and blurred_edge > sharp_edge * 0.9
	_check(edges_fade, "the blur fades with the tint at both edges, leaving the world sharp there")
	viewport.free()
