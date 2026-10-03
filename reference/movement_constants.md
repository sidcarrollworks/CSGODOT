# Movement constants

Every number in `src/movement/movement_config.gd`, where it came from, and
whether it has actually been checked against CS2.

Most motion values still lack controlled in-game measurements. Published
defaults and binary-derived values are evidence for parameters, not proof
that our movement integration matches CS2. The
[October 3 Ghidra audit](research/movement-ghidra-2026-10-03.md) records
confirmed algorithm differences. Paired CS2 console coordinates measure
an effective eye height of **60.75** at the mid-door setup and **63.9375**
at the B-doors setup; the base 64/46 eye values remain unchanged.

## Status

| Constant | Value | Source | Measured? |
|---|---|---|---|
| `sv_accelerate` | 5.5 | [totalcsgo](https://totalcsgo.com/commands/svaccelerate) | No. The page shows both 5.5 and 5.6, so this one genuinely needs checking. |
| `sv_airaccelerate` | 12 | [totalcsgo](https://totalcsgo.com/commands/svairaccelerate), corroborated by the deadstrafe writeup | No |
| `sv_friction` | 5.2 | Source/CS:GO default | No |
| `sv_stopspeed` | 80 | Source/CS:GO default | No |
| `sv_air_max_wishspeed` | 30 | [deadstrafe writeup](https://gist.github.com/zer0k-z/808bc8bfc494e0bbb5a423c2b1ca6685) | No |
| `sv_maxspeed` | 250 | Same; base speed with a knife | No |
| `duck_time` | 0.4 s | Source's TIME_TO_DUCK. CS:GO ducks faster than this. | No, and it is probably wrong |
| `sv_gravity` | 800 | Source/CS:GO default | No |
| `sv_jump_impulse` | 301.993 | Source/CS:GO default | No |
| walk modifier | 0.52 | CS:GO | No |
| duck modifier | 0.34 | Crouched speed is 34% of the held item's speed. Current server `180ab00d0` also scales ordinary land crouch acceleration by 0.34 after a 250-unit wish-speed floor; constants `1818ca884` and `1818ca8ac`. The port now uses that independent acceleration scale, including duck transitions. The speed target still uses the existing duck interpolation. See the October 3 audit below. | Binary verified; complete movement timing still requires CS2 captures |
| hull 32 x 32 x 72 | | Source player hull | No |
| duck height 54 | | CS:GO | No |
| step height 18 | | Source | No |
| max ground angle 45.57° | | Source uses a 0.7 normal threshold; acos(0.7) = 45.573° | Derived, exact |
| `NON_JUMP_VELOCITY` | 140 | `gamemovement.cpp:3830` | Read from the SDK, exact |
| `sv_maxvelocity` | 3500 | `movevars_shared.cpp:93` | Read from the SDK, exact |

## Crouch turning (Sid's PR #164 feedback, 2026-10-01)

The earlier standing-speed acceleration held a straight crouch at 0.34 of the
weapon's speed, but turning kept adding sideways velocity beyond that top.
The actual-body check reproduced an AK-47 rising from 73.1 to 79.0 u/s;
its movement cone widened from the crouched 0.310 to 4.878 degrees. A pure
solver run turning 5 degrees every tick reached 100.6 u/s.

For crouched commands, and when acceleration uses a speed above the target,
`PlayerBody._walk_move` limits the resulting horizontal speed to the
greater of the top and the speed left after friction. This lets residual
running speed decay gradually while preventing a turn from adding more.
The native step has the same arithmetic. Ordinary ground acceleration and
air acceleration keep their existing behavior; no traces are added.
This correction follows Sid's playtest feedback, rather than a verified
CS2 implementation: [Source SDK 2013's WalkMove](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/shared/gamemovement.cpp#L1758)
caps the wish-direction projection and has no total-speed clamp.

`Weapon.MOVING_SPEED_EPSILON` is 0.0001 u/s at the 34% movement-accuracy
threshold. Float32 velocity can round a few millionths above that threshold,
which the fourth-root penalty makes visible. The tolerance ignores only
that rounding; actual running, jumping and residual excess speed still
affect accuracy. `tests/run_sim_checks.gd` covers AK-47 and AWP turns with
and without Walk, turning on the spot, and real run/jump penalties alongside
the existing crouch transition checks.

## Crouch acceleration (Sid's slope playtest, 2026-10-03)

The previous correction kept the crouched speed limit, but acceleration
still used the uncrouched weapon speed. Current CS2's ordinary land branch
uses `max(250, wish_speed) * 0.34`, or 85 for ordinary crouched speeds.
That floor exceeds the AK's 73.1-unit target, so it overcomes stop friction
without the knife's old 250-unit acceleration burst.

`PlayerSim._ground_acceleration_speed` now supplies the crouched scale.
`MovementSolver.accelerate` and native `HullMover::accelerate` treat a
positive supplied scale independently of the speed target. This matters
during duck entry, when the target has not yet reached crouched speed.
The existing total-speed/accuracy guard remains active during crouching.

At 64 Hz with accelerate 5.5, the knife's first fully crouched step changes
from **21.484375** to **7.3046875 u/s**; after four steps it is **9.71875**
instead of **66.4375**. Holding movement still reaches 85 with the knife,
73.1 with the AK and 68 with the unscoped AWP. Crouching with Walk uses the
same acceleration as crouching without it.

The new real-command fixture passes **138 checks** on flat and +/-5/20-degree
Box3D floors, with **6,636 native/script steps** matching bit for bit.
The simulation, movement course, native movement and three grenade-lineup
suites also pass. No collision queries were added. Duck-rate/hull/view
transitions and deferred movement integration remain separate audit gaps.

## How to measure each kind

**Speeds.** Load the test course, run in a straight line, read the speedometer.
Compare against CS2 with `cl_showpos 1`.

**Acceleration.** Start from rest and count ticks to reach top speed. At 64 Hz
with `sv_accelerate 5.5` the first tick should add exactly 21.484375 u/s
(`5.5 × 250 / 64`). The test suite pins this value (worked out from the tick,
so it holds at any tick rate), so if you change `sv_accelerate` the test will
tell you the new expected figure.

**Jump height.** Walk into the jump gauges. You should clear 56 and not 64.

**Air acceleration.** Strafe jump down the marked lane and read `jump gain` on
the HUD. Do the same in CS2 on a flat surface and compare the gain per jump.
This is the fiddliest one and the most important, because air acceleration is
most of what makes CS movement feel like CS.

### Crouch jump height

Ducking in the air shrinks the hull and moves the body up by the difference, so
your head stays put and your feet come up 18 units. That is what a crouch jump
is, and it is the only way to reach a ledge a standing jump cannot.

Measured in our build at 64 Hz: a standing jump peaks at 59.37 units and a
crouch jump at 77.37, the difference being exactly the 18 unit hull delta
(58.19 and 76.19 at 128 Hz, the tick until 2026-09-23).

**76 may well be too generous.** The feet-raise is faithful to Source's
`FinishDuck`, but CS:GO and CS2 also gate how fast you can duck in the air, and
`duck_time` here is Source's 0.4 s rather than a measured CS2 value. Both of
those cap the real thing lower than the theoretical maximum. Measure the
highest ledge a crouch jump actually clears in CS2 before trusting this number.

## Known issue: leaving a surf ramp

Reported 2026-09-21: sliding down a surf ramp builds speed correctly, but
arcing up and launching off the end loses speed far faster than CS does.

**Partly investigated, not solved.** The leading suspect was the 0.03 unit
push-out along every collision normal, which Source does not do and s&box
explicitly left commented out. It was measured and it is real but small:
sliding the full ramp peaks at 392.03 u/s with it removed against 389.09 u/s
with it in, which is 0.75%. It is now removed (`MovementConfig.trace_epsilon`,
default 0), so that suspect is closed without accounting for the complaint.

**The test course cannot reproduce the reported case.** The surf lane's channel
runs down into the floor, so the scripted test slides to a stop at the bottom
rather than launching off a ramp end. Reproducing "arcing up and launching off
the end" needs a ramp that terminates in open air, and that geometry does not
exist yet. Building it is the first step, not more reading of the solver.

Remaining candidates, in order of suspicion:

1. The dead-strafe friction below, which cuts air acceleration to a quarter
   while vertical velocity is between 0 and +140. Leaving a ramp upward puts
   you squarely in that window. It is faithful to Source, so if this is the
   cause then CS2 does something else on top rather than us having a bug.
2. `clip_velocity` running against the ramp plane for a tick after you have
   actually left it.
3. `_categorize_position` snapping to ground on the lip. Note the quadrant
   retry added on 2026-09-21 makes grounding *more* likely near an edge, which
   could make this worse rather than better.

## Two decisions that are not settled

### The dead-strafe zone

`MovementConfig.source_deadstrafe`, default **on**. Renamed from
`cs2_deadstrafe` on 2026-09-21, because the old name was wrong in a way that
invited someone to "fix" it.

Surface friction drops to 0.25 when vertical velocity is between 0 and +140,
and the air acceleration function multiplies by that friction even though the
player is airborne. The effect is that air strafing is roughly a third as
effective for about the first quarter of a jump. GoldSrc keeps friction at 1.0
in the air and has no such dead zone.

**This is not a CS2 quirk.** It is Source 1 behaviour and it is in the public
SDK: `CategorizePosition` resets `m_surfaceFriction` to 1.0 and assigns 0.25
when the ground trace finds nothing walkable while moving up
(`gamemovement.cpp:3871-3877`). The upper bound is real too, because above
`NON_JUMP_VELOCITY` (140, `gamemovement.cpp:3830`) Source skips the ground
trace entirely, so the 0.25 never gets assigned.

Community writeup, which is where the wrong name came from:
<https://gist.github.com/zer0k-z/808bc8bfc494e0bbb5a423c2b1ca6685>

We keep it on by default because the goal is CS2, not a better CS2. Anyone who
plays a lot of CS will feel the difference either way, so this should be an
explicit choice rather than an accident.

### Jump height is tick-rate dependent in Source

**October 3 default:** `MovementConfig.cs2_jump` is now **on** for playtest,
using the [Ghidra-audited ordinary jump](research/grenade-subtick-snapshot-2026-10-03.md).
At gravity 800 its fixed adjustment subtracts 3.125 u/s from the 301.993
impulse, and interval gravity then integrates independently of jump phase.
The following Source-height comparison describes the legacy mode selected
with `cs2_jump = false`; it remains available to the course's comparison tests.

`MovementConfig.tick_rate_independent_jump`, default **off**, applies to that legacy mode.

Source splits gravity into two halves around the move, which normally makes
jump height independent of tick rate. But the jump impulse is applied *after*
the leading half-step, so the first tick of a jump travels at the full impulse
and the jump ends up higher than the physics alone would give:

| | Peak height |
|---|---|
| Textbook (`v²/2g`) | 57.00 units |
| Source ordering at 128 Hz | 58.18 units |
| Source ordering at 64 Hz | 59.36 units |

**This project now simulates at 64 Hz, as CS2 moves** (2026-09-23; it was 128,
which left its jumps about 1.2 units short of CS2's). Faithful to Source, a
jump peaks at 59.36, which is CS2's if CS2 kept Source's order of gravity and
impulse; a real CS2 jump against the jump gauges will say. If it did not,
`tick_rate_independent_jump` and `sv_jump_impulse` can be set to the measured
height at any tick rate. The test suite pins both behaviours so the choice
cannot drift by accident.

## What the tick rate does to the movement (2026-09-23)

The movement is Source's, a step each tick, so the tick rate shows in it. The
project moved from 128 ticks a second to CS2's 64 for what a server costs
(`reference/performance.md`). Worked out from MovementSolver at CS2's numbers:

| | 64 Hz | 128 Hz |
|---|---|---|
| An AK from a standstill to 99% of its 215 u/s | 531 ms | 539 ms |
| Letting go at full speed, the distance to a stop | 30.9 units | 32.3 units |
| A counter-strafe to the AK's standing cone | 78 ms | 78 ms |
| A perfectly strafed jump from 250 u/s | +77 u/s | +127 u/s |
| A perfectly strafed jump from 400 u/s | +52 u/s | +91 u/s |
| A standing jump's peak | 59.4 units | 58.2 units |

Most of it hardly moves. Air strafing does: a tick's air acceleration is
capped at 30 u/s along the wish direction however long the tick is, so twice
the ticks is nearly twice the gain a jump. That is why strafe jumps and bunny
hops came easier on CS:GO's 128-tick servers than in its matchmaking. What
CS2's own gain is (its sub-tick steps may split the air acceleration) is for
the HUD's jump gain readout against CS2's to say. If more is wanted than
CS2 gives, the air acceleration alone could be stepped twice a tick: a sum
with no traces in it, so it would cost the server nothing worth counting.

## What the Source 2 audit changed (2026-09-21)

A separate thread read our port line by line against Source SDK 2013,
`s&box` (MIT, and a shipping Source 2 game), and the CS2 protobufs, and found
eight specific gaps. The write-up is `source2-to-godot.md` in the project
files. All eight are now closed. What each one actually did, measured:

**`StayOnGround` was missing.** After every walk move Source traces up 2 and
down a full step height (18) and glues the player to whatever walkable surface
it finds. We only snapped 2 units, which is nine times too short to catch a
stair. Running the eight-step flight in the test course:

| | Ticks airborne | Peak speed |
|---|---|---|
| Glued (Source) | 0 of 90 | 215.0 u/s |
| Not glued (old) | 42 of 90 | 194.5 u/s |

Airborne means no ground friction and no ground acceleration, which is why the
old behaviour never reached run speed. This is the biggest single feel change
in the port and it will show everywhere on dust2. `MovementConfig.stay_on_ground`
turns it off, which exists only so the difference stays measurable.

**The 0.03 trace push-out is gone.** See the surf section above for the
measurement: real, 0.75%, and not the explanation for the parked complaint.

**Jump now happens at the instant it was pressed.** CS2 carries every button
transition with a fractional timestamp (`CSubtickMoveStep`). Ours quantised
jump to the tick, which is the input being used to test bunny hopping. A tick
with a mid-tick press is now split in two and both halves are simulated.
Hopping from 230 u/s:

| Press fraction | Speed kept |
|---|---|
| Rounded to the tick boundary | 230.00 u/s |
| 0.25 | 227.66 u/s |
| 0.50 | 225.33 u/s |
| 0.75 | 222.99 u/s |

The boundary case is not better, it is wrong: taking the jump before friction
is applied hands you a tick of speed you did not earn. `subtick_jump` off
reproduces it exactly.

**The shot origin is now a sub-tick sample.** It was the end-of-tick position
with sub-tick angles attached. At 250 u/s that put the muzzle up to 1.6 units
from where the click happened, which is the strafe-and-tap case hit
registration arguments are made of.

**The small ones.** Ground detection threshold is `NON_JUMP_VELOCITY` (140)
rather than half the jump impulse (151). `CheckVelocity` clamps each axis to
`sv_maxvelocity` (3500) twice a tick, per axis rather than by magnitude, which
changes the direction of an over-speed vector and so the angle you leave a ramp
at. `StepMove` keeps the flat move's vertical velocity when the stepped path
wins, as Source does. The ducked eye offset runs through `SimpleSpline` rather
than a straight lerp. The quadrant ground retry
(`TryTouchGroundInQuadrants`) keeps you standing when the hull centre is past
an edge but a corner is still over something.

**One deliberate divergence, now a flag.** `project_wish_dir_on_ground`,
default **off**. Source flattens the move direction and never consults the
ground normal; projecting onto the slope bleeds less speed uphill, which is
arguably better and is definitely not CS2. It was silent before, which is worse
than either choice.

Still open from that audit, on the map side: per-surface-property
collision. The other three it listed are in: the entity spawn points
(`SourceEntities`), the nav mesh (`SourceNavMesh`), and the real friction
table in `surfaceproperties.vsurf` (`SurfaceProperties.player_friction`,
the surface's friction times 1.25 at most 1, as Source's
`CategorizeGroundSurface` makes it), which is read but not yet fed to
`MovementSolver`; on dust2 only glass and pottery are below 1.

## What WalkMove skips (2026-09-23)

The port traced the hull 9 to 11 times a tick for someone walking and 9 for
someone standing still. At 20 to 50 us a trace on dust2's hull, ten players'
movement took more than half of every 128 Hz tick. Source's `WalkMove` traces
less, and the port now does what it does:

- Slower than a unit a second, `WalkMove` stops the player dead and returns
  (`spd < 1.0f`): no move and no `StayOnGround`. Friction takes anything under
  3.25 u/s to nothing on the next tick anyway, so the difference is one
  tick's drift of under a hundredth of a unit.
- It traces the flat move to the destination first and, if that meets
  nothing, takes it and runs `StayOnGround`; `StepMove` only runs against
  something in the way. A stepped move can go no further than one that met
  nothing, so the result is the same, for two to five traces fewer.
- The snap onto the floor after the ground check (HL1's, kept) moves by the
  check's own trace rather than tracing the same move again.
- A move no longer looks for the ground at its start when the last move's
  check looked from where the body still is, with the same hull, and it is
  not rising too fast to stand on anything: that check found what this one
  would. Source leaves it out the same way (PlayerMove, sv_optimizedmovement,
  on by default). The world does not move; a player walking out from under
  another is noticed a tick later, as in Source.

Running in the open is now 4 traces a tick, and standing 1. PlayerBody
counts them (`traces`), and run_tests.gd holds a tick to those numbers.

## The traces on Jolt (2026-09-23)

The hull's traces are Jolt's since the project moved to it. Two differences
from Godot Physics reach the movement; every movement check passes on both.

- Jolt's motion queries do not catch on the edges between the hull's
  triangles: meeting one, a trace gets the face's normal rather than the
  edge's (enhanced internal edge removal, on by default for motion queries),
  so a box sliding over a floor or a ramp cut into triangles has nothing to
  snag on. Godot Physics has nothing like it. It works between the shapes of
  one body and not across bodies, and all 38 parts of dust2's hull are one
  body: keep them so.
- Jolt rounds a box's corners by its shape's margin, 0.04 by default, which
  on the 32-unit hull is 0.04 of an inch: still Source's box, to about a
  thousandth of its width.
