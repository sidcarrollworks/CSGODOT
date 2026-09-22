class_name Crosshair
extends Control

## A CS-style crosshair: four ticks around a centre gap, drawn rather than
## typed.
##
## It has to be exactly on the point the bullet goes through, because that is
## the only thing anyone can use to judge whether aiming is correct. A Label
## holding "+" cannot do that: a Control's anchors position its top-left
## corner, so a centred Label puts the glyph down and to the right of the
## centre by half its own box, and the first bullet then appears to land up
## and to the left. That was a real bug, reported as the gun shooting off
## centre.

@export var gap: float = 4.0
@export var length: float = 7.0
@export var thickness: float = 2.0
@export var outline: float = 1.0
@export var colour: Color = Color(0.2, 1.0, 0.4)
@export var outline_colour: Color = Color(0, 0, 0, 0.85)

## Draw a dot in the middle as well. Useful while tuning, since it marks the
## exact pixel a shot with no spread passes through.
@export var centre_dot: bool = false


func _ready() -> void:
	# The whole viewport, so the centre of this Control is the centre of the
	# screen no matter how the window is resized.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(queue_redraw)


func _draw() -> void:
	var centre := size * 0.5
	var half := thickness * 0.5

	# Vertical ticks above and below, horizontal ticks left and right.
	var arms: Array[Rect2] = [
		Rect2(centre.x - half, centre.y - gap - length, thickness, length),
		Rect2(centre.x - half, centre.y + gap, thickness, length),
		Rect2(centre.x - gap - length, centre.y - half, length, thickness),
		Rect2(centre.x + gap, centre.y - half, length, thickness),
	]

	for arm in arms:
		draw_rect(arm.grow(outline), outline_colour)
	for arm in arms:
		draw_rect(arm, colour)

	if centre_dot:
		var dot := Rect2(centre.x - half, centre.y - half, thickness, thickness)
		draw_rect(dot.grow(outline), outline_colour)
		draw_rect(dot, colour)
