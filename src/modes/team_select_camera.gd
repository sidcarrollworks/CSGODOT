class_name TeamSelectCamera
extends Camera3D

## A presentation camera for the loaded map behind the startup chooser.
## Measured from Sid's Dust2 reference (2026-10-05), in game coordinates:
## the HUD's position is at the feet, so the view adds the standing eye offset.
## Other maps retain the prepared spawn view until their own view is authored.
const MAP_VIEWS := {
	"de_dust2": {"feet": Vector3(-573.7, 129.2, -1302.8), "angles": Vector2(220.4, 3.3)},
}


## Called after adding the camera. Does not move or change a prepared player.
func frame_map(contents: MapContents, spawn_camera: Camera3D, standing_eye_height: float) -> void:
	top_level = true
	near = spawn_camera.near
	far = spawn_camera.far
	fov = spawn_camera.fov
	keep_aspect = spawn_camera.keep_aspect
	cull_mask = spawn_camera.cull_mask
	global_transform = spawn_camera.global_transform
	# A missing-map fallback should stay on its fallback floor.
	if contents.has_both_sides() and MAP_VIEWS.has(contents.name):
		var view: Dictionary = MAP_VIEWS[contents.name]
		var angles: Vector2 = view["angles"]
		global_position = view["feet"] + Vector3.UP * standing_eye_height
		global_rotation = Vector3(deg_to_rad(angles.y), deg_to_rad(angles.x), 0.0)
	make_current()
