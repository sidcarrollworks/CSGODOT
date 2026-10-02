class_name UseSearch
extends RefCounted

## What E is on: the one thing a player's E takes, uses or asks of, among
## boxes in the world (a gun on the ground, the dropped bomb, a bot
## carrying it). Pure geometry: whoever asks passes the boxes, and a
## Callable that says whether the world lies between two points.
##
## Source's own use search, CBasePlayer::FindUseEntity in Source SDK 2013's
## game/shared/baseplayer_shared.cpp (read as the spec, not copied). CS2
## keeps its radius as the convar player_use_radius, 80 (SteamDatabase's
## DumpSource2 convars.txt), so the search is taken to be the same; the
## rest of CS2's search is in no file (measure it against CS2: a Local
## check in issue 3 of reference/playtest-2026-09-25.md). In order:
##
## 1. A ray along the aim: the box it hits first is taken if it is within
##    the radius. The radius is measured across from the eyes, and up or
##    down only to the nearest of the player's own height (feet to the top
##    of the hull), so a gun on the floor is taken from 80 units across,
##    about 102 from standing eyes. Far away the aim must be on the item
##    itself: a Glock is 8 units long.
## 2. Seven boxes 32 units wide swept 72 units from the eyes, turned down
##    from the aim by 45, 30, 20, 15 and 10 degrees and up by 10 and 15,
##    toward the player's view up. The last of them to find a box in the
##    radius is the guess. Near the feet this finds an item the aim passes
##    well over.
## 3. Everything whose nearest point is within the radius of the eyes and
##    within acos(0.8), 36.9 degrees, of the aim: the one whose nearest
##    point lies closest to the aim's line wins over the guess.
##
## So the tolerance is a distance from the aim, not an angle: up close an
## item far off the crosshair is taken, far away only one under it (Sid's
## playtest of 2026-09-30). Each step checks the world between the eyes
## and what it found with the Callable; a swept box is checked by a ray to
## its centre, not swept against the world itself, and it is swept against
## each box grown by its half width in the box's own axes.

## player_use_radius.
const RADIUS := 80.0
## The aim's ray, and the swept boxes' length and half width.
const RAY_LENGTH := 1024.0
const SWEEP_LENGTH := 72.0
const SWEEP_HALF := 16.0
## tan of the swept boxes' turns off the aim, down first: 45, 30, 20, 15,
## 10, then up by 10 and 15 degrees.
const SWEEP_TANGENTS: Array[float] = [1.0, 0.57735026919, 0.3639702342, 0.267949192431, 0.1763269807, -0.1763269807, -0.267949192431]
## How near the aim the radius search looks: the cosine, 36.9 degrees.
const LEAST_DOT := 0.8


## A box to search: where it is and its bounds in its own space.
class Target:
	extends RefCounted
	var body := Transform3D.IDENTITY
	var box := AABB()

	func _init(p_body := Transform3D.IDENTITY, p_box := AABB()) -> void:
		body = p_body
		box = p_box


## The index of the target E is on, or -1. eyes and aim are the player's;
## feet and height span their hull, which the radius is measured against up
## and down. clear(from, to) says the world leaves the way open; left
## invalid, nothing is in the way.
static func find(eyes: Vector3, aim: Vector3, feet: Vector3, height: float, targets: Array, clear := Callable(), radius := RADIUS) -> int:
	if targets.is_empty():
		return -1
	var forward := aim.normalized()
	# 1. The aim's ray: the first box it hits, if in reach.
	var hit := _first_hit(eyes, forward, RAY_LENGTH, targets, 0.0)
	if hit[0] >= 0:
		var at: Vector3 = eyes + forward * float(hit[1])
		if _reach(at - eyes, at.y, feet.y, height) < radius and _open(clear, eyes, at):
			return hit[0]
	# 2. The swept boxes, the last one to find something standing.
	var up := _view_up(forward)
	var nearest := -1
	for tangent in SWEEP_TANGENTS:
		var way := (forward - up * tangent).normalized()
		var swept := _first_hit(eyes, way, SWEEP_LENGTH, targets, SWEEP_HALF)
		if swept[0] < 0:
			continue
		var at: Vector3 = eyes + way * float(swept[1])
		if _reach(at - eyes, at.y, feet.y, height) < radius and _open(clear, eyes, at):
			nearest = swept[0]
	# 3. The radius: the nearest to the aim's line within the cone.
	var nearest_off := INF
	if nearest >= 0:
		nearest_off = _off_line(_nearest_point(targets[nearest], eyes), eyes, forward)
	for i in targets.size():
		var point := _nearest_point(targets[i], eyes)
		var to_point := point - eyes
		var distance := to_point.length()
		if distance > radius:
			continue
		if distance > 1e-4 and forward.dot(to_point / distance) < LEAST_DOT:
			continue
		var off := _off_line(point, eyes, forward)
		if off < nearest_off and _open(clear, eyes, point):
			nearest = i
			nearest_off = off
	return nearest


## Source's distance for reach: across as it is, up or down only past the
## player's own height.
static func _reach(delta: Vector3, y: float, low: float, height: float) -> float:
	var outside := 0.0
	if y < low:
		outside = low - y
	elif y > low + height:
		outside = y - low - height
	return Vector3(delta.x, outside, delta.z).length()


## The target a ray from origin along way first meets within length, each
## box grown by grow, and how far along: [index, distance], index -1 if none.
static func _first_hit(origin: Vector3, way: Vector3, length: float, targets: Array, grow: float) -> Array:
	var best := -1
	var best_t := INF
	for i in targets.size():
		var target: Target = targets[i]
		var t := _ray_box(origin, way, length, target.body, target.box.grow(grow) if grow > 0.0 else target.box)
		if t >= 0.0 and t < best_t:
			best = i
			best_t = t
	return [best, best_t]


## Where a ray first enters a box placed at body, 0 if it starts inside,
## -1 if it misses within length.
static func _ray_box(origin: Vector3, way: Vector3, length: float, body: Transform3D, box: AABB) -> float:
	var inverse := body.affine_inverse()
	var o := inverse * origin
	var d := inverse.basis * way
	var enter := 0.0
	var leave := length
	for axis in 3:
		var low := box.position[axis]
		var high := box.end[axis]
		if absf(d[axis]) < 1e-9:
			if o[axis] < low or o[axis] > high:
				return -1.0
			continue
		var t0 := (low - o[axis]) / d[axis]
		var t1 := (high - o[axis]) / d[axis]
		if t0 > t1:
			var swap := t0
			t0 = t1
			t1 = swap
		enter = maxf(enter, t0)
		leave = minf(leave, t1)
		if enter > leave:
			return -1.0
	return enter


## The point of a target's box nearest to point.
static func _nearest_point(target: Target, point: Vector3) -> Vector3:
	var local := target.body.affine_inverse() * point
	var box := target.box
	return target.body * local.clamp(box.position, box.end)


## How far a point lies from the aim's line.
static func _off_line(point: Vector3, origin: Vector3, forward: Vector3) -> float:
	var to_point := point - origin
	return (to_point - forward * to_point.dot(forward)).length()


## The view's up: square to the aim, toward the sky.
static func _view_up(forward: Vector3) -> Vector3:
	var right := Vector3(-forward.z, 0.0, forward.x)
	if right.length_squared() < 1e-8:
		return Vector3.FORWARD if forward.y > 0.0 else Vector3.BACK
	return right.normalized().cross(forward).normalized()


static func _open(clear: Callable, from: Vector3, to: Vector3) -> bool:
	return not clear.is_valid() or bool(clear.call(from, to))
