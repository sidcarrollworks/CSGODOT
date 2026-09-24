# CS2 money, buying, round flow and game events: research notes

Written 2026-09-24 for CSGODOT, to add to `reference/cs2-systems.md` sections 1 to 3,
`reference/systems/economy.md` and `reference/systems/contracts.md`.

## How to read this

- **GT** means SteamDatabase's GameTracking-CS2 at commit `d45f52d` (2026-09-23),
  `https://github.com/SteamDatabase/GameTracking-CS2/blob/master/<path>`. A file
  from an older commit is cited as `GT@<sha> <path>`.
- **CFG** is GT `game/csgo/cfg/gamemode_competitive.cfg`; **TMM** is GT
  `game/csgo/cfg/gamemode_competitive_tmm.cfg` (it says it runs after CFG);
  **CV** is GT `DumpSource2/convars.txt` (a convar's built-in default where CFG
  leaves it alone). **EN** is GT `game/csgo/pak01_dir/resource/csgo_english.txt`.
  **SS** is GT `game/csgo/bin/win64/server_strings.txt` (strings compiled into the
  server, so a localisation token found there is one the server really sends).
  **PS** is GT `content/csgo_addons/cs_script_demo/maps/scripts/point_script.d.ts`,
  Valve's own TypeScript typings for CS2's map scripting API.
- **Inferred** is my reading of a source, not something it states. **From memory**
  is my own knowledge with no source found (kept rare). **Disputed** means two
  sources disagree; both sides are given. **Community** marks a figure from a
  player-written page, reached only through a search engine's summary.
- Web access in this session was narrow: Liquipedia, the Counter-Strike fandom
  wiki, counter-strike.net, the Steam store and most community sites were blocked
  by the proxy, so web claims below come from search-result summaries and carry
  the page's URL. GitHub was reachable, and that is where most of the settled
  answers come from: the game's own files, plus GT's commit history for dating
  changes (fetched as `GT@<sha>`).

---

## 1. Findings that change what the project does

1. **CTs get $50 per dead Terrorist (July 16, 2025).** `cash_team_per_dead_enemy 50`
   first appears in the convar dump between GT@9b9a3d4d (2025-07-07) and
   GT@05b3cdb1 (2025-07-16), which is the day Valve's pre-Cologne update came out.
   Per the press coverage of that update, in every competitive mode each CT gets $50
   for each Terrorist eliminated that round, whether or not the round is won
   ([dust2.us](https://www.dust2.us/news/63719/how-does-the-new-cs2-economy-change-affect-the-ct-side),
   [egamersworld](https://egamersworld.com/counterstrike/news/28761/cs2-balance-changes-before-iem-cologne-2025-premie-GHlwMoEan),
   [esports.gg timeline](https://esports.gg/news/counter-strike-2/all-cs2-updates/)).
   CFG does not set it, so the CV default of 50 applies. The server sends it as team
   income. SS has `#Team_Cash_Award_Dead_Terrorists:f` and `#Team_Cash_Award_Dead_CTs:f`,
   and EN words them " +$%s1 team income for {num_enemies} eliminated terrorists".
   The wording includes a count, so it is **Inferred** that the award is paid once,
   at round end, as $50 times the number of dead Ts. The project does not build this.
   economy.md lists it under "no file says what it pays". That question is now
   answered.
2. **Money earned during a round can only be spent the next round.** The CS2
   controller keeps `m_iMoneyEarnedForNextRound` and `m_bReceivesMoneyNextRound`
   next to `m_iAccount` (GT `DumpSource2/schemas/server/CCSPlayerController_InGameMoneyServices.h`).
   The scripting API has `AddMoneySpendableNow` and `AddMoneyEarnedForNextRound` as
   separate calls (PS, `CSPlayerController`). The server sends
   `#Cstrike_TitlesTXT_Not_Enough_Money_NextRound` (SS), which reads "You have
   insufficient funds\n$%s1 that you just earned cannot be spent this round" (EN).
   Community guides say the same thing: a kill award is added to next round's money
   ([csgobooks2](https://csgobooks2.com/cs2-kill-reward-system-explained/)). The
   project's `Economy._on_player_death` pays kill awards straight into the account,
   so a kill made during buy time can be spent at once. That is CS:GO's behaviour,
   not CS2's. Still to measure: whether the banked money shows in the account at
   round end or at the next round's start.
3. **A suicide pays an enemy.** The server has
   `#Player_Cash_Award_ExplainSuicide_YouGotCash`, `_TeammateGotCash`, `_EnemyGotCash`
   and `_Spectators` (SS). EN words them "(You were awarded +$%s2 compensation for
   the suicide of %s1)", and so on. Community rule: an enemy gets the kill award
   they could have earned, and a random enemy gets it when nobody damaged the player
   ([search summary of fandom Money page and Steam threads](https://counterstrike.fandom.com/wiki/Money)).
   The project pays $0 and says "a suicide costs score, not money". The suicider's
   own money is a separate question. SS also has `#Team_Cash_Award_No_Income_Suicide`,
   which EN words " +$0 penalty for suiciding". **Inferred**: a player who suicides
   loses their end-of-round team income for that round.
4. **The loss-bonus formula is in the game's own UI code** (GT
   `game/csgo/pak01_dir/panorama/scripts/scoreboard.js`, `_RoundLossBonusMoneyForTeam`):
   `cash_team_loser_bonus + clamp(next_round_loss_bonus, 0, mp_consecutive_loss_max) * cash_team_loser_bonus_consecutive_rounds`.
   The tooltip reads "{team} will earn ${amount} with a round loss" (EN
   `Scoreboard_lossmoneybonus_tooltip`), and the scoreboard shows the count as up to
   4 pips. This confirms the repo's reading (section 2.2).

---

## 2. Money

### 2.1 Every `cash_` convar, and what competitive sets

CV is the built-in default and CFG is what competitive sets. TMM changes none of
them. Bomb-map values are marked **used**. Hostage and other-mode values are listed
so the table is complete.

| Convar | CV | CFG | What it pays (competitive, bomb maps) |
|---|---|---|---|
| `cash_team_elimination_bomb_map` | 3250 | 3250 | **used**: each winner, round won by killing the other side |
| `cash_team_win_by_time_running_out_bomb` | 3250 | 3250 | **used**: each CT, time ran out with no bomb planted |
| `cash_team_terrorist_win_bomb` | 3500 | 3500 | **used**: each T, bomb exploded |
| `cash_team_win_by_defusing_bomb` | 3250 | **3500** | **used**: each CT, bomb defused (CFG raises the default) |
| `cash_team_loser_bonus` | 1400 | 1400 | **used**: loss bonus base |
| `cash_team_loser_bonus_consecutive_rounds` | 500 | 500 | **used**: loss bonus step |
| `cash_team_planted_bomb_but_defused` | 600 | 600 | **used**: each T on top of the loss bonus when the bomb was planted and then defused |
| `cash_team_per_dead_enemy` | 50 | (not set) | **used since 2025-07-16**: $50 to each CT per dead T (section 1.1) |
| `cash_team_bonus_shorthanded` | 0 | **1000** | **used**: a team down a player (section 2.6) |
| `cash_team_winner_bonus_consecutive_rounds` | 0 | (not set) | 0, a win streak pays nothing extra |
| `cash_player_killed_enemy_default` | 300 | 300 | **used**: kill with an item that has no award of its own |
| `cash_player_killed_enemy_factor` | 1 | 1 | **used**: multiplies the weapon's `m_nKillAward` |
| `cash_player_killed_teammate` | -300 | -300 | **used**: team kill |
| `cash_player_bomb_planted` | 300 | 300 | **used**: the planter |
| `cash_player_bomb_defused` | 300 | 300 | **used**: the defuser |
| `cash_player_get_killed` | 0 | (not set) | 0, being killed |
| `cash_player_respawn_amount` | 0 | (not set) | 0 (respawn modes) |
| `cash_player_drop_on_death`, `_stack_value` | 0, 250 | (not set) | `developmentonly`, added 2026-04-20 (GT@c15581f2); not in play |
| `cash_player_interact_with_hostage` | 150 | 300 | hostage maps |
| `cash_player_rescued_hostage` | 1000 | 1000 | hostage maps |
| `cash_player_damage_hostage` | -30 | -30 | hostage maps |
| `cash_player_killed_hostage` | -1000 | -1000 | hostage maps |
| `cash_team_elimination_hostage_map_t` / `_ct` | 1000 / 2000 | 3000 / 3000 | hostage maps |
| `cash_team_win_by_hostage_rescue` | 3500 | 2900 | hostage maps |
| `cash_team_win_by_time_running_out_hostage` | 3250 | 3250 | hostage maps |
| `cash_team_hostage_interaction` | 500 | 600 | hostage maps |
| `cash_team_rescued_hostage` | 0 | 600 | hostage maps |
| `cash_team_hostage_alive` | 0 | 0 | hostage maps |

Other money convars:

| Convar | CV | CFG / TMM | Meaning (CV's description) |
|---|---|---|---|
| `mp_startmoney` | 800 | 800 | "amount of money each player gets when they reset" |
| `mp_maxmoney` | 16000 | 16000 | "maximum amount of money allowed in a player's account" |
| `mp_overtime_startmoney` | 10000 | (not set) | "Money assigned to all players at start of every overtime half" |
| `mp_starting_losses` | 0 | **1** | "Determines what the initial loss streak is." |
| `mp_consecutive_loss_max` | 4 | (not set) | no description; the scoreboard clamps the count to it |
| `mp_consecutive_loss_aversion` | 1 | (not set) | "0 = win fully resets loss bonus, 1 = first win steps down loss bonus, 2 = first win holds loss bonus and step down starting with second win" |
| `mp_afterroundmoney` | 0 | 0 | "amount of money awared to every player after each round" |
| `mp_playercashawards`, `mp_teamcashawards` | 1, 1 | 1, 1 | switch personal and team awards on |
| `mp_economy_reset_rounds` | 0 | (not set) | "Reset all player money every N rounds (0 for never)" |
| `mp_shorthanded_cash_bonus_round_delay` | 2 | (not set) | "number of previous rounds that a team needs to have been shorthanded before they are eligible" |
| `mp_shorthanded_cash_bonus_ignore_kicked` | true | (not set) | "whether kicked players are included in the assessment for short-handedness" |
| `mp_logmoney` | 0 | (not set) | logging, for measuring (section 7) |
| `dev_reportmoneychanges` | 0 | `developmentonly` | not usable in retail |

History (GT's commits since 2025-01-01, diffing every `cash_` and `mp_` convar
name and default in CV): the only economy changes are `cash_team_per_dead_enemy`
added on 2025-07-16, `sv_sellback_enabled` first appearing on 2026-03-04
(GT@f9fd8bf1), and the development-only drop-on-death pair on 2026-04-20. Between
2026-03-14, when GT started tracking the cfgs, and 2026-09-23, CFG and TMM changed
nothing about money. The only diff lines are `sv_allow_annotations_access_level`
and two spawn convars. **No economy change landed in July 2026.** The "July" change
people talk about is July 2025. The 2026-07-09 update added only
`mp_shoot_dropped_grenades`. The 2026-09-23 update made `mp_promoted_item_enabled`
default to true, but CFG and TMM both set it to 0, and it added
`mp_team_intro_type "auto"`.

### 2.2 The loss bonus ladder

- **Formula** (GT `panorama/scripts/scoreboard.js`): loss bonus =
  `1400 + 500 x n`, where `n` is the team's `next_round_loss_bonus`, clamped to
  0..`mp_consecutive_loss_max` (4). That gives $1,400, $1,900, $2,400, $2,900 and
  $3,400. The server keeps the count per side in `m_iNumConsecutiveCTLoses` and
  `m_iNumConsecutiveTerroristLoses` (GT `DumpSource2/schemas/server/CCSGameRules.h`).
- **Start of a half**: `mp_starting_losses 1` (CFG), so the pistol round's loser is
  paid 1400 + 500 x 1 = $1,900. **Inferred**: the count is set back to 1 at the side
  swap.
- **A win** steps the count down one (`mp_consecutive_loss_aversion 1`, CV), with a
  floor of 0. **A loss** pays by the current count, then raises it by one, up to the
  max. **Inferred** from the tooltip "will earn $X with a round loss", which is shown
  before the round is lost.
- Worked examples, same as the repo's: the pistol winner who loses round 2 is paid
  $1,400 (count 1, then 0 after the win, pays at 0). A side that loses rounds 1 and
  2 is paid $1,900 and then $2,400. Community pages agree on the ladder and on "a
  win steps down one"
  ([skin.land](https://skin.land/blog/cs2-loss-bonus/),
  [cs2guide](https://cs2guide.net/economy-system/loss-bonus-understanding/)).
  **Disputed**: one page says a win "resets" the bonus
  ([gamefreaks365](https://gamefreaks365.com/cs2-economy-guide-how-money-works-in-the-game/)),
  but `mp_consecutive_loss_aversion 1`'s own description settles it as a step down.
- **Overtime**: nothing says where the count starts in an overtime half.
  **Inferred**: `mp_starting_losses` again. Measure (E1).
- **A round draw**: no source found for whether it pays or moves the count. Measure.

### 2.3 Ts alive when time runs out

- The server has `#Team_Cash_Award_No_Income` (SS), which EN words
  " +$0 penalty for running out of time". No convar switches it (none in CV).
- The script API's `AddTeamMoney` (PS) says: "If players are not eligible to receive
  end-of-round money, then that restriction is honored". Eligibility is per player
  (`m_bReceivesMoneyNextRound` on the money services). **Inferred**: survivors of a
  time loss are marked not eligible, and a suicide is too (section 1.3).
- Community: "if Terrorists run out of time without planting and at least one
  survives, survivors get $0. If they all die or the bomb was planted, they receive
  the normal loss bonus"
  ([skin.land search summary](https://skin.land/blog/cs2-loss-bonus/)). EN's own
  CS2 highlight texts say the same in play: "leaving him with no money for the next
  round" (EN `HighlightDesc_aus2025_jimphatlosetotimevsvitalityontrain`,
  `..._zywoo3kdominatingvsmouzontrain`).
- **Still open**: whether survivors keep the kill awards they earned that round
  (**Inferred** yes: the $0 is the "team income" line). Also whether their side's
  count still goes up (**Inferred** yes, since it is a team loss).

### 2.4 Kills, team kills, suicides, world deaths

Kill awards (`m_nKillAward` times `cash_player_killed_enemy_factor 1`, from
`reference/weapons/vdata.csv`, which is generated from GT
`game/csgo/pak01_dir/scripts/weapons.vdata`):

| Award | Weapons |
|---|---|
| $1,500 | knife |
| $900 | Nova, MAG-7, Sawed-Off |
| $600 | MAC-10, MP9, MP7, MP5-SD, UMP-45, PP-Bizon, XM1014 |
| $300 | P90, every pistol (Glock, P2000, USP-S, Dual Berettas, P250, Tec-9, Five-SeveN, CZ75, Desert Eagle, R8), every rifle and machine gun (Galil, FAMAS, AK-47, M4A4, M4A1-S, SG 553, AUG, SSG 08, G3SG1, SCAR-20, M249, Negev), every grenade, the C4 entry |
| $100 | AWP, Zeus x27 |

- **Team kill**: -$300 (CFG). There is also contribution score -2
  (`contributionscore_team_kill`, CV). `mp_tkpunish 0` means no punishment next
  round. `mp_autokick 1` kicks team killers, `mp_td_dmgtowarn 200` /
  `mp_td_dmgtokick 300` handle team damage, and `mp_spawnprotectiontime 5` kicks
  anyone who team-kills within 5 s of the round restart (all CV).
- **Suicide**: see section 1.3. Contribution score -2 (`contributionscore_suicide`,
  CV). `mp_suicide_penalty 1` is described only as "Punish players for suicides"
  (CV).
- **World deaths** (falling, the bomb's blast): no source found. **From memory**:
  Source counts a fall with no recent attacker as a suicide, which would trigger the
  enemy's compensation. A blast death is credited to the planter's side in the kill
  feed as a C4 icon. Both need measuring (E1 already lists them).
- The server's money log line is
  `"%s<%i><%s><%s>" money change %d%s%d = $%d%s%s` (SS), which gives the old
  balance, the change, the new balance and a reason. A second format is
  `%s\t%d\t\t(total: %d)\tAddAccountFromTeam: REASON: %s` (SS). These are what
  `mp_logmoney 1` prints, so E1 can read every award and its reason off them.

### 2.5 Planting, defusing, and the $600

- The planter gets $300 and the defuser gets $300 (CFG), at the moment of the plant
  or defuse (EN " +$%s1 for planting the C4"). **Inferred** from section 1.2: this
  money is banked for next round like kill awards.
- Ts who planted and then lost get $600 each on top of the loss bonus
  (`cash_team_planted_bomb_but_defused`, CFG). EN words it " +$%s1 team income for
  planting the bomb". The only way Ts lose after a plant is a defuse (all CTs dead
  means the Ts win at once, and a bomb that explodes means the Ts win), so "planted
  and lost" and "planted and defused" are the same case on a bomb map.
  **Inferred**: a surrender is the only exception.
- Defusing pays the CT team $3,500 each in competitive (CFG), not the $3,250
  default (CV).

### 2.6 The short-handed bonus

- $1,000 (CFG). A team must have been short for `mp_shorthanded_cash_bonus_round_delay 2`
  earlier rounds, and kicked players do not count (`mp_shorthanded_cash_bonus_ignore_kicked 1`).
  CCSTeam keeps `m_nShorthandedRoundBonusStartRound` and
  `m_nLastRecievedShorthandedRoundBonus` (GT `DumpSource2/schemas/server/CCSTeam.h`).
- Strings (SS, EN): "Your team will be eligible for short-handed income in %s1
  rounds", "...in 1 round", " +$%s1 team income for being short-handed", and, shown
  to the other side, "Each enemy has received $%s1 short-handed income".
- **Disputed**, on when it pays. Valve's CS:GO announcement: "Competitive teams down
  a player will receive an extra $1000 shorthanded loser income (after exceptions
  are met) per round loss. This does not apply to teams who kick a player"
  ([@CSGO, Jan 2021](https://twitter.com/CSGO/status/1354576556375478273)). The
  fandom Money page (search summary) says it is paid "at the round start", but not
  in the second half's pistol round nor its first two rounds. Measure.
- The project fills every place with a bot, so no team is ever short. Low priority.

### 2.7 Half time, overtime, warmup, the cap

- **Half time**: everyone goes back to `mp_startmoney` $800 (**Inferred** from
  "money each player gets when they reset" and `mp_halftime 1`; universally reported)
  and the ladder goes back to `mp_starting_losses`.
- **Overtime** (TMM, Premier): `mp_overtime_enable 1`, `mp_overtime_limit 1`,
  `mp_overtime_maxrounds 6` (CV). That is one overtime of two 3-round halves, with
  $10,000 each at the start of every overtime half (`mp_overtime_startmoney`, CV).
  In plain Competitive (CFG only), overtime is off (`mp_overtime_enable 0`, CV), so
  12-12 is a draw. Community agrees: "In Competitive, a 12:12 score ends in a draw.
  Premier: one overtime ... If overtime ends in 15-15, the match ends as a draw"
  ([prosettings](https://prosettings.net/blog/cs2-premier-mode-explained/),
  [dmarket](https://dmarket.com/blog/premier-vs-competitive-modes-in-cs2/)).
- **Warmup**: `mp_warmuptime 120`, and `mp_warmuptime_all_players_connected 15`
  shortens it once everyone is in (CFG). `mp_warmup_offline_enabled 0` (CV) means
  **an offline bot match has no warmup at all**, which matters for a bots-only
  project. `mp_warmup_items_nocost 0` means weapons are not free in warmup.
  `mp_warmup_items_nocount_policy 42` (bits 2 C4, 8 defuser and kevlar,
  32 healthshot) makes those "unlimited during warmup". `mp_warmup_items_drop_policy 247`
  lets everything but the defuser (bit 8) drop. EN also has "You cannot drop weapons
  during warmup" (`SFUI_Notice_CannotDropWeaponDuringWarmup`). **Warmup money is in
  no file.** Community: "at the start of the warmup, players will have their money
  set to the money cap of the game mode", $16,000 in competitive (fandom via search
  summary). Measure (E2).
- **The cap**: $16,000 (CFG). Anything over it is lost (**From memory**).

### 2.8 Other money-adjacent UI facts

- The buy menu shows "Next Round Minimum: $X" (EN `BuyMenu_MinMoneyNextRound`, GT
  `panorama/layout/buymenu.xml` `buymenu-min-money-next-round`). **Inferred**: X is
  money now plus the loss bonus a loss would pay. The client convars
  `cl_buymenu_{t,ct}_nextround_low 1400` / `_high 5000` (CV) look like colour
  thresholds for that line (**Inferred**).
- The scoreboard has a "Loss Bonus" column (EN `Scoreboard_lossmoneybonus`) and
  per-team pips 1 to 4 (scoreboard.js).
- `bot_eco_limit 2000` (CV): bots do not buy below $2,000. That is for roadmap
  item 24.

---

## 3. Buying

### 3.1 Where and when

| Rule | Value | Source |
|---|---|---|
| Buy zone only | `mp_buy_anywhere 0` (1 both, 2 T, 3 CT) | CFG, CV |
| Buy time | `mp_buytime 20`, "How many seconds after round start players can buy items for" | CFG, CV |
| Buy while spawn-immune regardless of buy time | `mp_buy_during_immunity 0` | CFG, CV |
| Which guns may be bought | `mp_buy_allow_guns 255` (bits: pistols 1, SMGs 2, rifles 4, shotguns 8, snipers 16, heavy 32), `mp_buy_allow_grenades 1`, `mp_weapons_allow_{pistols,smgs,rifles,heavy} -1` | CV |
| Per-map override | `sv_buy_status_override -1` (0 all, 1 CT only, 2 T only, 3 nobody) | CV |
| Armour on sale | `mp_max_armor 2` (kevlar and helmet); `mp_free_armor 0` | CV, CFG |
| Purchases of one weapon type a round | `mp_weapons_allow_typecount 5`, "per player per round"; the refusal is "You can only purchase {n} of this type" | CV, EN `SFUI_BuyMenu_MaxItemsOfTypePurchased` |
| Zeus a round | `mp_weapons_allow_zeus 5` | CFG |
| Grenades carried | `ammo_grenade_limit_total 4`, `ammo_grenade_limit_flashbang 2`, `ammo_grenade_limit_default 1` (CV defaults are 3, 1, 1) | CFG, CV |
| Per-match weapon limit | `mp_weapons_max_gun_purchases_per_weapon_per_match -1` (none) | CV |
| Map-placed weapons kept | `mp_weapons_allow_map_placed 1` | CFG |

- **When the 20 s count from.** The convar says "after round start". Community
  pages agree that buy time runs 20 s after freeze time ends, so buying is open for
  the whole 15 s freeze plus 20 s
  ([search summary of totalcsgo / csgo-nade](https://totalcsgo.com/commands/mpbuytime)).
  **Inferred**: CS2's "round start" for timers is `m_fRoundStartTime`, which is the
  freeze's end, since the round clock starts then. The refusal text is
  "%s1 seconds have passed.\nYou can't buy anything now" (EN `Cstrike_TitlesTXT_Cant_buy`,
  used by the server per SS) and the buy menu shows "The %s1 second buy period has
  expired" (EN `SFUI_BuyMenu_OutOfTime`). Both name a number of seconds.
  `buytime_ended` is a game event (mod.gameevents), and CCSGameRules has
  `m_bBuyTimeEnded`. Leaving the zone gives "You have left the buy zone"
  (EN `BuyMenu_NotInBuyZone`).
- `m_bTCantBuy` and `m_bCTCantBuy` exist on the game rules (a map can forbid a side
  from buying). `CBuyZone` carries only `m_LegacyTeamNum` (GT
  `DumpSource2/schemas/server/CBuyZone.h`), and the pawn keeps `m_bInBuyZone`,
  `m_bWasInBuyZone` and the list `m_TouchingBuyZones` (GT
  `DumpSource2/schemas/server/CCSPlayerPawn.h`).

### 3.2 Refunds ("sellback")

- `sv_sellback_enabled 1`: "Determines whether players can undo purchases in the
  buy menu" (CFG, CV). Buttons: each item has a refund button (tooltip "Refund",
  EN `BuyMenu_Sellback`), the nav bar has "[DEL] Refund All", which runs the
  `sellbackall` command "Attempt to refund all equipment" (GT
  `DumpSource2/commands.txt`), and DEL is bound to `sellbackall` by default (GT
  `game/csgo/cfg/user_keys_default.vcfg`).
- What the server remembers per purchase: `SellbackPurchaseEntry_t` holds
  `m_unDefIdx`, `m_nCost`, `m_nPrevArmor`, `m_bPrevHelmet` and `m_hItem`, kept in
  `CCSPlayer_BuyServices.m_vecSellbackPurchaseEntries` on the **pawn** (GT
  `DumpSource2/schemas/server/SellbackPurchaseEntry_t.h`, `CCSPlayer_BuyServices.h`).
  So a refund gives back what was paid (not the list price), puts armour and the
  helmet back where they were, and is tied to the item's own entity. **Inferred**:
  refunds last only for the pawn's life and only for the item still held.
- There is a limit: the server prints "%s hit the sellback limit." (SS). Nothing
  gives its size.
- Community rules
  ([esports.gg](https://esports.gg/guides/counter-strike-2/how-to-sell-weapons-in-cs2/),
  [dotesports](https://dotesports.com/counter-strike/news/how-to-sell-weapons-in-cs2)):
  only in the round it was bought; only during buy time; only by the original buyer,
  who must not have dropped it (a gun picked up from a teammate cannot be refunded);
  not after firing it. **Disputed/measure**: one summary says leaving the buy zone
  does not stop a refund while buy time lasts. The menu itself cannot be opened
  outside the zone.
- History: at CS2's launch, refunding kevlar and helmet with `refundall` returned
  $1,000 and left the vest on; that was fixed quietly
  ([dotesports](https://dotesports.com/counter-strike/news/save-a-buck-new-cs2-exploit-lets-players-buy-cheap-gear)).
  This is why the entry stores the previous armour.

### 3.3 Armour and the helmet on its own

- Prices: kevlar $650, kevlar and helmet $1,000 (the repo's IG/WV). There is no
  helmet-only item in the buy menu. The server refuses with "You already have armor"
  (EN `SFUI_BuyMenu_OnlyOneArmor`).
- **Disputed**, on when the helmet costs only $350. One community summary says
  kevlar above 0% is enough; another says the armour must still be at 100
  ([bo3.gg](https://bo3.gg/articles/how-armour-and-helmets-work-in-cs2),
  [Steam thread](https://steamcommunity.com/app/730/discussions/0/350542683208997066/)).
  Measure (E2): buy kevlar, take damage to 80 armour, then buy kevlar and helmet.

### 3.4 Buying for teammates

- CS2 has "Buy & Throw". Hold the donate key (`cl_buywheel_donate_key`: 0 Left
  Ctrl, the default; 1 Left Alt; 2 Left Shift) while buying and the item is dropped
  for a teammate. The nav bar says "Hold [key] Buy & Throw" (EN
  `BuyMenu_BuyForTeammate`, `SFUI_Settings_BuyWheelDonateKey_*`; GT
  `panorama/layout/buymenu.xml` `BuyForTeammateLabel`). CCSGameRules has
  `m_bCanDonateWeapons`. The round-end fun facts count "donated N weapons that
  round" (EN `funfact_donated_weapons`).
- The buy menu also shows each **teammate's inventory** under each item
  (`TeammateInventory` in buymenu.xml) and a **"weapons on the ground" list** by
  category (`jsGroundWeaponsLister--Cat1..5`).
- The chat wheel has "Request a weapon", "We should save" and "We should buy" (EN
  `Chatwheel_requestweapon`, `_requestecoround`, `_requestspend`).
- `sv_buymenu_open_prevents_opportunistic_pickup 0` (CV): having the menu open does
  not stop walking over and picking up a thrown gun (**Inferred** from the name).

### 3.5 The menu and its keys

- Layout (GT `game/csgo/pak01_dir/panorama/layout/buymenu.xml`,
  `styles/buymenu.css`): the category columns lie left to right (`flow-children: right`)
  in the order `CategoryContainer1` equipment (`ccequip`), `2` pistols, `3` mid-tier,
  `4` rifles, `5` grenades. There is also a separate "promoted item" column, which
  `mp_promoted_item_enabled 0` turns off in CFG and TMM. Each column has a key label
  (`buymenu__category__column__keylabel`, text `{s:buymenu-category-key}`) that the
  game fills in at run time. Each item has a key label, name, icon, price, and
  "current value". The left panel shows money, "Buy Time Remaining" (EN
  `BuyMenu_TimerText`; "Immunity Time Remaining" when buying during immunity),
  and "Next Round Minimum". The right panel shows the chosen item's stats: cost,
  kill award ("KILL AWARD", with "Default" and "None" for items without one),
  damage, fire rate, recoil control, mobility, armour penetration, stopping power
  (EN `BuyMenu_*`). Failure messages appear in `PurchaseFailureLabel`.
- **The container IDs suggest the keys run 1 Equipment, 2 Pistols, 3 Mid-Tier,
  4 Rifles, 5 Grenades**, with Equipment leftmost (**Inferred**: the numbers are the
  element IDs, and the labels are filled in at run time). The repo's guess is
  "1 pistols ... 4 equipment". Community summaries repeat CS:GO's old layout and
  are no help. Measure (E2).
- `cl_buywheel_nonumberpurchasing 0` (CV): number keys buy from the menu unless
  this is set.
- Default binds (GT `game/csgo/cfg/user_keys_default.vcfg`): `b` buymenu, `F3`
  autobuy, `F4` rebuy, `DEL` sellbackall, `g` drop, `,` buyammo1, `.` buyammo2, `m`
  teammenu. `cl_use_opens_buy_menu 0` (CV): E does not open it by default.
- Autobuy and rebuy: `autobuy` buys the first affordable line of
  `game/csgo/pak01_dir/autobuy.txt`. The default list is vesthelm, vest, m4a1, ak47,
  famas, galilar, mp7, nova, defuser, and "a weapon that shares a slot ... will
  purchase the weapon currently equipped in that slot". `rebuy` takes a snapshot of
  your equipment at each purchase and rebuys it in the order Armor, PrimaryWeapon,
  Flashbang, SmokeGrenade, Defuser, HEGrenade, Flashbang, SecondaryWeapon, Molotov,
  IncGrenade, Decoy, Taser (`game/csgo/pak01_dir/rebuy.txt`).
- Buy aliases (autobuy.txt's list, which is also what `buy <alias>` takes): galilar,
  ak47, ssg08, sg556, awp, g3sg1, famas, m4a1, m4a1_silencer, aug, scar20, glock,
  deagle, elite, fn57, hkp2000, usp_silencer, p250, tec9, taser, xm1014, mag7, mac10,
  ump45, p90, bizon, mp7, mp9, m249, negev, nova, vest, vesthelm, flashbang,
  hegrenade, smokegrenade, molotov, incgrenade, decoy, defuser. Loadout-slot names
  appear too: `secondary0..4`, `smg0..4`, `rifle0..4`, `grenade0..4`. The retake
  convars buy with them (`mp_retake_*_loadout_*`, CV), and PS's `CSLoadoutSlot`
  enum lists MELEE, SECONDARY0-4, SMG0-4, RIFLE0-4, EQUIPMENT2.
- Refusal strings, useful for the project's own UI (EN): "Need $X more"
  (`SFUI_BuyMenu_Cannot_Afford`), "You can only carry {n} grenades",
  **"You can only purchase {n} grenades"** (`SFUI_BuyMenu_CanOnlyPurchaseTotalXGrenades`),
  "You already have armor", "Not allowed on your current team", "Not allowed in
  this game mode", "Not allowed on this map type", "In current inventory.".
  **Inferred**: the separate "purchase" line means there is a per-round cap on
  grenades bought as well as carried (a buy-throw-buy loop would otherwise be
  unlimited). Measure.

### 3.6 Loadouts

- Starting items (CFG): `mp_t_default_secondary weapon_glock`,
  `mp_ct_default_secondary weapon_hkp2000`, knife for both, and no default primary
  or grenades. A player's inventory loadout overrides the CT pistol with the USP-S
  (**From memory**; the repo's IG reading says the same).
  `mp_defuser_allocation 0` means no free kits.

---

## 4. Round flow

### 4.1 Phases and timers

| Phase | Value | Source |
|---|---|---|
| Warmup | 120 s; 15 s once everyone is connected; none offline | CFG `mp_warmuptime`, `mp_warmuptime_all_players_connected`; CV `mp_warmup_offline_enabled 0` |
| Warmup end to first round | 4 s | CV `sv_warmup_to_freezetime_delay 4` ("Delay between end of warmup and start of match") |
| Team intro | 6.5 s; type "auto" = normal when `mp_halftime` is on | CV `mp_team_intro_time`, `mp_team_intro_type` (new 2026-09-23); events `team_intro_start`, `team_intro_end` |
| Freeze time | 15 s (CFG), 20 s (TMM) | `mp_freezetime` |
| Round time | 1.92 min = 115.2 s | CFG `mp_roundtime_defuse` |
| Buy time | 20 s from freeze end (section 3.1) | CFG |
| Bomb timer | 40 s from plant | CV `mp_c4timer 40` |
| Win panel | 3 s | CFG `mp_win_panel_display_time` |
| Round end to next round | 7 s | CV `mp_round_restart_delay 7`. The win panel's report closes after `mp_round_restart_delay + mp_freezetime - 1` s (GT `panorama/scripts/hud/hudwinpanel.js`) |
| Half time | 15 s target, at least 8.5 s when team intros run | CV `mp_halftime_duration 15`, `mp_min_halftime_duration 8.5` |
| Match end | next map/restart after 25 s; +15 s in competitive for rankings | CV `mp_match_restart_delay 25`, `mp_competitive_endofmatch_extra_time 15` |
| Freeze cam on death | 2 s (CFG), after 0.8 s on the ragdoll | CFG `spec_freeze_time 2.0`; CV `spec_freeze_deathanim_time 0.8`, `spec_freeze_traveltime 0.3` |

- Game phases (EN `gamephase_0..5`): 0 Warmup, 1 Match, 2 First half, 3 Second
  half, 4 Half-time, 5 End of match. They are carried in `CCSGameRules.m_gamePhase`
  and announced by the `game_phase_changed {new_phase}` event.
- The game rules also track `m_nCTsAliveAtFreezetimeEnd` and
  `m_nTerroristsAliveAtFreezetimeEnd`, `m_bFreezePeriod`, `m_bWarmupPeriod`,
  `m_iRoundTime`, `m_fRoundStartTime`, `m_flRestartRoundTime`,
  `m_totalRoundsPlayed`, `m_nRoundsPlayedThisPhase` and `m_nOvertimePlaying` (GT
  `CCSGameRules.h`). These are good names for the project's `MatchState` fields.
- **Freeze-time beeps**: the events `cs_round_start_beep` and `cs_round_final_beep`
  (mod.gameevents) and `m_nLastFreezeEndBeep` on the rules. **From memory**: a beep
  each second for the last 3 s of freeze time, then the final beep at go.
- `round_time_warning` (game.gameevents) and `m_bRoundTimeWarningTriggered` handle
  the low-time warning. Its threshold is in no file.

### 4.2 Round end reasons

These are the numbers `round_end.reason` carries (the byte on the wire). They come
from CounterStrikeSharp's `RoundEndReason` enum (GPL; cited for the values only,
[source](https://github.com/roflmuffin/CounterStrikeSharp/blob/main/managed/CounterStrikeSharp.API/Modules/Entities/Constants/RoundEndReason.cs)),
matched to CS2's own notice and win-panel strings (EN `SFUI_Notice_*`,
`winpanel_end_*`):

| # | Name | Notice (EN) | Win panel (EN) | Competitive bomb map? | Team money |
|---|---|---|---|---|---|
| 1 | TargetBombed | "Target successfully bombed" | "Bomb detonated" | yes | T $3,500 |
| 4-6 | TerroristsEscaped, CTsPreventEscape, EscapingTerroristsNeutralized | escape mode | | no | |
| 7 | BombDefused | "The bomb has been defused" | "Bomb defused" | yes | CT $3,500; T loss + $600 |
| 8 | CTsWin (Ts eliminated) | "Counter-Terrorists Win" | "Terrorists eliminated" | yes | CT $3,250 |
| 9 | TerroristsWin (CTs eliminated) | "Terrorists Win" | "CTs eliminated" | yes | T $3,250 |
| 10 | RoundDraw | "Round Draw" | (`winpanel_draw` "Round Draw") | yes (rare) | measure |
| 11 | AllHostageRescued | "Hostage has been rescued" | "Hostage extracted" | no | |
| 12 | TargetSaved | "Target has been saved" | "Bombing failed" | yes | CT $3,250; surviving Ts $0 |
| 13 | HostagesNotRescued | "Hostages have not been rescued" | "Hostage Rescue failed" | no | |
| 14 | TerroristsNotEscaped | | | no | |
| 16 | GameCommencing | "Game Commencing" | | at warmup's end (**Inferred**) | none |
| 17 | TerroristsSurrender | "Terrorists Surrender" | "Terrorists surrender" | yes, by vote | |
| 18 | CTsSurrender | "CTs Surrender" | "CTs surrender" | yes, by vote | |
| 19 | TerroristsPlanted | | "Terrorists planted the bomb" | no (**Inferred**: a mode that ends on the plant) | |
| 20 | CTsReachedHostage | | "CTs have reached a hostage" | no | |
| 21, 22 | SurvivalWin, SurvivalDraw | "Glorious Victory!", "No Survivors" | | no | |

(2, 3 and 15 are the removed VIP mode.) Valve's scripting API has its own renumbered
list: `CSRoundEndReason` = UNKNOWN -1, IN_PROGRESS 0, GAME_COMMENCING 1, DRAW 2,
TARGET_BOMBED 3, TARGET_SAVED 4, BOMB_DEFUSED 5, HOSTAGES_RESCUED 6,
HOSTAGES_NOT_RESCUED 7, CTS_WIN 8, TERRORISTS_WIN 9, CTS_SURRENDER 10,
TERRORISTS_SURRENDER 11 (PS). **Valve's own shortlist of the reasons that still
matter** is these eleven. The project's six (TargetBombed, BombDefused, CTsWin,
TerroristsWin, TargetSaved, RoundDraw) cover all of them except GameCommencing and
the two surrenders.

The team income lines the server can print (SS, EN `Team_Cash_Award_*`) are "for
detonating bomb", "for eliminating the enemy team", "for running down the clock",
"for defusing the C4", "for losing", "for being short-handed", "for planting the
bomb", "+$0 penalty for running out of time", "+$0 penalty for suiciding", and "for
N eliminated terrorists/CTs". `Team_Cash_Award_Loser_Bonus_Neg` ("-$ team income for
losing") also exists, but no convar makes it negative in competitive.

### 4.3 How a round is decided

- **Elimination**: the side whose opponents are all dead wins (8 or 9), except when
  the bomb is planted and all Ts die. Then the round goes on until the defuse (7)
  or the explosion (1). The explosion makes it a T win even with no Ts alive
  (**From memory**, standard; the reason table above is consistent with it).
- **Time**: with no bomb planted, the CTs win on time (12). `mp_default_team_winner_no_objective -1`
  (CFG) applies only to maps with no objective.
- **Bomb planted**: the round clock stops mattering. The round ends on the defuse,
  the explosion, or all CTs dead (a T win by elimination, 9, paying $3,250, not
  $3,500). **From memory**: the HUD swaps the round clock for the bomb icon, and the
  remaining round time is not used. The win panel carries `show_timer_defend`,
  `show_timer_attack` and `timer_time` (event `cs_win_panel_round`), and the rules
  keep `m_bRoundEndShowTimerDefend` and `m_iRoundEndTimerTime`. **Inferred**: the
  win panel shows how much bomb time was left on a defuse, or round time on a
  time-out.
- **Both sides dead at once** (a trade on the same tick, an HE, fire): no source
  found. RoundDraw (10) exists. **From memory**, not certain: with no bomb planted a
  simultaneous wipe is a draw, and with the bomb planted it is a T win once the bomb
  explodes. Measure on a local server (`mp_logdetail 3` and a scripted HE on two
  1 HP bots).
- `mp_ignore_round_win_conditions 0` (CV) switches all of this off for practice.
- `mp_disconnect_kills_players 1` (CV): "When a player disconnects, kill them first
  (triggering item drops, stats, etc.)". So a disconnect is a death, and with the
  suicide rule it compensates the enemy (community, section 1.3).

### 4.4 Half, clinch, overtime, match end

- `mp_maxrounds 24`, `mp_halftime 1` (CFG): sides swap after 12. The swap fires
  `announce_phase_end` and `start_halftime` (mod.gameevents). CCSTeam keeps
  `m_scoreFirstHalf`, `m_scoreSecondHalf` and `m_scoreOvertime`.
  `m_bSwitchingTeamsAtRoundReset` and each controller's `m_bSwitchTeamsOnNextRoundReset`
  and `m_bRemoveAllItemsOnNextRoundReset` (GT `CCSPlayerController.h`) show that the
  swap happens at the next round reset and strips every item. **Inferred**: at half
  time every player loses their gear and gets the new side's pistol.
- `mp_match_can_clinch 1` (CFG): "team can clinch match win early if they win > 1/2
  total rounds". So 13 ends a 24-round match. The scoreboard marks the clinch round
  (scoreboard.js `can_clinch`, `num_wins_to_clinch`). The notices are "CTs clinched
  the match with the most wins" and the Terrorist version (EN
  `SFUI_Notice_CTs_Clinched_Match`).
- Announcements (game.gameevents): `round_announce_match_start`,
  `round_announce_warmup`, `round_announce_last_round_half`,
  `round_announce_match_point`, `round_announce_final` (the last round of
  regulation), `warmup_end`.
- Overtime (TMM): one overtime of 6 rounds (two halves of 3, sides swap), $10,000 a
  half. The match is a draw at 15-15, because `mp_overtime_limit 1` allows only one
  overtime (**Inferred** from the convar; community agrees, section 2.7). In an
  overtime, the clinch is 4 of 6 (**Inferred**).
- Match end: `cs_win_panel_match`, then `mp_match_restart_delay 25` s.
  `mp_endmatch_votenextmap 1` holds a vote for the next map, with 20 s to vote
  (`mp_endmatch_votenextleveltime`).

### 4.5 Timeouts, pauses, votes, surrender

| Rule | CFG | TMM | CV default |
|---|---|---|---|
| Tactical timeouts a team | (default) 1 | 3 | 1 |
| Timeout length | (default) 60 s | 31 s ("3 x 30s") | 60 |
| Added in overtime | 0 | 1 once and 1 each OT, at most 1 per OT | 0 / 0 / 1 |
| Technical timeouts a team | 1 of 120 s | 1 of 120 s | 0 |

- A timeout is called by vote ("Call a Tactical Timeout", EN `SFUI_Vote_StartTimeout`)
  and "will begin next freeze time" (EN `SFUI_vote_passed_timeout`). Refusals: "Your
  team has no timeouts left", "A timeout is already in progress". The rules keep
  `m_bTerroristTimeOutActive`, `m_flTerroristTimeOutRemaining` and `m_nTerroristTimeOuts`
  (and the CT versions), plus `m_bTechnicalTimeOut` and `m_bMatchWaitingForResume`.
  `mp_pause_match` "Pause the match in the next freeze time" (GT `DumpSource2/commands.txt`).
- Votes (CV): `sv_vote_timer_duration 15`, `sv_vote_quorum_ratio 0.501`,
  `sv_vote_command_delay 2` (0 in TMM), `sv_vote_creation_timer 120`,
  `sv_vote_failure_timer 300`, `sv_vote_allow_in_warmup 0`.
- **Surrender**: "You cannot surrender until a teammate abandons the match" (EN
  `SFUI_vote_failed_surrender_too_early`). When a teammate abandons, CS2 can offer an
  instant surrender: "Any YES vote will immediately end the match" (EN
  `Panorama_Vote_Text_AutoInstantSurrender`). The controller has
  `m_bAbandonAllowsSurrender` and `m_bAbandonOffersInstantSurrender`, and CCSTeam has
  `m_bSurrendered`. There is also a "continue or surrender" vote (EN
  `SFUI_otherteam_vote_continue_or_surrender`). **Disputed**: an esports.gg summary
  says an October patch made surrender need a majority
  ([esports.gg](https://esports.gg/news/counter-strike-2/how-to-surrender-in-cs2/)),
  while the live string says a single YES can end the match in the instant-surrender
  case. Both can be true for different vote types. The round ends with reason 17 or
  18. For a bots-only project this is low priority.

### 4.6 MVP

- `round_mvp {userid, reason, value, musickitmvps, nomusic, musickitid}`
  (mod.gameevents). Reason numbers come from GT `panorama/scripts/hud/hudwinpanel.js`
  `_SetMVP`, with EN's wording:

| reason | EN | 
|---|---|
| 1 | most eliminations ("MVP"; old text "for most eliminations") |
| 2 | "for planting the bomb" |
| 3 | "for defusing the bomb" |
| 4 | "for extracting a hostage" |
| 5 | Arms Race winner |
| 7, 12 | "MVP" (winner) |
| 9 | "for an Ace Round" |
| 10 | "for dealing a significant amount of fire damage" |
| 11 | "for dealing a significant amount of explosive damage" |
| 13 | "for planting and defending the bomb" (clutch plant) |
| 14 | "for a clutch defuse" |
| 15 | "for most kills (3k)" |
| 16 | "for most kills (4k)" |

  (6 and 8 are not handled by the panel; EN still has "for highest score" and "is
  the winner and sole survivor".)
- Rules, **Community** (the fandom MVP page via a search summary; written for
  CS:GO): an objective win gives MVP to the player who did the objective, though a
  defuser only gets it with at least one kill. Otherwise it goes to the most
  eliminations on the winning side. Ties go to score from kills (a kill is 2, an
  assist is 1), then to whoever joined the server first. A time win with no damage
  gives no MVP. CS2's extra reasons (fire, blast, clutch, 3k, 4k) are not described
  anywhere reachable. Measure, or treat as a later Local task. `sv_nomvp` is
  development-only (CV). The controller keeps `m_iMVPs` and `m_eMvpReason`.
- Contribution score (CV, used for score, MVP ties and bot difficulty): kill 2,
  assist 1, objective kill 3, planting 2, bomb exploded 1 (to the planter and each
  living T), defuse 3 with enemies alive or 1 after they are all dead, team kill -2,
  suicide -2. CFG sets `contributionscore_kill_reqs 1` and `_assist_reqs 1` ("all
  about pew-pew and bullets").

### 4.7 The round-end report CS2 sends

- User messages (GT `Protobufs/cstrike15_usermessages.proto`):
  `CS_UM_AdjustMoney {amount}`, `CS_UM_RoundEndReportData` (events with victim,
  objective and damage data, plus `terrorist_odds`), `CS_UM_CurrentRoundOdds {odds}`,
  `CS_UM_PostRoundDamageReport` (per opponent: damage given and taken, hits, kill
  type), `CS_UM_MatchEndConditions {fraglimit, mp_maxrounds, mp_winlimit, mp_timelimit}`.
  The win panel draws a win-probability graph from them, with objective icons for
  type 0 plant, 1 explosion, 2 defuse and 3 time (hudwinpanel.js). This is useful
  later for the HUD. The round-result icons are `win_elimination`, `win_defuse`,
  `win_time`, `win_bomb` and `win_rescue` (GT
  `panorama/scripts/common/gamerules_constants.js`).
- `cs_win_panel_round {show_timer_defend, show_timer_attack, timer_time, final_event,
  funfact_token, funfact_player, funfact_data1..3}` (mod.gameevents). `final_event`
  is "define in cs_gamerules.h" (the source comment), which **Inferred** means the
  round end reason.

---

## 5. Game events: CS2's list against the project's schema

CS2's events are in three files. Core engine events are in GT
`game/core/pak01_dir/resource/core.gameevents`, generic game events in GT
`game/csgo/pak01_dir/resource/game.gameevents`, and CS-specific ones in GT
`game/csgo/pak01_dir/resource/mod.gameevents`. When a name is in two files the
later one extends the earlier (mod's `player_death` comment: "this extents the
original player_death by a new fields").

### 5.1 Round and match

| Event | CS2 keys | Project (`src/game/game_events.gd`) | Note |
|---|---|---|---|
| `round_prestart` | none; "sent before all other round restart actions" | same | |
| `round_start` | timelimit (long, seconds), fraglimit, objective | same | |
| `round_poststart` | none; "sent after all other round restart actions" | same | |
| `round_freeze_end` | none | same | |
| `round_end` | winner (byte), reason (byte), message (string), legacy (byte), player_count (short: "total number of players alive at the end of round"), nomusic (byte); core adds `time` (float) | winner, reason, message, player_count | project: winner "T"/"CT" and reason by name (CS2 sends team 2/3 and the number, section 4.2). Missing: legacy, nomusic, time. `player_count` is **alive players**, not the roster |
| `round_officially_ended` | none | same | |
| `round_mvp` | userid, reason, value, musickitmvps, nomusic, musickitid | userid, reason, value | reasons in section 4.6 |
| `begin_new_match` | none; "Fired when a match ends or is restarted" | same | |
| `announce_phase_end` | none | same | |
| `cs_win_panel_match` | none | same | |
| `cs_win_panel_round` | show_timer_defend, show_timer_attack, timer_time, final_event, funfact_* | **missing** | the round's win panel |
| `start_halftime` | none | **missing** | |
| `cs_intermission` | none | **missing** | |
| `cs_pre_restart`, `cs_match_end_restart` | none | **missing** | |
| `round_announce_match_start`, `_warmup`, `_last_round_half`, `_match_point`, `_final`; `warmup_end` | none | **missing** | announcer lines; `round_announce_final` is also the "last round" music cue |
| `round_time_warning` | none | **missing** | |
| `cs_round_start_beep`, `cs_round_final_beep` | none | **missing** | freeze countdown beeps |
| `game_phase_changed` | new_phase (short, 0 to 5) | **missing** | |
| `team_intro_start`, `team_intro_end` | none | **missing** | |
| `buytime_ended` | none | same | |
| `match_end_conditions` | frags, max_rounds, win_rounds, time | **missing** | |
| `game_start` | roundslimit, timelimit, fraglimit, objective | **missing** | |
| `game_end` | winner | **missing** | |
| `team_score` | teamid, score | **missing** | the HUD's score change |
| `round_start_pre_entity`, `round_start_post_nav`, `teamplay_round_start {full_reset}`, `round_end_upload_stats`, `update_matchmaking_stats` | | **missing** | engine and stats plumbing; not needed |
| `switch_team`, `teamchange_pending {userid, toteam}`, `jointeam_failed {userid, reason}` | | **missing** | not needed with bots |
| `vote_started`, `vote_changed`, `vote_cast`, `vote_ended`, `vote_options`, `start_vote` | | **missing** | timeouts and surrender by vote |

### 5.2 Players and kills

| Event | CS2 keys | Project | Note |
|---|---|---|---|
| `player_spawn` (core) | userid | same | |
| `player_spawned` (mod) | userid, inrestart ("true if restart is pending") | **missing** | CS's own spawn event; `player_spawn` also exists, so keep that |
| `player_team` | userid, team, oldteam, disconnect, silent, isbot (+ name in core) | same, minus name | |
| `player_death` | userid, attacker, assister, assistedflash, weapon, weapon_itemid, weapon_fauxitemid, weapon_originalowner_xuid, headshot, dominated, revenge, wipe, penetrated, noreplay, noscope, thrusmoke, attackerblind, distance (**meters**), dmg_health, dmg_armor, hitgroup, attackerinair | same minus the item ids and noreplay | CS2's `distance` is "distance to victim in meters"; the project should state which unit it uses. CS2's `weapon` has no `weapon_` prefix (the project keeps it; already noted in contracts.md) |
| `player_hurt` | userid, attacker, health, armor, weapon, dmg_health, dmg_armor, hitgroup | same | |
| `other_death` | otherid, othertype, attacker, weapon, ... | missing | chickens and the like; not needed |
| `player_score` | userid, kills, deaths, score | missing | |
| `player_avenged_teammate` | avenger_id, avenged_player_id | missing | |
| `show_deathpanel` / `hide_deathpanel` | victim, killer, killer_controller, hits_taken, damage_taken, hits_given, damage_given | missing | the death panel's damage summary |
| `bullet_damage` | victim, attacker, distance, damage_dir, num_penetrations, no_scope, in_air, shoot and aim-punch angles, tick data, inaccuracy, recoil_index, type | missing | per-bullet diagnostics; useful for tests |
| `player_falldamage` | userid, damage (float) | same | |
| `player_blind` | userid, attacker, entityid, blind_duration | same | |

### 5.3 Items and buying

| Event | CS2 keys | Project | Note |
|---|---|---|---|
| `item_purchase` | userid, team (short), loadout (short), weapon (string) | same (team as "T"/"CT") | |
| `item_pickup` | userid, item, silent, defindex | minus defindex | CS2's `item` is the short name ("either a weapon such as 'tmp' or 'hegrenade'"); the project uses the class name |
| `item_pickup_failed` | userid, item, reason, limit | **missing** | a purchase or pickup refused ("You can only carry..."); the buy menu's failure line could listen for it |
| `item_pickup_slerp` | userid, index, behavior | missing | pickup animation |
| `item_remove` | userid, item, defindex | minus defindex | |
| `item_equip` | userid, item, defindex, canzoom, hassilencer, issilenced, hastracers, weptype, ispainted | minus defindex, hastracers, ispainted | `weptype`: -1 unknown, 0 knife, 1 pistol, 2 SMG, 3 rifle, 4 shotgun, 5 sniper, 6 machine gun, 7 C4, 8 grenade (the file's own comment) |
| `ammo_pickup` | userid, item, index | same | |
| `enter_buyzone` / `exit_buyzone` | userid, canbuy | same | |
| `buymenu_open` | none | **missing** | |
| `buymenu_close` | userid | **missing** | |
| `ammo_refill` | userid, success | missing | |
| `silencer_on`, `silencer_off`, `silencer_detach`, `inspect_weapon`, `weapon_zoom_rifle` | userid | missing | |

### 5.4 The bomb

| Event | CS2 keys | Project | Note |
|---|---|---|---|
| `bomb_beginplant`, `bomb_abortplant` | userid, site (short, "bombsite index") | same, site "A"/"B" | |
| `bomb_planted`, `bomb_defused`, `bomb_exploded` | userid, site, **c4** (short) | missing `c4` | `bomb_exploded.userid` is "player who planted the bomb" |
| `bomb_dropped` | userid, entindex | same | |
| `bomb_pickup` | userid (pawn) | same | |
| `bomb_begindefuse` | userid, haskit | same | |
| `bomb_abortdefuse` | userid | same | |
| `bomb_beep` | entindex | left out on purpose | |
| `defuser_dropped` / `defuser_pickup` | entityid (+ userid) | same | |
| `enter_bombzone` / `exit_bombzone` | userid, hasbomb, isplanted | same | |
| `player_given_c4` | userid | same | |

### 5.5 Grenades

The same as the project, with one difference: **CS2's `grenade_bounce` carries only
`userid`**, and the project adds x, y, z. `decoy_started.userid` is a pawn. There
is also `tagrenade_detonate` (unused).

### 5.6 What the economy needs that the schema lacks

- Nothing is missing for paying money. But `round_end.player_count` should be the
  living count, as CS2 defines it, if anything reads it.
- For the $50 per dead T, the economy needs every T death since `round_start`. It
  already counts `player_death`s. **Inferred**: the payout counts T deaths of any
  kind. That needs measuring: does a T killed by the bomb, or one who suicides,
  count?
- For money banked until next round, the economy needs to know when a round's money
  is handed over. `round_end` (or `round_prestart`) is enough, with no new event.
- The buy menu would want `item_pickup_failed` (reason, limit), `buymenu_open` and
  `buymenu_close` if it ever needs CS2's refusal messages from the server rather
  than working them out itself.

---

## 6. Answers to the repo's open guesses

From `reference/systems/economy.md` "Guesses, and what measures them", and
`reference/cs2-systems.md` E1 and E2.

| Guess | Verdict | Evidence | Still to measure |
|---|---|---|---|
| Loss ladder arithmetic (start at 1, pay 1400 + 500 x place then step up, cap 4; a win steps down one) | **Settled** (formula); timing **Inferred** | GT scoreboard.js `_RoundLossBonusMoneyForTeam`: `cash_team_loser_bonus + clamp(n, 0, mp_consecutive_loss_max) x cash_team_loser_bonus_consecutive_rounds`; tooltip "will earn $X with a round loss"; `mp_consecutive_loss_aversion` description; CFG `mp_starting_losses 1` | E1's "$1,400 for a pistol winner who loses round 2" is still a cheap check. Also: where the count starts in overtime, and whether a draw moves it |
| Ts alive when time runs out get no loss bonus | **Settled** that the rule exists (no convar) | SS `#Team_Cash_Award_No_Income`, EN " +$0 penalty for running out of time"; PS `AddTeamMoney` "not eligible to receive end-of-round money"; EN tournament highlight texts; community | Whether their side still steps up the ladder (**Inferred** yes), and whether they keep that round's kill awards (**Inferred** yes) |
| A death credited to no one moves no money | **Contradicted for suicides**; world and blast deaths **open** | SS/EN `Player_Cash_Award_ExplainSuicide_*` (an enemy is paid compensation for a suicide); `Team_Cash_Award_No_Income_Suicide` "+$0 penalty for suiciding"; `mp_disconnect_kills_players 1` (a disconnect is a death) | Who gets the compensation and how much (community: the kill award they could have had, to a random enemy when nobody damaged the player); whether a fall and a blast death count as suicides; whether the suicider loses their loss bonus |
| Helmet alone $350 | **Community figure, disputed** on the condition | bo3.gg / Steam threads (armour above 0 vs at 100); `SellbackPurchaseEntry_t.m_nPrevArmor/m_bPrevHelmet` shows a refund restores armour | E2: the price with damaged kevlar |
| Buy time counts from freeze end | **Community agrees**; files say "after round start" | CV `mp_buytime` description; totalcsgo / csgo-nade summaries; **Inferred** that round start = freeze end | E2, one stopwatch check |
| Warmup: buying open throughout, $800 | **Contradicted on money** (community) | Community: money is set to the mode's cap, $16,000; CV `mp_warmup_items_nocost 0` (not free), `nocount_policy 42`, `drop_policy 247`; `mp_warmup_offline_enabled 0` (**no warmup offline**) | E2: warmup money |
| Menu key order 1 pistols ... 5 grenades, undo by right-click | **Likely contradicted** | buymenu.xml `CategoryContainer1..5` = equipment, pistols, mid-tier, rifles, grenades, flowing left to right; refund is its own button on each item (`SellbackButton`) plus DEL `sellbackall` | E2: the key labels on screen (the file fills them at run time) |
| Short-handed bonus (not built) | **Rules found, timing disputed** | CFG 1000; CV delay 2, kicked players ignored; SS/EN eligibility notices; Valve 2021 "per round loss" vs fandom "at round start" | E1, only if the project ever lets a team be short |
| `cash_team_per_dead_enemy 50` "no file says what it pays" | **Settled** | Appeared 2025-07-16 (GT@05b3cdb1 vs GT@9b9a3d4d); press coverage of that update: each CT gets $50 per T eliminated, win or lose; SS/EN "team income for N eliminated terrorists" | CT only or both sides (EN has a CT-death string too); whether non-kill T deaths count; paid at round end (**Inferred**) |
| (new) Kill awards spendable at once | **Contradicted** | `m_iMoneyEarnedForNextRound`, PS `AddMoneyEarnedForNextRound` vs `AddMoneySpendableNow`, SS `Not_Enough_Money_NextRound` "$X that you just earned cannot be spent this round" | When the banked money reaches the account (round end or next round's start) |
| (new) Defuse win pays $3,250 | Already right in the repo ($3,500) | CFG overrides CV's 3250 | none |
| (new) Grenade purchase cap | **Open** | EN `SFUI_BuyMenu_CanOnlyPurchaseTotalXGrenades` "You can only purchase {n} grenades", separate from the carry limit; SS "hit the sellback limit" | How many grenades a round can be bought, and the refund limit |

### Suggested additions to the Local tasks

- **E1** (local server, `mp_logmoney 1`, which prints lines of the form
  `money change A+B = $C (reason)`). Check the $50 per dead T (CT only? counted on
  a bomb death or a suicide?), when kill money becomes spendable, who is paid for a
  suicide and how much, a fall death and a blast death, the loss count in overtime
  and after a draw, and what a simultaneous wipe ends as.
- **E2**. Check warmup money, the helmet price on damaged kevlar, the menu's key
  labels, the grenade purchase cap, and whether a refund works outside the zone
  during buy time.
