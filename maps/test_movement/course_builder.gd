@tool
extends Node3D

## Builds the grey-box movement test course from script.
##
## Deliberately not a hand-authored scene. While movement is being tuned, this
## course changes constantly, and a generated course is far easier to adjust
## and to reason about than a tree of hand-placed boxes. It also keeps the
## measurements honest: every distance here is a real number in Source units
## you can check against CS2.
##
## Everything is in Source units. See project.godot on scale.

const FLOOR_SIZE := 4096.0
const WALL_HEIGHT := 512.0

## Distance markers every this many units down the strafe lane, so you can see
## how far a jump actually carried you.
const MARKER_SPACING := 128.0

var _grey: StandardMaterial3D
var _accent: StandardMaterial3D
var _surf: StandardMaterial3D


func _ready() -> void:
	_make_materials()
	_build_floor()
	_build_strafe_lane()
	_build_stairs(Vector3(-512.0, 0.0, -256.0))
	_build_ramps(Vector3(512.0, 0.0, -256.0))
	_build_surf_lane(Vector3(0.0, 0.0, -1536.0))
	_build_jump_gauges(Vector3(-1024.0, 0.0, 0.0))
	_build_lighting()


func _make_materials() -> void:
	_grey = StandardMaterial3D.new()
	_grey.albedo_color = Color(0.45, 0.45, 0.47)

	_accent = StandardMaterial3D.new()
	_accent.albedo_color = Color(0.30, 0.42, 0.55)

	_surf = StandardMaterial3D.new()
	_surf.albedo_color = Color(0.55, 0.40, 0.30)


## A static box. Size and position are in Source units, rotation in degrees.
func _box(
	size: Vector3,
	position: Vector3,
	material: StandardMaterial3D,
	rotation_degrees_value: Vector3 = Vector3.ZERO
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position
	body.rotation_degrees = rotation_degrees_value

	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh_instance.mesh = box_mesh
	mesh_instance.material_override = material
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

	add_child(body)
	return body


func _build_floor() -> void:
	_box(Vector3(FLOOR_SIZE, 32.0, FLOOR_SIZE), Vector3(0.0, -16.0, 0.0), _grey)
	# Boundary walls, so you cannot wander off the edge while tuning.
	var half := FLOOR_SIZE * 0.5
	for offset in [
		Vector3(half, WALL_HEIGHT * 0.5, 0.0),
		Vector3(-half, WALL_HEIGHT * 0.5, 0.0),
	]:
		_box(Vector3(32.0, WALL_HEIGHT, FLOOR_SIZE), offset, _grey)
	for offset in [
		Vector3(0.0, WALL_HEIGHT * 0.5, half),
		Vector3(0.0, WALL_HEIGHT * 0.5, -half),
	]:
		_box(Vector3(FLOOR_SIZE, WALL_HEIGHT, 32.0), offset, _grey)


## A long open lane with distance markers, for bunny hopping and air strafing.
## The markers matter: "did that jump go further" is the whole question when
## tuning air acceleration, and eyeballing it on a blank floor is hopeless.
func _build_strafe_lane() -> void:
	var count := int(1536.0 / MARKER_SPACING)
	for i in range(1, count + 1):
		var z := -float(i) * MARKER_SPACING
		var material: StandardMaterial3D = _accent if i % 4 == 0 else _grey
		var height: float = 2.0 if i % 4 == 0 else 1.0
		_box(Vector3(256.0, height, 4.0), Vector3(0.0, height * 0.5, z), material)


## Steps below step_height, which should be walked up without jumping, and one
## above it, which should not.
func _build_stairs(origin: Vector3) -> void:
	var step_rise := 16.0
	var step_run := 32.0
	for i in range(8):
		var h := step_rise * float(i + 1)
		_box(
			Vector3(192.0, h, step_run),
			origin + Vector3(0.0, h * 0.5, -step_run * float(i)),
			_grey
		)
	# A 24-unit lip, above the 18-unit step height. You should have to jump.
	_box(
		Vector3(192.0, 24.0, 64.0),
		origin + Vector3(0.0, 12.0, -step_run * 9.0),
		_accent
	)


## Ramps either side of the walkable threshold. 44 degrees should be walkable,
## 50 should not, which is the boundary that makes surf possible.
func _build_ramps(origin: Vector3) -> void:
	var angles := [20.0, 35.0, 44.0, 50.0]
	for i in angles.size():
		var angle: float = angles[i]
		var material: StandardMaterial3D = _grey if angle < 45.0 else _surf
		_box(
			Vector3(192.0, 16.0, 384.0),
			origin + Vector3(float(i) * 256.0, 64.0, 0.0),
			material,
			Vector3(angle, 0.0, 0.0)
		)


## Two opposing steep ramps forming a surf lane. If collide-and-slide is right,
## you ride down these gaining speed. If it is wrong, you stick or stutter, and
## that is the single clearest test of whether the port is correct.
func _build_surf_lane(origin: Vector3) -> void:
	var ramp_angle := 55.0
	for side in [-1.0, 1.0]:
		_box(
			Vector3(32.0, 768.0, 2048.0),
			origin + Vector3(side * 256.0, 384.0, 0.0),
			_surf,
			Vector3(0.0, 0.0, side * ramp_angle)
		)
	# A raised start platform, so you can drop into the lane.
	_box(Vector3(256.0, 32.0, 256.0), origin + Vector3(0.0, 640.0, 1152.0), _accent)


## Ledges at known heights. With sv_jump_impulse 301.993 and gravity 800, a
## standing jump peaks at about 57 units, so 56 should be reachable and 64
## should not.
func _build_jump_gauges(origin: Vector3) -> void:
	var heights := [32.0, 48.0, 56.0, 64.0]
	for i in heights.size():
		var h: float = heights[i]
		var material: StandardMaterial3D = _grey if h <= 57.0 else _accent
		_box(
			Vector3(128.0, h, 128.0),
			origin + Vector3(0.0, h * 0.5, -float(i) * 192.0),
			material
		)


func _build_lighting() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	light.light_energy = 1.1
	light.shadow_enabled = true
	add_child(light)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	environment.sky.sky_material = ProceduralSkyMaterial.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.4

	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
