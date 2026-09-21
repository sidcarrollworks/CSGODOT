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
| `sv_gravity` | 800 | Source/CS:GO default | No |
| `sv_jump_impulse` | 301.993 | Source/CS:GO default | No |
| walk modifier | 0.52 | CS:GO | No |
| duck modifier | 0.34 | CS:GO | No |
| hull 32 x 32 x 72 | | Source player hull | No |
| duck height 54 | | CS:GO | No |
| step height 18 | | Source | No |
| max ground angle 45.57° | | Source uses a 0.7 normal threshold; acos(0.7) = 45.573° | Derived, exact |

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

## Two decisions that are not settled

### The CS2 dead-strafe quirk

`MovementConfig.cs2_deadstrafe`, default **on**.

CS2 drops surface friction to 0.25 when vertical velocity is between 0 and
+140, and the air acceleration function multiplies by that friction even though
the player is airborne. The effect is that air strafing is roughly a third as
effective for about the first quarter of a jump. GoldSrc keeps friction at 1.0
in the air and has no such dead zone.

Source: <https://gist.github.com/zer0k-z/808bc8bfc494e0bbb5a423c2b1ca6685>

We clone it by default because the goal is CS2, not a better CS2. Anyone who
plays a lot of CS2 will feel the difference either way, so this should be an
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
