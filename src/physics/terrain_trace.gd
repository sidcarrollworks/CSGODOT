class_name TerrainTrace
extends RefCounted

## CS2's terrain sampler sweeps a square with no vertical extent. Its end
## is a sampled height, never the clearance-adjusted end of player motion.
## Box3D accepts this degenerate box through its existing projectile query.
## The legacy backend uses the caller's thin box, solely for comparisons.
const LINEAR_SLOP := 0.001


static func cast(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D, width: float, native: Box3DQueries) -> Dictionary:
	var from := query.transform.origin
	if space == null or query.motion.is_zero_approx():
		return {}
	var hit: Dictionary
	if native != null:
		var disabled := native.begin_shape_cast(query)
		var mask := Box3DQueries._mask(query.collision_mask, query.collide_with_bodies, query.collide_with_areas)
		var raw: Dictionary = native.native_world.call(&"shape_cast_projectile_box",
			from * Box3DQueries.SCALE, (from + query.motion) * Box3DQueries.SCALE,
			Vector3(width, 0.0, width) * Box3DQueries.SCALE,
			LINEAR_SLOP * Box3DQueries.SCALE, mask, Box3DQueries.QUERY_LAYER)
		hit = native._mapped(raw) if bool(raw.get("hit", false)) else {}
		native.end_shape_cast(disabled)
	else:
		hit = ProjectileTrace._legacy(space, query)
	if hit.is_empty():
		return {}
	var fraction := clampf(float(hit.get("fraction", 0.0)), 0.0, 1.0)
	# No general bridge backoff or grenade departure push: this is the
	# square's center at contact, rather than a point on one of its corners.
	hit["end"] = from + query.motion * fraction
	hit["fraction"] = fraction
	return hit
