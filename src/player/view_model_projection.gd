class_name ViewModelProjection
extends RefCounted

## How the first-person arms and weapon are drawn: in the world's own
## render, through the player's camera, with their own projection.
##
## CS2 renders the view model at a narrower field of view than the world
## (viewmodel_fov 68 against fov 90), and in front of the world's depth, so
## the gun never pokes through a wall it is pressed against. Both are done
## here in the models' own vertex pass (player_draw.gdshaderinc), per
## instance: the field of view is narrowed and the depth squeezed towards the
## camera, and nothing else about the draw changes, so the arms take the sun,
## its shadows and the probes as anything in the world does. They used to be
## drawn by a second camera in a viewport of their own, which is the usual
## way, and which cannot be lit right: a camera sees only the lights and the
## shadow casters on its own layers, so the arms had the sky and never the
## sun, and no wall ever shaded them.
##
## Godot's Camera3D.fov is the vertical angle. CS2's fov numbers are the
## horizontal angle at 4:3, which is what a Source engine game has meant by
## it since Quake, so they are converted rather than copied. 90 comes out as
## 73.7 vertical; 68 as 53.6.

## CS2's fov and viewmodel_fov.
const WORLD_FOV := 90.0
const VIEW_MODEL_FOV := 68.0

## How much closer to the camera the arms are drawn than they are: a gun 40
## units long ends 8 units out, inside the player's own hull, so no wall
## reaches it. The camera's near plane is set to match (NEAR).
const DEPTH_SQUEEZE := 0.2
## The camera's near plane, in units, once the squeeze is allowed for: the
## stock of a rifle starts an inch or two from the eye.
const NEAR := 0.5


static func vertical_fov(source_fov: float) -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(source_fov * 0.5)) * 0.75))


## The narrowing of the field of view from the world's to the arms', as the
## ratio of the tangents of the half-angles.
static func fov_narrowing(world_fov: float = WORLD_FOV, view_model_fov: float = VIEW_MODEL_FOV) -> float:
	return tan(deg_to_rad(vertical_fov(world_fov) * 0.5)) / tan(deg_to_rad(vertical_fov(view_model_fov) * 0.5))


## The narrowing the arms are drawn at under camera: its field of view is
## the world's, a scope's included, and claim gave the arms the same.
static func narrowing_under(camera: Camera3D) -> float:
	return tan(deg_to_rad(camera.fov * 0.5)) / tan(deg_to_rad(vertical_fov(VIEW_MODEL_FOV) * 0.5))


## Makes a node's meshes draw as the view model, and stops them casting
## shadows: in the game the arms cast none. world_fov is the camera's, in
## CS2's degrees: a scope narrows it, and the arms keep their own 68.
static func claim(node: Node, world_fov: float = WORLD_FOV) -> void:
	var projection := Vector2(fov_narrowing(world_fov), DEPTH_SQUEEZE)
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(mesh as MeshInstance3D).set_instance_shader_parameter(&"view_model_projection", projection)


## Whether a mesh has been claimed.
static func claimed(mesh: MeshInstance3D) -> bool:
	var projection = mesh.get_instance_shader_parameter(&"view_model_projection")
	return projection is Vector2 and (projection as Vector2).y < 1.0
