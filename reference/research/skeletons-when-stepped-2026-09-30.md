# Skeletons fitted when the body steps (2026-09-30)

Sid chose it on 2026-09-30, the first of the frame costs proposed after the
native movement. Nothing had been researched for it.
`reference/godot/animation.md` had the skeleton's modifier modes from the
class reference, and the watched games of 2026-09-29 had where a frame goes
with nine bots. This page is what was found, what was changed, and what it
is worth.

## Implementation status, 2026-10-02

PR #171 merged after Sid's playtest acceptance. The manual fit scheduling
and tick-start fallback below are implemented. The tables retain the
original September 30 before/after runs; their savings are not a fresh
benchmark of the later hit-effect and flinch workload.

## What a frame was fitting

A body's skeleton carries four modifiers: `FootPlant` (the feet on the
floor, a ray under each ankle), `HandGrip` (the hands back on the gun),
`TwistModifier` (the twist bones) and, on your own drawn body only,
`LookDownArch`. Fitting is running them, in the skeleton's deferred update
at the frame's end. After them the skin is sent, and `skeleton_updated`
moves what rides the bones: the hitboxes (`SkinnedHitboxes.follow`), the
held gun (`RigModel._update_pins`) and the eyes (`CharacterEyes.update`).

A skeleton's own default (`modifier_callback_mode_process` IDLE) fits it
in every frame, whether its pose changed or not. Since perf/bot-tick a body
nobody sees steps its animation only in frames that run no tick
(`PlayerModel.step_off_tick_frames`), and a dead one at rest not at all. So
every frame that ran a tick fitted all ten bodies again to the pose they
already had. In the watched game of 2026-09-29 (Sid playing competitive at
1080p, main after #153) that was 0.71 ms of fitting in every frame holding a
tick, with no body stepped in it.

## What Godot 4.7.2 does with a skeleton fitted by hand

The class reference says of MANUAL only "Do not process modification. Use
advance()". What it does was measured headless with a modifier that writes
a bone and records each run. `tests/run_body_fit_checks.gd` holds every
MANUAL row on a stand-in body carrying the game's `FootPlant` and
`HandGrip`, which `PlayerModel` tells what the body does in every frame, as
it tells every body's:

| A frame in which | IDLE | MANUAL |
|---|---|---|
| nothing is set | fitted, by the frame's time | not fitted, nothing fires |
| a bone's pose is set (a mixer's step, `set_bone_pose_*`, `set_bone_global_pose`) | fitted | fitted once, by no time |
| `advance(d)` is called | | fitted once, by the sum of the frame's `advance()` calls |
| `advance(d)`, then the update forced on the tick | | fitted once at the notification, by d, and not again that frame |
| a modifier's `active` set to what it is | | nothing |
| a modifier's `active` set false, or true | | fitted once, by no time, the modifiers active then running |

So a manual skeleton is fitted exactly when its pose changes, which is what
was wanted. The one thing to supply is the time: `FootPlant` and `HandGrip`
ease in and out by the time they are given, and take a fit given none as
one to make at once.

## What was changed

- `PlayerModel.step_off_tick_frames` puts the body's skeleton in MANUAL,
  with its animation.
- Every fit is given the time since the last (`PlayerModel._fit`, by
  `Skeleton3D.advance`): a step's in `_process`, the step's own for
  `PlayerModel.step` as the checks and the profilers call it. The modifiers
  run once in that frame's update. Easing by `move_toward` and by
  `1 - exp(-t / EASE)` toward a target that holds comes to the same whether
  the time comes as one fit or as several; a target that changes (the floor
  under a moving body) is sampled once a fit rather than once a frame.
- **A body that went a frame without its fit is fitted as the next tick
  begins** (`PlayerModel.fit_for_tick`, called for every player by
  `GameWorld.begin_tick` before anyone runs), if its model has moved or
  turned since its last fit. Every tick met the hitboxes where the last
  frame's fit put them; where that frame ran a tick of its own and so did
  not fit a body nobody sees, the fit it would have made is made now, from
  the model where that frame left it. Later ticks of the same frame meet
  the same fit, as they did. It is forced there and then
  (`NOTIFICATION_UPDATE_SKELETON`), since the frame's own update comes
  after the tick.
- A pose set otherwise is fitted at once in its frame: a body posed where it
  spawns (`pose_now`) or comes back (`pose_again`), the bones a ragdoll
  writes, whose twist bones follow as before, and the feet and the hands
  switched off at a death and on at a respawn. `pose_now` and `pose_again`
  first tell the feet and the hands what the body does now
  (`PlayerModel.set_fit_flags`), which only `_process` did. A ragdoll at
  rest, which writes nothing, is fitted in no frame and for no tick.
- Your own drawn body and its shadow, the view model and the buy menu's
  agent keep the default. They are seen in every frame, and your body bends
  with your view in every frame.

## What it is worth

The game's own scene, headless, competitive warmup with nine bots, watched
by a script that stamps the clock before and after every node's callbacks
and before each skeleton's first modifier. Headless Godot paces every frame
to 6.9 ms (its low-processor sleep, 145 frames a second), so a frame's
length says nothing there; the figures are the frames' own work. Fitting is
from the first modifier to the end of `skeleton_updated`'s handlers (the
hitboxes, the gun and the eyes moved). The work after the scripts is from
the end of the last node's `_process` to the frame's last deferred call:
the skeletons' updates with their skin, and the other deferred work.

The first version (fitting only when the body stepped), two runs of each,
alternated, 45 s of play each (two more of 70 s before agree):

| A frame | main | branch | main | branch |
|---|---|---|---|---|
| With a tick: skeletons fitted | 10.00 | 0.25 | 10.01 | 0.37 |
| With a tick: fitting | 0.80 ms | 0.01 ms | 0.78 ms | 0.01 ms |
| With a tick: work after the scripts | 1.06 ms | 0.21 ms | 1.05 ms | 0.23 ms |
| Without a tick: skeletons fitted | 10.00 | 9.75 | 10.00 | 9.61 |
| Without a tick: work after the scripts | 1.09 ms | 1.07 ms | 1.07 ms | 1.07 ms |
| Its tick, mean | 1.91 ms | 1.83 ms | 1.89 ms | 1.88 ms |

A frame that holds a tick does 0.82 to 0.85 ms less, where it was the
frame's slowest kind; a frame without one is unchanged. A fit is about
80 us of a body (0.076 ms: the modifiers, the hitboxes moved, the gun and
the eyes). Over a second of play the bodies are fitted 803 times where they
were 1,450, and spend 62 ms on it where they spent 110. A frame without a
tick fits 9.6 to 9.75 bodies where it fitted ten: the 8.25 to 8.5 bots that
stepped, your own body, and the ragdolls still falling; a dead body at rest
is no longer fitted.

The final code, with the fit at a tick's start (below), measured again the
same way, a frame's work being its tick, its scripts and its work after
them:

| A frame | main | branch | main |
|---|---|---|---|
| With a tick: skeletons fitted | 10.00 | 0.34 | 10.00 |
| With a tick: fitting | 0.85 ms | 0.01 ms | 0.87 ms |
| With a tick: its work | 3.95 ms | 3.24 ms | 4.00 ms |
| Without a tick: its work | 2.87 ms | 2.99 ms | 2.88 ms |

(The branch's second run of this set ran at 136 frames a second
throughout, its slowest frame of each second 20 ms where every other run's
was 10, while its own measured work was as the first's: something outside
the game held the machine, and it is left out. Its frames with a tick that
followed none did 3.20 ms of work.)

At 145 frames a second two frames in a row never both run a tick, so the
fit at a tick's start is not seen above. Headless at 90 frames a second
(`--max-fps 90`), where two in a row do for half the ticks:

| A frame, 90 a second | main | branch | main | branch |
|---|---|---|---|---|
| With a tick, after one without: its work | 4.21 ms | 2.95 ms | 3.70 ms | 2.91 ms |
| With a tick, after one with a tick: skeletons fitted | 10.01 | 11.59 | 10.01 | 11.49 |
| With a tick, after one with a tick: its work | 4.35 ms | 4.38 ms | 4.03 ms | 4.34 ms |
| Without a tick: its work | 2.94 ms | 2.78 ms | 2.69 ms | 2.67 ms |
| Every frame: its work | 3.87 ms | 3.50 ms | 3.55 ms | 3.45 ms |

A tick that follows a tick fits the nine bodies the frame before owed as it
begins, and costs what main's frame spent on them; the 1.5 bodies more are
those that then step at the frame's end, having waited two ticks
(`MOST_UNSTEPPED_TICKS`). The frames with a tick after one without keep the
whole saving.

Of 14 starts of the branch and 14 of main headless, one of the branch's (the
first version's) crashed in its first second of loading, before the
watcher's stamps were on any skeleton, with no backtrace; the other 13 and
all of main's ran. Whether it is this change is not known; the watched game
on Sid's machine will say more.

## What changes, and what does not

- **A body you can see is fitted as before.** A body a camera draws steps
  in every frame, so it is fitted in every frame, ticks or not.
- **Every tick meets the hitboxes where it met them.** Where a frame
  without a tick comes before the tick, that frame stepped and fitted every
  body nobody sees, as before. Where the frame before also ran a tick, which
  happens whenever two frames together outlast a tick (below about 128
  frames a second: at 100, 28% of the frames and 44% of the ticks; and
  after any long frame), the tick fits the body as it begins, from where
  that frame left the model. The modifiers are given the same time either
  way; the floor under the feet is looked at where the fit is made.
- **A body nobody sees keeps its last fit through a frame with a tick until
  the next frame or tick.** Its skin is not drawn, and its hitboxes, gun and
  eyes stay where the last fit put them, moving with the player.
- **A body that comes into view in a frame holding a tick** is drawn once
  from its last fit, a frame old: its feet fitted to where it stood a frame
  before, and its eyes, which are aimed in the world, a frame behind. The
  next frame it is seen and fitted. Its pose was a frame old before too.
- **A respawn is fitted at once, as it was,** now told first what the body
  does: a body back with its gun in hand and no draw holds it at once,
  where it took the flags it lay dead with (holding nothing) and eased its
  hands back onto the gun over 0.3 s. One that draws lets go for the draw
  as it did. The feet snap to the floor as they did (`put_at_once`).

## What the review found

Two reviewers read the change (what it does to the game; whether the checks
and this page hold), and each finding was argued against by another. Four
were confirmed, all fixed:

| Found | Fixed by |
|---|---|
| This page said a round met an older fit of an unseen body only below 64 frames a second. Two frames in a row run a tick below about 128, where the game's own cap is on a 120 Hz screen (116) or a 100 Hz one (97): at 100, 28% of the frames and 44% of the ticks. Your own body, never drawn between ticks, then had its hitboxes turned to your yaw of a tick before | `fit_for_tick`: the fit the frame before would have made is made as the tick begins |
| The checks held half the table: the stand-in had no feet or hands for `PlayerModel` to tell what the body does, so the flags written every frame (which must fit nothing) were never written, nor the death's and the respawn's switching, nor a step with the update forced | The stand-in carries `FootPlant` and `HandGrip`; a check for each row |
| The check of a skeleton's default, said to be your own body's, tested only Godot | Said to be what the rest is measured against |
| The check that no time is given twice allowed two frames of error | Each fit's time is held to the float |

And one more, not verified but true on reading: a respawn's fit on the tick
comes before any frame has told the feet and the hands what the body does,
on main as on this branch; `pose_again` now tells them first.

## Played

Sid played the branch on 2026-09-30: competitive on dust2 against nine
bots, a 1920x1080 window, 4.3 minutes, 25 deaths, watched as the run of
2026-09-29 was (main after the native movement, 1.9 minutes, 13 deaths).
He made the window fullscreen for six seconds in the middle; those seconds
drew at 4K and are left out, with the two frames that switched (185 and
110 ms). "Feels pretty good."

| 1080p, Sid playing | 2026-09-29, main | 2026-09-30, branch |
|---|---|---|
| Frames a second | 190 | 208 |
| A frame: mean, 95th, 99th | 5.26, 7.35, 9.06 ms | 4.82, 6.24, 7.57 ms |
| Frames of 6 ms or more | 23.3% | 7.1% |
| Frames of 8 ms or more | 2.4% | 0.7% |
| A frame that holds a tick: mean, 95th | 6.36, 8.18 ms | 5.35, 6.93 ms |
| Skeletons fitted in it, and the fitting | 9.8, 0.71 ms | 1.4, 0.10 ms |
| A frame without a tick | 4.71 ms | 4.58 ms |
| Its tick, mean | 1.92 ms | 1.62 ms |
| The slowest frame of each second: median, 95th | 9.7, 17.6 ms | 7.9, 15.0 ms |
| Seconds with it under 6 ms, under 8 | 0%, 23% | 7%, 52% |

Of the frame with a tick's 1.0 ms, 0.6 is the fitting; the tick was 0.3 ms
lighter in this play, which had more quiet time (166 of 256 seconds with
nobody shooting, dying, spawning or buying, against 65 of 111), and the
change does nothing to it. The frames without a tick sit near the frame cap
(224 a second, 4.46 ms). No script error, and no crash at loading.

What made the slowest frames, the switches to and from fullscreen aside:
the buy menu first opened (41.9 ms, as the day before), entering the buy
zone (21.0), a purchase (18.9), a molotov's detonation (its tick 14.2 ms),
and at the very end, as the game was closed, a frame of 77.9 ms, 73 of it
scripts. None is the skeletons'.

## Code fixes and Local checks

- **Local: played** (above).
- **Next:** the bodies nobody sees are still animated in every frame without
  a tick, 8.5 of nine, where a round asks for their pose a few times a
  second. That is the larger part of what a frame spends on bodies
  (`reference/roadmap.md`).
