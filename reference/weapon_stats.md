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
| AK-47 | 16.00° | 3.39° | 21% |
| M4A1-S | 9.57° | 2.20° | 23% |

The view also stops climbing about a third of the way through and settles back
toward centre while the spray carries on, because the later part of both
patterns is mostly sideways and the spring keeps pulling. That is what "the
crosshair kicks up but only so much" means.

### How it is built

`Weapon.aim_punch` is an angle with its own velocity, damped, with a spring
pulling it back to zero. This is Source's `DecayPunchAngle`. A shot pushes the
**velocity**, not the angle, which is why the view rises into a kick over
several ticks instead of teleporting to it: the largest single-tick movement
during an AK spray is 0.30°, against 6.61° for the steepest single bullet step.

The knobs, all on `WeaponData`:

| | Default | |
|---|---|---|
| `recoil_view_fraction` | 0.45 | How much of the pattern the view is kicked by |
| `punch_impulse_scale` | 20 | How hard a shot pushes the punch velocity |
| `punch_damping` | 9 | Viscous damping on that velocity |
| `punch_spring` | 65 | Spring pulling the view back to where you point |
| `viewmodel_recoil` | 1.0 | Extra movement for the weapon model only |

The structure is Source's. The two spring constants are from memory of the SDK
and could not be verified from this machine, so treat them as tunables rather
than as facts. `recoil_view_fraction` is tuned by eye against CS2 and is the
first thing to change if the kick feels wrong.

Setting `recoil_view_fraction` to 0 removes the view kick entirely and **every
bullet still lands in exactly the same place**. There is a test that asserts
precisely that, because it is the property that makes a spray learnable.

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
