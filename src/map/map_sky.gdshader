shader_type sky;

// The EXR is scene-linear HDR, imported without hdr_as_srgb. source_color
// also lets Godot decode a fallback LDR panorama correctly.
uniform sampler2D panorama : filter_linear, source_color, hint_default_black;
uniform vec3 tint = vec3(1.0);
uniform float energy = 1.0;
uniform float lighting_energy = 1.0;

void sky() {
	vec3 texel = texture(panorama, SKY_COORDS).rgb;
	// Keep the old panorama's radiance for the world's lighting and fog;
	// the visible sky's authored brightness and tint only affect the backdrop.
	COLOR = AT_CUBEMAP_PASS ? texel * lighting_energy : texel * tint * energy;
}
