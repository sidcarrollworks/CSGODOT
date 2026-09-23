class_name GrenadeLane
extends Node3D

## The range's grenades: throw any of CS2's six from where you stand, at the
## strength of either mouse button or both, and read what each did.
##
##   4  the next grenade (CS2's grenade slot: HE, flash, smoke, molotov,
##      incendiary, decoy)
##   Q  throw it as a left click does, Z as a right click (a lob), X as
##      both buttons
##
## Throwing a grenade from your hand is the player's to do, through the
## inventory and the attack buttons (player_sim.gd), so here a key sends the
## game the throw command ("throw weapon_hegrenade 1"), and the grenade
## leaves your eyes on the next tick, as your hand would throw it. The throw
## takes the grenade from your inventory, so the lane hands you one first:
## there is no limit to how many.
##
## The readout at the bottom says which grenade is in hand and what the
## last ones did: the damage an HE or a fire did and to whom, how long a
## flash blinded you and the dummy, when a smoke or a decoy went off. Your
## own blinding whites out the screen, and the dummy's is in the readout,
## since a bot does not yet look away from what it cannot see.

const NEXT_KEY := KEY_4
const THROW_KEY := KEY_Q
const LOB_KEY := KEY_Z
const BOTH_KEY := KEY_X
const LOG_LINES := 6

var range_node: Node3D
var game: GameSystems
var system: GrenadeSystem
var view: GrenadeView
var overlay: FlashOverlay

## Which grenade is in hand, as an index into GrenadeRules.ALL.
var kind_index: int = 0
var _log := PackedStringArray()
var _label: Label
var _player_id: int = GameEvents.NOBODY
var _dummy_id: int = GameEvents.NOBODY


## Sets up on a range: the grenade system in its game (its world's, which
## steps it), what draws the grenades, the readout and the white-out, which
## covers the HUD as CS2's does.
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


func kind() -> String:
	return GrenadeRules.ALL[kind_index]


func next_kind() -> void:
	kind_index = (kind_index + 1) % GrenadeRules.ALL.size()


## A throw at a strength (GrenadeRules.strength_for), on the next tick.
## The range hands you the grenade first, so it throws without buying; the
## throw takes it back out. Refused when you carry four other grenades
## already (or the other of the molotov and incendiary).
func ask_throw(strength: float) -> void:
	var inventory := game.inventory(_player_id)
	if inventory != null and not inventory.has(kind()):
		if inventory.can_add(kind()) != Inventory.Can.OK:
			_note("no room for a %s: you carry too many grenades" % GrenadeRules.display_name(kind()))
			return
		inventory.add(kind())
	game.command(_player_id, "throw %s %s" % [kind(), strength])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"reset_range"):
		clear()
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).physical_keycode:
		NEXT_KEY:
			next_kind()
		THROW_KEY:
			ask_throw(GrenadeRules.strength_for(true, false))
		LOB_KEY:
			ask_throw(GrenadeRules.strength_for(false, true))
		BOTH_KEY:
			ask_throw(GrenadeRules.strength_for(true, true))


## Every grenade gone and nobody blind: O, the range's reset.
func clear() -> void:
	for entity in game.entities.all():
		if entity is GrenadeEntity or entity is InfernoEntity:
			entity.remove()
	system.clear()
	_log.clear()


func _process(_delta: float) -> void:
	if _label == null:
		return
	var lines := PackedStringArray([
		"GRENADE  %s     4 next   Q throw   Z lob   X both" % GrenadeRules.display_name(kind()),
	])
	var blind := system.blind_amount(_dummy_id)
	if blind > 0.0:
		lines.append("dummy blinded: %d%% white" % roundi(blind * 100.0))
	lines.append_array(_log)
	_label.text = "\n".join(lines)


func log_lines() -> PackedStringArray:
	return _log


## What the log says of the game's events: the grenades' own, and the hurt
## and blinding they did.
func _on_event(event: GameEvent) -> void:
	var line := ""
	var fields := event.fields
	match event.name:
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
