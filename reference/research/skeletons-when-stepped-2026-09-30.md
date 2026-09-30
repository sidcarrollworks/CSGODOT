# Skeletons fitted when the body steps (2026-09-30)

Sid chose it on 2026-09-30, the first of the frame costs proposed after the
native movement. Nothing had been researched for it.
`reference/godot/animation.md` had the skeleton's modifier modes from the
class reference, and the watched games of 2026-09-29 had where a frame goes
with nine bots. This page is what was found, what was changed, and what it
is worth.

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
a bone and records each run, then held in `tests/run_body_fit_checks.gd`:

| A frame in which | IDLE | MANUAL |
|---|---|---|
| nothing is set | fitted, by the frame's time | not fitted, nothing fires |
| a bone's pose is set (a mixer's step, `set_bone_pose_*`, `set_bone_global_pose`) | fitted | fitted once, by no time |
| `advance(d)` is called | | fitted once, by the sum of the frame's `advance()` calls |
| `advance(d)`, then the update forced on the tick | | fitted once at the notification, by d, and not again that frame |
| a modifier's `active` set to what it is | | nothing |
| `active` set false, then true | | the skin sent once, unfitted; then fitted once by no time |

So a manual skeleton is fitted exactly when its pose changes, which is what
was wanted. The one thing to supply is the time: `FootPlant` and `HandGrip`
ease in and out by the time they are given, and take a fit given none as
one to make at once.

## What was changed

- `PlayerModel.step_off_tick_frames` puts the body's skeleton in MANUAL,
  with its animation.
- `PlayerModel.step` hands the skeleton the step's time
  (`Skeleton3D.advance`) after the animation's. The modifiers run once in
  that frame's update, by the time since the body last stepped, as they did
  frame by frame. Easing by `move_toward` and by `1 - exp(-t / EASE)` toward
  a target that holds comes to the same whether the time comes as one fit
  or as several; a target that changes (the floor under a moving body) is
  sampled once a step rather than once a frame.
- A pose set otherwise is fitted at once in its frame: a body posed where it
  spawns (`pose_now`) or comes back (`pose_again`), and the bones a ragdoll
  writes, whose twist bones follow as before. A ragdoll at rest, which
  writes nothing, is fitted in no frame.
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

Two runs of each, alternated, 45 s of play each (and two more of 70 s
before, which agree):

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
were 1,450, and spend 62 ms on it where they spent 110.

Nothing else moved: the frames' scripts and the tick are the same within
the runs' spread. A frame without a tick fits 9.6 to 9.75 bodies where it
fitted ten: the 8.25 to 8.5 bots that stepped, your own body, and the
ragdolls still falling; a dead body at rest is no longer fitted.

Of 10 starts of the branch and 10 of main headless, one of the branch's
crashed in its first second of loading, before any skeleton was fitted by
the watcher's stamps, with no backtrace; the nine others and all of main's
ran. Whether it is this change is not known; the watched game on Sid's
machine will say more.

## What changes, and what does not

- **A body you can see is fitted as before.** A body a camera draws steps
  in every frame, so it is fitted in every frame, ticks or not.
- **A body nobody sees keeps its last fit through a frame with a tick.** Its
  skin is not drawn. Its hitboxes stay where the last fit put them and move
  with the player, as they did between fits before. A round in the next tick
  meets them where the frame before it placed them, which is where it met
  them before: a body nobody sees steps in every frame without a tick, and
  the frame before a tick is nearly always one. Only when two frames in a
  row each hold a tick (below 64 frames a second, or a hitch) does a round
  meet such a body where a frame a tick earlier placed it, a fraction of a
  tick's walk behind, where before it met it where the later of those
  frames placed it. `MOST_UNSTEPPED_TICKS` bounds that at two ticks.
- **A body that comes into view in a frame holding a tick** is drawn once
  from its last fit, a frame old: its feet fitted to where it stood a frame
  before, and its eyes, which are aimed in the world, a frame behind. The
  next frame it is seen and fitted. Its pose was a frame old before too.
- **A respawn fits the body at once.** Its hands take the gun, or let go of
  it for the draw, at once, rather than easing from where they were when it
  died. The feet did so already (`put_at_once`).

## Code fixes and Local checks

- **Local: play it.** The watched comp game at 1080p, as on 2026-09-29, to
  compare a frame that holds a tick (6.31 ms then, 1.9 of it the tick) and
  the slowest frame of each second, and to see whether the crash at loading
  comes again.
- **Next:** the bodies nobody sees are still animated in every frame without
  a tick, 8.5 of nine, where a round asks for their pose a few times a
  second. That is the larger part of what a frame spends on bodies
  (`reference/roadmap.md`).
