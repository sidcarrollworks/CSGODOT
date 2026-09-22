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
## Loaded from reference/spray_patterns/<name>.csv, which is read off a CS2
## spray plot. The shape is measured; the overall size is an estimate, and
## recoil_scale below is the one knob for correcting it.
@export var recoil_pattern: PackedVector2Array = PackedVector2Array()

## Multiplies every entry in the pattern.
##
## The plots the patterns were read from carry no angular scale, so the size
## of the spray is the one part of it that was not measured. This exists so
## that correcting it is one number against a reference spray, rather than
## thirty rows edited by hand. See reference/spray_patterns/README.md.
@export var recoil_scale: float = 1.0


## How long the trigger has to be off before the spray starts from the top
## again, in seconds.
##
## This is deliberately a time and not a test on how far the view has
## recovered. The first entry of a pattern is (0, 0) by definition, so the
## accumulated punch after shot one is zero, and a recovery test would decide
## the spray had finished before it had started. That bug made every shot
## shot number one and flattened the pattern entirely.
@export var recoil_reset_time: float = 0.4

# --- View punch -----------------------------------------------------------
#
# The view kick and the bullet trajectory are two different things, and this
# is the single most misunderstood part of how CS shoots. The bullets follow
# the spray pattern exactly. The view is given a smaller, springy nudge that
# only suggests the pattern. You cannot read your own recoil off the screen;
# you learn the pattern and pull against it.
#
# Gluing the two together, which is what this used to do, produces a view
# that snaps to each bullet and sags between shots. That is not what CS looks
# like and it is not what CS plays like.

## How much of the pattern the view is kicked by, against the full amount the
## bullets move. Well under 1.0: the crosshair moves noticeably less than the
## spray.
##
## Tuned by eye against CS2 rather than measured, so it is a starting point.
@export_range(0.0, 1.0) var recoil_view_fraction: float = 0.45

## How hard a shot kicks the view, as a multiplier on the impulse given to the
## punch velocity. Source's ViewPunch adds to the punch VELOCITY rather than
## to the angle, scaled by 20, which is why the view rises into a kick instead
## of teleporting to it.
@export var punch_impulse_scale: float = 20.0

## The spring that pulls the view back to where the player is actually
## pointing, and the damping that stops it oscillating.
##
## This is Source's DecayPunchAngle: an angle with its own velocity, a
## viscous damping term and a torsional spring toward zero. The structure is
## Source's; these two constants are from memory of the SDK and were not
## verifiable from here, so treat them as tunables rather than as facts.
@export var punch_damping: float = 9.0
@export var punch_spring: float = 65.0

## How much of the view punch the weapon model is moved by, on top of the
## camera. CS exposes this as viewmodel_recoil. Purely cosmetic: it moves the
## gun in your hands and changes nothing about aim or bullets.
@export_range(0.0, 4.0) var viewmodel_recoil: float = 1.0

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


## The pattern offset for a shot, scaled, holding the last entry once the
## pattern runs out. CS patterns cover the magazine; anything past the end
## should not move.
func recoil_offset(shot_index: int) -> Vector2:
	return RecoilPattern.offset_for(recoil_pattern, shot_index) * recoil_scale


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
