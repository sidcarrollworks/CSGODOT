extends "res://tests/check_suite.gd"

## Draws a tint-masked prop (prop_features.gdshaderinc's prop_tint) and
## reads the pixels back: a grey square whose material the export tinted
## red all over, as Source 2 Viewer bakes a draw call's tint into the base
## colour, with a made-up tint mask white over its left half and black over
## its right. The left comes out red, the right its own grey, as CS2 paints
## a window frame and leaves its bare wood (issue 25 of the 2026-09-25
## playtest).
##
## It needs a renderer, so it skips headless, as scripts/run_tests.sh runs
## it. In the cloud, where there is no Vulkan, the Compatibility renderer
## draws it through Mesa's llvmpipe:
##
##   xvfb-run godot --rendering-driver opengl3 --rendering-method gl_compatibility \
##       --path . --script tests/run_tint_mask_draw_checks.gd
##
## and on a GPU, godot --path . --script tests/run_tint_mask_draw_checks.gd
## draws it with Forward+. The drawing is saved as user://tint_mask_draw.png.

const SCRATCH := "user://tint_mask_draw_checks"
const SIZE := 256
const GREY := Color(0.5, 0.5, 0.5)
const TINT := Color(0.8, 0.1, 0.1)


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		_skip("tint_mask_draw", "it draws, and this run is headless (see the file's header for how to run it)")
		return
	var absolute := ProjectSettings.globalize_path(SCRATCH.path_join("materials/props"))
	DirAccess.make_dir_recursive_absolute(absolute)
	var mask := Image.create(8, 8, false, Image.FORMAT_RGB8)
	mask.fill(Color.BLACK)
	mask.fill_rect(Rect2i(0, 0, 4, 8), Color.WHITE)
	mask.save_png(absolute.path_join("frame_tintmask.png"))

	var albedo := Image.create(8, 8, false, Image.FORMAT_RGB8)
	albedo.fill(GREY)
	var source := StandardMaterial3D.new()
	source.albedo_texture = ImageTexture.create_from_image(albedo)
	source.albedo_color = TINT
	source.set_meta("extras", {"vmat": {
		"ShaderName": "csgo_vertexlitgeneric.vfx",
		"IntParams": {"F_TINT_MASK": 1},
		"TextureParams": {"g_tTintMask": "materials/props/frame_tintmask.vtex"},
	}})
	var masked := ProbeMaterials.build(source, SCRATCH)
	# The same material with no mask extracted: tinted all over, as before.
	var plain := source.duplicate() as StandardMaterial3D
	plain.set_meta("extras", source.get_meta("extras"))
	var unmasked := ProbeMaterials.build(plain, SCRATCH.path_join("nowhere"))

	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)

	# The masked square above, the unmasked one below, both facing the
	# camera and lit alike by the probe shader's default cube.
	var squares: Array[MeshInstance3D] = []
	for material: ShaderMaterial in [masked, unmasked]:
		var square := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(20.0, 9.0)
		square.mesh = quad
		square.material_override = material
		square.position = Vector3(0.0, 5.0 if material == masked else -5.0, 0.0)
		viewport.add_child(square)
		squares.append(square)

	var camera := Camera3D.new()
	camera.fov = 10.0
	camera.position = Vector3(0.0, 0.0, 150.0)
	viewport.add_child(camera)
	camera.current = true

	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("user://tint_mask_draw.png"))

	var paint := _at(image, camera, Vector3(-5.0, 5.0, 0.0)).srgb_to_linear()
	var wood := _at(image, camera, Vector3(5.0, 5.0, 0.0)).srgb_to_linear()
	var all_left := _at(image, camera, Vector3(-5.0, -5.0, 0.0)).srgb_to_linear()
	var all_right := _at(image, camera, Vector3(5.0, -5.0, 0.0)).srgb_to_linear()
	print("under the mask %s, clear of it %s; unmasked %s, %s" % [paint, wood, all_left, all_right])
	_check(
		wood.r > 0.05 and absf(wood.r - wood.g) < 0.02 and absf(wood.g - wood.b) < 0.02,
		"clear of the mask the surface keeps its own grey (%s)" % wood
	)
	# Compared with the unmasked square rather than with TINT itself, since
	# Compatibility multiplies the colour before it turns linear.
	_check(
		paint.r > paint.g * 4.0 and paint.g / wood.g < 0.2
			and absf(paint.r - all_left.r) < 0.01 and absf(paint.g - all_left.g) < 0.01,
		"under the mask it takes the whole tint, as the exported colour gave it (%s against %s)" % [paint, all_left]
	)
	_check(
		all_left.r > all_left.g * 4.0 and all_right.r > all_right.g * 4.0,
		"without the mask the whole surface is tinted, as exported (%s, %s)" % [all_left, all_right]
	)
	_finish("tint_mask_draw")


## The drawn colour where a point of the world lands on the screen.
func _at(image: Image, camera: Camera3D, point: Vector3) -> Color:
	var pixel := camera.unproject_position(point)
	return image.get_pixel(clampi(roundi(pixel.x), 0, SIZE - 1), clampi(roundi(pixel.y), 0, SIZE - 1))
