extends "res://tests/check_suite.gd"

## The render profiler's variants (RenderVariants) on a small stand-in for a
## map: a sun, an environment, a mesh casting from both faces, a skybox mesh
## and a reflection probe. Each variant has to change what it says it does,
## and its undo has to put every one of those things back, since the
## profiler runs them one after another on the same scene. Headless there
## is nothing drawn, so the frame times themselves are for
## scripts/profile_render.gd on a real GPU.

var _scene: Node3D
var _sun: DirectionalLight3D
var _environment: Environment
var _wall: MeshInstance3D
var _sky: MeshInstance3D
var _probe: ReflectionProbe


func _initialize() -> void:
	_build()
	_check_stats()
	_check_variants()
	_check_occluders()
	_check_render_debug()
	await _check_render_debug_lifecycle()
	if DisplayServer.get_name() != "headless":
		await _check_skybox_crossing_eye()
	_finish("render")


func _build() -> void:
	_scene = Node3D.new()
	root.add_child(_scene)
	# A map whose shadows are baked, as MapLighting sets its sun: the map's
	# layer left out of the live shadow map. Its angular size is kept apart
	# from the entity's here, so each variant that sets it shows.
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.light_angular_distance = 0.25
	_sun.set_meta(&"angular_diameter", 0.5)
	_sun.shadow_caster_mask = 0xFFFFFFFF & ~MapShadows.LAYER
	_sun.directional_shadow_max_distance = 8192.0
	_scene.add_child(_sun)

	_environment = Environment.new()
	_environment.glow_enabled = true
	_environment.fog_enabled = true
	_environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# Graded as MapLighting grades a map: ACES, with CS2's grade kept beside
	# it for other_grade (tests/run_grade_checks.gd checks the grades).
	_environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	_environment.set_meta(&"grade_aces", ColourGrade.current(_environment))
	_environment.set_meta(&"grade_post", MapPostProcessing.load_file(""))
	_environment.set_meta(&"grade_exposure", 1.0)
	_environment.set_meta(&"grade", "aces")
	var world_environment := WorldEnvironment.new()
	world_environment.environment = _environment
	_scene.add_child(world_environment)

	_wall = MeshInstance3D.new()
	_wall.mesh = BoxMesh.new()
	_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	_scene.add_child(_wall)

	_sky = MeshInstance3D.new()
	_sky.mesh = BoxMesh.new()
	_sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sky.material_override = FarMaterials.build(StandardMaterial3D.new(), FarMaterials.far_plane_depth())
	_scene.add_child(_sky)

	_probe = ReflectionProbe.new()
	_probe.size = Vector3.ONE * 256.0
	_scene.add_child(_probe)

	root.msaa_3d = Viewport.MSAA_4X
	root.use_occlusion_culling = true


func _check_stats() -> void:
	_check_equal(RenderVariants.sun_of(_scene), _sun, "the sun is found")
	_check_equal(RenderVariants.environment_of(_scene), _environment, "the environment is found")
	_check_equal(RenderVariants.far_meshes(_scene), [_sky] as Array[MeshInstance3D], "only the skybox's mesh is drawn behind everything")
	var stats := RenderVariants.scene_stats(_scene)
	_check_equal(stats["instances"], 2, "two mesh instances counted")
	_check_equal(stats["triangles"], 24, "a box is twelve triangles, two boxes 24")
	_check_equal(stats["casting_instances"], 1, "the wall casts, the skybox does not")
	_check_equal(stats["double_sided_casters"], 1, "the wall casts from both faces")
	_check_equal(stats["sun_casting_instances"], 1, "and into the sun's shadow map, on a layer it takes")
	_wall.layers = MapShadows.LAYER
	_check_equal(
		RenderVariants.scene_stats(_scene)["sun_casting_instances"], 0,
		"on the layer a map with baked shadows is drawn on, it casts into the lamps' shadows only"
	)
	_wall.layers = 1
	_check_equal(stats["skybox_instances"], 1, "the skybox's mesh is counted as the skybox")
	_check_equal(stats["skybox_triangles"], 12, "the skybox's triangles")


## Everything a variant may touch, as it stands.
func _state() -> Dictionary:
	var viewport := root
	return {
		"shadows": _sun.shadow_enabled,
		"angular": _sun.light_angular_distance,
		"casters": _sun.shadow_caster_mask,
		"distance": _sun.directional_shadow_max_distance,
		"casting": _wall.cast_shadow,
		"msaa": viewport.msaa_3d,
		"glow": _environment.glow_enabled,
		"tonemap": _environment.tonemap_mode,
		"fog": _environment.fog_enabled,
		"reflections": _environment.reflected_light_source,
		"probe": _probe.intensity,
		"probe_shown": _probe.visible,
		"sky": _sky.visible,
		"scale": viewport.scaling_3d_scale,
		"occlusion": viewport.use_occlusion_culling,
		"hdr_2d": viewport.use_hdr_2d,
	}


func _check_variants() -> void:
	var expected := {
		"live_map_shadows": {"casters": 0xFFFFFFFF, "angular": 0.5},
		"no_sun_shadows": {"shadows": false},
		"sun_hard_edges": {"angular": 0.0},
		"sun_filter_low": {},
		"sun_atlas_4096": {},
		"sun_distance_2048": {"distance": 2048.0},
		"one_sided_casters": {"casting": GeometryInstance3D.SHADOW_CASTING_SETTING_ON},
		"no_occlusion": {"occlusion": false},
		# This scene has no visibility to turn off: tests/run_map_tests.gd
		# checks it on the map's culling.
		"no_visibility": {},
		"no_msaa": {"msaa": Viewport.MSAA_DISABLED},
		"sdr_2d": {"hdr_2d": false},
		# This scene has no HUD to unblur: tests/run_hud_checks.gd checks it.
		"no_hud_blur": {},
		"no_glow": {"glow": false},
		# Source 2 Viewer's defaults have no bloom.
		"other_grade": {"tonemap": Environment.TONE_MAPPER_LINEAR, "glow": false},
		"no_fog": {"fog": false},
		"no_reflections": {"reflections": Environment.REFLECTION_SOURCE_DISABLED, "probe": 0.0},
		"no_skybox": {"sky": false},
		"no_players": {},
		"half_resolution": {"scale": 0.5},
		"all_off": {
			"shadows": false, "angular": 0.0, "distance": 2048.0,
			"casting": GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "msaa": Viewport.MSAA_DISABLED,
			"hdr_2d": false, "glow": false, "fog": false, "sky": false,
			"reflections": Environment.REFLECTION_SOURCE_DISABLED, "probe": 0.0,
		},
	}
	var before := _state()
	for variant in RenderVariants.names():
		_check(RenderVariants.VARIANTS[variant] is String, "%s says what it tells" % variant)
		if variant == "baseline":
			continue
		_check(expected.has(variant), "%s is checked here" % variant)
		var undo := RenderVariants.apply(variant, _scene, root)
		var during := _state()
		var changes: Dictionary = expected.get(variant, {})
		for what: String in before:
			var wanted: Variant = changes.get(what, before[what])
			_check_equal(during[what], wanted, "%s: %s" % [variant, what])
		undo.call()
		_check_equal(_state(), before, "%s is put back" % variant)


func _box(parent: Node, size: float, part: String, where: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * size
	mesh_instance.mesh = box
	mesh_instance.name = part
	mesh_instance.position = where
	parent.add_child(mesh_instance)
	return mesh_instance


## F11's steps (RenderDebug) each change their one thing and put it back.
func _check_render_debug() -> void:
	var skybox := Node3D.new()
	skybox.name = "Skybox"
	root.add_child(skybox)
	var visibility := WorldVisibility.new()
	root.add_child(visibility)
	visibility.set_process(true)
	var occlusion := root.use_occlusion_culling
	var steps := {
		"no_occlusion": func() -> bool: return root.use_occlusion_culling == false,
		"no_visibility": func() -> bool: return not visibility.is_processing(),
		"hide_skybox": func() -> bool: return not skybox.visible,
		"draw_occluders": func() -> bool: return root.debug_draw == Viewport.DEBUG_DRAW_OCCLUDERS,
	}
	_check_equal(RenderDebug.STEPS.size(), steps.size() + 1, "F11 steps through each of these and back to as is")
	for each: Array in RenderDebug.STEPS:
		if String(each[0]).is_empty():
			continue
		var undo: Callable = RenderDebug.apply(each[0], root, root)
		_check(steps.has(each[0]) and (steps[each[0]] as Callable).call(), "F11's %s does what it says" % each[0])
		undo.call()
		_check(
			root.use_occlusion_culling == occlusion and skybox.visible and visibility.is_processing()
				and root.debug_draw == Viewport.DEBUG_DRAW_DISABLED,
			"and is put back"
		)
	skybox.free()
	visibility.set_process(false)
	var undo := RenderDebug.apply("no_visibility", root, root)
	undo.call()
	_check(not visibility.is_processing(), "a visibility pass already paused stays paused after a debug step")
	visibility.free()


## Leaving the map while F11 is active must restore the surviving viewport.
func _check_render_debug_lifecycle() -> void:
	var skybox := Node3D.new()
	skybox.name = "Skybox"
	root.add_child(skybox)
	var visibility := WorldVisibility.new()
	root.add_child(visibility)
	visibility.set_process(true)
	var occlusion := root.use_occlusion_culling
	var drawing := root.debug_draw
	for step in range(1, RenderDebug.STEPS.size()):
		var debug := RenderDebug.new()
		root.add_child(debug)
		await process_frame
		var press := InputEventKey.new()
		press.keycode = RenderDebug.KEY
		press.pressed = true
		debug._unhandled_key_input(press)
		_check(debug.step == 1 and debug._label.visible and root.is_input_handled(),
			"an F11 press advances once, shows the step and consumes its event")
		press.echo = true
		debug._unhandled_key_input(press)
		press.echo = false
		press.pressed = false
		debug._unhandled_key_input(press)
		_check_equal(debug.step, 1, "F11 repeats and releases leave the view unchanged")
		debug.go_to(step)
		debug.free()
		_check(root.use_occlusion_culling == occlusion and root.debug_draw == drawing
			and skybox.visible and visibility.is_processing(),
			"leaving the map restores the %s step" % RenderDebug.STEPS[step][0])
	visibility.free()
	skybox.free()


## Dust2's skybox terrain can almost coincide with the eye. Large triangles
## then cross behind it: exercise real clipping, not just positive-distance
## arithmetic. Both the vertex squeeze and custom-vertex fallback must let
## the map floor win while keeping uncovered scenery beyond the near cutoff.
func _check_skybox_crossing_eye() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 180)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.fov = ViewModelProjection.vertical_fov(ViewModelProjection.WORLD_FOV)
	camera.near = ViewModelProjection.NEAR
	camera.far = 16384.0
	camera.rotation.x = deg_to_rad(-13.9)
	viewport.add_child(camera)
	camera.make_current()
	var floor_mesh := MeshInstance3D.new()
	var floor_plane := PlaneMesh.new()
	floor_plane.size = Vector2(13000, 9728)
	floor_mesh.mesh = floor_plane
	floor_mesh.position.y = -64.0
	var blue := Shader.new()
	blue.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled;\nvoid fragment() { ALBEDO = vec3(0.0, 0.0, 1.0); }\n"
	var floor_material := ShaderMaterial.new()
	floor_material.shader = blue
	floor_mesh.material_override = floor_material
	viewport.add_child(floor_mesh)
	var sky := MeshInstance3D.new()
	sky.mesh = floor_plane
	sky.custom_aabb = FarMaterials.CULL_BOX
	viewport.add_child(sky)
	for own_vertex in [false, true]:
		var red := Shader.new()
		red.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled;\n" \
			+ ("void vertex() { POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0); }\n" if own_vertex else "") \
			+ "void fragment() { ALBEDO = vec3(1.0, 0.0, 0.0); }\n"
		var sky_material := ShaderMaterial.new()
		sky_material.shader = red
		sky.set_surface_override_material(0, sky_material)
		var meshes: Array[MeshInstance3D] = [sky]
		FarMaterials.apply(meshes)
		for height: float in [-0.003, 0.003, -32.0]:
			# The skybox is static; move the eye and keep the map 64 below it.
			camera.position.y = -height
			floor_mesh.position.y = -height - 64.0
			await process_frame
			await RenderingServer.frame_post_draw
			var pixels := viewport.get_texture().get_image()
			var floor_pixels := 0
			var sky_pixels := 0
			for y in range(100, 178):
				for x in range(2, 318):
					var colour := pixels.get_pixel(x, y)
					if colour.b > 0.9 and colour.r < 0.1:
						floor_pixels += 1
					if colour.r > 0.9 and colour.b < 0.1:
						sky_pixels += 1
			_check(floor_pixels > 20000 and sky_pixels == 0,
				"the map floor wins over skybox terrain at eye offset %.3f (%s squeeze; %d floor, %d sky pixels)" \
				% [height, "fragment" if own_vertex else "vertex", floor_pixels, sky_pixels])
		# The squeezed red plane is still drawn when the map does not cover it.
		floor_mesh.visible = false
		await process_frame
		await RenderingServer.frame_post_draw
		var uncovered := viewport.get_texture().get_image().get_pixel(160, 140)
		_check(uncovered.r > 0.9 and uncovered.b < 0.1,
			"uncovered skybox terrain is kept visible (%s squeeze, %s)" % ["fragment" if own_vertex else "vertex", uncovered])
		floor_mesh.visible = true
		# Move from distant terrain back to nearly touching it. The cutoff
		# reads this draw's view-space position, without stale camera state.
		camera.position.y = 128.003
		floor_mesh.position.y = 64.003
		await process_frame
		await RenderingServer.frame_post_draw
		var distant := viewport.get_texture().get_image().get_pixel(160, 140)
		_check(distant.b > 0.9 and distant.r < 0.1,
			"distant skybox terrain remains behind the map (%s squeeze)" % ["fragment" if own_vertex else "vertex"])
		camera.position.y = 0.003
		floor_mesh.position.y = -63.997
		await process_frame
		await RenderingServer.frame_post_draw
		var teleported := viewport.get_texture().get_image().get_pixel(160, 140)
		_check(teleported.b > 0.9 and teleported.r < 0.1,
			"the near cutoff remains correct after teleporting the eye (%s squeeze)" % ["fragment" if own_vertex else "vertex"])
		camera.position.y = 0.0
		floor_mesh.position.y = -64.0
	viewport.free()


func _check_occluders() -> void:
	var skip := PackedStringArray(["playerclip", "grenadeclip"])
	_check(MapOccluders.occludes("physics_group_concrete", skip), "a concrete hull part hides what is behind it")
	_check(not MapOccluders.occludes("physics_group_playerclip", skip), "a player clip does not")
	_check(not MapOccluders.occludes("physics_group_grenadeclip", skip), "a grenade clip does not")
	_check(not MapOccluders.occludes("physics_group_Glass", skip), "glass does not, whatever its case")
	_check(not MapOccluders.occludes("physics_group_metalgrate", skip), "a grate does not")
	_check(not MapOccluders.occludes("physics_group_passbullets", skip), "what rounds pass through does not")
	_check(not MapOccluders.occludes("physics_sky", skip), "the sky's brushes do not: nobody sees them (playtest issue 11)")
	_check(MapOccluders.occludes("physics_group_wood_plank", skip), "nor does leaving the sky out catch a wall")

	# Out of the tree, as the importer may be: scaled and turned the way
	# the import turns a map, with its hull a level down.
	var importer := Node3D.new()
	importer.position = Vector3(1000.0, 0.0, 0.0)
	var hull := Node3D.new()
	hull.scale = Vector3.ONE * 2.0
	hull.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	importer.add_child(hull)
	var wall := _box(hull, 100.0, "physics_group_concrete", Vector3(10.0, 0.0, 0.0))
	_box(hull, 100.0, "physics_group_playerclip")
	_box(hull, 100.0, "physics_group_glass")
	_box(hull, 100.0, "physics_sky", Vector3(0.0, 0.0, 300.0))
	# Each face 2 by 2 units, 4 by 4 once scaled: its triangles are 8 square units.
	var pebble := _box(hull, 2.0, "physics_group_rock")
	var meshes: Array[MeshInstance3D] = []
	for child in hull.get_children():
		meshes.append(child as MeshInstance3D)

	var relative := MapOccluders.relative_transform(importer, wall)
	_check((relative.origin - Vector3(20.0, 0.0, 0.0)).length() < 0.001, "a part's place in the importer's space takes in the hull's scale")
	_check((relative.basis.y - Vector3(0.0, 0.0, -2.0)).length() < 0.001, "and its turn")
	_check_equal(MapOccluders.relative_transform(importer, pebble).basis.get_scale().x, 2.0, "and the scale down to each part")

	var triangles := MapOccluders.build(importer, meshes, skip)
	_check_equal(triangles, 12, "only the concrete wall occludes: its twelve triangles, not the sky's, the pebble's too small")
	var occluders := importer.find_children("*", "OccluderInstance3D", false, false)
	_check_equal(occluders.size(), 1, "one occluder is added under the importer")
	if occluders.size() == 1:
		var occluder := (occluders[0] as OccluderInstance3D).occluder
		var box := AABB()
		var first := true
		for vertex in occluder.get_vertices():
			box = AABB(vertex, Vector3.ZERO) if first else box.expand(vertex)
			first = false
		_check((box.get_center() - Vector3(20.0, 0.0, 0.0)).length() < 0.5, "the occluder stands where the wall is")
		_check_near(box.size.x, 200.0, "and is the wall's size once scaled")
	var nothing := Node3D.new()
	_check_equal(MapOccluders.build(nothing, [] as Array[MeshInstance3D]), 0, "no hull, no triangles")
	_check_equal(nothing.get_child_count(), 0, "and no occluder added")
	importer.free()
	nothing.free()
