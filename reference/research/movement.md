# How CS2 moves: research

Sid, 2026-09-24: "Looking at the roadmap is there anything else we should
research?", then "have a couple agents research those as well". This page
covers movement, his top priority: CS2's 2026 jump, stamina and the landing
slowdown, crouching, and sub-tick movement, each checked against the port
in `src/movement/` and `src/player/`. Accuracy while moving and landing is
researched separately; this page only gives the movement timings it rests
on. It changes no code.

`reference/research/combat.md` already covers the user command's fields,
netcode and the guns; this page builds on its section 4.

## Sources

Read on 2026-09-24. The key:

| Key | Source |
|---|---|
| CV | GameTracking-CS2 `DumpSource2/convars.txt` @d45f52d (2026-09-23), by line |
| CVH | The 52 dumps of that file from 2025-01-07 to 2026-09-23 in GameTracking-CS2's history |
| SCH | GameTracking-CS2 `DumpSource2/schemas/server/<Class>.h` @d45f52d, by line; SCHH is the same files' history (network annotations were dumped until 2026-04-20) |
| SS, CS | GameTracking-CS2 `game/csgo/bin/win64/server_strings.txt` and `client_strings.txt` @d45f52d (names and format strings only) |
| UC, UM15 | GameTracking-CS2 `Protobufs/usercmd.proto` and `cstrike15_usermessages.proto` |
| GI, CFG | GameTracking-CS2 `game/csgo/gameinfo.gi` and `game/csgo/cfg/gamemode_*.cfg`: neither overrides a movement convar |
| SDK | Source SDK 2013 `src/game/shared/gamemovement.cpp` @b8cfb12, read as a spec only |
| ZK | zer0k-z, `cs2-movement-issues` @26f1716: `readme.md` (measured with demos; its author marks it out of date since November 2025) and `bhopping branch.md` (2025-07-31, reverse-engineered notes on the jump check) |
| DP | demoparser2 (LaihoE/demoparser, MIT) @9ddb373, `src/parser/src/maps.rs`: the property names it reads from a CS2 demo |
| WS | A web search's summary of a named page. Steam, counter-strike.net, HLTV, Dust2.us, fandom, VDC, Liquipedia and teamfortress.tv all refused fetches from this session, so Valve's notes are quoted from search summaries. Re-read them before quoting them as Valve's words |
| MOD | Worked out here with `MovementSolver`'s equations at CS2's numbers (a Python copy of `apply_friction` and `accelerate`, 64 Hz) |

Labels: **inferred** means reasoned from names, fields or data, not stated
by Valve. **From memory** means not checked against a source reachable
here. Nothing on this page comes from Valve's leaked CS:GO source; ZK's
notes are a third party's reading of the shipped game, used as a
description only.

## In short

- **Our constants are CS2's.** Every movement convar CS2 ships agrees with
  `MovementConfig` (section 1), `sv_accelerate` 5.5 included. `sv_maxspeed`
  is 320 in CS2 but is only a ceiling that no item reaches; the 250 in our
  table is the knife's own speed, and the row is misnamed rather than wrong.
- **CS2 replaced its jump on 21 January 2026.** The landing is now timed to
  the sub-tick; a jump pressed within 3.9 ms either side of it (a 1/128 s
  window) is a perfect bunny hop; jumping and landing no longer cost stamina; instead a
  landing slows you by an amount set by when you landed and how fast you
  were falling (section 2). Ours has none of the three.
- **Our jump height may be 2.4 units high.** Source SDK 2013's jump takes
  half a tick of gravity off the impulse at once (`FinishGravity()` inside
  `CheckJumpButton`), which our port leaves out; with it a jump peaks at
  57.0 at any tick rate, as CS2's own convar description asks, and ours
  peaks at 59.4 (section 2.3). A jump against the gauges settles it.
- **CS2 does not duck instantly in the air** (fixed April 2026), and it
  slows ducking down when you spam it. Ours snaps in the air, so our crouch
  jump reaches 77 units where the community quotes about 66 (section 4).
- **CS2 splits a tick at every key and view change, and our movement keys
  are not sub-tick at all.** A counter-strafe here starts up to a tick
  before the key went down: 70 ms from the press to a third of the AK's
  speed on average here, against 80 ms when the tick splits at the press
  (section 5.4).

## 1. The constants

CS2's values (CV), all `replicated`, none overridden by GI or any
`gamemode_*.cfg`:

| Convar | CS2 | Ours (`movement_config.gd`) | Agrees |
|---|---|---|---|
| `sv_accelerate` | 5.5 (CV 9681) | `accelerate` 5.5 | Yes: retires the "5.5 or 5.6" question |
| `sv_airaccelerate` | 12 (CV 9696) | `air_accelerate` 12 | Yes |
| `sv_air_max_wishspeed` | 30 (CV 9693) | `air_max_wishspeed` 30 | Yes |
| `sv_friction` | 5.2 (CV 10074) | `friction` 5.2 | Yes |
| `sv_stopspeed` | 80 (CV 10755) | `stop_speed` 80 | Yes |
| `sv_gravity` | 800 (CV 10092) | `gravity` 800 | Yes |
| `sv_jump_impulse` | 301.993, "sqrt(2\*gravity\*height)" (CV 10179) | `jump_impulse` 301.993 | Yes; 301.993²/1600 = 57.0 units |
| `sv_maxvelocity` | 3500 (CV 10317) | `max_velocity` 3500 | Yes |
| `sv_stepsize` | 18 (CV 10752) | `step_height` 18 | Yes |
| `sv_standable_normal`, `sv_walkable_normal` | 0.7 (CV 10728, 10974) | `max_ground_angle_deg` 45.57 (acos 0.7) | Yes |
| `sv_maxspeed` | 320 (CV 10305) | none | See below |
| `sv_enablebunnyhopping` | false, "Allow jump speed to exceed 1.1x max speed" (CV 9993) | `enable_bunnyhopping` false, cap 1.1 | Yes |
| `sv_autobunnyhopping` | false (CV 9753) | `auto_bunnyhop` false | Yes |

**`sv_maxspeed`.** CS2's ceiling on anyone's speed is 320. What a player
runs at comes from what they hold: `m_flMaxSpeed` in the weapons vdata,
250 for the knife and the C4 and 245 at most for everything else
(`reference/weapons/vdata.csv`), and `PlayerSim._draw` already sets it from
there (player_sim.gd:444-448). Nothing in CS2 reaches 320, so the ceiling
never binds on dust2. The mistake is the row in
`reference/movement_constants.md:19`, which calls the knife's 250
`sv_maxspeed`. `CPlayer_MovementServices` keeps the player's own ceiling as
`m_flMaxspeed` (SCH `CPlayer_MovementServices.h:17`).

**`sv_accelerate_use_weapon_speed` true** (CV 9687, no description).
Inferred from its name: ground acceleration is scaled by the held weapon's
speed, as ours is (`accel_speed = accel * dt * wish_speed`,
movement_solver.gd:55). What CS2 does with it off, and whether walking or
ducking change the speed used in that product, is not in any file here; a
run from rest with Shift held settles it (Local).

## 2. The 2026 jump

### 2.1 What changed, and when

- **28 October 2024** (WS for Valve's notes): jump height consistent to
  0.015625 units wherever you are on the map; landing on surfaces near the
  top of a jump made reliable; "Jump height is still affected by stamina;
  when using `cl_showpos 2`, stamina at takeoff is reported". The client
  still carries that readout: `jump: %.3f (%.2f) [%.2f] @ stamina: %.1f,
  impulse mul: %.3f` (CS 35160). `sv_jump_precision_enable` (CV 10182) and
  the fields `m_flHeightAtJumpStart`, `m_flMaxJumpHeightThisJump`,
  `m_flAccumulatedJumpError` (SCH `CCSPlayer_MovementServices.h:38-43`)
  belong to this (inferred).
- **28 July to 1 August 2025**: a "bhopping branch" changed when the jump
  spam clock starts, to the instant of the press rather than the end of
  the sub-tick step it was processed in (ZK `bhopping branch.md`; WS for
  the notes, which one summary dates 2026 but which sit beside July 2025
  articles). `sv_subtick_movement_view_angles` first appears in the dump
  of 2025-07-29 (CVH).
- **21 January 2026** (WS: Valve's notes via fandom, Dust2.us and
  sportsdunia summaries): "Landing time is now calculated with subtick
  precision"; "Jumping and landing no longer affect stamina"; "The landing
  speed penalty is now a simple function of landing time"; "Any jump press
  within `sv_bhop_time_window` centered on the landing time that hasn't
  been penalized by `sv_jump_spam_penalty_time` will be treated as a
  successful bunnyhop"; "Legacy jump behavior can be restored on private
  servers with `sv_legacy_jump`". The dump of 2026-01-25 is the first with
  `sv_legacy_jump` and `sv_bhop_time_window`; it re-describes the stamina
  costs as legacy-only and `sv_enablebunnyhopping` as the 1.1x cap (CVH,
  diff of 10a53ce against 69f39e8). The same day the schema gained
  `CCSPlayerLegacyJump` and `CCSPlayerModernJump` (SCHH).
- **22 January 2026** (WS): "Landing vertical velocity now affects landing
  speed penalties similar to `sv_legacy_jump` stamina."
- **21 April 2026** (WS, the AnimGraph 2 notes): "Fixed several cases where
  crouch transitions in the air were instantaneous"; player height on
  slopes made consistent.
- No convar in CVH changed value between 2026-01-25 and 2026-09-23.

### 2.2 How the new jump decides

The convars (CV):

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

The modern jump's state (SCH `CCSPlayerModernJump.h`, networked as of
2026-01-25): the last actual press and the last usable press (not
cancelled by the spam penalty), each as a tick and a fraction; and the
last landing, as a tick, a fraction and the full landing velocity (x, y
and z). The fractions travel in 6 bits (SCHH), so 1/64 of a tick, 0.24 ms.

Inferred from those fields and the notes, the rule reads:

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

What ZK measured before the change still explains why a window was
needed: every sub-tick step runs the ground check again, so a press a
moment after landing lost speed to friction, and a player whose frames
fell badly could not hop perfectly at all (ZK readme, "The perf window").

### 2.3 How high a jump goes

Ours rises 59.37 units at 64 Hz (`reference/movement_constants.md`,
"Jump height is tick-rate dependent in Source"). That page says this is
Source's order. The SDK says otherwise:

- `CheckJumpButton` sets the jump velocity and then calls `FinishGravity()`
  itself, before the move (SDK gamemovement.cpp:2496), which takes half a
  tick of gravity off at once. `FullWalkMove` then runs its own
  `FinishGravity()` after the move as usual (SDK 2023-2125).
- The SDK has two branches. Ducked, it sets the vertical velocity to the
  impulse; otherwise it adds the impulse to what is there (HL2's code,
  SDK 2450-2462).

Worked out for each (MOD, standing on flat ground):

| | 64 Hz | 128 Hz |
|---|---|---|
| Ours (impulse, no `FinishGravity` in the jump) | 59.37 | 58.19 |
| SDK, velocity set to the impulse, then `FinishGravity` | 57.00 | 57.00 |
| SDK, impulse added after `StartGravity`, then `FinishGravity` | 54.65 | 55.83 |
| `sqrt(2*gravity*height)` as CS2's convar describes it | 57.00 | 57.00 |

The middle row is exactly what `MovementConfig.tick_rate_independent_jump`
does, so the fix, if it is one, is a flag already there. CS2's own
code is not public; its convar's description, the 2024 notes' promise of
a consistent height, and the fields that track the height reached all
point at 57.0 rather than 59.4 (inferred). Stamina scaled the impulse
before 2026 (`impulse mul`, CS 35160); whether anything still does is
unknown. The jump gauges settle it: clear 57 and not 58 (Local).

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

What CS2 keeps (CV): `sv_staminamax` 80, "Maximum stamina penalty"
(10722); `sv_staminarecoveryrate` 60, "Rate at which stamina recovers
(units/sec)" (10725). Only the jump and landing costs are marked
"sv_legacy_jump only": `sv_staminajumpcost` 0.08 and `sv_staminalandcost`
0.05 (10716-10720). `m_flStamina`, `m_flStaminaAtJumpStart` and
`m_flVelMulAtJumpStart` are still in the pawn's movement state (SCH
`CCSPlayer_MovementServices.h:37-42`); `m_flStamina` was networked as of
2026-01-25 (SCHH).

What that means, inferred: stamina is now the landing slowdown's own
meter, capped at 80 and recovering at 60 a second, and filled at a landing
by an amount set by the landing's vertical speed (the 22 January note)
rather than by fixed costs. Before 2026 a jump cost 0.08 and a landing
0.05, both taken as a share of speed (WS: totalcsgo's convar pages), and
stamina also scaled the next jump's impulse (CS 35160).

How stamina turns into speed is not in any file reachable here. From
memory, not checked: CS:GO multiplied ground speed by (100 - stamina) / 100
and set stamina from the costs times the vertical speed. The curve, and
what a standing jump on flat ground costs today, come from one demo (Local,
below).

`src/` has no stamina and no landing slowdown. Nothing in the movement
tests pins one either.

## 4. Crouching

CS2's state (SCH `CCSPlayer_MovementServices.h:8-19`): `m_flDuckAmount`
(0 standing, 1 ducked), `m_flDuckSpeed` (how fast the amount moves),
`m_bDesiresDuck`, `m_bDucking`, `m_bDucked`, `m_flLastDuckTime`,
`m_duckUntilOnGround`, `m_flDuckViewOffset`, `m_flDuckRootOffset` (both
since 2026-04-20, SCHH), and `m_vecLastPositionAtFullCrouchSpeed`.

- **Duck spam.** `sv_timebetweenducks` 0.4, "Minimum time before
  recognizing consecutive duck key" (CV 10815; the same in every dump since
  2025-01-07). A second press within 0.4 s of the last is ignored. On top
  of that `m_flDuckSpeed` falls as you spam and recovers (WS: community
  pages say CS2's penalty is stricter than CS:GO's); the numbers are in no
  file. `m_vecLastPositionAtFullCrouchSpeed` suggests the recovery is tied
  to where you were when the speed was last full (inferred, and unclear).
- **Ducking in the air is not instant.** The April 2026 notes fixed "cases
  where crouch transitions in the air were instantaneous" (WS). Inferred:
  the duck amount eases in the air as on the ground, and the feet come up
  as the hull shrinks. That is why CS2's crouch jump is lower than
  Source's instant one. Community pages give about 66 units for a crouch
  jump (WS, swap.gg and clash.gg summaries; 57 plus about 9), against ours
  at 77.37 (`movement_constants.md`, "Crouch jump height").
- **How long a duck takes** is not in any file. Ours is Source's 0.4 s
  (`duck_time`), which `movement_constants.md:20` already doubts.
- **Crouched speed** comes from the weapon; our 0.34 is CS:GO's
  (`duck_modifier`) and no CS2 file has it. Walking's 0.52 likewise.

What ours does (`_update_duck`, player_body.gd:215-231): the amount rises
at 1 / `duck_time` on the ground and the hull changes at full; in the air
the hull shrinks at once and the body moves up 18 units; no spam penalty,
no time between ducks.

## 5. Sub-tick movement

### 5.1 What the command carries

Each `CSubtickMoveStep` (UC 12-22) carries a button with pressed or
released and `when` (the fraction of the tick), analog changes to forward
and side movement (`analog_forward_delta`, `analog_left_delta`), and the
view change at that instant (`pitch_delta`, `yaw_delta`). Movement keys
are buttons like any other, so pressing D mid-tick is a step with its own
`when`. `sv_quantize_movement_input` true (CV 10518) keeps analog input to
the speeds digital keys give.

Since 28 July 2025 view angles travel with the other steps instead of
every frame, and the number of steps a tick carries is capped (WS; the cap
is in no file here). `cl_allow_multi_input_binds` false (CV 814) ignores
binds that press more than one movement or look command.

### 5.2 How the server runs them

- Movement runs once per step: the profiling scope
  `CPlayer_MovementServices::DoMovement::Subtick` (SS 13036, CS 15001) and
  the names `subtick_start_fraction`, `subtick_end_fraction`,
  `subtick_duration` (SS 33103-33106). ZK: "Every time a key is pressed or
  released, the tick simulation is split into two shorter simulations."
- View changes split it too, while `sv_subtick_movement_view_angles` is
  on: "Whether or not subtick view angles are taken into account during
  movement" (CV 10773). ZK adds that the client also generates extra view
  steps when it predicts the player will be on the ground.
- The game can force splits of its own: `m_arrForceSubtickMoveWhen[4]`
  (SCH `CPlayer_MovementServices.h:18`, `MAX_FUTURE_FORCED_SUBTICKS`, SS
  27477). Inferred: this is how a landing gets its own instant.
- **Splitting is meant not to change the result.** 17 September 2025:
  "Improved timestep-independence of subtick movement acceleration" (WS,
  quoting Valve's notes); 18 September fixed "abnormally low velocity
  while walking up ramps" (WS). `m_flGroundMoveEfficiency` left the schema
  on 2025-09-16 (SCHH).
- **Friction is taken from the speed at the start of the tick.** From
  2025-05 to 2026-04 the pawn carried `m_flOffsetTickCompleteTime` and
  `m_flOffsetTickStashedSpeed`; since 2026-04-20 it carries
  `m_bUseFrictionStashedSpeed`, `m_flUseFrictionStashedSpeedUntilFrac`
  and `m_flFrictionStashedSpeed` (SCH `CCSPlayer_MovementServices.h:34-36`,
  SCHH). Inferred: friction's control speed is stashed once and used for
  every step until a fraction of the tick, so ten steps take the same
  speed off as one.
- Late July 2025 fixed "movement button changes being ignored while
  adjusting view angles at high frame rates" and "air strafing resulting
  in higher than usual velocities" (WS, pcguide's summary): early evidence
  that extra steps could buy extra air speed, which timestep independence
  is there to stop.

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
of 215 (72 u/s, below which our guns stop charging for movement, `weapon_stats.md:100-101`),
read at the end of each tick, over 100 press instants:

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
step a tick; the September 2025 change and the July 2025 fix above say it
does not (inferred). ZK measured CS2's air strafe as matching 64-tick
CS:GO, "every flat ground jump is now up to 9 units shorter" than on
128-tick servers, and noted that a strafe released mid-tick gains less
than a whole tick's worth. So our 64 Hz figures are probably CS2's; the
HUD's jump gain against CS2's `cl_showpos 1` settles it (Local).

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
- `sv_auto_cstrafe_*` (CV 9726-9747) and `CCSUsrMsg_CounterStrafe` with
  `press_to_release_ns` and `total_keys_down` (UM15 602-605): CS2 counts
  overlapping and underlapping A and D ticks to detect automated
  counter-strafes (SS 33149-33157). It kicks nobody by default
  (`sv_auto_cstrafe_kick` false). Nothing for a single-player build to
  copy, but the message shows CS2 measures counter-strafes in nanoseconds
  from press to release.
- `sv_optimizedmovement` true (CV 10395): the one ground check a tick our
  port already copies (`_ground_known`).
- `m_bUsingGroundTopologyOffset` and its smoothing (SCH
  `CCSPlayer_MovementServices.h:4-5`, since April 2026): the "player height
  on slopes" change. Inferred to move what is drawn and the eye, not the
  hull; not worth copying before we see it matter.
- `m_vecWalkWishVel` (SCH :51, since 2026-04-20): a two-dimensional wish
  velocity kept between ticks. What it smooths is unknown.
- Ladders: `sv_ladder_scale_speed` 0.78 (CV 10203); dust2 has none.

## Corrections for other docs and code

Listed here, not made, so the four research threads do not collide.

1. `reference/movement_constants.md:19`: the row named `sv_maxspeed` is the
   knife's `m_flMaxSpeed` (250). CS2's `sv_maxspeed` is 320 (CV 10305) and
   never binds. The status column can mark every convar in section 1 as
   "read from CS2's convars" rather than "No".
2. `reference/movement_constants.md:14`: `sv_accelerate` is 5.5 in CS2
   (CV 9681); the "5.5 or 5.6" note can go, and so can the same doubt in
   `movement_config.gd:13-14`.
3. `reference/movement_constants.md`, "Jump height is tick-rate dependent
   in Source", and `movement_config.gd:53-63`: Source SDK 2013 calls
   `FinishGravity()` inside `CheckJumpButton` (SDK 2496), which our port
   leaves out; the SDK's jump peaks at 57.0 at any tick rate. Measure
   before flipping `tick_rate_independent_jump`.
4. `src/movement/player_body.gd`, with its inputs from `player_sim.gd`
   (off limits while the local agent wires it): CS2's modern jump, a sub-tick landing instant, a
   1/128 s bunny hop window around it, a 1/64 s spam penalty, and a
   landing slowdown set by the landing's vertical speed. `sv_legacy_jump`
   is how CS2 names the old behaviour; ours could keep its current jump
   behind the same name.
5. `player_body.gd:215-231`: ducking in the air eases rather than snaps
   (April 2026), and a second duck within 0.4 s is ignored
   (`sv_timebetweenducks`).
6. `src/player/player_input.gd:47-55`, `src/sim/user_cmd.gd` and
   `player_sim.gd:575-595` (off limits now; the local agent's): movement
   keys and duck as sub-tick steps, and the wish direction from the step's
   own yaw. The cheap way to do it, as an option: step velocity (friction
   and acceleration, which trace nothing) at each sub-tick instant and
   move the hull once a tick, so the server pays no extra trace for any
   number of steps. Splitting the move itself, as CS2 does, adds about four
   traces a walking player per step (`PlayerBody.traces`).
7. `reference/roadmap.md:518-523` ("Movement: what is still open"): add
   the modern jump, the landing slowdown, the duck spam penalty and
   sub-tick movement keys, and the Local measurements below.
8. `reference/research/combat.md:546` says nothing took jumps or movement
   off sub-tick; still true, and the 2026 jump made the landing sub-tick
   too.

## What only a Local measurement on Sid's machine can settle

One demo does most of it. On a local 64-tick server with `sv_cheats 1`,
`record movement`, then read it with demoparser2: per tick `velocity` (and
`velocity_X/Y/Z`), `duck_amount`, `duck_speed`, and
`CCSPlayerPawn.CCSPlayer_MovementServices.m_flStamina` (DP 193-196, 542-543,
629, 1053-1054). Those were networked as of 2026-01-25 (SCHH); whether the
April 2026 schema still sends each is unknown until the demo is read. Keep
`cl_showpos 2` on screen for the jump readout (CS 35160).

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

## Open questions no file here answers

- The landing slowdown's formula, and whether stamina still scales the
  jump impulse.
- CS2's duck speed, its spam penalty's numbers, and crouched and walking
  speeds (ours are CS:GO's).
- The cap on sub-tick steps per tick since July 2025.
- Whether air acceleration's 30 u/s cap is shared across a tick's steps
  or scaled by each step's share of the tick (inferred shared or scaled,
  not per step).
