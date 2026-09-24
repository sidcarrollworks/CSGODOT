class_name MoneyRules
extends Resource

## What money a match is played with: what a player starts with and may
## hold, what a round, a kill, a plant and a defuse pay, and what may be
## bought, when and where.
##
## Every default is CS2's competitive setting, from the game's own
## gamemode_competitive.cfg, or from the convar's own default where that
## file leaves it alone (SteamDatabase's GameTracking-CS2, checked
## 2026-09-23; reference/systems/economy.md lists each one). Each is named
## after its convar. A test or the test range changes them; nothing else
## should.

@export_group("Accounts")
## What every account holds at the start of a match and of each half
## (mp_startmoney).
@export var start_money: int = 800
## No account holds more (mp_maxmoney).
@export var max_money: int = 16000
## What every account holds at the start of each half of overtime
## (mp_overtime_startmoney).
@export var overtime_start_money: int = 10000
## What every account holds in warmup: the mode's cap, by the community's
## account (reference/research/round-economy.md 2.7); in no file, E2
## measures it.
@export var warmup_money: int = 16000

@export_group("Rounds")
## Each player on the side that won by killing the other side, on a map
## with a bomb (cash_team_elimination_bomb_map).
@export var win_elimination: int = 3250
## Each counter-terrorist when the round's time runs out
## (cash_team_win_by_time_running_out_bomb).
@export var win_time: int = 3250
## Each terrorist when the bomb goes off (cash_team_terrorist_win_bomb).
@export var win_bomb_exploded: int = 3500
## Each counter-terrorist when the bomb is defused
## (cash_team_win_by_defusing_bomb).
@export var win_bomb_defused: int = 3500
## The loss bonus: each player on the losing side gets this
## (cash_team_loser_bonus), and this more for each step up the loss ladder
## (cash_team_loser_bonus_consecutive_rounds).
@export var loss_bonus: int = 1400
@export var loss_bonus_step: int = 500
## How many steps the ladder has (mp_consecutive_loss_max): 1400 to 3400.
@export var loss_steps_max: int = 4
## Where each side's ladder starts, each half (mp_starting_losses): one
## step up, so the first round a side loses pays $1,900.
@export var starting_losses: int = 1
## What a won round does to the winners' ladder
## (mp_consecutive_loss_aversion): 0 takes it back to the bottom, 1 steps
## it down one, 2 holds it for the first win and steps it down from the
## second.
@export_range(0, 2) var loss_aversion: int = 1
## Each terrorist, on top of the loss bonus, when the side planted the bomb
## and lost the round (cash_team_planted_bomb_but_defused).
@export var planted_but_lost: int = 600
## Terrorists alive when the round's time runs out get no loss bonus. CS2
## has no convar for it; it is the rule as the community documents it
## (reference/systems/economy.md, E1 to check it).
@export var no_bonus_for_time_survivors: bool = true
## Whether rounds pay teams at all (mp_teamcashawards), and whether kills,
## plants and defuses pay players (mp_playercashawards).
@export var team_cash_awards: bool = true
@export var player_cash_awards: bool = true

@export_group("Players")
## A kill pays the killer the weapon's own kill award (weapons.vdata
## m_nKillAward) times this (cash_player_killed_enemy_factor).
@export var kill_award_factor: float = 1.0
## What a kill pays with anything that has no kill award of its own
## (cash_player_killed_enemy_default).
@export var kill_award_default: int = 300
## A teammate killed (cash_player_killed_teammate).
@export var team_kill: int = -300
## Planting and defusing the bomb, to whoever does it
## (cash_player_bomb_planted, cash_player_bomb_defused).
@export var bomb_planted: int = 300
@export var bomb_defused: int = 300
## Killing yourself. CS2 has no cash rule for it: its mp_suicide_penalty 1
## ("Punish players for suicides") takes score (contributionscore_suicide
## -2). The convar dump has no cash_ rule for a suicide; the one that covers
## every death, cash_player_get_killed, is 0. So 0.
@export var suicide: int = 0

@export_group("Buying")
## Seconds buying stays open after freeze time ends (mp_buytime). When the
## count starts is E2's to measure; freeze time's end is the guess.
@export var buy_seconds: float = 20.0
## Anywhere, not only in your side's buy zone (mp_buy_anywhere).
@export var buy_anywhere: bool = false
## Undoing a purchase in the buy menu while buying is open
## (sv_sellback_enabled).
@export var sellback: bool = true
## The most armour that can be bought (mp_max_armor): 0 none, 1 kevlar,
## 2 kevlar and helmet.
@export_range(0, 2) var max_armor: int = 2
## Purchases of each weapon type a player may make in a round
## (mp_weapons_allow_typecount), and of the Zeus (mp_weapons_allow_zeus);
## -1 for no limit.
@export var type_purchases: int = 5
@export var zeus_purchases: int = 5
## The helmet alone, bought over full kevlar. No file has it: it is the
## figure the community gives (E2 to measure).
@export var helmet_price: int = 350
