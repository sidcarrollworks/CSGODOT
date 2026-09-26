class_name FlashOverlay
extends ColorRect

## The flashbang's white-out: the whole screen white, as white as the
## grenades say the player watching is blind at the time the frame falls,
## fading as it wears off. It only reads (the blind_share query), so it
## shows what the server holds.
##
## The project blends 2D in linear light (project.godot's hdr_2d, for the
## HUD to blend as CS2's does), where white at a given share covers more of
## what is behind than it did in sRGB. CS2's white-out is its renderer's,
## not its HUD's, so this keeps the look it had: the share goes in as the
## linear value of that sRGB amount, which is the same over black and white
## and a little darker between.

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
		amount = float(game.query(&"blind_share", [viewer_id, DrawClock.usec()], 0.0))
	color.a = linear_share(amount) if get_viewport().use_hdr_2d else amount
	visible = amount > 0.0


## An sRGB share of white as the linear one that looks the same over black.
static func linear_share(amount: float) -> float:
	return Color(amount, amount, amount).srgb_to_linear().r
