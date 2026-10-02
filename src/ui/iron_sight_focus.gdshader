shader_type canvas_item;
render_mode blend_disabled;

// The complete 3D view, including transparent effects, is softened outside
// the lens. This draws in canvas layer -1, before the dot and the HUD.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float raised = 0.0;
uniform float lens_radius = 0.23;
// A slight blur at 1080p; scale its reach with the rendered screen height.
uniform float blur_level = 1.5;

void fragment() {
	vec2 from_lens = (SCREEN_UV - vec2(0.5)) / SCREEN_PIXEL_SIZE;
	float height = 1.0 / SCREEN_PIXEL_SIZE.y;
	float radius = height * lens_radius;
	float feather = max(height / 1080.0 * 2.0, 1.0);
	float outside = smoothstep(radius, radius + feather, length(from_lens));
	float level = max(blur_level + log2(height / 1080.0), 0.0);
	vec3 sharp = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	vec3 soft = textureLod(screen_texture, SCREEN_UV, level).rgb;
	COLOR = vec4(mix(sharp, soft, outside * raised), 1.0);
}
