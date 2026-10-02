class_name RenderDebug
extends Node

## F11 (a key CS2 leaves unbound, reference/binds.md) steps through the
## culling and the 3D skybox one at a time, so a picture that is wrong in
## one spot can be investigated without leaving the spot: a step that
## clears the fault points to the system involved. Sid's
## flat beige floor ahead of the crates (playtest of 2026-09-30) and the
## lower-mid flicker (playtest-2026-09-25.md, issue 11) are what it is for.
## Only what is drawn changes; the game runs on as it was.

const KEY := KEY_F11

## Each step and what it shows, in the order F11 goes through them; the
## first puts everything back.
const STEPS := [
	["", "as is"],
	["no_occlusion", "occlusion culling off (MapOccluders)"],
	["no_visibility", "the map's visibility off (WorldVisibility)"],
	["hide_skybox", "the 3D skybox hidden, every mesh of it"],
	["draw_occluders", "the occluders drawn (Viewport.DEBUG_DRAW_OCCLUDERS)"],
]

var step := 0
var _undo := func() -> void: pass
var _label: Label


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.position = Vector2(12, 60)
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 4)
	_label.visible = false
	layer.add_child(_label)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY:
		go_to((step + 1) % STEPS.size())
		get_viewport().set_input_as_handled()


## A debug step changes the viewport too, which outlives the current map.
func _exit_tree() -> void:
	_undo.call()
	_undo = func() -> void: pass


## Puts the last step back and takes this one.
func go_to(next: int) -> void:
	_undo.call()
	step = next
	_undo = apply(STEPS[step][0], get_tree().root, get_viewport())
	_label.text = "F11: %s" % STEPS[step][1]
	_label.visible = step != 0


## Switches one step on under root, drawn through viewport. Returns what
## puts it back.
static func apply(what: String, root: Node, viewport: Viewport) -> Callable:
	match what:
		"no_occlusion", "no_visibility":
			return RenderVariants.apply(what, root, viewport)
		"hide_skybox":
			# The whole import, not RenderVariants' no_skybox, which finds the
			# skybox by its squeezed materials and so would miss a surface
			# the squeeze was never put on.
			var shown: Array[Node3D] = []
			for node in root.find_children("Skybox", "Node3D", true, false):
				if (node as Node3D).visible:
					(node as Node3D).visible = false
					shown.append(node as Node3D)
			return func() -> void:
				for node in shown:
					if is_instance_valid(node):
						node.visible = true
		"draw_occluders":
			var before := viewport.debug_draw
			viewport.debug_draw = Viewport.DEBUG_DRAW_OCCLUDERS
			return func() -> void:
				if is_instance_valid(viewport):
					viewport.debug_draw = before
	return func() -> void: pass
