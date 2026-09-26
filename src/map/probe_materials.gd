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
## stands (light_placed); a body that moves is lit again by whoever moves it
## (light_instance).
##
## A material CS2 draws with its character shader (the players' models and
## your own arms) goes on character.gdshader instead, which lights the same
## way and adds what that shader does (CharacterMaterials).

const SHADER := preload("res://src/map/probe_lit.gdshader")
const PARAMETERS := [&"probe_px", &"probe_nx", &"probe_py", &"probe_ny", &"probe_pz", &"probe_nz"]
## The placement's four, in LightProbes.shadow_placement's order.
const SHADOW_PARAMETERS := [&"probe_shadow_scale", &"probe_shadow_offset", &"probe_shadow_min", &"probe_shadow_max"]

## How far a model lit by light_model moves before the probes are read for
## it again, in units: they are tens of units apart (RigModel.RELIGHT_DISTANCE).
const RELIGHT_DISTANCE := 1.0

## A mesh at most this far across is lit by the cube at its middle. One the
## export merged from a prop placed all over the map is not: dust2's windows
## are 760 units across, with the middle of their bounds inside a building,
## where the probes are black, and every window in them came out black. Those
## are lit by the cubes a little out from a spread of their own vertices,
## averaged, leaving out any point no probe volume holds (light_points), and
## read the sun's baked shadow in the volume round those points (shadow_for).
const ONE_POINT_ACROSS := 256.0
const SAMPLED_VERTICES := 16
const OUT_FROM_SURFACE := 4.0

static var _built := {}    # source Material -> ShaderMaterial
static var _variants := {}  # variant key -> Shader
static var _flat_orms := {}  # metallic, in 255ths -> a one-texel ORM texture


## Puts every surface of these meshes that still has a standard material
## on the probe shader, and lights each mesh from the probes where it stands
## (light_placed); a prop's decal and self-illumination come from textures_dir
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
			light_placed(mesh_instance, probes)
	return surfaces


## Puts what is left of these meshes on Godot's own lighting onto the probe
## shader, each lit where it stands (light_placed): for a map whose shadows
## are baked, where Godot's lighting would take the sun through the map
## (MapShadows). A mesh the probes do not reach is left as it is, and so
## are unshaded and additive surfaces (a glow, a light shaft), which the
## probe shader would draw as a lit, opaque colour. Returns how many
## surfaces moved.
static func apply_rest(meshes: Array[MeshInstance3D], probes: LightProbes, textures_dir: String = "") -> int:
	var surfaces := 0
	for mesh_instance in meshes:
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		var points := light_points(mesh_instance, probes)
		if probes.volume_holding(points) < 0:
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
			light_instance(mesh_instance, cube_for(mesh_instance, probes, points), shadow_for(mesh_instance, probes, points))
	return surfaces


## Lights a mesh placed in the map from the probes where it stands: the
## cube it is lit by (cube_for) and where its shader reads the sun's baked
## shadow (shadow_for), both from its light points.
static func light_placed(mesh_instance: MeshInstance3D, probes: LightProbes) -> void:
	var points := light_points(mesh_instance, probes)
	light_instance(mesh_instance, cube_for(mesh_instance, probes, points), shadow_for(mesh_instance, probes, points))


## Where a placed mesh is lit from: its middle, or, for a mesh too big for
## one point to stand for it (ONE_POINT_ACROSS), a spread of its vertices a
## few units out along their normals, leaving out any no probe volume
## holds; the middle again when none is left.
static func light_points(mesh_instance: MeshInstance3D, probes: LightProbes) -> PackedVector3Array:
	var box := mesh_instance.global_transform * mesh_instance.get_aabb()
	var middle := PackedVector3Array([box.get_center()])
	if box.size.length() <= ONE_POINT_ACROSS:
		return middle
	var mesh := mesh_instance.mesh
	var points := PackedVector3Array()
	@warning_ignore("integer_division")
	var per_surface := maxi(1, SAMPLED_VERTICES / maxi(1, mesh.get_surface_count()))
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		@warning_ignore("integer_division")
		var step := maxi(1, vertices.size() / per_surface)
		for i in range(0, vertices.size(), step):
			var point := mesh_instance.global_transform * vertices[i]
			if i < normals.size():
				point += (mesh_instance.global_basis * normals[i]).normalized() * OUT_FROM_SURFACE
			if probes.volume_at(point) >= 0:
				points.append(point)
	return points if not points.is_empty() else middle


## The cube a placed mesh is lit by: the one at its light point, or the
## average of those at its light points (light_points, worked out here
## when not handed in).
static func cube_for(mesh_instance: MeshInstance3D, probes: LightProbes, points := PackedVector3Array()) -> PackedColorArray:
	if points.is_empty():
		points = light_points(mesh_instance, probes)
	if points.size() == 1:
		return probes.cube_at(points[0])
	var total := PackedColorArray()
	total.resize(PARAMETERS.size())
	for point in points:
		var cube := probes.cube_at(point)
		for face in cube.size():
			total[face] += cube[face]
	for face in total.size():
		total[face] /= float(points.size())
	return total


## Where a placed mesh's shader reads the sun's baked shadow: in the probe
## volume holding the most of its light points (LightProbes.volume_holding),
## so a mesh merged from copies across the map reads the volume round all
## of them where there is one, rather than whichever holds its middle.
## Empty where no volume holds it, which leaves the sun uncut.
static func shadow_for(mesh_instance: MeshInstance3D, probes: LightProbes, points := PackedVector3Array()) -> Array:
	if points.is_empty():
		points = light_points(mesh_instance, probes)
	return probes.volume_placement(probes.volume_holding(points))


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
## one: textures, colour, cut, blend and sidedness. Made once per source. A
## character's material is on character.gdshader, its textures from the
## characters' own directory unless textures_dir says otherwise.
static func build(material: BaseMaterial3D, textures_dir: String = "") -> ShaderMaterial:
	if _built.has(material):
		return _built[material]
	var description := BlendMaterials.vmat(material)
	var character := CharacterMaterials.is_character(description)
	if character and textures_dir.is_empty():
		textures_dir = CharacterMaterials.TEXTURES_DIR
	var blended := material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA \
		or material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	var lit := ShaderMaterial.new()
	lit.shader = shader_for(
		blended, material.cull_mode == BaseMaterial3D.CULL_DISABLED, CharacterMaterials.SHADER if character else SHADER
	)
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
	lit.set_shader_parameter("probe_energy", LightmapMaterials.energy())
	LightmapMaterials.carry_features(lit, description, textures_dir)
	if character:
		CharacterMaterials.carry(lit, description, textures_dir)
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
## foliage and the like; variants made once from their source, this one's
## or the characters' (base).
static func shader_for(blended: bool, two_sided: bool, base: Shader = SHADER) -> Shader:
	if not blended and not two_sided:
		return base
	var key := "%s/%s/%s" % [base.resource_path, blended, two_sided]
	if _variants.has(key):
		return _variants[key]
	# Whatever line endings the checkout gave the file.
	var code := base.code.replace("\r\n", "\n")
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
