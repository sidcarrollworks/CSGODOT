class_name UiWorldBackdrop
extends HudElement

## A reusable menu surface over the loaded world. Use the HUD's explicit
## screen copy and resolution-aware blur; no polling or second 3D scene.
## Panorama's content container uses a 75% black tint. Blur reach is our
## approximation of its native backbuffer blur, calibrated to the reference.
@export var tint := Color(0, 0, 0, 0.75)


func _enter_tree() -> void:
	super._enter_tree()
	_blur.material = HudStyle.world_blur(5.0)
	resized.connect(redraw)


func _draw_blur(on: Control) -> void:
	on.draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)


func _draw_under(on: Control) -> void:
	on.draw_rect(Rect2(Vector2.ZERO, size), tint)
