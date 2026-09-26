class_name C4Rules
extends Resource

## The numbers the bomb is played by. The defaults are CS2's where the game
## has them (reference/cs2-systems.md, section 6); the ones marked as a
## guess are waiting on a measurement in CS2 (C1 there) and say what they
## were taken from.

## From the plant to the explosion (mp_c4timer).
@export var timer_seconds: float = 40.0
## How long the attack button is held, on the ground inside a site, before
## the bomb is down. A guess: CS:GO's arming time was 3 s, which is also
## what the community's CS2 references give; cs2-systems.md has "about
## 3.2 s" and C1 is to measure it. The first-person clip's last key press
## is at 2.17 s and its last stage at 2.47 s (equipment.md), both before 3.
@export var plant_seconds: float = 3.0
## How long a defuse takes, and with a kit (CS2's 10 and 5 seconds).
@export var defuse_seconds: float = 10.0
@export var kit_defuse_seconds: float = 5.0

## The blast before CS2's July 2026 shockwave: bomb_damage at the bomb,
## reaching radius_scale times that many units, falling off as a bell
## curve (C4.blast_damage). The map's info_map_parameters bombradius
## replaces the default (SourceEntities.bomb_radius: 700 on dust2).
@export var bomb_damage: float = 500.0
@export var radius_scale: float = 3.5

## How far from a defuser's eyes the bomb can be, and how far off their aim,
## for the use key to start a defuse. Guesses: CS2 wants you to look at the
## bomb and be next to it; these let a player standing over it and looking
## down at it defuse, and not one across the room. C1 is to measure them.
@export var defuse_reach: float = 90.0
@export var defuse_cone_degrees: float = 40.0

## CS2's bot_defer_to_human_items and bot_defer_to_human_goals, under their
## own names, at competitive's 1 (game/csgo/cfg/gamemode_competitive.cfg in
## GameTracking-CS2; the convar: "If nonzero and there is a human on the
## team, the bots will not get scenario items"). With a living human T, the
## round hands the bomb to a human and never to a bot, and a bot leaves a
## dropped bomb for them (Sid saw CS2 do so, 2026-09-26:
## playtest-2026-09-25.md issue 18).
@export var bot_defer_to_human_items: bool = true
## The same for the round's goals: with a human on the team, the bots leave
## the plant to them. Bots have no bomb goals yet (roadmap 24 is to read
## this when they plant).
@export var bot_defer_to_human_goals: bool = true

## How close a terrorist's feet have to come to a dropped bomb to pick it
## up, across and up. CS2 picks it up when the hull touches it: a hull is
## 32 across, so 16 from its middle plus the bomb's own few inches. The
## height is a crouched hull's.
@export var pickup_reach: float = 24.0
@export var pickup_height: float = 54.0
## A player who drops the bomb cannot pick it straight back up for this
## long: in CS2 the bomb is thrown clear, here it lands at their feet. A
## guess, so that dropping it does something.
@export var redrop_seconds: float = 1.0
