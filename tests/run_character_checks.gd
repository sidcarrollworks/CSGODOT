extends "res://tests/check_suite.gd"

## Checks CS2's character shading (CharacterMaterials, character.gdshader)
## without the extracted models: which materials take it, what each is
## handed from its description, the buy menu's agent lit by its own world,
## and the cloth masks readied for the import. Shaders do not compile
## headless, so what the shader draws is checked on a GPU
## (reference/rendering.md, R7); here only its code.
##
##   godot --headless --path . --script tests/run_character_checks.gd

const SCRATCH := "user://character_checks"


func _initialize() -> void:
	_test_routing()
	_test_carry()
	_test_surface_constants()
	_test_shader_code()
	_test_models_off_the_probes()
	_test_mask_alpha()
	_test_eye_carry()
	_test_iris_split()
	_test_eye_aim()
	await _test_eyes_on_the_rig()
	_test_extracted_lenses()
	await _test_lens_render()
	_finish("character")


## A character's description, as Source 2 Viewer writes it into the glTF's
## extras, and a standard material carrying it.
func _character(params: Dictionary = {}) -> StandardMaterial3D:
	var description := {
		"Name": "materials/test/agent_body.vmat",
		"ShaderName": CharacterMaterials.SHADER_NAME,
		"IntParams": params.get("ints", {}),
		"FloatParams": params.get("floats", {}),
		"VectorParams": params.get("vectors", {}),
		"TextureParams": params.get("textures", {}),
	}
	var material := StandardMaterial3D.new()
	material.set_meta("extras", {"vmat": description})
	return material


func _test_routing() -> void:
	var body := _character()
	var lit := ProbeMaterials.build(body)
	_check(
		lit.shader == CharacterMaterials.SHADER and ProbeMaterials.build(body) == lit
			and is_equal_approx(lit.get_shader_parameter("probe_energy"), LightmapMaterials.energy()),
		"a material CS2 draws with csgo_character goes on the character shader, made once, at the probes' energy"
	)
	var prop := StandardMaterial3D.new()
	prop.set_meta("extras", {"vmat": {"ShaderName": "csgo_complex.vfx"}})
	_check(ProbeMaterials.build(prop).shader == ProbeMaterials.SHADER, "anything else stays on the probe shader")

	var two_sided := _character()
	two_sided.cull_mode = BaseMaterial3D.CULL_DISABLED
	var two_sided_prop := StandardMaterial3D.new()
	two_sided_prop.cull_mode = BaseMaterial3D.CULL_DISABLED
	var character_variant := ProbeMaterials.build(two_sided).shader
	var prop_variant := ProbeMaterials.build(two_sided_prop).shader
	_check(
		character_variant != CharacterMaterials.SHADER and character_variant != prop_variant
			and character_variant.code.contains("cull_disabled") and character_variant.code.contains("character_charlie(")
			and not prop_variant.code.contains("character_charlie("),
		"a two-sided character material gets a two-sided variant of the character shader, apart from the props' one"
	)
	var blended := _character()
	blended.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var blended_code := ProbeMaterials.build(blended).shader.code
	_check(
		blended_code.contains("\tALPHA = albedo.a;\n") and not blended_code.contains("ALPHA_SCISSOR_THRESHOLD")
			and blended_code.contains("character_charlie("),
		"and a blended one a blended variant of it"
	)


func _test_carry() -> void:
	var plain := ProbeMaterials.build(_character({"floats": {"g_flAmbientOcclusionDirectSpecular": 0.25}}))
	_check(
		_flag(plain, "cloth_shading") == false
			and is_equal_approx(plain.get_shader_parameter("direct_diffuse_occlusion"), 1.0)
			and is_equal_approx(plain.get_shader_parameter("direct_specular_occlusion"), 0.25),
		"a material that asks for no cloth has none, and its occlusion on the direct light is CS2's default or its own"
	)

	# A mask decompiled where the material names it, under a directory of
	# the test's own.
	var directory := SCRATCH.path_join("carry")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory.path_join("materials/test")))
	var mask := Image.create(4, 4, false, Image.FORMAT_RGB8)
	mask.fill(Color(0.0, 0.0, 1.0))
	mask.save_png(ProjectSettings.globalize_path(directory.path_join("materials/test/agent_body_metal.png")))
	var cloth := _character({
		"ints": {"F_CLOTH_SHADING": 1},
		"floats": {"g_flSheenScale": 0.5},
		"vectors": {"g_flSheenTintColor": [0.5, 1.0, 1.0, 0.0]},
		"textures": {"g_tMetalness": "materials/test/agent_body_metal.vtex"},
	})
	var lit := ProbeMaterials.build(cloth, directory)
	var tint: Variant = lit.get_shader_parameter("sheen_tint")
	_check(
		_flag(lit, "cloth_shading") == true and lit.get_shader_parameter("cloth_mask") is Texture2D
			and is_equal_approx(lit.get_shader_parameter("sheen_scale"), 0.5)
			and tint is Vector3 and is_equal_approx((tint as Vector3).x, Color(0.5, 1, 1).srgb_to_linear().r)
			and is_equal_approx((tint as Vector3).y, 1.0),
		"a material that asks for cloth gets its mask, from where the material names it, with its sheen's scale, and its tint in linear light (%s)" % [tint]
	)
	var defaulted := ProbeMaterials.build(_character({
		"ints": {"F_CLOTH_SHADING": 1},
		"textures": {"g_tMetalness": "materials/test/agent_body_metal.vtex"},
	}), directory)
	_check(
		is_equal_approx(defaulted.get_shader_parameter("sheen_scale"), CharacterMaterials.SHEEN_SCALE)
			and (defaulted.get_shader_parameter("sheen_tint") as Vector3).is_equal_approx(Vector3.ONE),
		"and where the material leaves them out, CS2's defaults: a scale of 0.667, a white tint"
	)
	var unmasked := ProbeMaterials.build(_character({
		"ints": {"F_CLOTH_SHADING": 1},
		"textures": {"g_tMetalness": "materials/test/not_extracted.vtex"},
	}), directory)
	_check(
		_flag(unmasked, "cloth_shading") == false and unmasked.get_shader_parameter("cloth_mask") == null,
		"without its mask there, a material that asks for cloth is shaded as before"
	)
	_check(
		CharacterMaterials.mask_file(cloth.get_meta("extras")["vmat"], directory)
			== directory.path_join("materials/test/agent_body_metal.png")
			and CharacterMaterials.mask_file({}) == "",
		"the mask is looked for by the path the material names it by, as the extraction decompiles it"
	)


## Whether a float shader parameter is 0, or was never set (its default, 0).
func _zero(value: Variant) -> bool:
	return value == null or is_zero_approx(float(value))


## A bool shader parameter as set, or false where it was never set.
func _flag(lit: ShaderMaterial, name: String) -> bool:
	var value: Variant = lit.get_shader_parameter(name)
	return value == true


## CS2's SAS lenses have constant metalness 1 and roughness 32/255. Their
## exported ORM instead carries metalness 0 and roughness 1. Restore only
## the scalar source inputs; keep the imported textures, AO and cache.
func _test_surface_constants() -> void:
	var lens := _constant_lens()
	var lit := ProbeMaterials.build(lens)
	_check(
		lit.shader == CharacterMaterials.SHADER and ProbeMaterials.build(lens) == lit
			and is_equal_approx(lit.get_shader_parameter("source_metalness"), 1.0)
			and is_equal_approx(lit.get_shader_parameter("source_roughness"), 0.12549),
		"constant character surface inputs come from the material even when the exported ORM lost them, on the cached character shader"
	)
	_check(
		lit.get_shader_parameter("orm_texture") == lens.roughness_texture
			and lit.get_shader_parameter("albedo_texture") == lens.albedo_texture
			and not _flag(lit, "eyes"),
		"the lens keeps its imported textures and baked AO, and has no eyeball shader"
	)
	var cloth := ProbeMaterials.build(_character())
	var nonuniform := ProbeMaterials.build(_character({
		"vectors": {"TextureMetalness": [1, 0, 1, 0]},
		"textures": {"g_tMetalness": "materials/test/agent_vmat_g_tmetalness_1234abcd.vtex"},
	}))
	_check(
		_no_surface_constant(cloth, "source_metalness") and _no_surface_constant(cloth, "source_roughness")
			and _no_surface_constant(nonuniform, "source_metalness"),
		"textured clothing and nonuniform input vectors keep their exported ORM channels"
	)
	var zero := ProbeMaterials.build(_character({
		"vectors": {"TextureMetalness": [0, 0, 0, 0]},
		"textures": {"g_tMetalness": "materials/test/agent_vmat_g_tmetalness_1234abcd.vtex"},
	}))
	_check(
		zero.get_shader_parameter("source_metalness") != null
			and is_zero_approx(zero.get_shader_parameter("source_metalness")),
		"an explicitly nonmetallic source input is retained too"
	)
	var stale := _constant_lens()
	var stale_description := BlendMaterials.vmat(stale)
	stale_description["TextureParams"] = {
		"g_tMetalness": "materials/test/fabric_cloth_psd_1234abcd.vtex",
		"g_tNormal": "materials/test/fabric_normal_psd_1234abcd.vtex",
	}
	var varying := Image.create(2, 2, false, Image.FORMAT_RGB8)
	varying.fill(Color(0.75, 0.2, 0.0))
	varying.set_pixel(1, 1, Color(0.75, 0.6, 0.8))
	stale.roughness_texture = ImageTexture.create_from_image(varying)
	var textured := ProbeMaterials.build(stale)
	_check(
		_no_surface_constant(textured, "source_metalness") and _no_surface_constant(textured, "source_roughness")
			and textured.get_shader_parameter("orm_texture") == stale.roughness_texture,
		"a varying bound artist texture keeps its ORM channels despite stale uniform authoring vectors"
	)
	var unbound := ProbeMaterials.build(_character({"vectors": {
		"TextureMetalness": [1.0, 1.0, 1.0, 0.0], "TextureRoughness": [0.12549, 0.12549, 0.12549, 1.0],
	}}))
	_check(
		_no_surface_constant(unbound, "source_metalness") and _no_surface_constant(unbound, "source_roughness"),
		"authoring vectors without generated texture bindings leave the imported channels in use"
	)
	for invalid: float in [NAN, INF, -INF]:
		var broken := _constant_lens()
		var vectors: Dictionary = BlendMaterials.vmat(broken)["VectorParams"]
		vectors["TextureMetalness"] = [invalid, invalid, invalid, 0.0]
		vectors["TextureRoughness"] = [invalid, invalid, invalid, 1.0]
		var rejected := ProbeMaterials.build(broken)
		_check(
			_no_surface_constant(rejected, "source_metalness") and _no_surface_constant(rejected, "source_roughness"),
			"nonfinite source constants never reach the material (%s)" % invalid
		)


func _no_surface_constant(material: ShaderMaterial, parameter: String) -> bool:
	var value: Variant = material.get_shader_parameter(parameter)
	return value == null or is_equal_approx(float(value), -1.0)


## A lens fixture with the same lost channels as the local SAS export.
func _constant_lens() -> StandardMaterial3D:
	var lens := _character({"vectors": {
		"TextureMetalness": [1.0, 1.0, 1.0, 0.0],
		"TextureRoughness": [0.12549, 0.12549, 0.12549, 1.0],
	}, "textures": {
		"g_tMetalness": "materials/test/lens_vmat_g_tmetalness_1234abcd.vtex",
		"g_tNormal": "materials/test/lens_vmat_g_tnormal_1234abcd.vtex",
	}})
	var orm := Image.create(2, 2, false, Image.FORMAT_RGB8)
	orm.fill(Color(0.75, 1.0, 0.0))
	lens.roughness_texture = ImageTexture.create_from_image(orm)
	lens.albedo_color = Color(0.5, 0.478431, 0.478431)
	lens.normal_enabled = false
	return lens


func _test_shader_code() -> void:
	# Read as ProbeMaterials.shader_for reads it: a checkout on Windows has
	# the shader's lines end in CRLF.
	var code := CharacterMaterials.SHADER.code.replace("\r\n", "\n")
	_check(
		code.contains("\tIRRADIANCE = vec4(") and not code.contains("ambient_light_disabled")
			and code.contains("ambient_from_probes);"),
		"the character shader hands its probes' light to Godot as the ambient, or the environment's where told, and keeps the reflections"
	)
	_check(
		code.contains("render_mode blend_mix, depth_draw_opaque, cull_back;")
			and code.contains("\tif (alpha_scissor >= 0.0) {\n\t\tALPHA = albedo.a;\n\t\tALPHA_SCISSOR_THRESHOLD = alpha_scissor;\n\t}\n"),
		"it has what ProbeMaterials makes its variants from: the culling, and the cut as the probe shader writes it"
	)
	_check(
		code.contains("source_roughness >= 0.0 ? source_roughness : orm.g * roughness_factor")
			and code.contains("source_metalness >= 0.0 ? source_metalness : orm.b")
			and code.contains("ROUGHNESS = max(material_roughness, geometric_roughness)")
			and code.contains("cloth = mask.y * (1.0 - mask.x)") and code.contains("AO = orm.r;"),
		"the constant inputs replace only their channels before specular anti-aliasing, and true metal has no cloth sheen"
	)
	# Godot numbers a shader's instance uniforms in the order they are
	# declared and reads a mesh's by that number, so on a mesh with surfaces
	# on both shaders the ones they share have to line up.
	var probe_lit := _instance_uniforms(ProbeMaterials.SHADER.code)
	var character := _instance_uniforms(code)
	_check(
		probe_lit.size() == 11 and character.size() == probe_lit.size() + 1
			and character.slice(0, probe_lit.size()) == probe_lit and character[-1] == "ambient_from_probes"
			and character.size() <= 16,
		"the character shader's instance uniforms are the probe shader's, in the same slots, and one more, within Godot's 16 (%s)" % [character]
	)


## The names of a shader's instance uniforms in the order Godot numbers
## them, its includes read where they are included.
func _instance_uniforms(code: String) -> PackedStringArray:
	var names := PackedStringArray()
	var pattern := RegEx.create_from_string("instance uniform \\w+ (\\w+)")
	for line in code.replace("\r\n", "\n").split("\n"):
		if line.begins_with("#include \""):
			var include := load(line.trim_prefix("#include \"").trim_suffix("\"")) as ShaderInclude
			names.append_array(_instance_uniforms(include.code) if include != null else PackedStringArray(["?"]))
			continue
		var found := pattern.search(line)
		if found != null and not line.strip_edges().begins_with("//"):
			names.append(found.get_string(1))
	return names


## A model that stands in a world of its own (RigModel.probe_lit false):
## its character surfaces are shaded as the players' are, by the world's
## light, and the rest left alone; a body put on the probes later takes
## their light.
func _test_models_off_the_probes() -> void:
	var model := RigModel.new()
	model.probe_lit = false
	var rig := Skeleton3D.new()
	model.add_child(rig)
	root.add_child(model)
	var holder := Node3D.new()
	root.add_child(holder)
	var mesh := MeshInstance3D.new()
	var surfaces := ArrayMesh.new()
	var box := BoxMesh.new().get_mesh_arrays()
	surfaces.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box)
	surfaces.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box)
	var body := _character()
	var buckle := StandardMaterial3D.new()
	surfaces.surface_set_material(0, body)
	surfaces.surface_set_material(1, buckle)
	mesh.mesh = surfaces
	holder.add_child(mesh)
	model.adopt(mesh, rig)
	_check(
		mesh.get_surface_override_material(0) == ProbeMaterials.build(body)
			and mesh.get_surface_override_material(1) == null
			and mesh.get_instance_shader_parameter(CharacterMaterials.AMBIENT_FROM_PROBES) == 0.0,
		"off the probes, a character surface goes on the character shader, lit by its world's environment, and the rest is left as it was"
	)
	model.use_probe_lighting()
	_check(
		mesh.get_surface_override_material(0) == ProbeMaterials.build(body)
			and mesh.get_surface_override_material(1) == ProbeMaterials.build(buckle)
			and (mesh.get_surface_override_material(1) as ShaderMaterial).shader == ProbeMaterials.SHADER
			and mesh.get_instance_shader_parameter(CharacterMaterials.AMBIENT_FROM_PROBES) == 1.0,
		"put on the probes after all, the character surface takes their light and the rest goes on the probe shader"
	)
	model.free()
	holder.free()


## Check the actual imported lens surface when the local CS2 agents are
## available. The same source is used in the map and the buy-menu world.
func _test_extracted_lenses() -> void:
	var path := "res://assets/characters/agents/models/ctm_sas/ctm_sas.gltf"
	if not ResourceLoader.exists(path):
		print("no extracted SAS agent; its lens surfaces not checked")
		return
	var scene := RigModel.instantiate(path)
	var lenses := 0
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as BaseMaterial3D
			if source == null or source.resource_name != "ctm_sas_lenses":
				continue
			lenses += 1
			var description := BlendMaterials.vmat(source)
			var lit := ProbeMaterials.build(source)
			_check(
				CharacterMaterials.is_character(description) and not CharacterMaterials.wants_eyes(description)
					and lit.shader == CharacterMaterials.SHADER and not _flag(lit, "eyes")
					and is_equal_approx(lit.get_shader_parameter("source_metalness"), 1.0)
					and is_equal_approx(lit.get_shader_parameter("source_roughness"), 0.12549)
					and lit.get_shader_parameter("cloth_mask") is Texture2D,
				"the imported SAS gas-mask lenses retain CS2's polished metal inputs and source mask, without painted eyeballs"
			)
			CharacterMaterials.use_environment(mesh)
			_check(
				mesh.get_active_material(surface) == lit
					and is_zero_approx(mesh.get_instance_shader_parameter(CharacterMaterials.AMBIENT_FROM_PROBES)),
				"the buy-menu world's SAS lenses use the same cached material with its own ambient light"
			)
			CharacterMaterials.use_probes(mesh)
			_check(
				mesh.get_active_material(surface) == lit
					and is_equal_approx(mesh.get_instance_shader_parameter(CharacterMaterials.AMBIENT_FROM_PROBES), 1.0),
				"returning to map probes preserves the lens material and its constants"
			)
	_check(lenses > 0, "the extracted SAS agent includes its gas-mask lens surface")
	scene.free()


## A GPU check of the original failure: under direct warm light an ORM
## with metalness 0 paints tan. Restoring the source inputs makes the metal
## reflect its environment, whose blue is tested separately. Headless CI
## still runs the binding/asset checks above; it cannot compile a shader.
func _test_lens_render() -> void:
	if DisplayServer.get_name() == "headless":
		print("headless; the lens render check needs a GPU")
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64, 64)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color.BLACK
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_energy = 0.0
	world.environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	viewport.add_child(world)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.0, 2.0)
	camera.current = true
	camera.near = 0.01
	viewport.add_child(camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, -40.0, 0.0)
	sun.light_color = Color(1.0, 0.8, 0.6)
	sun.light_energy = 2.0
	viewport.add_child(sun)
	var mesh := MeshInstance3D.new()
	mesh.mesh = QuadMesh.new()
	viewport.add_child(mesh)
	var restored := ProbeMaterials.build(_constant_lens()).duplicate() as ShaderMaterial
	mesh.material_override = restored
	mesh.set_instance_shader_parameter(CharacterMaterials.AMBIENT_FROM_PROBES, 0.0)
	var metal := await _lens_pixel(viewport)
	var exported := restored.duplicate() as ShaderMaterial
	exported.set_shader_parameter("source_metalness", -1.0)
	exported.set_shader_parameter("source_roughness", -1.0)
	mesh.material_override = exported
	var tan := await _lens_pixel(viewport)
	_check(
		tan.r > 0.15 and metal.r < tan.r * 0.1,
		"the polished lens no longer receives the warm diffuse light of the broken ORM (metal %s, exported %s)" % [metal, tan]
	)
	# A uniform blue panorama removes scene/sky orientation from this check.
	var panorama := Image.create(8, 4, false, Image.FORMAT_RGBF)
	panorama.fill(Color(0.04, 0.2, 0.8))
	var sky_material := PanoramaSkyMaterial.new()
	sky_material.panorama = ImageTexture.create_from_image(panorama)
	var sky := Sky.new()
	sky.sky_material = sky_material
	world.environment.sky = sky
	world.environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	mesh.material_override = restored
	sun.visible = false
	var reflection := await _lens_pixel(viewport)
	_check(
		reflection.b > 0.1 and reflection.b > reflection.r * 2.0,
		"the restored metal reflects the blue environment instead of the tan base colour (%s)" % reflection
	)
	viewport.free()


func _lens_pixel(viewport: SubViewport) -> Color:
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image().get_pixel(32, 32)


## The masks' alpha dropped before the import, which would paint over the
## cloth wherever the rim mask is clear; a glTF not an agent's left alone,
## and nothing to do the second time.
func _test_mask_alpha() -> void:
	var directory := SCRATCH.path_join("masks")
	var agent := directory.path_join("agents/models/test/agent.gltf")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(agent.get_base_dir()))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory.path_join("materials/test")))
	var gltf := "{\"materials\": [{\"extras\": {\"vmat\": {\"TextureParams\": {\"g_tMetalness\": \"materials/test/body_metal.vtex\", \"g_tColor\": \"materials/test/body_color.vtex\"}}}}]}"
	var file := FileAccess.open(agent, FileAccess.WRITE)
	file.store_string(gltf)
	file.close()
	var png := directory.path_join("materials/test/body_metal.png")
	var colour := directory.path_join("materials/test/body_color.png")
	var mask := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	mask.fill(Color(0.2, 0.0, 1.0, 0.0))
	mask.set_pixel(0, 0, Color(0.2, 1.0, 0.0, 1.0))
	mask.save_png(ProjectSettings.globalize_path(png))
	mask.save_png(ProjectSettings.globalize_path(colour))
	var elsewhere := directory.path_join("maps/world.gltf")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(elsewhere.get_base_dir()))
	file = FileAccess.open(elsewhere, FileAccess.WRITE)
	file.store_string(gltf)
	file.close()

	var elsewhere_fixed := ExportCharacterMasks.fix_file(elsewhere, directory)
	var first := ExportCharacterMasks.fix_file(agent, directory)
	var second := ExportCharacterMasks.fix_file(agent, directory)
	var after := Image.load_from_file(ProjectSettings.globalize_path(png))
	_check(
		elsewhere_fixed == 0 and first == 1 and second == 0
			and after != null and after.detect_alpha() == Image.ALPHA_NONE
			and after.get_pixel(4, 4).is_equal_approx(Color(0.2, 0.0, 1.0)) and after.get_pixel(0, 0).is_equal_approx(Color(0.2, 1.0, 0.0))
			and Image.load_from_file(ProjectSettings.globalize_path(colour)).detect_alpha() != Image.ALPHA_NONE,
		"a mask an agent names loses its alpha and keeps its colours, once; a glTF not an agent's and the other textures are left alone (%d, %d, %d)"
			% [elsewhere_fixed, first, second]
	)


## The eye textures of a material that draws eyes, decompiled where it names
## them under directory, the iris split off as the prepare step splits it;
## and the material.
func _eye_material(directory: String, floats: Dictionary = {}) -> StandardMaterial3D:
	var absolute := ProjectSettings.globalize_path(directory.path_join("materials/eyes"))
	DirAccess.make_dir_recursive_absolute(absolute)
	var colour := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	colour.fill(Color(1, 1, 1, 0))
	colour.set_pixel(1, 1, Color(0.2, 0.3, 0.8, 1.0))
	colour.save_png(absolute.path_join("eye_color.png"))
	DirAccess.remove_absolute(absolute.path_join("eye_color_iris.png"))
	ExportCharacterMasks.split_iris(directory.path_join("materials/eyes/eye_color.png"))
	var mask := Image.create(4, 4, false, Image.FORMAT_RGB8)
	mask.fill(Color.WHITE)
	mask.save_png(absolute.path_join("eye_mask.png"))
	return _character({
		"ints": {"F_EYEBALLS": 1},
		"floats": floats,
		"textures": {
			CharacterMaterials.EYE_ALBEDO: "materials/eyes/eye_color.vtex",
			CharacterMaterials.EYE_MASK: "materials/eyes/eye_mask.vtex",
		},
	})


func _test_eye_carry() -> void:
	var directory := SCRATCH.path_join("eyes")
	var phoenix := {
		"g_flEyeBallRadius1": 0.6, "g_flEyeIrisSize1": 1.026, "g_flEyePupilSize1": 0.143,
		"g_flEyeHueShift1": 0.0, "g_flEyeSaturation1": 1.0,
		"g_flEyeBallWalleyeL1": 4.578, "g_flEyeBallWalleyeR1": 5.0,
	}
	var lit := ProbeMaterials.build(_eye_material(directory, phoenix), directory)
	_check(
		_flag(lit, "eyes") and lit.get_shader_parameter("eye_albedo") is Texture2D
			and lit.get_shader_parameter("eye_iris") is Texture2D and lit.get_shader_parameter("eye_mask") is Texture2D,
		"a material that draws eyes gets its eye colour, the iris split from it, and its eye mask, from where it names them"
	)
	_check(
		is_equal_approx(lit.get_shader_parameter("eye_radius"), 0.6)
			and is_equal_approx(lit.get_shader_parameter("eye_iris_size"), 1.026)
			and is_equal_approx(lit.get_shader_parameter("eye_pupil_size"), 0.143)
			and is_equal_approx(lit.get_shader_parameter("eye_saturation"), 1.0)
			and (lit.get_meta(CharacterMaterials.WALLEYE) as Vector2).is_equal_approx(Vector2(4.578, 5.0))
			and _zero(lit.get_shader_parameter("eye_scale")),
		"with the Phoenix's eyeball, iris and pupil sizes and walleye, and no eye painted until a rig aims it"
	)
	var defaulted := ProbeMaterials.build(_eye_material(directory), directory)
	_check(
		is_equal_approx(defaulted.get_shader_parameter("eye_iris_size"), 1.0)
			and is_equal_approx(defaulted.get_shader_parameter("eye_saturation"), 1.0),
		"where the material leaves them out, CS2's defaults: an iris size and a saturation of 1"
	)
	var unextracted := ProbeMaterials.build(_character({
		"ints": {"F_EYEBALLS": 1},
		"textures": {
			CharacterMaterials.EYE_ALBEDO: "materials/eyes/not_extracted.vtex",
			CharacterMaterials.EYE_MASK: "materials/eyes/eye_mask.vtex",
		},
	}), directory)
	_check(
		not _flag(unextracted, "eyes") and unextracted.get_shader_parameter("eye_albedo") == null,
		"without its eye textures there, a material keeps the white eyes its colour texture paints"
	)
	var described: Dictionary = _eye_material(directory).get_meta("extras")["vmat"]
	_check(
		CharacterMaterials.eye_file(described, CharacterMaterials.EYE_ALBEDO, false, directory)
			== directory.path_join("materials/eyes/eye_color.png")
			and CharacterMaterials.eye_file(described, CharacterMaterials.EYE_ALBEDO, true, directory)
			== directory.path_join("materials/eyes/eye_color_iris.png")
			and CharacterMaterials.eye_file({}, CharacterMaterials.EYE_MASK) == "",
		"the eye textures are looked for by the paths the material names them by, the iris beside the colour"
	)


## The eye colour's alpha, the iris, moved into a greyscale file of its own
## before the import, which would paint the iris's colour over the white.
func _test_iris_split() -> void:
	var directory := SCRATCH.path_join("iris")
	var agent := directory.path_join("agents/models/test/agent.gltf")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(agent.get_base_dir()))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory.path_join("materials/eyes")))
	var file := FileAccess.open(agent, FileAccess.WRITE)
	file.store_string("{\"materials\": [{\"extras\": {\"vmat\": {\"TextureParams\": {\"g_tEyeAlbedo1\": \"materials/eyes/brown.vtex\"}}}}]}")
	file.close()
	var png := directory.path_join("materials/eyes/brown.png")
	var colour := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	colour.fill(Color(1.0, 1.0, 1.0, 0.0))
	colour.set_pixel(4, 4, Color8(102, 51, 25))
	colour.save_png(ProjectSettings.globalize_path(png))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory.path_join("materials/eyes/brown_iris.png")))
	var first := ExportCharacterMasks.fix_file(agent, directory)
	var second := ExportCharacterMasks.fix_file(agent, directory)
	var after := Image.load_from_file(ProjectSettings.globalize_path(png))
	var iris := Image.load_from_file(ProjectSettings.globalize_path(directory.path_join("materials/eyes/brown_iris.png")))
	_check(
		first == 1 and second == 0 and after != null and after.detect_alpha() == Image.ALPHA_NONE
			and after.get_pixel(0, 0).is_equal_approx(Color(1, 1, 1)) and after.get_pixel(4, 4).is_equal_approx(Color8(102, 51, 25))
			and iris != null and iris.get_pixel(0, 0).r < 0.01 and iris.get_pixel(4, 4).r > 0.99,
		"an eye colour an agent names keeps its colours, white included, and its iris goes to a file of its own, once (%d, %d)"
			% [first, second]
	)


## Where CS2 aims an eye: at the target, turned outward by its walleye, and
## held within 40 degrees of its forward tipped half up and half down.
func _test_eye_aim() -> void:
	var forward := Vector3.FORWARD
	var up := Vector3.UP
	var left := up.cross(forward)
	var ahead := CharacterEyes.aim(Vector3.ZERO, forward, up, forward * 100.0, 0.0)
	_check(ahead.is_equal_approx(forward), "an eye with its target straight ahead looks straight ahead (%s)" % ahead)
	var walleyed := CharacterEyes.aim(Vector3.ZERO, forward, up, forward * 100.0, 5.0)
	_check(
		is_equal_approx(rad_to_deg(walleyed.angle_to(forward)), 5.0) and walleyed.dot(left) > 0.0,
		"a walleye of 5 degrees turns it 5 degrees toward the model's left, outward for the left eye (%s)" % walleyed
	)
	# The two 40-degree cones about the forward tipped half up and half
	# down (26.57 degrees each way) meet 13.43 degrees above and below it,
	# so that is as far as an eye turns up or down.
	var raised := (forward + up * 0.5).normalized()
	var lowered := (forward - up * 0.5).normalized()
	var overhead := CharacterEyes.aim(Vector3.ZERO, forward, up, up * 100.0 + forward, 0.0)
	_check(
		is_equal_approx(rad_to_deg(overhead.angle_to(lowered)), 40.0) and overhead.angle_to(raised) < deg_to_rad(40.0)
			and overhead.dot(up) > 0.0 and absf(overhead.dot(left)) < 1e-4,
		"a target overhead is looked at only as high as both 40-degree cones allow, 13.4 degrees up (%.2f)"
			% rad_to_deg(overhead.angle_to(forward))
	)
	var underfoot := CharacterEyes.aim(Vector3.ZERO, forward, up, -up * 100.0 + forward, 0.0)
	_check(
		is_equal_approx(rad_to_deg(underfoot.angle_to(raised)), 40.0) and underfoot.dot(up) < 0.0,
		"and one underfoot only as low (%.2f)" % rad_to_deg(underfoot.angle_to(forward))
	)


## A model's eyes on its rig: its own copy of the eye material, aimed from
## the eyeball and target bones, turning with the head, the shared material
## left alone.
func _test_eyes_on_the_rig() -> void:
	# The tree is up after the first frame, and the eyes are placed in it.
	await process_frame
	var directory := SCRATCH.path_join("rig")
	var source := _eye_material(directory, {"g_flEyeBallRadius1": 0.6, "g_flEyeBallWalleyeL1": 4.578, "g_flEyeBallWalleyeR1": 5.0})
	var shared := ProbeMaterials.build(source, directory)

	# A rig as the export makes one, in metres, facing -z with the model's
	# left at -x, and the model scaled to units as PlayerModel scales it.
	var model := RigModel.new()
	model.scale = Vector3.ONE * MapImporter.SOURCE2_VIEWER_SCALE
	var rig := Skeleton3D.new()
	rig.add_bone("head_0")
	rig.set_bone_rest(0, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.6, 0.0)))
	for bone: Array in [["eyeball_l", Vector3(-0.0343, 0.05, -0.06)], ["eyeball_r", Vector3(0.0343, 0.05, -0.06)], ["eye_target", Vector3(0.0, 0.0, -2.54)]]:
		var index := rig.get_bone_count()
		rig.add_bone(bone[0])
		rig.set_bone_parent(index, 0)
		rig.set_bone_rest(index, Transform3D(Basis.IDENTITY, bone[1]))
	rig.reset_bone_poses()
	model.add_child(rig)
	model.character_rig = rig
	root.add_child(model)
	var holder := Node3D.new()
	root.add_child(holder)
	var mesh := MeshInstance3D.new()
	var surfaces := ArrayMesh.new()
	surfaces.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BoxMesh.new().get_mesh_arrays())
	surfaces.surface_set_material(0, source)
	mesh.mesh = surfaces
	holder.add_child(mesh)
	model.adopt(mesh, rig)

	var own := mesh.get_surface_override_material(0) as ShaderMaterial
	var scale: Variant = own.get_shader_parameter("eye_scale") if own != null else null
	var left_eye: Variant = own.get_shader_parameter("eye_left_position") if own != null else null
	var expected_left := rig.global_transform * rig.get_bone_global_pose(rig.find_bone("eyeball_l")).origin
	_check(
		own != null and own != shared and own.shader == shared.shader and _flag(own, "eyes")
			and _zero(shared.get_shader_parameter("eye_scale")),
		"a model adopting a mesh with eyes draws them with its own copy of the material, the shared one left alone"
	)
	_check(
		scale is float and is_equal_approx(scale, 1.0) and left_eye is Vector3 and (left_eye as Vector3).is_equal_approx(expected_left),
		"the copy is told where the left eyeball is in the world and that a unit there is a Source unit (%s, %s)" % [left_eye, scale]
	)
	var looking: Vector3 = own.get_shader_parameter("eye_left_view")
	var across: Vector3 = own.get_shader_parameter("eye_left_across")
	_check(
		looking.dot(Vector3.FORWARD) > 0.99 and looking.dot(Vector3.LEFT) > 0.0 and across.dot(Vector3.LEFT) > 0.99,
		"the left eye looks ahead at the target, walled out a touch toward the left, its texture's right the model's left (%s, %s)"
			% [looking, across]
	)
	# The head turned a quarter to the model's left: the eyes turn with it.
	rig.set_bone_pose_rotation(0, Quaternion(Vector3.UP, PI / 2.0))
	(model.get("_eyes") as CharacterEyes).update()
	var turned: Vector3 = own.get_shader_parameter("eye_left_view")
	_check(turned.dot(Vector3.LEFT) > 0.99, "turning the head turns where the eyes look (%s)" % turned)
	model.use_probe_lighting()
	_check(mesh.get_surface_override_material(0) == own, "and the copy stays through the model's going on the probes")
	model.free()
	holder.free()
