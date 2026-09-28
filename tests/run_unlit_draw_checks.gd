extends "res://tests/check_suite.gd"

## Draws a cloud as dust2's 3D skybox has them (UnlitMaterials: CS2's
## csgo_unlitgeneric under its Additive blend, behind everything through
## FarMaterials) and reads the pixels back. A quad of it in front of the
## camera, over a sky-coloured background, under a strong sun: where its
## two textures' alpha multiplies to a quarter, the tint times a quarter is
## added to the sky, lit or not; where it is clear, the sky is untouched.
## Across the bottom a quad of the map, set farther off than the cloud,
## still hides it, since the cloud is drawn behind everything.
##
## It needs a renderer, so it skips headless, as scripts/run_tests.sh runs
## it. In the cloud, where there is no Vulkan, the Compatibility renderer
## draws it through Mesa's llvmpipe:
##
##   xvfb-run godot --rendering-driver opengl3 --rendering-method gl_compatibility \
##       --path . --script tests/run_unlit_draw_checks.gd
##
## and on a GPU, godot --path . --script tests/run_unlit_draw_checks.gd draws
## it with Forward+. Compatibility blends in sRGB, so what it adds is
## reckoned there in sRGB. The drawing is saved as user://unlit_draw.png.

const SCRATCH := "user://unlit_draw_checks"
const SIZE := 256
const SKY := Color(0.2, 0.3, 0.5)
const MAP := Color(0.6, 0.1, 0.1)
## The draw's tint, in linear light, as the export's colour factor is.
const TINT := Color(0.8, 0.4, 0.2)
## How near the drawn colour must come, in linear light.
const CLOSE := 0.03


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		_skip("unlit_draw", "it draws, and this run is headless (see the file's header for how to run it)")
		return
	# The two textures, white: the first's alpha a half over its left half
	# and clear over its right, the second's a half all over.
	var absolute := ProjectSettings.globalize_path(SCRATCH.path_join("materials/clouds"))
	DirAccess.make_dir_recursive_absolute(absolute)
	var first := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	first.fill(Color(1.0, 1.0, 1.0, 0.0))
	first.fill_rect(Rect2i(0, 0, 32, 64), Color(1.0, 1.0, 1.0, 0.5))
	first.save_png(absolute.path_join("clouds_color.png"))
	var second := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	second.fill(Color(1.0, 1.0, 1.0, 0.5))
	second.save_png(absolute.path_join("clouds_color2.png"))

	var source := StandardMaterial3D.new()
	source.albedo_color = TINT.linear_to_srgb()
	source.set_meta("extras", {"vmat": {
		"ShaderName": UnlitMaterials.SHADER_NAME,
		"IntParams": {"F_BLEND_MODE": UnlitMaterials.ADDITIVE, "F_TWOTEXTURE": 1},
		"TextureParams": {
			"g_tColor": "materials/clouds/clouds_color.vtex",
			"g_tColor2": "materials/clouds/clouds_color2.vtex",
		},
	}})
	var unlit := UnlitMaterials.build(source, SCRATCH)
	_check(unlit != null, "the cloud's material is built from its two textures")
	if unlit == null:
		_finish("unlit_draw")
		return

	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	# A colour property is sRGB; the drawing is in linear light.
	environment.background_color = SKY.linear_to_srgb()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	# Were the cloud lit, it would come out far brighter than its tint.
	var sun := DirectionalLight3D.new()
	sun.light_energy = 4.0
	sun.rotation_degrees = Vector3(-30.0, 0.0, 0.0)
	viewport.add_child(sun)

	var cloud := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(40.0, 40.0)
	quad.material = unlit
	cloud.mesh = quad
	cloud.position = Vector3(0.0, 0.0, -50.0)
	viewport.add_child(cloud)
	FarMaterials.apply([cloud] as Array[MeshInstance3D])

	var ground := MeshInstance3D.new()
	var strip := QuadMesh.new()
	strip.size = Vector2(200.0, 40.0)
	var map_material := StandardMaterial3D.new()
	map_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	map_material.albedo_color = MAP.linear_to_srgb()
	strip.material = map_material
	ground.mesh = strip
	ground.position = Vector3(0.0, -40.0, -100.0)
	viewport.add_child(ground)

	var camera := Camera3D.new()
	camera.fov = 60.0
	camera.far = 1000.0
	viewport.add_child(camera)
	camera.current = true

	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("user://unlit_draw.png"))

	var cloudy := _at(image, camera, Vector3(-8.0, 8.0, -50.0))
	var clear := _at(image, camera, Vector3(8.0, 8.0, -50.0))
	var hidden := _at(image, camera, Vector3(-8.0, -18.0, -50.0))
	var added := Color(SKY.r + TINT.r * 0.25, SKY.g + TINT.g * 0.25, SKY.b + TINT.b * 0.25)
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		# Compatibility blends in sRGB (reference/godot/rendering.md).
		var sky := SKY.linear_to_srgb()
		var tint := TINT.linear_to_srgb()
		added = Color(sky.r + tint.r * 0.25, sky.g + tint.g * 0.25, sky.b + tint.b * 0.25).srgb_to_linear()
	print("cloudy %s (expected %s), clear %s, behind the map %s" % [cloudy, added, clear, hidden])
	_check(
		_near(cloudy, added),
		"where the cloud's two alphas multiply to a quarter, a quarter of its tint is added to the sky, the sun or no (%s against %s)" % [cloudy, added]
	)
	_check(_near(clear, SKY), "where its alpha is clear the sky is untouched (%s)" % clear)
	_check(
		_near(hidden, MAP),
		"and the map, though farther off than the cloud, hides it: it is drawn behind everything (%s)" % hidden
	)
	_finish("unlit_draw")


func _near(drawn: Color, expected: Color) -> bool:
	return absf(drawn.r - expected.r) < CLOSE and absf(drawn.g - expected.g) < CLOSE and absf(drawn.b - expected.b) < CLOSE


## The drawn colour, in linear light, where a point of the world lands on
## the screen.
func _at(image: Image, camera: Camera3D, point: Vector3) -> Color:
	var pixel := camera.unproject_position(point)
	return image.get_pixel(clampi(roundi(pixel.x), 0, SIZE - 1), clampi(roundi(pixel.y), 0, SIZE - 1)).srgb_to_linear()
