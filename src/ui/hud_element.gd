class_name HudElement
extends Control

## The base of every piece of the HUD: a Control that draws itself in
## `_draw()` with HudStyle and does no work on a frame where nothing it
## shows changed.
##
## How it stays cheap:
## - No Labels or containers: each element is one CanvasItem (with a surface
##   or two under it for its panel), so there is no layout pass, no theme
##   lookup and no text shaping except when it redraws. Godot keeps an element's draw commands
##   until the next `queue_redraw()` (reference/godot/ui.md, "Drawing your
##   own"), so a HUD that does not change costs nothing to draw again.
## - The owner hands it its values each frame with `show_state()`, one array
##   compared with the last; only a difference redraws it.
## - An element that moves on its own (a roll, a flash, a bar opening) calls
##   `animate()`, which turns `_process` on until `_advance()` says it is
##   done, then off again. Idle, an element has no `_process` at all.
## - It never takes the mouse (MOUSE_FILTER_IGNORE), so nothing on the HUD
##   swallows a click meant for the game.
##
## How it blends, as CS2's does (HudStyle): an element that sets `additive`
## before it enters the tree draws in `_draw()` with light added to the world
## behind, as Panorama's `additive` class does; whatever it draws in
## `_draw_under()` (the dark panel behind its numbers) goes underneath with
## the ordinary blend; and the shapes it draws in `_draw_blur()` show the
## world behind them blurred, under that, as Panorama's world-blur does
## (only that part of the screen is copied for it: `_blur_rect()`).
##
## Everything is laid out on the 1920x1080 base size; the canvas_items
## stretch scales it to the window, and the icons, rasterized at twice their
## size (scripts/write_import_settings.gd), are drawn with their mipmaps so
## they are as sharp at 4K as at 1080p.

## Whether what `_draw()` draws adds its light (set before `_ready`).
var additive: bool = false

var _state: Array = []
var _animating: bool = false
var _under: Control
var _blur: Control
var _copy: BackBufferCopy
## How far round a blurred shape the screen is copied, in base pixels: the
## blur's reach at the level hud_blur.gdshader reads.
const BLUR_REACH := 24.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_process(false)


func _enter_tree() -> void:
	if additive:
		material = HudStyle.additive()
	if _blur == null and has_method(&"_draw_blur"):
		# The screen under the element copied first, only there: Godot
		# would otherwise copy and blur the whole screen for it.
		_copy = BackBufferCopy.new()
		_copy.name = "Copy"
		_copy.copy_mode = BackBufferCopy.COPY_MODE_RECT
		_copy.show_behind_parent = true
		add_child(_copy, false, Node.INTERNAL_MODE_FRONT)
		_blur = _surface("Blur", &"_draw_blur")
		_blur.material = HudStyle.world_blur()
		resized.connect(_fit_copy)
		get_viewport().size_changed.connect(_fit_copy)
		_fit_copy()
	if _under == null and has_method(&"_draw_under"):
		_under = _surface("Under", &"_draw_under")


## The part of the screen the blur reads: what `_blur_rect()` says, in this
## element's coordinates, with room round it for the blur's reach; nothing
## copied at all while it says there is nothing to blur. Godot 4.7 took a
## copy's rectangle, under a Control, as the viewport's pixels whatever the
## transforms above it (measured at 1080p and 4K), where its code reads as
## putting it through them; so the copy is given the screen's pixels and a
## transform that undoes its parent's, which comes out the same either way.
func _fit_copy() -> void:
	if _copy == null or not is_inside_tree():
		return
	var area: Rect2 = call(&"_blur_rect") if has_method(&"_blur_rect") else Rect2(Vector2.ZERO, size)
	_copy.visible = area.has_area()
	if not _copy.visible:
		return
	var to_screen := get_viewport().get_stretch_transform() * get_global_transform_with_canvas()
	_copy.transform = to_screen.affine_inverse()
	_copy.rect = to_screen * area.grow(BLUR_REACH)


## A surface of its own under the element, drawn by `method` on it.
func _surface(surface_name: String, method: StringName) -> Control:
	var surface := Control.new()
	surface.name = surface_name
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.texture_filter = texture_filter
	surface.show_behind_parent = true
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.draw.connect(func() -> void: call(method, surface))
	add_child(surface, false, Node.INTERNAL_MODE_FRONT)
	return surface


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
	redraw()
	return true


## Draws the element again this frame, the panel under it too.
func redraw() -> void:
	queue_redraw()
	if _under != null:
		_under.queue_redraw()
	if _blur != null:
		_blur.queue_redraw()
		_fit_copy()


## Redraws every frame until `_advance()` returns false.
func animate() -> void:
	if not _animating:
		_animating = true
		set_process(true)
	redraw()


func is_animating() -> bool:
	return _animating


func _process(delta: float) -> void:
	if not _advance(delta):
		_animating = false
		set_process(false)
	redraw()


## Moves an animation on by `delta` seconds; false once it is over. An
## element that animates overrides it.
func _advance(_delta: float) -> bool:
	return false
