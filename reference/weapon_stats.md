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
| AK-47 | 16.00° | 7.87° | 49% |
| M4A1-S | 9.57° | 4.71° | 49% |

The view gets there and no further because the spring pulls it back between rounds while the muzzle
keeps every degree it has climbed: the bullets accumulate and the view does
not.

The view also stops climbing about a third of the way through and settles back
toward centre while the spray carries on, because the later part of both
patterns is mostly sideways and the spring keeps pulling. That is what "the
crosshair kicks up but only so much" means.

### How it is built

`Weapon.aim_punch` is an angle with its own velocity, damped, with a spring
pulling it back to zero. This is Source's `DecayPunchAngle`. A shot pushes the
**velocity**, not the angle, which is why the view rises into a kick over
several ticks instead of teleporting to it: the largest single-tick movement
during an AK spray is 0.94°, against 3.44° for the steepest single bullet step.

The knobs, all on `WeaponData`:

| | Default | |
|---|---|---|
| `view_kick_spray_peak` | 0.5 | Where the crosshair peaks over a spray, against the spray's own climb |
| `view_punch_recovery_time` | 1.9 | How long the camera's SLOW half takes to settle, in seconds |
| `view_punch_release_time` | 0.35 | How long the slow half takes once the trigger is UP, in seconds |
| `trigger_release_cycles` | 1.25 | Rounds' worth of silence that also counts as the trigger being up |
| `view_punch_snap_time` | 0.18 | How long the camera's FAST half takes to settle, in seconds |
| `view_kick_snap_share` | 0.4 | How much of a round's kick goes to the fast half |
| `view_kick_side_ratio` | 0.2 | Sideways kick per round, against the climb |
| `recoil_animation_time` | measured | How long the WEAPON MODEL takes to settle, in seconds |
| `model_punch_snap_time` | 0.1 | How long the weapon model's FAST half takes to settle, in seconds |
| `model_kick_snap_share` | 0.75 | How much of a round's kick goes to the model's fast half |
| `punch_damping_ratio` | 0.558 | Shape of the kick: rise and settle, no visible bounce |
| `viewmodel_recoil` | 0.35 | How much the weapon model climbs on top of the camera |
| `viewmodel_sway` | 0.2 | How much of that it gets sideways, against the climb |

The spring frequency, the damping, the impulse and the per-round kick are all
derived from those.

### The per-round kick is solved, not picked

`view_kick_spray_peak` is the one knob for how hard the view kicks, expressed
as the thing you can actually see, and it is half: Sid read that off CS2 on
2026-09-22. `view_kick_up()` is solved from it: the spring is linear, so one pass of a
magazine with a unit kick gives the scale factor exactly, and the per-round
kick is one division rather than a search.

Solving it rather than tuning it means the thing that was actually observed
survives everything else. Change the spring, the fire rate, the magazine or
the pattern and the crosshair still peaks at half the spray; the per-round
kick moves to make it so. There is a test for the spec and another holding the
solver to what `Weapon` actually produces, since the two walk the same spring
in two places.

### Every round kicks the same

`view_kick_up()` is per round and does not vary across the magazine. That is
the correction to the obvious mistake, which this made on 2026-09-22 and which
Sid caught twice: scaling the kick by the round's own step through the spray
pattern.

A pattern's vertical steps are front-loaded and its sideways steps are not.
The AK climbs about two degrees a round for its first seven rounds and then
goes nearly flat, while its sideways steps grow past three degrees a round in
the second half. Scale the kick by those and the view punches hard twice and
then does nothing but sway. Sid's words were "the aimpunch happens with 1 or 2
shots. And the gun moves left and right too much".

The pattern still decides which WAY the view leans each round, so the view
goes with the gun. It does not decide how far.

### What the numbers come out at

| | Spray peaks | Shove per round | Single tap |
|---|---|---|---|
| AK-47 | 7.87° of a 16.00° spray | 1.40° | 1.67° |
| M4A1-S | 4.71° of a 9.57° spray | 0.85° | 1.00° |

### The camera's kick is two springs added together

One spring cannot rise fast and fall slowly. A damped spring's rise time and
its decay time are the same two constants read two ways, so one slow enough to
carry the crosshair up a whole spray is also smooth enough to have no rounds
in it: what came out was a clean ramp you could not see the shots in. Sid,
2026-09-22: "the motion as it moves up is too smooth. we still want it to feel
staccato, like each shot pushes it up."

So a round kicks two springs. `view_punch_snap_time` settles inside the gap
between rounds and gives each one its own shove; `view_punch_recovery_time`
settles over about two seconds and carries the crosshair up the spray.
`view_kick_snap_share` splits the round's kick between them, and both halves
are wanted: all snap and the crosshair never climbs, all hold and it ramps.

The crosshair shoves up about 1.4° and falls most of the way back on every AK
round, on a climb that totals 7.87°. There is a test that it falls back
between every round rather than ramping, and another that the shove is worth
at least a tenth of the climb.

### Letting go of the trigger

The slow half is slow so that a round's kick is still there when the next few
land. Nothing lands after the last round, so keeping it slow there only leaves
the view hanging: Sid, 2026-09-22, "the decay when you stop shooting... feels
a bit too floating." It switches to `view_punch_release_time` the moment the
trigger comes up. CS splits these the same way — its recoil index recovers
between rounds, not while they are going out.

**The weapon is told about the trigger, it does not infer it.**
`Weapon.trigger_held` is set once a tick by whoever drives the weapon. Working
it out from the gap since the last round instead, which is what this used to
do, costs `trigger_release_cycles` of dead time at the top of the spray where
the crosshair has stopped climbing and has not started falling — 200 ms on the
AK at the old value of 2, which Sid felt exactly: "it still feels like it hangs
at the top for 200ms." The gap still matters as well as the button, because an
empty magazine stops the rounds with the trigger still down.

**The return is a plain exponential, and that is a specific choice.** A spring
let go from rest starts with no speed at all, builds up and then eases out: an
S, which reads as a hang however short you make it. So the release is
critically damped and `Weapon` hands it exactly minus its own frequency times
its height as a velocity at the instant the trigger goes up — the one
combination a second-order system has that gives `V·exp(-ωt)`, steepest at the
moment of release and flattening into the bottom. Sid, 2026-09-22: "if it were
a curve it would be the bottom left quarter of a circle. A sharp drop and
smooth at the bottom." Only the velocity is touched, so there is no jump: the
crosshair is where it was, it has simply stopped climbing and started falling.
`release_frequency()` is `-log(SETTLE_FRACTION) / view_punch_release_time`,
with no peak term, because an exponential has no rise to peak past.

After a full AK magazine the crosshair is halfway home in 62 ms against 273,
within a quarter degree in 242 ms against 420, and never dips below centre. A
single tap comes out at 1.46° rather than 1.67°, and no longer depends on how
long the button is held past about 40 ms. The spray's height and the per-round
shove are untouched.

### The camera and the weapon model are separate springs

This is the part that took three goes to get right, so it is worth stating
plainly: **the camera settles in about two seconds and the weapon model in a
few hundred milliseconds, and only the model's timing was ever measured.**

Driving both off `recoil_animation_time` is the mistake. The crosshair then
reaches its full height within two or three rounds and sits there, when it
should climb with the spray, and the solver is forced to pick a per-round kick
high enough that a single tap throws the view five degrees. Sid, 2026-09-22:
"the crosshair still needs to move up about halfway as the shots go up. It
maxes out about 3 shots up."

With the camera on its own two-second recovery, the AK's crosshair passes
halfway up the spray while the bullets do, and a single tap is under two
degrees. The M4's is a degree, lighter than the AK's as it should be, which is
not something that came out when the two springs were one.

### The weapon model falls back between rounds

The gun got the same two-spring treatment the camera did, for the same reason
and then one more. CS2 does not run a spring on the weapon model at all: it
replays the firing clip from its start on every round, so the gun drops back
towards rest however fast the rounds come.

A single spring long enough to last the measured animation reaches its own
peak about 78 ms in, and the next AK round lands at 100 ms. It never got to
fall. The gun climbed over the first few rounds to a height and jittered there
for the rest of the magazine: 25 per cent of that height was all it gave back
between rounds. Sid, 2026-09-22: "the animation doesn't continually fall. It
pushes up till you stop holding the mouse button. After you stop and the
animation finished rising then it starts returning back to place. The
animation needs to fall a little between shots."

`model_punch_snap_time` is short enough to be most of the way home before the
next round lands, and `model_kick_snap_share` sends three quarters of the kick
to it. The AK's gun now swings 66 per cent of its height on every round and the
M4's 79, both falling back on every single one.

**`model_hold_time()` is solved, not picked.** `recoil_animation_time` is the
measurement and stays the specification, so splitting the spring must not
quietly change it. The slow half raises nothing but the tail while the fast
half raises the peak that the settle threshold is taken against, so the slow
half has to run somewhat longer than the measured number for the two together
to settle on it. There is no closed form for where a sum of two springs crosses
a hundredth of its own peak, so `WeaponData` bisects for it once and remembers.
The AK still settles in 648 ms against the measured 644, the M4 in 352 against
353, whatever either of the two knobs above is set to.

### How much the model moves

It hangs off the camera, so it already carries the whole view kick;
`viewmodel_recoil` is only the gun moving relative to the screen. That rotation
happens about the eye, so a degree of it throws the gun a long way sideways,
and anything but a small number reads as the weapon teleporting from shot to
shot (Sid, 2026-09-22). The view kick should be most of what moves.

Firing replays a firing clip on **every round**, cross-faded over 30 ms rather
than stopping the player dead and cutting to frame zero. Leaving a running clip
alone meant the gun animated about once per clip length: Sid, 2026-09-22, "with
the AK, it triggers the animation about every second. The m4, maybe a half a
second. Still not as fast as the gun shoots."

The clips are found at setup from whatever the weapon's set actually carries,
rather than one name being assumed, and cycled through, since CS2 ships several
so a spray does not repeat one animation.

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
