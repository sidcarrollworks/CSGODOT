class_name RenderVariants
extends RefCounted

## One rendering feature at a time switched off or turned down on a running
## map, and put back, so a frame's time can be taken apart by what it costs
## (scripts/profile_render.gd). Each variant changes one thing that
## MapLighting, MapImporter or the project settings chose, and apply hands
## back what undoes it, so the variants can be run one after another on the
## same scene. What each one tells is in VARIANTS.

## Every variant, in the order the profiler runs them, and what it tells.
const VARIANTS := {
	"baseline": "the game as it is",
	"live_map_shadows": "the map drawn into the sun's live shadow map again, with its soft edges, as before its shadows were baked (MapShadows): what the baking saves",
	"no_sun_shadows": "what the sun's four shadow splits cost altogether",
	"sun_hard_edges": "the soft penumbra (the sun's angular size), the shadow maps kept",
	"sun_filter_low": "the soft filter at its lowest rather than Soft High",
	"sun_atlas_4096": "a 4096 shadow atlas rather than 8192",
	"sun_distance_2048": "shadows out to 2048 units rather than 8192",
	"one_sided_casters": "the map casting from its front faces only, not both",
	"no_occlusion": "occlusion culling off (MapOccluders): what the map's walls save by hiding what is behind them",
	"no_visibility": "the map's own visibility off (WorldVisibility): what CS2's precomputed culling saves",
	"no_msaa": "4x MSAA off",
	"sdr_2d": "2D blended in sRGB rather than in linear light (project.godot's hdr_2d, which the HUD needs to blend as CS2's does)",
	"no_hud_blur": "the HUD's panels without the blurred world behind them (HudElement's screen copies)",
	"no_glow": "bloom off",
	"other_grade": "the other colour grade: CS2's curve and table from the map's post-processing (ColourGrade) on a map graded with ACES, ACES on one graded with CS2's; for looks, beside the game, more than for time",
	"no_fog": "the distance haze off",
	"no_reflections": "the reflection probes at no strength and the sky's reflections off (MapReflections); not what reflecting costs, since the probes are still drawn",
	"no_skybox": "the 3D skybox's meshes hidden",
	"no_players": "every body but the camera's hidden",
	"half_resolution": "the 3D drawn at half the width and height: fill rate against the rest",
	"all_off": "every one of the above at once but culling, resolution, the live map shadows and the grade: what is left is the map's geometry and materials",
}

## A far material includes the squeeze (far.gdshaderinc): the skybox's meshes.
const FAR_MARK := "far.gdshaderinc"


static func names() -> PackedStringArray:
	return PackedStringArray(VARIANTS.keys())


## Switches one variant on under root, drawn through viewport. Returns what
## puts it back.
static func apply(variant: String, root: Node, viewport: Viewport) -> Callable:
	var sun := sun_of(root)
	var environment := environment_of(root)
	match variant:
		"baseline":
			return func() -> void: pass
		"live_map_shadows":
			if sun == null:
				return func() -> void: pass
			var undo: Array[Callable] = [
				_change(sun, "shadow_caster_mask", 0xFFFFFFFF),
				_change(sun, "light_angular_distance", float(sun.get_meta(&"angular_diameter", sun.light_angular_distance))),
			]
			return _together(undo)
		"no_sun_shadows":
			return _change(sun, "shadow_enabled", false)
		"sun_hard_edges":
			return _change(sun, "light_angular_distance", 0.0)
		"sun_filter_low":
			var quality := int(ProjectSettings.get_setting(
				"rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 2))
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
			return func() -> void:
				RenderingServer.directional_soft_shadow_filter_set_quality(quality as RenderingServer.ShadowQuality)
		"sun_atlas_4096":
			var size := int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size", 4096))
			var half_floats := bool(ProjectSettings.get_setting(
				"rendering/lights_and_shadows/directional_shadow/16_bits", true))
			RenderingServer.directional_shadow_atlas_set_size(4096, half_floats)
			return func() -> void: RenderingServer.directional_shadow_atlas_set_size(size, half_floats)
		"sun_distance_2048":
			return _change(sun, "directional_shadow_max_distance", 2048.0)
		"one_sided_casters":
			var undo: Array[Callable] = []
			var visibility := visibility_of(root)
			for mesh in meshes_of(root):
				# The map's visibility sets how a mesh casts each time it draws
				# or hides it, so a mesh it culls is changed through it: one
				# hidden now as well, for when it is drawn.
				if visibility != null and visibility.drawn_cast_shadow(mesh) == GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED:
					visibility.set_drawn_cast_shadow(mesh, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
					undo.append(visibility.set_drawn_cast_shadow.bind(mesh, GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED))
				elif mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED:
					undo.append(_change(mesh, "cast_shadow", GeometryInstance3D.SHADOW_CASTING_SETTING_ON))
			return _together(undo)
		"no_occlusion":
			return _change(viewport, "use_occlusion_culling", false)
		"no_visibility":
			var visibility := visibility_of(root)
			if visibility == null:
				return func() -> void: pass
			# From a point no cluster holds, everything is drawn; stopped, it
			# stays so until put back, when it culls from the camera again.
			visibility.set_process(false)
			visibility.show_from(Vector3.INF)
			return func() -> void: visibility.set_process(true)
		"no_msaa":
			return _change(viewport, "msaa_3d", Viewport.MSAA_DISABLED)
		"sdr_2d":
			return _change(viewport, "use_hdr_2d", false)
		"no_hud_blur":
			var undo: Array[Callable] = []
			for element in root.find_children("*", "Control", true, false):
				if not element is HudElement:
					continue
				for surface in element.get_children(true):
					if surface is BackBufferCopy:
						undo.append(_change(surface, "copy_mode", BackBufferCopy.COPY_MODE_DISABLED))
					elif surface.name == &"Blur":
						undo.append(_change(surface, "visible", false))
			return _together(undo)
		"no_glow":
			return _change(environment, "glow_enabled", false)
		"no_fog":
			return _change(environment, "fog_enabled", false)
		"other_grade":
			if environment == null or not environment.has_meta(&"grade"):
				return func() -> void: pass
			var before := String(environment.get_meta(&"grade"))
			ColourGrade.use(environment, "aces" if before == "cs2" else "cs2")
			return func() -> void: ColourGrade.use(environment, before)
		"no_reflections":
			# At no strength rather than hidden: a probe shown again is drawn
			# again, and by then the map's visibility hides what the camera
			# cannot see, which the probe would be drawn without.
			var undo: Array[Callable] = [_change(environment, "reflected_light_source", Environment.REFLECTION_SOURCE_DISABLED)]
			for probe in root.find_children("*", "ReflectionProbe", true, false):
				undo.append(_change(probe, "intensity", 0.0))
			return _together(undo)
		"no_skybox":
			var undo: Array[Callable] = []
			for mesh in far_meshes(root):
				undo.append(_change(mesh, "visible", false))
			return _together(undo)
		"no_players":
			var undo: Array[Callable] = []
			for body in root.find_children("*", "Node3D", true, false):
				if body is PlayerModel:
					undo.append(_change(body, "visible", false))
			return _together(undo)
		"half_resolution":
			return _change(viewport, "scaling_3d_scale", 0.5)
		"all_off":
			var undo: Array[Callable] = []
			for each in VARIANTS:
				if not each in ["baseline", "all_off", "half_resolution", "no_occlusion", "no_visibility", "live_map_shadows", "other_grade"]:
					undo.append(apply(each, root, viewport))
			undo.reverse()
			return _together(undo)
	push_error("No render variant called %s." % variant)
	return func() -> void: pass


## The map's sun, or null.
static func sun_of(root: Node) -> DirectionalLight3D:
	var suns := root.find_children("*", "DirectionalLight3D", true, false)
	return suns[0] as DirectionalLight3D if not suns.is_empty() else null


## The map's own visibility culling (WorldVisibility), or null.
static func visibility_of(root: Node) -> WorldVisibility:
	for node in root.find_children("*", "Node", true, false):
		if node is WorldVisibility:
			return node as WorldVisibility
	return null


## The map's reflection probes (MapReflections), or null.
static func reflections_of(root: Node) -> MapReflections:
	for node in root.find_children("*", "Node3D", true, false):
		if node is MapReflections:
			return node as MapReflections
	return null


## The map's environment, or null.
static func environment_of(root: Node) -> Environment:
	for node in root.find_children("*", "WorldEnvironment", true, false):
		if (node as WorldEnvironment).environment != null:
			return (node as WorldEnvironment).environment
	return null


## Every mesh instance drawn under root.
static func meshes_of(root: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh != null and mesh.is_visible_in_tree():
			meshes.append(mesh)
	return meshes


## The meshes drawn behind everything (FarMaterials): the 3D skybox.
static func far_meshes(root: Node) -> Array[MeshInstance3D]:
	var far: Array[MeshInstance3D] = []
	for mesh in meshes_of(root):
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as ShaderMaterial
			if material != null and material.shader != null and material.shader.code.contains(FAR_MARK):
				far.append(mesh)
				break
	return far


## What is drawn under root, counted: mesh instances, their surfaces and
## triangles, how many cast shadows and from both faces, how many of those
## into the sun's (a map whose shadows are baked casts into the lamps' only,
## MapShadows), the materials by shader, and the skybox's share. A surface
## is a draw call in each pass that sees it, and one more in each shadow
## split that does.
static func scene_stats(root: Node) -> Dictionary:
	var stats := {
		"instances": 0, "surfaces": 0, "triangles": 0,
		"casting_instances": 0, "double_sided_casters": 0, "casting_triangles": 0, "sun_casting_instances": 0,
		"skybox_instances": 0, "skybox_triangles": 0,
		"materials": 0, "shaders": {},
	}
	var sun := sun_of(root)
	var sun_casters: int = sun.shadow_caster_mask if sun != null and sun.shadow_enabled else 0
	var materials := {}
	var far := {}
	for mesh in far_meshes(root):
		far[mesh] = true
	for mesh in meshes_of(root):
		var triangles := 0
		for surface in mesh.mesh.get_surface_count():
			triangles += _triangles(mesh.mesh, surface)
			var material := mesh.get_active_material(surface)
			if material != null and not materials.has(material):
				materials[material] = true
				var kind := _shader_kind(material)
				stats["shaders"][kind] = int(stats["shaders"].get(kind, 0)) + 1
		stats["instances"] += 1
		stats["surfaces"] += mesh.mesh.get_surface_count()
		stats["triangles"] += triangles
		if mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			stats["casting_instances"] += 1
			stats["casting_triangles"] += triangles
			if mesh.layers & sun_casters != 0:
				stats["sun_casting_instances"] += 1
		if mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED:
			stats["double_sided_casters"] += 1
		if far.has(mesh):
			stats["skybox_instances"] += 1
			stats["skybox_triangles"] += triangles
	stats["materials"] = materials.size()
	return stats


static func _triangles(mesh: Mesh, surface: int) -> int:
	if mesh is ArrayMesh:
		var array_mesh := mesh as ArrayMesh
		var indices := array_mesh.surface_get_array_index_len(surface)
		@warning_ignore("integer_division")
		return (indices if indices > 0 else array_mesh.surface_get_array_len(surface)) / 3
	# A primitive builds its arrays when asked; they are small.
	var arrays := mesh.surface_get_arrays(surface)
	var index: Variant = arrays[Mesh.ARRAY_INDEX]
	var count: int = (index as PackedInt32Array).size() if index != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	@warning_ignore("integer_division")
	return count / 3


## The shader a material draws with, by its file's name, or the kind of
## built-in material.
static func _shader_kind(material: Material) -> String:
	if material is ShaderMaterial:
		var shader := (material as ShaderMaterial).shader
		if shader == null:
			return "no shader"
		if not shader.resource_path.is_empty():
			return shader.resource_path.get_file()
		return "far variant" if shader.code.contains(FAR_MARK) else "generated shader"
	return material.get_class()


static func _change(object: Object, property: StringName, value: Variant) -> Callable:
	if object == null:
		return func() -> void: pass
	var before: Variant = object.get(property)
	object.set(property, value)
	return func() -> void:
		if is_instance_valid(object):
			object.set(property, before)


static func _together(undo: Array[Callable]) -> Callable:
	return func() -> void:
		for each in undo:
			each.call()
