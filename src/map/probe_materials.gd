class_name ProbeMaterials
extends RefCounted

## Lights meshes from the map's light probes (LightProbes), the way CS2
## lights its players, weapons and the props it did not lightmap.
##
## Every surface moves onto probe_lit.gdshader with what the import made of
## its material, and each mesh instance is handed the ambient cube read at
## its place as instance uniforms: one shader, one material per source
## material, a cube per instance. A prop is lit once, where it stands; a
## body that moves is lit again by whoever moves it (light_instance).

const SHADER := preload("res://src/map/probe_lit.gdshader")
const PARAMETERS := [&"probe_px", &"probe_nx", &"probe_py", &"probe_ny", &"probe_pz", &"probe_nz"]

static var _built := {}    # source Material -> ShaderMaterial
static var _variants := {}  # variant key -> Shader


## Puts every surface of these meshes that still has a standard material
## on the probe shader, and lights each mesh from the probes at its centre.
## Returns how many surfaces moved. Surfaces already on a shader material
## (the lightmapped and blended ones) are left alone.
static func apply(meshes: Array[MeshInstance3D], probes: LightProbes, only_shaders: Array = []) -> int:
	var surfaces := 0
	for mesh_instance in meshes:
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		var moved := false
		for surface in mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface)
			if not material is BaseMaterial3D:
				continue
			if not only_shaders.is_empty() and String(BlendMaterials.vmat(material).get("ShaderName", "")) not in only_shaders:
				continue
			mesh_instance.set_surface_override_material(surface, build(material as BaseMaterial3D))
			surfaces += 1
			moved = true
		if moved and probes != null:
			var centre := (mesh_instance.global_transform * mesh_instance.get_aabb()).get_center()
			light_instance(mesh_instance, probes.cube_at(centre))
	return surfaces


## Hands an instance the cube it stands in.
static func light_instance(instance: GeometryInstance3D, cube: PackedColorArray) -> void:
	for face in PARAMETERS.size():
		var light := cube[face] if face < cube.size() else Color.BLACK
		instance.set_instance_shader_parameter(PARAMETERS[face], Vector3(light.r, light.g, light.b))


## A probe-lit material carrying over what the import made of a standard
## one: textures, colour, cut, blend and sidedness. Made once per source.
static func build(material: BaseMaterial3D) -> ShaderMaterial:
	if _built.has(material):
		return _built[material]
	var blended := material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA \
		or material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	var lit := ShaderMaterial.new()
	lit.shader = shader_for(blended, material.cull_mode == BaseMaterial3D.CULL_DISABLED)
	lit.resource_name = material.resource_name
	lit.render_priority = material.render_priority
	lit.set_shader_parameter("albedo_texture", material.albedo_texture)
	lit.set_shader_parameter("albedo_color", material.albedo_color)
	lit.set_shader_parameter("normal_texture", material.normal_texture)
	lit.set_shader_parameter("has_normal_map", material.normal_enabled and material.normal_texture != null)
	lit.set_shader_parameter("normal_depth", material.normal_scale)
	lit.set_shader_parameter("orm_texture", material.roughness_texture)
	lit.set_shader_parameter("roughness_factor", material.roughness)
	if not blended:
		lit.set_shader_parameter(
			"alpha_scissor",
			material.alpha_scissor_threshold
			if material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR else -1.0
		)
	lit.set_shader_parameter("probe_energy", LightmapMaterials.ENERGY)
	lit.set_meta("extras", material.get_meta("extras", {}))
	_built[material] = lit
	return lit


## The shader for a material: blended for an alpha edge, two-sided for
## foliage and the like; variants made once from the one source.
static func shader_for(blended: bool, two_sided: bool) -> Shader:
	if not blended and not two_sided:
		return SHADER
	var key := "%s/%s" % [blended, two_sided]
	if _variants.has(key):
		return _variants[key]
	var code := SHADER.code
	if two_sided:
		code = code.replace("cull_back", "cull_disabled")
	if blended:
		code = code.replace(
			"\tif (alpha_scissor >= 0.0) {\n\t\tALPHA = albedo.a;\n\t\tALPHA_SCISSOR_THRESHOLD = alpha_scissor;\n\t}\n",
			"\tALPHA = albedo.a;\n"
		)
	var shader := Shader.new()
	shader.code = code
	_variants[key] = shader
	return shader
