# Weapon stats

Every number in `src/weapons/weapon_library.gd`, where it came from, and
whether it has been checked against CS2.

**Nothing here has been measured in-game yet.** CS2 keeps its weapon tuning in
`scripts/weapons.vdata_c`, which Source 2 Viewer does not decode into usable
values, so none of this can be extracted the way the map and the models were.
It is rebuilt from published community figures and CS:GO-era script dumps, and
the sources disagree in places. Treat it as a starting point for tuning.

## Damage

| | AK-47 | M4A1-S |
|---|---|---|
| Chest, unarmoured | 36 | 37 |
| Head, unarmoured | 144 | 132 |
| Armour penetration | 0.775 | 0.70 |
| Head multiplier | x4 | x3.57 |
| Stomach multiplier | x1.25 | x1.27 |
| Leg multiplier | x0.75 | x0.76 |
| Range modifier | 0.98 | 0.94 |

The M4A1-S head multiplier is 132/37 rather than a clean x4, which is why it is
stored as 3.57. Published tables give the chest and head figures directly, so
the multiplier is derived from them rather than the other way round.

Range modifier is applied per 500 units travelled, Source's `flRangeModifier`.
The AK barely falls off; the M4A1-S noticeably does, which is the usual
explanation for why it loses long-range trades it should win on paper.

Armour penetration is the fraction of damage that gets through armour, and
armour absorbs half of what it does stop. `WeaponData.damage_at()` holds the
arithmetic.

## Firing

| | AK-47 | M4A1-S |
|---|---|---|
| Cycle time | 0.1 s (600 RPM) | 0.1 s (600 RPM) |
| Magazine | 30 | 25 |
| Reserve | 90 | 75 |
| Reload | 2.5 s | 3.1 s |
| Move speed | 215 u/s | 225 u/s |

Both fire at 600 RPM, which is one shot every 12.8 ticks at 128 Hz. The weapon
does not round to ticks: `Weapon.can_fire()` compares against a timestamp, so a
click landing part-way through a tick fires at that fractional time and not at
the tick boundary. That is the same sub-tick handling the shot direction uses.

## Inaccuracy

These are the least trustworthy numbers here. CS2's inaccuracy model has a
separate value for standing, moving, walking, crouching, jumping and landing,
each decaying at its own rate, and none of them are published. What is in the
library is a four-value approximation: a standing cone, a moving cone
interpolated by speed, a jumping cone, and a per-shot addition that recovers
over time.

The one part of it that IS measured is how long that per-shot addition takes
to recover: see "Recovery timings, measured" below.

What the approximation does get right is the ordering, which is what the tests
pin: crouched is tighter than standing, walking under about a third of run
speed costs nothing, running is more than ten times the standing cone, and
jumping is worse than any of them.

## View kick, and why it is not the spray

**The bullets and the view are two different things, and this is the most
misunderstood part of how CS shoots.** Bullets follow the spray pattern
exactly. The view is given a smaller, springy nudge that only suggests the
pattern. You cannot read your own recoil off the screen: you learn the pattern
and pull against it. The community writeups are blunt about this, and CS2 even
exposes `weapon_recoil_view_punch_extra` (default 0.055) as a separate knob for
how hard the screen shakes.

Measured in our build, holding the trigger for a full magazine:

| | Bullets climb | View peaks at | View as a share |
|---|---|---|---|
| AK-47 | 16.00° | 1.81° | 11% |
| M4A1-S | 9.57° | 1.00° | 10% |

The view moves a tenth of what the spray does, and that is not a scale factor:
the spring pulls the view back between rounds while the muzzle keeps every
degree it has climbed. The bullets accumulate and the view does not.

The view also stops climbing about a third of the way through and settles back
toward centre while the spray carries on, because the later part of both
patterns is mostly sideways and the spring keeps pulling. That is what "the
crosshair kicks up but only so much" means.

### How it is built

`Weapon.aim_punch` is an angle with its own velocity, damped, with a spring
pulling it back to zero. This is Source's `DecayPunchAngle`. A shot pushes the
**velocity**, not the angle, which is why the view rises into a kick over
several ticks instead of teleporting to it: the largest single-tick movement
during an AK spray is 0.26°, against 3.44° for the steepest single bullet step.

The knobs, all on `WeaponData`:

| | Default | |
|---|---|---|
| `recoil_animation_time` | measured | How long the kick lasts, in seconds |
| `view_kick_up` | 1.2 / 1.0 | Degrees the view is kicked up, per round |
| `view_kick_side` | 0.25 / 0.2 | Degrees sideways, per round |
| `punch_damping_ratio` | 0.558 | Shape of the kick: rise and settle, no visible bounce |
| `viewmodel_recoil` | 0.35 | How much the weapon model climbs on top of the camera |
| `viewmodel_sway` | 0.2 | How much of that it gets sideways, against the climb |

The spring frequency, the damping and the impulse are derived from those. One
property falls out of the derivation and is worth keeping: re-measuring
`recoil_animation_time` changes how long the view moves and **not how far**,
because the impulse is normalised against the spring.

### Every round kicks the same

`view_kick_up` is per round and does not vary across the magazine. That is the
correction to the obvious mistake, which this made on 2026-09-22 and which Sid
caught immediately: scaling the kick by the round's own step through the spray
pattern.

A pattern's vertical steps are front-loaded and its sideways steps are not.
The AK climbs about two degrees a round for its first seven rounds and then
goes nearly flat, while its sideways steps grow past three degrees a round in
the second half. Scale the kick by those and the view punches hard twice and
then does nothing but sway, which is neither what a gun does nor what CS2
does. Sid's words were "the aimpunch happens with 1 or 2 shots. And the gun
moves left and right too much".

The pattern still decides which WAY the view leans each round, so the view
goes with the gun. It does not decide how far.

### What the numbers do

| | Per round | Held trigger settles at | Single tap |
|---|---|---|---|
| AK-47 | 1.2° up, 0.25° sideways | 1.2° | 1.23° |
| M4A1-S | 1.0° up, 0.2° sideways | 0.26° | 1.02° |

The M4's kicks stack up far less because its spring settles in 353 ms against
the AK's 644 ms, which is most of why it is the easier gun to hold down.

Both are by eye, not measured. They are the first thing to change if the kick
feels wrong.

### The weapon model

It hangs off the camera, so it already carries the whole view kick;
`viewmodel_recoil` is only the gun moving relative to the screen. That rotation
happens about the eye, so a degree of it throws the gun a long way sideways,
and anything but a small number reads as the weapon teleporting from shot to
shot (Sid, 2026-09-22). The view kick should be most of what moves.

Firing cross-fades into the `shoot1` clip over 30 ms rather than stopping the
player dead and cutting to frame zero. It does not replay the clip per round:
that was tried on 2026-09-22 and looked worse, because the clip is longer than
the gap between rounds at 600 RPM, so every round cut across the last one.

### Bullets do not care about any of this

Setting `view_kick_up` and `view_kick_side` to 0 removes the view kick
entirely and **every bullet still lands in exactly the same place**. There is a
test that asserts precisely that, because it is the property that makes a spray
learnable.

## Recovery timings, measured

**These are measured, not guessed.** Sid captured CS2 frame by frame on
2026-09-22 and tracked two things independently: the weapon model's distance
from its resting position, which gives the length of the recoil animation, and
the size of the accuracy box from `weapon_debug_spread_show 1`, which gives
when the weapon is accurate again. Three shots per weapon.

| | Recoil animation | Accuracy reset | Desync |
|---|---|---|---|
| AK-47 | 644 ± 5 ms | 867 ± 0 ms | 223 ms |
| M4A1-S | 353 ± 5 ms | 542 ± 0 ms | 189 ms |

**The two numbers are different, and the accuracy one is longer.** The gun
finishes moving a couple of hundred milliseconds before it finishes
recovering, so a player who taps again the moment the animation settles is
firing an inaccurate round. Across the wider set of weapons the desync runs
both ways and the Deagle is about 1250 ms out. This is CS2 behaviour, not a
bug, and reproducing it is deliberate: it is the reason the recoil animation
cannot be trusted as a readout of anything.

They live on `WeaponData` as `recoil_animation_time` and
`accuracy_reset_time`, per weapon, and everything else about the view spring
and the accuracy decay is derived from them. There are tests asserting each
build still hits both numbers and that the gap between them survives.

The accuracy penalty decays exponentially rather than linearly, which is both
what the measured curve does (its steps shrink as it recovers, a straight line
only on a log scale) and what CS:GO's accuracy penalty did. A single shot
recovers in exactly the measured time; a spray takes proportionally longer.

The test range prints both states side by side, so the desync is visible
without a capture: `cone ... ready|recovering` next to `view ... still|moving`.

Source: Sid's own capture and writeup, from
https://www.reddit.com/r/GlobalOffensive/comments/1lodfqw/ (that URL is not
reachable from the build machine; the numbers above came from Sid directly).

## Spray patterns

`reference/spray_patterns/*.csv`, one row per shot, in degrees from the point
of aim. **These are read off real CS2 spray plots** (2026-09-21), not
generated: 30 shots for the AK, 25 for the M4A1-S, with firing order recovered
from the plots' saturation ramp.

The shape is measured. The overall size is not, because the plots carry no
angular scale, so both were scaled together by assuming the AK climbs 16
degrees. `recoil_scale` on the weapon corrects that in one number.
`reference/spray_patterns/README.md` has the arithmetic.

The M4A1-S magazine is 25 rather than the 20 this file used to claim. Its
spray plot has 25 dots on it, which settles it.

## How to measure each kind

**Damage.** In CS2, `sv_damage_print_enable 1` prints the damage of every shot
that lands. Shoot a bot in each hitbox at point blank with and without armour,
then repeat at 1000 and 2000 units for the falloff curve.

**Fire rate.** Empty a magazine into a wall while recording, and divide the
magazine size by the elapsed time. Both rifles should come out at 600 RPM; if
they do not, the recording is wrong.

**Inaccuracy.** `weapon_debug_spread_show 1` draws the cone in CS2. Standing,
walking, running, crouched, mid-jump: read the cone in each state and write the
five numbers down. Replacing the four-value approximation with real per-state
values is the single biggest improvement available to shooting feel.

**Spray.** See the spray pattern README.
