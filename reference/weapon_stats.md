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
| Magazine | 30 | 20 |
| Reserve | 90 | 80 |
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

## Spray patterns

`reference/spray_patterns/*.csv`, one row per shot, in degrees from the point
of aim. **Both files are placeholders and say so in their header.** They come
from a crude model of the shape, not from measurement, so the guns currently
spray in roughly the right direction and nothing more.

`reference/spray_patterns/README.md` has the procedure for replacing them with
real measurements, which the test range exports in the same format.

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
