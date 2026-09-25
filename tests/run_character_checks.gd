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


func _init() -> void:
	_test_routing()
	_test_carry()
	_test_shader_code()
	_test_models_off_the_probes()
	_test_mask_alpha()
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
			and is_equal_approx(lit.get_shader_parameter("probe_energy"), LightmapMaterials.ENERGY),
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


## A bool shader parameter as set, or false where it was never set.
func _flag(lit: ShaderMaterial, name: String) -> bool:
	var value: Variant = lit.get_shader_parameter(name)
	return value == true


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
