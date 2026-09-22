class_name BlendMaterials
extends RefCounted

## Gives a map's two-layer materials their second layer back.
##
## Most of dust2's walls and ground are csgo_lightmappedgeneric with F_LAYERS
## on: two sets of textures, mixed by a weight painted onto the vertices and
## broken up by a mask texture, so plaster gives way to brick along a ragged
## edge rather than a straight one. A glTF material has one set of textures,
## so the export carries the first layer only, and every such wall comes out
## as its first layer from end to end.
##
## Everything needed to put that right does come through, just not as a
## material. The export keeps each material's full description in its extras
## (which textures, which tints, how soft the edge is); the paint is a vertex
## attribute, which ExportPaintChannel renames to one Godot keeps; and
## scripts/extract_assets.sh fetches the textures the glTF had no slot for.
## This reads the three and swaps in blend_material.gdshader.

const SHADER := preload("res://src/map/blend_material.gdshader")

## vmat float parameters and the shader uniforms they become.
const FLOATS := {
	"g_flBlendSoftness": "blend_softness",
	"g_flLayerBorderStrength": "border_strength",
	"g_flLayerBorderSoftness": "border_softness",
	"g_flLayerBorderOffset": "border_offset",
}

## vmat colour parameters and their uniforms. The fourth component is unused.
const COLOURS := {
	"g_vLayer1Tint": "layer1_tint",
	"g_vLayer2Tint": "layer2_tint",
	"g_vLayerBorderTint": "border_tint",
}

## vmat texture coordinate parameters, present on the few materials with
## F_TEXTURETRANSFORMS. On dust2 only the scales are ever anything but
## identity, so rotation and offset are not carried.
const UV_TRANSFORMS := {
	"g_vLayer2TexCoordScale": "layer2_uv_scale",
	"g_vLayer2TexCoordCenter": "layer2_uv_centre",
	"g_vBlendModulateTexCoordScale": "mask_uv_scale",
	"g_vBlendModulateTexCoordCenter": "mask_uv_centre",
}


## Swaps the blend shader onto every two-layer surface among these meshes.
## textures_dir is where extract_assets.sh put the map's materials/ directory.
## Returns {"blended": surfaces switched over, "materials": distinct materials,
## "missing": names of materials whose second layer was not on disk}.
static func apply(meshes: Array[MeshInstance3D], textures_dir: String) -> Dictionary:
	var built := {}  # material name -> ShaderMaterial, or null if it could not be
	var blended := 0
	for mesh_instance in meshes:
		var mesh := mesh_instance.mesh
		for surface in mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface) as BaseMaterial3D
			if material == null or not is_layered(vmat(material)):
				continue
			var key := String(vmat(material).get("Name", material.resource_name))
			if not built.has(key):
				built[key] = build(material, textures_dir)
			if built[key] != null:
				mesh_instance.set_surface_override_material(surface, built[key])
				blended += 1
			else:
				# Left as it is, but not tinted by its paint. Godot's importer
				# turns this on for some materials once a mesh has vertex colour,
				# and the paint is a weight, not a colour.
				material.vertex_color_use_as_albedo = false

	var missing := PackedStringArray()
	for key: String in built:
		if built[key] == null:
			missing.append(key.get_file().get_basename())
	return {
		"blended": blended,
		"materials": built.size() - missing.size(),
		"missing": missing,
	}


## The vmat description Source 2 Viewer attaches to a material, or empty.
static func vmat(material: Material) -> Dictionary:
	if material == null:
		return {}
	var extras: Variant = material.get_meta("extras", {})
	if not extras is Dictionary:
		return {}
	var description: Variant = (extras as Dictionary).get("vmat", {})
	if not description is Dictionary:
		return {}
	return description


static func is_layered(description: Dictionary) -> bool:
	var flags: Variant = description.get("IntParams", {})
	return flags is Dictionary and int((flags as Dictionary).get("F_LAYERS", 0)) >= 1


## The blend material standing in for one imported material, or null if its
## second layer's textures are not there to be had.
static func build(material: BaseMaterial3D, textures_dir: String) -> ShaderMaterial:
	var description := vmat(material)
	var textures: Dictionary = description.get("TextureParams", {})
	var layer2_albedo := load_texture(textures_dir, textures.get("g_tLayer2Color", ""))
	var layer2_normal := load_texture(textures_dir, textures.get("g_tLayer2NormalRoughness", ""))
	var mask := load_texture(textures_dir, textures.get("g_tBlendModulation", ""))
	if layer2_albedo == null or layer2_normal == null or mask == null:
		return null

	var blend := ShaderMaterial.new()
	blend.shader = SHADER
	blend.resource_name = material.resource_name
	# What the importer already made of the first layer.
	blend.set_shader_parameter("layer1_albedo", material.albedo_texture)
	blend.set_shader_parameter("layer1_normal", material.normal_texture)
	blend.set_shader_parameter("layer1_orm", material.roughness_texture)
	blend.set_shader_parameter("layer2_albedo", layer2_albedo)
	blend.set_shader_parameter("layer2_normal_roughness", layer2_normal)
	blend.set_shader_parameter("blend_modulation", mask)

	var flags: Dictionary = description.get("IntParams", {})
	blend.set_shader_parameter("fancy_blending", int(flags.get("F_FANCY_BLENDING", 2)))

	var floats: Dictionary = description.get("FloatParams", {})
	for parameter: String in FLOATS:
		if floats.has(parameter):
			blend.set_shader_parameter(FLOATS[parameter], float(floats[parameter]))
	var vectors: Dictionary = description.get("VectorParams", {})
	for parameter: String in COLOURS:
		var value: Variant = vectors.get(parameter)
		if value is Array and (value as Array).size() >= 3:
			blend.set_shader_parameter(
				COLOURS[parameter], Color(float(value[0]), float(value[1]), float(value[2]))
			)
	for parameter: String in UV_TRANSFORMS:
		var value: Variant = vectors.get(parameter)
		if value is Array and (value as Array).size() >= 2:
			blend.set_shader_parameter(
				UV_TRANSFORMS[parameter], Vector2(float(value[0]), float(value[1]))
			)
	# Kept for whoever reads the material later, the collision classifier included.
	blend.set_meta("extras", material.get_meta("extras", {}))
	return blend


## A texture the vmat names, such as "materials/de_dust/x_color_psd_1234.vtex",
## from under textures_dir, where it was extracted as a PNG by the same path.
static func load_texture(textures_dir: String, vtex_path: Variant) -> Texture2D:
	if textures_dir.is_empty() or not vtex_path is String or (vtex_path as String).is_empty():
		return null
	var path := textures_dir.path_join((vtex_path as String).get_basename() + ".png")
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	# Extracted but not imported yet: slower and uncompressed, but it is there.
	var absolute := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute):
		return null
	var image := Image.load_from_file(absolute)
	if image == null:
		return null
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
