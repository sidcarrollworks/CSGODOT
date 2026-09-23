class_name FireSpread
extends RefCounted

## A molotov's or an incendiary's fire: flames spreading over the ground
## from where it broke, then all going out together. The server's state;
## what burns whom (GrenadeSystem) and what draws the fire read the flames.
##
## Each new flame grows off one already burning, a flame's spacing away in a
## direction the fire's seed picks, onto ground no steeper than a floor,
## with no wall between the two and no flame there already, never further
## from where the fire started than its reach, and never into smoke. The
## incendiary spreads ten times faster and not as far, and burns shorter
## (GrenadeRules).

## What threw it: GrenadeRules.MOLOTOV or INCENDIARY.
var weapon_class: String = ""
var origin := Vector3.ZERO
var seed: int = 0
## Simulation time it caught.
var started_usec: int = 0
## Each flame's place on the ground, in the order they caught.
var flames := PackedVector3Array()
## Put out by smoke before its time.
var extinguished: bool = false

var _attempts: int = 0
var _next_spread_usec: int = 0
## How many traces it has made, for the performance rules' count.
var traces: int = 0

## A spread gives up on a flame after this many tries, until the next.
const TRIES_PER_SPREAD := 6


func _init(p_weapon_class: String = GrenadeRules.MOLOTOV, ground: Vector3 = Vector3.ZERO, at_usec: int = 0, p_seed: int = 0) -> void:
	weapon_class = p_weapon_class
	origin = ground
	started_usec = at_usec
	seed = p_seed
	flames.append(ground)
	_next_spread_usec = at_usec + _spread_usec()


## Whether it has burned out, or been put out.
func out(now_usec: int) -> bool:
	return extinguished or now_usec >= ends_usec()


func ends_usec() -> int:
	return started_usec + int(float(GrenadeRules.FIRE_SECONDS[weapon_class]) * 1_000_000.0)


## Spreads it as far as it gets by now_usec. might_spread(point) says
## whether a flame may go there (not in smoke); true where not given.
func spread(space: PhysicsDirectSpaceState3D, now_usec: int, might_spread: Callable = Callable()) -> int:
	var added := 0
	while now_usec >= _next_spread_usec and flames.size() < GrenadeRules.FIRE_MOST_FLAMES and not out(now_usec):
		_next_spread_usec += _spread_usec()
		for i in TRIES_PER_SPREAD:
			var place := _try_place(space)
			if place.is_empty():
				continue
			var at: Vector3 = place["position"]
			if might_spread.is_valid() and not bool(might_spread.call(at)):
				continue
			flames.append(at)
			added += 1
			break
	return added


## Whether a point stands in the fire: within a flame's reach across and
## no higher than a flame is tall.
func burns(point: Vector3) -> bool:
	for flame in flames:
		var across := Vector2(point.x - flame.x, point.z - flame.z).length()
		if across <= GrenadeRules.FIRE_FLAME_RADIUS and point.y >= flame.y - 16.0 \
				and point.y <= flame.y + GrenadeRules.FIRE_FLAME_HEIGHT:
			return true
	return false


## Puts out every flame inside smoke (contains(point) says which), and the
## fire with them if none is left. Returns how many went out.
func put_out(contains: Callable) -> int:
	var kept := PackedVector3Array()
	for flame in flames:
		if not bool(contains.call(flame)):
			kept.append(flame)
	var gone := flames.size() - kept.size()
	flames = kept
	if flames.is_empty():
		extinguished = true
	return gone


func _spread_usec() -> int:
	return int(float(GrenadeRules.FIRE_SPREAD_SECONDS[weapon_class]) * 1_000_000.0)


## One try at a new flame: a flame to grow from and a way to grow, both from
## the seed, then the ground there. Empty if it will not do.
func _try_place(space: PhysicsDirectSpaceState3D) -> Dictionary:
	_attempts += 1
	var pick := hash([seed, _attempts])
	var parent := flames[pick % flames.size()]
	var angle := float((pick >> 8) % 3600) / 3600.0 * TAU
	var toward := parent + Vector3(cos(angle), 0.0, sin(angle)) * GrenadeRules.FIRE_SPACING
	var reach: float = GrenadeRules.FIRE_REACH[weapon_class]
	if Vector2(toward.x - origin.x, toward.z - origin.z).length() > reach:
		return {}
	# No wall between the flame and the new one, a little off the ground.
	var lift := Vector3.UP * 8.0
	traces += 1
	var wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(parent + lift, toward + lift, Hitscan.WORLD_LAYER))
	if not wall.is_empty():
		return {}
	# Ground under it, facing up enough to be a floor.
	traces += 1
	var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		toward + Vector3.UP * 32.0, toward + Vector3.DOWN * 64.0, Hitscan.WORLD_LAYER
	))
	if ground.is_empty() or (ground["normal"] as Vector3).y < GrenadeRules.FLOOR_NORMAL_Y:
		return {}
	var at: Vector3 = ground["position"]
	for flame in flames:
		if flame.distance_to(at) < GrenadeRules.FIRE_SPACING * 0.75:
			return {}
	return {"position": at}
