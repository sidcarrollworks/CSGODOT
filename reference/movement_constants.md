# Movement constants

Every number in `src/movement/movement_config.gd`, where it came from, and
whether it has actually been checked against CS2.

**Nothing here has been measured in-game yet.** These are published defaults
and code-derived values, which is a starting point and not the finish line.
As each one gets measured, record the measurement and the method below.

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
| duck modifier | 0.34 | CS:GO | No |
| hull 32 x 32 x 72 | | Source player hull | No |
| duck height 54 | | CS:GO | No |
| step height 18 | | Source | No |
| max ground angle 45.57° | | Source uses a 0.7 normal threshold; acos(0.7) = 45.573° | Derived, exact |
| `NON_JUMP_VELOCITY` | 140 | `gamemovement.cpp:3830` | Read from the SDK, exact |
| `sv_maxvelocity` | 3500 | `movevars_shared.cpp:93` | Read from the SDK, exact |

## How to measure each kind

**Speeds.** Load the test course, run in a straight line, read the speedometer.
Compare against CS2 with `cl_showpos 1`.

**Acceleration.** Start from rest and count ticks to reach top speed. At 128 Hz
with `sv_accelerate 5.5` the first tick should add exactly 10.7421875 u/s
(`5.5 × 250 / 128`). The test suite pins this value, so if you change
`sv_accelerate` the test will tell you the new expected figure.

**Jump height.** Walk into the jump gauges. You should clear 56 and not 64.

**Air acceleration.** Strafe jump down the marked lane and read `jump gain` on
the HUD. Do the same in CS2 on a flat surface and compare the gain per jump.
This is the fiddliest one and the most important, because air acceleration is
most of what makes CS movement feel like CS.

### Crouch jump height

Ducking in the air shrinks the hull and moves the body up by the difference, so
your head stays put and your feet come up 18 units. That is what a crouch jump
is, and it is the only way to reach a ledge a standing jump cannot.

Measured in our build: a standing jump peaks at 58.19 units and a crouch jump
at 76.19, the difference being exactly the 18 unit hull delta.

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

`MovementConfig.tick_rate_independent_jump`, default **off** (Source-faithful).

Source splits gravity into two halves around the move, which normally makes
jump height independent of tick rate. But the jump impulse is applied *after*
the leading half-step, so the first tick of a jump travels at the full impulse
and the jump ends up higher than the physics alone would give:

| | Peak height |
|---|---|
| Textbook (`v²/2g`) | 57.00 units |
| Source ordering at 128 Hz | 58.18 units |
| Source ordering at 64 Hz | 59.36 units |

**This project simulates at 128 Hz and CS2 moves at 64.** So being faithful to
Source still leaves our jumps about 1.2 units short of CS2's. Options, once
someone measures a real CS2 jump:

1. Accept the difference. It is about 2%.
2. Turn on `tick_rate_independent_jump` and raise `sv_jump_impulse` until the
   height matches CS2's measured value at any tick rate.
3. Simulate movement at 64 Hz to match CS2 exactly, and keep 128 Hz only for
   shooting.

Option 2 is probably right, but it needs the measurement first. The test suite
pins both behaviours so the choice cannot drift by accident.

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

Still open from that audit, both on the map side: per-surface-property
collision and the real friction table in `surfaceproperties.vsurf`. The other
two it listed are in: the entity spawn points (`SourceEntities`) and the nav
mesh (`SourceNavMesh`).
