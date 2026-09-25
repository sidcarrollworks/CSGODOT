class_name ProbeMaterials
extends RefCounted

## Lights meshes from the map's light probes (LightProbes), the way CS2
## lights its players, weapons and the props it did not lightmap.
##
## Every surface moves onto probe_lit.gdshader with what the import made of
## its material, and each mesh instance is handed the ambient cube read at
## its place as instance uniforms: one shader, one material per source
## material, a cube per instance. Where the map's sun shadow is baked, the
## instance is also told where to read it (LightProbes.shadow_placement),
## which its shader does at every fragment. A prop is lit once, where it
## stands; a body that moves is lit again by whoever moves it
## (light_instance).

const SHADER := preload("res://src/map/probe_lit.gdshader")
const PARAMETERS := [&"probe_px", &"probe_nx", &"probe_py", &"probe_ny", &"probe_pz", &"probe_nz"]
## The placement's four, in LightProbes.shadow_placement's order.
const SHADOW_PARAMETERS := [&"probe_shadow_scale", &"probe_shadow_offset", &"probe_shadow_min", &"probe_shadow_max"]

## How far a model lit by light_model moves before the probes are read for
## it again, in units: they are tens of units apart (RigModel.RELIGHT_DISTANCE).
const RELIGHT_DISTANCE := 1.0

static var _built := {}    # source Material -> ShaderMaterial
static var _variants := {}  # variant key -> Shader
static var _flat_orms := {}  # metallic, in 255ths -> a one-texel ORM texture


## Puts every surface of these meshes that still has a standard material
## on the probe shader, and lights each mesh from the probes at its centre;
## a prop's decal and self-illumination come from textures_dir
## (LightmapMaterials.carry_features). Returns how many surfaces moved.
## Surfaces already on a shader material (the lightmapped and blended ones)
## are left alone.
static func apply(meshes: Array[MeshInstance3D], probes: LightProbes, only_shaders: Array = [], textures_dir: String = "") -> int:
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
			mesh_instance.set_surface_override_material(surface, build(material as BaseMaterial3D, textures_dir))
			surfaces += 1
			moved = true
		if moved and probes != null:
			var centre := (mesh_instance.global_transform * mesh_instance.get_aabb()).get_center()
			light_instance(mesh_instance, probes.cube_at(centre), probes.shadow_placement(centre))
	return surfaces


## Puts what is left of these meshes on Godot's own lighting onto the probe
## shader, lit from the probes at each mesh's centre: for a map whose
## shadows are baked, where Godot's lighting would take the sun through the
## map (MapShadows). A mesh the probes do not reach is left as it is, and
## so are unshaded and additive surfaces (a glow, a light shaft), which the
## probe shader would draw as a lit, opaque colour. Returns how many
## surfaces moved.
static func apply_rest(meshes: Array[MeshInstance3D], probes: LightProbes, textures_dir: String = "") -> int:
	var surfaces := 0
	for mesh_instance in meshes:
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		var centre := (mesh_instance.global_transform * mesh_instance.get_aabb()).get_center()
		if probes.volume_at(centre) < 0:
			continue
		var moved := false
		for surface in mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface) as BaseMaterial3D
			if material == null or not _lit(material) or material.blend_mode != BaseMaterial3D.BLEND_MODE_MIX:
				continue
			mesh_instance.set_surface_override_material(surface, build(material, textures_dir))
			surfaces += 1
			moved = true
		if moved:
			light_instance(mesh_instance, probes.cube_at(centre), probes.shadow_placement(centre))
	return surfaces


## Hands an instance the cube it stands in, and where to read the sun's
## baked shadow round it (LightProbes.shadow_placement; empty for none,
## which leaves the sun uncut).
static func light_instance(instance: GeometryInstance3D, cube: PackedColorArray, shadow: Array = []) -> void:
	for face in PARAMETERS.size():
		var light := cube[face] if face < cube.size() else Color.BLACK
		instance.set_instance_shader_parameter(PARAMETERS[face], Vector3(light.r, light.g, light.b))
	if shadow.size() == SHADOW_PARAMETERS.size():
		for i in SHADOW_PARAMETERS.size():
			instance.set_instance_shader_parameter(SHADOW_PARAMETERS[i], shadow[i])
	else:
		instance.set_instance_shader_parameter(SHADOW_PARAMETERS[0], Vector4.ZERO)


## Lights a model that moves from the scene's light probes at a point, as
## RigModel.light_from lights the players: the first time, its lit standard
## materials go on the probe shader (adopt), and it is lit again each time
## it has moved RELIGHT_DISTANCE. For the dropped guns, the grenades and
## their smoke, and the bomb: on a map whose shadows are baked the live
## shadow map no longer holds the map, so anything left on Godot's own
## lighting would take the sun indoors. Nothing on a map without probes.
static func light_model(root: Node3D, at: Vector3) -> void:
	if not root.is_inside_tree():
		return
	var probes := LightProbeField.find(root.get_tree())
	if probes == null:
		return
	var lit_before := root.has_meta(&"probe_lit_by")
	if lit_before and root.get_meta(&"probe_lit_by") == probes \
			and at.distance_squared_to(root.get_meta(&"probe_lit_at")) < RELIGHT_DISTANCE * RELIGHT_DISTANCE:
		return
	if not lit_before:
		adopt(root)
	root.set_meta(&"probe_lit_by", probes)
	root.set_meta(&"probe_lit_at", at)
	var cube := probes.cube_at(at)
	var shadow := probes.shadow_placement(at)
	for instance in _geometry(root):
		light_instance(instance, cube, shadow)


## Puts the lit standard materials of root and everything drawn under it on
## the probe shader: each surface's, or the override where one is set,
## which Godot draws in place of them; a multimesh's, as its override.
## Unshaded ones (a glow, a flame) are left as they are.
static func adopt(root: Node) -> void:
	for instance in _geometry(root):
		if instance.material_override is BaseMaterial3D:
			if _lit(instance.material_override):
				instance.material_override = build(instance.material_override as BaseMaterial3D)
			continue
		if instance is MeshInstance3D:
			var mesh_instance := instance as MeshInstance3D
			if mesh_instance.mesh == null:
				continue
			for surface in mesh_instance.mesh.get_surface_count():
				var material := mesh_instance.get_active_material(surface)
				if material is BaseMaterial3D and _lit(material):
					mesh_instance.set_surface_override_material(surface, build(material as BaseMaterial3D))
		elif instance is MultiMeshInstance3D:
			var multimesh := (instance as MultiMeshInstance3D).multimesh
			var mesh := multimesh.mesh if multimesh != null else null
			if mesh != null and mesh.get_surface_count() > 0:
				var material := mesh.surface_get_material(0)
				if material is BaseMaterial3D and _lit(material):
					instance.material_override = build(material as BaseMaterial3D)


static func _lit(material: Material) -> bool:
	return (material as BaseMaterial3D).shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED


## root, if it is drawn, and everything drawn under it.
static func _geometry(root: Node) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	if root is GeometryInstance3D:
		out.append(root as GeometryInstance3D)
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		out.append(node as GeometryInstance3D)
	return out


## A probe-lit material carrying over what the import made of a standard
## one: textures, colour, cut, blend and sidedness. Made once per source.
static func build(material: BaseMaterial3D, textures_dir: String = "") -> ShaderMaterial:
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
	# The shader reads occlusion, roughness and metalness from one texture;
	# a material made by hand has none, and the shader's white default
	# would make it all metal.
	lit.set_shader_parameter(
		"orm_texture", material.roughness_texture if material.roughness_texture != null else flat_orm(material.metallic)
	)
	lit.set_shader_parameter("roughness_factor", material.roughness)
	if not blended:
		lit.set_shader_parameter(
			"alpha_scissor",
			material.alpha_scissor_threshold
			if material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR else -1.0
		)
	lit.set_shader_parameter("probe_energy", LightmapMaterials.ENERGY)
	LightmapMaterials.carry_features(lit, BlendMaterials.vmat(material), textures_dir)
	lit.set_meta("extras", material.get_meta("extras", {}))
	_built[material] = lit
	return lit


## One texel of occlusion, roughness and metalness for a material without
## the texture: none of the first, the material's roughness factor for the
## second (1 here), its metalness for the third.
static func flat_orm(metallic: float) -> ImageTexture:
	var key := roundi(clampf(metallic, 0.0, 1.0) * 255.0)
	if not _flat_orms.has(key):
		var image := Image.create(1, 1, false, Image.FORMAT_RGB8)
		image.set_pixel(0, 0, Color(1.0, 1.0, key / 255.0))
		_flat_orms[key] = ImageTexture.create_from_image(image)
	return _flat_orms[key]


## The shader for a material: blended for an alpha edge, two-sided for
## foliage and the like; variants made once from the one source.
static func shader_for(blended: bool, two_sided: bool) -> Shader:
	if not blended and not two_sided:
		return SHADER
	var key := "%s/%s" % [blended, two_sided]
	if _variants.has(key):
		return _variants[key]
	# Whatever line endings the checkout gave the file.
	var code := SHADER.code.replace("\r\n", "\n")
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
