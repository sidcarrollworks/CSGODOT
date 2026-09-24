class_name FarMaterials
extends RefCounted

## Draws meshes behind everything else, whatever their distance.
##
## Source 2 draws the 3D skybox in a pass of its own before the world, with
## the depth buffer cleared in between, so the world always wins where the
## two overlap. Here the skybox is ordinary geometry scaled up into the
## world, and its terrain, which sits at the skybox's own ground level,
## shows through wherever the map's floor lies below that: at eye height
## under the awning at CT spawn, whose floor is at -70.
##
## So every material on those meshes is replaced by one that squeezes its
## depth against the far plane (far.gdshaderinc): the map wins the depth
## test everywhere, and the skybox still sorts among its own parts. A
## standard material moves onto far.gdshader with what the import made of
## it; a shader material (a blend material, say) gets a variant of its own
## shader with the squeeze added.

const SHADER := preload("res://src/map/far.gdshader")
const INCLUDE := "#include \"res://src/map/far.gdshaderinc\""
## Where a blended material's edge is cut, drawn behind everything.
const BLENDED_CUT := 0.5

static var _variants := {}  # Shader -> its far variant, and a two-sided one under a string key


## Puts every surface of these meshes behind everything. Returns how many.
static func apply(meshes: Array[MeshInstance3D]) -> int:
	var far := far_plane_depth()
	var built := {}
	var surfaces := 0
	for mesh_instance in meshes:
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface)
			if material == null:
				continue
			if not built.has(material):
				built[material] = build(material, far)
			if built[material] == null:
				continue
			mesh_instance.set_surface_override_material(surface, built[material])
			surfaces += 1
	return surfaces


## Which end of the depth buffer is far: Forward+ and Mobile reverse it.
static func far_plane_depth() -> float:
	return 1.0 if RenderingServer.get_current_rendering_method() == "gl_compatibility" else 0.0


## A material like this one, drawn behind everything; null for a shader
## material whose shader has no fragment function to add the squeeze to.
static func build(material: Material, far: float) -> Material:
	if material is ShaderMaterial:
		var variant := variant_of((material as ShaderMaterial).shader)
		if variant == null:
			return null
		var copy := material.duplicate() as ShaderMaterial
		copy.shader = variant
		copy.set_shader_parameter("far_plane_depth", far)
		return copy
	if not material is BaseMaterial3D:
		return null
	var base := material as BaseMaterial3D
	var lit := ShaderMaterial.new()
	lit.shader = _two_sided(SHADER) if base.cull_mode == BaseMaterial3D.CULL_DISABLED else SHADER
	lit.resource_name = base.resource_name
	lit.render_priority = base.render_priority
	lit.set_shader_parameter("albedo_texture", base.albedo_texture)
	lit.set_shader_parameter("albedo_color", base.albedo_color)
	lit.set_shader_parameter("normal_texture", base.normal_texture)
	lit.set_shader_parameter("has_normal_map", base.normal_enabled and base.normal_texture != null)
	lit.set_shader_parameter("normal_depth", base.normal_scale)
	lit.set_shader_parameter("orm_texture", base.roughness_texture)
	lit.set_shader_parameter("roughness_factor", base.roughness)
	lit.set_shader_parameter(
		"alpha_scissor",
		base.alpha_scissor_threshold if base.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		# A blended edge is cut instead: the squeeze is written in the
		# opaque pass, and at the skybox's distance a cut edge looks the
		# same. Drawn opaque, the palms' tree cards were solid triangles.
		else BLENDED_CUT if base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		else -1.0
	)
	lit.set_shader_parameter("far_plane_depth", far)
	lit.set_meta("extras", base.get_meta("extras", {}))
	return lit


## A shader's code with the squeeze added: the include after the type line,
## and the depth written at the top of fragment(), unconditionally, as a
## written DEPTH has to be. Made once per shader.
static func variant_of(base: Shader) -> Shader:
	if base == null or not base.code.contains("void fragment() {"):
		return null
	if _variants.has(base):
		return _variants[base]
	var shader := Shader.new()
	var code := base.code
	if not code.contains(INCLUDE):
		code = code.replace("shader_type spatial;", "shader_type spatial;\n" + INCLUDE)
	code = code.replace("void fragment() {", "void fragment() {\n\tDEPTH = far_depth(FRAGCOORD.z);")
	shader.code = code
	_variants[base] = shader
	return shader


static func _two_sided(base: Shader) -> Shader:
	var key := "two-sided:" + base.resource_path
	if not _variants.has(key):
		var shader := Shader.new()
		shader.code = base.code.replace("cull_back", "cull_disabled")
		_variants[key] = shader
	return _variants[key]
