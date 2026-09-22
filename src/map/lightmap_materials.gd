class_name LightmapMaterials
extends RefCounted

## Gives a map's surfaces the bounce light CS2 baked for them.
##
## The map ships its indirect lighting as lightmaps, and a lightmapped
## surface carries the coordinates into them in the glTF's second UV set.
## What it does not ship is a way for Godot's standard material to read
## them, so every lightmapped surface gets a shader that does: the two-layer
## ones already have one (BlendMaterials) and are handed the textures; the
## rest are moved onto lightmapped.gdshader with what the import made of them.
##
## The world's own geometry is always lightmapped. A prop is lightmapped
## when it was placed so: its second UV set is then laid out as charts at
## the map's texel density, or, for a prop the map lights by light probes,
## collapsed onto one texel of its own that holds that light. Other props
## carry their model's own second UV set, or none, and keep Godot's ambient,
## which MapLighting sets to the lightmap's average when it has been
## measured (measure_average, run by scripts/prepare_export.gd).

const OPAQUE_SHADER := preload("res://src/map/lightmapped.gdshader")
const OVERLAY_SHADER := preload("res://src/map/lightmapped_overlay.gdshader")

## Where the extraction puts them, relative to the directory the world glTF
## is in, and where the prepare step writes the average.
const IRRADIANCE_FILE := "lightmaps/irradiance.exr"
const DIRECTION_FILE := "lightmaps/directional_irradiance.png"
const AVERAGE_FILE := "lightmaps/average.json"

## The lightmap is in the game's units; this is the scale into Godot's,
## alongside the sun as MapLighting sets it (see lightmap.gdshaderinc).
const ENERGY := 0.4

const WORLD_SHADERS := ["csgo_lightmappedgeneric.vfx", "csgo_static_overlay.vfx"]
const PROP_SHADERS := ["csgo_vertexlitgeneric.vfx", "csgo_foliage.vfx", "csgo_complex.vfx", "csgo_environment.vfx"]

## A prop's charts sit at the world's texel density, give or take a
## mapper's resolution bias; a model's own second UV set is ten times
## denser and more. Measured against the world's own surfaces, or against
## dust2's density when there are none to measure.
const DENSITY_BELOW := 8.0
const DENSITY_ABOVE := 4.0
const DEFAULT_DENSITY := 0.75
const SAMPLE_TRIANGLES := 64

static var _two_sided := {}


## Applies the lightmaps under map_dir to every lightmapped surface of these
## meshes, whose vertices are still in the export's units, unit_scale map
## units each. Returns {"surfaces": how many, "props": how many of those
## are props, "found": whether the maps were there, "ambient": the
## lightmap's average light as a Color, or null if unmeasured}; without the
## maps nothing changes.
static func apply(meshes: Array[MeshInstance3D], map_dir: String, unit_scale: float = 1.0) -> Dictionary:
	var irradiance := _load(map_dir.path_join(IRRADIANCE_FILE))
	var direction := _load(map_dir.path_join(DIRECTION_FILE))
	if irradiance == null or direction == null:
		return {"surfaces": 0, "props": 0, "found": false, "ambient": null}
	var lightmap_size := Vector2(irradiance.get_size())

	# Every candidate, and the world's own density to judge the props by.
	var candidates: Array[Array] = []  # [mesh_instance, surface, material, is_prop, density]
	var world_densities := PackedFloat32Array()
	for mesh_instance in meshes:
		var mesh := mesh_instance.mesh as ArrayMesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface)
			if material == null or not (mesh.surface_get_format(surface) & Mesh.ARRAY_FORMAT_TEX_UV2):
				continue
			var shader := String(BlendMaterials.vmat(material).get("ShaderName", ""))
			var is_prop := shader in PROP_SHADERS
			if not (is_prop or shader in WORLD_SHADERS):
				continue
			var density := chart_density(mesh, surface, unit_scale, lightmap_size)
			if not is_prop and density > 0.0:
				world_densities.append(density)
			candidates.append([mesh_instance, surface, material, is_prop, density])
	var reference := DEFAULT_DENSITY
	if not world_densities.is_empty():
		world_densities.sort()
		reference = world_densities[world_densities.size() / 2]

	var built := {}
	var surfaces := 0
	var props := 0
	for candidate in candidates:
		var mesh_instance: MeshInstance3D = candidate[0]
		var surface: int = candidate[1]
		var material: Material = candidate[2]
		var density: float = candidate[4]
		if candidate[3]:
			if density > 0.0 and (density < reference / DENSITY_BELOW or density > reference * DENSITY_ABOVE):
				continue
			props += 1
		surfaces += 1
		if material is ShaderMaterial:
			# A blend material, which reads the same lightmap uniforms.
			(material as ShaderMaterial).set_shader_parameter("lightmap_irradiance", irradiance)
			(material as ShaderMaterial).set_shader_parameter("lightmap_direction", direction)
			(material as ShaderMaterial).set_shader_parameter("lightmap_energy", ENERGY)
			continue
		if not built.has(material):
			built[material] = build(material as BaseMaterial3D, irradiance, direction)
		mesh_instance.set_surface_override_material(surface, built[material])
	return {"surfaces": surfaces, "props": props, "found": true, "ambient": read_average(map_dir)}


static func is_lightmapped(description: Dictionary) -> bool:
	var shader := String(description.get("ShaderName", ""))
	return shader in WORLD_SHADERS or shader in PROP_SHADERS


## How densely a surface's second UV set covers the lightmap, in texels per
## unit of its edges, over a sample of its triangles: the median, leaving
## out triangles collapsed onto one texel. Zero when every sampled triangle
## is, or when there is nothing to measure.
static func chart_density(mesh: Mesh, surface: int, unit_scale: float, lightmap_size: Vector2) -> float:
	var arrays := mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var triangles := index.size() / 3 if not index.is_empty() else vertices.size() / 3
	if triangles == 0 or uv2.size() != vertices.size():
		return 0.0
	var texels_per_uv := lightmap_size.x * lightmap_size.y
	var densities := PackedFloat32Array()
	for triangle in range(0, triangles, maxi(1, triangles / SAMPLE_TRIANGLES)):
		var i0 := index[triangle * 3] if not index.is_empty() else triangle * 3
		var i1 := index[triangle * 3 + 1] if not index.is_empty() else triangle * 3 + 1
		var i2 := index[triangle * 3 + 2] if not index.is_empty() else triangle * 3 + 2
		var area := (vertices[i1] - vertices[i0]).cross(vertices[i2] - vertices[i0]).length() * 0.5
		area *= unit_scale * unit_scale
		var texels := absf((uv2[i1] - uv2[i0]).cross(uv2[i2] - uv2[i0])) * 0.5 * texels_per_uv
		if area < 1e-6 or texels < 1e-6:
			continue
		densities.append(sqrt(texels / area))
	if densities.is_empty():
		return 0.0
	densities.sort()
	return densities[densities.size() / 2]


## A lightmapped material carrying over what the import made of a standard
## one: its textures, colour, cut and sidedness.
static func build(material: BaseMaterial3D, irradiance: Texture2D, direction: Texture2D) -> ShaderMaterial:
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
	lit.set_shader_parameter("lightmap_irradiance", irradiance)
	lit.set_shader_parameter("lightmap_direction", direction)
	lit.set_shader_parameter("lightmap_energy", ENERGY)
	# Kept for whoever reads the material later.
	lit.set_meta("extras", material.get_meta("extras", {}))
	return lit


## The lightmapped shader for a material: the blended one for an alpha
## edge, and a two-sided variant of either for foliage and the like, made
## once from the same source.
static func shader_for(blended: bool, two_sided: bool) -> Shader:
	var base: Shader = OVERLAY_SHADER if blended else OPAQUE_SHADER
	if not two_sided:
		return base
	if not _two_sided.has(base):
		var shader := Shader.new()
		shader.code = base.code.replace("cull_back", "cull_disabled")
		_two_sided[base] = shader
	return _two_sided[base]


## The lightmap's average light, over the texels that hold any, in the
## game's units. Reading the full map in takes a gigabyte of memory, so it
## is done once, by the prepare step, and written down (write_average).
static func measure_average(image: Image) -> Color:
	var sum := Color(0.0, 0.0, 0.0, 0.0)
	var count := 0
	var step := maxi(1, image.get_width() / 1024)
	for y in range(0, image.get_height(), step):
		for x in range(0, image.get_width(), step):
			var texel := image.get_pixel(x, y)
			if texel.r + texel.g + texel.b <= 0.0:
				continue
			sum += texel
			count += 1
	if count == 0:
		return Color(0.0, 0.0, 0.0, 0.0)
	return Color(sum.r / count, sum.g / count, sum.b / count, 1.0)


static func write_average(map_dir: String, average: Color) -> void:
	var file := FileAccess.open(map_dir.path_join(AVERAGE_FILE), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"irradiance": [average.r, average.g, average.b]}, "  ") + "\n")


## The written average, or null.
static func read_average(map_dir: String) -> Variant:
	var path := map_dir.path_join(AVERAGE_FILE)
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not parsed.get("irradiance") is Array or (parsed["irradiance"] as Array).size() != 3:
		return null
	var values: Array = parsed["irradiance"]
	return Color(float(values[0]), float(values[1]), float(values[2]), 1.0)


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
