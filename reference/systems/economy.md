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
| A suicide | $0: CS2's penalty for one is score, not money | CV `mp_suicide_penalty 1` ("Punish players for suicides"), `contributionscore_suicide -2`; no `cash_` convar for it, and `cash_player_get_killed`, for any death, is 0 |
| A death credited to no one (the bomb's blast, a teammate burning after a fire's first 6 s) | $0, and not a suicide | no `cash_` convar for it |
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
| 4 Equipment | Kevlar | Kevlar & Helmet | Zeus x27 | - / Defuse Kit | |
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
- **A death credited to no one moves no money.** No convar pays or charges
  for it, which is all the files say; the bomb thread credits a blast death
  to no one, as CS2's kill feed shows it (#49).
- **The helmet alone**, over full kevlar: $350, the community's figure.
  Kevlar and helmet bought with a helmet and worn kevlar costs the vest's
  $650.
- **When buy time counts from**: the end of freeze time, so buying is open
  for all of freeze time and 20 s after.
- **Warmup**: buying is open for as long as warmup lasts, and accounts hold
  $16,000 (`MoneyRules.warmup_money`, set on `round_announce_warmup`), the
  community's figure; CS2's warmup money is not in the files (E2). The
  match's money starts at `begin_new_match`, when warmup ends. CS2's
  offline match has no warmup at all (`mp_warmup_offline_enabled false`,
  `reference/research/audio-round.md` 1.2); dust2 keeps its 120 s
  (`warmup_seconds`, 0 for CS2's way) for trying things out.
- **Sounds**: buying makes none here yet. CS2's buyer hears the menu's own
  (`buymenu_purchase`, `buymenu_failure`), and others hear armour put on
  within 1000 units (`reference/cs2-systems.md` B2 has them all, and the
  Local check that settles the rest).
- **Half time's money comes at the next round's start.** The half is
  announced as its last round ends (`announce_phase_end`), and the money
  and the ladders go back to a half's start on the next `round_prestart`,
  as CS2 swaps the sides at the round reset (`m_bSwitchingTeamsAtRoundReset`,
  round-economy.md); so nothing earned in the pause outlasts it.
- **A gun bought is taken in hand** (a primary or a pistol); armour, the
  kit, grenades and the Zeus are only carried. From memory of CS2.
- **The menu's key order** (1 pistols to 5 grenades) follows the loadout's
  order; undoing is a right-click. Both by eye; CS2's own menu decides.
- Not built: the short-handed bonus (CFG `cash_team_bonus_shorthanded 1000`,
  paid after a team has been short for `mp_shorthanded_cash_bonus_round_delay
  2` rounds; bots fill every place, so no team is short) and CV
  `cash_team_per_dead_enemy 50` (no file says what it pays; CFG leaves it
  alone).

Local tasks (Sid's machine), added to `reference/cs2-systems.md`'s E1 and E2:

- **E1.** On a local server with `mp_logmoney 1`: that a suicide and a
  death in the bomb's blast move no money; that Ts who survive a round lost on time get nothing; what a pistol-round
  winner that loses round 2 is paid ($1,400 expected); and what
  `cash_team_per_dead_enemy` pays.
- **E2.** When buy time counts from, the helmet's own price, and the
  menu's key order.

## How it is wired in

On dust2 (done 2026-09-23, `de_dust2.gd`'s `_add_systems`):

1. The economy is a system in the world's game:
   `Economy.new(MoneyRules.new(), BuyZones.from_volumes(BrushVolume.buy_zones(entities, root)))`,
   with `economy.match_rules` set to the match's `MatchRules`. Where the
   buy zones have not been extracted (`scripts/extract_assets.sh volumes`)
   a stand-in box 128 units round each side's spawn points is used, and the
   map says so in the top left; CS2 has no such fallback.
2. `MatchState` sends the round's events into the world's events
   (`GameWorld.match_state` hands it them): `round_announce_warmup`,
   `begin_new_match` when warmup ends, `round_prestart` (handed out at
   once, before anyone spawns), `round_start`, `round_freeze_end`,
   `round_end` with `GameEvents.round_end_reason` and its message, and
   `announce_phase_end` as each half's last round ends, half time,
   regulation into overtime and each overtime half alike.
3. A spawn from nothing gives `Inventory.give_starting_items(side)` and no
   armour (`MatchRules.free_armor`, CS2's `mp_free_armor 0`); a survivor
   keeps what they had, including what they bought.
4. Deaths go through `DamageInfo.deal`, the bomb sends `bomb_planted`,
   `bomb_defused` and `bomb_exploded`, and every spawn sends
   `player_spawn`.
5. The HUD (`GameHud`) shows your money above your health and, while you
   may buy, "B  buy" with the buy time left; B opens `BuyMenu`, and when it
   may not open the HUD says why for two seconds (the menu's `refused`).
6. Bots buy through the same `buy` command (below).

On the test range (`maps/test_range/range_shop.gd`) the economy is a
system in the range's `game`, with a buy zone round the spawn, $16,000 (O
fills it again) and buying that never closes. The range's starting items
are added beside whatever is carried already, so the order the range sets
things up in does not matter.

## Bots buying

What CS2's classic bot (CCSBot, which plays competitive and casual) does,
as `BotBuying` (`src/bots/bot_buying.gd`) plans it and `Bot` carries it
out, as the buy commands a player's menu sends, so the economy prices and
refuses each as it does anyone's (reference/research/round-hud-bots.md B):

| Rule | CS2 | Source |
|---|---|---|
| Nothing below the eco limit | $2,000 (`bot_eco_limit`), so nothing on a pistol round | CV |
| Order | primary, secondary, armour, then with what is left a grenade | CV `sv_bot_buy_grenade_chance`'s description |
| Primary | the first gun on its weapon template its side may buy and it can afford; none when it carries one | GT `botprofile.db` |
| Templates | Rifle 25, RifleT 12, Sniper 8, PunchT 6, Spray 5, Punch 4, Shotgun 4, Power 2 of 147 profiles; 81 with none | GT `botprofile.db` |
| Grenade | a third of the time (`sv_bot_buy_grenade_chance 33`), one, HE 6 : flash, smoke, fire, decoy 1 each | CV |
| Kit | a CT buys one when it can | From memory |

The choices where CS2 is silent, each marked in the code:

- **When**: 0.25 to 1 s after it spawns (16 ticks, then up to 48 more from
  its seed), so nine bots do not all buy on one tick. CS2's delay is in no
  file.
- **A bot's template** is picked from its name, weighted as the 147
  profiles use them, and kept all match. The 81 profiles with no preference
  buy by CS2's own `autobuy.txt` gun order, a stand-in.
- **The loadout**: a template's `m4a1` buys the M4 the side's loadout
  holds (the M4A1-S), and `mp7` the MP5-SD, by `autobuy.txt`'s rule that a
  weapon sharing a place buys the one equipped there; a gun the loadout
  does not hold (M249, SCAR-20, G3SG1) is skipped, as the menu cannot buy
  it either.
- **No pistol step**: which pistol CS2's bot buys is in no file; it keeps
  its own.
- **Armour**: the suit, then the vest (refused once the suit is on).
- **The kit before the grenade.**
- A molotov weight stands for the incendiary on a CT.

After buying, a bot takes its best gun out (a primary over a pistol), and
a gun it picks up the same way. Everything is seeded from the game's own
state (its userid, the tick, its name), so two runs of a match buy the
same. Checked by `tests/run_bot_buy_checks.gd`. A team's plan (full buy,
force, save, dropping guns for teammates) goes beyond CS2's own bots and
is roadmap item 24's.
