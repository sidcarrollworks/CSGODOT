extends "res://tests/check_suite.gd"

## Draws CS2's eye (character.gdshader's F_EYEBALLS path) and reads the
## pixels back: a synthetic eye, its white, a blue iris and the pupil the
## shader cuts, on a ball behind a flat face whose eye mask covers only its
## top half, the ball looking at the camera. The pupil comes out dark, the
## iris blue, the white neutral and brighter, and below the mask, or off
## the ball, the face's own colour.
##
## It needs a renderer, so it skips headless, as scripts/run_tests.sh runs
## it. In the cloud, where there is no Vulkan, the Compatibility renderer
## draws it through Mesa's llvmpipe:
##
##   xvfb-run godot --rendering-driver opengl3 --rendering-method gl_compatibility \
##       --path . --script tests/run_eye_draw_checks.gd
##
## and on a GPU, godot --path . --script tests/run_eye_draw_checks.gd draws
## it with Forward+. The drawing is saved as user://eye_draw.png.

const SCRATCH := "user://eye_draw_checks"
const SIZE := 256
## World units to a Source unit, so the eyeball is 6 units across the
## radius where CS2's material says 0.6.
const SCALE := 10.0
const RADIUS := 0.6
const PUPIL := 0.2
const FACE := Color(0.8, 0.1, 0.1)
const IRIS := Color(0.15, 0.3, 0.9)


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		_skip("eye_draw", "it draws, and this run is headless (see the file's header for how to run it)")
		return
	var directory := SCRATCH
	var absolute := ProjectSettings.globalize_path(directory.path_join("materials/eyes"))
	DirAccess.make_dir_recursive_absolute(absolute)
	# The eye's colour: white, and a blue iris over the middle half, its
	# alpha the iris as CS2's is, split for the import as the prepare step
	# splits it.
	var eye := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var from_middle := Vector2(x + 0.5 - 32.0, y + 0.5 - 32.0).length() / 32.0
			eye.set_pixel(x, y, Color(IRIS, 1.0) if from_middle < 0.5 else Color(1, 1, 1, 0))
	eye.save_png(absolute.path_join("eye_color.png"))
	DirAccess.remove_absolute(absolute.path_join("eye_color_iris.png"))
	ExportCharacterMasks.split_iris(directory.path_join("materials/eyes/eye_color.png"))
	# The mask: the face's top half.
	var mask := Image.create(64, 64, false, Image.FORMAT_RGB8)
	mask.fill(Color.BLACK)
	mask.fill_rect(Rect2i(0, 0, 64, 32), Color.WHITE)
	mask.save_png(absolute.path_join("eye_mask.png"))

	var description := {
		"Name": "materials/test/face.vmat",
		"ShaderName": CharacterMaterials.SHADER_NAME,
		"IntParams": {"F_EYEBALLS": 1},
		"FloatParams": {"g_flEyeBallRadius1": RADIUS, "g_flEyePupilSize1": PUPIL, "g_flEyeIrisSize1": 1.0},
		"TextureParams": {
			CharacterMaterials.EYE_ALBEDO: "materials/eyes/eye_color.vtex",
			CharacterMaterials.EYE_MASK: "materials/eyes/eye_mask.vtex",
		},
	}
	var source := StandardMaterial3D.new()
	source.albedo_color = FACE
	source.set_meta("extras", {"vmat": description})
	var lit := ProbeMaterials.build(source, directory)

	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 1.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)

	# The face: a square in front of the ball, facing the camera.
	var face := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(20.0, 20.0)
	face.mesh = quad
	face.position = Vector3(0.0, 0.0, RADIUS * SCALE)
	face.material_override = lit
	viewport.add_child(face)
	face.set_instance_shader_parameter(CharacterMaterials.AMBIENT_FROM_PROBES, 0.0)
	# The ball at the origin, looking at the camera, the texture's right
	# along +x as CS2 lays it (the eye's up crossed with its look).
	for side in ["left", "right"]:
		lit.set_shader_parameter("eye_%s_position" % side, Vector3.ZERO if side == "left" else Vector3(1000.0, 0.0, 0.0))
		lit.set_shader_parameter("eye_%s_view" % side, Vector3.BACK)
		lit.set_shader_parameter("eye_%s_across" % side, Vector3.UP.cross(Vector3.BACK))
	lit.set_shader_parameter("eye_scale", SCALE)

	var camera := Camera3D.new()
	camera.fov = 8.0
	camera.position = Vector3(0.0, 0.0, 200.0)
	viewport.add_child(camera)
	camera.current = true

	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("user://eye_draw.png"))

	var eyes := _flag(lit)
	_check(eyes, "a material that draws eyes, with its textures there, has the eye path on")
	# Up the screen is up the ball, which is up the eye's texture.
	var pupil := _at(image, camera, Vector3(0.0, 0.7, RADIUS * SCALE))
	var iris := _at(image, camera, Vector3(0.0, 2.4, RADIUS * SCALE))
	var white := _at(image, camera, Vector3(0.0, 4.2, RADIUS * SCALE))
	var unmasked := _at(image, camera, Vector3(0.0, -2.4, RADIUS * SCALE))
	var off_ball := _at(image, camera, Vector3(8.0, 8.0, RADIUS * SCALE))
	print("pupil %s, iris %s, white %s, unmasked %s, off the ball %s" % [pupil, iris, white, unmasked, off_ball])
	_check(pupil.get_luminance() < 0.1, "the middle of the iris is the pupil, dark (%s)" % pupil)
	_check(iris.b > iris.r * 2.0 and iris.b > 0.3, "around it the iris, in the eye texture's blue (%s)" % iris)
	_check(
		absf(white.r - white.b) < 0.1 and white.get_luminance() > pupil.get_luminance() + 0.3,
		"further out the white, neutral and brighter (%s)" % white
	)
	_check(
		unmasked.r > unmasked.b * 3.0 and off_ball.r > off_ball.b * 3.0,
		"and where the eye mask is clear, or off the ball, the face's own colour (%s, %s)" % [unmasked, off_ball]
	)
	_finish("eye_draw")


func _flag(lit: ShaderMaterial) -> bool:
	return lit.get_shader_parameter("eyes") == true


## The drawn colour where a point of the world lands on the screen.
func _at(image: Image, camera: Camera3D, point: Vector3) -> Color:
	var pixel := camera.unproject_position(point)
	return image.get_pixel(clampi(roundi(pixel.x), 0, SIZE - 1), clampi(roundi(pixel.y), 0, SIZE - 1))
