class_name WeaponData
extends Resource

## Everything that decides how a weapon behaves.
##
## IMPORTANT: none of these numbers have been measured against CS2. They come
## from published community figures, which are close but not authoritative, and
## the values that matter most for feel (recoil, inaccuracy) are not published
## at all in a form anyone can copy.
##
## The weapon tuning data in CS2 lives in scripts/weapons.vdata_c and no
## published artifact carries its values, so this cannot be extracted and has
## to be measured:
## https://github.com/CS2OpenDev/CS2OpenDev-SchemaTracker/issues/16
##
## reference/spray_patterns/README.md says how to do the measuring.

@export var display_name: String = ""

# --- Damage ---------------------------------------------------------------

## Damage to an unarmoured chest at point blank.
@export var base_damage: float = 36.0

## Fraction of damage that gets through armour.
@export_range(0.0, 1.0) var armor_penetration: float = 0.775

## Per-hitbox multipliers, applied to base_damage.
@export var head_multiplier: float = 4.0
@export var chest_multiplier: float = 1.0
@export var stomach_multiplier: float = 1.25
@export var leg_multiplier: float = 0.75

## Damage falls off by this factor every falloff_distance units.
@export var range_modifier: float = 0.98
@export var falloff_distance: float = 500.0

## Beyond this the bullet stops entirely.
@export var max_range: float = 8192.0

# --- Rate of fire ---------------------------------------------------------

## Seconds between shots. 600 RPM is 0.1.
@export var cycle_time: float = 0.1

@export var magazine_size: int = 30
@export var reserve_ammo: int = 90

## How long a reload takes.
@export var reload_time: float = 2.5

# --- Movement -------------------------------------------------------------

## Top running speed while holding this weapon, in units per second. The knife
## is 250; rifles are slower.
@export var max_player_speed: float = 215.0

# --- Recoil ---------------------------------------------------------------

## Per-shot aim offsets in degrees, indexed by shot number. This is the spray
## pattern, and it is the single most recognisable thing about a CS weapon.
##
## Loaded from reference/spray_patterns/<name>.csv. The file shipped with the
## project is a placeholder generated from a crude model, NOT the real
## pattern. See that directory's README.
@export var recoil_pattern: PackedVector2Array = PackedVector2Array()

## How fast accumulated recoil decays once you stop firing, in pattern indices
## per second. CS returns your aim over a short window rather than instantly.
@export var recoil_recovery_rate: float = 10.0

## How much of the recoil offset is applied to the view rather than only to
## where the bullets go. At 1.0 the crosshair climbs with the spray, which is
## what CS does.
@export_range(0.0, 1.0) var recoil_view_fraction: float = 1.0

# --- Inaccuracy -----------------------------------------------------------

## Cone half-angle in degrees added to every shot, by player state. Standing
## still and not firing should be very close to zero for a rifle; everything
## else opens it up. These are the numbers that make spraying while running
## useless, so they matter as much as the pattern.
@export var inaccuracy_standing: float = 0.02
@export var inaccuracy_crouching: float = 0.015
@export var inaccuracy_moving: float = 0.9
@export var inaccuracy_jumping: float = 4.0

## Added per shot while firing, and how fast it decays, in degrees.
@export var inaccuracy_per_shot: float = 0.12
@export var inaccuracy_recovery_rate: float = 1.4

## Speed below which movement inaccuracy does not apply. CS lets you walk
## slowly without penalty, which is why counter-strafing matters.
@export var inaccuracy_speed_threshold: float = 55.0


## Damage at a given distance, before armour.
func damage_at(distance: float) -> float:
	return base_damage * pow(range_modifier, distance / falloff_distance)


## Multiplier for a named hitbox.
func hitbox_multiplier(hitbox: StringName) -> float:
	match hitbox:
		&"head": return head_multiplier
		&"chest": return chest_multiplier
		&"stomach": return stomach_multiplier
		&"leg": return leg_multiplier
		_: return chest_multiplier
