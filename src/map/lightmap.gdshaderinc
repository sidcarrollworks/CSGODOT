// The map's baked bounce light, read from CS2's own lightmaps.
//
// CS2 bakes the indirect light into an irradiance map and computes the sun
// live, so the irradiance is exactly the term Godot has no way to compute
// here: what light reaches a surface after bouncing off everything else.
// A companion map says which way that light mostly arrives, in tangent
// space, so a normal-mapped wall can respond to it, and how directional it
// is. The maths is Source 2 Viewer's ComputeLightmapShading, less the
// curvature term, which needs the derivatives of the geometric normal and
// buys very little on a map of flat walls.
//
// A material that uses this hands the result to Godot as its ambient light
// (IRRADIANCE), in place of the environment's, and Godot multiplies it by
// the occlusion and the albedo as the decals left them (baked_light.gdshaderinc).

uniform sampler2D lightmap_irradiance : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform sampler2D lightmap_direction : hint_default_white, filter_linear, repeat_disable;

// The lightmap is in the game's units, this is the scale into Godot's. Set
// against a screenshot of the game at B site: shaded ground comes out at
// the same brightness in both (0.27), a shaded wall a little lighter here
// (0.24 against 0.20), with the sun as MapLighting sets it.
uniform float lightmap_energy = 0.4;
uniform float lightmap_directional_strength = 1.0;

// The static map's shadow from each light CS2 bakes one for, a channel each
// and 1 where it is blocked (direct_light_shadows, MapShadows), and which
// channel is the sun's. Without the page the channel is zero, which reads
// as no shadow: the sun's live shadow map then draws the map as before.
uniform sampler2D lightmap_shadows : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform vec4 lightmap_sun_channel = vec4(0.0);

// Where a surface's lightmap coordinates are: the second UV set, or on a
// prop whose second set is its own (F_FORCE_UV2: its decal reads it) the
// third, which Godot imports as CUSTOM0. This include writes vertex(), so a
// shader using it has none of its own.
uniform bool lightmap_uv_in_custom0 = false;
varying vec2 lightmap_uv;

void vertex() {
	lightmap_uv = lightmap_uv_in_custom0 ? CUSTOM0.xy : UV2;
#ifdef FAR_SQUEEZE
	// Drawn behind everything (far.gdshaderinc), and this is the vertex().
	POSITION = far_position(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0), CLIP_SPACE_FAR);
#endif
}

const float LIGHTMAP_DIRECTION_MIN_Z = 0.0872;
const float LIGHTMAP_DIRECTIONAL_MIN_Z = 0.05;

// The bounce light a surface receives, given its tangent-space normal.
vec3 lightmap_indirect(vec2 uv, vec3 tangent_normal) {
	vec3 irradiance = texture(lightmap_irradiance, uv).rgb;
	vec4 direction = texture(lightmap_direction, uv);

	float max_xy = sqrt(1.0 - LIGHTMAP_DIRECTION_MIN_Z * LIGHTMAP_DIRECTION_MIN_Z);
	vec2 xy = direction.xy * 2.0 - 1.0;
	xy *= max_xy / max(max_xy, length(xy));
	float cos_theta = sqrt(max(0.0, 1.0 - dot(xy, xy)));
	vec3 light = normalize(vec3(xy, cos_theta));

	float directionality = direction.z * lightmap_directional_strength;
	vec3 undirected = irradiance * clamp(directionality, 0.0, 1.0);
	float n_dot_l = max(dot(light, tangent_normal), 0.0);
	float light_z = max(light.z, LIGHTMAP_DIRECTIONAL_MIN_Z);
	return (n_dot_l * (irradiance - undirected) / light_z + undirected) * lightmap_energy;
}

// How much of the sun reaches a surface past the static map, as CS2 baked
// it: Source 2 Viewer's lighting.slang takes one minus the sun's channel.
float lightmap_sun(vec2 uv) {
	return clamp(1.0 - dot(texture(lightmap_shadows, uv), lightmap_sun_channel), 0.0, 1.0);
}

// A normal map texel as a tangent-space normal, at a strength.
vec3 lightmap_tangent_normal(vec2 normal_rg, float depth) {
	vec2 xy = (normal_rg * 2.0 - 1.0) * depth;
	return normalize(vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy)))));
}
