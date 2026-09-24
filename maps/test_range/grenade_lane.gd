class_name GrenadeLane
extends Node3D

## The range's grenades: CS2's, thrown from your hand, and what each did.
##
## Throwing is the player's own (player_sim.gd): 4 takes a grenade out,
## pressed again the next one; either attack button pulls the pin and
## letting go throws it, the left alone overhand, the right alone a lob,
## both between. The throw takes the grenade from your inventory, as in a
## match, so the lane stocks you with four, the most CS2 lets you carry (an
## HE, a flashbang, a smoke and your side's fire grenade), and hands back
## each one you throw: there is no limit to how many. A decoy, or the other
## side's fire grenade, is the buy menu's, with room made for it (G drops
## the grenade in hand).
##
## The readout at the bottom says what the last ones did: the damage an HE
## or a fire did and to whom, how long a flash blinded you and the dummy,
## when a smoke or a decoy went off. Your own blinding whites out the
## screen, and the dummy's is in the readout, since a bot does not yet look
## away from what it cannot see.

const LOG_LINES := 6

var range_node: Node3D
var game: GameSystems
var system: GrenadeSystem
var view: GrenadeView
var overlay: FlashOverlay

var _log := PackedStringArray()
var _label: Label
var _player_id: int = GameEvents.NOBODY
var _dummy_id: int = GameEvents.NOBODY


## Sets up on a range: the grenade system in its game (its world's, which
## steps it), what draws the grenades, the readout and the white-out, which
## covers the HUD as CS2's does; and your grenades.
func build(p_range: Node3D) -> void:
	range_node = p_range
	game = range_node.game
	_player_id = game.roster.userid_of(range_node.player)
	_dummy_id = game.roster.userid_of(range_node.dummy)
	system = GrenadeSystem.new()
	game.add_system(system)
	view = GrenadeView.new()
	view.name = "GrenadeView"
	add_child(view)
	view.watch(game)
	game.events.listen_all(_on_event)
	stock()

	var canvas := CanvasLayer.new()
	canvas.layer = 2
	add_child(canvas)
	overlay = FlashOverlay.new()
	overlay.game = game
	overlay.viewer_id = _player_id
	canvas.add_child(overlay)
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_label.offset_bottom = -24.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	canvas.add_child(_label)


## The grenades the lane keeps you in: an HE, a flashbang, a smoke and your
## side's fire grenade.
func stocked() -> Array[String]:
	var fire := GrenadeRules.INCENDIARY if String(range_node.player.team) == "CT" else GrenadeRules.MOLOTOV
	return [GrenadeRules.HE, GrenadeRules.FLASHBANG, GrenadeRules.SMOKE, fire]


## Hands you whichever of them you are without, where there is room.
func stock() -> void:
	var inventory := game.inventory(_player_id)
	if inventory == null:
		return
	for grenade in stocked():
		if not inventory.has(grenade) and inventory.can_add(grenade) == Inventory.Can.OK:
			inventory.add(grenade)


## Every grenade gone and nobody blind: O, the range's reset.
func clear() -> void:
	for entity in game.entities.all():
		if entity is GrenadeEntity or entity is InfernoEntity:
			entity.remove()
	system.clear()
	_log.clear()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"reset_range"):
		clear()


func _process(_delta: float) -> void:
	if _label == null:
		return
	var lines := PackedStringArray([
		"GRENADES  4 takes one out   left throws   right lobs   both between",
	])
	var blind := system.blind_amount(_dummy_id)
	if blind > 0.0:
		lines.append("dummy blinded: %d%% white" % roundi(blind * 100.0))
	lines.append_array(_log)
	_label.text = "\n".join(lines)


func log_lines() -> PackedStringArray:
	return _log


## What the log says of the game's events: the grenades' own, and the hurt
## and blinding they did. A grenade of yours thrown is handed back, and a
## spawn, which strips you, stocks you again.
func _on_event(event: GameEvent) -> void:
	var line := ""
	var fields := event.fields
	match event.name:
		&"grenade_thrown", &"player_spawn":
			if int(fields["userid"]) == _player_id:
				stock()
			return
		&"hegrenade_detonate", &"flashbang_detonate", &"smokegrenade_detonate", &"decoy_started", \
				&"decoy_detonate", &"molotov_detonate", &"inferno_extinguish", &"smokegrenade_expired":
			line = String(event.name).replace("_", " ")
		&"player_hurt":
			if not GrenadeRules.is_grenade(String(fields["weapon"])) and String(fields["weapon"]) != "":
				return
			line = "%s took %d from %s, %d left" % [
				_who(int(fields["userid"])), int(fields["dmg_health"]),
				GrenadeRules.display_name(String(fields["weapon"])) if fields["weapon"] != "" else "fire", int(fields["health"]),
			]
		&"player_blind":
			line = "%s blinded for %.1f s" % [_who(int(fields["userid"])), float(fields["blind_duration"])]
		_:
			return
	_note(line)


func _note(line: String) -> void:
	_log.insert(0, line)
	if _log.size() > LOG_LINES:
		_log.resize(LOG_LINES)


func _who(userid: int) -> String:
	if userid == _player_id:
		return "you"
	if userid == _dummy_id:
		return "the dummy"
	return "the shooter"
