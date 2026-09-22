class_name ViewModelOverlay
extends CanvasLayer

## Draws the view model through a camera of its own, over the world.
##
## CS2 renders the first-person arms and weapon at a narrower field of view
## than the world (viewmodel_fov 68 against fov 90), and with the world's
## depth out of the way, so the gun never pokes through a wall it is pressed
## against. Both come from rendering them separately, which is what this is:
## a viewport over the whole screen, transparent where nothing is drawn, with
## a camera that follows the player's and sees only the view model's layer.
##
## The world's lighting is kept: the viewport shares the world, so the sun and
## its shadows fall on the arms, and its environment is copied for the tone
## mapping and the sky's ambient light, less the sky itself and the screen
## effects that would double up.

## Godot's Camera3D.fov is the vertical angle. CS2's fov numbers are the
## horizontal angle at 4:3, which is what a Source engine game has meant by
## it since Quake, so they are converted rather than copied. 90 comes out as
## 73.7 vertical; 68 as 53.6.
static func vertical_fov(source_fov: float) -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(source_fov * 0.5)) * 0.75))

## The visual layer the view model is on and the world is not.
const LAYER := 2

var camera: Camera3D
var _viewport: SubViewport
var _world_environment: Environment


func _init() -> void:
	name = "ViewModelOverlay"
	# Behind the HUD, which sits on the default layer.
	layer = -1

	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.own_world_3d = false
	_viewport.handle_input_locally = false
	container.add_child(_viewport)

	camera = Camera3D.new()
	camera.fov = vertical_fov(68.0)
	camera.near = 0.5
	camera.far = 256.0
	camera.cull_mask = 1 << (LAYER - 1)
	_viewport.add_child(camera)


## Puts the overlay's camera where the player's is, with the world's
## lighting. Called after the player's camera has moved for the frame.
func follow(player_camera: Camera3D) -> void:
	camera.global_transform = player_camera.global_transform
	var environment := player_camera.get_world_3d().environment
	if environment != _world_environment:
		_world_environment = environment
		camera.environment = _adapt(environment)


## The world's environment as the overlay needs it: no background of its
## own, no fog on something a foot away, and no screen effects on top of the
## world's; the tone mapping, the sky's ambient light and reflections stay.
func _adapt(environment: Environment) -> Environment:
	if environment == null:
		return null
	var copy := environment.duplicate() as Environment
	copy.background_mode = Environment.BG_CLEAR_COLOR
	copy.fog_enabled = false
	copy.glow_enabled = false
	copy.ssao_enabled = false
	copy.ssil_enabled = false
	copy.volumetric_fog_enabled = false
	return copy


## Puts a node's meshes on the overlay's layer, where only its camera looks,
## and stops them casting shadows into the world: in the game the arms cast
## none.
static func claim(node: Node) -> void:
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).layers = 1 << (LAYER - 1)
		(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
