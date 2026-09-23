class_name SmokeVoxels
extends RefCounted

## A smoke's cloud: cubes of smoke filled out from where the grenade stopped,
## flowing through the hull round walls and through doors, as CS2's smokes
## do. The server's state, and all that sight asks about; whatever draws
## the cloud reads the cubes.
##
## The fill is a search outward from the landing point, nearest first,
## where near is the distance from the landing point (counting going up as
## further and going down as nearer, so the cloud sits on the ground as a
## dome and pours down steps) plus a share of however far the smoke had to
## go round to get there, and each cube's is nudged by the smoke's seed, as
## CS2's m_nRandomSeed shapes its cloud the same for everyone. Going by the
## straight distance rather than the steps between cubes keeps the cloud
## round rather than a diamond. A cube is reached from its neighbour
## only if a trace between their centres meets no wall, or only walls the
## game lets smoke through (SurfaceProperties' smoke_through: chain-link,
## metal railings). It stops at GrenadeRules.SMOKE_VOXELS cubes, or where
## the way has flowed SMOKE_REACH, and it is spread over the bloom: a share
## of the cubes each tick, so the traces are spread too.
##
## A cube can be cleared for a while: an HE blows a hole that fills back in,
## a round a thin tunnel that closes almost at once.

## The grid: cube (0, 0, 0) sits on the floor under where the smoke landed.
var anchor := Vector3.ZERO
var seed: int = 0
## Every cube filled so far, by grid position, to the order it was filled
## in (the view grows the cloud in that order).
var filled := {}
## Cubes cleared until a simulation time, by grid position.
var cleared_until := {}
## The box every filled cube is inside, for a line of sight to be ruled
## out without looking at cubes.
var bounds := AABB()

## The search's frontier: [priority, order, key, path] in a binary heap,
## and the shortest way found to each cube.
var _heap: Array = []
var _best := {}
var _order: int = 0
## How many traces the fill has made, for the performance rules' count.
var traces: int = 0

## How much of a way round beyond what an open path takes counts.
const DETOUR_SHARE := 0.5

const NEIGHBOURS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1),
	Vector3i(0, 0, -1), Vector3i(0, 1, 0), Vector3i(0, -1, 0),
]


## A cloud growing from a grenade lying at rest_position (its centre, a
## sphere's radius off the floor).
func _init(rest_position: Vector3 = Vector3.ZERO, p_seed: int = 0) -> void:
	anchor = rest_position + Vector3.UP * (GrenadeRules.SMOKE_VOXEL * 0.5 - GrenadeRules.RADIUS)
	seed = p_seed
	_push(0.0, Vector3i.ZERO, 0.0)
	_best[Vector3i.ZERO] = 0.0


func centre_of(key: Vector3i) -> Vector3:
	return anchor + Vector3(key) * GrenadeRules.SMOKE_VOXEL


func key_of(point: Vector3) -> Vector3i:
	var local := (point - anchor) / GrenadeRules.SMOKE_VOXEL
	return Vector3i(roundi(local.x), roundi(local.y), roundi(local.z))


## Whether there is nothing left to fill.
func full() -> bool:
	return filled.size() >= GrenadeRules.SMOKE_VOXELS or _heap.is_empty()


## How many cubes a tick fills, so the whole cloud takes the bloom.
static func per_tick() -> int:
	return ceili(float(GrenadeRules.SMOKE_VOXELS) / maxf(float(SimClock.ticks_in(GrenadeRules.SMOKE_BLOOM_SECONDS)), 1.0))


## Fills up to count more cubes, cheapest first. Returns how many it filled.
func grow(space: PhysicsDirectSpaceState3D, count: int) -> int:
	var added := 0
	while added < count and not full():
		var top: Array = _pop()
		var key: Vector3i = top[2]
		var path: float = top[3]
		if filled.has(key) or path > float(_best.get(key, INF)) + 1e-6:
			continue
		filled[key] = filled.size()
		var box := AABB(centre_of(key) - Vector3.ONE * GrenadeRules.SMOKE_VOXEL * 0.5, Vector3.ONE * GrenadeRules.SMOKE_VOXEL)
		bounds = box if filled.size() == 1 else bounds.merge(box)
		added += 1
		for step in NEIGHBOURS:
			var next := key + step
			if filled.has(next):
				continue
			var next_path := path + _step_cost(step)
			if next_path > GrenadeRules.SMOKE_REACH or next_path >= float(_best.get(next, INF)):
				continue
			if not _open(space, centre_of(key), centre_of(next)):
				continue
			_best[next] = next_path
			_push(_priority(next, next_path), next, next_path)
	return added


## Whether smoke fills a point now: a filled cube that is not cleared.
func contains(point: Vector3, now_usec: int) -> bool:
	return _thick(key_of(point), now_usec)


func _thick(key: Vector3i, now_usec: int) -> bool:
	return filled.has(key) and int(cleared_until.get(key, 0)) <= now_usec


## How much of the line from one point to another is in smoke, in units:
## the line walked in steps of half a cube.
func length_through(from: Vector3, to: Vector3, now_usec: int) -> float:
	if filled.is_empty():
		return 0.0
	var direction := to - from
	var length := direction.length()
	if length < 1e-3:
		return GrenadeRules.SMOKE_VOXEL * 0.5 if contains(from, now_usec) else 0.0
	# Only the stretch of it inside the cloud's box is looked at.
	var inside := _clip(from, direction / length, length)
	if inside.is_empty():
		return 0.0
	var step := GrenadeRules.SMOKE_VOXEL * 0.5
	var through := 0.0
	var at: float = inside[0]
	while at <= inside[1]:
		if contains(from + direction / length * at, now_usec):
			through += step
		at += step
	return minf(through, length)


## Clears every cube within radius of a point until a time: an HE's hole.
func clear_sphere(centre: Vector3, radius: float, until_usec: int) -> int:
	var cleared := 0
	for key: Vector3i in filled:
		if centre_of(key).distance_to(centre) <= radius:
			cleared_until[key] = maxi(int(cleared_until.get(key, 0)), until_usec)
			cleared += 1
	return cleared


## Clears the cubes a line goes through until a time: a round's tunnel.
func clear_line(from: Vector3, to: Vector3, until_usec: int) -> int:
	var direction := to - from
	var length := direction.length()
	if filled.is_empty() or length < 1e-3:
		return 0
	var inside := _clip(from, direction / length, length)
	if inside.is_empty():
		return 0
	var cleared := 0
	var at: float = inside[0]
	while at <= inside[1]:
		var key := key_of(from + direction / length * at)
		if filled.has(key) and int(cleared_until.get(key, 0)) < until_usec:
			cleared_until[key] = until_usec
			cleared += 1
		at += GrenadeRules.SMOKE_VOXEL * 0.5
	return cleared


## The cubes that are thick now, as their centres, in the order they
## filled: what the view draws.
func thick_centres(now_usec: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for key: Vector3i in filled:
		if _thick(key, now_usec):
			out.append(centre_of(key))
	return out


## The stretch [enter, leave] of a line (from, unit direction, length) inside
## the cloud's box, or empty if it misses.
func _clip(from: Vector3, unit: Vector3, length: float) -> Array:
	var near := 0.0
	var far := length
	for axis in 3:
		var origin := from[axis]
		var lo := bounds.position[axis]
		var hi := bounds.end[axis]
		if absf(unit[axis]) < 1e-9:
			if origin < lo or origin > hi:
				return []
			continue
		var t0 := (lo - origin) / unit[axis]
		var t1 := (hi - origin) / unit[axis]
		if t0 > t1:
			var swap := t0
			t0 = t1
			t1 = swap
		near = maxf(near, t0)
		far = minf(far, t1)
		if near > far:
			return []
	return [near, far]


## How far flowing one cube that way goes.
static func _step_cost(step: Vector3i) -> float:
	if step.y > 0:
		return GrenadeRules.SMOKE_VOXEL * GrenadeRules.SMOKE_UP_COST
	if step.y < 0:
		return GrenadeRules.SMOKE_VOXEL * GrenadeRules.SMOKE_DOWN_COST
	return GrenadeRules.SMOKE_VOXEL


## How soon a cube fills: its straight distance from the landing point, up
## counting more and down less, plus a share of the way round beyond that,
## nudged by the seed so no two clouds are quite the same shape. The steps
## between cubes are at most 1.7 times the straight distance in the open,
## so the share taken of the difference is small, and a cloud through a
## door still fills what is behind the wall later than what is in front.
func _priority(key: Vector3i, path: float) -> float:
	var offset := Vector3(key) * GrenadeRules.SMOKE_VOXEL
	offset.y *= GrenadeRules.SMOKE_UP_COST if offset.y > 0.0 else GrenadeRules.SMOKE_DOWN_COST
	var straight := offset.length()
	var nudge := float(hash([seed, key]) % 1000) / 1000.0
	return (straight + DETOUR_SHARE * maxf(path - straight * 1.75, 0.0)) * (0.95 + 0.1 * nudge)


## Whether smoke gets from one cube's centre to the next: no wall between,
## or only walls it passes through.
func _open(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var start := from
	var along := (to - from).normalized()
	for i in 4:
		traces += 1
		var query := PhysicsRayQueryParameters3D.create(start, to, Hitscan.WORLD_LAYER)
		query.hit_from_inside = true
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return true
		var surface := Penetration.surface_for(Hitscan._surface_name(hit))
		if SurfaceProperties.text(surface, "smoke_through") != "true":
			return false
		start = (hit["position"] as Vector3) + along * 0.5
	return false


func _push(priority: float, key: Vector3i, path: float) -> void:
	_heap.append([priority, _order, key, path])
	_order += 1
	var i := _heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if not _less(_heap[i], _heap[parent]):
			break
		var swap = _heap[i]
		_heap[i] = _heap[parent]
		_heap[parent] = swap
		i = parent


func _pop() -> Array:
	var top: Array = _heap[0]
	var last: Array = _heap.pop_back()
	if not _heap.is_empty():
		_heap[0] = last
		var i := 0
		while true:
			var smallest := i
			for child in [2 * i + 1, 2 * i + 2]:
				if child < _heap.size() and _less(_heap[child], _heap[smallest]):
					smallest = child
			if smallest == i:
				break
			var swap = _heap[i]
			_heap[i] = _heap[smallest]
			_heap[smallest] = swap
			i = smallest
	return top


static func _less(a: Array, b: Array) -> bool:
	return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1])
