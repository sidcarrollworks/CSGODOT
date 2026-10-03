class_name ProjectileTrace
extends RefCounted

## Axis-aligned projectile boxes, in Source inches. Fraction describes
## elapsed flight; end includes a separate normal clearance. The numerical
## skin is our Box3D bridge tolerance, not a recovered Source2 constant.
const LINEAR_SLOP := 0.001
const CLEARANCE := 0.01


static func cast(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D, native: Box3DQueries) -> Dictionary:
	var from := query.transform.origin
	var result := {"hit": false, "fraction": 1.0, "end": from + query.motion,
		"normal": Vector3.ZERO, "offset": Vector3.ZERO, "blocked_start": false}
	assert(query.shape is BoxShape3D and query.transform.basis.is_equal_approx(Basis.IDENTITY),
		"Projectile traces require an axis-aligned box")
	if query.motion.is_zero_approx() or space == null:
		return result
	var hit: Dictionary
	if native != null:
		var disabled := native.begin_shape_cast(query)
		var mask := Box3DQueries._mask(query.collision_mask, query.collide_with_bodies, query.collide_with_areas)
		var raw: Dictionary = native.native_world.call(&"shape_cast_projectile_box",
			from * Box3DQueries.SCALE, (from + query.motion) * Box3DQueries.SCALE,
			(query.shape as BoxShape3D).size * Box3DQueries.SCALE,
			LINEAR_SLOP * Box3DQueries.SCALE, mask, Box3DQueries.QUERY_LAYER)
		hit = native._mapped(raw) if bool(raw.get("hit", false)) else {}
		native.end_shape_cast(disabled)
	else:
		hit = _legacy(space, query)
	if hit.is_empty():
		return result
	if not hit.has("collider"):
		hit["collider"] = instance_from_id(int(hit.get("collider_id", 0))) if int(hit.get("collider_id", 0)) != 0 else null
	result.merge(hit, true)
	result["hit"] = true
	var blocked := bool(hit.get("blocked_start", false))
	var fraction := 0.0 if blocked else clampf(float(hit.get("fraction", 0.0)), 0.0, 1.0)
	var normal: Vector3 = Vector3.ZERO if blocked else hit.get("normal", Vector3.ZERO)
	# Missing/invalid geometry is a blocked trace, never an invented bounce.
	if not normal.is_finite() or normal.length_squared() < 0.5:
		blocked = true
		fraction = 0.0
		normal = Vector3.ZERO
	else:
		normal = normal.normalized()
	var offset := normal * CLEARANCE
	result["fraction"] = fraction
	result["normal"] = normal
	result["offset"] = offset
	result["end"] = from + query.motion * fraction + offset
	result["blocked_start"] = blocked
	return result


static func _legacy(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D) -> Dictionary:
	# Godot cast_motion ignores an initially embedded shape. Detect that
	# explicitly; get_rest_info supplies its original RID/shape metadata.
	var overlaps := space.intersect_shape(query, 1)
	if not overlaps.is_empty():
		var inside := space.get_rest_info(query)
		if inside.is_empty():
			inside = overlaps[0].duplicate()
		inside["blocked_start"] = true
		return inside
	var fractions := space.cast_motion(query)
	if fractions.size() < 2 or fractions[0] >= 1.0:
		return {}
	var at := query.transform
	query.transform.origin += query.motion * fractions[1]
	var hit := space.get_rest_info(query)
	query.transform = at
	# A cast without recoverable contact must stop conservatively.
	if hit.is_empty():
		return {"blocked_start": true}
	hit["fraction"] = fractions[0]
	hit["blocked_start"] = false
	return hit
