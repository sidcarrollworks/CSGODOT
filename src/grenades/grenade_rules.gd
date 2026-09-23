class_name GrenadeRules
extends RefCounted

## CS2's grenades as numbers: what each one is, how it is thrown, how it
## flies and what it does when it goes off.
##
## Where the game's files have a number it comes from them, through
## WeaponVData (reference/weapons/vdata.csv): each grenade's damage, reach,
## armour ratio, throw speed, price and the speed you move holding it. The
## rest is the game's code, which nobody has the source of. Those numbers
## are CS:GO's behaviour as the community has documented it (CS2 is thought
## to keep it) or the figures reference/cs2-systems.md gives, and every one
## is marked with the measurement in the roadmap that would settle it
## (G1 to G5, all Local). Nothing here is from Valve's leaked code.
##
## A grenade is named by its CS2 class name (weapon_hegrenade), as every
## item is to be (reference/systemization.md, step 1).

const HE := "weapon_hegrenade"
const FLASHBANG := "weapon_flashbang"
const SMOKE := "weapon_smokegrenade"
const MOLOTOV := "weapon_molotov"
const INCENDIARY := "weapon_incgrenade"
const DECOY := "weapon_decoy"

## All six, in the order the range cycles through them.
const ALL: Array[String] = [HE, FLASHBANG, SMOKE, MOLOTOV, INCENDIARY, DECOY]

## The layers a grenade in flight bounces off: the world (not the player
## clips, which are on MapImporter.PLAYER_CLIP_LAYER), players' hulls, and
## the map's grenade clips once the importer puts them on a layer of their
## own (it leaves them out for now: reference/systems/grenades.md).
const GRENADE_CLIP_LAYER := 32
const COLLIDE_MASK := Hitscan.WORLD_LAYER | PlayerSim.PLAYER_LAYER | GRENADE_CLIP_LAYER

# --- The throw (G1) -------------------------------------------------------

## How hard each button throws: left click all the way, right click a lob,
## both between (CS:GO's m_flThrowStrength).
const STRENGTH_LEFT := 1.0
const STRENGTH_BOTH := 0.5
const STRENGTH_RIGHT := 0.0

## The throw speed is the game's m_flThrowVelocity (750) times this, then
## times 0.3 at the weakest throw up to 1 at the strongest (CS:GO).
const THROW_SPEED_SCALE := 0.9
const THROW_POWER_MIN := 0.3
## How much of the thrower's own velocity the grenade takes (CS:GO).
const THROWER_VELOCITY_SHARE := 1.25
## A throw aims up a little: ten degrees at the horizon, none straight up
## or down (CS:GO).
const THROW_LIFT_DEGREES := 10.0
## Where it leaves the hand: this far ahead of the eyes, and up to 12 units
## lower for a lob (CS:GO).
const RELEASE_AHEAD := 22.0
const RELEASE_DROP := 12.0

# --- Flight (G1) ----------------------------------------------------------

## sv_gravity, as MovementConfig has it.
const SV_GRAVITY := 800.0
## A grenade falls at this share of sv_gravity, and keeps this share
## of its speed off each bounce, less off a player (CS:GO).
const GRAVITY_SCALE := 0.4
const ELASTICITY := 0.45
const PLAYER_ELASTICITY := 0.3
## A floor is anything facing up more than this (about 45 degrees of
## slope), and a bounce off one that leaves it slower than REST_SPEED puts
## it down (CS:GO).
const FLOOR_NORMAL_Y := 0.7
const REST_SPEED := 20.0
## The grenade's size: a box two units each way from its centre, traced as
## a sphere of that radius.
const RADIUS := 2.0

# --- Fuses (G1) -----------------------------------------------------------

## The HE and the flash go off this long after the throw.
const FUSE_SECONDS := 1.5
## The smoke and the decoy go off once they have stopped, looked at every
## this often.
const REST_CHECK_SECONDS := 0.2
## A molotov goes off in the air this long after the throw, if it has not
## met the ground by then (molotov_throw_detonate_time, CS2's convar).
const MOLOTOV_AIR_SECONDS := 2.0
## It goes off on ground no steeper than this (weapon_molotov_maxdetonateslope).
const MOLOTOV_MAX_SLOPE_DEGREES := 30.0
## Gone off in the air, its fire lands on the ground below if there is any
## this close (a guess, G1).
const MOLOTOV_AIRBURST_DROP := 128.0

# --- HE (G2) --------------------------------------------------------------

## Damage falls off from the game's m_nDamage at the centre to nothing at its
## m_flRange along a bell curve whose spread is a third of the range (CS:GO's
## documented curve; G2 measures CS2's).
const HE_FALLOFF_SIGMA_SHARE := 1.0 / 3.0
## An HE clears the smoke this close to it, which fills back in after
## SMOKE_HOLE_SECONDS (a guess, G4).
const HE_SMOKE_CLEAR_RADIUS := 128.0

# --- Flashbang (G3) -------------------------------------------------------

## The longest a flash blinds, facing it close up (the community's figure
## in reference/cs2-systems.md: about 5 s).
const FLASH_MAX_SECONDS := 4.87
## The screen fades back over the last this-many seconds of it; before that
## it is held white (a guess, G3).
const FLASH_FADE_SECONDS := 3.0
## Full strength within this distance, falling off to nothing at
## FLASH_REACH (guesses, G3).
const FLASH_FULL_WITHIN := 250.0
const FLASH_REACH := 2000.0
## How much facing matters: looking within about 37 degrees of it is all of
## it, side-on less, with your back to it FLASH_BEHIND of it (guesses, G3).
const FLASH_FACING_DOT := 0.8
const FLASH_BEHIND_DOT := -0.3
const FLASH_BEHIND := 0.2
## A kill on a player flashed past this is a blind kill
## (sv_flashed_amount_for_blind_kill).
const FLASHED_FOR_BLIND_KILL := 0.7

# --- Smoke (G4) -----------------------------------------------------------

## The cloud is cubes this size, filled out from where the grenade stopped
## through the hull, until it holds SMOKE_VOXELS or has gone SMOKE_REACH
## along the way it flowed. The number is half a sphere of 144 units'
## radius, CS:GO's, standing on open ground (a guess for CS2's, G4).
const SMOKE_VOXEL := 16.0
const SMOKE_VOXELS := 1600
const SMOKE_REACH := 400.0
## Flowing up costs more than flowing across, and down less, so the cloud
## sits on the ground as a dome and pours down steps (guesses, G4).
const SMOKE_UP_COST := 1.25
const SMOKE_DOWN_COST := 0.8
## How long it takes to bloom (the fill is spread over it) and how long it
## lasts after (reference/cs2-systems.md: 18 or 20 s, G4).
const SMOKE_BLOOM_SECONDS := 1.0
const SMOKE_SECONDS := 18.0
## A hole an HE blows fills back in after this; a round's tunnel after
## SMOKE_TUNNEL_SECONDS (guesses, G4).
const SMOKE_HOLE_SECONDS := 3.0
const SMOKE_TUNNEL_SECONDS := 0.25
## Bots see through at most this much of it (bot_max_visible_smoke_length).
const BOT_MAX_VISIBLE_SMOKE_LENGTH := 200.0

# --- Molotov and incendiary (reference/cs2-systems.md) --------------------

## Up to 16 flames, 42 units apart.
const FIRE_MOST_FLAMES := 16
const FIRE_SPACING := 42.0
## How far from where it landed the fire reaches, how long each flame
## burns, and how often a new flame spreads out (the incendiary ten times
## faster; the molotov's interval is a guess, G1).
const FIRE_REACH := {MOLOTOV: 150.0, INCENDIARY: 110.0}
const FIRE_SECONDS := {MOLOTOV: 7.0, INCENDIARY: 5.5}
const FIRE_SPREAD_SECONDS := {MOLOTOV: 0.2, INCENDIARY: 0.02}
## Anyone standing within this of a flame burns, in steps of
## FIRE_DAMAGE_STEP at the game's m_nDamage a second; the burn ramps up from
## FIRE_RAMP_FROM of it to all of it over FIRE_RAMP_SECONDS of standing in it
## (the reach and the ramp are guesses). Armour does not stop fire.
const FIRE_FLAME_RADIUS := 30.0
const FIRE_FLAME_HEIGHT := 72.0
const FIRE_DAMAGE_STEP := 0.2
const FIRE_RAMP_FROM := 0.5
const FIRE_RAMP_SECONDS := 1.0
## Fire is always the thrower's against the other side and themselves; its
## burns on their teammates are the thrower's only this long, and after it
## nobody's (inferno_friendly_fire_duration 6: the thrower answers for team
## damage only early on).
const FIRE_TEAM_CREDIT_SECONDS := 6.0

# --- Decoy (G5) -----------------------------------------------------------

## Once it stops it fires its thrower's gun in bursts for this long, then
## pops for a little damage close by; none to the thrower's side
## (ff_damage_decoy_explosion false). The bursts' lengths and gaps, and the
## pop, are guesses (G5).
const DECOY_SECONDS := 15.0
const DECOY_BURST_MOST := 5
const DECOY_GAP_LEAST := 0.5
const DECOY_GAP_MOST := 2.0
const DECOY_POP_DAMAGE := 5.0
const DECOY_POP_RADIUS := 64.0

# --- Friendly fire (reference/cs2-systems.md) -----------------------------

## In a match a grenade does this share to the thrower's side, all of it to
## the thrower. Alone on the range, everything is all of it.
const TEAM_DAMAGE_IN_MATCH := 0.85


static func is_grenade(weapon_class: String) -> bool:
	return weapon_class in ALL


## The game's own numbers for a grenade, as a WeaponData: what a hit it does
## goes by (its damage, armour ratio and how hard it tags) and what the log
## calls it.
static func weapon_data(weapon_class: String) -> WeaponData:
	var data := WeaponData.new()
	WeaponVData.apply(data, weapon_class)
	data.display_name = display_name(weapon_class)
	return data


static func damage(weapon_class: String) -> float:
	return WeaponVData.number(weapon_class, "m_nDamage")


## The HE's reach; for the rest the game's 4096, which nothing reads.
static func reach(weapon_class: String) -> float:
	return WeaponVData.number(weapon_class, "m_flRange")


static func throw_speed(weapon_class: String) -> float:
	return WeaponVData.number(weapon_class, "m_flThrowVelocity")


static func display_name(weapon_class: String) -> String:
	match weapon_class:
		HE:
			return "HE Grenade"
		FLASHBANG:
			return "Flashbang"
		SMOKE:
			return "Smoke Grenade"
		MOLOTOV:
			return "Molotov"
		INCENDIARY:
			return "Incendiary Grenade"
		DECOY:
			return "Decoy Grenade"
	return weapon_class


## An HE's damage a distance from the blast, before armour and walls: the
## game's m_nDamage at the centre, along the bell curve, nothing past its
## m_flRange.
static func he_damage_at(distance: float) -> float:
	var reach := reach(HE)
	if distance >= reach:
		return 0.0
	var sigma := reach * HE_FALLOFF_SIGMA_SHARE
	return damage(HE) * exp(-(distance * distance) / (2.0 * sigma * sigma))


## Whether it burns when it goes off.
static func is_fire(weapon_class: String) -> bool:
	return weapon_class == MOLOTOV or weapon_class == INCENDIARY


## How strong a throw the buttons make: left, right or both.
static func strength_for(left: bool, right: bool) -> float:
	if left and right:
		return STRENGTH_BOTH
	return STRENGTH_RIGHT if right else STRENGTH_LEFT
