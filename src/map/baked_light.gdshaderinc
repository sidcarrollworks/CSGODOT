// How the map's baked light (the lightmaps, or the light probes) reaches
// the screen: its bounce as Godot's own ambient light, its sun's shadow in
// the light pass.
//
// The bounce is written to IRRADIANCE in fragment(), with an alpha of 1,
// which puts it in place of the ambient Godot would take from the
// environment. Godot multiplies it by the occlusion (AO) and the albedo
// after the decals have been painted over them, so a bullet hole darkens
// it; baked light carried as emission, as it first was, was fixed before
// the decals and deaf to a hole. And it keeps Godot's reflections. They
// came with the ambient light, so the switch that turns that off
// (ambient_light_disabled, which these materials used to set, bringing the
// bounce in through light() instead) took every reflection with it, the
// sky's and the reflection probes' (MapReflections) alike: nothing shone
// in the shade, a player's jacket least of all (checked in Godot 4.7.2's
// scene_forward_clustered.glsl). Godot also dims a reflection where the
// ambient reaching a surface is faint, which is its stand-in for CS2
// scaling its cubemaps by the baked light at each pixel.
//
// Defining light() replaces Godot's own direct lighting, so that is written
// out below as Godot has it: Burley diffuse, Schlick-GGX specular
// (scene_forward_lights_inc.glsl). It is here for the sun's shadow: the
// static map's, as CS2 baked it, handed across in a varying (set in
// fragment(), read in light()) from the lightmap's shadow page on the map's
// surfaces (lightmap_sun), from the light probes' on what they light
// (probe_sun). The live shadow map, in ATTENUATION, is on top of it, and
// on a map whose shadows are baked it holds only what moves (MapShadows).
// Every shader that includes this sets IRRADIANCE and baked_sun in
// fragment().

varying float baked_sun;

float baked_schlick(float u) {
	float m = 1.0 - u;
	float m2 = m * m;
	return m2 * m2 * m;
}

void light() {
	float shadow = ATTENUATION;
	if (LIGHT_IS_DIRECTIONAL) {
		shadow *= baked_sun;
	}

	vec3 half_vector = normalize(VIEW + LIGHT);
	float n_dot_l = max(dot(NORMAL, LIGHT), 0.0);
	float n_dot_v = max(dot(NORMAL, VIEW), 1e-4);
	float n_dot_h = max(dot(NORMAL, half_vector), 0.0);
	float l_dot_h = max(dot(LIGHT, half_vector), 0.0);

	// Burley diffuse. LIGHT_COLOR carries the light's energy times PI.
	float fd90_minus_1 = 2.0 * l_dot_h * l_dot_h * ROUGHNESS - 0.5;
	float fd_v = 1.0 + fd90_minus_1 * baked_schlick(n_dot_v);
	float fd_l = 1.0 + fd90_minus_1 * baked_schlick(n_dot_l);
	DIFFUSE_LIGHT += LIGHT_COLOR * shadow * (fd_v * fd_l * n_dot_l / PI);

	// Schlick-GGX specular, with the dielectric reflectance Godot's default
	// SPECULAR of 0.5 gives (0.16 * 0.5 * 0.5).
	float alpha = ROUGHNESS * ROUGHNESS;
	float a2 = alpha * alpha;
	float denominator = n_dot_h * n_dot_h * (a2 - 1.0) + 1.0;
	float distribution = a2 / (PI * denominator * denominator);
	float visibility = 0.5 / (
		n_dot_l * sqrt(n_dot_v * n_dot_v * (1.0 - a2) + a2)
		+ n_dot_v * sqrt(n_dot_l * n_dot_l * (1.0 - a2) + a2) + 1e-5
	);
	vec3 f0 = mix(vec3(0.04), ALBEDO, METALLIC);
	float f90 = clamp(dot(f0, vec3(50.0 * 0.33)), METALLIC, 1.0);
	vec3 fresnel = f0 + (f90 - f0) * baked_schlick(l_dot_h);
	SPECULAR_LIGHT += LIGHT_COLOR * shadow * SPECULAR_AMOUNT * n_dot_l * distribution * fresnel * visibility;
}
