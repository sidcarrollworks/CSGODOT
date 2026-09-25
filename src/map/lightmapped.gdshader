shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// A one-layer world material with the map's baked bounce light. What
// Godot's import made of the material (colour, normal map, the roughness
// and occlusion texture, an alpha cut) is carried over by LightmapMaterials;
// the lightmap terms come from lightmap.gdshaderinc.

#include "res://src/map/lightmap.gdshaderinc"
#include "res://src/map/baked_light.gdshaderinc"
#include "res://src/map/prop_features.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_depth = 1.0;
// The export's occlusion (red), roughness (green) and metal (blue) texture.
uniform sampler2D orm_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float roughness_factor = 1.0;
// Below zero means no cut: the material is opaque.
uniform float alpha_scissor = -1.0;
uniform bool has_normal_map = true;

void fragment() {
	vec4 albedo = texture(albedo_texture, UV) * albedo_color;
	vec3 orm = texture(orm_texture, UV).rgb;
	ALBEDO = prop_decal(albedo.rgb, UV, UV2);
	EMISSION = prop_self_illum(ALBEDO, UV, UV2);
	ROUGHNESS = orm.g * roughness_factor;
	METALLIC = orm.b;
	AO = orm.r;
	if (alpha_scissor >= 0.0) {
		ALPHA = albedo.a;
		ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	}

	vec3 tangent_normal = vec3(0.0, 0.0, 1.0);
	if (has_normal_map) {
		vec2 rg = texture(normal_texture, UV).rg;
		NORMAL_MAP = vec3(rg, 1.0);
		NORMAL_MAP_DEPTH = normal_depth;
		tangent_normal = lightmap_tangent_normal(rg, normal_depth);
	}
	IRRADIANCE = vec4(lightmap_indirect(lightmap_uv, tangent_normal), 1.0);
	baked_sun = lightmap_sun(lightmap_uv);
}
