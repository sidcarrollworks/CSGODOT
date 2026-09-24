class_name FlashOverlay
extends ColorRect

## The flashbang's white-out: the whole screen white, as white as the
## grenades say the player watching is blind at the time the frame falls,
## fading as it wears off. It only reads (the blind_share query), so it
## shows what the server holds.

var game: GameSystems
## Whose eyes the screen is.
var viewer_id: int = GameEvents.NOBODY


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(1.0, 1.0, 1.0, 0.0)


func _process(_delta: float) -> void:
	var amount := 0.0
	if game != null and viewer_id != GameEvents.NOBODY:
		amount = float(game.query(&"blind_share", [viewer_id, SimClock.draw_usec()], 0.0))
	color.a = amount
	visible = amount > 0.0
