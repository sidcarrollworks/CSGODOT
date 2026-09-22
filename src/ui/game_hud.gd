class_name GameHud
extends CanvasLayer

## What the player needs to see and nothing else: a crosshair, health in
## the bottom left, the magazine and reserve in the bottom right, and a
## line across the middle when dead, counting down to the respawn.

var player: PlayerController

var _health: Label
var _ammo: Label
var _dead: Label


func _ready() -> void:
	var crosshair := Crosshair.new()
	add_child(crosshair)
	_health = _label(Control.PRESET_BOTTOM_LEFT, Vector2(24, -56), HORIZONTAL_ALIGNMENT_LEFT, 28)
	_ammo = _label(Control.PRESET_BOTTOM_RIGHT, Vector2(-224, -56), HORIZONTAL_ALIGNMENT_RIGHT, 28)
	_ammo.size.x = 200.0
	_dead = _label(Control.PRESET_CENTER, Vector2(-300, 40), HORIZONTAL_ALIGNMENT_CENTER, 26)
	_dead.size.x = 600.0
	_dead.visible = false


func _process(_delta: float) -> void:
	if player == null:
		return
	if player.hit_target != null:
		_health.text = "+ %d" % roundi(player.hit_target.health)
	if player.weapon != null:
		_ammo.text = "%d / %d" % [player.weapon.ammo, player.weapon.reserve]
	_dead.visible = not player.alive
	if not player.alive:
		_dead.text = "You died. Back in %d" % ceili(player.seconds_to_respawn())


func _label(preset: Control.LayoutPreset, at: Vector2, alignment: HorizontalAlignment, size: int) -> Label:
	var label := Label.new()
	label.set_anchors_preset(preset)
	label.position = at
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)
	return label
