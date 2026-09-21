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

const FLOOR_SIZE := 6144.0
const WALL_HEIGHT := 512.0

## Distance markers every this many units down the strafe lane, so you can see
## how far a jump actually carried you.
const MARKER_SPACING := 128.0

## Points on the course that the tests need to know about, published here so
## the tests and the geometry cannot drift apart.
var surf_left_surface_point: Vector3
var surf_channel_top_height: float
var access_ramp_bottom: Vector3

var _grey: StandardMaterial3D
var _accent: StandardMaterial3D
var _surf: StandardMaterial3D


func _ready() -> void:
	_make_materials()
	_build_floor()
	_build_strafe_lane()
	_build_stairs(Vector3(-512.0, 0.0, -256.0))
	_build_ramps(Vector3(512.0, 0.0, -256.0))
	_build_surf_lane(Vector3(-1800.0, 0.0, -700.0))
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


## Two opposing steep ramps forming a V channel, with a platform to drop in
## from and a walkable ramp up to it.
##
## The angle here is the surface angle, which is not the same as the rotation
## applied to the box. A flat box rotated by A about Z presents a surface at A
## degrees; a tall box rotated by A presents one at 90 - A. Getting that
## backwards is how the first version of this course ended up with 35 degree
## surfaces you could walk on, when it was meant to be 55 degree ones you
## surf. The tests now pin the surface normals so it cannot happen again.
const SURF_ANGLE := 55.0
const SURF_RAMP_WIDTH := 512.0
const SURF_RAMP_LENGTH := 1800.0
const SURF_RAMP_THICKNESS := 24.0

## Half-width of the gap at the bottom of the V, and how high that gap sits.
const SURF_CHANNEL_HALF_WIDTH := 96.0
const SURF_CHANNEL_FLOOR := 128.0

## Angle of the walkable ramp that gets you up to the drop-in platform.
const ACCESS_RAMP_ANGLE := 35.0


func _build_surf_lane(origin: Vector3) -> void:
	var angle := deg_to_rad(SURF_ANGLE)
	var half_width := SURF_RAMP_WIDTH * 0.5

	# Offset from a ramp's centre to its low inner edge. For the left wall the
	# box is rotated by -SURF_ANGLE, which sends its local +X end right and
	# down, so that end is the one at the bottom of the channel.
	var to_inner_edge := Vector2(half_width * cos(angle), -half_width * sin(angle))
	var inner_edge := Vector2(-SURF_CHANNEL_HALF_WIDTH, SURF_CHANNEL_FLOOR)
	var left_centre := inner_edge - to_inner_edge

	var ramp_size := Vector3(SURF_RAMP_WIDTH, SURF_RAMP_THICKNESS, SURF_RAMP_LENGTH)
	var centre_offset := absf(left_centre.x)

	# The outward-facing normal of the left ramp's surfable face, and a point
	# on that face two thirds of the way up, which is where the tests drop a
	# player to check that it slides rather than stands.
	var face_normal := Vector3(sin(angle), cos(angle), 0.0)
	var left_centre_world := origin + Vector3(-centre_offset, left_centre.y, 0.0)
	surf_left_surface_point = (
		left_centre_world
		+ face_normal * (SURF_RAMP_THICKNESS * 0.5)
		- Vector3(cos(angle), -sin(angle), 0.0) * (SURF_RAMP_WIDTH * 0.17)
	)
	for side in [-1.0, 1.0]:
		_box(
			ramp_size,
			origin + Vector3(side * centre_offset, left_centre.y, 0.0),
			_surf,
			Vector3(0.0, 0.0, side * SURF_ANGLE)
		)

	# The top outer edge of each ramp, which is where you step off.
	var top_height := SURF_CHANNEL_FLOOR + SURF_RAMP_WIDTH * sin(angle)
	surf_channel_top_height = top_height
	var top_x := SURF_CHANNEL_HALF_WIDTH + SURF_RAMP_WIDTH * cos(angle)

	# Drop-in platform, level with the top of the left ramp and just beyond the
	# entry end of the channel.
	var platform_depth := 256.0
	var platform_width := 384.0
	var entry_z := SURF_RAMP_LENGTH * 0.5
	var platform_centre := origin + Vector3(
		-top_x - platform_width * 0.5,
		top_height - SURF_RAMP_THICKNESS * 0.5,
		entry_z + platform_depth * 0.5
	)
	_box(
		Vector3(platform_width, SURF_RAMP_THICKNESS, platform_depth),
		platform_centre,
		_accent
	)

	# Walkable ramp from the floor up to the platform, descending toward +Z.
	_build_access_ramp(
		Vector3(
			platform_centre.x,
			top_height,
			platform_centre.z + platform_depth * 0.5
		),
		top_height,
		ACCESS_RAMP_ANGLE,
		platform_width
	)


## Places a walkable ramp whose high edge's top surface sits at `top_edge`,
## descending toward +Z until it reaches y = top_edge.y - height.
func _build_access_ramp(
	top_edge: Vector3, height: float, angle_deg: float, width: float
) -> void:
	var angle := deg_to_rad(angle_deg)
	var length := height / sin(angle)
	var half := length * 0.5

	# Rotating by +angle about X sends the local +Z end down, so the high end
	# is the -Z one.
	var to_high_end := Vector3(0.0, half * sin(angle), -half * cos(angle))
	var surface_normal := Vector3(0.0, cos(angle), sin(angle))
	var centre := (
		top_edge
		- to_high_end
		- surface_normal * (SURF_RAMP_THICKNESS * 0.5)
	)

	_box(
		Vector3(width, SURF_RAMP_THICKNESS, length),
		centre,
		_grey,
		Vector3(angle_deg, 0.0, 0.0)
	)

	# Where the ramp meets the floor, so a test can walk up it from the bottom.
	access_ramp_bottom = top_edge + Vector3(0.0, -height, length * cos(angle))


## Ledges at known heights. A standing jump peaks at about 58 units, so the
## grey ones are reachable standing and the blue ones need a crouch jump, which
## pulls the feet up 18 units on top of that.
func _build_jump_gauges(origin: Vector3) -> void:
	var heights := [32.0, 48.0, 56.0, 64.0, 72.0]
	for i in heights.size():
		var h: float = heights[i]
		var material: StandardMaterial3D = _grey if h <= 58.0 else _accent
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
