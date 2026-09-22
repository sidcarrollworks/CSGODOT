// How the map's baked light (the lightmaps, or the light probes) reaches
// the screen: through the light pass, not as emission.
//
// Godot runs a material's fragment() first, then paints any decals over its
// albedo, then lights it. Emission set in fragment() is fixed before the
// decals, so baked light carried as emission (albedo times bounce light) is
// deaf to a bullet hole: the hole darkens the sun's share of the light and
// not the bounce, which on a shaded wall is all of it. The light pass sees
// the albedo as it is after the decals, and DIFFUSE_LIGHT is multiplied by
// that albedo at the end, so the baked light is handed across in this
// varying (set in fragment(), read in light()) and added there, once, on the
// sun's pass. Defining light() replaces Godot's own direct lighting, so that
// is written out below as Godot has it: Burley diffuse, Schlick-GGX
// specular (scene_forward_lights_inc.glsl).
//
// The cost is that the baked light rides on the sun: a scene with no
// directional light shows none. Every map here has its sun.

varying vec3 baked_light;

float baked_schlick(float u) {
	float m = 1.0 - u;
	float m2 = m * m;
	return m2 * m2 * m;
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT += baked_light;
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
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (fd_v * fd_l * n_dot_l / PI);

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
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * SPECULAR_AMOUNT * n_dot_l * distribution * fresnel * visibility;
}
