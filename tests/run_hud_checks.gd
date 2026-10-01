extends "res://tests/check_suite.gd"

## The HUD's own checks: the elements redraw only when what they show
## changes and stop working once an animation is over, the numbers they
## show are CS2's (the reserve as the game counts it, the money's odometer,
## the clock), they blend as CS2's do, the font falls back to Rajdhani
## without the extraction and is a pre-drawn distance field with it, and the
## HUD's pieces sit where CS2 puts them. How they look is checked by a
## render beside CS2's screenshot on Sid's machine.

var _redraws := {}


## A HUD fixture needs a player, but no camera, models or input capture.
class PromptPlayer extends PlayerController:
	func _ready() -> void:
		config = MovementConfig.new()


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
	await _test_the_bomb_carrier()
	await _test_the_pickup_prompt()
	await _test_the_alert_lines()
	await _test_the_buy_menu_agent()
	await _test_the_weapon_selection()
	_test_what_is_read_ahead()
	_finish("HUD")


## Every image a part of the HUD asks HudStyle.icon() for by name is one
## the HUD reads before the match (GameHud.images_to_read), so none is read
## from the disk on the frame that first shows it. The parts' scripts are
## read for the names: a part that draws a new image and does not name it in
## GameHud.IMAGES fails here.
func _test_what_is_read_ahead() -> void:
	var read_ahead := GameHud.images_to_read()
	var asked := {}
	var call := RegEx.create_from_string("HudStyle\\.icon\\(([^\\n]*)")
	var literal := RegEx.create_from_string("\"([^\"]+)\"")
	var scripts := PackedStringArray()
	for folder: String in ["res://src/ui", "res://src/economy", "res://src/player", "res://src/match"]:
		for file in DirAccess.get_files_at(folder):
			if file.ends_with(".gd") and file not in ["hud_style.gd", "game_hud.gd"]:
				scripts.append(folder.path_join(file))
	for path in scripts:
		var text := FileAccess.get_file_as_string(path)
		for found in call.search_all(text):
			for name in literal.search_all(found.get_string(1)):
				# A name has a folder in it; "CT" and the like are not names.
				if name.get_string(1).contains("/"):
					asked[name.get_string(1)] = path.get_file()
	var missing := PackedStringArray()
	for name: String in asked:
		if not read_ahead.has(name):
			missing.append("%s (%s)" % [name, asked[name]])
	_check(asked.size() >= 10 and missing.is_empty(),
		"every image the HUD's parts ask for by name is read before the match (%d names in %d scripts; not read: %s)"
			% [asked.size(), scripts.size(), ", ".join(missing) if not missing.is_empty() else "none"])
	_check(
		KillFeed.ICONS.values().all(func(path: String) -> bool: return read_ahead.has(path))
			and HealthAmmoCenter.RESERVE_ICONS.keys().all(func(gun: String) -> bool: return read_ahead.has(HealthAmmoCenter.reserve_icon(gun)))
			and read_ahead.has(HealthAmmoCenter.reserve_icon("weapon_m4a1")),
		"and so are those asked for from a table: the kill feed's marks and every gun's reserve icon"
	)
	# Read, they are in hand: asking again reads nothing.
	HudStyle.read_ahead(read_ahead)
	var in_hand := 0
	for name: String in read_ahead:
		if HudStyle._icons.has(name):
			in_hand += 1
	var items := 0
	for definition in ItemRegistry.all():
		if HudStyle._icons.has("icons/equipment/" + definition.item_class.trim_prefix("weapon_").trim_prefix("item_")):
			items += 1
	_check(in_hand == read_ahead.size() and items == ItemRegistry.all().size() and HudStyle._faces.size() == HudStyle.FACES.size(),
		"read ahead, every one of them is in hand, found or not: %d images, %d items' icons, %d faces"
			% [in_hand, items, HudStyle._faces.size()])


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
	_check(HudStyle.icon("no/such/icon") == null, "a missing icon is null, for the element to draw its own")


func _test_elements_redraw_only_on_change() -> void:
	var cluster := HealthAmmoCenter.new()
	root.add_child(cluster)
	cluster.draw.connect(func() -> void: _redraws["cluster"] = _redraws.get("cluster", 0) + 1)
	var show := func(clip: int) -> void:
		cluster.show_values("T", HudStyle.TEAMMATE_COLOURS[3], 100, 100, true, "weapon_ak47", true, clip, 30, 90, true, false)
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
	cluster.show_values("T", HudStyle.T_COLOUR, 100, 0, false, "", false, 0, 1, 0, true, false)
	cluster.show_values("T", HudStyle.T_COLOUR, 73, 0, false, "", false, 0, 1, 0, true, false)
	_check(cluster.is_processing() and cluster.is_animating(), "a hit throws the red copy of the health, running _process while it falls")
	# Its clocks run by name (_advance): one that did not advance stopped
	# the panel as one that had run out does, and read as nothing wrong.
	var part := HealthAmmoCenter.JITTER_SECONDS * 0.5
	cluster._process(part)
	_check(cluster.is_animating() and is_equal_approx(float(cluster.get("_damage")), part)
		and is_equal_approx(float(cluster.get("_jitter")), part),
		"part of the way through it is falling still, its clocks as far on as the frame was long (%.3f and %.3f of %.3f)" % [
			float(cluster.get("_damage")), float(cluster.get("_jitter")), part])
	cluster._process(HealthAmmoCenter.JITTER_SECONDS)
	_check(cluster.is_animating() and float(cluster.get("_jitter")) < 0.0 and float(cluster.get("_damage")) > 0.0,
		"its shake is over before its fall is")
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
	# The ring's colour: a player's own in a match, the team's without one.
	var state := MatchState.new()
	var sides := ["T", "CT", "T", "T", "T", "T", "T"]
	for i in sides.size():
		var player := PlayerSim.new()
		player.team = sides[i]
		player.userid = 10 + i
		state.add_player(player)
	var t_colours := {}
	for player in state.players.slice(0, 1) + state.players.slice(2, 6):
		t_colours[state.colour_of(player)] = true
	_check(t_colours.size() == 5 and state.colour_of(state.players[1]) >= 0,
		"in a match each player draws a colour, no two alike on a team while the five last (%s)" % [t_colours.keys()])
	_check(state.colour_of(state.players[6]) >= 0, "and a sixth on a team still gets one")
	var draws := {}
	for seed in 8:
		var again := MatchState.new()
		again.colour_seed = seed
		var alone := PlayerSim.new()
		alone.team = "T"
		alone.userid = 10
		again.add_player(alone)
		draws[again.colour_of(alone)] = true
		alone.free()
		again.free()
	_check(draws.size() > 1, "and the draw differs from match to match (%s)" % [draws.keys()])
	_check(GameHud.player_colour(state, state.players[1]) == HudStyle.TEAMMATE_COLOURS[state.colour_of(state.players[1])],
		"the HUD shows the colour the match drew")
	_check(GameHud.player_colour(null, state.players[0]) == HudStyle.T_COLOUR and GameHud.player_colour(null, state.players[1]) == HudStyle.CT_COLOUR,
		"without one, the team's own colour, as CS2's deathmatch rings the emblem")
	for player in state.players:
		player.free()
	state.free()
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


## Who carries the bomb (playtest issue 18): CS2's C4 on the carrier's card,
## your own team's only, and "You picked up the bomb" when you walk over it
## on the ground, not when a round hands it to you.
func _test_the_bomb_carrier() -> void:
	var state := MatchState.new()
	root.add_child(state)
	var you := PlayerSim.new()
	you.team = "T"
	var mate := PlayerSim.new()
	mate.team = "T"
	var enemy := PlayerSim.new()
	enemy.team = "CT"
	for n in 3:
		var sim: PlayerSim = [you, mate, enemy][n]
		sim.userid = n
		root.add_child(sim)
		state.add_player(sim)
	var counter := TeamCounter.new()
	root.add_child(counter)
	await process_frame
	var bomb := C4.new()
	var carrying := func() -> Array:
		var marked := []
		for side: String in MatchState.SIDES:
			for card: TeamCounter.Card in counter.cards[side]:
				if card.bomb:
					marked.append(card.name)
		return marked
	counter.show_match(state, you, null, 0, bomb)
	_check(carrying.call().is_empty(), "no card is marked before the bomb is handed out")
	bomb.give_to(mate.userid)
	counter.show_match(state, you, null, 0, bomb)
	_check_equal(carrying.call(), [str(mate.name)], "a teammate carrying it is marked on their card")
	bomb.give_to(you.userid)
	counter.show_match(state, you, null, 0, bomb)
	_check_equal(carrying.call(), [str(you.name)], "and you, on your own")
	counter.show_match(state, enemy, null, 0, bomb)
	_check(carrying.call().is_empty(), "the other side's cards never show it")
	_check(TeamCounter.C4_WASH == Color8(255, 255, 95), "washed CS2's yellow")
	_check(
		Rect2(0.0, 0.0, TeamCounter.CARD, TeamCounter.CARD).encloses(TeamCounter.C4_BOX)
			and TeamCounter.C4_BOX.position.x > TeamCounter.CARD * 0.5 and TeamCounter.C4_BOX.position.y > TeamCounter.CARD * 0.5,
		"in the portrait's lower right, as on Sid's CS2 screenshot"
	)
	_check(
		TeamCounter.C4_ROW.position.y > TeamCounter.GUN_ROW.end.y and TeamCounter.C4_ROW.end.y < TeamCounter.TOP + TeamCounter.COLUMN_HEIGHT
			and absf(TeamCounter.C4_ROW.get_center().x - TeamCounter.CARD * 0.5) < 1.0,
		"and again in the column, centred under the gun"
	)

	# "[E] Take Bomb" under the crosshair, looking at a bot teammate who
	# carries it.
	mate.is_bot = true
	mate.global_position = Vector3(0.0, 0.0, -50.0)
	you.global_position = Vector3.ZERO
	you.yaw_degrees = 0.0
	you.pitch_degrees = rad_to_deg(atan2(C4.BODY_MIDDLE - you.eye_height(), 50.0))
	bomb.give_to(mate.userid, mate.global_position)
	_check_equal(UsePrompt.line_for(you, bomb, mate), "[E] Take Bomb", "looking at a bot carrying it: [E] Take Bomb")
	_check(UsePrompt.TAKE_BOMB_COLOUR == Color("e5da25"), "in CS2's yellow for it")
	you.yaw_degrees = 180.0
	_check_equal(UsePrompt.line_for(you, bomb, mate), "", "not looking away")
	you.yaw_degrees = 0.0
	mate.is_bot = false
	_check_equal(UsePrompt.line_for(you, bomb, mate), "", "nor at a person carrying it")
	bomb.give_to(you.userid)
	_check_equal(GameHud.bomb_hint(C4.State.NONE, C4.NOBODY, bomb, you.userid), "",
		"handed it at a round's start, no hint: the card says so")
	_check_equal(GameHud.bomb_hint(C4.State.DROPPED, C4.NOBODY, bomb, you.userid), "You picked up the bomb",
		"picked up off the ground, CS2's hint")
	_check_equal(GameHud.bomb_hint(C4.State.DROPPED, C4.NOBODY, bomb, mate.userid), "",
		"but not when someone else picks it up")
	for node: Node in [counter, you, mate, enemy, state]:
		node.free()


func _test_the_pickup_prompt() -> void:
	var you := PromptPlayer.new()
	root.add_child(you)
	var game := GameSystems.new()
	you.userid = game.add_player(you, null, you.inventory)
	var selected := {"item": "weapon_ak47", "reads": 0}
	game.provide(&"use_pickup_item", func(_userid: int) -> String:
		selected.reads += 1
		return selected.item)
	var hud := GameHud.new()
	hud.player = you
	hud.userid = you.userid
	hud.game = game
	hud.set_process(false)
	hud.set_physics_process(false)
	root.add_child(hud)
	hud._physics_process(0.0)
	hud._process(0.0)
	_check_equal(hud.use_prompt.text, "Press [E] to pick up AK-47", "a HUD without C4 shows the ground gun prompt")
	_check_equal(hud.use_prompt.colour, Color.WHITE, "ground pickup text is white")
	selected.item = "weapon_hegrenade"
	hud._process(0.0)
	_check(selected.reads == 1 and hud.use_prompt.text.ends_with("AK-47"), "drawing reads the cached selection without another sight query")
	hud._physics_process(0.0)
	hud._process(0.0)
	_check_equal(hud.use_prompt.text, "Press [E] to pick up High Explosive Grenade", "the next physics frame selects and names the grenade")
	var menu := BuyMenu.new()
	hud.buy_menu = menu
	hud._process(0.0)
	_check_equal(hud.use_prompt.text, "", "opening the buy menu hides the prompt immediately")
	hud._physics_process(0.0)
	_check(selected.reads == 2 and hud._pickup_item.is_empty(), "no sight query while buying")
	hud.buy_menu = null
	menu.free()
	you.alive = false
	hud._process(0.0)
	_check_equal(hud.use_prompt.text, "", "a dead player has no pickup prompt")
	you.alive = true
	selected.item = ""
	hud._physics_process(0.0)
	hud._process(0.0)
	_check_equal(hud.use_prompt.text, "", "no selected ground item clears the prompt")
	hud.free()
	you.free()
	await process_frame


func _test_the_alert_lines() -> void:
	var state := MatchState.new()
	root.add_child(state)
	_check_equal(GameHud.alert_line(state)[0], "Warmup", "warmup says Warmup, as CS2's alert does")
	state.phase = MatchState.Phase.LIVE
	_check_equal(GameHud.alert_line(state)[0], "", "a live round has no alert")
	state.phase = MatchState.Phase.ROUND_END
	state.last_winner = "CT"
	_check_equal(GameHud.alert_line(state)[0], "", "a round's end leaves who won to the win panel")
	state.free()
	await process_frame


## The agent beside the buy menu: CS2's pose for each item as its UI graph
## picks it, for everything the menu sells on either side; the map camera's
## view cut down to the strip it is drawn in, with the agent in the strip;
## and, where the poses were extracted, the agent built from them, the other
## side's read with it, and each item's own bones where its pose puts them.
func _test_the_buy_menu_agent() -> void:
	_check_equal(BuyMenuAgent.pose_for("weapon_ak47", "T"), "t/t_buymenu_ak_03",
		"a terrorist holds the AK-47 in CS2's T pose for it")
	_check_equal(BuyMenuAgent.pose_for("weapon_m4a1", "CT"), "ct/ct_buymenu_m4a1",
		"a counter-terrorist holds the M4A4 in the M4A1-S's pose, as CS2's graph has it")
	_check_equal(BuyMenuAgent.pose_for("weapon_m4a1", "T"), "t/t_buymenu_m4a4", "and a terrorist in its own")
	_check(BuyMenuAgent.pose_for("weapon_flashbang", "T") == "shared/sh_buymenu_flash"
		and BuyMenuAgent.pose_for("weapon_flashbang", "CT") == "shared/sh_buymenu_flash",
		"both sides share the grenades' poses")
	_check(BuyMenuAgent.pose_for("item_kevlar", "T") == BuyMenuAgent.pose_for("item_assaultsuit", "CT"),
		"the vest, and the vest with a helmet, share the armour's")
	_check_equal(BuyMenuAgent.pose_for("weapon_nothing", "T"), "", "an item the graph has no pose for has none")
	var unposed := PackedStringArray()
	for side: String in ["T", "CT"]:
		for item_class in Loadout.items(side):
			if BuyMenuAgent.pose_for(item_class, side).is_empty():
				unposed.append("%s %s" % [side, item_class])
	_check(unposed.is_empty(), "everything the menu sells on either side has a pose (none for %s)" % ", ".join(unposed))

	var screen := Vector2(1920.0, 1080.0)
	var whole: Array = BuyMenuAgent.frustum(Rect2(Vector2.ZERO, screen), screen)
	var height := 2.0 * BuyMenuAgent.NEAR * tan(deg_to_rad(BuyMenuAgent.FOV * 0.5))
	_check(is_equal_approx(whole[0], height) and (whole[1] as Vector2).is_zero_approx(),
		"over the whole screen the camera is the map's: 30 degrees from top to bottom, centred")
	var strip := Rect2(1020.0, 0.0, 900.0, 1080.0)
	var cut: Array = BuyMenuAgent.frustum(strip, screen)
	_check(is_equal_approx(cut[0], height) and is_equal_approx((cut[1] as Vector2).x, (1470.0 - 960.0) * height / 1080.0)
		and is_zero_approx((cut[1] as Vector2).y), "a strip of it sees its part of that view, moved right as the strip is")
	var ahead := SourceEntities.to_game(BuyMenuAgent.AGENT_AT) - SourceEntities.to_game(BuyMenuAgent.CAMERA_AT)
	var yaw := deg_to_rad(BuyMenuAgent.CAMERA_YAW)
	var forward := SourceEntities.to_game(Vector3(cos(yaw), sin(yaw), 0.0))
	var across := screen.x * 0.5 + ahead.dot(forward.cross(Vector3.UP)) / ahead.dot(forward) \
		* screen.y * 0.5 / tan(deg_to_rad(BuyMenuAgent.FOV * 0.5))
	_check(absf(across - 1397.0) < 10.0, "the map stands the agent %.0f px across, where Sid's screenshot has it (1397)" % across)

	if not ResourceLoader.exists(BuyMenuAgent.pose_path(BuyMenuAgent.RIG_POSE)):
		print("the buy menu's poses not extracted; skipping the agent's build (scripts/extract_assets.sh hud)")
		return
	var agent := BuyMenuAgent.new()
	root.add_child(agent)
	_check(agent.build("T"), "a terrorist's agent builds from CS2's poses")
	# Shut, as the menu starts: past the fit of the pose it was built in,
	# its skeleton fits nothing a frame (its twist bones, skin and eyes),
	# where it fitted in every one.
	await process_frame
	var fits := [0]
	agent.body.character_rig.skeleton_updated.connect(func() -> void: fits[0] += 1)
	await process_frame
	await process_frame
	var shut_fits: int = fits[0]
	agent.draw_while(true)
	await process_frame
	await process_frame
	_check(shut_fits == 0 and fits[0] > 0 and agent.body.process_mode == Node.PROCESS_MODE_INHERIT,
		"shut, the agent fits nothing (%d in two frames); open, it moves (%d)" % [shut_fits, fits[0] - shut_fits])
	agent.draw_while(false)
	_check(agent.body.process_mode == Node.PROCESS_MODE_DISABLED, "and shut again, it stops")
	var unread := PackedStringArray()
	for item_class: String in BuyMenuAgent.POSES:
		for side: String in ["T", "CT"]:
			if not BuyMenuAgent._clips.has(BuyMenuAgent.pose_path(BuyMenuAgent.pose_for(item_class, side))):
				unread.append("%s %s" % [side, item_class])
	_check(unread.is_empty(), "with both sides' poses read, none left for half time (%s)" % ", ".join(unread))
	agent.show_item("weapon_elite")
	var elites := agent._models.get("weapon_elite") as Node3D
	var rig := elites.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D if elites != null else null
	var moved := func(bone_name: String) -> bool:
		var bone := rig.find_bone(bone_name)
		return bone >= 0 and not rig.get_bone_pose(bone).is_equal_approx(rig.get_bone_rest(bone))
	_check(rig != null and moved.call("weapon_hand_l") and moved.call("weapon_hand_r"),
		"the Dual Berettas go one to each hand, as their pose puts them")
	_check(rig != null and moved.call("elite_holster"), "and their holster, which the model names otherwise, with them")
	agent.show_item("weapon_xm1014")
	var shotgun := agent._models.get("weapon_xm1014") as Node3D
	var shells := shotgun.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D if shotgun != null else null
	_check(shells != null and shells.get_bone_pose_scale(shells.find_bone("shell1")).x < 0.01,
		"the XM1014's loaded shells go, as its pose hides them")
	_check(not elites.visible and shotgun.visible, "only what is held shows")
	agent.show_item("item_kevlar")
	var shown := 0
	for model: Variant in agent._models.values():
		if model != null and (model as Node3D).visible:
			shown += 1
	var pose := (agent._tree.tree_root as AnimationNodeBlendTree).get_node(&"pose") as AnimationNodeAnimation
	_check(shown == 0 and pose.animation == &"sh_buymenu_armor_helmet",
		"over the armour the agent holds nothing, in the armour's pose")
	agent.queue_free()
	await process_frame


## What you carry, in the bottom right (reference/playtest-2026-09-25.md,
## issue 15): a row for each slot carried in, the primary's first; it comes
## up when what is in hand changes, not for the first look, slides in, holds
## and fades, and stops working once gone; icons in the team's colour turned
## as CS2's css turns them, brighter in hand, the C4 in its own.
func _test_the_weapon_selection() -> void:
	var inventory := Inventory.new()
	inventory.give_starting_items("T")
	for item_class in ["weapon_ak47", "weapon_flashbang", "weapon_flashbang", "weapon_smokegrenade", "weapon_c4"]:
		inventory.add(item_class)
	inventory.select("weapon_ak47")
	var rows := WeaponSelection.rows_for(inventory)
	var keys := rows.map(func(row: Array) -> int: return row[0])
	_check(keys == [1, 2, 3, 4, 5] and rows[3][1] == [["weapon_flashbang", 2], ["weapon_smokegrenade", 1]]
		and rows[4][1] == [["weapon_c4", 1]],
		"a row a slot, 1 to 5, the grenades in one row with the two flashbangs counted (%s)" % [rows])

	var list := WeaponSelection.new()
	root.add_child(list)
	await process_frame
	var box := list.get_global_rect()
	_check(is_equal_approx(box.end.x, 1920.0 - WeaponSelection.ROW_RIGHT) and is_equal_approx(box.end.y, 1080.0 - WeaponSelection.ALWAYS_ON)
		and is_equal_approx(box.size.x, WeaponSelection.ROW_WIDTH),
		"it stands in the bottom right, 300 wide, 6 in from the edge, on the always-on row's 84 (%s)" % box)
	var added := list.material as CanvasItemMaterial
	_check(added != null and added.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD and list.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"it adds its light, as the items' `additive` class does, and never takes the mouse")
	list.show_inventory("T", rows, "weapon_ak47")
	_check(not list.is_showing() and not list.is_processing(), "the first look at what you carry brings nothing up")
	list.show_inventory("T", rows, "weapon_ak47")
	_check(not list.is_showing(), "nor does the same again")
	list.show_inventory("T", rows, "weapon_glock")
	_check(list.is_showing() and list.is_processing() and is_zero_approx(list._slide), "a switch brings it up, sliding in")
	list._process(WeaponSelection.SLIDE_SECONDS)
	_check(is_equal_approx(list._slide, 1.0) and is_equal_approx(list.opacity, 1.0), "in after 0.2 s")
	list._process(WeaponSelection.HOLD_SECONDS - WeaponSelection.SLIDE_SECONDS + 0.01)
	list._process(WeaponSelection.FADE_SECONDS * 0.5)
	_check(list.opacity > 0.0 and list.opacity < 1.0, "held, then fading (%.2f)" % list.opacity)
	list._process(WeaponSelection.FADE_SECONDS)
	_check(not list.is_showing() and not list.is_processing(), "gone in 0.1 s, with no _process left running")
	list.show_inventory("T", rows, "weapon_ak47")
	list.hide_now()
	_check(not list.is_showing(), "dying or opening the buy menu puts it away at once")
	list.free()

	var turned := Color.from_hsv(HudStyle.T_COLOUR.h, HudStyle.T_COLOUR.s * 0.96, HudStyle.T_COLOUR.v * 0.9)
	var idle := WeaponSelection.wash("T", "weapon_glock", false)
	var held := WeaponSelection.wash("T", "weapon_glock", true)
	_check(idle.is_equal_approx(Color(turned, 0.8)) and is_equal_approx(held.a, 1.0) and held.b > idle.b
		and not WeaponSelection.wash("T", "weapon_c4", false).is_equal_approx(idle),
		"icons in the team's colour turned by 0, 0.96, 0.9 at 0.8 light, the one in hand brighter at full, the C4 in its own (%s, %s)" % [idle, held])
