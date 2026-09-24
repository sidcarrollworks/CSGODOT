class_name ScopeOverlay
extends Control

## A sniper's scope, over the view while it is scoped in: black round a
## circle as tall as the screen, and thin black lines across it through
## the centre, where the round goes. The AUG and SG 553 keep their arms
## and crosshair instead (WeaponData.hides_view_model_when_zoomed).
##
## Where `scripts/extract_assets.sh hud` has fetched CS2's scope, its mask
## (scope_circle) makes the lens; without it a drawn circle stands in. The
## game composes the rest in code (the lens's tint, the soft cross) and that
## is not matched: the cross here is a plain line. It only reads the
## player's weapon.

const MASK_PATH := "res://assets/hud/panorama/images/hud/scope/scope_circle_png.png"

## Whose scope it is.
var player: PlayerSim

@export var colour: Color = Color(0, 0, 0, 1)
## The lines through the centre, in pixels.
@export var line_width: float = 1.0

## CS2's own mask, when it is extracted; null draws the stand-in.
var mask: Texture2D


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	get_viewport().size_changed.connect(queue_redraw)
	if ResourceLoader.exists(MASK_PATH):
		mask = load(MASK_PATH) as Texture2D


func _process(_delta: float) -> void:
	visible = shown_for(player)


## Whether a player's view is through the scope now.
static func shown_for(who: PlayerSim) -> bool:
	if who == null or not who.alive or who.weapon == null:
		return false
	return who.weapon.zoom_level > 0 and who.weapon.data.hides_view_model_when_zoomed


func _draw() -> void:
	var centre := size * 0.5
	var radius := size.y * 0.5
	# Either side of the lens.
	draw_rect(Rect2(0.0, 0.0, centre.x - radius, size.y), colour)
	draw_rect(Rect2(centre.x + radius, 0.0, size.x - centre.x - radius, size.y), colour)
	if mask != null:
		draw_texture_rect(mask, Rect2(centre.x - radius, 0.0, radius * 2.0, size.y), false)
	else:
		# The corners of the square the lens sits in: a ring from the lens
		# out past them.
		var ring := radius * (sqrt(2.0) - 1.0) + 2.0
		draw_arc(centre, radius + ring * 0.5, 0.0, TAU, 128, colour, ring, true)
	# The lines, edge to edge of the lens.
	draw_line(Vector2(centre.x - radius, centre.y), Vector2(centre.x + radius, centre.y), colour, line_width)
	draw_line(Vector2(centre.x, centre.y - radius), Vector2(centre.x, centre.y + radius), colour, line_width)
