extends "res://tests/check_suite.gd"

## The HUD's own checks: the elements redraw only when what they show
## changes and stop working once an animation is over, the numbers they
## show are CS2's (the reserve in magazines, the clock), the font falls back
## to Rajdhani without the extraction, and the HUD's pieces sit where CS2
## puts them. How they look is checked by a render on Sid's machine.

var _redraws := {}


func _initialize() -> void:
	root.size = Vector2i(1920, 1080)
	await process_frame
	_test_the_font_and_style()
	await _test_elements_redraw_only_on_change()
	await _test_animations_stop()
	_test_numbers()
	await _test_placement()
	await _test_the_alert_lines()
	_finish("HUD")


func _test_the_font_and_style() -> void:
	var font := HudStyle.font()
	_check(font != null, "the HUD has a font")
	if not HudStyle.has_cs2_font():
		_check(font.resource_path == HudStyle.FALLBACK_BOLD, "without CS2's Stratum2 it is Rajdhani (%s)" % font.resource_path)
	_check(HudStyle.team_colour("T").to_html(false) == "eabe54", "the terrorists' colour is CS2's t-color #eabe54")
	_check(HudStyle.team_colour("CT").to_html(false) == Color8(150, 200, 250).to_html(false), "the counter-terrorists' is ct-color rgb(150, 200, 250)")
	_check(HudStyle.icon("no/such/icon") == null, "a missing icon is null, for the element to draw its own")


func _test_elements_redraw_only_on_change() -> void:
	var cluster := HealthAmmoCenter.new()
	root.add_child(cluster)
	cluster.draw.connect(func() -> void: _redraws["cluster"] = _redraws.get("cluster", 0) + 1)
	cluster.show_values("T", 100, 100, true, true, 30, 30, 90)
	await process_frame
	await process_frame
	var after_first: int = _redraws.get("cluster", 0)
	for i in 5:
		cluster.show_values("T", 100, 100, true, true, 30, 30, 90)
		await process_frame
	_check_equal(_redraws.get("cluster", 0), after_first, "the same numbers five frames running redraw nothing")
	cluster.show_values("T", 100, 100, true, true, 29, 30, 90)
	await process_frame
	_check_equal(_redraws.get("cluster", 0), after_first + 1, "one round fired redraws it once")
	_check(not cluster.is_processing(), "and idle, it has no _process running")
	cluster.free()


func _test_animations_stop() -> void:
	var cluster := HealthAmmoCenter.new()
	root.add_child(cluster)
	cluster.show_values("T", 100, 0, false, false, 0, 1, 0)
	cluster.show_values("T", 73, 0, false, false, 0, 1, 0)
	_check(cluster.is_processing() and cluster.is_animating(), "a hit flashes the health, running _process while it does")
	cluster._process(HealthAmmoCenter.DAMAGE_FLASH_SECONDS + 0.01)
	_check(not cluster.is_processing(), "and stops once the flash is over")
	cluster.free()

	var money := MoneyPanel.new()
	root.add_child(money)
	money.show_values("CT", 800, false)
	money.show_values("CT", 4050, true)
	_check(money.shown() == 800 and money.is_processing(), "money rolls from the old amount (%d)" % money.shown())
	money._process(MoneyPanel.ROLL_SECONDS * 0.5)
	_check(money.shown() > 800 and money.shown() < 4050, "half way through, it is between (%d)" % money.shown())
	money._process(MoneyPanel.ROLL_SECONDS)
	_check(money.shown() == 4050 and not money.is_processing(), "then shows the new amount and stops (%d)" % money.shown())
	money.free()

	var alert := HudAlert.new()
	root.add_child(alert)
	alert.say("Warmup")
	_check(alert.is_showing() and alert.is_processing(), "an alert opens out")
	alert._process(HudAlert.OPEN_SECONDS)
	_check(not alert.is_processing(), "and is still once open")
	alert.say("")
	_check(not alert.is_showing(), "an empty line hides it")
	alert.free()


func _test_numbers() -> void:
	_check_equal(HealthAmmoCenter.reserve_magazines(90, 30), 3, "an AK-47's 90 in reserve read 3, as CS2 shows it")
	_check_equal(HealthAmmoCenter.reserve_magazines(100, 50), 2, "a P90's 100 read 2")
	_check_equal(HealthAmmoCenter.reserve_magazines(31, 30), 2, "a part-full magazine counts whole")
	_check_equal(HealthAmmoCenter.reserve_magazines(0, 30), 0, "none reads 0")
	_check_equal(GameHud.money_text(13650), "$13650", "money reads as CS2's $13650")


func _test_placement() -> void:
	var cluster := HealthAmmoCenter.new()
	var money := MoneyPanel.new()
	var counter := TeamCounter.new()
	for element: Control in [cluster, money, counter]:
		root.add_child(element)
	await process_frame
	var screen := Vector2(1920, 1080)
	var box := cluster.get_global_rect()
	_check(is_equal_approx(box.get_center().x, screen.x * 0.5) and is_equal_approx(box.end.y, screen.y - HealthAmmoCenter.BOTTOM_MARGIN),
		"health and ammo sit at the bottom in the middle (%s)" % box)
	_check(money.get_global_rect().position.x == 0.0 and is_equal_approx(money.get_global_rect().end.y, screen.y),
		"money in the bottom left (%s)" % money.get_global_rect())
	_check(is_equal_approx(counter.get_global_rect().get_center().x, screen.x * 0.5) and counter.get_global_rect().position.y == 0.0,
		"the team counter at the top in the middle (%s)" % counter.get_global_rect())
	for element: Control in [cluster, money, counter]:
		_check(element.mouse_filter == Control.MOUSE_FILTER_IGNORE, "%s never takes the mouse" % element.get_script().get_global_name())
		element.free()


func _test_the_alert_lines() -> void:
	var state := MatchState.new()
	root.add_child(state)
	_check_equal(GameHud.alert_line(state)[0], "Warmup", "warmup says Warmup, as CS2's alert does")
	state.phase = MatchState.Phase.LIVE
	_check_equal(GameHud.alert_line(state)[0], "", "a live round has no alert")
	state.phase = MatchState.Phase.ROUND_END
	state.last_winner = "CT"
	_check_equal(GameHud.alert_line(state)[0], "Counter-terrorists win", "a round's end says who won")
	state.free()
	await process_frame
