# The walking hitch, and the tick after it — 28 September 2026

Sid, playing dust2 after Box3D became the game's physics: walking the map,
the character now and then stops dead as if it had met a wall, every bit of
speed gone, and sets off again at once. And with nine bots the frames that
run a tick are too long for the goal, a frame of 6 ms at most
([performance.md](../performance.md), "Against CS2"). This page is what was
found, what was changed, and what is left. It follows the
[bridge and movement fixes](box3d-performance-fixes-2026-09-26.md).

## The hitch

**Found with** `scripts/profile_hull_traces.gd` (written for this): five bots
walk Competitive's site routes on dust2, holding fire, the world's tick run
by hand so each bot is seen before and after its command, and every hull
trace written down by a bot script that overrides `_trace`. A hitch is a
tick that starts on the ground at 100 u/s or more with a move held and ends
under 1 u/s. On main (dfd4208): 13 in a minute of game, 18 in a minute and a
half, none of them near a wall.

**What happened in one** (tick 126, a bot at -778 119 -858, walking mostly
-z along the foot of a floor rising toward +x):

| Trace | Result |
|---|---|
| The move, 3.83 units | met a floor triangle, normal (-0.072, 0.997, 0), 1.92 units on; **no travel** |
| The move again, clipped to that plane, three times | the same |
| The step: up 18.03 | clear |
| The move, from up there | clear |
| The step: down 18.03 | **no floor** |
| Stay on ground: up 2, down 20 | the floor, 2.0 down |

Two faults, one after the other.

1. **A hit at a shallow angle took the whole move.** Box3D's sweep stops
   0.197 units short of what it meets, and counts a start closer than about
   0.2 to 0.246 as an overlap, so the bridge kept 0.06 more between a hull
   and what it met (`CAST_CLEARANCE`), by backing the hull off along its
   motion until it was that much further from the plane. That is
   `0.06 / |direction . normal|` of back-off. Straight down onto a floor it
   is 0.06 units. At tick 126 the motion closed on the plane by 0.0027 a
   unit travelled, so it was 22 units, more than the move: the hull went
   nowhere, against a plane it could walk on. Four bumps of that, and
   Source's TryPlayerMove stops a move that made no way at all.
2. **The step that should have saved it found no floor.** Box3D's cast
   reports a hit only where the shape would touch within the sweep. The
   hull went up 18.03 and on 3.83, over a floor 0.1 higher than where it
   had stood 0.257 clear, so 18.19 over it; swept down 18.03 it would end
   0.16 over the floor, inside the band and touching nothing, and the cast
   reported nothing. With no landing the step is refused, as it is over a
   drop, and the flat move's zero stands.

The second fault is also most of what made a tick dear: a move that ends
inside the band without a hit leaves the hull there, and the next trace
starts in overlap and searches for a way out, eight casts a direction.

## What was changed

- **`Box3DQueries.shape_cast_prepared`**, which every sweep goes through
  (the hull's, a grenade's): it sweeps 0.5 further than asked
  (`CAST_REACH`) and reports a hit wherever the motion's end would be
  inside the clearance; it backs off along the motion by 0.25 at most
  (`CAST_BACK_OFF`), and hands back what the clearance still lacks as
  `offset`, a push along the hit's normal (0.06 at most). `PlayerBody._trace`
  adds the offset as it adds a recovery: part of the travel, none of the
  move's time. A hit can now come back with `fraction` 1: the whole motion,
  and the push.
- **A recovery tries 0.125 first** (`NATIVE_RECOVERY_STEP`) along a
  direction that clears, before the binary search: two casts where eight
  were, the correction 0.07 more at most.
- **A player's tick is a scope** (`Box3DQueries.begin_scope`,
  `PlayerBody.simulate`): nothing else moves in it, and everything it asks
  leaves its own hull out, so the other hulls are synchronized once for it
  rather than for every cast, and its own proxy is taken out of the native
  world once rather than by each cast.
- **A ray that starts in the open is one native call**, its nearest hit,
  where it was three (what holds its start, the nearest hit, every hit).
  Inside a scope a player's own rays start in the open, its hull being out.
- **Unit normals** from the bridge, and **`FootPlant` eases its floor
  normals with `lerp` and makes a unit of the result**: `Vector3.slerp`
  between two normals a fraction of a degree apart finds its axis from a
  cross product too small to make a unit of, and printed "The axis Vector3
  must be normalized" every frame for every such foot, 1,000 times a minute
  with five bots. None now.

## Measured

An AMD Ryzen 7 7800X3D, Godot 4.7.2, headless. "Main" is dfd4208 in a second
checkout, alternated with the change.

**Walking** (`scripts/profile_hull_traces.gd -- 5 60`, five bots, 3,840
ticks; counts, so the same every run):

| | Main | Now |
|---|---:|---:|
| Hitches | 13 | 0 |
| Hull casts | 117,008 | 95,974 |
| Ticks of more than 12 traces, of 19,200 | 3,093 | 71 |
| Most traces in a tick | 105 | 93 |
| Moves that went nowhere against a plane | 3,355 | 817 |
| Stay on ground's up 2: starts in overlap, and its casts | 2,101, 35,129 | 1,678, 21,428 |

**The tick** (`scripts/profile_box3d_match.gd -- --physics box3d`, the seeded
768 ticks with ten players of the 26 September page, five runs of each,
alternated):

| | Main | Now |
|---|---:|---:|
| Mean, the median of five (least to most) | 3.68 ms (3.62 to 3.73) | 3.09 ms (3.06 to 3.16) |
| 95th | 4.79 ms | 4.05 ms |
| Worst | 6.66 ms (6.00 to 6.92) | 6.22 ms (5.71 to 6.88) |
| Hull traces a tick, and the most | 54.05, 105 | 51.97, 81 |

That workload walks less than a match does, so it shows the scope's saving
more than the searches'. Its split (`scripts/profile_box3d_costs.gd`, one run
of each, instrumented, so a little over the figures above):

| Exclusive, ms a tick | Main | Now |
|---|---:|---:|
| Commands run, outside the queries | 1.178 | 1.136 |
| Native casts | 0.498 | 0.501 |
| Bots thinking, outside the queries | 0.450 | 0.448 |
| The sweep's wrapper | 0.238 | 0.258 |
| Rays | 0.305 | 0.233 |
| Animation parameters | 0.213 | 0.207 |
| Proxies synchronized | 0.610 | 0.208 |
| End of tick | 0.196 | 0.193 |
| The native step, four times | 0.155 | 0.154 |
| A hull left out of its own casts | 0.152 | 0.001 |
| **The tick** | **4.012** | **3.354** |

**The merges did not slow the tick.** Sid's impression was that the Box3D
branch ran faster before the pull requests of 27 and 28 September went in.
The branch as Codex left it (16c03d4), #125's merge (9040288) and main
(dfd4208), alternated on the same afternoon: 4.15 and 4.23 ms; 4.45 and
4.55; 4.42 and 4.58, 4.34 and 4.49. Main is 0.2 ms over the branch, and
level with #125's merge. The 26 September page's 3.28 ms was the same
workload on a quieter machine: the mean moved from 4.45 to 3.68 on main
within this afternoon. A figure on a page is not a baseline; the other build
run beside this one is.

**In the editor's profiler**, "Physics Frame Time 15.62 ms" is the length of
a tick at 64 Hz, not a cost. "Physics Time" is the cost, and nearly all of
it is `GameWorld.step`. "Physics 3D" reads 0 because Godot's own physics
server has nothing in it: Box3D's step is inside `GameWorld.end_tick`.

## Checks

- `tests/run_dust2_bot_checks.gd` (dust2, so Sid's machine): five Ts walk
  for a minute and none is stopped dead in a tick. On main's code it fails,
  13 times.
- `tests/run_box3d_movement_checks.gd`: what a sweep hands back (one that
  would end in the band, one that ends clear of it, one grazing the floor);
  floors rising 1, 2, 3 and 5 degrees walked up at a run; a slope rising
  beside the way, met 1, 2, 5 and 10 degrees off its foot. On main's code
  six of the eleven fail: the sweep's two, and four on the traces a tick
  (13, a search). Boxes do not stop a hull dead as dust2's triangles do,
  which is why the check that does is the one on dust2.
- `tests/run_box3d_sync_checks.gd`: the scope, its owner out of the world
  and back, resized inside it, and another hull moved by hand inside it.
- `tests/run_foot_plant_checks.gd`: a normal eased between two a hair
  apart.
- The whole suite with the extracted assets: 4,301 checks in 56 files, all
  passed, the AWP's four settling checks known open as before.

## What is left of the 6 ms

The goal is every frame under 6 ms at 4K with nine bots. A frame that runs
a tick is the tick and the frame's own work on one thread; on 26 September
those frames' 99th percentile was 10.3 to 10.5 ms with a tick of 3.2 ms, and
the frames that run no tick 5.6 ms, with the GPU at 4.4 ms. So the tick has
to come to about 1.5 ms, or leave the thread that draws, and neither is a
matter of tuning. Drawn frames were not measured for this page
(`scripts/profile_combat.gd` does, on Sid's machine).

What the tick is now, and what each part could give:

| Part | Now | What could be done | Worth |
|---|---:|---|---|
| Commands run, in GDScript | 1.14 ms | The movement solver (`PlayerBody`, `MovementSolver`) in C++, a GDExtension beside Box3D's, calling its casts directly | most of 1.1 ms, and most of the two rows below: no wrapper, no dictionaries |
| Native casts | 0.50 ms | Fewer traces: the stay-on-ground pair only when the move met something or left the ground, as the step already is | 0.1 to 0.2 ms |
| The sweep's wrapper | 0.26 ms | Hand the movement a result without a dictionary's copy and three `get_meta` | 0.1 ms |
| Bots thinking | 0.45 ms | Sight every fourth tick, staggered by bot (performance.md, "Next", 7) | 0.3 ms |
| Rays | 0.23 ms | The scope round a player's whole command, so sight rays start in the open too | 0.1 ms |
| Animation parameters | 0.21 ms | Per frame, for the bodies drawn, until a server needs them per tick | 0.2 ms |
| Proxies synchronized | 0.21 ms | Nothing asked inside the scope at all | 0.15 ms |

The small ones together are under a millisecond. The two that reach the
goal are the movement in native code, which keeps everything on one thread
and keeps Source's rules line for line, and the simulation in a process of
its own, a listen server, which is where the game is going anyway
(performance.md, "Going online") and takes the whole tick out of the frame.
They are Sid's to choose between.

## Reproduce

```text
godot --headless --path . --script scripts/profile_hull_traces.gd -- 5 60
godot --headless --path . --script scripts/profile_box3d_match.gd -- --physics box3d
godot --headless --path . --script scripts/profile_box3d_costs.gd -- --physics box3d
godot --headless --path . --script tests/run_dust2_bot_checks.gd
```

For the other build, a worktree of it with junctions to `assets`,
`.godot/imported` and `addons/box3d/bin`, imported once
(`godot --headless --path . --import`), and the two alternated.
