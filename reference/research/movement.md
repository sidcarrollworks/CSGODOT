# How CS2 moves: research

Sid, 2026-09-24: "Looking at the roadmap is there anything else we should
research?", then "have a couple agents research those as well". This page
covers movement, his top priority: CS2's 2026 jump, stamina and the landing
slowdown, crouching, and sub-tick movement, each checked against the port
in `src/movement/` and `src/player/`, and what players criticise and want
changed. Accuracy while moving and landing is researched separately; this
page only gives the movement timings it rests on. It changes no code.

`reference/research/combat.md` already covers the user command's fields,
netcode and the guns; this page builds on its section 4.

## Sources

Sid, 2026-09-24: "make sure it's clear that we want the most up to date
information for primary sources if possible". So the sources are ranked:

1. CS2's own files at its newest build, and Valve's own release notes.
2. Older CS2 builds, used only to date a change.
3. Source SDK 2013 and anything CS:GO-era, used only where no CS2 source
   says anything, and marked **older** beside the claim.
4. Community measurements, pages and search summaries, marked
   **secondary** beside the claim.

| Key | Source | Date or build |
|---|---|---|
| CV | GameTracking-CS2 `DumpSource2/convars.txt` @d45f52d, by line | CS2 build 2000915, patch 1.41.8.3, 23 Sep 2026: the newest GameTracking-CS2 commit on 24 Sep 2026 |
| SCH | GameTracking-CS2 `DumpSource2/schemas/server/<Class>.h` @d45f52d, by line | Build 2000915 |
| SS, CS | GameTracking-CS2 `game/csgo/bin/win64/server_strings.txt` and `client_strings.txt` @d45f52d (names and format strings only) | Build 2000915 |
| UC, UM15 | GameTracking-CS2 `Protobufs/usercmd.proto` and `cstrike15_usermessages.proto` @d45f52d | Build 2000915 |
| GI, CFG | GameTracking-CS2 `game/csgo/gameinfo.gi` and `game/csgo/cfg/gamemode_*.cfg` @d45f52d: neither overrides a movement convar | Build 2000915 |
| VN | Valve's release notes, the text of counter-strike.net/news/updates as archived by ckreisl/cs-updates-as-json @656981c (`data/cs2/updates_raw.json`), dated as Valve dated them (the date in the heading, or the date posted where the heading has none) | 231 posts, 22 Mar 2023 to 22 Sep 2026 |
| CVH, SCHH | The same convar and schema files in GameTracking-CS2's history: 52 convar dumps from 7 Jan 2025 on (older builds, used to date changes; network annotations were dumped until 20 Apr 2026) | 7 Jan 2025 to 23 Sep 2026 |
| SDK | Source SDK 2013 `src/game/shared/gamemovement.cpp` @b8cfb12, read as a spec only. **Older**: Half-Life 2's movement code, not CS2's | Commit of 17 May 2025; the code dates from the Source 1 era |
| DP | demoparser2 (LaihoE/demoparser, MIT) @9ddb373, `src/parser/src/maps.rs`: the property names it reads from a CS2 demo. **Secondary** | 21 Sep 2026 |
| ZK | zer0k-z, `cs2-movement-issues` @26f1716: `readme.md` (measured with demos) and `bhopping branch.md` (reverse-engineered notes on the jump check, 31 Jul 2025). **Secondary**, and its author marks the readme out of date since November 2025, so it predates the 2026 jump | Last commit 21 Jan 2026 |
| WS | A web search's summary of a named page. **Secondary.** Steam, counter-strike.net, HLTV, Dust2.us, fandom, VDC, Liquipedia and teamfortress.tv all refused fetches from this session | Each dated where the summary gives one |
| MOD | Worked out here with `MovementSolver`'s equations at CS2's numbers (a Python copy of `apply_friction` and `accelerate`, 64 Hz) | 24 Sep 2026, off main 3975eef |

Labels: **inferred** means reasoned from names, fields or data, not stated
by Valve. **From memory** means not checked against any source reachable
here. Nothing on this page comes from Valve's leaked CS:GO source; ZK's
notes are a third party's reading of the shipped game, used as a
description only.

## In short

- **Our constants are CS2's** (CV, build 2000915). Every movement convar
  agrees with `MovementConfig`, `sv_accelerate` 5.5 included.
  `sv_maxspeed` is 320 in CS2 but is only a ceiling no item reaches; the
  250 in our table is the knife's own speed, and the row is misnamed.
- **CS2 replaced its jump on 21 January 2026** (VN). The landing is timed
  to the sub-tick; a jump pressed within 3.9 ms either side of it (a
  1/128 s window) is a perfect bunny hop; jumping and landing no longer
  cost stamina; since 22 January a landing slows you by an amount set by
  when you landed and how fast you were falling (section 2). Ours has none
  of the three.
- **Our jump height may be 2.4 units high.** No CS2 source gives the
  height. The **older** Source SDK 2013 jump takes half a tick of gravity
  off the impulse at once, which our port leaves out; with it a jump peaks
  at 57.0 at any tick rate, the height CS2's own convar description gives
  (CV 10179), and ours peaks at 59.4 (section 2.3). A jump against the
  gauges settles it.
- **CS2 does not duck instantly in the air** (VN, 1, 21 and 24 April
  2026), and it ignores a second duck within 0.4 s (CV 10815). Ours snaps
  in the air, so our crouch jump reaches 77 units; the only figure for
  CS2's is a **secondary** community one, about 66 (section 4).
- **CS2 splits a tick at every key and view change, and our movement keys
  are not sub-tick at all.** A counter-strafe here starts up to a tick
  before the key went down: 70 ms from the press to a third of the AK's
  speed on average here, against 80 ms when the tick splits at the press
  (MOD, section 5.4).
- **What players want** (section 7): mostly 128-tick air strafing, hops
  that do not depend on luck, no advantage from scroll wheels or special
  keyboards, and a gentler crouch penalty. Each is weighed against ours.

## 1. The constants

CS2's values (CV, build 2000915), all `replicated`, none overridden by GI
or any `gamemode_*.cfg`:

| Convar | CS2 | Ours (`movement_config.gd`) | Agrees |
|---|---|---|---|
| `sv_accelerate` | 5.5 (CV 9681) | `accelerate` 5.5 | Yes: retires the "5.5 or 5.6" question |
| `sv_airaccelerate` | 12 (CV 9696) | `air_accelerate` 12 | Yes |
| `sv_air_max_wishspeed` | 30 (CV 9693) | `air_max_wishspeed` 30 | Yes |
| `sv_friction` | 5.2 (CV 10074) | `friction` 5.2 | Yes |
| `sv_stopspeed` | 80 (CV 10755) | `stop_speed` 80 | Yes |
| `sv_gravity` | 800 (CV 10092) | `gravity` 800 | Yes |
| `sv_jump_impulse` | 301.993, "sqrt(2\*gravity\*height)" (CV 10179) | `jump_impulse` 301.993 | Yes; 301.993²/1600 = 57.0 units |
| `sv_maxvelocity` | 3500 (CV 10317) | `max_velocity` 3500 | Yes. VN 12 Nov 2025 raised the most a server may set to 16,384; the default is unchanged |
| `sv_stepsize` | 18 (CV 10752) | `step_height` 18 | Yes |
| `sv_standable_normal`, `sv_walkable_normal` | 0.7 (CV 10728, 10974; added for community servers, VN 16 Nov 2023) | `max_ground_angle_deg` 45.57 (acos 0.7) | Yes |
| `sv_maxspeed` | 320 (CV 10305) | none | See below |
| `sv_enablebunnyhopping` | false, "Allow jump speed to exceed 1.1x max speed" (CV 9993) | `enable_bunnyhopping` false, cap 1.1 | Yes |
| `sv_autobunnyhopping` | false (CV 9753) | `auto_bunnyhop` false | Yes |

**`sv_maxspeed`.** CS2's ceiling on anyone's speed is 320. What a player
runs at comes from what they hold: `m_flMaxSpeed` in the weapons vdata,
250 for the knife and the C4 and 245 at most for everything else
(`reference/weapons/vdata.csv`, generated from build-era weapons.vdata),
and `PlayerSim._draw` already sets it from there (player_sim.gd:444-448).
Nothing in CS2 reaches 320, so the ceiling never binds on dust2. The
mistake is the row in `reference/movement_constants.md:19`, which calls the
knife's 250 `sv_maxspeed`. `CPlayer_MovementServices` keeps the player's
own ceiling as `m_flMaxspeed` (SCH `CPlayer_MovementServices.h:17`).

**`sv_accelerate_use_weapon_speed` true** (CV 9687, no description).
Inferred from its name: ground acceleration is scaled by the held weapon's
speed, as ours is (`accel_speed = accel * dt * wish_speed`,
movement_solver.gd:55). What CS2 does with it off, and whether walking or
ducking change the speed used in that product, is in no CS2 file; a run
from rest with Shift held settles it (Local).

## 2. The 2026 jump

### 2.1 What changed, and when

All from Valve's notes (VN), by the date posted, and dated in CS2's files
where they show it:

- **29 June 2023**: "Bunny hopping feel should now closely match CS:GO
  running at 128 tick"; `sv_jump_spam_penalty_time` added. 30 June: "Bunny
  hopping once again has a speedlimit".
- **28 October 2024**: "Improved jump height consistency to be within
  0.015625 of a unit regardless of distance from the map origin";
  "Improved consistency of successfully landing on surfaces very close to
  the maximum height of a jump"; "Jump height is still affected by
  stamina; when using `cl_showpos 2`, stamina at takeoff is reported and
  output is color coded based on possible jump height." 29 October:
  `sv_jump_precision_enable` added so surf servers can opt out (CV 10182).
  The client still carries the readout: `jump: %.3f (%.2f) [%.2f] @
  stamina: %.1f, impulse mul: %.3f` (CS 35160). The fields
  `m_flHeightAtJumpStart`, `m_flMaxJumpHeightThisJump` and
  `m_flAccumulatedJumpError` (SCH `CCSPlayer_MovementServices.h:38-43`)
  belong to this (inferred).
- **1 August 2025**: "Fixed a bug that would cause bhopping penalty to
  continue to accumulate even when jump had not been pressed"; "Bhopping
  jump spam clock now starts at the instant the input is registered,
  rather than then end of the subtick where that command was processed."
- **12 November 2025**: "Fixed a case where clients would mispredict jump
  button presses" and "jump apexes". `m_bJumpApexPending` joined the
  schema on 4 November 2025 (SCHH).
- **21 January 2026**: "Jump changes: Landing time is now calculated with
  subtick precision"; "Jumping and landing no longer affect stamina. The
  landing speed penalty is now a simple function of landing time"; "Any
  jump press within `sv_bhop_time_window` centered on the landing time
  that hasn't been penalized by `sv_jump_spam_penalty_time` will be treated
  as a successful bunnyhop"; "Legacy jump behavior can be restored on
  private servers with `sv_legacy_jump`." The dump of 25 January 2026 is
  the first with `sv_legacy_jump` and `sv_bhop_time_window`; it
  re-describes the stamina costs as legacy-only and `sv_enablebunnyhopping`
  as the 1.1x cap (CVH, 10a53ce against 69f39e8). The same day the schema
  gained `CCSPlayerLegacyJump` and `CCSPlayerModernJump` (SCHH).
- **22 January 2026**: "Landing vertical velocity now affects landing speed
  penalties similar to `sv_legacy_jump` stamina."
- No movement convar changed value between 25 January and 23 September
  2026 (CVH), and no later note changes the jump.

### 2.2 How the new jump decides

The convars (CV, build 2000915):

- `sv_legacy_jump` false: "Whether or not to use the pre-2026 jump code"
  (10221).
- `sv_bhop_time_window` 0.0078125 s, "the time window (in seconds) around
  landing where a jump press is considered a bhop attempt" (9771). That is
  1/128 s, half a 64 Hz tick, centred on the landing: 3.9 ms either side.
- `sv_jump_spam_penalty_time` 0.015625 s: "For subtick jumps, if this much
  time or less has elapsed since the last time the user has pressed the
  jump key, pretend they hadn't. Lowering this makes bunnyhopping easier"
  (10185). One 64 Hz tick. It is what makes spinning the scroll wheel
  worse than one clean press.

The modern jump's state (SCH `CCSPlayerModernJump.h`, build 2000915;
networked as of 25 January 2026, SCHH): the last actual press and the last
usable press (not cancelled by the spam penalty), each as a tick and a
fraction; and the last landing, as a tick, a fraction and the full landing
velocity (x, y and z). The fractions travel in 6 bits (SCHH), so 1/64 of a
tick, 0.24 ms.

Inferred from those fields and Valve's notes, the rule reads:

1. A press closer than 15.6 ms after the previous press does not count.
2. The landing is found to the sub-tick: the fraction of the step at which
   the body met the ground, not the end of the tick.
3. A counting press within 3.9 ms of that instant, before or after, is a
   perfect hop: the jump leaves as if from the landing instant. Storing
   the horizontal landing velocity suggests a late press inside the window
   gets back what friction took in the meantime (inferred).
4. A press outside the window is an ordinary jump from the ground, after
   whatever friction and landing slowdown have taken.
5. A hop's speed is still cut to 1.1 times the held weapon's speed
   (`sv_enablebunnyhopping`, CV 9993).

Why a window was needed, from before the change (**secondary**, ZK readme
"The perf window", pre-2026): every sub-tick step ran the ground check
again, so a press a moment after landing lost speed to friction, and a
player whose frames fell badly could not hop perfectly at all.

### 2.3 How high a jump goes

No CS2 file or note gives the height a jump reaches. What CS2 says: the
impulse is "sqrt(2\*gravity\*height)" (CV 10179), which at 301.993 and 800
is 57.0 units, and since 28 October 2024 the height is consistent to
1/64 unit (VN).

Ours rises 59.37 units at 64 Hz (`reference/movement_constants.md`, "Jump
height is tick-rate dependent in Source"). That page says this is Source's
order. The **older** Source SDK 2013 (Half-Life 2's code, not CS2's) says
otherwise:

- `CheckJumpButton` sets the jump velocity and then calls `FinishGravity()`
  itself, before the move (SDK gamemovement.cpp:2496), which takes half a
  tick of gravity off at once. `FullWalkMove` then runs its own
  `FinishGravity()` after the move as usual (SDK 2023-2125).
- The SDK has two branches. Ducked, it sets the vertical velocity to the
  impulse; otherwise it adds the impulse to what is there (SDK 2450-2462).

Worked out for each (MOD, standing on flat ground):

| | 64 Hz | 128 Hz |
|---|---|---|
| Ours (impulse, no `FinishGravity` in the jump) | 59.37 | 58.19 |
| SDK, velocity set to the impulse, then `FinishGravity` | 57.00 | 57.00 |
| SDK, impulse added after `StartGravity`, then `FinishGravity` | 54.65 | 55.83 |
| `sqrt(2*gravity*height)` as CS2's convar describes it | 57.00 | 57.00 |

The middle row is exactly what `MovementConfig.tick_rate_independent_jump`
does, so the fix, if it is one, is a flag already there. CS2's convar
description, the 2024 note's consistent height, and the fields that track
the height reached all point at 57.0 rather than 59.4 (inferred). Stamina
scaled the impulse before 2026 (`impulse mul`, CS 35160, and VN 28 October
2024); whether anything still does is unknown. The jump gauges settle it:
clear 57 and not 58 (Local).

### 2.4 What ours does

- The jump splits the tick at the press (`PlayerBody.simulate`,
  player_body.gd:124-152) and needs a fresh press on the ground
  (`_try_jump`, :301-313). That matches the sub-tick press.
- The landing is found only at the end of a step (`_categorize_position`
  at :182), not at the instant the hull met the ground.
- A press in the air just before landing is lost: in the air `_try_jump`
  does nothing, and on the next tick the key counts as held
  (`_jump_held_last_tick`). CS2 counts it if it is within 3.9 ms.
- There is no spam penalty: two scroll clicks in successive ticks both
  count.
- There is no landing slowdown in movement (section 3); only the gun's
  landing inaccuracy exists.

## 3. Stamina and the landing slowdown

What CS2 keeps (CV, build 2000915): `sv_staminamax` 80, "Maximum stamina
penalty" (10722); `sv_staminarecoveryrate` 60, "Rate at which stamina
recovers (units/sec)" (10725). Only the jump and landing costs are marked
"sv_legacy_jump only": `sv_staminajumpcost` 0.08 and `sv_staminalandcost`
0.05 (10716-10720). `m_flStamina`, `m_flStaminaAtJumpStart` and
`m_flVelMulAtJumpStart` are still in the pawn's movement state (SCH
`CCSPlayer_MovementServices.h:37-42`); `m_flStamina` was networked as of
25 January 2026 (SCHH).

What that means, inferred from those and VN 21 and 22 January 2026:
stamina is now the landing slowdown's own meter, capped at 80 and
recovering at 60 a second, and filled at a landing by an amount set by
when you landed and the landing's vertical speed, rather than by fixed
costs. Before 2026 stamina also scaled the next jump's impulse (VN 28
October 2024; CS 35160). That the old costs were a share of speed, 8% for
a jump and 5% for a landing, comes only from **secondary** convar pages
(WS: totalcsgo, undated).

How stamina turns into speed is in no CS2 file or note. **From memory,
older and not checked**: CS:GO multiplied ground speed by (100 - stamina)
/ 100 and set stamina from the costs times the vertical speed. The curve,
and what a standing jump on flat ground costs today, come from one demo
(Local, below).

`src/` has no stamina and no landing slowdown. Nothing in the movement
tests pins one either.

## 4. Crouching

CS2's state (SCH `CCSPlayer_MovementServices.h:8-19`, build 2000915):
`m_flDuckAmount` (0 standing, 1 ducked), `m_flDuckSpeed` (how fast the
amount moves), `m_bDesiresDuck`, `m_bDucking`, `m_bDucked`,
`m_flLastDuckTime`, `m_duckUntilOnGround`, `m_flDuckViewOffset`,
`m_flDuckRootOffset` (both since 20 April 2026, SCHH), and
`m_vecLastPositionAtFullCrouchSpeed`.

- **Duck spam.** `sv_timebetweenducks` 0.4, "Minimum time before
  recognizing consecutive duck key" (CV 10815; the same in every dump since
  7 January 2025). A second press within 0.4 s of the last is ignored.
  That `m_flDuckSpeed` also falls as you spam and recovers is inferred
  from its name; that CS2's penalty is stricter than CS:GO's is
  **secondary** (WS: a Steam thread, 2023). The numbers are in no file.
  `m_vecLastPositionAtFullCrouchSpeed` suggests the recovery is tied to
  where you were when the speed was last full (inferred, and unclear).
  Valve's notes touch duck speed twice: "Fixed cases of unintended slow
  crouch/uncrouch" (VN 29 June 2023) and a slower duck in Toggle mode fixed
  (VN 16 November 2023).
- **Ducking in the air is not instant.** VN 1 April 2026: "Smoothed in-air
  crouching transitions in first and third-person." VN 21 April 2026:
  "Fixed several cases where crouch transitions in the air were
  instantaneous." VN 24 April 2026: "Adjusted the firstperson in-air
  crouch transition time to match the thirdperson animation better."
  Inferred: the duck amount eases in the air as on the ground, and the feet
  come up as the hull shrinks, which makes CS2's crouch jump lower than an
  instant one.
- **Crouch jump height.** No CS2 file or note gives it. The only figure is
  **secondary**: about 66 units (WS: swap.gg and clash.gg guides, undated,
  and possibly from before April 2026), against ours at 77.37
  (`movement_constants.md`, "Crouch jump height"). Measure it (Local).
- **How long a duck takes** is in no CS2 file or note. Ours is the
  **older** Source's 0.4 s (`duck_time`), which `movement_constants.md:20`
  already doubts.
- **Crouched and walking speed.** Our 0.34 and 0.52 (`duck_modifier`,
  `walk_modifier`) are **older** CS:GO values; no CS2 file has them.
- **Player height on slopes** changed: "Player height on ramps is now
  consistent and no longer depends on approach direction" (VN 1 April
  2026), with ground smoothing adjusted on 30 April and 7 May 2026 (VN).
  `m_bUsingGroundTopologyOffset` (SCH :4-5) belongs to it (inferred).

What ours does (`_update_duck`, player_body.gd:215-231): the amount rises
at 1 / `duck_time` on the ground and the hull changes at full; in the air
the hull shrinks at once and the body moves up 18 units; no spam penalty,
no time between ducks.

## 5. Sub-tick movement

### 5.1 What the command carries

Each `CSubtickMoveStep` (UC 12-22, build 2000915) carries a button with
pressed or released and `when` (the fraction of the tick), analog changes
to forward and side movement (`analog_forward_delta`,
`analog_left_delta`), and the view change at that instant (`pitch_delta`,
`yaw_delta`). Movement keys are buttons like any other, and their releases
are timed too: "Releasing movement keys now correctly convey their
sub-tick timing" (VN 6 June 2023). `sv_quantize_movement_input` true (CV
10518; VN 27 November 2024) keeps analog input to the speeds digital keys
give.

Since 26 September 2025, "`sv_subtick_movement_view_angles` will now only
send subtick view angles to the server with other subtick events instead
of sending them for every frame they change" (VN). Binds that press more
than one movement or look command are ignored (`cl_allow_multi_input_binds`
false, CV 814; VN 19 August 2024).

### 5.2 How the server runs them

- Movement runs once per step: the profiling scope
  `CPlayer_MovementServices::DoMovement::Subtick` (SS 13036, CS 15001) and
  the names `subtick_start_fraction`, `subtick_end_fraction`,
  `subtick_duration` (SS 33103-33106). **Secondary** (ZK, pre-2026):
  "Every time a key is pressed or released, the tick simulation is split
  into two shorter simulations."
- View changes split it too, while `sv_subtick_movement_view_angles` is
  on: "Whether or not subtick view angles are taken into account during
  movement" (CV 10773; first in the dump of 29 July 2025, CVH).
- The game can force splits of its own: `m_arrForceSubtickMoveWhen[4]`
  (SCH `CPlayer_MovementServices.h:18`, `MAX_FUTURE_FORCED_SUBTICKS`, SS
  27477). Inferred: this is how a landing gets its own instant.
- **Splitting is meant not to change the result.** VN 17 September 2025:
  "Improved timestep-independence of subtick movement acceleration." VN 24
  September 2025: "Fixed a case where velocity was abnormally low while
  walking up ramps." `m_flGroundMoveEfficiency` left the schema on 16
  September 2025 (SCHH).
- **Friction is taken from the speed at the start of the tick.** From May
  2025 to April 2026 the pawn carried `m_flOffsetTickCompleteTime` and
  `m_flOffsetTickStashedSpeed`; since 20 April 2026 it carries
  `m_bUseFrictionStashedSpeed`, `m_flUseFrictionStashedSpeedUntilFrac`
  and `m_flFrictionStashedSpeed` (SCH `CCSPlayer_MovementServices.h:34-36`,
  SCHH). Inferred: friction's control speed is stashed once and used for
  every step until a fraction of the tick, so ten steps take the same
  speed off as one.
- Extra steps once bought extra speed, and Valve has closed those cases
  one by one: "Fixed a case where movement button changes were ignored
  while adjusting view angles at very high frame rates" and "Fixed a case
  where air strafing would result in higher than usual velocities" (VN 30
  July 2025); "Fixed a case where air acceleration was clamped incorrectly
  while surfing" and a slow surf up a ramp "misidentified as a jump apex"
  (VN 4 November 2025).

### 5.3 What ours does

- Only jumps split the tick (`PlayerBody.simulate`, player_body.gd:134-148).
- The movement keys are not in `PlayerInput.BUTTONS`
  (player_input.gd:47-55); they are read once when the command is built
  (`cmd.move`, :232-235) and act on the whole tick.
- The wish direction uses the yaw at the end of the tick
  (`UserCmd.wish_direction`, user_cmd.gd:111-121); the step angles are
  kept for shots only.
- Duck is read as held at the end of the tick (player_sim.gd:579).
- Every command covers the stretch since the last one was built, so a key
  that went down part-way through acts from the stretch's start: early by
  that fraction of a tick.

### 5.4 What it means at 64 Hz

**Counter-strafing (MOD).** An AK at its full 215 u/s presses the opposite
key at a random instant; time from the press until speed is under a third
of 215 (72 u/s, below which our guns stop charging for movement,
`weapon_stats.md:100-101`), read at the end of each tick, over 100 press
instants:

| | Tick splits at the press (CS2) | Whole tick takes the new key (ours) |
|---|---|---|
| Opposite key | 80 ms (72 to 88) | 70 ms (63 to 78) |
| Let go of every key | 210 ms (202 to 218) | 195 ms (188 to 203) |

The 78 ms in `weapon_stats.md:106-108` and `movement_constants.md:157` is
the tick-aligned case, a press exactly at a tick's start, and is the same
in both columns. Ours is quicker on average by about half a tick because
the key acts before it was pressed. The same early start makes the
release of a strafe key cost speed early.

**Air strafing.** A tick's air acceleration is capped at 30 u/s along the
wish direction however long the tick is, so gain grows with the number of
steps (`movement_constants.md:147-169`: a perfect strafe jump from 250
gains 77 u/s at 64 Hz, 127 at 128 Hz). If each sub-tick view step got the
full cap, CS2's gain would climb toward the 128 Hz figure with a second
step a tick; the fixes of July and November 2025 and the timestep
independence of September 2025 (VN) say it does not (inferred). The only
measurement is **secondary** and older than those fixes: ZK found CS2's
air strafe matching 64-tick CS:GO, "every flat ground jump is now up to 9
units shorter" than on 128-tick servers. So our 64 Hz figures are probably
CS2's; the HUD's jump gain against CS2's `cl_showpos 1` settles it
(Local).

What sub-tick view angles change for us is the direction, not the cap:
ours turns the wish direction once a tick, at its end, so a strafe's turn
lands up to a tick late. That is felt most at the start of a strafe.

**The bunny hop.** At 64 Hz a tick is 15.6 ms, and CS2's window is 7.8 ms
wide around the landing. Ours has no window: a press in the air is lost,
and a press after landing pays friction for the part of the tick before
it (hopping at 230 u/s keeps 227.66 at a quarter of a tick,
`movement_constants.md`, "Jump now happens at the instant it was
pressed").

## 6. Smaller things

- `sv_step_move_vel_min` 64, "Min velocity for step move" (CV 10749,
  cheat). Inferred: below 64 u/s the move does not try the stepped path.
  Ours tries it at any speed that meets something. Crouched and walking
  speeds are above 64, so this touches only a player barely moving.
- `sv_min_jump_landing_sound` 260 (CV 10326): a landing slower than 260
  u/s downward makes no landing sound (inferred from the name). For the
  footsteps research, which has the sound thresholds.
- Counter-strafe automation: "hardware-assisted counter strafing will now
  be detected on Valve official servers, resulting in a kick from the
  match" (VN 19 August 2024); options for other servers followed (VN 9
  September 2024), as `sv_auto_cstrafe_*` (CV 9726-9747), which count
  overlapping and underlapping A and D ticks (SS 33149-33157).
  `CCSUsrMsg_CounterStrafe` carries `press_to_release_ns` and
  `total_keys_down` (UM15 602-605). Nothing for a single-player build to
  copy.
- `sv_optimizedmovement` true (CV 10395): the one ground check a tick our
  port already copies (`_ground_known`).
- `m_vecWalkWishVel` (SCH :51, since 20 April 2026): a two-dimensional
  wish velocity kept between ticks. What it smooths is unknown.
- Ladders: `sv_ladder_scale_speed` 0.78 (CV 10203); dust2 has none.

## 7. What players criticise and want

Sid, 2026-09-24: "While researching keep track of critiques and
improvements players want to see". Forum pages refuse fetches here, so
most of these are **secondary**; each is dated, CS2-era feedback comes
first, and where Valve answered, its note is given. His standing
direction applies: CS2 is the starting point, not the limit, and anything
that runs per tick per player is weighed by what it costs a server.

| Critique or wish | When and source | Valve's answer | What it could mean for ours |
|---|---|---|---|
| Perfect bunny hops depended on luck: every sub-tick step re-ran the ground check, so badly timed frames made a perfect hop impossible | ZK readme ("The perf window"), before November 2025; **secondary** | The 3.9 ms window around a sub-tick landing (VN 21 January 2026) | Copy the window (correction 4). It is a comparison of two times, no traces |
| Scroll wheels, free-spinning ones most, buy extra sub-tick steps: faster slides up ramps and guaranteed ledge grabs ("pay2win") | ZK readme, before November 2025; **secondary** | Surf and ramp fixes (VN 30 July, 24 September and 4 November 2025); ZK says 5 November 2025 reduced it | Any sub-tick movement we add must give nothing for more steps: step velocity with friction stashed per tick, and cap steps per command (correction 6) |
| Air strafing is weaker than on CS:GO's 128-tick servers; flat jumps up to 9 units shorter | ZK readme, before November 2025; **secondary** | None; the tick stays 64 | Measurable improvement, Sid's call: step only the air acceleration twice a tick. It traces nothing, so it costs the server a few multiplications a player (`movement_constants.md`, "What the tick rate does") |
| 64 Hz with sub-tick is still not as good as 128 Hz; pros such as SPUNJ asked for 128-tick servers | Dust2.us article (WS; the summary gives no date); **secondary** | Tick stays 64 | Sid chose 64 Hz for server cost (2026-09-23). The movement part that 128 Hz changes most is air strafing, above |
| Movement feels "floaty" and heavy: slower to start, softer stops | Valve noted it "per player-feedback" in VN 6 June 2023; later a csgo-news.com guide (WS, undated); **secondary** | "Sub-tick movement is now more precise and less floaty" (VN 6 June 2023); later sub-tick feedback shown on the next frame (VN 8 November 2023) | Our constants are CS2's, so feel comes from timing: sub-tick keys (5.4) and the landing slowdown (3). The counter-strafe demo compares the two |
| Frame-perfect crouch jumps, jump bugs and W-release are only open to keyboards that automate them, since multi-command binds are blocked | ZK readme, before November 2025; **secondary** | Multi-input binds blocked and hardware counter-strafing detected (VN 19 August 2024) | Option for Sid: a built-in crouch-jump command gives everyone the same reach. Costs nothing per tick |
| Snap Tap (SOCD) keyboards: some players wanted them allowed | August 2024, PC Gamer and others (WS); **secondary** | Detected and kicked on Valve servers (VN 19 August 2024) | Nothing for single player; bots counter-strafe by their own commands |
| The crouch penalty is so strict it gets in the way of crouch jumps and AWP peeks | Steam thread "Crouching in CS2 is too cumbersome", 2023 (WS); **secondary**, and older than the April 2026 crouch changes | Slow crouch fixed (VN 29 June 2023); nothing since on the penalty | When we add the penalty, keep its numbers as named convars, measure CS2's, and weigh a gentler one as an option |
| Walking up ramps became slow after the 17 September 2025 update; NiKo and ropz among the critics | September 2025, esportsinsider (WS); **secondary** | "Fixed a case where velocity was abnormally low while walking up ramps" (VN 24 September 2025) | A ramp-walk speed check belongs with any sub-tick stepping we add |
| Jump height drifted, so 66-unit boxes (Ancient's A site) were unreliable | ZK readme, before November 2025; **secondary** | Height consistent to 1/64 unit anywhere on the map (VN 28 October 2024) | Ours is deterministic per tick; settle the 57.0 question first (2.3) |
| The dead-strafe zone is never explained to players | ZK readme; **secondary** | None | Ours keeps it (`source_deadstrafe`); showing it on the range is an option |
| The 2026 jump ended some bunny hop tricks, such as the "van jump" | 2026, pirateswap.com (WS); **secondary** | None | Follows from copying the modern jump |

## Corrections for other docs and code

Listed here, not made, so the four research threads do not collide.

1. `reference/movement_constants.md:19`: the row named `sv_maxspeed` is the
   knife's `m_flMaxSpeed` (250). CS2's `sv_maxspeed` is 320 (CV 10305) and
   never binds. The status column can mark every convar in section 1 as
   "read from CS2's convars, build 2000915" rather than "No".
2. `reference/movement_constants.md:14`: `sv_accelerate` is 5.5 in CS2
   (CV 9681); the "5.5 or 5.6" note can go, and so can the same doubt in
   `movement_config.gd:13-14`.
3. `reference/movement_constants.md`, "Jump height is tick-rate dependent
   in Source", and `movement_config.gd:53-63`: the **older** Source SDK
   2013 calls `FinishGravity()` inside `CheckJumpButton` (SDK 2496), which
   our port leaves out; the SDK's jump peaks at 57.0 at any tick rate, the
   height CS2's convar description gives. Measure before flipping
   `tick_rate_independent_jump`.
4. `src/movement/player_body.gd`, with its inputs from `player_sim.gd`
   (off limits while the local agent wires it): CS2's modern jump, a
   sub-tick landing instant, a 1/128 s bunny hop window around it, a 1/64 s
   spam penalty, and a landing slowdown set by the landing's time and
   vertical speed. `sv_legacy_jump` is how CS2 names the old behaviour;
   ours could keep its current jump behind the same name.
5. `player_body.gd:215-231`: ducking in the air eases rather than snaps
   (VN April 2026), and a second duck within 0.4 s is ignored
   (`sv_timebetweenducks`).
6. `src/player/player_input.gd:47-55`, `src/sim/user_cmd.gd` and
   `player_sim.gd:575-595` (off limits now; the local agent's): movement
   keys and duck as sub-tick steps, and the wish direction from the step's
   own yaw. The cheap way to do it, as an option: step velocity (friction
   and acceleration, which trace nothing) at each sub-tick instant, with
   friction's control speed stashed once a tick as CS2 does, and move the
   hull once a tick, so the server pays no extra trace for any number of
   steps and more steps buy no speed. Splitting the move itself, as CS2
   does, adds about four traces a walking player per step
   (`PlayerBody.traces`). Either way, cap the steps a command may carry.
7. `reference/roadmap.md:518-523` ("Movement: what is still open"): add
   the modern jump, the landing slowdown, the duck spam penalty and
   sub-tick movement keys, and the Local measurements below.
8. `reference/research/combat.md:546` says nothing took jumps or movement
   off sub-tick; still true, and the 2026 jump made the landing sub-tick
   too. Its "Changes since launch" list dates from search summaries; VN
   now has Valve's own text for each.

## What only a Local measurement on Sid's machine can settle

One demo does most of it, on today's build. On a local 64-tick server with
`sv_cheats 1`, `record movement`, then read it with demoparser2: per tick
`velocity` (and `velocity_X/Y/Z`), `duck_amount`, `duck_speed`, and
`CCSPlayerPawn.CCSPlayer_MovementServices.m_flStamina` (DP 193-196,
542-543, 629, 1053-1054). Those were networked as of 25 January 2026
(SCHH); whether the April 2026 schema still sends each is unknown until the
demo is read. Keep `cl_showpos 2` on screen for the jump readout (CS
35160).

| Unknown | How |
|---|---|
| Standing jump height: 57.0 or 59.4 | The jump gauges on flat ground; `cl_showpos 2`'s jump line |
| Crouch jump height, and how fast the air duck is | The gauges with a crouch jump; `duck_amount` each tick through the jump |
| The landing slowdown: how much, for how long, and how it grows with the fall | Demo: jump in place on flat ground and walk off 64, 128 and 256 unit drops, holding a direction; `velocity` and `m_flStamina` each tick for a second after landing |
| The bunny hop window and spam penalty in practice | Demo: hop with the space bar and with the scroll wheel; speed kept per hop |
| Duck time on the ground; the spam penalty's size and recovery | Demo: one duck, then ten quick ducks; `duck_amount` and `duck_speed` each tick |
| Counter-strafe to a third of the AK's speed | Demo: full run, tap the opposite key; the ticks from the press to under 72 u/s |
| Air strafe gain at 64 Hz | A strafe jump on flat ground with `cl_showpos 1`, speed before and after, against our HUD's jump gain |
| Acceleration with Shift or ducked | Demo: run from rest walking and crouched; `velocity` each tick against 5.5 x speed / 64 |
| The dead-strafe zone | Already on the roadmap; the same strafe jump shows it |

## Open questions no CS2 file or note answers

- The landing slowdown's formula, and whether stamina still scales the
  jump impulse.
- CS2's duck speed, its spam penalty's numbers, and crouched and walking
  speeds (ours are CS:GO's).
- Whether air acceleration's 30 u/s cap is shared across a tick's steps
  or scaled by each step's share of the tick (inferred one or the other,
  not per step).
- Whether CS2 caps the sub-tick steps a command carries. One **secondary**
  summary said a cap came on 28 July 2025; Valve's notes for that day say
  nothing of it.
