shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// A one-layer material drawn behind everything: its depth is squeezed
// against the far plane, so any surface of the map in front of it or
// behind it wins the depth test, while its own parts still sort among
// themselves. For the 3D skybox, which Source 2 draws in a pass of its own
// before the world and which is ordinary geometry here. What Godot's import
// made of the material is carried over by FarMaterials.

#include "res://src/map/far.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_depth = 1.0;
uniform sampler2D orm_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float roughness_factor = 1.0;
uniform float alpha_scissor = -1.0;
uniform bool has_normal_map = true;

void vertex() {
	POSITION = far_position(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0), CLIP_SPACE_FAR);
}

void fragment() {
	vec4 albedo = texture(albedo_texture, UV) * albedo_color;
	vec3 orm = texture(orm_texture, UV).rgb;
	ALBEDO = albedo.rgb;
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
}
