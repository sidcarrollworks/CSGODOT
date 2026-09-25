// The map's baked light at one place, as an ambient cube: what CS2 lights
// its players, weapons and most props with, read from its light-probe
// volumes (LightProbes) at the object's position and handed to the shader
// per instance. The six colours are the light arriving from the game's
// +X, -X, +Y, -Y, +Z, -Z, and a surface takes each by the square of its
// normal's part along that axis, which is Valve's ambient cube.
//
// A material that uses this turns Godot's ambient off for itself and adds
// the result, times its occlusion, in the light pass (baked_light.gdshaderinc),
// at the same energy as the lightmapped surfaces.

instance uniform vec3 probe_px = vec3(0.4);
instance uniform vec3 probe_nx = vec3(0.4);
instance uniform vec3 probe_py = vec3(0.5);
instance uniform vec3 probe_ny = vec3(0.3);
instance uniform vec3 probe_pz = vec3(0.4);
instance uniform vec3 probe_nz = vec3(0.4);
uniform float probe_energy = 0.4;

// The static map's shadow from the sun, as CS2 baked it into its probes (the
// atlas's _dlshd page, MapShadows): LightProbes makes one 3D texture of it
// for the whole map, how much of the sun reaches each cell (1 for all of
// it), and each instance is told where the cells of the volume it stands
// in lie in that texture (ProbeMaterials.light_instance): a Source-axes
// point times the scale plus the offset, kept half a cell inside the
// volume's block, which is how LightProbes reads it too. Read at every
// fragment, as Source 2 Viewer's SampleProbeDirectLightShadows does, so a
// shadow's edge can cross a body. The scale's w is 1 once an instance is
// placed; until then, and on a map without the page, the sun is not cut.
global uniform sampler3D probe_sun_visibility;
instance uniform vec4 probe_shadow_scale = vec4(0.0);
instance uniform vec3 probe_shadow_offset = vec3(0.0);
instance uniform vec3 probe_shadow_min = vec3(0.0);
instance uniform vec3 probe_shadow_max = vec3(0.0);

vec3 probe_ambient(vec3 world_normal) {
	vec3 n = normalize(world_normal);
	vec3 weights = n * n;
	vec3 light = weights.x * (n.x >= 0.0 ? probe_px : probe_nx)
		+ weights.y * (n.y >= 0.0 ? probe_py : probe_ny)
		+ weights.z * (n.z >= 0.0 ? probe_pz : probe_nz);
	return light * probe_energy;
}

// How much of the sun reaches a point in the world past the static map.
float probe_sun(vec3 world_position) {
	if (probe_shadow_scale.w == 0.0) {
		return 1.0;
	}
	// Source's X is the game's Z, its Y the game's X, its Z the game's Y.
	vec3 cell = world_position.zxy * probe_shadow_scale.xyz + probe_shadow_offset;
	return texture(probe_sun_visibility, clamp(cell, probe_shadow_min, probe_shadow_max)).r;
}
