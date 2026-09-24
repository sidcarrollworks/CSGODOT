# How CS2's accuracy on the move works: research

Sid, 2026-09-24: "have a couple agents research those as well", about the
research gaps listed in the project chat that morning. This page takes
accuracy on the move: how a gun's inaccuracy grows with the shooter's speed,
what the walk key does to that, and how landing from a jump or a drop costs
accuracy. It checks each against what `src/weapons/weapon.gd` does today.

How fast a player stops (deceleration, counter-strafing's timing), the jump
itself, stamina, crouching and sub-tick movement belong to the parallel
research on movement and are left to it. The guns' other numbers, being hit,
the knife, the Zeus and netcode are in `combat.md`, which this page builds
on and does not repeat.

It records what CS2 does and what is still unknown, says how Sid can measure
each unknown (Local), and changes no code.

## Sources

One research pass on 2026-09-24. The keys follow `combat.md`'s:

| Key | Source |
|---|---|
| WV | CS2's `scripts/weapons.vdata`, as `reference/weapons/vdata.csv` carries it (GameTracking-CS2 `game/csgo/pak01_dir/scripts/weapons.vdata` @d45f52d is the same file). A pair `a\|b` is `[normal, alternate]` |
| SH | Sid's community sheet, `reference/weapons/cs2_weapon_sheet.csv` (18 March 2026) |
| CV | GameTracking-CS2 `DumpSource2/convars.txt` @d45f52d, by line |
| SCH | GameTracking-CS2 `DumpSource2/schemas/server/<Class>.h` @d45f52d, CS2's own class layouts |
| PB | GameTracking-CS2 `Protobufs/cs_gameevents.proto` @d45f52d |
| SS | GameTracking-CS2 `game/csgo/bin/win64/{server,client}_strings.txt` @d45f52d (names and format strings only) |
| DP | demoparser2 (LaihoE/demoparser, MIT), `src/parser/src/maps.rs` on `main`, 2026-09-24: the properties it reads from a CS2 demo |
| WS | A web search's summary of a named page. The proxy refused cs.money, the Counter-Strike fandom wiki, HLTV, Steam and gist.github.com, so these are search summaries, not the pages. Re-read them before quoting them |

Labels: **inferred** means reasoned from names, fields or data, not stated
by Valve. **From memory** means not checked against any source reachable
here. Nothing on this page comes from Valve's leaked CS:GO source.

## What the repo does now (main at 3975eef)

- **Speed.** `Weapon.current_inaccuracy` (`src/weapons/weapon.gd:386-404`)
  adds nothing below 0.34 of the gun's `m_flMaxSpeed` and the whole
  `m_flInaccuracyMove` from 0.95 up (`MOVING_FROM`, `MOVING_FULL`,
  `weapon.gd:78-81`). Between, the share is the fourth root of how far along
  the speed is, or the share itself with the walk key down. The speed is the
  horizontal one (`player_sim.gd:630-633`, read only).
- **Landing.** On the tick the shooter touches ground, the penalty becomes
  at least the sheet's "Inaccuracy After Landing" less standing
  (`weapon.gd:264-267`), the same for every fall, and recovers on the
  standing or crouched recovery time. The game's own landing field is not
  used (`weapon_vdata.gd:12-14`).
- **Airborne.** The whole `m_flInaccuracyJump` while off the ground
  (`weapon.gd:390-391`). `m_flInaccuracyJumpInitial` and
  `m_flInaccuracyJumpApex` are not used.
- `reference/weapon_stats.md:100-104` and `movement_constants.md:23-24`
  describe the same model and give it as CS:GO's.

## Summary

| What the repo assumes | Verdict |
|---|---|
| No cost below 34% of the gun's top speed | **Community figure for CS2 too** (WS). No file states it; it is a compiled constant |
| Full cost from 95% | **Unsourced** (from memory, CS:GO). Nothing reachable here names it |
| Fourth-root rise between, steep early | **Open, and possibly backwards.** Valve's one public word on the shape (CS:GO, 10 July 2013) calls it exponential, which usually means slow early, steep late (WS) |
| The walk key makes the rise linear | **Unconfirmed** (from memory). CS2 does track the walk key on the player (`m_bIsWalking`, SCH) |
| Landing costs the same for every fall | **Probably wrong.** The game's landing field is a coefficient about a thousand times smaller than every other inaccuracy, and CS2 keeps each landing's speed (WV, SCH; inferred) |
| The sheet's landing figure is the penalty landing puts on | **Probably wrong.** It cannot be rebuilt from the game's coefficient and any one fall speed; the factor between them runs from 1.5 to 484 and follows each gun's recovery time (below) |
| Jumping is one flat term | **Incomplete.** CS2 has three jump fields; see `combat.md` §R13 "Jumping" |

All three open questions come out of one demo on Sid's machine (last
section).

## 1. Speed to inaccuracy

### What CS2 stores

- Per gun and mode: `m_flInaccuracyMove` and `m_flMaxSpeed` (WV; SCH
  `CCSWeaponBaseVData`, both `CFiringModeFloat`, so the scoped or silenced
  mode has its own). The AK is 0.17506 and 215; the AWP 0.17648 at 200
  unscoped and 100 scoped; the M4A1-S 0.09288 with the silencer off and
  0.122 with it on (WV).
- **Every shot reports its movement term apart from the rest.**
  `CMsgTEFireBullets` carries `inaccuracy` and `spread`, and in its `Extra`
  part `inaccuracy_move` and `inaccuracy_air` (PB lines 20-45). So the total
  is built from separate terms, one of them the speed's, which is how the
  repo adds them (inferred from the field names).
- The server's debug line for a shot prints the speed beside the
  inaccuracy: `FireBullets @ %10f [ %s ]: inaccuracy=%f spread=%f max
  dispersion=%f mode=%2i vel=%10f seed=%3i` (SS). Inferred: the speed the
  movement term is read from is the one in effect when the round fires.
- **No convar sets the curve.** The only movement-accuracy convars are
  disabled experiments: `sv_strafing_inaccuracy_enabled false` with its
  bias 0.5 and scale 0.1, `sv_turning_inaccuracy_enabled false` with its
  angle 4 and decay 0.8 (CV 10758-10830), and the development-only
  `sv_extreme_strafe_accuracy_fishtail 0`, "degrees of aim 'fishtail' when
  making an extreme strafe direction change" (CV 10020). The weapon keeps
  their state (`m_flTurningInaccuracy`, `m_flTurningInaccuracyDelta`, SCH
  `CCSWeaponBase`), unused while they are off. The thresholds and the shape
  are compiled in; no strings file carries a float, so they cannot be read
  here.

### The threshold

- Community guides for CS2 give 34% of top speed as where moving starts to
  cost accuracy, "roughly 88 units/s with a rifle" (WS: steamanalyst.com,
  metabot.gg, 2026). 34% of the AK's 215 is 73 u/s; 88 would be 34% of 260,
  so the guide's figure is loose. Same threshold as the repo.
- A coincidence worth knowing: the duck speed is 0.34 of top speed
  (`movement_constants.md:24`, CS:GO's). Crouch-walking at full crouch speed
  therefore sits exactly at the threshold and costs nothing (inferred; it
  holds if both numbers are CS2's).
- **Which top speed.** The repo divides by the gun's `m_flMaxSpeed` for the
  current mode. CS2 also keeps the player's own current top speed
  (`m_flMaxspeed`, SCH `CPlayer_MovementServices`), which differs from the
  gun's when tagged (`m_flVelocityModifier`, SCH `CCSPlayerPawn`) or on the
  Negev, whose `m_flAttackMovespeedFactor` 0.5 is the only one not 1.0 (WV;
  inferred: it halves speed while firing). Which one the threshold uses is
  unknown. Either way a tagged player slows and so shoots straighter, since
  the cost follows speed (inferred).

### The shape between

- CS:GO's release notes of 10 July 2013: "Adjusted the function that maps
  movement speed to weapon inaccuracy. The linear portion of this function
  is now exponential." Players at the time read it as changing only the
  stretch from standing to moving accuracy, not the running figure (WS:
  HLTV news 10954, a Steam discussion of 7/10/13). Nothing reachable here
  says Valve changed it again for CS2.
- "Exponential" in everyday use means slow at first and steep near the top.
  The repo's fourth root is the opposite: steep at first, flat near the top.
  For the AK at 80 u/s, just past the threshold, the repo gives 5.2 degrees
  of a full run's 10.3; a curve that rises late would give well under 1. How
  a counter-strafe feels in its last few ticks depends on which is right.
  The repo's shape came into PR #23 without a cited source (from memory).
- The community's "0.95" and the fourth root are not in any file or search
  result this pass reached.

## 2. The walk key

- CS2 keeps whether the player is walking on the pawn, `m_bIsWalking` (SCH
  `CCSPlayerPawn`), and demos carry it (`is_walking`, and the `WALK` button
  bit 1 << 16, DP). Inferred: it is networked because something the client
  predicts reads it, and the weapon's inaccuracy is the obvious candidate.
- The walk speed is 0.52 of top speed in the repo (CS:GO's,
  `movement_constants.md:23`); 112 u/s for the AK, above the 73 u/s
  threshold. So a walking AK is never at standing accuracy while it moves.
  Whether CS2's walk is still 0.52 is the movement research's to settle.
- **What the key does to the curve is unconfirmed.** The repo's reading
  (linear while walking, fourth root otherwise) is from memory. Two other
  readings fit what players say ("walking is more accurate"): the key does
  nothing to the curve and walking only helps by being slower; or walking
  uses its own curve. At the AK's full walk speed the three give 3.4
  degrees (the repo's linear), 7.8 (the repo's running curve at walking
  speed), or something else. Guides only say walking is better than running
  and worse than standing (WS: csmarket.gg, cs.money).
- The test that separates them holds the speed and flips only the key (see
  the last section).

## 3. Landing

### What CS2 stores

- **`m_flInaccuracyLand` is a coefficient, not a cone.** The AK's is
  0.000242; its standing inaccuracy is 0.00641 and its running term 0.17506
  (WV). Across the guns it runs from 0.000043 (Deagle) to 0.000409 (Negev),
  a thousand times smaller than the other inaccuracies. Inferred: it is
  multiplied by something about the landing, most plausibly the fall speed
  in units a second, which is in the hundreds.
- **CS2 keeps each landing's speed.** `CPlayer_MovementServices_Humanoid`
  has `m_flFallVelocity`; the modern jump keeps `m_nLastLandedTick`,
  `m_flLastLandedFrac` and `m_flLastLandedVelocityX/Y/Z`
  (`CCSPlayerModernJump`); the pawn keeps `m_lastLandTime`,
  `m_flLandingTimeSeconds` and `m_bOnGroundLastTick` (SCH). Demos carry
  `m_flFallVelocity` as `fall_velo` (DP). demoparser2 also names a
  `m_flMaxFallVelocity`, which today's schema no longer has.
- **One penalty per gun.** `CCSWeaponBase` has a single accumulating
  `m_fAccuracyPenalty` with its `m_flLastAccuracyUpdateTime` (SCH), and
  demos carry it per tick as `accuracy_penalty` (DP). Inferred: landing
  adds to this penalty, as firing does, and it recovers on the gun's
  recovery times like the rest. The repo already keeps one penalty
  (`_inaccuracy`) but sets the landing figure as a floor instead of adding
  to it.
- `weapon_land_dip_amt 20`, "the amount the gun should dip when the player
  lands after a jump" (CV 11793), is the view model's dip only: cosmetic.
- The Deagle's April 2020 change also shortened "the time to recover
  accuracy after the player lands" (WS: CS:GO release notes 2020). With no
  landing-recovery field in WV, inferred: that was done through the
  coefficient or the recovery time, not a separate timer.

### What a fall-scaled landing would give

A jump on flat ground lands at about its take-off speed, 302 u/s
(`sv_jump_impulse` 301.993 in the repo); a drop of 100 units lands at
about 400 u/s. Coefficient times fall speed, if that is the rule (inferred):

| Gun | Coefficient (WV) | Flat jump, x 302 | 100-unit drop, x 400 | Sheet's excess over standing (SH) |
|---|---|---|---|---|
| AK-47 | 0.000242 | 73.1 (4.2°) | 96.8 (5.5°) | 26.6 (1.5°) |
| M4A1-S, silencer on | 0.000197 | 59.5 (3.4°) | 78.8 (4.5°) | 16.6 (1.0°) |
| AWP, scoped | 0.0001 | 30.2 (1.7°) | 40.0 (2.3°) | 17.8 (1.0°) |
| Desert Eagle | 0.000043 | 13.0 (0.7°) | 17.2 (1.0°) | 20.8 (1.2°) |
| Glock-18 | 0.000185 | 55.9 (3.2°) | 74.0 (4.2°) | 3.1 (0.2°) |
| SSG 08, scoped | 0.000215 | 64.9 (3.7°) | 86.0 (4.9°) | 0.3 (0.02°) |

Figures in thousandths (the sheet's unit), degrees in brackets. A step
down a small ledge would cost almost nothing under such a rule; the repo
charges it the full figure.

### What the sheet's landing figure is

`vdata.md` calls the sheet's figure a composite "of another kind", the
game's term scaled by the fall. It does not fit one fall speed. Taking the
sheet's figure less standing inaccuracy and spread, and dividing by the
game's coefficient, gives a factor that is the same for a gun's two modes
(the AWP excepted: 80 unscoped, 178 scoped) and for guns sharing a
recovery time (MP7 and MP5-SD 142.2; G3SG1 and SCAR-20 217.3; Nova and
Sawed-Off 158.4 and 158.2, with coefficients 0.000236 and 0.000108), but
runs from 1.5 (SSG 08) and 16.8 (Glock, Five-SeveN) through 110 (AK) to
398 (M249) and 484 (Deagle). It correlates with `m_flRecoveryTimeStand` at
r = 0.97 and with no other field above 0.86 (all 33 guns, computed here).

Inferred: the sheet's figure is not the penalty at the moment of landing
but what is left of it some time later, after the gun's own recovery has
worked on it; a slow-recovering gun (Deagle, M249) keeps more, a fast one
(SSG 08, Glock) almost none. No single fall speed and delay reproduces all
33 exactly, so the sheet's method is still unknown. Either way the repo
puts that already-recovered figure on at landing and then recovers it
again, so its landing penalty is likely too small at first and gone too
soon for most guns, and too large for the Deagle.

## 4. Jumping, as it bears on landing

`combat.md` §R13 "Jumping" covers the three fields. Only what matters for
landing: `m_flInaccuracyJumpInitial` (AK 0.10094) is, by its name, the cost
at take-off (inferred); if it goes into the same penalty it is still
recovering when a short hop lands. The Deagle's apex term has a flag on
the movement service, `m_bJumpApexPending` (SCH
`CCSPlayer_MovementServices`), so the game marks the apex as an event
(inferred). `weapon_air_spread_scale 1` scales the airborne term (CV 11772).

## Corrections other docs and code need

For whoever takes these on; this PR makes none of them.

1. `src/weapons/weapon.gd:78-81`, `:392-404`: the 0.95 and the fourth root
   are unsourced, and the one public description of the shape suggests a
   late rise. Keep them until the demo below, then fit the measured curve.
   The comments that say "as CS does" should say "CS:GO's, unconfirmed"
   until then.
2. `src/weapons/weapon.gd:264-267`: landing should add the game's
   coefficient times the landing speed to the penalty, not floor it at the
   sheet's figure, once the demo confirms the rule. The shooter state would
   need the landing speed, which `player_sim.gd` (the local agent's) would
   pass; a hook to list in `reference/systems/` rather than edit here. No
   extra traces: the speed is the velocity already in hand on the landing
   tick.
3. `src/weapons/weapon_vdata.gd:12-14` and `reference/weapons/README.md:14`,
   `:95`: the landing is "a coefficient the game scales by the fall" holds;
   add that the sheet's figure looks like the penalty after some recovery,
   not at landing.
4. `reference/weapon_stats.md:96-104`: "as in CS:GO" for the thresholds and
   the fourth root should say unconfirmed, and the landing sentence should
   point here.
5. `reference/movement_constants.md:23-24`: the walk and duck modifiers
   matter to accuracy too (the duck one sits exactly on the threshold);
   note it beside them.
6. `reference/research/combat.md` §R13 "Jumping": add
   `m_bJumpApexPending` and the landing fields above.
7. `tests/run_tests.gd` phase 9 (counter-strafe timings) measures when the
   cone closes; the 78 ms and 203 ms it prints depend on the curve's shape
   and will move when the curve does.

## Measuring in CS2 (Local)

Only Sid has CS2. One demo answers everything above. Record on a local
64-tick server with `sv_cheats 1` (`record moving`), and parse it with
demoparser2 (MIT), which reads per tick `velocity`, `is_walking`,
`is_airborne`, `fall_velo` and `accuracy_penalty`, and per shot the
`fire_bullets` event with `inaccuracy`, `spread`, `inaccuracy_move` and
`inaccuracy_air` (DP; PB). `combat.md`'s last section has the bot and
placement commands.

| Unknown | How |
|---|---|
| Threshold, full point and shape of the speed curve | AK, `weapon_accuracy_nospread 0`; hold fire and let go of a run key so the speed falls through the whole range; repeat by strafing and by releasing. Plot `inaccuracy_move` against horizontal speed from `velocity` |
| Whose top speed sets the threshold | The same with the AWP scoped (100) and unscoped (200); and with a tagged player (`velo_modifier` below 1) |
| What the walk key does | `sv_maxspeed 110`, so running and walking both top out at the same speed; run and walk at it with the AK and compare `inaccuracy_move`. Different at the same speed means the key changes the curve |
| Walk speed | `cl_showpos 1`, or `velocity` in the demo, walking at full speed with the knife and the AK |
| Landing rule | Drop from heights of 0, 16, 32, 64, 128 and 256 units (`setpos_exact`) with the AK; read `accuracy_penalty` on the landing tick and the tick before, and `fall_velo` just before landing. A fall-scaled rule makes the jump in penalty a straight line in fall speed; check its slope against 0.000242 |
| Whether landing adds or floors | Fire a few rounds, then land while the penalty is still up; compare with a landing from rest |
| What the sheet's landing figure is | The AK's penalty 0.2, 0.3 and 0.4 s after a flat jump's landing, against the sheet's 26.6 thousandths less standing |
| Take-off cost | `accuracy_penalty` on the take-off tick of a standing jump, against `m_flInaccuracyJumpInitial` |
| Crouch-walking | Crouch-walk at full speed; `inaccuracy_move` should be 0 if the duck speed is 0.34 |

Until these are in, the repo's curve and landing stay as they are:
changing them on a guess would only swap one guess for another.
