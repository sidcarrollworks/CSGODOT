# How CS2's combat works: research

Sid, 2026-09-24: "spin up a couple agents to do some research on how all
these systems work in the actual game." This page covers combat: the gun
features `reference/weapons/TODO.md` still has open (R3, R4, R5, R6, R7, R10,
R13), the knife and Zeus (roadmap item 21), being hit (items 2 to 4a, and A1
in `reference/cs2-systems.md`), and how hits register online (item 25 and
systemization step 3.3). Money, the bomb, grenades, drops, round flow, the
round HUD and bots are researched separately.

It records what CS2 does and what is still unknown. Where an item needs a
number that no file has, it says how Sid can measure it (Local). It changes
no code.

## Sources

Four research passes on 2026-09-24, each citing every claim. The key:

| Key | Source |
|---|---|
| WV | CS2's `scripts/weapons.vdata`, GameTracking-CS2 `game/csgo/pak01_dir/scripts/weapons.vdata` @10f3693 (the same file as `reference/weapons/vdata.csv`). A pair `a\|b` is `[normal, alternate]` |
| WVH | The 13 versions of that file in GameTracking-CS2's history, 2024-05-03 to 2026-09-23 |
| CV | GameTracking-CS2 `DumpSource2/convars.txt` @d45f52d, by line. CVH: its 70 dumps, 2024-10-04 to 2026-09-23 |
| CMD | GameTracking-CS2 `DumpSource2/commands.txt` |
| SCH | GameTracking-CS2 `DumpSource2/schemas/{server,client}/<Class>.h`, CS2's own class layouts |
| PB | GameTracking-CS2 `Protobufs/`: `usercmd.proto` (UC), `cs_usercmd.proto` (CUC), `netmessages.proto` (NM), `cstrike15_usermessages.proto` (UM15), `cs_gameevents.proto`, `cs_prediction_events.proto` |
| GI | GameTracking-CS2 `game/csgo/gameinfo.gi`, the game's own convar overrides |
| CFG | GameTracking-CS2 `game/csgo/cfg/gamemode_<mode>.cfg` |
| LOC | GameTracking-CS2 `game/csgo/pak01_dir/resource/csgo_english.txt` (menu text) |
| SND | GameTracking-CS2 `game/csgo/pak01_dir/soundevents/game_sounds_weapons.vsndevts` |
| SS | GameTracking-CS2 `game/csgo/bin/win64/server_strings.txt` (names only) |
| HUD | GameTracking-CS2 `game/csgo/pak01_dir/panorama/layout/hud/huddamageindicator.xml` and its `.css` |
| IG | `items_game.txt` in GameTracking-CS2's history: CS:GO's (2016-12-11, 2023-05-04) and CS2's before stats moved to vdata (2024-04-03) |
| SDK | Source SDK 2013, read as a spec only |
| DP | demoparser2 (LaihoE/demoparser, MIT), `src/parser/src/maps.rs`: the property names it reads from a CS2 demo |
| ZK | zer0k-z, `cs2-movement-issues` README (measured with demos; out of date since Nov 2025) |
| WS | A web search's summary of a named page. This session's proxy blocked Steam, counter-strike.net, HLTV, Reddit, fandom, Liquipedia and most news sites, so release notes are quoted from search summaries. Re-read them before quoting them as Valve's words |

Labels: **inferred** means reasoned from names, fields or data, not stated
by Valve. **From memory** means not checked against a source reachable
here. Nothing on this page comes from Valve's leaked CS:GO source.

## Corrections to what the repo says

1. **CS2 rewinds at most 200 ms, not 1 s.** `sv_maxunlag` is 1 by engine
   default (CV 10308), but CS2's game config sets `"sv_maxunlag" "0.200"`
   (GI 81). The same file sets `cl_interp_ratio 0` (GI 83; engine default
   2) and `cq_buffer_bloat_msecs_max 64` (GI 241; default 150). This PR
   fixes `cs2-systems.md` §12 and roadmap item 25.
2. **The Desert Eagle's jump inaccuracy agrees with the sheet.**
   `vdata.md` flags the sheet's 378.30 against the game's 46.75. The sheet
   adds `m_flInaccuracyJumpApex`: 4.2 stand + 2 spread + 40.55 jump +
   331.55 apex = 378.30 (WV: 0.0042, 0.002, 0.04055, 0.33155). WV even
   stores the sum, 0.37155, as the Deagle's alternate jump value. Valve
   added the apex term for the Deagle alone in April 2020 (it first appears
   in IG on 2020-04-17; WS for the 16 April 2020 notes). So the difference
   is a field `vdata.md` leaves out, not a disagreement.
3. **CS2 has no `weapon_recoil_*` convars.** None of CS:GO's
   `weapon_recoil_scale`, `_decay2_exp`, `_decay2_lin`, `_vel_decay` or
   `_view_punch_extra` is in any of the 70 dumps (CVH).
   `reference/weapon_stats.md` line 168 says CS2 exposes
   `weapon_recoil_view_punch_extra`. It does not. The 8, 18, 4.5 and 2 in
   `src/weapons/recoil_state.gd` are CS:GO's (from memory), not published
   CS2 values. CS2's recoil convars are only `view_punch_decay 18`
   (CV 11565, cheat), `sv_suppress_viewpunch` (CV 10779) and
   `mp_flinch_punch_scale 3` (CV 4791).
4. **The zoom times probably mean the time to reach each level.**
   `vdata.md` reads `m_flZoomTime0/1/2` as into level 1, into level 2 and
   back out. For the AUG that gives 0.06, 0.1 and 0.0: a time for a second
   level it does not have, and no time to unzoom. Read as "time to reach
   level N", the AUG unzooms in 0.06 s and zooms in 0.1 s, and the missing
   level 2 is 0 (WV). Inferred; check at `host_timescale 0.1`.
5. **CS2's damage indicator lights one of four quadrants.** The HUD file
   draws four fixed 90-degree segments (top, right, bottom, left) of a
   300 px ring, coloured `#cc3300` (HUD). The range draws an arc at the
   exact angle (roadmap item 4). The fade time is not in the file.

## 1. The guns' open features

### R13: recovery after a spray

- **The rule.** Valve split recovery into initial and final values in
  CS:GO's "Second Shot" update (1.35.4.4, 3 August 2016): shorter bursts can
  recover faster than long sprays (WS: blog.counter-strike.net/second-shot,
  hltv.org/news/18356).
- **The fields.** `m_flRecoveryTimeStand` and `...Crouch` are the initial
  times; `m_flRecoveryTimeStandFinal` and `...CrouchFinal` the final ones;
  `m_nRecoveryTransitionStartBullet` and `...EndBullet` the rounds they
  blend between (WV; SCH `CCSWeaponBaseVData`).
- **The blend.** Inferred from the names and Valve's description: the
  initial time up to StartBullet, the final time from EndBullet, a straight
  blend between. Whether the count is the integer `m_iRecoilIndex` or the
  float `m_flRecoilIndex`, which decays between taps, is unknown (both are
  weapon state, SCH `CCSWeaponBase`).
- **Only ten guns use it.** Every other gun's final time equals its
  initial, so its round numbers do nothing (WV):

| Gun | Stand, initial / final (s) | Crouch, initial / final (s) | Rounds |
|---|---|---|---|
| Glock-18 | 0.2 / 0.33 | 0.2 / 0.33 | 0 to 5 |
| Five-SeveN | 0.2 / 0.5 | 0.2 / 0.5 | 0 to 5 |
| CZ75-Auto | 0.2425 / 0.345 | 0.2275 / 0.288 | 3 to 10 |
| R8 | 0.9 / 0.811 | 0.7 / 0.45 | 3 to 10 |
| Galil AR | 0.3 / 0.5 | 0.15 / 0.47 | 2 to 5 |
| FAMAS | 0.25 / 0.5 | 0.12 / 0.48 | 2 to 5 |
| AK-47 | 0.368 / 0.506 | 0.305 / 0.42 | 2 to 5 |
| M4A4, M4A1-S | 0.339 / 0.466 | 0.242 / 0.333 | 2 to 5 |
| Negev | 0.3 / 0.1 | 0.25 / 0.08 | 9 to 12 |

  On the Negev and the R8 the final time is shorter, so a long burst
  recovers faster. The Negev's `m_flInaccuracyFire` is 0.03|0.00337 (WV);
  the second is presumably its sustained-fire value (inferred). Valve's
  April 2017 Negev rework says recoil "concentrates" after sustained fire,
  and its shot sound changes to `Weapon_Negev.SingleFocused` once accurate:
  `m_flInaccuracyAltSoundThreshold` 0.02 and `m_flInaccuracyPitchShift` -50
  are set on the Negev alone (WV; SND 2850; WS: hltv.org/news/20235).
- **Unknown:** the curve's shape and its count. Measured by the demo in
  "Measuring in CS2" below, reading `accuracy_penalty`, `i_recoil_idx` and
  `fl_recoil_idx` each tick (DP 1146-1148) after 1, 3 and 6 AK rounds. The
  same trace gives the recoil index's decay between taps, which
  `recoil_state.gd` takes from CS:GO.

### R13: spread against inaccuracy

- `m_flSpread` is its own value per mode, apart from the stand, crouch,
  move, jump, land, ladder, fire and reload inaccuracies (WV; SCH
  `CFiringModeFloat`).
- The largest miss is inaccuracy plus spread:
  `weapon_debug_spread_show` "Draws the current weapon's true inaccuracy +
  spread radius around the crosshair" (CV 11790).
- The offset is a direction and a size: `weapon_debug_inaccuracy_only_up`
  forces "inaccuracy to be in exactly the up direction" and
  `weapon_debug_max_inaccuracy` forces "all shots to have maximum
  inaccuracy" (CV 11784, 11787).
- Every shot's network event carries its `seed`, `inaccuracy`, `spread`,
  `recoil_index`, `player_inair` and `player_scoped`, with `aim_punch`,
  `inaccuracy_move` and `inaccuracy_air` in its extra part (PB
  `CMsgTEFireBullets`). Client and server have rolled the same spread
  numbers by default since 8 November 2023 (WS: Steam notes of that date).
- **Shots cluster toward the centre.** The community's account is two
  offsets, one sized uniformly in [0, inaccuracy] and one in [0, spread],
  each at a uniform random angle, added. A uniform radius, not a uniform
  area, puts half the rounds inside half the cone. The repo models it this
  way (`weapon_stats.md`). Not confirmed by any source reachable here (from
  memory). To measure: `sv_cheats 1; weapon_accuracy_forcespread 0.05`
  (CV 11754), 100 single rounds standing at a wall with `sv_showimpacts 1`,
  and count those inside half the radius: about 50% for a uniform radius,
  25% for a uniform area.
- **Jumping.** `m_flInaccuracyJumpInitial`, `m_flInaccuracyJump` and (the
  Deagle only) `m_flInaccuracyJumpApex` (WV). `weapon_air_spread_scale 1`
  scales jumping inaccuracy, 0 making it equal standing (CV 11772). How
  Initial plays out over a jump is unknown; a demo's
  `fire_bullets.extra.inaccuracy_air` against time since take-off shows it.
- **Boost stacks.** `weapon_accuracy_stack_boost_limit 2` (added 18 May
  2026, CVH) gives ladder inaccuracy to a player boosted by two or more
  players (CV 11769).
- `sv_strafing_inaccuracy_*` and `sv_turning_inaccuracy_*` are disabled
  experiments (CV 10758-10830).

### R6: "random" recoil

- `m_flRecoilAngle` and `...AngleVariance` look like degrees (0 to 180);
  `m_flRecoilMagnitude` and `...MagnitudeVariance` are in CS's own units;
  all four are per mode (WV).
- `m_nRecoilSeed` is set on all 34 guns, the sheet's "Random" ones
  included (AK 223, Glock 4484, Deagle 1454, AWP 4100). Inferred: every
  gun's kicks are a fixed sequence drawn from its seed by round number, so
  a "Random" gun kicks the same irregular way every time rather than
  rolling afresh. The AK has angle variance 70 and a fixed pattern, which
  fits.
- How angle and magnitude become degrees is in no file. It can be read off
  the game instead of reconstructed: a demo with
  `weapon_accuracy_nospread 1` (CV 11760) leaves only recoil, and gives
  `aim_punch_angle` each tick and `fire_bullets.extra.aim_punch` each shot
  (DP 909). That also settles `recoil_scale` (roadmap item 8) without the
  wall plot. Two identical Deagle tap runs settle whether "Random" is
  seeded.
- **Recent changes.**
  - 21 May 2025: the drawn view kick moved from per tick to per frame;
    bullets and maths unchanged (WS: dust2.in/news/61651).
  - 21 April 2026: aim punch split into `CCSPlayer_AimPunchServices`, with
    a predictable part (your own recoil) and an unpredictable part (from
    being hit) (SCH). The notes: camera motion from recoil "adjusted to
    match CS:GO more closely", bullet trajectories unchanged (WS:
    talkesport.com, CS2 April 22 update).
  - 22 and 23 September 2026: the crosshair was rebuilt. The default style
    is now 7, "Dynamic Quad"; styles 0, 1 and 7 "track the weapon's actual
    inaccuracy" (CV 1006, 958; CVH 2026-09-23). The weapons lost their
    crosshair distance fields and the four snipers gained
    `m_bShowCrosshair false` (WVH).
  - `cl_crosshair_recoil` makes the crosshair follow "the weapon's
    predicted recoil (aim punch)" (CV 970). Its menu default is unverified.

### R10: tracers

- **How often.** `m_nTracerFrequency` per mode: 1 every round, 3 every
  third, 0 none (WV). `vdata.md` misses the alternates: the M4A1-S is 3|0
  and the USP-S 1|0, so no tracers with the silencer on. The MP5-SD is 0.
  Snipers, the M249, the Negev and the Zeus draw every round.
- **Which round.** Source SDK 2013 counts shots in one counter and draws
  when `count++ % frequency == 0` (SDK `baseentity_shared.cpp` 1956).
  Whether CS2 counts per gun, per player or for everyone, and whether a
  spray's first round has one, is unknown. Tap single rounds at a wall and
  note which show one.
- **The effects.** `m_szTracerParticle` names one of ten in
  `particles/weapons/cs_weapon_fx/`: `weapon_tracers_pistol` (every
  pistol), `_shot` (shotguns), `_smg`, `_assrifle` (Galil, FAMAS, AK, both
  M4s), `_assrifle_aug` (AUG, SG 553), `_mach` (M249, Negev), `_rifle`
  (AWP), `_rifle_ssg` (SSG 08, G3SG1), `_rifle_scar` (SCAR-20), and
  `_taser` (WV).
- **Where they start.** At the muzzle. `m_vecMuzzlePos0` is the first-person
  muzzle; `m_vecMuzzlePos1` sits further forward on the M4A1-S and USP-S
  (inferred: silencer on) and is the left pistol on the Dual Berettas (WV).
  Source SDK 2013 also starts tracers at the muzzle attachment (SDK
  `baseentity_shared.cpp` 2164-2173).
- **Your own.** `r_drawtracers_firstperson true` is a user setting, on by
  default (CV 7437).
- **Snipers.** With `sv_sniper_tracer_mode 1`, a shot more than 0.085
  inaccurate draws only a 200-unit tracer (`sv_sniper_tracer_innacuracy`,
  `..._length`; CV 10686-10693), so a noscope's tracer does not show where
  its round went (inferred).
- **Speed.** In the particle file, not in any data this session could read.
  Source SDK 2013's default is 5000 units a second (SDK `fx_tracer.cpp`
  19). Local: decompile `weapon_tracers_assrifle.vpcf_c` with Source 2
  Viewer. *(Done 2026-09-24, `reference/weapons/effects.md`: 20,500 for the
  rifles, 18,000 pistols and SMGs, 24,000-24,500 shotguns, 30,000 snipers,
  15,500 machine guns. And which round: CS2's client draws every one,
  `cl_tracer_frequency_override 1`, a development-only setting, so fixed.)*
- **The whiz.** `cl_tracer_whiz_distance 72` and
  `cl_tracer_whiz_infront_distance 32` (CV 2242-2245). Source SDK 2013
  plays its near-miss sound when a round passes within 72 units of the
  listener, at most every 0.1 s (SDK `clientsideeffects_test.cpp` 180-290).
  The sounds are `BulletBy.Supersonic.Crack` and `BulletBy.Subsonic`
  (SND 33452, 34081). Which guns are subsonic, and whether rounds without a
  tracer whiz, is unknown.

### R5: shotguns

| Gun | Pellets | Damage a pellet | Range | Range modifier | Spread | Spread seed |
|---|---|---|---|---|---|---|
| Nova | 9 | 26 | 3000 | 0.70 | 0.04 | 17514 |
| XM1014 | 6 | 20 | 3000 | 0.70 | 0.038 | 817955 |
| Sawed-Off | 8 | 32 | 1400 | 0.45 | 0.062 | 9571223 |
| MAG-7 | 8 | 30 | 1400 | 0.45 | 0.04 | 19899236 |

(WV: `m_nNumBullets`, `m_nDamage`, `m_flRange`, `m_flRangeModifier`,
`m_flSpread`, `m_nSpreadSeed`.)

- **Fixed pellet patterns.** Valve's "Holiday Spread" update (December
  2017) gave each shotgun its own pattern, "treated similarly to recoil",
  in place of pellets scattered at random (WS:
  blog.counter-strike.net/holiday-spread). It sat behind
  `weapon_accuracy_shotgun_spread_patterns`, which is on in CS2 in every
  dump (CV 11766). Only the four shotguns have a nonzero spread seed (WV).
  Inferred: the pattern comes from that seed and the cone scales it. Its
  shape is unknown: five shots per shotgun at the range's wall from 496
  units with `sv_showimpacts 1`, overlaid, would give it (Local).
- **Reloads.** `m_bReloadsSingleShells` is true on the Nova, XM1014 and
  Sawed-Off; the MAG-7 has a magazine (WV). Since 18 March 2026 a reload
  throws away the rounds left in the magazine and reserve is counted in
  magazines (`m_bReserveAmmoAsClips`), except on those three, which keep
  32 rounds in reserve (WVH; WS: hltv.org/news/44128).

### R4: scopes

- Levels, FOVs and zoom times are in `vdata.md` (see correction 4 for the
  times). Scoped values are the alternate of each per-mode field (WV):

| Gun | Speed | Stand inaccuracy | Recoil magnitude |
|---|---|---|---|
| AWP | 200 \| 100 | 0.0808 \| 0.002 | 78 \| 25 |
| SSG 08 | 230 \| 230 | 0.0317 \| 0.003 | 33 \| 25 |
| G3SG1, SCAR-20 | 215 \| 120 | 0.0258 \| 0.002 | |
| AUG | 220 \| 150 | 0.0049 \| 0.00368 | 24 \| 16 |
| SG 553 | 210 \| 150 | 0.00581 \| 0.00381 | 28 \| 19 |

- **After a shot.** Only the AWP and SSG 08 unzoom (`m_bUnzoomsAfterShot`),
  and `cl_sniper_auto_rezoom true` zooms back in (CV 2122). Since 22
  September 2026 unscoping makes no sound (WS: steamdb patch notes
  25470087).
- **Holding right click** does not cycle levels by default
  (`cl_debounce_zoom true`, CV 1045).
- **Sensitivity.** `zoom_sensitivity_ratio 1` is an extra factor on top of
  the zoomed FOV (CV 11841). Source scales sensitivity by zoomed over
  default FOV (from memory: 0.444 at FOV 40, 0.111 at 10). To measure:
  mouse counts for a full turn, scoped and not.
- **Accuracy ramps in after scoping.** The weapon keeps
  `m_fAccuracySmoothedForZoom` (SCH `CCSWeaponBase`). Inferred: scoped
  accuracy is eased in over time, which is what makes quickscopes miss.
  No numbers are published. To measure: `weapon_debug_spread_show 1` at
  `host_timescale 0.1`, counting frames from zoom until the circle stops
  shrinking.
- Since October 2025 the sniper scope can show inaccuracy
  (`cl_sniper_show_inaccuracy true`, CV 2128).
- The four snipers hide the first-person model when zoomed; the AUG and
  SG 553 do not, and alone carry iron-sight fields (`m_flIronSightFOV` 45,
  pull-up speed 10, put-down speed 8) (WV).

### R3: burst fire

- **Glock-18 and FAMAS** (`m_bHasBurstMode`). Between bursts
  (`m_flCycleTimeWhenInBurstMode`): Glock 0.5 s, FAMAS 0.55 s. Between a
  burst's rounds (`m_flTimeBetweenBurstShots`): Glock 0.05 s, FAMAS 0.075 s
  (WV).
- **Three rounds a burst.** The schema's default `m_nBurstShotCount` is 2
  (no gun overrides it; SCH), and inferred to be the rounds after the
  first. The 21 April 2026 bug that fired all three at once confirms three
  (WS: pcguide.com), as does WVH, where the two burst fields vanished on
  2026-04-20 and came back the next day.
- **Burst values** are the alternate slot (WV). Glock: spread 0.002|0.015,
  fire 0.056|0.045, recoil magnitude 18|30. FAMAS: stand 0.00759|0.00369,
  fire 0.00605|0.00335.
- **Unknown:** how inaccuracy builds between a burst's rounds, and whether
  a held trigger repeats bursts (the FAMAS has `m_bIsFullAuto true`). The
  demo's `fire_bullets.inaccuracy` for each round of a burst answers the
  first.

### R3: silencers

- `m_eSilencerType` is detachable on the M4A1-S and USP-S, integrated on
  the MP5-SD (WV; SCH `CSWeaponSilencerType`).
- **Damage cannot change with the silencer.** Only per-mode fields have two
  values: cycle time, speed, spread, the inaccuracies, recoil and tracer
  frequency. Damage, range modifier, penetration, armour ratio and recovery
  are single values (SCH `CCSWeaponBaseVData`): M4A1-S 38, USP-S 35 either
  way (WV).
- Off|on (WV). M4A1-S: fire 0.012|0.007, move 0.09288|0.122, recoil 25|21,
  spread 0.0006|0.0005, tracers 3|0. USP-S: fire 0.071|0.052, recoil 29|23,
  spread 0.0025|0.0015, tracers 1|0.
- **Detaching is off by default.** `cl_silencer_mode 0` means the silencer
  cannot come off; 1 lets right click detach it (CV 2050; LOC "Removal of
  the silencer is disabled. Enable it in settings."). The switch time is
  the clip's, in `timings.md`.
- **Sound.** A silenced shot's near layer is gone by 1400 units and it has
  no distant layer. An unsilenced one is heard to 2500 units, with a
  distant layer from 800 to 2869 (SND 13122-14263, 20536, 35011-35093).

### R7: the R8's hammer

- The primary shot is postponed: the weapon keeps
  `m_nPostponeFireReadyTicks` and `m_flPostponeFireReadyFrac` (SCH), so it
  fires at a set tick and fraction after the press. The delay is not in WV.
  Community wikis say about 0.2 s, with speed dropping to 180 while the
  hammer is back (WS: counterstrike.fandom.com R8 page).
- Right click (fan fire): cycle 0.4 s, spread 0.068, speed 220 (WV).
- To measure exactly: the demo's `post_pone_fire_ready_time` (DP 1150)
  against the press tick and the `fire_bullets` tick. That also shows what
  releasing early does.

## 2. Knife and Zeus

### The knife

- **In the game's files.** Armour ratio 1.7, so 85% of the damage goes
  through kevlar; $1,500 a kill; speed 250; deploy 1.0 s; tagging 0.3 large and
  small (WV `weapon_knife`). `m_nDamage 50`,
  `m_flRange 4096` and `m_flCycleTime 0.15|0.3` are the class's defaults,
  not the swing's (the same values sit on the Zeus and grenades).
  `m_flHeadshotMultiplier` 4.0 is also the default; a wiki says CS:GO's
  knife had none (WS: counterstrike.fandom.com Knife page). Measure it.
- **Swing damage is still in no file.** The figures everyone quotes: left
  40 on the first swing then 25, right 65, backstabs 90 (left) and 180
  (right); through kevlar 34, 21, 55, 76, 153 (WS: fandom Knife page).
  The armoured ones are the unarmoured times 0.85, rounded down, which
  fits the 1.7 ratio (inferred check). A right backstab kills through
  kevlar.
- **The first swing does more.** The server's knife keeps one networked
  `m_bFirstAttack` (SCH `CKnife`). Since 2 November 2023 a swing right after
  drawing always does full damage (WS: patch notes of that date). How long
  after a swing the 40 comes back is in no source found.
- **One victim, enemies first.** Since 2 November 2023 a swing hits a
  teammate only if no enemy is in range, and hit effects and sounds wait
  for the server (WS: same notes). A trace filter
  `CTraceFilterKnifeIgnoreTeammates` exists (SS).
- **Outcomes.** The third-person graph has light and heavy attacks, each
  with hit, miss and backstab (SS `attack_knife_*`), matching the
  first-person clips (`equipment.md`). Since 22 January 2026 left, right
  and backstab hits sound different (WS: hltv.org/news/43689; the sound
  names arrive in SS between September 2025 and January 2026). An
  armoured victim plays its own hit sound for the attacker (SS).
- **Reach, trace shape, backstab angle and swing rates are unknown.** The
  usual 48 units left and 32 right, a line then a box, are from memory and
  probably trace back to Valve's code, so they are guesses to measure.
  Guides give about 0.4 s a left swing and 1.0 s a right (WS: profilerr
  guide, not measured).
- **Teammates.** Competitive has friendly fire with bullets at 33% and
  everything else at 40% (`ff_damage_reduction_bullets 0.33`,
  `ff_damage_reduction_other 0.4`, CFG competitive 36-52). Which the knife
  uses is unknown.
- The knife cannot be dropped (`mp_drop_knife_enable false`, CV 4758). CTs
  carry `weapon_knife` and Ts `weapon_knife_t` (IG). The shield and the
  other melee classes left CS2's schema in March 2025 (SCH history).

### The Zeus x27

| Field | Value |
|---|---|
| Damage | 500 (`m_nDamage`) |
| Range | 120 units (`m_flRange`) |
| Range modifier | 0.99 (so 499 at 120 units, with the guns' formula) |
| Armour ratio | 2.0 (armour does not help) |
| Price, kill award | $200, $100 |
| Speed, deploy | 230, 1.0 s |
| Charges | 1 (`m_iMaxClip1`), `AMMO_TYPE_TASERCHARGE` |
| Tracer | every shot, `weapon_tracers_taser` |
| Tagging | 0.5 large, 0.65 small |

(WV `weapon_taser`.)

- **Recharge.** `mp_taser_recharge_time 30` (CV 5091; -1 disables it). It
  became rechargeable in every mode in the 6 February 2024 update, with
  the charging and charged sounds (WS: esports.gg; the sound names first
  appear in SS on 2024-02-07).
- **Range.** Before 25 April 2024 CS2's own item file had range 190, falloff
  0.0049 and a $0 award (IG 2024-04-03). That update changed range to 120
  and the award to $100 without mention in the notes (WS: dust2.us news
  48106, spotted on Reddit). The often-quoted 183 units is CS:GO's.
  Whether the Zeus uses the guns' falloff formula is unresolved: measure
  its damage at 100, 115, 119, 120, 121 and 125 units.
- **Its inaccuracy.** WV gives it stand 0.06, fire 0.05 (ten times an
  AK's). Whether these apply to its trace is unknown;
  `weapon_debug_spread_show 1` shows it.
- **Limits.** Buys a round: 5 in competitive and wingman, 2 in casual,
  unlimited in deathmatch (`mp_weapons_allow_zeus`, CFG). No limit a match.
  It drops on death (`mp_death_drop_taser true`, CV 4683).
- The ragdoll's taser force is set by development-only client convars
  (`cl_random_taser_power 4000`, CV 1909-1916), so it is cosmetic.

## 3. Being hit

### Tagging

- **The mechanism fits the project's.** The slowdown is a networked
  multiplier on the pawn, `m_flVelocityModifier`, beside a new
  `m_flFlinchStack` (SCH `CCSPlayerPawn` 75-76). A GPL server plugin treats
  it as a multiplier of base speed (CS2Fixes `src/customio.cpp` 499, 572),
  as the project does.
- **CS2 predicts it on the victim's own client.** The server sends a
  `CCSPredictionEvent_DamageTag` with `flinch_mod_small`,
  `flinch_mod_large` and a friendly-fire ratio (PB
  `cs_prediction_events.proto` 9-13). It carries no hitgroup, damage or
  armour, so the choice between Large and Small rests on something the
  victim already knows (inferred), and a teammate's hit presumably tags
  less by the friendly-fire ratio (inferred).
- **Large against Small.** Small is the milder on almost every gun (AK 0.4
  and 0.55). The common claim that Small is for leg hits is a CS:GO forum
  post (WS: AlliedModders t=304752). CS:GO's 2 October 2014 notes say
  tagging was "unified" across body parts and argue against it. The same
  notes made tagging "slightly cumulative" and let the victim's own weapon
  set how much they are tagged (WS: dexerto, October 2 2014 notes).
  `m_flFlinchStack` fits the first (inferred). None of it is confirmed
  for CS2.
- **Every SMG is 0.0 and 0.0** (WV), which taken at face value stops the
  victim dead. Untested.
- **Timing.** `sv_predictable_damage_tag_ticks 2` came with the 14 August
  2024 update, to stop players teleporting when hit (WS: Steam notes
  8/14/2024). A 15 October 2025 fix stopped one tick being taken off it,
  so the delay is really two ticks now (WS: strafe.com).
- **Recovery.** The project's 0.4 of full speed a second is a CS:GO
  community figure (WS: csgoarticles.com, no method given). CS2 has no
  convar for it. Whether it recovers in the air is unknown.

### Aim punch when hit

- **It moves the bullets.** The 21 April 2026 notes: "The effects of aim
  punch on bullet trajectories are still applied immediately on the
  server", and players now get "the full camera motion due to external
  sources of aim punch (e.g. getting shot) regardless of network latency"
  (WS: talkesport.com, op.gg).
- **Stored as an angle, not a push.** The punch from being hit is
  `m_unpredictableBaseAngle` with its tick, and no velocity, beside the
  recoil's predictable angle and velocity (SCH
  `CCSPlayer_AimPunchServices`, since 2026-04-21). Inferred: a hit sets an
  offset that then decays. The project pushes a velocity into a spring
  (`player_sim.gd`, `hit_punch.velocity`). The demo below shows which.
- `view_punch_decay 18` belongs to the camera's separate view punch
  (`m_vecCsViewPunchAngle`, SCH `CPlayer_CameraServices`), not the aim.
  `mp_flinch_punch_scale 3` scales the view punch when hit (CV 4791); its
  base is in no file.
- **Armour.** CS:GO's 14 September 2017 notes "significantly reduced
  unarmored aimpunch" (WS: blog.counter-strike.net/2017/09). Size,
  direction and the helmet's effect on a headshot are unknown for CS2.

### The flinch on the body, and the HUD

- Three additive layers, `BodyFlinch`, `HeadFlinch` and `FireFlinch`, are
  already read out in `reference/animgraph/worldmodel.md`. The body flinch
  is chosen by hitgroup and the side the round came from
  (`flinch_body_type`: arms, chest north/south/east/west, stomach, legs),
  the head's by side. The server can suppress a flinch or override its
  hitgroup (SCH `CTakeDamageResult`).
- The damage indicator is correction 5 above. The message behind it
  carries the amount and the attacker's world position
  (`CCSUsrMsg_Damage`, UM15 181-185).

### Hitgroups

- Head: `m_flHeadshotMultiplier` per gun, 4.0 on nearly all, M4A1-S 3.475,
  Desert Eagle 3.9 (WV).
- Chest and arms 1.0, stomach 1.25, legs 0.75 are in no CS2 file; only
  community pages give them (WS: bo3.gg, profilerr.net), and the project's
  sheet agrees. A neck hit is said to count as the head (WS: critfeed.com);
  the project maps group 8 to the head (`hitbox_set.gd`).
- Kevlar covers chest, stomach and arms, the helmet the head, nothing the
  legs (WS: bo3.gg). One CS:GO Steam guide says the arms are not covered,
  so one shot settles it: an AK arm hit on kevlar does 27 if covered, 36
  if not.
- No Valve note of a CS2 change to hitgroups was found.

## 4. How hits register online

### What the client sends

- **Each command** (UC `CBaseUserCmdPB`): its number and client tick, the
  buttons (three 64-bit words; inferred held, pressed and released), the
  view angles at the end, the move axes, raw mouse deltas, `random_seed`,
  and `subtick_moves`.
- **Each sub-tick step** (UC `CSubtickMoveStep`): a button, pressed or
  released, and `when`, the fraction of the tick it happened; analog move
  changes; and `pitch_delta` and `yaw_delta`, the view change at that
  instant, which movement uses while `sv_subtick_movement_view_angles` is
  on (CV 10773).
- **For a shot** (CUC `CSGOInputHistoryEntryPB`), one entry per client
  frame, with `attack1_start_history_index` naming the one the trigger went
  down in. Each entry holds the view angles at that frame; the tick and
  fraction the client was drawing others at (`render_tick_count`,
  `render_tick_fraction`); the exact tick pairs and blend it drew
  (`sv_interp0`, `sv_interp1`, `player_interp`); the eye position it fired
  from (`shoot_position`); and its own view of the target
  (`target_head_pos_check`, `target_abs_pos_check`), which the server
  checks (`sv_csgo_shoot_lagcompensation_max_error`, CV 9897).
- **The times are frame times.** A sub-tick event is timed to the client
  frame it was read in, not the input device's timestamp (ZK; SigmaSkid's
  High-Precision-Input-POC README). The project already reads Godot's
  event timestamps (`player_input.gd`), which is finer.
- **Changes since launch** (WS for each: Steam, HLTV and dust2 news of the
  date):
  - 8 November 2023: feedback from sub-tick input renders on the next
    frame; spread numbers synced.
  - 19 August 2024: binds with more than one movement, attack or look
    command are ignored (`cl_allow_multi_input_binds`, CV 814), ending
    "desubtick" and jump-throw binds; hardware Snap Tap gets you kicked on
    Valve servers.
  - 28 October 2024: jump height the same everywhere.
  - 28 July 2025: "hitbox interpolation and movement prediction" moved
    closer to what the client sees.
  - 17 September 2025: sub-tick acceleration made timestep-independent;
    "subtick shooting consistency" improved.
  - Nothing found took jumps or movement off sub-tick.

### Lag compensation

- The server rewinds each target to the tick **and fraction** the shooter
  was drawing, rather than a whole tick worked out from latency, as Source
  1 did (inferred from CUC and `sv_csgo_shoot_use_full_interp 1`, CV 9906;
  Source 1's rule in SDK `player_lagcompensation.cpp` 381-411).
- At most 200 ms back on Valve's servers (correction 1).
  `sv_maxunlag_player` can cap humans lower than bots (CV 10311);
  `sv_lagcomp_filterbyviewangle` rewinds only targets in view (CV 10209).
- What is rewound is the posed hitboxes (`sv_showlagcompensation_rec`,
  CV 10659; `CCSUsrMsg_ShootInfo` carries hitbox transforms, UM15 560).
- November 2024 fixed rewinds going further back than the screen
  mid-spray, and rewinds that ignored the player's buffering setting (WS:
  hltv.org/news/40200; Steam notes 11/12/2024).
- **Damage prediction** (13 November 2024): the shooter can play blood,
  the headshot effect and the kill ragdoll before the server confirms.
  Body and head effects are off by default, ragdolls on
  (`cl_predict_body_shot_fx 0`, `cl_predict_head_shot_fx 0`,
  `cl_predict_kill_ragdolls 1`, CV 1726-1735). The menu warns it can be
  wrong "due to aim punch, tagging, or a death that your client isn't yet
  aware of" and is off at high ping (LOC 129-136). The server answers each
  pellet with `CCSUsrMsg_DamagePrediction` (UM15 607).

### Interpolation and buffering

- The setting "Buffering to smooth over packet loss / jitter" is none, one
  or two ticks (`cl_net_buffer_ticks`, CV 1552; LOC). By default it
  delays the client's clock rather than lengthening the blend
  (`cl_net_buffer_ticks_use_interp 0`, CV 1555).
- Clock sync keeps 5 ms between a snapshot arriving and being needed, and
  5 ms between a command reaching the server and being run, speeding up
  or slowing down within limits (CV 901-929, 2209-2228). The server keeps
  a command queue and makes up at most four commands for a client gone
  quiet (`cq_*`, CV 2500-2534).
- How far behind others are drawn at 64 Hz, inferred from the above and
  not measured: 5 to 21 ms plus half the ping with buffering off, and
  15.6 ms more a buffered tick. Source 1's default was 100 ms (from
  memory).
- There is no `net_graph`; `cl_hud_telemetry_*` shows ping, missed ticks,
  jitter and how early commands arrive (CV 1375-1400).

### Prediction

- The client predicts its own movement, recoil and aim punch, weapon
  drops, the defuse, and optionally damage effects (CV 970, 1729, 1738).
  Other players, health, hits and kills are the server's (inferred).
- After an error it replays its unacknowledged commands and smooths the
  view over 0.2 s (`cl_smoothtime`, CV 2110), with a new spring for the
  body (`cl_smooth_root_*`, CV 2092-2107).

### Transport

- Up to four commands a packet, delta-coded (`cl_usercmd_max_per_movemsg
  4`, CV 2284; inferred: the new one plus resends). `cl_cmdrate`,
  `cl_updaterate` and `cl_cmdbackup` no longer exist.
- Snapshots are deltas against a tick the client acknowledged, and
  acknowledgements out of order get a client kicked
  (`sv_deltaticks_enforce 2`, CV 9936; NM `CSVCMsg_PacketEntities`).

### Peeker's advantage, and options past CS2

Nobody has published a careful measurement for CS2. With Riot's formula
(WS: technology.riotgames.com, "Peeking Valorant's netcode"), two players on
30 ms pings at 64 Hz with buffering off come to about 45 to 75 ms (inferred
estimate). Following `CLAUDE.md` (CS2 is the starting point, not the limit),
these are options, each with its cost:

1. **Hitbox history on the tick, rewound to the command's tick and
   fraction.** CS2's own model and already the plan (systemization finding
   8). Removes the "rewound further than the screen" class of bug. Cost:
   about 0.1 ms a body a tick, 450 bytes a player a tick
   (`performance.md`).
2. **Clock-sync buffering instead of a fixed blend delay**, as CS2 does by
   default: others drawn about 0.3 to 1.3 ticks behind instead of two.
   Cost: a clock loop on both ends and a missed-tick counter.
3. **A rewind cap of 200 ms**, like CS2's, optionally lower against humans.
   Bounds how far behind cover a high-ping peeker can hit you. Cost:
   players over the cap must lead their targets.
4. **Rewind only part of the peeker's latency.** The peeker feels some of
   the delay. Cost: high-ping shots can miss what they saw; needs a
   playtest.
5. **Draw others with sub-tick timing.** The server knows each input's
   `when`, so a snapshot could carry a player's position at their last
   input change. Not a CS2 feature. Cost: bandwidth and extrapolation that
   can overshoot.
6. **Keep input times from the OS event**, which the project already does
   and CS2 does not.

When the rewind lands: `player_sim.gd` blends the shot's origin between the
last two positions, where CS2 sends the client's own `shoot_position` and
checks it (inferred worth copying).

## Measuring in CS2 (Local)

Most unknowns above come out of one recording rather than a stopwatch.
Record a demo on a local 64-tick server with `sv_cheats 1` (`record test`),
then parse it with demoparser2 (MIT). Per tick it reads
`velo_modifier` (the tag), `aim_punch_angle`, `accuracy_penalty`,
`i_recoil_idx`, `fl_recoil_idx`, `zoom_lvl`, `is_burst_mode`,
`burst_shots_remaining`, `post_pone_fire_ready_time` and
`time_silencer_switch_complete`; per shot the `fire_bullets` event (seed,
inaccuracy, spread, aim punch) and `bullet_impact` (DP 640-643, 829-847,
909-910, 1096, 1145-1163). The aim punch from being hit moved to
`CCSPlayer_AimPunchServices` in April 2026, so demoparser2 needs that field
path added before it can read the flinch.

The rig: `bot_add_t`, `bot_stop 1`, `bot_dont_shoot 1`, `mp_free_armor`
0, 1 or 2, `buddha 1` when Sid is the one shot; place a bot exactly with
`setpos_player` and `ent_setang`, and himself with `setpos_exact` (CMD).

| Unknown | Item | How |
|---|---|---|
| Recovery curve, recoil index decay between taps | R13 | Demo: 1, 3 and 6 AK rounds, `accuracy_penalty` and `fl_recoil_idx` each tick |
| Recoil in degrees, `recoil_scale`, "random" recoil seeded | R6, item 8 | Demo with `weapon_accuracy_nospread 1`: `aim_punch_angle` and impacts; two identical Deagle tap runs |
| Shots clustering toward the centre | R13 | `weapon_accuracy_forcespread 0.05`, 100 rounds, count inside half the radius |
| Shotgun patterns | R5 | Five shots per shotgun at a wall from 496 units, `sv_showimpacts 1` |
| Tracer order and speed | R10 | Tap singles at a wall; decompile a tracer `.vpcf_c` |
| Scope accuracy ramp, zoom times | R4 | `weapon_debug_spread_show 1` at `host_timescale 0.1` |
| Burst accuracy | R3 | Demo: `fire_bullets.inaccuracy` for each round of a burst |
| R8 hammer delay | R7 | Demo: `post_pone_fire_ready_time` against the press and the shot |
| Knife damage, reset window, reach, backstab angle, swing rates | K1 | Bot moved 1 unit at a time; turned 5 degrees at a time; swings timed at `host_timescale 0.25` |
| Zeus range and falloff, whether its inaccuracy applies | item 21 | Bot at 100 to 125 units; `weapon_debug_spread_show 1` |
| Knife and Zeus damage to teammates | item 21 | Competitive friendly fire, armoured and not |
| Tag size, Large or Small, recovery, stacking, in the air, armour | 4a, A1 | Demo: `velo_modifier` after head, chest, arm, leg, armoured, two and three quick hits, a jumping victim, an MP9 hit |
| Flinch size, direction, decay, armour and helmet | 4a | Demo: the new aim punch field; screenshots at `host_timescale 0.1` |
| Stomach and leg multipliers, arm armour | 4a | One AK round each to head, chest, stomach, arm, leg; expect 144, 36, 45, 36, 27 unarmoured |
| Damage indicator fade | 4 | Screen recording at `host_timescale 0.1` |
