class_name FlashBlind
extends RefCounted

## How a flashbang blinds one player, and how that wears off: CS2 keeps it
## on the player as a duration and a peak (m_flFlashDuration,
## m_flFlashMaxAlpha), and draws the white from them. Server-side state,
## since a blinded bot must not see and a blind kill must be counted.
##
## It blinds anyone whose eyes it can see, teammates and the thrower too,
## for longer the closer they are and the more directly they face it, not
## at all from behind a wall. Smoke does not stop it (as in CS:GO). The
## figures are guesses until measured (G3): GrenadeRules.

## Simulation time it went off, how long it blinds and how white it gets
## at the most (1 all white).
var started_usec: int = 0
var duration: float = 0.0
var peak: float = 0.0
## Who threw it, and the flash's entity, for the kill feed's blind kills
## and flash assists.
var attacker: int = -1
var entityid: int = -1


## How a flash at a point blinds eyes looking along forward, or null if it
## cannot see them. exclude is left out of the line of sight (the viewer's
## own body).
static func from(
	space: PhysicsDirectSpaceState3D, flash: Vector3, eyes: Vector3, forward: Vector3,
	at_usec: int, exclude: Array[RID] = []
) -> FlashBlind:
	var query := PhysicsRayQueryParameters3D.create(flash, eyes, Hitscan.WORLD_LAYER, exclude)
	if not space.intersect_ray(query).is_empty():
		return null
	var strength := facing_share(flash, eyes, forward) * distance_share(flash.distance_to(eyes))
	if strength <= 0.0:
		return null
	var blind := FlashBlind.new()
	blind.started_usec = at_usec
	blind.duration = GrenadeRules.FLASH_MAX_SECONDS * strength
	# Only a flash seen well enough whites out the screen; one seen from the
	# side or behind leaves it grey.
	blind.peak = clampf(strength * 2.0, 0.0, 1.0)
	return blind


## How much of a flash's strength reaches eyes facing a way: all of it
## looked at, less side-on, a little behind.
static func facing_share(flash: Vector3, eyes: Vector3, forward: Vector3) -> float:
	var to_flash := flash - eyes
	if to_flash.length_squared() < 1e-6:
		return 1.0
	var dot := forward.normalized().dot(to_flash.normalized())
	if dot >= GrenadeRules.FLASH_FACING_DOT:
		return 1.0
	if dot <= GrenadeRules.FLASH_BEHIND_DOT:
		return GrenadeRules.FLASH_BEHIND
	var t := (dot - GrenadeRules.FLASH_BEHIND_DOT) / (GrenadeRules.FLASH_FACING_DOT - GrenadeRules.FLASH_BEHIND_DOT)
	return lerpf(GrenadeRules.FLASH_BEHIND, 1.0, t)


## How much of it reaches a distance away.
static func distance_share(distance: float) -> float:
	if distance <= GrenadeRules.FLASH_FULL_WITHIN:
		return 1.0
	return clampf(
		1.0 - (distance - GrenadeRules.FLASH_FULL_WITHIN) / (GrenadeRules.FLASH_REACH - GrenadeRules.FLASH_FULL_WITHIN),
		0.0, 1.0
	)


## How white it is at a simulation time, 0 to 1: held at the peak, then
## fading over the last GrenadeRules.FLASH_FADE_SECONDS (all of it for a
## short one).
func amount(now_usec: int) -> float:
	var t := float(now_usec - started_usec) / 1_000_000.0
	if t < 0.0 or t >= duration:
		return 0.0
	var fade := minf(GrenadeRules.FLASH_FADE_SECONDS, duration)
	var hold := duration - fade
	if t <= hold:
		return peak
	return peak * (1.0 - (t - hold) / fade)


func ends_usec() -> int:
	return started_usec + int(duration * 1_000_000.0)


## Of two blinds on one player, the one still to run longer wins, as a new
## flash only ever adds to being blind.
func outlasts(other: FlashBlind) -> bool:
	return other == null or ends_usec() > other.ends_usec()
