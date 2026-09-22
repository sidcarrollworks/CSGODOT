// What the first-person arms and weapon need of their shader
// (probe_lit.gdshader) that nothing else does: off by default, set per
// instance by ViewModelProjection.
//
// They are drawn in the world's own render, so they take the sun, its
// shadows and the probes like everything else, with their projection changed
// in the vertex pass: the field of view narrowed to CS2's viewmodel_fov, and
// the depth squeezed towards the camera so the gun is never behind a wall it
// is pressed against. Only the clip position changes; the position the
// fragment is lit and shadowed at is the true one.

// x: the field of view's narrowing, as the ratio of the tangents of the
// half-angles, world over arms. y: the depth squeeze. (1, 1) draws as anything else.
instance uniform vec2 view_model_projection = vec2(1.0, 1.0);

vec4 view_model_clip_position(vec3 view_vertex, mat4 projection) {
	vec3 squeezed = view_vertex * view_model_projection.y;
	squeezed.xy *= view_model_projection.x;
	return projection * vec4(squeezed, 1.0);
}
