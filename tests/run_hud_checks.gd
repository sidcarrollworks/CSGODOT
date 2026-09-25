extends "res://tests/check_suite.gd"

## The HUD's own checks: the elements redraw only when what they show
## changes and stop working once an animation is over, the numbers they
## show are CS2's (the reserve as the game counts it, the money's odometer,
## the clock), they blend as CS2's do, the font falls back to Rajdhani
## without the extraction and is a pre-drawn distance field with it, and the
## HUD's pieces sit where CS2 puts them. How they look is checked by a
## render beside CS2's screenshot on Sid's machine.

var _redraws := {}


func _initialize() -> void:
	root.size = Vector2i(1920, 1080)
	await process_frame
	_test_the_font_and_style()
	await _test_elements_redraw_only_on_change()
	await _test_animations_stop()
	_test_numbers()
	await _test_the_odometer()
	await _test_placement_and_blending()
	await _test_the_blur()
	await _test_the_team_counter()
	await _test_the_alert_lines()
	_finish("HUD")


func _test_the_font_and_style() -> void:
	var font := HudStyle.face()
	_check(font != null, "the HUD has a font")
	if HudStyle.has_cs2_font():
		var numbers := font as FontFile
		_check(numbers != null and numbers.get_font_name() == "Stratum2 Bold TF",
			"its numbers are CS2's Stratum2 Bold TF (%s)" % (numbers.get_font_name() if numbers != null else "none"))
		_check(numbers != null and numbers.multichannel_signed_distance_field,
			"imported as a distance field, one set of glyphs for every size")
		var drawn := numbers.get_glyph_list(0, Vector2i(48, 0)).size() if numbers != null and numbers.get_cache_count() > 0 else 0
		_check(drawn >= 95, "with the printable ASCII drawn at import, so a first number rasterizes nothing (%d glyphs)" % drawn)
		_check((HudStyle.face(&"mono_bold") as FontFile).get_font_name() == "Stratum2 Mono",
			"the money's digits are Stratum2 Mono, as CS2's digit panel's are")
	else:
		_check(font.resource_path == HudStyle.FALLBACK_BOLD, "without CS2's Stratum2 it is Rajdhani (%s)" % font.resource_path)
	_check(HudStyle.team_colour("T").to_html(false) == "eabe54", "the terrorists' colour is CS2's t-color #eabe54")
	_check(HudStyle.team_colour("CT").to_html(false) == Color8(150, 200, 250).to_html(false), "the counter-terrorists' is ct-color rgb(150, 200, 250)")
	_check(HudStyle.counter_colour("T").to_html(false) == "ead18a" and HudStyle.counter_colour("CT").to_html(false) == "b5d4ee",
		"the team counter's are color-T #EAD18A and color-CT #B5D4EE")
	_check(HudStyle.ring_colour("T").to_html(false) == Color8(230, 128, 42).to_html(false)
		and HudStyle.ring_colour("CT").to_html(false) == Color8(136, 206, 245).to_html(false),
		"the ring round the emblem is orange for the terrorists and blue for the counter-terrorists")
	_check(HudStyle.icon("no/such/icon") == null, "a missing icon is null, for the element to draw its own")


func _test_elements_redraw_only_on_change() -> void:
	var cluster := HealthAmmoCenter.new()
	root.add_child(cluster)
	cluster.draw.connect(func() -> void: _redraws["cluster"] = _redraws.get("cluster", 0) + 1)
	var show := func(clip: int) -> void:
		cluster.show_values("T", 100, 100, true, "weapon_ak47", true, clip, 30, 90, true, false)
	show.call(30)
	await process_frame
	await process_frame
	var after_first: int = _redraws.get("cluster", 0)
	for i in 5:
		show.call(30)
		await process_frame
	_check_equal(_redraws.get("cluster", 0), after_first, "the same numbers five frames running redraw nothing")
	show.call(29)
	await process_frame
	_check(_redraws.get("cluster", 0) > after_first, "one round fired redraws it")
	cluster._process(HealthAmmoCenter.FIRED_SECONDS + 0.01)
	_check(not cluster.is_processing(), "and once the shot's jolt is over, it has no _process running")
	cluster.free()


func _test_animations_stop() -> void:
	var cluster := HealthAmmoCenter.new()
	root.add_child(cluster)
	cluster.show_values("T", 100, 0, false, "", false, 0, 1, 0, true, false)
	cluster.show_values("T", 73, 0, false, "", false, 0, 1, 0, true, false)
	_check(cluster.is_processing() and cluster.is_animating(), "a hit throws the red copy of the health, running _process while it falls")
	cluster._process(HealthAmmoCenter.DAMAGE_SECONDS + 0.01)
	_check(not cluster.is_processing(), "and stops once it is gone")
	cluster.free()

	var alert := HudAlert.new()
	root.add_child(alert)
	alert.say("Warmup")
	_check(alert.is_showing() and alert.is_processing() and alert.openness() == 0.0,
		"an alert waits a quarter of a second closed, as CS2's transition does")
	alert._process(HudAlert.WAIT_SECONDS + HudAlert.OPEN_SECONDS * 0.5)
	_check(alert.openness() > 0.0 and alert.openness() < 1.0, "then opens out (%.2f)" % alert.openness())
	alert._process(HudAlert.OPEN_SECONDS)
	_check(not alert.is_processing() and alert.openness() == 1.0, "and is still once open")
	alert.say("")
	_check(not alert.is_showing(), "an empty line hides it")
	alert.free()


func _test_numbers() -> void:
	_check_equal(HealthAmmoCenter.reserve_shown(90, 30, true), 3, "an AK-47's 90 in reserve read 3 magazines")
	_check_equal(HealthAmmoCenter.reserve_shown(100, 50, true), 2, "a P90's 100 read 2, as CS2's screenshot shows")
	_check_equal(HealthAmmoCenter.reserve_shown(31, 30, true), 2, "a part-full magazine counts whole")
	_check_equal(HealthAmmoCenter.reserve_shown(0, 30, true), 0, "none reads 0")
	_check_equal(HealthAmmoCenter.reserve_shown(32, 8, false), 32, "a Nova's reserve reads in shells")
	var nova := WeaponLibrary.build("weapon_nova")
	var ak := WeaponLibrary.build("weapon_ak47")
	var mag7 := WeaponLibrary.build("weapon_mag7")
	_check(not nova.reserve_as_clips and ak.reserve_as_clips and mag7.reserve_as_clips,
		"which the game's m_bReserveAmmoAsClips says: not for the Nova, yes for the AK-47 and the magazine-fed MAG-7")
	_check_equal(HealthAmmoCenter.reserve_icon("weapon_p90"), "hud/ammo_reserve_p90", "the P90's reserve has its own magazine's icon")
	_check_equal(HealthAmmoCenter.reserve_icon("weapon_nova"), "hud/ammo_reserve_shotgun_shell", "the Nova's a shell")
	_check_equal(HealthAmmoCenter.reserve_icon("weapon_usp_silencer"), "hud/ammo_reserve_magazine", "any other gun a plain magazine")
	_check_equal(GameHud.money_text(13650), "$13650", "money reads as CS2's $13650")
	_check_equal(GameHud.clock_text(61.2), "1:02", "the clock rounds its seconds up")


func _test_the_odometer() -> void:
	var cells := MoneyPanel.symbols_for(800)
	var read := ""
	for index in cells:
		read += MoneyPanel.SYMBOLS[int(index)]
	_check_equal(read, "  $800", "$800 sits right-aligned in the six cells, as CS2's digit panel pads it")
	var timing := func(t: float) -> float: return MoneyPanel.cubic_bezier(t, 0.9, 0.01, 0.1, 1.0)
	_check(absf(timing.call(0.2) - 0.024) < 0.002 and absf(timing.call(0.5) - 0.504) < 0.002
		and absf(timing.call(0.8) - 0.978) < 0.002,
		"the roll's timing is the script's cubic-bezier(0.9, 0.01, 0.1, 1): 2 %% of the way at a fifth, half at half, 98 %% at four fifths (%.3f, %.3f, %.3f)" % [
			timing.call(0.2), timing.call(0.5), timing.call(0.8)])

	var money := MoneyPanel.new()
	root.add_child(money)
	money.show_values("CT", 800, false)
	_check_equal(money.shown(), "$800", "the first amount shows at once")
	money.show_values("CT", 4050, true)
	_check(money.is_processing(), "a new amount rolls")
	money._process(MoneyPanel.ROLL_SECONDS * 0.5)
	_check(money.shown() != "$800" and money.shown() != "$4050", "half way, the cells are between (%s)" % money.shown())
	money._process(MoneyPanel.ROLL_SECONDS)
	_check(money.shown() == "$4050" and not money.is_processing(), "then read the new amount and stop (%s)" % money.shown())
	money.free()


func _test_placement_and_blending() -> void:
	var cluster := HealthAmmoCenter.new()
	var money := MoneyPanel.new()
	var counter := TeamCounter.new()
	var alert := HudAlert.new()
	var hint := HudAlert.new()
	hint.kind = HudAlert.Kind.HINT
	for element: Control in [cluster, money, counter, alert, hint]:
		root.add_child(element)
	await process_frame
	var screen := Vector2(1920, 1080)
	var box := cluster.get_global_rect()
	_check(is_equal_approx(box.get_center().x, screen.x * 0.5) and is_equal_approx(box.end.y, screen.y - HealthAmmoCenter.BOTTOM),
		"health and ammo sit at the bottom in the middle, the ring's centre 1029 down as on CS2's screenshot (%s)" % box)
	_check(is_equal_approx(box.position.x + HealthAmmoCenter.SIDE - HealthAmmoCenter.INSET - HealthAmmoCenter.TEXT_WIDTH * 0.5, 693.0),
		"the health's number centred 693 across, where CS2 has it")
	_check(money.get_global_rect().position.x == 0.0 and is_equal_approx(money.get_global_rect().end.y, screen.y),
		"money in the bottom left (%s)" % money.get_global_rect())
	_check(is_equal_approx(counter.get_global_rect().get_center().x, screen.x * 0.5) and counter.get_global_rect().position.y == 0.0,
		"the team counter at the top in the middle (%s)" % counter.get_global_rect())
	_check(is_equal_approx(alert.get_global_rect().position.y, 750.7) and is_equal_approx(hint.get_global_rect().position.y, 750.7 + 52.0),
		"the alert's bar 750.7 down, a refusal's 52 below it (%.1f, %.1f)" % [alert.get_global_rect().position.y, hint.get_global_rect().position.y])
	for element: Control in [cluster, money, counter]:
		var added := element.material as CanvasItemMaterial
		_check(added != null and added.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD,
			"%s adds its light, as CS2's `additive` does" % element.get_script().get_global_name())
	var under := cluster.get_children(true).filter(func(child: Node) -> bool: return child.name == "Under")
	_check(under.size() == 1 and (under[0] as CanvasItem).show_behind_parent and (under[0] as CanvasItem).material == null,
		"and the ring's dark disc is drawn under it with the ordinary blend")
	for element: Control in [cluster, money, counter, alert, hint]:
		_check(element.mouse_filter == Control.MOUSE_FILTER_IGNORE, "%s never takes the mouse" % element.get_script().get_global_name())
		element.free()


func _test_the_blur() -> void:
	var cluster := HealthAmmoCenter.new()
	var alert := HudAlert.new()
	var counter := TeamCounter.new()
	for element: Control in [cluster, alert, counter]:
		root.add_child(element)
	await process_frame
	var surfaces := cluster.get_children(true).map(func(child: Node) -> String: return child.name)
	_check(surfaces.slice(0, 3) == ["Copy", "Blur", "Under"],
		"under the ring: the screen copied, then the world blurred, then the dark disc (%s)" % [surfaces])
	var copy := cluster.get_children(true)[0] as BackBufferCopy
	var blur := cluster.get_children(true)[1] as CanvasItem
	_check(copy.copy_mode == BackBufferCopy.COPY_MODE_RECT and blur.show_behind_parent
		and (blur.material as ShaderMaterial).shader.resource_path == "res://src/ui/hud_blur.gdshader",
		"only a rectangle of the screen is copied, and blurred by hud_blur.gdshader")
	var to_screen := root.get_stretch_transform() * cluster.get_global_transform_with_canvas()
	var ring := to_screen * cluster._blur_rect()
	_check(copy.visible and copy.rect.encloses(ring) and copy.rect.size.x < 200.0,
		"the copy is the ring and its reach, on the screen's pixels (%s round %s)" % [copy.rect, ring])
	var net := to_screen * copy.transform
	_check(net.is_equal_approx(Transform2D.IDENTITY),
		"and the copy's own transform undoes its parent's, so its rectangle means the same pixels however Godot reads it")

	var alert_copy := alert.get_children(true).filter(func(child: Node) -> bool: return child is BackBufferCopy)
	_check(alert_copy.size() == 1 and not (alert_copy[0] as CanvasItem).visible, "a hidden alert copies nothing")
	alert.say("Warmup")
	alert._process(HudAlert.WAIT_SECONDS + HudAlert.OPEN_SECONDS)
	_check((alert_copy[0] as CanvasItem).visible, "an open one copies its bar's part of the screen")

	var counter_copy := counter.get_children(true).filter(func(child: Node) -> bool: return child is BackBufferCopy)
	counter._fit_copy()
	_check(counter_copy.size() == 1 and not (counter_copy[0] as CanvasItem).visible,
		"the team counter copies nothing in a live round, when no card shows its equipment")

	var undo := RenderVariants.apply("no_hud_blur", root, root)
	_check(copy.copy_mode == BackBufferCopy.COPY_MODE_DISABLED and not blur.visible,
		"the profiler's no_hud_blur turns the copies and the blur off")
	undo.call()
	_check(copy.copy_mode == BackBufferCopy.COPY_MODE_RECT and blur.visible, "and puts them back")
	for element: Control in [cluster, alert, counter]:
		element.free()


func _test_the_team_counter() -> void:
	var counter := TeamCounter.new()
	root.add_child(counter)
	await process_frame
	var block := counter._block_left()
	_check(counter._card_left(true, 0) + TeamCounter.CARD < block and counter._card_left(false, 0) > block + TeamCounter.BLOCK_WIDTH,
		"the counter-terrorists' cards go out to the left and the terrorists' to the right, whoever you play")
	_check(is_equal_approx(counter.get_global_rect().position.x + counter._card_left(false, 0), 1004.5),
		"the first card starts 1004.5 across, as on CS2's screenshot")
	counter.free()


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
