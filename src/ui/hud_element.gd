class_name HudElement
extends Control

## The base of every piece of the HUD: a Control that draws itself in
## `_draw()` with HudStyle and does no work on a frame where nothing it
## shows changed.
##
## How it stays cheap:
## - No child nodes, Labels or containers: each element is one CanvasItem,
##   so there is no layout pass, no theme lookup and no text shaping except
##   when it redraws. Godot keeps an element's draw commands until the next
##   `queue_redraw()` (reference/godot/ui.md, "Drawing your own"), so a
##   HUD that does not change costs nothing to draw again.
## - The owner hands it its values each frame with `show_state()`, one array
##   compared with the last; only a difference redraws it.
## - An element that moves on its own (a roll, a flash, a bar opening) calls
##   `animate()`, which turns `_process` on until `_advance()` says it is
##   done, then off again. Idle, an element has no `_process` at all.
## - It never takes the mouse (MOUSE_FILTER_IGNORE), so nothing on the HUD
##   swallows a click meant for the game.
##
## Everything is laid out on the 1920x1080 base size; the canvas_items
## stretch scales it to the window.

var _state: Array = []
var _animating: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


## Anchors the element at `anchor` (0 to 1 of the screen on each axis) with
## its box `box` relative to that point, in base-size pixels.
func place(anchor: Vector2, box: Rect2) -> void:
	anchor_left = anchor.x
	anchor_right = anchor.x
	anchor_top = anchor.y
	anchor_bottom = anchor.y
	offset_left = box.position.x
	offset_top = box.position.y
	offset_right = box.end.x
	offset_bottom = box.end.y


## This frame's values, as one array; redraws when they differ from the
## last. Returns whether they did.
func show_state(state: Array) -> bool:
	if state == _state:
		return false
	_state = state.duplicate()
	queue_redraw()
	return true


## Redraws every frame until `_advance()` returns false.
func animate() -> void:
	if not _animating:
		_animating = true
		set_process(true)
	queue_redraw()


func is_animating() -> bool:
	return _animating


func _process(delta: float) -> void:
	if not _advance(delta):
		_animating = false
		set_process(false)
	queue_redraw()


## Moves an animation on by `delta` seconds; false once it is over. An
## element that animates overrides it.
func _advance(_delta: float) -> bool:
	return false
