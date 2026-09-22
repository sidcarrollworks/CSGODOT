class_name GameHud
extends CanvasLayer

## What the player needs to see and nothing else: a crosshair, health and
## armour in the bottom left (the shield drawn with a helmet's dome on it
## when there is one), the magazine and reserve in the bottom right, a red
## arc round the crosshair on the side each hit came from, and a line
## across the middle when dead, counting down to the respawn.
##
## And, small in the top left, where you are and where you are looking,
## like CS2's getpos: the feet's position in units and the view's yaw and
## pitch in degrees, the numbers a render of the same view is set up from,
## so a screenshot says exactly where it was taken. F3 hides it.

var player: PlayerController

var _health: Label
var _armor: Label
var _shield: Control
var _ammo: Label
var damage_indicator: DamageIndicator
var _dead: Label
var _where: Label


func _ready() -> void:
	var crosshair := Crosshair.new()
	add_child(crosshair)
	_health = _label(Control.PRESET_BOTTOM_LEFT, Vector2(24, -56), HORIZONTAL_ALIGNMENT_LEFT, 28)
	_shield = Control.new()
	_shield.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_shield.position = Vector2(150, -50)
	_shield.size = Vector2(22, 26)
	_shield.draw.connect(_draw_shield)
	add_child(_shield)
	_armor = _label(Control.PRESET_BOTTOM_LEFT, Vector2(180, -56), HORIZONTAL_ALIGNMENT_LEFT, 28)
	damage_indicator = DamageIndicator.new()
	damage_indicator.player = player
	add_child(damage_indicator)
	if player != null:
		player.hurt.connect(func(_amount: float, _zone: StringName, from: Vector3) -> void:
			damage_indicator.hit_from(from))
	_ammo = _label(Control.PRESET_BOTTOM_RIGHT, Vector2(-224, -56), HORIZONTAL_ALIGNMENT_RIGHT, 28)
	_ammo.size.x = 200.0
	_dead = _label(Control.PRESET_CENTER, Vector2(-300, 40), HORIZONTAL_ALIGNMENT_CENTER, 26)
	_dead.size.x = 600.0
	_dead.visible = false
	_where = _label(Control.PRESET_TOP_LEFT, Vector2(12, 8), HORIZONTAL_ALIGNMENT_LEFT, 16)
	_where.add_theme_constant_override("outline_size", 4)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F3:
		_where.visible = not _where.visible


func _process(_delta: float) -> void:
	if player == null:
		return
	if player.hit_target != null:
		_health.text = "+ %d" % roundi(player.hit_target.health)
		var armor := roundi(player.hit_target.armor)
		_armor.text = str(armor)
		_armor.visible = armor > 0
		if _shield.visible != (armor > 0) or _shield.get_meta(&"helmet", false) != player.hit_target.helmet:
			_shield.visible = armor > 0
			_shield.set_meta(&"helmet", player.hit_target.helmet)
			_shield.queue_redraw()
	if player.weapon != null:
		_ammo.text = "%d / %d" % [player.weapon.ammo, player.weapon.reserve]
	_dead.visible = not player.alive
	if not player.alive:
		_dead.text = "You died. Back in %d" % ceili(player.seconds_to_respawn())
	if _where.visible:
		_where.text = where_line(player.global_position, player.input.yaw_degrees, player.input.pitch_degrees)


## The armour's shield, and a helmet's dome over it when there is one.
func _draw_shield() -> void:
	var w := _shield.size.x
	var h := _shield.size.y
	var top := 6.0 if _shield.get_meta(&"helmet", false) else 0.0
	var outline := PackedVector2Array([
		Vector2(0, top), Vector2(w, top), Vector2(w, top + (h - top) * 0.5),
		Vector2(w * 0.5, h), Vector2(0, top + (h - top) * 0.5),
	])
	_shield.draw_colored_polygon(outline, Color(0, 0, 0))
	var inner := PackedVector2Array()
	for point in outline:
		inner.append(point.lerp(Vector2(w * 0.5, top + (h - top) * 0.45), 0.25))
	_shield.draw_colored_polygon(inner, Color(1, 1, 1))
	if top > 0.0:
		_shield.draw_arc(Vector2(w * 0.5, top), w * 0.3, PI, TAU, 12, Color(1, 1, 1), 3.0, true)


## Where a player is and looks, in one line: the feet's position in units,
## the yaw from 0 to 360 and the pitch, up positive.
static func where_line(position: Vector3, yaw_degrees: float, pitch_degrees: float) -> String:
	return "pos %.1f %.1f %.1f   yaw %.1f   pitch %.1f" % [
		position.x, position.y, position.z, fposmod(yaw_degrees, 360.0), pitch_degrees,
	]


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
