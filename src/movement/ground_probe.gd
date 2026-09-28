class_name GroundProbe
extends RefCounted

## How far the ground is below a point, by one ray straight down: the body's
## height above the ground in the air (PlayerBody.height_above_ground, CS2's
## air_height_above_ground), and, drawn only, how far a foot is from the
## floor under it.
##
## A ray, not a hull trace: it asks what is under one point, which is what a
## height or a foot needs, and a ray costs a few microseconds against a hull
## trace's tens on dust2 (reference/performance.md). It sees the world only:
## player clips stop a hull but are nothing to stand a foot on or to be above,
## and other players are not the ground.

## What the ray sees: the map's world layer.
const MASK := Hitscan.WORLD_LAYER
## How far above the point the ray starts, so a point resting on the floor,
## or a hair under it, still finds it.
const LIFT := 1.0


## The distance from point down to the first world surface below it, no
## further than reach; INF when there is none that close. exclude takes
## bodies to look through.
static func height_below(space: PhysicsDirectSpaceState3D, point: Vector3, reach: float, exclude: Array[RID] = []) -> float:
	var ground := ground_below(space, point, reach, exclude)
	return INF if ground.is_empty() else float(ground["height"])


## The same, with the surface's normal: {"height": distance down,
## "normal": the surface's}, or empty when there is no ground that close.
static func ground_below(space: PhysicsDirectSpaceState3D, point: Vector3, reach: float, exclude: Array[RID] = []) -> Dictionary:
	if space == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * LIFT, point + Vector3.DOWN * reach, MASK, exclude)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return {}
	return {"height": maxf(0.0, point.y - (hit["position"] as Vector3).y), "normal": hit["normal"] as Vector3}
