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
## collapsed onto one texel of its own that holds that light. A prop whose
## material says F_FORCE_UV2 carries its model's own second UV set (a decal
## or a tint mask reads it), and its lightmap coordinates, where it has any,
## in a third, which Godot imports as CUSTOM0: dust2's kasbah towers and
## arches. The props with neither are lit by the light probes instead
## (ProbeMaterials). Those lit from CUSTOM0 are drawn without the LODs
## Godot's import made for them (drop_lods).

const OPAQUE_SHADER := preload("res://src/map/lightmapped.gdshader")
const OVERLAY_SHADER := preload("res://src/map/lightmapped_overlay.gdshader")

## Where the extraction puts them, relative to the directory the world glTF
## is in, and where the prepare step writes the average.
const IRRADIANCE_FILE := "lightmaps/irradiance.exr"
const DIRECTION_FILE := "lightmaps/directional_irradiance.png"
const AVERAGE_FILE := "lightmaps/average.json"

## The lightmap is in the game's units; this is the scale into Godot's,
## alongside the sun as MapLighting sets it (see lightmap.gdshaderinc), under
## the ACES grade, where it was fitted by eye. Under CS2's own grade
## (ColourGrade) the game's units are Godot's, CS2_ENERGY: fitted at long
## doors against Sid's CS2 screenshot, it put the sunlit and shaded ground
## and the sunlit plaster within 1% of the game's (reference/
## playtest-2026-09-25.md, issue 10). energy() gives the one in use.
const ENERGY := 0.4
const CS2_ENERGY := 1.0


## The scale the baked light takes under the grade mode (ColourGrade.mode()
## unless given).
static func energy(mode: String = "") -> float:
	var grade := mode if mode in ColourGrade.MODES else ColourGrade.mode()
	return CS2_ENERGY if grade == "cs2" else ENERGY

const WORLD_SHADERS := ["csgo_lightmappedgeneric.vfx", "csgo_static_overlay.vfx"]
const PROP_SHADERS := ["csgo_vertexlitgeneric.vfx", "csgo_foliage.vfx", "csgo_complex.vfx", "csgo_environment.vfx"]

## A prop's charts sit at the world's texel density, give or take a
## mapper's resolution bias; a model's own second UV set is usually ten
## times denser, but not always (a crate's decal coordinates came out at
## twice the world's), so the material's F_FORCE_UV2 is what decides, and
## the density is the check behind it. Measured against the world's own
## surfaces, or against dust2's density when there are none to measure.
const DENSITY_BELOW := 8.0
const DENSITY_ABOVE := 4.0
const DEFAULT_DENSITY := 0.75
const SAMPLE_TRIANGLES := 64

static var _two_sided := {}


## Applies the lightmaps under map_dir to every lightmapped surface of these
## meshes, whose vertices are still in the export's units, unit_scale map
## units each; a prop's decal and self-illumination come from textures_dir
## (carry_features). With the sun's channel of the map's baked shadows
## (MapShadows.sun_channel_at), the page of them goes on too. Returns
## {"surfaces": how many, "props": how many of those are props, "no_lods":
## how many of those lit from CUSTOM0 lost their LODs (drop_lods), "found":
## whether the maps were there, "shadows": whether the sun's baked shadow
## was, "ambient": the lightmap's average light as a Color, or null if
## unmeasured}; without the maps nothing changes.
static func apply(
	meshes: Array[MeshInstance3D], map_dir: String, unit_scale: float = 1.0, textures_dir: String = "", sun_channel: int = -1
) -> Dictionary:
	var irradiance := _load(map_dir.path_join(IRRADIANCE_FILE))
	var direction := _load(map_dir.path_join(DIRECTION_FILE))
	if irradiance == null or direction == null:
		return {"surfaces": 0, "props": 0, "no_lods": 0, "found": false, "shadows": false, "ambient": null}
	var lightmap_size := Vector2(irradiance.get_size())
	var shadows: Texture2D = null
	if sun_channel >= 0:
		for file in MapShadows.FILES:
			shadows = _load(map_dir.path_join(file))
			if shadows != null:
				break
	var sun_mask := MapShadows.channel_mask(sun_channel if shadows != null else -1)

	# Every candidate, and the world's own density to judge the props by.
	var candidates: Array[Array] = []  # [mesh_instance, surface, material, is_prop, density, in_custom0]
	var world_densities := PackedFloat32Array()
	for mesh_instance in meshes:
		var mesh := mesh_instance.mesh as ArrayMesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface)
			if material == null or not (mesh.surface_get_format(surface) & Mesh.ARRAY_FORMAT_TEX_UV2):
				continue
			var description := BlendMaterials.vmat(material)
			var shader := String(description.get("ShaderName", ""))
			var is_prop := shader in PROP_SHADERS
			if not (is_prop or shader in WORLD_SHADERS):
				continue
			var in_custom0 := is_prop and uses_own_uv2(description)
			if in_custom0 and not has_third_uv(mesh, surface):
				continue
			var density := chart_density(mesh, surface, unit_scale, lightmap_size, in_custom0)
			if not is_prop and density > 0.0:
				world_densities.append(density)
			candidates.append([mesh_instance, surface, material, is_prop, density, in_custom0])
	var world_median := DEFAULT_DENSITY
	if not world_densities.is_empty():
		world_densities.sort()
		@warning_ignore("integer_division")
		world_median = world_densities[world_densities.size() / 2]

	var built := {}
	var surfaces := 0
	var props := 0
	var lit_from_custom0 := {}  # ArrayMesh -> PackedInt32Array of its surfaces
	for candidate in candidates:
		var mesh_instance: MeshInstance3D = candidate[0]
		var surface: int = candidate[1]
		var material: Material = candidate[2]
		var density: float = candidate[4]
		var in_custom0: bool = candidate[5]
		if candidate[3]:
			if density > 0.0 and (density < world_median / DENSITY_BELOW or density > world_median * DENSITY_ABOVE):
				continue
			props += 1
		surfaces += 1
		if in_custom0:
			var mesh := mesh_instance.mesh as ArrayMesh
			var listed: PackedInt32Array = lit_from_custom0.get(mesh, PackedInt32Array())
			if not surface in listed:
				listed.append(surface)
			lit_from_custom0[mesh] = listed
		if material is ShaderMaterial:
			# A blend material, which reads the same lightmap uniforms.
			(material as ShaderMaterial).set_shader_parameter("lightmap_irradiance", irradiance)
			(material as ShaderMaterial).set_shader_parameter("lightmap_direction", direction)
			(material as ShaderMaterial).set_shader_parameter("lightmap_energy", energy())
			set_shadows(material as ShaderMaterial, shadows, sun_mask)
			continue
		var key := [material, in_custom0]
		if not built.has(key):
			built[key] = build(material as BaseMaterial3D, irradiance, direction, in_custom0, textures_dir)
			set_shadows(built[key], shadows, sun_mask)
		mesh_instance.set_surface_override_material(surface, built[key])
	var no_lods := 0
	for mesh: ArrayMesh in lit_from_custom0:
		no_lods += drop_lods(mesh, lit_from_custom0[mesh])
	return {
		"surfaces": surfaces, "props": props, "no_lods": no_lods, "found": true, "shadows": shadows != null,
		"ambient": read_average(map_dir),
	}


## Takes the LODs off these surfaces of a mesh, which are then drawn at full
## detail at every distance; its other surfaces keep theirs. Returns how
## many had any.
##
## Godot's glTF import gives every surface LODs (meshes/generate_lods), and
## its simplifier welds vertices that share a position, UV, UV2, normal,
## tangent sign and colour without comparing CUSTOM0 to 3; every LOD's
## indices then point at the first vertex of each welded group
## (ImporterMesh::generate_lods, scene/resources/3d/importer_mesh.cpp). A
## surface lit from CUSTOM0 has seams there, between lightmap charts, that
## nothing else marks, so in a lower LOD a triangle on one takes a corner
## from the neighbouring chart and samples the lightmap across the gap:
## the zigzag stripes on dust2's kasbah towers (playtest of 2026-09-25,
## issue 12). A surface lit from UV2 keeps its seams, since UV2 is compared.
##
## The surfaces go back through the pair ArrayMesh serialises itself with
## (_get_surfaces, _set_surfaces), less their "lods" entry: nothing is
## decompressed or compressed again, and they keep their order, names,
## materials and bounds, so a MeshInstance3D's overrides still line up.
## At load only, never in the tick; the mesh is uploaded once more.
static func drop_lods(mesh: ArrayMesh, surfaces: PackedInt32Array) -> int:
	var data: Array = mesh._get_surfaces()
	var dropped := 0
	for surface in surfaces:
		if surface < 0 or surface >= data.size():
			continue
		var entry: Dictionary = data[surface]
		if (entry.get("lods", []) as Array).is_empty():
			continue
		entry.erase("lods")
		dropped += 1
	if dropped > 0:
		mesh._set_surfaces(data)
	return dropped


## Gives a lightmapped material the page of baked shadows and the sun's
## channel of it (lightmap.gdshaderinc); without the page, no channel,
## which leaves the sun to the live shadow map.
static func set_shadows(material: ShaderMaterial, shadows: Texture2D, sun_mask: Vector4) -> void:
	material.set_shader_parameter("lightmap_shadows", shadows)
	material.set_shader_parameter("lightmap_sun_channel", sun_mask if shadows != null else Vector4.ZERO)


static func is_lightmapped(description: Dictionary) -> bool:
	var shader := String(description.get("ShaderName", ""))
	return shader in WORLD_SHADERS or shader in PROP_SHADERS


## Whether a material's second UV set is the model's own rather than a
## lightmap's: F_FORCE_UV2 keeps it for a decal or a tint mask.
static func uses_own_uv2(description: Dictionary) -> bool:
	return int((description.get("IntParams", {}) as Dictionary).get("F_FORCE_UV2", 0)) != 0


## Whether a surface has a third UV set: two floats a vertex in CUSTOM0,
## which is how Godot imports the glTF's TEXCOORD_2.
static func has_third_uv(mesh: ArrayMesh, surface: int) -> bool:
	var format := mesh.surface_get_format(surface)
	if format & Mesh.ARRAY_FORMAT_CUSTOM0 == 0:
		return false
	return (format >> Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) & Mesh.ARRAY_FORMAT_CUSTOM_MASK == Mesh.ARRAY_CUSTOM_RG_FLOAT


## How densely a surface's lightmap coordinates (its second UV set, or its
## third with in_custom0) cover the lightmap, in texels per unit of its
## edges, over a sample of its triangles: the median, leaving out triangles
## collapsed onto one texel. Zero when every sampled triangle is, or when
## there is nothing to measure.
static func chart_density(mesh: Mesh, surface: int, unit_scale: float, lightmap_size: Vector2, in_custom0: bool = false) -> float:
	var arrays := mesh.surface_get_arrays(surface)
	var coordinates: Variant = arrays[Mesh.ARRAY_CUSTOM0 if in_custom0 else Mesh.ARRAY_TEX_UV2]
	if coordinates == null or arrays[Mesh.ARRAY_VERTEX] == null:
		return 0.0
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv2 := PackedVector2Array()
	if in_custom0:
		var pairs: PackedFloat32Array = coordinates
		@warning_ignore("integer_division")
		uv2.resize(pairs.size() / 2)
		for i in uv2.size():
			uv2[i] = Vector2(pairs[i * 2], pairs[i * 2 + 1])
	else:
		uv2 = coordinates
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	@warning_ignore("integer_division")
	var triangles := index.size() / 3 if not index.is_empty() else vertices.size() / 3
	if triangles == 0 or uv2.size() != vertices.size():
		return 0.0
	var texels_per_uv := lightmap_size.x * lightmap_size.y
	var densities := PackedFloat32Array()
	@warning_ignore("integer_division")
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
	@warning_ignore("integer_division")
	return densities[densities.size() / 2]


## A lightmapped material carrying over what the import made of a standard
## one: its textures, colour, cut and sidedness.
static func build(
	material: BaseMaterial3D, irradiance: Texture2D, direction: Texture2D, in_custom0: bool = false, textures_dir: String = ""
) -> ShaderMaterial:
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
	lit.set_shader_parameter("lightmap_energy", energy())
	lit.set_shader_parameter("lightmap_uv_in_custom0", in_custom0)
	carry_features(lit, BlendMaterials.vmat(material), textures_dir)
	# Kept for whoever reads the material later.
	lit.set_meta("extras", material.get_meta("extras", {}))
	return lit


## Carries what CS2's prop shaders add that the glTF has no slot for onto a
## material drawn with prop_features.gdshaderinc: the decal over its colour
## and its self-illumination, from the material's description (its vmat),
## with the textures the layers step fetched under textures_dir. Without
## them, nothing changes.
static func carry_features(lit: ShaderMaterial, description: Dictionary, textures_dir: String) -> void:
	var flags: Dictionary = description.get("IntParams", {})
	var textures: Dictionary = description.get("TextureParams", {})
	var floats: Dictionary = description.get("FloatParams", {})
	var own_uv2 := uses_own_uv2(description)
	if int(flags.get("F_DECAL_TEXTURE", 0)) != 0:
		var decal := BlendMaterials.load_texture(textures_dir, textures.get("g_tDecal"))
		if decal != null:
			lit.set_shader_parameter("decal_texture", decal)
			lit.set_shader_parameter("decal_mode", int(flags.get("F_DECAL_BLEND_MODE", 0)))
			lit.set_shader_parameter("decal_on_uv2", own_uv2 or int(flags.get("g_bUseSecondaryUvForDecal", 0)) != 0)
	if int(flags.get("F_SELF_ILLUM", 0)) != 0:
		var mask := BlendMaterials.load_texture(textures_dir, textures.get("g_tSelfIllumMask"))
		if mask != null:
			var tint: Array = (description.get("VectorParams", {}) as Dictionary).get("g_vSelfIllumTint", [1.0, 1.0, 1.0])
			# The tint is read as sRGB; the brightness is a power of two.
			var colour := Color(float(tint[0]), float(tint[1]), float(tint[2])).srgb_to_linear()
			var brightness := float(floats.get("g_flSelfIllumBrightness", 0.0))
			var strength := pow(2.0, brightness) * float(floats.get("g_flSelfIllumScale", 1.0)) * energy()
			lit.set_shader_parameter("self_illum_mask", mask)
			lit.set_shader_parameter("self_illum_color", Vector3(colour.r, colour.g, colour.b) * strength)
			lit.set_shader_parameter("self_illum_albedo_factor", float(floats.get("g_flSelfIllumAlbedoFactor", 0.0)))
			lit.set_shader_parameter("self_illum_on_uv2", own_uv2 or int(flags.get("g_bUseSecondaryUvForSelfIllum", 0)) != 0)


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
	@warning_ignore("integer_division")
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
