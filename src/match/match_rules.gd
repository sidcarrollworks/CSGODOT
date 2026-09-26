class_name MatchRules
extends Resource

## The rules a match is played by: how long each part of a round lasts, how
## many rounds there are, and what a teammate's round does to you.
##
## Every default is CS2's competitive setting, from the game's own
## gamemode_competitive.cfg and convars as SteamDatabase publishes them
## (reference/cs2-systems.md, section 1). A test or a practice map shortens
## them; nothing else should.

## Before the match: everyone plays, dies and comes back, and nothing counts
## (mp_warmuptime).
@export var warmup_seconds: float = 120.0
## Warmup's clock stands still and warmup lasts until it is ended (F5,
## mp_warmup_end), as mp_warmup_pausetimer 1 has it; off in competitive.
## Practice turns it on.
@export var warmup_paused: bool = false
## At the start of each round nobody moves or fires (mp_freezetime).
@export var freeze_seconds: float = 15.0
## How long a round is played before it runs out, 1:55 (mp_roundtime_defuse
## 1.92 minutes, which the game rounds to 115 s).
@export var round_seconds: float = 115.0
## From a round's end to the next one's start (mp_round_restart_delay).
@export var round_restart_seconds: float = 7.0
## From the round before a side swap to the next one's start, in place of
## the restart delay (mp_halftime_duration).
@export var halftime_seconds: float = 15.0

## Regulation: 24 rounds, sides swapping after 12 (mp_maxrounds).
@export var max_rounds: int = 24
## A team that reaches more than half of them has won; the rest are not
## played (mp_match_can_clinch).
@export var can_clinch: bool = true
## At 12-12, overtime (mp_overtime_enable): this many rounds, sides swapping
## half way (mp_overtime_maxrounds), the first to more than half of them
## winning it.
@export var overtime: bool = true
@export var overtime_rounds: int = 6
## How many overtimes before a tie stands as a draw; 0 plays them until
## someone wins. Premier plays one: 15-15 is a draw.
@export var overtime_limit: int = 1

## A round from your own team does this share of its damage
## (ff_damage_reduction_bullets), before armour takes its part.
@export var friendly_fire_bullets: float = 0.33

## The armour a player spawns with: 0 none, 1 kevlar, 2 kevlar and a helmet
## (mp_free_armor; none in competitive).
@export_range(0, 2) var free_armor: int = 0

## Dead, how long the camera stays on your own body before it moves to a
## living teammate (spec_freeze_time).
@export var freeze_cam_seconds: float = 2.0
