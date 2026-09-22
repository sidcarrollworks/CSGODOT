class_name MapLighting
extends RefCounted

## Lights a map the way the map says it should be lit.
##
## Everything here is the cheap kind of lighting: one sun, the map's own sky
## panorama, fog, tone mapping and screen-space occlusion. Nothing is baked
## and no global illumination runs. The numbers come from the map's entity
## lump (light_environment, env_cubemap_fog, post_processing_volume), so this
## is a translation of what CS2 does with them rather than a look picked by
## eye; where Godot has no equivalent, the nearest thing is used and said so.
##
## What is not here, and would be the expensive step: bounce light. CS2 bakes
## it (bouncescale 1.75 on dust2, which is a lot), and without it Godot's
## shadows are only as warm as the ambient term below makes them.

## Source's light_environment brightness is in a unit of its own. This is the
## factor that puts dust2's 2.5 where a sunlit wall tone-maps to about what
## the game shows, found by comparing renders against the game.
const SUN_ENERGY_PER_BRIGHTNESS := 0.7

## Screen-space occlusion reaches this far, in inches. Godot's default is one
## metre, which at this scale is one unit: nothing.
const OCCLUSION_RADIUS := 24.0


## Adds a sun and a WorldEnvironment under parent. sun is what MapImporter
## reports ({"basis", "color"}), or empty; entities is the parsed entity lump,
## or empty; sky_path is the res:// path of the sky panorama, or "";
## bounce is the lightmap's average light (LightmapMaterials), or null.
## Returns what was used, for the report.
static func build(
	parent: Node, sun: Dictionary, entities: Array[Dictionary], sky_path: String, bounce: Variant = null
) -> Dictionary:
	var sun_entity := _first(entities, "light_environment")
	var fog_entity := _first(entities, "env_cubemap_fog")
	var post_entity := _first(entities, "post_processing_volume")

	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.rotation_degrees = Vector3(-50.0, -120.0, 0.0)
	if not sun.is_empty():
		light.basis = sun["basis"]
		light.light_color = sun["color"]
	light.light_energy = 1.2
	if not sun_entity.is_empty():
		light.light_color = _colour(sun_entity.get("color", ""), light.light_color)
		light.light_energy = float(sun_entity.get("brightness", "1.0")) * SUN_ENERGY_PER_BRIGHTNESS
		# The sun's size in the sky, which is how soft its shadows' edges are.
		light.light_angular_distance = float(sun_entity.get("angulardiameter", "0.5"))
	light.shadow_enabled = true
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	light.directional_shadow_blend_splits = true
	# The default is 100, which is metres to Godot and eight feet to us.
	light.directional_shadow_max_distance = 4096.0
	parent.add_child(light)

	var environment := Environment.new()
	var sky := Sky.new()
	var sky_colour := _colour(sun_entity.get("skycolor", ""), Color(0.83, 0.89, 0.97))
	var panorama := load(sky_path) as Texture2D if not sky_path.is_empty() and ResourceLoader.exists(sky_path) else null
	if panorama != null:
		var material := PanoramaSkyMaterial.new()
		material.panorama = panorama
		material.energy_multiplier = float(sun_entity.get("skyintensity", "1.0"))
		sky.sky_material = material
	else:
		var material := ProceduralSkyMaterial.new()
		material.sky_top_color = sky_colour.darkened(0.3)
		material.sky_horizon_color = sky_colour
		material.ground_horizon_color = sky_colour
		sky.sky_material = material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky

	# Ambient, for whatever has no lightmap coordinates of its own: props
	# the map lights by light probes, the far skybox, the players. The
	# lightmap's average light where it has been measured, in the same
	# units as the lightmapped surfaces read it; otherwise the sky's own
	# light plus a warm floor. CS2 gives that bounce a colour of its own
	# (skyambientbounce), which is what the floor is tinted with.
	if bounce is Color:
		var average: Color = bounce
		var peak := maxf(average.r, maxf(average.g, average.b))
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color(average.r / peak, average.g / peak, average.b / peak).linear_to_srgb()
		environment.ambient_light_energy = peak * LightmapMaterials.ENERGY
	else:
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		environment.ambient_light_sky_contribution = 0.7
		environment.ambient_light_color = _colour(sun_entity.get("skyambientbounce", ""), Color(0.6, 0.6, 0.6))
		environment.ambient_light_energy = 1.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	# CS2's tone mapper is filmic with a fixed exposure window; the middle of
	# that window is the exposure here.
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.0
	if not post_entity.is_empty():
		environment.tonemap_exposure = (
			float(post_entity.get("minexposure", "1.0")) + float(post_entity.get("maxexposure", "1.0"))
		) * 0.5
	environment.tonemap_white = 1.0

	# Distance haze. CS2 fogs with the sky's own colour in each direction,
	# which is what aerial perspective does here.
	if not fog_entity.is_empty():
		environment.fog_enabled = true
		environment.fog_mode = Environment.FOG_MODE_DEPTH
		environment.fog_depth_begin = float(fog_entity.get("cubemapfogstartdistance", "512"))
		environment.fog_depth_end = float(fog_entity.get("cubemapfogenddistance", "9000"))
		environment.fog_depth_curve = float(fog_entity.get("cubemapfogfalloffexponent", "1.0"))
		environment.fog_density = float(fog_entity.get("cubemapfogmaxopacity", "0.5"))
		environment.fog_light_color = sky_colour
		environment.fog_aerial_perspective = 1.0
		environment.fog_sky_affect = 0.0

	# Contact shadows in corners and under props, the cheap way.
	environment.ssao_enabled = true
	environment.ssao_radius = OCCLUSION_RADIUS
	environment.ssao_intensity = 2.0
	environment.ssao_detail = 0.5

	# A little bloom off the brightest surfaces, which is what the game has.
	environment.glow_enabled = true
	environment.glow_intensity = 0.4
	environment.glow_bloom = 0.05
	environment.glow_hdr_threshold = 1.0

	# ACES pulls bright warm surfaces towards white; the game's tone mapper
	# keeps more of the sand in them.
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.15

	var world_environment := WorldEnvironment.new()
	world_environment.name = "Atmosphere"
	world_environment.environment = environment
	parent.add_child(world_environment)

	return {
		"sun_energy": light.light_energy,
		"ambient": "the lightmap's average" if bounce is Color else "the sky",
		"sky": "the map's panorama" if panorama != null else "a procedural stand-in",
		"fog": environment.fog_enabled,
		"exposure": environment.tonemap_exposure,
	}


static func _first(entities: Array[Dictionary], classname: String) -> Dictionary:
	for entity in entities:
		if entity.get("classname", "") == classname:
			return entity
	return {}


## Reads "[ 255, 222, 189 ]".
static func _colour(value: Variant, fallback: Color) -> Color:
	if not value is String or (value as String).is_empty():
		return fallback
	var parts := (value as String).trim_prefix("[").trim_suffix("]").replace(" ", "").split_floats(",")
	if parts.size() < 3:
		return fallback
	return Color(parts[0] / 255.0, parts[1] / 255.0, parts[2] / 255.0)
