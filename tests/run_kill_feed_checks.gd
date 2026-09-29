extends "res://tests/check_suite.gd"

## CS2's kill feed (KillFeed, in GameHud's top right): what a row says for
## each death the game hands out, how long it stays, how the rows move, and
## where they sit.
##
##   godot --headless --path . --script tests/run_kill_feed_checks.gd
##
## Needs nothing extracted: without the HUD's icons the weapon shows as its
## name and each mark as a word. How it looks beside CS2's is Sid's check.

## A player as the roster needs one: a node with a side.
class Someone extends Node3D:
	var team: String = "T"


var _game: GameSystems
var _ids := {}


func _initialize() -> void:
	root.size = Vector2i(1920, 1080)
	await process_frame
	_new_game()
	_test_rows()
	_test_marks()
	_test_yours()
	_test_names()
	await _test_the_feed()
	await _test_the_hud_has_it()
	_finish("kill-feed")


## Two a side, T1, T2, C1 and C2, joined in that order.
func _new_game() -> void:
	_game = GameSystems.new()
	for side in ["T", "CT"]:
		for i in 2:
			var who := Someone.new()
			who.name = ("T%d" if side == "T" else "C%d") % (i + 1)
			who.team = side
			root.add_child(who)
			_ids[str(who.name)] = _game.add_player(who)


func _id(player_name: String) -> int:
	return _ids.get(player_name, GameEvents.NOBODY)


func _death(fields: Dictionary) -> Dictionary:
	var full: Dictionary = (GameEvents.SCHEMA[&"player_death"] as Dictionary).duplicate()
	full.merge(fields, true)
	return full


func _kinds(n: KillFeed.Notice) -> Array:
	return KillFeed.parts_of(n).map(func(p: Array) -> String:
		return p[0] if p[0] != "icon" else "icon:" + p[1])


func _test_rows() -> void:
	var n := KillFeed.notice_for(_death({"userid": _id("C1"), "attacker": _id("T1"), "weapon": "weapon_glock"}),
		_game.roster, GameEvents.NOBODY)
	_check(n.attacker == "T1" and n.victim == "C1", "a row names the killer and the victim")
	_check(n.attacker_side == "T" and n.victim_side == "CT", "with their sides")
	_check_equal(_kinds(n), ["name", "weapon", "name"], "killer, weapon, victim, left to right")
	_check(KillFeed.side_colour("T") == KillFeed.T_COLOUR and KillFeed.side_colour("CT") == KillFeed.CT_COLOUR,
		"names in the feed's own TColor and CTColor")
	_check(KillFeed.side_colour("") == KillFeed.FADED_COLOUR, "and FadedColor for no side")

	var assisted := KillFeed.notice_for(_death({"userid": _id("C1"), "attacker": _id("T1"), "assister": _id("T2"),
		"assistedflash": true, "weapon": "weapon_ak47"}), _game.roster, GameEvents.NOBODY)
	_check_equal(_kinds(assisted), ["name", "plus", "icon:flash", "name", "weapon", "name"],
		"an assist: killer, +, the flash's icon, the assister, then the weapon")

	var bomb := KillFeed.notice_for(_death({"userid": _id("C2"), "weapon": "weapon_c4"}), _game.roster,
		GameEvents.NOBODY)
	_check_equal(_kinds(bomb), ["weapon", "name"], "the bomb's kill shows the C4 and the victim, no killer")

	var fall := KillFeed.notice_for(_death({"userid": _id("T2")}), _game.roster, GameEvents.NOBODY)
	_check_equal(_kinds(fall), ["icon:suicide", "name"], "a fall shows the skull and the victim")
	var own := KillFeed.notice_for(_death({"userid": _id("T2"), "attacker": _id("T2"), "weapon": "weapon_hegrenade"}),
		_game.roster, GameEvents.NOBODY)
	_check_equal(_kinds(own), ["icon:suicide", "name"], "so does killing yourself, in the weapon's place")


func _test_marks() -> void:
	var n := KillFeed.notice_for(_death({
		"userid": _id("C1"), "attacker": _id("T1"), "weapon": "weapon_awp", "headshot": true, "penetrated": 1,
		"noscope": true, "thrusmoke": true, "attackerblind": true, "attackerinair": true, "revenge": 1,
		"dominated": 1,
	}), _game.roster, GameEvents.NOBODY)
	_check_equal(_kinds(n), ["icon:revenge", "icon:domination", "icon:blind", "name", "icon:in_air", "weapon",
		"icon:noscope", "icon:smoke", "icon:penetrate", "icon:headshot", "name"],
		"every mark in huddeathnotice.xml's order")
	var plain := KillFeed.notice_for(_death({"userid": _id("C1"), "attacker": _id("T1"), "weapon": "weapon_ak47"}),
		_game.roster, GameEvents.NOBODY)
	_check(plain.marks.is_empty(), "and none that the death does not carry")


func _test_yours() -> void:
	var you := _id("T1")
	var killed := KillFeed.notice_for(_death({"userid": _id("C1"), "attacker": you}), _game.roster, you)
	_check_equal(killed.yours, KillFeed.Yours.KILLER, "your kill is marked yours (DeathNotice_Killer)")
	_check_near(killed.lifetime(), 7.5, "and stays 7.5 s (5 s, half as long again)")
	_check_equal(KillFeed.name_size(killed), 15, "with 15 px names")
	var died := KillFeed.notice_for(_death({"userid": you, "attacker": _id("C1")}), _game.roster, you)
	_check_equal(died.yours, KillFeed.Yours.VICTIM, "your death is marked (DeathNotice_Victim)")
	var assisted := KillFeed.notice_for(_death({"userid": _id("C2"), "attacker": _id("T2"), "assister": you}),
		_game.roster, you)
	_check(assisted.yours == KillFeed.Yours.NONE and is_equal_approx(assisted.lifetime(), 7.5),
		"your assist is not ringed, but stays as long")
	var theirs := KillFeed.notice_for(_death({"userid": _id("C2"), "attacker": _id("T2")}), _game.roster, you)
	_check(theirs.yours == KillFeed.Yours.NONE and is_equal_approx(theirs.lifetime(), 5.0),
		"someone else's stays 5 s (DeathNoticeLifetime)")


func _test_names() -> void:
	var bot := KillFeed.fit_name("Azul", true, 16)
	_check(bot[0] == "[BOT] " and bot[1] == "Azul", "a bot's name carries the [BOT] tag")
	_check_equal(KillFeed.fit_name("Azul", false, 16)[0], "", "a player's none")
	var long := KillFeed.fit_name("A really very extremely long player name here", false, 16)
	_check(long[1].ends_with("…"), "a name past 160 px is cut with an ellipsis")
	var width := HudStyle.face(&"bold").get_string_size(long[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	_check(width <= KillFeed.NAME_MAX + 0.5, "to fit 160 px")


func _test_the_feed() -> void:
	var feed := KillFeed.new()
	root.add_child(feed)
	feed.watch(_game, _id("T1"))
	await process_frame
	var box := feed.get_global_rect()
	_check_near(box.end.x, 1920.0 - KillFeed.RIGHT, "the feed's right edge is 10 px in (padding-right)")
	_check_near(box.position.y + KillFeed.row_top(0), 75.0, "its first row 75 px down, as on CS2's screenshot")
	_check(not feed.is_animating(), "idle with nothing to show")

	_game.events.send(&"player_death", {"userid": _id("C1"), "attacker": _id("T2"), "weapon": "weapon_ak47"})
	_check(feed.notices().is_empty(), "nothing shows until the tick's events are handed out")
	_game.events.flush()
	# The tick only takes the death down: the row is laid out on a frame.
	_check(feed._notices.is_empty() and feed._waiting.size() == 1 and feed.is_animating(),
		"handed out on the tick, the death waits for the frame: no row is laid out in the tick")
	await process_frame
	_check(feed._notices.size() == 1 and feed._waiting.is_empty(), "the next frame makes it a row")
	# Its side and name are the roster's as the death was told, not as the
	# frame finds them.
	_game.events.send(&"player_death", {"userid": _id("C2"), "attacker": _id("T1"), "weapon": "weapon_ak47"})
	_game.events.flush()
	var told: KillFeed.Notice = feed._waiting[0]
	_check(told.victim == "C2" and told.victim_side == "CT" and told.attacker_side == "T",
		"what it says is read as it is told (%s of %s, by %s)" % [told.victim, told.victim_side, told.attacker_side])
	feed._process(100.0)
	_check(feed.notices().is_empty(), "(and both rows have gone)")
	_game.events.send(&"player_death", {"userid": _id("C1"), "attacker": _id("T2"), "weapon": "weapon_ak47"})
	_game.events.flush()
	_check_equal(feed.notices().size(), 1, "then the death is a row")
	_check(feed.is_animating(), "and the feed keeps time")

	for i in KillFeed.MOST_SHOWN + 1:
		_game.events.send(&"player_death", {"userid": _id("C2"), "attacker": _id("T2"), "weapon": "weapon_glock"})
	_game.events.flush()
	_check_equal(feed.notices().size(), KillFeed.MOST_SHOWN, "no more than MOST_SHOWN rows")
	var newest: KillFeed.Notice = feed.notices()[-1]
	_check_near(newest.y, KillFeed.row_top(KillFeed.MOST_SHOWN - 1), "the newest at the bottom")
	_check_equal(feed.notices()[0].weapon, "weapon_glock", "the oldest went to make room")

	# A row is whole for its 5 s, then fades out over 1 s.
	var n: KillFeed.Notice = feed.notices()[0]
	feed._process(4.9)
	_check_near(KillFeed.opacity_of(n), 1.0, "a row is whole until its time is up")
	feed._process(0.6)
	_check(KillFeed.opacity_of(n) > 0.0 and KillFeed.opacity_of(n) < 1.0, "then fades")
	feed._process(0.6)
	_check(feed.notices().is_empty(), "and is gone after its second of fading")
	_check(not feed.is_animating(), "an empty feed does no work a frame")

	# Rows slide up into a gone row's place.
	_game.events.send(&"player_death", {"userid": _id("C1"), "attacker": _id("T2"), "weapon": "weapon_ak47"})
	_game.events.flush()
	feed._process(2.0)
	_game.events.send(&"player_death", {"userid": _id("C2"), "attacker": _id("T2"), "weapon": "weapon_ak47"})
	_game.events.flush()
	var second: KillFeed.Notice = feed.notices()[1]
	feed._process(4.0)
	_check_equal(feed.notices().size(), 1, "the first row goes on its own time")
	_check(second.y > KillFeed.row_top(0), "the next starts from where it was")
	feed._process(KillFeed.SLIDE_SECONDS)
	_check_near(second.y, KillFeed.row_top(0), "and slides up into its place over .2 s")
	feed.free()


func _test_the_hud_has_it() -> void:
	var hud := GameHud.new()
	hud.game = _game
	hud.userid = _id("T1")
	root.add_child(hud)
	await process_frame
	_check(hud.kill_feed != null, "the HUD has a kill feed")
	_game.events.send(&"player_death", {"userid": _id("C1"), "attacker": _id("T1"), "weapon": "weapon_ak47",
		"headshot": true})
	_game.events.flush()
	_check_equal(hud.kill_feed.notices().size(), 1, "and shows the game's deaths")
	_check_equal(hud.kill_feed.notices()[0].yours, KillFeed.Yours.KILLER, "yours marked as yours")
	hud.free()
	await process_frame
	_game.events.send(&"player_death", {"userid": _id("C2")})
	_game.events.flush()
	_check(true, "a freed HUD stops listening")
