# The bomb, the six grenades, and dropping and picking up: how CS2 does them

Research for CSGODOT, 2026-09-24. It adds to `reference/cs2-systems.md` sections 4, 6 and 7,
`reference/systems/bomb.md`, `reference/systems/grenades.md` and the drop table in
`reference/systems/contracts.md`, and does not repeat what they already settle.

## How this was researched, and what could not be reached

- **The game's own files** come from SteamDatabase's GameTracking-CS2 at commit d45f52d
  (2026-09-23), cited as GT `<path>` (URL form
  `https://github.com/SteamDatabase/GameTracking-CS2/blob/master/<path>`). Besides the
  convars, schemas, `weapons.vdata`, gamemode configs and localisation, three string dumps
  were useful: GT `game/csgo/bin/win64/server_strings.txt` and `client_strings.txt` (the
  printable strings inside `server.dll` and `client.dll`: log formats, debug messages, sound
  event names) and GT `content/csgo_addons/cs_script_demo/maps/scripts/point_script.d.ts`
  (Valve's typed API for map scripts).
- **The web could only be searched, not read.** WebFetch and curl were refused by the
  egress proxy for every site tried (counter-strike.net, Steam, Liquipedia, Reddit, the
  Valve Developer wiki, HLTV, Dust2.us, fandom and others). Only `raw.githubusercontent.com`
  was reachable. Web claims below therefore come from **search-result summaries**. Each one
  is cited by the URL the result named, and marked "(search summary)". Treat those as weaker
  than a quote, and re-read the page before relying on one.
- **Valve's release notes** could not be opened, so none is quoted word for word. The July
  2026 bomb notes are given as the Fandom patch page and news sites paraphrased them. Where
  several sources repeat the same sentence, it is marked as close to Valve's wording.
- **Nothing from Valve's leaked CS:GO source was used.** One source in the bomb-damage
  section, the `cs2-c4-damage` project, rests on a third party's reverse engineering of
  CS2's `client.dll` and `server.dll`. That is not the leak, but it is marked where used.
  Only its stated findings are cited, not its code. The file-format facts come from
  ValveResourceFormat, which is MIT-licensed.

Markers: **Inferred** (my reading of a name or value, not stated anywhere), **From memory**
(my own knowledge, not checked against a source), **Disputed** (sources disagree; both sides
given).

---

## 1. The bomb

### 1.1 The game's own values (convars, configs, schemas)

| Setting | Default | Competitive | Source |
|---|---|---|---|
| `mp_c4timer` | 40 (min 10) | 40 | GT `DumpSource2/convars.txt` |
| `mp_give_player_c4` | true: "Whether this map should spawn a c4 bomb for a player" | | convars.txt |
| `mp_anyone_can_pickup_c4` | false: "everyone can pick up the c4, not just Ts" | | convars.txt |
| `mp_death_drop_c4` | true | | convars.txt |
| `sv_spawn_afk_bomb_drop_time` | 15: "Players that have **never moved since they spawned** will drop the bomb after this amount of time" | | convars.txt |
| `mp_c4_cannot_be_defused` | false | | convars.txt |
| `mp_plant_c4_anywhere` | false | | convars.txt |
| `mp_defuser_allocation` | 0 (0 none, 1 random, 2 everyone) | 0 (casual 2) | convars.txt; GT `game/csgo/cfg/gamemode_competitive.cfg`, `gamemode_casual.cfg` |
| `mp_death_drop_defuser` | true | 1 | convars.txt; competitive cfg |
| `mp_roundtime_defuse` | 0 (use `mp_roundtime`) | 1.92 min | competitive cfg |
| `cash_player_bomb_planted` / `_defused` | 300 / 300 | 300 / 300 | convars.txt; competitive cfg |
| `cash_team_win_by_defusing_bomb` | **3250** | **3500** | convars.txt vs competitive cfg (the cfg overrides it) |
| `cash_team_planted_bomb_but_defused` | 600 | 600 | same |
| `cl_predict_bomb_defusal` | true (dev only) | | convars.txt: the client predicts the defuse |
| `sv_c4_upright_constraint_enabled` / `_strength` / `_damping` | true / 0.6 / 0.5: "Use a constraint to keep C4 pointed upright when thrown" | | convars.txt |
| `player_use_radius` | 80 (cheat, no description) | | convars.txt |
| `sv_use_hi_pri_context_switch_time` | 1: "+use search behaves as though high priority items are usable for this long after they become unusable" | | convars.txt |
| `contributionscore_bomb_planted` / `_defuse_major` / `_defuse_minor` / `_exploded` | 2 / 3 / 1 / 1 | | convars.txt (scoreboard points, not money) |

C4 in `weapons.vdata` (GT `game/csgo/pak01_dir/scripts/weapons.vdata`, the `c4` prefab):
`m_flDeployDuration` 1.233333, `m_flMaxSpeed` 250, `m_nKillAward` 300, `m_nPrice` 0,
`GEAR_SLOT_C4`. There is no `m_flDropSpeed` override for it or any other weapon, so the class
default of **300** applies (section 3.2).

The schemas that decide the rules:
- `CC4` (GT `DumpSource2/schemas/server/CC4.h`) has `m_bStartedArming`, `m_fArmedTime`,
  `m_bIsPlantingViaUse`, `bool[7] m_bPlayedArmingBeeps`, `m_vecLastValidPlayerHeldPosition`,
  `m_vecLastValidDroppedPosition`, `m_bDoValidDroppedPositionCheck`, `m_nSpotRules` and
  `m_entitySpottedState`.
- `CPlantedC4` (`CPlantedC4.h`) has `m_flC4Blow`, `m_flTimerLength`, `m_flDefuseLength`,
  `m_flDefuseCountDown`, `m_hBombDefuser`, `m_bBeingDefused`,
  `m_bAbortDetonationBecauseWorldIsFrozen`, `bool[4] m_bVoiceAlertPlayed`,
  `m_flNextBotBeepTime` and `m_angCatchUpToPlayerEye`.
- The client's `C_PlantedC4` (fetched from GT `DumpSource2/schemas/client/C_PlantedC4.h`)
  adds `m_flNextBeep`, `m_flNextGlow`, `m_bTenSecWarning`, `m_flNextRadarFlashTime`,
  `m_bRadarFlash` and `m_hDefuserMultimeter`.
- `CTriggerBombReset` exists (`trigger_bomb_reset` in server_strings.txt): a brush that
  sends a dropped bomb back to its last valid position, which is what the two
  `m_vecLastValid…Position` fields are for (**Inferred** from the names).
- `CCSPlayerPawn` has `m_bInBombZone`, `m_bInNoDefuseArea`, `m_bIsDefusing`,
  `m_iBlockingUseActionInProgress` (enum `CSPlayerBlockingUseAction_t`: DefusingDefault = 1,
  DefusingWithKit = 2, …; GT `DumpSource2/schemas/client/CSPlayerBlockingUseAction_t.h`),
  `m_fLastGivenBombTime` and `m_fLastGivenDefuserTime`.
- `CCSPlayer_MovementServices` has `m_flBombPlantViewOffset`, found in server_strings.txt
  as `NetworkVar_m_flBombPlantViewOffset`: the planter's eyes drop while planting.

### 1.2 Planting

- **Where and how.** Localisation (GT `game/csgo/pak01_dir/resource/csgo_english.txt`):
  - "C4 must be planted at a bomb site"
  - "You must be standing on the ground to plant the C4"
  - "Arming sequence canceled\nC4 can only be placed at a bomb target", when you leave the
    zone mid-plant
  - "Hold to Plant Bomb"

  So the rules are: on the ground, inside the site, and holding the button.
  `bomb_beginplant` and `bomb_abortplant` exist (GT `game/csgo/pak01_dir/resource/mod.gameevents`).
  Crouching while planting is allowed (**From memory**).
- **Planting with E.** `m_bIsPlantingViaUse` shows CS2 can plant with the use key. Players
  describe holding E in a bomb zone switching to the bomb and planting it
  ([Steam discussion](https://steamcommunity.com/app/730/discussions/0/1734336452549558758/), search summary).
- **Plant time. Disputed.**
  - **3.2 s** is what CS2 guides give
    ([cs.money](https://cs.money/blog/games/all-c4-secrets/),
    [gamertagmythras](https://gamertagmythras.com/blog/counter-strike-2/cs2-bomb-timer-defuse-blast-guide),
    [cs2guide.net](https://cs2guide.net/gameplay-mechanics/bomb-planting-mechanics/);
    search summaries). One source says about 3.5 s.
  - **3.0 s** is CS:GO's figure ([Fandom C4](https://counterstrike.fandom.com/wiki/C4_Explosive), search summary; also **From memory**).
  - No file gives the arming time. `m_bPlayedArmingBeeps` has 7 entries, which matches the 7
    key presses in the first-person clip (0.67 to 2.17 s, `reference/weapons/equipment.md`).
  - The draw (1.23 s) comes before any of this if the bomb was not already in hand.
  - C1 still has to time it from pressing the button to `bomb_planted`.
- **Held still.** CS:GO and CS2 freeze the planter's movement (**From memory**). The eye
  offset above lowers the view.

### 1.3 The timer, the beeps and the last ten seconds

- 40 s from arming (`mp_c4timer`: "how long from when the C4 is armed until it blows").
- **Beep cadence.** The client schedules beeps from the fraction of the timer done: client.dll
  holds the debug line "C4 Sounds: Playing sound %s at %f bomb detonation in %fs at %f;
  fComplete = %f" (GT `client_strings.txt`). The best public fit is Wouter Gritter's CS:GO
  measurement (17 data points, fitted by regression), published as code at
  [WouterGritter/CSGO-Bomb `armed_state.ino`](https://github.com/WouterGritter/CSGO-Bomb/blob/master/armed_state.ino):

  beeps per second = 1.04865 × e^(0.244018·x + 1.763798·x²), where x is the fraction of
  the timer done (0 to 1).

  | Time left (of 40 s) | x | Beeps/s | Interval |
  |---|---|---|---|
  | 40 s | 0 | 1.05 | 0.95 s |
  | 30 s | 0.25 | 1.23 | 0.81 s |
  | 20 s | 0.5 | 1.76 | 0.57 s |
  | 10 s | 0.75 | 3.19 | 0.31 s |
  | 5 s | 0.875 | 4.93 | 0.20 s |
  | 0 s | 1 | 7.8 | 0.13 s |

  The fit is CS:GO's. The client string suggests CS2 kept the fraction-based schedule
  (**Inferred**). One search summary says "every 1.33 s at 40 s left"
  ([gritter.nl](https://gritter.nl/posts/csgo-bomb-beep-pattern/)); that does not match the
  fitted code and may be a misreading. C1 should check a few intervals in CS2.
- **Ten seconds left.** The client has `m_bTenSecWarning` and separate sounds
  `C4.PlantSound_10sec` and `C4.PlantSoundB_10sec`, beside `C4.PlantSound` and
  `C4.PlantSoundB` (client_strings.txt). The music `Music.BombTenSecCount` plays at 10 s.
  The HUD uses three pulse speeds (`BombPlantedPulse__Slow`, `__Medium`, `__Fast`). No
  mechanical rule changes at ten seconds. A kitless defuse (10 s) started after that point
  cannot finish, and the game lets the bomb win (`bomb.md` already has "a defuse that would
  end after the bomb goes off loses to it").
- `bomb_beep` {entindex} is a game event (mod.gameevents). The server keeps
  `m_flNextBotBeepTime`, so bots hear the beeps.

### 1.4 Defusing

- **Time:** 10 s, 5 s with a kit. `m_flDefuseLength` is networked. Localisation has
  "Defusing bomb WITH defuse kit." and "…WITHOUT…".
- **On the ground:** "You must be on the ground\nto defuse the bomb"
  (`Cstrike_TitlesTXT_C4_Defuse_Must_Be_On_Ground`).
- **One defuser:** "The bomb is already being defused." Defusing is a "blocking use action"
  (`m_iBlockingUseActionInProgress`).
- **Reach.** Defusing goes through the `+use` search (client_strings.txt:
  "CPlantedC4::Use() start defusal"). That search:
  - reaches `player_use_radius` 80 (**Inferred** that this is the reach);
  - is cone-based: `sv_weapon_swap_difficulty_near_hi_pri` talks of "cone searches" and
    "high priority items". The planted bomb is a high-priority use target (**Inferred**).

  The repo's guess of eyes within 90 units and a 40° aim cone is close. 80 is the game's
  number for the radius; the cone angle is not in any file. **Still needs measuring (C1).**
- **From above, and through walls.** In November 2024 players found they could defuse from
  "virtually any height" if they could see the bomb below them (Nuke silos, Mirage B box,
  Dust2 B window). Valve fixed this in a later update, which the news called removing the
  defuse kit "extension cords"
  ([Dust2.us](https://www.dust2.us/news/54820/new-cs2-bug-lets-you-defuse-from-virtually-any-height),
  [Dust2.us fix](https://www.dust2.us/news/54891/latest-cs2-update-brings-improved-hit-reg-removes-defuse-kit-extension-cords),
  [Fandom, Nov 6 2024 patch](https://counterstrike.fandom.com/wiki/Counter-Strike_2_patches/November_6,_2024);
  search summaries). The use search therefore needs a line of sight to the bomb, and today
  a height limit as well (**Inferred**). A defuse through a solid wall is not possible
  (**From memory**).
- **Fake defuses, October 2025.** In beta 1.41.3-rc1 (2025-10-14), defusing lowers the
  viewmodel, blocks scoping, and delays the first shot by **150 ms** after leaving the defuse
  ([HLTV](https://www.hltv.org/news/42951/valve-adjust-defuse-mechanics-in-cs2-beta-update),
  [esportsinsider](https://esportsinsider.com/2025/10/cs2-defuse-mechanic-changes);
  search summaries). DMarket's write-up of the live update repeats it: "After exiting defuse,
  the following shot is delayed by 150ms"
  ([DMarket](https://dmarket.com/blog/cs2-update-c4-adjustments-and-map-scripting/), search
  summary). **Inferred** to be live now; the exact date is not confirmed.
- **No bomb after the match or at halftime.** The same update: "There is no more C4
  detonation after the match and in between the halves" (DMarket, search summary). This
  matches `m_bAbortDetonationBecauseWorldIsFrozen` in `CPlantedC4.h`.
- **Ninja defuse, instant defuse.** No special rule exists. A defuse only needs the timer to
  outlast the defuse time. There is no instant defuse: the "defused with 0.049 s left"
  highlight in csgo_english.txt shows how close a finish can be. Nothing in the files shows
  a defuse that lets go and resumes: letting go starts it over (**From memory**; `bomb.md`
  already has it).

### 1.5 The explosion

**Before July 2026 (the old rule, which the repo builds today).** The damage is
`info_map_parameters` `bombradius` (500 by default), reaching 3.5 times that (1,750 units),
and walls do not matter: "the engine only takes in consideration pure distance"
([Dignitas](https://dignitas.gg/articles/blogs/CSGO/8189/bomb-survival-a-guide-to-surviving-the-blast-radius),
[cs.money](https://cs.money/blog/games/all-c4-secrets/); search summaries). server.dll still
holds "Bomb Damage is %.0f, Radius is %.0f" (server_strings.txt). The per-map baked data
also keeps a legacy fallback: "Native legacy fallback exists" (cs2-c4-damage `docs/model.md`,
below).

**The July 2026 shockwave, as reported** (Valve's page could not be opened):

- **8 July 2026.** Wording that recurs across the Fandom patch page, Dust2.us and fpshub,
  close to Valve's:
  - "Re-designed the effective range and extent of C4 explosion damage on all official
    defusal-mode maps."
  - "Damage is now applied according to precomputed simulation values, baked into the
    compiled map."
  - "Explosion shockwave damage now rapidly expands from the center of the explosion instead
    of being applied instantly."

  The blog text says the shockwave spreads "rapidly (but not instantly) from that point
  through any available path"; the damage "does not pass through walls"; "The shockwave can
  still spread around corners" and "dissipates around corners"; and the health bar previews
  the damage you would take.
  ([Fandom July 8 2026](https://counterstrike.fandom.com/wiki/Counter-Strike_2_patches/July_8,_2026),
  [Dust2.us](https://www.dust2.us/news/75797/cs2-july-8th-update-brings-bomb-explosion-re-design-new-armory-items),
  [insider-gaming](https://insider-gaming.com/counter-strike-2-july-update-bomb-rework/);
  search summaries.)
- **9 July 2026:**
  - "Removed map-wide minimum one point of damage from new C4 explosions."
  - "Fixed a case where new C4 damage was calculated incorrectly near boundaries to other map
    areas."
  - "New C4 explosions now apply more force to dropped weapons."

  ([SteamAnalyst July 9 2026](https://www.steamanalyst.com/updates/counter-strike-2-update-2026-07-09), search summary.)
- **20 or 21 July 2026:**
  - The C4 explosion "disperses active smoke clouds and extinguishes molotov/incendiary fire
    in its blast radius".
  - The damage preview on the health bar is "revealed when the bomb becomes audible", so it
    no longer gives away where the bomb is.
  - The bomb-damage bar is animated.

  ([Dust2.us](https://www.dust2.us/news/76184/latest-cs2-update-brings-big-changes-to-how-the-bomb-interacts-with-utility),
  [insider-gaming](https://insider-gaming.com/cs2-update-bomb-smoke-interaction/),
  [skin.club](https://community.skin.club/en/news/cs2-update-c4-now-affects-smokes-and-fire);
  search summaries.)
- **Sound events** in server.dll: `c4.shockwave.boom`, `c4.shockwave.hit`, `c4.explode`
  (server_strings.txt). The client's HUD element is `ExpectedBombHealthBar`.

**The baked file can now be read (this answers most of C2).** ValveResourceFormat (MIT)
decodes `maps/<map>/baked_bomb_damage.vdata`, generic data type `CS2_BOMB_DAMAGE_DATA`,
versions 1 and 2.
([`BombDamage.cs`](https://github.com/ValveResourceFormat/ValveResourceFormat/blob/8a322d749c605c36e4e31b4ba34c70a5fd96c884/ValveResourceFormat/Resource/ResourceTypes/GenericData/CS2/BombDamage.cs),
[`BombDamageBombsite.cs`](https://github.com/ValveResourceFormat/ValveResourceFormat/blob/8a322d749c605c36e4e31b4ba34c70a5fd96c884/ValveResourceFormat/Resource/ResourceTypes/GenericData/CS2/BombDamageBombsite.cs),
[`BombDamageDamageValue.cs`](https://github.com/ValveResourceFormat/ValveResourceFormat/blob/8a322d749c605c36e4e31b4ba34c70a5fd96c884/ValveResourceFormat/Resource/ResourceTypes/GenericData/CS2/BombDamageDamageValue.cs),
read through raw.githubusercontent.)

| Blob (in `data`) | Layout |
|---|---|
| `bombsites` | 7 floats per site: bounds min xyz, bounds max xyz, `BombPower`. "The game expands them by 32 units on each axis when loading." |
| `positions` | 3 int16 per point (world x, y, z) |
| `damage_values` | 4 bytes per (site, point): `Phase` uint16 little-endian, `Yaw` uint8, `Pitch` uint8. Index = `positionCount × siteIndex + positionIndex`. Count must equal sites × points. |

**This is the repo's "8 bytes a point":** dust2 has 2 sites × 4 bytes each.

- **Damage.** With `MaxDamage` = 100 and `MaxPhase` = 1800:

  damage = clamp(100 − 100 × (Phase − BombPower) / min(Phase, 1800), 0, 255)

  At Phase 0 the damage is 100, or 0 when BombPower ≤ 0. Up to Phase 1800 this reduces to
  **100 × BombPower / Phase**. "Phase" is described as the "effective distance from the
  bombsite used for damage falloff", which is the distance the shockwave travels along its
  path, not a straight line. `BombPower` is "approximately the distance at which the bomb
  deals 100 damage". Past Phase 1800 the fall-off becomes linear, reaching 0 at
  BombPower + 1800. (**Inferred** from the formula.)
- **Yaw and Pitch** give the direction the blast arrives from: rotate unit X by Yaw/256 of a
  turn about Z, then by Pitch/256 of a turn about Y.
- **Build checked.** For Mirage on build 25218825 the file holds 2 sites, 68,177 points and
  136,354 records ([cs2-c4-damage `docs/research/native-query-closure.md`](https://github.com/Starfie1d1272/cs2-c4-damage/blob/main/docs/research/native-query-closure.md)).
  The repo's dust2 count of 85,697 points fits the same format.
- **How the game reads it.** From the Apache-2.0 project
  [cs2-c4-damage](https://github.com/Starfie1d1272/cs2-c4-damage) (`README.md`,
  `docs/model.md`). **Its evidence is a third party's static reverse engineering of CS2's
  DLLs, credited to "unicbm"; treat it as scoped to that build.** It reports:
  - the query picks the site by the expanded box and takes the nearest point (a KD-tree);
  - the damage byte is an integer, truncated and clamped;
  - there is a crouch and facing correction that applies only below 100 damage (crouch
    enters it as "0.45", described as "a nonlinear Bias parameter, not a multiplier");
  - **standard C4 damage ignores armour**;
  - a second, ground-corrected sample is taken in some cases, and exactly when is not
    worked out.

  The project refuses to promise exact predictions for these reasons.

**Consequence for the repo:** build C2's decoder from the VRF layout. Then take damage as
100·power/phase at the nearest baked point of the planted site. The armour, crouch and facing
effects are for C1 to measure.

### 1.6 Carrying, dropping, picking up; who gets it

- **At round start** one T gets it (`mp_give_player_c4`). Guides say one of the Ts,
  implying at random ([csdb](https://csdb.gg/commands/sv_spawn_afk_bomb_drop_time/), search
  summary; **From memory**: random). **Corrected 2026-09-26** (playtest-2026-09-25.md
  issue 18): with bots, not among all Ts. GT `game/csgo/cfg/gamemode_competitive.cfg` sets
  `bot_defer_to_human_items 1` and `bot_defer_to_human_goals 1`, and the convar dump
  describes the first as "If nonzero and there is a human on the team, the bots will not get
  scenario items". So a human T gets it whenever there is one; a bot only on a side of bots.
  It also stops a bot's touch pickup of a bomb a living human T dropped, and warmup hands
  out no bomb (both seen in CS2 by Sid, 2026-09-26). `CCSPlayerPawn.m_fLastGivenBombTime` may mean the
  choice leans away from whoever had it last (**Inferred** from the name alone; not
  confirmed). Warmup carries a drop policy (`mp_warmup_items_drop_policy` 247, where bit 2
  is c4).
- **Idle carrier.** `sv_spawn_afk_bomb_drop_time` 15 counts from **spawn**, for a player who
  has **never moved**, not from freeze end. Competitive freeze time is 15 s
  (`mp_freezetime 15`), so a player who never moves drops it at about the moment the freeze
  ends (**Inferred**). The chat line is "I dropped the bomb." (`Cstrike_TitlesTXT_Game_afk_bomb_drop`).
- **Dropping.** It is thrown like any weapon, at `m_flDropSpeed` 300 (the class default in
  GT `DumpSource2/schemas/server/CCSWeaponBaseVData.h`, which lists `"m_flDropSpeed":
  300.000000`, with no override in `weapons.vdata`). An upright constraint keeps it pointing
  up while it flies (`sv_c4_upright_constraint_*`). `bomb_dropped` {userid, entindex}. The
  drop is logged as `triggered "Dropped_The_Bomb"` (server_strings.txt).
- **Picking up** is by touch, Ts only (`mp_anyone_can_pickup_c4 false`). The sound is
  `Player.PickupC4`, the events are `bomb_pickup` {userid}, and the text is "You picked up
  the bomb". Re-pickup waits are the generic weapon ones (1.5 s for whoever dropped it, 1.3 s
  for anyone else; section 3.2). The bomb is a `CCSWeaponBase`, so it has
  `m_nextPrevOwnerTouchTime` and `m_nextOwnerTouchTime`. **Inferred** that the same waits
  apply to it.
- **An unreachable bomb** is returned by `trigger_bomb_reset` volumes to its last valid
  position (1.1).
- **On the radar.** The bomb and the planted bomb carry `m_entitySpottedState` and
  `m_nSpotRules`. Ts always see the bomb (carried, dropped, planted); CTs see it only once
  someone on their team spots it (**From memory**; the schema only shows that spotting
  rules exist). There are also `RadarBombPlantPulse` and `m_bRadarFlash`.

### 1.7 Money and credit

- **A kill by the blast credits nobody.** server.dll logs such a death as
  `"%s<%i><%s><%s>" [%.0f %.0f %.0f] was killed by the bomb.`, a victim-only line, unlike
  the attacker-and-victim kill format (server_strings.txt). The death panel reads "You were
  killed by the C4 explosion" (`DeathPanel_KilledByC4`). So the C4's `m_nKillAward` 300 is
  never paid. This backs `bomb.md`'s from-memory note.
- **The kit drops on death** (`mp_death_drop_defuser`), with `defuser_dropped` {entityid}.
  A fun fact exists for "defused the bomb with a dropped defuse kit".

---

## 2. Grenades

### 2.1 Every grenade convar (defaults; competitive where it differs)

From GT `DumpSource2/convars.txt` and `game/csgo/cfg/gamemode_competitive.cfg`.

| Convar | Default | Comp | Description / note |
|---|---|---|---|
| `ammo_grenade_limit_total` | 3 | **4** | |
| `ammo_grenade_limit_flashbang` | 1 | **2** | |
| `ammo_grenade_limit_default` | 1 | | every other type |
| `ff_damage_reduction_grenade` | 0.25 | **0.85** | "How much to reduce damage done to teammates by a thrown grenade" (1 = full) |
| `ff_damage_reduction_grenade_self` | 1 | 1 | |
| `ff_damage_reduction_other` | 0.25 | **0.4** | "things other than bullets and grenades" |
| `ff_damage_reduction_bullets` | 0.1 | **0.33** | (for comparison) |
| `ff_damage_decoy_explosion` | false | | |
| `sv_hegrenade_damage_multiplier`, `sv_hegrenade_radius_multiplier` | 1, 1 | | |
| `molotov_throw_detonate_time` | 2 | | air-burst time |
| `weapon_molotov_maxdetonateslope` | 30 | | "Maximum angle of slope on which the molotov will detonate" |
| `molotov_usethrow_direction` | false | | cheat |
| `sv_molotov_broken_glass_trap` | false | | |
| `inferno_max_flames` | 16 | | |
| `inferno_flame_spacing` | 42 | | "Minimum distance between separate flame spawns" |
| `inferno_max_range` / `_ct` | 150 / 110 | | "Maximum distance flames can spread from their initial ignition point" |
| `inferno_flame_lifetime` / `_incendiary` | 7 / 5.5 | | "Average lifetime of each flame" |
| `inferno_damage` / `_ct` | 40 / 40 | | "Damage per second" |
| `inferno_damage_timer` | 0.2 | | "How long between times for the inferno to deal damage" |
| `inferno_friendly_fire_duration` | 6 | | "For this long, FF is credited back to the thrower" |
| `inferno_initial_spawn_interval` | 0.02 | | "Time between spawning flames for first fire" |
| `inferno_child_spawn_interval_multiplier` | 0.1 | | "Amount spawn interval increases for each child" |
| `inferno_max_child_spawn_interval` | 0.5 | | "Largest time interval for child flame spawning" |
| `inferno_per_flame_spawn_duration` | 3 | | "Duration each new flame will attempt to spawn new flames" |
| `inferno_child_spawn_max_depth` | 4 | | |
| `inferno_spawn_angle` | 45 | | "Angular change from parent" |
| `inferno_spread_speed_mult` / `_ct` | 1 / 10 | | "Speed up the spreadrate … until max number of nodes are created" |
| `inferno_ct_experiment` | true | | "enable ct incendiary experiment" (the 110, 5.5, ×10 values) |
| `inferno_surface_offset` | 15 | | |
| `inferno_velocity_factor` / `_ct` | 0.003 / 0.003 | | how the throw's velocity pushes the spread (**Inferred**) |
| `inferno_velocity_decay_factor`, `inferno_velocity_normal_factor`, `inferno_forward_reduction_factor` | 0.2, 0, 0.9 | | |
| `inferno_smoke_volume_density` | 0.03 | | |
| `inferno_max_trace_per_tick` | 16 | | dev: the server caps the fire's traces per tick |
| `bot_max_visible_smoke_length` | 200 | | |
| `sv_flashed_amount_for_blind_kill` | 0.7 | | "Minimum flashed alpha value …" |
| `sv_grenade_collision_sphere` / `_radius` | **false** / 2 | | the sphere is off by default |
| `mp_shoot_dropped_grenades` | false | | "Dropped grenades detonate when shot" |
| `mp_drop_grenade_enable` | true | | |
| `mp_death_drop_grenade` | 2 | 2 | "0=none, 1=best, 2=current or best, 3=all". The convar's max is 2, so 3 cannot be set. |
| `sv_ignoregrenaderadio` | false | 0 | "Fire in the hole" |
| `sv_grenade_trajectory_time_spectator` | 0 | 4 | |
| `cl_grenadecrosshairdelay_*` | 2 | | lineup crosshair |
| `sv_smoke_volume_blind_start`, `cl_use_prompt_smoke_density` | 0.2, 0.03 | | client |
| `cl_smoke_torus_ring_radius` / `_subradius`, `cl_smoke_origin_height` | 61 / 88, 68 | | dev only: the drawn cloud's torus shape |
| `smoke_grenade_ct_color`, `smoke_grenade_t_color` | [75,127,155], [180,129,50] | | dev only |

**Nothing in the dump sets flash durations or fuses** (`sv_flash*` does not exist). They are
in code.

### 2.2 The six in `weapons.vdata`

All six share `m_flThrowVelocity` 750, `m_flDeployDuration` 1.0, `m_flMaxSpeed` 245 and
`m_nKillAward` 300 (GT `weapons.vdata`).

| Grenade | Price | `m_nDamage` | `m_flRange` | `m_flArmorRatio` |
|---|---|---|---|---|
| HE | 300 | 99 | 350 | 1.2 |
| Flashbang | 200 | 50 | 4096 | 1.0 |
| Smoke | 300 | 50 | 4096 | 1.0 |
| Molotov | 400 | 40 | 4096 | 1.8 |
| Incendiary | 500 | 40 | 4096 | 1.475 |
| Decoy | 50 | 50 | 4096 | 1.0 |

The 50s look like placeholders. The molotov and incendiary armour ratios do not decide fire
damage: the repo already has armour not softening fire (**From memory**). The C4 has an
`m_nKillAward` too (1.7).

### 2.3 The throw

- **The game stashes the throw at a jump.** `CCSPlayerPawn` has `m_grenadeParameterStashTime`,
  `m_bGrenadeParametersStashed`, `m_angStashedShootAngles`, `m_vecStashedGrenadeThrowPosition`,
  `m_vecStashedGrenadeThrowPawnCenter` and `m_vecStashedVelocity`, and `CBaseCSGrenade` has
  `m_bJumpThrow` (GT `CCSPlayerPawn.h`, `CBaseCSGrenade.h`). The sounds
  `BaseGrenade.JumpThrowF` and `…M` are in server_strings.txt: the grunt that confirms a
  jump-throw. On 19 August 2024 Valve removed binds that do more than one action, saying
  "Jump-throws became such an important part of the game that we've done the work to make
  them reliable without any special scripting or binds (i.e., by jumping and quickly
  throwing a grenade)."
  ([HLTV](https://www.hltv.org/news/39658/valve-take-stance-against-snap-tap-like-features-remove-jump-throw-binds),
  [Dust2.us](https://www.dust2.us/news/51933/cs2-8-19-update-null-binds-snaptap-and-jump-binds-banned-in-latest-update);
  search summaries.) So when a jump and a throw release come close together, the throw uses
  the angles, position and velocity stashed at the jump (**Inferred** from the fields and
  the note). **Disputed window:** guides say about 200 ms, or about 50 ms for precise
  lineups
  ([skin.club](https://community.skin.club/en/news/cs2-jumpthrow-timing-fps-error-window),
  search summary). Needs measuring.
- **Other throw fields:** `m_flThrowStrength`, `m_fPinPullTime`, `m_nNextHoldTick` and
  `m_flNextHoldFrac` (subtick hold timing), `m_fThrowTime`, and `m_hSwitchToWeaponAfterThrow`.
- **Throw speeds per button, and how much of your velocity is added:** no CS2 source found.
  The repo's CS:GO values (750 × 0.9, strength 0.3 to 1, 1.25 of your velocity) stand until
  G1.
- **Spin.** The map-script API gives a thrown grenade a default angular velocity of
  `{600, rand(-1200,1200), 0}` (GT `…/point_script.d.ts`, `SpawnGrenadeProjectileConfigWithOwner`).
- **Collision.** `sv_grenade_collision_sphere` is **false** by default. Without it the
  projectile collides with its own physics shape, not a radius-2 sphere (**Inferred**). The
  repo's radius-2 sphere is what the game uses only when the convar is on.
- **Settling:** `m_nTicksAtZeroVelocity`, `m_nBounces`, `m_vecLastHitSurfaceNormal`
  (`CBaseCSGrenadeProjectile.h`). The rest check counts ticks at zero speed; no threshold is
  given.
- **Changes to throws, 2024 to 2026** (search summaries):
  - Aug 2026: grenades thrown through level geometry fixed
    ([Dust2.us](https://www.dust2.us/news/76553/august-3rd-cs2-update-fixes-grenade-clipping-bug)).
  - Earlier: "Improved consistency of grenade jump throws and the accuracy of the jump throw
    preview camera"
    ([cs2tricks](https://www.cs2tricks.com/posts/how-to-jump-throw-and-run-throw-grenades-in-cs2-7b46)).

### 2.4 HE

- 99 damage, reaching 350, armour ratio 1.2 (vdata). The HE's explosion type carries forces
  (`m_bHasForces` on `grenade`, GT `game/csgo/pak01_dir/scripts/explosion_types.vdata`), so
  it pushes physics objects such as dropped guns.
- **29 or 30 January 2026:** "damage from HE grenades that explode mid-air near the ground
  will no longer be calculated as if they exploded on the ground"
  ([Escorenews](https://escorenews.com/en/csgo/news/75490-cs2-update-fixes-he-grenade-bug-that-caused-decreased-damage),
  search summary).
- **30 March 2023 (the limited test):** "HE grenades no longer affect smokes through walls"
  ([Sportskeeda](https://www.sportskeeda.com/esports/news-counter-strike-2-march-30-official-patch-notes-addresses-he-grenades-affecting-smoke-wallhack-command-inspect-visuals),
  search summary).
- **The smoke hole:** "a massive gap … for about 2-3 seconds before it re-expands"; bullet
  holes last "less than a second"
  ([cs.money](https://cs.money/blog/news/mythbusting-cs-2-smokes/), [thespike](https://www.thespike.gg/counter-strike-2/beginner-guides/how-to-use-smokes-cs2-guide);
  search summaries). The repo's 3 s fits. Its 128-unit radius is still to measure.
- **Fuse:** no CS2 figure found (section 2.5).

### 2.5 Flashbang

- **The model is hold then fade.** server.dll prints "Blinded: holdTime = %3.2f, fadeTime =
  %3.2f, alpha = %3.2f" and logs `blinded for %.2f by … from flashbang entindex %d`. The
  pawn has `m_flFlashDuration`, `m_flFlashMaxAlpha`, `m_blindStartTime` and
  `m_blindUntilTime` (GT `CCSPlayerPawnBase.h`). There are three ringing sounds,
  `Flashbang.Ring.Short`, `.Medium` and `.Long` (server_strings.txt), so the sound comes in
  three strengths (**Inferred**). `player_blind` carries `blind_duration`. The projectile
  counts `m_numOpponentsHit` and `m_numTeammatesHit` (GT `CFlashbangProjectile.h`), both for
  stats.
- **Durations:** up to **4.87 s** looking straight at it
  ([cs2pulse](https://cs2pulse.com/flash-bangs/), search summary), which matches the repo.
  About 1 s with your back to it ([cs2apps](https://www.cs2apps.com/grenades/), search
  summary). **Disputed:** other guides give "up to 3 s" or "4.5 s"
  ([bo3.gg](https://bo3.gg/articles/how-long-do-cs2-grenades-last), search summary). No
  distance or angle curve for CS2 was found; G3 stands.
- **Fuse:** measured in CS:GO at a constant **1.40 s** from the grenade first appearing on
  screen to the first white frame
  ([David Durst](https://davidbdurst.com/blog/csknow_flashbang_length.html), search summary).
  The repo's 1.5 s is from the throw command, so the two can both hold if the grenade leaves
  the hand about 0.1 s after the command (**Inferred**). G1 should time throw to pop in CS2.
- **Flash through smoke:** no source found either way for CS2. Leave the repo's "smoke does
  not stop it" as a guess.
- **Blind kills:** a kill counts as blind at `sv_flashed_amount_for_blind_kill` 0.7 (flash
  alpha). `killswhileblind` and `assistedflash` are in server_strings.txt.

### 2.6 Smoke

- **Server side:** `CSmokeGrenadeProjectile` has `m_nRandomSeed`, `m_vSmokeDetonationPos`,
  the networked `m_VoxelFrameData` (a `uint8` vector) with `m_nVoxelFrameDataSize` and
  `m_nVoxelUpdate`, and **`m_bExplodeFromInferno`**. server.dll has
  `CSmokeGrenadeProjectileThink_BuildingSmokeVolume`, `…_Update` and `…_Remove`, the strings
  "Dense voxels", "Sparse voxels" and `voxel_size`, and the flag `allowsmokethrough`.
- **A smoke that lands in fire pops at once.** That is what `m_bExplodeFromInferno` names
  (**Inferred**; the name alone).
- **A smoke that covers a fire puts all of it out, once a third is covered.** server.dll
  debug: "**Molotov extinguished: when %d/%d fire areas were covered by smoke (exceeded
  1/3rd).**" (server_strings.txt). The fire is put out whole once more than a third of its
  flame areas are in smoke; the flames do not go out one by one. The sounds are
  `Molotov.Extinguish` and `SmokeGrenade.Clear`. `CInferno.m_bWasCreatedInSmoke` covers a
  fire started in smoke (a fizzle; `Molotov.StartFailed` and `IncGrenade.StartFailed` are
  sounds).
- **Duration. Disputed:**
  - **18 s**, "about 15 seconds of strong cover, while the full effect, including the fade,
    lasts about 18 seconds" ([Swap.gg](https://swap.gg/blog/how-long-does-smoke-last-in-cs2),
    search summary);
  - **20 s** ([bo3.gg](https://bo3.gg/articles/how-long-do-cs2-grenades-last), search
    summary).

  G4 decides it. Time `smokegrenade_detonate` to `smokegrenade_expired`.
- **The C4 blast clears it** (July 2026, 1.5).
- **Visuals only:** the torus shape convars in 2.1, the smoke colours per team, and
  "Unable to render more than %d smokes." (client_strings.txt).

### 2.7 Molotov and incendiary

- **Rules already in the repo:** the 2 s air burst, the 30° slope, 16 flames 42 apart,
  150 / 110 reach, 7 / 5.5 s, damage every 0.2 s, 6 s of team-damage credit.
- **How the flames spread** (**Inferred** from the convar descriptions):
  - the first fire lays flames every **0.02 s**;
  - each child's interval grows by **0.1 per child**, up to **0.5 s**;
  - each flame keeps trying to spawn children for **3 s**, no more than **4** generations
    deep, at up to **45°** from its parent;
  - `inferno_spread_speed_mult` (1 for the molotov, 10 for the incendiary) scales the rate
    until the 16 flames are placed;
  - the throw's velocity pushes the spread (`inferno_velocity_factor` 0.003, decaying by
    0.2).

  The repo's 0.2 s molotov interval is a guess the convars do not support. Its incendiary
  0.02 s appears to be the molotov's first interval.
- **The ramp is real:** `CInferno` has `m_damageRampTimer` beside `m_damageTimer`, and the
  pawn has `m_fMolotovDamageTime`. Its length is not in any file.
- **The 30-unit reach** from a flame is still a guess. `CInferno.m_extent` exists.
- **Changes** (search summaries):
  - **23 May 2024:** the incendiary got a shorter duration, a smaller area, and a price cut
    from $600 to $500
    ([Sportskeeda](https://www.sportskeeda.com/esports/cs2-release-notes-may-23-gameplay-changes-map-updates-bug-fixes),
    [Dust2.us](https://www.dust2.us/news/48823/cs2-5-23-update-most-important-changes),
    [HLTV](https://www.hltv.org/news/39059/update-economy-incendiary-vertigo-changes)).
    This is **Inferred** to be where 110 and 5.5 come from.
  - **July 2025 (weak):** one search summary said the incendiary's fire "spreads more
    rapidly" from a July 2025 update, without naming its source. It fits
    `inferno_spread_speed_mult_ct 10`, but it is unconfirmed.
  - **27 January 2026:** a molotov or incendiary that bounces off an enemy gets a one-time
    fuse extension, so it does not air-burst
    ([cybershoke](https://cybershoke.net/blog/cs2-updates-summer-2026/)).
- **Team damage.** Competitive `ff_damage_reduction_grenade` is 0.85, but fire is dealt by
  the `inferno` entity, and `ff_damage_reduction_other` (0.4) covers "things other than
  bullets and grenades". Which of the two scales fire is **not settled**. The repo applies
  0.85; measure it (hurt a teammate with a molotov in a competitive-rules server).

### 2.8 Decoy

- `CDecoyProjectile` has `m_shotsRemaining`, `m_fExpireTime`, `m_nDecoyShotTick` and
  `m_decoyWeaponDefIndex`. The events are `decoy_started`, `decoy_firing` and
  `decoy_detonate`. The description: it "emulates the sound of the most powerful weapon you
  are carrying" (`CSGO_Item_Desc_Decoy_Grenade`).
- **Duration. Disputed:** 15 s of firing
  ([bo3.gg](https://bo3.gg/articles/how-long-do-cs2-grenades-last)), or self-detonation
  after "roughly 18 seconds" ([Fandom Decoy](https://counterstrike.fandom.com/wiki/Decoy_Grenade)).
  Search summaries.
- **The pop:** "up to 5 damage in a narrow radius", none to teammates (Fandom, search
  summary; `ff_damage_decoy_explosion false`). It shows on the radar as a player.

### 2.9 Other grenade rules

- **Limits in competitive:** 4 in total, 2 flashes, 1 of each other type. The HUD line is
  "You can only carry %s1 grenades" (`csgo_instr_pickup_grenade`). A molotov and an
  incendiary share one "fire" slot (**From memory**).
- **Kill awards:** $300 for every grenade (vdata; `cash_player_killed_enemy_default` 300).
- **Team-only rules:** the decoy's pop hurts no teammate. Every other grenade hurts
  teammates at 0.85 in competitive, and the thrower at 1.
- **Dropped grenades:** can be dropped (`mp_drop_grenade_enable`). "Grenades explode when
  shot" arrived in July 2026 for custom games only (`mp_shoot_dropped_grenades` is false
  by default)
  ([Escorenews](https://escorenews.com/en/csgo/news/79372-dropped-grenades-can-be-exploded-with-gunshots-in-new-cs2-update-but-only-in-custom-games),
  search summary).

---

## 3. Dropping and picking up

### 3.1 What drops on death

| Convar | Default | Comp | Meaning |
|---|---|---|---|
| `mp_death_drop_gun` | 1 | 1 | "0=none, 1=best, 2=current or best, 3=both" |
| `mp_death_drop_grenade` | 2 | 2 | "current or best" (max 2) |
| `mp_death_drop_defuser`, `_taser`, `_c4`, `_healthshot` | true | | |
| `cash_player_drop_on_death` | 0 (dev) | | cash does not drop |
| `mp_warmup_items_drop_policy` | 247 | | bits: 1 gun, 2 c4, 4 nade, 8 defuser, 16 taser, 32 healthshot. 247 is all but bit 8 (the defuser). |

All from GT convars.txt and the competitive cfg.

### 3.2 Drop and pickup mechanics

| Item | Value | Source |
|---|---|---|
| Drop speed | **300** for every weapon (`m_flDropSpeed` class default, no override) | GT `CCSWeaponBaseVData.h`, `CBasePlayerWeaponVData.h`, `weapons.vdata` |
| Pickup mode | touch, unless `mp_require_gun_use_to_acquire` ("Whether guns must be +used to acquire or default is touch-to-pickup"): false | convars.txt |
| Re-pickup waits | `mp_weapon_prev_owner_touch_time` 1.5, `mp_weapon_next_owner_touch_time` 1.3 | convars.txt (already in contracts.md) |
| Swap with E | a cone search. `sv_weapon_swap_difficulty_near_hi_pri` 2: "cone searches are disabled near high priority items" (so E near the bomb or a hostage does not grab a gun). `sv_weapon_require_use_grace_period` 1. | convars.txt |
| Use reach | `player_use_radius` 80 | convars.txt |
| Buy menu | `sv_buymenu_open_prevents_opportunistic_pickup` false: walking over a gun with the buy menu open still picks it up | convars.txt |
| Knife | cannot be dropped (`mp_drop_knife_enable false`); "This weapon cannot be dropped" | convars.txt; csgo_english.txt |
| Full inventory | "You cannot carry any more"; `item_pickup_failed` {item, reason, limit} | csgo_english.txt; mod.gameevents |
| Map-placed weapons | `mp_weapons_allow_map_placed` false by default, **1 in competitive and casual** ("the game will not delete weapons placed in the map") | convars.txt; cfgs |
| Cleanup | `weapon_auto_cleanup_time` 0, `weapon_max_before_cleanup` 0: nothing is removed during a round | convars.txt |
| Ammo kept | a dropped gun keeps its clip and reserve: `m_iClip1` and `m_pReserveAmmo[2]` live on the weapon (`CBasePlayerWeapon`) | GT schema (fetched) |

- **Walking over a gun** picks it up when its slot is free. A full slot shows the E prompt
  ([cs2pulse](https://cs2pulse.com/how-to-pick-up-guns-in-cs2/), search summary). A client
  setting, "Switch to picked up weapon", decides whether you equip it.
- **Picking up from the buy menu.** In buy time, weapons dropped near the buy zone can be
  picked up from the buy menu. A later note fixed "picking up dropped weapons through the
  Buy Menu would fail to complete"
  ([YouTube](https://www.youtube.com/watch?v=2HDF2uzvRSo), search summary). The schema
  backs it: `CCSWeaponBase.m_bDroppedNearBuyZone` and `m_donated`, and
  `CCSGameRules.m_bCanDonateWeapons`.
- **Dropping for teammates in freeze time** is allowed (**From memory**; consistent with
  `m_bCanDonateWeapons`).
- **Original owner.** The weapon keeps `m_hPrevOwner`, `m_iOriginalTeamNumber`,
  `m_bWasOwnedByCT` and `m_bWasOwnedByTerrorist`. The script API has
  `CSWeaponBase.GetOriginalOwner()`. A skin stays the original owner's. StatTrak counts only
  the original owner's kills, and the counter shows "ERROR" for anyone else
  ([Fandom StatTrak](https://counterstrike.fandom.com/wiki/StatTrak%E2%84%A2), search
  summary). The kill itself (feed, money) goes to whoever fired (**From memory**).
- **Blasts push dropped guns.** Explosions have forces (`m_bHasForces`, explosion_types.vdata),
  and on 9 July 2026 "New C4 explosions now apply more force to dropped weapons".
- **Pickup reach:** the player has a "touch expansion" component (`cs_logtouchexpansion`:
  "Log player touch expansion component"). The pickup box is bigger than the hull, by an
  amount no file gives.

---

## Answers to the repo's open guesses

### `reference/systems/bomb.md`, "The numbers"

| Guess in bomb.md | Finding | Status |
|---|---|---|
| Plant 3.0 s held | 3.2 s in CS2 guides, 3.0 s in CS:GO; no file gives it; 7 arming beeps | **Disputed; measure (C1)** |
| Defuse reach: eyes within 90 u, aim within 40° | Defusing is the `+use` search: `player_use_radius` 80 plus a cone; line of sight needed; the extreme-height case was fixed in Nov 2024 | **Partly contradicted** (80, not 90). Cone angle: measure (C1) |
| Pickup: feet within 24 across and 54 up or down | Touch-based, Ts only; the player's touch box is expanded ("touch expansion"), by an unknown amount | **Still measure** |
| Dropping: lands at the dropper's feet; 1 s before they can take it back | Thrown at `m_flDropSpeed` 300 like any weapon, kept upright; the dropper waits 1.5 s, anyone else 1.3 s | **Contradicted**: throw it at 300 and use 1.5 / 1.3 |
| Beeps: 1/s at the plant, closing steadily to 10/s | CS:GO fit: 1.05/s rising exponentially with the fraction done to about 7.8/s at the end (table in 1.3); CS2's client schedules by fraction done; different beep sounds in the last 10 s | **Contradicted** in shape and top rate; confirm in CS2 (C1) |
| Sounds `c4_beep*`, `c4_explode*` | Sound event names: `C4.PlantSound`, `C4.PlantSoundB`, `…_10sec`, `c4.plant`, `c4.plantquiet`, `c4.initiate`, `c4.disarmstart`, `c4.disarmfinish`, `C4.ExplodeWarning`, `C4.ExplodeTriggerTrip`, `c4.explode`, `c4.shockwave.boom`, `c4.shockwave.hit`, `Player.PickupC4`, `Music.BombTenSecCount` | **Settled** as event names; the `.vsnd` files behind them are for the local extraction to map |
| Blast: old radius rule, walls do not shield | Superseded on 8 July 2026. The baked file is now decodable: damage = 100·BombPower/Phase up to Phase 1800, linear beyond; per-site power; nearest baked point | **Settled** (format and formula); C2 can finish |
| Blast armour as a grenade's (0.5) | Reverse-engineering evidence says standard C4 damage ignores armour, with a crouch and facing correction below 100 damage | **Contradicted (weak source)**; C1 with and without armour decides |
| Blast credits nobody | server.dll's victim-only "was killed by the bomb." log line | **Settled** |
| A counting bomb can go off after the round | Still true between rounds (**Inferred**), but not after the match or at halftime (Oct 2025; `m_bAbortDetonationBecauseWorldIsFrozen`) | **Refined** |
| Defuser on the ground, one at a time | Localisation confirms both | **Settled** |
| (not in bomb.md) Defusing changes the defuser's gun | Viewmodel lowered, no scoping, first shot 150 ms after leaving the defuse | **New rule** to add |
| (not in bomb.md) Planting with E | `m_bIsPlantingViaUse` | **New rule** to add |
| (not in bomb.md) Idle bomb drop | Counts 15 s from spawn, for players who never moved | **Refines** cs2-systems "after 15 s" |

### `reference/systems/grenades.md`, "Guesses, each to be measured"

| Guess | Finding | Status |
|---|---|---|
| Molotov air-burst drop (up to 128 below) | Nothing found. Jan 2026: a molotov bouncing off an enemy gets a one-time fuse extension | **Still measure (G1)**; add the fuse extension |
| Fire spread interval for the molotov (0.2 s) | Convars: first fire every 0.02 s, children +0.1 each up to 0.5 s, 3 s per flame, depth 4, 45°, molotov ×1, incendiary ×10 | **Contradicted**: build from the convars (their meaning is Inferred) |
| The fire's 30-unit reach | Not in any file (`m_extent` exists) | **Still measure** |
| The fire's ramp (half to full over 1 s) | A ramp exists (`m_damageRampTimer`); its length is unknown | **Partly settled**; measure its length |
| Flames go out one by one under smoke | The whole fire goes out once more than a third of its flame areas are covered | **Contradicted**: switch to the one-third rule |
| (implicit) A smoke into fire | `m_bExplodeFromInferno`: pops at once | **Inferred**, add |
| HE's smoke hole (128 u, 3 s) | Community: about 2 to 3 s | **Roughly supported**; radius still to measure (G4) |
| The round's tunnel (0.25 s) | Community: "less than a second" | **Consistent**; measure |
| Smoke size, shape, 18 s | Disputed 18 vs 20 s; the shape convars are visual only | **Still measure (G4)** |
| Every flash figure | 4.87 s max straight on (matches); about 1 s behind; the hold-and-fade model confirmed by server.dll; three ring strengths | **Partly supported**; curve still G3 |
| Flash fuse 1.5 s | CS:GO measured 1.40 s from visible grenade to white | **Consistent** if timed from the throw command; measure (G1) |
| Decoy bursts and pop | 15 s vs about 18 s disputed; pop up to 5 damage in a small radius, no team damage | **Still measure (G5)** |
| Grenades' 85% team damage | Competitive cfg: 0.85 (default convar 0.25). Whether fire counts as a grenade or as "other" (0.4) is open | **Settled for HE and flash**; fire open |
| Sphere radius 2 | The sphere is **off** by default (`sv_grenade_collision_sphere false`) | **Contradicted** as the default; keep it only as a simplification |
| Throw (750 × 0.9, strength, 1.25 of velocity, lift, offsets) | Nothing CS2-specific found; CS2 adds the stashed jump-throw | **Still measure (G1)**; add the jump stash |

### `reference/cs2-systems.md` measure items

| Item | What this research settles | What still needs the game |
|---|---|---|
| **C1** (plant time, beep cadence, blast at spots with and without armour) | Beep shape (CS:GO fit, fraction-based in CS2); the blast formula from the baked file; the bomb credits nobody | The plant time (3.0 vs 3.2); a few beep intervals; damage at 3 to 5 spots per site standing, crouched and facing away, with and without armour, to confirm "ignores armour" and the correction |
| **C2** (decode the baked damage) | **Settled in format:** 7 floats per site, int16 xyz per point, 4 bytes per (site, point): Phase u16, Yaw u8, Pitch u8; sites expanded by 32 | Check the decoder against C1's spots |
| **G1** (throw speeds, gravity, fuses) | Jump-throw stash; spin; sphere off by default; flash fuse about 1.4 s visible | The speeds per button, velocity share, gravity, bounce, the HE and flash fuse from the throw, the molotov air-burst drop |
| **G2** (HE damage at 50 to 300 u) | Nothing new beyond the Jan 2026 mid-air fix | All of it |
| **G3** (flash by distance and angle) | Hold-and-fade model; 4.87 s max; three ring tiers | The curve |
| **G4** (smoke duration and size) | Disputed 18 vs 20 s; HE hole 2 to 3 s; the one-third extinguish rule; the C4 blast clears smoke | Duration, size, hole radius |
| **G5** (decoy) | Disputed 15 vs 18 s; pop up to 5 | Burst pattern, duration, pop |

### `reference/systems/contracts.md` "In no file (measure)"

| Item | Finding |
|---|---|
| Drop throw speed (200 forward, 100 up) | **Contradicted**: `m_flDropSpeed` 300 for every weapon, the C4 included. The split between forward and up is not in any file. |
| Pickup reach | Still unknown ("touch expansion"). E reaches 80 (`player_use_radius`). |
| Which grenade is "best" | Not found. `GrenadeType_t` orders them explosive 0, flash 1, fire 2, decoy 3, smoke 4 (GT `DumpSource2/schemas/client/GrenadeType_t.h`); that it is also the drop priority is only an **Inferred** possibility. |
| A gun's mass and bounce; blasts and bullets pushing it | Blasts push (explosion forces; stronger for the C4 since 9 July 2026). Bullets are not known to push dropped guns. |
| The C4 takes the same waits | **Inferred** yes: it is a `CCSWeaponBase` with the same touch-time fields |
