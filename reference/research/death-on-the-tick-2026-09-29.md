# What a death costs on the tick (2026-09-29)

Sid's goal is a frame under 6 ms with nine bots, always. After the hitboxes
for shots (`hitboxes-for-shots-2026-09-28.md`) the worst ticks of a match
were the ones somebody died in: 8 to 14 ms in `scripts/profile_dust2.gd`'s
ten-player round, where a tick with nothing in it is 2. No research covered
it; this page is the measurement and what was done.

## How it was measured

Godot 4.7.2 headless on Sid's machine (Ryzen 7 7800X3D), Box3D, dust2's
seeded ten-player match (the match of `scripts/profile_worst_ticks.gd`:
seed 20260926, five a side, 6 s of freeze time, $16000), 3,600 ticks
stepped by hand with every body posed on the tick, played twice in one
process. The first play pays what is paid once; the second is warm. Three
players die in it, at ticks 1553, 2060 and 2112.

A stopwatch was put into the code for the run and taken out after: a span
round each part of `PlayerSim._on_hit_target_died`, of the ragdoll's build,
of `GameSystems.step`, of `Box3DDrops.tick`, and round every listener an
event is handed to. It is not committed. The totals in "Before and after"
are from runs with nothing put into the code, the two builds in turn,
twice, on two occasions.

The same build's tick differs by a fifth from one run to the next on this
machine (`reference/performance.md`, "Measuring it again": a figure on a
page is not a baseline), so the parts below are each from one run, and
only builds run in turn are set against each other.

## Where it went

A tick with a death was 7.7 ms warm (6.8 to 8.4) and 10.5 the first time
(9.7 to 11.8); a quiet tick in the same run 2.2.

| In the shooter's run, 3.2 ms | us |
|---|---|
| The ragdoll made (`Ragdoll.build`) | 3,000 |
| of it: fifteen bodies made in the native world | 790 |
| their joints | 440 |
| two parts a joint apart or inside each other found, and an exception made for each | 580 |
| every part made an exception for every part of each dead body near | 480 (none near) to 2,240 (two near) |
| lifted clear of the floor | 220 |
| the bones' names, the capsules by bone, the bodies laid at rest and back | 490 |
| The hit target and the hull switched off, the model letting go, `killed` told | 140 |

| At the tick's end, 2.2 ms (a quiet tick's is 0.25, 0.63 with a body lying) | us |
|---|---|
| The native step | 770 |
| The ragdolls before the step (parts under the floor put back on it) | 340 |
| What the death drops (`ItemDrops._on_death`) | 460 |
| The kill feed's row | 130; 6,000 the first time, 2,400 the second |
| The systems, as on any tick | 240 |

The kill feed laid its row out as it was told: names measured, the gun's
icon and the marks read. The first of a match read a face (3 to 5 ms) and
an icon (1 to 6 ms) from the disk, on the tick.

And for the rest of the round every tick stepped the native world for the
bodies lying, 0.25 ms, and every frame posed them again where they lay: a
ragdoll listened to the step for as long as it was there, and the world is
stepped while anything listens.

## What was done

- **The body is made ahead** (`Ragdoll.prepare`). Its parts, joints and
  the exceptions between parts a joint apart are its own, whatever pose it
  dies in: they are made once, laid out as the skeleton stands at rest
  (where the joints' limits are measured from), and switched off in the
  native world (`enabled`). `GameWorld._process` has one player's made a
  frame, 1.3 ms, off the tick. A death puts each part on its bone and
  switches it on (`drop`), a respawn switches them off again for the next
  (`park`). A death before the body is made makes it then, as before.
- **An upper layer for each dead body.** The addon has 64 layers
  (`collision_layer_high`, `collision_mask_high`). A body's parts touch the
  world by the first layer and each other by one of the upper thirty-two,
  which is the body's own, so two dead bodies' parts have no layer in
  common and nothing is made to keep them apart. Past thirty-two bodies two
  share a layer and are told part by part, as all were.
- **Two parts too far apart to touch are not looked at closer**: by how far
  each reaches from its middle. Most of the hundred pairs.
- **A body at rest is left lying** (`_rest`): every part asleep for eight
  ticks, it listens to the step no more and is posed no more. Nothing a
  dead body touches moves, so nothing wakes it.
- **The kill feed makes its rows on the frame.** What a death says is read
  as it is told, from the roster as it is; the row is laid out on the next
  frame.
- **The HUD reads its faces and icons before play**
  (`HudStyle.read_ahead`): every face, every item's icon, the feed's marks,
  0.15 s as the HUD is made.

Measured on the addon before it was built on
(a probe, two capsules over a floor): two bodies whose upper layers share a
bit collide and with different bits pass through each other, the last bit
too; a body switched off hangs where it is, is not counted awake, can be
moved, and falls when switched on; a joint made between two bodies holds
after both are switched off and on. Switching fifteen bodies is 5 to 8 us.

## After

| In the shooter's run, 0.56 ms | us |
|---|---|
| The ragdoll dropped (`Ragdoll.drop`) | 450 |
| of it: parts on their bones, switched on | 115 |
| two parts inside each other found | 85 |
| lifted clear of the floor | 165 |
| written | 40 |

| At the tick's end, 1.5 to 1.9 ms | us |
|---|---|
| The native step | 590 |
| The ragdolls before the step | 190 |
| What the death drops | 310 to 380 |
| The kill feed told | 26 |

## Before and after

Main with the gun's fix (`e5d69a9`) and this branch, in turn, two runs of
each, on two occasions (the branch as first written, `ed87c51`, and as
reviewed, `e9f7e4b`). Each figure is a run's.

| The seeded match, ms | before | after |
|---|---|---|
| A tick with a death, warm (the second play) | 7.3, 7.2, 6.4, 6.6 | 4.8, 4.8, 4.0, 4.0 |
| its worst | 8.8, 8.7, 7.0, 7.1 | 5.1, 5.8, 4.1, 4.2 |
| A tick with a death, the first play of a process | 13.3, 14.1, 9.5, 8.5 | 6.8, 6.2, 4.1, 4.1 |
| its worst, the first death | 20.4, 23.2, 13.9, 11.1 | 9.2, 9.2, 4.2, 4.5 |
| The run the death is in, warm | 4.0, 3.8, 3.4, 3.3 | 1.6, 1.5, 1.2, 1.3 |
| The tick's end, warm | 1.9, 2.0, 1.6, 1.8 | 1.6, 1.7, 1.4, 1.4 |
| A quiet tick | 2.11, 2.12, 2.00, 1.86 | 1.96, 1.96, 1.80, 1.75 |
| its end, bodies lying | 0.57, 0.57, 0.54, 0.51 | 0.35, 0.34, 0.31, 0.31 |
| Every tick: the mean | 2.14, 2.13, 2.01, 1.87 | 1.98, 1.96, 1.81, 1.76 |
| the 99th | 3.5, 3.7, 3.5, 3.2 | 3.4, 3.3, 3.1, 2.9 |

And the warmup Sid played (2026-09-29: nine bots, shooting nothing
himself, a worst frame over 10 ms where alone it is 5.5 to 7), headless
with `scripts/profile_dust2.gd -- 5 8`, forty seconds of it, the bots
fighting and coming back: the worst tick of each five seconds.

| Warmup's worst ticks, ms | before | after |
|---|---|---|
| The five seconds of the first deaths | 8.9, 9.4 | 4.6, 4.5 |
| The worst of the others | 7.4, 9.7 | 5.2, 5.7 |
| The frames' scripts, mean and worst | 2.0 to 2.4, 7 | 2.0 to 2.5, 7 |

The frames' scripts are the same: nothing here is of the frame but the
kill feed's row, which was the tick's.

**The profiler misled once.** `profile_dust2.gd` took freed nodes out of
its lists with `erase`, which will not take a freed object out of a typed
list and prints two errors each time it is asked. A ragdoll freed at a
respawn was asked for on every frame after: 900 errors in forty seconds of
warmup on main, none on the branch, which frees none, and main's frames
timed with the printing in were 10 to 29 ms where the branch's were 5 to
7. With the profiler dropping what has gone by where it is, the two are
the same. Fixed here.

## Reviewed

Three reviewers, one each for the ragdoll, the player and the world, and
the kill feed with the HUD and the checks, and a skeptic for each finding
(Opus, 9 agents, 1.09 M tokens). Six findings held and are put right:

- **A dead bot's body would have shaken once it lay at rest.** A bot's
  model was drawn between its last two ticks every frame, dead too, and
  dead it runs no tick: the model went to and fro between the two it died
  between, up to 4 units for one killed running. The ragdoll posing the
  body every frame hid it. A dead bot's model is left where it was last
  drawn, and a body at rest is posed again if what its skeleton hangs
  under moves.
- **The world stuck on a body that cannot be made**, asked for it every
  frame and made nobody's after it.
- **The HUD's images first drawn mid-match** (the dead card's skull, the
  win panel's arrows, the other side's emblem) were still read on the
  frame that drew them. All are read ahead, and a check reads the parts'
  scripts for the names.
- Three checks that could not fail, or were not there: the upper layers'
  counts, the player's use of the body made ahead, a parked body's native
  parts.

## Left

- **The first death's step.** In three runs of six the native step of
  the tick of a process's first death took 6 to 8 ms, where it is 0.6
  after: the 9 ms worst above. A capsule, a ragdoll and a dropped pistol
  stepped for the first time on dust2 by themselves each took 0.2 to 0.7
  ms, so it is something of the match that was not found.
- **A bone folded into another's part has its capsule laid out as at
  rest**, not as it died, since the parts are made before the death: a
  spine bent as it died is drawn bent and collides straight, a few units
  apart. Only with the hitbox capsules, which fold the spine and the neck;
  CS2's own shapes fold nothing.
- What a death drops, 0.3 to 0.4 ms: a native body made for each thing
  dropped, its hull from a mesh.
- A falling body's parts looked for under the floor every tick, 0.15 to
  0.25 ms a body while it falls, and as much once at the death.
- The native step with a body falling, 0.45 to 0.6 ms a tick.
- The round that kills, 0.6 ms in the shooter's run
  (`hitboxes-for-shots-2026-09-28.md`).
- A player's ragdoll is made from its nineteen hitbox capsules, folded to
  fifteen bodies, not from CS2's fifteen ragdoll shapes: `RagdollShapes` is
  only ever read by a check. Found here, not changed here.
