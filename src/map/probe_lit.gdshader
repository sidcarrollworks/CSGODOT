shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, ambient_light_disabled;

// A one-layer material lit by the map's light probes (probe_lit.gdshaderinc)
// in place of Godot's ambient: for props without lightmap coordinates, and
// for the players' models, and so for the first-person arms, drawn with a
// projection of their own (player_draw.gdshaderinc). What Godot's import made
// of the material is carried over by ProbeMaterials.

#include "res://src/map/probe_lit.gdshaderinc"
#include "res://src/map/baked_light.gdshaderinc"
#include "res://src/map/prop_features.gdshaderinc"
#include "res://src/player/player_draw.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_depth = 1.0;
uniform sampler2D orm_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float roughness_factor = 1.0;
uniform float alpha_scissor = -1.0;
uniform bool has_normal_map = true;

void vertex() {
	POSITION = view_model_clip_position((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, PROJECTION_MATRIX);
}

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
	if (has_normal_map) {
		NORMAL_MAP = vec3(texture(normal_texture, UV).rg, 1.0);
		NORMAL_MAP_DEPTH = normal_depth;
	}
	vec3 world_normal = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	baked_light = orm.r * probe_ambient(world_normal);
}
