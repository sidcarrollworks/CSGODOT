// Batched current/next frames may occupy different atlas rectangles.
// Motion vectors use green/alpha, signed about 0.5, as Source 2 Viewer's
// particle_spritecard SampleFlow reads them. This is animation flow,
// rather than temporal-antialiasing motion data.
uniform sampler2D effect_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D frame_rects : filter_nearest, repeat_disable;
uniform sampler2D motion_texture : filter_linear, repeat_disable;
uniform sampler2D motion_rects : filter_nearest, repeat_disable;
uniform sampler2D color_gradient : filter_linear, repeat_disable;
uniform bool motion_enabled = false;
uniform bool gradient_enabled = false;
uniform bool gradient_multiply = true;
uniform bool gradient_premul_input = true;
uniform float gradient_strength = 1.0;
uniform vec2 motion_scale = vec2(0.0);

varying flat vec4 frames;

vec4 rectangle(sampler2D rects, float index) {
	int count = textureSize(rects, 0).x;
	return texelFetch(rects, ivec2(clamp(int(index), 0, count - 1), 0), 0);
}

vec2 atlas_uv(vec4 rect, vec2 card_uv) {
	return mix(rect.xy, rect.zw, card_uv);
}

vec3 gamma_color(vec3 linear_color) {
	return mix(12.92 * linear_color, 1.055 * pow(max(linear_color, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055,
		step(vec3(0.0031308), linear_color));
}

void vertex() {
	frames = INSTANCE_CUSTOM;
}

void fragment() {
	vec4 current_rect = rectangle(frame_rects, frames.x);
	vec4 next_rect = rectangle(frame_rects, frames.y);
	vec2 current_uv = atlas_uv(current_rect, UV);
	vec2 next_uv = atlas_uv(next_rect, UV);
	if (motion_enabled) {
		vec4 current_motion = rectangle(motion_rects, frames.x);
		vec4 next_motion = rectangle(motion_rects, frames.y);
		vec2 flow = (texture(motion_texture, atlas_uv(current_motion, UV)).ga * 2.0 - 1.0) * motion_scale;
		vec2 next_flow = (texture(motion_texture, atlas_uv(next_motion, UV)).ga * 2.0 - 1.0) * motion_scale;
		current_uv -= flow * frames.z;
		next_uv += next_flow * (1.0 - frames.z);
	}
	// Keep warped samples in their own atlas frame to avoid adjacent blood.
	current_uv = clamp(current_uv, current_rect.xy, current_rect.zw);
	next_uv = clamp(next_uv, next_rect.xy, next_rect.zw);
	vec4 texel = mix(texture(effect_texture, current_uv), texture(effect_texture, next_uv), frames.z);
	if (gradient_enabled) {
		// Source 2's lookup uses gamma-space luminance (LUMA_601).
		vec3 lookup_rgb = gradient_premul_input ? texel.rgb * texel.a : texel.rgb;
		float intensity = dot(gamma_color(lookup_rgb), vec3(0.299, 0.587, 0.114));
		vec4 ramp = vec4(texture(color_gradient, vec2(clamp(intensity, 0.0, 1.0), 0.5)).rgb, texel.a);
		vec4 composed = gradient_multiply ? texel * ramp : ramp;
		texel = max(mix(texel, composed, gradient_strength), vec4(0.0));
	}
	// A continuous coverage remap, not opaque alpha-test/depth writes.
	float alpha = clamp((texel.a - frames.w) / max(1.0 - frames.w, 0.00001), 0.0, 1.0) * COLOR.a;
	vec3 tint = texel.rgb * COLOR.rgb;
#ifdef PREMULTIPLY_HIT_COLOR
	tint *= alpha;
#endif
	ALBEDO = tint;
	ALPHA = alpha;
}
