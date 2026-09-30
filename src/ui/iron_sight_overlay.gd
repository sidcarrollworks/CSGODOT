class_name IronSightOverlay
extends Control

## What the HUD draws while an AUG or SG 553 is up at the eye
## (Weapon.iron_sight_amount): the scope's dot in the middle of the lens,
## in the crosshair's colour, where the gun's own scope is drawn round it
## (ViewModel.raise_to_eye; reference/research/scopes.md). The crosshair is
## put away meanwhile (GameHud.shows_crosshair).
##
## CS2 draws the dot on the lens from scope_dot_white, sized by the "Scope
## dot scale" setting and coloured red, or the crosshair's colour with "Use
## crosshair color for scope dot" (cl_ironsight_usecrosshaircolor); Sid's
## CS2 has that on (his green dot). Its size here is read off his
## screenshot of 2026-09-30.
##
## Where the gun's model has not been extracted (the cloud, CI), nothing is
## raised to the eye, so a drawn stand-in shows where the scope would be: a
## dark housing round a black-rimmed lens, sized off the same screenshot.
## Only the view reads it.

## Whose scope it is.
var player: PlayerSim
## Whose colour the dot takes.
var crosshair: Crosshair

## The dot's radius, and the stand-in's lens, rim and housing, as shares of
## the screen's height (Sid's screenshot, 2158 high: a dot about 6 across,
## the lens 1085, its black rim out to 1160, the housing about 2050).
const DOT_RADIUS := 0.0027
const LENS_RADIUS := 0.25
const RIM_RADIUS := 0.27
const HOUSING_RADIUS := 0.475
const RIM_COLOUR := Color(0.02, 0.02, 0.02)
const HOUSING_COLOUR := Color(0.27, 0.25, 0.22)
## The dot is drawn once the gun is this far up.
const DOT_FROM := 0.9

## Whether each gun's first-person model is there, by its path, looked up
## once rather than on every frame.
static var _model_found := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _process(_delta: float) -> void:
	var raised := amount_for(player)
	visible = raised > 0.0
	if visible:
		queue_redraw()


## How far a player's gun is up at the eye now, 0 to 1.
static func amount_for(who: PlayerSim) -> float:
	if who == null or not who.alive or who.weapon == null:
		return 0.0
	return who.weapon.iron_sight_amount(DrawClock.usec())


## Whether the stand-in is drawn for a gun: its first-person model is not
## there to be raised.
static func stands_in(data: WeaponData) -> bool:
	if data.model_path.is_empty():
		return true
	if not _model_found.has(data.model_path):
		_model_found[data.model_path] = ResourceLoader.exists(data.model_path)
	return not _model_found[data.model_path]


func _draw() -> void:
	var raised := amount_for(player)
	if raised <= 0.0:
		return
	var centre := size * 0.5
	var height := size.y
	if stands_in(player.weapon.data):
		# The housing, and the black rim inside it, fading in as the gun
		# comes up.
		var lens := height * LENS_RADIUS
		var rim := height * RIM_RADIUS
		var housing := height * HOUSING_RADIUS
		var fade := Color(1, 1, 1, raised)
		draw_arc(centre, (housing + rim) * 0.5, 0.0, TAU, 128, HOUSING_COLOUR * fade, housing - rim, true)
		draw_arc(centre, (rim + lens) * 0.5, 0.0, TAU, 128, RIM_COLOUR * fade, rim - lens, true)
	if raised >= DOT_FROM:
		var colour := crosshair.colour if crosshair != null else Color(1, 0, 0)
		draw_circle(centre, maxf(height * DOT_RADIUS, 1.5), colour, true, -1.0, true)
