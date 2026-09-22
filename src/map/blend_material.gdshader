shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, ambient_light_disabled;

// Two texture layers mixed by a painted weight, the way CS2's
// csgo_lightmappedgeneric does it with F_LAYERS on. BlendMaterials fills the
// uniforms in from each material's vmat; see there for where it all comes from.
//
// The blend itself follows Source 2 Viewer's implementation of the same shader
// (Renderer/Shaders/complex.frag.slang and ApplyBlendModulation in
// common/utils.slang), which is the nearest thing to a reference there is:
// the weight is the paint's first component, the mask is the blend texture's
// green, a weight of one is all layer 2, and normals are mixed as texels
// before they are decoded, "not more correct, but how Source 2 does it".
//
// Bounce light comes from the map's lightmaps (lightmap.gdshaderinc) in
// place of Godot's ambient, like every other world material.

#include "res://src/map/lightmap.gdshaderinc"

// Layer 1, as Godot's glTF import left it: colour, a normal map, and the
// export's occlusion/roughness/metal texture with roughness in green.
uniform sampler2D layer1_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D layer1_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D layer1_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

// Layer 2, as Source 2 stores it: colour, and a normal with roughness in alpha.
uniform sampler2D layer2_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D layer2_normal_roughness : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

// Breaks the painted edge up. Green is the mask. Red is how soft the edge is
// at that texel, which is used when fancy_blending is 1.
uniform sampler2D blend_modulation : hint_default_white, filter_linear_mipmap, repeat_enable;

// F_FANCY_BLENDING: 1 takes the edge's softness from the mask texture, 2 from
// blend_softness.
uniform int fancy_blending = 2;
uniform float blend_softness = 0.05;

uniform vec3 layer1_tint : source_color = vec3(1.0);
uniform vec3 layer2_tint : source_color = vec3(1.0);

// Scale about a centre, for the few materials that tile layer 2 or the mask
// differently from layer 1.
uniform vec2 layer2_uv_scale = vec2(1.0);
uniform vec2 layer2_uv_centre = vec2(0.0);
uniform vec2 mask_uv_scale = vec2(1.0);
uniform vec2 mask_uv_centre = vec2(0.0);

// A band of tint along the edge between the layers: the dirt line where
// plaster has come away. Source 2 Viewer does not implement this one, so
// unlike the blend this is a reading of the parameter names, not of a
// reference: tint strongest where the weight is halfway.
uniform vec3 border_tint : source_color = vec3(1.0);
uniform float border_strength = 0.0;
uniform float border_softness = 0.1;
uniform float border_offset = 0.0;

float apply_blend_modulation(float weight, float mask, float softness) {
	float low = max(0.0, mask - softness);
	float high = min(1.0, mask + softness);
	return smoothstep(low, high, weight);
}

void fragment() {
	vec2 uv2 = (UV - layer2_uv_centre) * layer2_uv_scale + layer2_uv_centre;
	vec2 uv_mask = (UV - mask_uv_centre) * mask_uv_scale + mask_uv_centre;

	// The painted weight arrives as vertex colour; see ExportPaintChannel.
	vec4 mask = texture(blend_modulation, uv_mask);
	float softness = fancy_blending == 1 ? mask.r : blend_softness;
	float weight = apply_blend_modulation(COLOR.r, mask.g, softness);

	vec3 albedo1 = texture(layer1_albedo, UV).rgb * layer1_tint;
	vec3 albedo2 = texture(layer2_albedo, uv2).rgb * layer2_tint;
	vec3 albedo = mix(albedo1, albedo2, weight);

	float edge = 1.0 - abs(weight * 2.0 - 1.0);
	float border = smoothstep(border_offset, border_offset + max(border_softness, 0.001), edge);
	ALBEDO = mix(albedo, albedo * border_tint, border * border_strength);

	vec4 second = texture(layer2_normal_roughness, uv2);
	vec2 normal_rg = mix(texture(layer1_normal, UV).rg, second.rg, weight);
	NORMAL_MAP = vec3(normal_rg, 1.0);
	vec3 orm = texture(layer1_orm, UV).rgb;
	ROUGHNESS = mix(orm.g, second.a, weight);
	AO = orm.r;
	METALLIC = 0.0;
	EMISSION = ALBEDO * orm.r * lightmap_indirect(UV2, lightmap_tangent_normal(normal_rg, 1.0));
}
