class_name MapLighting
extends RefCounted

## Lights a map the way the map says it should be lit.
##
## Everything here is the cheap kind of lighting: one sun, the few lamps CS2
## lights as it draws (add_lamps), the map's own sky panorama, fog, tone
## mapping and screen-space occlusion. Nothing is baked and no global
## illumination runs. The numbers come from the map's entity lump
## (light_environment, the lamps, env_cubemap_fog, post_processing_volume), so this
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

## How far towards the sun a shadow split reaches, in units (see build).
const SHADOW_PANCAKE := 4096.0

## A lamp's light (add_lamps) reaches this far past where CS2 stops it:
## Godot fades a light out over its whole range, as (1 - (d/r)^4)^2, where
## CS2's lamps shine undimmed to their range. At 2.5 times, what reaches
## CS2's range keeps 95% of its light.
const LAMP_RANGE_BEYOND := 2.5
## A lamp's shadow's depth bias, in units (see barn_light).
const LAMP_SHADOW_BIAS := 1.0

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
	# dust2 is about 5,000 units across, so from anywhere on it this reaches
	# the far side; the far buildings beyond that are the skybox's. The
	# shadow map is 8192 square (project settings) to keep the near split
	# sharp over that range, and the soft filter at its highest, or the
	# penumbra of the sun's quarter degree comes out as dither.
	light.directional_shadow_max_distance = 8192.0
	# How far towards the sun each split's shadow map reaches before what
	# is beyond is squashed flat onto its edge ("pancaked"). The default is
	# 20, metres to Godot and 20 inches to us: every building taller than a
	# crate was squashed, and a squashed wall's huge triangles tilt in depth
	# and stop covering the ground they shade. Standing in a tall building's
	# shadow at T spawn, it came out as a lit street with ghost rings of the
	# rooftop dishes in it, and whole from further off, where a larger split
	# took it. dust2's roofs stand about 1,100 units over its streets, 1,400
	# along its 50-degree sun; this covers any map's at any sun above 15.
	light.directional_shadow_pancake_size = SHADOW_PANCAKE
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
	var lamps := add_lamps(parent, entities)

	return {
		"sun_energy": light.light_energy,
		"lamps": lamps["built"],
		"lamps_left_out": lamps["left_out"],
		"ambient": "the lightmap's average" if bounce is Color else "the sky",
		"sky": "the map's panorama" if panorama != null else "a procedural stand-in",
		"fog": environment.fog_enabled,
		"exposure": environment.tonemap_exposure,
	}


## The map's lamps CS2 lights as it draws rather than baking them into the
## lightmap: a stationary light (directlight 3, or a baked shadow index)
## leaves only its bounce light and a shadow mask there, and a dynamic one
## (directlight 2) nothing. On dust2 those are the two lamps down lower
## tunnels; its other lamps are baked whole (directlight 1), so their light
## is already in the lightmap. A barn light (light_barn) is built as Source 2
## Viewer shades one (SceneLight, lighting.barn.slang), each is its own node
## under parent; the other kinds, which dust2 has none of live, are counted
## in "left_out". Returns {"built", "left_out"}.
static func add_lamps(parent: Node, entities: Array[Dictionary]) -> Dictionary:
	var built := 0
	var left_out := 0
	for entity in entities:
		var classname := String(entity.get("classname", ""))
		if not classname.begins_with("light_") or classname == "light_environment" or not is_drawn_live(entity):
			continue
		var lamp: Light3D = barn_light(entity) if classname == "light_barn" else null
		if lamp == null:
			left_out += 1
			continue
		lamp.name = "Lamp%d" % built
		parent.add_child(lamp)
		built += 1
	return {"built": built, "left_out": left_out}


## Whether CS2 lights a light as it draws, stationary or dynamic, rather than
## baking it: Source 2 Viewer's SceneLight.GetCost. A light that is off, or
## has no direct light, is neither.
static func is_drawn_live(entity: Dictionary) -> bool:
	if String(entity.get("enabled", "true")) in ["false", "0"]:
		return false
	var direct := int(entity.get("directlight", "2"))
	if direct == 0:
		return false
	if direct != 1:
		return true
	return int(entity.get("bakedshadowindex", entity.get("bakelightindex", "-1"))) >= 0


## A light_barn as a spot light. CS2's is a frustum whose eye sits
## 1 / size_params.z behind the lamp, size_params.x and y wide either side
## there; its lumens are spread over the frustum's solid angle, 40 pi lumens
## a steradian at one unit, and fall off as the inverse square from the eye,
## faded over its outer soft_x (a third, on dust2's). That is the unit the sun's
## brightness is in, so it takes SUN_ENERGY_PER_BRIGHTNESS as the sun does.
## Its shadow is Godot's, in place of the lightmap's baked mask. Null for an
## orthographic barn (size_params.z of 0), which is not built.
static func barn_light(entity: Dictionary) -> SpotLight3D:
	var size := SourceEntities.vector(String(entity.get("size_params", "")))
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		return null
	var near := 1.0 / size.z
	var turn := BrushVolume.source_basis(SourceEntities.vector(String(entity.get("angles", "[ 0, 0, 0 ]"))))
	var forward := SourceEntities.to_game(turn.x).normalized()
	var up := SourceEntities.to_game(turn.z).normalized()
	var eye := SourceEntities.to_game(SourceEntities.vector(String(entity.get("origin", "[ 0, 0, 0 ]")))) - forward * near
	var solid_angle := 4.0 * asin(size.x * size.y / sqrt((size.x * size.x + near * near) * (size.y * size.y + near * near)))
	var lumens := float(entity.get("brightness_lumens", "224")) * float(entity.get("brightnessscale", "1"))

	var lamp := SpotLight3D.new()
	lamp.light_color = _colour(entity.get("color", ""), Color.WHITE)
	lamp.light_energy = 40.0 * PI * lumens / solid_angle * SUN_ENERGY_PER_BRIGHTNESS
	# The inverse square, in units from the eye.
	lamp.spot_attenuation = 2.0
	lamp.spot_range = (near + float(entity.get("range", "512"))) * LAMP_RANGE_BEYOND
	lamp.spot_angle = rad_to_deg(atan(maxf(size.x, size.y) / near))
	# Godot's own cone fade, at its default exponent of 1: measured on a
	# plane, it keeps the full light to about three quarters of the angle
	# and fades over the rest, near CS2's soft third. A larger exponent
	# darkens the whole cone (at 9, a third of the light 30 degrees in).
	lamp.spot_angle_attenuation = 1.0
	lamp.shadow_enabled = int(entity.get("castshadows", "1")) != 0
	# Godot's 0.03 is for metres: at it, the walls and the floor under the
	# tunnels' lamps shadowed themselves in stripes.
	lamp.shadow_bias = LAMP_SHADOW_BIAS
	lamp.transform = Transform3D(Basis.looking_at(forward, up), eye)
	return lamp


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
