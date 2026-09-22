# Weapon stats

Every number in `src/weapons/weapon_library.gd`, where it came from, and
whether it has been checked against CS2.

CS2 keeps its weapon tuning in `scripts/weapons.vdata_c`, which Source 2
Viewer does not decode into usable values, so none of this can be extracted
the way the map and the models were.

Since 2026-09-22 the damage, armour, falloff, fire rate, speed and inaccuracy
figures come from the **CS2 Weapon Spreadsheet** (last weapon update 18 March
2026), which Sid supplied. Its rows for the two weapons are copied at the end
of this file. The spray patterns and the recovery timings were measured in CS2
by hand, and still rule where the sheet disagrees (see "Where the sheet and
the build differ"). Reload times are not in the sheet and are still community
figures.

## Damage

| | AK-47 | M4A1-S |
|---|---|---|
| Chest, unarmoured | 36 | 38 |
| Head, unarmoured | 144 | 132 |
| Armour penetration | 0.775 | 0.70 |
| Head multiplier | x4 | x3.475 |
| Stomach multiplier | x1.25 | x1.25 |
| Leg multiplier | x0.75 | x0.75 |
| Range modifier | 0.98 | 0.94 |

The sheet gives damage, armour penetration, the head multiplier and the
falloff per 500 units. It has no stomach or leg multiplier; x1.25 and x0.75
are what every rifle in CS uses.

Range modifier is applied per 500 units travelled, Source's `flRangeModifier`.
The AK barely falls off; the M4A1-S noticeably does, which is the usual
explanation for why it loses long-range trades it should win on paper.

Armour penetration is the fraction of damage that gets through armour, and
armour absorbs half of what it does stop. `WeaponData.damage_at()` holds the
arithmetic.

The sheet's "fatal headshot range" pins all of that at once, and the tests
hold the build to it: an AK headshot kills out to 9,025 units without a helmet
and 2,716 through one; an M4A1-S headshot kills out to 2,247 without a helmet
and never through one.

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

The sheet gives inaccuracy in CS's own units: thousandths of the tangent of
the widest angle a round can leave the aim by, which is how the weapon scripts
store it. Its "accurate range" is the check: the AK's standing 7.01 is 15.24
cm (6 inches) off at 21.74 m, the sheet's accurate range.
`WeaponLibrary.cs_inaccuracy()` turns them into the degrees the cone is kept
in.

| | AK-47 | | M4A1-S (silencer on) | |
|---|---|---|---|---|
| | sheet | degrees | sheet | degrees |
| Standing | 7.01 | 0.40 | 5.40 | 0.31 |
| Crouching | 5.41 | 0.31 | 4.60 | 0.26 |
| Full run | 182.07 | 10.32 | 127.40 | 7.26 |
| Top of a standing jump | 147.77 | 8.41 | 105.10 | 6.00 |
| Each round fired | 7.80 | 0.45 | 7.00 | 0.40 |

Each figure is a total, the rifle's spread included: the AK's 7.01 standing
is 6.41 of inaccuracy and 0.6 of spread. So moving and jumping add their excess
over standing still, and a jump taken at a run is worse than either
(`Weapon.current_inaccuracy`). Before the sheet the build had a standing cone
twenty times too tight and a running one ten times too tight.

The per-round figure is added on every round and recovers over the measured
time below.

The tests pin the ordering: crouched is tighter than standing, walking under
about a third of run speed costs nothing, running is more than ten times the
standing cone, and jumping at a run is worse than anything.

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
| `view_punch_release_time` | 0.7 | How long the slow half takes once the trigger is UP, in seconds |
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

`view_punch_release_time` is the whole travel, end of fire to recentred, and
it is the one knob for how long the return takes: the shape above is scale
free, so doubling it doubles every milestone and changes nothing else. It went
from 0.35 to 0.7 on 2026-09-22 — Sid, "the total travel time of the crosshair
from end of fire to recenter should be twice as long."

After a full AK magazine the crosshair is halfway home in 109 ms and within a
quarter degree in 484 ms, against 273 and 420 before any of this, and never
dips below centre. The M4 is within a quarter degree in 406 ms. A single tap
comes out at 1.46° rather than 1.67°, and no longer depends on how long the
button is held past about 40 ms. The spray's height and the per-round shove are
untouched.

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

## Where the sheet and the build differ

- **M4A1-S magazine.** The sheet says 20 (reserve 60, 80 in all). The build
  keeps 25, because the CS2 spray plot the pattern was read from has 25 dots.
  One of the two is wrong; Sid decides.
- **Recovery.** The sheet's recovery time (AK 0.368 s standing, 0.305
  crouched; M4A1-S 0.339 and 0.242) is, going by CS:GO's code, the time for
  the firing penalty to fall to a tenth. Sid's frame-by-frame capture (AK 867
  ms, M4A1-S 542 ms back to baseline) is what the build uses, and the build
  reads "baseline" as a hundredth. Read at a tenth, the capture gives AK 0.43
  s and M4A1-S 0.27 s: the AK recovers a little slower than the sheet and the
  M4A1-S a little faster. Worth a second look if taps feel off.
- **Not modelled yet:** landing inaccuracy (AK 33.63, M4A1-S 21.98), ladder
  inaccuracy (no ladders), tagging power (60% for both), penetration power
  (200% for both), and recoil amount and variance (AK 30 / 70 / 0, M4A1-S with
  its silencer 21 / 65 / 0). Tagging and penetration are on the roadmap. The
  recoil amount may be the way to retire the estimated `recoil_scale`.
- **The cone's shape.** CS:GO's code picks a round's offset with the radius linear in a
  random number, which bunches rounds towards the centre. The build spreads
  them evenly over the disc. Same widest angle, different average.

## The sheet's rows

CS2 Weapon Spreadsheet, last weapon update 18 March 2026. Inaccuracy in CS
units; distances in metres as the sheet gives them; fatal headshot range in
units.

| | AK-47 | M4A1-S (no silencer) | M4A1-S (silencer) |
|---|---|---|---|
| Price | $2,700 | $2,900 | |
| Kill award | $300 | $300 | |
| Damage | 36 | 38 | same |
| Armour penetration | 77.50% | 70.00% | same |
| Falloff @ 500 u | 2% | 6% | same |
| Headshot multiplier | 4.000x | 3.475x | same |
| Fire rate (RPM) | 600 | 600 | same |
| Penetration power | 200% | 200% | same |
| Magazine / reserve / total | 30 / 90 / 120 | 20 / 60 / 80 | same |
| Mobility | 215 | 225 | same |
| Tagging power | 60% | 60% | same |
| Bullet range | 8,192 | 8,192 | same |
| Tracers | every third | every third | none |
| Accurate range, stand / crouch | 21.74 m / 28.17 m | 27.71 m / 32.43 m | 28.22 m / 33.13 m |
| Inaccuracy standing / crouching | 7.01 / 5.41 | 5.50 / 4.70 | 5.40 / 4.60 |
| Inaccuracy running | 182.07 | 98.38 | 127.40 |
| Inaccuracy on a ladder | 280.60 | 222.59 | 227.84 |
| Inaccuracy at jump apex | 147.77 | 105.20 | 105.10 |
| Inaccuracy after landing | 33.63 | 22.08 | 21.98 |
| Inaccuracy from firing | 7.80 | 12.00 | 7.00 |
| Recovery time crouch / stand | 0.305257 / 0.368000 | 0.242100 / 0.338941 | same |
| Recoil amount / angle variance / amount variance | 30 / 70 / 0 | 25 / 65 / 3 | 21 / same / 0 |
| Recoil pattern | set | set | same |
| Fatal headshot range / with helmet | 9,024.61 / 2,716.24 | 2,246.53 / none | same |
