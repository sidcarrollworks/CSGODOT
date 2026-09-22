class_name LightmapMaterials
extends RefCounted

## Gives a map's world surfaces the bounce light CS2 baked for them.
##
## The map ships its indirect lighting as lightmaps, and every world surface
## carries the coordinates into them (the glTF's second UV set). What it
## does not ship is a way for Godot's standard material to read them, so
## every lightmapped surface gets a shader that does: the two-layer ones
## already have one (BlendMaterials) and are handed the textures; the rest
## are moved onto lightmapped.gdshader with what the import made of them.
##
## Props are lit by light probes in CS2 rather than lightmaps, and keep
## Godot's sky ambient until those are read too. Only the world's own
## geometry, csgo_lightmappedgeneric and the static overlays, is touched.

const OPAQUE_SHADER := preload("res://src/map/lightmapped.gdshader")
const OVERLAY_SHADER := preload("res://src/map/lightmapped_overlay.gdshader")

## Where the extraction puts them, relative to the directory the world glTF
## is in.
const IRRADIANCE_FILE := "lightmaps/irradiance.exr"
const DIRECTION_FILE := "lightmaps/directional_irradiance.png"

const SHADERS := ["csgo_lightmappedgeneric.vfx", "csgo_static_overlay.vfx"]


## Applies the lightmaps under map_dir to every lightmapped surface of these
## meshes. Returns {"surfaces": how many, "found": whether the maps were
## there}; without them nothing changes.
static func apply(meshes: Array[MeshInstance3D], map_dir: String) -> Dictionary:
	var irradiance := _load(map_dir.path_join(IRRADIANCE_FILE))
	var direction := _load(map_dir.path_join(DIRECTION_FILE))
	if irradiance == null or direction == null:
		return {"surfaces": 0, "found": false}

	var built := {}
	var surfaces := 0
	for mesh_instance in meshes:
		var mesh := mesh_instance.mesh
		for surface in mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface)
			if material == null or not is_lightmapped(BlendMaterials.vmat(material)):
				continue
			if material is ShaderMaterial:
				# A blend material, which reads the same lightmap uniforms.
				(material as ShaderMaterial).set_shader_parameter("lightmap_irradiance", irradiance)
				(material as ShaderMaterial).set_shader_parameter("lightmap_direction", direction)
				surfaces += 1
				continue
			if not built.has(material):
				built[material] = build(material as BaseMaterial3D, irradiance, direction)
			mesh_instance.set_surface_override_material(surface, built[material])
			surfaces += 1
	return {"surfaces": surfaces, "found": true}


static func is_lightmapped(description: Dictionary) -> bool:
	return String(description.get("ShaderName", "")) in SHADERS


## A lightmapped material carrying over what the import made of a standard
## one: its textures, colour, cut and sidedness.
static func build(material: BaseMaterial3D, irradiance: Texture2D, direction: Texture2D) -> ShaderMaterial:
	var blended := material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA \
		or material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	var lit := ShaderMaterial.new()
	lit.shader = OVERLAY_SHADER if blended else OPAQUE_SHADER
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
	lit.set_shader_parameter("lightmap_irradiance", irradiance)
	lit.set_shader_parameter("lightmap_direction", direction)
	# Kept for whoever reads the material later.
	lit.set_meta("extras", material.get_meta("extras", {}))
	return lit


static func _load(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	# Extracted but not imported yet: uncompressed, and the irradiance is a
	# gigabyte that way, but it is there.
	var absolute := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute):
		return null
	var image := Image.load_from_file(absolute)
	if image == null:
		return null
	return ImageTexture.create_from_image(image)
