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
// far_depth stays for a shader whose vertex() sets POSITION already.
//
// The fragment keeps a thousandth of its distance from the far plane, so
// the parts of a far scene still sort among themselves while anything of
// the near scene, at any depth, lands in front. Which end of the buffer is
// far depends on the renderer: Forward+ and Mobile reverse it (far is 0),
// Compatibility does not (far is 1); the material is told.

uniform float far_plane_depth = 0.0;
const float FAR_DEPTH_KEEP = 0.001;

float far_depth(float depth) {
	return far_plane_depth + (depth - far_plane_depth) * FAR_DEPTH_KEEP;
}

// A clip position with its depth squeezed towards the far plane, the way
// far_depth squeezes a fragment's. far is where the far plane is in clip
// space, which the renderer gives as CLIP_SPACE_FAR: 0 in Forward+ and
// Mobile, -1 in Compatibility (both reverse the depth, and OpenGL's clip
// space runs from -1).
vec4 far_position(vec4 clip, float far) {
	clip.z = far * clip.w + (clip.z - far * clip.w) * FAR_DEPTH_KEEP;
	return clip;
}
