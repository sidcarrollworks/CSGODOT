// Depth squeezed against the far plane, for what is drawn behind everything.
//
// The squeeze is done to the vertex's clip position (far_position), which
// leaves the GPU's early depth test working: a skybox fragment behind the
// map is thrown away before its shader runs. Written per fragment instead
// (DEPTH), every fragment of the skybox ran its shader, hidden or not,
// which measured 0.8 ms of a 3.1 ms frame at 1920x1080 and 3.2 of 10.4 at
// 3840x2160 (reference/rendering.md). It is the same depth at every pixel
// either way: the squeeze is affine in the depth the rasteriser
// interpolates (z over w), so doing it at the corners is exact.
// A shader has one vertex(), so one that has its own brought in by an
// include (lightmap.gdshaderinc) squeezes there, under FAR_SQUEEZE, which
// this defines ahead of it (FarMaterials.variant_of); far_depth stays for
// a shader whose vertex() sets POSITION already.
//
// The fragment keeps a thousandth of its distance from the far plane, so
// the parts of a far scene still sort among themselves while anything of
// the near scene, at any depth, lands in front. Every renderer reverses
// the depth buffer since Godot 4.3, Compatibility included, so far is 0
// (FarMaterials.far_plane_depth); the material is told. Per fragment, a
// part past the far plane is clipped before its fragment runs, so only the
// squeeze in the vertex stage (far_position) brings it back.

#define FAR_SQUEEZE

uniform float far_plane_depth = 0.0;
const float FAR_DEPTH_KEEP = 0.001;

float far_depth(float depth) {
	return far_plane_depth + (depth - far_plane_depth) * FAR_DEPTH_KEEP;
}

// A clip position with its depth squeezed towards the far plane, the way
// far_depth squeezes a fragment's. far is where the far plane is in clip
// space, which the renderer gives as CLIP_SPACE_FAR: 0 in Forward+ and
// Mobile, -1 in Compatibility (both reverse the depth, and OpenGL's clip
// space runs from -1). projection is PROJECTION_MATRIX.
//
// A perspective projection's clip depth, measured from the far plane
// (z - far * w), falls off in a straight line with the distance w, from
// eye_depth at the eye to 0 at the far plane and below it beyond; its depth
// (over w) is eye_depth * (1 / w - 1 / far distance). The squeeze keeps a
// thousandth of eye_depth / w instead, the same curve as if the far plane
// were at infinity: every distance, however great, lands in the thin slab
// just inside the far plane, farther parts nearer the plane. Squeezing the
// depth itself (a thousandth of z - far * w) left what lay past the far
// plane past it, and clipped: the 3D skybox's terrain, imported at sixteen
// times its size, runs out to half a million units, and dust2's hill with
// it was cut from T spawn (reference/playtest-2026-09-25.md, issue 23).
// Inside the far plane the two differ by a constant, a thousandth of
// eye_depth / far distance, so the far parts sort among themselves as they
// did, and the map, anywhere within 8,192 units, still wins against any of
// them from 32 units out (tests/run_map_tests.gd). The view's x and y and w
// are left alone, and so is VERTEX, which the fog's aerial perspective
// reads its distance from (Godot 4.7.2's fog_process), not the depth.
// In Forward+ and Mobile the squeezed clip depth is the slab alone, exact
// in 32 bits at any distance. In Compatibility it is -w plus the slab,
// which far off rounds onto the far plane itself: drawn, since the clip
// test takes the plane, but no longer sorted among its own parts.
float far_eye_depth(mat4 projection, float far) {
	vec4 eye = projection * vec4(0.0, 0.0, 0.0, 1.0);
	return eye.z - far * eye.w;
}

vec4 far_position(vec4 clip, float far, mat4 projection) {
	clip.z = far * clip.w + far_eye_depth(projection, far) * FAR_DEPTH_KEEP;
	return clip;
}
