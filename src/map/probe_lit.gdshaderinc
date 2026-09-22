// The map's baked light at one place, as an ambient cube: what CS2 lights
// its players, weapons and most props with, read from its light-probe
// volumes (LightProbes) at the object's position and handed to the shader
// per instance. The six colours are the light arriving from the game's
// +X, -X, +Y, -Y, +Z, -Z, and a surface takes each by the square of its
// normal's part along that axis, which is Valve's ambient cube.
//
// A material that uses this turns Godot's ambient off for itself and adds
// the result as emission, times its albedo and occlusion, at the same
// energy as the lightmapped surfaces.

instance uniform vec3 probe_px = vec3(0.4);
instance uniform vec3 probe_nx = vec3(0.4);
instance uniform vec3 probe_py = vec3(0.5);
instance uniform vec3 probe_ny = vec3(0.3);
instance uniform vec3 probe_pz = vec3(0.4);
instance uniform vec3 probe_nz = vec3(0.4);
uniform float probe_energy = 0.4;

vec3 probe_ambient(vec3 world_normal) {
	vec3 n = normalize(world_normal);
	vec3 weights = n * n;
	vec3 light = weights.x * (n.x >= 0.0 ? probe_px : probe_nx)
		+ weights.y * (n.y >= 0.0 ? probe_py : probe_ny)
		+ weights.z * (n.z >= 0.0 ? probe_pz : probe_nz);
	return light * probe_energy;
}
