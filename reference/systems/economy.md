# Money and buying

Roadmap item 13 (the economy) and the buying half of items 12 and 14, as
built in `src/economy/`, with the checks in `tests/run_economy_checks.gd`.
It is one of the game's systems on the shared contracts
(`reference/systems/contracts.md`): it listens to game events, puts what is
bought into the buyer's `Inventory`, and never calls the round code.

## What is where

| File | What it is |
|---|---|
| `money_rules.gd` | `MoneyRules`: every number below, each named after its convar |
| `economy.gd` | `Economy`: the system. Accounts by userid, the loss ladders, the rewards, buy time, buy zones, purchases and undoing them |
| `buy_zones.gd` | `BuyZones`: each side's `func_buyzone` volumes (`BrushVolume.buy_zones`), or boxes on the range |
| `loadout.gd` | `Loadout`: the buy menu's five columns of five, CS2's default loadout |
| `buy_menu.gd` | `BuyMenu`: the menu. Reads the economy, asks it for purchases; drawing only |

A purchase is CS2's own console command, `buy ak47` (CS2's short names,
`vest`, `vesthelm`, or the class name), sent with `game.command(userid,
...)` and carried out at the start of the next tick, as CS2's server
carries out a client's; `sellback ak47` undoes one (a command this project
adds; CS2's menu undoes through its own UI). `Economy.buy` and `undo` send
them. The menu is a client, and would stay one over a network. A gun a
purchase replaces falls at the buyer's feet as a `DroppedItem`.

## CS2's numbers

From SteamDatabase's GameTracking-CS2, checked 2026-09-23:
`game/csgo/cfg/gamemode_competitive.cfg` (CFG), the convar dump
`DumpSource2/convars.txt` (CV, a convar's default where CFG leaves it alone),
`scripts/items/items_game.txt` (IG) and `reference/weapons/vdata.csv` (WV).

| Rule | Value | Where |
|---|---|---|
| Start money, each half | $800 | CFG `mp_startmoney` |
| Most an account holds | $16,000 | CFG `mp_maxmoney` |
| Each half of overtime | $10,000 | CV `mp_overtime_startmoney` |
| Win by elimination | $3,250 each | CFG `cash_team_elimination_bomb_map` |
| Win on time (CT) | $3,250 each | CFG `cash_team_win_by_time_running_out_bomb` |
| Win by the bomb going off (T) | $3,500 each | CFG `cash_team_terrorist_win_bomb` |
| Win by defusing (CT) | $3,500 each | CFG `cash_team_win_by_defusing_bomb` |
| Loss bonus | $1,400 plus $500 a step, 4 steps: $1,400 to $3,400 | CFG `cash_team_loser_bonus`, `cash_team_loser_bonus_consecutive_rounds`; CV `mp_consecutive_loss_max 4` |
| Where the ladder starts each half | one step up: a half's first loss pays $1,900 | CFG `mp_starting_losses 1` |
| A win | steps the ladder down one | CV `mp_consecutive_loss_aversion 1` |
| Ts who planted and lost | $600 each on top of the loss bonus | CFG `cash_team_planted_bomb_but_defused` |
| Kill | the weapon's own kill award times 1 (knife $1,500; SMGs $600, P90 $300; Nova, MAG-7, Sawed-Off $900; XM1014 $600; AWP and Zeus $100; the rest $300) | WV `m_nKillAward`, CFG `cash_player_killed_enemy_factor 1` |
| Kill with anything that has no award | $300 | CFG `cash_player_killed_enemy_default` |
| Team kill | -$300 | CFG `cash_player_killed_teammate` |
| Planting, defusing | $300 to whoever does it | CFG `cash_player_bomb_planted`, `cash_player_bomb_defused` |
| Buy time | 20 s | CFG `mp_buytime` |
| Where | only your side's buy zone | CFG `mp_buy_anywhere 0` |
| Undoing a purchase | yes, while buying is open | CFG `sv_sellback_enabled 1` |
| Armour for sale | kevlar and helmet | CV `mp_max_armor 2` |
| Purchases a round | 5 of each weapon type, 5 Zeus | CV `mp_weapons_allow_typecount 5`, CFG `mp_weapons_allow_zeus 5` |
| Prices | every weapon's `m_nPrice`; kevlar $650, kevlar and helmet $1,000, kit $400 | WV, IG `in game price` (through `ItemRegistry`) |
| Who buys what | T only: Glock-18, Tec-9, MAC-10, Sawed-Off, Galil AR, AK-47, SG 553, G3SG1, molotov. CT only: P2000, USP-S, Five-SeveN, MP9, MAG-7, FAMAS, M4A4, M4A1-S, AUG, SCAR-20, incendiary, kit | IG `used_by_classes` (through `ItemRegistry`) |

The default loadout, the menu's columns (IG `flexible_loadout_slot` and
`flexible_loadout_default`; T / CT where they differ):

| | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| 1 Pistols | Glock-18 / P2000 | Dual Berettas | P250 | Tec-9 / Five-SeveN | Desert Eagle |
| 2 Mid-Tier | Nova | XM1014 | MP5-SD | P90 | MAC-10 / MP9 |
| 3 Rifles | Galil AR / FAMAS | AK-47 / M4A1-S | SSG 08 | SG 553 / AUG | AWP |
| 4 Equipment | Kevlar | Kevlar + Helmet | Zeus x27 | - / Defuse Kit | |
| 5 Grenades | Flashbang | Smoke | HE | Molotov / Incendiary | Decoy |

## Guesses, and what measures them

- **The loss ladder's arithmetic** is one reading of the convars: a side's
  place starts at 1, a loss pays $1,400 + $500 x place and then moves it up
  one (to 4 at most), a win moves it down one. So a side that wins the
  pistol round and loses the next is paid $1,400, and a side that loses
  both is paid $1,900 then $2,400. That matches what CS2 players report;
  no file states it.
- **Ts alive when time runs out get no loss bonus.** The community's rule,
  not in any file (`MoneyRules.no_bonus_for_time_survivors`). Their side
  still moves up the ladder.
- **A suicide** costs money in CS2 (CV `mp_suicide_penalty 1`), but no file
  says how much: $0 here until measured.
- **The helmet alone**, over full kevlar: $350, the community's figure.
  Kevlar and helmet bought with a helmet and worn kevlar costs the vest's
  $650.
- **When buy time counts from**: the end of freeze time, so buying is open
  for all of freeze time and 20 s after.
- **Warmup**: buying is open for as long as warmup lasts, and accounts hold
  $800. CS2's warmup money is not in the files.
- **The menu's key order** (1 pistols to 5 grenades) follows the loadout's
  order; undoing is a right-click. Both by eye; CS2's own menu decides.
- Not built: the short-handed bonus (CFG `cash_team_bonus_shorthanded 1000`,
  paid after a team has been short for `mp_shorthanded_cash_bonus_round_delay
  2` rounds; bots fill every place, so no team is short) and CV
  `cash_team_per_dead_enemy 50` (no file says what it pays; CFG leaves it
  alone).

Local tasks (Sid's machine), added to `reference/cs2-systems.md`'s E1 and E2:

- **E1.** On a local server with `mp_logmoney 1`: a suicide's cost; that
  Ts who survive a round lost on time get nothing; what a pistol-round
  winner that loses round 2 is paid ($1,400 expected); and what
  `cash_team_per_dead_enemy` pays.
- **E2.** When buy time counts from, the helmet's own price, and the
  menu's key order.

## What the GameWorld needs to do to wire it in

None of this is in the files the local agent owns (`player_sim.gd`,
`bot.gd`, `match_state.gd`, `de_dust2.gd`). Checked against the GameWorld
(PR #50): the two combine without a conflict and every check passes. Once
the world holds a `GameSystems` and steps it in `GameWorld.end_tick`, after
the match:

1. Add the economy to it:
   `game.add_system(Economy.new(MoneyRules.new(), BuyZones.from_volumes(BrushVolume.buy_zones(entities, root))))`,
   with `economy.match_rules` set to the match's `MatchRules`. It reads the
   tick's time from the `SimTick` it is handed, so it runs on the world's
   count like everything else.
2. `MatchState` sends, as the contract lists: `begin_new_match` when warmup
   ends, `round_start` and `round_freeze_end` each round, `round_end` with
   `GameEvents.round_end_reason`, and `announce_phase_end` at every side
   swap, after the round that ends the half has been paid. Money needs
   nothing else from it.
3. `MatchState._arm` stops handing a fresh player a rifle: a fresh player
   gets `Inventory.give_starting_items(side)`, and a survivor keeps what
   they had, including what they bought.
4. Deaths go through `DamageInfo.deal` (it sends `player_death` with the
   weapon's class), and the bomb sends `bomb_planted` and `bomb_defused`.
5. On dust2, `BuyMenu` goes in the HUD's layer with `economy` and your
   `userid` set (see `maps/test_range/test_range.gd`), and B opens it.
6. Bots buying (roadmap item 24) sends the same `buy` command.

On the test range this is done already (`maps/test_range/range_shop.gd`):
the economy is a system in the range's `game`, with a buy zone round the
spawn, $16,000 (O fills it again) and buying that never closes, and until
the player carries their inventory, a gun bought is put in their hands.
