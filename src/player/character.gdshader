shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// The players' models, and so your own arms in first person, lit as CS2's
// csgo_character shader lights them: probe_lit.gdshader with the three
// things that shader's players lost, which made them shine all over where
// CS2's do not (reference/rendering.md, R7).
//
// Cloth. Where a material asks for it (F_CLOTH_SHADING), the blue channel
// of its metalness texture marks cloth (times one less the metalness, in
// the green), and there the specular is a soft sheen, Charlie's
// distribution under Neubelt's visibility, brightest at the edges seen
// edge-on, rather than GGX's highlight, which a knit's ribs catch one by
// one. Its reflectance at a head-on view is the sheen colour, the tint
// times the albedo's square root times the scale, rather than 4%. The
// glTF has no slot for the mask, so it is decompiled on its own
// (scripts/extract_assets.sh character-masks) and set by CharacterMaterials.
//
// Occlusion. CS2 darkens the direct light by the occlusion texture as well
// as the bounce (g_flAmbientOcclusionDirectDiffuse and ...Specular, 1 by
// default); Godot darkens only the bounce, so the sun lit every crease.
//
// Specular anti-aliasing. The roughness is raised where the surface's own
// normal turns fast from one pixel to the next, to that turn to the power
// of a third, so a highlight smaller than a pixel spreads rather than
// sparkles; a body across a room is a few pixels of tightly curved folds.
//
// The rest is CS2's direct light, as Source 2 Viewer's reimplementation of
// its shaders has it (complex.frag.slang, common/pbr.slang, lighting.slang
// and environment.slang): Lambert diffuse; GGX with Schlick-Smith
// visibility, k = (r + 1)^2 / 8; Schlick's Fresnel to 1 at grazing; the
// energy CS2 gives back to rough specular. Its units: Source 2 lights carry
// the irradiance over PI where Godot's LIGHT_COLOR carries it whole, so
// Lambert is divided by PI here and the specular lobes are the textbook
// ones. The ambient cube is read at the normal-mapped normal, as CS2's
// ComputeLightProbeShading reads it.
//
// The bounce light is the probes' (probe_lit.gdshaderinc) as Godot's
// ambient, as on the map (baked_light.gdshaderinc), or, for a model lit by
// a world of its own rather than the map (the buy menu's agent), the
// world's environment: the instance's ambient_from_probes, 1 or 0
// (CharacterMaterials). The sun's baked shadow comes across as there, in
// baked_sun. Godot's reflections of the surroundings are GGX's, so they
// are kept off the cloth (SPECULAR) and out of the creases, and the cloth's
// own reflection (CS2's EnvBRDFCloth) rides Godot's ambient light, which it
// multiplies by ALBEDO: the sheen's share goes on the albedo, and light()
// takes it back off the direct diffuse.
//
// Eyes. A material that draws eyes (F_EYEBALLS: the Phoenix's balaclava)
// has them painted white in its colour texture, and CS2 paints the iris,
// pupil and sclera over them in the shader, as Source 2 Viewer's
// reimplementation has it (features/csgo_character_eyes_ps.slang, ApplyEye):
// the view ray meets a sphere of the eyeball's radius at the eye bone, and
// the eye's own texture is laid on that sphere around where the eye looks,
// darker away from it, through the material's eye mask, polished (roughness
// 0.1) and with the sphere's normal, the iris's tipped back. Where each eye
// is and where it looks is the rig's, per model and per frame
// (CharacterEyes); until the rig sets them, eye_scale is 0 and nothing is
// painted.

#include "res://src/map/probe_lit.gdshaderinc"
#include "res://src/player/player_draw.gdshaderinc"
#include "res://src/map/prop_features.gdshaderinc"

// After the includes' instance uniforms, which probe_lit.gdshader declares
// in the same order: a mesh with surfaces on both shaders keeps one set of
// slots, and Godot reads a slot by its index.
instance uniform float ambient_from_probes = 1.0;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_depth = 1.0;
uniform sampler2D orm_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float roughness_factor = 1.0;
uniform float alpha_scissor = -1.0;
uniform bool has_normal_map = true;

// CS2's own metalness texture: g the metalness, b the cloth.
uniform bool cloth_shading = false;
uniform sampler2D cloth_mask : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float sheen_scale = 0.667;
// Linear; the material gives it in sRGB.
uniform vec3 sheen_tint = vec3(1.0);
uniform float direct_diffuse_occlusion = 1.0;
uniform float direct_specular_occlusion = 1.0;

// CS2's eyes (F_EYEBALLS), from the material (CharacterMaterials): the
// eye's colour, its iris mask (the colour's alpha in CS2, kept apart here,
// ExportCharacterMasks), where on the model the eyes are, and the eyeball's
// size in Source units, the iris's and the pupil's, the iris's hue shift
// and saturation.
uniform bool eyes = false;
uniform sampler2D eye_albedo : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D eye_iris : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform sampler2D eye_mask : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float eye_radius = 0.6;
uniform float eye_iris_size = 1.0;
uniform float eye_pupil_size = 0.0;
uniform float eye_hue_shift = 0.0;
uniform float eye_saturation = 1.0;
// Per model, each frame (CharacterEyes), in the world: each eyeball's
// centre, the way it looks and its right hand as the texture lies (the
// model's left), and world units to a Source unit, 0 until it is set.
uniform vec3 eye_left_position;
uniform vec3 eye_left_view = vec3(0.0, 0.0, 1.0);
uniform vec3 eye_left_across = vec3(1.0, 0.0, 0.0);
uniform vec3 eye_right_position;
uniform vec3 eye_right_view = vec3(0.0, 0.0, 1.0);
uniform vec3 eye_right_across = vec3(1.0, 0.0, 0.0);
uniform float eye_scale = 0.0;

varying float baked_sun;
// The albedo before the cloth's reflection went on it, the occlusion, how
// much is cloth, and the cloth's reflectance head-on.
varying vec3 character_albedo;
varying float character_occlusion;
varying float character_cloth;
varying vec3 character_sheen;

// The albedo in linear light, and back, whichever renderer draws it: the
// Compatibility renderer hands fragment() its colours in sRGB and turns
// ALBEDO to linear light after it (its OUTPUT_IS_SRGB), where Forward+ and
// Mobile are linear throughout. Only the cloth's arithmetic needs it.
vec3 character_to_linear(vec3 colour) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return mix(pow((colour + 0.055) / 1.055, vec3(2.4)), colour / 12.92, lessThan(colour, vec3(0.04045)));
#else
	return colour;
#endif
}

vec3 character_from_linear(vec3 colour) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return mix(1.055 * pow(colour, vec3(1.0 / 2.4)) - 0.055, colour * 12.92, lessThan(colour, vec3(0.0031308)));
#else
	return colour;
#endif
}

float character_pow5(float u) {
	float u2 = u * u;
	return u2 * u2 * u;
}

// Charlie's sheen distribution, as Source 2 has it: alpha the roughness
// squared, the sine's square held above 1/128.
float character_charlie(float alpha, float n_dot_h) {
	float inverse = 1.0 / alpha;
	return (inverse + 2.0) * pow(max(1.0 - n_dot_h * n_dot_h, 0.0078125), inverse * 0.5) / TAU;
}

// Turns a colour about the grey axis (Source 2 Viewer's RotateHue).
vec3 character_rotate_hue(vec3 colour, float angle) {
	vec3 grey = vec3(0.57735);
	float c = cos(angle);
	return colour * c + cross(grey, colour) * sin(angle) + grey * dot(grey, colour) * (1.0 - c);
}

// CS2's eye (ApplyEye) at a point of the surface, in the world, seen from
// camera: how much of the eye covers it (0 where none), and there the
// eye's colour in linear light and the eyeball's normal. mask is the
// material's eye mask there. Written without branches on the pixel, so the
// derivative the far glint reads is defined on every pixel.
float character_eye(vec3 world, vec3 camera, float mask, out vec3 colour, out vec3 normal) {
	bool is_right = distance(world, eye_right_position) < distance(world, eye_left_position);
	vec3 centre = is_right ? eye_right_position : eye_left_position;
	vec3 look = normalize(is_right ? eye_right_view : eye_left_view);
	vec3 across = normalize(is_right ? eye_right_across : eye_left_across);
	vec3 up = normalize(cross(look, across));
	float radius = eye_radius * eye_scale;

	// Where the ray from the camera through the point first meets the ball.
	vec3 ray = normalize(world - camera);
	vec3 from_centre = camera - centre;
	float along = dot(from_centre, ray);
	float discriminant = along * along - (dot(from_centre, from_centre) - radius * radius);
	float hit = discriminant > 0.0 ? -along - sqrt(max(discriminant, 0.0)) : 0.0;
	normal = normalize(camera + ray * max(hit, 0.0) - centre);

	// The texture lies on the ball around the look, right across and up
	// the image's down, the iris stretched by its size toward the middle.
	vec2 on_ball = vec2(dot(normal, across), dot(normal, -up));
	float out_from_middle = length(on_ball);
	vec2 coordinate = mix(on_ball * (2.0 - eye_iris_size), on_ball, vec2(out_from_middle));
	vec2 texel_uv = coordinate * 0.5 + 0.5;
	vec3 texel = character_to_linear(texture(eye_albedo, texel_uv, -0.5).rgb);
	float iris = texture(eye_iris, texel_uv, -0.5).r;

	colour = mix(texel, character_rotate_hue(texel, eye_hue_shift), iris);
	vec3 saturated = mix(vec3(dot(colour, vec3(0.2125, 0.7154, 0.0721))), colour, eye_saturation);
	colour = mix(colour, saturated, iris);
	colour *= smoothstep(eye_pupil_size, eye_pupil_size + 0.03, out_from_middle);
	float facing = clamp(dot(look, normal), 0.0, 1.0);
	colour *= facing;
	// An eye a few pixels across gets a glint, from 100 units away to 120.
	float glint = abs(dFdx(coordinate.x)) > 0.15
		? clamp((distance(camera, world) / max(eye_scale, 1e-4) - 100.0) * 0.05, 0.0, 1.0) : 0.0;
	float spot = smoothstep(0.1, 0.08, length(coordinate - vec2(eye_pupil_size, -eye_pupil_size)));
	colour = mix(colour, colour * 0.8 + vec3(spot), glint);

	// The iris's normal leans back from the look.
	normal = normalize(mix(normal, normalize(normal - look * 0.5), iris));
	return hit > 0.0 && mask > 0.0 && eye_scale > 0.0 ? mask * smoothstep(0.1, 0.3, facing) : 0.0;
}

void vertex() {
	POSITION = view_model_clip_position((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, PROJECTION_MATRIX);
}

void fragment() {
	vec4 albedo = texture(albedo_texture, UV) * albedo_color;
	vec3 orm = texture(orm_texture, UV).rgb;
	vec3 base = prop_decal(albedo.rgb, UV, UV2);
	EMISSION = prop_self_illum(base, UV, UV2);
	vec3 geometric_normal = normalize(NORMAL);
	vec3 across = dFdx(geometric_normal);
	vec3 down = dFdy(geometric_normal);
	float geometric_roughness = pow(clamp(max(dot(across, across), dot(down, down)), 0.0, 1.0), 1.0 / 3.0);
	ROUGHNESS = max(orm.g * roughness_factor, geometric_roughness);
	METALLIC = orm.b;
	AO = orm.r;
	if (alpha_scissor >= 0.0) {
		ALPHA = albedo.a;
		ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	}
	// The normal Godot lights with, worked out as it works it out
	// (scene_forward_clustered.glsl), for the ambient cube and the cloth.
	vec3 shading_normal = geometric_normal;
	if (has_normal_map) {
		vec2 normal_sample = texture(normal_texture, UV).rg;
		NORMAL_MAP = vec3(normal_sample, 1.0);
		NORMAL_MAP_DEPTH = normal_depth;
		vec2 slope = normal_sample * 2.0 - 1.0;
		vec3 mapped = TANGENT * slope.x + BINORMAL * slope.y + NORMAL * sqrt(max(0.0, 1.0 - dot(slope, slope)));
		shading_normal = normalize(mix(NORMAL, mapped, normal_depth));
	}
	// CS2's eye, over the albedo in linear light, the roughness and the
	// normal, after the roughness has been raised for the geometry, as CS2
	// does it.
	vec3 linear_base = character_to_linear(base);
	if (eyes) {
		vec3 eye_colour;
		vec3 eye_normal;
		float eye = character_eye(
			(INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, CAMERA_POSITION_WORLD,
			texture(eye_mask, UV, -0.5).r, eye_colour, eye_normal
		);
		if (eye > 0.0) {
			linear_base = mix(linear_base, eye_colour, eye);
			ROUGHNESS = mix(ROUGHNESS, 0.1, eye);
			shading_normal = normalize(mix(shading_normal, (VIEW_MATRIX * vec4(eye_normal, 0.0)).xyz, sqrt(eye)));
			// The normal map is in the normal already.
			NORMAL = shading_normal;
			NORMAL_MAP_DEPTH = 0.0;
		}
	}
	IRRADIANCE = vec4(probe_ambient((INV_VIEW_MATRIX * vec4(shading_normal, 0.0)).xyz), ambient_from_probes);
	baked_sun = probe_sun((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);

	float cloth = 0.0;
	if (cloth_shading) {
		vec2 mask = texture(cloth_mask, UV).gb;
		cloth = mask.y * (1.0 - mask.x);
	}
	character_albedo = linear_base;
	character_occlusion = orm.r;
	character_cloth = cloth;
	character_sheen = clamp(sheen_tint * sqrt(character_albedo) * sheen_scale, 0.0, 1.0);
	// Godot's reflection takes 0.16 times this squared as its reflectance
	// head-on: 4% times what is not cloth, times the occlusion.
	SPECULAR = 0.5 * sqrt(orm.r * (1.0 - cloth));
	// The cloth's reflection of its surroundings: the sheen's lobe halfway
	// between the normal and the view, times Neubelt's visibility with the
	// light along the normal (a quarter) and PI (CS2's EnvBRDFCloth).
	vec3 halfway = shading_normal + VIEW;
	float n_dot_h = clamp(dot(shading_normal, halfway) * inversesqrt(max(dot(halfway, halfway), 1e-8)), 0.0, 1.0);
	float reflection = character_charlie(max(ROUGHNESS * ROUGHNESS, 1e-4), n_dot_h) * 0.25 * PI;
	ALBEDO = character_from_linear(character_albedo + character_sheen * cloth * reflection);
}

void light() {
	float shadow = ATTENUATION;
	if (LIGHT_IS_DIRECTIONAL) {
		shadow *= baked_sun;
	}

	vec3 half_vector = normalize(VIEW + LIGHT);
	float n_dot_l = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float n_dot_v = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float n_dot_h = clamp(dot(NORMAL, half_vector), 0.0, 1.0);
	float l_dot_h = clamp(dot(LIGHT, half_vector), 0.0, 1.0);
	vec3 arriving = LIGHT_COLOR * shadow * n_dot_l;

	// Lambert. Godot multiplies this by ALBEDO, which carries the cloth's
	// reflection as well (fragment()), so that share is taken back out.
	vec3 diffuse_share = character_albedo / max(ALBEDO, vec3(1e-4));
	DIFFUSE_LIGHT += arriving / PI * mix(1.0, character_occlusion, direct_diffuse_occlusion) * diffuse_share;

	// GGX with Schlick-Smith visibility, or on cloth the sheen, which is
	// lit by the cosine once more (Source 2's CLOTH_ENERGY_SCALE times N.L,
	// the scale being the PI in LIGHT_COLOR).
	float alpha = max(ROUGHNESS * ROUGHNESS, 1e-4);
	float a2 = alpha * alpha;
	float denominator = n_dot_h * n_dot_h * (a2 - 1.0) + 1.0;
	float k = (ROUGHNESS + 1.0) * (ROUGHNESS + 1.0) / 8.0;
	float visibility = 1.0 / (4.0 * max((n_dot_l * (1.0 - k) + k) * (n_dot_v * (1.0 - k) + k), 1e-4));
	float ggx = a2 / (PI * denominator * denominator) * visibility;
	float neubelt = clamp(1.0 / max(4.0 * (n_dot_l + n_dot_v - n_dot_l * n_dot_v), 1.532e-5), 0.0, 1.0);
	float sheen = character_charlie(alpha, n_dot_h) * neubelt * n_dot_l;
	float lobe = mix(ggx, sheen, character_cloth);

	vec3 f0 = mix(mix(vec3(0.04), character_sheen, character_cloth), character_albedo, METALLIC);
	vec3 fresnel = f0 + (1.0 - f0) * character_pow5(1.0 - l_dot_h);
	// What CS2 gives back to rough specular for the light a single bounce
	// misses; none on cloth.
	float rough = ROUGHNESS * ROUGHNESS;
	vec3 compensation = mix(1.0 + f0 * 2.0 * rough * rough * n_dot_v, vec3(1.0), character_cloth);
	SPECULAR_LIGHT += arriving * SPECULAR_AMOUNT * lobe * fresnel * compensation
		* mix(1.0, character_occlusion, direct_specular_occlusion);
}
