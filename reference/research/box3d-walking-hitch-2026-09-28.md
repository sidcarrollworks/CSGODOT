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
   only looks at a triangle the swept hull reaches (below, "What Box3D's
   sweep looks at"). The hull went up 18.03 and on 3.83, over a floor 0.1
   higher than where it had stood 0.257 clear, so 18.19 over it; swept down
   18.03 it would end 0.16 over the floor, inside the band and short of it,
   and the cast reported nothing. With no landing the step is refused, as
   it is over a drop, and the flat move's zero stands.

The second fault is also most of what made a tick dear: a move that ends
inside the band without a hit leaves the hull there, and the next trace
starts in overlap and searches for a way out, eight casts a direction.

## What was changed

- **`Box3DQueries.shape_cast_prepared`**, the hull's sweep: it sweeps 0.5 further than asked
  (`CAST_REACH`) and reports a hit wherever the motion's end would be
  inside the clearance; it backs off along the motion by 0.25 at most
  (`CAST_BACK_OFF`), and hands back what the clearance still lacks as
  `offset`, a push along the hit's normal (0.06 at most). `PlayerBody._trace`
  adds the offset as it adds a recovery: part of the travel, none of the
  move's time. A hit can now come back with `fraction` 1: the whole motion,
  and the push. (The reach is 0.75 and the back-off 0.5 since the sweep's
  shape was made smaller, "The contained changes".)
- **Anything else sweeps as it did** (`Box3DQueries.shape_cast`, which
  `PhysicsQueries.shape_cast` and `cast_motion` ask: a grenade, a dropped
  item). At first every sweep took the hull's rule, and a review found what
  that did to those handed two fractions and no push: a dropped box coming
  at a floor at 3 degrees was told it might go to 0.209 over it, inside
  the band where its next sweep starts in overlap. It stops 0.257 over
  again, at any angle. Box3D's sphere cast turned out not to be its box
  cast: it stops a sphere 0.197 past touching, not short of it, and knows
  no overlap at the start, so a grenade rests 0.137 into a floor, as it has
  since the game went over to Box3D. Whether that shows, or a grenade's
  bounce wants the hull's rule and its push, is for a playtest.
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
  13 times (12 as the check is since it leaves out a stop with a wall
  within four units the way meant: one of the 13 had one).
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

## A walking bot's tick, function by function

`scripts/profile_player_tick.gd -- 5 60`, after the change: five bots walk
the site routes holding fire, 88% of their ticks at a run, a bot script
putting a clock round each function of the tick. Microseconds a bot a tick;
a function's own time is without the functions it called, and without the
clocks (0.5 us a pair).

| | Calls | With what it calls | Its own |
|---|---:|---:|---:|
| The bot thinks (`command_for`), holding fire | 1 | 31 | 10 |
| Its way (`_way_on`) | 1 | 21 | 21 |
| `run_command`: its own is the body's animation parameters | 1 | 212 | 23 |
| `_run`, the weapon, the hits, held still | 1 | 189 | 15 |
| `simulate`: its own is the scope, the others synchronized, the pose published | 1 | 172 | 24 |
| `_simulate_step`, `_walk_move`, `_air_move`, the duck, the air | | | 12 |
| `_step_move` and its `_try_player_move` | 0.84 | 53 | 5 |
| `_stay_on_ground` | 0.84 | 44 | 5 |
| `_categorize_position` | 1.03 | 30 | 7 |
| `_trace`, 4.5 a tick: the script round the cast | 4.51 | 112 | 43 |
| `_cast_hull`, 5.0 a tick: the bridge's wrapper and the native cast | 5.00 | 66 | 66 |

243 us a walking bot, so 2.4 ms for ten. Nearly half of it is traces, and
of a trace's 25 us the native cast is 10, the bridge's wrapper 3 and the
script round it 10. Staying on the ground and the ground check that
follows it are 74 us between them, three casts to find the floor the hull
is standing on.

The frame's own work, headless, ten players in freeze time
(`scripts/profile_dust2.gd -- 5 3 round --physics box3d
--skip-single-operations`): 1.35 to 1.43 ms a frame, of which the skeletons
posed and the hitboxes moved to them 0.51, the bodies' own step 0.37 to
0.40, the HUD 0.18, the view's two animation trees 0.11. The tick there,
everyone standing, 1.62 ms: a standing bot's `run_command` is 107 us.

## What Box3D's sweep looks at

Measured through the binding (`shape_cast_box`), the hull a given height
over a floor and swept down, up, along and nearly along it; the scripts
were scratch ones.

- **Over a box**, and over triangles it is swept at steeply enough: a
  start closer than 0.246 units (between 0.245 and 0.25) is an overlap, a
  hit at the start with no normal; from further the sweep stops 0.197 short
  of touching.
- **Over triangles, only those the swept hull's bounds reach are looked at
  at all**, and the bounds are the hull's own, with nothing added for the
  0.197 or the 0.246. A level floor is a plane with no height, so a sweep
  that ends over it, by however little, does not see it: the hull swept
  four units along and 0.1 down from 0.15 over a level floor ends 0.05 over
  it and is told nothing; swept level, or up, it is told nothing from any
  height, 0.05 included. A floor tilted three degrees has height, and the
  same sweeps over it are answered as over a box.

So a level move never meets a level floor, which costs nothing; a move onto
a level floor a fraction higher than the last ends a hair over it, or in it,
untold; and a sweep down that stops short of a level floor finds none. The
bridge's half unit past a sweep's end (`CAST_REACH`) covers the last.

## The contained changes

The same day, on top of the above (`perf/tick-contained`), none of which
changes what a move does:

- **The floor found once a walking tick.** Source's StayOnGround sweeps up
  two units, down twenty, and its ground check down two more: three casts
  for the floor the hull stands on. Over native collision it is one: down
  to a step's height under the hull from a unit over it, not swept up to
  (`STAY_ON_GROUND_LIFT`), so that it starts clear of a floor the move
  ended a hair over or in; from where the hull stands, getting clear first,
  only where something is over its head. The ground check takes the floor
  it found, and none is looked for where the step's own sweep down has just
  put the hull on one. The hull is put on the floor whatever the distance:
  under Source's half unit it used to be left, and the ground check closed
  the gap. On Godot's own physics nothing changes.
- **A trace asks the bridge for the cast and nothing else** inside the
  body's own tick: what every sweep shares is set once, the others are
  synchronized once, and the physics the body is in is found once and kept
  while both stand.
- **The hulls are looked over once a tick** (`Box3DQueries.begin_tick`,
  from `GameWorld`), not once a player. What moves a hull in a tick
  publishes it: a player's tick and a spawn did, and a death and a revival
  now do, so nobody walks into the hull of someone killed earlier in the
  tick. Outside a tick every query looks, as the checks move hulls by hand.
  A review found one move in a tick that was not published: a bot with a
  route and no spawn point, back at its route's start (`Bot.respawn`). It
  is now.
- **Box3D is not stepped while nothing in it is awake**
  (`get_awake_body_count`) and no ragdoll lies: a ragdoll writes its bodies
  before every step for as long as it lies, so with one in the world it is
  stepped as ever. Left: a ragdoll at rest letting go of the step.
- **The hull's sweep's shape is an eighth of a unit smaller all round**
  (`CAST_INSET`; a grenade's and a dropped item's are swept whole, by the
  rule they had), and kept as much further from what it meets, so it stops
  where it did, 0.257 from it. Box3D's overlap is of the shape swept: a
  whole hull at rest 0.257 over a floor was 0.011 from being in overlap,
  and a hull is now in overlap within 0.12 of what it is near. It was
  found by a bot with another standing on its head on dust2, as a boost
  has them: 0.21 over the floor and 0.257 under the other, it was in
  overlap with one or the other wherever it looked for a way out, 91
  casts, and stopped dead for the tick. The figures in the table are from
  before it; with it the seeded tick is 2.02 ms where it was 2.12 (four
  runs of each, alternated), its traces 24.6 a tick where they were 30.2,
  the most in a tick 48; and the walk's casts 2.37 a bot a tick, 103 of its
  moves starting in overlap and none of its other traces, the most traces
  in a tick 29 where they were 79, a walking bot's tick 172 us.

| | The hitch's fix | With these |
|---|---:|---:|
| Seeded ten-player tick, mean, the median of five alternated | 3.12 ms (3.05 to 3.27) | 2.31 ms (2.30 to 2.35) |
| Its 95th | 4.06 ms | 3.10 ms |
| Its worst | 6.17 ms (5.78 to 6.91) | 4.99 ms (4.87 to 5.55) |
| Hull traces a tick, and the most | 51.97, 81 | 30.16, 60 |
| A walking bot's tick | 243 us | 192 us |
| Its hull casts | 5.00 | 2.77 |
| The walk's sweeps that start in overlap, of the floor's | 1,678 of 16,129 | 53 of 12,702 |

From main the seeded tick has gone from 3.68 ms to 2.31. Its split now
(instrumented, 2.64 ms; the instrument listens to the native step, so that
is stepped every tick for it): commands run outside the queries 0.85 ms,
bots thinking 0.45, native casts 0.32, rays 0.23, animation parameters
0.20, the end of the tick 0.21, the native step 0.16, the sweep's wrapper
0.15, proxies synchronized 0.06. A walking bot: `simulate`'s own 28 us,
the animation parameters 24, its way 22, the script round its two traces
11, the bridge and the native cast 43 for 2.8 casts.

Checks: someone standing on a player's head, the one underneath a little
under where it rests, who walks out from under at a run in four traces a
tick (47 before the smaller shape); a level floor of triangles 0.05, 0.2
and 0.5 higher walked onto at a run in two traces a tick (four on the code
before, seven for the last);
the movement course's budgets, two traces a tick running in the open and
four up a stair where they were four and seven; a tick's hulls looked over
once, a death's published, and a bot's return to its route's start; the
native world left alone with nothing awake and stepped again when a gun is
moved. The whole suite with the extracted assets: 4,330 checks in 56 files, all passed.

## What is left of the 6 ms

The goal is every frame under 6 ms at 4K with nine bots. Sid's CS2 on the
same machine reads 5.5 ms at most alone on dust2 and 7 to 8 with nine bots,
with spikes to 13 when shooting
([player-update-performance-2026-09-26.md](player-update-performance-2026-09-26.md)),
so the goal is past CS2's own worst with bots. Ours, drawn, on 26 September:
5.4 ms mean, 9.5 at the 99th, 13.6 to 15.5 at worst, with a tick of 2.9 ms
and the GPU at 4.4. A frame that runs a tick is the tick and the frame's
own work on one thread: those frames' 99th was 10.3 to 10.5 ms, the others'
5.6. Drawn frames were not measured for this page
(`scripts/profile_combat.gd` does, on Sid's machine).

What keeps Source's rules and results as they are and is still to do, in
the order of what it is worth with ten players ("The contained changes"
has what is done):

| What | Where the time is now | Worth |
|---|---|---|
| The bots thinking on worker threads: everyone's command first, from the world as the last tick left it, then everyone run in turn | 0.45 ms in the seeded tick, 33 us a walking bot | 0.3 to 0.4 ms |
| A ragdoll at rest letting go of the native step | 0.16 ms a tick once anyone has died | 0.15 ms |
| The sweep's wrapper without a dictionary's copy and three `get_meta` | 3 us a cast | 0.1 ms |
| Hitboxes moved to their bones when a round asks, not every frame | 0.51 ms a frame with the skeletons | 0.2 to 0.3 ms a frame |
| The HUD set only when what it shows changes | 0.18 ms a frame | 0.1 ms a frame |

With the tick at 2.3 ms the frames that run one should be about 8.5 ms at
the 99th, which is CS2's with bots, not 6; not measured drawn yet.

What reaches 6, each a decision:

- **Godot's renderer on a thread of its own**
  (`rendering/driver/threads/thread_model`): a setting, so the first to
  try, measured drawn on Sid's machine. It takes the renderer's share of
  the frame off the thread that runs the tick. What it gives here is not
  known.
- **The movement in native code**: `PlayerBody` and `MovementSolver` as a
  GDExtension beside Box3D's, calling its casts directly. It takes most of
  a walking bot's 243 us (all but the native casts' 50), keeps everything
  on one thread and Source's rules line for line, and pays on a server too.
- **The simulation in a process of its own**, a listen server, which is
  where the game is going (performance.md, "Going online"): the whole tick
  out of the frame. The largest of the three.

## Reproduce

```text
godot --headless --path . --script scripts/profile_hull_traces.gd -- 5 60
godot --headless --path . --script scripts/profile_player_tick.gd -- 5 60
godot --headless --path . --script scripts/profile_box3d_match.gd -- --physics box3d
godot --headless --path . --script scripts/profile_box3d_costs.gd -- --physics box3d
godot --headless --path . --script tests/run_dust2_bot_checks.gd
```

For the other build, a worktree of it with junctions to `assets`,
`.godot/imported` and `addons/box3d/bin`, imported once
(`godot --headless --path . --import`), and the two alternated.
