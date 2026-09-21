extends CanvasLayer

## Live readout of the numbers you tune movement against.
##
## This is the most useful thing in the project right now. "Does it feel right"
## is the goal, but "is horizontal speed 250 while running, does a strafe jump
## gain speed, what did that jump peak at" is how you get there, and none of
## that is visible without a readout.

@export var player_path: NodePath

var _player: PlayerBody
var _label: Label

var _peak_speed: float = 0.0
var _speed_at_takeoff: float = 0.0
var _was_on_ground: bool = true


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(24, 24)
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 6)
	add_child(_label)

	if player_path != NodePath():
		_player = get_node_or_null(player_path) as PlayerBody


func _process(_delta: float) -> void:
	if _player == null:
		return

	var horizontal := Vector2(_player.velocity.x, _player.velocity.z).length()
	_peak_speed = maxf(_peak_speed, horizontal)

	# Speed gained over a whole jump is the number that tells you whether air
	# acceleration is right, so capture it at takeoff and compare on landing.
	if _was_on_ground and not _player.on_ground:
		_speed_at_takeoff = horizontal
	if not _was_on_ground and _player.on_ground:
		_peak_speed = horizontal
	_was_on_ground = _player.on_ground

	var gained := horizontal - _speed_at_takeoff

	_label.text = "\n".join([
		"speed      %6.1f u/s" % horizontal,
		"vertical   %6.1f u/s" % _player.velocity.y,
		"peak       %6.1f u/s" % _peak_speed,
		"jump gain  %+6.1f u/s" % gained,
		"ground     %s" % ("yes" if _player.on_ground else "no"),
		"fps        %6d" % Engine.get_frames_per_second(),
	])
